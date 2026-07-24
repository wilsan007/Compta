-- ============================================
-- SAGE 100 ACCOUNTING FEATURES - PHASE 6
-- ============================================
-- Tables for missing Sage 100 Comptabilité features:
-- 1. Saisie par lot (batch entries)
-- 2. Libellé automatique (auto label rules)
-- 3. Extourne automatique (reversal log)
-- 4. Reports à-nouveaux (carry forward log)
-- 5. Pré-lettrage (pre-lettrage proposals)
-- 6. Écarts de lettrage (lettrage differences)
-- 7. Contrôles comptables (accounting control runs)
-- 8. Contrôle de caisse (cash control sessions)
-- 9. Attestation FEC (FEC attestations)
-- 10. Multi-RIB par tiers (tier RIBs)
-- 11. IAS/IFRS adjustments
-- 12. Télépaiements (tax payments)
-- 13. Modèles d'édition personnalisés (custom report templates)
-- 14. Impressions différées (deferred printing)
-- 15. Protection journaux par droits (journal access rights)
-- 16. TVA sur encaissements (VAT on collections)
-- ============================================

-- 1. Auto Label Rules (Libellé automatique)
CREATE TABLE IF NOT EXISTS auto_label_rules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  name text NOT NULL,
  description text,
  journal_code text,
  account_code text,
  account_prefix text,
  label_pattern text NOT NULL,
  priority int NOT NULL DEFAULT 100,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_auto_label_rules_tenant ON auto_label_rules(tenant_id);
CREATE INDEX IF NOT EXISTS idx_auto_label_rules_active ON auto_label_rules(active);
ALTER TABLE auto_label_rules ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_select_auto_label_rules ON auto_label_rules;
DROP POLICY IF EXISTS tenant_insert_auto_label_rules ON auto_label_rules;
DROP POLICY IF EXISTS tenant_update_auto_label_rules ON auto_label_rules;
DROP POLICY IF EXISTS tenant_delete_auto_label_rules ON auto_label_rules;
CREATE POLICY tenant_select_auto_label_rules ON auto_label_rules FOR SELECT USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_insert_auto_label_rules ON auto_label_rules FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
CREATE POLICY tenant_update_auto_label_rules ON auto_label_rules FOR UPDATE USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_delete_auto_label_rules ON auto_label_rules FOR DELETE USING (tenant_id = current_tenant_id());

-- 2. Extourne Log (Extourne automatique)
CREATE TABLE IF NOT EXISTS extourne_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  original_entry_id uuid NOT NULL,
  extourne_entry_id uuid NOT NULL,
  extourne_date date NOT NULL,
  reason text,
  journal_code text,
  total_debit numeric(14,2) NOT NULL DEFAULT 0,
  total_credit numeric(14,2) NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'completed',
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_extourne_log_tenant ON extourne_log(tenant_id);
CREATE INDEX IF NOT EXISTS idx_extourne_log_original ON extourne_log(original_entry_id);
ALTER TABLE extourne_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_select_extourne_log ON extourne_log;
DROP POLICY IF EXISTS tenant_insert_extourne_log ON extourne_log;
CREATE POLICY tenant_select_extourne_log ON extourne_log FOR SELECT USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_insert_extourne_log ON extourne_log FOR INSERT WITH CHECK (tenant_id = current_tenant_id());

-- 3. Carry Forward Log (Reports à-nouveaux)
CREATE TABLE IF NOT EXISTS carry_forward_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  source_fiscal_year_id uuid NOT NULL,
  target_fiscal_year_id uuid NOT NULL,
  carry_forward_date date NOT NULL,
  total_debit numeric(14,2) NOT NULL DEFAULT 0,
  total_credit numeric(14,2) NOT NULL DEFAULT 0,
  entry_count int NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'completed',
  journal_entry_id uuid,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_carry_forward_log_tenant ON carry_forward_log(tenant_id);
ALTER TABLE carry_forward_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_select_carry_forward_log ON carry_forward_log;
DROP POLICY IF EXISTS tenant_insert_carry_forward_log ON carry_forward_log;
CREATE POLICY tenant_select_carry_forward_log ON carry_forward_log FOR SELECT USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_insert_carry_forward_log ON carry_forward_log FOR INSERT WITH CHECK (tenant_id = current_tenant_id());

-- 4. Lettrage Differences (Écarts de lettrage)
CREATE TABLE IF NOT EXISTS lettrage_differences (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  third_party_code text NOT NULL,
  lettrage_code text NOT NULL,
  line_id_1 uuid NOT NULL,
  line_id_2 uuid NOT NULL,
  debit_amount numeric(14,2) NOT NULL DEFAULT 0,
  credit_amount numeric(14,2) NOT NULL DEFAULT 0,
  difference numeric(14,2) NOT NULL DEFAULT 0,
  difference_account text,
  generated_entry_id uuid,
  status text NOT NULL DEFAULT 'pending',
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_lettrage_diff_tenant ON lettrage_differences(tenant_id);
ALTER TABLE lettrage_differences ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_select_lettrage_diff ON lettrage_differences;
DROP POLICY IF EXISTS tenant_insert_lettrage_diff ON lettrage_differences;
DROP POLICY IF EXISTS tenant_update_lettrage_diff ON lettrage_differences;
DROP POLICY IF EXISTS tenant_delete_lettrage_diff ON lettrage_differences;
CREATE POLICY tenant_select_lettrage_diff ON lettrage_differences FOR SELECT USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_insert_lettrage_diff ON lettrage_differences FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
CREATE POLICY tenant_update_lettrage_diff ON lettrage_differences FOR UPDATE USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_delete_lettrage_diff ON lettrage_differences FOR DELETE USING (tenant_id = current_tenant_id());

-- 5. Accounting Control Runs (Contrôles comptables)
CREATE TABLE IF NOT EXISTS accounting_control_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  control_type text NOT NULL,
  fiscal_year_id uuid,
  period_id uuid,
  run_date timestamptz NOT NULL DEFAULT now(),
  status text NOT NULL DEFAULT 'completed',
  total_checks int NOT NULL DEFAULT 0,
  errors_found int NOT NULL DEFAULT 0,
  warnings_found int NOT NULL DEFAULT 0,
  details jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_acct_control_runs_tenant ON accounting_control_runs(tenant_id);
CREATE INDEX IF NOT EXISTS idx_acct_control_runs_type ON accounting_control_runs(control_type);
ALTER TABLE accounting_control_runs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_select_acct_control ON accounting_control_runs;
DROP POLICY IF EXISTS tenant_insert_acct_control ON accounting_control_runs;
CREATE POLICY tenant_select_acct_control ON accounting_control_runs FOR SELECT USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_insert_acct_control ON accounting_control_runs FOR INSERT WITH CHECK (tenant_id = current_tenant_id());

-- 6. Cash Control Sessions (Contrôle de caisse)
CREATE TABLE IF NOT EXISTS cash_control_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  session_number text NOT NULL,
  journal_code text NOT NULL,
  session_date date NOT NULL,
  theoretical_balance numeric(14,2) NOT NULL DEFAULT 0,
  counted_balance numeric(14,2) NOT NULL DEFAULT 0,
  difference numeric(14,2) NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'open',
  counted_by text,
  validated_by text,
  validated_at timestamptz,
  notes text,
  details jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_cash_control_tenant ON cash_control_sessions(tenant_id);
CREATE INDEX IF NOT EXISTS idx_cash_control_date ON cash_control_sessions(session_date);
ALTER TABLE cash_control_sessions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_select_cash_control ON cash_control_sessions;
DROP POLICY IF EXISTS tenant_insert_cash_control ON cash_control_sessions;
DROP POLICY IF EXISTS tenant_update_cash_control ON cash_control_sessions;
DROP POLICY IF EXISTS tenant_delete_cash_control ON cash_control_sessions;
CREATE POLICY tenant_select_cash_control ON cash_control_sessions FOR SELECT USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_insert_cash_control ON cash_control_sessions FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
CREATE POLICY tenant_update_cash_control ON cash_control_sessions FOR UPDATE USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_delete_cash_control ON cash_control_sessions FOR DELETE USING (tenant_id = current_tenant_id());

-- 7. FEC Attestations (Attestation FEC)
CREATE TABLE IF NOT EXISTS fec_attestations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  fiscal_year_id uuid NOT NULL,
  attestation_number text NOT NULL,
  attestation_date date NOT NULL,
  fec_type text NOT NULL DEFAULT 'definitive',
  entry_count int NOT NULL DEFAULT 0,
  total_debit numeric(14,2) NOT NULL DEFAULT 0,
  total_credit numeric(14,2) NOT NULL DEFAULT 0,
  file_name text,
  file_content text,
  status text NOT NULL DEFAULT 'generated',
  generated_by text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_fec_attest_tenant ON fec_attestations(tenant_id);
ALTER TABLE fec_attestations ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_select_fec_attest ON fec_attestations;
DROP POLICY IF EXISTS tenant_insert_fec_attest ON fec_attestations;
DROP POLICY IF EXISTS tenant_delete_fec_attest ON fec_attestations;
CREATE POLICY tenant_select_fec_attest ON fec_attestations FOR SELECT USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_insert_fec_attest ON fec_attestations FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
CREATE POLICY tenant_delete_fec_attest ON fec_attestations FOR DELETE USING (tenant_id = current_tenant_id());

-- 8. Tier RIBs (Multi-RIB par tiers)
CREATE TABLE IF NOT EXISTS tier_ribs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  third_party_account_id uuid NOT NULL,
  rib_label text NOT NULL,
  iban text NOT NULL,
  bic text,
  bank_name text,
  bank_code text,
  branch_code text,
  account_number text,
  key text,
  is_default boolean NOT NULL DEFAULT false,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_tier_ribs_tenant ON tier_ribs(tenant_id);
CREATE INDEX IF NOT EXISTS idx_tier_ribs_tp ON tier_ribs(third_party_account_id);
ALTER TABLE tier_ribs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_select_tier_ribs ON tier_ribs;
DROP POLICY IF EXISTS tenant_insert_tier_ribs ON tier_ribs;
DROP POLICY IF EXISTS tenant_update_tier_ribs ON tier_ribs;
DROP POLICY IF EXISTS tenant_delete_tier_ribs ON tier_ribs;
CREATE POLICY tenant_select_tier_ribs ON tier_ribs FOR SELECT USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_insert_tier_ribs ON tier_ribs FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
CREATE POLICY tenant_update_tier_ribs ON tier_ribs FOR UPDATE USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_delete_tier_ribs ON tier_ribs FOR DELETE USING (tenant_id = current_tenant_id());

-- 9. IFRS Adjustments (IAS/IFRS)
CREATE TABLE IF NOT EXISTS ifrs_adjustments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  fiscal_year_id uuid,
  adjustment_type text NOT NULL,
  account_code text NOT NULL,
  counter_account_code text NOT NULL,
  description text NOT NULL,
  amount numeric(14,2) NOT NULL DEFAULT 0,
  adjustment_date date NOT NULL,
  ifrs_standard text,
  journal_entry_id uuid,
  status text NOT NULL DEFAULT 'draft',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_ifrs_adj_tenant ON ifrs_adjustments(tenant_id);
ALTER TABLE ifrs_adjustments ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_select_ifrs_adj ON ifrs_adjustments;
DROP POLICY IF EXISTS tenant_insert_ifrs_adj ON ifrs_adjustments;
DROP POLICY IF EXISTS tenant_update_ifrs_adj ON ifrs_adjustments;
DROP POLICY IF EXISTS tenant_delete_ifrs_adj ON ifrs_adjustments;
CREATE POLICY tenant_select_ifrs_adj ON ifrs_adjustments FOR SELECT USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_insert_ifrs_adj ON ifrs_adjustments FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
CREATE POLICY tenant_update_ifrs_adj ON ifrs_adjustments FOR UPDATE USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_delete_ifrs_adj ON ifrs_adjustments FOR DELETE USING (tenant_id = current_tenant_id());

-- 10. Tax Payments (Télépaiements)
CREATE TABLE IF NOT EXISTS tax_payments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  payment_number text NOT NULL,
  tax_type text NOT NULL,
  period_label text NOT NULL,
  period_start date NOT NULL,
  period_end date NOT NULL,
  amount numeric(14,2) NOT NULL DEFAULT 0,
  payment_date date NOT NULL,
  payment_method text NOT NULL DEFAULT 'telepayment',
  bank_account_id uuid,
  status text NOT NULL DEFAULT 'draft',
  confirmation_number text,
  journal_entry_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_tax_payments_tenant ON tax_payments(tenant_id);
CREATE INDEX IF NOT EXISTS idx_tax_payments_type ON tax_payments(tax_type);
ALTER TABLE tax_payments ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_select_tax_payments ON tax_payments;
DROP POLICY IF EXISTS tenant_insert_tax_payments ON tax_payments;
DROP POLICY IF EXISTS tenant_update_tax_payments ON tax_payments;
DROP POLICY IF EXISTS tenant_delete_tax_payments ON tax_payments;
CREATE POLICY tenant_select_tax_payments ON tax_payments FOR SELECT USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_insert_tax_payments ON tax_payments FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
CREATE POLICY tenant_update_tax_payments ON tax_payments FOR UPDATE USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_delete_tax_payments ON tax_payments FOR DELETE USING (tenant_id = current_tenant_id());

-- 11. Custom Report Templates (Modèles d'édition personnalisés)
CREATE TABLE IF NOT EXISTS custom_report_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  name text NOT NULL,
  description text,
  report_type text NOT NULL,
  category text NOT NULL DEFAULT 'accounting',
  columns jsonb NOT NULL DEFAULT '[]'::jsonb,
  filters jsonb NOT NULL DEFAULT '{}'::jsonb,
  group_by text,
  sort_by text,
  sort_order text DEFAULT 'asc',
  page_orientation text DEFAULT 'portrait',
  page_size text DEFAULT 'A4',
  header_text text,
  footer_text text,
  show_logo boolean NOT NULL DEFAULT true,
  show_date boolean NOT NULL DEFAULT true,
  show_page_numbers boolean NOT NULL DEFAULT true,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_custom_reports_tenant ON custom_report_templates(tenant_id);
CREATE INDEX IF NOT EXISTS idx_custom_reports_type ON custom_report_templates(report_type);
ALTER TABLE custom_report_templates ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_select_custom_reports ON custom_report_templates;
DROP POLICY IF EXISTS tenant_insert_custom_reports ON custom_report_templates;
DROP POLICY IF EXISTS tenant_update_custom_reports ON custom_report_templates;
DROP POLICY IF EXISTS tenant_delete_custom_reports ON custom_report_templates;
CREATE POLICY tenant_select_custom_reports ON custom_report_templates FOR SELECT USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_insert_custom_reports ON custom_report_templates FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
CREATE POLICY tenant_update_custom_reports ON custom_report_templates FOR UPDATE USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_delete_custom_reports ON custom_report_templates FOR DELETE USING (tenant_id = current_tenant_id());

-- 12. Deferred Printing Jobs (Impressions différées)
CREATE TABLE IF NOT EXISTS deferred_printing_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  job_name text NOT NULL,
  report_type text NOT NULL,
  parameters jsonb NOT NULL DEFAULT '{}'::jsonb,
  scheduled_date timestamptz NOT NULL,
  status text NOT NULL DEFAULT 'pending',
  output_format text NOT NULL DEFAULT 'pdf',
  output_data text,
  generated_at timestamptz,
  generated_by text,
  error_message text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_deferred_print_tenant ON deferred_printing_jobs(tenant_id);
CREATE INDEX IF NOT EXISTS idx_deferred_print_status ON deferred_printing_jobs(status);
CREATE INDEX IF NOT EXISTS idx_deferred_print_scheduled ON deferred_printing_jobs(scheduled_date);
ALTER TABLE deferred_printing_jobs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_select_deferred_print ON deferred_printing_jobs;
DROP POLICY IF EXISTS tenant_insert_deferred_print ON deferred_printing_jobs;
DROP POLICY IF EXISTS tenant_update_deferred_print ON deferred_printing_jobs;
DROP POLICY IF EXISTS tenant_delete_deferred_print ON deferred_printing_jobs;
CREATE POLICY tenant_select_deferred_print ON deferred_printing_jobs FOR SELECT USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_insert_deferred_print ON deferred_printing_jobs FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
CREATE POLICY tenant_update_deferred_print ON deferred_printing_jobs FOR UPDATE USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_delete_deferred_print ON deferred_printing_jobs FOR DELETE USING (tenant_id = current_tenant_id());

-- 13. Journal Access Rights (Protection journaux par droits)
CREATE TABLE IF NOT EXISTS journal_access_rights (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  user_id uuid NOT NULL,
  journal_code text NOT NULL,
  can_view boolean NOT NULL DEFAULT true,
  can_create boolean NOT NULL DEFAULT false,
  can_edit boolean NOT NULL DEFAULT false,
  can_delete boolean NOT NULL DEFAULT false,
  can_close boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(tenant_id, user_id, journal_code)
);
CREATE INDEX IF NOT EXISTS idx_journal_access_tenant ON journal_access_rights(tenant_id);
CREATE INDEX IF NOT EXISTS idx_journal_access_user ON journal_access_rights(user_id);
ALTER TABLE journal_access_rights ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_select_journal_access ON journal_access_rights;
DROP POLICY IF EXISTS tenant_insert_journal_access ON journal_access_rights;
DROP POLICY IF EXISTS tenant_update_journal_access ON journal_access_rights;
DROP POLICY IF EXISTS tenant_delete_journal_access ON journal_access_rights;
CREATE POLICY tenant_select_journal_access ON journal_access_rights FOR SELECT USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_insert_journal_access ON journal_access_rights FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
CREATE POLICY tenant_update_journal_access ON journal_access_rights FOR UPDATE USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_delete_journal_access ON journal_access_rights FOR DELETE USING (tenant_id = current_tenant_id());

-- 14. VAT on Collections (TVA sur encaissements)
CREATE TABLE IF NOT EXISTS vat_on_collections (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  fiscal_year_id uuid,
  period_label text NOT NULL,
  period_start date NOT NULL,
  period_end date NOT NULL,
  vat_base numeric(14,2) NOT NULL DEFAULT 0,
  vat_rate numeric(5,2) NOT NULL DEFAULT 0,
  vat_amount numeric(14,2) NOT NULL DEFAULT 0,
  collected_amount numeric(14,2) NOT NULL DEFAULT 0,
  uncollected_amount numeric(14,2) NOT NULL DEFAULT 0,
  vat_collected numeric(14,2) NOT NULL DEFAULT 0,
  vat_uncollected numeric(14,2) NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'draft',
  journal_entry_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_vat_collections_tenant ON vat_on_collections(tenant_id);
ALTER TABLE vat_on_collections ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_select_vat_collections ON vat_on_collections;
DROP POLICY IF EXISTS tenant_insert_vat_collections ON vat_on_collections;
DROP POLICY IF EXISTS tenant_update_vat_collections ON vat_on_collections;
DROP POLICY IF EXISTS tenant_delete_vat_collections ON vat_on_collections;
CREATE POLICY tenant_select_vat_collections ON vat_on_collections FOR SELECT USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_insert_vat_collections ON vat_on_collections FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
CREATE POLICY tenant_update_vat_collections ON vat_on_collections FOR UPDATE USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_delete_vat_collections ON vat_on_collections FOR DELETE USING (tenant_id = current_tenant_id());

-- 15. Batch Entry Sessions (Saisie par lot)
CREATE TABLE IF NOT EXISTS batch_entry_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  session_name text NOT NULL,
  journal_code text NOT NULL,
  session_date date NOT NULL,
  entry_count int NOT NULL DEFAULT 0,
  total_debit numeric(14,2) NOT NULL DEFAULT 0,
  total_credit numeric(14,2) NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'draft',
  validated_at timestamptz,
  validated_by text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_batch_entry_tenant ON batch_entry_sessions(tenant_id);
ALTER TABLE batch_entry_sessions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_select_batch_entry ON batch_entry_sessions;
DROP POLICY IF EXISTS tenant_insert_batch_entry ON batch_entry_sessions;
DROP POLICY IF EXISTS tenant_update_batch_entry ON batch_entry_sessions;
DROP POLICY IF EXISTS tenant_delete_batch_entry ON batch_entry_sessions;
CREATE POLICY tenant_select_batch_entry ON batch_entry_sessions FOR SELECT USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_insert_batch_entry ON batch_entry_sessions FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
CREATE POLICY tenant_update_batch_entry ON batch_entry_sessions FOR UPDATE USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_delete_batch_entry ON batch_entry_sessions FOR DELETE USING (tenant_id = current_tenant_id());
