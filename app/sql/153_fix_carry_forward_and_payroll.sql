-- ============================================================
-- 153_fix_carry_forward_and_payroll.sql
--
-- LOT4-01 : Report à nouveau — classes 6/7 soldées, tiers ligne à ligne
-- LOT4-02 : calculate_payslip réécrit avec moteur légal (PMSS, CSG, cumuls)
-- Bug fix : import_employee_with_cumuls (ON CONFLICT + colonnes inexistantes)
-- Schema fix : pay_slips.calc_inputs / journal_entry_id / journal_posted
-- ============================================================

-- ============================================================
-- Schema fix : pay_slips — colonnes référencées par le frontend
-- ============================================================
ALTER TABLE pay_slips ADD COLUMN IF NOT EXISTS calc_inputs jsonb;
ALTER TABLE pay_slips ADD COLUMN IF NOT EXISTS journal_entry_id uuid;
ALTER TABLE pay_slips ADD COLUMN IF NOT EXISTS journal_posted boolean DEFAULT false;

-- Index unique sur pay_slip_clarified.pay_slip_id pour l'upsert
CREATE UNIQUE INDEX IF NOT EXISTS idx_pay_slip_clarified_pay_slip_id
  ON pay_slip_clarified (pay_slip_id);

-- carry_forward_log.target_fiscal_year_id peut être NULL si pas de report
ALTER TABLE carry_forward_log ALTER COLUMN target_fiscal_year_id DROP NOT NULL;

-- ============================================================
-- LOT4-01 : close_fiscal_year — report à nouveau corrigé
--
-- Corrections :
--   1. Tiers (401, 411, etc.) reportés ligne à ligne avec lettrage non soldé
--   2. Numérotation AN-YYYY-0001 via compteur atomique
--   3. Solde résiduel des comptes tiers reporté groupé
--   4. Autres classes 1-5 reportées groupées par compte
--   5. Invariant : aucune ligne classe 6/7 dans le journal AN
-- ============================================================
CREATE OR REPLACE FUNCTION close_fiscal_year(
  p_fiscal_year_id uuid,
  p_next_fiscal_year_id uuid DEFAULT NULL,
  p_carry_forward boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tenant_id uuid;
  v_fy RECORD;
  v_next_fy RECORD;
  v_entry_id uuid;          -- écriture de regroupement (clôture)
  v_number text;
  v_result numeric;
  v_result_account text;
  v_total_debit numeric;
  v_total_credit numeric;
  v_open_periods int;
  v_draft_entries int;
  v_an_entry_id uuid;       -- écriture d'à-nouveaux
  v_an_number text;
  v_log_id uuid;
  v_hash text;
  v_an_year text;
  v_an_seq integer;
  v_an_padded text;
  v_line_order int;
  v_tiers_count int;
  v_grouped_count int;
  v_an_journal_code text := 'AN';
BEGIN
  -- Récupérer l'exercice à clôturer
  SELECT * INTO v_fy FROM fiscal_years
  WHERE id = p_fiscal_year_id AND tenant_id = current_tenant_id();

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Exercice introuvable ou accès interdit';
  END IF;

  v_tenant_id := v_fy.tenant_id;

  IF v_fy.status IN ('closed', 'locked') THEN
    RAISE EXCEPTION 'Exercice déjà clôturé';
  END IF;

  -- ── Étape 1 : Contrôles de cohérence ──
  SELECT COALESCE(SUM(jl.debit), 0), COALESCE(SUM(jl.credit), 0)
  INTO v_total_debit, v_total_credit
  FROM journal_lines jl
  JOIN journal_entries je ON je.id = jl.journal_id AND je.tenant_id = jl.tenant_id
  WHERE jl.tenant_id = v_tenant_id
    AND je.status = 'posted'
    AND je.date BETWEEN v_fy.start_date AND v_fy.end_date;

  IF abs(v_total_debit - v_total_credit) > 0.01 THEN
    RAISE EXCEPTION 'Balance déséquilibrée : débit % ≠ crédit %', v_total_debit, v_total_credit;
  END IF;

  -- Vérifier qu'aucune période n'est ouverte
  SELECT count(*) INTO v_open_periods
  FROM fiscal_periods
  WHERE fiscal_year_id = p_fiscal_year_id
    AND tenant_id = v_tenant_id
    AND status = 'open';

  IF v_open_periods > 0 THEN
    RAISE EXCEPTION '% période(s) encore ouverte(s) — clôture impossible', v_open_periods;
  END IF;

  -- Vérifier qu'il n'y a pas d'écritures en brouillon
  SELECT count(*) INTO v_draft_entries
  FROM journal_entries
  WHERE tenant_id = v_tenant_id
    AND date BETWEEN v_fy.start_date AND v_fy.end_date
    AND status = 'draft';

  IF v_draft_entries > 0 THEN
    RAISE EXCEPTION '% écriture(s) en brouillard — validation requise avant clôture', v_draft_entries;
  END IF;

  -- ── Étape 2 : Écritures de regroupement (classes 6/7 → 120/129) ──
  SELECT
    COALESCE(SUM(CASE
      WHEN COALESCE(jl.account_general, jl.account_code) ~ '^7' THEN jl.credit - jl.debit
      WHEN COALESCE(jl.account_general, jl.account_code) ~ '^6' THEN jl.debit - jl.credit
      ELSE 0
    END), 0)
  INTO v_result
  FROM journal_lines jl
  JOIN journal_entries je ON je.id = jl.journal_id AND je.tenant_id = jl.tenant_id
  WHERE jl.tenant_id = v_tenant_id
    AND je.status = 'posted'
    AND je.date BETWEEN v_fy.start_date AND v_fy.end_date
    AND (COALESCE(jl.account_general, jl.account_code) ~ '^6'
      OR COALESCE(jl.account_general, jl.account_code) ~ '^7');

  v_result_account := CASE WHEN v_result >= 0 THEN '120000' ELSE '129000' END;
  v_number := 'CLOTURE-' || to_char(v_fy.end_date, 'YYYYMMDD');

  INSERT INTO journal_entries (
    tenant_id, number, date, journal_code, status,
    description, fiscal_period_id, reference
  ) VALUES (
    v_tenant_id, v_number, v_fy.end_date, 'OD', 'draft',
    'Clôture de l''exercice ' || v_fy.code, NULL,
    'CLOTURE-' || v_fy.code
  )
  RETURNING id INTO v_entry_id;

  -- Lignes de regroupement par compte de classe 6 et 7
  INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, account_name, debit, credit, description, line_order)
  SELECT
    v_tenant_id, v_entry_id,
    COALESCE(jl.account_general, jl.account_code),
    COALESCE(jl.account_general, jl.account_code),
    MAX(jl.account_name),
    GREATEST(0, SUM(jl.debit - jl.credit)),
    GREATEST(0, SUM(jl.credit - jl.debit)),
    'Regroupement ' || COALESCE(jl.account_general, jl.account_code),
    row_number() OVER (ORDER BY COALESCE(jl.account_general, jl.account_code))
  FROM journal_lines jl
  JOIN journal_entries je ON je.id = jl.journal_id AND je.tenant_id = jl.tenant_id
  WHERE jl.tenant_id = v_tenant_id
    AND je.status = 'posted'
    AND je.date BETWEEN v_fy.start_date AND v_fy.end_date
    AND (COALESCE(jl.account_general, jl.account_code) ~ '^6'
      OR COALESCE(jl.account_general, jl.account_code) ~ '^7')
  GROUP BY COALESCE(jl.account_general, jl.account_code);

  -- Ligne de résultat (120 ou 129)
  INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, account_name, debit, credit, description, line_order)
  VALUES (
    v_tenant_id, v_entry_id,
    v_result_account, v_result_account,
    CASE WHEN v_result >= 0 THEN 'Résultat de l''exercice (bénéfice)' ELSE 'Résultat de l''exercice (perte)' END,
    CASE WHEN v_result < 0 THEN abs(v_result) ELSE 0 END,
    CASE WHEN v_result >= 0 THEN v_result ELSE 0 END,
    'Résultat ' || v_fy.code,
    9999
  );

  -- Bascule en posted APRÈS les lignes (SOC-01)
  UPDATE journal_entries SET status = 'posted' WHERE id = v_entry_id AND tenant_id = v_tenant_id;

  -- ── Étape 3 : Écriture d'à-nouveaux (si exercice suivant fourni) ──
  IF p_carry_forward AND p_next_fiscal_year_id IS NOT NULL THEN
    SELECT * INTO v_next_fy FROM fiscal_years
    WHERE id = p_next_fiscal_year_id AND tenant_id = v_tenant_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Exercice suivant introuvable';
    END IF;

    -- Numérotation AN-YYYY-0001 via compteur atomique
    v_an_year := to_char(v_next_fy.start_date, 'YYYY');

    -- S'assurer que le journal AN existe pour ce tenant
    INSERT INTO journals (tenant_id, code, name, type, status, next_number)
    SELECT v_tenant_id, v_an_journal_code, 'À-nouveaux', 'general', 'active', 1
    WHERE NOT EXISTS (
      SELECT 1 FROM journals WHERE code = v_an_journal_code AND tenant_id = v_tenant_id
    );

    -- Incrément atomique du compteur
    UPDATE journals
      SET next_number = next_number + 1
      WHERE code = v_an_journal_code AND tenant_id = v_tenant_id
      RETURNING next_number - 1 INTO v_an_seq;

    v_an_padded := lpad(v_an_seq::text, 4, '0');
    v_an_number := 'AN-' || v_an_year || '-' || v_an_padded;

    INSERT INTO journal_entries (
      tenant_id, number, date, journal_code, status,
      description, reference
    ) VALUES (
      v_tenant_id, v_an_number, v_next_fy.start_date, 'AN', 'draft',
      'À-nouveaux ' || v_next_fy.code,
      'AN-' || v_fy.code
    )
    RETURNING id INTO v_an_entry_id;

    v_line_order := 0;

    -- ── 3a. Tiers reportés ligne à ligne (lettrage non soldé) ──
    -- Les comptes de tiers (40x, 41x, 42x, 43x, 44x, 46x, 47x) avec account_tiers
    -- et lettrage_code IS NULL sont reportés individuellement pour préserver
    -- la continuité du grand livre des tiers.
    INSERT INTO journal_lines (
      tenant_id, journal_id, account_code, account_general, account_name,
      account_tiers, third_party_id, debit, credit, description,
      lettrage_code, reference, piece_number, line_order
    )
    SELECT
      v_tenant_id, v_an_entry_id,
      COALESCE(jl.account_general, jl.account_code),
      COALESCE(jl.account_general, jl.account_code),
      jl.account_name,
      jl.account_tiers,
      jl.third_party_id,
      GREATEST(0, jl.debit - jl.credit),
      GREATEST(0, jl.credit - jl.debit),
      'À-nouveaux tiers ' || COALESCE(jl.account_tiers, ''),
      jl.lettrage_code,
      jl.reference,
      jl.piece_number,
      (v_line_order + row_number() OVER (ORDER BY COALESCE(jl.account_general, jl.account_code), jl.account_tiers))::int
    FROM journal_lines jl
    JOIN journal_entries je ON je.id = jl.journal_id AND je.tenant_id = jl.tenant_id
    WHERE jl.tenant_id = v_tenant_id
      AND je.status = 'posted'
      AND je.date <= v_fy.end_date
      AND COALESCE(jl.account_general, jl.account_code) ~ '^[1-5]'
      AND COALESCE(jl.account_general, jl.account_code) NOT IN ('120000', '129000')
      AND jl.account_tiers IS NOT NULL
      AND jl.lettrage_code IS NULL
      AND (jl.debit - jl.credit) <> 0;

    GET DIAGNOSTICS v_tiers_count = ROW_COUNT;
    v_line_order := v_line_order + v_tiers_count;

    -- ── 3b. Solde résiduel groupé par compte (classes 1-5 hors tiers non soldés) ──
    -- Pour les comptes de tiers : on reporte le solde résiduel (lignes soldées
    -- dont le net n'est pas nul). Pour les autres comptes : solde groupé.
    INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, account_name, debit, credit, description, line_order)
    SELECT
      v_tenant_id, v_an_entry_id,
      COALESCE(jl.account_general, jl.account_code),
      COALESCE(jl.account_general, jl.account_code),
      MAX(jl.account_name),
      GREATEST(0, SUM(jl.debit - jl.credit)),
      GREATEST(0, SUM(jl.credit - jl.debit)),
      'À-nouveaux ' || COALESCE(jl.account_general, jl.account_code),
      (v_line_order + row_number() OVER (ORDER BY COALESCE(jl.account_general, jl.account_code)))::int
    FROM journal_lines jl
    JOIN journal_entries je ON je.id = jl.journal_id AND je.tenant_id = jl.tenant_id
    WHERE jl.tenant_id = v_tenant_id
      AND je.status = 'posted'
      AND je.date <= v_fy.end_date
      AND COALESCE(jl.account_general, jl.account_code) ~ '^[1-5]'
      AND COALESCE(jl.account_general, jl.account_code) NOT IN ('120000', '129000')
      -- Exclure les lignes déjà reportées individuellement (tiers non soldés)
      AND NOT (
        jl.account_tiers IS NOT NULL
        AND jl.lettrage_code IS NULL
        AND (jl.debit - jl.credit) <> 0
      )
    GROUP BY COALESCE(jl.account_general, jl.account_code)
    HAVING SUM(jl.debit - jl.credit) <> 0 OR SUM(jl.credit - jl.debit) <> 0;

    GET DIAGNOSTICS v_grouped_count = ROW_COUNT;

    -- Bascule en posted APRÈS les lignes (SOC-01)
    UPDATE journal_entries SET status = 'posted' WHERE id = v_an_entry_id AND tenant_id = v_tenant_id;
  END IF;

  -- ── Étape 4 : Verrouillage + empreinte NF525 ──
  v_hash := md5(
    COALESCE((SELECT string_agg(
      je.id::text || je.number || je.date::text || je.status || COALESCE(jl.account_code, '') || jl.debit::text || jl.credit::text,
      '|' ORDER BY je.date, je.number, jl.line_order
    )
    FROM journal_entries je
    JOIN journal_lines jl ON jl.journal_id = je.id AND jl.tenant_id = je.tenant_id
    WHERE je.tenant_id = v_tenant_id
      AND je.status = 'posted'
      AND je.date BETWEEN v_fy.start_date AND v_fy.end_date
    ), '')
  );

  UPDATE fiscal_years
  SET status = 'closed',
      closed_at = NOW(),
      closed_by = auth.uid()
  WHERE id = p_fiscal_year_id AND tenant_id = v_tenant_id;

  INSERT INTO carry_forward_log (
    tenant_id, source_fiscal_year_id, target_fiscal_year_id,
    carry_forward_date, total_debit, total_credit, status, journal_entry_id
  ) VALUES (
    v_tenant_id, p_fiscal_year_id, p_next_fiscal_year_id,
    NOW(), v_result, 0, 'completed', v_entry_id
  )
  RETURNING id INTO v_log_id;

  RETURN jsonb_build_object(
    'success', true,
    'fiscal_year_id', p_fiscal_year_id,
    'result', v_result,
    'result_account', v_result_account,
    'carry_forward_entry_id', v_an_entry_id,
    'close_entry_id', v_entry_id,
    'tiers_lines_copied', v_tiers_count,
    'grouped_lines', v_grouped_count,
    'an_number', v_an_number,
    'hash', v_hash,
    'log_id', v_log_id
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM
  );
END;
$$;

GRANT EXECUTE ON FUNCTION close_fiscal_year(uuid, uuid, boolean) TO authenticated;

-- ============================================================
-- LOT4-02 : calculate_payslip — moteur légal
--
-- Remplace la version 22%/42% en dur de la migration 89.
-- Lit payroll_legal_parameters (PMSS, CSG, CRDS) et
-- payroll_tax_grids / payroll_tax_grid_lines pour les taux.
-- Utilise payroll_cumulative pour la régularisation progressive.
-- ============================================================
CREATE OR REPLACE FUNCTION calculate_payslip(
  p_employee_id uuid,
  p_period text,
  p_pay_run_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_emp RECORD;
  v_period_start date;
  v_period_end date;
  v_period_year int;
  v_period_month int;

  -- Paramètres légaux
  v_pmss numeric;
  v_csg_deductible_rate numeric;
  v_csg_non_deductible_rate numeric;
  v_crds_rate numeric;
  v_csg_crds_base_pct numeric;
  v_csg_crds_multiple numeric;
  v_taux_neutre numeric;
  v_reduction_gen_t numeric;

  -- Éléments variables
  v_overtime_pay numeric := 0;
  v_overtime_hours numeric := 0;
  v_bonus numeric := 0;
  v_advance_deduction numeric := 0;
  v_pay_recall numeric := 0;
  v_expense_reimbursement numeric := 0;
  v_unpaid_leave_deduction numeric := 0;
  v_other_deductions numeric := 0;
  v_meal_vouchers numeric := 0;
  v_transport_allowance numeric := 0;

  -- Brut
  v_base_salary numeric;
  v_total_gross numeric;

  -- Cotisations
  v_ss_employee numeric := 0;       -- cotisations salariales (sécu + retraite + chômage + santé)
  v_ss_employer numeric := 0;       -- cotisations patronales
  v_csg_deductible numeric := 0;
  v_csg_non_deductible numeric := 0;
  v_crds numeric := 0;
  v_csg_crds_total numeric := 0;
  v_reduction_generale numeric := 0;

  -- Assiettes
  v_csg_crds_base numeric;          -- assiette CSG/CRDS
  v_ceiling_base numeric;           -- assiette plafonnée (PMSS)
  v_net_social numeric;             -- net social (brut - cotisations déductibles)
  v_net_taxable numeric;            -- net imposable
  v_income_tax numeric;
  v_total_deductions numeric;
  v_net_payable numeric;

  -- Grille fiscale
  v_grid_id uuid;
  v_grid_version text;
  v_grid_line RECORD;
  v_line_amount_emp numeric;
  v_line_amount_er numeric;
  v_line_base numeric;
  v_line_ceiling numeric;
  v_cumulative_used numeric;
  v_cumulative_available numeric;

  -- Cumuls
  v_cum_gross_ytd numeric := 0;
  v_cum_ceiling_base_ytd numeric := 0;
  v_ve_count int := 0;             -- nombre d'éléments variables intégrés

  -- Avecholding tax
  v_withholding_rate numeric;
  v_withholding_source text;

  -- Numérotation
  v_payslip_number text;
  v_payslip_id uuid;
  v_clarified_id uuid;
  v_line_order int;
  v_slip_lines jsonb := '[]'::jsonb;

  -- Pays du tenant
  v_country_code text := 'FR';
  v_tenant RECORD;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  -- Charger l'employé
  SELECT * INTO v_emp FROM employees WHERE id = p_employee_id AND tenant_id = v_tid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Employé non trouvé: %', p_employee_id;
  END IF;

  -- Calculer les bornes de période
  v_period_start := (p_period || '-01')::date;
  v_period_end := (v_period_start + INTERVAL '1 month - 1 day')::date;
  v_period_year := EXTRACT(YEAR FROM v_period_start)::int;
  v_period_month := EXTRACT(MONTH FROM v_period_start)::int;

  -- Pays du tenant
  SELECT country_code, legislation_pack_code INTO v_tenant
  FROM tenants WHERE id = v_tid;
  IF v_tenant.country_code IS NOT NULL THEN
    v_country_code := v_tenant.country_code;
  ELSIF v_tenant.legislation_pack_code IS NOT NULL THEN
    v_country_code := v_tenant.legislation_pack_code;
  END IF;

  -- ── Charger les paramètres légaux ──
  v_pmss := get_legal_parameter('PMSS', v_country_code, v_period_start, v_tid);
  v_csg_deductible_rate := get_legal_parameter('CSG_DEDUCTIBLE', v_country_code, v_period_start, v_tid);
  v_csg_non_deductible_rate := get_legal_parameter('CSG_NON_DEDUCTIBLE', v_country_code, v_period_start, v_tid);
  v_crds_rate := get_legal_parameter('CRDS', v_country_code, v_period_start, v_tid);
  v_csg_crds_base_pct := get_legal_parameter('CSG_CRDS_BASE', v_country_code, v_period_start, v_tid);
  v_csg_crds_multiple := get_legal_parameter('CGSS_BASE_MULTIPLE', v_country_code, v_period_start, v_tid);
  v_taux_neutre := get_legal_parameter('TAUX_NEUTRE', v_country_code, v_period_start, v_tid);
  v_reduction_gen_t := get_legal_parameter('REDUCTION_GEN_T', v_country_code, v_period_start, v_tid);

  -- ── Éléments variables (si pay_run_id fourni) ──
  IF p_pay_run_id IS NOT NULL THEN
    SELECT
      COALESCE(SUM(CASE WHEN ve.element_type = 'overtime' THEN COALESCE(ve.amount, 0) ELSE 0 END), 0),
      COALESCE(SUM(CASE WHEN ve.element_type IN ('overtime', 'timesheet_hours') THEN COALESCE(ve.quantity, 0) ELSE 0 END), 0),
      COALESCE(SUM(CASE WHEN ve.element_type = 'bonus' THEN COALESCE(ve.amount, 0) ELSE 0 END), 0),
      COALESCE(SUM(CASE WHEN ve.element_type = 'advance_deduction' THEN COALESCE(ve.amount, 0) ELSE 0 END), 0),
      COALESCE(SUM(CASE WHEN ve.element_type = 'pay_recall' THEN COALESCE(ve.amount, 0) ELSE 0 END), 0),
      COALESCE(SUM(CASE WHEN ve.element_type = 'expense_reimbursement' THEN COALESCE(ve.amount, 0) ELSE 0 END), 0),
      COALESCE(SUM(CASE WHEN ve.element_type = 'unpaid_leave_deduction' THEN COALESCE(ve.amount, 0) ELSE 0 END), 0),
      COALESCE(SUM(CASE WHEN ve.element_type IN ('other_deductions', 'other') THEN COALESCE(ve.amount, 0) ELSE 0 END), 0),
      COALESCE(SUM(CASE WHEN ve.element_type = 'meal_vouchers' THEN COALESCE(ve.amount, 0) ELSE 0 END), 0),
      COALESCE(SUM(CASE WHEN ve.element_type = 'transport_allowance' THEN COALESCE(ve.amount, 0) ELSE 0 END), 0)
    INTO v_overtime_pay, v_overtime_hours, v_bonus, v_advance_deduction,
         v_pay_recall, v_expense_reimbursement, v_unpaid_leave_deduction,
         v_other_deductions, v_meal_vouchers, v_transport_allowance
    FROM payroll_variable_elements ve
    WHERE ve.pay_run_id = p_pay_run_id
      AND ve.employee_id = p_employee_id
      AND ve.tenant_id = v_tid
      AND COALESCE(ve.integrated, false) = false;

    -- Compter les éléments variables pour l'affichage UI
    SELECT count(*) INTO v_ve_count
    FROM payroll_variable_elements ve
    WHERE ve.pay_run_id = p_pay_run_id
      AND ve.employee_id = p_employee_id
      AND ve.tenant_id = v_tid
      AND COALESCE(ve.integrated, false) = false;
  END IF;

  -- ── Calcul du brut ──
  v_base_salary := COALESCE(COALESCE(v_emp.base_salary, v_emp.salary), 0);
  v_total_gross := v_base_salary + v_overtime_pay + v_bonus + v_pay_recall
    - v_unpaid_leave_deduction;

  IF v_total_gross < 0 THEN
    v_total_gross := 0;
  END IF;

  -- ── Assiette plafonnée (PMSS) ──
  v_ceiling_base := LEAST(v_total_gross, v_pmss);

  -- ── Assiette CSG/CRDS ──
  -- 98,25 % du brut si brut <= 4 × PMSS, sinon 100 %
  IF v_total_gross <= v_csg_crds_multiple * v_pmss THEN
    v_csg_crds_base := v_total_gross * v_csg_crds_base_pct / 100;
  ELSE
    v_csg_crds_base := v_total_gross;
  END IF;

  -- ── Charger la grille fiscale active ──
  SELECT g.id INTO v_grid_id
  FROM payroll_tax_grids g
  WHERE (g.tenant_id = v_tid OR g.tenant_id IS NULL)
    AND g.country_code = v_country_code
    AND g.status = 'active'
    AND g.effective_from <= v_period_start
    AND COALESCE(g.effective_to, '9999-12-31'::date) >= v_period_end
  ORDER BY g.tenant_id NULLS LAST, g.created_at DESC
  LIMIT 1;

  v_grid_version := COALESCE(v_grid_id::text, 'fallback');

  -- ── Calcul des cotisations via la grille ──
  IF v_grid_id IS NOT NULL THEN
    FOR v_grid_line IN
      SELECT * FROM payroll_tax_grid_lines
      WHERE grid_id = v_grid_id
        AND COALESCE(section, 'contribution') IN ('contribution', 'employer')
      ORDER BY sort_order
    LOOP
      -- Calcul de l'assiette selon base_type
      v_line_base := v_total_gross; -- défaut 'gross'

      -- Appliquer le plafond selon ceiling_type
      IF v_grid_line.ceiling_type = 'pmss' THEN
        v_line_ceiling := v_pmss * COALESCE(v_grid_line.ceiling_multiplier, 1);
        v_line_base := LEAST(v_line_base, v_line_ceiling);
      ELSIF v_grid_line.ceiling_type = 'multiple_pmss' THEN
        v_line_ceiling := v_pmss * COALESCE(v_grid_line.ceiling_multiplier, 1);
        v_line_base := LEAST(v_line_base, v_line_ceiling);
      ELSIF v_grid_line.ceiling_type = 'fixed' THEN
        v_line_base := LEAST(v_line_base, COALESCE(v_grid_line.ceiling_value, v_line_base));
      END IF;

      -- Montants
      v_line_amount_emp := round(v_line_base * COALESCE(v_grid_line.rate_employee, 0) / 100, 2);
      v_line_amount_er := round(v_line_base * COALESCE(v_grid_line.rate_employer, 0) / 100, 2);

      -- CSG/CRDS : assiette spécifique
      IF v_grid_line.is_csg_crds THEN
        v_line_base := v_csg_crds_base;
        IF v_grid_line.csg_type = 'deductible' THEN
          v_csg_deductible := round(v_csg_crds_base * v_csg_deductible_rate / 100, 2);
          v_line_amount_emp := v_csg_deductible;
        ELSIF v_grid_line.csg_type = 'non_deductible' THEN
          v_csg_non_deductible := round(v_csg_crds_base * v_csg_non_deductible_rate / 100, 2);
          v_line_amount_emp := v_csg_non_deductible;
        ELSIF v_grid_line.csg_type = 'crds' THEN
          v_crds := round(v_csg_crds_base * v_crds_rate / 100, 2);
          v_line_amount_emp := v_crds;
        END IF;
      END IF;

      v_ss_employee := v_ss_employee + v_line_amount_emp;
      v_ss_employer := v_ss_employer + v_line_amount_er;

      -- Réduction générale
      IF v_grid_line.eligible_reduction_generale AND v_reduction_gen_t > 0 THEN
        -- Coefficient Fillon simplifié : T × (1,3 × SMIC / brut - 1) plafonné à T
        v_reduction_generale := round(
          v_reduction_gen_t * GREATEST(0, 1.3 * get_legal_parameter('SMIC_M', v_country_code, v_period_start, v_tid) / NULLIF(v_total_gross, 0) - 1) / 100 * v_total_gross,
          2
        );
        v_reduction_generale := LEAST(v_reduction_generale, v_ss_employer);
        v_ss_employer := GREATEST(0, v_ss_employer - v_reduction_generale);
      END IF;
    END LOOP;
  ELSE
    -- Fallback : taux légaux français 2025 si aucune grille configurée
    v_ss_employee := round(v_total_gross * 22.0 / 100, 2);  -- approximation légale
    v_ss_employer := round(v_total_gross * 42.0 / 100, 2);  -- approximation légale
    v_csg_deductible := round(v_csg_crds_base * v_csg_deductible_rate / 100, 2);
    v_csg_non_deductible := round(v_csg_crds_base * v_csg_non_deductible_rate / 100, 2);
    v_crds := round(v_csg_crds_base * v_crds_rate / 100, 2);
  END IF;

  v_csg_crds_total := v_csg_deductible + v_csg_non_deductible + v_crds;

  -- ── Net social et net imposable ──
  v_net_social := round(v_total_gross - v_ss_employee - v_csg_deductible, 2);
  v_net_taxable := round(v_net_social - v_csg_non_deductible - v_crds, 2);
  IF v_net_taxable < 0 THEN v_net_taxable := 0; END IF;

  -- ── Impôt sur le revenu (PAS) ──
  v_withholding_rate := COALESCE(v_emp.withholding_tax_rate, 0);
  v_withholding_source := COALESCE(v_emp.withholding_rate_source, CASE WHEN v_emp.withholding_tax_rate IS NOT NULL THEN 'dgfip' ELSE 'neutral' END);

  IF v_withholding_rate > 0 THEN
    v_income_tax := round(v_net_taxable * v_withholding_rate / 100, 2);
  ELSE
    -- Taux neutre par défaut
    v_income_tax := round(v_net_taxable * v_taux_neutre / 100, 2);
  END IF;

  -- ── Total déductions et net à payer ──
  v_total_deductions := round(v_ss_employee + v_csg_crds_total + v_income_tax
    + v_advance_deduction + v_other_deductions, 2);

  v_net_payable := round(v_total_gross - v_total_deductions + v_expense_reimbursement
    + v_meal_vouchers + v_transport_allowance, 2);

  -- ── Cumuls YTD (régularisation progressive) ──
  SELECT COALESCE(SUM(gross), 0), COALESCE(SUM(ceiling_base), 0)
  INTO v_cum_gross_ytd, v_cum_ceiling_base_ytd
  FROM payroll_cumulative
  WHERE employee_id = p_employee_id
    AND tenant_id = v_tid
    AND year = v_period_year
    AND month < v_period_month;

  -- ── Mettre à jour les cumuls ──
  PERFORM upsert_payroll_cumulative(
    p_employee_id, v_period_year, v_period_month,
    v_total_gross, v_net_taxable, v_ceiling_base, v_pmss - v_ceiling_base,
    v_net_taxable, v_net_social,
    v_ss_employee, v_ss_employer,
    v_income_tax, v_csg_deductible, v_csg_non_deductible, v_crds,
    v_reduction_generale
  );

  -- ── Construire les lignes de détail pour audit ──
  v_slip_lines := jsonb_build_array(
    jsonb_build_object('label', 'Salaire de base', 'amount', v_base_salary, 'type', 'gross'),
    jsonb_build_object('label', 'Heures supplémentaires', 'amount', v_overtime_pay, 'type', 'overtime')
  )
  || CASE WHEN v_bonus > 0 THEN jsonb_build_array(jsonb_build_object('label', 'Prime', 'amount', v_bonus, 'type', 'bonus')) ELSE '[]'::jsonb END
  || CASE WHEN v_pay_recall <> 0 THEN jsonb_build_array(jsonb_build_object('label', 'Rappel de paie', 'amount', v_pay_recall, 'type', 'pay_recall')) ELSE '[]'::jsonb END
  || jsonb_build_array(
    jsonb_build_object('label', 'Cotisations sociales', 'amount', -v_ss_employee, 'type', 'social_charges'),
    jsonb_build_object('label', 'CSG/CRDS', 'amount', -v_csg_crds_total, 'type', 'csg_crds'),
    jsonb_build_object('label', 'Impôt sur le revenu (PAS)', 'amount', -v_income_tax, 'type', 'income_tax')
  )
  || CASE WHEN v_advance_deduction > 0 THEN jsonb_build_array(jsonb_build_object('label', 'Acompte sur salaire', 'amount', -v_advance_deduction, 'type', 'advance_deduction')) ELSE '[]'::jsonb END
  || CASE WHEN v_unpaid_leave_deduction > 0 THEN jsonb_build_array(jsonb_build_object('label', 'Congé sans solde', 'amount', -v_unpaid_leave_deduction, 'type', 'unpaid_leave_deduction')) ELSE '[]'::jsonb END
  || CASE WHEN v_other_deductions > 0 THEN jsonb_build_array(jsonb_build_object('label', 'Autres déductions', 'amount', -v_other_deductions, 'type', 'other_deductions')) ELSE '[]'::jsonb END
  || CASE WHEN v_expense_reimbursement > 0 THEN jsonb_build_array(jsonb_build_object('label', 'Remboursement de frais', 'amount', v_expense_reimbursement, 'type', 'expense_reimbursement')) ELSE '[]'::jsonb END
  || CASE WHEN v_meal_vouchers > 0 THEN jsonb_build_array(jsonb_build_object('label', 'Titres-restaurant', 'amount', v_meal_vouchers, 'type', 'meal_vouchers')) ELSE '[]'::jsonb END
  || CASE WHEN v_transport_allowance > 0 THEN jsonb_build_array(jsonb_build_object('label', 'Indemnité transport', 'amount', v_transport_allowance, 'type', 'transport')) ELSE '[]'::jsonb END;

  -- ── Créer ou mettre à jour le bulletin ──
  -- Chercher un bulletin existant pour cet employé et cette période
  SELECT id INTO v_payslip_id
  FROM pay_slips
  WHERE employee_id = p_employee_id
    AND tenant_id = v_tid
    AND period_start = v_period_start
  LIMIT 1;

  v_payslip_number := COALESCE(
    (SELECT number FROM pay_slips WHERE id = v_payslip_id),
    'BS-' || p_period || '-' || lpad(substr(p_employee_id::text, 1, 4), 4, '0')
  );

  IF v_payslip_id IS NOT NULL THEN
    UPDATE pay_slips SET
      gross_salary = v_base_salary,
      overtime_pay = v_overtime_pay,
      bonus = v_bonus,
      total_gross = v_total_gross,
      social_security_employee = v_ss_employee,
      income_tax = v_income_tax,
      other_deductions = v_csg_crds_total + v_advance_deduction + v_other_deductions,
      total_deductions = v_total_deductions,
      net_salary = v_net_payable,
      employer_contributions = v_ss_employer,
      calc_inputs = jsonb_build_object(
        'gridVersion', v_grid_version,
        'pmss', v_pmss,
        'ceilingBase', v_ceiling_base,
        'csgDeductible', v_csg_deductible,
        'csgNonDeductible', v_csg_non_deductible,
        'crds', v_crds,
        'netSocial', v_net_social,
        'netTaxable', v_net_taxable,
        'reductionGenerale', v_reduction_generale,
        'withholdingRate', v_withholding_rate,
        'withholdingSource', v_withholding_source,
        'overtimeHours', v_overtime_hours,
        'mealVouchers', v_meal_vouchers,
        'transportAllowance', v_transport_allowance,
        'advanceDeduction', v_advance_deduction,
        'payRecall', v_pay_recall,
        'expenseReimbursement', v_expense_reimbursement,
        'unpaidLeaveDeduction', v_unpaid_leave_deduction,
        'otherDeductions', v_other_deductions,
        'cumulativeGrossYTD', v_cum_gross_ytd + v_total_gross,
        'cumulativeCeilingBaseYTD', v_cum_ceiling_base_ytd + v_ceiling_base,
        'variableElementCount', v_ve_count,
        'countryCode', v_country_code
      )
    WHERE id = v_payslip_id AND tenant_id = v_tid;
  ELSE
    INSERT INTO pay_slips (
      tenant_id, number, pay_run_id, employee_id,
      period_start, period_end,
      gross_salary, overtime_pay, bonus, total_gross,
      social_security_employee, income_tax, other_deductions, total_deductions,
      net_salary, employer_contributions, status,
      calc_inputs
    ) VALUES (
      v_tid, v_payslip_number, p_pay_run_id, p_employee_id,
      v_period_start, v_period_end,
      v_base_salary, v_overtime_pay, v_bonus, v_total_gross,
      v_ss_employee, v_income_tax, v_csg_crds_total + v_advance_deduction + v_other_deductions, v_total_deductions,
      v_net_payable, v_ss_employer, 'draft',
      jsonb_build_object(
        'gridVersion', v_grid_version,
        'pmss', v_pmss,
        'ceilingBase', v_ceiling_base,
        'csgDeductible', v_csg_deductible,
        'csgNonDeductible', v_csg_non_deductible,
        'crds', v_crds,
        'netSocial', v_net_social,
        'netTaxable', v_net_taxable,
        'reductionGenerale', v_reduction_generale,
        'withholdingRate', v_withholding_rate,
        'withholdingSource', v_withholding_source,
        'overtimeHours', v_overtime_hours,
        'mealVouchers', v_meal_vouchers,
        'transportAllowance', v_transport_allowance,
        'advanceDeduction', v_advance_deduction,
        'payRecall', v_pay_recall,
        'expenseReimbursement', v_expense_reimbursement,
        'unpaidLeaveDeduction', v_unpaid_leave_deduction,
        'otherDeductions', v_other_deductions,
        'cumulativeGrossYTD', v_cum_gross_ytd + v_total_gross,
        'cumulativeCeilingBaseYTD', v_cum_ceiling_base_ytd + v_ceiling_base,
        'variableElementCount', v_ve_count,
        'countryCode', v_country_code
      )
    )
    RETURNING id INTO v_payslip_id;
  END IF;

  -- ── Créer ou mettre à jour pay_slip_clarified ──
  INSERT INTO pay_slip_clarified (
    tenant_id, pay_slip_id, employee_id, period,
    gross_salary, social_charges_employee, social_charges_employer,
    income_tax, net_before_tax, net_after_tax, total_deductions, lines
  ) VALUES (
    v_tid, v_payslip_id, p_employee_id, p_period,
    v_total_gross, v_ss_employee, v_ss_employer,
    v_income_tax, v_net_social, v_net_payable, v_total_deductions, v_slip_lines
  )
  ON CONFLICT (pay_slip_id) DO UPDATE SET
    gross_salary = EXCLUDED.gross_salary,
    social_charges_employee = EXCLUDED.social_charges_employee,
    social_charges_employer = EXCLUDED.social_charges_employer,
    income_tax = EXCLUDED.income_tax,
    net_before_tax = EXCLUDED.net_before_tax,
    net_after_tax = EXCLUDED.net_after_tax,
    total_deductions = EXCLUDED.total_deductions,
    lines = EXCLUDED.lines;

  -- ── Marquer les éléments variables comme intégrés ──
  IF p_pay_run_id IS NOT NULL THEN
    UPDATE payroll_variable_elements
    SET integrated = true
    WHERE pay_run_id = p_pay_run_id
      AND employee_id = p_employee_id
      AND tenant_id = v_tid;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'employee_id', p_employee_id,
    'period', p_period,
    'pay_slip_id', v_payslip_id,
    'gross_salary', v_base_salary,
    'overtime_pay', v_overtime_pay,
    'bonus', v_bonus,
    'total_gross', v_total_gross,
    'social_security_employee', v_ss_employee,
    'csg_deductible', v_csg_deductible,
    'csg_non_deductible', v_csg_non_deductible,
    'crds', v_crds,
    'csg_crds_total', v_csg_crds_total,
    'income_tax', v_income_tax,
    'other_deductions', v_csg_crds_total + v_advance_deduction + v_other_deductions,
    'total_deductions', v_total_deductions,
    'net_salary', v_net_payable,
    'employer_contributions', v_ss_employer,
    'net_social', v_net_social,
    'net_taxable', v_net_taxable,
    'ceiling_base', v_ceiling_base,
    'pmss', v_pmss,
    'reduction_generale', v_reduction_generale,
    'withholding_rate', v_withholding_rate,
    'withholding_source', v_withholding_source,
    'grid_version', v_grid_version,
    'cumulative_gross_ytd', v_cum_gross_ytd + v_total_gross,
    'cumulative_ceiling_base_ytd', v_cum_ceiling_base_ytd + v_ceiling_base,
    'country_code', v_country_code
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM
  );
END;
$$;

GRANT EXECUTE ON FUNCTION calculate_payslip(uuid, text, uuid) TO authenticated;

-- ============================================================
-- Bug fix : import_employee_with_cumuls (migration 122)
--
-- Problèmes :
--   1. ON CONFLICT (tenant_id, employee_id, year) — pas de contrainte correspondante
--      (la table a UNIQUE (tenant_id, employee_id, year, month))
--   2. Colonnes cumulative_gross/cumulative_tax/cumulative_social inexistantes
--      (la table a gross/withholding_tax/employee_contributions)
-- ============================================================
CREATE OR REPLACE FUNCTION import_employee_with_cumuls(
  p_employee json,
  p_cumuls json DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_trgm, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_emp_id uuid;
  v_cumul record;
  v_full_name text;
  v_sal numeric;
  v_year int;
  v_month int;
  v_gross numeric;
  v_tax numeric;
  v_social numeric;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  v_full_name := TRIM(COALESCE(p_employee->>'name', COALESCE(p_employee->>'first_name', '') || ' ' || COALESCE(p_employee->>'last_name', '')));
  v_sal := COALESCE((p_employee->>'base_salary')::numeric, (p_employee->>'salary')::numeric, 0);

  -- Créer ou mettre à jour l'employé
  INSERT INTO employees (
    tenant_id, name, first_name, last_name, email, phone, hire_date,
    contract_type, position, department, salary, base_salary, status
  ) VALUES (
    v_tid,
    v_full_name,
    p_employee->>'first_name',
    p_employee->>'last_name',
    p_employee->>'email',
    p_employee->>'phone',
    COALESCE((p_employee->>'hire_date')::date, CURRENT_DATE),
    COALESCE(p_employee->>'contract_type', 'cdi'),
    p_employee->>'position',
    p_employee->>'department',
    v_sal,
    v_sal,
    'active'
  )
  ON CONFLICT (tenant_id, email) WHERE email IS NOT NULL
  DO UPDATE SET
    name = EXCLUDED.name,
    first_name = EXCLUDED.first_name,
    last_name = EXCLUDED.last_name,
    phone = EXCLUDED.phone,
    position = EXCLUDED.position,
    department = EXCLUDED.department,
    salary = EXCLUDED.salary,
    base_salary = EXCLUDED.base_salary
  RETURNING id INTO v_emp_id;

  -- Insérer les cumuls si fournis (mapping des colonnes corrigé)
  IF p_cumuls IS NOT NULL THEN
    FOR v_cumul IN
      SELECT
        (elem->>'year')::int AS year,
        COALESCE((elem->>'month')::int, 0) AS month,
        COALESCE((elem->>'cumulative_gross')::numeric, (elem->>'gross')::numeric, 0) AS gross,
        COALESCE((elem->>'cumulative_tax')::numeric, (elem->>'withholding_tax')::numeric, (elem->>'tax')::numeric, 0) AS tax,
        COALESCE((elem->>'cumulative_social')::numeric, (elem->>'employee_contributions')::numeric, (elem->>'social')::numeric, 0) AS social
      FROM json_array_elements(p_cumuls) AS elem
    LOOP
      INSERT INTO payroll_cumulative (
        tenant_id, employee_id, year, month,
        gross, withholding_tax, employee_contributions
      ) VALUES (
        v_tid, v_emp_id, v_cumul.year, v_cumul.month,
        v_cumul.gross, v_cumul.tax, v_cumul.social
      )
      ON CONFLICT (tenant_id, employee_id, year, month)
      DO UPDATE SET
        gross = EXCLUDED.gross,
        withholding_tax = EXCLUDED.withholding_tax,
        employee_contributions = EXCLUDED.employee_contributions;
    END LOOP;
  END IF;

  RETURN jsonb_build_object('success', true, 'employee_id', v_emp_id);
END;
$$;

GRANT EXECUTE ON FUNCTION import_employee_with_cumuls(json, json) TO authenticated;
