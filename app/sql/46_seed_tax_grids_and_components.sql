-- ============================================================
-- 46_seed_tax_grids_and_components.sql
-- Seed corporate tax grids (IS) for FR, SN, CI, CM
-- Seed payroll tax grids for CI, CM
-- Seed standard payroll components
-- All platform-level (tenant_id = NULL), easily updatable
-- ============================================================

-- ============================================
-- CORPORATE TAX GRIDS (Impôt sur les sociétés)
-- ============================================

-- France: IS 2024-2025
-- 15% sur les premiers 42 500 € (PME), 25% au-delà
INSERT INTO corporate_tax_grids (tenant_id, country_code, tax_type, name, description, status, source, is_default, effective_from)
VALUES (NULL, 'FR', 'corporate_income_tax', 'Impôt sur les sociétés France 2024-2025', 'IS - 15% PME / 25% taux normal', 'active', 'platform', TRUE, '2024-01-01')
ON CONFLICT DO NOTHING;

DO $$
DECLARE v_grid_id UUID;
BEGIN
  SELECT id INTO v_grid_id FROM corporate_tax_grids
  WHERE country_code = 'FR' AND tax_type = 'corporate_income_tax' AND source = 'platform' AND is_default = TRUE
  LIMIT 1;
  IF v_grid_id IS NOT NULL THEN
    INSERT INTO corporate_tax_grid_lines (grid_id, line_type, label, base_type, min_amount, max_amount, rate, sort_order) VALUES
    (v_grid_id, 'bracket', 'Tranche 1: 0 - 42 500 € (PME 15%)', 'profit', 0, 42500, 15.00, 1),
    (v_grid_id, 'bracket', 'Tranche 2: > 42 500 € (25%)', 'profit', 42501, NULL, 25.00, 2)
    ON CONFLICT DO NOTHING;
  END IF;
END $$;

-- France: Impôt minimum forfaitaire (IMF) — 0,125% du CA minimum 3 125 €
INSERT INTO corporate_tax_grids (tenant_id, country_code, tax_type, name, description, status, source, is_default, effective_from)
VALUES (NULL, 'FR', 'minimum_tax', 'Impôt minimum forfaitaire France', 'IMF 0,125% du CA — minimum 3 125 €', 'active', 'platform', FALSE, '2024-01-01')
ON CONFLICT DO NOTHING;

DO $$
DECLARE v_grid_id UUID;
BEGIN
  SELECT id INTO v_grid_id FROM corporate_tax_grids
  WHERE country_code = 'FR' AND tax_type = 'minimum_tax' AND source = 'platform'
  LIMIT 1;
  IF v_grid_id IS NOT NULL THEN
    INSERT INTO corporate_tax_grid_lines (grid_id, line_type, label, base_type, min_amount, max_amount, rate, fixed_amount, sort_order) VALUES
    (v_grid_id, 'percentage', 'IMF (0,125% du CA)', 'turnover', 0, NULL, 0.125, 0, 1)
    ON CONFLICT DO NOTHING;
  END IF;
END $$;

-- Sénégal: IS 2024 — 30% (taux unique)
INSERT INTO corporate_tax_grids (tenant_id, country_code, tax_type, name, description, status, source, is_default, effective_from)
VALUES (NULL, 'SN', 'corporate_income_tax', 'Impôt sur les sociétés Sénégal 2024', 'IS - 30% taux unique', 'active', 'platform', TRUE, '2024-01-01')
ON CONFLICT DO NOTHING;

DO $$
DECLARE v_grid_id UUID;
BEGIN
  SELECT id INTO v_grid_id FROM corporate_tax_grids
  WHERE country_code = 'SN' AND tax_type = 'corporate_income_tax' AND source = 'platform' AND is_default = TRUE
  LIMIT 1;
  IF v_grid_id IS NOT NULL THEN
    INSERT INTO corporate_tax_grid_lines (grid_id, line_type, label, base_type, min_amount, max_amount, rate, sort_order) VALUES
    (v_grid_id, 'flat', 'IS Sénégal (30%)', 'profit', 0, NULL, 30.00, 1)
    ON CONFLICT DO NOTHING;
  END IF;
END $$;

-- Sénégal: Impôt minimum forfaitaire (IMF) — 0,5% du CA
INSERT INTO corporate_tax_grids (tenant_id, country_code, tax_type, name, description, status, source, is_default, effective_from)
VALUES (NULL, 'SN', 'minimum_tax', 'Impôt minimum forfaitaire Sénégal', 'IMF 0,5% du CA', 'active', 'platform', FALSE, '2024-01-01')
ON CONFLICT DO NOTHING;

DO $$
DECLARE v_grid_id UUID;
BEGIN
  SELECT id INTO v_grid_id FROM corporate_tax_grids
  WHERE country_code = 'SN' AND tax_type = 'minimum_tax' AND source = 'platform'
  LIMIT 1;
  IF v_grid_id IS NOT NULL THEN
    INSERT INTO corporate_tax_grid_lines (grid_id, line_type, label, base_type, min_amount, max_amount, rate, sort_order) VALUES
    (v_grid_id, 'percentage', 'IMF (0,5% du CA)', 'turnover', 0, NULL, 0.50, 1)
    ON CONFLICT DO NOTHING;
  END IF;
END $$;

-- Côte d'Ivoire: IS 2024 — 25%
INSERT INTO corporate_tax_grids (tenant_id, country_code, tax_type, name, description, status, source, is_default, effective_from)
VALUES (NULL, 'CI', 'corporate_income_tax', 'Impôt sur les sociétés Côte d''Ivoire 2024', 'IS - 25% taux unique', 'active', 'platform', TRUE, '2024-01-01')
ON CONFLICT DO NOTHING;

DO $$
DECLARE v_grid_id UUID;
BEGIN
  SELECT id INTO v_grid_id FROM corporate_tax_grids
  WHERE country_code = 'CI' AND tax_type = 'corporate_income_tax' AND source = 'platform' AND is_default = TRUE
  LIMIT 1;
  IF v_grid_id IS NOT NULL THEN
    INSERT INTO corporate_tax_grid_lines (grid_id, line_type, label, base_type, min_amount, max_amount, rate, sort_order) VALUES
    (v_grid_id, 'flat', 'IS Côte d''Ivoire (25%)', 'profit', 0, NULL, 25.00, 1)
    ON CONFLICT DO NOTHING;
  END IF;
END $$;

-- Côte d'Ivoire: IMF — 0,5% du CA minimum 3 000 000 FCFA
INSERT INTO corporate_tax_grids (tenant_id, country_code, tax_type, name, description, status, source, is_default, effective_from)
VALUES (NULL, 'CI', 'minimum_tax', 'Impôt minimum forfaitaire Côte d''Ivoire', 'IMF 0,5% du CA — minimum 3 000 000 FCFA', 'active', 'platform', FALSE, '2024-01-01')
ON CONFLICT DO NOTHING;

DO $$
DECLARE v_grid_id UUID;
BEGIN
  SELECT id INTO v_grid_id FROM corporate_tax_grids
  WHERE country_code = 'CI' AND tax_type = 'minimum_tax' AND source = 'platform'
  LIMIT 1;
  IF v_grid_id IS NOT NULL THEN
    INSERT INTO corporate_tax_grid_lines (grid_id, line_type, label, base_type, min_amount, max_amount, rate, fixed_amount, sort_order) VALUES
    (v_grid_id, 'percentage', 'IMF (0,5% du CA)', 'turnover', 0, NULL, 0.50, 3000000, 1)
    ON CONFLICT DO NOTHING;
  END IF;
END $$;

-- Cameroun: IS 2024 — 30,8% (30% + 0,8% centimes additionnels)
INSERT INTO corporate_tax_grids (tenant_id, country_code, tax_type, name, description, status, source, is_default, effective_from)
VALUES (NULL, 'CM', 'corporate_income_tax', 'Impôt sur les sociétés Cameroun 2024', 'IS - 30,8% (30% + 0,8% centimes)', 'active', 'platform', TRUE, '2024-01-01')
ON CONFLICT DO NOTHING;

DO $$
DECLARE v_grid_id UUID;
BEGIN
  SELECT id INTO v_grid_id FROM corporate_tax_grids
  WHERE country_code = 'CM' AND tax_type = 'corporate_income_tax' AND source = 'platform' AND is_default = TRUE
  LIMIT 1;
  IF v_grid_id IS NOT NULL THEN
    INSERT INTO corporate_tax_grid_lines (grid_id, line_type, label, base_type, min_amount, max_amount, rate, sort_order) VALUES
    (v_grid_id, 'flat', 'IS Cameroun (30,8%)', 'profit', 0, NULL, 30.80, 1)
    ON CONFLICT DO NOTHING;
  END IF;
END $$;

-- Cameroun: IMF — 1,1% du CA minimum 500 000 FCFA
INSERT INTO corporate_tax_grids (tenant_id, country_code, tax_type, name, description, status, source, is_default, effective_from)
VALUES (NULL, 'CM', 'minimum_tax', 'Impôt minimum forfaitaire Cameroun', 'IMF 1,1% du CA — minimum 500 000 FCFA', 'active', 'platform', FALSE, '2024-01-01')
ON CONFLICT DO NOTHING;

DO $$
DECLARE v_grid_id UUID;
BEGIN
  SELECT id INTO v_grid_id FROM corporate_tax_grids
  WHERE country_code = 'CM' AND tax_type = 'minimum_tax' AND source = 'platform'
  LIMIT 1;
  IF v_grid_id IS NOT NULL THEN
    INSERT INTO corporate_tax_grid_lines (grid_id, line_type, label, base_type, min_amount, max_amount, rate, fixed_amount, sort_order) VALUES
    (v_grid_id, 'percentage', 'IMF (1,1% du CA)', 'turnover', 0, NULL, 1.10, 500000, 1)
    ON CONFLICT DO NOTHING;
  END IF;
END $$;

-- ============================================
-- PAYROLL TAX GRIDS for Côte d'Ivoire
-- ============================================

-- CI: ITS (Impôt sur le Traitement du Salaire) — tranches mensuelles
INSERT INTO payroll_tax_grids (tenant_id, country_code, grid_type, name, description, status, source, is_default, effective_from)
VALUES (NULL, 'CI', 'its', 'Grille ITS Côte d''Ivoire - Tranches mensuelles', 'Impôt sur le traitement du salaire - Barème mensuel CI', 'active', 'platform', TRUE, '2024-01-01')
ON CONFLICT DO NOTHING;

DO $$
DECLARE v_grid_id UUID;
BEGIN
  SELECT id INTO v_grid_id FROM payroll_tax_grids
  WHERE country_code = 'CI' AND grid_type = 'its' AND source = 'platform' AND is_default = TRUE
  LIMIT 1;
  IF v_grid_id IS NOT NULL THEN
    INSERT INTO payroll_tax_grid_lines (grid_id, line_type, category, label, base_type, min_amount, max_amount, rate_employee, sort_order) VALUES
    (v_grid_id, 'bracket', 'its', 'Tranche 1: 0 - 30 000', 'gross', 0, 30000, 0, 1),
    (v_grid_id, 'bracket', 'its', 'Tranche 2: 30 001 - 50 000', 'gross', 30001, 50000, 1.5, 2),
    (v_grid_id, 'bracket', 'its', 'Tranche 3: 50 001 - 80 000', 'gross', 50001, 80000, 5, 3),
    (v_grid_id, 'bracket', 'its', 'Tranche 4: 80 001 - 120 000', 'gross', 80001, 120000, 10, 4),
    (v_grid_id, 'bracket', 'its', 'Tranche 5: 120 001 - 200 000', 'gross', 120001, 200000, 15, 5),
    (v_grid_id, 'bracket', 'its', 'Tranche 6: 200 001 - 300 000', 'gross', 200001, 300000, 20, 6),
    (v_grid_id, 'bracket', 'its', 'Tranche 7: > 300 000', 'gross', 300001, NULL, 25, 7)
    ON CONFLICT DO NOTHING;
  END IF;
END $$;

-- CI: Cotisations patronales
INSERT INTO payroll_tax_grids (tenant_id, country_code, grid_type, name, description, status, source, is_default, effective_from)
VALUES (NULL, 'CI', 'employer_contribution', 'Cotisations patronales Côte d''Ivoire', 'Charges patronales - CNPS + autres', 'active', 'platform', TRUE, '2024-01-01')
ON CONFLICT DO NOTHING;

DO $$
DECLARE v_grid_id UUID;
BEGIN
  SELECT id INTO v_grid_id FROM payroll_tax_grids
  WHERE country_code = 'CI' AND grid_type = 'employer_contribution' AND source = 'platform' AND is_default = TRUE
  LIMIT 1;
  IF v_grid_id IS NOT NULL THEN
    INSERT INTO payroll_tax_grid_lines (grid_id, line_type, category, label, base_type, rate_employer, cap_amount, sort_order) VALUES
    (v_grid_id, 'percentage', 'social_security', 'CNPS (retraite patronale)', 'gross', 7.2, 360000, 1),
    (v_grid_id, 'percentage', 'health', 'CNPS (maladie patronale)', 'gross', 3.0, 360000, 2),
    (v_grid_id, 'percentage', 'employer_charge', 'Accidents du travail', 'gross', 2.0, NULL, 3),
    (v_grid_id, 'percentage', 'employer_charge', 'Impôt sur les salaires', 'gross', 1.2, NULL, 4),
    (v_grid_id, 'percentage', 'employer_charge', 'Fonds national de solidarité', 'gross', 0.5, NULL, 5)
    ON CONFLICT DO NOTHING;
  END IF;
END $$;

-- CI: Cotisations salariales
INSERT INTO payroll_tax_grids (tenant_id, country_code, grid_type, name, description, status, source, is_default, effective_from)
VALUES (NULL, 'CI', 'employee_contribution', 'Cotisations salariales Côte d''Ivoire', 'Retenues salariales - CNPS', 'active', 'platform', TRUE, '2024-01-01')
ON CONFLICT DO NOTHING;

DO $$
DECLARE v_grid_id UUID;
BEGIN
  SELECT id INTO v_grid_id FROM payroll_tax_grids
  WHERE country_code = 'CI' AND grid_type = 'employee_contribution' AND source = 'platform' AND is_default = TRUE
  LIMIT 1;
  IF v_grid_id IS NOT NULL THEN
    INSERT INTO payroll_tax_grid_lines (grid_id, line_type, category, label, base_type, rate_employee, cap_amount, sort_order) VALUES
    (v_grid_id, 'percentage', 'social_security', 'CNPS (retraite salariale)', 'gross', 6.3, 360000, 1),
    (v_grid_id, 'percentage', 'health', 'CNPS (maladie salariale)', 'gross', 2.4, 360000, 2),
    (v_grid_id, 'percentage', 'other_deduction', 'Fonds national de solidarité', 'gross', 0.5, NULL, 3)
    ON CONFLICT DO NOTHING;
  END IF;
END $$;

-- ============================================
-- PAYROLL TAX GRIDS for Cameroun
-- ============================================

-- CM: IRPP (Impôt sur le Revenu des Personnes Physiques) — tranches mensuelles
INSERT INTO payroll_tax_grids (tenant_id, country_code, grid_type, name, description, status, source, is_default, effective_from)
VALUES (NULL, 'CM', 'its', 'Grille IRPP Cameroun - Tranches mensuelles', 'Impôt sur le revenu des personnes physiques - Barème mensuel CM', 'active', 'platform', TRUE, '2024-01-01')
ON CONFLICT DO NOTHING;

DO $$
DECLARE v_grid_id UUID;
BEGIN
  SELECT id INTO v_grid_id FROM payroll_tax_grids
  WHERE country_code = 'CM' AND grid_type = 'its' AND source = 'platform' AND is_default = TRUE
  LIMIT 1;
  IF v_grid_id IS NOT NULL THEN
    INSERT INTO payroll_tax_grid_lines (grid_id, line_type, category, label, base_type, min_amount, max_amount, rate_employee, sort_order) VALUES
    (v_grid_id, 'bracket', 'its', 'Tranche 1: 0 - 50 000', 'gross', 0, 50000, 0, 1),
    (v_grid_id, 'bracket', 'its', 'Tranche 2: 50 001 - 100 000', 'gross', 50001, 100000, 10, 2),
    (v_grid_id, 'bracket', 'its', 'Tranche 3: 100 001 - 200 000', 'gross', 100001, 200000, 15, 3),
    (v_grid_id, 'bracket', 'its', 'Tranche 4: 200 001 - 400 000', 'gross', 200001, 400000, 25, 4),
    (v_grid_id, 'bracket', 'its', 'Tranche 5: > 400 000', 'gross', 400001, NULL, 35, 5)
    ON CONFLICT DO NOTHING;
  END IF;
END $$;

-- CM: Cotisations patronales CNPS
INSERT INTO payroll_tax_grids (tenant_id, country_code, grid_type, name, description, status, source, is_default, effective_from)
VALUES (NULL, 'CM', 'employer_contribution', 'Cotisations patronales Cameroun', 'Charges patronales - CNPS Cameroun', 'active', 'platform', TRUE, '2024-01-01')
ON CONFLICT DO NOTHING;

DO $$
DECLARE v_grid_id UUID;
BEGIN
  SELECT id INTO v_grid_id FROM payroll_tax_grids
  WHERE country_code = 'CM' AND grid_type = 'employer_contribution' AND source = 'platform' AND is_default = TRUE
  LIMIT 1;
  IF v_grid_id IS NOT NULL THEN
    INSERT INTO payroll_tax_grid_lines (grid_id, line_type, category, label, base_type, rate_employer, cap_amount, sort_order) VALUES
    (v_grid_id, 'percentage', 'social_security', 'CNPS (retraite patronale)', 'gross', 7.0, 300000, 1),
    (v_grid_id, 'percentage', 'health', 'CNPS (maladie patronale)', 'gross', 2.8, 300000, 2),
    (v_grid_id, 'percentage', 'employer_charge', 'Accidents du travail', 'gross', 1.75, NULL, 3),
    (v_grid_id, 'percentage', 'employer_charge', 'Impôt sur les salaires', 'gross', 2.0, NULL, 4),
    (v_grid_id, 'percentage', 'employer_charge', 'Fonds national de l''emploi', 'gross', 1.2, NULL, 5)
    ON CONFLICT DO NOTHING;
  END IF;
END $$;

-- CM: Cotisations salariales CNPS
INSERT INTO payroll_tax_grids (tenant_id, country_code, grid_type, name, description, status, source, is_default, effective_from)
VALUES (NULL, 'CM', 'employee_contribution', 'Cotisations salariales Cameroun', 'Retenues salariales - CNPS Cameroun', 'active', 'platform', TRUE, '2024-01-01')
ON CONFLICT DO NOTHING;

DO $$
DECLARE v_grid_id UUID;
BEGIN
  SELECT id INTO v_grid_id FROM payroll_tax_grids
  WHERE country_code = 'CM' AND grid_type = 'employee_contribution' AND source = 'platform' AND is_default = TRUE
  LIMIT 1;
  IF v_grid_id IS NOT NULL THEN
    INSERT INTO payroll_tax_grid_lines (grid_id, line_type, category, label, base_type, rate_employee, cap_amount, sort_order) VALUES
    (v_grid_id, 'percentage', 'social_security', 'CNPS (retraite salariale)', 'gross', 4.2, 300000, 1),
    (v_grid_id, 'percentage', 'health', 'CNPS (maladie salariale)', 'gross', 1.2, 300000, 2)
    ON CONFLICT DO NOTHING;
  END IF;
END $$;

-- ============================================
-- PAYROLL COMPONENTS (standard rubriques)
-- ============================================
-- These are platform-level components that every tenant inherits.
-- Tenants can override or add their own.

INSERT INTO payroll_components (tenant_id, code, name, type, calculation_type, default_value, rate_employer, rate_employee, display_order, active)
VALUES
  (NULL, 'BASE', 'Salaire de base', 'gross', 'fixed', 0, 0, 0, 1, true),
  (NULL, 'PRIME_ANC', 'Prime d''ancienneté', 'gross', 'percentage', 0, 0, 0, 2, true),
  (NULL, 'PRIME_TRANSP', 'Indemnité de transport', 'benefit', 'fixed', 0, 0, 0, 3, true),
  (NULL, 'PRIME_REPAS', 'Titres restaurant', 'benefit', 'fixed', 0, 0, 0, 4, true),
  (NULL, 'HSUPP', 'Heures supplémentaires', 'gross', 'percentage', 0, 0, 0, 5, true),
  (NULL, 'SEC_SOC', 'Sécurité sociale (salariale)', 'contribution', 'percentage', 0, 0, 0, 10, true),
  (NULL, 'SEC_SOC_PAT', 'Sécurité sociale (patronale)', 'contribution', 'percentage', 0, 0, 0, 11, true),
  (NULL, 'MALADIE', 'Assurance maladie (salariale)', 'contribution', 'percentage', 0, 0, 0, 12, true),
  (NULL, 'MALADIE_PAT', 'Assurance maladie (patronale)', 'contribution', 'percentage', 0, 0, 0, 13, true),
  (NULL, 'RETRAITE', 'Retraite (salariale)', 'contribution', 'percentage', 0, 0, 0, 14, true),
  (NULL, 'RETRAITE_PAT', 'Retraite (patronale)', 'contribution', 'percentage', 0, 0, 0, 15, true),
  (NULL, 'CHOMAGE', 'Chômage (salarial)', 'contribution', 'percentage', 0, 0, 0, 16, true),
  (NULL, 'CHOMAGE_PAT', 'Chômage (patronal)', 'contribution', 'percentage', 0, 0, 0, 17, true),
  (NULL, 'CSG_CRDS', 'CSG/CRDS', 'contribution', 'percentage', 0, 0, 0, 18, true),
  (NULL, 'ITS', 'Impôt sur le traitement du salaire', 'tax', 'bracket', 0, 0, 0, 20, true),
  (NULL, 'PAS', 'Prélèvement à la source', 'tax', 'percentage', 0, 0, 0, 21, true),
  (NULL, 'NET', 'Net à payer', 'net', 'formula', 0, 0, 0, 99, true)
ON CONFLICT DO NOTHING;

-- ============================================
-- DONE
-- ============================================
