-- Sprint B: Customer Advanced — Customer 360°, Multi-contacts, Credit control, Email settings
-- Run in Supabase Dashboard > SQL Editor

-- ============ New table: customer_contacts ============
CREATE TABLE IF NOT EXISTS customer_contacts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  customer_id uuid NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  name text NOT NULL,
  role text,
  email text,
  phone text,
  mobile text,
  is_default boolean DEFAULT false,
  active boolean DEFAULT true,
  notes text,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_cc_customer ON customer_contacts(customer_id);
ALTER TABLE customer_contacts ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_customer_contacts') THEN
    CREATE POLICY "allow_all_customer_contacts" ON customer_contacts FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;

-- ============ New table: supplier_contacts ============
CREATE TABLE IF NOT EXISTS supplier_contacts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  supplier_id uuid NOT NULL REFERENCES suppliers(id) ON DELETE CASCADE,
  name text NOT NULL,
  role text,
  email text,
  phone text,
  mobile text,
  is_default boolean DEFAULT false,
  active boolean DEFAULT true,
  notes text,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_sc_supplier ON supplier_contacts(supplier_id);
ALTER TABLE supplier_contacts ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_supplier_contacts') THEN
    CREATE POLICY "allow_all_supplier_contacts" ON supplier_contacts FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;

-- ============ Extensions: customers ============
ALTER TABLE customers ADD COLUMN IF NOT EXISTS bank_account_id uuid;
ALTER TABLE customers ADD COLUMN IF NOT EXISTS price_list_id uuid;
ALTER TABLE customers ADD COLUMN IF NOT EXISTS sales_rep_id uuid;
ALTER TABLE customers ADD COLUMN IF NOT EXISTS email_settings jsonb DEFAULT '{}'::jsonb;
ALTER TABLE customers ADD COLUMN IF NOT EXISTS credit_limit numeric(15,2) DEFAULT 0;
ALTER TABLE customers ADD COLUMN IF NOT EXISTS credit_used numeric(15,2) DEFAULT 0;
ALTER TABLE customers ADD COLUMN IF NOT EXISTS credit_blocked boolean DEFAULT false;

-- ============ Extensions: suppliers ============
ALTER TABLE suppliers ADD COLUMN IF NOT EXISTS bank_account_id uuid;
ALTER TABLE suppliers ADD COLUMN IF NOT EXISTS price_list_id uuid;
ALTER TABLE suppliers ADD COLUMN IF NOT EXISTS email_settings jsonb DEFAULT '{}'::jsonb;
