-- ============================================================
-- 660_location_putaway_pick_tests.sql — STK-11 / E.3
--
-- Mesuré AVANT la 660 : aucune règle de rangement ni de prélèvement. Après : on
-- propose où ranger (regrouper, sinon un casier vide, sinon le moins occupé) et
-- où prélever (le casier qui en détient le plus).
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '660', false);
DELETE FROM _audit_results WHERE file = '660';

CREATE OR REPLACE FUNCTION _mk660(p_nom text, OUT t uuid, OUT wh uuid, OUT loca uuid, OUT locb uuid, OUT p uuid) LANGUAGE plpgsql AS $$
BEGIN
  t := _mk_tenant(p_nom, false);
  INSERT INTO warehouses (tenant_id, code, name) VALUES (t, 'W-' || p_nom, 'Dépôt ' || p_nom) RETURNING id INTO wh;
  INSERT INTO warehouse_locations (tenant_id, warehouse_id, code, location_type) VALUES (t, wh, 'A-01', 'storage') RETURNING id INTO loca;
  INSERT INTO warehouse_locations (tenant_id, warehouse_id, code, location_type) VALUES (t, wh, 'A-02', 'storage') RETURNING id INTO locb;
  INSERT INTO products (tenant_id, name, sku, type, cost_price) VALUES (t, 'Art ' || p_nom, 'SKU-' || p_nom, 'stock', 10) RETURNING id INTO p;
  INSERT INTO stock_quantities (tenant_id, product_id, warehouse_id, quantity, unit_cost) VALUES (t, p, wh, 100, 10);
END $$;

-- T01 — sans affectation, on propose un casier vide
DO $$
DECLARE t uuid; wh uuid; loca uuid; locb uuid; p uuid; lc text; r text;
BEGIN
  SELECT * INTO t, wh, loca, locb, p FROM _mk660('VAL660T01');
  SELECT location_code, reason INTO lc, r FROM suggest_putaway_location(p, wh);
  PERFORM _rec('T01', 'sans affectation, le rangement propose un casier vide', (lc = 'A-01' AND r = 'empty'), format('casier=%s, motif=%s (A-01 / empty)', lc, r));
END $$;

-- T02 — un article déjà rangé est regroupé
DO $$
DECLARE t uuid; wh uuid; loca uuid; locb uuid; p uuid; lc text; r text;
BEGIN
  SELECT * INTO t, wh, loca, locb, p FROM _mk660('VAL660T02');
  PERFORM assign_stock_to_location(p, wh, locb, 30);
  SELECT location_code, reason INTO lc, r FROM suggest_putaway_location(p, wh);
  PERFORM _rec('T02', 'un article déjà au casier A-02 y est regroupé', (lc = 'A-02' AND r = 'consolidate'), format('casier=%s, motif=%s (A-02 / consolidate)', lc, r));
END $$;

-- T03 — le prélèvement propose le casier qui en détient le plus
DO $$
DECLARE t uuid; wh uuid; loca uuid; locb uuid; p uuid; lc text; q numeric;
BEGIN
  SELECT * INTO t, wh, loca, locb, p FROM _mk660('VAL660T03');
  PERFORM assign_stock_to_location(p, wh, loca, 20);
  PERFORM assign_stock_to_location(p, wh, locb, 50);
  SELECT location_code, quantity INTO lc, q FROM suggest_pick_location(p, wh);
  PERFORM _rec('T03', 'le prélèvement propose le casier qui en détient le plus (A-02, 50)', (lc = 'A-02' AND q = 50), format('casier=%s, quantité=%s (A-02 / 50)', lc, q));
END $$;

SELECT _audit_assert('660');
