-- ============================================
-- Phase 7B: Medium Fixes
-- Items 8-15: lettrage en saisie, création compte volée,
-- bon à payer, marquage paramétrable, multi-échéances,
-- justificatif de solde, état rapprochement, 10 niveaux de relance
-- ============================================

-- ============================================
-- 1. REMINDER_LEVELS — 10 niveaux de relance
-- ============================================
CREATE TABLE IF NOT EXISTS reminder_levels (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  level int NOT NULL CHECK (level >= 1 AND level <= 10),
  name text NOT NULL,
  template text,
  days_after_due int NOT NULL DEFAULT 0,
  penalty_rate numeric(5,2) DEFAULT 0,
  active boolean DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(tenant_id, level)
);

CREATE INDEX IF NOT EXISTS idx_reminder_levels_tenant ON reminder_levels(tenant_id);
CREATE INDEX IF NOT EXISTS idx_reminder_levels_active ON reminder_levels(active);

ALTER TABLE reminder_levels ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_select_reminder_levels ON reminder_levels;
DROP POLICY IF EXISTS tenant_insert_reminder_levels ON reminder_levels;
DROP POLICY IF EXISTS tenant_update_reminder_levels ON reminder_levels;
DROP POLICY IF EXISTS tenant_delete_reminder_levels ON reminder_levels;
DO $$ BEGIN
  CREATE POLICY tenant_select_reminder_levels ON reminder_levels FOR SELECT USING (tenant_id = current_tenant_id());
  CREATE POLICY tenant_insert_reminder_levels ON reminder_levels FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
  CREATE POLICY tenant_update_reminder_levels ON reminder_levels FOR UPDATE USING (tenant_id = current_tenant_id());
  CREATE POLICY tenant_delete_reminder_levels ON reminder_levels FOR DELETE USING (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'reminder_levels RLS: %', SQLERRM; END $$;

-- ============================================
-- 2. PAYMENT_PROMISES — promesses de paiement
-- ============================================
CREATE TABLE IF NOT EXISTS payment_promises (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  third_party_code text NOT NULL,
  amount numeric(14,2) NOT NULL DEFAULT 0,
  promised_date date NOT NULL,
  reminder_level int DEFAULT 1,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'kept', 'broken', 'cancelled')),
  notes text,
  created_by text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_payment_promises_tenant ON payment_promises(tenant_id);
CREATE INDEX IF NOT EXISTS idx_payment_promises_status ON payment_promises(status);
CREATE INDEX IF NOT EXISTS idx_payment_promises_date ON payment_promises(promised_date);

ALTER TABLE payment_promises ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_select_payment_promises ON payment_promises;
DROP POLICY IF EXISTS tenant_insert_payment_promises ON payment_promises;
DROP POLICY IF EXISTS tenant_update_payment_promises ON payment_promises;
DROP POLICY IF EXISTS tenant_delete_payment_promises ON payment_promises;
DO $$ BEGIN
  CREATE POLICY tenant_select_payment_promises ON payment_promises FOR SELECT USING (tenant_id = current_tenant_id());
  CREATE POLICY tenant_insert_payment_promises ON payment_promises FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
  CREATE POLICY tenant_update_payment_promises ON payment_promises FOR UPDATE USING (tenant_id = current_tenant_id());
  CREATE POLICY tenant_delete_payment_promises ON payment_promises FOR DELETE USING (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'payment_promises RLS: %', SQLERRM; END $$;

-- ============================================
-- 3. DISPUTES — gestion des litiges
-- ============================================
CREATE TABLE IF NOT EXISTS disputes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  third_party_code text NOT NULL,
  invoice_ref text,
  amount numeric(14,2) NOT NULL DEFAULT 0,
  reason text NOT NULL,
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'under_review', 'resolved', 'rejected')),
  resolution text,
  opened_date date NOT NULL DEFAULT CURRENT_DATE,
  resolved_date date,
  created_by text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_disputes_tenant ON disputes(tenant_id);
CREATE INDEX IF NOT EXISTS idx_disputes_status ON disputes(status);

ALTER TABLE disputes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_select_disputes ON disputes;
DROP POLICY IF EXISTS tenant_insert_disputes ON disputes;
DROP POLICY IF EXISTS tenant_update_disputes ON disputes;
DROP POLICY IF EXISTS tenant_delete_disputes ON disputes;
DO $$ BEGIN
  CREATE POLICY tenant_select_disputes ON disputes FOR SELECT USING (tenant_id = current_tenant_id());
  CREATE POLICY tenant_insert_disputes ON disputes FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
  CREATE POLICY tenant_update_disputes ON disputes FOR UPDATE USING (tenant_id = current_tenant_id());
  CREATE POLICY tenant_delete_disputes ON disputes FOR DELETE USING (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'disputes RLS: %', SQLERRM; END $$;

-- ============================================
-- 4. SEED DEFAULT REMINDER LEVELS (per tenant)
-- ============================================
INSERT INTO reminder_levels (tenant_id, level, name, days_after_due, penalty_rate, active)
SELECT t.id, lvl.level, lvl.name, lvl.days, lvl.penalty, true
FROM tenants t
CROSS JOIN (VALUES
  (1, '1ère relance', 7, 0.00),
  (2, '2ème relance', 15, 0.00),
  (3, '3ème relance', 30, 0.00),
  (4, 'Mise en demeure', 45, 2.00),
  (5, 'Procédure', 60, 5.00)
) AS lvl(level, name, days, penalty)
WHERE NOT EXISTS (
  SELECT 1 FROM reminder_levels rl WHERE rl.tenant_id = t.id AND rl.level = lvl.level
);

-- ============================================
-- 5. Add reminder_level_id to collection_reminders
-- ============================================
DO $$ BEGIN
  ALTER TABLE collection_reminders ADD COLUMN IF NOT EXISTS reminder_level_id uuid REFERENCES reminder_levels(id) ON DELETE SET NULL;
  ALTER TABLE collection_reminders ADD COLUMN IF NOT EXISTS dispute_id uuid REFERENCES disputes(id) ON DELETE SET NULL;
  ALTER TABLE collection_reminders ADD COLUMN IF NOT EXISTS promise_id uuid REFERENCES payment_promises(id) ON DELETE SET NULL;
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'collection_reminders alters: %', SQLERRM; END $$;

-- ============================================
-- 6. JUSTIFICATIF_SOLDE — table de stockage des justificatifs
-- ============================================
CREATE TABLE IF NOT EXISTS justificatif_solde (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  account_code text NOT NULL,
  third_party_code text,
  fiscal_period_id uuid,
  opening_balance numeric(14,2) NOT NULL DEFAULT 0,
  total_debit numeric(14,2) NOT NULL DEFAULT 0,
  total_credit numeric(14,2) NOT NULL DEFAULT 0,
  closing_balance numeric(14,2) NOT NULL DEFAULT 0,
  generated_at timestamptz NOT NULL DEFAULT now(),
  generated_by text
);

CREATE INDEX IF NOT EXISTS idx_justificatif_solde_tenant ON justificatif_solde(tenant_id);
CREATE INDEX IF NOT EXISTS idx_justificatif_solde_account ON justificatif_solde(account_code);

ALTER TABLE justificatif_solde ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_select_justificatif_solde ON justificatif_solde;
DROP POLICY IF EXISTS tenant_insert_justificatif_solde ON justificatif_solde;
DROP POLICY IF EXISTS tenant_delete_justificatif_solde ON justificatif_solde;
DO $$ BEGIN
  CREATE POLICY tenant_select_justificatif_solde ON justificatif_solde FOR SELECT USING (tenant_id = current_tenant_id());
  CREATE POLICY tenant_insert_justificatif_solde ON justificatif_solde FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
  CREATE POLICY tenant_delete_justificatif_solde ON justificatif_solde FOR DELETE USING (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'justificatif_solde RLS: %', SQLERRM; END $$;

-- ============================================
-- 7. ETAT_RAPPROCHEMENT — table de stockage
-- ============================================
CREATE TABLE IF NOT EXISTS etat_rapprochement (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  bank_account_id uuid,
  account_code text NOT NULL,
  period_start date NOT NULL,
  period_end date NOT NULL,
  bank_balance numeric(14,2) NOT NULL DEFAULT 0,
  book_balance numeric(14,2) NOT NULL DEFAULT 0,
  difference numeric(14,2) NOT NULL DEFAULT 0,
  reconciled_items int DEFAULT 0,
  unreconciled_items int DEFAULT 0,
  generated_at timestamptz NOT NULL DEFAULT now(),
  generated_by text
);

CREATE INDEX IF NOT EXISTS idx_etat_rapprochement_tenant ON etat_rapprochement(tenant_id);
CREATE INDEX IF NOT EXISTS idx_etat_rapprochement_account ON etat_rapprochement(account_code);

ALTER TABLE etat_rapprochement ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_select_etat_rapprochement ON etat_rapprochement;
DROP POLICY IF EXISTS tenant_insert_etat_rapprochement ON etat_rapprochement;
DROP POLICY IF EXISTS tenant_delete_etat_rapprochement ON etat_rapprochement;
DO $$ BEGIN
  CREATE POLICY tenant_select_etat_rapprochement ON etat_rapprochement FOR SELECT USING (tenant_id = current_tenant_id());
  CREATE POLICY tenant_insert_etat_rapprochement ON etat_rapprochement FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
  CREATE POLICY tenant_delete_etat_rapprochement ON etat_rapprochement FOR DELETE USING (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'etat_rapprochement RLS: %', SQLERRM; END $$;

-- ============================================
-- 8. Add marking_type_id FK on journal_lines
-- ============================================
DO $$ BEGIN
  ALTER TABLE journal_lines
    ADD CONSTRAINT fk_jl_marking_type
    FOREIGN KEY (marking_code) REFERENCES marking_types(code) ON DELETE SET NULL;
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'FK marking_type: %', SQLERRM; END $$;

-- ============================================
-- 9. Add BAP and lettrage columns to journal_lines
-- ============================================
DO $$ BEGIN
  ALTER TABLE journal_lines ADD COLUMN IF NOT EXISTS marked_bap boolean DEFAULT false;
  ALTER TABLE journal_lines ADD COLUMN IF NOT EXISTS marked_bap_date date;
  ALTER TABLE journal_lines ADD COLUMN IF NOT EXISTS lettrage_code text;
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'journal_lines BAP/lettrage columns: %', SQLERRM; END $$;

CREATE INDEX IF NOT EXISTS idx_journal_lines_marked_bap ON journal_lines(marked_bap) WHERE marked_bap = true;
CREATE INDEX IF NOT EXISTS idx_journal_lines_lettrage ON journal_lines(lettrage_code) WHERE lettrage_code IS NOT NULL;
