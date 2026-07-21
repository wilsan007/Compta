-- ============================================
-- MULTI ANALYTIC PLANS
-- ============================================
-- Multiple analytic plans for different
-- dimensions (cost center, project, etc.)
-- ============================================

CREATE TABLE IF NOT EXISTS analytic_plans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  code text NOT NULL,
  name text NOT NULL,
  description text,
  is_default boolean NOT NULL DEFAULT false,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_analytic_plans_tenant ON analytic_plans(tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_analytic_plans_code ON analytic_plans(tenant_id, code);

ALTER TABLE analytic_sections
  ADD COLUMN IF NOT EXISTS plan_id uuid REFERENCES analytic_plans(id) ON DELETE SET NULL;

ALTER TABLE analytic_plans ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_analytic_plans') THEN
    CREATE POLICY "allow_all_analytic_plans" ON analytic_plans FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;
