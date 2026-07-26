-- ============================================================
-- Sprint 2: Multi-Devises sur Écritures + Comptes + Paiements
-- Elements: #33 (Devise écritures), #79 (Devise comptes - déjà en Sprint 1), #85 (Devise paiements)
-- ============================================================

-- ============================================================
-- #33: Currency on Journal Entries
-- ============================================================
ALTER TABLE journal_entries ADD COLUMN IF NOT EXISTS currency_code text DEFAULT 'EUR';
ALTER TABLE journal_entries ADD COLUMN IF NOT EXISTS functional_currency text DEFAULT 'EUR';
ALTER TABLE journal_entries ADD COLUMN IF NOT EXISTS exchange_rate numeric(12,6) DEFAULT 1.0;
ALTER TABLE journal_entries ADD COLUMN IF NOT EXISTS exchange_rate_date date;

-- ============================================================
-- #85: Currency on Customer Payments
-- ============================================================
ALTER TABLE customer_payments ADD COLUMN IF NOT EXISTS currency_code text DEFAULT 'EUR';
ALTER TABLE customer_payments ADD COLUMN IF NOT EXISTS exchange_rate numeric(12,6) DEFAULT 1.0;
ALTER TABLE customer_payments ADD COLUMN IF NOT EXISTS amount_currency numeric(14,2);
ALTER TABLE customer_payments ADD COLUMN IF NOT EXISTS exchange_gain_loss numeric(14,2) DEFAULT 0;

-- ============================================================
-- #85: Currency on Supplier Payments
-- ============================================================
ALTER TABLE supplier_payments ADD COLUMN IF NOT EXISTS currency_code text DEFAULT 'EUR';
ALTER TABLE supplier_payments ADD COLUMN IF NOT EXISTS exchange_rate numeric(12,6) DEFAULT 1.0;
ALTER TABLE supplier_payments ADD COLUMN IF NOT EXISTS amount_currency numeric(14,2);
ALTER TABLE supplier_payments ADD COLUMN IF NOT EXISTS exchange_gain_loss numeric(14,2) DEFAULT 0;

-- ============================================================
-- #85: Currency on Payment Orders (if table exists)
-- ============================================================
DO $$ BEGIN
  ALTER TABLE payment_orders ADD COLUMN IF NOT EXISTS currency_code text DEFAULT 'EUR';
  ALTER TABLE payment_orders ADD COLUMN IF NOT EXISTS exchange_rate numeric(12,6) DEFAULT 1.0;
  ALTER TABLE payment_orders ADD COLUMN IF NOT EXISTS amount_currency numeric(14,2);
  ALTER TABLE payment_orders ADD COLUMN IF NOT EXISTS exchange_gain_loss numeric(14,2) DEFAULT 0;
EXCEPTION WHEN undefined_table THEN NULL; END $$;
