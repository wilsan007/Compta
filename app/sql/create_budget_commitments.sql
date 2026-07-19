-- Budget Commitments Table
-- Run this in Supabase Dashboard > SQL Editor
-- Or via: psql $DATABASE_URL -f this file

CREATE TABLE IF NOT EXISTS budget_commitments (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  description text NOT NULL,
  account_code text NOT NULL,
  fiscal_year_id uuid REFERENCES fiscal_years(id) ON DELETE CASCADE,
  amount numeric(15,2) NOT NULL DEFAULT 0,
  commitment_date date NOT NULL DEFAULT current_date,
  source_type text DEFAULT 'manual' CHECK (source_type IN ('manual', 'purchase_order', 'purchase_invoice')),
  source_id uuid,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'consumed', 'cancelled')),
  supplier_id uuid REFERENCES suppliers(id) ON DELETE SET NULL,
  notes text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_budget_commitments_account ON budget_commitments(account_code);
CREATE INDEX IF NOT EXISTS idx_budget_commitments_fiscal_year ON budget_commitments(fiscal_year_id);
CREATE INDEX IF NOT EXISTS idx_budget_commitments_status ON budget_commitments(status);

ALTER TABLE budget_commitments ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_budget_commitments') THEN
    CREATE POLICY "allow_all_budget_commitments" ON budget_commitments FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;
