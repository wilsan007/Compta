-- ============================================================
-- 651_mrp_consommation_previsions_tests.sql — PRD-03
--
-- Mesuré AVANT la 651 : `run_mrp` additionnait prévision ET commande ferme
-- (100 + 40 = 140). La politique standard (Sage « consommation des prévisions »,
-- Odoo « consume forecast ») veut que la commande ferme consomme la prévision
-- de la période : 100 − 40 = 60.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '651', false);
DELETE FROM _audit_results WHERE file = '651';

CREATE OR REPLACE FUNCTION _mk651(p_nom text, OUT t uuid, OUT p uuid) LANGUAGE plpgsql AS $$
BEGIN
  t := _mk_tenant(p_nom, false);
  INSERT INTO products (tenant_id, name, sku, type, cost_price, safety_stock, lead_time_days)
  VALUES (t, 'Article ' || p_nom, 'SKU-' || p_nom, 'stock', 10, 0, 7)
  RETURNING id INTO p;
END $$;

-- Une prévision de p_qte et, si p_so > 0, une commande ferme de p_so livrée dans
-- la fenêtre de la prévision (J+5).
CREATE OR REPLACE FUNCTION _setup651(p_t uuid, p_p uuid, p_prev numeric, p_so numeric)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_so uuid;
BEGIN
  IF p_prev IS NOT NULL THEN
    INSERT INTO production_forecasts (tenant_id, forecast_number, period, start_date, end_date, product_id, forecasted_quantity)
    VALUES (p_t, 'PREV-' || p_p, '2026-10', CURRENT_DATE, CURRENT_DATE + 30, p_p, p_prev);
  END IF;
  IF p_so IS NOT NULL AND p_so > 0 THEN
    INSERT INTO sales_orders (tenant_id, number, status, delivery_date)
    VALUES (p_t, 'SO-' || p_p, 'confirmed', CURRENT_DATE + 5) RETURNING id INTO v_so;
    INSERT INTO sales_order_lines (tenant_id, sales_order_id, product_id, description, quantity, unit_price)
    VALUES (p_t, v_so, p_p, 'Ligne', p_so, 10);
  END IF;
END $$;

-- T01 — la commande ferme consomme la prévision : 100 − 40 = 60 (et non 140)
DO $$
DECLARE t uuid; p uuid; g numeric;
BEGIN
  SELECT * INTO t, p FROM _mk651('VAL651T01');
  PERFORM _setup651(t, p, 100, 40);
  SELECT COALESCE(SUM(gross_need), 0) INTO g FROM run_mrp(t, 365);
  PERFORM _rec('T01', 'commande ferme de 40 consomme la prévision de 100 → besoin brut 60',
    g = 60, format('gross_need=%s (attendu 60 ; sans consommation : 140)', g));
END $$;

-- T02 — porte de non-régression : p_consume_forecast := false rend le double comptage
DO $$
DECLARE t uuid; p uuid; g numeric;
BEGIN
  SELECT * INTO t, p FROM _mk651('VAL651T02');
  PERFORM _setup651(t, p, 100, 40);
  SELECT COALESCE(SUM(gross_need), 0) INTO g FROM run_mrp(t, 365, false);
  PERFORM _rec('T02', 'politique brute (p_consume_forecast=false) : 100 + 40 = 140',
    g = 140, format('gross_need=%s (attendu 140)', g));
END $$;

-- T03 — une commande ferme hors de toute fenêtre de prévision reste un besoin
DO $$
DECLARE t uuid; p uuid; g numeric;
BEGIN
  SELECT * INTO t, p FROM _mk651('VAL651T03');
  PERFORM _setup651(t, p, NULL, 25);
  SELECT COALESCE(SUM(gross_need), 0) INTO g FROM run_mrp(t, 365);
  PERFORM _rec('T03', 'commande ferme sans prévision → besoin brut 25',
    g = 25, format('gross_need=%s (attendu 25)', g));
END $$;

-- T04 — une prévision sans commande ferme reste un besoin plein
DO $$
DECLARE t uuid; p uuid; g numeric;
BEGIN
  SELECT * INTO t, p FROM _mk651('VAL651T04');
  PERFORM _setup651(t, p, 100, NULL);
  SELECT COALESCE(SUM(gross_need), 0) INTO g FROM run_mrp(t, 365);
  PERFORM _rec('T04', 'prévision seule → besoin brut 100',
    g = 100, format('gross_need=%s (attendu 100)', g));
END $$;

SELECT _audit_assert('651');
