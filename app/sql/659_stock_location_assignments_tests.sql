-- ============================================================
-- 659_stock_location_assignments_tests.sql — STK-11 / E.3
--
-- Mesuré AVANT la 659 : rien ne ventile le stock par casier. Après : le stock
-- s'affecte à un casier, la somme (casiers + non affecté) vaut le stock dépôt,
-- et une affectation au-delà du stock est refusée.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '659', false);
DELETE FROM _audit_results WHERE file = '659';

CREATE OR REPLACE FUNCTION _mk659(p_nom text, OUT t uuid, OUT wh uuid, OUT loc uuid, OUT p uuid) LANGUAGE plpgsql AS $$
BEGIN
  t := _mk_tenant(p_nom, false);
  INSERT INTO warehouses (tenant_id, code, name) VALUES (t, 'W-' || p_nom, 'Dépôt ' || p_nom) RETURNING id INTO wh;
  INSERT INTO warehouse_locations (tenant_id, warehouse_id, code) VALUES (t, wh, 'A-01') RETURNING id INTO loc;
  INSERT INTO products (tenant_id, name, sku, type, cost_price) VALUES (t, 'Art ' || p_nom, 'SKU-' || p_nom, 'stock', 10) RETURNING id INTO p;
  INSERT INTO stock_quantities (tenant_id, product_id, warehouse_id, quantity, unit_cost) VALUES (t, p, wh, 100, 10);
END $$;

-- T01 — affecter 30 : 30 au casier + 70 non affecté = 100 (le stock dépôt)
DO $$
DECLARE t uuid; wh uuid; loc uuid; p uuid; n int; tot numeric; atloc numeric;
BEGIN
  SELECT * INTO t, wh, loc, p FROM _mk659('VAL659T01');
  PERFORM assign_stock_to_location(p, wh, loc, 30);
  SELECT count(*), SUM(quantity), max(quantity) FILTER (WHERE assigned) INTO n, tot, atloc
  FROM location_stock(wh) WHERE product_id = p;
  PERFORM _rec('T01', '30 au casier + 70 non affecté = 100 (stock dépôt)', (n = 2 AND tot = 100 AND atloc = 30), format('lignes=%s, total=%s (100), casier=%s (30)', n, tot, atloc));
END $$;

-- T02 — affecter au-delà du stock est refusé (deux casiers)
DO $$
DECLARE t uuid; wh uuid; loc uuid; p uuid; loc2 uuid; refus boolean := false;
BEGIN
  SELECT * INTO t, wh, loc, p FROM _mk659('VAL659T02');
  INSERT INTO warehouse_locations (tenant_id, warehouse_id, code) VALUES (t, wh, 'A-02') RETURNING id INTO loc2;
  PERFORM assign_stock_to_location(p, wh, loc, 30);
  BEGIN PERFORM assign_stock_to_location(p, wh, loc2, 80); EXCEPTION WHEN OTHERS THEN refus := true; END;
  PERFORM _rec('T02', 'affecter 30 (casier A) + 80 (casier B) sur un stock de 100 est refusé', refus, 'refus=' || refus);
END $$;

-- T03 — réaffecter le même casier remplace la quantité (pas de doublon)
DO $$
DECLARE t uuid; wh uuid; loc uuid; p uuid; n int; atloc numeric; rest numeric;
BEGIN
  SELECT * INTO t, wh, loc, p FROM _mk659('VAL659T03');
  PERFORM assign_stock_to_location(p, wh, loc, 30);
  PERFORM assign_stock_to_location(p, wh, loc, 40);
  SELECT count(*), max(quantity) FILTER (WHERE assigned) INTO n, atloc FROM location_stock(wh) WHERE product_id = p;
  SELECT max(quantity) INTO rest FROM location_stock(wh) WHERE product_id = p AND NOT assigned;
  PERFORM _rec('T03', 'réaffecter le même casier à 40 : 40 au casier, 60 non affecté', (n = 2 AND atloc = 40 AND rest = 60), format('lignes=%s, casier=%s (40), reste=%s (60)', n, atloc, rest));
END $$;

SELECT _audit_assert('659');
