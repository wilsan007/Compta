-- ============================================================
-- 83_attendance_and_lateness.sql
--
-- Infrastructure de pointage, calcul de retard et déduction automatique.
--
-- Inspiré de :
--   - Rippling : clock-in → lateness alert → payroll
--   - PayFit   : retard → déduction sur bulletin (avec politique)
--   - Gusto    : time tracking → payroll sync
--   - Workday  : attendance → payroll calculation input
--
-- Sections :
--   A. Ajout colonnes attendance sur timesheets
--   B. Ajout colonnes work schedule sur employees
--   C. Ajout colonnes lateness policy sur leave_rules
--   D. Trigger calcul automatique du retard (BEFORE INSERT/UPDATE)
--   E. Trigger déduction retard → payroll_variable_elements
--   F. Trigger déduction absence non justifiée → payroll_variable_elements
-- ============================================================

-- ============================================================
-- SECTION A — Colonnes attendance sur timesheets
-- ============================================================

-- La table timesheets n'avait que : id, employee_id, date, hours, description,
-- project_id, status, created_at, tenant_id
-- On ajoute les colonnes de pointage.

ALTER TABLE timesheets ADD COLUMN IF NOT EXISTS arrival_time timestamptz;
ALTER TABLE timesheets ADD COLUMN IF NOT EXISTS departure_time timestamptz;
ALTER TABLE timesheets ADD COLUMN IF NOT EXISTS scheduled_start time DEFAULT '09:00';
ALTER TABLE timesheets ADD COLUMN IF NOT EXISTS scheduled_end time DEFAULT '17:00';
ALTER TABLE timesheets ADD COLUMN IF NOT EXISTS late_minutes integer DEFAULT 0;
ALTER TABLE timesheets ADD COLUMN IF NOT EXISTS late_justified boolean DEFAULT false;
ALTER TABLE timesheets ADD COLUMN IF NOT EXISTS late_justification text;
ALTER TABLE timesheets ADD COLUMN IF NOT EXISTS early_leave_minutes integer DEFAULT 0;
ALTER TABLE timesheets ADD COLUMN IF NOT EXISTS overtime_minutes integer DEFAULT 0;
ALTER TABLE timesheets ADD COLUMN IF NOT EXISTS absence_type text DEFAULT 'none';
ALTER TABLE timesheets ADD COLUMN IF NOT EXISTS absence_reason text;
ALTER TABLE timesheets ADD COLUMN IF NOT EXISTS shift_date date DEFAULT CURRENT_DATE;
ALTER TABLE timesheets ADD COLUMN IF NOT EXISTS approved_by uuid;
ALTER TABLE timesheets ADD COLUMN IF NOT EXISTS approved_at timestamptz;

-- Commentaires pour documentation
COMMENT ON COLUMN timesheets.arrival_time IS 'Horodatage réel d''arrivée de l''employé';
COMMENT ON COLUMN timesheets.departure_time IS 'Horodatage réel de départ de l''employé';
COMMENT ON COLUMN timesheets.scheduled_start IS 'Heure de début prévue (ex: 09:00)';
COMMENT ON COLUMN timesheets.scheduled_end IS 'Heure de fin prévue (ex: 17:00)';
COMMENT ON COLUMN timesheets.late_minutes IS 'Minutes de retard calculées (arrival - scheduled_start - grace)';
COMMENT ON COLUMN timesheets.late_justified IS 'True si le retard est justifié (pas de déduction)';
COMMENT ON COLUMN timesheets.early_leave_minutes IS 'Minutes de départ anticipé calculées';
COMMENT ON COLUMN timesheets.overtime_minutes IS 'Minutes au-delà de l''horaire prévu';
COMMENT ON COLUMN timesheets.absence_type IS 'Type d''absence: none, sick, unpaid, personal, mission';
COMMENT ON COLUMN timesheets.shift_date IS 'Date du shift de travail (différente de created_at)';


-- ============================================================
-- SECTION B — Colonnes work schedule sur employees
-- ============================================================

ALTER TABLE employees ADD COLUMN IF NOT EXISTS weekly_hours numeric DEFAULT 35;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS default_start_time time DEFAULT '09:00';
ALTER TABLE employees ADD COLUMN IF NOT EXISTS default_end_time time DEFAULT '17:00';

COMMENT ON COLUMN employees.weekly_hours IS 'Heures hebdomadaires contractuelles (défaut: 35)';
COMMENT ON COLUMN employees.default_start_time IS 'Heure de début de shift par défaut';
COMMENT ON COLUMN employees.default_end_time IS 'Heure de fin de shift par défaut';


-- ============================================================
-- SECTION C — Colonnes lateness policy sur leave_rules
-- ============================================================

-- On réutilise leave_rules comme table de configuration des politiques
-- de retard (en plus des congés). On ajoute des colonnes optionnelles.
ALTER TABLE leave_rules ADD COLUMN IF NOT EXISTS lateness_threshold_minutes integer DEFAULT 15;
ALTER TABLE leave_rules ADD COLUMN IF NOT EXISTS lateness_deduction_rate numeric DEFAULT 100;
ALTER TABLE leave_rules ADD COLUMN IF NOT EXISTS lateness_grace_period integer DEFAULT 5;

COMMENT ON COLUMN leave_rules.lateness_threshold_minutes IS 'Minutes de tolérance avant déduction (défaut: 15)';
COMMENT ON COLUMN leave_rules.lateness_deduction_rate IS '% du taux horaire déduit par minute de retard au-delà du seuil';
COMMENT ON COLUMN leave_rules.lateness_grace_period IS 'Minutes de grâce non déduites (défaut: 5)';


-- ============================================================
-- SECTION D — Trigger calcul automatique du retard
-- ============================================================

-- Calcule late_minutes, early_leave_minutes et overtime_minutes
-- automatiquement avant INSERT ou UPDATE sur timesheets.
CREATE OR REPLACE FUNCTION calculate_lateness_on_timesheet()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_scheduled_start timestamptz;
  v_scheduled_end timestamptz;
  v_arrival timestamptz;
  v_departure timestamptz;
  v_diff_min integer;
  v_emp RECORD;
BEGIN
  -- Récupérer les horaires par défaut de l'employé si non spécifiés
  IF NEW.scheduled_start IS NULL OR NEW.scheduled_end IS NULL THEN
    SELECT default_start_time, default_end_time INTO v_emp.default_start_time, v_emp.default_end_time
    FROM employees
    WHERE id = NEW.employee_id AND tenant_id = NEW.tenant_id;

    IF NEW.scheduled_start IS NULL THEN
      NEW.scheduled_start := COALESCE(v_emp.default_start_time, '09:00'::time);
    END IF;
    IF NEW.scheduled_end IS NULL THEN
      NEW.scheduled_end := COALESCE(v_emp.default_end_time, '17:00'::time);
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

  -- Calculer les heures travaillées si arrival et departure sont renseignées
  IF NEW.arrival_time IS NOT NULL AND NEW.departure_time IS NOT NULL THEN
    NEW.hours := EXTRACT(EPOCH FROM (NEW.departure_time - NEW.arrival_time))::integer / 3600.0;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS calculate_lateness ON timesheets;
CREATE TRIGGER calculate_lateness
  BEFORE INSERT OR UPDATE OF arrival_time, departure_time, scheduled_start, scheduled_end ON timesheets
  FOR EACH ROW
  EXECUTE FUNCTION calculate_lateness_on_timesheet();


-- ============================================================
-- SECTION E — Trigger déduction retard → payroll_variable_elements
-- ============================================================

-- Quand un timesheet est approuvé (status → 'approved') et que le retard
-- n'est pas justifié, on crée un payroll_variable_element de type
-- 'lateness_deduction'.
-- La déduction = (late_minutes - grace_period) × taux_horaire × deduction_rate
-- Le retard n'est déduit que s'il dépasse le seuil (threshold_minutes).
CREATE OR REPLACE FUNCTION deduct_lateness_on_timesheet_approval()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_rule RECORD;
  v_period text;
  v_pay_run_id uuid;
  v_emp RECORD;
  v_hourly_rate numeric;
  v_deductible_minutes integer;
  v_deduction numeric;
  v_threshold integer := 15;
  v_grace integer := 5;
  v_deduction_rate numeric := 100;
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status AND NEW.status = 'approved' THEN
    -- Ne traiter que les retards non justifiés
    IF NEW.late_minutes IS NULL OR NEW.late_minutes <= 0 OR NEW.late_justified = true THEN
      RETURN NEW;
    END IF;

    -- Récupérer la politique de retard (leave_rules avec lateness_threshold)
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

    -- Le retard ne est déductible que s'il dépasse le seuil
    IF NEW.late_minutes <= v_threshold THEN
      RETURN NEW;
    END IF;

    -- Minutes déductibles = retard total - seuil - grâce
    v_deductible_minutes := GREATEST(NEW.late_minutes - v_threshold - v_grace, 0);

    IF v_deductible_minutes <= 0 THEN
      RETURN NEW;
    END IF;

    -- Calculer le taux horaire de l'employé
    SELECT salary, weekly_hours INTO v_emp.salary, v_emp.weekly_hours
    FROM employees
    WHERE id = NEW.employee_id AND tenant_id = NEW.tenant_id;

    IF v_emp.salary IS NULL OR v_emp.salary <= 0 THEN
      RETURN NEW;
    END IF;

    v_hourly_rate := v_emp.salary / (COALESCE(v_emp.weekly_hours, 35) * 4.33) / 60;  -- taux par minute

    -- Déduction = minutes déductibles × taux par minute × taux de déduction
    v_deduction := v_deductible_minutes * v_hourly_rate * (v_deduction_rate / 100);

    v_period := to_char(NEW.date, 'YYYY-MM');

    -- Trouver le pay_run en cours
    SELECT id INTO v_pay_run_id
    FROM pay_runs
    WHERE tenant_id = NEW.tenant_id
      AND to_char(period_start, 'YYYY-MM') = v_period
      AND status IN ('draft', 'processing')
    ORDER BY created_at DESC
    LIMIT 1;

    -- Éviter les doublons : vérifier qu'un élément lateness n'existe pas déjà
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

DROP TRIGGER IF EXISTS deduct_lateness ON timesheets;
CREATE TRIGGER deduct_lateness
  AFTER UPDATE ON timesheets
  FOR EACH ROW
  EXECUTE FUNCTION deduct_lateness_on_timesheet_approval();


-- ============================================================
-- SECTION F — Trigger absence non justifiée → payroll_variable_elements
-- ============================================================

-- Quand un timesheet est approuvé avec un type d'absence 'unpaid',
-- on crée un payroll_variable_element de type 'unpaid_absence_deduction'.
CREATE OR REPLACE FUNCTION deduct_unpaid_absence_on_timesheet_approval()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_period text;
  v_pay_run_id uuid;
  v_emp RECORD;
  v_daily_rate numeric;
  v_deduction numeric;
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status AND NEW.status = 'approved' THEN
    -- Ne traiter que les absences non payées
    IF NEW.absence_type IS NULL OR NEW.absence_type != 'unpaid' THEN
      RETURN NEW;
    END IF;

    v_period := to_char(NEW.date, 'YYYY-MM');

    -- Calculer le taux journalier
    SELECT salary INTO v_emp.salary
    FROM employees
    WHERE id = NEW.employee_id AND tenant_id = NEW.tenant_id;

    IF v_emp.salary IS NULL OR v_emp.salary <= 0 THEN
      RETURN NEW;
    END IF;

    v_daily_rate := v_emp.salary / 30;
    v_deduction := v_daily_rate;  -- 1 jour d'absence

    -- Trouver le pay_run en cours
    SELECT id INTO v_pay_run_id
    FROM pay_runs
    WHERE tenant_id = NEW.tenant_id
      AND to_char(period_start, 'YYYY-MM') = v_period
      AND status IN ('draft', 'processing')
    ORDER BY created_at DESC
    LIMIT 1;

    -- Éviter les doublons
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

DROP TRIGGER IF EXISTS deduct_unpaid_absence ON timesheets;
CREATE TRIGGER deduct_unpaid_absence
  AFTER UPDATE ON timesheets
  FOR EACH ROW
  EXECUTE FUNCTION deduct_unpaid_absence_on_timesheet_approval();


-- ============================================================
-- RÉCAPITULATIF
-- ============================================================
-- Colonnes ajoutées :
--   timesheets : 14 nouvelles colonnes (arrival_time, departure_time, etc.)
--   employees : 3 nouvelles colonnes (weekly_hours, default_start_time, default_end_time)
--   leave_rules : 3 nouvelles colonnes (lateness_threshold, deduction_rate, grace_period)
--
-- Triggers créés :
--   D. calculate_lateness        BEFORE INSERT/UPDATE sur timesheets
--      → calcule late_minutes, early_leave_minutes, overtime_minutes, hours
--   E. deduct_lateness           AFTER UPDATE sur timesheets (status → approved)
--      → crée payroll_variable_elements 'lateness_deduction' si retard > seuil
--   F. deduct_unpaid_absence     AFTER UPDATE sur timesheets (status → approved)
--      → crée payroll_variable_elements 'unpaid_absence_deduction' si absence unpaid
--
-- Sécurité :
--   - Idempotent : vérifie l'existence avant d'insérer (source + source_id)
--   - Respecte late_justified : pas de déduction si justifié
--   - Respecte le seuil (threshold_minutes) et la grâce (grace_period)
--   - Respecte le taux de déduction (deduction_rate)
--   - N'agit que sur transition de statut (OLD.status IS DISTINCT FROM NEW.status)
-- ============================================================
