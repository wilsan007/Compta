-- Sprint D: Gestion Administrative, Arrêts de Travail & Suivi RH
-- Tables: work_stoppages, ijss_history, work_hardship_records, cpf_transactions,
--         career_history (extend), medical_exams, expense_categories, expense_report_lines (extend),
--         interview_campaigns, employee_objectives

-- ============ work_stoppages (Arrêts de travail) ============
CREATE TABLE IF NOT EXISTS work_stoppages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  employee_id uuid NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  stoppage_type text NOT NULL,
  start_date date NOT NULL,
  end_date date,
  expected_end_date date,
  reprise_date date,
  reprise_type text,
  days_count decimal(5,2),
  working_days_count decimal(5,2),
  subrogation boolean DEFAULT false,
  net_guarantee boolean DEFAULT false,
  ijss_net_amount decimal(15,2) DEFAULT 0,
  ijss_brut_amount decimal(15,2) DEFAULT 0,
  ijss_daily_rate decimal(15,2) DEFAULT 0,
  ijss_days_count int DEFAULT 0,
  ijss_care_days int DEFAULT 0,
  pas_days_count int DEFAULT 0,
  employer_maintenance_amount decimal(15,2) DEFAULT 0,
  employer_maintenance_rate decimal(5,2) DEFAULT 100,
  bpij_number text,
  bpij_imported_at timestamptz,
  regularization_amount decimal(15,2) DEFAULT 0,
  regularization_type text,
  medical_certificate_url text,
  notes text,
  status text DEFAULT 'active' CHECK (status IN ('active', 'closed', 'regularized')),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_work_stoppages_employee ON work_stoppages(employee_id);
CREATE INDEX IF NOT EXISTS idx_work_stoppages_dates ON work_stoppages(start_date, end_date);
CREATE INDEX IF NOT EXISTS idx_work_stoppages_type ON work_stoppages(stoppage_type);
ALTER TABLE work_stoppages ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_work_stoppages') THEN
    DROP POLICY IF EXISTS "allow_all_work_stoppages" ON work_stoppages;
    CREATE POLICY "allow_all_work_stoppages" ON work_stoppages FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;

-- ============ ijss_history (Historique des IJSS par arrêt) ============
CREATE TABLE IF NOT EXISTS ijss_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  work_stoppage_id uuid NOT NULL REFERENCES work_stoppages(id) ON DELETE CASCADE,
  employee_id uuid NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  period text NOT NULL,
  ijss_net_received decimal(15,2) DEFAULT 0,
  ijss_brut_calculated decimal(15,2) DEFAULT 0,
  days_paid int DEFAULT 0,
  pas_amount decimal(15,2) DEFAULT 0,
  pas_rate decimal(5,2) DEFAULT 0,
  integrated_in_payslip boolean DEFAULT false,
  payslip_id uuid,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_ijss_history_stoppage ON ijss_history(work_stoppage_id);
CREATE INDEX IF NOT EXISTS idx_ijss_history_employee ON ijss_history(employee_id);
ALTER TABLE ijss_history ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_ijss_history') THEN
    DROP POLICY IF EXISTS "allow_all_ijss_history" ON ijss_history;
    CREATE POLICY "allow_all_ijss_history" ON ijss_history FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;

-- ============ work_hardship_records (Pénibilité — C3P) ============
CREATE TABLE IF NOT EXISTS work_hardship_records (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  employee_id uuid NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  exposure_type text NOT NULL,
  exposure_level text NOT NULL,
  exposure_start date,
  exposure_end date,
  duration_months int,
  points decimal(5,2) DEFAULT 0,
  declaration_status text DEFAULT 'pending' CHECK (declaration_status IN ('pending', 'declared', 'rejected')),
  declared_at timestamptz,
  notes text,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_hardship_employee ON work_hardship_records(employee_id);
CREATE INDEX IF NOT EXISTS idx_hardship_type ON work_hardship_records(exposure_type);
ALTER TABLE work_hardship_records ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_work_hardship_records') THEN
    DROP POLICY IF EXISTS "allow_all_work_hardship_records" ON work_hardship_records;
    CREATE POLICY "allow_all_work_hardship_records" ON work_hardship_records FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;

-- ============ cpf_transactions (Historique des utilisations CPF) ============
CREATE TABLE IF NOT EXISTS cpf_transactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  employee_id uuid NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  transaction_type text NOT NULL,
  hours decimal(8,2) DEFAULT 0,
  amount decimal(15,2) DEFAULT 0,
  training_label text,
  training_start_date date,
  training_end_date date,
  training_provider text,
  notes text,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_cpf_transactions_employee ON cpf_transactions(employee_id);
ALTER TABLE cpf_transactions ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_cpf_transactions') THEN
    DROP POLICY IF EXISTS "allow_all_cpf_transactions" ON cpf_transactions;
    CREATE POLICY "allow_all_cpf_transactions" ON cpf_transactions FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;

-- ============ medical_exams (Suivi médecine du travail) ============
CREATE TABLE IF NOT EXISTS medical_exams (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  employee_id uuid NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  exam_type text NOT NULL,
  scheduled_date date NOT NULL,
  completed_date date,
  result text,
  restrictions text,
  next_exam_date date,
  occupational_doctor text,
  notes text,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_medical_exams_employee ON medical_exams(employee_id);
CREATE INDEX IF NOT EXISTS idx_medical_exams_date ON medical_exams(scheduled_date);
ALTER TABLE medical_exams ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_medical_exams') THEN
    DROP POLICY IF EXISTS "allow_all_medical_exams" ON medical_exams;
    CREATE POLICY "allow_all_medical_exams" ON medical_exams FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;

-- ============ expense_categories (Catégories de dépenses) ============
CREATE TABLE IF NOT EXISTS expense_categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  code text NOT NULL,
  label text NOT NULL,
  account_code text,
  vat_rate decimal(5,2) DEFAULT 20,
  max_amount decimal(15,2),
  max_monthly decimal(15,2),
  requires_receipt boolean DEFAULT true,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);
ALTER TABLE expense_categories ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_expense_categories') THEN
    DROP POLICY IF EXISTS "allow_all_expense_categories" ON expense_categories;
    CREATE POLICY "allow_all_expense_categories" ON expense_categories FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;

-- ============ interview_campaigns (Campagnes d'entretiens) ============
CREATE TABLE IF NOT EXISTS interview_campaigns (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  name text NOT NULL,
  campaign_type text NOT NULL,
  start_date date NOT NULL,
  end_date date,
  reminder_days int DEFAULT 7,
  status text DEFAULT 'draft' CHECK (status IN ('draft', 'active', 'closed')),
  form_template jsonb,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_interview_campaigns_status ON interview_campaigns(status);
ALTER TABLE interview_campaigns ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_interview_campaigns') THEN
    DROP POLICY IF EXISTS "allow_all_interview_campaigns" ON interview_campaigns;
    CREATE POLICY "allow_all_interview_campaigns" ON interview_campaigns FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;

-- ============ employee_objectives (Objectifs individuels) ============
CREATE TABLE IF NOT EXISTS employee_objectives (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  employee_id uuid NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  campaign_id uuid REFERENCES interview_campaigns(id) ON DELETE SET NULL,
  title text NOT NULL,
  description text,
  target_value decimal(15,2),
  current_value decimal(15,2) DEFAULT 0,
  unit text,
  period text,
  frequency text DEFAULT 'annual',
  status text DEFAULT 'active' CHECK (status IN ('active', 'achieved', 'missed', 'cancelled')),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_objectives_employee ON employee_objectives(employee_id);
CREATE INDEX IF NOT EXISTS idx_objectives_campaign ON employee_objectives(campaign_id);
ALTER TABLE employee_objectives ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_employee_objectives') THEN
    DROP POLICY IF EXISTS "allow_all_employee_objectives" ON employee_objectives;
    CREATE POLICY "allow_all_employee_objectives" ON employee_objectives FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;

-- ============ Extensions de tables existantes ============

-- Étendre cpf_accounts
ALTER TABLE cpf_accounts ADD COLUMN IF NOT EXISTS last_sync_date timestamptz;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'cpf_accounts_employee_unique') THEN
    ALTER TABLE cpf_accounts ADD CONSTRAINT cpf_accounts_employee_unique UNIQUE(employee_id);
  END IF;
END $$;

-- Étendre career_history avec nouveaux champs
ALTER TABLE career_history ADD COLUMN IF NOT EXISTS event_type text;
ALTER TABLE career_history ADD COLUMN IF NOT EXISTS event_date date;
ALTER TABLE career_history ADD COLUMN IF NOT EXISTS previous_position text;
ALTER TABLE career_history ADD COLUMN IF NOT EXISTS new_position text;
ALTER TABLE career_history ADD COLUMN IF NOT EXISTS previous_department text;
ALTER TABLE career_history ADD COLUMN IF NOT EXISTS new_department text;
ALTER TABLE career_history ADD COLUMN IF NOT EXISTS previous_salary decimal(15,2);
ALTER TABLE career_history ADD COLUMN IF NOT EXISTS new_salary decimal(15,2);
ALTER TABLE career_history ADD COLUMN IF NOT EXISTS previous_manager_id uuid;
ALTER TABLE career_history ADD COLUMN IF NOT EXISTS new_manager_id uuid;
ALTER TABLE career_history ADD COLUMN IF NOT EXISTS previous_collective_agreement_id uuid;
ALTER TABLE career_history ADD COLUMN IF NOT EXISTS new_collective_agreement_id uuid;
ALTER TABLE career_history ADD COLUMN IF NOT EXISTS reason text;
ALTER TABLE career_history ADD COLUMN IF NOT EXISTS documents jsonb DEFAULT '[]';

-- Étendre expense_report_lines avec nouveaux champs
ALTER TABLE expense_report_lines ADD COLUMN IF NOT EXISTS tenant_id uuid;
ALTER TABLE expense_report_lines ADD COLUMN IF NOT EXISTS category_id uuid REFERENCES expense_categories(id) ON DELETE SET NULL;
ALTER TABLE expense_report_lines ADD COLUMN IF NOT EXISTS amount_ht decimal(15,2) DEFAULT 0;
ALTER TABLE expense_report_lines ADD COLUMN IF NOT EXISTS amount_ttc decimal(15,2) DEFAULT 0;
ALTER TABLE expense_report_lines ADD COLUMN IF NOT EXISTS ocr_data jsonb;
ALTER TABLE expense_report_lines ADD COLUMN IF NOT EXISTS ocr_processed boolean DEFAULT false;
ALTER TABLE expense_report_lines ADD COLUMN IF NOT EXISTS ceiling_exceeded boolean DEFAULT false;

-- Étendre expense_reports avec manager_id et reimbursement_date
ALTER TABLE expense_reports ADD COLUMN IF NOT EXISTS manager_id uuid;
ALTER TABLE expense_reports ADD COLUMN IF NOT EXISTS manager_comment text;
ALTER TABLE expense_reports ADD COLUMN IF NOT EXISTS reimbursement_date date;

-- Étendre interviews avec campaign_id et form_data
ALTER TABLE interviews ADD COLUMN IF NOT EXISTS campaign_id uuid REFERENCES interview_campaigns(id) ON DELETE SET NULL;
ALTER TABLE interviews ADD COLUMN IF NOT EXISTS form_data jsonb;
ALTER TABLE interviews ADD COLUMN IF NOT EXISTS employee_feedback text;
ALTER TABLE interviews ADD COLUMN IF NOT EXISTS employee_rating int;
