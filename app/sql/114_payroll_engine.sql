-- ============================================================
-- 114_payroll_engine.sql
-- PAY-12 + PAY-02 + PAY-03 + PAY-04 + PAY-05 + PAY-06
--
-- Refonte du moteur de paie :
-- - Table des paramètres légaux par période (PMSS, SMIC, plafonds)
-- - Extension des grid_lines avec ceiling_type, ceiling_multiplier, floor_multiplier
-- - Table des cumuls annuels (régularisation progressive)
-- - Scission CSG déductible / non déductible / CRDS
-- - Réduction générale de cotisations (coefficient Fillon)
-- ============================================================

-- ============================================================
-- PAY-02 : Table des paramètres légaux par période
-- ============================================================
CREATE TABLE IF NOT EXISTS payroll_legal_parameters (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid,                 -- NULL = paramètre global fourni par l'éditeur
  country_code text NOT NULL,
  code text NOT NULL,             -- 'PMSS','SMIC_H','PLAFOND_TR2','TAUX_NEUTRE'…
  value numeric NOT NULL,
  valid_from date NOT NULL,
  valid_to date,
  UNIQUE (tenant_id, country_code, code, valid_from)
);

ALTER TABLE payroll_legal_parameters ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS payroll_legal_params_select ON payroll_legal_parameters;
CREATE POLICY payroll_legal_params_select ON payroll_legal_parameters
  FOR SELECT USING (tenant_id IS NULL OR tenant_id = current_tenant_id());
DROP POLICY IF EXISTS payroll_legal_params_all ON payroll_legal_parameters;
CREATE POLICY payroll_legal_params_all ON payroll_legal_parameters
  FOR ALL USING (tenant_id IS NULL OR tenant_id = current_tenant_id())
  WITH CHECK (tenant_id IS NULL OR tenant_id = current_tenant_id());

-- Seed : paramètres légaux français 2025
INSERT INTO payroll_legal_parameters (tenant_id, country_code, code, value, valid_from)
SELECT NULL, 'FR', v.code, v.value, '2025-01-01'
FROM (VALUES
  ('PMSS', 3925),           -- Plafond mensuel sécurité sociale 2025
  ('SMIC_H', 11.88),        -- SMIC horaire brut 2025
  ('SMIC_M', 1801.80),      -- SMIC mensuel brut 2025 (151,67h)
  ('PLAFOND_TR2', 31400),  -- Plafond tranche 2 AGIRC-ARRCO (8 × PMSS)
  ('TAUX_NEUTRE', 10),     -- Taux neutre PAS par défaut
  ('CSG_DEDUCTIBLE', 6.80),
  ('CSG_NON_DEDUCTIBLE', 2.40),
  ('CRDS', 0.50),
  ('CSG_CRDS_BASE', 98.25), -- Assiette CSG-CRDS = 98,25 % du brut
  ('CGSS_BASE_MULTIPLE', 4), -- Au-delà de 4 PMSS, assiette CSG = 100 %
  ('REDUCTION_GEN_T', 0.3194), -- T paramètre réduction générale 2025
  ('REDUCTION_GEN_T_MAX', 0.3194),
  ('TAUX_CEG', 1.29),       -- Contribution équilibre général AGIRC-ARRCO
  ('TAUX_CET', 0.21),       -- Contribution équilibre technique
  ('TAUX_APPEL_T1', 1.0),   -- Taux d'appel tranche 1
  ('TAUX_APPEL_T2', 1.0)    -- Taux d'appel tranche 2
) AS v(code, value)
WHERE NOT EXISTS (
  SELECT 1 FROM payroll_legal_parameters
  WHERE tenant_id IS NULL AND country_code = 'FR' AND code = v.code AND valid_from = '2025-01-01'
);

-- ============================================================
-- PAY-02 : Étendre payroll_tax_grid_lines avec plafonds
-- ============================================================
ALTER TABLE payroll_tax_grid_lines ADD COLUMN IF NOT EXISTS ceiling_type text
  DEFAULT 'none' CHECK (ceiling_type IN ('none', 'pmss', 'multiple_pmss', 'fixed'));
ALTER TABLE payroll_tax_grid_lines ADD COLUMN IF NOT EXISTS ceiling_multiplier numeric DEFAULT 1;
ALTER TABLE payroll_tax_grid_lines ADD COLUMN IF NOT EXISTS floor_multiplier numeric DEFAULT 0;
ALTER TABLE payroll_tax_grid_lines ADD COLUMN IF NOT EXISTS ceiling_value numeric;
ALTER TABLE payroll_tax_grid_lines ADD COLUMN IF NOT EXISTS cumulative_key text;
ALTER TABLE payroll_tax_grid_lines ADD COLUMN IF NOT EXISTS section text
  DEFAULT 'contribution' CHECK (section IN ('gross', 'contribution', 'tax', 'net', 'employer', 'info'));
ALTER TABLE payroll_tax_grid_lines ADD COLUMN IF NOT EXISTS risk text
  CHECK (risk IS NULL OR risk IN ('health', 'atmp', 'retirement', 'family', 'unemployment', 'other'));
ALTER TABLE payroll_tax_grid_lines ADD COLUMN IF NOT EXISTS is_csg_crds boolean DEFAULT false;
ALTER TABLE payroll_tax_grid_lines ADD COLUMN IF NOT EXISTS csg_type text
  CHECK (csg_type IS NULL OR csg_type IN ('deductible', 'non_deductible', 'crds'));
ALTER TABLE payroll_tax_grid_lines ADD COLUMN IF NOT EXISTS eligible_reduction_generale boolean DEFAULT false;

-- ============================================================
-- PAY-04 : Table des cumuls annuels
-- ============================================================
CREATE TABLE IF NOT EXISTS payroll_cumulative (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  employee_id uuid NOT NULL,
  year integer NOT NULL,
  month integer NOT NULL,
  gross numeric DEFAULT 0,
  taxable_gross numeric DEFAULT 0,
  ceiling_base numeric DEFAULT 0,       -- assiette plafonnée cumulée
  ceiling_available numeric DEFAULT 0,  -- plafond cumulé disponible
  net_taxable numeric DEFAULT 0,
  net_social numeric DEFAULT 0,
  employee_contributions numeric DEFAULT 0,
  employer_contributions numeric DEFAULT 0,
  withholding_tax numeric DEFAULT 0,
  csg_deductible numeric DEFAULT 0,
  csg_non_deductible numeric DEFAULT 0,
  crds numeric DEFAULT 0,
  reduction_generale numeric DEFAULT 0,
  UNIQUE (tenant_id, employee_id, year, month)
);

ALTER TABLE payroll_cumulative ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS payroll_cumulative_tenant ON payroll_cumulative;
CREATE POLICY payroll_cumulative_tenant ON payroll_cumulative
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

CREATE INDEX IF NOT EXISTS idx_payroll_cumulative_emp_year
  ON payroll_cumulative (tenant_id, employee_id, year, month);

-- ============================================================
-- PAY-03 : Méthode de retenue d'absence paramétrable
-- ============================================================
ALTER TABLE company_settings ADD COLUMN IF NOT EXISTS absence_method text
  DEFAULT 'hours_real' CHECK (absence_method IN ('hours_real', 'working_days', 'thirtieth'));

-- ============================================================
-- PAY-05 : RPC de calcul du net imposable et net social
-- ============================================================
CREATE OR REPLACE FUNCTION get_legal_parameter(
  p_code text,
  p_country_code text DEFAULT 'FR',
  p_date date DEFAULT CURRENT_DATE,
  p_tenant_id uuid DEFAULT NULL
)
RETURNS numeric
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT COALESCE(
    (SELECT value FROM payroll_legal_parameters
     WHERE tenant_id = p_tenant_id AND country_code = p_country_code
       AND code = p_code AND valid_from <= p_date
       AND COALESCE(valid_to, '9999-12-31'::date) >= p_date
     ORDER BY valid_from DESC LIMIT 1),
    (SELECT value FROM payroll_legal_parameters
     WHERE tenant_id IS NULL AND country_code = p_country_code
       AND code = p_code AND valid_from <= p_date
       AND COALESCE(valid_to, '9999-12-31'::date) >= p_date
     ORDER BY valid_from DESC LIMIT 1),
    0
  );
$$;

-- ============================================================
-- PAY-04 : Récupérer les cumuls d'un salarié pour une année
-- ============================================================
CREATE OR REPLACE FUNCTION get_payroll_cumulative(
  p_employee_id uuid,
  p_year integer
)
RETURNS TABLE(
  month integer,
  gross numeric,
  taxable_gross numeric,
  ceiling_base numeric,
  ceiling_available numeric,
  net_taxable numeric,
  net_social numeric,
  employee_contributions numeric,
  employer_contributions numeric,
  withholding_tax numeric,
  csg_deductible numeric,
  csg_non_deductible numeric,
  crds numeric,
  reduction_generale numeric
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT month, gross, taxable_gross, ceiling_base, ceiling_available,
         net_taxable, net_social, employee_contributions, employer_contributions,
         withholding_tax, csg_deductible, csg_non_deductible, crds, reduction_generale
  FROM payroll_cumulative
  WHERE employee_id = p_employee_id
    AND tenant_id = current_tenant_id()
    AND year = p_year
  ORDER BY month;
$$;

-- ============================================================
-- PAY-04 : Mettre à jour les cumuls après calcul d'un bulletin
-- ============================================================
CREATE OR REPLACE FUNCTION upsert_payroll_cumulative(
  p_employee_id uuid,
  p_year integer,
  p_month integer,
  p_gross numeric,
  p_taxable_gross numeric,
  p_ceiling_base numeric,
  p_ceiling_available numeric,
  p_net_taxable numeric,
  p_net_social numeric,
  p_employee_contributions numeric,
  p_employer_contributions numeric,
  p_withholding_tax numeric,
  p_csg_deductible numeric,
  p_csg_non_deductible numeric,
  p_crds numeric,
  p_reduction_generale numeric
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
  INSERT INTO payroll_cumulative (
    tenant_id, employee_id, year, month,
    gross, taxable_gross, ceiling_base, ceiling_available,
    net_taxable, net_social,
    employee_contributions, employer_contributions,
    withholding_tax, csg_deductible, csg_non_deductible, crds,
    reduction_generale
  ) VALUES (
    current_tenant_id(), p_employee_id, p_year, p_month,
    p_gross, p_taxable_gross, p_ceiling_base, p_ceiling_available,
    p_net_taxable, p_net_social,
    p_employee_contributions, p_employer_contributions,
    p_withholding_tax, p_csg_deductible, p_csg_non_deductible, p_crds,
    p_reduction_generale
  )
  ON CONFLICT (tenant_id, employee_id, year, month)
  DO UPDATE SET
    gross = EXCLUDED.gross,
    taxable_gross = EXCLUDED.taxable_gross,
    ceiling_base = EXCLUDED.ceiling_base,
    ceiling_available = EXCLUDED.ceiling_available,
    net_taxable = EXCLUDED.net_taxable,
    net_social = EXCLUDED.net_social,
    employee_contributions = EXCLUDED.employee_contributions,
    employer_contributions = EXCLUDED.employer_contributions,
    withholding_tax = EXCLUDED.withholding_tax,
    csg_deductible = EXCLUDED.csg_deductible,
    csg_non_deductible = EXCLUDED.csg_non_deductible,
    crds = EXCLUDED.crds,
    reduction_generale = EXCLUDED.reduction_generale;
END;
$$;
