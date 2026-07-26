-- ============================================================
-- Sprint 3: Advanced Tax Engine (#11, #18, #20, #21)
-- ============================================================

-- ============================================================
-- #11: Grouped Taxes (children_tax_ids)
-- ============================================================
ALTER TABLE tax_rates ADD COLUMN IF NOT EXISTS amount_type text DEFAULT 'percent';
ALTER TABLE tax_rates ADD COLUMN IF NOT EXISTS type_tax_use text DEFAULT 'none';
ALTER TABLE tax_rates ADD COLUMN IF NOT EXISTS sequence integer DEFAULT 10;
ALTER TABLE tax_rates ADD COLUMN IF NOT EXISTS parent_tax_id uuid REFERENCES tax_rates(id);

CREATE TABLE IF NOT EXISTS tax_groups (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  name text NOT NULL,
  country_code text,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_tax_groups_tenant ON tax_groups(tenant_id);

ALTER TABLE tax_groups ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY tax_groups_select ON tax_groups FOR SELECT USING (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE POLICY tax_groups_all ON tax_groups FOR ALL USING (true) WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ============================================================
-- #18: Tax Repartition Lines
-- ============================================================
CREATE TABLE IF NOT EXISTS tax_repartition_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  tax_id uuid NOT NULL REFERENCES tax_rates(id) ON DELETE CASCADE,
  document_type text NOT NULL,
  repartition_type text NOT NULL,
  factor numeric(5,2) DEFAULT 100,
  account_code text,
  tag_ids text[],
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_tax_repartition_tax ON tax_repartition_lines(tax_id);

ALTER TABLE tax_repartition_lines ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY tax_repartition_select ON tax_repartition_lines FOR SELECT USING (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE POLICY tax_repartition_all ON tax_repartition_lines FOR ALL USING (true) WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ============================================================
-- #20: Cash Basis VAT (TVA sur encaissement)
-- ============================================================
ALTER TABLE tax_rates ADD COLUMN IF NOT EXISTS tax_exigibility text DEFAULT 'on_invoice';
ALTER TABLE tax_rates ADD COLUMN IF NOT EXISTS cash_basis_transition_account text;

CREATE TABLE IF NOT EXISTS tax_cash_basis_entries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  tax_id uuid REFERENCES tax_rates(id),
  payment_id uuid,
  journal_entry_id uuid,
  base_amount numeric(14,2),
  tax_amount numeric(14,2),
  transition_date date,
  status text DEFAULT 'pending',
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_tax_cash_basis_tax ON tax_cash_basis_entries(tax_id);
CREATE INDEX IF NOT EXISTS idx_tax_cash_basis_payment ON tax_cash_basis_entries(payment_id);

ALTER TABLE tax_cash_basis_entries ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY tax_cash_basis_select ON tax_cash_basis_entries FOR SELECT USING (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE POLICY tax_cash_basis_all ON tax_cash_basis_entries FOR ALL USING (true) WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ============================================================
-- #21: Flat-rate and Division Taxes
-- ============================================================
ALTER TABLE tax_rates ADD COLUMN IF NOT EXISTS price_include boolean DEFAULT false;
ALTER TABLE tax_rates ADD COLUMN IF NOT EXISTS include_base_amount boolean DEFAULT false;
ALTER TABLE tax_rates ADD COLUMN IF NOT EXISTS is_base_affected boolean DEFAULT true;
ALTER TABLE tax_rates ADD COLUMN IF NOT EXISTS analytic boolean DEFAULT false;
ALTER TABLE tax_rates ADD COLUMN IF NOT EXISTS fixed_amount numeric(14,2);
