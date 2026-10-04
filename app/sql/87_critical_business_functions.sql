-- ============================================================
-- 87_critical_business_functions.sql
--
-- Fonctions SQL métier critiques manquantes, inspirées des
-- leaders du marché (PayFit, Silae, Sage, Pennylane, Odoo).
--
-- 7 fonctions critiques :
--   1. calculate_payslip()        — Calcul brut→net (PayFit/Silae)
--   2. generate_dsn()             — Génération DSN (Silae/PayFit)
--   3. calculate_vat_ca3()        — Calcul TVA CA3 (Pennylane/Sage)
--   4. generate_vat_return()      — Déclaration TVA (Pennylane/Sage)
--   5. generate_balance_sheet()   — Bilan comptable (Sage/Odoo)
--   6. generate_profit_loss()     — Compte de résultat (Sage/Odoo)
--   7. close_fiscal_year()        — Clôture annuelle (Sage/Odoo)
--
-- Toutes les fonctions utilisent current_tenant_id() pour
-- l'isolation multi-tenant et SECURITY DEFINER avec search_path.
-- ============================================================

-- ============================================================
-- 1. calculate_payslip(p_employee_id, p_period)
--    Inspiré de : PayFit, Silae, Gusto, Rippling
--    Calcule le brut→net en intégrant les éléments variables,
--    les charges sociales (grilles fiscales) et le PAS (impôt).
-- ============================================================
CREATE OR REPLACE FUNCTION calculate_payslip(
  p_employee_id uuid,
  p_period text  -- format 'YYYY-MM'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_emp RECORD;
  v_pay_run_id uuid;
  v_period_start date;
  v_period_end date;
  v_base_salary numeric := 0;
  v_overtime_pay numeric := 0;
  v_bonus numeric := 0;
  v_total_gross numeric := 0;
  v_social_security_employee numeric := 0;
  v_social_security_employer numeric := 0;
  v_income_tax numeric := 0;
  v_other_deductions numeric := 0;
  v_total_deductions numeric := 0;
  v_net_salary numeric := 0;
  v_var RECORD;
  v_grid RECORD;
  v_grid_line RECORD;
  v_pas_rate numeric := 0;
  v_at_rate numeric := 0;
  v_result jsonb;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  -- Récupérer l'employé
  SELECT * INTO v_emp
  FROM employees
  WHERE id = p_employee_id AND tenant_id = v_tid;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Employé non trouvé: %', p_employee_id;
  END IF;

  -- Calculer les dates de la période
  v_period_start := (p_period || '-01')::date;
  v_period_end := (v_period_start + INTERVAL '1 month' - INTERVAL '1 day')::date;

  -- Trouver le pay_run de la période
  SELECT id INTO v_pay_run_id
  FROM pay_runs
  WHERE tenant_id = v_tid
    AND to_char(period_start, 'YYYY-MM') = p_period
  ORDER BY created_at DESC
  LIMIT 1;

  -- Salaire de base (mensuel)
  v_base_salary := COALESCE(v_emp.salary, 0);

  -- Intégrer les éléments variables (heures supp, primes, indemnités, etc.)
  FOR v_var IN
    SELECT * FROM payroll_variable_elements
    WHERE tenant_id = v_tid
      AND employee_id = p_employee_id
      AND period = p_period
  LOOP
    IF v_var.element_type IN ('overtime', 'overtime_pay') THEN
      v_overtime_pay := v_overtime_pay + COALESCE(v_var.amount, 0);
    ELSIF v_var.element_type IN ('bonus', 'prime', 'commission') THEN
      v_bonus := v_bonus + COALESCE(v_var.amount, 0);
    ELSIF v_var.element_type IN ('advance_deduction', 'unpaid_leave_deduction', 'loan_deduction') THEN
      v_other_deductions := v_other_deductions + COALESCE(v_var.amount, 0);
    ELSIF v_var.element_type IN ('expense_reimbursement', 'expense_refund') THEN
      -- Les remboursements de notes de frais ne sont pas soumis à charges
      NULL;
    END IF;
  END LOOP;

  -- Salaire brut total
  v_total_gross := v_base_salary + v_overtime_pay + v_bonus;

  -- Calcul des charges sociales via la grille fiscale
  SELECT * INTO v_grid
  FROM payroll_tax_grids
  WHERE tenant_id = v_tid
    AND grid_type = 'social_charges'
    AND status = 'active'
    AND (effective_to IS NULL OR effective_to >= v_period_end)
  ORDER BY effective_from DESC
  LIMIT 1;

  IF FOUND THEN
    FOR v_grid_line IN
      SELECT * FROM payroll_tax_grid_lines
      WHERE grid_id = v_grid.id
        AND (min_amount IS NULL OR v_total_gross >= min_amount)
        AND (max_amount IS NULL OR v_total_gross <= max_amount)
      ORDER BY sort_order
    LOOP
      IF v_grid_line.rate_employee IS NOT NULL AND v_grid_line.rate_employee > 0 THEN
        v_social_security_employee := v_social_security_employee
          + (v_total_gross * v_grid_line.rate_employee / 100);
      END IF;
      IF v_grid_line.rate_employer IS NOT NULL AND v_grid_line.rate_employer > 0 THEN
        v_social_security_employer := v_social_security_employer
          + (v_total_gross * v_grid_line.rate_employer / 100);
      END IF;
    END LOOP;
  ELSE
    -- Taux par défaut France 2024-2025 (approximatifs)
    -- Cotisations salariales ~22% (sécu, retraite, chômage, CSG/CRDS)
    -- Cotisations patronales ~42% (sécu, retraite, chômage, AT/MP, formation)
    v_social_security_employee := v_total_gross * 0.22;
    v_social_security_employer := v_total_gross * 0.42;
  END IF;

  -- Prélèvement à la source (PAS)
  SELECT rate INTO v_pas_rate
  FROM pas_rates
  WHERE tenant_id = v_tid
    AND (employee_id = p_employee_id OR employee_id IS NULL)
    AND effective_date <= v_period_end
    AND (expiry_date IS NULL OR expiry_date >= v_period_start)
  ORDER BY employee_id NULLS LAST, effective_date DESC
  LIMIT 1;

  IF v_pas_rate IS NULL THEN
    v_pas_rate := 0;  -- Taux neutre par défaut = 0 (à configurer)
  END IF;

  -- Base imposable = brut - cotisations sociales déductibles
  v_income_tax := (v_total_gross - v_social_security_employee) * v_pas_rate / 100;

  -- Total des déductions
  v_total_deductions := v_social_security_employee + v_income_tax + v_other_deductions;

  -- Net à payer
  v_net_salary := v_total_gross - v_total_deductions;

  -- Construire le résultat
  v_result := jsonb_build_object(
    'employee_id', p_employee_id,
    'employee_name', v_emp.position,
    'period', p_period,
    'period_start', v_period_start,
    'period_end', v_period_end,
    'pay_run_id', v_pay_run_id,
    'base_salary', round(v_base_salary, 2),
    'overtime_pay', round(v_overtime_pay, 2),
    'bonus', round(v_bonus, 2),
    'total_gross', round(v_total_gross, 2),
    'social_security_employee', round(v_social_security_employee, 2),
    'social_security_employer', round(v_social_security_employer, 2),
    'income_tax', round(v_income_tax, 2),
    'other_deductions', round(v_other_deductions, 2),
    'total_deductions', round(v_total_deductions, 2),
    'net_salary', round(v_net_salary, 2),
    'pas_rate', v_pas_rate,
    'calculated_at', now()
  );

  -- Mettre à jour ou créer le bulletin de paie
  INSERT INTO pay_slips (
    tenant_id, number, pay_run_id, employee_id,
    period_start, period_end,
    gross_salary, overtime_pay, bonus, total_gross,
    social_security_employee, income_tax, other_deductions,
    total_deductions, net_salary, employer_contributions,
    status
  ) VALUES (
    v_tid,
    'PS-' || p_period || '-' || substr(p_employee_id::text, 1, 8),
    v_pay_run_id, p_employee_id,
    v_period_start, v_period_end,
    v_base_salary, v_overtime_pay, v_bonus, v_total_gross,
    v_social_security_employee, v_income_tax, v_other_deductions,
    v_total_deductions, v_net_salary, v_social_security_employer,
    'draft'
  )
  ON CONFLICT (tenant_id, number) DO UPDATE SET
    gross_salary = EXCLUDED.gross_salary,
    overtime_pay = EXCLUDED.overtime_pay,
    bonus = EXCLUDED.bonus,
    total_gross = EXCLUDED.total_gross,
    social_security_employee = EXCLUDED.social_security_employee,
    income_tax = EXCLUDED.income_tax,
    other_deductions = EXCLUDED.other_deductions,
    total_deductions = EXCLUDED.total_deductions,
    net_salary = EXCLUDED.net_salary,
    employer_contributions = EXCLUDED.employer_contributions;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION calculate_payslip(uuid, text) TO authenticated;


-- ============================================================
-- 2. generate_dsn(p_period)
--    Inspiré de : Silae, PayFit, Sage Paie
--    Génère une déclaration DSN mensuelle agrégée.
-- ============================================================
CREATE OR REPLACE FUNCTION generate_dsn(p_period text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_period_start date;
  v_period_end date;
  v_dsn_id uuid;
  v_emp_count integer := 0;
  v_gross_total numeric := 0;
  v_net_total numeric := 0;
  v_social_charges_total numeric := 0;
  v_ps RECORD;
  v_company RECORD;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  v_period_start := (p_period || '-01')::date;
  v_period_end := (v_period_start + INTERVAL '1 month' - INTERVAL '1 day')::date;

  -- Récupérer les infos entreprise
  SELECT * INTO v_company
  FROM company_settings
  WHERE tenant_id = v_tid
  LIMIT 1;

  -- Agréger les bulletins de paie de la période
  SELECT
    count(*),
    COALESCE(SUM(total_gross), 0),
    COALESCE(SUM(net_salary), 0),
    COALESCE(SUM(social_security_employee + employer_contributions), 0)
  INTO v_emp_count, v_gross_total, v_net_total, v_social_charges_total
  FROM pay_slips
  WHERE tenant_id = v_tid
    AND period_start = v_period_start
    AND status IN ('draft', 'validated', 'paid');

  -- Créer ou mettre à jour la déclaration DSN
  INSERT INTO dsn_declarations (
    tenant_id, period, type, status, generated_at
  ) VALUES (
    v_tid, p_period, 'mensuelle', 'draft', now()
  )
  ON CONFLICT (tenant_id, period, type) DO UPDATE SET
    generated_at = now(),
    status = 'draft'
  RETURNING id INTO v_dsn_id;

  RETURN jsonb_build_object(
    'dsn_id', v_dsn_id,
    'period', p_period,
    'type', 'mensuelle',
    'status', 'draft',
    'employee_count', v_emp_count,
    'gross_total', round(v_gross_total, 2),
    'net_total', round(v_net_total, 2),
    'social_charges_total', round(v_social_charges_total, 2),
    'company_siret', COALESCE(v_company.siret, ''),
    'company_name', COALESCE(v_company.company_name, v_company.name, ''),
    'generated_at', now()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION generate_dsn(text) TO authenticated;


-- ============================================================
-- 3. calculate_vat_ca3(p_period_start, p_period_end)
--    Inspiré de : Pennylane, Sage, Odoo
--    Calcule la TVA collectée et déductible pour la période.
-- ============================================================
CREATE OR REPLACE FUNCTION calculate_vat_ca3(
  p_period_start date,
  p_period_end date
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_output_vat numeric := 0;   -- TVA collectée (ventes)
  v_input_vat numeric := 0;    -- TVA déductible (achats)
  v_total_sales_ht numeric := 0;
  v_total_purchases_ht numeric := 0;
  v_vat_due numeric := 0;
  v_deposits_collected numeric := 0;
  v_deposits_deductible numeric := 0;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  -- TVA collectée sur les factures de vente
  SELECT
    COALESCE(SUM(il.vat_total), 0),
    COALESCE(SUM(il.quantity * il.unit_price), 0)
  INTO v_output_vat, v_total_sales_ht
  FROM invoices i
  JOIN invoice_lines il ON il.invoice_id = i.id AND il.tenant_id = v_tid
  WHERE i.tenant_id = v_tid
    AND i.date >= p_period_start
    AND i.date <= p_period_end
    AND i.status NOT IN ('cancelled', 'draft');

  -- TVA collectée sur les avoirs (négatif)
  SELECT COALESCE(SUM(cnl.vat_total), 0)
  INTO v_deposits_collected
  FROM credit_notes cn
  JOIN credit_note_lines cnl ON cnl.credit_note_id = cn.id AND cnl.tenant_id = v_tid
  WHERE cn.tenant_id = v_tid
    AND cn.date >= p_period_start
    AND cn.date <= p_period_end
    AND cn.status NOT IN ('cancelled', 'draft');

  v_output_vat := v_output_vat - v_deposits_collected;

  -- TVA déductible sur les factures d'achat
  SELECT
    COALESCE(SUM(pil.vat_total), 0),
    COALESCE(SUM(pil.quantity * pil.unit_price), 0)
  INTO v_input_vat, v_total_purchases_ht
  FROM purchase_invoices pi
  JOIN purchase_invoice_lines pil ON pil.purchase_invoice_id = pi.id AND pil.tenant_id = v_tid
  WHERE pi.tenant_id = v_tid
    AND pi.date >= p_period_start
    AND pi.date <= p_period_end
    AND pi.status NOT IN ('cancelled', 'draft');

  -- TVA déductible sur les avoirs d'achat (négatif)
  SELECT COALESCE(SUM(pcnl.vat_total), 0)
  INTO v_deposits_deductible
  FROM purchase_credit_notes pcn
  JOIN purchase_credit_lines pcnl ON pcnl.purchase_credit_note_id = pcn.id AND pcnl.tenant_id = v_tid
  WHERE pcn.tenant_id = v_tid
    AND pcn.date >= p_period_start
    AND pcn.date <= p_period_end
    AND pcn.status NOT IN ('cancelled', 'draft');

  v_input_vat := v_input_vat - v_deposits_deductible;

  -- TVA à décaisser
  v_vat_due := v_output_vat - v_input_vat;

  RETURN jsonb_build_object(
    'period_start', p_period_start,
    'period_end', p_period_end,
    'total_sales_ht', round(v_total_sales_ht, 2),
    'total_purchases_ht', round(v_total_purchases_ht, 2),
    'output_vat', round(v_output_vat, 2),
    'input_vat', round(v_input_vat, 2),
    'deposits_vat_collected', round(v_deposits_collected, 2),
    'deposits_vat_deductible', round(v_deposits_deductible, 2),
    'vat_due', round(v_vat_due, 2),
    'net_vat', round(GREATEST(v_vat_due, 0), 2),
    'repayment_due', round(GREATEST(-v_vat_due, 0), 2),
    'calculated_at', now()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION calculate_vat_ca3(date, date) TO authenticated;


-- ============================================================
-- 4. generate_vat_return(p_period_start, p_period_end)
--    Inspiré de : Pennylane, Sage, Odoo
--    Crée ou met à jour une déclaration TVA (CA3) en base.
-- ============================================================
CREATE OR REPLACE FUNCTION generate_vat_return(
  p_period_start date,
  p_period_end date
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_calc jsonb;
  v_return_id uuid;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  -- Calculer la TVA via la fonction calculate_vat_ca3
  SELECT calculate_vat_ca3(p_period_start, p_period_end) INTO v_calc;

  -- Créer ou mettre à jour la déclaration TVA
  INSERT INTO vat_returns (
    tenant_id, period_start, period_end, status,
    box1_output_vat, box2_input_vat,
    box3_vat_due, box4_repayment_due, box5_net_vat,
    total_sales, total_purchases,
    deposits_vat_collected, deposits_vat_deductible
  ) VALUES (
    v_tid, p_period_start, p_period_end, 'draft',
    (v_calc->>'output_vat')::numeric,
    (v_calc->>'input_vat')::numeric,
    (v_calc->>'vat_due')::numeric,
    (v_calc->>'repayment_due')::numeric,
    (v_calc->>'net_vat')::numeric,
    (v_calc->>'total_sales_ht')::numeric,
    (v_calc->>'total_purchases_ht')::numeric,
    (v_calc->>'deposits_vat_collected')::numeric,
    (v_calc->>'deposits_vat_deductible')::numeric
  )
  ON CONFLICT (tenant_id, period_start, period_end) DO UPDATE SET
    box1_output_vat = EXCLUDED.box1_output_vat,
    box2_input_vat = EXCLUDED.box2_input_vat,
    box3_vat_due = EXCLUDED.box3_vat_due,
    box4_repayment_due = EXCLUDED.box4_repayment_due,
    box5_net_vat = EXCLUDED.box5_net_vat,
    total_sales = EXCLUDED.total_sales,
    total_purchases = EXCLUDED.total_purchases,
    deposits_vat_collected = EXCLUDED.deposits_vat_collected,
    deposits_vat_deductible = EXCLUDED.deposits_vat_deductible
  RETURNING id INTO v_return_id;

  RETURN jsonb_build_object(
    'return_id', v_return_id,
    'period_start', p_period_start,
    'period_end', p_period_end,
    'status', 'draft',
    'calculation', v_calc
  );
END;
$$;

GRANT EXECUTE ON FUNCTION generate_vat_return(date, date) TO authenticated;


-- ============================================================
-- 5. generate_balance_sheet(p_fiscal_year_id)
--    Inspiré de : Sage, Odoo, QuickBooks, Xero
--    Génère le bilan (actif/passif) à partir des écritures.
--    Actif = comptes classe 1 (immobilisations) + classe 2 (stocks)
--            + classe 3 (créances) + classe 4 (disponibilités)
--    Passif = comptes classe 1 (capitaux) + classe 4 (dettes)
--    En France : Actif = classes 2,3,4,5 ; Passif = classes 1,4,5
-- ============================================================
CREATE OR REPLACE FUNCTION generate_balance_sheet(p_fiscal_year_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_fy RECORD;
  v_asset_total numeric := 0;
  v_liability_total numeric := 0;
  v_equity_total numeric := 0;
  v_accounts jsonb := '[]'::jsonb;
  v_rec RECORD;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  SELECT * INTO v_fy FROM fiscal_years WHERE id = p_fiscal_year_id AND tenant_id = v_tid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Exercice non trouvé: %', p_fiscal_year_id;
  END IF;

  -- Calculer le solde par compte (débit - crédit)
  FOR v_rec IN
    SELECT
      ca.code,
      ca.name,
      ca.type,
      ca.classe,
      ca.account_type,
      COALESCE(SUM(jl.debit - jl.credit), 0) as solde
    FROM chart_accounts ca
    LEFT JOIN journal_lines jl ON jl.account_code = ca.code AND jl.tenant_id = v_tid
    LEFT JOIN journal_entries je ON je.id = jl.journal_id AND je.tenant_id = v_tid
      AND je.date >= v_fy.start_date
      AND je.date <= v_fy.end_date
      AND je.status = 'posted'
    WHERE ca.tenant_id = v_tid
      AND ca.classe IN ('1','2','3','4','5')
      AND ca.deprecated = false
    GROUP BY ca.code, ca.name, ca.type, ca.classe, ca.account_type
    HAVING COALESCE(SUM(jl.debit - jl.credit), 0) != 0
    ORDER BY ca.code
  LOOP
    v_accounts := v_accounts || jsonb_build_object(
      'code', v_rec.code,
      'name', v_rec.name,
      'type', v_rec.type,
      'classe', v_rec.classe,
      'account_type', v_rec.account_type,
      'solde', round(v_rec.solde, 2)
    );

    -- Actif : comptes 2,3,4,5 avec solde débit > 0
    -- (immobilisations, stocks, créances, trésorerie)
    IF v_rec.classe IN ('2','3','5') AND v_rec.solde > 0 THEN
      v_asset_total := v_asset_total + v_rec.solde;
    ELSIF v_rec.classe = '4' THEN
      -- Classe 4 : tiers - débit = créance (actif), crédit = dette (passif)
      IF v_rec.solde > 0 THEN
        v_asset_total := v_asset_total + v_rec.solde;
      ELSE
        v_liability_total := v_liability_total + ABS(v_rec.solde);
      END IF;
    -- Passif : classe 1 (capitaux propres) et classe 5 crédit (concours bancaires)
    ELSIF v_rec.classe = '1' THEN
      IF v_rec.solde < 0 THEN
        -- Capitaux propres (solde créditeur)
        v_equity_total := v_equity_total + ABS(v_rec.solde);
      ELSE
        v_asset_total := v_asset_total + v_rec.solde;
      END IF;
    ELSIF v_rec.classe = '5' AND v_rec.solde < 0 THEN
      v_liability_total := v_liability_total + ABS(v_rec.solde);
    END IF;
  END LOOP;

  v_liability_total := v_liability_total + v_equity_total;

  RETURN jsonb_build_object(
    'fiscal_year_id', p_fiscal_year_id,
    'fiscal_year_code', v_fy.code,
    'start_date', v_fy.start_date,
    'end_date', v_fy.end_date,
    'accounts', v_accounts,
    'asset_total', round(v_asset_total, 2),
    'liability_total', round(v_liability_total, 2),
    'equity_total', round(v_equity_total, 2),
    'balanced', (round(v_asset_total, 2) = round(v_liability_total, 2)),
    'generated_at', now()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION generate_balance_sheet(uuid) TO authenticated;


-- ============================================================
-- 6. generate_profit_loss(p_fiscal_year_id)
--    Inspiré de : Sage, Odoo, QuickBooks, Xero
--    Génère le compte de résultat (charges/produits).
--    Charges = classe 6 (achats + charges externes + personnel)
--    Produits = classe 7 (ventes + production)
-- ============================================================
CREATE OR REPLACE FUNCTION generate_profit_loss(p_fiscal_year_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_fy RECORD;
  v_revenue_total numeric := 0;
  v_expense_total numeric := 0;
  v_result numeric := 0;
  v_accounts jsonb := '[]'::jsonb;
  v_rec RECORD;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  SELECT * INTO v_fy FROM fiscal_years WHERE id = p_fiscal_year_id AND tenant_id = v_tid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Exercice non trouvé: %', p_fiscal_year_id;
  END IF;

  -- Calculer le solde par compte de classe 6 et 7
  FOR v_rec IN
    SELECT
      ca.code,
      ca.name,
      ca.type,
      ca.classe,
      COALESCE(SUM(jl.debit), 0) as total_debit,
      COALESCE(SUM(jl.credit), 0) as total_credit,
      COALESCE(SUM(jl.credit - jl.debit), 0) as solde
    FROM chart_accounts ca
    LEFT JOIN journal_lines jl ON jl.account_code = ca.code AND jl.tenant_id = v_tid
    LEFT JOIN journal_entries je ON je.id = jl.journal_id AND je.tenant_id = v_tid
      AND je.date >= v_fy.start_date
      AND je.date <= v_fy.end_date
      AND je.status = 'posted'
    WHERE ca.tenant_id = v_tid
      AND ca.classe IN ('6','7')
      AND ca.deprecated = false
    GROUP BY ca.code, ca.name, ca.type, ca.classe
    HAVING COALESCE(SUM(jl.debit), 0) != 0 OR COALESCE(SUM(jl.credit), 0) != 0
    ORDER BY ca.code
  LOOP
    v_accounts := v_accounts || jsonb_build_object(
      'code', v_rec.code,
      'name', v_rec.name,
      'type', v_rec.type,
      'classe', v_rec.classe,
      'debit', round(v_rec.total_debit, 2),
      'credit', round(v_rec.total_credit, 2),
      'solde', round(v_rec.solde, 2)
    );

    IF v_rec.classe = '7' THEN
      -- Produits (solde créditeur = positif)
      v_revenue_total := v_revenue_total + v_rec.solde;
    ELSIF v_rec.classe = '6' THEN
      -- Charges (solde débiteur = négatif, on prend la valeur absolue)
      v_expense_total := v_expense_total + ABS(v_rec.solde);
    END IF;
  END LOOP;

  -- Résultat = Produits - Charges
  v_result := v_revenue_total - v_expense_total;

  RETURN jsonb_build_object(
    'fiscal_year_id', p_fiscal_year_id,
    'fiscal_year_code', v_fy.code,
    'start_date', v_fy.start_date,
    'end_date', v_fy.end_date,
    'accounts', v_accounts,
    'revenue_total', round(v_revenue_total, 2),
    'expense_total', round(v_expense_total, 2),
    'result', round(v_result, 2),
    'result_type', CASE WHEN v_result > 0 THEN 'bénéfice' ELSE 'perte' END,
    'generated_at', now()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION generate_profit_loss(uuid) TO authenticated;


-- ============================================================
-- 7. close_fiscal_year(p_fiscal_year_id)
--    Inspiré de : Sage, Odoo, QuickBooks
--    Clôture l'exercice : calcule le résultat, génère l'écriture
--    de clôture (solde des comptes 6/7 → compte 120/129),
--    verrouille les périodes et crée l'exercice suivant.
-- ============================================================
CREATE OR REPLACE FUNCTION close_fiscal_year(p_fiscal_year_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_fy RECORD;
  v_pl jsonb;
  v_result numeric := 0;
  v_entry_id uuid;
  v_number text;
  v_next_fy_id uuid;
  v_next_start date;
  v_next_end date;
  v_next_code text;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  SELECT * INTO v_fy FROM fiscal_years WHERE id = p_fiscal_year_id AND tenant_id = v_tid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Exercice non trouvé: %', p_fiscal_year_id;
  END IF;

  IF v_fy.status = 'closed' THEN
    RAISE EXCEPTION 'Exercice déjà clôturé';
  END IF;

  -- Calculer le compte de résultat
  SELECT generate_profit_loss(p_fiscal_year_id) INTO v_pl;
  v_result := (v_pl->>'result')::numeric;

  -- Générer l'écriture de clôture (solde des comptes 6 et 7)
  v_number := 'CLOT-' || v_fy.code;

  -- Entête de l'écriture
  INSERT INTO journal_entries (
    tenant_id, number, date, journal_code, status,
    description, piece_number
  ) VALUES (
    v_tid, v_number, v_fy.end_date, 'OD', 'posted',
    'Clôture exercice ' || v_fy.code, v_number
  )
  RETURNING id INTO v_entry_id;

  -- Pour chaque compte de classe 6 : créditer pour solder (solde débiteur)
  INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, debit, credit, description, line_order)
  SELECT
    v_tid, v_entry_id, ca.code, ca.code, 0,
    COALESCE(SUM(jl.debit - jl.credit), 0),
    'Solde clôture ' || ca.name,
    ROW_NUMBER() OVER (ORDER BY ca.code)
  FROM chart_accounts ca
  JOIN journal_lines jl ON jl.account_code = ca.code AND jl.tenant_id = v_tid
  JOIN journal_entries je ON je.id = jl.journal_id AND je.tenant_id = v_tid
    AND je.date >= v_fy.start_date AND je.date <= v_fy.end_date AND je.status = 'posted'
  WHERE ca.tenant_id = v_tid AND ca.classe = '6'
  GROUP BY ca.code, ca.name
  HAVING COALESCE(SUM(jl.debit - jl.credit), 0) != 0;

  -- Pour chaque compte de classe 7 : débiter pour solder (solde créditeur)
  INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, debit, credit, description, line_order)
  SELECT
    v_tid, v_entry_id, ca.code, ca.code,
    COALESCE(SUM(jl.credit - jl.debit), 0), 0,
    'Solde clôture ' || ca.name,
    1000 + ROW_NUMBER() OVER (ORDER BY ca.code)
  FROM chart_accounts ca
  JOIN journal_lines jl ON jl.account_code = ca.code AND jl.tenant_id = v_tid
  JOIN journal_entries je ON je.id = jl.journal_id AND je.tenant_id = v_tid
    AND je.date >= v_fy.start_date AND je.date <= v_fy.end_date AND je.status = 'posted'
  WHERE ca.tenant_id = v_tid AND ca.classe = '7'
  GROUP BY ca.code, ca.name
  HAVING COALESCE(SUM(jl.credit - jl.debit), 0) != 0;

  -- Écrire le résultat dans le compte 120 (bénéfice) ou 129 (perte)
  IF v_result > 0 THEN
    -- Bénéfice : crédit compte 120
    INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, debit, credit, description, line_order)
    VALUES (v_tid, v_entry_id, '120000', '120000', 0, v_result, 'Résultat de l''exercice (bénéfice)', 9998);
  ELSIF v_result < 0 THEN
    -- Perte : débit compte 129
    INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, debit, credit, description, line_order)
    VALUES (v_tid, v_entry_id, '129000', '129000', ABS(v_result), 0, 'Résultat de l''exercice (perte)', 9998);
  END IF;

  -- Verrouiller toutes les périodes de l'exercice
  UPDATE fiscal_periods
    SET status = 'closed'
  WHERE fiscal_year_id = p_fiscal_year_id AND tenant_id = v_tid;

  -- Marquer l'exercice comme clôturé
  UPDATE fiscal_years
    SET status = 'closed', closed_at = now()
  WHERE id = p_fiscal_year_id AND tenant_id = v_tid;

  -- Créer l'exercice suivant
  v_next_start := v_fy.end_date + INTERVAL '1 day';
  v_next_end := v_next_start + INTERVAL '1 year' - INTERVAL '1 day';
  v_next_code := to_char(v_next_start, 'YYYY');

  INSERT INTO fiscal_years (
    tenant_id, code, start_date, end_date, status
  ) VALUES (
    v_tid, v_next_code, v_next_start, v_next_end, 'open'
  )
  ON CONFLICT DO NOTHING
  RETURNING id INTO v_next_fy_id;

  -- Créer les périodes mensuelles de l'exercice suivant
  IF v_next_fy_id IS NOT NULL THEN
    INSERT INTO fiscal_periods (
      tenant_id, fiscal_year_id, period_number, period_label, start_date, end_date, status
    )
    SELECT
      v_tid, v_next_fy_id, m,
      to_char(v_next_start + (m || ' month')::interval - '1 month'::interval, 'YYYY-MM'),
      (v_next_start + (m || ' month')::interval - '1 month'::interval)::date,
      ((v_next_start + (m || ' month')::interval - '1 month'::interval)::date
        + INTERVAL '1 month' - INTERVAL '1 day')::date,
      'open'
    FROM generate_series(1, 12) AS m
    ON CONFLICT DO NOTHING;
  END IF;

  RETURN jsonb_build_object(
    'fiscal_year_id', p_fiscal_year_id,
    'fiscal_year_code', v_fy.code,
    'status', 'closed',
    'result', round(v_result, 2),
    'result_type', CASE WHEN v_result > 0 THEN 'bénéfice' ELSE 'perte' END,
    'closing_entry_id', v_entry_id,
    'closing_entry_number', v_number,
    'next_fiscal_year_id', v_next_fy_id,
    'next_fiscal_year_code', v_next_code,
    'closed_at', now()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION close_fiscal_year(uuid) TO authenticated;


-- ============================================================
-- RÉCAPITULATIF
-- ============================================================
-- 1. calculate_payslip(employee_id, period)    — Calcul brut→net
-- 2. generate_dsn(period)                      — Génération DSN
-- 3. calculate_vat_ca3(start, end)             — Calcul TVA
-- 4. generate_vat_return(start, end)           — Déclaration TVA
-- 5. generate_balance_sheet(fiscal_year_id)    — Bilan
-- 6. generate_profit_loss(fiscal_year_id)      — Compte de résultat
-- 7. close_fiscal_year(fiscal_year_id)         — Clôture annuelle
-- ============================================================
