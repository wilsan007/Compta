-- Sprint I: Dématérialisation
-- Tables: electronic_signatures, online_payments, document_shares

-- electronic_signatures
CREATE TABLE IF NOT EXISTS electronic_signatures (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  document_type text NOT NULL,
  document_id uuid NOT NULL,
  signer_name text NOT NULL,
  signer_email text,
  signature_hash text,
  signature_data text,
  ip_address text,
  signed_at timestamptz DEFAULT now(),
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_es_doc ON electronic_signatures(document_type, document_id);
ALTER TABLE electronic_signatures ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_electronic_signatures') THEN
    CREATE POLICY "allow_all_electronic_signatures" ON electronic_signatures FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;

-- online_payments
CREATE TABLE IF NOT EXISTS online_payments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  invoice_id uuid REFERENCES invoices(id) ON DELETE SET NULL,
  customer_id uuid REFERENCES customers(id) ON DELETE SET NULL,
  payment_provider text,
  provider_transaction_id text,
  amount numeric(15,2) NOT NULL,
  currency_code text DEFAULT 'EUR',
  status text DEFAULT 'pending',
  payment_url text,
  paid_at timestamptz,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_op_invoice ON online_payments(invoice_id);
ALTER TABLE online_payments ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_online_payments') THEN
    CREATE POLICY "allow_all_online_payments" ON online_payments FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;

-- document_shares
CREATE TABLE IF NOT EXISTS document_shares (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  document_type text NOT NULL,
  document_id uuid NOT NULL,
  shared_with_email text NOT NULL,
  share_token text NOT NULL,
  share_url text,
  expires_at timestamptz,
  viewed boolean DEFAULT false,
  viewed_at timestamptz,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_ds_token ON document_shares(share_token);
ALTER TABLE document_shares ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_document_shares') THEN
    CREATE POLICY "allow_all_document_shares" ON document_shares FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
