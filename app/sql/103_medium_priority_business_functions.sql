-- ============================================================
-- 89_medium_priority_business_functions.sql
--
-- 9 fonctions SQL Medium priority :
--   1. calculate_late_payment_penalties() — Pénalités de retard (Art L441-10)
--   2. calculate_sales_commissions()      — Commissions commerciaux
--   3. customer_credit_score()            — Scoring risque client
--   4. calculate_project_profitability()  — Rentabilité projet (EAC/ETC)
--   5. calculate_provisions()             — Provisions (créances, stocks)
--   6. post_deferred_charge()             — CCA / PCA
--   7. generate_accounting_annex()        — Annexe comptable
--   8. calculate_production_cost()        — Coût de production (OF)
--   9. calculate_inventory_variance()     — Écarts d'inventaire
--
-- Inspiré de : Sage, Odoo, Pennylane, SAP, ERPNext
-- ============================================================

-- ============================================================
-- 1. calculate_late_payment_penalties(p_invoice_id)
--    Pénalités de retard : 3x taux d'intérêt légal (Art L441-10 CDC)
--    + indemnité forfaitaire 40€ (Art D441-5)
--    Inspiré de : Pennylane, Sage
-- ============================================================
CREATE OR REPLACE FUNCTION calculate_late_payment_penalties(p_invoice_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_inv RECORD;
  v_days_overdue integer;
  v_legal_rate numeric := 3.15;  -- Taux d'intérêt légal 2024 (France)
  v_penalty_rate numeric;
  v_penalty_amount numeric := 0;
  v_flat_fee numeric := 40;      -- Indemnité forfaitaire (Art D441-5)
  v_total_penalty numeric;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  SELECT * INTO v_inv FROM invoices WHERE id = p_invoice_id AND tenant_id = v_tid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Facture non trouvée: %', p_invoice_id;
  END IF;

  IF v_inv.due_date IS NULL OR v_inv.due_date >= current_date THEN
    RETURN jsonb_build_object('eligible', false, 'message', 'Facture non en retard');
  END IF;

  v_days_overdue := current_date - v_inv.due_date;
  v_penalty_rate := v_legal_rate * 3 / 100;  -- 3x taux légal
  v_penalty_amount := v_inv.total * v_penalty_rate * v_days_overdue / 365;
  v_total_penalty := v_penalty_amount + v_flat_fee;

  RETURN jsonb_build_object(
    'invoice_id', p_invoice_id,
    'invoice_number', v_inv.number,
    'due_date', v_inv.due_date,
    'days_overdue', v_days_overdue,
    'invoice_total', round(v_inv.total, 2),
    'legal_rate', v_legal_rate,
    'penalty_rate', round(v_penalty_rate * 100, 2),
    'penalty_interest', round(v_penalty_amount, 2),
    'flat_fee', v_flat_fee,
    'total_penalty', round(v_total_penalty, 2),
    'legal_reference', 'Art L441-10 CDC + Art D441-5',
    'eligible', true
  );
END;
$$;

GRANT EXECUTE ON FUNCTION calculate_late_payment_penalties(uuid) TO authenticated;


-- ============================================================
-- 2. calculate_sales_commissions(p_period, p_rep_id)
--    Commissions des commerciaux basées sur CA facturé
--    Inspiré de : Salesforce, Odoo, SAP
-- ============================================================
CREATE OR REPLACE FUNCTION calculate_sales_commissions(
  p_period text DEFAULT to_char(now(), 'YYYY-MM'),
  p_rep_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_period_start date;
  v_period_end date;
  v_result jsonb := '[]'::jsonb;
  v_rec RECORD;
  v_total_commission numeric := 0;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  v_period_start := (p_period || '-01')::date;
  v_period_end := (v_period_start + INTERVAL '1 month' - INTERVAL '1 day')::date;

  FOR v_rec IN
    SELECT
      sr.id as rep_id,
      sr.name as rep_name,
      COALESCE(sr.commission_rate, 0) as rate,
      COALESCE(sum(i.total), 0) as revenue,
      count(i.id) as invoice_count
    FROM sales_representatives sr
    LEFT JOIN customers c ON c.sales_rep_id = sr.id AND c.tenant_id = v_tid
    LEFT JOIN invoices i ON i.customer_id = c.id AND i.tenant_id = v_tid
      AND i.date >= v_period_start AND i.date <= v_period_end
      AND i.status NOT IN ('cancelled', 'draft')
    WHERE sr.tenant_id = v_tid
      AND sr.active = true
      AND (p_rep_id IS NULL OR sr.id = p_rep_id)
    GROUP BY sr.id, sr.name, sr.commission_rate
    ORDER BY sr.name
  LOOP
    DECLARE
      v_commission numeric := v_rec.revenue * v_rec.rate / 100;
    BEGIN
      v_result := v_result || jsonb_build_object(
        'rep_id', v_rec.rep_id,
        'rep_name', v_rec.rep_name,
        'commission_rate', v_rec.rate,
        'revenue', round(v_rec.revenue, 2),
        'invoice_count', v_rec.invoice_count,
        'commission', round(v_commission, 2)
      );
      v_total_commission := v_total_commission + v_commission;
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'period', p_period,
    'representatives', v_result,
    'total_commission', round(v_total_commission, 2),
    'calculated_at', now()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION calculate_sales_commissions(text, uuid) TO authenticated;


-- ============================================================
-- 3. customer_credit_score(p_customer_id)
--    Scoring de risque client (0-100)
--    Inspiré de : Pennylane, Sage, Coface
-- ============================================================
CREATE OR REPLACE FUNCTION customer_credit_score(p_customer_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_cust RECORD;
  v_score integer := 50;
  v_factors jsonb := '[]'::jsonb;
  v_overdue_count integer := 0;
  v_overdue_amount numeric := 0;
  v_total_invoiced numeric := 0;
  v_avg_payment_days numeric := 0;
  v_credit_limit numeric := 0;
  v_rating text;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  SELECT * INTO v_cust FROM customers WHERE id = p_customer_id AND tenant_id = v_tid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Client non trouvé: %', p_customer_id;
  END IF;

  -- Facteur 1 : Retards de paiement (-20 par facture en retard, plafond -40)
  SELECT count(*), COALESCE(sum(total - COALESCE(amount_paid, 0)), 0)
  INTO v_overdue_count, v_overdue_amount
  FROM invoices
  WHERE tenant_id = v_tid AND customer_id = p_customer_id
    AND payment_state IN ('not_paid', 'partial')
    AND due_date < current_date
    AND status NOT IN ('cancelled', 'draft');

  IF v_overdue_count = 0 THEN
    v_score := v_score + 20;
    v_factors := v_factors || jsonb_build_object('factor', 'no_overdue', 'impact', +20);
  ELSE
    DECLARE v_penalty integer := LEAST(v_overdue_count * 10, 40); BEGIN
      v_score := v_score - v_penalty;
      v_factors := v_factors || jsonb_build_object('factor', 'overdue_invoices', 'count', v_overdue_count, 'impact', -v_penalty);
    END;
  END IF;

  -- Facteur 2 : Volume de CA (bonus si volume important)
  SELECT COALESCE(sum(total), 0) INTO v_total_invoiced
  FROM invoices
  WHERE tenant_id = v_tid AND customer_id = p_customer_id
    AND status NOT IN ('cancelled', 'draft')
    AND date >= current_date - 365;

  IF v_total_invoiced > 100000 THEN
    v_score := v_score + 15;
    v_factors := v_factors || jsonb_build_object('factor', 'high_volume', 'impact', +15);
  ELSIF v_total_invoiced > 10000 THEN
    v_score := v_score + 5;
    v_factors := v_factors || jsonb_build_object('factor', 'medium_volume', 'impact', +5);
  END IF;

  -- Facteur 3 : Délai moyen de paiement
  SELECT COALESCE(avg(payment_date - due_date), 0)
  INTO v_avg_payment_days
  FROM customer_payments cp
  JOIN invoices i ON i.id = cp.invoice_id AND i.tenant_id = v_tid
  WHERE i.customer_id = p_customer_id AND cp.status = 'completed';

  IF v_avg_payment_days <= 0 THEN
    v_score := v_score + 15;
    v_factors := v_factors || jsonb_build_object('factor', 'early_payment', 'avg_days', v_avg_payment_days, 'impact', +15);
  ELSIF v_avg_payment_days <= 10 THEN
    v_score := v_score + 5;
    v_factors := v_factors || jsonb_build_object('factor', 'on_time', 'avg_days', v_avg_payment_days, 'impact', +5);
  ELSIF v_avg_payment_days > 30 THEN
    v_score := v_score - 15;
    v_factors := v_factors || jsonb_build_object('factor', 'late_payment', 'avg_days', v_avg_payment_days, 'impact', -15);
  END IF;

  -- Normaliser le score (0-100)
  v_score := GREATEST(LEAST(v_score, 100), 0);

  -- Rating
  v_rating := CASE
    WHEN v_score >= 80 THEN 'A'  -- Excellent
    WHEN v_score >= 60 THEN 'B'  -- Bon
    WHEN v_score >= 40 THEN 'C'  -- Moyen
    WHEN v_score >= 20 THEN 'D'  -- Risqué
    ELSE 'E'                      -- Critique
  END;

  -- Limite de crédit recommandée
  v_credit_limit := CASE
    WHEN v_score >= 80 THEN v_total_invoiced * 0.3
    WHEN v_score >= 60 THEN v_total_invoiced * 0.2
    WHEN v_score >= 40 THEN v_total_invoiced * 0.1
    WHEN v_score >= 20 THEN 5000
    ELSE 0
  END;

  RETURN jsonb_build_object(
    'customer_id', p_customer_id,
    'customer_name', v_cust.name,
    'score', v_score,
    'rating', v_rating,
    'factors', v_factors,
    'overdue_count', v_overdue_count,
    'overdue_amount', round(v_overdue_amount, 2),
    'total_invoiced_12m', round(v_total_invoiced, 2),
    'avg_payment_days', round(v_avg_payment_days, 1),
    'recommended_credit_limit', round(v_credit_limit, 2)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION customer_credit_score(uuid) TO authenticated;


-- ============================================================
-- 4. calculate_project_profitability(p_project_id)
--    Rentabilité projet : EAC, ETC, marge, % d'avancement
--    Inspiré de : Odoo, SAP, Workday, Monday.com
-- ============================================================
CREATE OR REPLACE FUNCTION calculate_project_profitability(p_project_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_proj RECORD;
  v_invoiced numeric := 0;
  v_cost numeric := 0;
  v_budget numeric := 0;
  v_margin numeric := 0;
  v_margin_pct numeric := 0;
  v_progress_pct numeric := 0;
  v_eac numeric := 0;  -- Estimate At Completion
  v_etc numeric := 0;  -- Estimate To Complete
  v_cpi numeric := 0;  -- Cost Performance Index
  v_hours_logged numeric := 0;
  v_task_count integer := 0;
  v_completed_tasks integer := 0;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  SELECT * INTO v_proj FROM projects WHERE id = p_project_id AND tenant_id = v_tid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Projet non trouvé: %', p_project_id;
  END IF;

  -- CA facturé sur le projet
  SELECT COALESCE(sum(i.total), 0) INTO v_invoiced
  FROM invoices i
  WHERE i.tenant_id = v_tid AND i.project_id = p_project_id
    AND i.status NOT IN ('cancelled', 'draft');

  -- Coûts (temps + dépenses)
  SELECT COALESCE(sum(te.hours * COALESCE(e.salary, 0) / 160), 0)
  INTO v_hours_logged
  FROM project_time_entries te
  LEFT JOIN employees e ON e.id = te.employee_id AND e.tenant_id = v_tid
  WHERE te.tenant_id = v_tid AND te.project_id = p_project_id;

  SELECT COALESCE(sum(er.total), 0) INTO v_cost
  FROM expense_reports er
  WHERE er.tenant_id = v_tid AND er.project_id = p_project_id
    AND er.status = 'approved';

  v_cost := v_cost + v_hours_logged;

  -- Budget
  v_budget := COALESCE(v_proj.budget, 0);

  -- Marges
  v_margin := v_invoiced - v_cost;
  v_margin_pct := CASE WHEN v_invoiced > 0 THEN (v_margin / v_invoiced) * 100 ELSE 0 END;

  -- Avancement (basé sur tâches)
  SELECT count(*), count(*) FILTER (WHERE status = 'done' OR status = 'completed')
  INTO v_task_count, v_completed_tasks
  FROM project_tasks
  WHERE tenant_id = v_tid AND project_id = p_project_id;

  v_progress_pct := CASE WHEN v_task_count > 0 THEN (v_completed_tasks::numeric / v_task_count) * 100 ELSE 0 END;

  -- EAC / ETC / CPI (Earned Value Management)
  IF v_progress_pct > 0 AND v_cost > 0 THEN
    v_cpi := (v_budget * v_progress_pct / 100) / v_cost;
    v_eac := CASE WHEN v_cpi > 0 THEN v_budget / v_cpi ELSE v_cost END;
    v_etc := v_eac - v_cost;
  ELSE
    v_eac := v_cost;
    v_etc := v_budget - v_cost;
  END IF;

  RETURN jsonb_build_object(
    'project_id', p_project_id,
    'project_name', v_proj.name,
    'status', v_proj.status,
    'budget', round(v_budget, 2),
    'invoiced', round(v_invoiced, 2),
    'cost', round(v_cost, 2),
    'hours_logged', round(v_hours_logged, 2),
    'margin', round(v_margin, 2),
    'margin_pct', round(v_margin_pct, 2),
    'progress_pct', round(v_progress_pct, 2),
    'task_count', v_task_count,
    'completed_tasks', v_completed_tasks,
    'eac', round(v_eac, 2),
    'etc', round(v_etc, 2),
    'cpi', round(v_cpi, 2),
    'health', CASE
      WHEN v_margin_pct > 20 THEN 'healthy'
      WHEN v_margin_pct > 0 THEN 'warning'
      ELSE 'critical'
    END
  );
END;
$$;

GRANT EXECUTE ON FUNCTION calculate_project_profitability(uuid) TO authenticated;


-- ============================================================
-- 5. calculate_provisions(p_fiscal_year_id)
--    Provisions (créances douteuses, stocks obsolètes)
--    Inspiré de : Sage, Odoo, Cegid
-- ============================================================
CREATE OR REPLACE FUNCTION calculate_provisions(p_fiscal_year_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_fy RECORD;
  v_provisions jsonb := '[]'::jsonb;
  v_total numeric := 0;
  v_rec RECORD;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  SELECT * INTO v_fy FROM fiscal_years WHERE id = p_fiscal_year_id AND tenant_id = v_tid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Exercice non trouvé: %', p_fiscal_year_id;
  END IF;

  -- 1. Provisions pour créances douteuses (>90 jours de retard)
  FOR v_rec IN
    SELECT i.id, i.number, i.customer_id, c.name as customer_name,
           i.total - COALESCE(i.amount_paid, 0) as outstanding,
           i.due_date,
           current_date - i.due_date as days_overdue
    FROM invoices i
    LEFT JOIN customers c ON c.id = i.customer_id
    WHERE i.tenant_id = v_tid
      AND i.payment_state IN ('not_paid', 'partial')
      AND i.due_date < v_fy.end_date - INTERVAL '90 days'
      AND i.status NOT IN ('cancelled', 'draft')
    ORDER BY days_overdue DESC
  LOOP
    DECLARE
      v_prov_rate numeric := CASE
        WHEN v_rec.days_overdue > 180 THEN 1.00
        WHEN v_rec.days_overdue > 120 THEN 0.75
        WHEN v_rec.days_overdue > 90 THEN 0.50
        ELSE 0.25
      END;
      v_prov_amount numeric := v_rec.outstanding * v_prov_rate;
    BEGIN
      v_provisions := v_provisions || jsonb_build_object(
        'type', 'creance_douteuse',
        'invoice_number', v_rec.number,
        'customer', v_rec.customer_name,
        'outstanding', round(v_rec.outstanding, 2),
        'days_overdue', v_rec.days_overdue,
        'provision_rate', v_prov_rate,
        'provision_amount', round(v_prov_amount, 2)
      );
      v_total := v_total + v_prov_amount;
    END;
  END LOOP;

  -- 2. Provisions pour stocks obsolètes (pas de mouvement depuis 12 mois)
  FOR v_rec IN
    SELECT p.id, p.name, sq.quantity, sq.unit_cost,
           sq.quantity * sq.unit_cost as stock_value,
           COALESCE(max(sm.movement_date), current_date - 400) as last_movement
    FROM stock_quantities sq
    JOIN products p ON p.id = sq.product_id AND p.tenant_id = v_tid
    LEFT JOIN stock_movements sm ON sm.product_id = p.id AND sm.tenant_id = v_tid
    WHERE sq.tenant_id = v_tid AND sq.quantity > 0
    GROUP BY p.id, p.name, sq.quantity, sq.unit_cost
    HAVING max(sm.movement_date) IS NULL OR max(sm.movement_date) < v_fy.start_date - INTERVAL '365 days'
  LOOP
    DECLARE
      v_prov_amount numeric := v_rec.stock_value * 0.50;  -- 50% pour stock obsolète
    BEGIN
      v_provisions := v_provisions || jsonb_build_object(
        'type', 'stock_obsolete',
        'product', v_rec.name,
        'quantity', v_rec.quantity,
        'stock_value', round(v_rec.stock_value, 2),
        'last_movement', v_rec.last_movement,
        'provision_amount', round(v_prov_amount, 2)
      );
      v_total := v_total + v_prov_amount;
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'fiscal_year_id', p_fiscal_year_id,
    'fiscal_year_code', v_fy.code,
    'provisions', v_provisions,
    'total_provisions', round(v_total, 2),
    'provision_count', jsonb_array_length(v_provisions),
    'calculated_at', now()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION calculate_provisions(uuid) TO authenticated;


-- ============================================================
-- 6. post_deferred_charge(p_entry_id, p_type, p_amount, p_months)
--    CCA (Charges Constatées d'Avance) / PCA (Produits Constatés d'Avance)
--    Répartit une charge/produit sur plusieurs mois
--    Inspiré de : Sage, Cegid, Odoo
-- ============================================================
CREATE OR REPLACE FUNCTION post_deferred_charge(
  p_entry_id uuid,
  p_type text,        -- 'cca' ou 'pca'
  p_amount numeric,
  p_months integer DEFAULT 12
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_je RECORD;
  v_monthly_amount numeric;
  v_entries jsonb := '[]'::jsonb;
  v_entry_id uuid;
  v_number text;
  v_date date;
  v_account_deferred text;
  v_account_charge text;
  v_is_debit boolean;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  IF p_type NOT IN ('cca', 'pca') THEN
    RAISE EXCEPTION 'Type doit être cca ou pca';
  END IF;

  SELECT * INTO v_je FROM journal_entries WHERE id = p_entry_id AND tenant_id = v_tid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Écriture non trouvée: %', p_entry_id;
  END IF;

  v_monthly_amount := p_amount / p_months;
  v_account_deferred := CASE WHEN p_type = 'cca' THEN '486000' ELSE '487000' END;
  v_is_debit := (p_type = 'cca');

  -- Écriture de transfert initial (date de l'écriture d'origine)
  v_number := v_je.number || '-DEF';
  INSERT INTO journal_entries (
    tenant_id, number, date, journal_code, status, description
  ) VALUES (
    v_tid, v_number, v_je.date, 'OD', 'posted',
    CASE WHEN p_type = 'cca' THEN 'CCA ' ELSE 'PCA ' END || v_je.description
  )
  RETURNING id INTO v_entry_id;

  -- Transfert vers compte d'attente
  IF p_type = 'cca' THEN
    -- CCA : Débit 486 (charge constatée d'avance) / Crédit compte de charge
    INSERT INTO journal_lines (tenant_id, journal_id, account_code, debit, credit, description, line_order)
    VALUES (v_tid, v_entry_id, v_account_deferred, p_amount, 0, 'CCA à répartir', 1);
    INSERT INTO journal_lines (tenant_id, journal_id, account_code, debit, credit, description, line_order)
    VALUES (v_tid, v_entry_id, '6_____', 0, p_amount, 'Reprise charge CCA', 2);
  ELSE
    -- PCA : Débit compte de produit / Crédit 487 (produit constaté d'avance)
    INSERT INTO journal_lines (tenant_id, journal_id, account_code, debit, credit, description, line_order)
    VALUES (v_tid, v_entry_id, '7_____', p_amount, 0, 'Reprise produit PCA', 1);
    INSERT INTO journal_lines (tenant_id, journal_id, account_code, debit, credit, description, line_order)
    VALUES (v_tid, v_entry_id, v_account_deferred, 0, p_amount, 'PCA à répartir', 2);
  END IF;

  v_entries := v_entries || jsonb_build_object(
    'type', 'initial_deferral',
    'entry_number', v_number,
    'amount', round(p_amount, 2),
    'account', v_account_deferred
  );

  -- Écritures mensuelles de reprise
  FOR i IN 1..p_months LOOP
    v_date := (to_char(v_je.date + (i || ' month')::interval, 'YYYY-MM-01'))::date;
    v_number := v_je.number || '-DEF-' || i;

    INSERT INTO journal_entries (
      tenant_id, number, date, journal_code, status, description
    ) VALUES (
      v_tid, v_number, v_date, 'OD', 'posted',
      'Reprise ' || CASE WHEN p_type = 'cca' THEN 'CCA' ELSE 'PCA' END || ' mois ' || i || '/' || p_months
    )
    RETURNING id INTO v_entry_id;

    IF p_type = 'cca' THEN
      -- Reprise CCA : Débit compte de charge / Crédit 486
      INSERT INTO journal_lines (tenant_id, journal_id, account_code, debit, credit, description, line_order)
      VALUES (v_tid, v_entry_id, '6_____', v_monthly_amount, 0, 'Reprise CCA mois ' || i, 1);
      INSERT INTO journal_lines (tenant_id, journal_id, account_code, debit, credit, description, line_order)
      VALUES (v_tid, v_entry_id, v_account_deferred, 0, v_monthly_amount, 'Solde CCA mois ' || i, 2);
    ELSE
      -- Reprise PCA : Débit 487 / Crédit compte de produit
      INSERT INTO journal_lines (tenant_id, journal_id, account_code, debit, credit, description, line_order)
      VALUES (v_tid, v_entry_id, v_account_deferred, v_monthly_amount, 0, 'Solde PCA mois ' || i, 1);
      INSERT INTO journal_lines (tenant_id, journal_id, account_code, debit, credit, description, line_order)
      VALUES (v_tid, v_entry_id, '7_____', 0, v_monthly_amount, 'Reprise PCA mois ' || i, 2);
    END IF;

    v_entries := v_entries || jsonb_build_object(
      'type', 'monthly_recognition',
      'month', i,
      'entry_number', v_number,
      'date', v_date,
      'amount', round(v_monthly_amount, 2)
    );
  END LOOP;

  RETURN jsonb_build_object(
    'original_entry', v_je.number,
    'type', p_type,
    'total_amount', round(p_amount, 2),
    'monthly_amount', round(v_monthly_amount, 2),
    'months', p_months,
    'entries', v_entries,
    'entry_count', jsonb_array_length(v_entries)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION post_deferred_charge(uuid, text, numeric, integer) TO authenticated;


-- ============================================================
-- 7. generate_accounting_annex(p_fiscal_year_id)
--    Annexe comptable : notes et informations complémentaires
--    Inspiré de : Sage, Cegid, Pennylane
-- ============================================================
CREATE OR REPLACE FUNCTION generate_accounting_annex(p_fiscal_year_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_fy RECORD;
  v_sections jsonb := '[]'::jsonb;
  v_rec RECORD;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  SELECT * INTO v_fy FROM fiscal_years WHERE id = p_fiscal_year_id AND tenant_id = v_tid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Exercice non trouvé: %', p_fiscal_year_id;
  END IF;

  -- Section 1 : Immobilisations
  SELECT
    count(*) as count,
    COALESCE(sum(purchase_value), 0) as gross_value,
    COALESCE(sum(current_value), 0) as net_value
  INTO v_rec
  FROM fixed_assets
  WHERE tenant_id = v_tid AND status = 'active'
    AND purchase_date <= v_fy.end_date;

  v_sections := v_sections || jsonb_build_object(
    'section', 'immobilisations',
    'title', 'État des immobilisations',
    'data', jsonb_build_object(
      'count', v_rec.count,
      'gross_value', round(v_rec.gross_value, 2),
      'net_value', round(v_rec.net_value, 2)
    )
  );

  -- Section 2 : Amortissements
  SELECT
    count(*) as count,
    COALESCE(sum(amount), 0) as total_depreciation
  INTO v_rec
  FROM asset_depreciations
  WHERE tenant_id = v_tid
    AND fiscal_year_code = v_fy.code;

  v_sections := v_sections || jsonb_build_object(
    'section', 'amortissements',
    'title', 'Tableau des amortissements',
    'data', jsonb_build_object(
      'count', v_rec.count,
      'total_depreciation', round(v_rec.total_depreciation, 2)
    )
  );

  -- Section 3 : Créances clients
  SELECT
    count(*) as invoice_count,
    COALESCE(sum(total - COALESCE(amount_paid, 0)), 0) as outstanding
  INTO v_rec
  FROM invoices
  WHERE tenant_id = v_tid
    AND status NOT IN ('cancelled', 'draft')
    AND payment_state IN ('not_paid', 'partial')
    AND date <= v_fy.end_date;

  v_sections := v_sections || jsonb_build_object(
    'section', 'creances_clients',
    'title', 'État des créances clients',
    'data', jsonb_build_object(
      'invoice_count', v_rec.invoice_count,
      'outstanding', round(v_rec.outstanding, 2)
    )
  );

  -- Section 4 : Dettes fournisseurs
  SELECT
    count(*) as invoice_count,
    COALESCE(sum(total - COALESCE(amount_paid, 0)), 0) as outstanding
  INTO v_rec
  FROM purchase_invoices
  WHERE tenant_id = v_tid
    AND status NOT IN ('cancelled', 'draft')
    AND payment_state IN ('not_paid', 'partial')
    AND date <= v_fy.end_date;

  v_sections := v_sections || jsonb_build_object(
    'section', 'dettes_fournisseurs',
    'title', 'État des dettes fournisseurs',
    'data', jsonb_build_object(
      'invoice_count', v_rec.invoice_count,
      'outstanding', round(v_rec.outstanding, 2)
    )
  );

  -- Section 5 : Stocks
  SELECT
    count(DISTINCT sq.product_id) as product_count,
    COALESCE(sum(sq.quantity * sq.unit_cost), 0) as stock_value
  INTO v_rec
  FROM stock_quantities sq
  WHERE sq.tenant_id = v_tid AND sq.quantity > 0;

  v_sections := v_sections || jsonb_build_object(
    'section', 'stocks',
    'title', 'État des stocks',
    'data', jsonb_build_object(
      'product_count', v_rec.product_count,
      'stock_value', round(v_rec.stock_value, 2)
    )
  );

  -- Section 6 : Effectifs
  SELECT
    count(*) as headcount,
    COALESCE(sum(salary), 0) as total_payroll
  INTO v_rec
  FROM employees
  WHERE tenant_id = v_tid AND status = 'active';

  v_sections := v_sections || jsonb_build_object(
    'section', 'effectifs',
    'title', 'Effectifs et masse salariale',
    'data', jsonb_build_object(
      'headcount', v_rec.headcount,
      'monthly_payroll', round(v_rec.total_payroll, 2)
    )
  );

  RETURN jsonb_build_object(
    'fiscal_year_id', p_fiscal_year_id,
    'fiscal_year_code', v_fy.code,
    'sections', v_sections,
    'section_count', jsonb_array_length(v_sections),
    'generated_at', now()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION generate_accounting_annex(uuid) TO authenticated;


-- ============================================================
-- 8. calculate_production_cost(p_manufacturing_order_id)
--    Coût de production : matières + main d'œuvre + charges indirectes
--    Inspiré de : Odoo, SAP, Sage Production
-- ============================================================
CREATE OR REPLACE FUNCTION calculate_production_cost(p_manufacturing_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_mo RECORD;
  v_material_cost numeric := 0;
  v_labor_cost numeric := 0;
  v_overhead_cost numeric := 0;
  v_total_cost numeric := 0;
  v_unit_cost numeric := 0;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  SELECT * INTO v_mo FROM manufacturing_orders WHERE id = p_manufacturing_order_id AND tenant_id = v_tid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ordre de fabrication non trouvé: %', p_manufacturing_order_id;
  END IF;

  -- Coût des matières premières consommées
  SELECT COALESCE(sum(oc.quantity * COALESCE(p.standard_cost, p.stock_quantity * COALESCE(sq.unit_cost, 0), 0)), 0)
  INTO v_material_cost
  FROM of_consumptions oc
  JOIN products p ON p.id = oc.product_id AND p.tenant_id = v_tid
  LEFT JOIN stock_quantities sq ON sq.product_id = p.id AND sq.tenant_id = v_tid
  WHERE oc.tenant_id = v_tid AND oc.manufacturing_order_id = p_manufacturing_order_id;

  -- Coût de la main d'œuvre (basé sur les entrées de temps)
  SELECT COALESCE(sum(te.hours * COALESCE(e.salary, 0) / 160), 0)
  INTO v_labor_cost
  FROM project_time_entries te
  LEFT JOIN employees e ON e.id = te.employee_id AND e.tenant_id = v_tid
  WHERE te.tenant_id = v_tid AND te.reference_id = p_manufacturing_order_id;

  -- Charges indirectes (10% du coût direct par défaut)
  v_overhead_cost := (v_material_cost + v_labor_cost) * 0.10;

  -- Coût total
  v_total_cost := v_material_cost + v_labor_cost + v_overhead_cost;

  -- Coût unitaire
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

GRANT EXECUTE ON FUNCTION calculate_production_cost(uuid) TO authenticated;


-- ============================================================
-- 9. calculate_inventory_variance(p_warehouse_id)
--    Écarts d'inventaire : théorique vs physique
--    Inspiré de : Odoo, SAP, Sage
-- ============================================================
CREATE OR REPLACE FUNCTION calculate_inventory_variance(p_warehouse_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_variances jsonb := '[]'::jsonb;
  v_rec RECORD;
  v_total_variance numeric := 0;
  v_positive_variance numeric := 0;
  v_negative_variance numeric := 0;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  -- Comparer stock théorique (stock_quantities) avec mouvements réels
  FOR v_rec IN
    SELECT
      sq.product_id,
      p.name as product_name,
      sq.warehouse_id,
      w.name as warehouse_name,
      sq.quantity as theoretical_qty,
      sq.unit_cost,
      COALESCE((
        SELECT sum(CASE
          WHEN movement_type IN ('in','initial') THEN quantity
          WHEN movement_type IN ('out') THEN -quantity
          WHEN movement_type = 'adjustment' AND quantity > 0 THEN quantity
          WHEN movement_type = 'adjustment' AND quantity < 0 THEN -quantity
          ELSE 0
        END)
        FROM stock_movements sm
        WHERE sm.tenant_id = v_tid
          AND sm.product_id = sq.product_id
          AND sm.warehouse_id = sq.warehouse_id
      ), 0) as calculated_qty
    FROM stock_quantities sq
    JOIN products p ON p.id = sq.product_id AND p.tenant_id = v_tid
    JOIN warehouses w ON w.id = sq.warehouse_id AND w.tenant_id = v_tid
    WHERE sq.tenant_id = v_tid
      AND (p_warehouse_id IS NULL OR sq.warehouse_id = p_warehouse_id)
      AND sq.quantity > 0
  LOOP
    DECLARE
      v_variance numeric := v_rec.calculated_qty - v_rec.theoretical_qty;
      v_variance_value numeric := v_variance * v_rec.unit_cost;
    BEGIN
      IF v_variance != 0 THEN
        v_variances := v_variances || jsonb_build_object(
          'product_id', v_rec.product_id,
          'product_name', v_rec.product_name,
          'warehouse_name', v_rec.warehouse_name,
          'theoretical_qty', v_rec.theoretical_qty,
          'calculated_qty', v_rec.calculated_qty,
          'variance_qty', round(v_variance, 2),
          'unit_cost', round(v_rec.unit_cost, 2),
          'variance_value', round(v_variance_value, 2),
          'variance_type', CASE WHEN v_variance > 0 THEN 'positive' ELSE 'negative' END
        );

        v_total_variance := v_total_variance + v_variance_value;
        IF v_variance > 0 THEN
          v_positive_variance := v_positive_variance + v_variance_value;
        ELSE
          v_negative_variance := v_negative_variance + v_variance_value;
        END IF;
      END IF;
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'warehouse_id', p_warehouse_id,
    'variances', v_variances,
    'variance_count', jsonb_array_length(v_variances),
    'total_variance', round(v_total_variance, 2),
    'positive_variance', round(v_positive_variance, 2),
    'negative_variance', round(v_negative_variance, 2),
    'calculated_at', now()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION calculate_inventory_variance(uuid) TO authenticated;


-- ============================================================
-- RÉCAPITULATIF
-- ============================================================
-- 1. calculate_late_payment_penalties() — Pénalités de retard
-- 2. calculate_sales_commissions()      — Commissions commerciaux
-- 3. customer_credit_score()            — Scoring risque client
-- 4. calculate_project_profitability()  — Rentabilité projet
-- 5. calculate_provisions()             — Provisions
-- 6. post_deferred_charge()             — CCA / PCA
-- 7. generate_accounting_annex()        — Annexe comptable
-- 8. calculate_production_cost()        — Coût de production
-- 9. calculate_inventory_variance()     — Écarts d'inventaire
-- ============================================================
