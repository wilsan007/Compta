-- ============================================================
-- 525_regle_r043_of_annule_contrepassation_tests.sql — partie B, lot Production, R-043
--
--   T01  annuler un OF CONTRE-PASSE ses mouvements (1 sortie → 1 entrée inverse) + lien ;
--   T02  un OF SANS mouvement ne produit rien (trace « sans_effet ») ;
--   T03  IDEMPOTENCE — un rejeu ne double pas la contre-passation.
-- \ir ci/audit_helpers.sql.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '525', false);
DELETE FROM _audit_results WHERE file = '525';

CREATE OR REPLACE FUNCTION _b525(p_nom text, p_mouvement boolean DEFAULT true,
                                 OUT t uuid, OUT mo uuid, OUT wh uuid, OUT p uuid)
LANGUAGE plpgsql AS $$
DECLARE v_wh uuid;
BEGIN
  t := _mk_tenant(p_nom);
  INSERT INTO warehouses (tenant_id, code, name) VALUES (t, 'W-' || p_nom, 'Dépôt') RETURNING id INTO wh;
  INSERT INTO products (tenant_id, name, sku, type) VALUES (t, 'Art ' || p_nom, 'A-' || p_nom, 'stock') RETURNING id INTO p;
  INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, movement_type, type, quantity, unit_cost, reference, movement_date, date)
    VALUES (t, p, wh, 'in', 'in', 100, 5, 'INIT', CURRENT_DATE, CURRENT_DATE);
  INSERT INTO manufacturing_orders (tenant_id, number, product_id, quantity, status)
    VALUES (t, 'OF-' || p_nom, p, 5, 'in_progress') RETURNING id INTO mo;
  IF p_mouvement THEN
    INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, movement_type, type, quantity, unit_cost,
                                 reference, reference_type, reference_id, movement_date, date)
      VALUES (t, p, wh, 'out', 'out', 5, 5, 'OF-' || p_nom, 'production', mo, CURRENT_DATE, CURRENT_DATE);
  END IF;
END $$;

DO $$
DECLARE x record; n_in int; nl int; ne int;
BEGIN
  x := _b525('T01');
  PERFORM _as_user();
  UPDATE manufacturing_orders SET status = 'cancelled' WHERE id = x.mo;

  SELECT count(*) INTO n_in FROM stock_movements sm
  WHERE sm.tenant_id = x.t AND sm.reference LIKE 'ANN-OF-%' AND sm.reference_type = 'production_reversal'
    AND sm.reference_id = x.mo AND sm.movement_type = 'in';
  PERFORM _rec('T01a', 'la contre-passation inverse la sortie (1 entrée ANN-OF-…)', n_in = 1, format('entrées=%s (1 attendue)', n_in));

  SELECT count(*) INTO nl FROM document_links dl
  WHERE dl.tenant_id = x.t AND dl.amont_type = 'manufacturing_orders' AND dl.amont_id = x.mo
    AND dl.effet = 'production.order.cancelled_reversed';
  PERFORM _rec('T01b', 'l''OF est lié à son mouvement de contre-passation', nl = 1, format('liens=%s (1 attendu)', nl));

  SELECT count(*) INTO ne FROM domain_events de
  WHERE de.tenant_id = x.t AND de.event_name = 'manufacturing_orders.cancelled_reversed' AND de.aggregate_id = x.mo;
  PERFORM _rec('T01c', 'un événement manufacturing_orders.cancelled_reversed est émis', ne = 1, format('événements=%s (1 attendu)', ne));
END $$;

DO $$
DECLARE x record; n int; nt int;
BEGIN
  x := _b525('T02', false);
  PERFORM _as_user();
  UPDATE manufacturing_orders SET status = 'cancelled' WHERE id = x.mo;
  SELECT count(*) INTO n FROM stock_movements sm
  WHERE sm.tenant_id = x.t AND sm.reference = 'ANN-OF-T02';
  SELECT count(*) INTO nt FROM chain_traces ct
  WHERE ct.tenant_id = x.t AND ct.effet = 'production.order.cancelled_reversed' AND ct.amont_id = x.mo AND ct.resultat = 'sans_effet';
  PERFORM _rec('T02', 'un OF sans mouvement ne produit rien (trace « sans_effet »)',
    n = 0 AND nt = 1, format('mouvements=%s trace sans_effet=%s (0 / 1 attendus)', n, nt));
END $$;

DO $$
DECLARE x record; n int;
BEGIN
  x := _b525('T03');
  PERFORM _as_user();
  UPDATE manufacturing_orders SET status = 'cancelled' WHERE id = x.mo;
  UPDATE manufacturing_orders SET status = 'in_progress' WHERE id = x.mo;
  UPDATE manufacturing_orders SET status = 'cancelled' WHERE id = x.mo;
  SELECT count(*) INTO n FROM stock_movements sm
  WHERE sm.tenant_id = x.t AND sm.reference LIKE 'ANN-OF-%' AND sm.movement_type = 'in' AND sm.reference_id = x.mo;
  PERFORM _rec('T03', 'un rejeu ne double pas la contre-passation', n = 1, format('entrées=%s (1 attendue)', n));
END $$;

SELECT _audit_assert('525');