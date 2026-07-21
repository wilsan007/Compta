-- ============================================
-- BANK STATEMENT IMPORT (CFONB, MT940, Camt.053)
-- ============================================
-- Tracks imported bank statement files
-- and their parsing status
-- ============================================

CREATE TABLE IF NOT EXISTS bank_statement_imports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  bank_account_id uuid REFERENCES bank_accounts(id) ON DELETE CASCADE,
  filename text NOT NULL,
  format text NOT NULL,
  file_size bigint,
  status text NOT NULL DEFAULT 'pending',
  imported_count int DEFAULT 0,
  error_message text,
  imported_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_bank_stmt_imports_tenant ON bank_statement_imports(tenant_id);
CREATE INDEX IF NOT EXISTS idx_bank_stmt_imports_account ON bank_statement_imports(bank_account_id);
CREATE INDEX IF NOT EXISTS idx_bank_stmt_imports_status ON bank_statement_imports(status);

ALTER TABLE bank_statement_imports ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_bank_stmt_imports') THEN
    CREATE POLICY "allow_all_bank_stmt_imports" ON bank_statement_imports FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;
