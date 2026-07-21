-- ============================================
-- AUTOMATIC BANK RECONCILIATION (AFB codes)
-- ============================================
-- AFB100 codes for automatic matching
-- of bank transactions with entries
-- ============================================

CREATE TABLE IF NOT EXISTS bank_reconciliation_rules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  name text NOT NULL,
  afb_code text NOT NULL,
  description text,
  match_pattern text,
  counterpart_account text,
  journal_code text,
  priority int NOT NULL DEFAULT 100,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_bank_recon_rules_tenant ON bank_reconciliation_rules(tenant_id);
CREATE INDEX IF NOT EXISTS idx_bank_recon_rules_afb ON bank_reconciliation_rules(afb_code);
CREATE INDEX IF NOT EXISTS idx_bank_recon_rules_active ON bank_reconciliation_rules(active);

ALTER TABLE bank_reconciliation_rules ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_bank_recon_rules') THEN
    CREATE POLICY "allow_all_bank_recon_rules" ON bank_reconciliation_rules FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

ALTER TABLE bank_transactions
  ADD COLUMN IF NOT EXISTS afb_code text,
  ADD COLUMN IF NOT EXISTS reconciled boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS reconciled_entry_id uuid,
  ADD COLUMN IF NOT EXISTS reconciled_at timestamptz;
