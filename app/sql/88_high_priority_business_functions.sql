-- ============================================================
-- 88_high_priority_business_functions.sql
--
-- 11 fonctions SQL High priority manquantes :
--   1.  calculate_depreciation()         — Amortissements (linéaire/dégressif)
--   2.  auto_letter_accounts()           — Lettrage automatique comptable
--   3.  smart_bank_reconciliation()      — Rapprochement bancaire intelligent
--   4.  calculate_stock_valuation()      — Valorisation stock CUMP/FIFO/LIFO
--   5.  cash_flow_forecast()             — Prévisions de trésorerie
--   6.  calculate_leave_acquisition()    — Droits congés payés
--   7.  calculate_severance_pay()        — Indemnité rupture conventionnelle
--   8.  calculate_payment_due_dates()    — Échéances de paiement
--   9.  generate_general_ledger()        — Grand livre
--   10. generate_trial_balance()         — Balance générale
--   11. generate_adjusting_entries()     — Écritures de régularisation
--
-- Inspiré de : Sage, Odoo, Pennylane, PayFit, Silae, QuickBooks, Xero
-- ============================================================

-- ============================================================
-- 1. calculate_depreciation(p_asset_id, p_period)
--    Calcul des amortissements linéaire et dégressif
--    Inspiré de : Sage, Odoo, QuickBooks
-- ============================================================
CREATE OR REPLACE FUNCTION calculate_depreciation(
  p_asset_id uuid,
  p_period text DEFAULT to_char(now(), 'YYYY-MM')
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_asset RECORD;
  v_plan RECORD;
  v_period_year integer;
  v_period_month integer;
  v_period_start date;
  v_period_end date;
  v_monthly_amount numeric := 0;
  v_annual_amount numeric := 0;
  v_accumulated numeric := 0;
  v_net_value numeric := 0;
  v_months_elapsed integer := 0;
  v_months_total integer := 0;
  v_existing_depreciation numeric := 0;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  SELECT * INTO v_asset FROM fixed_assets WHERE id = p_asset_id AND tenant_id = v_tid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Immobilisation non trouvée: %', p_asset_id;
  END IF;

  v_period_year := split_part(p_period, '-', 1)::integer;
  v_period_month := split_part(p_period, '-', 2)::integer;
  v_period_start := (p_period || '-01')::date;
  v_period_end := (v_period_start + INTERVAL '1 month' - INTERVAL '1 day')::date;

  -- Vérifier qu'on a un plan d'amortissement
  SELECT * INTO v_plan
  FROM asset_depreciation_plans
  WHERE asset_id = p_asset_id AND tenant_id = v_tid AND active = true
  ORDER BY created_at DESC LIMIT 1;

  IF NOT FOUND THEN
    -- Créer un plan automatiquement si absent
    v_months_total := COALESCE(v_asset.useful_life_years, 5) * 12;
    INSERT INTO asset_depreciation_plans (
      tenant_id, asset_id, plan_type, depreciation_method,
      duration_months, residual_value, annual_rate,
      start_date, end_date,
      accumulated_depreciation, current_net_value, active
    ) VALUES (
      v_tid, p_asset_id, 'accounting',
      COALESCE(v_asset.depreciation_method, 'linear'),
      v_months_total,
      COALESCE(v_asset.residual_value, 0),
      CASE WHEN v_months_total > 0 THEN 100.0 / (v_months_total / 12) ELSE 20 END,
      COALESCE(v_asset.purchase_date, v_period_start),
      (COALESCE(v_asset.purchase_date, v_period_start) + (v_months_total || ' months')::interval)::date,
      0,
      COALESCE(v_asset.purchase_value, v_asset.current_value, 0),
      true
    )
    RETURNING * INTO v_plan;
  END IF;

  -- Calculer l'amortissement déjà cumulé
  SELECT COALESCE(SUM(amount), 0) INTO v_existing_depreciation
  FROM asset_depreciations
  WHERE asset_id = p_asset_id AND tenant_id = v_tid;

  -- Mois écoulés depuis le début d'amortissement
  v_months_elapsed := 
    (v_period_year - extract(year FROM v_plan.start_date)::integer) * 12 +
    (v_period_month - extract(month FROM v_plan.start_date)::integer) + 1;
  v_months_elapsed := GREATEST(v_months_elapsed, 0);

  -- Calcul selon la méthode
  IF v_plan.depreciation_method = 'linear' OR v_plan.depreciation_method = 'linéaire' THEN
    -- Linéaire : (valeur d'achat - valeur résiduelle) / durée en mois
    v_monthly_amount := (COALESCE(v_asset.purchase_value, v_asset.current_value, 0) - COALESCE(v_plan.residual_value, 0)) / v_plan.duration_months;
    v_annual_amount := v_monthly_amount * 12;
    v_accumulated := v_monthly_amount * LEAST(v_months_elapsed, v_plan.duration_months);

  ELSIF v_plan.depreciation_method = 'declining' OR v_plan.depreciation_method = 'dégressif' THEN
    -- Dégressif : taux dégressif = taux linéaire × coefficient
    -- Coefficient: 1.25 (3-4 ans), 1.75 (5-6 ans), 2.25 (>6 ans)
    DECLARE
      v_coefficient numeric := 1.75;
      v_base_value numeric;
      v_rate numeric;
    BEGIN
      v_base_value := COALESCE(v_asset.purchase_value, v_asset.current_value, 0) - COALESCE(v_plan.residual_value, 0);
      v_rate := (100.0 / (v_plan.duration_months / 12)) * v_coefficient / 100;
      v_monthly_amount := v_base_value * v_rate / 12;
      v_annual_amount := v_base_value * v_rate;
      v_accumulated := LEAST(v_monthly_amount * v_months_elapsed, v_base_value);
    END;
  ELSE
    -- Par défaut: linéaire
    v_monthly_amount := (COALESCE(v_asset.purchase_value, v_asset.current_value, 0) - COALESCE(v_plan.residual_value, 0)) / v_plan.duration_months;
    v_accumulated := v_monthly_amount * LEAST(v_months_elapsed, v_plan.duration_months);
  END IF;

  -- Valeur nette comptable
  v_net_value := COALESCE(v_asset.purchase_value, v_asset.current_value, 0) - v_accumulated;

  -- Créer ou mettre à jour l'amortissement du mois
  INSERT INTO asset_depreciations (
    tenant_id, asset_id, fiscal_year_code, period,
    depreciation_type, amount, cumulative_amount, net_book_value
  ) VALUES (
    v_tid, p_asset_id, v_period_year::text,
    v_period_month,
    'monthly', v_monthly_amount, v_accumulated, v_net_value
  )
  ON CONFLICT DO NOTHING;

  -- Mettre à jour le plan
  UPDATE asset_depreciation_plans
    SET accumulated_depreciation = v_accumulated,
        current_net_value = v_net_value,
        updated_at = now()
  WHERE id = v_plan.id;

  RETURN jsonb_build_object(
    'asset_id', p_asset_id,
    'asset_name', v_asset.name,
    'period', p_period,
    'method', v_plan.depreciation_method,
    'monthly_amount', round(v_monthly_amount, 2),
    'annual_amount', round(v_annual_amount, 2),
    'accumulated_depreciation', round(v_accumulated, 2),
    'net_book_value', round(v_net_value, 2),
    'months_elapsed', v_months_elapsed,
    'months_total', v_plan.duration_months
  );
END;
$$;

GRANT EXECUTE ON FUNCTION calculate_depreciation(uuid, text) TO authenticated;


-- ============================================================
-- 2. auto_letter_accounts(p_account_code, p_tolerance)
--    Lettrage automatique : associe débits et crédits de même montant
--    Inspiré de : Sage, Cegid, Pennylane
-- ============================================================
CREATE OR REPLACE FUNCTION auto_letter_accounts(
  p_account_code text DEFAULT NULL,
  p_tolerance numeric DEFAULT 0.01
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_lettered_count integer := 0;
  v_lettering_code text;
  v_rec RECORD;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  -- Pour chaque compte tiers (classe 4) non lettré
  FOR v_rec IN
    SELECT DISTINCT jl.account_code
    FROM journal_lines jl
    JOIN journal_entries je ON je.id = jl.journal_id AND je.tenant_id = v_tid
    JOIN chart_accounts ca ON ca.code = jl.account_code AND ca.tenant_id = v_tid
    WHERE jl.tenant_id = v_tid
      AND je.status = 'posted'
      AND (p_account_code IS NULL OR jl.account_code = p_account_code)
      AND (ca.classe = '4' OR ca.saisie_tiers = true)
      AND jl.lettering_code IS NULL
    ORDER BY jl.account_code
  LOOP
    -- Générer un code de lettrage unique
    v_lettering_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));

    -- Lettrer les pairs exacts (débit = crédit)
    WITH pairs AS (
      SELECT
        d.id as debit_id,
        c.id as credit_id,
        d.debit as amount
      FROM journal_lines d
      JOIN journal_entries jed ON jed.id = d.journal_id AND jed.tenant_id = v_tid AND jed.status = 'posted'
      JOIN journal_lines c ON c.account_code = d.account_code AND c.tenant_id = v_tid
      JOIN journal_entries jec ON jec.id = c.journal_id AND jec.tenant_id = v_tid AND jec.status = 'posted'
      WHERE d.tenant_id = v_tid
        AND d.account_code = v_rec.account_code
        AND d.debit > 0 AND d.lettering_code IS NULL
        AND c.credit > 0 AND c.lettering_code IS NULL
        AND abs(d.debit - c.credit) <= p_tolerance
      LIMIT 1000
    )
    UPDATE journal_lines
      SET lettering_code = v_lettering_code,
          lettering_date = current_date
    WHERE id IN (SELECT debit_id FROM pairs)
       OR id IN (SELECT credit_id FROM pairs);

    GET DIAGNOSTICS v_lettered_count = ROW_COUNT;
  END LOOP;

  RETURN jsonb_build_object(
    'lettered_lines', v_lettered_count,
    'executed_at', now()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION auto_letter_accounts(text, numeric) TO authenticated;


-- ============================================================
-- 3. smart_bank_reconciliation(p_bank_account_id, p_from_date, p_to_date)
--    Rapprochement bancaire intelligent : correspondance automatique
--    Inspiré de : Pennylane, Qonto, Xero, QuickBooks
-- ============================================================
CREATE OR REPLACE FUNCTION smart_bank_reconciliation(
  p_bank_account_id uuid,
  p_from_date date DEFAULT NULL,
  p_to_date date DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_matched integer := 0;
  v_unmatched_bank integer := 0;
  v_unmatched_entries integer := 0;
  v_rec RECORD;
  v_from date;
  v_to date;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  v_from := COALESCE(p_from_date, current_date - 90);
  v_to := COALESCE(p_to_date, current_date);

  -- 1. Correspondance exacte : montant identique + date proche (±3 jours)
  FOR v_rec IN
    SELECT bt.id as bank_tx_id, bt.amount, bt.date as tx_date,
           jl.id as line_id
    FROM bank_transactions bt
    JOIN journal_lines jl ON jl.tenant_id = v_tid
    JOIN journal_entries je ON je.id = jl.journal_id AND je.tenant_id = v_tid AND je.status = 'posted'
    WHERE bt.tenant_id = v_tid
      AND bt.account_id = p_bank_account_id
      AND bt.reconciled = false
      AND bt.date >= v_from AND bt.date <= v_to
      AND jl.account_code IN (
        SELECT ca.code FROM chart_accounts ca
        WHERE ca.tenant_id = v_tid AND ca.classe = '5'
      )
      AND jl.lettering_code IS NULL
      AND abs(bt.amount - abs(jl.debit - jl.credit)) < 0.01
      AND abs(bt.date - je.date) <= 3
    LIMIT 500
  LOOP
    UPDATE bank_transactions
      SET reconciled = true,
          reconciled_entry_id = (SELECT journal_id FROM journal_lines WHERE id = v_rec.line_id),
          reconciled_at = now()
    WHERE id = v_rec.bank_tx_id;

    UPDATE journal_lines
      SET lettering_code = 'RAPP-' || substr(v_rec.bank_tx_id::text, 1, 8),
          lettering_date = current_date
    WHERE id = v_rec.line_id;

    v_matched := v_matched + 1;
  END LOOP;

  -- 2. Compter les non-rapprochées
  SELECT count(*) INTO v_unmatched_bank
  FROM bank_transactions
  WHERE tenant_id = v_tid
    AND account_id = p_bank_account_id
    AND reconciled = false
    AND date >= v_from AND date <= v_to;

  SELECT count(*) INTO v_unmatched_entries
  FROM journal_lines jl
  JOIN journal_entries je ON je.id = jl.journal_id AND je.tenant_id = v_tid AND je.status = 'posted'
  WHERE jl.tenant_id = v_tid
    AND jl.account_code IN (
      SELECT ca.code FROM chart_accounts ca
      WHERE ca.tenant_id = v_tid AND ca.classe = '5'
    )
    AND jl.lettering_code IS NULL
    AND je.date >= v_from AND je.date <= v_to;

  RETURN jsonb_build_object(
    'bank_account_id', p_bank_account_id,
    'from_date', v_from,
    'to_date', v_to,
    'matched', v_matched,
    'unmatched_bank_transactions', v_unmatched_bank,
    'unmatched_journal_entries', v_unmatched_entries,
    'executed_at', now()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION smart_bank_reconciliation(uuid, date, date) TO authenticated;


-- ============================================================
-- 4. calculate_stock_valuation(p_method, p_warehouse_id)
--    Valorisation des stocks : CUMP, FIFO, LIFO
--    Inspiré de : Odoo, Sage, SAP, ERPNext
-- ============================================================
CREATE OR REPLACE FUNCTION calculate_stock_valuation(
  p_method text DEFAULT 'cump',
  p_warehouse_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_result jsonb := '[]'::jsonb;
  v_rec RECORD;
  v_cump numeric;
  v_fifo_value numeric;
  v_lifo_value numeric;
  v_total_cump numeric := 0;
  v_total_fifo numeric := 0;
  v_total_lifo numeric := 0;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  FOR v_rec IN
    SELECT
      sq.product_id,
      p.name as product_name,
      sq.warehouse_id,
      w.name as warehouse_name,
      sq.quantity
    FROM stock_quantities sq
    JOIN products p ON p.id = sq.product_id AND p.tenant_id = v_tid
    JOIN warehouses w ON w.id = sq.warehouse_id AND w.tenant_id = v_tid
    WHERE sq.tenant_id = v_tid
      AND sq.quantity > 0
      AND (p_warehouse_id IS NULL OR sq.warehouse_id = p_warehouse_id)
  LOOP
    -- CUMP : Coût Unitaire Moyen Pondéré
    SELECT COALESCE(sum(sm.unit_cost * sm.quantity) / NULLIF(sum(sm.quantity), 0), 0)
    INTO v_cump
    FROM stock_movements sm
    WHERE sm.tenant_id = v_tid
      AND sm.product_id = v_rec.product_id
      AND sm.warehouse_id = v_rec.warehouse_id
      AND sm.movement_type IN ('in', 'initial');

    v_cump := COALESCE(v_cump, 0);

    -- FIFO : premiers entrés, premiers sortis
    -- On calcule la valeur des entrées restantes
    SELECT COALESCE(sum(sm.unit_cost * sm.quantity), 0)
    INTO v_fifo_value
    FROM (
      SELECT unit_cost, quantity,
        sum(quantity) OVER (ORDER BY movement_date DESC) as running_qty
      FROM stock_movements
      WHERE tenant_id = v_tid
        AND product_id = v_rec.product_id
        AND warehouse_id = v_rec.warehouse_id
        AND movement_type IN ('in', 'initial')
    ) sm
    WHERE running_qty - quantity < v_rec.quantity;

    v_fifo_value := COALESCE(v_fifo_value, v_cump * v_rec.quantity);

    -- LIFO : derniers entrés, premiers sortis
    SELECT COALESCE(sum(sm.unit_cost * sm.quantity), 0)
    INTO v_lifo_value
    FROM (
      SELECT unit_cost, quantity,
        sum(quantity) OVER (ORDER BY movement_date ASC) as running_qty
      FROM stock_movements
      WHERE tenant_id = v_tid
        AND product_id = v_rec.product_id
        AND warehouse_id = v_rec.warehouse_id
        AND movement_type IN ('in', 'initial')
    ) sm
    WHERE running_qty - quantity < v_rec.quantity;

    v_lifo_value := COALESCE(v_lifo_value, v_cump * v_rec.quantity);

    -- Mettre à jour le CUMP dans stock_quantities
    UPDATE stock_quantities
      SET unit_cost = v_cump
    WHERE product_id = v_rec.product_id
      AND warehouse_id = v_rec.warehouse_id
      AND tenant_id = v_tid;

    v_result := v_result || jsonb_build_object(
      'product_id', v_rec.product_id,
      'product_name', v_rec.product_name,
      'warehouse_name', v_rec.warehouse_name,
      'quantity', v_rec.quantity,
      'cump', round(v_cump, 2),
      'fifo_value', round(v_fifo_value, 2),
      'lifo_value', round(v_lifo_value, 2),
      'cump_total', round(v_cump * v_rec.quantity, 2)
    );

    v_total_cump := v_total_cump + v_cump * v_rec.quantity;
    v_total_fifo := v_total_fifo + v_fifo_value;
    v_total_lifo := v_total_lifo + v_lifo_value;
  END LOOP;

  RETURN jsonb_build_object(
    'method', p_method,
    'warehouse_id', p_warehouse_id,
    'items', v_result,
    'total_cump', round(v_total_cump, 2),
    'total_fifo', round(v_total_fifo, 2),
    'total_lifo', round(v_total_lifo, 2),
    'calculated_at', now()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION calculate_stock_valuation(text, uuid) TO authenticated;


-- ============================================================
-- 5. cash_flow_forecast(p_days)
--    Prévisions de trésorerie à N jours
--    Inspiré de : Pennylane, Xero, QuickBooks, Treasury Wolf
-- ============================================================
CREATE OR REPLACE FUNCTION cash_flow_forecast(p_days integer DEFAULT 90)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_start date := current_date;
  v_end date := current_date + p_days;
  v_current_balance numeric := 0;
  v_expected_inflows numeric := 0;
  v_expected_outflows numeric := 0;
  v_net_flow numeric := 0;
  v_projected_balance numeric := 0;
  v_daily jsonb := '[]'::jsonb;
  v_rec RECORD;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  -- Solde actuel (somme des comptes bancaires)
  SELECT COALESCE(sum(current_balance), 0) INTO v_current_balance
  FROM bank_accounts
  WHERE tenant_id = v_tid AND active = true;

  -- Encaissements attendus : factures clients non payées avec échéance dans la période
  SELECT COALESCE(sum(total - COALESCE(amount_paid, 0)), 0)
  INTO v_expected_inflows
  FROM invoices
  WHERE tenant_id = v_tid
    AND status NOT IN ('cancelled', 'draft')
    AND payment_state IN ('not_paid', 'partial')
    AND due_date >= v_start AND due_date <= v_end;

  -- Décaissements attendus : factures fournisseurs non payées
  SELECT COALESCE(sum(total - COALESCE(amount_paid, 0)), 0)
  INTO v_expected_outflows
  FROM purchase_invoices
  WHERE tenant_id = v_tid
    AND status NOT IN ('cancelled', 'draft')
    AND payment_state IN ('not_paid', 'partial')
    AND due_date >= v_start AND due_date <= v_end;

  -- Salaires prévisionnels (estimation basée sur les salaires de base)
  SELECT COALESCE(sum(COALESCE(salary, 0)) * ceil(p_days / 30.0), 0)
  INTO v_expected_outflows
  FROM employees
  WHERE tenant_id = v_tid AND status = 'active';

  v_net_flow := v_expected_inflows - v_expected_outflows;
  v_projected_balance := v_current_balance + v_net_flow;

  -- Prévision journalière simplifiée
  FOR v_rec IN
    SELECT
      d::date as date,
      COALESCE(sum(CASE WHEN i.due_date = d::date THEN i.total - COALESCE(i.amount_paid, 0) ELSE 0 END), 0) as inflow,
      COALESCE(sum(CASE WHEN pi.due_date = d::date THEN pi.total - COALESCE(pi.amount_paid, 0) ELSE 0 END), 0) as outflow
    FROM generate_series(v_start, v_end, '1 day'::interval) d
    LEFT JOIN invoices i ON i.due_date = d::date AND i.tenant_id = v_tid
      AND i.payment_state IN ('not_paid', 'partial') AND i.status NOT IN ('cancelled', 'draft')
    LEFT JOIN purchase_invoices pi ON pi.due_date = d::date AND pi.tenant_id = v_tid
      AND pi.payment_state IN ('not_paid', 'partial') AND pi.status NOT IN ('cancelled', 'draft')
    GROUP BY d::date
    ORDER BY d::date
  LOOP
    v_daily := v_daily || jsonb_build_object(
      'date', v_rec.date,
      'inflow', round(v_rec.inflow, 2),
      'outflow', round(v_rec.outflow, 2),
      'net', round(v_rec.inflow - v_rec.outflow, 2)
    );
  END LOOP;

  RETURN jsonb_build_object(
    'start_date', v_start,
    'end_date', v_end,
    'days', p_days,
    'current_balance', round(v_current_balance, 2),
    'expected_inflows', round(v_expected_inflows, 2),
    'expected_outflows', round(v_expected_outflows, 2),
    'net_flow', round(v_net_flow, 2),
    'projected_balance', round(v_projected_balance, 2),
    'daily', v_daily,
    'generated_at', now()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION cash_flow_forecast(integer) TO authenticated;


-- ============================================================
-- 6. calculate_leave_acquisition(p_employee_id, p_year)
--    Calcul des droits aux congés payés (2.5 jours/mois en France)
--    Inspiré de : PayFit, Silae, Gusto, Rippling
-- ============================================================
CREATE OR REPLACE FUNCTION calculate_leave_acquisition(
  p_employee_id uuid,
  p_year integer DEFAULT extract(year FROM now())::integer
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_emp RECORD;
  v_acquired numeric := 0;
  v_taken numeric := 0;
  v_pending numeric := 0;
  v_carry_over numeric := 0;
  v_remaining numeric := 0;
  v_months_worked integer := 0;
  v_period_start date;
  v_period_end date;
  v_rule RECORD;
  v_annual_days numeric := 30;  -- 2.5 × 12 par défaut
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  SELECT * INTO v_emp FROM employees WHERE id = p_employee_id AND tenant_id = v_tid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Employé non trouvé: %', p_employee_id;
  END IF;

  -- Période de référence : 1er juin N-1 au 31 mai N (France)
  -- Pour simplifier, on utilise l'année civile
  v_period_start := (p_year::text || '-01-01')::date;
  v_period_end := (p_year::text || '-12-31')::date;

  -- Mois travaillés dans l'année
  v_months_worked := 
    CASE 
      WHEN v_emp.hire_date IS NULL OR extract(year FROM v_emp.hire_date)::integer < p_year THEN 12
      WHEN extract(year FROM v_emp.hire_date)::integer = p_year THEN 12 - extract(month FROM v_emp.hire_date)::integer + 1
      ELSE 0
    END;

  -- Récupérer la règle de congé
  SELECT * INTO v_rule
  FROM leave_rules
  WHERE tenant_id = v_tid AND leave_type = 'paid_leave' AND active = true
  LIMIT 1;

  IF FOUND AND v_rule.acquisition_rate IS NOT NULL THEN
    v_annual_days := v_rule.acquisition_rate * 12;
  END IF;

  -- Droits acquis : 2.5 jours par mois travaillé (plafond 30)
  v_acquired := LEAST(v_months_worked * 2.5, v_annual_days);

  -- Report de l'année précédente
  SELECT COALESCE(remaining, 0) INTO v_carry_over
  FROM leave_balances
  WHERE tenant_id = v_tid
    AND employee_id = p_employee_id
    AND leave_type = 'paid_leave'
    AND year = p_year - 1;

  -- Congés pris dans l'année
  SELECT COALESCE(sum(days), 0) INTO v_taken
  FROM leave_requests
  WHERE tenant_id = v_tid
    AND employee_id = p_employee_id
    AND leave_type = 'paid_leave'
    AND status = 'approved'
    AND start_date >= v_period_start AND end_date <= v_period_end;

  -- Congés en attente
  SELECT COALESCE(sum(days), 0) INTO v_pending
  FROM leave_requests
  WHERE tenant_id = v_tid
    AND employee_id = p_employee_id
    AND leave_type = 'paid_leave'
    AND status = 'pending'
    AND start_date >= v_period_start AND end_date <= v_period_end;

  -- Reste
  v_remaining := v_acquired + v_carry_over - v_taken;

  -- Mettre à jour le solde
  INSERT INTO leave_balances (
    tenant_id, employee_id, leave_type, year,
    acquired, taken, pending, remaining, carry_over
  ) VALUES (
    v_tid, p_employee_id, 'paid_leave', p_year,
    v_acquired, v_taken, v_pending, v_remaining, v_carry_over
  )
  ON CONFLICT (tenant_id, employee_id, leave_type, year) DO UPDATE SET
    acquired = EXCLUDED.acquired,
    taken = EXCLUDED.taken,
    pending = EXCLUDED.pending,
    remaining = EXCLUDED.remaining,
    carry_over = EXCLUDED.carry_over,
    updated_at = now();

  RETURN jsonb_build_object(
    'employee_id', p_employee_id,
    'year', p_year,
    'months_worked', v_monthsWorked,
    'acquired', v_acquired,
    'carry_over', v_carry_over,
    'taken', v_taken,
    'pending', v_pending,
    'remaining', v_remaining,
    'annual_entitlement', v_annual_days
  );
END;
$$;

GRANT EXECUTE ON FUNCTION calculate_leave_acquisition(uuid, integer) TO authenticated;


-- ============================================================
-- 7. calculate_severance_pay(p_employee_id, p_exit_date)
--    Indemnité de rupture conventionnelle / licenciement
--    Inspiré de : PayFit, Silae, Sage Paie
--    Formule légale : 1/4 de salaire mensuel par année d'ancienneté
--    + 1/3 au-delà de 10 ans
-- ============================================================
CREATE OR REPLACE FUNCTION calculate_severance_pay(
  p_employee_id uuid,
  p_exit_date date DEFAULT current_date
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_emp RECORD;
  v_seniority_years numeric;
  v_seniority_months integer;
  v_avg_salary numeric;
  v_legal_indemnity numeric;
  v_conventional_indemnity numeric := 0;
  v_final_indemnity numeric;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  SELECT * INTO v_emp FROM employees WHERE id = p_employee_id AND tenant_id = v_tid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Employé non trouvé: %', p_employee_id;
  END IF;

  -- Ancienneté
  IF v_emp.hire_date IS NULL THEN
    RAISE EXCEPTION 'Date d''embauche manquante';
  END IF;

  v_seniority_months := 
    (extract(year FROM p_exit_date) - extract(year FROM v_emp.hire_date))::integer * 12 +
    (extract(month FROM p_exit_date) - extract(month FROM v_emp.hire_date))::integer;
  v_seniority_years := v_seniority_months / 12.0;

  -- Salaire moyen des 12 derniers mois (ou salaire de base)
  SELECT COALESCE(avg(total_gross), v_emp.salary) INTO v_avg_salary
  FROM pay_slips
  WHERE tenant_id = v_tid
    AND employee_id = p_employee_id
    AND period_start >= p_exit_date - INTERVAL '12 months'
    AND period_start <= p_exit_date;

  v_avg_salary := COALESCE(v_avg_salary, v_emp.salary, 0);

  -- Indemnité légale (loi de 2008)
  -- Moins de 10 ans : 1/4 de salaire mensuel × années d'ancienneté
  -- Plus de 10 ans : + 1/3 de salaire mensuel × années au-delà de 10
  IF v_seniority_years < 10 THEN
    v_legal_indemnity := (v_avg_salary / 4) * v_seniority_years;
  ELSE
    v_legal_indemnity := (v_avg_salary / 4) * 10
      + (v_avg_salary / 3) * (v_seniority_years - 10);
  END IF;

  -- Minimum : indemnité légale ne peut pas être inférieure à
  -- 1/4 salaire × années (même pour moins de 8 mois d'ancienneté)
  IF v_seniority_months < 8 THEN
    v_legal_indemnity := 0;  -- Pas d'indemnité si moins de 8 mois
  END IF;

  v_final_indemnity := GREATEST(v_legal_indemnity, v_conventional_indemnity);

  RETURN jsonb_build_object(
    'employee_id', p_employee_id,
    'exit_date', p_exit_date,
    'hire_date', v_emp.hire_date,
    'seniority_months', v_seniority_months,
    'seniority_years', round(v_seniority_years, 2),
    'avg_salary_12m', round(v_avg_salary, 2),
    'legal_indemnity', round(v_legal_indemnity, 2),
    'conventional_indemnity', round(v_conventional_indemnity, 2),
    'final_indemnity', round(v_final_indemnity, 2),
    'eligible', v_seniority_months >= 8
  );
END;
$$;

GRANT EXECUTE ON FUNCTION calculate_severance_pay(uuid, date) TO authenticated;


-- ============================================================
-- 8. calculate_payment_due_dates(p_invoice_date, p_payment_terms_id)
--    Calcul des échéances selon les conditions de paiement
--    Inspiré de : Sage, Odoo, Pennylane
-- ============================================================
CREATE OR REPLACE FUNCTION calculate_payment_due_dates(
  p_invoice_date date,
  p_payment_terms_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_terms RECORD;
  v_due_date date;
  v_installments jsonb := '[]'::jsonb;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  SELECT * INTO v_terms
  FROM payment_terms
  WHERE id = p_payment_terms_id AND tenant_id = v_tid AND active = true;

  IF NOT FOUND THEN
    -- Par défaut : 30 jours nets
    v_due_date := p_invoice_date + 30;
    RETURN jsonb_build_object(
      'due_date', v_due_date,
      'installments', jsonb_build_array(jsonb_build_object(
        'date', v_due_date, 'pct', 100, 'label', '30 jours nets'
      ))
    );
  END IF;

  -- Selon le type de conditions
  IF v_terms.type = 'immediate' THEN
    v_due_date := p_invoice_date;
    v_installments := jsonb_build_array(jsonb_build_object(
      'date', v_due_date, 'pct', 100, 'label', 'Comptant'
    ));

  ELSIF v_terms.type = 'net_days' OR v_terms.type = 'end_of_month' THEN
    DECLARE
      v_base_date date;
    BEGIN
      v_base_date := p_invoice_date + COALESCE(v_terms.days_1, 30);
      IF v_terms.end_of_month THEN
        v_base_date := date_trunc('month', v_base_date + INTERVAL '1 month')::date - 1;
      END IF;
      v_due_date := v_base_date;
      v_installments := jsonb_build_array(jsonb_build_object(
        'date', v_due_date, 'pct', 100, 'label', v_terms.name
      ));
    END;

  ELSIF v_terms.type = 'installments' OR v_terms.type = 'split' THEN
    -- Paiement échelonné : days_1/pct_1 + days_2/pct_2
    DECLARE
      v_date1 date;
      v_date2 date;
    BEGIN
      v_date1 := p_invoice_date + COALESCE(v_terms.days_1, 30);
      IF v_terms.end_of_month THEN
        v_date1 := date_trunc('month', v_date1 + INTERVAL '1 month')::date - 1;
      END IF;
      v_installments := v_installments || jsonb_build_object(
        'date', v_date1, 'pct', COALESCE(v_terms.pct_1, 50), 'label', '1er versement'
      );

      IF v_terms.days_2 IS NOT NULL THEN
        v_date2 := p_invoice_date + v_terms.days_2;
        IF v_terms.end_of_month THEN
          v_date2 := date_trunc('month', v_date2 + INTERVAL '1 month')::date - 1;
        END IF;
        v_installments := v_installments || jsonb_build_object(
          'date', v_date2, 'pct', COALESCE(v_terms.pct_2, 50), 'label', '2ème versement'
        );
        v_due_date := v_date2;
      ELSE
        v_due_date := v_date1;
      END IF;
    END;

  ELSE
    v_due_date := p_invoice_date + COALESCE(v_terms.days_1, 30);
    v_installments := jsonb_build_array(jsonb_build_object(
      'date', v_due_date, 'pct', 100, 'label', v_terms.name
    ));
  END IF;

  RETURN jsonb_build_object(
    'due_date', v_due_date,
    'payment_terms', v_terms.name,
    'installments', v_installments
  );
END;
$$;

GRANT EXECUTE ON FUNCTION calculate_payment_due_dates(date, uuid) TO authenticated;


-- ============================================================
-- 9. generate_general_ledger(p_from_date, p_to_date, p_account_code)
--    Grand livre : toutes les écritures par compte
--    Inspiré de : Sage, Cegid, Odoo, QuickBooks
-- ============================================================
CREATE OR REPLACE FUNCTION generate_general_ledger(
  p_from_date date DEFAULT NULL,
  p_to_date date DEFAULT NULL,
  p_account_code text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_from date;
  v_to date;
  v_entries jsonb := '[]'::jsonb;
  v_rec RECORD;
  v_total_debit numeric := 0;
  v_total_credit numeric := 0;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  v_from := COALESCE(p_from_date, current_date - 365);
  v_to := COALESCE(p_to_date, current_date);

  FOR v_rec IN
    SELECT
      je.number as entry_number,
      je.date,
      je.journal_code,
      je.description,
      jl.account_code,
      ca.name as account_name,
      jl.description as line_description,
      jl.debit,
      jl.credit,
      jl.lettering_code,
      je.status
    FROM journal_lines jl
    JOIN journal_entries je ON je.id = jl.journal_id AND je.tenant_id = v_tid
    LEFT JOIN chart_accounts ca ON ca.code = jl.account_code AND ca.tenant_id = v_tid
    WHERE jl.tenant_id = v_tid
      AND je.status = 'posted'
      AND je.date >= v_from AND je.date <= v_to
      AND (p_account_code IS NULL OR jl.account_code = p_account_code)
    ORDER BY jl.account_code, je.date, je.number
  LOOP
    v_entries := v_entries || jsonb_build_object(
      'entry_number', v_rec.entry_number,
      'date', v_rec.date,
      'journal_code', v_rec.journal_code,
      'account_code', v_rec.account_code,
      'account_name', v_rec.account_name,
      'description', v_rec.line_description,
      'debit', round(COALESCE(v_rec.debit, 0), 2),
      'credit', round(COALESCE(v_rec.credit, 0), 2),
      'lettering_code', v_rec.lettering_code,
      'status', v_rec.status
    );
    v_total_debit := v_total_debit + COALESCE(v_rec.debit, 0);
    v_total_credit := v_total_credit + COALESCE(v_rec.credit, 0);
  END LOOP;

  RETURN jsonb_build_object(
    'from_date', v_from,
    'to_date', v_to,
    'account_code', p_account_code,
    'entries', v_entries,
    'total_debit', round(v_total_debit, 2),
    'total_credit', round(v_total_credit, 2),
    'balanced', round(v_total_debit, 2) = round(v_total_credit, 2),
    'entry_count', jsonb_array_length(v_entries),
    'generated_at', now()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION generate_general_ledger(date, date, text) TO authenticated;


-- ============================================================
-- 10. generate_trial_balance(p_from_date, p_to_date)
--     Balance générale : soldes par compte
--     Inspiré de : Sage, Cegid, Odoo, QuickBooks
-- ============================================================
CREATE OR REPLACE FUNCTION generate_trial_balance(
  p_from_date date DEFAULT NULL,
  p_to_date date DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_from date;
  v_to date;
  v_accounts jsonb := '[]'::jsonb;
  v_rec RECORD;
  v_total_debit numeric := 0;
  v_total_credit numeric := 0;
  v_total_solde numeric := 0;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  v_from := COALESCE(p_from_date, current_date - 365);
  v_to := COALESCE(p_to_date, current_date);

  FOR v_rec IN
    SELECT
      ca.code,
      ca.name,
      ca.classe,
      ca.type,
      COALESCE(sum(jl.debit), 0) as total_debit,
      COALESCE(sum(jl.credit), 0) as total_credit,
      COALESCE(sum(jl.debit - jl.credit), 0) as solde
    FROM chart_accounts ca
    LEFT JOIN journal_lines jl ON jl.account_code = ca.code AND jl.tenant_id = v_tid
    LEFT JOIN journal_entries je ON je.id = jl.journal_id AND je.tenant_id = v_tid
      AND je.status = 'posted'
      AND je.date >= v_from AND je.date <= v_to
    WHERE ca.tenant_id = v_tid
      AND ca.deprecated = false
    GROUP BY ca.code, ca.name, ca.classe, ca.type
    HAVING COALESCE(sum(jl.debit), 0) != 0 OR COALESCE(sum(jl.credit), 0) != 0
    ORDER BY ca.code
  LOOP
    v_accounts := v_accounts || jsonb_build_object(
      'code', v_rec.code,
      'name', v_rec.name,
      'classe', v_rec.classe,
      'type', v_rec.type,
      'debit', round(v_rec.total_debit, 2),
      'credit', round(v_rec.total_credit, 2),
      'solde', round(v_rec.solde, 2),
      'solde_type', CASE WHEN v_rec.solde > 0 THEN 'débit' WHEN v_rec.solde < 0 THEN 'crédit' ELSE 'nul' END
    );
    v_total_debit := v_total_debit + v_rec.total_debit;
    v_total_credit := v_total_credit + v_rec.total_credit;
    v_total_solde := v_total_solde + v_rec.solde;
  END LOOP;

  RETURN jsonb_build_object(
    'from_date', v_from,
    'to_date', v_to,
    'accounts', v_accounts,
    'total_debit', round(v_total_debit, 2),
    'total_credit', round(v_total_credit, 2),
    'total_solde', round(v_total_solde, 2),
    'balanced', round(v_total_debit, 2) = round(v_total_credit, 2),
    'account_count', jsonb_array_length(v_accounts),
    'generated_at', now()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION generate_trial_balance(date, date) TO authenticated;


-- ============================================================
-- 11. generate_adjusting_entries(p_fiscal_year_id)
--     Écritures de régularisation (CCA/PCA, provisions)
--     Inspiré de : Sage, Cegid, Odoo
-- ============================================================
CREATE OR REPLACE FUNCTION generate_adjusting_entries(p_fiscal_year_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_fy RECORD;
  v_rec RECORD;
  v_entries jsonb := '[]'::jsonb;
  v_entry_count integer := 0;
  v_entry_id uuid;
  v_number text;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  SELECT * INTO v_fy FROM fiscal_years WHERE id = p_fiscal_year_id AND tenant_id = v_tid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Exercice non trouvé: %', p_fiscal_year_id;
  END IF;

  -- 1. Charges Constatées d'Avance (CCA) : charges payées mais non consommées
  -- Compte 486 (Charges constatées d'avance)
  -- Note: la génération automatique des CCA/PCA nécessite des données de cutoff
  -- précises qui ne sont pas encore disponibles. Section réservée pour évolution.

  -- 2. Produits Constatés d'Avance (PCA) : produits encaissés mais non réalisés
  -- Compte 487

  -- 3. Provisions pour créances douteuses
  -- Compte 6817 / 491
  FOR v_rec IN
    SELECT i.id, i.number, i.customer_id, i.amount_due,
           c.name as customer_name
    FROM invoices i
    LEFT JOIN customers c ON c.id = i.customer_id
    WHERE i.tenant_id = v_tid
      AND i.payment_state = 'not_paid'
      AND i.due_date < v_fy.end_date - INTERVAL '90 days'
      AND i.status NOT IN ('cancelled', 'draft')
  LOOP
    v_number := 'REG-PROV-' || v_rec.number;
    -- Écriture de provision
    INSERT INTO journal_entries (
      tenant_id, number, date, journal_code, status, description
    ) VALUES (
      v_tid, v_number, v_fy.end_date, 'OD', 'draft',
      'Provision pour créance douteuse ' || v_rec.number
    )
    RETURNING id INTO v_entry_id;

    -- Débit : 6817 (Dotation provisions)
    INSERT INTO journal_lines (tenant_id, journal_id, account_code, debit, credit, description, line_order)
    VALUES (v_tid, v_entry_id, '681700', v_rec.amount_due, 0, 'Dotation provision ' || v_rec.customer_name, 1);

    -- Crédit : 491 (Provisions pour créances douteuses)
    INSERT INTO journal_lines (tenant_id, journal_id, account_code, debit, credit, description, line_order)
    VALUES (v_tid, v_entry_id, '491000', 0, v_rec.amount_due, 'Provision ' || v_rec.number, 2);

    v_entries := v_entries || jsonb_build_object(
      'type', 'provision_creceance',
      'entry_number', v_number,
      'invoice_number', v_rec.number,
      'customer', v_rec.customer_name,
      'amount', round(v_rec.amount_due, 2)
    );
    v_entry_count := v_entry_count + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'fiscal_year_id', p_fiscal_year_id,
    'fiscal_year_code', v_fy.code,
    'entries', v_entries,
    'entry_count', v_entry_count,
    'generated_at', now()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION generate_adjusting_entries(uuid) TO authenticated;


-- ============================================================
-- RÉCAPITULATIF
-- ============================================================
-- 1.  calculate_depreciation()         — Amortissements
-- 2.  auto_letter_accounts()           — Lettrage automatique
-- 3.  smart_bank_reconciliation()      — Rapprochement bancaire
-- 4.  calculate_stock_valuation()      — Valorisation stock CUMP/FIFO/LIFO
-- 5.  cash_flow_forecast()             — Prévisions trésorerie
-- 6.  calculate_leave_acquisition()    — Droits congés payés
-- 7.  calculate_severance_pay()        — Indemnité rupture
-- 8.  calculate_payment_due_dates()    — Échéances de paiement
-- 9.  generate_general_ledger()        — Grand livre
-- 10. generate_trial_balance()         — Balance générale
-- 11. generate_adjusting_entries()     — Écritures de régularisation
-- ============================================================
