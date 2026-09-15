-- ============================================================
-- 115_mrp_recursive.sql
-- PRD-02 + PRD-03 + PRD-04 : MRP récursif, sources du besoin, délais
-- ============================================================

-- ============================================================
-- PRD-04 : Colonnes de réapprovisionnement sur products
-- ============================================================
ALTER TABLE products ADD COLUMN IF NOT EXISTS safety_stock numeric DEFAULT 0;
ALTER TABLE products ADD COLUMN IF NOT EXISTS lead_time_days int DEFAULT 7;
ALTER TABLE products ADD COLUMN IF NOT EXISTS min_order_qty numeric DEFAULT 0;
ALTER TABLE products ADD COLUMN IF NOT EXISTS qty_multiple numeric DEFAULT 1;
ALTER TABLE products ADD COLUMN IF NOT EXISTS scrap_rate numeric DEFAULT 0;
ALTER TABLE bom_lines ADD COLUMN IF NOT EXISTS scrap_rate numeric DEFAULT 0;

-- ============================================================
-- PRD-02 : Fonction d'éclatement récursif des nomenclatures
-- ============================================================
CREATE OR REPLACE FUNCTION explode_bom_recursive(
  p_tenant_id uuid,
  p_bom_id uuid,
  p_quantity numeric,
  p_max_level int DEFAULT 15
)
RETURNS TABLE(
  product_id uuid,
  gross_need numeric,
  low_level_code int
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  WITH RECURSIVE explosion AS (
    -- Niveau 0 : les composants directs de la nomenclature
    SELECT
      bl.product_id,
      bl.quantity * p_quantity * (1 + COALESCE(bl.scrap_rate, 0)) AS qty,
      0 AS level
    FROM bom_lines bl
    WHERE bl.bom_id = p_bom_id AND bl.tenant_id = p_tenant_id

    UNION ALL

    -- Niveau n+1 : éclater les composants qui ont eux-mêmes une nomenclature
    SELECT
      bl.product_id,
      e.qty * (bl.quantity / COALESCE(NULLIF(b.quantity, 0), 1)) * (1 + COALESCE(bl.scrap_rate, 0)),
      e.level + 1
    FROM explosion e
    JOIN boms b ON b.product_id = e.product_id AND b.tenant_id = p_tenant_id AND b.active = true
    JOIN bom_lines bl ON bl.bom_id = b.id AND bl.tenant_id = p_tenant_id
    WHERE e.level < p_max_level
  )
  SELECT explosion.product_id, sum(explosion.qty) AS gross_need, max(explosion.level) AS low_level_code
  FROM explosion
  GROUP BY explosion.product_id
  ORDER BY low_level_code;
$$;

-- ============================================================
-- PRD-02 + PRD-03 : Fonction MRP complète
--   Sources : OF planifiés + commandes clients + prévisions
--   Éclatement récursif des nomenclatures
--   Déduction : stock + commandes en cours + OF en cours
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
  -- 1. Besoins bruts : éclatement récursif des OF planifiés
  CREATE TEMP TABLE IF NOT EXISTS _mrp_needs AS
  SELECT
    exp.product_id,
    exp.gross_need,
    exp.low_level_code,
    mo.start_date AS need_date,
    'manufacturing_order' AS source
  FROM manufacturing_orders mo
  CROSS JOIN LATERAL explode_bom_recursive(v_tid, mo.bom_id, mo.quantity) exp
  WHERE mo.tenant_id = v_tid AND mo.status IN ('planned', 'in_progress');

  -- 2. Ajouter les besoins des commandes clients confirmées non livrées
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

  -- 3. Ajouter les prévisions de production
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

  -- 4. Agréger les besoins par produit
  -- et calculer le besoin net = besoin brut + stock de sécurité - stock - commandes en cours
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
  open_po AS (
    SELECT
      pol.product_id,
      SUM(pol.quantity - COALESCE(pol.quantity_received, 0)) AS open_qty
    FROM purchase_order_lines pol
    JOIN purchase_orders po ON po.id = pol.purchase_order_id AND po.tenant_id = pol.tenant_id
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
    -- PRD-04 : besoin net = besoin brut + stock de sécurité - stock - commandes en cours
    GREATEST(0, a.total_gross_need + COALESCE(p.safety_stock, 0) - COALESCE(s.stock_qty, 0) - COALESCE(po.open_qty, 0) - COALESCE(mo.open_qty, 0)) AS net_need,
    -- PRD-04 : arrondi au multiple de conditionnement, plancher au minimum de commande
    CASE
      WHEN GREATEST(0, a.total_gross_need + COALESCE(p.safety_stock, 0) - COALESCE(s.stock_qty, 0) - COALESCE(po.open_qty, 0) - COALESCE(mo.open_qty, 0)) > 0
      THEN GREATEST(
        CEIL(GREATEST(0, a.total_gross_need + COALESCE(p.safety_stock, 0) - COALESCE(s.stock_qty, 0) - COALESCE(po.open_qty, 0) - COALESCE(mo.open_qty, 0)) / COALESCE(p.qty_multiple, 1)) * COALESCE(p.qty_multiple, 1),
        COALESCE(p.min_order_qty, 0)
      )
      ELSE 0
    END AS suggested_qty,
    -- PRD-04 : jalonnement amont : reculer depuis la date de besoin
    CASE
      WHEN a.earliest_need_date IS NOT NULL
      THEN (a.earliest_need_date - COALESCE(p.lead_time_days, 7))
      ELSE (CURRENT_DATE + COALESCE(p.lead_time_days, 7))
    END::date AS suggested_date,
    a.low_level_code,
    'mrp'::text AS source,
    a.earliest_need_date,
    -- PRD-04 : signaler les propositions en retard
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
