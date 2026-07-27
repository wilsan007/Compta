-- Sprint H: Pilotage RH, Dashboard & Reportings
-- Tables: rh_dashboard_configs, rh_reports, employee_activity_logs

-- ============ rh_dashboard_configs (Configuration des tableaux de bord) ============
CREATE TABLE IF NOT EXISTS rh_dashboard_configs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  user_email text NOT NULL,
  dashboard_type text NOT NULL,
  widgets jsonb DEFAULT '[]',
  filters jsonb DEFAULT '{}',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(user_email, dashboard_type)
);

CREATE INDEX IF NOT EXISTS idx_rh_dashboard_configs_user ON rh_dashboard_configs(user_email);
CREATE INDEX IF NOT EXISTS idx_rh_dashboard_configs_tenant ON rh_dashboard_configs(tenant_id);

ALTER TABLE rh_dashboard_configs ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_rh_dashboard_configs') THEN
    CREATE POLICY "allow_all_rh_dashboard_configs" ON rh_dashboard_configs FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;

-- ============ rh_reports (Reportings sauvegardés) ============
CREATE TABLE IF NOT EXISTS rh_reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  name text NOT NULL,
  report_type text NOT NULL,
  parameters jsonb DEFAULT '{}',
  chart_type text,
  data jsonb,
  data_calculated_at timestamptz,
  created_by text,
  shared boolean DEFAULT false,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_rh_reports_type ON rh_reports(report_type);
CREATE INDEX IF NOT EXISTS idx_rh_reports_tenant ON rh_reports(tenant_id);
CREATE INDEX IF NOT EXISTS idx_rh_reports_shared ON rh_reports(shared);

ALTER TABLE rh_reports ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_rh_reports') THEN
    CREATE POLICY "allow_all_rh_reports" ON rh_reports FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;

-- ============ employee_activity_logs (Timeline d'activité employé) ============
CREATE TABLE IF NOT EXISTS employee_activity_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  employee_id uuid NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  activity_type text NOT NULL,
  description text,
  metadata jsonb DEFAULT '{}',
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_activity_logs_employee ON employee_activity_logs(employee_id);
CREATE INDEX IF NOT EXISTS idx_activity_logs_date ON employee_activity_logs(created_at);
CREATE INDEX IF NOT EXISTS idx_activity_logs_tenant ON employee_activity_logs(tenant_id);
CREATE INDEX IF NOT EXISTS idx_activity_logs_type ON employee_activity_logs(activity_type);

ALTER TABLE employee_activity_logs ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_employee_activity_logs') THEN
    CREATE POLICY "allow_all_employee_activity_logs" ON employee_activity_logs FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;

-- ============ Extend employees table with self-service fields ============
ALTER TABLE employees ADD COLUMN IF NOT EXISTS emergency_contact_name text;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS emergency_contact_phone text;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS emergency_contact_relation text;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS photo_url text;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS bank_iban text;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS bank_bic text;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS bank_account_holder text;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS transport_mode text;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS transport_cost decimal(10,2) DEFAULT 0;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS meal_voucher_count int DEFAULT 0;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS meal_voucher_value decimal(10,2) DEFAULT 0;
