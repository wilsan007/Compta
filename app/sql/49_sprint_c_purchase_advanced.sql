-- Sprint C: Purchase Advanced — Purchase requests, Supplier price lists, Delivery schedules
-- Run in Supabase Dashboard > SQL Editor

-- ============ New table: purchase_requests ============
CREATE TABLE IF NOT EXISTS purchase_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  number text NOT NULL,
  requester text,
  department text,
  status text DEFAULT 'draft',
  priority text DEFAULT 'normal',
  expected_date date,
  notes text,
  approved_by text,
  approved_at timestamptz,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_pr_number ON purchase_requests(number);
ALTER TABLE purchase_requests ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_purchase_requests') THEN
    CREATE POLICY "allow_all_purchase_requests" ON purchase_requests FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;

-- ============ New table: purchase_request_lines ============
CREATE TABLE IF NOT EXISTS purchase_request_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  purchase_request_id uuid NOT NULL REFERENCES purchase_requests(id) ON DELETE CASCADE,
  product_id uuid REFERENCES products(id) ON DELETE SET NULL,
  description text NOT NULL,
  quantity numeric(15,2) NOT NULL DEFAULT 1,
  unit text,
  estimated_price numeric(15,2),
  preferred_supplier_id uuid REFERENCES suppliers(id) ON DELETE SET NULL,
  notes text,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_prl_request ON purchase_request_lines(purchase_request_id);
ALTER TABLE purchase_request_lines ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_purchase_request_lines') THEN
    CREATE POLICY "allow_all_purchase_request_lines" ON purchase_request_lines FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;

-- ============ New table: supplier_price_lists ============
CREATE TABLE IF NOT EXISTS supplier_price_lists (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  supplier_id uuid NOT NULL REFERENCES suppliers(id) ON DELETE CASCADE,
  name text NOT NULL,
  valid_from date NOT NULL DEFAULT CURRENT_DATE,
  valid_to date,
  currency_code text DEFAULT 'EUR',
  min_quantity numeric(15,2) DEFAULT 1,
  discount_percent numeric(5,2) DEFAULT 0,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_spl_supplier ON supplier_price_lists(supplier_id);
ALTER TABLE supplier_price_lists ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_supplier_price_lists') THEN
    CREATE POLICY "allow_all_supplier_price_lists" ON supplier_price_lists FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;

-- ============ New table: supplier_price_list_lines ============
CREATE TABLE IF NOT EXISTS supplier_price_list_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  price_list_id uuid NOT NULL REFERENCES supplier_price_lists(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  supplier_ref text,
  unit_price numeric(15,2) NOT NULL,
  min_quantity numeric(15,2) DEFAULT 1,
  discount_percent numeric(5,2) DEFAULT 0,
  lead_time_days integer,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_spll_pl ON supplier_price_list_lines(price_list_id);
CREATE INDEX IF NOT EXISTS idx_spll_product ON supplier_price_list_lines(product_id);
ALTER TABLE supplier_price_list_lines ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_supplier_price_list_lines') THEN
    CREATE POLICY "allow_all_supplier_price_list_lines" ON supplier_price_list_lines FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;

-- ============ New table: supplier_delivery_schedules ============
CREATE TABLE IF NOT EXISTS supplier_delivery_schedules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  supplier_id uuid NOT NULL REFERENCES suppliers(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  warehouse_id uuid REFERENCES warehouses(id) ON DELETE SET NULL,
  frequency text NOT NULL,
  monday_qty numeric(15,2) DEFAULT 0,
  tuesday_qty numeric(15,2) DEFAULT 0,
  wednesday_qty numeric(15,2) DEFAULT 0,
  thursday_qty numeric(15,2) DEFAULT 0,
  friday_qty numeric(15,2) DEFAULT 0,
  saturday_qty numeric(15,2) DEFAULT 0,
  sunday_qty numeric(15,2) DEFAULT 0,
  start_date date NOT NULL DEFAULT CURRENT_DATE,
  end_date date,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_sds_supplier ON supplier_delivery_schedules(supplier_id);
ALTER TABLE supplier_delivery_schedules ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_supplier_delivery_schedules') THEN
    CREATE POLICY "allow_all_supplier_delivery_schedules" ON supplier_delivery_schedules FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
