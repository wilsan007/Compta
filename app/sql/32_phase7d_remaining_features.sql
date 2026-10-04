-- ============================================
-- Phase 7D — Remaining Features
-- Migration: 32_phase7d_remaining_features.sql
-- 
-- Creates tables for:
--   1. grid_templates (Modèles de grille)
--   2. payment_templates_compta (Modèles de règlement compta)
--   3. standard_labels (Libellés / bibliothèque)
--   4. analytic_journal_codes (Codes journaux analytiques)
--   5. reimputation_logs (Réimputation)
-- ============================================

-- ============================================
-- 1. grid_templates — Modèles de grille
-- ============================================
CREATE TABLE IF NOT EXISTS grid_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  code text NOT NULL,
  name text NOT NULL,
  description text,
  journal_code text,
  columns_config jsonb NOT NULL DEFAULT '[]'::jsonb,
  default_account text,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_grid_templates_tenant ON grid_templates(tenant_id);
CREATE INDEX IF NOT EXISTS idx_grid_templates_code ON grid_templates(tenant_id, code);

ALTER TABLE grid_templates ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS grid_templates_tenant_isolation ON grid_templates;
CREATE POLICY grid_templates_tenant_isolation ON grid_templates
  USING (tenant_id = auth.uid() OR tenant_id IS NULL);

-- ============================================
-- 2. payment_templates_compta — Modèles de règlement (compta)
-- ============================================
CREATE TABLE IF NOT EXISTS payment_templates_compta (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  code text NOT NULL,
  name text NOT NULL,
  description text,
  payment_method text NOT NULL DEFAULT 'transfer',
  day_count integer DEFAULT 30,
  end_of_month boolean DEFAULT false,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_payment_templates_compta_tenant ON payment_templates_compta(tenant_id);
CREATE INDEX IF NOT EXISTS idx_payment_templates_compta_code ON payment_templates_compta(tenant_id, code);

ALTER TABLE payment_templates_compta ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS payment_templates_compta_tenant_isolation ON payment_templates_compta;
CREATE POLICY payment_templates_compta_tenant_isolation ON payment_templates_compta
  USING (tenant_id = auth.uid() OR tenant_id IS NULL);

-- ============================================
-- 3. standard_labels — Libellés (bibliothèque)
-- ============================================
CREATE TABLE IF NOT EXISTS standard_labels (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  code text NOT NULL,
  label text NOT NULL,
  category text DEFAULT 'general',
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_standard_labels_tenant ON standard_labels(tenant_id);
CREATE INDEX IF NOT EXISTS idx_standard_labels_category ON standard_labels(tenant_id, category);

ALTER TABLE standard_labels ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS standard_labels_tenant_isolation ON standard_labels;
CREATE POLICY standard_labels_tenant_isolation ON standard_labels
  USING (tenant_id = auth.uid() OR tenant_id IS NULL);

-- ============================================
-- 4. analytic_journal_codes — Codes journaux analytiques
-- ============================================
CREATE TABLE IF NOT EXISTS analytic_journal_codes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  code text NOT NULL,
  name text NOT NULL,
  description text,
  type text DEFAULT 'analytic',
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_analytic_journal_codes_tenant ON analytic_journal_codes(tenant_id);
CREATE INDEX IF NOT EXISTS idx_analytic_journal_codes_code ON analytic_journal_codes(tenant_id, code);

ALTER TABLE analytic_journal_codes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS analytic_journal_codes_tenant_isolation ON analytic_journal_codes;
CREATE POLICY analytic_journal_codes_tenant_isolation ON analytic_journal_codes
  USING (tenant_id = auth.uid() OR tenant_id IS NULL);

-- ============================================
-- 5. reimputation_logs — Réimputation
-- ============================================
CREATE TABLE IF NOT EXISTS reimputation_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  original_entry_id uuid REFERENCES journal_entries(id),
  original_line_id uuid REFERENCES journal_lines(id),
  reimputed_entry_id uuid,
  reimputed_line_id uuid,
  from_account text NOT NULL,
  to_account text NOT NULL,
  amount numeric(15,2) NOT NULL DEFAULT 0,
  reason text,
  status text DEFAULT 'completed',
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_reimputation_logs_tenant ON reimputation_logs(tenant_id);
CREATE INDEX IF NOT EXISTS idx_reimputation_logs_entry ON reimputation_logs(tenant_id, original_entry_id);

ALTER TABLE reimputation_logs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS reimputation_logs_tenant_isolation ON reimputation_logs;
CREATE POLICY reimputation_logs_tenant_isolation ON reimputation_logs
  USING (tenant_id = auth.uid() OR tenant_id IS NULL);

-- ============================================
-- GRANTS
-- ============================================
GRANT SELECT, INSERT, UPDATE, DELETE ON
  grid_templates, payment_templates_compta, standard_labels,
  analytic_journal_codes, reimputation_logs
  TO authenticated;

-- ============================================
-- 6. ALTER TABLE employees — additional fields
-- ============================================
ALTER TABLE employees ADD COLUMN IF NOT EXISTS employee_number text;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS social_security_number text;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS birth_date date;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS address text;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS city text;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS postal_code text;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS contract_type text DEFAULT 'CDI';
ALTER TABLE employees ADD COLUMN IF NOT EXISTS contract_end_date date;
