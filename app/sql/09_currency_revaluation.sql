-- ============================================
-- CURRENCY REVALUATION (Réévaluation créances/dettes en devises)
-- ============================================
-- Revaluation entries for foreign currency
-- receivables and payables at period end
-- ============================================

CREATE TABLE IF NOT EXISTS currency_revaluations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  fiscal_year_id uuid,
  period_date date NOT NULL,
  account_code text NOT NULL,
  third_party_code text,
  currency text NOT NULL,
  original_rate numeric(12,6) NOT NULL DEFAULT 1,
  new_rate numeric(12,6) NOT NULL DEFAULT 1,
  original_amount numeric(14,2) NOT NULL DEFAULT 0,
  original_amount_eur numeric(14,2) NOT NULL DEFAULT 0,
  revalued_amount_eur numeric(14,2) NOT NULL DEFAULT 0,
  gain_loss numeric(14,2) NOT NULL DEFAULT 0,
  type text NOT NULL, -- receivable, payable
  status text NOT NULL DEFAULT 'pending', -- pending, posted
  entry_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_currency_reval_tenant ON currency_revaluations(tenant_id);
CREATE INDEX IF NOT EXISTS idx_currency_reval_status ON currency_revaluations(status);
CREATE INDEX IF NOT EXISTS idx_currency_reval_period ON currency_revaluations(period_date);

ALTER TABLE currency_revaluations ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_currency_revaluations') THEN
    CREATE POLICY "allow_all_currency_revaluations" ON currency_revaluations FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;
