-- ============================================================
-- 144_fix_mrp_and_valuation.sql
-- LOT4-07 : Éclatement MRP récursif + run_mrp
--
-- Problèmes :
-- 1. run_mrp utilise CREATE TEMP TABLE IF NOT EXISTS → échec au 2e appel
-- 2. run_mrp référence pol.quantity_received sur purchase_order_lines
--    qui n'existe pas (cf. LOT2-17)
-- 3. explode_bom_recursive semble déjà correct dans 115
--
-- Fix : Réécrire run_mrp avec DROP + CREATE TEMP TABLE,
-- et calculer les quantités reçues depuis goods_receipt_lines.
-- ============================================================

CREATE OR REPLACE FUNCTION run_mrp(
  p_tenant_id uuid DEFAULT NULL,
  p_horizon_days int DEFAULT 90
)
RETURNS TABLE(
  product_id uuid,
  product_name text,
  gross_need numeric,
  stock_available numeric,
  open_purchase_qty numeric,
  open_production_qty numeric,
  net_need numeric,
  suggested_qty numeric,
  suggested_date date,
  low_level_code int,
  source text,
  need_date date,
  is_late boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := COALESCE(p_tenant_id, current_tenant_id());
  v_horizon date := CURRENT_DATE + p_horizon_days;
BEGIN
  -- LOT4-07 : DROP + CREATE au lieu de IF NOT EXISTS
  DROP TABLE IF EXISTS _mrp_needs;
  CREATE TEMP TABLE _mrp_needs AS
  SELECT
    exp.product_id,
    exp.gross_need,
    exp.low_level_code,
    mo.start_date AS need_date,
    'manufacturing_order' AS source
  FROM manufacturing_orders mo
  CROSS JOIN LATERAL explode_bom_recursive(v_tid, mo.bom_id, mo.quantity) exp
  WHERE mo.tenant_id = v_tid AND mo.status IN ('planned', 'in_progress');

  -- 2. Besoins des commandes clients confirmées non livrées
  INSERT INTO _mrp_needs
  SELECT
    sol.product_id,
    sol.quantity AS gross_need,
    0 AS low_level_code,
    so.delivery_date AS need_date,
    'sales_order' AS source
  FROM sales_orders so
  JOIN sales_order_lines sol ON sol.sales_order_id = so.id AND sol.tenant_id = v_tid
  WHERE so.tenant_id = v_tid AND so.status IN ('confirmed', 'in_progress')
    AND COALESCE(so.delivery_date, CURRENT_DATE) <= v_horizon;

  -- 3. Prévisions de production
  INSERT INTO _mrp_needs
  SELECT
    pf.product_id,
    pf.quantity AS gross_need,
    0 AS low_level_code,
    pf.forecast_date AS need_date,
    'forecast' AS source
  FROM production_forecasts pf
  WHERE pf.tenant_id = v_tid
    AND COALESCE(pf.forecast_date, CURRENT_DATE) <= v_horizon;

  -- 4. Agréger et calculer le besoin net
  RETURN QUERY
  WITH aggregated_needs AS (
    SELECT
      n.product_id,
      SUM(n.gross_need) AS total_gross_need,
      MAX(n.low_level_code) AS low_level_code,
      MIN(n.need_date) AS earliest_need_date,
      MAX(n.need_date) AS latest_need_date
    FROM _mrp_needs n
    GROUP BY n.product_id
  ),
  stock_info AS (
    SELECT
      sq.product_id,
      COALESCE(SUM(sq.quantity), 0) AS stock_qty
    FROM stock_quantities sq
    WHERE sq.tenant_id = v_tid
    GROUP BY sq.product_id
  ),
  -- LOT4-07 : Calculer les quantités reçues depuis goods_receipt_lines
  -- au lieu de pol.quantity_received (inexistant sur purchase_order_lines)
  open_po AS (
    SELECT
      pol.product_id,
      SUM(pol.quantity - COALESCE(grl.qty_received, 0)) AS open_qty
    FROM purchase_order_lines pol
    JOIN purchase_orders po ON po.id = pol.purchase_order_id AND po.tenant_id = pol.tenant_id
    LEFT JOIN LATERAL (
      SELECT SUM(grl.quantity_received) AS qty_received
      FROM goods_receipt_lines grl
      JOIN goods_receipts gr ON gr.id = grl.goods_receipt_id AND gr.tenant_id = grl.tenant_id
      WHERE gr.purchase_order_id = po.id
        AND gr.tenant_id = v_tid
        AND grl.product_id = pol.product_id
        AND gr.status = 'received'
    ) grl ON true
    WHERE po.tenant_id = v_tid AND po.status IN ('draft', 'sent')
    GROUP BY pol.product_id
  ),
  open_mo AS (
    SELECT
      mo.product_id,
      SUM(mo.quantity - COALESCE(mo.qty_produced, 0)) AS open_qty
    FROM manufacturing_orders mo
    WHERE mo.tenant_id = v_tid AND mo.status IN ('planned', 'in_progress')
    GROUP BY mo.product_id
  )
  SELECT
    a.product_id,
    p.name AS product_name,
    a.total_gross_need AS gross_need,
    COALESCE(s.stock_qty, 0) AS stock_available,
    COALESCE(po.open_qty, 0) AS open_purchase_qty,
    COALESCE(mo.open_qty, 0) AS open_production_qty,
    GREATEST(0, a.total_gross_need + COALESCE(p.safety_stock, 0) - COALESCE(s.stock_qty, 0) - COALESCE(po.open_qty, 0) - COALESCE(mo.open_qty, 0)) AS net_need,
    CASE
      WHEN GREATEST(0, a.total_gross_need + COALESCE(p.safety_stock, 0) - COALESCE(s.stock_qty, 0) - COALESCE(po.open_qty, 0) - COALESCE(mo.open_qty, 0)) > 0
      THEN GREATEST(
        CEIL(GREATEST(0, a.total_gross_need + COALESCE(p.safety_stock, 0) - COALESCE(s.stock_qty, 0) - COALESCE(po.open_qty, 0) - COALESCE(mo.open_qty, 0)) / COALESCE(p.qty_multiple, 1)) * COALESCE(p.qty_multiple, 1),
        COALESCE(p.min_order_qty, 0)
      )
      ELSE 0
    END AS suggested_qty,
    CASE
      WHEN a.earliest_need_date IS NOT NULL
      THEN (a.earliest_need_date - COALESCE(p.lead_time_days, 7))
      ELSE (CURRENT_DATE + COALESCE(p.lead_time_days, 7))
    END::date AS suggested_date,
    a.low_level_code,
    'mrp'::text AS source,
    a.earliest_need_date,
    CASE
      WHEN a.earliest_need_date IS NOT NULL
       AND (a.earliest_need_date - COALESCE(p.lead_time_days, 7)) < CURRENT_DATE
      THEN true
      ELSE false
    END AS is_late
  FROM aggregated_needs a
  JOIN products p ON p.id = a.product_id AND p.tenant_id = v_tid
  LEFT JOIN stock_info s ON s.product_id = a.product_id
  LEFT JOIN open_po po ON po.product_id = a.product_id
  LEFT JOIN open_mo mo ON mo.product_id = a.product_id
  WHERE a.total_gross_need > 0
  ORDER BY a.low_level_code, a.product_id;

  DROP TABLE IF EXISTS _mrp_needs;
END;
$$;
