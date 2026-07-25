-- ============================================
-- BANK STATEMENT TEMPLATES
-- Stores learned PDF parsing templates per bank
-- First upload uses AI to learn the format,
-- subsequent uploads reuse the saved template
-- ============================================

CREATE TABLE IF NOT EXISTS bank_statement_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  bank_name text NOT NULL,
  account_number_pattern text,
  date_pattern text NOT NULL,
  amount_pattern text NOT NULL,
  description_pattern text,
  reference_pattern text,
  debit_indicator text,
  credit_indicator text,
  period_pattern text,
  balance_pattern text,
  currency_pattern text,
  skip_lines_pattern text,
  sample_text text,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_bank_stmt_templates_tenant
  ON bank_statement_templates(tenant_id);
CREATE INDEX IF NOT EXISTS idx_bank_stmt_templates_bank
  ON bank_statement_templates(tenant_id, bank_name);

ALTER TABLE bank_statement_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE bank_statement_templates FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS bank_stmt_templates_tenant_isolation ON bank_statement_templates;
DROP POLICY IF EXISTS tenant_select_bank_statement_templates ON bank_statement_templates;
DROP POLICY IF EXISTS tenant_insert_bank_statement_templates ON bank_statement_templates;
DROP POLICY IF EXISTS tenant_update_bank_statement_templates ON bank_statement_templates;
DROP POLICY IF EXISTS tenant_delete_bank_statement_templates ON bank_statement_templates;

-- SECURITY: Use current_tenant_id() not auth.uid() — auth.uid() returns the Supabase auth user ID, not the tenant_id
DO $$ BEGIN
  CREATE POLICY tenant_select_bank_statement_templates ON bank_statement_templates
    FOR SELECT USING (tenant_id = current_tenant_id() OR tenant_id IS NULL);
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'select policy: %', SQLERRM; END $$;
DO $$ BEGIN
  CREATE POLICY tenant_insert_bank_statement_templates ON bank_statement_templates
    FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'insert policy: %', SQLERRM; END $$;
DO $$ BEGIN
  CREATE POLICY tenant_update_bank_statement_templates ON bank_statement_templates
    FOR UPDATE USING (tenant_id = current_tenant_id())
    WITH CHECK (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'update policy: %', SQLERRM; END $$;
DO $$ BEGIN
  CREATE POLICY tenant_delete_bank_statement_templates ON bank_statement_templates
    FOR DELETE USING (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'delete policy: %', SQLERRM; END $$;

GRANT SELECT, INSERT, UPDATE, DELETE ON bank_statement_templates TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON bank_statement_templates TO service_role;
