-- ============================================================
-- 143_fix_remaining_triggers.sql
-- LOT2-17 : update_po_status_on_receipt — quantity_received inexistant
-- LOT2-18/19/20 : v_emp RECORD non typé → variables séparées
-- LOT2-21 : sync_cpf_on_transaction — ON CONFLICT sans index unique
-- ============================================================

-- ============================================================
-- LOT2-17 : Corriger update_po_status_on_receipt
-- purchase_order_lines n'a pas quantity_received.
-- Il faut calculer depuis goods_receipt_lines.
-- ============================================================
CREATE OR REPLACE FUNCTION update_po_status_on_receipt()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  v_po RECORD;
  v_total_ordered numeric;
  v_total_received numeric;
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status AND NEW.status = 'received' THEN
    IF NEW.purchase_order_id IS NOT NULL THEN
      -- Total commandé depuis purchase_order_lines
      SELECT COALESCE(SUM(quantity), 0)
      INTO v_total_ordered
      FROM purchase_order_lines
      WHERE purchase_order_id = NEW.purchase_order_id
        AND tenant_id = NEW.tenant_id;

      -- LOT2-17 : Total reçu depuis goods_receipt_lines (pas purchase_order_lines)
      SELECT COALESCE(SUM(grl.quantity_received), 0)
      INTO v_total_received
      FROM goods_receipt_lines grl
      JOIN goods_receipts gr ON gr.id = grl.goods_receipt_id
        AND gr.tenant_id = grl.tenant_id
      WHERE gr.purchase_order_id = NEW.purchase_order_id
        AND gr.tenant_id = NEW.tenant_id
        AND gr.status = 'received';

      IF v_total_received >= v_total_ordered AND v_total_ordered > 0 THEN
        UPDATE purchase_orders
        SET status = 'received', updated_at = now()
        WHERE id = NEW.purchase_order_id AND tenant_id = NEW.tenant_id;
      ELSIF v_total_received > 0 THEN
        UPDATE purchase_orders
        SET status = 'partial', updated_at = now()
        WHERE id = NEW.purchase_order_id AND tenant_id = NEW.tenant_id;
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

-- ============================================================
-- LOT2-18 : Corriger calculate_lateness_on_timesheet
-- v_emp RECORD → variables typées séparées
-- ============================================================
CREATE OR REPLACE FUNCTION calculate_lateness_on_timesheet()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_scheduled_start timestamptz;
  v_scheduled_end timestamptz;
  v_arrival timestamptz;
  v_departure timestamptz;
  v_diff_min integer;
  v_default_start time;
  v_default_end time;
BEGIN
  -- Récupérer les horaires par défaut de l'employé si non spécifiés
  IF NEW.scheduled_start IS NULL OR NEW.scheduled_end IS NULL THEN
    SELECT default_start_time, default_end_time
    INTO v_default_start, v_default_end
    FROM employees
    WHERE id = NEW.employee_id AND tenant_id = NEW.tenant_id;

    IF NEW.scheduled_start IS NULL THEN
      NEW.scheduled_start := COALESCE(v_default_start, '09:00'::time);
    END IF;
    IF NEW.scheduled_end IS NULL THEN
      NEW.scheduled_end := COALESCE(v_default_end, '17:00'::time);
    END IF;
  END IF;

  -- Calculer le retard si l'heure d'arrivée est renseignée
  IF NEW.arrival_time IS NOT NULL THEN
    v_scheduled_start := (NEW.date::date + NEW.scheduled_start)::timestamptz;
    v_arrival := NEW.arrival_time;

    IF v_arrival > v_scheduled_start THEN
      v_diff_min := EXTRACT(EPOCH FROM (v_arrival - v_scheduled_start))::integer / 60;
      NEW.late_minutes := GREATEST(v_diff_min, 0);
    ELSE
      NEW.late_minutes := 0;
    END IF;
  END IF;

  -- Calculer le départ anticipé et les heures supplémentaires
  IF NEW.departure_time IS NOT NULL THEN
    v_scheduled_end := (NEW.date::date + NEW.scheduled_end)::timestamptz;
    v_departure := NEW.departure_time;

    IF v_departure < v_scheduled_end THEN
      v_diff_min := EXTRACT(EPOCH FROM (v_scheduled_end - v_departure))::integer / 60;
      NEW.early_leave_minutes := GREATEST(v_diff_min, 0);
    ELSE
      NEW.early_leave_minutes := 0;
    END IF;

    IF v_departure > v_scheduled_end THEN
      v_diff_min := EXTRACT(EPOCH FROM (v_departure - v_scheduled_end))::integer / 60;
      NEW.overtime_minutes := GREATEST(v_diff_min, 0);
    ELSE
      NEW.overtime_minutes := 0;
    END IF;
  END IF;

  -- Calculer les heures travaillées
  IF NEW.arrival_time IS NOT NULL AND NEW.departure_time IS NOT NULL THEN
    NEW.hours := EXTRACT(EPOCH FROM (NEW.departure_time - NEW.arrival_time))::integer / 3600.0;
  END IF;

  RETURN NEW;
END;
$$;

-- ============================================================
-- LOT2-19 : Corriger deduct_lateness_on_timesheet_approval
-- v_emp RECORD → variables typées séparées
-- ============================================================
CREATE OR REPLACE FUNCTION deduct_lateness_on_timesheet_approval()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_rule RECORD;
  v_period text;
  v_pay_run_id uuid;
  v_emp_salary numeric;
  v_emp_weekly_hours numeric;
  v_hourly_rate numeric;
  v_deductible_minutes integer;
  v_deduction numeric;
  v_threshold integer := 15;
  v_grace integer := 5;
  v_deduction_rate numeric := 100;
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status AND NEW.status = 'approved' THEN
    IF NEW.late_minutes IS NULL OR NEW.late_minutes <= 0 OR NEW.late_justified = true THEN
      RETURN NEW;
    END IF;

    SELECT * INTO v_rule
    FROM leave_rules
    WHERE tenant_id = NEW.tenant_id
      AND active = true
      AND lateness_threshold_minutes IS NOT NULL
    ORDER BY lateness_threshold_minutes DESC
    LIMIT 1;

    IF FOUND THEN
      v_threshold := COALESCE(v_rule.lateness_threshold_minutes, 15);
      v_grace := COALESCE(v_rule.lateness_grace_period, 5);
      v_deduction_rate := COALESCE(v_rule.lateness_deduction_rate, 100);
    END IF;

    IF NEW.late_minutes <= v_threshold THEN
      RETURN NEW;
    END IF;

    v_deductible_minutes := GREATEST(NEW.late_minutes - v_threshold - v_grace, 0);

    IF v_deductible_minutes <= 0 THEN
      RETURN NEW;
    END IF;

    -- LOT2-19 : variables typées au lieu de v_emp.salary
    SELECT salary, weekly_hours
    INTO v_emp_salary, v_emp_weekly_hours
    FROM employees
    WHERE id = NEW.employee_id AND tenant_id = NEW.tenant_id;

    IF v_emp_salary IS NULL OR v_emp_salary <= 0 THEN
      RETURN NEW;
    END IF;

    v_hourly_rate := v_emp_salary / (COALESCE(v_emp_weekly_hours, 35) * 4.33) / 60;

    v_deduction := v_deductible_minutes * v_hourly_rate * (v_deduction_rate / 100);

    v_period := to_char(NEW.date, 'YYYY-MM');

    SELECT id INTO v_pay_run_id
    FROM pay_runs
    WHERE tenant_id = NEW.tenant_id
      AND to_char(period_start, 'YYYY-MM') = v_period
      AND status IN ('draft', 'processing')
    ORDER BY created_at DESC
    LIMIT 1;

    IF NOT EXISTS (
      SELECT 1 FROM payroll_variable_elements
      WHERE tenant_id = NEW.tenant_id
        AND employee_id = NEW.employee_id
        AND source = 'timesheet_lateness'
        AND source_id = NEW.id
    ) THEN
      INSERT INTO payroll_variable_elements (
        tenant_id, employee_id, pay_run_id, period,
        element_type, description, quantity, unit_price, amount,
        source, source_id, integrated
      ) VALUES (
        NEW.tenant_id, NEW.employee_id, v_pay_run_id, v_period,
        'lateness_deduction',
        'Déduction retard ' || v_deductible_minutes || 'min le ' || to_char(NEW.date, 'DD/MM/YYYY'),
        v_deductible_minutes, v_hourly_rate, v_deduction,
        'timesheet_lateness', NEW.id, false
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- ============================================================
-- LOT2-20 : Corriger deduct_unpaid_absence_on_timesheet_approval
-- v_emp RECORD → variable typée
-- ============================================================
CREATE OR REPLACE FUNCTION deduct_unpaid_absence_on_timesheet_approval()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_period text;
  v_pay_run_id uuid;
  v_emp_salary numeric;
  v_daily_rate numeric;
  v_deduction numeric;
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status AND NEW.status = 'approved' THEN
    IF NEW.absence_type IS NULL OR NEW.absence_type != 'unpaid' THEN
      RETURN NEW;
    END IF;

    v_period := to_char(NEW.date, 'YYYY-MM');

    -- LOT2-20 : variable typée au lieu de v_emp.salary
    SELECT salary INTO v_emp_salary
    FROM employees
    WHERE id = NEW.employee_id AND tenant_id = NEW.tenant_id;

    IF v_emp_salary IS NULL OR v_emp_salary <= 0 THEN
      RETURN NEW;
    END IF;

    v_daily_rate := v_emp_salary / 30;
    v_deduction := v_daily_rate;

    SELECT id INTO v_pay_run_id
    FROM pay_runs
    WHERE tenant_id = NEW.tenant_id
      AND to_char(period_start, 'YYYY-MM') = v_period
      AND status IN ('draft', 'processing')
    ORDER BY created_at DESC
    LIMIT 1;

    IF NOT EXISTS (
      SELECT 1 FROM payroll_variable_elements
      WHERE tenant_id = NEW.tenant_id
        AND employee_id = NEW.employee_id
        AND source = 'timesheet_absence'
        AND source_id = NEW.id
    ) THEN
      INSERT INTO payroll_variable_elements (
        tenant_id, employee_id, pay_run_id, period,
        element_type, description, amount,
        source, source_id, integrated
      ) VALUES (
        NEW.tenant_id, NEW.employee_id, v_pay_run_id, v_period,
        'unpaid_absence_deduction',
        'Absence non justifiée le ' || to_char(NEW.date, 'DD/MM/YYYY'),
        v_deduction,
        'timesheet_absence', NEW.id, false
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- ============================================================
-- LOT2-21 : Créer l'index unique sur cpf_accounts (tenant_id, employee_id)
-- pour que ON CONFLICT (tenant_id, employee_id) fonctionne
-- ============================================================
-- L'index existant est sur employee_id seul, ce qui ne correspond pas
-- au ON CONFLICT (tenant_id, employee_id) du trigger sync_cpf_on_transaction.
CREATE UNIQUE INDEX IF NOT EXISTS cpf_accounts_tenant_employee_unique
  ON cpf_accounts (tenant_id, employee_id);
