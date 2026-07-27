-- Sprint B: Congés, Absences & Gestion des Temps
-- Tables: leave_balances, public_holidays, leave_rules, approval_workflows, leave_provisions, staff_requirements

-- ============ leave_balances ============
CREATE TABLE IF NOT EXISTS leave_balances (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  employee_id uuid NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  leave_type text NOT NULL,
  year int NOT NULL DEFAULT extract(year from current_date)::int,
  acquired decimal(5,2) DEFAULT 0,
  taken decimal(5,2) DEFAULT 0,
  pending decimal(5,2) DEFAULT 0,
  remaining decimal(5,2) DEFAULT 0,
  carry_over decimal(5,2) DEFAULT 0,
  provision decimal(15,2) DEFAULT 0,
  provision_calculated_at timestamptz,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(employee_id, leave_type, year)
);
CREATE INDEX IF NOT EXISTS idx_leave_balances_employee ON leave_balances(employee_id);
CREATE INDEX IF NOT EXISTS idx_leave_balances_year ON leave_balances(year);
ALTER TABLE leave_balances ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_leave_balances') THEN
    CREATE POLICY "allow_all_leave_balances" ON leave_balances FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;

-- ============ public_holidays ============
CREATE TABLE IF NOT EXISTS public_holidays (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  name text NOT NULL,
  holiday_date date NOT NULL,
  region text DEFAULT 'national',
  country text DEFAULT 'FR',
  is_working_day boolean DEFAULT false,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_public_holidays_date ON public_holidays(holiday_date);
CREATE INDEX IF NOT EXISTS idx_public_holidays_region ON public_holidays(region);
ALTER TABLE public_holidays ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_public_holidays') THEN
    CREATE POLICY "allow_all_public_holidays" ON public_holidays FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;

-- ============ leave_rules ============
CREATE TABLE IF NOT EXISTS leave_rules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  leave_type text NOT NULL,
  label text NOT NULL,
  accrual_rate decimal(5,2) DEFAULT 2.08,
  max_carry_over decimal(5,2) DEFAULT 0,
  carry_over_expiry_months int DEFAULT 3,
  requires_justification boolean DEFAULT false,
  requires_manager_approval boolean DEFAULT true,
  min_notice_days int DEFAULT 7,
  max_consecutive_days int DEFAULT 30,
  color text DEFAULT '#3b82f6',
  count_method text DEFAULT 'working_days',
  affects_pay boolean DEFAULT false,
  deduction_rate decimal(5,2) DEFAULT 100,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);
ALTER TABLE leave_rules ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_leave_rules') THEN
    CREATE POLICY "allow_all_leave_rules" ON leave_rules FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;

-- ============ approval_workflows ============
CREATE TABLE IF NOT EXISTS approval_workflows (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  name text NOT NULL,
  entity_type text NOT NULL,
  steps jsonb DEFAULT '[]',
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);
ALTER TABLE approval_workflows ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_approval_workflows') THEN
    CREATE POLICY "allow_all_approval_workflows" ON approval_workflows FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;

-- ============ leave_provisions ============
CREATE TABLE IF NOT EXISTS leave_provisions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  employee_id uuid NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  period text NOT NULL,
  cp_remaining_days decimal(5,2) DEFAULT 0,
  rtt_remaining_days decimal(5,2) DEFAULT 0,
  recovery_remaining_days decimal(5,2) DEFAULT 0,
  daily_rate decimal(15,2) DEFAULT 0,
  cp_provision decimal(15,2) DEFAULT 0,
  rtt_provision decimal(15,2) DEFAULT 0,
  recovery_provision decimal(15,2) DEFAULT 0,
  total_provision decimal(15,2) DEFAULT 0,
  accounting_entry_id uuid,
  status text DEFAULT 'draft' CHECK (status IN ('draft', 'calculated', 'posted')),
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_leave_provisions_employee ON leave_provisions(employee_id);
CREATE INDEX IF NOT EXISTS idx_leave_provisions_period ON leave_provisions(period);
ALTER TABLE leave_provisions ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_leave_provisions') THEN
    CREATE POLICY "allow_all_leave_provisions" ON leave_provisions FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;

-- ============ staff_requirements ============
CREATE TABLE IF NOT EXISTS staff_requirements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  department text NOT NULL,
  min_staff int NOT NULL DEFAULT 1,
  days_of_week text[] DEFAULT '{1,2,3,4,5}',
  start_date date,
  end_date date,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);
ALTER TABLE staff_requirements ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_staff_requirements') THEN
    CREATE POLICY "allow_all_staff_requirements" ON staff_requirements FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;

-- ============ Seed: default leave rules ============
INSERT INTO leave_rules (tenant_id, leave_type, label, accrual_rate, max_carry_over, requires_justification, requires_manager_approval, min_notice_days, max_consecutive_days, color, count_method)
SELECT NULL, 'annual', 'Congés payés', 2.08, 0, false, true, 7, 30, '#3b82f6', 'working_days'
WHERE NOT EXISTS (SELECT 1 FROM leave_rules WHERE leave_type = 'annual');

INSERT INTO leave_rules (tenant_id, leave_type, label, accrual_rate, max_carry_over, requires_justification, requires_manager_approval, min_notice_days, max_consecutive_days, color, count_method)
SELECT NULL, 'rtt', 'RTT', 0.83, 0, false, true, 3, 10, '#10b981', 'working_days'
WHERE NOT EXISTS (SELECT 1 FROM leave_rules WHERE leave_type = 'rtt');

INSERT INTO leave_rules (tenant_id, leave_type, label, accrual_rate, max_carry_over, requires_justification, requires_manager_approval, min_notice_days, max_consecutive_days, color, count_method)
SELECT NULL, 'sick', 'Maladie', 0, 0, true, false, 0, 365, '#ef4444', 'calendar_days'
WHERE NOT EXISTS (SELECT 1 FROM leave_rules WHERE leave_type = 'sick');

INSERT INTO leave_rules (tenant_id, leave_type, label, accrual_rate, max_carry_over, requires_justification, requires_manager_approval, min_notice_days, max_consecutive_days, color, count_method)
SELECT NULL, 'unpaid', 'Congé sans solde', 0, 0, true, true, 7, 90, '#f59e0b', 'calendar_days'
WHERE NOT EXISTS (SELECT 1 FROM leave_rules WHERE leave_type = 'unpaid');

-- ============ Seed: French public holidays 2024 ============
INSERT INTO public_holidays (tenant_id, name, holiday_date, region, country, is_working_day)
SELECT NULL, 'Jour de l''An', '2024-01-01', 'national', 'FR', false
WHERE NOT EXISTS (SELECT 1 FROM public_holidays WHERE holiday_date = '2024-01-01');
INSERT INTO public_holidays (tenant_id, name, holiday_date, region, country, is_working_day)
SELECT NULL, 'Lundi de Pâques', '2024-04-01', 'national', 'FR', false
WHERE NOT EXISTS (SELECT 1 FROM public_holidays WHERE holiday_date = '2024-04-01');
INSERT INTO public_holidays (tenant_id, name, holiday_date, region, country, is_working_day)
SELECT NULL, 'Fête du Travail', '2024-05-01', 'national', 'FR', false
WHERE NOT EXISTS (SELECT 1 FROM public_holidays WHERE holiday_date = '2024-05-01');
INSERT INTO public_holidays (tenant_id, name, holiday_date, region, country, is_working_day)
SELECT NULL, 'Victoire 1945', '2024-05-08', 'national', 'FR', false
WHERE NOT EXISTS (SELECT 1 FROM public_holidays WHERE holiday_date = '2024-05-08');
INSERT INTO public_holidays (tenant_id, name, holiday_date, region, country, is_working_day)
SELECT NULL, 'Ascension', '2024-05-09', 'national', 'FR', false
WHERE NOT EXISTS (SELECT 1 FROM public_holidays WHERE holiday_date = '2024-05-09');
INSERT INTO public_holidays (tenant_id, name, holiday_date, region, country, is_working_day)
SELECT NULL, 'Lundi de Pentecôte', '2024-05-20', 'national', 'FR', false
WHERE NOT EXISTS (SELECT 1 FROM public_holidays WHERE holiday_date = '2024-05-20');
INSERT INTO public_holidays (tenant_id, name, holiday_date, region, country, is_working_day)
SELECT NULL, 'Fête Nationale', '2024-07-14', 'national', 'FR', false
WHERE NOT EXISTS (SELECT 1 FROM public_holidays WHERE holiday_date = '2024-07-14');
INSERT INTO public_holidays (tenant_id, name, holiday_date, region, country, is_working_day)
SELECT NULL, 'Assomption', '2024-08-15', 'national', 'FR', false
WHERE NOT EXISTS (SELECT 1 FROM public_holidays WHERE holiday_date = '2024-08-15');
INSERT INTO public_holidays (tenant_id, name, holiday_date, region, country, is_working_day)
SELECT NULL, 'Toussaint', '2024-11-01', 'national', 'FR', false
WHERE NOT EXISTS (SELECT 1 FROM public_holidays WHERE holiday_date = '2024-11-01');
INSERT INTO public_holidays (tenant_id, name, holiday_date, region, country, is_working_day)
SELECT NULL, 'Armistice 1918', '2024-11-11', 'national', 'FR', false
WHERE NOT EXISTS (SELECT 1 FROM public_holidays WHERE holiday_date = '2024-11-11');
INSERT INTO public_holidays (tenant_id, name, holiday_date, region, country, is_working_day)
SELECT NULL, 'Noël', '2024-12-25', 'national', 'FR', false
WHERE NOT EXISTS (SELECT 1 FROM public_holidays WHERE holiday_date = '2024-12-25');
