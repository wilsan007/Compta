-- ============================================================
-- 510_regle_achats_commande_recue_tests.sql — partie B, lot Achats, règle R-011
--
-- Ce que la règle garantit (doc/audit/plan6/B1-INVENTAIRE-62-REGLES-2026-10-05.md) :
--   T01  une commande passée à `received` se rapproche de SES réceptions (1 lien) et
--        mesure l'écart de quantité (commandé 10, reçu 10 → écart 0) ;
--   T02  écart réel : commandé 10, reçu 6 → écart 4 ;
--   T03  IDEMPOTENCE — un rejeu ne pose pas un second lien.
--
-- \ir ci/audit_helpers.sql.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '510', false);
DELETE FROM _audit_results WHERE file = '510';

-- Société isolée : une commande d'achat (1 ligne de Q qte) et une réception reçue.
CREATE OR REPLACE FUNCTION _b510(p_nom text, p_cmd_qte numeric DEFAULT 10, p_recu_qte numeric DEFAULT 10,
                                 OUT t uuid, OUT po uuid, OUT gr uuid)
LANGUAGE plpgsql AS $$
DECLARE s uuid; p uuid;
BEGIN
  t := _mk_tenant(p_nom);
  INSERT INTO suppliers (tenant_id, name) VALUES (t, 'Fourn ' || p_nom) RETURNING id INTO s;
  INSERT INTO products (tenant_id, name, sku, type) VALUES (t, 'Art ' || p_nom, 'A-' || p_nom, 'stock') RETURNING id INTO p;
  INSERT INTO purchase_orders (tenant_id, number, supplier_id, order_date, status)
    VALUES (t, 'CMD-' || p_nom, s, '2026-03-01', 'draft') RETURNING id INTO po;
  INSERT INTO purchase_order_lines (tenant_id, purchase_order_id, product_id, description, quantity, unit_price)
    VALUES (t, po, p, 'Ligne ' || p_nom, p_cmd_qte, 100);
  INSERT INTO goods_receipts (tenant_id, number, purchase_order_id, receipt_date, status)
    VALUES (t, 'BR-' || p_nom, po, '2026-03-05', 'received') RETURNING id INTO gr;
  INSERT INTO goods_receipt_lines (tenant_id, goods_receipt_id, product_id, description, quantity_received)
    VALUES (t, gr, p, 'Ligne ' || p_nom, p_recu_qte);
END $$;

-- ── T01 : rapprochement + écart 0 ───────────────────────────────
DO $$
DECLARE x record; nl int; ne int; ec numeric;
BEGIN
  x := _b510('T01', 10, 10);
  PERFORM _as_user();
  UPDATE purchase_orders SET status = 'received' WHERE id = x.po;

  SELECT count(*) INTO nl FROM document_links dl
  WHERE dl.tenant_id = x.t AND dl.amont_type = 'purchase_orders' AND dl.amont_id = x.po
    AND dl.aval_type = 'goods_receipts' AND dl.effet = 'purchase.order.received';
  PERFORM _rec('T01a', 'la commande reçue se rapproche de sa réception (1 lien)',
    nl = 1, format('liens=%s (1 attendu)', nl));

  SELECT count(*), max((de.payload->>'ecart_qte')::numeric) INTO ne, ec
  FROM domain_events de
  WHERE de.tenant_id = x.t AND de.event_name = 'purchase_orders.received' AND de.aggregate_id = x.po;
  PERFORM _rec('T01b', 'l''événement porte l''écart de quantité (10 reçus sur 10 → 0)',
    ne = 1 AND ec = 0, format('événements=%s écart=%s (1 / 0 attendus)', ne, ec));
END $$;

-- ── T02 : écart de quantité réel ────────────────────────────────
DO $$
DECLARE x record; ec numeric;
BEGIN
  x := _b510('T02', 10, 6);
  PERFORM _as_user();
  UPDATE purchase_orders SET status = 'received' WHERE id = x.po;
  SELECT max((de.payload->>'ecart_qte')::numeric) INTO ec
  FROM domain_events de
  WHERE de.tenant_id = x.t AND de.event_name = 'purchase_orders.received' AND de.aggregate_id = x.po;
  PERFORM _rec('T02', 'l''écart de quantité est mesuré (10 commandés − 6 reçus = 4)',
    ec = 4, format('écart=%s (4 attendu)', ec));
END $$;

-- ── T03 : idempotence ───────────────────────────────────────────
DO $$
DECLARE x record; nl int;
BEGIN
  x := _b510('T03', 10, 10);
  PERFORM _as_user();
  UPDATE purchase_orders SET status = 'received' WHERE id = x.po;
  UPDATE purchase_orders SET status = 'draft'    WHERE id = x.po;
  UPDATE purchase_orders SET status = 'received' WHERE id = x.po;
  SELECT count(*) INTO nl FROM document_links dl
  WHERE dl.tenant_id = x.t AND dl.amont_id = x.po AND dl.effet = 'purchase.order.received';
  PERFORM _rec('T03', 'un rejeu ne pose pas un second lien',
    nl = 1, format('liens=%s (1 attendu)', nl));
END $$;

SELECT _audit_assert('510');