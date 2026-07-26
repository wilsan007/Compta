-- ============================================================
-- Sprint 7: Banque — Sync API + Soldes Relevé + Multi-Devises + Banque Tiers
-- Elements: #69 (Sync API), #70 (Soldes Relevé), #72 (Multi-Devises), #80 (Banque Tiers)
-- ============================================================

-- ============================================================
-- #69: Bank Connections (API sync)
-- ============================================================
CREATE TABLE IF NOT EXISTS bank_connections (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  provider text NOT NULL,
  provider_connection_id text,
  bank_account_id uuid REFERENCES bank_accounts(id),
  status text DEFAULT 'pending',
  last_sync_at timestamptz,
  sync_frequency text DEFAULT 'daily',
  next_sync_at timestamptz,
  error_message text,
  metadata jsonb,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_bank_connections_tenant ON bank_connections(tenant_id);
CREATE INDEX IF NOT EXISTS idx_bank_connections_status ON bank_connections(status);

ALTER TABLE bank_connections ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_bank_connections') THEN
    CREATE POLICY "allow_all_bank_connections" ON bank_connections FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- ============================================================
-- #70: Statement Balances on bank_accounts
-- ============================================================
ALTER TABLE bank_accounts ADD COLUMN IF NOT EXISTS statement_balance numeric(14,2) DEFAULT 0;
ALTER TABLE bank_accounts ADD COLUMN IF NOT EXISTS statement_balance_date date;
ALTER TABLE bank_accounts ADD COLUMN IF NOT EXISTS calculated_balance numeric(14,2) DEFAULT 0;
ALTER TABLE bank_accounts ADD COLUMN IF NOT EXISTS reconciliation_diff numeric(14,2) DEFAULT 0;

-- ============================================================
-- #72: Multi-Currency Reconciliation — add exchange rate fields to bank_transactions
-- ============================================================
ALTER TABLE bank_transactions ADD COLUMN IF NOT EXISTS original_currency text;
ALTER TABLE bank_transactions ADD COLUMN IF NOT EXISTS original_amount numeric(14,2);
ALTER TABLE bank_transactions ADD COLUMN IF NOT EXISTS exchange_rate numeric(10,6) DEFAULT 1.0;
ALTER TABLE bank_transactions ADD COLUMN IF NOT EXISTS exchange_gain_loss numeric(14,2) DEFAULT 0;
ALTER TABLE bank_transactions ADD COLUMN IF NOT EXISTS source text DEFAULT 'manual';

-- ============================================================
-- #80: Partner Bank Accounts (res.partner.bank)
-- ============================================================
CREATE TABLE IF NOT EXISTS partner_bank_accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  partner_type text NOT NULL,
  partner_id uuid NOT NULL,
  account_number text NOT NULL,
  bank_name text,
  bic text,
  bank_code text,
  sort_code text,
  account_key text,
  currency_code text DEFAULT 'EUR',
  is_default boolean DEFAULT false,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_partner_bank_accounts_tenant ON partner_bank_accounts(tenant_id);
CREATE INDEX IF NOT EXISTS idx_partner_bank_accounts_partner ON partner_bank_accounts(partner_id);

ALTER TABLE partner_bank_accounts ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_partner_bank_accounts') THEN
    CREATE POLICY "allow_all_partner_bank_accounts" ON partner_bank_accounts FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;
