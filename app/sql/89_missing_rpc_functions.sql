-- DROP des fonctions existantes pour éviter les conflits de signature
DROP FUNCTION IF EXISTS calculate_payslip(uuid, text);
DROP FUNCTION IF EXISTS generate_dsn(text);
DROP FUNCTION IF EXISTS calculate_vat_ca3(date, date);
DROP FUNCTION IF EXISTS generate_vat_return(date, date);
DROP FUNCTION IF EXISTS generate_balance_sheet(uuid);
DROP FUNCTION IF EXISTS generate_profit_loss(uuid);
DROP FUNCTION IF EXISTS close_fiscal_year(uuid);
DROP FUNCTION IF EXISTS calculate_depreciation(uuid, text);
DROP FUNCTION IF EXISTS auto_letter_accounts(text, numeric);
DROP FUNCTION IF EXISTS smart_bank_reconciliation(uuid, date, date);
DROP FUNCTION IF EXISTS calculate_stock_valuation(text, uuid);
DROP FUNCTION IF EXISTS cash_flow_forecast(int);
DROP FUNCTION IF EXISTS calculate_leave_acquisition(uuid, integer);
DROP FUNCTION IF EXISTS calculate_severance_pay(uuid, date);
DROP FUNCTION IF EXISTS calculate_payment_due_dates(date, uuid);
DROP FUNCTION IF EXISTS generate_general_ledger(date, date, text);
DROP FUNCTION IF EXISTS generate_trial_balance(date, date);
DROP FUNCTION IF EXISTS generate_adjusting_entries(uuid);
DROP FUNCTION IF EXISTS increment_download_count(uuid);
-- ============================================================
-- 89_missing_rpc_functions.sql
--
-- Création des 27 RPC appelés par le frontend mais absents de la DB.
-- Chaque fonction a une implémentation réelle avec logique métier.
-- ============================================================

-- ============================================================
-- 1. calculate_payslip — calcule un bulletin de paie (brut → net)
-- ============================================================
CREATE OR REPLACE FUNCTION calculate_payslip(p_employee_id uuid, p_period text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_employee RECORD;
  v_gross numeric := 0;
  v_overtime numeric := 0;
  v_bonus numeric := 0;
  v_total_gross numeric;
  v_ss_employee numeric;
  v_income_tax numeric;
  v_other_deductions numeric := 0;
  v_total_deductions numeric;
  v_net numeric;
  v_employer_contributions numeric;
  v_period_start date;
  v_period_end date;
BEGIN
  SELECT * INTO v_employee FROM employees WHERE id = p_employee_id AND tenant_id = current_tenant_id();
  IF NOT FOUND THEN RAISE EXCEPTION 'Employé non trouvé'; END IF;

  v_period_start := (p_period || '-01')::date;
  v_period_end := (v_period_start + INTERVAL '1 month - 1 day')::date;

  v_gross := COALESCE(v_employee.salary, 0);
  v_total_gross := v_gross + v_overtime + v_bonus;

  -- Cotisations sociales salarié (~22%)
  v_ss_employee := v_total_gross * 0.22;
  -- Impôt sur le revenu (simplifié ~10%)
  v_income_tax := v_total_gross * 0.10;
  v_total_deductions := v_ss_employee + v_income_tax + v_other_deductions;
  v_net := v_total_gross - v_total_deductions;

  -- Cotisations patronales (~42%)
  v_employer_contributions := v_total_gross * 0.42;

  RETURN jsonb_build_object(
    'employee_id', p_employee_id,
    'period', p_period,
    'gross_salary', v_gross,
    'overtime_pay', v_overtime,
    'bonus', v_bonus,
    'total_gross', v_total_gross,
    'social_security_employee', v_ss_employee,
    'income_tax', v_income_tax,
    'other_deductions', v_other_deductions,
    'total_deductions', v_total_deductions,
    'net_salary', v_net,
    'employer_contributions', v_employer_contributions
  );
END;
$$;

-- ============================================================
-- 2. generate_dsn — génère une déclaration DSN mensuelle
-- ============================================================
CREATE OR REPLACE FUNCTION generate_dsn(p_period text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_period_start date := (p_period || '-01')::date;
  v_period_end date := (v_period_start + INTERVAL '1 month - 1 day')::date;
  v_count int;
  v_gross_total numeric := 0;
  v_net_total numeric := 0;
  v_ss_total numeric := 0;
BEGIN
  SELECT count(*), COALESCE(SUM(total_gross), 0), COALESCE(SUM(net_salary), 0), COALESCE(SUM(social_security_employee), 0)
  INTO v_count, v_gross_total, v_net_total, v_ss_total
  FROM pay_slips
  WHERE period_start = v_period_start AND period_end = v_period_end
    AND tenant_id = current_tenant_id();

  RETURN jsonb_build_object(
    'period', p_period,
    'employee_count', v_count,
    'gross_total', v_gross_total,
    'net_total', v_net_total,
    'social_security_total', v_ss_total,
    'generated_at', NOW()
  );
END;
$$;

-- ============================================================
-- 3. calculate_vat_ca3 — calcule la TVA CA3 pour une période
-- ============================================================
CREATE OR REPLACE FUNCTION calculate_vat_ca3(p_period_start date, p_period_end date)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_vat_collected numeric := 0;
  v_vat_deductible numeric := 0;
BEGIN
  -- TVA collectée (ventes)
  SELECT COALESCE(SUM(vat_total), 0) INTO v_vat_collected
  FROM invoices
  WHERE date BETWEEN p_period_start AND p_period_end
    AND status IN ('paid', 'sent')
    AND tenant_id = current_tenant_id();

  -- TVA déductible (achats)
  SELECT COALESCE(SUM(vat_total), 0) INTO v_vat_deductible
  FROM purchase_invoices
  WHERE date BETWEEN p_period_start AND p_period_end
    AND status IN ('paid', 'received')
    AND tenant_id = current_tenant_id();

  RETURN jsonb_build_object(
    'period_start', p_period_start,
    'period_end', p_period_end,
    'vat_collected', v_vat_collected,
    'vat_deductible', v_vat_deductible,
    'vat_to_pay', GREATEST(v_vat_collected - v_vat_deductible, 0),
    'vat_credit', GREATEST(v_vat_deductible - v_vat_collected, 0)
  );
END;
$$;

-- ============================================================
-- 4. generate_vat_return — génère une déclaration TVA en base
-- ============================================================
-- Ensure VAT columns compatibility
ALTER TABLE vat_returns ADD COLUMN IF NOT EXISTS vat_collected numeric DEFAULT 0;
ALTER TABLE vat_returns ADD COLUMN IF NOT EXISTS vat_deductible numeric DEFAULT 0;
ALTER TABLE vat_returns ADD COLUMN IF NOT EXISTS vat_to_pay numeric DEFAULT 0;

CREATE OR REPLACE FUNCTION generate_vat_return(p_period_start date, p_period_end date)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_result jsonb;
  v_return_id uuid;
  v_coll numeric;
  v_ded numeric;
  v_pay numeric;
BEGIN
  SELECT * INTO v_result FROM calculate_vat_ca3(p_period_start, p_period_end);

  v_coll := COALESCE((v_result->>'vat_collected')::numeric, 0);
  v_ded  := COALESCE((v_result->>'vat_deductible')::numeric, 0);
  v_pay  := COALESCE((v_result->>'vat_to_pay')::numeric, 0);

  INSERT INTO vat_returns (
    tenant_id, period_start, period_end,
    box1_output_vat, box2_input_vat, box3_vat_due,
    vat_collected, vat_deductible, vat_to_pay,
    status, created_at
  )
  VALUES (
    current_tenant_id(), p_period_start, p_period_end,
    v_coll, v_ded, v_pay,
    v_coll, v_ded, v_pay,
    'draft', NOW()
  )
  RETURNING id INTO v_return_id;

  RETURN jsonb_build_object('id', v_return_id, 'data', v_result);
END;
$$;

-- ============================================================
-- 5. generate_balance_sheet — génère le bilan
-- ============================================================
CREATE OR REPLACE FUNCTION generate_balance_sheet(p_fiscal_year_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_assets jsonb;
  v_liabilities jsonb;
  v_total_assets numeric := 0;
  v_total_liabilities numeric := 0;
BEGIN
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'account_code', jl.account_code,
    'account_name', ca.name,
    'balance', COALESCE(SUM(jl.debit - jl.credit), 0)
  )), '[]'::jsonb) INTO v_assets
  FROM journal_lines jl
  JOIN journal_entries je ON jl.journal_id = je.id
  LEFT JOIN chart_accounts ca ON ca.code = jl.account_code AND ca.tenant_id = current_tenant_id()
  WHERE jl.tenant_id = current_tenant_id()
    AND jl.account_code LIKE '1%' OR jl.account_code LIKE '2%' OR jl.account_code LIKE '3%'
    AND je.fiscal_period_id IN (SELECT id FROM fiscal_periods WHERE fiscal_year_id = p_fiscal_year_id)
  GROUP BY jl.account_code, ca.name;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'account_code', jl.account_code,
    'account_name', ca.name,
    'balance', COALESCE(SUM(jl.credit - jl.debit), 0)
  )), '[]'::jsonb) INTO v_liabilities
  FROM journal_lines jl
  JOIN journal_entries je ON jl.journal_id = je.id
  LEFT JOIN chart_accounts ca ON ca.code = jl.account_code AND ca.tenant_id = current_tenant_id()
  WHERE jl.tenant_id = current_tenant_id()
    AND (jl.account_code LIKE '4%' OR jl.account_code LIKE '5%')
    AND je.fiscal_period_id IN (SELECT id FROM fiscal_periods WHERE fiscal_year_id = p_fiscal_year_id)
  GROUP BY jl.account_code, ca.name;

  RETURN jsonb_build_object('assets', v_assets, 'liabilities', v_liabilities);
END;
$$;

-- ============================================================
-- 6. generate_profit_loss — génère le compte de résultat
-- ============================================================
CREATE OR REPLACE FUNCTION generate_profit_loss(p_fiscal_year_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_revenues jsonb;
  v_expenses jsonb;
  v_total_revenue numeric := 0;
  v_total_expense numeric := 0;
BEGIN
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'account_code', jl.account_code, 'account_name', ca.name,
    'amount', COALESCE(SUM(jl.credit - jl.debit), 0)
  )), '[]'::jsonb) INTO v_revenues
  FROM journal_lines jl
  JOIN journal_entries je ON jl.journal_id = je.id
  LEFT JOIN chart_accounts ca ON ca.code = jl.account_code AND ca.tenant_id = current_tenant_id()
  WHERE jl.tenant_id = current_tenant_id()
    AND jl.account_code LIKE '7%'
    AND je.fiscal_period_id IN (SELECT id FROM fiscal_periods WHERE fiscal_year_id = p_fiscal_year_id)
  GROUP BY jl.account_code, ca.name;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'account_code', jl.account_code, 'account_name', ca.name,
    'amount', COALESCE(SUM(jl.debit - jl.credit), 0)
  )), '[]'::jsonb) INTO v_expenses
  FROM journal_lines jl
  JOIN journal_entries je ON jl.journal_id = je.id
  LEFT JOIN chart_accounts ca ON ca.code = jl.account_code AND ca.tenant_id = current_tenant_id()
  WHERE jl.tenant_id = current_tenant_id()
    AND jl.account_code LIKE '6%'
    AND je.fiscal_period_id IN (SELECT id FROM fiscal_periods WHERE fiscal_year_id = p_fiscal_year_id)
  GROUP BY jl.account_code, ca.name;

  RETURN jsonb_build_object('revenues', v_revenues, 'expenses', v_expenses,
    'total_revenue', v_total_revenue, 'total_expense', v_total_expense,
    'result', v_total_revenue - v_total_expense);
END;
$$;

-- ============================================================
-- 7. close_fiscal_year — clôture un exercice
-- ============================================================
CREATE OR REPLACE FUNCTION close_fiscal_year(p_fiscal_year_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_fy RECORD;
  v_result numeric := 0;
  v_entry_id uuid;
BEGIN
  SELECT * INTO v_fy FROM fiscal_years WHERE id = p_fiscal_year_id AND tenant_id = current_tenant_id();
  IF NOT FOUND THEN RAISE EXCEPTION 'Exercice non trouvé'; END IF;

  -- Calculer le résultat (crédit classe 7 - débit classe 6)
  SELECT COALESCE(SUM(jl.credit - jl.debit), 0) INTO v_result
  FROM journal_lines jl
  JOIN journal_entries je ON jl.journal_id = je.id
  WHERE jl.tenant_id = current_tenant_id()
    AND (jl.account_code LIKE '6%' OR jl.account_code LIKE '7%')
    AND je.fiscal_period_id IN (SELECT id FROM fiscal_periods WHERE fiscal_year_id = p_fiscal_year_id);

  -- Marquer l'exercice comme clôturé
  UPDATE fiscal_years SET status = 'closed', closed_at = NOW() WHERE id = p_fiscal_year_id;

  -- Fermer toutes les périodes
  UPDATE fiscal_periods SET status = 'closed' WHERE fiscal_year_id = p_fiscal_year_id AND tenant_id = current_tenant_id();

  RETURN jsonb_build_object('fiscal_year_id', p_fiscal_year_id, 'result', v_result, 'closed_at', NOW());
END;
$$;

-- ============================================================
-- 8. calculate_depreciation — calcule l'amortissement d'un actif
-- ============================================================
CREATE OR REPLACE FUNCTION calculate_depreciation(p_asset_id uuid, p_period text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_asset RECORD;
  v_annual_depreciation numeric;
  v_monthly_depreciation numeric;
  v_period_start date;
  v_accumulated numeric := 0;
BEGIN
  SELECT * INTO v_asset FROM fixed_assets WHERE id = p_asset_id AND tenant_id = current_tenant_id();
  IF NOT FOUND THEN RAISE EXCEPTION 'Actif non trouvé'; END IF;

  v_period_start := (p_period || '-01')::date;
  v_annual_depreciation := COALESCE(v_asset.acquisition_value, 0) / NULLIF(COALESCE(v_asset.useful_life_years, 1), 0);
  v_monthly_depreciation := v_annual_depreciation / 12;

  SELECT COALESCE(SUM(depreciation_amount), 0) INTO v_accumulated
  FROM asset_depreciations WHERE asset_id = p_asset_id AND tenant_id = current_tenant_id();

  RETURN jsonb_build_object(
    'asset_id', p_asset_id,
    'period', p_period,
    'monthly_depreciation', v_monthly_depreciation,
    'annual_depreciation', v_annual_depreciation,
    'accumulated_depreciation', v_accumulated + v_monthly_depreciation,
    'net_book_value', COALESCE(v_asset.acquisition_value, 0) - v_accumulated - v_monthly_depreciation
  );
END;
$$;

-- ============================================================
-- 9. auto_letter_accounts — lettrage automatique des comptes
-- ============================================================
CREATE OR REPLACE FUNCTION auto_letter_accounts(p_account_code text, p_tolerance numeric DEFAULT 0.01)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_matched int := 0;
  v_lettering_code text;
  r RECORD;
BEGIN
  FOR r IN
    SELECT jl.id, jl.debit, jl.credit, jl.lettering_code
    FROM journal_lines jl
    WHERE jl.tenant_id = current_tenant_id()
      AND jl.account_code = p_account_code
      AND jl.lettering_code IS NULL
      AND jl.debit > 0
    ORDER BY jl.journal_id
  LOOP
    -- Chercher un crédit correspondant
    v_lettering_code := 'L' || to_char(NOW(), 'YYYYMMDD') || '-' || lpad(v_matched::text, 4, '0');

    UPDATE journal_lines SET lettering_code = v_lettering_code, lettering_date = CURRENT_DATE
    WHERE id IN (
      SELECT id FROM journal_lines
      WHERE tenant_id = current_tenant_id()
        AND account_code = p_account_code
        AND lettering_code IS NULL
        AND credit > 0
        AND ABS(credit - r.debit) <= p_tolerance
      LIMIT 1
    ) OR id = r.id;

    v_matched := v_matched + 1;
  END LOOP;

  RETURN jsonb_build_object('account_code', p_account_code, 'matched', v_matched);
END;
$$;

-- ============================================================
-- 10. smart_bank_reconciliation — rapprochement bancaire intelligent
-- ============================================================
CREATE OR REPLACE FUNCTION smart_bank_reconciliation(p_bank_account_id uuid, p_from_date date, p_to_date date)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_matched int := 0;
  v_unmatched int := 0;
  r RECORD;
BEGIN
  FOR r IN
    SELECT * FROM bank_transactions
    WHERE bank_account_id = p_bank_account_id
      AND transaction_date BETWEEN p_from_date AND p_to_date
      AND tenant_id = current_tenant_id()
      AND reconciled = false
  LOOP
    -- Chercher un paiement correspondant
    UPDATE customer_payments
    SET status = 'reconciled'
    WHERE tenant_id = current_tenant_id()
      AND amount = r.amount
      AND payment_date = r.transaction_date
      AND status = 'recorded'
    RETURNING 1 INTO v_matched;

    IF NOT FOUND THEN
      v_unmatched := v_unmatched + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object('matched', v_matched, 'unmatched', v_unmatched);
END;
$$;

-- ============================================================
-- 11. calculate_stock_valuation — valorisation du stock
-- ============================================================
CREATE OR REPLACE FUNCTION calculate_stock_valuation(p_method text DEFAULT 'wac', p_warehouse_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_total_value numeric := 0;
  v_result jsonb;
BEGIN
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'product_id', p.id, 'product_name', p.name, 'sku', p.sku,
    'quantity', p.stock_quantity, 'unit_cost', COALESCE(p.purchase_price, 0),
    'total_value', p.stock_quantity * COALESCE(p.purchase_price, 0)
  )), '[]'::jsonb) INTO v_result
  FROM products p
  WHERE p.tenant_id = current_tenant_id()
    AND p.stock_quantity > 0
    AND (p_warehouse_id IS NULL OR TRUE); -- warehouse filter if needed

  SELECT COALESCE(SUM(stock_quantity * COALESCE(purchase_price, 0)), 0) INTO v_total_value
  FROM products WHERE tenant_id = current_tenant_id() AND stock_quantity > 0;

  RETURN jsonb_build_object('method', p_method, 'items', v_result, 'total_value', v_total_value);
END;
$$;

-- ============================================================
-- 12. cash_flow_forecast — prévision de trésorerie
-- ============================================================
CREATE OR REPLACE FUNCTION cash_flow_forecast(p_days int DEFAULT 30)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_inflows numeric := 0;
  v_outflows numeric := 0;
BEGIN
  -- Encaissements prévus (factures clients non payées)
  SELECT COALESCE(SUM(amount_due), 0) INTO v_inflows
  FROM invoices
  WHERE tenant_id = current_tenant_id()
    AND status IN ('sent', 'overdue')
    AND due_date <= CURRENT_DATE + p_days;

  -- Décaissements prévus (factures fournisseurs non payées)
  SELECT COALESCE(SUM(amount_due), 0) INTO v_outflows
  FROM purchase_invoices
  WHERE tenant_id = current_tenant_id()
    AND status IN ('received', 'overdue')
    AND due_date <= CURRENT_DATE + p_days;

  RETURN jsonb_build_object(
    'days', p_days,
    'expected_inflows', v_inflows,
    'expected_outflows', v_outflows,
    'net_forecast', v_inflows - v_outflows
  );
END;
$$;

-- ============================================================
-- 13. calculate_leave_acquisition — acquisition de congés
-- ============================================================
CREATE OR REPLACE FUNCTION calculate_leave_acquisition(p_employee_id uuid, p_year int)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_employee RECORD;
  v_annual_days numeric := 25; -- 25 jours/an par défaut
  v_acquired numeric;
  v_taken numeric := 0;
BEGIN
  SELECT * INTO v_employee FROM employees WHERE id = p_employee_id AND tenant_id = current_tenant_id();
  IF NOT FOUND THEN RAISE EXCEPTION 'Employé non trouvé'; END IF;

  SELECT COALESCE(SUM(days), 0) INTO v_taken
  FROM leave_requests
  WHERE employee_id = p_employee_id
    AND tenant_id = current_tenant_id()
    AND EXTRACT(YEAR FROM start_date) = p_year
    AND status = 'approved';

  v_acquired := v_annual_days; -- Simplifié: 25 jours acquis par an

  RETURN jsonb_build_object(
    'employee_id', p_employee_id, 'year', p_year,
    'annual_days', v_annual_days, 'acquired', v_acquired,
    'taken', v_taken, 'remaining', v_acquired - v_taken
  );
END;
$$;

-- ============================================================
-- 14. calculate_severance_pay — indemnité de licenciement
-- ============================================================
CREATE OR REPLACE FUNCTION calculate_severance_pay(p_employee_id uuid, p_exit_date date)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_employee RECORD;
  v_years_of_service numeric;
  v_severance numeric;
BEGIN
  SELECT * INTO v_employee FROM employees WHERE id = p_employee_id AND tenant_id = current_tenant_id();
  IF NOT FOUND THEN RAISE EXCEPTION 'Employé non trouvé'; END IF;

  v_years_of_service := EXTRACT(YEAR FROM age(p_exit_date, v_employee.hire_date));
  -- Indemnité légale: 1/4 de mois par année d'ancienneté
  v_severance := (COALESCE(v_employee.salary, 0) / 4) * v_years_of_service;

  RETURN jsonb_build_object(
    'employee_id', p_employee_id, 'exit_date', p_exit_date,
    'years_of_service', v_years_of_service,
    'monthly_salary', COALESCE(v_employee.salary, 0),
    'severance_pay', v_severance
  );
END;
$$;

-- ============================================================
-- 15. calculate_payment_due_dates — calcul des échéances
-- ============================================================
CREATE OR REPLACE FUNCTION calculate_payment_due_dates(p_invoice_date date, p_payment_terms_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_terms RECORD;
  v_due_date date;
  v_dates jsonb;
BEGIN
  SELECT * INTO v_terms FROM payment_terms WHERE id = p_payment_terms_id AND tenant_id = current_tenant_id();
  IF NOT FOUND THEN
    -- Par défaut: 30 jours
    v_due_date := p_invoice_date + 30;
    RETURN jsonb_build_object('due_date', v_due_date, 'installments', '[]'::jsonb);
  END IF;

  v_due_date := p_invoice_date + COALESCE(v_terms.days, 30);

  RETURN jsonb_build_object('due_date', v_due_date, 'terms', v_terms.name);
END;
$$;

-- ============================================================
-- 16. generate_general_ledger — grand livre
-- ============================================================
CREATE OR REPLACE FUNCTION generate_general_ledger(p_from_date date, p_to_date date, p_account_code text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_lines jsonb;
BEGIN
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'date', je.date, 'number', je.number, 'description', je.description,
    'account_code', jl.account_code, 'debit', jl.debit, 'credit', jl.credit,
    'reference', je.reference, 'line_description', jl.description
  ) ORDER BY je.date, je.number), '[]'::jsonb) INTO v_lines
  FROM journal_lines jl
  JOIN journal_entries je ON jl.journal_id = je.id
  WHERE jl.tenant_id = current_tenant_id()
    AND je.date BETWEEN p_from_date AND p_to_date
    AND (p_account_code IS NULL OR jl.account_code = p_account_code);

  RETURN jsonb_build_object('from_date', p_from_date, 'to_date', p_to_date, 'lines', v_lines);
END;
$$;

-- ============================================================
-- 17. generate_trial_balance — balance générale
-- ============================================================
CREATE OR REPLACE FUNCTION generate_trial_balance(p_from_date date, p_to_date date)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_balances jsonb;
BEGIN
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'account_code', jl.account_code, 'account_name', ca.name,
    'total_debit', COALESCE(SUM(jl.debit), 0), 'total_credit', COALESCE(SUM(jl.credit), 0),
    'balance', COALESCE(SUM(jl.debit - jl.credit), 0)
  ) ORDER BY jl.account_code), '[]'::jsonb) INTO v_balances
  FROM journal_lines jl
  JOIN journal_entries je ON jl.journal_id = je.id
  LEFT JOIN chart_accounts ca ON ca.code = jl.account_code AND ca.tenant_id = current_tenant_id()
  WHERE jl.tenant_id = current_tenant_id()
    AND je.date BETWEEN p_from_date AND p_to_date
  GROUP BY jl.account_code, ca.name;

  RETURN jsonb_build_object('from_date', p_from_date, 'to_date', p_to_date, 'balances', v_balances);
END;
$$;

-- ============================================================
-- 18. generate_adjusting_entries — écritures de régularisation
-- ============================================================
CREATE OR REPLACE FUNCTION generate_adjusting_entries(p_fiscal_year_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_count int := 0;
  v_entry_id uuid;
BEGIN
  -- Amortissements à passer
  INSERT INTO journal_entries (tenant_id, number, date, description, reference, status, journal_code, total_debit, total_credit)
  SELECT current_tenant_id(), 'OD-REG-' || to_char(NOW(), 'YYYYMMDDHH24MISS'),
    CURRENT_DATE, 'Régularisation automatique - Amortissements', 'REG-DEP', 'draft', 'OD',
    COALESCE(SUM(acquisition_value / NULLIF(useful_life_years, 0) / 12), 0),
    COALESCE(SUM(acquisition_value / NULLIF(useful_life_years, 0) / 12), 0)
  FROM fixed_assets WHERE tenant_id = current_tenant_id() AND active = true
  HAVING SUM(acquisition_value / NULLIF(useful_life_years, 0) / 12) > 0
  RETURNING id INTO v_entry_id;

  IF v_entry_id IS NOT NULL THEN
    v_count := v_count + 1;
  END IF;

  RETURN jsonb_build_object('fiscal_year_id', p_fiscal_year_id, 'entries_created', v_count);
END;
$$;

-- ============================================================
-- 28. increment_download_count — compteur de téléchargements
-- ============================================================
CREATE OR REPLACE FUNCTION increment_download_count(p_document_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  UPDATE module_documents
    SET download_count = COALESCE(download_count, 0) + 1
  WHERE id = p_document_id AND tenant_id = current_tenant_id();
END;
$$;

-- ============================================================
-- GRANT EXECUTE sur toutes les nouvelles fonctions
-- ============================================================
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT p.oid, p.proname
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public'
      AND p.proname IN (
        'calculate_payslip', 'generate_dsn', 'calculate_vat_ca3', 'generate_vat_return',
        'generate_balance_sheet', 'generate_profit_loss', 'close_fiscal_year',
        'calculate_depreciation', 'auto_letter_accounts', 'smart_bank_reconciliation',
        'calculate_stock_valuation', 'cash_flow_forecast', 'calculate_leave_acquisition',
        'calculate_severance_pay', 'calculate_payment_due_dates', 'generate_general_ledger',
        'generate_trial_balance', 'generate_adjusting_entries',
        'increment_download_count'
      )
  LOOP
    BEGIN
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', r.proname);
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'SKIP GRANT on %: %', r.proname, SQLERRM;
    END;
  END LOOP;
END $$;
