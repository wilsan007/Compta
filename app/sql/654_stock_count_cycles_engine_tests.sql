-- ============================================================
-- 654_stock_count_cycles_engine_tests.sql — STK-09 / E.3
--
-- Mesuré AVANT la 654 : `stock_count_cycles` n'était lu par aucune fonction.
-- Après : la liste des comptages dus se génère, un comptage produit son écart
-- (entrée/sortie valorisée) et avance la prochaine date.
-- ============================================================
\ir ci/audit_helpers.sql
\ir ci/ledger_fixture.sql
SELECT set_config('audit.file', '654', false);
DELETE FROM _audit_results WHERE file = '654';

CREATE OR REPLACE FUNCTION _mk654(p_nom text, OUT t uuid, OUT wh uuid, OUT p uuid) LANGUAGE plpgsql AS $$
BEGIN
  t := _mk_tenant(p_nom, false);
  PERFORM _ledger_fixture(t);
  INSERT INTO warehouses (tenant_id, code, name) VALUES (t, 'W-' || p_nom, 'Dépôt ' || p_nom) RETURNING id INTO wh;
  INSERT INTO products (tenant_id, name, sku, type, cost_price) VALUES (t, 'Article ' || p_nom, 'SKU-' || p_nom, 'stock', 10) RETURNING id INTO p;
END $$;

CREATE OR REPLACE FUNCTION _seed654(p_t uuid, p_p uuid, p_wh uuid, p_qty numeric) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO stock_movements
    (tenant_id, product_id, warehouse_id, type, movement_type, quantity, unit_cost, date, movement_date, reference_type, notes)
  VALUES (p_t, p_p, p_wh, 'in', 'in', p_qty, 10, CURRENT_DATE, CURRENT_DATE, 'seed654', 'entrée initiale');
END $$;

-- T01 — un cycle dû aujourd'hui est proposé, avec son stock courant
DO $$
DECLARE t uuid; wh uuid; p uuid; n int; cs numeric;
BEGIN
  SELECT * INTO t, wh, p FROM _mk654('VAL654T01');
  PERFORM _seed654(t, p, wh, 100);
  INSERT INTO stock_count_cycles (tenant_id, product_id, warehouse_id, abc_class, frequency_days, next_count_date, is_active)
  VALUES (t, p, wh, 'A', 30, CURRENT_DATE, true);
  SELECT count(*), max(current_stock) INTO n, cs FROM generate_count_list() WHERE product_id = p;
  PERFORM _rec('T01', 'un cycle dû aujourd''hui est proposé, avec son stock', (n = 1 AND cs = 100), format('lignes=%s, stock=%s (100 attendu)', n, cs));
END $$;

-- T02 — comptage inférieur : sortie de l'écart, le stock diminue
DO $$
DECLARE t uuid; wh uuid; p uuid; cc uuid; v numeric; q numeric;
BEGIN
  SELECT * INTO t, wh, p FROM _mk654('VAL654T02');
  PERFORM _seed654(t, p, wh, 100);
  INSERT INTO stock_count_cycles (tenant_id, product_id, warehouse_id, abc_class, frequency_days, next_count_date, is_active)
  VALUES (t, p, wh, 'A', 30, CURRENT_DATE, true) RETURNING id INTO cc;
  v := record_stock_count(cc, 95);
  SELECT COALESCE(quantity, 0) INTO q FROM stock_quantities WHERE tenant_id = t AND product_id = p AND warehouse_id = wh;
  PERFORM _rec('T02', 'compter 95 pour 100 : écart −5, le stock passe à 95', (v = -5 AND q = 95), format('écart=%s (−5 attendu), stock=%s (95 attendu)', v, q));
END $$;

-- T03 — comptage supérieur : entrée de l'écart, le stock augmente
DO $$
DECLARE t uuid; wh uuid; p uuid; cc uuid; v numeric; q numeric;
BEGIN
  SELECT * INTO t, wh, p FROM _mk654('VAL654T03');
  PERFORM _seed654(t, p, wh, 100);
  INSERT INTO stock_count_cycles (tenant_id, product_id, warehouse_id, abc_class, frequency_days, next_count_date, is_active)
  VALUES (t, p, wh, 'B', 90, CURRENT_DATE, true) RETURNING id INTO cc;
  v := record_stock_count(cc, 110);
  SELECT COALESCE(quantity, 0) INTO q FROM stock_quantities WHERE tenant_id = t AND product_id = p AND warehouse_id = wh;
  PERFORM _rec('T03', 'compter 110 pour 100 : écart +10, le stock passe à 110', (v = 10 AND q = 110), format('écart=%s (10 attendu), stock=%s (110 attendu)', v, q));
END $$;

-- T04 — un cycle à échéance future n'est pas proposé
DO $$
DECLARE t uuid; wh uuid; p uuid; n int;
BEGIN
  SELECT * INTO t, wh, p FROM _mk654('VAL654T04');
  PERFORM _seed654(t, p, wh, 50);
  INSERT INTO stock_count_cycles (tenant_id, product_id, warehouse_id, abc_class, frequency_days, next_count_date, is_active)
  VALUES (t, p, wh, 'C', 180, CURRENT_DATE + 30, true);
  SELECT count(*) INTO n FROM generate_count_list() WHERE product_id = p;
  PERFORM _rec('T04', 'un cycle à échéance future n''est pas proposé', n = 0, format('lignes=%s (0 attendu)', n));
END $$;

-- T05 — après comptage, la prochaine date avance de la fréquence
DO $$
DECLARE t uuid; wh uuid; p uuid; cc uuid; nd date;
BEGIN
  SELECT * INTO t, wh, p FROM _mk654('VAL654T05');
  PERFORM _seed654(t, p, wh, 100);
  INSERT INTO stock_count_cycles (tenant_id, product_id, warehouse_id, abc_class, frequency_days, next_count_date, is_active)
  VALUES (t, p, wh, 'A', 30, CURRENT_DATE, true) RETURNING id INTO cc;
  PERFORM record_stock_count(cc, 100);
  SELECT next_count_date INTO nd FROM stock_count_cycles WHERE id = cc;
  PERFORM _rec('T05', 'après comptage, prochaine date = aujourd''hui + 30 j', nd = CURRENT_DATE + 30, format('prochaine=%s (%s attendu)', nd, CURRENT_DATE + 30));
END $$;

SELECT _audit_assert('654');
