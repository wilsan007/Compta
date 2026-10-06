-- ============================================================
-- 655_stock_by_location_tests.sql — STK-11 / E.3
--
-- Mesuré AVANT la 655 : aucun moyen de ventiler le stock par emplacement, alors
-- que `stock_quantities.location_id` et l'arbre des emplacements existent.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '655', false);
DELETE FROM _audit_results WHERE file = '655';

CREATE OR REPLACE FUNCTION _mk655(p_nom text, OUT t uuid, OUT wh uuid) LANGUAGE plpgsql AS $$
BEGIN
  t := _mk_tenant(p_nom, false);
  INSERT INTO warehouses (tenant_id, code, name) VALUES (t, 'W-' || p_nom, 'Dépôt ' || p_nom) RETURNING id INTO wh;
END $$;

-- T01 — un stock sans emplacement se lit « non affecté » (location_code NULL)
DO $$
DECLARE t uuid; wh uuid; p uuid; n int; cs numeric; lc text;
BEGIN
  SELECT * INTO t, wh FROM _mk655('VAL655T01');
  INSERT INTO products (tenant_id, name, sku, type, cost_price) VALUES (t, 'Art T01', 'SKU-T01', 'stock', 10) RETURNING id INTO p;
  INSERT INTO stock_quantities (tenant_id, product_id, warehouse_id, quantity, unit_cost) VALUES (t, p, wh, 100, 10);
  SELECT count(*), max(quantity), max(location_code) INTO n, cs, lc FROM stock_by_location(wh) WHERE product_id = p;
  PERFORM _rec('T01', 'un stock sans emplacement se lit « non affecté » (code NULL)', (n = 1 AND cs = 100 AND lc IS NULL), format('lignes=%s, qty=%s, code=%s', n, cs, lc));
END $$;

-- T02 — un stock affecté affiche le code de son emplacement
DO $$
DECLARE t uuid; wh uuid; p uuid; loc uuid; cs numeric; lc text;
BEGIN
  SELECT * INTO t, wh FROM _mk655('VAL655T02');
  INSERT INTO warehouse_locations (tenant_id, warehouse_id, code, location_type) VALUES (t, wh, 'A-01-01', 'storage') RETURNING id INTO loc;
  INSERT INTO products (tenant_id, name, sku, type, cost_price) VALUES (t, 'Art T02', 'SKU-T02', 'stock', 10) RETURNING id INTO p;
  INSERT INTO stock_quantities (tenant_id, product_id, warehouse_id, location_id, quantity, unit_cost) VALUES (t, p, wh, loc, 30, 10);
  SELECT max(quantity), max(location_code) INTO cs, lc FROM stock_by_location(wh) WHERE product_id = p;
  PERFORM _rec('T02', 'un stock affecté affiche le code de son emplacement', (cs = 30 AND lc = 'A-01-01'), format('qty=%s, code=%s (A-01-01 attendu)', cs, lc));
END $$;

-- T03 — le filtre par dépôt isole le stock
DO $$
DECLARE t uuid; wh uuid; wh2 uuid; p uuid; n int;
BEGIN
  SELECT * INTO t, wh FROM _mk655('VAL655T03');
  INSERT INTO warehouses (tenant_id, code, name) VALUES (t, 'W2-T03', 'Dépôt 2') RETURNING id INTO wh2;
  INSERT INTO products (tenant_id, name, sku, type, cost_price) VALUES (t, 'Art T03', 'SKU-T03', 'stock', 10) RETURNING id INTO p;
  INSERT INTO stock_quantities (tenant_id, product_id, warehouse_id, quantity, unit_cost) VALUES (t, p, wh, 10, 10);
  SELECT count(*) INTO n FROM stock_by_location(wh2) WHERE product_id = p;
  PERFORM _rec('T03', 'le filtre par dépôt isole le stock', n = 0, format('lignes=%s (0 attendu)', n));
END $$;

SELECT _audit_assert('655');
