-- Sprint G: Dématérialisation RH
-- Tables: employee_documents, document_distribution_logs, rh_requests, rh_knowledge_base

-- ============ employee_documents ============
-- Add missing columns to existing table from migration 21
ALTER TABLE employee_documents ADD COLUMN IF NOT EXISTS title text;
ALTER TABLE employee_documents ADD COLUMN IF NOT EXISTS file_size bigint;
ALTER TABLE employee_documents ADD COLUMN IF NOT EXISTS mime_type text;
ALTER TABLE employee_documents ADD COLUMN IF NOT EXISTS period text;
ALTER TABLE employee_documents ADD COLUMN IF NOT EXISTS uploaded_by text;
ALTER TABLE employee_documents ADD COLUMN IF NOT EXISTS visible_to_employee boolean DEFAULT true;
ALTER TABLE employee_documents ADD COLUMN IF NOT EXISTS requires_acknowledgment boolean DEFAULT false;
ALTER TABLE employee_documents ADD COLUMN IF NOT EXISTS acknowledged boolean DEFAULT false;
ALTER TABLE employee_documents ADD COLUMN IF NOT EXISTS e_signed boolean DEFAULT false;
ALTER TABLE employee_documents ADD COLUMN IF NOT EXISTS e_signed_at timestamptz;
ALTER TABLE employee_documents ADD COLUMN IF NOT EXISTS e_signature_hash text;
ALTER TABLE employee_documents ADD COLUMN IF NOT EXISTS archived boolean DEFAULT false;
ALTER TABLE employee_documents ADD COLUMN IF NOT EXISTS archive_date date;
ALTER TABLE employee_documents ADD COLUMN IF NOT EXISTS retention_years int DEFAULT 10;
-- Set title from file_name for existing rows if title is null
UPDATE employee_documents SET title = file_name WHERE title IS NULL AND file_name IS NOT NULL;
UPDATE employee_documents SET title = 'Untitled' WHERE title IS NULL;
-- Make title NOT NULL after backfill
ALTER TABLE employee_documents ALTER COLUMN title SET NOT NULL;
CREATE INDEX IF NOT EXISTS idx_emp_docs_employee ON employee_documents(employee_id);
CREATE INDEX IF NOT EXISTS idx_emp_docs_type ON employee_documents(document_type);
CREATE INDEX IF NOT EXISTS idx_emp_docs_period ON employee_documents(period);
ALTER TABLE employee_documents ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_employee_documents') THEN
    CREATE POLICY "allow_all_employee_documents" ON employee_documents FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;

-- ============ document_distribution_logs ============
CREATE TABLE IF NOT EXISTS document_distribution_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  batch_id uuid,
  employee_document_id uuid REFERENCES employee_documents(id) ON DELETE CASCADE,
  employee_id uuid NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  document_type text,
  period text,
  distributed_at timestamptz,
  acknowledged_at timestamptz,
  status text DEFAULT 'distributed' CHECK (status IN ('distributed', 'acknowledged', 'bounced', 'failed')),
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_dist_logs_batch ON document_distribution_logs(batch_id);
CREATE INDEX IF NOT EXISTS idx_dist_logs_employee ON document_distribution_logs(employee_id);
ALTER TABLE document_distribution_logs ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_document_distribution_logs') THEN
    CREATE POLICY "allow_all_document_distribution_logs" ON document_distribution_logs FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;

-- ============ rh_requests ============
CREATE TABLE IF NOT EXISTS rh_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  employee_id uuid NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  request_type text NOT NULL,
  subject text NOT NULL,
  description text,
  status text DEFAULT 'pending' CHECK (status IN ('pending', 'in_progress', 'resolved', 'rejected')),
  assigned_to text,
  response text,
  resolved_at timestamptz,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_rh_requests_status ON rh_requests(status);
CREATE INDEX IF NOT EXISTS idx_rh_requests_employee ON rh_requests(employee_id);
ALTER TABLE rh_requests ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_rh_requests') THEN
    CREATE POLICY "allow_all_rh_requests" ON rh_requests FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;

-- ============ rh_knowledge_base ============
CREATE TABLE IF NOT EXISTS rh_knowledge_base (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  title text NOT NULL,
  content text NOT NULL,
  category text,
  tags text[],
  author_id text,
  published boolean DEFAULT false,
  views int DEFAULT 0,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_rh_kb_category ON rh_knowledge_base(category);
ALTER TABLE rh_knowledge_base ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='allow_all_rh_knowledge_base') THEN
    CREATE POLICY "allow_all_rh_knowledge_base" ON rh_knowledge_base FOR ALL USING(true) WITH CHECK(true);
  END IF;
END $$;
