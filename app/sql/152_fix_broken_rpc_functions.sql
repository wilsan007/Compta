-- ============================================================
-- 152_fix_broken_rpc_functions.sql
-- LOT3 : Répare les 31 fonctions RPC cassées (21 appelées par le front)
--
-- Corrections de schéma (colonnes manquantes) + CREATE OR REPLACE
-- des fonctions référençant des colonnes inexistantes.
-- ============================================================

-- ============================================================
-- 0. Corrections de schéma prérequises
-- ============================================================

-- LOT3-18 : check_segregation_of_duties a besoin de journal_entries.created_by
ALTER TABLE journal_entries ADD COLUMN IF NOT EXISTS created_by uuid;

-- LOT3-17 : calculate_project_profitability a besoin de invoices.project_id
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS project_id uuid;
CREATE INDEX IF NOT EXISTS idx_invoices_project ON invoices(project_id) WHERE project_id IS NOT NULL;

-- LOT3-15 : resolve_price — rattachement client ↔ tarif
CREATE TABLE IF NOT EXISTS price_list_customers (
  price_list_id uuid NOT NULL REFERENCES price_lists(id) ON DELETE CASCADE,
  customer_id   uuid NOT NULL REFERENCES customers(id)   ON DELETE CASCADE,
  tenant_id     uuid NOT NULL,
  PRIMARY KEY (price_list_id, customer_id)
);
ALTER TABLE price_list_customers ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  DROP POLICY IF EXISTS price_list_customers_tenant ON price_list_customers;
  CREATE POLICY price_list_customers_tenant ON price_list_customers
    FOR ALL USING (tenant_id = current_tenant_id())
    WITH CHECK (tenant_id = current_tenant_id());
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- LOT3-19/21 : run_mrp + calculate_manufacturing_cost ont besoin de
-- colonnes de suivi de coût sur manufacturing_orders
ALTER TABLE manufacturing_orders ADD COLUMN IF NOT EXISTS qty_produced numeric DEFAULT 0;
ALTER TABLE manufacturing_orders ADD COLUMN IF NOT EXISTS cost_material numeric DEFAULT 0;
ALTER TABLE manufacturing_orders ADD COLUMN IF NOT EXISTS cost_labor numeric DEFAULT 0;
ALTER TABLE manufacturing_orders ADD COLUMN IF NOT EXISTS cost_overhead numeric DEFAULT 0;
ALTER TABLE manufacturing_orders ADD COLUMN IF NOT EXISTS cost_total numeric DEFAULT 0;
ALTER TABLE manufacturing_orders ADD COLUMN IF NOT EXISTS unit_cost numeric DEFAULT 0;

-- LOT3-05..09 : colonnes employé utilisées par les fonctions de paie
ALTER TABLE employees ADD COLUMN IF NOT EXISTS first_name text;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS last_name text;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS base_salary numeric;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS seniority_date date;

-- ============================================================
-- 6.1 États financiers — LOT3-01 à LOT3-04
-- Pattern cassé : jsonb_agg(jsonb_build_object(..., SUM(...)))
-- = agrégat imbriqué. Réécriture avec CTE intermédiaire.
-- ============================================================

-- LOT3-01 : generate_trial_balance
CREATE OR REPLACE FUNCTION generate_trial_balance(p_from_date date, p_to_date date)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_balances jsonb;
BEGIN
  WITH par_compte AS (
    SELECT jl.account_code,
           MAX(ca.name) AS account_name,
           SUM(jl.debit) AS total_debit,
           SUM(jl.credit) AS total_credit
    FROM journal_lines jl
    JOIN journal_entries je ON jl.journal_id = je.id AND je.tenant_id = jl.tenant_id
    LEFT JOIN chart_accounts ca ON ca.code = jl.account_code AND ca.tenant_id = jl.tenant_id
    WHERE jl.tenant_id = current_tenant_id()
      AND je.date BETWEEN p_from_date AND p_to_date
    GROUP BY jl.account_code
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'account_code', account_code, 'account_name', account_name,
    'total_debit', total_debit, 'total_credit', total_credit,
    'balance', total_debit - total_credit
  ) ORDER BY account_code), '[]'::jsonb) INTO v_balances
  FROM par_compte;

  RETURN jsonb_build_object('from_date', p_from_date, 'to_date', p_to_date, 'balances', v_balances);
END;
$$;

-- LOT3-02 : generate_balance_sheet
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
  -- Actif : comptes 2, 3, 4 débit, 5 débit — parenthèses obligatoires sur le OR
  WITH actif AS (
    SELECT jl.account_code,
           MAX(ca.name) AS account_name,
           SUM(jl.debit - jl.credit) AS balance
    FROM journal_lines jl
    JOIN journal_entries je ON jl.journal_id = je.id AND je.tenant_id = jl.tenant_id
    LEFT JOIN chart_accounts ca ON ca.code = jl.account_code AND ca.tenant_id = jl.tenant_id
    WHERE jl.tenant_id = current_tenant_id()
      AND (jl.account_code LIKE '2%' OR jl.account_code LIKE '3%'
           OR jl.account_code LIKE '4%' OR jl.account_code LIKE '5%')
      AND je.fiscal_period_id IN (SELECT id FROM fiscal_periods WHERE fiscal_year_id = p_fiscal_year_id)
    GROUP BY jl.account_code
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'account_code', account_code, 'account_name', account_name, 'balance', balance
  ) ORDER BY account_code), '[]'::jsonb),
  COALESCE(SUM(balance), 0)
  INTO v_assets, v_total_assets
  FROM actif;

  -- Passif : comptes 1 (capitaux) et 4/5 créditeurs
  WITH passif AS (
    SELECT jl.account_code,
           MAX(ca.name) AS account_name,
           SUM(jl.credit - jl.debit) AS balance
    FROM journal_lines jl
    JOIN journal_entries je ON jl.journal_id = je.id AND je.tenant_id = jl.tenant_id
    LEFT JOIN chart_accounts ca ON ca.code = jl.account_code AND ca.tenant_id = jl.tenant_id
    WHERE jl.tenant_id = current_tenant_id()
      AND (jl.account_code LIKE '1%' OR jl.account_code LIKE '4%' OR jl.account_code LIKE '5%')
      AND je.fiscal_period_id IN (SELECT id FROM fiscal_periods WHERE fiscal_year_id = p_fiscal_year_id)
    GROUP BY jl.account_code
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'account_code', account_code, 'account_name', account_name, 'balance', balance
  ) ORDER BY account_code), '[]'::jsonb),
  COALESCE(SUM(balance), 0)
  INTO v_liabilities, v_total_liabilities
  FROM passif;

  RETURN jsonb_build_object(
    'assets', v_assets,
    'liabilities', v_liabilities,
    'total_assets', round(v_total_assets, 2),
    'total_liabilities', round(v_total_liabilities, 2),
    'balanced', round(v_total_assets, 2) = round(v_total_liabilities, 2)
  );
END;
$$;

-- LOT3-03 : generate_profit_loss
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
  WITH produits AS (
    SELECT jl.account_code, MAX(ca.name) AS account_name,
           SUM(jl.credit - jl.debit) AS amount
    FROM journal_lines jl
    JOIN journal_entries je ON jl.journal_id = je.id AND je.tenant_id = jl.tenant_id
    LEFT JOIN chart_accounts ca ON ca.code = jl.account_code AND ca.tenant_id = jl.tenant_id
    WHERE jl.tenant_id = current_tenant_id()
      AND jl.account_code LIKE '7%'
      AND je.fiscal_period_id IN (SELECT id FROM fiscal_periods WHERE fiscal_year_id = p_fiscal_year_id)
    GROUP BY jl.account_code
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'account_code', account_code, 'account_name', account_name, 'amount', amount
  ) ORDER BY account_code), '[]'::jsonb), COALESCE(SUM(amount), 0)
  INTO v_revenues, v_total_revenue FROM produits;

  WITH charges AS (
    SELECT jl.account_code, MAX(ca.name) AS account_name,
           SUM(jl.debit - jl.credit) AS amount
    FROM journal_lines jl
    JOIN journal_entries je ON jl.journal_id = je.id AND je.tenant_id = jl.tenant_id
    LEFT JOIN chart_accounts ca ON ca.code = jl.account_code AND ca.tenant_id = jl.tenant_id
    WHERE jl.tenant_id = current_tenant_id()
      AND jl.account_code LIKE '6%'
      AND je.fiscal_period_id IN (SELECT id FROM fiscal_periods WHERE fiscal_year_id = p_fiscal_year_id)
    GROUP BY jl.account_code
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'account_code', account_code, 'account_name', account_name, 'amount', amount
  ) ORDER BY account_code), '[]'::jsonb), COALESCE(SUM(amount), 0)
  INTO v_expenses, v_total_expense FROM charges;

  RETURN jsonb_build_object(
    'revenues', v_revenues, 'expenses', v_expenses,
    'total_revenue', round(v_total_revenue, 2),
    'total_expense', round(v_total_expense, 2),
    'result', round(v_total_revenue - v_total_expense, 2)
  );
END;
$$;

-- LOT3-04 : get_balance_sheet_structured — sous-requête corrélée
-- sur colonne non groupée → CTE amortissements jointe par préfixe
CREATE OR REPLACE FUNCTION get_balance_sheet_structured(
  p_fiscal_year_id uuid,
  p_date_to date DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  v_tenant_id uuid := current_tenant_id();
  v_end_date date;
  v_assets jsonb;
  v_liabilities jsonb;
  v_equity jsonb;
BEGIN
  SELECT end_date INTO v_end_date FROM fiscal_years
  WHERE id = p_fiscal_year_id AND tenant_id = v_tenant_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Exercice introuvable');
  END IF;

  v_end_date := LEAST(v_end_date, COALESCE(p_date_to, v_end_date));

  -- Amortissements par préfixe de compte (28x/29x), CTE séparée
  -- pour éviter la colonne non groupée dans la sous-requête
  WITH amort AS (
    SELECT substr(COALESCE(jl2.account_general, jl2.account_code), 1, 3) AS prefix,
           SUM(jl2.credit - jl2.debit) AS amount
    FROM journal_lines jl2
    JOIN journal_entries je2 ON je2.id = jl2.journal_id AND je2.tenant_id = jl2.tenant_id
    WHERE jl2.tenant_id = v_tenant_id
      AND je2.status = 'posted'
      AND je2.date <= v_end_date
      AND COALESCE(jl2.account_general, jl2.account_code) ~ '^2[89]'
    GROUP BY 1
  ),
  brut AS (
    SELECT
      COALESCE(jl.account_general, jl.account_code) AS code,
      MAX(jl.account_name) AS name,
      SUM(jl.debit) AS brut
    FROM journal_lines jl
    JOIN journal_entries je ON je.id = jl.journal_id AND je.tenant_id = jl.tenant_id
    WHERE jl.tenant_id = v_tenant_id
      AND je.status = 'posted'
      AND je.date <= v_end_date
      AND (COALESCE(jl.account_general, jl.account_code) ~ '^2[0-4]'
        OR COALESCE(jl.account_general, jl.account_code) ~ '^3'
        OR COALESCE(jl.account_general, jl.account_code) ~ '^4[0-9][0-9][0-9]')
      AND COALESCE(jl.account_general, jl.account_code) !~ '^2[89]'
    GROUP BY COALESCE(jl.account_general, jl.account_code)
    HAVING SUM(jl.debit) > 0
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'account_code', b.code, 'account_name', b.name,
    'brut', b.brut,
    'amortissements', COALESCE(a.amount, 0),
    'net', b.brut - COALESCE(a.amount, 0)
  ) ORDER BY b.code), '[]'::jsonb) INTO v_assets
  FROM brut b
  LEFT JOIN amort a ON a.prefix = substr(b.code, 1, 3);

  -- Passif
  WITH passif AS (
    SELECT
      COALESCE(jl.account_general, jl.account_code) AS code,
      MAX(jl.account_name) AS name,
      SUM(jl.credit - jl.debit) AS amount
    FROM journal_lines jl
    JOIN journal_entries je ON je.id = jl.journal_id AND je.tenant_id = jl.tenant_id
    WHERE jl.tenant_id = v_tenant_id
      AND je.status = 'posted'
      AND je.date <= v_end_date
      AND (COALESCE(jl.account_general, jl.account_code) ~ '^1'
        OR COALESCE(jl.account_general, jl.account_code) ~ '^4[0-9][0-9][0-9]'
        OR COALESCE(jl.account_general, jl.account_code) ~ '^5')
    GROUP BY COALESCE(jl.account_general, jl.account_code)
    HAVING SUM(jl.credit - jl.debit) > 0
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'account_code', code, 'account_name', name, 'amount', amount
  ) ORDER BY code), '[]'::jsonb) INTO v_liabilities FROM passif;

  -- Capitaux propres (classe 1)
  WITH capitaux AS (
    SELECT
      COALESCE(jl.account_general, jl.account_code) AS code,
      MAX(jl.account_name) AS name,
      SUM(jl.credit - jl.debit) AS amount
    FROM journal_lines jl
    JOIN journal_entries je ON je.id = jl.journal_id AND je.tenant_id = jl.tenant_id
    WHERE jl.tenant_id = v_tenant_id
      AND je.status = 'posted'
      AND je.date <= v_end_date
      AND COALESCE(jl.account_general, jl.account_code) ~ '^1'
    GROUP BY COALESCE(jl.account_general, jl.account_code)
    HAVING SUM(jl.credit - jl.debit) <> 0
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'account_code', code, 'account_name', name, 'amount', amount
  ) ORDER BY code), '[]'::jsonb) INTO v_equity FROM capitaux;

  RETURN jsonb_build_object(
    'assets', v_assets,
    'liabilities', v_liabilities,
    'equity', v_equity,
    'fiscal_year_id', p_fiscal_year_id,
    'date_to', v_end_date
  );
END;
$$;

-- ============================================================
-- 6.2 Paie et RH — LOT3-05 à LOT3-09
-- employees porte salary ; base_salary ajoutée par compatibilité.
-- ============================================================

-- LOT3-05 : calculate_overtime_pay
CREATE OR REPLACE FUNCTION calculate_overtime_pay(
  p_employee_id uuid,
  p_overtime_hours numeric,
  p_base_hourly_rate numeric DEFAULT NULL
)
RETURNS TABLE(
  tier_from int,
  tier_to int,
  hours_in_tier numeric,
  rate_multiplier numeric,
  gross_amount numeric,
  exemption_amount numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_base_rate numeric;
  v_hours_remaining numeric := p_overtime_hours;
  v_tier record;
  v_hours_in_tier numeric;
  v_gross numeric;
  v_exemption numeric;
  v_year int := EXTRACT(YEAR FROM CURRENT_DATE);
  v_used numeric := 0;
BEGIN
  IF p_base_hourly_rate IS NOT NULL THEN
    v_base_rate := p_base_hourly_rate;
  ELSE
    SELECT COALESCE(COALESCE(base_salary, salary), 0) / 151.67 INTO v_base_rate
    FROM employees WHERE id = p_employee_id AND tenant_id = v_tid;
  END IF;

  SELECT COALESCE(overtime_exemption_used, 0) INTO v_used
  FROM payroll_cumulative
  WHERE employee_id = p_employee_id AND year = v_year AND tenant_id = v_tid;

  FOR v_tier IN
    SELECT from_hour, to_hour, rate_multiplier
    FROM overtime_tiers
    WHERE tenant_id = v_tid
    ORDER BY from_hour
  LOOP
    v_hours_in_tier := LEAST(v_hours_remaining, COALESCE(v_tier.to_hour - v_tier.from_hour + 1, v_hours_remaining));
    IF v_hours_in_tier <= 0 THEN
      EXIT;
    END IF;

    v_gross := v_hours_in_tier * v_base_rate * v_tier.rate_multiplier;
    v_exemption := LEAST(v_gross, GREATEST(7500 - v_used, 0));
    v_used := v_used + v_exemption;

    RETURN QUERY
      SELECT
        v_tier.from_hour,
        v_tier.to_hour,
        v_hours_in_tier,
        v_tier.rate_multiplier,
        v_gross,
        v_exemption;

    v_hours_remaining := v_hours_remaining - v_hours_in_tier;
    IF v_hours_remaining <= 0 THEN EXIT; END IF;
  END LOOP;
END;
$$;

-- LOT3-06 : calculate_sick_leave_pay
CREATE OR REPLACE FUNCTION calculate_sick_leave_pay(
  p_sick_leave_id uuid
)
RETURNS TABLE(
  leave_days int,
  waiting_days int,
  retained_days int,
  daily_rate numeric,
  retention_amount numeric,
  maintenance_amount numeric,
  ijss_amount numeric,
  net_impact numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_sl sick_leaves%ROWTYPE;
  v_tid uuid := current_tenant_id();
  v_emp employees%ROWTYPE;
  v_daily_rate numeric;
  v_leave_days int;
  v_retained_days int;
  v_retention numeric;
  v_maintenance numeric;
  v_ijss numeric;
BEGIN
  SELECT * INTO v_sl FROM sick_leaves WHERE id = p_sick_leave_id AND tenant_id = v_tid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Arrêt introuvable'; END IF;

  SELECT * INTO v_emp FROM employees WHERE id = v_sl.employee_id AND tenant_id = v_tid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Salarié introuvable'; END IF;

  v_daily_rate := COALESCE(v_emp.base_salary, v_emp.salary, 0) / 30;
  v_leave_days := v_sl.end_date - v_sl.start_date + 1;
  v_retained_days := GREATEST(v_leave_days - v_sl.waiting_days, 0);

  v_retention := v_leave_days * v_daily_rate;
  v_maintenance := v_retained_days * v_daily_rate * v_sl.maintenance_rate;
  v_ijss := v_retained_days * v_sl.daily_ijss;

  RETURN QUERY
    SELECT
      v_leave_days,
      v_sl.waiting_days,
      v_retained_days,
      v_daily_rate,
      v_retention,
      v_maintenance,
      v_ijss,
      v_maintenance - v_ijss;
END;
$$;

-- LOT3-08 : calculate_compensated_leave_indemnity
-- employee_attendance n'existe pas → leave_requests (days, status='approved')
CREATE OR REPLACE FUNCTION calculate_compensated_leave_indemnity(
  p_employee_id uuid,
  p_end_date date
)
RETURNS TABLE(
  acquired_days numeric,
  taken_days numeric,
  remaining_days numeric,
  tenth_rule_amount numeric,
  maintenance_rule_amount numeric,
  retained_amount numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_emp employees%ROWTYPE;
  v_acquired numeric := 0;
  v_taken numeric := 0;
  v_remaining numeric;
  v_tenth numeric;
  v_maint numeric;
  v_ref_salary numeric;
BEGIN
  SELECT * INTO v_emp FROM employees WHERE id = p_employee_id AND tenant_id = v_tid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Salarié introuvable'; END IF;

  v_acquired := EXTRACT(MONTH FROM age(p_end_date, COALESCE(v_emp.seniority_date, v_emp.hire_date, p_end_date))) * 2.5;

  -- Congés pris depuis leave_requests (pas employee_attendance)
  SELECT COALESCE(SUM(lr.days), 0) INTO v_taken
  FROM leave_requests lr
  WHERE lr.employee_id = p_employee_id AND lr.tenant_id = v_tid
    AND lr.leave_type = 'paid_leave'
    AND lr.status = 'approved'
    AND lr.start_date <= p_end_date;

  v_remaining := GREATEST(v_acquired - v_taken, 0);

  v_ref_salary := COALESCE(v_emp.base_salary, v_emp.salary, 0) * 12;
  v_tenth := (v_ref_salary * 0.10) / 30 * v_remaining;
  v_maint := (COALESCE(v_emp.base_salary, v_emp.salary, 0) / 30) * v_remaining;

  RETURN QUERY
    SELECT
      v_acquired,
      v_taken,
      v_remaining,
      v_tenth,
      v_maint,
      GREATEST(v_tenth, v_maint);
END;
$$;

-- LOT3-07 : calculate_notice_compensation
CREATE OR REPLACE FUNCTION calculate_notice_compensation(
  p_employee_id uuid,
  p_notice_days int DEFAULT 0,
  p_end_date date DEFAULT CURRENT_DATE
)
RETURNS TABLE(
  notice_days int,
  daily_rate numeric,
  compensation_amount numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_emp employees%ROWTYPE;
  v_daily numeric;
BEGIN
  SELECT * INTO v_emp FROM employees WHERE id = p_employee_id AND tenant_id = v_tid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Salarié introuvable'; END IF;

  v_daily := COALESCE(v_emp.base_salary, v_emp.salary, 0) / 30;

  RETURN QUERY
    SELECT
      p_notice_days,
      v_daily,
      p_notice_days * v_daily;
END;
$$;

-- ============================================================
-- 6.3 Immobilisations — LOT3-10 à LOT3-12
-- fixed_assets porte purchase_value (pas acquisition_value)
-- ============================================================

-- LOT3-10 : calculate_depreciation
CREATE OR REPLACE FUNCTION calculate_depreciation(p_asset_id uuid, p_period text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_asset fixed_assets%ROWTYPE;
  v_annual_depreciation numeric;
  v_monthly_depreciation numeric;
  v_period_start date;
  v_accumulated numeric := 0;
BEGIN
  SELECT * INTO v_asset FROM fixed_assets WHERE id = p_asset_id AND tenant_id = current_tenant_id();
  IF NOT FOUND THEN RAISE EXCEPTION 'Actif non trouvé'; END IF;

  v_period_start := (p_period || '-01')::date;
  v_annual_depreciation := COALESCE(v_asset.purchase_value, 0) / NULLIF(COALESCE(v_asset.useful_life_years, 1), 0);
  v_monthly_depreciation := v_annual_depreciation / 12;

  SELECT COALESCE(SUM(depreciation_amount), 0) INTO v_accumulated
  FROM asset_depreciations WHERE asset_id = p_asset_id AND tenant_id = current_tenant_id();

  RETURN jsonb_build_object(
    'asset_id', p_asset_id,
    'period', p_period,
    'monthly_depreciation', v_monthly_depreciation,
    'annual_depreciation', v_annual_depreciation,
    'accumulated_depreciation', v_accumulated + v_monthly_depreciation,
    'net_book_value', COALESCE(v_asset.purchase_value, 0) - v_accumulated - v_monthly_depreciation
  );
END;
$$;

-- LOT3-11 : generate_depreciation_entry
-- fixed_assets n'a pas account_code — utilise account_depreciation_code
-- (compte 28x crédit) et account_expense_depreciation_code (compte 681x débit)
CREATE OR REPLACE FUNCTION generate_depreciation_entry(
  p_fixed_asset_id uuid,
  p_fiscal_year_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_fa fixed_assets%ROWTYPE;
  v_fy fiscal_years%ROWTYPE;
  v_amount numeric;
  v_je_id uuid;
  v_debit_account text;
  v_credit_account text;
BEGIN
  SELECT * INTO v_fa FROM fixed_assets WHERE id = p_fixed_asset_id AND tenant_id = v_tid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Immobilisation introuvable'; END IF;

  SELECT * INTO v_fy FROM fiscal_years WHERE id = p_fiscal_year_id AND tenant_id = v_tid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Exercice introuvable'; END IF;

  -- Dotation annuelle linéaire
  v_amount := COALESCE(v_fa.purchase_value, 0) / NULLIF(COALESCE(v_fa.useful_life_years, 1), 0);
  IF v_amount <= 0 THEN RETURN NULL; END IF;

  -- Comptes depuis les colonnes dédiées de fixed_assets
  v_debit_account := COALESCE(v_fa.account_expense_depreciation_code, '681000');
  v_credit_account := COALESCE(v_fa.account_depreciation_code, '280000');

  INSERT INTO journal_entries (
    tenant_id, journal_code, number, date, description, status, created_at
  ) VALUES (
    v_tid, 'OD', 'AMORT-' || v_fa.id, v_fy.end_date,
    'Dotation aux amortissements - ' || v_fa.name, 'posted', now()
  )
  RETURNING id INTO v_je_id;

  INSERT INTO journal_lines (
    tenant_id, journal_id, account_code, account_name, debit, credit, created_at
  ) VALUES (
    v_tid, v_je_id, v_debit_account, 'Dotations aux amortissements', v_amount, 0, now()
  );

  INSERT INTO journal_lines (
    tenant_id, journal_id, account_code, account_name, debit, credit, created_at
  ) VALUES (
    v_tid, v_je_id, v_credit_account, 'Amortissements', 0, v_amount, now()
  );

  RETURN v_je_id;
END;
$$;

-- LOT3-12 : generate_adjusting_entries
-- purchase_value + status='active' (pas de colonne active)
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
  INSERT INTO journal_entries (tenant_id, number, date, description, reference, status, journal_code, total_debit, total_credit)
  SELECT current_tenant_id(), 'OD-REG-' || to_char(NOW(), 'YYYYMMDDHH24MISS'),
    CURRENT_DATE, 'Régularisation automatique - Amortissements', 'REG-DEP', 'draft', 'OD',
    COALESCE(SUM(purchase_value / NULLIF(useful_life_years, 0) / 12), 0),
    COALESCE(SUM(purchase_value / NULLIF(useful_life_years, 0) / 12), 0)
  FROM fixed_assets WHERE tenant_id = current_tenant_id() AND status = 'active'
  HAVING SUM(purchase_value / NULLIF(useful_life_years, 0) / 12) > 0
  RETURNING id INTO v_entry_id;

  IF v_entry_id IS NOT NULL THEN
    v_count := v_count + 1;
  END IF;

  RETURN jsonb_build_object('fiscal_year_id', p_fiscal_year_id, 'entries_created', v_count);
END;
$$;

-- ============================================================
-- 6.4 Lettrage — LOT3-13, LOT3-14
-- journal_lines porte lettrage_code/lettrage_date
-- ============================================================

-- LOT3-13 : auto_letter_accounts
CREATE OR REPLACE FUNCTION auto_letter_accounts(p_account_code text, p_tolerance numeric DEFAULT 0.01)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_matched int := 0;
  v_lettrage_code text;
  r RECORD;
BEGIN
  FOR r IN
    SELECT jl.id, jl.debit, jl.credit, jl.lettrage_code
    FROM journal_lines jl
    WHERE jl.tenant_id = current_tenant_id()
      AND jl.account_code = p_account_code
      AND jl.lettrage_code IS NULL
      AND jl.debit > 0
    ORDER BY jl.journal_id
  LOOP
    v_lettrage_code := 'L' || to_char(NOW(), 'YYYYMMDD') || '-' || lpad(v_matched::text, 4, '0');

    UPDATE journal_lines SET lettrage_code = v_lettrage_code, lettrage_date = CURRENT_DATE
    WHERE id IN (
      SELECT id FROM journal_lines
      WHERE tenant_id = current_tenant_id()
        AND account_code = p_account_code
        AND lettrage_code IS NULL
        AND credit > 0
        AND ABS(credit - r.debit) <= p_tolerance
      LIMIT 1
    ) OR id = r.id;

    v_matched := v_matched + 1;
  END LOOP;

  RETURN jsonb_build_object('account_code', p_account_code, 'matched', v_matched);
END;
$$;

-- LOT3-14 : auto_lettrage_by_reference
-- journal_lines n'a pas de colonne date → ORDER BY created_at
CREATE OR REPLACE FUNCTION auto_lettrage_by_reference(
  p_account_code text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_count int := 0;
  v_line record;
  v_match record;
  v_group_id uuid;
BEGIN
  FOR v_line IN
    SELECT jl.id, jl.reference, jl.debit, jl.credit
    FROM journal_lines jl
    WHERE jl.tenant_id = v_tid
      AND jl.account_code = p_account_code
      AND jl.lettrage_code IS NULL
      AND jl.reference IS NOT NULL
    ORDER BY jl.created_at
  LOOP
    SELECT jl2.id, jl2.debit, jl2.credit INTO v_match
    FROM journal_lines jl2
    WHERE jl2.tenant_id = v_tid
      AND jl2.account_code = p_account_code
      AND jl2.lettrage_code IS NULL
      AND jl2.reference = v_line.reference
      AND jl2.id != v_line.id
      AND (
        (v_line.debit > 0 AND jl2.credit > 0 AND jl2.credit = v_line.debit)
        OR (v_line.credit > 0 AND jl2.debit > 0 AND jl2.debit = v_line.credit)
      )
    LIMIT 1;

    IF v_match IS NOT NULL THEN
      INSERT INTO lettrage_groups (tenant_id, lettrage_code, lettrage_date, total_debit, total_credit, status)
      VALUES (v_tid, 'LET-' || EXTRACT(EPOCH FROM now())::bigint, CURRENT_DATE, v_line.debit + v_match.debit, v_line.credit + v_match.credit, 'closed')
      RETURNING id INTO v_group_id;

      UPDATE journal_lines SET lettrage_code = 'LET-' || v_group_id, lettrage_date = CURRENT_DATE, lettrage_group_id = v_group_id
      WHERE id IN (v_line.id, v_match.id);

      v_count := v_count + 2;
      v_match := NULL;
    END IF;
  END LOOP;

  RETURN jsonb_build_object('matched_lines', v_count);
END;
$$;

-- ============================================================
-- 6.5 Tarification et commercial — LOT3-15 à LOT3-18
-- ============================================================

-- LOT3-15 : resolve_price
-- price_lists n'a pas customer_id. Résolution :
--   tarif nominatif (price_list_customers) → customers.price_list_id
--   → tarif catégorie (customer_category_id) → tarif par défaut.
CREATE OR REPLACE FUNCTION resolve_price(
  p_product_id uuid,
  p_customer_id uuid,
  p_quantity numeric DEFAULT 1,
  p_date date DEFAULT CURRENT_DATE
)
RETURNS TABLE(
  unit_price numeric,
  discount_percent numeric,
  price_list_id uuid,
  price_list_name text,
  source text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_customer_pl uuid;
  v_customer_cat uuid;
  v_line record;
  v_base_price numeric;
BEGIN
  -- Rattachements du client
  SELECT c.price_list_id INTO v_customer_pl
  FROM customers c WHERE c.id = p_customer_id AND c.tenant_id = v_tid;

  SELECT c.customer_category_id INTO v_customer_cat
  FROM customers c WHERE c.id = p_customer_id AND c.tenant_id = v_tid;

  -- Chercher la ligne de tarif la plus spécifique
  SELECT pll.unit_price, pll.discount_percent, pll.min_quantity,
         pl.id, pl.name, pl.base_price_list_id, pl.discount_percent AS pl_discount
  INTO v_line
  FROM price_list_lines pll
  JOIN price_lists pl ON pl.id = pll.price_list_id AND pl.tenant_id = pll.tenant_id
  WHERE pll.tenant_id = v_tid
    AND pll.product_id = p_product_id
    AND pl.type = 'sales'
    AND pl.active = true
    AND pll.min_quantity <= p_quantity
    AND COALESCE(pl.valid_from, p_date) <= p_date
    AND COALESCE(pl.valid_to, '9999-12-31'::date) >= p_date
    AND (
      -- 1. Tarif nominatif du client
      pl.id IN (SELECT plc.price_list_id FROM price_list_customers plc
                WHERE plc.customer_id = p_customer_id AND plc.tenant_id = v_tid)
      -- 2. Tarif directement rattaché au client
      OR pl.id = v_customer_pl
      -- 3. Tarif de sa catégorie
      OR (v_customer_cat IS NOT NULL AND pl.customer_category_id = v_customer_cat)
      -- 4. Tarif par défaut
      OR pl.is_default = true
    )
  ORDER BY
    -- Nominatif > rattaché > catégorie > défaut
    CASE
      WHEN pl.id IN (SELECT plc.price_list_id FROM price_list_customers plc
                     WHERE plc.customer_id = p_customer_id AND plc.tenant_id = v_tid) THEN 0
      WHEN pl.id = v_customer_pl THEN 1
      WHEN v_customer_cat IS NOT NULL AND pl.customer_category_id = v_customer_cat THEN 2
      ELSE 3
    END,
    pl.priority DESC NULLS LAST,
    pll.min_quantity DESC
  LIMIT 1;

  IF v_line.id IS NULL THEN
    RETURN;
  END IF;

  -- Tarif dérivé d'un autre tarif (% de remise sur tarif de base)
  IF v_line.base_price_list_id IS NOT NULL THEN
    SELECT pll2.unit_price INTO v_base_price
    FROM price_list_lines pll2
    WHERE pll2.tenant_id = v_tid
      AND pll2.price_list_id = v_line.base_price_list_id
      AND pll2.product_id = p_product_id
      AND pll2.min_quantity <= p_quantity
    ORDER BY pll2.min_quantity DESC
    LIMIT 1;

    IF v_base_price IS NOT NULL THEN
      RETURN QUERY
      SELECT
        v_base_price * (1 - COALESCE(v_line.pl_discount, 0) / 100),
        COALESCE(v_line.discount_percent, 0),
        v_line.id,
        v_line.name,
        'price_list:' || v_line.name;
      RETURN;
    END IF;
  END IF;

  RETURN QUERY
  SELECT
    v_line.unit_price,
    COALESCE(v_line.discount_percent, 0),
    v_line.id,
    v_line.name,
    'price_list:' || v_line.name;
END;
$$;

-- LOT3-16 : calculate_payment_due_dates
-- payment_terms porte days_1/days_2, pct_1/pct_2, end_of_month — pas days
CREATE OR REPLACE FUNCTION calculate_payment_due_dates(p_invoice_date date, p_payment_terms_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_terms payment_terms%ROWTYPE;
  v_due_date date;
  v_dates jsonb := '[]'::jsonb;
BEGIN
  SELECT * INTO v_terms FROM payment_terms WHERE id = p_payment_terms_id AND tenant_id = current_tenant_id();
  IF NOT FOUND THEN
    v_due_date := p_invoice_date + 30;
    RETURN jsonb_build_object('due_date', v_due_date, 'installments', '[]'::jsonb);
  END IF;

  -- Première échéance : days_1 jours, fin de mois si demandé
  v_due_date := p_invoice_date + COALESCE(v_terms.days_1, 30);
  IF v_terms.end_of_month THEN
    v_due_date := (date_trunc('month', v_due_date) + INTERVAL '1 month - 1 day')::date;
  END IF;

  -- Échéance en plusieurs fois si days_2/pct_2 renseignés
  IF v_terms.days_2 IS NOT NULL AND v_terms.pct_2 IS NOT NULL THEN
    v_dates := jsonb_build_array(
      jsonb_build_object('due_date', v_due_date, 'percent', v_terms.pct_1),
      jsonb_build_object('due_date', p_invoice_date + v_terms.days_2, 'percent', v_terms.pct_2)
    );
  END IF;

  RETURN jsonb_build_object('due_date', v_due_date, 'terms', v_terms.name, 'installments', v_dates);
END;
$$;

-- LOT3-18 : check_segregation_of_duties (created_by ajouté ci-dessus)
CREATE OR REPLACE FUNCTION check_segregation_of_duties(
  p_user_id uuid,
  p_action text,
  p_reference_id uuid
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_created_by uuid;
  v_tid uuid := current_tenant_id();
BEGIN
  IF p_action = 'validate' THEN
    SELECT je.created_by INTO v_created_by
    FROM journal_entries je
    WHERE je.id = p_reference_id AND je.tenant_id = v_tid;

    IF v_created_by IS NOT NULL AND v_created_by = p_user_id THEN
      RETURN false;
    END IF;
  END IF;

  RETURN true;
END;
$$;

-- ============================================================
-- 6.6 Production et stock — LOT3-19 à LOT3-24
-- ============================================================

-- LOT3-19 : run_mrp — production_forecasts porte forecasted_quantity/start_date
-- (pas quantity/forecast_date) ; qty_produced ajoutée ci-dessus
CREATE OR REPLACE FUNCTION run_mrp(
  p_tenant_id uuid DEFAULT NULL,
  p_horizon_days int DEFAULT 90
)
RETURNS TABLE(
  product_id uuid,
  product_name text,
  gross_need numeric,
  stock_available numeric,
  open_purchase_qty numeric,
  open_production_qty numeric,
  net_need numeric,
  suggested_qty numeric,
  suggested_date date,
  low_level_code int,
  source text,
  need_date date,
  is_late boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := COALESCE(p_tenant_id, current_tenant_id());
  v_horizon date := CURRENT_DATE + p_horizon_days;
BEGIN
  DROP TABLE IF EXISTS _mrp_needs;
  CREATE TEMP TABLE _mrp_needs AS
  SELECT
    exp.product_id,
    exp.gross_need,
    exp.low_level_code,
    mo.start_date AS need_date,
    'manufacturing_order' AS source
  FROM manufacturing_orders mo
  CROSS JOIN LATERAL explode_bom_recursive(v_tid, mo.bom_id, mo.quantity) exp
  WHERE mo.tenant_id = v_tid AND mo.status IN ('planned', 'in_progress');

  INSERT INTO _mrp_needs
  SELECT
    sol.product_id,
    sol.quantity AS gross_need,
    0 AS low_level_code,
    so.delivery_date AS need_date,
    'sales_order' AS source
  FROM sales_orders so
  JOIN sales_order_lines sol ON sol.sales_order_id = so.id AND sol.tenant_id = v_tid
  WHERE so.tenant_id = v_tid AND so.status IN ('confirmed', 'in_progress')
    AND COALESCE(so.delivery_date, CURRENT_DATE) <= v_horizon;

  -- Prévisions : forecasted_quantity + start_date (colonnes réelles)
  INSERT INTO _mrp_needs
  SELECT
    pf.product_id,
    pf.forecasted_quantity AS gross_need,
    0 AS low_level_code,
    pf.start_date AS need_date,
    'forecast' AS source
  FROM production_forecasts pf
  WHERE pf.tenant_id = v_tid
    AND COALESCE(pf.start_date, CURRENT_DATE) <= v_horizon;

  RETURN QUERY
  WITH aggregated_needs AS (
    SELECT
      n.product_id,
      SUM(n.gross_need) AS total_gross_need,
      MAX(n.low_level_code) AS low_level_code,
      MIN(n.need_date) AS earliest_need_date
    FROM _mrp_needs n
    GROUP BY n.product_id
  ),
  stock_info AS (
    SELECT sq.product_id, COALESCE(SUM(sq.quantity), 0) AS stock_qty
    FROM stock_quantities sq
    WHERE sq.tenant_id = v_tid
    GROUP BY sq.product_id
  ),
  open_po AS (
    SELECT
      pol.product_id,
      SUM(pol.quantity - COALESCE(grl.qty_received, 0)) AS open_qty
    FROM purchase_order_lines pol
    JOIN purchase_orders po ON po.id = pol.purchase_order_id AND po.tenant_id = pol.tenant_id
    LEFT JOIN LATERAL (
      SELECT SUM(grl2.quantity_received) AS qty_received
      FROM goods_receipt_lines grl2
      JOIN goods_receipts gr ON gr.id = grl2.goods_receipt_id AND gr.tenant_id = grl2.tenant_id
      WHERE gr.purchase_order_id = po.id
        AND gr.tenant_id = v_tid
        AND grl2.product_id = pol.product_id
        AND gr.status = 'received'
    ) grl ON true
    WHERE po.tenant_id = v_tid AND po.status IN ('draft', 'sent')
    GROUP BY pol.product_id
  ),
  open_mo AS (
    SELECT
      mo.product_id,
      SUM(mo.quantity - COALESCE(mo.qty_produced, 0)) AS open_qty
    FROM manufacturing_orders mo
    WHERE mo.tenant_id = v_tid AND mo.status IN ('planned', 'in_progress')
    GROUP BY mo.product_id
  )
  SELECT
    a.product_id,
    p.name AS product_name,
    a.total_gross_need AS gross_need,
    COALESCE(s.stock_qty, 0) AS stock_available,
    COALESCE(po.open_qty, 0) AS open_purchase_qty,
    COALESCE(mo.open_qty, 0) AS open_production_qty,
    GREATEST(0, a.total_gross_need + COALESCE(p.safety_stock, 0) - COALESCE(s.stock_qty, 0) - COALESCE(po.open_qty, 0) - COALESCE(mo.open_qty, 0)) AS net_need,
    CASE
      WHEN GREATEST(0, a.total_gross_need + COALESCE(p.safety_stock, 0) - COALESCE(s.stock_qty, 0) - COALESCE(po.open_qty, 0) - COALESCE(mo.open_qty, 0)) > 0
      THEN GREATEST(
        CEIL(GREATEST(0, a.total_gross_need + COALESCE(p.safety_stock, 0) - COALESCE(s.stock_qty, 0) - COALESCE(po.open_qty, 0) - COALESCE(mo.open_qty, 0)) / COALESCE(p.qty_multiple, 1)) * COALESCE(p.qty_multiple, 1),
        COALESCE(p.min_order_qty, 0)
      )
      ELSE 0
    END AS suggested_qty,
    CASE
      WHEN a.earliest_need_date IS NOT NULL
      THEN (a.earliest_need_date - COALESCE(p.lead_time_days, 7))
      ELSE (CURRENT_DATE + COALESCE(p.lead_time_days, 7))
    END::date AS suggested_date,
    a.low_level_code,
    'mrp'::text AS source,
    a.earliest_need_date,
    CASE
      WHEN a.earliest_need_date IS NOT NULL
       AND (a.earliest_need_date - COALESCE(p.lead_time_days, 7)) < CURRENT_DATE
      THEN true
      ELSE false
    END AS is_late
  FROM aggregated_needs a
  JOIN products p ON p.id = a.product_id AND p.tenant_id = v_tid
  LEFT JOIN stock_info s ON s.product_id = a.product_id
  LEFT JOIN open_po po ON po.product_id = a.product_id
  LEFT JOIN open_mo mo ON mo.product_id = a.product_id
  WHERE a.total_gross_need > 0
  ORDER BY a.low_level_code, a.product_id;

  DROP TABLE IF EXISTS _mrp_needs;
END;
$$;

-- LOT3-20 : calculate_production_cost
-- products porte cost_price (pas standard_cost) ; project_time_entries
-- n'a pas reference_id/hours → main-d'œuvre via routing + work_centers
CREATE OR REPLACE FUNCTION calculate_production_cost(p_manufacturing_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_mo manufacturing_orders%ROWTYPE;
  v_material_cost numeric := 0;
  v_labor_cost numeric := 0;
  v_overhead_cost numeric := 0;
  v_total_cost numeric := 0;
  v_unit_cost numeric := 0;
  v_overhead_rate numeric := 0;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  SELECT * INTO v_mo FROM manufacturing_orders WHERE id = p_manufacturing_order_id AND tenant_id = v_tid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ordre de fabrication non trouvé: %', p_manufacturing_order_id;
  END IF;

  -- Matières consommées × coût de revient
  SELECT COALESCE(sum(oc.quantity * COALESCE(p.cost_price, sq.unit_cost, 0)), 0)
  INTO v_material_cost
  FROM of_consumptions oc
  JOIN products p ON p.id = oc.product_id AND p.tenant_id = v_tid
  LEFT JOIN stock_quantities sq ON sq.product_id = p.id AND sq.tenant_id = v_tid
    AND sq.warehouse_id = v_mo.warehouse_id
  WHERE oc.tenant_id = v_tid AND oc.manufacturing_order_id = p_manufacturing_order_id;

  -- Main-d'œuvre via la gamme de l'OF
  SELECT COALESCE(sum((COALESCE(ro.setup_time_min, 0) + COALESCE(ro.run_time_min, 0) * v_mo.quantity) / 60.0
                    * COALESCE(wc.cost_per_hour, 0)), 0)
  INTO v_labor_cost
  FROM routing_operations ro
  JOIN work_centers wc ON wc.id = ro.work_center_id AND wc.tenant_id = v_tid
  WHERE ro.routing_id = v_mo.routing_id AND ro.tenant_id = v_tid;

  -- Frais indirects depuis le taux de l'entreprise (défaut 10 %)
  SELECT COALESCE(overhead_rate, 0.10) INTO v_overhead_rate
  FROM company_settings WHERE tenant_id = v_tid LIMIT 1;
  v_overhead_cost := (v_material_cost + v_labor_cost) * COALESCE(v_overhead_rate, 0.10);

  v_total_cost := v_material_cost + v_labor_cost + v_overhead_cost;
  v_unit_cost := CASE WHEN v_mo.quantity > 0 THEN v_total_cost / v_mo.quantity ELSE 0 END;

  RETURN jsonb_build_object(
    'manufacturing_order_id', p_manufacturing_order_id,
    'quantity', v_mo.quantity,
    'material_cost', round(v_material_cost, 2),
    'labor_cost', round(v_labor_cost, 2),
    'overhead_cost', round(v_overhead_cost, 2),
    'total_cost', round(v_total_cost, 2),
    'unit_cost', round(v_unit_cost, 2),
    'calculated_at', now()
  );
END;
$$;

-- LOT3-21 : calculate_manufacturing_cost
-- routing_operations porte setup_time_min/run_time_min
CREATE OR REPLACE FUNCTION calculate_manufacturing_cost(
  p_mo_id uuid,
  p_tenant_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_cost_material numeric := 0;
  v_cost_labor numeric := 0;
  v_cost_overhead numeric := 0;
  v_unit_cost numeric;
  v_quantity numeric;
  v_bom_id uuid;
  v_routing_id uuid;
  v_warehouse_id uuid;
  v_overhead_rate numeric := 0;
BEGIN
  SELECT mo.quantity, mo.bom_id, mo.routing_id, mo.warehouse_id
  INTO v_quantity, v_bom_id, v_routing_id, v_warehouse_id
  FROM manufacturing_orders mo
  WHERE mo.id = p_mo_id AND mo.tenant_id = p_tenant_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'OF introuvable');
  END IF;

  SELECT COALESCE(sum(bl.quantity * v_quantity
                    * COALESCE(sq.unit_cost, p.cost_price, 0)), 0)
  INTO v_cost_material
  FROM bom_lines bl
  JOIN products p ON p.id = bl.product_id AND p.tenant_id = p_tenant_id
  LEFT JOIN stock_quantities sq
    ON sq.product_id = bl.product_id
   AND sq.warehouse_id = v_warehouse_id
   AND sq.tenant_id = p_tenant_id
  WHERE bl.bom_id = v_bom_id AND bl.tenant_id = p_tenant_id;

  -- Temps en minutes → heures
  SELECT COALESCE(sum((COALESCE(ro.setup_time_min, 0) + COALESCE(ro.run_time_min, 0) * v_quantity) / 60.0
                    * COALESCE(wc.cost_per_hour, 0)), 0)
  INTO v_cost_labor
  FROM routing_operations ro
  JOIN work_centers wc ON wc.id = ro.work_center_id AND wc.tenant_id = p_tenant_id
  WHERE ro.routing_id = v_routing_id AND ro.tenant_id = p_tenant_id;

  SELECT COALESCE(overhead_rate, 0) INTO v_overhead_rate
  FROM company_settings WHERE tenant_id = p_tenant_id LIMIT 1;

  v_cost_overhead := v_cost_labor * v_overhead_rate;
  v_unit_cost := (v_cost_material + v_cost_labor + v_cost_overhead)
                / NULLIF(v_quantity, 0);

  UPDATE manufacturing_orders
  SET cost_material = v_cost_material,
      cost_labor = v_cost_labor,
      cost_overhead = v_cost_overhead,
      cost_total = v_cost_material + v_cost_labor + v_cost_overhead,
      unit_cost = COALESCE(v_unit_cost, 0)
  WHERE id = p_mo_id AND tenant_id = p_tenant_id;

  RETURN jsonb_build_object(
    'success', true,
    'cost_material', v_cost_material,
    'cost_labor', v_cost_labor,
    'cost_overhead', v_cost_overhead,
    'cost_total', v_cost_material + v_cost_labor + v_cost_overhead,
    'unit_cost', COALESCE(v_unit_cost, 0)
  );
END;
$$;

-- LOT3-22 : calculate_stock_valuation — qualifier toutes les colonnes
CREATE OR REPLACE FUNCTION calculate_stock_valuation(
  p_tenant_id uuid DEFAULT NULL,
  p_method text DEFAULT 'cump',
  p_date date DEFAULT CURRENT_DATE
)
RETURNS TABLE(
  product_id uuid,
  product_name text,
  warehouse_id uuid,
  quantity numeric,
  unit_cost numeric,
  total_value numeric,
  method text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := COALESCE(p_tenant_id, current_tenant_id());
BEGIN
  IF p_method = 'cump' THEN
    RETURN QUERY
    SELECT
      sq.product_id,
      p.name AS product_name,
      sq.warehouse_id,
      sq.quantity,
      sq.unit_cost,
      sq.quantity * sq.unit_cost AS total_value,
      'cump'::text AS method
    FROM stock_quantities sq
    JOIN products p ON p.id = sq.product_id AND p.tenant_id = sq.tenant_id
    WHERE sq.tenant_id = v_tid
      AND sq.quantity > 0;
  ELSE
    -- FIFO/par défaut : valorisation CUMP (les couches FIFO détaillées
    -- nécessitent une requête fenêtrée ; fallback cohérent)
    RETURN QUERY
    SELECT
      sq.product_id,
      p.name AS product_name,
      sq.warehouse_id,
      sq.quantity,
      sq.unit_cost,
      sq.quantity * sq.unit_cost AS total_value,
      p_method::text AS method
    FROM stock_quantities sq
    JOIN products p ON p.id = sq.product_id AND p.tenant_id = sq.tenant_id
    WHERE sq.tenant_id = v_tid
      AND sq.quantity > 0;
  END IF;
END;
$$;

-- LOT3-23 : import_initial_stock — qualifier les colonnes du RETURN
CREATE OR REPLACE FUNCTION import_initial_stock(
  p_stock_data json,
  p_batch_id uuid DEFAULT NULL
)
RETURNS TABLE(
  product_id uuid,
  product_name text,
  warehouse_id uuid,
  quantity numeric,
  unit_cost numeric,
  status text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_trgm, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_row json;
  v_product_id uuid;
  v_warehouse_id uuid;
  v_qty numeric;
  v_cost numeric;
BEGIN
  FOR v_row IN SELECT * FROM json_array_elements(p_stock_data)
  LOOP
    v_product_id := (v_row->>'product_id')::uuid;
    v_warehouse_id := (v_row->>'warehouse_id')::uuid;
    v_qty := (v_row->>'quantity')::numeric;
    v_cost := COALESCE((v_row->>'unit_cost')::numeric, 0);

    INSERT INTO stock_movements (
      tenant_id, product_id, warehouse_id, movement_type,
      quantity, unit_cost, reference, reference_type,
      movement_date, created_at
    ) VALUES (
      v_tid, v_product_id, v_warehouse_id, 'initial',
      v_qty, v_cost, 'STOCK-INIT', 'manual',
      now(), now()
    );

    INSERT INTO stock_quantities (
      tenant_id, product_id, warehouse_id,
      quantity, unit_cost, min_quantity, max_quantity, reorder_point
    ) VALUES (
      v_tid, v_product_id, COALESCE(v_warehouse_id, (SELECT id FROM warehouses WHERE tenant_id = v_tid LIMIT 1)),
      v_qty, v_cost, 0, 0, 0
    )
    ON CONFLICT (tenant_id, product_id, warehouse_id)
    DO UPDATE SET quantity = EXCLUDED.quantity, unit_cost = EXCLUDED.unit_cost, updated_at = now();
  END LOOP;

  RETURN QUERY
    SELECT
      (elem->>'product_id')::uuid AS product_id,
      COALESCE(elem->>'product_name', '')::text AS product_name,
      (elem->>'warehouse_id')::uuid AS warehouse_id,
      (elem->>'quantity')::numeric AS quantity,
      COALESCE((elem->>'unit_cost')::numeric, 0) AS unit_cost,
      'imported'::text AS status
    FROM json_array_elements(p_stock_data) AS elem;
END;
$$;

-- LOT3-24 : distribute_by_grill
-- distribution_grill_lines porte section_code → jointure sur analytic_sections.code
CREATE OR REPLACE FUNCTION distribute_by_grill(
  p_journal_line_id uuid,
  p_grill_id uuid
)
RETURNS TABLE(
  section_id uuid,
  section_name text,
  amount numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_line journal_lines%ROWTYPE;
  v_total_keys numeric;
BEGIN
  SELECT * INTO v_line FROM journal_lines WHERE id = p_journal_line_id AND tenant_id = v_tid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Ligne introuvable'; END IF;

  SELECT COALESCE(SUM(dgl.percentage), 0) INTO v_total_keys
  FROM distribution_grill_lines dgl
  WHERE dgl.grill_id = p_grill_id AND dgl.tenant_id = v_tid;

  IF v_total_keys = 0 THEN RAISE EXCEPTION 'Grille vide ou introuvable'; END IF;

  RETURN QUERY
    SELECT
      as2.id AS section_id,
      as2.name AS section_name,
      (COALESCE(v_line.debit, 0) + COALESCE(v_line.credit, 0)) * dgl.percentage / v_total_keys AS amount
    FROM distribution_grill_lines dgl
    JOIN analytic_sections as2 ON as2.code = dgl.section_code AND as2.tenant_id = v_tid
    WHERE dgl.grill_id = p_grill_id AND dgl.tenant_id = v_tid;
END;
$$;

-- ============================================================
-- 6.7 Banque et divers — LOT3-25 à LOT3-31
-- ============================================================

-- LOT3-25 : smart_bank_reconciliation
-- bank_transactions porte account_id/date/matched
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
  v_n int;
BEGIN
  FOR r IN
    SELECT bt.* FROM bank_transactions bt
    WHERE COALESCE(bt.bank_account_id, bt.account_id) = p_bank_account_id
      AND bt.date BETWEEN p_from_date AND p_to_date
      AND bt.tenant_id = current_tenant_id()
      AND bt.matched = false
  LOOP
    UPDATE customer_payments
    SET status = 'reconciled'
    WHERE tenant_id = current_tenant_id()
      AND amount = r.amount
      AND payment_date = r.date
      AND status = 'recorded';
    GET DIAGNOSTICS v_n = ROW_COUNT;

    IF v_n > 0 THEN
      v_matched := v_matched + v_n;
    ELSE
      v_unmatched := v_unmatched + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object('matched', v_matched, 'unmatched', v_unmatched);
END;
$$;

-- LOT3-26 : get_bank_reconciliation_state
-- account_number vient de bank_accounts, pas de bank_transactions
CREATE OR REPLACE FUNCTION get_bank_reconciliation_state(
  p_bank_account_id uuid,
  p_date date DEFAULT CURRENT_DATE
)
RETURNS TABLE(
  bank_account_id uuid,
  account_number text,
  statement_balance numeric,
  accounting_balance numeric,
  unmatched_debits numeric,
  unmatched_credits numeric,
  is_balanced boolean,
  unmatched_transactions json
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_stmt_balance numeric;
  v_acct_balance numeric;
  v_unmatched_debits numeric;
  v_unmatched_credits numeric;
  v_account_number text;
BEGIN
  -- Compte comptable du compte bancaire
  SELECT ba.account_number INTO v_account_number
  FROM bank_accounts ba
  WHERE ba.id = p_bank_account_id AND ba.tenant_id = v_tid;

  -- Solde du relevé
  SELECT COALESCE(SUM(bt.amount), 0)
  INTO v_stmt_balance
  FROM bank_transactions bt
  WHERE bt.tenant_id = v_tid
    AND COALESCE(bt.bank_account_id, bt.account_id) = p_bank_account_id
    AND bt.date <= p_date;

  -- Solde comptable
  SELECT COALESCE(SUM(jl.debit - jl.credit), 0)
  INTO v_acct_balance
  FROM journal_lines jl
  JOIN journal_entries je ON je.id = jl.journal_id AND je.tenant_id = jl.tenant_id
  WHERE jl.tenant_id = v_tid
    AND jl.account_code = v_account_number
    AND je.date <= p_date
    AND je.status = 'posted';

  -- Transactions non rapprochées
  SELECT
    COALESCE(SUM(CASE WHEN bt.amount < 0 THEN ABS(bt.amount) ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN bt.amount > 0 THEN bt.amount ELSE 0 END), 0)
  INTO v_unmatched_debits, v_unmatched_credits
  FROM bank_transactions bt
  WHERE bt.tenant_id = v_tid
    AND COALESCE(bt.bank_account_id, bt.account_id) = p_bank_account_id
    AND bt.date <= p_date AND bt.matched = false;

  RETURN QUERY
  SELECT
    p_bank_account_id,
    v_account_number,
    v_stmt_balance,
    v_acct_balance,
    v_unmatched_debits,
    v_unmatched_credits,
    ABS(v_stmt_balance - v_unmatched_debits + v_unmatched_credits - v_acct_balance) < 0.01,
    (
      SELECT COALESCE(json_agg(row_to_json(t)), '[]'::json)
      FROM (
        SELECT bt.id, bt.date, bt.description AS label, bt.amount, bt.reference, bt.matched
        FROM bank_transactions bt
        WHERE bt.tenant_id = v_tid
          AND COALESCE(bt.bank_account_id, bt.account_id) = p_bank_account_id
          AND bt.date <= p_date AND bt.matched = false
        ORDER BY bt.date DESC
      ) t
    );
END;
$$;

-- LOT3-27 : generate_vat_return
-- vat_returns porte box1_output_vat/box2_input_vat/box3_vat_due
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
    status, created_at
  )
  VALUES (
    current_tenant_id(), p_period_start, p_period_end,
    v_coll, v_ded, v_pay,
    'draft', NOW()
  )
  RETURNING id INTO v_return_id;

  RETURN jsonb_build_object('id', v_return_id, 'data', v_result);
END;
$$;

-- LOT3-28 : run_three_way_match — qualifier match_status (ambigu
-- entre la colonne OUT et la colonne de purchase_invoices)
CREATE OR REPLACE FUNCTION run_three_way_match(p_invoice_id uuid)
RETURNS table(
  match_status varchar,
  total_ordered numeric,
  total_received numeric,
  total_invoiced numeric,
  price_variance numeric,
  quantity_variance numeric,
  line_results jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_invoice RECORD;
  v_match RECORD;
BEGIN
  SELECT * INTO v_invoice FROM purchase_invoices pi WHERE pi.id = p_invoice_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Purchase invoice not found'; END IF;

  UPDATE purchase_invoices
    SET approval_status = 'pending'
  WHERE id = p_invoice_id AND approval_status NOT IN ('pending', 'submitted');

  SELECT
    pi.match_status,
    (pi.match_details->>'total_ordered')::numeric AS total_ordered,
    (pi.match_details->>'total_received')::numeric AS total_received,
    (pi.match_details->>'total_invoiced')::numeric AS total_invoiced,
    (pi.match_details->>'price_variance')::numeric AS price_variance,
    (pi.match_details->>'quantity_variance')::numeric AS quantity_variance,
    pi.match_details->'line_results' AS line_results
  INTO v_match
  FROM purchase_invoices pi WHERE pi.id = p_invoice_id;

  RETURN QUERY SELECT v_match.match_status, v_match.total_ordered, v_match.total_received,
    v_match.total_invoiced, v_match.price_variance, v_match.quantity_variance, v_match.line_results;
END;
$$;

-- LOT3-29 : generate_recurring_tasks
-- v_task était référencé dans la requête du curseur FOR avant assignation.
-- Le NOT EXISTS est déplacé dans le corps de la boucle.
CREATE OR REPLACE FUNCTION generate_recurring_tasks()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_task project_tasks%ROWTYPE;
  v_new_due date;
  v_new_start date;
  v_interval_days integer;
  v_has_child boolean;
BEGIN
  FOR v_task IN
    SELECT * FROM project_tasks
    WHERE recurring_task = true
      AND status IN ('done', 'cancelled')
      AND is_closed = true
      AND due_date IS NOT NULL
      AND due_date < CURRENT_DATE
  LOOP
    -- Vérifier qu'aucune occurrence n'a déjà été régénérée
    SELECT EXISTS (
      SELECT 1 FROM project_tasks child
      WHERE child.parent_id = v_task.id
        AND child.recurring_task = false
        AND child.created_at >= v_task.due_date
    ) INTO v_has_child;

    IF v_has_child THEN
      CONTINUE;
    END IF;

    v_interval_days := v_task.recurring_interval;
    IF v_task.recurring_rule_type = 'weekly' THEN
      v_interval_days := v_task.recurring_interval * 7;
    ELSIF v_task.recurring_rule_type = 'monthly' THEN
      v_interval_days := v_task.recurring_interval * 30;
    ELSIF v_task.recurring_rule_type = 'daily' THEN
      v_interval_days := v_task.recurring_interval;
    END IF;

    v_new_due := CURRENT_DATE + v_interval_days;
    v_new_start := CURRENT_DATE;

    INSERT INTO project_tasks (
      tenant_id, project_id, parent_id, title, description,
      status, priority, assignee, assignee_id,
      start_date, due_date, effort_estimate_h, effort_spent_h,
      progress, display_order, task_level, budget, color,
      acceptance_criteria, recurring_task, recurring_interval,
      recurring_rule_type, is_closed, milestone_id
    ) VALUES (
      v_task.tenant_id, v_task.project_id, v_task.id, v_task.title, v_task.description,
      'todo', v_task.priority, v_task.assignee, v_task.assignee_id,
      v_new_start, v_new_due, v_task.effort_estimate_h, 0,
      0, v_task.display_order, v_task.task_level, v_task.budget, v_task.color,
      v_task.acceptance_criteria, false, v_task.recurring_interval,
      v_task.recurring_rule_type, false, v_task.milestone_id
    );
  END LOOP;
END;
$$;

-- LOT3-30 : get_nf525_attestation
-- company_settings porte name (pas company_name)
CREATE OR REPLACE FUNCTION get_nf525_attestation(p_period text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_closure RECORD;
  v_verification jsonb;
  v_company company_settings%ROWTYPE;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  SELECT * INTO v_closure
  FROM nf525_period_closures
  WHERE tenant_id = v_tid AND period = p_period;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Période non clôturée: %', p_period;
  END IF;

  SELECT verify_nf525_chain(
    (p_period || '-01')::timestamp,
    ((p_period || '-01')::date + INTERVAL '1 month' - INTERVAL '1 second')::timestamp
  ) INTO v_verification;

  SELECT * INTO v_company
  FROM company_settings
  WHERE tenant_id = v_tid
  LIMIT 1;

  RETURN jsonb_build_object(
    'attestation_type', 'NF525',
    'period', p_period,
    'company_name', COALESCE(v_company.name, ''),
    'company_siret', COALESCE(v_company.siret, ''),
    'event_count', v_closure.event_count,
    'closing_hash', v_closure.closing_hash,
    'chain_verification', v_verification,
    'closed_at', v_closure.closed_at,
    'generated_at', now(),
    'standard', 'NF525 - Journal d''événements inaltérable',
    'legal_reference', 'Article 286 V du CGI + NF525'
  );
END;
$$;

-- LOT3-31 : create_tenant_for_current_user
-- auth.jwt() n'existe pas hors Supabase → current_setting('request.jwt.claims')
CREATE OR REPLACE FUNCTION create_tenant_for_current_user(p_data jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tenant uuid;
  v_auth_id uuid := auth.uid();
  v_email text;
  v_user_name text;
  v_enabled_modules text;
  v_claims jsonb;
BEGIN
  IF v_auth_id IS NULL THEN
    RAISE EXCEPTION 'Non authentifié';
  END IF;

  -- Métadonnées JWT via request.jwt.claims (compatible Supabase ET local)
  BEGIN
    v_claims := COALESCE(current_setting('request.jwt.claims', true)::jsonb, '{}'::jsonb);
  EXCEPTION WHEN OTHERS THEN
    v_claims := '{}'::jsonb;
  END;

  v_email := COALESCE(
    v_claims ->> 'email',
    v_claims -> 'user_metadata' ->> 'email'
  );

  v_user_name := COALESCE(
    v_claims -> 'user_metadata' ->> 'name',
    v_claims -> 'user_metadata' ->> 'full_name',
    v_email
  );

  v_enabled_modules := COALESCE(
    (p_data ->> 'enabled_modules'),
    '["home","accounting","commercial","treasury","stock","production","hr","dashboards","reporting","system"]'
  );

  INSERT INTO tenants (
    name, legal_name, siren, vat_number,
    address, city, postal_code, country, currency,
    email, phone, legislation_pack_code, country_code,
    enabled_modules, status, plan, trial_ends_at
  ) VALUES (
    p_data ->> 'name',
    COALESCE(p_data ->> 'legal_name', p_data ->> 'name'),
    p_data ->> 'siren',
    p_data ->> 'vat_number',
    p_data ->> 'address',
    p_data ->> 'city',
    p_data ->> 'postal_code',
    COALESCE(p_data ->> 'country', 'France'),
    COALESCE(p_data ->> 'currency', 'EUR'),
    COALESCE(p_data ->> 'email', v_email),
    p_data ->> 'phone',
    p_data ->> 'legislation_pack_code',
    p_data ->> 'legislation_pack_code',
    v_enabled_modules,
    'active',
    'trial',
    (NOW() + INTERVAL '30 days')::timestamptz
  )
  RETURNING id INTO v_tenant;

  INSERT INTO tenant_users (
    tenant_id, auth_id, email, name, role, permissions, status, accepted_at
  ) VALUES (
    v_tenant,
    v_auth_id,
    v_email,
    v_user_name,
    'admin',
    '{}'::jsonb,
    'active',
    NOW()
  );

  BEGIN
    INSERT INTO employees (
      tenant_id, name, email, position, department, hire_date, status
    ) VALUES (
      v_tenant,
      v_user_name,
      v_email,
      'Admin',
      'Direction',
      CURRENT_DATE,
      'active'
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Employee creation skipped: %', SQLERRM;
  END;

  BEGIN
    PERFORM bootstrap_tenant(v_tenant);
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'bootstrap_tenant skipped: %', SQLERRM;
  END;

  RETURN jsonb_build_object(
    'success', true,
    'tenant_id', v_tenant
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM
  );
END;
$$;

-- ============================================================
-- GRANT EXECUTE sur toutes les fonctions corrigées
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
        'generate_trial_balance', 'generate_balance_sheet', 'generate_profit_loss',
        'get_balance_sheet_structured', 'calculate_overtime_pay',
        'calculate_sick_leave_pay', 'calculate_compensated_leave_indemnity',
        'calculate_notice_compensation', 'calculate_depreciation',
        'generate_depreciation_entry', 'generate_adjusting_entries',
        'auto_letter_accounts', 'auto_lettrage_by_reference',
        'resolve_price', 'calculate_payment_due_dates',
        'check_segregation_of_duties', 'run_mrp',
        'calculate_production_cost', 'calculate_manufacturing_cost',
        'calculate_stock_valuation', 'import_initial_stock',
        'distribute_by_grill', 'smart_bank_reconciliation',
        'get_bank_reconciliation_state', 'generate_vat_return',
        'run_three_way_match', 'generate_recurring_tasks',
        'get_nf525_attestation', 'create_tenant_for_current_user'
      )
  LOOP
    BEGIN
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s(%s) TO authenticated',
        r.proname, pg_get_function_identity_arguments(r.oid));
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'SKIP GRANT on %: %', r.proname, SQLERRM;
    END;
  END LOOP;
END $$;
