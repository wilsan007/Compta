-- ============================================================
-- 653_reorder_suggestions_tests.sql — STK-09 / E.3
--
-- Mesuré AVANT la 653 : `reorder_rules` n'était lue par aucune fonction — un
-- écran n'aurait rien pu en tirer. Après : on propose jusqu'au maximum, arrondi
-- au multiple de conditionnement, dès que le stock atteint le minimum.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '653', false);
DELETE FROM _audit_results WHERE file = '653';

CREATE OR REPLACE FUNCTION _mk653(p_nom text, OUT t uuid, OUT wh uuid, OUT p uuid) LANGUAGE plpgsql AS $$
BEGIN
  t := _mk_tenant(p_nom, false);
  INSERT INTO warehouses (tenant_id, code, name) VALUES (t, 'W-' || p_nom, 'Dépôt ' || p_nom) RETURNING id INTO wh;
  INSERT INTO products (tenant_id, name, sku, type, cost_price) VALUES (t, 'Article ' || p_nom, 'SKU-' || p_nom, 'stock', 10) RETURNING id INTO p;
END $$;

CREATE OR REPLACE FUNCTION _stock653(p_t uuid, p_p uuid, p_wh uuid, p_qty numeric) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO stock_quantities (tenant_id, product_id, warehouse_id, quantity, unit_cost)
  VALUES (p_t, p_p, p_wh, p_qty, 10);
END $$;

-- T01 — stock 8 ≤ min 10 : on remonte au max 50, arrondi au multiple 5 → 45
DO $$
DECLARE t uuid; wh uuid; p uuid; g numeric;
BEGIN
  SELECT * INTO t, wh, p FROM _mk653('VAL653T01');
  PERFORM _stock653(t, p, wh, 8);
  INSERT INTO reorder_rules (tenant_id, product_id, warehouse_id, min_quantity, max_quantity, multiple_quantity)
  VALUES (t, p, wh, 10, 50, 5);
  SELECT suggested_qty INTO g FROM reorder_suggestions() WHERE product_id = p;
  PERFORM _rec('T01', 'stock 8 ≤ min 10 → max 50, arrondi multiple 5 = 45', g = 45, format('suggéré=%s (45 attendu)', g));
END $$;

-- T02 — stock au-dessus du minimum : aucune proposition
DO $$
DECLARE t uuid; wh uuid; p uuid; n int;
BEGIN
  SELECT * INTO t, wh, p FROM _mk653('VAL653T02');
  PERFORM _stock653(t, p, wh, 30);
  INSERT INTO reorder_rules (tenant_id, product_id, warehouse_id, min_quantity, max_quantity, multiple_quantity)
  VALUES (t, p, wh, 10, 50, 5);
  SELECT count(*) INTO n FROM reorder_suggestions() WHERE product_id = p;
  PERFORM _rec('T02', 'stock 30 > min 10 → aucune suggestion', n = 0, format('lignes=%s (0 attendu)', n));
END $$;

-- T03 — stock exactement au minimum : on propose
DO $$
DECLARE t uuid; wh uuid; p uuid; g numeric;
BEGIN
  SELECT * INTO t, wh, p FROM _mk653('VAL653T03');
  PERFORM _stock653(t, p, wh, 10);
  INSERT INTO reorder_rules (tenant_id, product_id, warehouse_id, min_quantity, max_quantity, multiple_quantity)
  VALUES (t, p, wh, 10, 50, 5);
  SELECT suggested_qty INTO g FROM reorder_suggestions() WHERE product_id = p;
  PERFORM _rec('T03', 'stock = min 10 → max 50, multiple 5 = 40', g = 40, format('suggéré=%s (40 attendu)', g));
END $$;

-- T04 — multiple 0 (ou nul) vaut 1 : on ne divise pas par zéro
DO $$
DECLARE t uuid; wh uuid; p uuid; g numeric;
BEGIN
  SELECT * INTO t, wh, p FROM _mk653('VAL653T04');
  PERFORM _stock653(t, p, wh, 8);
  INSERT INTO reorder_rules (tenant_id, product_id, warehouse_id, min_quantity, max_quantity, multiple_quantity)
  VALUES (t, p, wh, 10, 50, 0);
  SELECT suggested_qty INTO g FROM reorder_suggestions() WHERE product_id = p;
  PERFORM _rec('T04', 'multiple 0 traité comme 1 → max 50 − stock 8 = 42', g = 42, format('suggéré=%s (42 attendu)', g));
END $$;

-- T05 — règle sans dépôt : le stock lu est le total de la société
DO $$
DECLARE t uuid; wh uuid; p uuid; wh2 uuid; g numeric;
BEGIN
  SELECT * INTO t, wh, p FROM _mk653('VAL653T05');
  INSERT INTO warehouses (tenant_id, code, name) VALUES (t, 'W2-VAL653T05', 'Dépôt 2') RETURNING id INTO wh2;
  PERFORM _stock653(t, p, wh, 5);
  PERFORM _stock653(t, p, wh2, 5);
  INSERT INTO reorder_rules (tenant_id, product_id, warehouse_id, min_quantity, max_quantity, multiple_quantity)
  VALUES (t, p, NULL, 10, 50, 1);
  SELECT suggested_qty INTO g FROM reorder_suggestions() WHERE product_id = p;
  PERFORM _rec('T05', 'règle « tous dépôts » : stock total 10 ≤ min 10 → 40', g = 40, format('suggéré=%s (40 attendu)', g));
END $$;

SELECT _audit_assert('653');
