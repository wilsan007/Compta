-- ============================================
-- PRE-DISTRIBUTION GRILLS (Pré-ventilation par grilles)
-- ============================================
-- Automatic analytic distribution grills
-- for accounts (e.g. 60% center A, 40% center B)
-- ============================================

CREATE TABLE IF NOT EXISTS distribution_grills (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  name text NOT NULL,
  description text,
  account_code text NOT NULL,
  journal_code text,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS distribution_grill_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  grill_id uuid REFERENCES distribution_grills(id) ON DELETE CASCADE,
  section_code text NOT NULL,
  percentage numeric(5,2) NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_distribution_grills_tenant ON distribution_grills(tenant_id);
CREATE INDEX IF NOT EXISTS idx_distribution_grills_account ON distribution_grills(account_code);
CREATE INDEX IF NOT EXISTS idx_distribution_grill_lines_grill ON distribution_grill_lines(grill_id);

ALTER TABLE distribution_grills ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_distribution_grills') THEN
    CREATE POLICY "allow_all_distribution_grills" ON distribution_grills FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

ALTER TABLE distribution_grill_lines ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_distribution_grill_lines') THEN
    CREATE POLICY "allow_all_distribution_grill_lines" ON distribution_grill_lines FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;
