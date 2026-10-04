-- ============================================================
-- Sprint 6: Tiers + Immobilisation
-- Elements: #62 (Multi-contacts), #63 (Hierarchy parent_id + is_company),
--           #64 (Partner categories), #65 (Commercial assigné),
--           #90, #91, #92 (Comptes liés immobilisation),
--           #93 (Journal lié immobilisation)
-- ============================================================

-- ============================================================
-- #62: Partner Contacts (adresses livraison/facturation)
-- ============================================================
CREATE TABLE IF NOT EXISTS partner_contacts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  partner_type text NOT NULL,
  partner_id uuid NOT NULL,
  contact_type text NOT NULL,
  name text NOT NULL,
  email text,
  phone text,
  mobile text,
  function text,
  address text,
  postal_code text,
  city text,
  country text,
  is_default boolean DEFAULT false,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_partner_contacts_partner ON partner_contacts(partner_type, partner_id);

ALTER TABLE partner_contacts ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_partner_contacts') THEN
    DROP POLICY IF EXISTS "allow_all_partner_contacts" ON partner_contacts;
    CREATE POLICY "allow_all_partner_contacts" ON partner_contacts FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- ============================================================
-- #63: Hierarchy — parent_id + is_company on customers/suppliers
-- ============================================================
ALTER TABLE customers ADD COLUMN IF NOT EXISTS parent_id uuid;
ALTER TABLE customers ADD COLUMN IF NOT EXISTS is_company boolean DEFAULT true;

ALTER TABLE suppliers ADD COLUMN IF NOT EXISTS parent_id uuid;
ALTER TABLE suppliers ADD COLUMN IF NOT EXISTS is_company boolean DEFAULT true;

-- ============================================================
-- #64: Partner Categories + Mappings
-- ============================================================
CREATE TABLE IF NOT EXISTS partner_categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  name text NOT NULL,
  color text,
  parent_id uuid,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE partner_categories ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_partner_categories') THEN
    DROP POLICY IF EXISTS "allow_all_partner_categories" ON partner_categories;
    CREATE POLICY "allow_all_partner_categories" ON partner_categories FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS partner_category_mappings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  category_id uuid NOT NULL REFERENCES partner_categories(id) ON DELETE CASCADE,
  partner_type text NOT NULL,
  partner_id uuid NOT NULL,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_partner_cat_mapping ON partner_category_mappings(partner_type, partner_id);
CREATE INDEX IF NOT EXISTS idx_partner_cat_mapping_cat ON partner_category_mappings(category_id);

ALTER TABLE partner_category_mappings ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_partner_cat_mappings') THEN
    DROP POLICY IF EXISTS "allow_all_partner_cat_mappings" ON partner_category_mappings;
    CREATE POLICY "allow_all_partner_cat_mappings" ON partner_category_mappings FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- ============================================================
-- #65: Commercial Assigné (sales_rep_id on customers/suppliers)
-- ============================================================
ALTER TABLE customers ADD COLUMN IF NOT EXISTS sales_rep_id uuid;
ALTER TABLE suppliers ADD COLUMN IF NOT EXISTS sales_rep_id uuid;

-- ============================================================
-- #80: Partner Bank Accounts (res.partner.bank)
-- ============================================================
CREATE TABLE IF NOT EXISTS partner_bank_accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  partner_type text NOT NULL,
  partner_id uuid NOT NULL,
  account_number text NOT NULL,
  bank_name text,
  bic text,
  bank_code text,
  sort_code text,
  account_key text,
  currency_code text DEFAULT 'EUR',
  is_default boolean DEFAULT false,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_partner_bank_accounts ON partner_bank_accounts(partner_type, partner_id);

ALTER TABLE partner_bank_accounts ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_partner_bank_accounts') THEN
    DROP POLICY IF EXISTS "allow_all_partner_bank_accounts" ON partner_bank_accounts;
    CREATE POLICY "allow_all_partner_bank_accounts" ON partner_bank_accounts FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- ============================================================
-- #90, #91, #92, #93: Comptes liés immobilisation + Journal
-- ============================================================
ALTER TABLE fixed_assets ADD COLUMN IF NOT EXISTS account_asset_code text;
ALTER TABLE fixed_assets ADD COLUMN IF NOT EXISTS account_depreciation_code text;
ALTER TABLE fixed_assets ADD COLUMN IF NOT EXISTS account_expense_depreciation_code text;
ALTER TABLE fixed_assets ADD COLUMN IF NOT EXISTS journal_id uuid;
ALTER TABLE fixed_assets ADD COLUMN IF NOT EXISTS partner_id uuid;
ALTER TABLE fixed_assets ADD COLUMN IF NOT EXISTS currency_code text DEFAULT 'EUR';
