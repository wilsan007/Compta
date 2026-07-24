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
DROP POLICY IF EXISTS bank_stmt_templates_tenant_isolation ON bank_statement_templates;
CREATE POLICY bank_stmt_templates_tenant_isolation ON bank_statement_templates
  USING (tenant_id = auth.uid() OR tenant_id IS NULL);

GRANT SELECT, INSERT, UPDATE, DELETE ON bank_statement_templates TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON bank_statement_templates TO service_role;
