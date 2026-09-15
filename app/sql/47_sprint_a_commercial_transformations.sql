-- ============================================================
-- Sprint A: Transformations du cycle commercial
-- File: 47_sprint_a_commercial_transformations.sql
-- ============================================================

-- ============ New tables ============

-- Document charges (shipping, handling, insurance, packaging)
CREATE TABLE IF NOT EXISTS document_charges (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  document_type text NOT NULL,
  document_id uuid NOT NULL,
  charge_type text NOT NULL,
  label text NOT NULL,
  amount numeric(15,2) DEFAULT 0,
  vat_rate numeric(5,2) DEFAULT 0,
  vat_amount numeric(15,2) DEFAULT 0,
  total_amount numeric(15,2) DEFAULT 0,
  supplier_id uuid REFERENCES suppliers(id) ON DELETE SET NULL,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_doc_charges_doc ON document_charges(document_type, document_id);
ALTER TABLE document_charges ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_document_charges') THEN
    DROP POLICY IF EXISTS "allow_all_document_charges" ON document_charges;
    CREATE POLICY "allow_all_document_charges" ON document_charges FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;

-- Document transformations (trace conversions: quote→order→delivery→invoice→credit)
CREATE TABLE IF NOT EXISTS document_transformations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  source_type text NOT NULL,
  source_id uuid NOT NULL,
  target_type text NOT NULL,
  target_id uuid NOT NULL,
  transformation_type text NOT NULL,
  transformed_by text,
  transformed_at timestamptz DEFAULT now(),
  notes text
);
CREATE INDEX IF NOT EXISTS idx_doc_trans_src ON document_transformations(source_type, source_id);
CREATE INDEX IF NOT EXISTS idx_doc_trans_tgt ON document_transformations(target_type, target_id);
ALTER TABLE document_transformations ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_doc_transformations') THEN
    DROP POLICY IF EXISTS "allow_all_doc_transformations" ON document_transformations;
    CREATE POLICY "allow_all_doc_transformations" ON document_transformations FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;

-- ============ Extensions to existing tables ============

-- sales_orders
ALTER TABLE sales_orders ADD COLUMN IF NOT EXISTS quote_id uuid;
ALTER TABLE sales_orders ADD COLUMN IF NOT EXISTS fully_delivered boolean DEFAULT false;
ALTER TABLE sales_orders ADD COLUMN IF NOT EXISTS delivery_status text DEFAULT 'pending';

-- sales_order_lines
ALTER TABLE sales_order_lines ADD COLUMN IF NOT EXISTS delivered_quantity numeric(15,2) DEFAULT 0;

-- delivery_notes
ALTER TABLE delivery_notes ADD COLUMN IF NOT EXISTS fully_invoiced boolean DEFAULT false;
ALTER TABLE delivery_notes ADD COLUMN IF NOT EXISTS invoice_status text DEFAULT 'pending';

-- delivery_note_lines
ALTER TABLE delivery_note_lines ADD COLUMN IF NOT EXISTS invoiced_quantity numeric(15,2) DEFAULT 0;
ALTER TABLE delivery_note_lines ADD COLUMN IF NOT EXISTS sales_order_line_id uuid;

-- invoices
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS delivery_note_id uuid;
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS sales_order_id uuid;
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS quote_id uuid;
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS is_advance_invoice boolean DEFAULT false;
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS advance_amount numeric(15,2) DEFAULT 0;
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS invoice_type text DEFAULT 'standard';
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS parent_invoice_id uuid;

-- invoice_lines
ALTER TABLE invoice_lines ADD COLUMN IF NOT EXISTS delivery_note_line_id uuid;
ALTER TABLE invoice_lines ADD COLUMN IF NOT EXISTS sales_order_line_id uuid;

-- credit_notes
ALTER TABLE credit_notes ADD COLUMN IF NOT EXISTS source_invoice_id uuid;

-- products
ALTER TABLE products ADD COLUMN IF NOT EXISTS barcode text;
ALTER TABLE products ADD COLUMN IF NOT EXISTS weight numeric(10,3);
ALTER TABLE products ADD COLUMN IF NOT EXISTS photo_url text;
ALTER TABLE products ADD COLUMN IF NOT EXISTS supplier_ref text;
ALTER TABLE products ADD COLUMN IF NOT EXISTS criticality_level text DEFAULT 'normal';
ALTER TABLE products ADD COLUMN IF NOT EXISTS cost_price numeric(15,2) DEFAULT 0;

-- quotes
ALTER TABLE quotes ADD COLUMN IF NOT EXISTS transformed_to_order_id uuid;
ALTER TABLE quotes ADD COLUMN IF NOT EXISTS transformation_status text DEFAULT 'pending';
