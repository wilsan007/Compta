-- ============================================================
-- 36_tax_grids_payroll_corporate.sql
-- Tax grids for payroll (ITS, cotisations) and corporate taxes
-- Supports multi-country, importable, and data-driven calculation
-- ============================================================

-- ============ Payroll tax grids (header) ============
CREATE TABLE IF NOT EXISTS payroll_tax_grids (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   UUID REFERENCES tenants(id) ON DELETE CASCADE,
  country_code TEXT NOT NULL,
  grid_type   TEXT NOT NULL CHECK (grid_type IN (
    'its',                    -- Impôt sur le traitement du travail (income tax on salary)
    'employer_contribution',  -- Cotisations patronales
    'employee_contribution',  -- Cotisations salariales
    'income_tax',             -- Impôt sur le revenu
    'other_deduction',        -- Autres retenues
    'other_income',           -- Autres revenus
    'composite'               -- Grille composite (toutes catégories)
  )),
  name        TEXT NOT NULL,
  description TEXT,
  effective_from DATE NOT NULL DEFAULT CURRENT_DATE,
  effective_to   DATE,
  status      TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','active','archived')),
  source      TEXT NOT NULL DEFAULT 'manual' CHECK (source IN ('platform','imported','manual','api')),
  file_url    TEXT,
  is_default  BOOLEAN NOT NULL DEFAULT FALSE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ptg_tenant ON payroll_tax_grids(tenant_id);
CREATE INDEX IF NOT EXISTS idx_ptg_country ON payroll_tax_grids(country_code);
CREATE INDEX IF NOT EXISTS idx_ptg_type ON payroll_tax_grids(grid_type);
CREATE INDEX IF NOT EXISTS idx_ptg_active ON payroll_tax_grids(status) WHERE status = 'active';

-- RLS: tenant-isolated policies (same pattern as 24_security_fix_rls_policies.sql)
ALTER TABLE payroll_tax_grids ENABLE ROW LEVEL SECURITY;
ALTER TABLE payroll_tax_grids FORCE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'tenant_select_payroll_tax_grids') THEN
    DROP POLICY IF EXISTS "tenant_select_payroll_tax_grids" ON payroll_tax_grids;
    CREATE POLICY "tenant_select_payroll_tax_grids" ON payroll_tax_grids
      FOR SELECT USING (tenant_id = current_tenant_id() OR tenant_id IS NULL);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'tenant_insert_payroll_tax_grids') THEN
    DROP POLICY IF EXISTS "tenant_insert_payroll_tax_grids" ON payroll_tax_grids;
    CREATE POLICY "tenant_insert_payroll_tax_grids" ON payroll_tax_grids
      FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'tenant_update_payroll_tax_grids') THEN
    DROP POLICY IF EXISTS "tenant_update_payroll_tax_grids" ON payroll_tax_grids;
    CREATE POLICY "tenant_update_payroll_tax_grids" ON payroll_tax_grids
      FOR UPDATE USING (tenant_id = current_tenant_id()) WITH CHECK (tenant_id = current_tenant_id());
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'tenant_delete_payroll_tax_grids') THEN
    DROP POLICY IF EXISTS "tenant_delete_payroll_tax_grids" ON payroll_tax_grids;
    CREATE POLICY "tenant_delete_payroll_tax_grids" ON payroll_tax_grids
      FOR DELETE USING (tenant_id = current_tenant_id());
  END IF;
END $$;

-- ============ Payroll tax grid lines (detail) ============
CREATE TABLE IF NOT EXISTS payroll_tax_grid_lines (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  grid_id     UUID NOT NULL REFERENCES payroll_tax_grids(id) ON DELETE CASCADE,
  line_type   TEXT NOT NULL CHECK (line_type IN ('bracket','flat','percentage','fixed_amount')),
  category    TEXT NOT NULL CHECK (category IN (
    'social_security','health','retirement','unemployment','csg_crds',
    'its','income_tax','other_deduction','other_income','other_tax',
    'employer_charge','employee_charge'
  )),
  label       TEXT NOT NULL,
  base_type   TEXT NOT NULL DEFAULT 'gross' CHECK (base_type IN (
    'gross','taxable_gross','net','total_gross','custom'
  )),
  min_amount  NUMERIC(12,2) DEFAULT 0,
  max_amount  NUMERIC(12,2),
  rate_employee   NUMERIC(8,4) DEFAULT 0,
  rate_employer   NUMERIC(8,4) DEFAULT 0,
  cap_amount      NUMERIC(12,2),
  fixed_amount    NUMERIC(12,2) DEFAULT 0,
  sort_order  INTEGER NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ptgl_grid ON payroll_tax_grid_lines(grid_id);
CREATE INDEX IF NOT EXISTS idx_ptgl_sort ON payroll_tax_grid_lines(grid_id, sort_order);

-- RLS: tenant-isolated via parent grid
ALTER TABLE payroll_tax_grid_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE payroll_tax_grid_lines FORCE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'tenant_select_payroll_tax_grid_lines') THEN
    DROP POLICY IF EXISTS "tenant_select_payroll_tax_grid_lines" ON payroll_tax_grid_lines;
    CREATE POLICY "tenant_select_payroll_tax_grid_lines" ON payroll_tax_grid_lines
      FOR SELECT USING (EXISTS (
        SELECT 1 FROM payroll_tax_grids g
        WHERE g.id = grid_id AND (g.tenant_id = current_tenant_id() OR g.tenant_id IS NULL)
      ));
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'tenant_insert_payroll_tax_grid_lines') THEN
    DROP POLICY IF EXISTS "tenant_insert_payroll_tax_grid_lines" ON payroll_tax_grid_lines;
    CREATE POLICY "tenant_insert_payroll_tax_grid_lines" ON payroll_tax_grid_lines
      FOR INSERT WITH CHECK (EXISTS (
        SELECT 1 FROM payroll_tax_grids g
        WHERE g.id = grid_id AND g.tenant_id = current_tenant_id()
      ));
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'tenant_update_payroll_tax_grid_lines') THEN
    DROP POLICY IF EXISTS "tenant_update_payroll_tax_grid_lines" ON payroll_tax_grid_lines;
    CREATE POLICY "tenant_update_payroll_tax_grid_lines" ON payroll_tax_grid_lines
      FOR UPDATE USING (EXISTS (
        SELECT 1 FROM payroll_tax_grids g
        WHERE g.id = grid_id AND g.tenant_id = current_tenant_id()
      ));
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'tenant_delete_payroll_tax_grid_lines') THEN
    DROP POLICY IF EXISTS "tenant_delete_payroll_tax_grid_lines" ON payroll_tax_grid_lines;
    CREATE POLICY "tenant_delete_payroll_tax_grid_lines" ON payroll_tax_grid_lines
      FOR DELETE USING (EXISTS (
        SELECT 1 FROM payroll_tax_grids g
        WHERE g.id = grid_id AND g.tenant_id = current_tenant_id()
      ));
  END IF;
END $$;

-- ============ Corporate tax grids (IS, impôt sur bénéfices, etc.) ============
CREATE TABLE IF NOT EXISTS corporate_tax_grids (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   UUID REFERENCES tenants(id) ON DELETE CASCADE,
  country_code TEXT NOT NULL,
  tax_type    TEXT NOT NULL CHECK (tax_type IN (
    'corporate_income_tax',   -- Impôt sur les bénéfices (IS)
    'minimum_tax',            -- Impôt minimum forfaitaire
    'turnover_tax',           -- Impôt sur le chiffre d'affaires
    'withholding_tax',        -- Retenue à la source
    'property_tax',           -- Impôt foncier
    'other_corporate_tax'
  )),
  name        TEXT NOT NULL,
  description TEXT,
  effective_from DATE NOT NULL DEFAULT CURRENT_DATE,
  effective_to   DATE,
  status      TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','active','archived')),
  source      TEXT NOT NULL DEFAULT 'manual' CHECK (source IN ('platform','imported','manual','api')),
  file_url    TEXT,
  is_default  BOOLEAN NOT NULL DEFAULT FALSE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ctg_tenant ON corporate_tax_grids(tenant_id);
CREATE INDEX IF NOT EXISTS idx_ctg_country ON corporate_tax_grids(country_code);
CREATE INDEX IF NOT EXISTS idx_ctg_active ON corporate_tax_grids(status) WHERE status = 'active';

ALTER TABLE corporate_tax_grids ENABLE ROW LEVEL SECURITY;
ALTER TABLE corporate_tax_grids FORCE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'tenant_select_corporate_tax_grids') THEN
    DROP POLICY IF EXISTS "tenant_select_corporate_tax_grids" ON corporate_tax_grids;
    CREATE POLICY "tenant_select_corporate_tax_grids" ON corporate_tax_grids
      FOR SELECT USING (tenant_id = current_tenant_id() OR tenant_id IS NULL);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'tenant_insert_corporate_tax_grids') THEN
    DROP POLICY IF EXISTS "tenant_insert_corporate_tax_grids" ON corporate_tax_grids;
    CREATE POLICY "tenant_insert_corporate_tax_grids" ON corporate_tax_grids
      FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'tenant_update_corporate_tax_grids') THEN
    DROP POLICY IF EXISTS "tenant_update_corporate_tax_grids" ON corporate_tax_grids;
    CREATE POLICY "tenant_update_corporate_tax_grids" ON corporate_tax_grids
      FOR UPDATE USING (tenant_id = current_tenant_id()) WITH CHECK (tenant_id = current_tenant_id());
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'tenant_delete_corporate_tax_grids') THEN
    DROP POLICY IF EXISTS "tenant_delete_corporate_tax_grids" ON corporate_tax_grids;
    CREATE POLICY "tenant_delete_corporate_tax_grids" ON corporate_tax_grids
      FOR DELETE USING (tenant_id = current_tenant_id());
  END IF;
END $$;

-- ============ Corporate tax grid lines ============
CREATE TABLE IF NOT EXISTS corporate_tax_grid_lines (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  grid_id     UUID NOT NULL REFERENCES corporate_tax_grids(id) ON DELETE CASCADE,
  line_type   TEXT NOT NULL CHECK (line_type IN ('bracket','flat','percentage','fixed_amount')),
  label       TEXT NOT NULL,
  base_type   TEXT NOT NULL DEFAULT 'profit' CHECK (base_type IN (
    'profit','turnover','property_value','custom'
  )),
  min_amount  NUMERIC(15,2) DEFAULT 0,
  max_amount  NUMERIC(15,2),
  rate        NUMERIC(8,4) DEFAULT 0,
  cap_amount  NUMERIC(15,2),
  fixed_amount NUMERIC(15,2) DEFAULT 0,
  sort_order  INTEGER NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ctgl_grid ON corporate_tax_grid_lines(grid_id);
CREATE INDEX IF NOT EXISTS idx_ctgl_sort ON corporate_tax_grid_lines(grid_id, sort_order);

ALTER TABLE corporate_tax_grid_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE corporate_tax_grid_lines FORCE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'tenant_select_corporate_tax_grid_lines') THEN
    DROP POLICY IF EXISTS "tenant_select_corporate_tax_grid_lines" ON corporate_tax_grid_lines;
    CREATE POLICY "tenant_select_corporate_tax_grid_lines" ON corporate_tax_grid_lines
      FOR SELECT USING (EXISTS (
        SELECT 1 FROM corporate_tax_grids g
        WHERE g.id = grid_id AND (g.tenant_id = current_tenant_id() OR g.tenant_id IS NULL)
      ));
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'tenant_insert_corporate_tax_grid_lines') THEN
    DROP POLICY IF EXISTS "tenant_insert_corporate_tax_grid_lines" ON corporate_tax_grid_lines;
    CREATE POLICY "tenant_insert_corporate_tax_grid_lines" ON corporate_tax_grid_lines
      FOR INSERT WITH CHECK (EXISTS (
        SELECT 1 FROM corporate_tax_grids g
        WHERE g.id = grid_id AND g.tenant_id = current_tenant_id()
      ));
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'tenant_update_corporate_tax_grid_lines') THEN
    DROP POLICY IF EXISTS "tenant_update_corporate_tax_grid_lines" ON corporate_tax_grid_lines;
    CREATE POLICY "tenant_update_corporate_tax_grid_lines" ON corporate_tax_grid_lines
      FOR UPDATE USING (EXISTS (
        SELECT 1 FROM corporate_tax_grids g
        WHERE g.id = grid_id AND g.tenant_id = current_tenant_id()
      ));
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'tenant_delete_corporate_tax_grid_lines') THEN
    DROP POLICY IF EXISTS "tenant_delete_corporate_tax_grid_lines" ON corporate_tax_grid_lines;
    CREATE POLICY "tenant_delete_corporate_tax_grid_lines" ON corporate_tax_grid_lines
      FOR DELETE USING (EXISTS (
        SELECT 1 FROM corporate_tax_grids g
        WHERE g.id = grid_id AND g.tenant_id = current_tenant_id()
      ));
  END IF;
END $$;

-- ============ Updated trigger ============
CREATE OR REPLACE FUNCTION update_tax_grid_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_ptg_updated ON payroll_tax_grids;
CREATE TRIGGER trg_ptg_updated BEFORE UPDATE ON payroll_tax_grids
  FOR EACH ROW EXECUTE FUNCTION update_tax_grid_timestamp();

DROP TRIGGER IF EXISTS trg_ctg_updated ON corporate_tax_grids;
CREATE TRIGGER trg_ctg_updated BEFORE UPDATE ON corporate_tax_grids
  FOR EACH ROW EXECUTE FUNCTION update_tax_grid_timestamp();

-- ============ Seed: French payroll grid (platform default) ============
INSERT INTO payroll_tax_grids (tenant_id, country_code, grid_type, name, description, status, source, is_default, effective_from)
VALUES (NULL, 'FR', 'composite', 'Grille paie France 2024-2025', 'Cotisations sociales et prélèvement à la source - France', 'active', 'platform', TRUE, '2024-01-01')
ON CONFLICT DO NOTHING;

-- Get the grid id for seeding lines
DO $$
DECLARE
  v_grid_id UUID;
BEGIN
  SELECT id INTO v_grid_id FROM payroll_tax_grids
  WHERE country_code = 'FR' AND grid_type = 'composite' AND source = 'platform' AND is_default = TRUE
  LIMIT 1;

  IF v_grid_id IS NOT NULL THEN
    -- Employee contributions
    INSERT INTO payroll_tax_grid_lines (grid_id, line_type, category, label, base_type, rate_employee, rate_employer, sort_order) VALUES
    (v_grid_id, 'percentage', 'social_security', 'Sécurité sociale (salariale)', 'gross', 6.98, 29.74, 1),
    (v_grid_id, 'percentage', 'health', 'Assurance maladie (salariale)', 'gross', 0.40, 7.28, 2),
    (v_grid_id, 'percentage', 'retirement', 'Retraite (salariale)', 'gross', 11.40, 10.93, 3),
    (v_grid_id, 'percentage', 'unemployment', 'Chômage (salarial)', 'gross', 0.24, 4.28, 4),
    (v_grid_id, 'percentage', 'csg_crds', 'CSG/CRDS', 'total_gross', 9.20, 0, 5),
    (v_grid_id, 'percentage', 'its', 'Prélèvement à la source', 'taxable_gross', 0, 0, 6)
    ON CONFLICT DO NOTHING;
  END IF;
END $$;

-- ============ Seed: Senegal ITS grid (platform default) ============
INSERT INTO payroll_tax_grids (tenant_id, country_code, grid_type, name, description, status, source, is_default, effective_from)
VALUES (NULL, 'SN', 'its', 'Grille ITS Sénégal - Tranches mensuelles', 'Impôt sur le traitement du travail - Barème mensuel Sénégal', 'active', 'platform', TRUE, '2024-01-01')
ON CONFLICT DO NOTHING;

DO $$
DECLARE
  v_grid_id UUID;
BEGIN
  SELECT id INTO v_grid_id FROM payroll_tax_grids
  WHERE country_code = 'SN' AND grid_type = 'its' AND source = 'platform' AND is_default = TRUE
  LIMIT 1;

  IF v_grid_id IS NOT NULL THEN
    -- ITS Senegal: tranches mensuelles (approximatif)
    INSERT INTO payroll_tax_grid_lines (grid_id, line_type, category, label, base_type, min_amount, max_amount, rate_employee, sort_order) VALUES
    (v_grid_id, 'bracket', 'its', 'Tranche 1: 0 - 62 500', 'gross', 0, 62500, 0, 1),
    (v_grid_id, 'bracket', 'its', 'Tranche 2: 62 501 - 150 000', 'gross', 62501, 150000, 5, 2),
    (v_grid_id, 'bracket', 'its', 'Tranche 3: 150 001 - 250 000', 'gross', 150001, 250000, 10, 3),
    (v_grid_id, 'bracket', 'its', 'Tranche 4: 250 001 - 500 000', 'gross', 250001, 500000, 15, 4),
    (v_grid_id, 'bracket', 'its', 'Tranche 5: 500 001 - 1 000 000', 'gross', 500001, 1000000, 20, 5),
    (v_grid_id, 'bracket', 'its', 'Tranche 6: > 1 000 000', 'gross', 1000001, NULL, 25, 6)
    ON CONFLICT DO NOTHING;
  END IF;
END $$;

-- ============ Seed: Senegal employer/employee contributions ============
INSERT INTO payroll_tax_grids (tenant_id, country_code, grid_type, name, description, status, source, is_default, effective_from)
VALUES (NULL, 'SN', 'employer_contribution', 'Cotisations patronales Sénégal', 'Charges patronales - Sénégal', 'active', 'platform', TRUE, '2024-01-01')
ON CONFLICT DO NOTHING;

DO $$
DECLARE
  v_grid_id UUID;
BEGIN
  SELECT id INTO v_grid_id FROM payroll_tax_grids
  WHERE country_code = 'SN' AND grid_type = 'employer_contribution' AND source = 'platform' AND is_default = TRUE
  LIMIT 1;

  IF v_grid_id IS NOT NULL THEN
    INSERT INTO payroll_tax_grid_lines (grid_id, line_type, category, label, base_type, rate_employer, cap_amount, sort_order) VALUES
    (v_grid_id, 'percentage', 'social_security', 'Sécurité sociale (IPM)', 'gross', 5, 75000, 1),
    (v_grid_id, 'percentage', 'retirement', 'Retraite (IPM)', 'gross', 8.4, 75000, 2),
    (v_grid_id, 'percentage', 'health', 'Allocations familiales', 'gross', 7, 75000, 3),
    (v_grid_id, 'percentage', 'employer_charge', 'Impôt sur les salaires (TFPC)', 'gross', 3, NULL, 4),
    (v_grid_id, 'percentage', 'employer_charge', 'Fonds national de solidarité', 'gross', 1, NULL, 5)
    ON CONFLICT DO NOTHING;
  END IF;
END $$;

INSERT INTO payroll_tax_grids (tenant_id, country_code, grid_type, name, description, status, source, is_default, effective_from)
VALUES (NULL, 'SN', 'employee_contribution', 'Cotisations salariales Sénégal', 'Retenues salariales - Sénégal', 'active', 'platform', TRUE, '2024-01-01')
ON CONFLICT DO NOTHING;

DO $$
DECLARE
  v_grid_id UUID;
BEGIN
  SELECT id INTO v_grid_id FROM payroll_tax_grids
  WHERE country_code = 'SN' AND grid_type = 'employee_contribution' AND source = 'platform' AND is_default = TRUE
  LIMIT 1;

  IF v_grid_id IS NOT NULL THEN
    INSERT INTO payroll_tax_grid_lines (grid_id, line_type, category, label, base_type, rate_employee, cap_amount, sort_order) VALUES
    (v_grid_id, 'percentage', 'social_security', 'Sécurité sociale (IPM)', 'gross', 3.6, 75000, 1),
    (v_grid_id, 'percentage', 'retirement', 'Retraite (IPM)', 'gross', 5.6, 75000, 2),
    (v_grid_id, 'percentage', 'other_deduction', 'Fonds national de solidarité', 'gross', 1, NULL, 3)
    ON CONFLICT DO NOTHING;
  END IF;
END $$;
