-- ============================================================
-- Sprint 5: Analytique Multi-Axes + Écritures Enhancements
-- Elements: #45 (Distribution JSON), #46 (Distribution Lines),
--           #30 (Residual), #34 (Extourne - already exists),
--           #39 (Tax Tags), #40 (Product), #42 (Analytic %),
--           #47 (Payment State)
-- ============================================================

-- ============================================================
-- #45: Analytic Distribution Multi-Axes (JSON on journal_lines)
-- ============================================================
ALTER TABLE journal_lines ADD COLUMN IF NOT EXISTS analytic_distribution jsonb;

-- ============================================================
-- #46: Analytic Distribution Lines (multi-sections per plan)
-- ============================================================
CREATE TABLE IF NOT EXISTS analytic_distribution_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  journal_line_id uuid REFERENCES journal_lines(id) ON DELETE CASCADE,
  plan_id uuid REFERENCES analytic_plans(id),
  section_id uuid REFERENCES analytic_sections(id),
  percentage numeric(5,2) NOT NULL,
  amount numeric(14,2),
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_analytic_dist_line ON analytic_distribution_lines(journal_line_id);
CREATE INDEX IF NOT EXISTS idx_analytic_dist_line_plan ON analytic_distribution_lines(plan_id);

ALTER TABLE analytic_distribution_lines ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'tenant_isolated_analytic_dist_lines') THEN
    DROP POLICY IF EXISTS "tenant_isolated_analytic_dist_lines" ON analytic_distribution_lines;
    CREATE POLICY "tenant_isolated_analytic_dist_lines" ON analytic_distribution_lines
      FOR ALL USING (tenant_id IS NULL OR tenant_id = current_setting('app.tenant_id', true)::uuid)
      WITH CHECK (tenant_id IS NULL OR tenant_id = current_setting('app.tenant_id', true)::uuid);
  END IF;
END $$;

-- ============================================================
-- #30: Amount Residual on journal_lines
-- ============================================================
ALTER TABLE journal_lines ADD COLUMN IF NOT EXISTS amount_residual numeric(14,2) DEFAULT 0;

-- ============================================================
-- #39: Tax Tag IDs on journal_lines
-- ============================================================
ALTER TABLE journal_lines ADD COLUMN IF NOT EXISTS tax_tag_ids text[] DEFAULT '{}';

-- ============================================================
-- #40: Product on journal_lines
-- ============================================================
ALTER TABLE journal_lines ADD COLUMN IF NOT EXISTS product_id uuid;
ALTER TABLE journal_lines ADD COLUMN IF NOT EXISTS product_uom text;

-- ============================================================
-- #47: Payment State on invoices + purchase_invoices
-- ============================================================
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS payment_state text DEFAULT 'not_paid';
ALTER TABLE purchase_invoices ADD COLUMN IF NOT EXISTS payment_state text DEFAULT 'not_paid';

-- ============================================================
-- #34: Extourne - table already exists in 25_accounting_features.sql
-- Ensure the generateExtourne function can link entries
-- ============================================================
-- (No additional SQL needed - extourne_log table already exists)
