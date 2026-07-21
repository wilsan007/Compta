-- ============================================
-- REGULARIZATION ENTRIES (CCA / PCA / PRC / CRC)
-- ============================================
-- Charges Constatées d'Avance (CCA) — account 486
-- Produits Constatés d'Avance (PCA) — account 487
-- Provisions pour Risques et Charges (PRC) — account 151
-- Comptes de Régularisation par nature (CRC)
-- ============================================

CREATE TABLE IF NOT EXISTS regularization_entries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  type text NOT NULL, -- CCA, PCA, PRC, CRC
  fiscal_year_id uuid,
  account_code text NOT NULL, -- 486, 487, 151, etc.
  third_party_code text,
  description text NOT NULL,
  invoice_number text,
  invoice_date date,
  invoice_amount numeric(14,2) NOT NULL DEFAULT 0,
  start_date date NOT NULL,
  end_date date NOT NULL,
  amount numeric(14,2) NOT NULL DEFAULT 0,
  used_amount numeric(14,2) NOT NULL DEFAULT 0,
  remaining_amount numeric(14,2) NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'pending', -- pending, regularized, extourned
  journal_id text,
  journal_code text,
  created_entry_id uuid,
  extourne_entry_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_regularization_tenant ON regularization_entries(tenant_id);
CREATE INDEX IF NOT EXISTS idx_regularization_type ON regularization_entries(type);
CREATE INDEX IF NOT EXISTS idx_regularization_status ON regularization_entries(status);
CREATE INDEX IF NOT EXISTS idx_regularization_fiscal_year ON regularization_entries(fiscal_year_id);

ALTER TABLE regularization_entries ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_regularization_entries') THEN
    CREATE POLICY "allow_all_regularization_entries" ON regularization_entries FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;
