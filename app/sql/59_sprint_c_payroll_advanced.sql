-- Sprint C: Paie Avancée
-- Tables: meal_voucher_config, payroll_variable_elements, sepa_payment_orders, pay_slip_clarified

-- ============ meal_voucher_config ============
CREATE TABLE IF NOT EXISTS meal_voucher_config (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  voucher_value decimal(15,2) NOT NULL DEFAULT 3.50,
  employer_share decimal(5,2) DEFAULT 60,
  employee_share decimal(5,2) DEFAULT 40,
  eligible_days text[] DEFAULT '{1,2,3,4,5}',
  max_per_month int DEFAULT 20,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);
ALTER TABLE meal_voucher_config ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_meal_voucher_config') THEN
    DROP POLICY IF EXISTS "allow_all_meal_voucher_config" ON meal_voucher_config;
    CREATE POLICY "allow_all_meal_voucher_config" ON meal_voucher_config FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;

-- ============ payroll_variable_elements ============
CREATE TABLE IF NOT EXISTS payroll_variable_elements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  employee_id uuid NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  pay_run_id uuid,
  period text NOT NULL,
  element_type text NOT NULL,
  description text,
  quantity decimal(15,3),
  unit_price decimal(15,2),
  amount decimal(15,2) NOT NULL DEFAULT 0,
  source text,
  source_id uuid,
  integrated boolean DEFAULT false,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_variable_elements_employee ON payroll_variable_elements(employee_id);
CREATE INDEX IF NOT EXISTS idx_variable_elements_period ON payroll_variable_elements(period);
CREATE INDEX IF NOT EXISTS idx_variable_elements_payrun ON payroll_variable_elements(pay_run_id);
ALTER TABLE payroll_variable_elements ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_payroll_variable_elements') THEN
    DROP POLICY IF EXISTS "allow_all_payroll_variable_elements" ON payroll_variable_elements;
    CREATE POLICY "allow_all_payroll_variable_elements" ON payroll_variable_elements FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;

-- ============ sepa_payment_orders ============
CREATE TABLE IF NOT EXISTS sepa_payment_orders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  pay_run_id uuid,
  number text NOT NULL,
  execution_date date NOT NULL,
  total_amount decimal(15,2) NOT NULL DEFAULT 0,
  currency text DEFAULT 'EUR',
  employee_count int DEFAULT 0,
  file_url text,
  file_generated_at timestamptz,
  status text DEFAULT 'draft' CHECK (status IN ('draft', 'generated', 'transmitted', 'processed', 'rejected')),
  transmitted_at timestamptz,
  processed_at timestamptz,
  notes text,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_sepa_orders_payrun ON sepa_payment_orders(pay_run_id);
ALTER TABLE sepa_payment_orders ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_sepa_payment_orders') THEN
    DROP POLICY IF EXISTS "allow_all_sepa_payment_orders" ON sepa_payment_orders;
    CREATE POLICY "allow_all_sepa_payment_orders" ON sepa_payment_orders FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;

-- ============ pay_slip_clarified ============
CREATE TABLE IF NOT EXISTS pay_slip_clarified (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  pay_slip_id uuid NOT NULL REFERENCES pay_slips(id) ON DELETE CASCADE,
  employee_id uuid NOT NULL,
  period text NOT NULL,
  gross_salary decimal(15,2) DEFAULT 0,
  social_charges_employee decimal(15,2) DEFAULT 0,
  social_charges_employer decimal(15,2) DEFAULT 0,
  income_tax decimal(15,2) DEFAULT 0,
  net_before_tax decimal(15,2) DEFAULT 0,
  net_after_tax decimal(15,2) DEFAULT 0,
  total_deductions decimal(15,2) DEFAULT 0,
  lines jsonb DEFAULT '[]',
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_payslip_clarified_slip ON pay_slip_clarified(pay_slip_id);
ALTER TABLE pay_slip_clarified ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_pay_slip_clarified') THEN
    DROP POLICY IF EXISTS "allow_all_pay_slip_clarified" ON pay_slip_clarified;
    CREATE POLICY "allow_all_pay_slip_clarified" ON pay_slip_clarified FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;

-- ============ Seed: default meal voucher config ============
INSERT INTO meal_voucher_config (tenant_id, voucher_value, employer_share, employee_share, eligible_days, max_per_month, active)
SELECT NULL, 3.50, 60, 40, '{1,2,3,4,5}', 20, true
WHERE NOT EXISTS (SELECT 1 FROM meal_voucher_config WHERE active = true);
