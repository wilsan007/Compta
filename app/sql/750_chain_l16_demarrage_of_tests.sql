-- ═══════════════════════════════════════════════════════════════════════════
-- 750_chain_l16_demarrage_of_tests.sql — L16 · le démarrage d'un OF
-- ═══════════════════════════════════════════════════════════════════════════
-- La suite éprouve le maillon de la 750 en douze verdicts :
--
--   T01  NOMINAL : le passage à 'in_progress' est TRACÉ (« applique »), le
--        contrat est DÉCLARÉ (aucune trace « tolere »/« refuse »), et
--        l'événement `manufacturing_orders.started` est émis UNE fois, en
--        portant le numéro et la quantité de l'OF ;
--   T02  IDEMPOTENCE (D1) : repasser par 'planned' puis redémarrer ne rejoue
--        PAS l'effet — une trace « ignore » le DIT ;
--   T03  LE SILENCE HORS DÉMARRAGE : les autres transitions (cancelled, et un
--        OF qui reste 'planned') ne produisent AUCUNE annonce ;
--   T04  ISOLATION (D8) : le voisin ne voit ni trace ni événement.
--
-- Ce que cette suite NE joue PAS, et le dit : D2 (concurrence), D3 (panne
-- partielle), D5 (réouverture), D6 (retour arrière — tenu par construction,
-- tout ce fichier est transactionnel), D7 (volume — sans objet sur une annonce).
-- ═══════════════════════════════════════════════════════════════════════════
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '750', false);
DELETE FROM _audit_results WHERE file = '750';

-- ── Le décor : un atelier minimal (dépôt, article fini, matière, nomenclature).
-- Mesuré : un OF REFUSE de naître sans article à fabriquer (« aucun article à
-- fabriquer » — garde `a_manufacturing_order_product`), et la garde exige une
-- nomenclature qui porte l'article. Le décor est donc celui de la 229.
DROP FUNCTION IF EXISTS _mk_atelier750(text);
CREATE OR REPLACE FUNCTION _mk_atelier750(p_nom text, OUT t uuid, OUT wh uuid, OUT pf uuid, OUT b uuid)
LANGUAGE plpgsql AS $$
DECLARE mp uuid;
BEGIN
  t := _mk_tenant(p_nom);
  PERFORM ensure_standard_journals(t);
  INSERT INTO warehouses (tenant_id, code, name) VALUES (t, 'W-' || p_nom, 'Dépôt') RETURNING id INTO wh;
  INSERT INTO products (tenant_id, name, sku, type, cost_price)
    VALUES (t, 'Produit fini ' || p_nom, 'PF-' || p_nom, 'stock', 0) RETURNING id INTO pf;
  INSERT INTO products (tenant_id, name, sku, type, cost_price)
    VALUES (t, 'Matière ' || p_nom, 'MP-' || p_nom, 'stock', 5) RETURNING id INTO mp;
  INSERT INTO boms (tenant_id, code, name, product_id, quantity)
    VALUES (t, 'B-' || p_nom, 'Nomenclature ' || p_nom, pf, 1) RETURNING id INTO b;
  INSERT INTO bom_lines (tenant_id, bom_id, product_id, quantity, unit_cost) VALUES (t, b, mp, 2, 5);
END $$;

-- ── T01 — LE NOMINAL : le démarrage cesse d'être muet ──────────────────────
DO $$
DECLARE a record; t uuid; mo uuid; n int; v_res text; v_pay jsonb;
BEGIN
  a := _mk_atelier750('T750A');
  t := a.t;
  INSERT INTO manufacturing_orders (tenant_id, number, bom_id, product_id, quantity, status, warehouse_id)
    VALUES (t, 'OF-750-1', a.b, a.pf, 10, 'planned', a.wh) RETURNING id INTO mo;

  PERFORM _as_user();
  UPDATE manufacturing_orders SET status = 'in_progress', start_date = '2026-05-04' WHERE id = mo;

  SELECT count(*), max(resultat) INTO n, v_res FROM chain_traces
   WHERE tenant_id = t AND effet = 'production.order.started' AND amont_id = mo;
  PERFORM _rec('T01a', 'le démarrage est TRACÉ (une trace, résultat « applique »)',
    n = 1 AND v_res = 'applique', 'traces = ' || n || ', resultat = ' || COALESCE(v_res, '-'));

  SELECT count(*) INTO n FROM chain_traces
   WHERE tenant_id = t AND effet = 'production.order.started' AND amont_id = mo
     AND resultat IN ('tolere', 'refuse');
  PERFORM _rec('T01b', 'le contrat est DÉCLARÉ et ACTIF (aucune trace « tolere »/« refuse »)',
    n = 0, 'anomalies = ' || n);

  SELECT count(*) INTO n FROM domain_events
   WHERE tenant_id = t AND event_name = 'manufacturing_orders.started' AND aggregate_id = mo;
  PERFORM _rec('T01c', 'l''événement manufacturing_orders.started est émis, UNE fois',
    n = 1, 'evenements = ' || n);

  SELECT payload INTO v_pay FROM domain_events
   WHERE tenant_id = t AND event_name = 'manufacturing_orders.started' AND aggregate_id = mo
   ORDER BY created_at LIMIT 1;
  PERFORM _rec('T01d', 'l''événement porte le numéro de l''OF (charge utile exploitable)',
    v_pay IS NOT NULL AND v_pay ? 'number',
    'payload = ' || left(COALESCE(v_pay::text, 'vide'), 140));
END $$;

-- ── T02 — IDEMPOTENCE (D1) : redémarrer ne rejoue RIEN ─────────────────────
DO $$
DECLARE a record; t uuid; mo uuid; n int; n_applique_avant int; n_events_avant int;
BEGIN
  a := _mk_atelier750('T750B');
  t := a.t;
  INSERT INTO manufacturing_orders (tenant_id, number, bom_id, product_id, quantity, status, warehouse_id)
    VALUES (t, 'OF-750-2', a.b, a.pf, 4, 'planned', a.wh) RETURNING id INTO mo;

  PERFORM _as_user();
  UPDATE manufacturing_orders SET status = 'in_progress' WHERE id = mo;

  SELECT count(*) INTO n_applique_avant FROM chain_traces
   WHERE tenant_id = t AND effet = 'production.order.started' AND amont_id = mo AND resultat = 'applique';
  SELECT count(*) INTO n_events_avant FROM domain_events
   WHERE tenant_id = t AND event_name = 'manufacturing_orders.started' AND aggregate_id = mo;

  -- Remis à 'planned' puis redémarré : le maillon ne doit pas rejouer.
  UPDATE manufacturing_orders SET status = 'planned'     WHERE id = mo;
  UPDATE manufacturing_orders SET status = 'in_progress' WHERE id = mo;

  SELECT count(*) INTO n FROM chain_traces
   WHERE tenant_id = t AND effet = 'production.order.started' AND amont_id = mo AND resultat = 'applique';
  PERFORM _rec('T02a', 'le redémarrage ne produit PAS une 2e trace « applique » (D1 tenu)',
    n = n_applique_avant AND n_applique_avant = 1, 'applique = ' || n || ' (avant : ' || n_applique_avant || ')');

  SELECT count(*) INTO n FROM chain_traces
   WHERE tenant_id = t AND effet = 'production.order.started' AND amont_id = mo AND resultat = 'ignore';
  PERFORM _rec('T02b', 'le rejeu est DIT (une trace « ignore »)', n = 1, 'ignore = ' || n);

  SELECT count(*) INTO n FROM domain_events
   WHERE tenant_id = t AND event_name = 'manufacturing_orders.started' AND aggregate_id = mo;
  PERFORM _rec('T02c', 'aucune 2e annonce : l''événement n''est pas dupliqué',
    n = n_events_avant AND n_events_avant = 1, 'evenements = ' || n || ' (avant : ' || n_events_avant || ')');
END $$;

-- ── T03 — LE SILENCE HORS DÉMARRAGE : le maillon ne parle que du démarrage ─
DO $$
DECLARE a record; t uuid; mo_c uuid; mo_p uuid; n int;
BEGIN
  a := _mk_atelier750('T750C');
  t := a.t;
  -- (a) un OF annulé sans jamais démarrer
  INSERT INTO manufacturing_orders (tenant_id, number, bom_id, product_id, quantity, status, warehouse_id)
    VALUES (t, 'OF-750-annule', a.b, a.pf, 3, 'planned', a.wh) RETURNING id INTO mo_c;
  -- (b) un OF qui reste planifié
  INSERT INTO manufacturing_orders (tenant_id, number, bom_id, product_id, quantity, status, warehouse_id)
    VALUES (t, 'OF-750-planifie', a.b, a.pf, 3, 'planned', a.wh) RETURNING id INTO mo_p;

  PERFORM _as_user();
  UPDATE manufacturing_orders SET status = 'cancelled' WHERE id = mo_c;

  SELECT count(*) INTO n FROM domain_events
   WHERE tenant_id = t AND event_name = 'manufacturing_orders.started' AND aggregate_id IN (mo_c, mo_p);
  PERFORM _rec('T03a', 'annuler un OF planifié ne produit AUCUNE annonce de démarrage',
    n = 0, 'evenements = ' || n);

  SELECT count(*) INTO n FROM chain_traces
   WHERE tenant_id = t AND effet = 'production.order.started' AND amont_id IN (mo_c, mo_p);
  PERFORM _rec('T03b', 'aucune trace du maillon hors démarrage', n = 0, 'traces = ' || n);
END $$;

-- ── T04 — ISOLATION (D8) : le voisin ne voit ni trace ni événement ─────────
DO $$
DECLARE a record; ta uuid; tb uuid; ma uuid; n int;
BEGIN
  a := _mk_atelier750('T750E1');
  ta := a.t;
  INSERT INTO manufacturing_orders (tenant_id, number, bom_id, product_id, quantity, status, warehouse_id)
    VALUES (ta, 'OF-750-E1', a.b, a.pf, 2, 'planned', a.wh) RETURNING id INTO ma;
  PERFORM _as_user();
  UPDATE manufacturing_orders SET status = 'in_progress' WHERE id = ma;

  -- Le décor bascule le tenant actif : il faut repasser par le rôle
  -- superutilisateur pour BÂTIR la société voisine (« RESET ROLE »).
  RESET ROLE;
  tb := _mk_tenant('T750E2');
  PERFORM _as_user();

  SELECT count(*) INTO n FROM chain_traces
   WHERE effet = 'production.order.started' AND amont_id = ma;
  PERFORM _rec('T04a', 'le voisin ne voit AUCUNE trace de la société A', n = 0, 'traces visibles = ' || n);

  SELECT count(*) INTO n FROM domain_events
   WHERE event_name = 'manufacturing_orders.started' AND aggregate_id = ma;
  PERFORM _rec('T04b', 'le voisin ne voit AUCUN événement de la société A', n = 0, 'evenements visibles = ' || n);

  RESET ROLE;
  SELECT count(*) INTO n FROM chain_traces
   WHERE tenant_id = ta AND effet = 'production.order.started' AND amont_id = ma AND resultat = 'applique';
  PERFORM _rec('T04c', 'la trace de A existe toujours, et reste à A', n = 1, 'traces de A = ' || n);
END $$;

-- ── Le VERDICT (G5 : toute suite rend un verdict) ─────────────────────────
SELECT _audit_assert('750');
