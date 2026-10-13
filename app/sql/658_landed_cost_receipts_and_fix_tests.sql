-- ============================================================
-- 658_landed_cost_receipts_and_fix_tests.sql — STK-08 / E.3
--
-- Mesuré AVANT la 658 : `distribute_landed_cost` répartissait sur TOUTES les
-- réceptions de la société, sans cible, sans garde, sans idempotence.
-- Après : elle ne répartit que sur les réceptions ciblées, ajuste le bon CUMP,
-- efface une répartition antérieure et refuse un second appel.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '658', false);
DELETE FROM _audit_results WHERE file = '658';

CREATE OR REPLACE FUNCTION _mk658(p_nom text, OUT t uuid, OUT wh uuid, OUT p uuid) LANGUAGE plpgsql AS $$
BEGIN
  t := _mk_tenant(p_nom, false);
  INSERT INTO warehouses (tenant_id, code, name) VALUES (t, 'W-' || p_nom, 'Dépôt ' || p_nom) RETURNING id INTO wh;
  INSERT INTO products (tenant_id, name, sku, type, cost_price) VALUES (t, 'Art ' || p_nom, 'SKU-' || p_nom, 'stock', 10) RETURNING id INTO p;
  INSERT INTO stock_quantities (tenant_id, product_id, warehouse_id, quantity, unit_cost) VALUES (t, p, wh, 100, 10);
END $$;

CREATE OR REPLACE FUNCTION _receipt658(p_t uuid, p_wh uuid, p_p uuid, p_qty numeric, p_num text) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v uuid;
BEGIN
  INSERT INTO goods_receipts (tenant_id, number, warehouse_id, receipt_date, status)
  VALUES (p_t, p_num, p_wh, CURRENT_DATE, 'received') RETURNING id INTO v;
  INSERT INTO goods_receipt_lines (tenant_id, goods_receipt_id, product_id, description, quantity_received)
  VALUES (p_t, v, p_p, 'Ligne ' || p_num, p_qty);
  RETURN v;
END $$;

-- T01 — 500 € répartis sur une réception de 1 000 € : CUMP 10 → 15
DO $$
DECLARE t uuid; wh uuid; p uuid; rc uuid; lc uuid; amt numeric; cump numeric;
BEGIN
  SELECT * INTO t, wh, p FROM _mk658('VAL658T01');
  rc := _receipt658(t, wh, p, 100, 'RC-T01');
  INSERT INTO landed_costs (tenant_id, invoice_number, total_amount, distribution_method, status)
  VALUES (t, 'LC-T01', 500, 'value', 'pending') RETURNING id INTO lc;
  INSERT INTO landed_cost_receipts (tenant_id, landed_cost_id, receipt_id) VALUES (t, lc, rc);
  PERFORM distribute_landed_cost(lc);
  SELECT max(distributed_amount) INTO amt FROM landed_cost_lines WHERE landed_cost_id = lc;
  SELECT max(unit_cost) INTO cump FROM stock_quantities WHERE tenant_id = t AND product_id = p AND warehouse_id = wh;
  PERFORM _rec('T01', '500 € sur une réception de 1 000 € : réparti 500, CUMP 10 → 15', (amt = 500 AND cump = 15), format('réparti=%s (500), CUMP=%s (15)', amt, cump));
END $$;

-- T02 — une dépense sans réception ciblée refuse de répartir (base nulle)
DO $$
DECLARE t uuid; wh uuid; p uuid; lc uuid; refus boolean := false;
BEGIN
  SELECT * INTO t, wh, p FROM _mk658('VAL658T02');
  PERFORM _receipt658(t, wh, p, 100, 'RC-T02');
  INSERT INTO landed_costs (tenant_id, invoice_number, total_amount, distribution_method, status)
  VALUES (t, 'LC-T02', 500, 'value', 'pending') RETURNING id INTO lc;
  BEGIN PERFORM distribute_landed_cost(lc); EXCEPTION WHEN OTHERS THEN refus := true; END;
  PERFORM _rec('T02', 'sans réception ciblée, la répartition est refusée', refus, 'refus=' || refus);
END $$;

-- T03 — un second appel est refusé (idempotence)
DO $$
DECLARE t uuid; wh uuid; p uuid; rc uuid; lc uuid; refus boolean := false;
BEGIN
  SELECT * INTO t, wh, p FROM _mk658('VAL658T03');
  rc := _receipt658(t, wh, p, 100, 'RC-T03');
  INSERT INTO landed_costs (tenant_id, invoice_number, total_amount, distribution_method, status)
  VALUES (t, 'LC-T03', 500, 'value', 'pending') RETURNING id INTO lc;
  INSERT INTO landed_cost_receipts (tenant_id, landed_cost_id, receipt_id) VALUES (t, lc, rc);
  PERFORM distribute_landed_cost(lc);
  BEGIN PERFORM distribute_landed_cost(lc); EXCEPTION WHEN OTHERS THEN refus := true; END;
  PERFORM _rec('T03', 'un frais déjà réparti refuse un second appel', refus, 'refus=' || refus);
END $$;

-- T04 — la base ne retient QUE la réception ciblée (une autre réception est ignorée)
DO $$
DECLARE t uuid; wh uuid; p uuid; rc1 uuid; rc2 uuid; lc uuid; base numeric;
BEGIN
  SELECT * INTO t, wh, p FROM _mk658('VAL658T04');
  rc1 := _receipt658(t, wh, p, 100, 'RC-T04a');
  rc2 := _receipt658(t, wh, p, 900, 'RC-T04b');
  INSERT INTO landed_costs (tenant_id, invoice_number, total_amount, distribution_method, status)
  VALUES (t, 'LC-T04', 500, 'value', 'pending') RETURNING id INTO lc;
  INSERT INTO landed_cost_receipts (tenant_id, landed_cost_id, receipt_id) VALUES (t, lc, rc1);
  base := (distribute_landed_cost(lc) ->> 'base')::numeric;
  PERFORM _rec('T04', 'la base ne retient que la réception ciblée (1 000, pas 10 000)', base = 1000, format('base=%s (1000 attendu)', base));
END $$;

SELECT _audit_assert('658');
