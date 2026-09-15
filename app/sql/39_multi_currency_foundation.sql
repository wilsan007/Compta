-- ============================================================
-- Sprint 1: Multi-Devises Foundation + Account Types
-- Elements: #1 (Types comptes), #88 (Taux change auto), #57 (Devise journaux)
-- ============================================================

-- Fix pre-existing bug: TG_TABLENAME → TG_TABLE_NAME (correct PostgreSQL variable)
-- This must match the definition in 37_security_fix_all_allow_all_policies.sql
CREATE OR REPLACE FUNCTION set_tenant_id()
RETURNS trigger AS $$
BEGIN
  IF NEW.tenant_id IS NULL AND TG_TABLE_NAME != 'tenants' THEN
    NEW.tenant_id := current_tenant_id();
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- #88: Exchange Rates Table
-- ============================================================
CREATE TABLE IF NOT EXISTS exchange_rates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  base_currency text NOT NULL,
  quote_currency text NOT NULL,
  rate numeric(12,6) NOT NULL,
  rate_date date NOT NULL,
  source text DEFAULT 'manual',
  created_at timestamptz DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_exchange_rates_unique
  ON exchange_rates(tenant_id, base_currency, quote_currency, rate_date);

CREATE INDEX IF NOT EXISTS idx_exchange_rates_latest
  ON exchange_rates(tenant_id, base_currency, quote_currency, rate_date DESC);

-- RLS
ALTER TABLE exchange_rates ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  DROP POLICY IF EXISTS exchange_rates_select ON exchange_rates;
  CREATE POLICY exchange_rates_select ON exchange_rates FOR SELECT USING (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  DROP POLICY IF EXISTS exchange_rates_all ON exchange_rates;
  CREATE POLICY exchange_rates_all ON exchange_rates FOR ALL USING (true) WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ============================================================
-- #57: Currency on Journals
-- ============================================================
ALTER TABLE journals ADD COLUMN IF NOT EXISTS currency_code text DEFAULT 'EUR';
ALTER TABLE journals ADD COLUMN IF NOT EXISTS sequence integer DEFAULT 0;

-- ============================================================
-- #79 (partial): Currency + Reconcile + Deprecated on Chart Accounts
-- ============================================================
ALTER TABLE chart_accounts ADD COLUMN IF NOT EXISTS currency_code text;
ALTER TABLE chart_accounts ADD COLUMN IF NOT EXISTS reconcile boolean DEFAULT false;
ALTER TABLE chart_accounts ADD COLUMN IF NOT EXISTS deprecated boolean DEFAULT false;

-- ============================================================
-- #1: Precise Account Types (19 values)
-- ============================================================
ALTER TABLE chart_accounts ADD COLUMN IF NOT EXISTS account_type text;

-- Migration: map existing 'type' values to new 'account_type'
UPDATE chart_accounts SET account_type = CASE
  WHEN type = 'asset' AND code LIKE '41%' THEN 'asset_receivable'
  WHEN type = 'asset' AND code LIKE '51%' THEN 'asset_cash'
  WHEN type = 'asset' AND code LIKE '53%' THEN 'asset_cash'
  WHEN type = 'asset' AND code LIKE '2%' THEN 'asset_fixed'
  WHEN type = 'asset' AND code LIKE '48%' THEN 'asset_prepayments'
  WHEN type = 'asset' THEN 'asset_current'
  WHEN type = 'liability' AND code LIKE '40%' THEN 'liability_payable'
  WHEN type = 'liability' AND code LIKE '1%' THEN 'liability_non_current'
  WHEN type = 'liability' THEN 'liability_current'
  WHEN type = 'equity' AND code LIKE '12%' THEN 'equity_unaffected'
  WHEN type = 'equity' THEN 'equity'
  WHEN type = 'income' AND code LIKE '7%' AND code NOT LIKE '70%' AND code NOT LIKE '74%' THEN 'income_other'
  WHEN type = 'income' THEN 'income'
  WHEN type = 'expense' AND code LIKE '68%' THEN 'expense_depreciation'
  WHEN type = 'expense' AND code LIKE '60%' OR code LIKE '61%' OR code LIKE '62%' THEN 'expense_direct_cost'
  WHEN type = 'expense' AND code LIKE '78%' OR code LIKE '681%' THEN 'expense_other'
  WHEN type = 'expense' THEN 'expense'
  ELSE 'asset_current'
END;

-- Set default for future inserts
ALTER TABLE chart_accounts ALTER COLUMN account_type SET DEFAULT 'asset_current';

-- ============================================================
-- #88: Enhance currencies table with last_rate_date
-- ============================================================
ALTER TABLE currencies ADD COLUMN IF NOT EXISTS last_rate_date date;
ALTER TABLE currencies ADD COLUMN IF NOT EXISTS decimal_places integer DEFAULT 2;
ALTER TABLE currencies ADD COLUMN IF NOT EXISTS rounding numeric(14,2) DEFAULT 0.01;
ALTER TABLE currencies ADD COLUMN IF NOT EXISTS active boolean DEFAULT true;
ALTER TABLE currencies ADD COLUMN IF NOT EXISTS position text DEFAULT 'after';

-- Currencies are global reference data (EUR, USD, MAD, etc.) shared across tenants.
-- Make tenant_id nullable so seed data doesn't require a tenant.
ALTER TABLE currencies ALTER COLUMN tenant_id DROP NOT NULL;

-- Remove duplicate currency entries (keep the oldest by created_at)
DELETE FROM currencies a USING currencies b
WHERE a.code = b.code AND a.created_at > b.created_at;

-- Ensure currency codes are unique globally (prevents duplicate key warnings in UI)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'currencies_code_unique') THEN
    ALTER TABLE currencies ADD CONSTRAINT currencies_code_unique UNIQUE (code);
  END IF;
END $$;

-- ============================================================
-- #88: Seed common currencies if not present (tenant_id = NULL = global)
-- ============================================================
DO $$
BEGIN
  -- Try each insert, ignore errors (e.g. tenant_id NOT NULL still enforced by older migration)
  BEGIN
    INSERT INTO currencies (code, name, symbol, exchange_rate, is_base, decimal_places, position, active, tenant_id)
    SELECT 'EUR', 'Euro', '€', 1.0, true, 2, 'after', true, NULL
    WHERE NOT EXISTS (SELECT 1 FROM currencies WHERE code = 'EUR');
  EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN
    INSERT INTO currencies (code, name, symbol, exchange_rate, is_base, decimal_places, position, active, tenant_id)
    SELECT 'USD', 'Dollar US', '$', 1.085, false, 2, 'before', true, NULL
    WHERE NOT EXISTS (SELECT 1 FROM currencies WHERE code = 'USD');
  EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN
    INSERT INTO currencies (code, name, symbol, exchange_rate, is_base, decimal_places, position, active, tenant_id)
    SELECT 'GBP', 'Livre Sterling', '£', 0.855, false, 2, 'before', true, NULL
    WHERE NOT EXISTS (SELECT 1 FROM currencies WHERE code = 'GBP');
  EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN
    INSERT INTO currencies (code, name, symbol, exchange_rate, is_base, decimal_places, position, active, tenant_id)
    SELECT 'MAD', 'Dirham Marocain', 'DH', 10.95, false, 2, 'after', true, NULL
    WHERE NOT EXISTS (SELECT 1 FROM currencies WHERE code = 'MAD');
  EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN
    INSERT INTO currencies (code, name, symbol, exchange_rate, is_base, decimal_places, position, active, tenant_id)
    SELECT 'XOF', 'Franc CFA', 'FCFA', 655.957, false, 0, 'after', true, NULL
    WHERE NOT EXISTS (SELECT 1 FROM currencies WHERE code = 'XOF');
  EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN
    INSERT INTO currencies (code, name, symbol, exchange_rate, is_base, decimal_places, position, active, tenant_id)
    SELECT 'CHF', 'Franc Suisse', 'CHF', 0.965, false, 2, 'after', true, NULL
    WHERE NOT EXISTS (SELECT 1 FROM currencies WHERE code = 'CHF');
  EXCEPTION WHEN OTHERS THEN NULL; END;
END $$;
