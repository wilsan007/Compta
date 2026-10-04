-- ============================================================
-- 125_stock_advanced.sql
-- STK-07 : Unités de mesure et conversions
-- STK-08 : Frais accessoires d'achat (landed costs)
-- STK-09 : Réapprovisionnement et inventaire tournant
-- STK-10 : Comptes de stock par catégorie
-- STK-11 : Emplacements et logique d'entrepôt
-- STK-12 : Préparation de commande et expédition
-- STK-13 : Contrôle qualité
-- STK-14 : Transferts inter-entrepôts et variantes
-- ============================================================

-- ============================================================
-- STK-07 : Unités de mesure et conversions
-- ============================================================
CREATE TABLE IF NOT EXISTS uom_categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  name text NOT NULL,  -- poids, volume, longueur, unité, temps
  created_at timestamptz DEFAULT now()
);

ALTER TABLE uom_categories ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS uom_categories_tenant ON uom_categories;
CREATE POLICY uom_categories_tenant ON uom_categories
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

CREATE TABLE IF NOT EXISTS uoms (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  code text NOT NULL,           -- KG, G, T, L, ML, M, PIECE, HOUR
  name text NOT NULL,
  category_id uuid NOT NULL REFERENCES uom_categories(id) ON DELETE CASCADE,
  factor numeric NOT NULL DEFAULT 1,  -- Facteur par rapport à l'unité de référence
  is_base boolean DEFAULT false,      -- Unité de référence de la catégorie
  rounding numeric DEFAULT 0.01,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE uoms ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS uoms_tenant ON uoms;
CREATE POLICY uoms_tenant ON uoms
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

-- Ajouter les unités aux produits
ALTER TABLE products ADD COLUMN IF NOT EXISTS uom_id uuid REFERENCES uoms(id);
ALTER TABLE products ADD COLUMN IF NOT EXISTS purchase_uom_id uuid REFERENCES uoms(id);
ALTER TABLE products ADD COLUMN IF NOT EXISTS sale_uom_id uuid REFERENCES uoms(id);

-- Fonction de conversion
CREATE OR REPLACE FUNCTION convert_uom(
  p_quantity numeric,
  p_from_uom_id uuid,
  p_to_uom_id uuid
)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_from record;
  v_to record;
BEGIN
  SELECT * INTO v_from FROM uoms WHERE id = p_from_uom_id;
  SELECT * INTO v_to FROM uoms WHERE id = p_to_uom_id;

  IF NOT FOUND OR v_from IS NULL OR v_to IS NULL THEN
    RAISE EXCEPTION 'Unité introuvable';
  END IF;

  -- Interdire la conversion entre catégories différentes
  IF v_from.category_id != v_to.category_id THEN
    RAISE EXCEPTION 'Conversion impossible entre catégories différentes';
  END IF;

  -- Convertir via l'unité de référence
  RETURN ROUND(
    (p_quantity * v_from.factor / v_to.factor) / v_to.rounding
  ) * v_to.rounding;
END;
$$;

-- ============================================================
-- STK-08 : Frais accessoires d'achat (landed costs)
-- ============================================================
CREATE TABLE IF NOT EXISTS landed_costs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  invoice_number text,
  supplier_id uuid,
  total_amount numeric NOT NULL,
  distribution_method text NOT NULL DEFAULT 'value'
    CHECK (distribution_method IN ('value', 'quantity', 'weight', 'volume')),
  status text DEFAULT 'pending' CHECK (status IN ('pending', 'distributed', 'cancelled')),
  created_at timestamptz DEFAULT now()
);

ALTER TABLE landed_costs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS landed_costs_tenant ON landed_costs;
CREATE POLICY landed_costs_tenant ON landed_costs
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

CREATE TABLE IF NOT EXISTS landed_cost_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  landed_cost_id uuid NOT NULL REFERENCES landed_costs(id) ON DELETE CASCADE,
  receipt_id uuid,               -- Réception concernée
  product_id uuid,
  distributed_amount numeric NOT NULL,
  original_unit_cost numeric,
  new_unit_cost numeric,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE landed_cost_lines ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS landed_cost_lines_tenant ON landed_cost_lines;
CREATE POLICY landed_cost_lines_tenant ON landed_cost_lines
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

-- Fonction de répartition des frais accessoires
CREATE OR REPLACE FUNCTION distribute_landed_cost(
  p_landed_cost_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_lc record;
  v_total_base numeric := 0;
  v_line record;
  v_distributed numeric;
BEGIN
  SELECT * INTO v_lc FROM landed_costs WHERE id = p_landed_cost_id AND tenant_id = v_tid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Frais accessoire introuvable'; END IF;

  -- Calculer la base de répartition
  SELECT COALESCE(SUM(
    CASE v_lc.distribution_method
      WHEN 'value' THEN sm.unit_cost * sm.quantity
      WHEN 'quantity' THEN sm.quantity
      ELSE sm.unit_cost * sm.quantity
    END
  ), 0) INTO v_total_base
  FROM stock_movements sm
  WHERE sm.reference_type = 'receipt'
    AND sm.tenant_id = v_tid
    AND sm.movement_type = 'in';

  IF v_total_base = 0 THEN
    RAISE EXCEPTION 'Aucune réception à répartir';
  END IF;

  -- Répartir
  FOR v_line IN
    SELECT product_id, unit_cost, quantity
    FROM stock_movements
    WHERE reference_type = 'receipt' AND tenant_id = v_tid AND movement_type = 'in'
  LOOP
    v_distributed := v_lc.total_amount * (
      CASE v_lc.distribution_method
        WHEN 'value' THEN v_line.unit_cost * v_line.quantity
        WHEN 'quantity' THEN v_line.quantity
        ELSE v_line.unit_cost * v_line.quantity
      END / v_total_base
    );

    INSERT INTO landed_cost_lines (
      tenant_id, landed_cost_id, product_id,
      distributed_amount, original_unit_cost, new_unit_cost
    ) VALUES (
      v_tid, p_landed_cost_id, v_line.product_id,
      v_distributed, v_line.unit_cost,
      v_line.unit_cost + v_distributed / v_line.quantity
    );

    -- Ajuster le CUMP
    UPDATE stock_quantities
    SET unit_cost = unit_cost + v_distributed / v_line.quantity,
        updated_at = now()
    WHERE product_id = v_line.product_id AND tenant_id = v_tid;
  END LOOP;

  UPDATE landed_costs SET status = 'distributed' WHERE id = p_landed_cost_id;

  RETURN jsonb_build_object('success', true, 'landed_cost_id', p_landed_cost_id);
END;
$$;

-- ============================================================
-- STK-09 : Réapprovisionnement et inventaire tournant
-- ============================================================
CREATE TABLE IF NOT EXISTS reorder_rules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  product_id uuid NOT NULL,
  warehouse_id uuid,
  min_quantity numeric NOT NULL,
  max_quantity numeric NOT NULL,
  multiple_quantity numeric DEFAULT 1,
  lead_time_days int DEFAULT 0,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE reorder_rules ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS reorder_rules_tenant ON reorder_rules;
CREATE POLICY reorder_rules_tenant ON reorder_rules
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

-- Inventaire tournant (comptages cycliques)
CREATE TABLE IF NOT EXISTS stock_count_cycles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  product_id uuid NOT NULL,
  warehouse_id uuid,
  abc_class text DEFAULT 'C' CHECK (abc_class IN ('A', 'B', 'C')),
  frequency_days int NOT NULL DEFAULT 90,  -- A: 30, B: 90, C: 180
  last_count_date date,
  next_count_date date,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE stock_count_cycles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS stock_count_cycles_tenant ON stock_count_cycles;
CREATE POLICY stock_count_cycles_tenant ON stock_count_cycles
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

-- ============================================================
-- STK-10 : Comptes de stock par catégorie
-- ============================================================
ALTER TABLE product_categories ADD COLUMN IF NOT EXISTS stock_account_code text;
ALTER TABLE product_categories ADD COLUMN IF NOT EXISTS variation_account_code text;

-- Fonction de résolution du compte de stock
CREATE OR REPLACE FUNCTION resolve_stock_account(
  p_product_id uuid
)
RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT COALESCE(
    pc.stock_account_code,
    '310000'  -- Fallback par défaut
  )
  FROM products p
  LEFT JOIN product_categories pc ON pc.id = p.category_id AND pc.tenant_id = p.tenant_id
  WHERE p.id = p_product_id;
$$;

CREATE OR REPLACE FUNCTION resolve_variation_account(
  p_product_id uuid
)
RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT COALESCE(
    pc.variation_account_code,
    '603000'  -- Fallback par défaut
  )
  FROM products p
  LEFT JOIN product_categories pc ON pc.id = p.category_id AND pc.tenant_id = p.tenant_id
  WHERE p.id = p_product_id;
$$;

-- ============================================================
-- STK-11 : Emplacements et logique d'entrepôt
-- ============================================================
ALTER TABLE stock_movements ADD COLUMN IF NOT EXISTS location_id uuid;
ALTER TABLE stock_quantities ADD COLUMN IF NOT EXISTS location_id uuid;

-- Structurer les emplacements en arbre
ALTER TABLE warehouse_locations ADD COLUMN IF NOT EXISTS parent_id uuid REFERENCES warehouse_locations(id);
ALTER TABLE warehouse_locations ADD COLUMN IF NOT EXISTS location_type text DEFAULT 'storage'
  CHECK (location_type IN ('reception', 'storage', 'picking', 'shipping', 'scrap', 'quarantine'));
ALTER TABLE warehouse_locations ADD COLUMN IF NOT EXISTS max_weight numeric;
ALTER TABLE warehouse_locations ADD COLUMN IF NOT EXISTS max_volume numeric;
ALTER TABLE warehouse_locations ADD COLUMN IF NOT EXISTS max_pallets int;

-- ============================================================
-- STK-12 : Préparation de commande et expédition
-- ============================================================
ALTER TABLE pick_lists ADD COLUMN IF NOT EXISTS wave_id uuid;
ALTER TABLE pick_lists ADD COLUMN IF NOT EXISTS tour_id uuid;
ALTER TABLE pick_lists ADD COLUMN IF NOT EXISTS status text DEFAULT 'pending'
  CHECK (status IN ('pending', 'in_progress', 'completed', 'cancelled'));
ALTER TABLE pick_list_lines ADD COLUMN IF NOT EXISTS picked_quantity numeric DEFAULT 0;
ALTER TABLE pick_list_lines ADD COLUMN IF NOT EXISTS pick_order int;  -- Ordre de prélèvement

-- ============================================================
-- STK-13 : Contrôle qualité
-- ============================================================
CREATE TABLE IF NOT EXISTS quality_control_plans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  product_id uuid,               -- NULL = applique à tous
  category_id uuid,              -- NULL = applique à tous
  name text NOT NULL,
  is_active boolean DEFAULT true,
  sampling_method text DEFAULT 'systematic'
    CHECK (sampling_method IN ('systematic', 'rate', 'table')),
  sampling_rate numeric DEFAULT 100,  -- Pourcentage
  created_at timestamptz DEFAULT now()
);

ALTER TABLE quality_control_plans ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS quality_control_plans_tenant ON quality_control_plans;
CREATE POLICY quality_control_plans_tenant ON quality_control_plans
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

CREATE TABLE IF NOT EXISTS quality_control_points (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  plan_id uuid NOT NULL REFERENCES quality_control_plans(id) ON DELETE CASCADE,
  name text NOT NULL,
  check_type text NOT NULL CHECK (check_type IN ('measure', 'visual', 'binary')),
  tolerance_min numeric,
  tolerance_max numeric,
  unit text,
  is_mandatory boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE quality_control_points ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS quality_control_points_tenant ON quality_control_points;
CREATE POLICY quality_control_points_tenant ON quality_control_points
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

-- ============================================================
-- STK-14 : Transferts inter-entrepôts
-- ============================================================
CREATE TABLE IF NOT EXISTS stock_transfers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  transfer_number text NOT NULL,
  from_warehouse_id uuid NOT NULL,
  to_warehouse_id uuid NOT NULL,
  shipment_date date,
  expected_receipt_date date,
  actual_receipt_date date,
  status text DEFAULT 'pending' CHECK (status IN ('pending', 'in_transit', 'received', 'cancelled')),
  notes text,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE stock_transfers ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS stock_transfers_tenant ON stock_transfers;
CREATE POLICY stock_transfers_tenant ON stock_transfers
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

CREATE TABLE IF NOT EXISTS stock_transfer_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  transfer_id uuid NOT NULL REFERENCES stock_transfers(id) ON DELETE CASCADE,
  product_id uuid NOT NULL,
  quantity numeric NOT NULL,
  unit_cost numeric,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE stock_transfer_lines ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS stock_transfer_lines_tenant ON stock_transfer_lines;
CREATE POLICY stock_transfer_lines_tenant ON stock_transfer_lines
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

-- Vue du stock en transit
CREATE OR REPLACE VIEW v_stock_in_transit AS
SELECT
  st.tenant_id,
  st.id AS transfer_id,
  st.transfer_number,
  st.from_warehouse_id,
  st.to_warehouse_id,
  stl.product_id,
  p.name AS product_name,
  stl.quantity,
  stl.unit_cost,
  stl.quantity * stl.unit_cost AS total_value,
  st.status
FROM stock_transfers st
JOIN stock_transfer_lines stl ON stl.transfer_id = st.id AND stl.tenant_id = st.tenant_id
JOIN products p ON p.id = stl.product_id AND p.tenant_id = stl.tenant_id
WHERE st.status = 'in_transit';
