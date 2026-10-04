-- Sprint F: Déclarations Sociales & Reporting
-- Tables: social_declarations, cice_config, pas_rates, at_rates, bdes_indicators, honorarium_records

-- ============ social_declarations ============
CREATE TABLE IF NOT EXISTS social_declarations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  number text NOT NULL,
  declaration_type text NOT NULL,
  subtype text,
  period_month int,
  period_year int,
  period text,
  due_date date,
  status text DEFAULT 'draft' CHECK (status IN ('draft', 'generated', 'transmitted', 'accepted', 'rejected', 'regularized')),
  file_url text,
  file_format text,
  generated_at timestamptz,
  transmitted_at timestamptz,
  response_code text,
  response_message text,
  anomalies jsonb DEFAULT '[]',
  amount decimal(15,2),
  employee_count int,
  details jsonb DEFAULT '{}',
  notes text,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_social_declarations_type ON social_declarations(declaration_type);
CREATE INDEX IF NOT EXISTS idx_social_declarations_period ON social_declarations(period);
CREATE INDEX IF NOT EXISTS idx_social_declarations_status ON social_declarations(status);
ALTER TABLE social_declarations ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_social_declarations') THEN
    DROP POLICY IF EXISTS "allow_all_social_declarations" ON social_declarations;
    CREATE POLICY "allow_all_social_declarations" ON social_declarations FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;

-- ============ cice_config ============
CREATE TABLE IF NOT EXISTS cice_config (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  year int NOT NULL,
  smic_threshold decimal(15,2) DEFAULT 2.5,
  rate decimal(5,2) DEFAULT 6,
  eligible_salary_cap decimal(15,2),
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);
ALTER TABLE cice_config ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_cice_config') THEN
    DROP POLICY IF EXISTS "allow_all_cice_config" ON cice_config;
    CREATE POLICY "allow_all_cice_config" ON cice_config FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;

-- ============ pas_rates ============
CREATE TABLE IF NOT EXISTS pas_rates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  employee_id uuid NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  rate decimal(5,4) NOT NULL DEFAULT 0,
  effective_date date NOT NULL,
  expiry_date date,
  source text DEFAULT 'import',
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_pas_rates_employee ON pas_rates(employee_id);
CREATE INDEX IF NOT EXISTS idx_pas_rates_dates ON pas_rates(effective_date, expiry_date);
ALTER TABLE pas_rates ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_pas_rates') THEN
    DROP POLICY IF EXISTS "allow_all_pas_rates" ON pas_rates;
    CREATE POLICY "allow_all_pas_rates" ON pas_rates FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;

-- ============ at_rates ============
CREATE TABLE IF NOT EXISTS at_rates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  employee_id uuid NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  rate decimal(5,4) NOT NULL DEFAULT 0,
  bonus_malus_rate decimal(5,4) DEFAULT 0,
  effective_date date NOT NULL,
  expiry_date date,
  risk_category text,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_at_rates_employee ON at_rates(employee_id);
ALTER TABLE at_rates ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_at_rates') THEN
    DROP POLICY IF EXISTS "allow_all_at_rates" ON at_rates;
    CREATE POLICY "allow_all_at_rates" ON at_rates FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;

-- ============ bdes_indicators ============
CREATE TABLE IF NOT EXISTS bdes_indicators (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  year int NOT NULL,
  category text NOT NULL,
  indicator_name text NOT NULL,
  indicator_value decimal(15,2),
  indicator_unit text,
  breakdown jsonb DEFAULT '{}',
  target_value decimal(15,2),
  previous_year_value decimal(15,2),
  notes text,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_bdes_year ON bdes_indicators(year);
CREATE INDEX IF NOT EXISTS idx_bdes_category ON bdes_indicators(category);
ALTER TABLE bdes_indicators ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_bdes_indicators') THEN
    DROP POLICY IF EXISTS "allow_all_bdes_indicators" ON bdes_indicators;
    CREATE POLICY "allow_all_bdes_indicators" ON bdes_indicators FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;

-- ============ honorarium_records ============
CREATE TABLE IF NOT EXISTS honorarium_records (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  employee_id uuid REFERENCES employees(id) ON DELETE SET NULL,
  recipient_name text NOT NULL,
  recipient_type text,
  period text,
  amount decimal(15,2) NOT NULL DEFAULT 0,
  description text,
  accounting_entry_id uuid,
  status text DEFAULT 'pending' CHECK (status IN ('pending', 'paid', 'accounted')),
  created_at timestamptz DEFAULT now()
);
ALTER TABLE honorarium_records ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_honorarium_records') THEN
    DROP POLICY IF EXISTS "allow_all_honorarium_records" ON honorarium_records;
    CREATE POLICY "allow_all_honorarium_records" ON honorarium_records FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
