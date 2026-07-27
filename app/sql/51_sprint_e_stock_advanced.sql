-- ============================================================
-- Sprint E: Stock avancé
-- File: 51_sprint_e_stock_advanced.sql
-- ============================================================

-- ============ Extensions to existing tables ============

-- Extend stock_quantities
ALTER TABLE stock_quantities ADD COLUMN IF NOT EXISTS reserved_quantity numeric(15,2) DEFAULT 0;
ALTER TABLE stock_quantities ADD COLUMN IF NOT EXISTS incoming_quantity numeric(15,2) DEFAULT 0;

-- ============ New tables ============

-- Warehouse users (affectation utilisateurs par dépôt)
CREATE TABLE IF NOT EXISTS warehouse_users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  warehouse_id uuid NOT NULL REFERENCES warehouses(id) ON DELETE CASCADE,
  user_email text NOT NULL,
  role text DEFAULT 'operator',    -- 'manager'|'operator'|'viewer'
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_wu_warehouse ON warehouse_users(warehouse_id);
CREATE INDEX IF NOT EXISTS idx_wu_user ON warehouse_users(user_email);
ALTER TABLE warehouse_users ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_warehouse_users') THEN
    CREATE POLICY "allow_all_warehouse_users" ON warehouse_users FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;

-- Stock alerts (alertes de seuil)
CREATE TABLE IF NOT EXISTS stock_alerts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  warehouse_id uuid REFERENCES warehouses(id) ON DELETE SET NULL,
  alert_type text NOT NULL,        -- 'low_stock'|'out_of_stock'|'overstock'|'expiry'
  threshold numeric(15,2),
  current_value numeric(15,2),
  status text DEFAULT 'active',    -- 'active'|'acknowledged'|'resolved'
  triggered_at timestamptz DEFAULT now(),
  resolved_at timestamptz,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_sa_product ON stock_alerts(product_id);
CREATE INDEX IF NOT EXISTS idx_sa_status ON stock_alerts(status);
ALTER TABLE stock_alerts ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_stock_alerts') THEN
    CREATE POLICY "allow_all_stock_alerts" ON stock_alerts FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
