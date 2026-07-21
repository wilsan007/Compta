-- ============================================
-- TVA ENCAISSEMENT VS DÉBIT + TVA SUR ACOMPTES + TVS
-- ============================================
-- Phase 1.14: VAT on collection vs on delivery
-- Phase 1.15: VAT on deposits/advances
-- Phase 1.16: Company Vehicle Tax (TVS)
-- ============================================

-- Phase 1.14: Add VAT method to company settings
ALTER TABLE company_settings
  ADD COLUMN IF NOT EXISTS vat_method text DEFAULT 'debit'
  CHECK (vat_method IN ('debit', 'encaissement'));

-- Phase 1.15: Add VAT on deposits tracking
ALTER TABLE vat_returns
  ADD COLUMN IF NOT EXISTS deposits_vat_collected numeric(14,2) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS deposits_vat_deductible numeric(14,2) DEFAULT 0;

-- Phase 1.16: Company Vehicle Tax (TVS) table
CREATE TABLE IF NOT EXISTS tvs_declarations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  fiscal_year int NOT NULL,
  vehicle_registration text NOT NULL,
  vehicle_type text,
  co2_emissions int,
  first_registration_date date,
  amount_co2 numeric(14,2) DEFAULT 0,
  amount_age numeric(14,2) DEFAULT 0,
  amount_total numeric(14,2) DEFAULT 0,
  status text DEFAULT 'draft' CHECK (status IN ('draft', 'filed', 'paid')),
  filed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_tvs_tenant ON tvs_declarations(tenant_id);
CREATE INDEX IF NOT EXISTS idx_tvs_fiscal_year ON tvs_declarations(fiscal_year);

ALTER TABLE tvs_declarations ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_tvs_declarations') THEN
    CREATE POLICY "allow_all_tvs_declarations" ON tvs_declarations FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;
