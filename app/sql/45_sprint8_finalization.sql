-- ============================================================
-- Sprint 8: Finalisation — Multi-Devises Étendu + Chéquier
-- Elements: #5 (Devise factures), #9 (Écarts de change), #87 (Devise tiers), #82 (Chéquier)
-- #86 déjà couvert dans 44_sprint6, #12-24 déjà couverts dans Sprint 3/4
-- ============================================================

-- ============================================================
-- #5: Devise sur Factures (invoices, purchase_invoices, credit_notes, purchase_credit_notes)
-- ============================================================
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS currency_code text DEFAULT 'EUR';
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS exchange_rate numeric(12,6) DEFAULT 1.0;
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS amount_untaxed_currency numeric(14,2);
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS amount_tax_currency numeric(14,2);
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS amount_total_currency numeric(14,2);

ALTER TABLE purchase_invoices ADD COLUMN IF NOT EXISTS currency_code text DEFAULT 'EUR';
ALTER TABLE purchase_invoices ADD COLUMN IF NOT EXISTS exchange_rate numeric(12,6) DEFAULT 1.0;
ALTER TABLE purchase_invoices ADD COLUMN IF NOT EXISTS amount_untaxed_currency numeric(14,2);
ALTER TABLE purchase_invoices ADD COLUMN IF NOT EXISTS amount_tax_currency numeric(14,2);
ALTER TABLE purchase_invoices ADD COLUMN IF NOT EXISTS amount_total_currency numeric(14,2);

ALTER TABLE credit_notes ADD COLUMN IF NOT EXISTS currency_code text DEFAULT 'EUR';
ALTER TABLE credit_notes ADD COLUMN IF NOT EXISTS exchange_rate numeric(12,6) DEFAULT 1.0;
ALTER TABLE credit_notes ADD COLUMN IF NOT EXISTS amount_untaxed_currency numeric(14,2);
ALTER TABLE credit_notes ADD COLUMN IF NOT EXISTS amount_tax_currency numeric(14,2);
ALTER TABLE credit_notes ADD COLUMN IF NOT EXISTS amount_total_currency numeric(14,2);

ALTER TABLE purchase_credit_notes ADD COLUMN IF NOT EXISTS currency_code text DEFAULT 'EUR';
ALTER TABLE purchase_credit_notes ADD COLUMN IF NOT EXISTS exchange_rate numeric(12,6) DEFAULT 1.0;
ALTER TABLE purchase_credit_notes ADD COLUMN IF NOT EXISTS amount_untaxed_currency numeric(14,2);
ALTER TABLE purchase_credit_notes ADD COLUMN IF NOT EXISTS amount_tax_currency numeric(14,2);
ALTER TABLE purchase_credit_notes ADD COLUMN IF NOT EXISTS amount_total_currency numeric(14,2);

-- ============================================================
-- #87: Devise sur Tiers (currency_code normalisé sur customers, suppliers)
-- ============================================================
ALTER TABLE customers ADD COLUMN IF NOT EXISTS currency_code text DEFAULT 'EUR';
ALTER TABLE suppliers ADD COLUMN IF NOT EXISTS currency_code text DEFAULT 'EUR';

-- Migration: copier currency → currency_code si currency_code est NULL ou 'EUR' par défaut
UPDATE customers SET currency_code = currency WHERE currency IS NOT NULL AND currency != '' AND currency_code = 'EUR';
UPDATE suppliers SET currency_code = currency WHERE currency IS NOT NULL AND currency != '' AND currency_code = 'EUR';

-- ============================================================
-- #9: Écarts de Change sur Règlements
-- ============================================================
CREATE TABLE IF NOT EXISTS exchange_gain_loss_entries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  payment_id uuid,
  invoice_id uuid,
  type text NOT NULL,
  amount numeric(14,2),
  exchange_rate_original numeric(12,6),
  exchange_rate_payment numeric(12,6),
  account_gain_code text,
  account_loss_code text,
  journal_entry_id uuid,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_exchange_gain_loss_tenant ON exchange_gain_loss_entries(tenant_id);
CREATE INDEX IF NOT EXISTS idx_exchange_gain_loss_payment ON exchange_gain_loss_entries(payment_id);
CREATE INDEX IF NOT EXISTS idx_exchange_gain_loss_invoice ON exchange_gain_loss_entries(invoice_id);

ALTER TABLE exchange_gain_loss_entries ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_exchange_gain_loss_entries') THEN
    CREATE POLICY "allow_all_exchange_gain_loss_entries" ON exchange_gain_loss_entries FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- ============================================================
-- #82: Suivi des Chèques — check_books + checks
-- ============================================================
CREATE TABLE IF NOT EXISTS check_books (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  bank_account_id uuid REFERENCES bank_accounts(id),
  journal_id uuid,
  name text NOT NULL,
  first_check_number text NOT NULL,
  last_check_number text NOT NULL,
  next_check_number text NOT NULL,
  status text DEFAULT 'active',
  issued_count integer DEFAULT 0,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_check_books_tenant ON check_books(tenant_id);
CREATE INDEX IF NOT EXISTS idx_check_books_bank_account ON check_books(bank_account_id);
CREATE INDEX IF NOT EXISTS idx_check_books_status ON check_books(status);

ALTER TABLE check_books ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_check_books') THEN
    CREATE POLICY "allow_all_check_books" ON check_books FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS checks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  check_book_id uuid REFERENCES check_books(id) ON DELETE CASCADE,
  check_number text NOT NULL,
  amount numeric(14,2) NOT NULL,
  payee text NOT NULL,
  issue_date date NOT NULL,
  due_date date,
  status text DEFAULT 'draft',
  journal_entry_id uuid,
  payment_id uuid,
  notes text,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_checks_tenant ON checks(tenant_id);
CREATE INDEX IF NOT EXISTS idx_checks_check_book ON checks(check_book_id);
CREATE INDEX IF NOT EXISTS idx_checks_status ON checks(status);
CREATE INDEX IF NOT EXISTS idx_checks_issue_date ON checks(issue_date);

ALTER TABLE checks ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_checks') THEN
    CREATE POLICY "allow_all_checks" ON checks FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;
