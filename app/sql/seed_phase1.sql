-- ============================================
-- SEED DATA FOR PHASE 1 FEATURES (1.0 - 1.22)
-- Run after all migrations are applied
-- Uses a test tenant: '00000000-0000-0000-0000-000000000001'
-- ============================================

-- Ensure test tenant exists
INSERT INTO tenants (id, name, created_at) VALUES
  ('00000000-0000-0000-0000-000000000001', 'Test Company SARL', now())
ON CONFLICT (id) DO NOTHING;

-- ============================================
-- Phase 1.0: i18n — no seed data needed (UI only)
-- ============================================

-- ============================================
-- Phase 1.1: Recurring Entries (Écritures d'abonnement)
-- ============================================
INSERT INTO recurring_entries (id, tenant_id, name, description, journal_id, journal_code, frequency, day_of_month, start_date, end_date, next_generation_date, lines, total_debit, total_credit, status, created_at, updated_at) VALUES
  ('a0000001-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Loyer bureau', 'Loyer mensuel bureau principal', 'OD', 'OD', 'monthly', 1, '2024-01-01', '2024-12-31', '2024-06-01', '[{"account_code":"613000","description":"Loyer bureau","debit":1500,"credit":0},{"account_code":"401000","description":"Loyer à payer","debit":0,"credit":1500}]'::jsonb, 1500.00, 1500.00, 'active', now(), now()),
  ('a0000002-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Assurance pro', 'Assurance responsabilité civile', 'OD', 'OD', 'quarterly', 15, '2024-01-01', '2024-12-31', '2024-07-15', '[{"account_code":"616000","description":"Assurance RC pro","debit":900,"credit":0},{"account_code":"401000","description":"Assurance à payer","debit":0,"credit":900}]'::jsonb, 900.00, 900.00, 'active', now(), now()),
  ('a0000003-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Amortissement ordinateurs', 'Amortissement linéaire 3 ans', 'OD', 'OD', 'monthly', 28, '2024-01-01', '2026-12-31', '2024-06-28', '[{"account_code":"681100","description":"Dotation amortissement","debit":300,"credit":0},{"account_code":"281500","description":"Amortissement matériel","debit":0,"credit":300}]'::jsonb, 300.00, 300.00, 'active', now(), now())
ON CONFLICT (id) DO NOTHING;

-- ============================================
-- Phase 1.2: Regularization CCA/PCA
-- ============================================
INSERT INTO regularization_entries (id, tenant_id, type, account_code, description, amount, start_date, end_date, status, created_at, updated_at) VALUES
  ('b0000001-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'CCA', '486000', 'Assurance payée d''avance 2024', 3600.00, '2024-01-01', '2024-12-31', 'pending', now(), now()),
  ('b0000002-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'PCA', '487000', 'Abonnement annuel perçu d''avance', 12000.00, '2024-01-01', '2024-12-31', 'pending', now(), now())
ON CONFLICT (id) DO NOTHING;

-- ============================================
-- Phase 1.3: Calculator — no seed data (utility function)
-- ============================================

-- ============================================
-- Phase 1.4: Bon à payer — uses purchase_invoices
-- Add a few purchase invoices with approval status
-- ============================================
-- (Uses existing purchase_invoices table — add bon_a_payer column if not exists)
-- Skipped: relies on existing purchase_invoices seed data

-- ============================================
-- Phase 1.5: Payment delays report — uses invoices
-- ============================================
-- (Relies on existing invoices with payment dates)

-- ============================================
-- Phase 1.6: Currency revaluation
-- ============================================
INSERT INTO currency_revaluations (id, tenant_id, account_code, currency, original_rate, new_rate, original_amount, original_amount_eur, revalued_amount_eur, gain_loss, type, period_date, status, created_at, updated_at) VALUES
  ('c0000001-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', '411USD', 'USD', 1.080000, 0.920000, 15000.00, 16200.00, 13800.00, -2400.00, 'receivable', '2024-06-30', 'posted', now(), now()),
  ('c0000002-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', '401GBP', 'GBP', 1.120000, 1.170000, 8000.00, 8960.00, 9360.00, 400.00, 'payable', '2024-06-30', 'pending', now(), now())
ON CONFLICT (id) DO NOTHING;

-- ============================================
-- Phase 1.7: Collection reminders + payment links
-- ============================================
INSERT INTO collection_reminders (id, tenant_id, number, customer_id, invoice_id, reminder_level, reminder_date, amount, payment_link_url, payment_status, status, created_at) VALUES
  ('d0000001-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'REL-2024-001', NULL, NULL, 1, '2024-06-01', 2500.00, 'https://pay.example.com/inv-001', 'unpaid', 'sent', now()),
  ('d0000002-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'REL-2024-002', NULL, NULL, 2, '2024-06-15', 2500.00, 'https://pay.example.com/inv-001', 'unpaid', 'sent', now()),
  ('d0000003-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'REL-2024-003', NULL, NULL, 3, '2024-07-01', 1800.00, 'https://pay.example.com/inv-002', 'unpaid', 'sent', now())
ON CONFLICT (id) DO NOTHING;

-- ============================================
-- Phase 1.8: Third-party statistical fields
-- ============================================
-- Add stats fields to customers/suppliers (ALTER TABLE in migration)
-- Seed: update existing customers with stats data
UPDATE customers SET
  revenue_range = '100K-500K',
  payment_delay_avg = 35,
  legal_form = 'SARL',
  ape_code = '6201Z',
  employee_count_range = '10-49'
WHERE tenant_id = '00000000-0000-0000-0000-000000000001';

-- ============================================
-- Phase 1.9: Multi analytic plans
-- ============================================
INSERT INTO analytic_plans (id, tenant_id, code, name, description, active, created_at) VALUES
  ('e0000001-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'AN1', 'Analytique principal', 'Plan analytique par défaut', true, now()),
  ('e0000002-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'AN2', 'Centres de coût', 'Répartition par centre de coût', true, now()),
  ('e0000003-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'AN3', 'Projets', 'Suivi analytique par projet', false, now())
ON CONFLICT (id) DO NOTHING;

-- ============================================
-- Phase 1.10: Distribution grills
-- ============================================
INSERT INTO distribution_grills (id, tenant_id, name, account_code, description, active, created_at) VALUES
  ('f0000001-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Frais généraux', '614000', 'Répartition frais généraux par centre', true, now()),
  ('f0000002-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Charges personnel', '641000', 'Répartition charges de personnel', true, now())
ON CONFLICT (id) DO NOTHING;

-- ============================================
-- Phase 1.11: Bank reconciliation rules (AFB)
-- ============================================
INSERT INTO bank_reconciliation_rules (id, tenant_id, name, afb_code, description, match_pattern, counterpart_account, journal_code, priority, active, created_at, updated_at) VALUES
  ('10000001-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Virements reçus', 'VIR', 'Virements reçus clients', 'VIREMENT', '411000', 'BQ', 1, true, now(), now()),
  ('10000002-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Prélèvements SEPA', 'PRLV', 'Prélèvements fournisseurs', 'PRELEVEMENT', '401000', 'BQ', 2, true, now(), now()),
  ('10000003-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Frais bancaires', 'FRA', 'Frais et commissions bancaires', 'FRAIS BANCAIRES', '627000', 'BQ', 3, true, now(), now())
ON CONFLICT (id) DO NOTHING;

-- ============================================
-- Phase 1.12: Bank statement imports
-- ============================================
INSERT INTO bank_statement_imports (id, tenant_id, bank_account_id, filename, format, file_size, status, imported_count, imported_at) VALUES
  ('11000001-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', NULL, 'extrait_juin_2024.cfonb', 'cfonb', 51200, 'completed', 45, now()),
  ('11000002-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', NULL, 'extrait_juillet_2024.mt940', 'mt940', NULL, 'pending', 0, now())
ON CONFLICT (id) DO NOTHING;

-- ============================================
-- Phase 1.13: EDI-TVA
-- ============================================
-- EDI-TVA data is stored in vat_returns table (columns added by migration 16)
-- Ensure EDI columns exist before INSERT
ALTER TABLE vat_returns ADD COLUMN IF NOT EXISTS edi_tva_id text;
ALTER TABLE vat_returns ADD COLUMN IF NOT EXISTS edi_status text DEFAULT 'not_submitted'
  CHECK (edi_status IN ('not_submitted', 'preparing', 'submitted', 'acknowledged', 'rejected'));
ALTER TABLE vat_returns ADD COLUMN IF NOT EXISTS edi_submitted_at timestamptz;
ALTER TABLE vat_returns ADD COLUMN IF NOT EXISTS edi_acknowledgment text;
ALTER TABLE vat_returns ADD COLUMN IF NOT EXISTS edi_acknowledged_at timestamptz;
ALTER TABLE vat_returns ADD COLUMN IF NOT EXISTS deposits_vat_collected numeric(14,2) DEFAULT 0;
ALTER TABLE vat_returns ADD COLUMN IF NOT EXISTS deposits_vat_deductible numeric(14,2) DEFAULT 0;

INSERT INTO vat_returns (id, tenant_id, period_start, period_end, status, box1_output_vat, box2_input_vat, box3_vat_due, box5_net_vat, total_sales, total_purchases, edi_tva_id, edi_status, edi_submitted_at, created_at) VALUES
  ('12000001-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', '2024-01-01', '2024-03-31', 'submitted', 15450.00, 8200.00, 7250.00, 7250.00, 77250.00, 41000.00, 'EDI-2024-Q1-001', 'submitted', '2024-04-15T10:00:00Z', now()),
  ('12000002-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', '2024-04-01', '2024-06-30', 'draft', 18200.00, 9100.00, 9100.00, 9100.00, 91000.00, 45500.00, 'EDI-2024-Q2-001', 'preparing', NULL, now())
ON CONFLICT (id) DO NOTHING;

-- ============================================
-- Phase 1.14: VAT method (company_settings)
-- ============================================
-- Ensure columns from migrations 17 & 18 exist
ALTER TABLE company_settings ADD COLUMN IF NOT EXISTS vat_method text DEFAULT 'debit'
  CHECK (vat_method IN ('debit', 'encaissement'));
ALTER TABLE company_settings ADD COLUMN IF NOT EXISTS gdpr_enabled boolean DEFAULT false;
ALTER TABLE company_settings ADD COLUMN IF NOT EXISTS gdpr_retention_years int DEFAULT 10;
ALTER TABLE company_settings ADD COLUMN IF NOT EXISTS gdpr_anonymize_after boolean DEFAULT true;
ALTER TABLE company_settings ADD COLUMN IF NOT EXISTS accounting_standard text DEFAULT 'french_pcga'
  CHECK (accounting_standard IN ('french_pcga', 'ias_ifrs', 'french_pcg'));

UPDATE company_settings SET
  vat_method = 'debit'
WHERE tenant_id = '00000000-0000-0000-0000-000000000001';

-- ============================================
-- Phase 1.15: VAT on deposits
-- ============================================
UPDATE vat_returns SET
  deposits_vat_collected = 1200.00,
  deposits_vat_deductible = 800.00
WHERE tenant_id = '00000000-0000-0000-0000-000000000001'
  AND period_start = '2024-01-01' AND period_end = '2024-03-31';

-- ============================================
-- Phase 1.16: TVS (Company Vehicle Tax)
-- ============================================
INSERT INTO tvs_declarations (id, tenant_id, fiscal_year, vehicle_registration, vehicle_type, co2_emissions, first_registration_date, amount_co2, amount_age, amount_total, status, filed_at, created_at, updated_at) VALUES
  ('16000001-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 2024, 'AB-123-CD', 'berline', 145, '2022-03-15', 500.00, 0.00, 500.00, 'filed', '2024-01-15T09:00:00Z', now(), now()),
  ('16000002-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 2024, 'EF-456-GH', 'utilitaire', 195, '2020-06-01', 1000.00, 250.00, 1250.00, 'draft', NULL, now(), now()),
  ('16000003-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 2024, 'IJ-789-KL', 'suv', 210, '2019-01-10', 1100.00, 500.00, 1600.00, 'paid', '2024-02-01T14:00:00Z', now(), now())
ON CONFLICT (id) DO NOTHING;

-- ============================================
-- Phase 1.17: RGPD — company_settings
-- ============================================
UPDATE company_settings SET
  gdpr_enabled = true,
  gdpr_retention_years = 10,
  gdpr_anonymize_after = true
WHERE tenant_id = '00000000-0000-0000-0000-000000000001';

-- ============================================
-- Phase 1.18: IAS-IFRS — company_settings
-- ============================================
UPDATE company_settings SET
  accounting_standard = 'french_pcga'
WHERE tenant_id = '00000000-0000-0000-0000-000000000001';

-- ============================================
-- Phase 1.19: Progressive balance — uses journal entries
-- (Relies on existing journal_lines data)
-- ============================================

-- ============================================
-- Phase 1.20: Journal access control
-- ============================================
ALTER TABLE journals ADD COLUMN IF NOT EXISTS access_level text DEFAULT 'all'
  CHECK (access_level IN ('all', 'restricted', 'admin_only'));

UPDATE journals SET
  access_level = 'all'
WHERE tenant_id = '00000000-0000-0000-0000-000000000001';

UPDATE journals SET
  access_level = 'restricted'
WHERE tenant_id = '00000000-0000-0000-0000-000000000001'
  AND code = 'AN';

-- ============================================
-- Phase 1.21: 10 fiscal years
-- ============================================
INSERT INTO fiscal_years (id, tenant_id, code, start_date, end_date, status, created_at) VALUES
  ('17000001-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'EX2015', '2015-01-01', '2015-12-31', 'closed', now()),
  ('17000002-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'EX2016', '2016-01-01', '2016-12-31', 'closed', now()),
  ('17000003-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'EX2017', '2017-01-01', '2017-12-31', 'closed', now()),
  ('17000004-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'EX2018', '2018-01-01', '2018-12-31', 'closed', now()),
  ('17000005-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'EX2019', '2019-01-01', '2019-12-31', 'closed', now()),
  ('17000006-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'EX2020', '2020-01-01', '2020-12-31', 'closed', now()),
  ('17000007-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'EX2021', '2021-01-01', '2021-12-31', 'closed', now()),
  ('17000008-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'EX2022', '2022-01-01', '2022-12-31', 'closed', now()),
  ('17000009-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'EX2023', '2023-01-01', '2023-12-31', 'closed', now()),
  ('1700000a-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'EX2024', '2024-01-01', '2024-12-31', 'open', now())
ON CONFLICT (id) DO NOTHING;

-- ============================================
-- Phase 1.22: Fiscal backups
-- ============================================
CREATE TABLE IF NOT EXISTS fiscal_backups (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  fiscal_year_id uuid,
  backup_type text NOT NULL DEFAULT 'manual',
  status text NOT NULL DEFAULT 'pending',
  file_url text,
  file_size bigint,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_fiscal_backups_tenant ON fiscal_backups(tenant_id);
CREATE INDEX IF NOT EXISTS idx_fiscal_backups_fiscal_year ON fiscal_backups(fiscal_year_id);

INSERT INTO fiscal_backups (id, tenant_id, fiscal_year_id, backup_type, status, file_url, file_size, created_by, created_at) VALUES
  ('18000001-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', '17000009-0000-0000-0000-000000000001', 'manual', 'completed', 'https://storage.example.com/backup-2023.zip', 1048576, NULL, '2024-01-15T10:00:00Z'),
  ('18000002-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', '1700000a-0000-0000-0000-000000000001', 'automatic', 'completed', 'https://storage.example.com/backup-2024-q1.zip', 2097152, NULL, '2024-04-01T02:00:00Z'),
  ('18000003-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', NULL, 'manual', 'pending', NULL, NULL, NULL, now())
ON CONFLICT (id) DO NOTHING;

-- ============================================
-- SUMMARY
-- ============================================
-- 3 recurring entries
-- 2 regularization entries (CCA/PCA)
-- 2 currency revaluations
-- 3 collection reminders
-- 3 analytic plans
-- 2 distribution grills
-- 3 bank reconciliation rules
-- 2 bank statement imports
-- 2 EDI-TVA declarations (in vat_returns)
-- 3 TVS declarations
-- 10 fiscal years (2015-2024)
-- 3 fiscal backups
-- company_settings updated with VAT method, GDPR, IFRS
-- journals updated with access levels
