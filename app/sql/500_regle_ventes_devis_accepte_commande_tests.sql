-- ============================================================
-- 500_regle_ventes_devis_accepte_commande_tests.sql — partie B, lot Ventes, règle R-001
--
-- Ce que la règle R-001 garantit (doc/audit/plan6/B1-INVENTAIRE-62-REGLES-2026-10-05.md) :
--   T01  un devis ACCEPTÉ produit sa COMMANDE (brouillon), avec ses lignes et le
--        PRIX GELÉ ; le devis pointe la commande, un lien `created_from` est posé,
--        un événement `quotes.accepted` est émis, le maillon est tracé `applique` ;
--   T02  IDEMPOTENCE — ré-accepter un devis déjà transformé ne crée pas de 2e commande ;
--   T03  PRIX GELÉ — modifier le prix du devis APRÈS acceptation ne touche pas la commande.
--
-- S'exécute comme les suites d'audit : société posée en superutilisateur, puis rôle
-- `authenticated` (un utilisateur réel, sous RLS) — \ir ci/audit_helpers.sql.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '500', false);
DELETE FROM _audit_results WHERE file = '500';

-- Société isolée : client, un devis « envoyé » et deux lignes (2 × 100 @20, 1 × 50 @20).
CREATE OR REPLACE FUNCTION _b500_devis(p_nom text, OUT t uuid, OUT c uuid, OUT q uuid)
LANGUAGE plpgsql AS $$
BEGIN
  t := _mk_tenant(p_nom);
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client ' || p_nom) RETURNING id INTO c;
  INSERT INTO quotes (tenant_id, number, customer_id, date, expiry_date, status, validation_status)
    VALUES (t, 'DEV-' || p_nom, c, '2026-03-10', '2026-04-10', 'sent', 'draft')
    RETURNING id INTO q;
  INSERT INTO quote_lines (tenant_id, quote_id, description, quantity, unit_price, vat_rate, line_order)
    VALUES (t, q, 'Article A', 2, 100, 20, 0),
           (t, q, 'Article B', 1, 50, 20, 1);
END $$;

-- ── T01 : l'acceptation d'un devis crée la commande ─────────────
DO $$
DECLARE v record; n int; st text; nl int; ht numeric; tva numeric; tot numeric; o uuid;
BEGIN
  v := _b500_devis('T01');
  PERFORM _as_user();
  UPDATE quotes SET status = 'accepted' WHERE id = v.q;

  SELECT count(*), min(o.status) INTO n, st
  FROM sales_orders o WHERE o.tenant_id = v.t AND o.quote_id = v.q;
  PERFORM _rec('T01a', 'le devis accepté produit UNE commande, au statut brouillon',
    n = 1 AND st = 'draft', format('commandes=%s statut=%s (1 / draft attendus)', n, st));

  SELECT count(*) INTO nl FROM sales_order_lines l
  JOIN sales_orders o ON o.id = l.sales_order_id AND o.tenant_id = l.tenant_id
  WHERE o.tenant_id = v.t AND o.quote_id = v.q;
  PERFORM _rec('T01b', 'la commande reprend les deux lignes du devis',
    nl = 2, format('lignes=%s (2 attendues)', nl));

  SELECT o.subtotal, o.vat, o.total INTO ht, tva, tot
  FROM sales_orders o WHERE o.tenant_id = v.t AND o.quote_id = v.q;
  PERFORM _rec('T01c', 'les totaux de la commande sont ceux du devis (250 / 50 / 300)',
    ht = 250 AND tva = 50 AND tot = 300, format('ht=%s tva=%s total=%s', ht, tva, tot));

  PERFORM _rec('T01d', 'le devis pointe sa commande et se déclare transformé',
    (SELECT transformed_to_order_id IS NOT NULL AND transformation_status = 'transformed'
     FROM quotes WHERE id = v.q),
    (SELECT format('order=%s statut=%s', transformed_to_order_id, transformation_status)
     FROM quotes WHERE id = v.q));

  PERFORM _rec('T01e', 'le lien devis → commande est posé (created_from)',
    (SELECT count(*) FROM document_links dl
     WHERE dl.tenant_id = v.t AND dl.amont_type = 'quotes' AND dl.amont_id = v.q
       AND dl.aval_type = 'sales_orders' AND dl.effet = 'sale.quote.order'
       AND dl.link_type = 'created_from') = 1,
    (SELECT format('liens=%s', count(*)) FROM document_links dl
     WHERE dl.tenant_id = v.t AND dl.amont_id = v.q));

  PERFORM _rec('T01f', 'un événement quotes.accepted est émis',
    (SELECT count(*) FROM domain_events de
     WHERE de.tenant_id = v.t AND de.event_name = 'quotes.accepted' AND de.aggregate_id = v.q) = 1,
    (SELECT format('événements=%s', count(*)) FROM domain_events de
     WHERE de.tenant_id = v.t AND de.aggregate_id = v.q));

  PERFORM _rec('T01g', 'le maillon est tracé « applique »',
    (SELECT count(*) FROM chain_traces ct
     WHERE ct.tenant_id = v.t AND ct.effet = 'sale.quote.order'
       AND ct.amont_id = v.q AND ct.resultat = 'applique') = 1,
    (SELECT format('traces=%s', count(*)) FROM chain_traces ct
     WHERE ct.tenant_id = v.t AND ct.effet = 'sale.quote.order' AND ct.amont_id = v.q));
END $$;

-- ── T02 : l'idempotence — pas de 2e commande ────────────────────
DO $$
DECLARE v record; n int;
BEGIN
  v := _b500_devis('T02');
  PERFORM _as_user();
  UPDATE quotes SET status = 'accepted' WHERE id = v.q;   -- 1re acceptation
  UPDATE quotes SET status = 'sent'     WHERE id = v.q;   -- on recule
  UPDATE quotes SET status = 'accepted' WHERE id = v.q;   -- on ré-accepte

  SELECT count(*) INTO n FROM sales_orders WHERE tenant_id = v.t AND quote_id = v.q;
  PERFORM _rec('T02', 'ré-accepter un devis déjà transformé ne crée pas de deuxième commande',
    n = 1, format('commandes=%s (1 attendue)', n));
END $$;

-- ── T03 : le prix est gelé ──────────────────────────────────────
DO $$
DECLARE v record; pu numeric;
BEGIN
  v := _b500_devis('T03');
  PERFORM _as_user();
  UPDATE quotes SET status = 'accepted' WHERE id = v.q;
  -- Le prix du devis change APRÈS l'acceptation : la commande ne doit pas bouger.
  UPDATE quote_lines SET unit_price = 999 WHERE quote_id = v.q AND description = 'Article A';

  SELECT l.unit_price INTO pu FROM sales_order_lines l
  JOIN sales_orders o ON o.id = l.sales_order_id AND o.tenant_id = l.tenant_id
  WHERE o.tenant_id = v.t AND o.quote_id = v.q AND l.description = 'Article A';
  PERFORM _rec('T03', 'le prix de la commande reste celui du devis à l''acceptation (100)',
    pu = 100, format('prix unitaire=%s (100 attendu)', pu));
END $$;

SELECT _audit_assert('500');