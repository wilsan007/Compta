-- ============================================
-- BANK REGISTRY + TEMPLATE VALIDATION
-- 1. Global banks table (shared across all tenants)
-- 2. Update bank_statement_templates with validation tracking
-- ============================================

-- 1. Global banks registry (NOT tenant-scoped, shared by all)
CREATE TABLE IF NOT EXISTS banks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL UNIQUE,
  swift_code text,
  country text,
  logo_url text,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

-- Seed common banks (country = ISO 3166-1 alpha-3 code)
INSERT INTO banks (name, country, swift_code) VALUES
  ('BCIM Djibouti', 'DJI', 'BCIMDJDJ'),
  ('Bank of Africa', 'DJI', 'AFRIDJDJ'),
  ('BRED', 'FRA', 'BREDFRPP'),
  ('Salam African Bank', 'DJI', 'SALMDJDJ'),
  ('Commercial Bank of Ethiopia', 'ETH', 'CBETETAA'),
  ('Exim Bank Djibouti', 'DJI', 'EXIMDJDJ'),
  ('Banque pour le Commerce et l Industrie', 'DJI', 'BCIDDJDJ')
ON CONFLICT (name) DO NOTHING;

-- Public read access for banks (all tenants can see the list)
ALTER TABLE banks ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS banks_read_all ON banks;
CREATE POLICY banks_read_all ON banks FOR SELECT USING (true);

GRANT SELECT ON banks TO authenticated;
GRANT SELECT ON banks TO anon;

-- 2. Add validation tracking to bank_statement_templates
ALTER TABLE bank_statement_templates
  ADD COLUMN IF NOT EXISTS bank_id uuid REFERENCES banks(id) ON DELETE SET NULL;

ALTER TABLE bank_statement_templates
  ADD COLUMN IF NOT EXISTS validation_status text NOT NULL DEFAULT 'pending'
  CHECK (validation_status IN ('pending', 'validated', 'rejected'));

ALTER TABLE bank_statement_templates
  ADD COLUMN IF NOT EXISTS consecutive_successes integer NOT NULL DEFAULT 0;

ALTER TABLE bank_statement_templates
  ADD COLUMN IF NOT EXISTS validation_count integer NOT NULL DEFAULT 0;

ALTER TABLE bank_statement_templates
  ADD COLUMN IF NOT EXISTS last_validated_at timestamptz;

ALTER TABLE bank_statement_templates
  ADD COLUMN IF NOT EXISTS last_correction_notes text;

-- Index for looking up templates by bank (cross-tenant for validated patterns)
CREATE INDEX IF NOT EXISTS idx_bank_stmt_templates_bank
  ON bank_statement_templates(bank_id, validation_status);

-- Allow tenants to use validated templates from other tenants
-- (validated patterns are shared knowledge)
CREATE INDEX IF NOT EXISTS idx_bank_stmt_templates_validated
  ON bank_statement_templates(bank_id)
  WHERE validation_status = 'validated';
