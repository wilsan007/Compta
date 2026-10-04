-- ============================================
-- Phase 7A: Critical Fixes
-- Adds missing columns to journal_lines, tax_rates, third_party_accounts,
-- journals, chart_accounts + creates payment_terms and marking_types tables.
-- ============================================

-- ============================================
-- 1. JOURNAL_LINES — add VAT, echeance, quantity, marking columns
-- ============================================
DO $$ BEGIN
  ALTER TABLE journal_lines ADD COLUMN IF NOT EXISTS vat_code text;
  ALTER TABLE journal_lines ADD COLUMN IF NOT EXISTS vat_amount numeric(14,2) DEFAULT 0;
  ALTER TABLE journal_lines ADD COLUMN IF NOT EXISTS echeance_date date;
  ALTER TABLE journal_lines ADD COLUMN IF NOT EXISTS quantity numeric(14,4);
  ALTER TABLE journal_lines ADD COLUMN IF NOT EXISTS marking_code text;
  ALTER TABLE journal_lines ADD COLUMN IF NOT EXISTS marked_bap boolean DEFAULT false;
  ALTER TABLE journal_lines ADD COLUMN IF NOT EXISTS marked_bap_date date;
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'journal_lines alters: %', SQLERRM; END $$;

-- ============================================
-- 2. TAX_RATES — add account_collectee, account_deductible, type, mode
-- ============================================
DO $$ BEGIN
  ALTER TABLE tax_rates ADD COLUMN IF NOT EXISTS account_collectee text;
  ALTER TABLE tax_rates ADD COLUMN IF NOT EXISTS account_deductible text;
  ALTER TABLE tax_rates ADD COLUMN IF NOT EXISTS type text DEFAULT 'CA3';
  ALTER TABLE tax_rates ADD COLUMN IF NOT EXISTS mode text DEFAULT 'debits';
  ALTER TABLE tax_rates ADD COLUMN IF NOT EXISTS tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE;
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'tax_rates alters: %', SQLERRM; END $$;

-- Make tax_rates tenant-scoped (was global, now per-tenant for custom rates)
ALTER TABLE tax_rates ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_select_tax_rates ON tax_rates;
DROP POLICY IF EXISTS tenant_insert_tax_rates ON tax_rates;
DROP POLICY IF EXISTS tenant_update_tax_rates ON tax_rates;
DROP POLICY IF EXISTS tenant_delete_tax_rates ON tax_rates;
DO $$ BEGIN
  DROP POLICY IF EXISTS tenant_select_tax_rates ON tax_rates;
  CREATE POLICY tenant_select_tax_rates ON tax_rates FOR SELECT USING (tenant_id IS NULL OR tenant_id = current_tenant_id());
  DROP POLICY IF EXISTS tenant_insert_tax_rates ON tax_rates;
  CREATE POLICY tenant_insert_tax_rates ON tax_rates FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
  DROP POLICY IF EXISTS tenant_update_tax_rates ON tax_rates;
  CREATE POLICY tenant_update_tax_rates ON tax_rates FOR UPDATE USING (tenant_id = current_tenant_id());
  DROP POLICY IF EXISTS tenant_delete_tax_rates ON tax_rates;
  CREATE POLICY tenant_delete_tax_rates ON tax_rates FOR DELETE USING (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'tax_rates RLS: %', SQLERRM; END $$;

-- ============================================
-- 3. THIRD_PARTY_ACCOUNTS — add payment_term_id, default_bank_account_id, credit_limit
-- ============================================
DO $$ BEGIN
  ALTER TABLE third_party_accounts ADD COLUMN IF NOT EXISTS payment_term_id uuid;
  ALTER TABLE third_party_accounts ADD COLUMN IF NOT EXISTS default_bank_account_id uuid;
  ALTER TABLE third_party_accounts ADD COLUMN IF NOT EXISTS credit_limit numeric(14,2) DEFAULT 0;
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'third_party_accounts alters: %', SQLERRM; END $$;

-- ============================================
-- 4. JOURNALS — add numbering_mode, account_attente, is_analytic, analytic_plan_id
-- ============================================
DO $$ BEGIN
  ALTER TABLE journals ADD COLUMN IF NOT EXISTS numbering_mode text DEFAULT 'manual';
  ALTER TABLE journals ADD COLUMN IF NOT EXISTS account_attente text;
  ALTER TABLE journals ADD COLUMN IF NOT EXISTS is_analytic boolean DEFAULT false;
  ALTER TABLE journals ADD COLUMN IF NOT EXISTS analytic_plan_id uuid;
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'journals alters: %', SQLERRM; END $$;

-- ============================================
-- 5. CHART_ACCOUNTS — add racine, classe, nature, code_taxe_default, saisie_* columns
-- ============================================
DO $$ BEGIN
  ALTER TABLE chart_accounts ADD COLUMN IF NOT EXISTS racine text;
  ALTER TABLE chart_accounts ADD COLUMN IF NOT EXISTS classe text;
  ALTER TABLE chart_accounts ADD COLUMN IF NOT EXISTS nature text;
  ALTER TABLE chart_accounts ADD COLUMN IF NOT EXISTS code_taxe_default text;
  ALTER TABLE chart_accounts ADD COLUMN IF NOT EXISTS saisie_analytic boolean DEFAULT false;
  ALTER TABLE chart_accounts ADD COLUMN IF NOT EXISTS saisie_echeance boolean DEFAULT false;
  ALTER TABLE chart_accounts ADD COLUMN IF NOT EXISTS saisie_tiers boolean DEFAULT false;
  ALTER TABLE chart_accounts ADD COLUMN IF NOT EXISTS debit_n1 numeric(14,2) DEFAULT 0;
  ALTER TABLE chart_accounts ADD COLUMN IF NOT EXISTS credit_n1 numeric(14,2) DEFAULT 0;
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'chart_accounts alters: %', SQLERRM; END $$;

-- ============================================
-- 6. PAYMENT_TERMS — new table (Modèles de règlement)
-- ============================================
CREATE TABLE IF NOT EXISTS payment_terms (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  code text NOT NULL,
  name text NOT NULL,
  type text NOT NULL CHECK (type IN ('fixed', 'end_of_month', 'split')),
  days_1 int NOT NULL DEFAULT 30,
  days_2 int DEFAULT NULL,
  pct_1 numeric(5,2) DEFAULT 100.00,
  pct_2 numeric(5,2) DEFAULT NULL,
  end_of_month boolean DEFAULT false,
  description text,
  active boolean DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(tenant_id, code)
);

CREATE INDEX IF NOT EXISTS idx_payment_terms_tenant ON payment_terms(tenant_id);
CREATE INDEX IF NOT EXISTS idx_payment_terms_active ON payment_terms(active);

ALTER TABLE payment_terms ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_select_payment_terms ON payment_terms;
DROP POLICY IF EXISTS tenant_insert_payment_terms ON payment_terms;
DROP POLICY IF EXISTS tenant_update_payment_terms ON payment_terms;
DROP POLICY IF EXISTS tenant_delete_payment_terms ON payment_terms;
DO $$ BEGIN
  DROP POLICY IF EXISTS tenant_select_payment_terms ON payment_terms;
  CREATE POLICY tenant_select_payment_terms ON payment_terms FOR SELECT USING (tenant_id = current_tenant_id());
  DROP POLICY IF EXISTS tenant_insert_payment_terms ON payment_terms;
  CREATE POLICY tenant_insert_payment_terms ON payment_terms FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
  DROP POLICY IF EXISTS tenant_update_payment_terms ON payment_terms;
  CREATE POLICY tenant_update_payment_terms ON payment_terms FOR UPDATE USING (tenant_id = current_tenant_id());
  DROP POLICY IF EXISTS tenant_delete_payment_terms ON payment_terms;
  CREATE POLICY tenant_delete_payment_terms ON payment_terms FOR DELETE USING (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'payment_terms RLS: %', SQLERRM; END $$;

-- ============================================
-- 7. MARKING_TYPES — new table (Types de marquage paramétrables)
-- ============================================
CREATE TABLE IF NOT EXISTS marking_types (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  code text NOT NULL,
  label text NOT NULL,
  color text DEFAULT 'neutral',
  active boolean DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(tenant_id, code)
);

CREATE INDEX IF NOT EXISTS idx_marking_types_tenant ON marking_types(tenant_id);

ALTER TABLE marking_types ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_select_marking_types ON marking_types;
DROP POLICY IF EXISTS tenant_insert_marking_types ON marking_types;
DROP POLICY IF EXISTS tenant_update_marking_types ON marking_types;
DROP POLICY IF EXISTS tenant_delete_marking_types ON marking_types;
DO $$ BEGIN
  DROP POLICY IF EXISTS tenant_select_marking_types ON marking_types;
  CREATE POLICY tenant_select_marking_types ON marking_types FOR SELECT USING (tenant_id = current_tenant_id());
  DROP POLICY IF EXISTS tenant_insert_marking_types ON marking_types;
  CREATE POLICY tenant_insert_marking_types ON marking_types FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
  DROP POLICY IF EXISTS tenant_update_marking_types ON marking_types;
  CREATE POLICY tenant_update_marking_types ON marking_types FOR UPDATE USING (tenant_id = current_tenant_id());
  DROP POLICY IF EXISTS tenant_delete_marking_types ON marking_types;
  CREATE POLICY tenant_delete_marking_types ON marking_types FOR DELETE USING (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'marking_types RLS: %', SQLERRM; END $$;

-- ============================================
-- 8. Add FK from third_party_accounts.payment_term_id to payment_terms
-- ============================================
DO $$ BEGIN
  ALTER TABLE third_party_accounts
    ADD CONSTRAINT fk_tpa_payment_term
    FOREIGN KEY (payment_term_id) REFERENCES payment_terms(id) ON DELETE SET NULL;
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'FK payment_term: %', SQLERRM; END $$;

-- ============================================
-- 9. SEED DEFAULT PAYMENT TERMS (per tenant)
-- ============================================
INSERT INTO payment_terms (tenant_id, code, name, type, days_1, pct_1, end_of_month, description)
SELECT t.id, 'IMM', 'Immédiat', 'fixed', 0, 100.00, false, 'Paiement immédiat'
FROM tenants t
WHERE NOT EXISTS (SELECT 1 FROM payment_terms pt WHERE pt.tenant_id = t.id AND pt.code = 'IMM');

INSERT INTO payment_terms (tenant_id, code, name, type, days_1, pct_1, end_of_month, description)
SELECT t.id, '30J', '30 jours', 'fixed', 30, 100.00, false, 'Paiement à 30 jours'
FROM tenants t
WHERE NOT EXISTS (SELECT 1 FROM payment_terms pt WHERE pt.tenant_id = t.id AND pt.code = '30J');

INSERT INTO payment_terms (tenant_id, code, name, type, days_1, pct_1, end_of_month, description)
SELECT t.id, '30JFM', '30 jours fin de mois', 'end_of_month', 30, 100.00, true, 'Paiement à 30 jours fin de mois'
FROM tenants t
WHERE NOT EXISTS (SELECT 1 FROM payment_terms pt WHERE pt.tenant_id = t.id AND pt.code = '30JFM');

INSERT INTO payment_terms (tenant_id, code, name, type, days_1, days_2, pct_1, pct_2, end_of_month, description)
SELECT t.id, '50-30-60', '50% à 30j / 50% à 60j', 'split', 30, 60, 50.00, 50.00, false, 'Fractionnement 50/50 à 30 et 60 jours'
FROM tenants t
WHERE NOT EXISTS (SELECT 1 FROM payment_terms pt WHERE pt.tenant_id = t.id AND pt.code = '50-30-60');

-- ============================================
-- 10. SEED DEFAULT MARKING TYPES (per tenant)
-- ============================================
INSERT INTO marking_types (tenant_id, code, label, color)
SELECT t.id, 'BAP', 'Bon à payer', 'success'
FROM tenants t
WHERE NOT EXISTS (SELECT 1 FROM marking_types mt WHERE mt.tenant_id = t.id AND mt.code = 'BAP');

INSERT INTO marking_types (tenant_id, code, label, color)
SELECT t.id, 'LITIGE', 'Litige', 'danger'
FROM tenants t
WHERE NOT EXISTS (SELECT 1 FROM marking_types mt WHERE mt.tenant_id = t.id AND mt.code = 'LITIGE');

INSERT INTO marking_types (tenant_id, code, label, color)
SELECT t.id, 'ATTENTE', 'En attente', 'warning'
FROM tenants t
WHERE NOT EXISTS (SELECT 1 FROM marking_types mt WHERE mt.tenant_id = t.id AND mt.code = 'ATTENTE');
