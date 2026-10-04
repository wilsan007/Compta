-- ============================================================
-- Sprint 4: Position Fiscale + Tags Fiscaux
-- Elements: #32 (Position Fiscale), #56 (Mapping Fiscal), #66 (Application Auto), #22 (Tags Fiscaux)
-- ============================================================

-- ============================================================
-- #32: Fiscal Positions
-- ============================================================
CREATE TABLE IF NOT EXISTS fiscal_positions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  name text NOT NULL,
  country_code text,
  country_group_id text,
  zip_from text,
  zip_to text,
  auto_apply boolean DEFAULT false,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_fiscal_positions_tenant ON fiscal_positions(tenant_id);
CREATE INDEX IF NOT EXISTS idx_fiscal_positions_country ON fiscal_positions(country_code);

ALTER TABLE fiscal_positions ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  DROP POLICY IF EXISTS tenant_select_fiscal_positions ON fiscal_positions;
  CREATE POLICY tenant_select_fiscal_positions ON fiscal_positions
    FOR SELECT USING (tenant_id = current_tenant_id() OR tenant_id IS NULL);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  DROP POLICY IF EXISTS tenant_insert_fiscal_positions ON fiscal_positions;
  CREATE POLICY tenant_insert_fiscal_positions ON fiscal_positions
    FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  DROP POLICY IF EXISTS tenant_update_fiscal_positions ON fiscal_positions;
  CREATE POLICY tenant_update_fiscal_positions ON fiscal_positions
    FOR UPDATE USING (tenant_id = current_tenant_id()) WITH CHECK (tenant_id = current_tenant_id());
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  DROP POLICY IF EXISTS tenant_delete_fiscal_positions ON fiscal_positions;
  CREATE POLICY tenant_delete_fiscal_positions ON fiscal_positions
    FOR DELETE USING (tenant_id = current_tenant_id());
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ============================================================
-- #56: Fiscal Position Mappings
-- ============================================================
CREATE TABLE IF NOT EXISTS fiscal_position_mappings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  fiscal_position_id uuid NOT NULL REFERENCES fiscal_positions(id) ON DELETE CASCADE,
  source_tax_id uuid REFERENCES tax_rates(id),
  target_tax_id uuid REFERENCES tax_rates(id),
  source_account_code text,
  target_account_code text,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_fiscal_mapping_position ON fiscal_position_mappings(fiscal_position_id);
CREATE INDEX IF NOT EXISTS idx_fiscal_mapping_tenant ON fiscal_position_mappings(tenant_id);

ALTER TABLE fiscal_position_mappings ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  DROP POLICY IF EXISTS tenant_select_fiscal_position_mappings ON fiscal_position_mappings;
  CREATE POLICY tenant_select_fiscal_position_mappings ON fiscal_position_mappings
    FOR SELECT USING (tenant_id = current_tenant_id() OR tenant_id IS NULL);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  DROP POLICY IF EXISTS tenant_insert_fiscal_position_mappings ON fiscal_position_mappings;
  CREATE POLICY tenant_insert_fiscal_position_mappings ON fiscal_position_mappings
    FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  DROP POLICY IF EXISTS tenant_update_fiscal_position_mappings ON fiscal_position_mappings;
  CREATE POLICY tenant_update_fiscal_position_mappings ON fiscal_position_mappings
    FOR UPDATE USING (tenant_id = current_tenant_id()) WITH CHECK (tenant_id = current_tenant_id());
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  DROP POLICY IF EXISTS tenant_delete_fiscal_position_mappings ON fiscal_position_mappings;
  CREATE POLICY tenant_delete_fiscal_position_mappings ON fiscal_position_mappings
    FOR DELETE USING (tenant_id = current_tenant_id());
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ============================================================
-- #66: Application Automatique sur Factures
-- ============================================================
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS fiscal_position_id uuid REFERENCES fiscal_positions(id);
ALTER TABLE purchase_invoices ADD COLUMN IF NOT EXISTS fiscal_position_id uuid REFERENCES fiscal_positions(id);

-- ============================================================
-- #22: Account Tags
-- ============================================================
CREATE TABLE IF NOT EXISTS account_tags (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  name text NOT NULL,
  applicability text NOT NULL DEFAULT 'accounts',
  color text,
  country_code text,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_account_tags_tenant ON account_tags(tenant_id);
CREATE INDEX IF NOT EXISTS idx_account_tags_applicability ON account_tags(applicability);

ALTER TABLE account_tags ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  DROP POLICY IF EXISTS tenant_select_account_tags ON account_tags;
  CREATE POLICY tenant_select_account_tags ON account_tags
    FOR SELECT USING (tenant_id = current_tenant_id() OR tenant_id IS NULL);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  DROP POLICY IF EXISTS tenant_insert_account_tags ON account_tags;
  CREATE POLICY tenant_insert_account_tags ON account_tags
    FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  DROP POLICY IF EXISTS tenant_update_account_tags ON account_tags;
  CREATE POLICY tenant_update_account_tags ON account_tags
    FOR UPDATE USING (tenant_id = current_tenant_id()) WITH CHECK (tenant_id = current_tenant_id());
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  DROP POLICY IF EXISTS tenant_delete_account_tags ON account_tags;
  CREATE POLICY tenant_delete_account_tags ON account_tags
    FOR DELETE USING (tenant_id = current_tenant_id());
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ============================================================
-- #22: Account Tag Mappings (many2many)
-- ============================================================
CREATE TABLE IF NOT EXISTS account_tag_mappings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  tag_id uuid NOT NULL REFERENCES account_tags(id) ON DELETE CASCADE,
  entity_type text NOT NULL,
  entity_id text NOT NULL,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_account_tag_mappings_tag ON account_tag_mappings(tag_id);
CREATE INDEX IF NOT EXISTS idx_account_tag_mappings_entity ON account_tag_mappings(entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_account_tag_mappings_tenant ON account_tag_mappings(tenant_id);

ALTER TABLE account_tag_mappings ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  DROP POLICY IF EXISTS tenant_select_account_tag_mappings ON account_tag_mappings;
  CREATE POLICY tenant_select_account_tag_mappings ON account_tag_mappings
    FOR SELECT USING (tenant_id = current_tenant_id() OR tenant_id IS NULL);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  DROP POLICY IF EXISTS tenant_insert_account_tag_mappings ON account_tag_mappings;
  CREATE POLICY tenant_insert_account_tag_mappings ON account_tag_mappings
    FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  DROP POLICY IF EXISTS tenant_update_account_tag_mappings ON account_tag_mappings;
  CREATE POLICY tenant_update_account_tag_mappings ON account_tag_mappings
    FOR UPDATE USING (tenant_id = current_tenant_id()) WITH CHECK (tenant_id = current_tenant_id());
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  DROP POLICY IF EXISTS tenant_delete_account_tag_mappings ON account_tag_mappings;
  CREATE POLICY tenant_delete_account_tag_mappings ON account_tag_mappings
    FOR DELETE USING (tenant_id = current_tenant_id());
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ============================================================
-- #39: Tax tag IDs on journal lines (already in plan Cluster 11)
-- ============================================================
ALTER TABLE journal_lines ADD COLUMN IF NOT EXISTS tax_tag_ids text[] DEFAULT '{}';

-- Done
