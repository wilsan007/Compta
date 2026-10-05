-- ============================================================
-- 501_regle_ventes_commande_facturee_tests.sql — partie B, lot Ventes, règle R-004
--
-- Ce que la règle R-004 garantit (doc/audit/plan6/B1-INVENTAIRE-62-REGLES-2026-10-05.md) :
--   T01  une commande passée à `invoiced` RAPPROCHE ses factures : UN lien
--        `invoiced_by`, UN événement `sales_orders.invoiced`, UNE trace `applique`,
--        et le RELIQUAT non facturé mesuré (commandé 1000 − facturé 400 = 600) ;
--   T02  IDEMPOTENCE — repasser par `invoiced` ne pose pas un second lien ;
--   T03  MESURE — une commande facturée sans facture rattachée dit son reliquat
--        entier (1000) et ne pose aucun lien.
--
-- \ir ci/audit_helpers.sql : société posée en superutilisateur, puis rôle
-- `authenticated` (un utilisateur réel, sous RLS).
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '501', false);
DELETE FROM _audit_results WHERE file = '501';

-- Société isolée : une commande brouillon (1 ligne 10 × 100 @20 = 1000 HT) et,
-- si demandé, une facture rattachée à sa ligne (4 × 100 = 400 HT facturé).
CREATE OR REPLACE FUNCTION _b501(p_nom text, p_facture boolean DEFAULT true,
                                 OUT t uuid, OUT o uuid, OUT ol uuid, OUT i uuid)
LANGUAGE plpgsql AS $$
DECLARE c uuid; p uuid;
BEGIN
  t := _mk_tenant(p_nom);
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client ' || p_nom) RETURNING id INTO c;
  INSERT INTO products (tenant_id, name, sku, type)
    VALUES (t, 'Art ' || p_nom, 'A-' || p_nom, 'stock') RETURNING id INTO p;
  INSERT INTO sales_orders (tenant_id, number, customer_id, order_date, status)
    VALUES (t, 'CMD-' || p_nom, c, '2026-03-10', 'draft') RETURNING id INTO o;
  INSERT INTO sales_order_lines (tenant_id, sales_order_id, product_id, description,
                                 quantity, unit_price, vat_rate)
    VALUES (t, o, p, 'Ligne ' || p_nom, 10, 100, 20) RETURNING id INTO ol;
  IF p_facture THEN
    INSERT INTO invoices (tenant_id, customer_id, date, due_date, status)
      VALUES (t, c, '2026-03-15', '2026-04-15', 'draft') RETURNING id INTO i;
    INSERT INTO invoice_lines (tenant_id, invoice_id, product_id, description,
                               quantity, unit_price, vat_rate, sales_order_line_id)
      VALUES (t, i, p, 'Facture ' || p_nom, 4, 100, 20, ol);
  END IF;
END $$;

-- ── T01 : commande facturée → rapprochement + reliquat ──────────
DO $$
DECLARE v record; nl int; ne int; nt int; rel numeric;
BEGIN
  v := _b501('T01');
  PERFORM _as_user();
  UPDATE sales_orders SET status = 'invoiced' WHERE id = v.o;

  SELECT count(*) INTO nl FROM document_links dl
  WHERE dl.tenant_id = v.t AND dl.amont_type = 'sales_orders' AND dl.amont_id = v.o
    AND dl.aval_type = 'invoices' AND dl.effet = 'sale.order.invoiced'
    AND dl.link_type = 'invoiced_by';
  PERFORM _rec('T01a', 'la commande facturée se rapproche de sa facture (1 lien invoiced_by)',
    nl = 1, format('liens=%s (1 attendu)', nl));

  SELECT count(*), max((de.payload->>'reliquat')::numeric) INTO ne, rel
  FROM domain_events de
  WHERE de.tenant_id = v.t AND de.event_name = 'sales_orders.invoiced' AND de.aggregate_id = v.o;
  PERFORM _rec('T01b', 'un événement sales_orders.invoiced porte le reliquat (600)',
    ne = 1 AND rel = 600, format('événements=%s reliquat=%s (1 / 600 attendus)', ne, rel));

  SELECT count(*) INTO nt FROM chain_traces ct
  WHERE ct.tenant_id = v.t AND ct.effet = 'sale.order.invoiced'
    AND ct.amont_id = v.o AND ct.resultat = 'applique';
  PERFORM _rec('T01c', 'le maillon est tracé « applique »',
    nt = 1, format('traces=%s (1 attendue)', nt));
END $$;

-- ── T02 : idempotence — pas de second lien ──────────────────────
DO $$
DECLARE v record; nl int;
BEGIN
  v := _b501('T02');
  PERFORM _as_user();
  UPDATE sales_orders SET status = 'invoiced' WHERE id = v.o;  -- 1re fois
  UPDATE sales_orders SET status = 'draft'    WHERE id = v.o;  -- on recule
  UPDATE sales_orders SET status = 'invoiced' WHERE id = v.o;  -- rejeu de l'état

  SELECT count(*) INTO nl FROM document_links dl
  WHERE dl.tenant_id = v.t AND dl.amont_type = 'sales_orders' AND dl.amont_id = v.o
    AND dl.effet = 'sale.order.invoiced' AND dl.link_type = 'invoiced_by';
  PERFORM _rec('T02', 'un rejeu de l''état « facturée » ne pose pas un second lien',
    nl = 1, format('liens=%s (1 attendu)', nl));
END $$;

-- ── T03 : la mesure — commande facturée sans facture rattachée ──
DO $$
DECLARE v record; nl int; rel numeric;
BEGIN
  v := _b501('T03', false);
  PERFORM _as_user();
  UPDATE sales_orders SET status = 'invoiced' WHERE id = v.o;

  SELECT count(*) INTO nl FROM document_links dl
  WHERE dl.tenant_id = v.t AND dl.amont_id = v.o AND dl.effet = 'sale.order.invoiced';
  SELECT max((de.payload->>'reliquat')::numeric) INTO rel
  FROM domain_events de
  WHERE de.tenant_id = v.t AND de.event_name = 'sales_orders.invoiced' AND de.aggregate_id = v.o;
  PERFORM _rec('T03', 'sans facture rattachée : aucun lien, reliquat = commandé (1000)',
    nl = 0 AND rel = 1000, format('liens=%s reliquat=%s (0 / 1000 attendus)', nl, rel));
END $$;

SELECT _audit_assert('501');