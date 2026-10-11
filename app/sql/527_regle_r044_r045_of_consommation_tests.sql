-- ============================================================
-- 527_regle_r044_r045_of_consommation_tests.sql — partie B, lot Production, R-045, R-044
--
--   T01  un OF PLANIFIÉ RÉSERVE ses composants (1 réservation, qty 10) ;
--   T02  un OF EN COURS solde ses réservations et N'ÉCRIT PAS la sortie de stock — la
--        consommation physique (mouvements + écriture 601000/310000) appartient à la CLÔTURE
--        (`81`/`229`, `create_stock_on_manufacturing_complete`) : voir l'en-tête de la règle ;
--   T03  IDEMPOTENCE — un rejeu ne double pas la réservation ;
--   T04  LE CONTRAT DE L'ÉCRAN M04 (`08_prod_treso`) : OF terminé → +5 produits finis et
--        −10 composants, UNE SEULE consommation. Garde-fou de la réconciliation : si un jour
--        R-044 réécrivait la sortie ici, la clôture refuserait (23505 « OF … déjà clôturé »)
--        et ce test le dirait.
-- \ir ci/audit_helpers.sql.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '527', false);
DELETE FROM _audit_results WHERE file = '527';

CREATE OR REPLACE FUNCTION _b527(p_nom text, p_statut text, OUT t uuid, OUT mo uuid, OUT wh uuid, OUT comp uuid)
LANGUAGE plpgsql AS $$
DECLARE pf uuid; b uuid;
BEGIN
  t := _mk_tenant(p_nom);
  PERFORM ensure_standard_journals(t);
  INSERT INTO warehouses (tenant_id, code, name) VALUES (t, 'W-' || p_nom, 'Dépôt') RETURNING id INTO wh;
  INSERT INTO products (tenant_id, name, sku, type) VALUES (t, 'PF ' || p_nom, 'PF-' || p_nom, 'stock') RETURNING id INTO pf;
  INSERT INTO products (tenant_id, name, sku, type) VALUES (t, 'MP ' || p_nom, 'MP-' || p_nom, 'stock') RETURNING id INTO comp;
  INSERT INTO boms (tenant_id, code, name, product_id) VALUES (t, 'BOM-' || p_nom, 'Nomenc ' || p_nom, pf) RETURNING id INTO b;
  INSERT INTO bom_lines (tenant_id, bom_id, product_id, quantity) VALUES (t, b, comp, 2);
  INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, movement_type, type, quantity, unit_cost, reference, movement_date, date)
    VALUES (t, comp, wh, 'in', 'in', 100, 5, 'INIT', CURRENT_DATE, CURRENT_DATE);
  INSERT INTO manufacturing_orders (tenant_id, number, product_id, bom_id, quantity, warehouse_id, status)
    VALUES (t, 'OF-' || p_nom, pf, b, 5, wh, p_statut) RETURNING id INTO mo;
END $$;

DO $$
DECLARE x record; n int; q numeric; ne int;
BEGIN
  x := _b527('T01', 'in_progress');
  PERFORM _as_user();
  UPDATE manufacturing_orders SET status = 'planned' WHERE id = x.mo;
  SELECT count(*), max(quantity) INTO n, q FROM stock_reservations sr
  WHERE sr.tenant_id = x.t AND sr.reference_type = 'manufacturing_order' AND sr.reference_id = x.mo;
  PERFORM _rec('T01a', 'un OF planifié RÉSERVE ses composants (1 réservation, qty 10)',
    n = 1 AND q = 10, format('réservations=%s qty=%s (1 / 10 attendus)', n, q));
  SELECT count(*) INTO ne FROM domain_events de
  WHERE de.tenant_id = x.t AND de.event_name = 'manufacturing_orders.components_reserved' AND de.aggregate_id = x.mo;
  PERFORM _rec('T01b', 'un événement manufacturing_orders.components_reserved est émis', ne = 1, format('événements=%s (1 attendu)', ne));
END $$;

DO $$
DECLARE x record; n int; soldees int; ne int;
BEGIN
  x := _b527('T02', 'in_progress');
  PERFORM _as_user();
  -- La réservation naît de l'ENTRÉE dans « planifié » (R-045) : on y passe d'abord, comme T01.
  UPDATE manufacturing_orders SET status = 'planned'     WHERE id = x.mo;
  UPDATE manufacturing_orders SET status = 'in_progress' WHERE id = x.mo;
  SELECT count(*) INTO n FROM stock_movements sm
  WHERE sm.tenant_id = x.t AND sm.reference_type = 'production' AND sm.reference_id = x.mo AND sm.movement_type = 'out';
  PERFORM _rec('T02a', 'un OF en cours N''ÉCRIT PAS la sortie de stock — la consommation appartient à la clôture (81/229)',
    n = 0, format('sorties=%s (0 attendue : la clôture les produit)', n));
  SELECT count(*) INTO soldees FROM stock_reservations sr
  WHERE sr.tenant_id = x.t AND sr.reference_id = x.mo AND sr.status = 'consumed';
  PERFORM _rec('T02b', 'les réservations de l''OF sont SOLDÉES (consumed)', soldees = 1,
    format('réservations soldées=%s (1 attendue)', soldees));
  SELECT count(*) INTO ne FROM domain_events de
  WHERE de.tenant_id = x.t AND de.event_name = 'manufacturing_orders.components_consumed' AND de.aggregate_id = x.mo;
  PERFORM _rec('T02c', 'un événement manufacturing_orders.components_consumed est émis', ne = 1, format('événements=%s (1 attendu)', ne));
END $$;

DO $$
DECLARE x record; n int;
BEGIN
  x := _b527('T03', 'in_progress');
  PERFORM _as_user();
  UPDATE manufacturing_orders SET status = 'planned'     WHERE id = x.mo;
  UPDATE manufacturing_orders SET status = 'in_progress' WHERE id = x.mo;
  UPDATE manufacturing_orders SET status = 'planned'     WHERE id = x.mo;
  SELECT count(*) INTO n FROM stock_reservations sr
  WHERE sr.tenant_id = x.t AND sr.reference_id = x.mo AND sr.reference_type = 'manufacturing_order';
  PERFORM _rec('T03', 'un rejeu ne crée pas une seconde réservation',
    n = 1, format('réservations=%s (1 attendue)', n));
END $$;

-- T04 — LE CONTRAT DE L'ÉCRAN M04 (`08_prod_treso`) : la clôture produit la consommation,
-- UNE seule fois. Si R-044 réécrivait la sortie ici, la clôture serait refusée (23505
-- « OF … déjà clôturé ») et ce scénario le dirait.
DO $$
DECLARE x record; pf uuid; c_out numeric; pf_in numeric; mo_statut text;
BEGIN
  x := _b527('T04', 'planned');
  PERFORM _as_user();
  UPDATE manufacturing_orders SET status = 'in_progress' WHERE id = x.mo;
  UPDATE manufacturing_orders SET status = 'completed'   WHERE id = x.mo;
  PERFORM set_config('role', 'postgres', true);

  SELECT product_id, status INTO pf, mo_statut FROM manufacturing_orders WHERE id = x.mo;
  SELECT COALESCE(sum(sm.quantity), 0) INTO c_out FROM stock_movements sm
  WHERE sm.tenant_id = x.t AND sm.reference_type = 'production' AND sm.reference_id = x.mo
    AND sm.product_id = x.comp AND sm.movement_type = 'out';
  SELECT COALESCE(sum(sm.quantity), 0) INTO pf_in FROM stock_movements sm
  WHERE sm.tenant_id = x.t AND sm.reference_type = 'production' AND sm.reference_id = x.mo
    AND sm.product_id = pf AND sm.movement_type = 'in';

  PERFORM _rec('T04a', 'la clôture est ACCEPTÉE (R-044 n''a pas écrit la sortie) — statut completed',
    mo_statut = 'completed', format('statut=%s (completed attendu)', mo_statut));
  PERFORM _rec('T04b', 'OF terminé : −10 composants (UNE consommation, celle de la clôture)',
    c_out = 10, format('sortie composant=%s (10 attendue)', c_out));
  PERFORM _rec('T04c', 'OF terminé : +5 produits finis', pf_in = 5, format('entrée produit fini=%s (5 attendue)', pf_in));
END $$;

SELECT _audit_assert('527');