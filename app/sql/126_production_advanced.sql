-- ============================================================
-- 126_production_advanced.sql
-- PRD-06 : Déclaration de production et rebuts
-- PRD-07 : Capacité finie et ordonnancement
-- PRD-10 : Workflows et équivalences
-- PRD-11 : Maintenance des machines et des outillages
-- ============================================================

-- ============================================================
-- PRD-06 : Déclaration de production (consommations et opérations réelles)
-- ============================================================
CREATE TABLE IF NOT EXISTS mo_consumptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  manufacturing_order_id uuid NOT NULL REFERENCES manufacturing_orders(id) ON DELETE CASCADE,
  product_id uuid NOT NULL,
  theoretical_quantity numeric NOT NULL,
  actual_quantity numeric DEFAULT 0,
  lot_id uuid,
  variance_quantity numeric GENERATED ALWAYS AS (actual_quantity - theoretical_quantity) STORED,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE mo_consumptions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS mo_consumptions_tenant ON mo_consumptions;
CREATE POLICY mo_consumptions_tenant ON mo_consumptions
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

CREATE TABLE IF NOT EXISTS mo_operations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  manufacturing_order_id uuid NOT NULL REFERENCES manufacturing_orders(id) ON DELETE CASCADE,
  operation_id uuid,
  operation_name text,
  planned_time_minutes int,
  actual_time_minutes int DEFAULT 0,
  operator_id uuid,
  quantity_produced numeric DEFAULT 0,
  quantity_scrapped numeric DEFAULT 0,
  scrap_reason text,
  started_at timestamptz,
  completed_at timestamptz,
  status text DEFAULT 'pending' CHECK (status IN ('pending', 'in_progress', 'completed', 'cancelled')),
  created_at timestamptz DEFAULT now()
);

ALTER TABLE mo_operations ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS mo_operations_tenant ON mo_operations;
CREATE POLICY mo_operations_tenant ON mo_operations
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

-- Vue des écarts de production
CREATE OR REPLACE VIEW v_production_variances AS
SELECT
  mo.tenant_id,
  mo.id AS manufacturing_order_id,
  mo.number AS mo_number,
  moc.product_id,
  p.name AS product_name,
  moc.theoretical_quantity,
  moc.actual_quantity,
  moc.variance_quantity,
  (moc.variance_quantity * COALESCE(sq.unit_cost, 0)) AS material_quantity_variance,
  moop.operation_name,
  moop.planned_time_minutes,
  moop.actual_time_minutes,
  (moop.actual_time_minutes - moop.planned_time_minutes) AS time_variance,
  moop.quantity_produced,
  moop.quantity_scrapped,
  (moop.quantity_scrapped * COALESCE(sq.unit_cost, 0)) AS scrap_value
FROM manufacturing_orders mo
LEFT JOIN mo_consumptions moc ON moc.manufacturing_order_id = mo.id AND moc.tenant_id = mo.tenant_id
LEFT JOIN mo_operations moop ON moop.manufacturing_order_id = mo.id AND moop.tenant_id = mo.tenant_id
LEFT JOIN products p ON p.id = moc.product_id AND p.tenant_id = moc.tenant_id
LEFT JOIN stock_quantities sq ON sq.product_id = moc.product_id AND sq.tenant_id = moc.tenant_id
WHERE mo.tenant_id = current_tenant_id();

-- ============================================================
-- PRD-07 : Capacité finie et ordonnancement
-- ============================================================
CREATE TABLE IF NOT EXISTS work_center_calendars (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  work_center_id uuid NOT NULL,
  date date NOT NULL,
  available_hours numeric DEFAULT 0,
  is_holiday boolean DEFAULT false,
  is_closed boolean DEFAULT false,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE work_center_calendars ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS work_center_calendars_tenant ON work_center_calendars;
CREATE POLICY work_center_calendars_tenant ON work_center_calendars
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

-- Vue charge/capacité par poste et par jour
CREATE OR REPLACE VIEW v_work_center_load AS
SELECT
  mo.tenant_id,
  ro.work_center_id,
  wc.name AS work_center_name,
  mo.start_date::date AS load_date,
  SUM(ro.setup_time_min + ro.run_time_min) / 60.0 AS load_hours,
  wc.capacity_hours_per_day AS capacity_hours,
  wc.capacity_hours_per_day - SUM(ro.setup_time_min + ro.run_time_min) / 60.0 AS available_hours,
  CASE
    WHEN SUM(ro.setup_time_min + ro.run_time_min) / 60.0 > wc.capacity_hours_per_day THEN 'overloaded'
    WHEN SUM(ro.setup_time_min + ro.run_time_min) / 60.0 > wc.capacity_hours_per_day * 0.8 THEN 'high'
    ELSE 'normal'
  END AS load_level
FROM manufacturing_orders mo
JOIN routing_operations ro ON ro.routing_id = mo.routing_id AND ro.tenant_id = mo.tenant_id
JOIN work_centers wc ON wc.id = ro.work_center_id AND wc.tenant_id = mo.tenant_id
WHERE mo.tenant_id = current_tenant_id()
  AND mo.status IN ('planned', 'in_progress')
GROUP BY mo.tenant_id, ro.work_center_id, wc.name, wc.capacity_hours_per_day, mo.start_date::date;

-- ============================================================
-- PRD-10 : Équivalences exploitables dans le MRP
-- ============================================================
CREATE OR REPLACE FUNCTION find_equivalent_product(
  p_product_id uuid
)
RETURNS TABLE(
  equivalent_product_id uuid,
  equivalent_name text,
  cost_difference numeric
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT
    pe.equivalent_product_id,
    p.name,
    COALESCE(sq2.unit_cost, 0) - COALESCE(sq1.unit_cost, 0)
  FROM product_equivalences pe
  JOIN products p ON p.id = pe.equivalent_product_id AND p.tenant_id = pe.tenant_id
  LEFT JOIN stock_quantities sq1 ON sq1.product_id = pe.product_id AND sq1.tenant_id = pe.tenant_id
  LEFT JOIN stock_quantities sq2 ON sq2.product_id = pe.equivalent_product_id AND sq2.tenant_id = pe.tenant_id
  WHERE pe.product_id = p_product_id
    AND pe.tenant_id = current_tenant_id();
$$;

-- ============================================================
-- PRD-11 : Maintenance des machines et des outillages
-- ============================================================
CREATE TABLE IF NOT EXISTS maintenance_plans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  machine_id uuid,
  tool_id uuid,
  name text NOT NULL,
  maintenance_type text NOT NULL CHECK (maintenance_type IN ('preventive', 'corrective', 'predictive')),
  frequency_days int,
  last_maintenance_date date,
  next_maintenance_date date,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE maintenance_plans ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS maintenance_plans_tenant ON maintenance_plans;
CREATE POLICY maintenance_plans_tenant ON maintenance_plans
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

CREATE TABLE IF NOT EXISTS maintenance_records (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  plan_id uuid REFERENCES maintenance_plans(id) ON DELETE SET NULL,
  machine_id uuid,
  tool_id uuid,
  maintenance_date date NOT NULL,
  duration_hours numeric,
  cost numeric DEFAULT 0,
  technician text,
  notes text,
  status text DEFAULT 'completed' CHECK (status IN ('planned', 'in_progress', 'completed', 'cancelled')),
  created_at timestamptz DEFAULT now()
);

ALTER TABLE maintenance_records ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS maintenance_records_tenant ON maintenance_records;
CREATE POLICY maintenance_records_tenant ON maintenance_records
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

-- Vue des maintenances à venir
CREATE OR REPLACE VIEW v_maintenance_due AS
SELECT
  mp.tenant_id,
  mp.id AS plan_id,
  mp.name,
  mp.maintenance_type,
  mp.frequency_days,
  mp.last_maintenance_date,
  mp.next_maintenance_date,
  CURRENT_DATE - mp.next_maintenance_date AS days_overdue,
  CASE
    WHEN mp.next_maintenance_date < CURRENT_DATE THEN 'overdue'
    WHEN mp.next_maintenance_date <= CURRENT_DATE + 7 THEN 'due_soon'
    ELSE 'scheduled'
  END AS status,
  m.name AS machine_name,
  t.name AS tool_name
FROM maintenance_plans mp
LEFT JOIN machines m ON m.id = mp.machine_id AND m.tenant_id = mp.tenant_id
LEFT JOIN toolings t ON t.id = mp.tool_id AND t.tenant_id = mp.tenant_id
WHERE mp.tenant_id = current_tenant_id()
  AND mp.is_active = true;
