-- Schéma exporté de Supabase (compta)
-- Généré automatiquement

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- ============================================
-- STUBS DE FONCTIONS (seront remplacés plus tard)
-- ============================================
CREATE OR REPLACE FUNCTION current_tenant_id() RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER AS $$ SELECT NULL::uuid $$;
CREATE OR REPLACE FUNCTION current_user_role() RETURNS text LANGUAGE sql STABLE SECURITY DEFINER AS $$ SELECT 'admin' $$;
CREATE OR REPLACE FUNCTION current_user_permissions() RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER AS $$ SELECT '{}'::jsonb $$;
CREATE OR REPLACE FUNCTION can_perform(p_table text, p_action text) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER AS $$ SELECT true $$;
CREATE OR REPLACE FUNCTION set_tenant_id() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$ BEGIN NEW.tenant_id := current_tenant_id(); RETURN NEW; END $$;
CREATE OR REPLACE FUNCTION update_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN NEW.updated_at = now(); RETURN NEW; END $$;
CREATE OR REPLACE FUNCTION update_updated_at_column() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN NEW.updated_at = now(); RETURN NEW; END $$;
CREATE OR REPLACE FUNCTION check_journal_entry_balance() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RETURN NEW; END $$;
CREATE OR REPLACE FUNCTION update_tax_grid_timestamp() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RETURN NEW; END $$;
CREATE OR REPLACE FUNCTION prevent_posted_entry_modification() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RETURN NEW; END $$;
CREATE OR REPLACE FUNCTION check_fiscal_period_open() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RETURN NEW; END $$;
-- Utilisées par les politiques module_documents ci-dessous, définies réellement par la migration 69
CREATE OR REPLACE FUNCTION current_module_role(p_module text) RETURNS text LANGUAGE sql STABLE SECURITY DEFINER AS $$ SELECT NULL::text $$;
CREATE OR REPLACE FUNCTION current_tenant_user_id() RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER AS $$ SELECT NULL::uuid $$;
CREATE OR REPLACE FUNCTION current_guest_permissions() RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER AS $$ SELECT '{}'::jsonb $$;
CREATE OR REPLACE FUNCTION has_module_access(p_module text) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER AS $$ SELECT false $$;
CREATE OR REPLACE FUNCTION has_module_permission(p_module text, p_permission text) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER AS $$ SELECT false $$;

-- ============================================
-- TABLES
-- ============================================
CREATE TABLE IF NOT EXISTS account_tag_mappings (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  tag_id uuid NOT NULL,
  entity_type text NOT NULL,
  entity_id text NOT NULL,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS account_tags (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  name text NOT NULL,
  applicability text NOT NULL DEFAULT 'accounts'::text,
  color text,
  country_code text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS accounting_control_runs (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  control_type text NOT NULL,
  fiscal_year_id uuid,
  period_id uuid,
  run_date timestamptz NOT NULL DEFAULT now(),
  status text NOT NULL DEFAULT 'completed'::text,
  total_checks integer NOT NULL DEFAULT 0,
  errors_found integer NOT NULL DEFAULT 0,
  warnings_found integer NOT NULL DEFAULT 0,
  details jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS analytic_distribution_lines (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  journal_line_id uuid,
  plan_id uuid,
  section_id uuid,
  percentage numeric NOT NULL,
  amount numeric,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS analytic_journal_codes (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  code text NOT NULL,
  name text NOT NULL,
  description text,
  type text DEFAULT 'analytic'::text,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS analytic_plans (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  code text NOT NULL,
  name text NOT NULL,
  description text,
  is_default boolean NOT NULL DEFAULT false,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS analytic_sections (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  code text NOT NULL,
  name text NOT NULL,
  parent_id uuid,
  axis text,
  level integer DEFAULT 1,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  tenant_id uuid NOT NULL,
  plan_id uuid
);

CREATE TABLE IF NOT EXISTS approval_workflows (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  name text NOT NULL,
  entity_type text NOT NULL,
  steps jsonb DEFAULT '[]'::jsonb,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS asset_batch_disposal_lines (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  batch_id uuid NOT NULL,
  asset_id uuid NOT NULL,
  disposal_type text,
  proceeds numeric DEFAULT 0,
  net_book_value numeric DEFAULT 0,
  gain_loss numeric DEFAULT 0,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS asset_batch_disposals (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  batch_number text NOT NULL,
  disposal_date date NOT NULL DEFAULT CURRENT_DATE,
  total_assets integer DEFAULT 0,
  total_proceeds numeric DEFAULT 0,
  total_gain_loss numeric DEFAULT 0,
  status text DEFAULT 'draft'::text,
  journal_entry_id uuid,
  notes text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS asset_depreciation_plans (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  asset_id uuid NOT NULL,
  plan_type text NOT NULL,
  depreciation_method text DEFAULT 'linear'::text,
  duration_months integer NOT NULL,
  residual_value numeric DEFAULT 0,
  annual_rate numeric,
  start_date date NOT NULL,
  end_date date,
  accumulated_depreciation numeric DEFAULT 0,
  current_net_value numeric DEFAULT 0,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS asset_depreciations (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  asset_id uuid NOT NULL,
  fiscal_year_code text,
  period integer NOT NULL,
  depreciation_type text NOT NULL,
  amount numeric NOT NULL DEFAULT 0,
  cumulative_amount numeric NOT NULL DEFAULT 0,
  net_book_value numeric NOT NULL DEFAULT 0,
  entry_number text,
  created_at timestamptz DEFAULT now(),
  tenant_id uuid NOT NULL
);

CREATE TABLE IF NOT EXISTS asset_documents (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  asset_id uuid NOT NULL,
  document_type text,
  file_url text NOT NULL,
  file_name text,
  description text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS asset_families (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  code text NOT NULL,
  name text NOT NULL,
  parent_id uuid,
  default_account text,
  default_depreciation_account text,
  default_duration_months integer,
  default_method text DEFAULT 'linear'::text,
  depreciation_rate numeric,
  description text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS asset_free_fields (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  asset_id uuid NOT NULL,
  field_key text NOT NULL,
  field_value text,
  field_type text DEFAULT 'text'::text,
  field_category text DEFAULT 'free'::text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS asset_revaluations (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  asset_id uuid NOT NULL,
  revaluation_date date NOT NULL,
  old_value numeric NOT NULL DEFAULT 0,
  new_value numeric NOT NULL DEFAULT 0,
  difference numeric DEFAULT 0,
  reason text,
  journal_entry_id uuid,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS asset_split_components (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  split_id uuid NOT NULL,
  new_asset_id uuid NOT NULL,
  allocated_value numeric NOT NULL DEFAULT 0,
  allocated_percentage numeric DEFAULT 0,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS asset_splits (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  original_asset_id uuid NOT NULL,
  split_date date NOT NULL DEFAULT CURRENT_DATE,
  reason text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS at_rates (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  employee_id uuid NOT NULL,
  rate numeric NOT NULL DEFAULT 0,
  bonus_malus_rate numeric DEFAULT 0,
  effective_date date NOT NULL,
  expiry_date date,
  risk_category text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS audit_log (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  user_id uuid,
  action text NOT NULL,
  entity_type text NOT NULL,
  entity_id uuid,
  entity_number text,
  description text,
  metadata jsonb,
  ip_address text,
  created_at timestamptz DEFAULT now(),
  tenant_id uuid NOT NULL
);

CREATE TABLE IF NOT EXISTS auto_label_rules (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  name text NOT NULL,
  description text,
  journal_code text,
  account_code text,
  account_prefix text,
  label_pattern text NOT NULL,
  priority integer NOT NULL DEFAULT 100,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS bank_accounts (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  name text NOT NULL,
  type text NOT NULL,
  account_number text,
  sort_code text,
  balance numeric DEFAULT 0,
  currency text DEFAULT 'EUR'::text,
  bank_name text,
  last_reconciled date,
  connected boolean DEFAULT false,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  tenant_id uuid NOT NULL,
  statement_balance numeric DEFAULT 0,
  statement_balance_date date,
  calculated_balance numeric DEFAULT 0,
  reconciliation_diff numeric DEFAULT 0
);

CREATE TABLE IF NOT EXISTS bank_connections (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  provider text NOT NULL,
  provider_connection_id text,
  bank_account_id uuid,
  status text DEFAULT 'pending'::text,
  last_sync_at timestamptz,
  sync_frequency text DEFAULT 'daily'::text,
  next_sync_at timestamptz,
  error_message text,
  metadata jsonb,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS bank_reconciliation_rules (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  name text NOT NULL,
  afb_code text NOT NULL,
  description text,
  match_pattern text,
  counterpart_account text,
  journal_code text,
  priority integer NOT NULL DEFAULT 100,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS bank_rules (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  name text NOT NULL,
  condition_field text NOT NULL,
  condition_operator text NOT NULL,
  condition_value text NOT NULL,
  action_category text NOT NULL,
  action_account_code text,
  action_vat_rate numeric,
  priority integer DEFAULT 0,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  tenant_id uuid NOT NULL
);

CREATE TABLE IF NOT EXISTS bank_statement_imports (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  bank_account_id uuid,
  filename text NOT NULL,
  format text NOT NULL,
  file_size bigint,
  status text NOT NULL DEFAULT 'pending'::text,
  imported_count integer DEFAULT 0,
  error_message text,
  imported_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS bank_statement_templates (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  bank_name text NOT NULL,
  account_number_pattern text,
  date_pattern text NOT NULL,
  amount_pattern text NOT NULL,
  description_pattern text,
  reference_pattern text,
  debit_indicator text,
  credit_indicator text,
  period_pattern text,
  balance_pattern text,
  currency_pattern text,
  skip_lines_pattern text,
  sample_text text,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  bank_id uuid,
  validation_status text NOT NULL DEFAULT 'pending'::text,
  consecutive_successes integer NOT NULL DEFAULT 0,
  validation_count integer NOT NULL DEFAULT 0,
  last_validated_at timestamptz,
  last_correction_notes text
);

CREATE TABLE IF NOT EXISTS bank_transactions (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  account_id uuid,
  date date NOT NULL DEFAULT CURRENT_DATE,
  description text NOT NULL,
  reference text,
  type text NOT NULL,
  amount numeric NOT NULL DEFAULT 0,
  category text,
  reconciled boolean DEFAULT false,
  matched boolean DEFAULT false,
  invoice_id uuid,
  purchase_invoice_id uuid,
  created_at timestamptz DEFAULT now(),
  tenant_id uuid NOT NULL,
  afb_code text,
  reconciled_entry_id uuid,
  reconciled_at timestamptz,
  original_currency text,
  original_amount numeric,
  exchange_rate numeric DEFAULT 1.0,
  exchange_gain_loss numeric DEFAULT 0,
  source text DEFAULT 'manual'::text
);

CREATE TABLE IF NOT EXISTS banks (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  name text NOT NULL,
  swift_code text,
  country text,
  logo_url text,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS batch_entry_sessions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  session_name text NOT NULL,
  journal_code text NOT NULL,
  session_date date NOT NULL,
  entry_count integer NOT NULL DEFAULT 0,
  total_debit numeric NOT NULL DEFAULT 0,
  total_credit numeric NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'draft'::text,
  validated_at timestamptz,
  validated_by text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS bdes_indicators (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  year integer NOT NULL,
  category text NOT NULL,
  indicator_name text NOT NULL,
  indicator_value numeric,
  indicator_unit text,
  breakdown jsonb DEFAULT '{}'::jsonb,
  target_value numeric,
  previous_year_value numeric,
  notes text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS bom_lines (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  bom_id uuid,
  product_id uuid NOT NULL,
  quantity numeric NOT NULL DEFAULT 1,
  unit_cost numeric DEFAULT 0,
  position integer DEFAULT 1,
  tenant_id uuid NOT NULL
);

CREATE TABLE IF NOT EXISTS boms (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  code text NOT NULL,
  name text NOT NULL,
  product_id uuid,
  quantity numeric DEFAULT 1,
  unit text DEFAULT 'unit'::text,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  tenant_id uuid NOT NULL,
  routing_id uuid,
  bom_type text DEFAULT 'standard'::text
);

CREATE TABLE IF NOT EXISTS budget_commitments (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  description text NOT NULL,
  account_code text NOT NULL,
  fiscal_year_id uuid,
  amount numeric NOT NULL DEFAULT 0,
  commitment_date date NOT NULL DEFAULT CURRENT_DATE,
  source_type text DEFAULT 'manual'::text,
  source_id uuid,
  status text NOT NULL DEFAULT 'active'::text,
  supplier_id uuid,
  notes text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  tenant_id uuid NOT NULL
);

CREATE TABLE IF NOT EXISTS budgets (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  name text NOT NULL,
  fiscal_year_id uuid,
  account_code text,
  analytic_section_id uuid,
  period_1 numeric DEFAULT 0,
  period_2 numeric DEFAULT 0,
  period_3 numeric DEFAULT 0,
  period_4 numeric DEFAULT 0,
  period_5 numeric DEFAULT 0,
  period_6 numeric DEFAULT 0,
  period_7 numeric DEFAULT 0,
  period_8 numeric DEFAULT 0,
  period_9 numeric DEFAULT 0,
  period_10 numeric DEFAULT 0,
  period_11 numeric DEFAULT 0,
  period_12 numeric DEFAULT 0,
  created_at timestamptz DEFAULT now(),
  tenant_id uuid NOT NULL
);

CREATE TABLE IF NOT EXISTS career_history (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  employee_id uuid NOT NULL,
  position text,
  department text,
  salary numeric,
  start_date date NOT NULL,
  end_date date,
  change_type text,
  notes text,
  created_at timestamptz DEFAULT now(),
  event_type text,
  event_date date,
  previous_position text,
  new_position text,
  previous_department text,
  new_department text,
  previous_salary numeric,
  new_salary numeric,
  previous_manager_id uuid,
  new_manager_id uuid,
  previous_collective_agreement_id uuid,
  new_collective_agreement_id uuid,
  reason text,
  documents jsonb DEFAULT '[]'::jsonb
);

CREATE TABLE IF NOT EXISTS carry_forward_log (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  source_fiscal_year_id uuid NOT NULL,
  target_fiscal_year_id uuid NOT NULL,
  carry_forward_date date NOT NULL,
  total_debit numeric NOT NULL DEFAULT 0,
  total_credit numeric NOT NULL DEFAULT 0,
  entry_count integer NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'completed'::text,
  journal_entry_id uuid,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS cash_control_sessions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  session_number text NOT NULL,
  journal_code text NOT NULL,
  session_date date NOT NULL,
  theoretical_balance numeric NOT NULL DEFAULT 0,
  counted_balance numeric NOT NULL DEFAULT 0,
  difference numeric NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'open'::text,
  counted_by text,
  validated_by text,
  validated_at timestamptz,
  notes text,
  details jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS chart_account_templates (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  pack_code text NOT NULL,
  code text NOT NULL,
  name text NOT NULL,
  type text NOT NULL,
  vat_rate text,
  parent_code text,
  sort_order integer DEFAULT 0,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS chart_accounts (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  code text NOT NULL,
  name text NOT NULL,
  type text NOT NULL,
  balance numeric DEFAULT 0,
  vat_rate text,
  description text,
  parent_id uuid,
  created_at timestamptz DEFAULT now(),
  tenant_id uuid NOT NULL,
  racine text,
  classe text,
  nature text,
  code_taxe_default text,
  saisie_analytic boolean DEFAULT false,
  saisie_echeance boolean DEFAULT false,
  saisie_tiers boolean DEFAULT false,
  debit_n1 numeric DEFAULT 0,
  credit_n1 numeric DEFAULT 0,
  current_debit numeric DEFAULT 0,
  current_credit numeric DEFAULT 0,
  current_balance numeric DEFAULT 0,
  currency_code text,
  reconcile boolean DEFAULT false,
  deprecated boolean DEFAULT false,
  account_type text DEFAULT 'asset_current'::text
);

CREATE TABLE IF NOT EXISTS check_books (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  bank_account_id uuid,
  journal_id uuid,
  name text NOT NULL,
  first_check_number text NOT NULL,
  last_check_number text NOT NULL,
  next_check_number text NOT NULL,
  status text DEFAULT 'active'::text,
  issued_count integer DEFAULT 0,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS checks (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  check_book_id uuid,
  check_number text NOT NULL,
  amount numeric NOT NULL,
  payee text NOT NULL,
  issue_date date NOT NULL,
  due_date date,
  status text DEFAULT 'draft'::text,
  journal_entry_id uuid,
  payment_id uuid,
  notes text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS cice_config (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  year integer NOT NULL,
  smic_threshold numeric DEFAULT 2.5,
  rate numeric DEFAULT 6,
  eligible_salary_cap numeric,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS collection_reminders (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  number text NOT NULL,
  customer_id uuid,
  third_party_id uuid,
  invoice_id uuid,
  reminder_level integer NOT NULL DEFAULT 1,
  reminder_date date NOT NULL DEFAULT CURRENT_DATE,
  due_date date,
  amount numeric NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'sent'::text,
  notes text,
  created_at timestamptz DEFAULT now(),
  tenant_id uuid NOT NULL,
  payment_link_token text,
  payment_link_url text,
  payment_link_expires_at timestamptz,
  payment_status text DEFAULT 'unpaid'::text,
  reminder_level_id uuid,
  dispute_id uuid,
  promise_id uuid
);

CREATE TABLE IF NOT EXISTS compaction_logs (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  fiscal_year_id uuid,
  entries_compacted integer NOT NULL DEFAULT 0,
  lines_compacted integer NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'completed'::text,
  compacted_by text,
  compacted_at timestamptz NOT NULL DEFAULT now(),
  details jsonb
);

CREATE TABLE IF NOT EXISTS company_settings (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  name text NOT NULL,
  legal_name text,
  vat_number text,
  siret text,
  address text,
  city text,
  postal_code text,
  country text DEFAULT 'France'::text,
  currency text DEFAULT 'EUR'::text,
  fiscal_year_start text DEFAULT '01-01'::text,
  email text,
  phone text,
  website text,
  logo_url text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  tenant_id uuid NOT NULL,
  country_code text,
  legislation_pack_code text,
  vat_method text DEFAULT 'debit'::text,
  gdpr_enabled boolean DEFAULT false,
  gdpr_retention_years integer DEFAULT 10,
  gdpr_anonymize_after boolean DEFAULT true,
  accounting_standard text DEFAULT 'french_pcga'::text,
  saisie_negative boolean DEFAULT false,
  multi_currency boolean DEFAULT false,
  show_quantities boolean DEFAULT false,
  vat_regime text DEFAULT 'CA3'::text,
  vat_periodicity text DEFAULT 'monthly'::text
);

CREATE TABLE IF NOT EXISTS consolidated_treasury (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  consolidation_date date NOT NULL DEFAULT CURRENT_DATE,
  total_assets numeric DEFAULT 0,
  total_liabilities numeric DEFAULT 0,
  net_position numeric DEFAULT 0,
  details jsonb DEFAULT '[]'::jsonb,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS contracts (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  number text NOT NULL,
  employee_id uuid NOT NULL,
  contract_type text NOT NULL,
  start_date date NOT NULL,
  end_date date,
  position text,
  department text,
  monthly_salary numeric DEFAULT 0,
  hourly_rate numeric DEFAULT 0,
  weekly_hours numeric DEFAULT 35,
  trial_period_days integer DEFAULT 0,
  status text NOT NULL DEFAULT 'active'::text,
  notes text,
  created_at timestamptz DEFAULT now(),
  tenant_id uuid NOT NULL
);

CREATE TABLE IF NOT EXISTS corporate_tax_grid_lines (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  grid_id uuid NOT NULL,
  line_type text NOT NULL,
  label text NOT NULL,
  base_type text NOT NULL DEFAULT 'profit'::text,
  min_amount numeric DEFAULT 0,
  max_amount numeric,
  rate numeric DEFAULT 0,
  cap_amount numeric,
  fixed_amount numeric DEFAULT 0,
  sort_order integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS corporate_tax_grids (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  country_code text NOT NULL,
  tax_type text NOT NULL,
  name text NOT NULL,
  description text,
  effective_from date NOT NULL DEFAULT CURRENT_DATE,
  effective_to date,
  status text NOT NULL DEFAULT 'draft'::text,
  source text NOT NULL DEFAULT 'manual'::text,
  file_url text,
  is_default boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS cpf_accounts (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  employee_id uuid NOT NULL,
  balance_hours numeric DEFAULT 0,
  balance_amount numeric DEFAULT 0,
  history jsonb DEFAULT '[]'::jsonb,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  last_sync_date timestamptz
);

CREATE TABLE IF NOT EXISTS cpf_transactions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  employee_id uuid NOT NULL,
  transaction_type text NOT NULL,
  hours numeric DEFAULT 0,
  amount numeric DEFAULT 0,
  training_label text,
  training_start_date date,
  training_end_date date,
  training_provider text,
  notes text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS credit_lines (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  bank_account_id uuid,
  name text NOT NULL,
  type text DEFAULT 'credit_line'::text,
  limit_amount numeric NOT NULL DEFAULT 0,
  used_amount numeric DEFAULT 0,
  interest_rate numeric DEFAULT 0,
  start_date date,
  end_date date,
  monthly_payment numeric DEFAULT 0,
  status text DEFAULT 'active'::text,
  notes text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS credit_note_lines (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  credit_note_id uuid,
  description text NOT NULL,
  quantity numeric DEFAULT 1,
  unit_price numeric DEFAULT 0,
  vat_rate numeric DEFAULT 20.0,
  total numeric DEFAULT 0,
  vat_total numeric DEFAULT 0,
  line_order integer DEFAULT 0,
  created_at timestamptz DEFAULT now(),
  tenant_id uuid NOT NULL
);

CREATE TABLE IF NOT EXISTS credit_notes (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  number text NOT NULL,
  customer_id uuid,
  customer_name text,
  date date NOT NULL DEFAULT CURRENT_DATE,
  status text NOT NULL DEFAULT 'draft'::text,
  subtotal numeric DEFAULT 0,
  vat_total numeric DEFAULT 0,
  total numeric DEFAULT 0,
  reason text,
  invoice_id uuid,
  created_at timestamptz DEFAULT now(),
  tenant_id uuid NOT NULL,
  currency_code text DEFAULT 'EUR'::text,
  exchange_rate numeric DEFAULT 1.0,
  amount_untaxed_currency numeric,
  amount_tax_currency numeric,
  amount_total_currency numeric,
  source_invoice_id uuid
);

CREATE TABLE IF NOT EXISTS crm_activities (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  opportunity_id uuid,
  customer_id uuid,
  activity_type text NOT NULL,
  subject text NOT NULL,
  description text,
  scheduled_date timestamptz,
  completed_date timestamptz,
  duration_minutes integer,
  status text DEFAULT 'planned'::text,
  assigned_to text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS crm_campaign_recipients (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  campaign_id uuid NOT NULL,
  customer_id uuid,
  prospect_id uuid,
  email text,
  phone text,
  sent boolean DEFAULT false,
  sent_at timestamptz,
  opened boolean DEFAULT false,
  opened_at timestamptz,
  clicked boolean DEFAULT false,
  responded boolean DEFAULT false,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS crm_campaigns (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  name text NOT NULL,
  description text,
  campaign_type text NOT NULL,
  status text DEFAULT 'draft'::text,
  start_date date,
  end_date date,
  budget numeric DEFAULT 0,
  actual_cost numeric DEFAULT 0,
  target_audience text,
  segment_criteria jsonb,
  sent_count integer DEFAULT 0,
  open_count integer DEFAULT 0,
  click_count integer DEFAULT 0,
  response_count integer DEFAULT 0,
  conversion_count integer DEFAULT 0,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS crm_forecasts (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  period text NOT NULL,
  sales_rep_id uuid,
  target_amount numeric DEFAULT 0,
  committed_amount numeric DEFAULT 0,
  best_case_amount numeric DEFAULT 0,
  pipeline_amount numeric DEFAULT 0,
  closed_amount numeric DEFAULT 0,
  notes text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS crm_opportunities (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  number text NOT NULL,
  customer_id uuid,
  prospect_id uuid,
  title text NOT NULL,
  description text,
  stage text NOT NULL DEFAULT 'new'::text,
  probability integer DEFAULT 0,
  expected_amount numeric DEFAULT 0,
  expected_close_date date,
  actual_amount numeric,
  actual_close_date date,
  sales_rep_id uuid,
  source text,
  lost_reason text,
  tags text[],
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS crm_territories (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  name text NOT NULL,
  code text,
  parent_id uuid,
  sales_rep_id uuid,
  regions text[],
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS currencies (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  code text NOT NULL,
  name text NOT NULL,
  symbol text,
  exchange_rate numeric DEFAULT 1.0,
  is_base boolean DEFAULT false,
  created_at timestamptz DEFAULT now(),
  tenant_id uuid NOT NULL,
  last_rate_date date,
  decimal_places integer DEFAULT 2,
  rounding numeric DEFAULT 0.01,
  active boolean DEFAULT true,
  position text DEFAULT 'after'::text
);

CREATE TABLE IF NOT EXISTS currency_revaluations (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  fiscal_year_id uuid,
  period_date date NOT NULL,
  account_code text NOT NULL,
  third_party_code text,
  currency text NOT NULL,
  original_rate numeric NOT NULL DEFAULT 1,
  new_rate numeric NOT NULL DEFAULT 1,
  original_amount numeric NOT NULL DEFAULT 0,
  original_amount_eur numeric NOT NULL DEFAULT 0,
  revalued_amount_eur numeric NOT NULL DEFAULT 0,
  gain_loss numeric NOT NULL DEFAULT 0,
  type text NOT NULL,
  status text NOT NULL DEFAULT 'pending'::text,
  entry_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS custom_report_templates (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  name text NOT NULL,
  description text,
  report_type text NOT NULL,
  category text NOT NULL DEFAULT 'accounting'::text,
  columns jsonb NOT NULL DEFAULT '[]'::jsonb,
  filters jsonb NOT NULL DEFAULT '{}'::jsonb,
  group_by text,
  sort_by text,
  sort_order text DEFAULT 'asc'::text,
  page_orientation text DEFAULT 'portrait'::text,
  page_size text DEFAULT 'A4'::text,
  header_text text,
  footer_text text,
  show_logo boolean NOT NULL DEFAULT true,
  show_date boolean NOT NULL DEFAULT true,
  show_page_numbers boolean NOT NULL DEFAULT true,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS customer_contacts (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  customer_id uuid NOT NULL,
  name text NOT NULL,
  role text,
  email text,
  phone text,
  mobile text,
  is_default boolean DEFAULT false,
  active boolean DEFAULT true,
  notes text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS customer_payments (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  number text NOT NULL,
  customer_id uuid,
  invoice_id uuid,
  payment_date date NOT NULL DEFAULT CURRENT_DATE,
  amount numeric NOT NULL DEFAULT 0,
  method text,
  bank_account_id uuid,
  reference text,
  status text NOT NULL DEFAULT 'recorded'::text,
  created_at timestamptz DEFAULT now(),
  tenant_id uuid NOT NULL,
  currency_code text DEFAULT 'EUR'::text,
  exchange_rate numeric DEFAULT 1.0,
  amount_currency numeric,
  exchange_gain_loss numeric DEFAULT 0,
  transferred_entry_id uuid
);

CREATE TABLE IF NOT EXISTS customers (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  name text NOT NULL,
  email text,
  phone text,
  address text,
  city text,
  postal_code text,
  country text DEFAULT 'France'::text,
  vat_number text,
  contact_name text,
  balance numeric DEFAULT 0,
  credit_limit numeric DEFAULT 0,
  payment_terms text DEFAULT '30 days'::text,
  currency text DEFAULT 'EUR'::text,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  tenant_id uuid NOT NULL,
  legal_form text,
  ape_code text,
  naf_code text,
  employee_count_range text,
  revenue_range text,
  payment_delay_avg integer,
  siret text,
  sector_code text,
  geographic_zone text,
  parent_id uuid,
  is_company boolean DEFAULT true,
  sales_rep_id uuid,
  currency_code text DEFAULT 'EUR'::text,
  bank_account_id uuid,
  price_list_id uuid,
  email_settings jsonb DEFAULT '{}'::jsonb,
  credit_used numeric DEFAULT 0,
  credit_blocked boolean DEFAULT false
);

CREATE TABLE IF NOT EXISTS dashboard_widgets (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  user_id text NOT NULL,
  widget_type text NOT NULL,
  title text NOT NULL,
  config jsonb DEFAULT '{}'::jsonb,
  position integer NOT NULL DEFAULT 0,
  size text NOT NULL DEFAULT 'medium'::text,
  visible boolean DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS deferred_printing_jobs (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  job_name text NOT NULL,
  report_type text NOT NULL,
  parameters jsonb NOT NULL DEFAULT '{}'::jsonb,
  scheduled_date timestamptz NOT NULL,
  status text NOT NULL DEFAULT 'pending'::text,
  output_format text NOT NULL DEFAULT 'pdf'::text,
  output_data text,
  generated_at timestamptz,
  generated_by text,
  error_message text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS delivery_note_lines (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  delivery_note_id uuid,
  product_id uuid,
  description text NOT NULL,
  quantity numeric NOT NULL DEFAULT 1,
  tenant_id uuid NOT NULL,
  ordered_quantity numeric DEFAULT 0,
  invoiced_quantity numeric DEFAULT 0,
  sales_order_line_id uuid
);

CREATE TABLE IF NOT EXISTS delivery_notes (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  number text NOT NULL,
  customer_id uuid,
  sales_order_id uuid,
  delivery_date date NOT NULL DEFAULT CURRENT_DATE,
  status text NOT NULL DEFAULT 'pending'::text,
  carrier text,
  tracking_number text,
  notes text,
  created_at timestamptz DEFAULT now(),
  tenant_id uuid NOT NULL,
  validation_status text DEFAULT 'draft'::text,
  fully_invoiced boolean DEFAULT false,
  invoice_status text DEFAULT 'pending'::text
);

CREATE TABLE IF NOT EXISTS delivery_schedules (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  customer_id uuid,
  product_id uuid NOT NULL,
  frequency text DEFAULT 'weekly'::text,
  quantity numeric NOT NULL DEFAULT 0,
  start_date date NOT NULL DEFAULT CURRENT_DATE,
  end_date date,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS disputes (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  third_party_code text NOT NULL,
  invoice_ref text,
  amount numeric NOT NULL DEFAULT 0,
  reason text NOT NULL,
  status text NOT NULL DEFAULT 'open'::text,
  resolution text,
  opened_date date NOT NULL DEFAULT CURRENT_DATE,
  resolved_date date,
  created_by text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS distribution_grill_lines (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  grill_id uuid,
  section_code text NOT NULL,
  percentage numeric NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  tenant_id uuid
);

CREATE TABLE IF NOT EXISTS distribution_grills (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  name text NOT NULL,
  description text,
  account_code text NOT NULL,
  journal_code text,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS document_charges (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  document_type text NOT NULL,
  document_id uuid NOT NULL,
  charge_type text NOT NULL,
  label text NOT NULL,
  amount numeric DEFAULT 0,
  vat_rate numeric DEFAULT 0,
  vat_amount numeric DEFAULT 0,
  total_amount numeric DEFAULT 0,
  supplier_id uuid,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS document_distribution_logs (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  batch_id uuid,
  employee_document_id uuid,
  employee_id uuid NOT NULL,
  document_type text,
  period text,
  distributed_at timestamptz,
  acknowledged_at timestamptz,
  status text DEFAULT 'distributed'::text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS document_shares (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
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

CREATE TABLE IF NOT EXISTS document_templates (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  name text NOT NULL,
  document_type text NOT NULL,
  logo_url text,
  primary_color text DEFAULT '#2563eb'::text,
  secondary_color text DEFAULT '#64748b'::text,
  template_config jsonb DEFAULT '{}'::jsonb,
  is_default boolean DEFAULT false,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS document_transformations (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  source_type text NOT NULL,
  source_id uuid NOT NULL,
  target_type text NOT NULL,
  target_id uuid NOT NULL,
  transformation_type text NOT NULL,
  transformed_by text,
  transformed_at timestamptz DEFAULT now(),
  notes text
);

CREATE TABLE IF NOT EXISTS dpae_records (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  employee_id uuid NOT NULL,
  hire_date date NOT NULL,
  contract_type text,
  position text,
  status text DEFAULT 'pending'::text,
  transmitted_at timestamptz,
  response_code text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS dsn_declarations (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  period text NOT NULL,
  type text DEFAULT 'mensuelle'::text,
  status text DEFAULT 'draft'::text,
  file_url text,
  generated_at timestamptz,
  transmitted_at timestamptz,
  response_code text,
  response_message text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS electronic_signatures (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
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

CREATE TABLE IF NOT EXISTS employee_activity_logs (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  employee_id uuid NOT NULL,
  activity_type text NOT NULL,
  description text,
  metadata jsonb DEFAULT '{}'::jsonb,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS employee_documents (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  employee_id uuid NOT NULL,
  document_type text NOT NULL,
  file_url text NOT NULL,
  file_name text,
  distributed_at timestamptz,
  acknowledged_at timestamptz,
  created_at timestamptz DEFAULT now(),
  title text NOT NULL,
  file_size bigint,
  mime_type text,
  period text,
  uploaded_by text,
  visible_to_employee boolean DEFAULT true,
  requires_acknowledgment boolean DEFAULT false,
  acknowledged boolean DEFAULT false,
  e_signed boolean DEFAULT false,
  e_signed_at timestamptz,
  e_signature_hash text,
  archived boolean DEFAULT false,
  archive_date date,
  retention_years integer DEFAULT 10
);

CREATE TABLE IF NOT EXISTS employee_exit_processes (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  employee_id uuid NOT NULL,
  exit_date date NOT NULL,
  exit_reason text NOT NULL,
  step integer DEFAULT 1,
  status text DEFAULT 'in_progress'::text,
  cp_indemnity numeric DEFAULT 0,
  rtt_indemnity numeric DEFAULT 0,
  recovery_indemnity numeric DEFAULT 0,
  bonus_amount numeric DEFAULT 0,
  advance_deduction numeric DEFAULT 0,
  overtime_amount numeric DEFAULT 0,
  total_gross numeric DEFAULT 0,
  total_net numeric DEFAULT 0,
  work_certificate_url text,
  settlement_receipt_url text,
  pole_emploi_attestation_url text,
  dsn_exit_url text,
  documents_generated boolean DEFAULT false,
  dsn_exit_generated boolean DEFAULT false,
  dsn_exit_transmitted boolean DEFAULT false,
  exit_payslip_id uuid,
  notes text,
  created_at timestamptz DEFAULT now(),
  completed_at timestamptz
);

CREATE TABLE IF NOT EXISTS employee_objectives (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  employee_id uuid NOT NULL,
  campaign_id uuid,
  title text NOT NULL,
  description text,
  target_value numeric,
  current_value numeric DEFAULT 0,
  unit text,
  period text,
  frequency text DEFAULT 'annual'::text,
  status text DEFAULT 'active'::text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS employees (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  name text NOT NULL,
  email text,
  phone text,
  position text,
  department text,
  salary numeric DEFAULT 0,
  hire_date date DEFAULT CURRENT_DATE,
  status text NOT NULL DEFAULT 'active'::text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  tenant_id uuid NOT NULL,
  employee_number text,
  social_security_number text,
  birth_date date,
  address text,
  city text,
  postal_code text,
  contract_type text DEFAULT 'CDI'::text,
  contract_end_date date,
  emergency_contact_name text,
  emergency_contact_phone text,
  emergency_contact_relation text,
  photo_url text,
  bank_iban text,
  bank_bic text,
  bank_account_holder text,
  transport_mode text,
  transport_cost numeric DEFAULT 0,
  meal_voucher_count integer DEFAULT 0,
  meal_voucher_value numeric DEFAULT 0
);

CREATE TABLE IF NOT EXISTS entry_templates (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  name text NOT NULL,
  journal_code text,
  description text,
  template_lines jsonb,
  is_default boolean DEFAULT false,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  tenant_id uuid NOT NULL,
  counterpart_account text,
  payment_terms text
);

CREATE TABLE IF NOT EXISTS etat_rapprochement (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  bank_account_id uuid,
  account_code text NOT NULL,
  period_start date NOT NULL,
  period_end date NOT NULL,
  bank_balance numeric NOT NULL DEFAULT 0,
  book_balance numeric NOT NULL DEFAULT 0,
  difference numeric NOT NULL DEFAULT 0,
  reconciled_items integer DEFAULT 0,
  unreconciled_items integer DEFAULT 0,
  generated_at timestamptz NOT NULL DEFAULT now(),
  generated_by text
);

CREATE TABLE IF NOT EXISTS exchange_gain_loss_entries (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  payment_id uuid,
  invoice_id uuid,
  type text NOT NULL,
  amount numeric,
  exchange_rate_original numeric,
  exchange_rate_payment numeric,
  account_gain_code text,
  account_loss_code text,
  journal_entry_id uuid,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS exchange_rates (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  base_currency text NOT NULL,
  quote_currency text NOT NULL,
  rate numeric NOT NULL,
  rate_date date NOT NULL,
  source text DEFAULT 'manual'::text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS expense_categories (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  code text NOT NULL,
  label text NOT NULL,
  account_code text,
  vat_rate numeric DEFAULT 20,
  max_amount numeric,
  max_monthly numeric,
  requires_receipt boolean DEFAULT true,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS expense_report_lines (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  expense_report_id uuid NOT NULL,
  date date NOT NULL,
  description text NOT NULL,
  category text,
  amount numeric NOT NULL DEFAULT 0,
  vat_rate numeric DEFAULT 0,
  vat_amount numeric DEFAULT 0,
  receipt_url text,
  created_at timestamptz DEFAULT now(),
  category_id uuid,
  amount_ht numeric DEFAULT 0,
  amount_ttc numeric DEFAULT 0,
  ocr_data jsonb,
  ocr_processed boolean DEFAULT false,
  ceiling_exceeded boolean DEFAULT false
);

CREATE TABLE IF NOT EXISTS expense_reports (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  employee_id uuid NOT NULL,
  number text NOT NULL,
  period text,
  total_amount numeric DEFAULT 0,
  total_vat numeric DEFAULT 0,
  status text DEFAULT 'draft'::text,
  submitted_at timestamptz,
  approved_by text,
  approved_at timestamptz,
  notes text,
  created_at timestamptz DEFAULT now(),
  manager_id uuid,
  manager_comment text,
  reimbursement_date date
);

CREATE TABLE IF NOT EXISTS extourne_log (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  original_entry_id uuid NOT NULL,
  extourne_entry_id uuid NOT NULL,
  extourne_date date NOT NULL,
  reason text,
  journal_code text,
  total_debit numeric NOT NULL DEFAULT 0,
  total_credit numeric NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'completed'::text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS fec_attestations (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  fiscal_year_id uuid NOT NULL,
  attestation_number text NOT NULL,
  attestation_date date NOT NULL,
  fec_type text NOT NULL DEFAULT 'definitive'::text,
  entry_count integer NOT NULL DEFAULT 0,
  total_debit numeric NOT NULL DEFAULT 0,
  total_credit numeric NOT NULL DEFAULT 0,
  file_name text,
  file_content text,
  status text NOT NULL DEFAULT 'generated'::text,
  generated_by text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS fiscal_backups (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  fiscal_year_id uuid,
  backup_type text NOT NULL DEFAULT 'manual'::text,
  status text NOT NULL DEFAULT 'pending'::text,
  file_url text,
  file_size bigint,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS fiscal_periods (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  fiscal_year_id uuid,
  period_number integer NOT NULL,
  period_label text NOT NULL,
  start_date date NOT NULL,
  end_date date NOT NULL,
  status text DEFAULT 'open'::text,
  created_at timestamptz DEFAULT now(),
  tenant_id uuid NOT NULL
);

CREATE TABLE IF NOT EXISTS fiscal_position_mappings (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  fiscal_position_id uuid NOT NULL,
  source_tax_id uuid,
  target_tax_id uuid,
  source_account_code text,
  target_account_code text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS fiscal_positions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  name text NOT NULL,
  country_code text,
  country_group_id text,
  zip_from text,
  zip_to text,
  auto_apply boolean DEFAULT false,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS fiscal_years (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  code text NOT NULL,
  start_date date NOT NULL,
  end_date date NOT NULL,
  status text DEFAULT 'open'::text,
  closed_at timestamptz,
  closed_by uuid,
  created_at timestamptz DEFAULT now(),
  tenant_id uuid NOT NULL
);

CREATE TABLE IF NOT EXISTS fixed_assets (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  name text NOT NULL,
  code text,
  category text,
  purchase_date date NOT NULL DEFAULT CURRENT_DATE,
  purchase_value numeric DEFAULT 0,
  current_value numeric DEFAULT 0,
  depreciation_method text DEFAULT 'straight_line'::text,
  useful_life_years integer DEFAULT 5,
  residual_value numeric DEFAULT 0,
  status text NOT NULL DEFAULT 'active'::text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  tenant_id uuid NOT NULL,
  asset_type text DEFAULT 'owned'::text,
  parent_asset_id uuid,
  family_id uuid,
  asset_number text,
  lease_start_date date,
  lease_end_date date,
  lease_monthly_payment numeric DEFAULT 0,
  purchase_entry_id uuid,
  account_asset_code text,
  account_depreciation_code text,
  account_expense_depreciation_code text,
  journal_id uuid,
  partner_id uuid,
  currency_code text DEFAULT 'EUR'::text
);

CREATE TABLE IF NOT EXISTS fusion_logs (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  source_account_code text NOT NULL,
  target_account_code text NOT NULL,
  lines_moved integer NOT NULL DEFAULT 0,
  fused_by text,
  fused_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS future_accounting_movements (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  description text NOT NULL,
  account_code text NOT NULL,
  third_party_id uuid,
  amount numeric NOT NULL DEFAULT 0,
  movement_type text NOT NULL,
  expected_date date NOT NULL,
  source_type text,
  source_id uuid,
  incorporated boolean DEFAULT false,
  incorporated_entry_id uuid,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS goods_receipt_lines (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  goods_receipt_id uuid,
  product_id uuid,
  description text NOT NULL,
  quantity_ordered numeric DEFAULT 0,
  quantity_received numeric DEFAULT 0,
  tenant_id uuid NOT NULL
);

CREATE TABLE IF NOT EXISTS goods_receipts (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  number text NOT NULL,
  supplier_id uuid,
  purchase_order_id uuid,
  receipt_date date NOT NULL DEFAULT CURRENT_DATE,
  status text NOT NULL DEFAULT 'pending'::text,
  notes text,
  created_at timestamptz DEFAULT now(),
  tenant_id uuid NOT NULL
);

CREATE TABLE IF NOT EXISTS grid_templates (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
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

CREATE TABLE IF NOT EXISTS honorarium_records (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  employee_id uuid,
  recipient_name text NOT NULL,
  recipient_type text,
  period text,
  amount numeric NOT NULL DEFAULT 0,
  description text,
  accounting_entry_id uuid,
  status text DEFAULT 'pending'::text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS ifrs_adjustments (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  fiscal_year_id uuid,
  adjustment_type text NOT NULL,
  account_code text NOT NULL,
  counter_account_code text NOT NULL,
  description text NOT NULL,
  amount numeric NOT NULL DEFAULT 0,
  adjustment_date date NOT NULL,
  ifrs_standard text,
  journal_entry_id uuid,
  status text NOT NULL DEFAULT 'draft'::text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS ijss_history (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  work_stoppage_id uuid NOT NULL,
  employee_id uuid NOT NULL,
  period text NOT NULL,
  ijss_net_received numeric DEFAULT 0,
  ijss_brut_calculated numeric DEFAULT 0,
  days_paid integer DEFAULT 0,
  pas_amount numeric DEFAULT 0,
  pas_rate numeric DEFAULT 0,
  integrated_in_payslip boolean DEFAULT false,
  payslip_id uuid,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS interview_campaigns (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  name text NOT NULL,
  campaign_type text NOT NULL,
  start_date date NOT NULL,
  end_date date,
  reminder_days integer DEFAULT 7,
  status text DEFAULT 'draft'::text,
  form_template jsonb,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS interviews (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  employee_id uuid NOT NULL,
  type text DEFAULT 'annual'::text,
  scheduled_date date,
  conducted_at timestamptz,
  conducted_by text,
  objectives text,
  feedback text,
  rating integer,
  status text DEFAULT 'scheduled'::text,
  created_at timestamptz DEFAULT now(),
  campaign_id uuid,
  form_data jsonb,
  employee_feedback text,
  employee_rating integer
);

CREATE TABLE IF NOT EXISTS investments (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  name text NOT NULL,
  type text DEFAULT 'opcv'::text,
  institution text,
  initial_amount numeric NOT NULL DEFAULT 0,
  current_value numeric DEFAULT 0,
  acquisition_date date,
  maturity_date date,
  interest_rate numeric DEFAULT 0,
  status text DEFAULT 'active'::text,
  notes text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS invoice_lines (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  invoice_id uuid,
  product_id uuid,
  description text NOT NULL,
  quantity numeric DEFAULT 1,
  unit_price numeric DEFAULT 0,
  vat_rate numeric DEFAULT 20.0,
  total numeric DEFAULT 0,
  vat_total numeric DEFAULT 0,
  line_order integer DEFAULT 0,
  created_at timestamptz DEFAULT now(),
  tenant_id uuid NOT NULL,
  delivery_note_line_id uuid,
  sales_order_line_id uuid
);

CREATE TABLE IF NOT EXISTS invoices (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  number text NOT NULL,
  customer_id uuid,
  customer_name text,
  date date NOT NULL DEFAULT CURRENT_DATE,
  due_date date NOT NULL,
  status text NOT NULL DEFAULT 'draft'::text,
  subtotal numeric DEFAULT 0,
  vat_total numeric DEFAULT 0,
  total numeric DEFAULT 0,
  amount_paid numeric DEFAULT 0,
  amount_due numeric DEFAULT 0,
  notes text,
  recurring boolean DEFAULT false,
  recurring_frequency text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  tenant_id uuid NOT NULL,
  validation_status text DEFAULT 'draft'::text,
  fiscal_position_id uuid,
  payment_state text DEFAULT 'not_paid'::text,
  currency_code text DEFAULT 'EUR'::text,
  exchange_rate numeric DEFAULT 1.0,
  amount_untaxed_currency numeric,
  amount_tax_currency numeric,
  amount_total_currency numeric,
  delivery_note_id uuid,
  sales_order_id uuid,
  quote_id uuid,
  is_advance_invoice boolean DEFAULT false,
  advance_amount numeric DEFAULT 0,
  invoice_type text DEFAULT 'standard'::text,
  parent_invoice_id uuid,
  transferred_entry_id uuid
);

CREATE TABLE IF NOT EXISTS journal_access_rights (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  user_id uuid NOT NULL,
  journal_code text NOT NULL,
  can_view boolean NOT NULL DEFAULT true,
  can_create boolean NOT NULL DEFAULT false,
  can_edit boolean NOT NULL DEFAULT false,
  can_delete boolean NOT NULL DEFAULT false,
  can_close boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS journal_entries (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  number text NOT NULL,
  date date NOT NULL DEFAULT CURRENT_DATE,
  description text NOT NULL,
  reference text,
  status text NOT NULL DEFAULT 'draft'::text,
  total_debit numeric DEFAULT 0,
  total_credit numeric DEFAULT 0,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  journal_code text,
  fiscal_period_id uuid,
  piece_number text,
  invoice_ref text,
  entry_template_id uuid,
  status_detail text DEFAULT 'open'::text,
  validated_by uuid,
  validated_at timestamptz,
  tenant_id uuid NOT NULL,
  ifrs_mode boolean DEFAULT false,
  currency_code text DEFAULT 'EUR'::text,
  functional_currency text DEFAULT 'EUR'::text,
  exchange_rate numeric DEFAULT 1.0,
  exchange_rate_date date
);

CREATE TABLE IF NOT EXISTS journal_lines (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  journal_id uuid,
  account_code text NOT NULL,
  account_name text,
  debit numeric DEFAULT 0,
  credit numeric DEFAULT 0,
  description text,
  line_order integer DEFAULT 0,
  created_at timestamptz DEFAULT now(),
  account_general text,
  account_tiers text,
  third_party_id uuid,
  lettrage_code text,
  lettrage_date date,
  piece_number text,
  reference text,
  analytic_section_id uuid,
  analytic_amount numeric,
  running_balance numeric,
  reconciled boolean DEFAULT false,
  line_date date,
  tenant_id uuid NOT NULL,
  vat_code text,
  vat_amount numeric DEFAULT 0,
  echeance_date date,
  quantity numeric,
  marking_code text,
  marked_bap boolean DEFAULT false,
  marked_bap_date date,
  tax_tag_ids text[] DEFAULT '{}'::text[],
  analytic_distribution jsonb,
  amount_residual numeric DEFAULT 0,
  product_id uuid,
  product_uom text
);

CREATE TABLE IF NOT EXISTS journals (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  code text NOT NULL,
  name text NOT NULL,
  type text NOT NULL,
  account_counterpart text,
  bank_account_id uuid,
  default_entry_template_id uuid,
  status text DEFAULT 'active'::text,
  locked boolean DEFAULT false,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  tenant_id uuid NOT NULL,
  access_level text DEFAULT 'all'::text,
  numbering_mode text DEFAULT 'manual'::text,
  account_attente text,
  is_analytic boolean DEFAULT false,
  analytic_plan_id uuid,
  currency_code text DEFAULT 'EUR'::text,
  sequence integer DEFAULT 0,
  next_number integer DEFAULT 1
);

CREATE TABLE IF NOT EXISTS justificatif_solde (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  account_code text NOT NULL,
  third_party_code text,
  fiscal_period_id uuid,
  opening_balance numeric NOT NULL DEFAULT 0,
  total_debit numeric NOT NULL DEFAULT 0,
  total_credit numeric NOT NULL DEFAULT 0,
  closing_balance numeric NOT NULL DEFAULT 0,
  generated_at timestamptz NOT NULL DEFAULT now(),
  generated_by text
);

CREATE TABLE IF NOT EXISTS knowledge_base_articles (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  title text NOT NULL,
  category text,
  content text NOT NULL,
  tags text[],
  author text,
  status text DEFAULT 'draft'::text,
  views integer DEFAULT 0,
  helpful_count integer DEFAULT 0,
  not_helpful_count integer DEFAULT 0,
  is_public boolean DEFAULT false,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS leave_balances (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  employee_id uuid NOT NULL,
  leave_type text NOT NULL,
  year integer NOT NULL DEFAULT (EXTRACT(year FROM CURRENT_DATE))::integer,
  acquired numeric DEFAULT 0,
  taken numeric DEFAULT 0,
  pending numeric DEFAULT 0,
  remaining numeric DEFAULT 0,
  carry_over numeric DEFAULT 0,
  provision numeric DEFAULT 0,
  provision_calculated_at timestamptz,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS leave_provisions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  employee_id uuid NOT NULL,
  period text NOT NULL,
  cp_remaining_days numeric DEFAULT 0,
  rtt_remaining_days numeric DEFAULT 0,
  recovery_remaining_days numeric DEFAULT 0,
  daily_rate numeric DEFAULT 0,
  cp_provision numeric DEFAULT 0,
  rtt_provision numeric DEFAULT 0,
  recovery_provision numeric DEFAULT 0,
  total_provision numeric DEFAULT 0,
  accounting_entry_id uuid,
  status text DEFAULT 'draft'::text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS leave_requests (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  employee_id uuid NOT NULL,
  leave_type text NOT NULL,
  start_date date NOT NULL,
  end_date date NOT NULL,
  days numeric DEFAULT 0,
  status text NOT NULL DEFAULT 'pending'::text,
  reason text,
  approved_by uuid,
  approved_at timestamptz,
  created_at timestamptz DEFAULT now(),
  tenant_id uuid NOT NULL
);

CREATE TABLE IF NOT EXISTS leave_rules (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  leave_type text NOT NULL,
  label text NOT NULL,
  accrual_rate numeric DEFAULT 2.08,
  max_carry_over numeric DEFAULT 0,
  carry_over_expiry_months integer DEFAULT 3,
  requires_justification boolean DEFAULT false,
  requires_manager_approval boolean DEFAULT true,
  min_notice_days integer DEFAULT 7,
  max_consecutive_days integer DEFAULT 30,
  color text DEFAULT '#3b82f6'::text,
  count_method text DEFAULT 'working_days'::text,
  affects_pay boolean DEFAULT false,
  deduction_rate numeric DEFAULT 100,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS legal_declarations (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  number text NOT NULL,
  declaration_type text NOT NULL,
  period_month integer NOT NULL,
  period_year integer NOT NULL,
  due_date date NOT NULL,
  submission_date date,
  amount numeric DEFAULT 0,
  status text NOT NULL DEFAULT 'pending'::text,
  notes text,
  created_at timestamptz DEFAULT now(),
  tenant_id uuid NOT NULL
);

CREATE TABLE IF NOT EXISTS legal_watch (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  title text NOT NULL,
  category text,
  source text,
  summary text,
  content_url text,
  published_date date,
  relevance text,
  read boolean DEFAULT false,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS legislation_packs (
  code text NOT NULL,
  name text NOT NULL,
  country_code text NOT NULL,
  country_name text NOT NULL,
  accounting_standard text NOT NULL,
  currency text NOT NULL DEFAULT 'EUR'::text,
  currency_decimals integer NOT NULL DEFAULT 2,
  date_format text NOT NULL DEFAULT 'DD/MM/YYYY'::text,
  locale text NOT NULL DEFAULT 'fr-FR'::text,
  fiscal_year_start text NOT NULL DEFAULT '01-01'::text,
  tax_id_label text NOT NULL DEFAULT 'N° TVA'::text,
  tax_id_secondary_label text,
  is_default boolean NOT NULL DEFAULT false,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  tenant_id uuid
);

CREATE TABLE IF NOT EXISTS lettrage_differences (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  third_party_code text NOT NULL,
  lettrage_code text NOT NULL,
  line_id_1 uuid NOT NULL,
  line_id_2 uuid NOT NULL,
  debit_amount numeric NOT NULL DEFAULT 0,
  credit_amount numeric NOT NULL DEFAULT 0,
  difference numeric NOT NULL DEFAULT 0,
  difference_account text,
  generated_entry_id uuid,
  status text NOT NULL DEFAULT 'pending'::text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS machines (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  code text NOT NULL,
  name text NOT NULL,
  work_center_id uuid,
  capacity_per_hour numeric DEFAULT 0,
  status text DEFAULT 'active'::text,
  purchase_date date,
  notes text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS manufacturing_orders (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  number text NOT NULL,
  bom_id uuid,
  product_id uuid,
  quantity numeric NOT NULL DEFAULT 1,
  status text NOT NULL DEFAULT 'planned'::text,
  start_date date,
  end_date date,
  warehouse_id uuid,
  notes text,
  created_at timestamptz DEFAULT now(),
  tenant_id uuid NOT NULL,
  routing_id uuid,
  origin text DEFAULT 'manual'::text,
  parent_mo_id uuid,
  lot_number text,
  expiry_date date,
  custom_expiry_date date,
  expiry_type text,
  label_enabled boolean DEFAULT false,
  additional_text text
);

CREATE TABLE IF NOT EXISTS marking_types (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  code text NOT NULL,
  label text NOT NULL,
  color text DEFAULT 'neutral'::text,
  active boolean DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS meal_voucher_config (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  voucher_value numeric NOT NULL DEFAULT 3.50,
  employer_share numeric DEFAULT 60,
  employee_share numeric DEFAULT 40,
  eligible_days text[] DEFAULT '{1,2,3,4,5}'::text[],
  max_per_month integer DEFAULT 20,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS medical_exams (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  employee_id uuid NOT NULL,
  exam_type text NOT NULL,
  scheduled_date date NOT NULL,
  completed_date date,
  result text,
  restrictions text,
  next_exam_date date,
  occupational_doctor text,
  notes text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS mirror_servers (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  machine_id text NOT NULL,
  machine_name text NOT NULL,
  os text,
  ip_address text,
  mirror_dir text,
  registered_at timestamptz DEFAULT now(),
  last_heartbeat timestamptz DEFAULT now(),
  status text NOT NULL DEFAULT 'active'::text,
  config jsonb,
  install_status text DEFAULT 'pending'::text,
  verification_data jsonb,
  verified_at timestamptz,
  install_token text,
  install_platform text,
  tenant_id uuid NOT NULL
);

CREATE TABLE IF NOT EXISTS mirror_verification_details (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  mirror_server_id uuid,
  table_name text NOT NULL,
  cloud_rows integer NOT NULL DEFAULT 0,
  local_rows integer NOT NULL DEFAULT 0,
  match boolean NOT NULL DEFAULT false,
  verified_at timestamptz DEFAULT now(),
  tenant_id uuid NOT NULL
);

CREATE TABLE IF NOT EXISTS module_document_access_log (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  document_id uuid NOT NULL,
  user_id uuid NOT NULL,
  action text NOT NULL,
  ip_address inet,
  user_agent text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS module_document_shares (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  document_id uuid NOT NULL,
  share_token text NOT NULL,
  password_hash text,
  created_by uuid NOT NULL,
  expires_at timestamptz,
  max_downloads integer,
  download_count integer DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS module_documents (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  module text NOT NULL,
  document_type text NOT NULL,
  confidentiality text NOT NULL DEFAULT 'restricted'::text,
  entity_type text,
  entity_id uuid,
  title text NOT NULL,
  description text,
  file_url text NOT NULL,
  file_name text NOT NULL,
  file_size bigint,
  mime_type text,
  file_hash text,
  status text NOT NULL DEFAULT 'pending'::text,
  approved_by uuid,
  approved_at timestamptz,
  rejection_reason text,
  expires_at timestamptz,
  archived_at timestamptz,
  uploaded_by uuid NOT NULL,
  metadata jsonb DEFAULT '{}'::jsonb,
  download_count integer DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS mrp_pending_docs (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  doc_type text NOT NULL,
  doc_id uuid,
  product_id uuid,
  quantity numeric DEFAULT 0,
  status text DEFAULT 'pending'::text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS mrp_proposals (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  mrp_run_id uuid NOT NULL,
  product_id uuid NOT NULL,
  proposal_type text,
  gross_need numeric NOT NULL DEFAULT 0,
  stock_available numeric DEFAULT 0,
  open_orders numeric DEFAULT 0,
  net_need numeric NOT NULL DEFAULT 0,
  suggested_quantity numeric DEFAULT 0,
  suggested_date date,
  bom_id uuid,
  supplier_id uuid,
  status text DEFAULT 'pending'::text,
  notes text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS mrp_runs (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  run_number text NOT NULL,
  run_date timestamptz DEFAULT now(),
  status text DEFAULT 'completed'::text,
  parameters jsonb,
  summary jsonb,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS notification_email_queue (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  recipient_email varchar(255) NOT NULL,
  recipient_name varchar(255),
  notification_type varchar(50) NOT NULL,
  subject varchar(500) NOT NULL,
  status varchar(20) DEFAULT 'pending'::character varying,
  resend_id varchar(255),
  error_message text,
  sent_at timestamptz,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS notification_preferences (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  employee_id uuid NOT NULL,
  email_enabled boolean DEFAULT true,
  email_types jsonb DEFAULT '{}'::jsonb,
  digest_mode varchar(20) DEFAULT 'instant'::character varying,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS of_consumptions (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  manufacturing_order_id uuid NOT NULL,
  product_id uuid NOT NULL,
  quantity numeric NOT NULL DEFAULT 0,
  unit text DEFAULT 'unit'::text,
  consumption_date date NOT NULL DEFAULT CURRENT_DATE,
  is_deferred boolean DEFAULT false,
  notes text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS of_document_access (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  user_id uuid NOT NULL,
  document_type text NOT NULL,
  can_view boolean DEFAULT true,
  can_print boolean DEFAULT false,
  can_export boolean DEFAULT false,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS of_labels (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  manufacturing_order_id uuid NOT NULL,
  label_number text NOT NULL,
  product_id uuid,
  planned_quantity numeric DEFAULT 0,
  actual_quantity numeric DEFAULT 0,
  is_complete boolean DEFAULT false,
  is_declared boolean DEFAULT false,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS of_lots (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  manufacturing_order_id uuid NOT NULL,
  lot_number text NOT NULL,
  product_id uuid,
  quantity numeric DEFAULT 0,
  production_date date,
  expiry_date date,
  custom_expiry_date date,
  expiry_type text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS online_payments (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  invoice_id uuid,
  customer_id uuid,
  payment_provider text,
  provider_transaction_id text,
  amount numeric NOT NULL,
  currency_code text DEFAULT 'EUR'::text,
  status text DEFAULT 'pending'::text,
  payment_url text,
  paid_at timestamptz,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS partner_bank_accounts (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  partner_type text NOT NULL,
  partner_id uuid NOT NULL,
  account_number text NOT NULL,
  bank_name text,
  bic text,
  bank_code text,
  sort_code text,
  account_key text,
  currency_code text DEFAULT 'EUR'::text,
  is_default boolean DEFAULT false,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS partner_categories (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  name text NOT NULL,
  color text,
  parent_id uuid,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS partner_category_mappings (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  category_id uuid NOT NULL,
  partner_type text NOT NULL,
  partner_id uuid NOT NULL,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS partner_contacts (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  partner_type text NOT NULL,
  partner_id uuid NOT NULL,
  contact_type text NOT NULL,
  name text NOT NULL,
  email text,
  phone text,
  mobile text,
  function text,
  address text,
  postal_code text,
  city text,
  country text,
  is_default boolean DEFAULT false,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS pas_rates (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  employee_id uuid NOT NULL,
  rate numeric NOT NULL DEFAULT 0,
  effective_date date NOT NULL,
  expiry_date date,
  source text DEFAULT 'import'::text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS pay_recalls (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  employee_id uuid NOT NULL,
  reference_period text NOT NULL,
  recall_amount numeric NOT NULL DEFAULT 0,
  reason text,
  status text DEFAULT 'pending'::text,
  processed_pay_run_id uuid,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS pay_runs (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  number text NOT NULL,
  period_start date NOT NULL,
  period_end date NOT NULL,
  pay_date date NOT NULL,
  status text NOT NULL DEFAULT 'draft'::text,
  gross_total numeric DEFAULT 0,
  tax_total numeric DEFAULT 0,
  net_total numeric DEFAULT 0,
  employee_count integer DEFAULT 0,
  created_at timestamptz DEFAULT now(),
  tenant_id uuid NOT NULL
);

CREATE TABLE IF NOT EXISTS pay_slip_clarified (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  pay_slip_id uuid NOT NULL,
  employee_id uuid NOT NULL,
  period text NOT NULL,
  gross_salary numeric DEFAULT 0,
  social_charges_employee numeric DEFAULT 0,
  social_charges_employer numeric DEFAULT 0,
  income_tax numeric DEFAULT 0,
  net_before_tax numeric DEFAULT 0,
  net_after_tax numeric DEFAULT 0,
  total_deductions numeric DEFAULT 0,
  lines jsonb DEFAULT '[]'::jsonb,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS pay_slips (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  number text NOT NULL,
  pay_run_id uuid,
  employee_id uuid NOT NULL,
  period_start date NOT NULL,
  period_end date NOT NULL,
  gross_salary numeric DEFAULT 0,
  overtime_pay numeric DEFAULT 0,
  bonus numeric DEFAULT 0,
  total_gross numeric DEFAULT 0,
  social_security_employee numeric DEFAULT 0,
  income_tax numeric DEFAULT 0,
  other_deductions numeric DEFAULT 0,
  total_deductions numeric DEFAULT 0,
  net_salary numeric DEFAULT 0,
  employer_contributions numeric DEFAULT 0,
  status text NOT NULL DEFAULT 'draft'::text,
  payment_date date,
  created_at timestamptz DEFAULT now(),
  tenant_id uuid NOT NULL
);

CREATE TABLE IF NOT EXISTS payment_orders (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  number text NOT NULL,
  type text NOT NULL,
  status text NOT NULL DEFAULT 'draft'::text,
  bank_account_id uuid,
  third_party_id uuid,
  third_party_name text,
  third_party_iban text,
  amount numeric NOT NULL DEFAULT 0,
  payment_date date NOT NULL DEFAULT CURRENT_DATE,
  reference text,
  description text,
  remise_number text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  tenant_id uuid NOT NULL,
  currency_code text DEFAULT 'EUR'::text,
  exchange_rate numeric DEFAULT 1.0,
  amount_currency numeric,
  exchange_gain_loss numeric DEFAULT 0
);

CREATE TABLE IF NOT EXISTS payment_promises (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  third_party_code text NOT NULL,
  amount numeric NOT NULL DEFAULT 0,
  promised_date date NOT NULL,
  reminder_level integer DEFAULT 1,
  status text NOT NULL DEFAULT 'pending'::text,
  notes text,
  created_by text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS payment_templates_compta (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  code text NOT NULL,
  name text NOT NULL,
  description text,
  payment_method text NOT NULL DEFAULT 'transfer'::text,
  day_count integer DEFAULT 30,
  end_of_month boolean DEFAULT false,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS payment_terms (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  code text NOT NULL,
  name text NOT NULL,
  type text NOT NULL,
  days_1 integer NOT NULL DEFAULT 30,
  days_2 integer,
  pct_1 numeric DEFAULT 100.00,
  pct_2 numeric DEFAULT NULL::numeric,
  end_of_month boolean DEFAULT false,
  description text,
  active boolean DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS payroll_accounting_entries (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  number text NOT NULL,
  pay_run_id uuid,
  period_date date NOT NULL,
  gross_total numeric DEFAULT 0,
  employer_contributions_total numeric DEFAULT 0,
  employee_deductions_total numeric DEFAULT 0,
  net_total numeric DEFAULT 0,
  journal_entry_id uuid,
  status text NOT NULL DEFAULT 'draft'::text,
  created_at timestamptz DEFAULT now(),
  tenant_id uuid NOT NULL
);

CREATE TABLE IF NOT EXISTS payroll_archives (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  employee_id uuid,
  period text NOT NULL,
  archive_type text,
  file_url text NOT NULL,
  file_encrypted boolean DEFAULT true,
  retention_until date,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS payroll_component_rates (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  component_id uuid NOT NULL,
  legislation_pack text,
  rate_employer numeric DEFAULT 0,
  rate_employee numeric DEFAULT 0,
  ceiling_amount numeric,
  effective_date date NOT NULL DEFAULT CURRENT_DATE,
  end_date date,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS payroll_components (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  code text NOT NULL,
  name text NOT NULL,
  type text NOT NULL,
  calculation_type text DEFAULT 'fixed'::text,
  default_value numeric DEFAULT 0,
  rate_employer numeric DEFAULT 0,
  rate_employee numeric DEFAULT 0,
  ceiling_amount numeric,
  ceiling_basis text,
  tax_deductible boolean DEFAULT false,
  display_order integer DEFAULT 100,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS payroll_tax_grid_lines (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  grid_id uuid NOT NULL,
  line_type text NOT NULL,
  category text NOT NULL,
  label text NOT NULL,
  base_type text NOT NULL DEFAULT 'gross'::text,
  min_amount numeric DEFAULT 0,
  max_amount numeric,
  rate_employee numeric DEFAULT 0,
  rate_employer numeric DEFAULT 0,
  cap_amount numeric,
  fixed_amount numeric DEFAULT 0,
  sort_order integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS payroll_tax_grids (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  country_code text NOT NULL,
  grid_type text NOT NULL,
  name text NOT NULL,
  description text,
  effective_from date NOT NULL DEFAULT CURRENT_DATE,
  effective_to date,
  status text NOT NULL DEFAULT 'draft'::text,
  source text NOT NULL DEFAULT 'manual'::text,
  file_url text,
  is_default boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS payroll_templates (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  name text NOT NULL,
  category text DEFAULT 'standard'::text,
  component_ids jsonb DEFAULT '[]'::jsonb,
  description text,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS payroll_variable_elements (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  employee_id uuid NOT NULL,
  pay_run_id uuid,
  period text NOT NULL,
  element_type text NOT NULL,
  description text,
  quantity numeric,
  unit_price numeric,
  amount numeric NOT NULL DEFAULT 0,
  source text,
  source_id uuid,
  integrated boolean DEFAULT false,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS pick_list_lines (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  pick_list_id uuid NOT NULL,
  product_id uuid NOT NULL,
  location_id uuid,
  quantity_to_pick numeric NOT NULL DEFAULT 0,
  quantity_picked numeric DEFAULT 0,
  barcode text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS pick_lists (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  number text NOT NULL,
  reference_type text DEFAULT 'sales_order'::text,
  reference_id uuid,
  warehouse_id uuid,
  status text DEFAULT 'draft'::text,
  picked_by text,
  picked_at timestamptz,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS planning_slots (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  manufacturing_order_id uuid NOT NULL,
  routing_operation_id uuid,
  machine_id uuid,
  work_center_id uuid,
  planned_start timestamptz,
  planned_end timestamptz,
  setup_time numeric DEFAULT 0,
  run_time numeric DEFAULT 0,
  status text DEFAULT 'planned'::text,
  material_available boolean DEFAULT true,
  material_check_date timestamptz,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS pos_sessions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  terminal_id uuid NOT NULL,
  user_email text NOT NULL,
  opening_amount numeric DEFAULT 0,
  closing_amount numeric,
  expected_amount numeric,
  difference numeric,
  status text DEFAULT 'open'::text,
  opened_at timestamptz DEFAULT now(),
  closed_at timestamptz,
  notes text
);

CREATE TABLE IF NOT EXISTS pos_terminals (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  name text NOT NULL,
  warehouse_id uuid,
  location text,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS pos_ticket_lines (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  ticket_id uuid NOT NULL,
  product_id uuid,
  description text NOT NULL,
  quantity numeric NOT NULL DEFAULT 1,
  unit_price numeric NOT NULL,
  vat_rate numeric DEFAULT 0,
  line_total numeric NOT NULL,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS pos_tickets (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  number text NOT NULL,
  session_id uuid NOT NULL,
  terminal_id uuid NOT NULL,
  customer_id uuid,
  date timestamptz DEFAULT now(),
  subtotal numeric DEFAULT 0,
  vat_total numeric DEFAULT 0,
  total numeric DEFAULT 0,
  payment_method text,
  amount_paid numeric DEFAULT 0,
  change_given numeric DEFAULT 0,
  status text DEFAULT 'completed'::text,
  invoice_id uuid,
  notes text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS price_list_lines (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  price_list_id uuid,
  product_id uuid,
  unit_price numeric NOT NULL DEFAULT 0,
  min_quantity numeric DEFAULT 1,
  discount_percent numeric DEFAULT 0,
  tenant_id uuid NOT NULL
);

CREATE TABLE IF NOT EXISTS price_lists (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  name text NOT NULL,
  code text,
  type text NOT NULL DEFAULT 'sales'::text,
  currency text DEFAULT 'EUR'::text,
  valid_from date,
  valid_to date,
  active boolean DEFAULT true,
  is_default boolean DEFAULT false,
  created_at timestamptz DEFAULT now(),
  tenant_id uuid NOT NULL
);

CREATE TABLE IF NOT EXISTS product_attributes (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  name text NOT NULL,
  type text NOT NULL DEFAULT 'select'::text,
  options jsonb DEFAULT '[]'::jsonb,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS product_batches (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  product_id uuid NOT NULL,
  batch_number text NOT NULL,
  quantity numeric NOT NULL DEFAULT 0,
  expiry_date date,
  status text DEFAULT 'active'::text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS product_equivalences (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  product_id uuid NOT NULL,
  equivalent_product_id uuid NOT NULL,
  conversion_ratio numeric DEFAULT 1,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS product_grid_combinations (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  product_id uuid NOT NULL,
  combination jsonb NOT NULL,
  sku text,
  barcode text,
  price_override numeric,
  stock_quantity numeric DEFAULT 0,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS product_grids (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  product_id uuid NOT NULL,
  name text NOT NULL,
  axis text NOT NULL,
  values jsonb NOT NULL DEFAULT '[]'::jsonb,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS product_links (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  product_id uuid NOT NULL,
  linked_product_id uuid NOT NULL,
  link_type text NOT NULL,
  quantity numeric DEFAULT 1,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS product_packagings (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  product_id uuid NOT NULL,
  name text NOT NULL,
  quantity numeric NOT NULL,
  unit text,
  barcode text,
  weight numeric,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS product_serial_numbers (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  product_id uuid NOT NULL,
  serial_number text NOT NULL,
  status text DEFAULT 'in_stock'::text,
  warranty_expiry date,
  notes text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS product_substitutes (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  product_id uuid NOT NULL,
  substitute_id uuid NOT NULL,
  priority integer DEFAULT 1,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS product_variants (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  product_id uuid NOT NULL,
  sku text NOT NULL,
  attributes jsonb DEFAULT '{}'::jsonb,
  price_override numeric,
  barcode text,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS production_forecasts (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  forecast_number text NOT NULL,
  period text NOT NULL,
  start_date date NOT NULL,
  end_date date NOT NULL,
  product_id uuid,
  forecasted_quantity numeric NOT NULL DEFAULT 0,
  actual_quantity numeric DEFAULT 0,
  reliability_rate numeric DEFAULT 0,
  source text DEFAULT 'manual'::text,
  notes text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS products (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  name text NOT NULL,
  sku text,
  description text,
  type text NOT NULL,
  sale_price numeric DEFAULT 0,
  purchase_price numeric DEFAULT 0,
  vat_rate numeric DEFAULT 20.0,
  stock_quantity numeric DEFAULT 0,
  reorder_level numeric DEFAULT 0,
  unit text DEFAULT 'unité'::text,
  category text,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  tenant_id uuid NOT NULL,
  is_amalgam boolean DEFAULT false,
  units_per_carton integer,
  st_unit text,
  purchase_unit text,
  st_multiple numeric DEFAULT 1,
  shelf_life_days integer,
  exclude_from_mrp boolean DEFAULT false,
  barcode text,
  weight numeric,
  photo_url text,
  supplier_ref text,
  criticality_level text DEFAULT 'normal'::text,
  cost_price numeric DEFAULT 0
);

CREATE TABLE IF NOT EXISTS project_activity_log (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  task_id uuid,
  project_id uuid,
  user_id uuid,
  user_name varchar(200),
  action_type varchar(50) NOT NULL,
  old_value jsonb,
  new_value jsonb,
  description text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS project_docs (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  project_id uuid,
  title text NOT NULL DEFAULT ''::text,
  content text NOT NULL DEFAULT ''::text,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS project_members (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  project_id uuid NOT NULL,
  employee_id uuid NOT NULL,
  role varchar(50) NOT NULL DEFAULT 'team_member'::character varying,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS project_milestones (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  project_id uuid NOT NULL,
  name varchar(255) NOT NULL,
  deadline date,
  is_reached boolean DEFAULT false,
  is_reached_manually boolean DEFAULT false,
  sale_line_id uuid,
  sale_line_qty_percentage numeric DEFAULT 0,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS project_notifications (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  recipient_id uuid NOT NULL,
  task_id uuid,
  project_id uuid,
  notification_type varchar(50) NOT NULL,
  title varchar(255) NOT NULL,
  message text,
  is_read boolean DEFAULT false,
  action_url varchar(500),
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS project_stages (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  name varchar(100) NOT NULL,
  sequence integer DEFAULT 0,
  fold boolean DEFAULT false,
  case_default boolean DEFAULT false,
  mail_template_id uuid,
  legend_priority varchar(200),
  legend_blocked varchar(200),
  legend_done varchar(200),
  legend_normal varchar(200),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS project_tags (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  name varchar(100) NOT NULL,
  color integer DEFAULT 0,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS project_task_assignees (
  task_id uuid NOT NULL,
  employee_id uuid NOT NULL
);

CREATE TABLE IF NOT EXISTS project_task_dependencies (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  task_id uuid NOT NULL,
  depends_on_task_id uuid NOT NULL,
  dependency_type varchar(30) NOT NULL DEFAULT 'finish-to-start'::character varying,
  lag_days integer DEFAULT 0,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS project_task_tags (
  task_id uuid NOT NULL,
  tag_id uuid NOT NULL,
  tenant_id uuid
);

CREATE TABLE IF NOT EXISTS project_task_templates (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  name varchar(200) NOT NULL,
  description text,
  default_status varchar(20) DEFAULT 'todo'::character varying,
  default_priority varchar(20) DEFAULT 'medium'::character varying,
  default_assignee_id uuid,
  default_tags text[] DEFAULT '{}'::text[],
  default_effort_estimate numeric DEFAULT 0,
  default_budget numeric DEFAULT 0,
  checklist_template jsonb DEFAULT '[]'::jsonb,
  subtasks_template jsonb DEFAULT '[]'::jsonb,
  is_public boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS project_task_watchers (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  task_id uuid NOT NULL,
  employee_id uuid NOT NULL,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS project_tasks (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  project_id uuid,
  parent_id uuid,
  title varchar(200) NOT NULL,
  description text,
  status varchar(20) NOT NULL DEFAULT 'todo'::character varying,
  priority varchar(20) NOT NULL DEFAULT 'medium'::character varying,
  assignee varchar(200),
  start_date date,
  due_date date,
  effort_estimate_h numeric DEFAULT 0,
  effort_spent_h numeric DEFAULT 0,
  progress integer DEFAULT 0,
  display_order varchar(50) NOT NULL DEFAULT '0'::character varying,
  task_level integer DEFAULT 0,
  budget numeric DEFAULT 0,
  color integer DEFAULT 0,
  acceptance_criteria text,
  recurring_task boolean DEFAULT false,
  recurring_interval integer DEFAULT 1,
  recurring_rule_type varchar(20) DEFAULT 'weekly'::character varying,
  is_closed boolean DEFAULT false,
  linked_action_id uuid,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  assignee_id uuid
);

CREATE TABLE IF NOT EXISTS project_time_entries (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  task_id uuid,
  project_id uuid,
  employee_id uuid,
  start_time timestamptz NOT NULL DEFAULT now(),
  end_time timestamptz,
  duration_seconds integer DEFAULT 0,
  description text,
  is_billable boolean DEFAULT false,
  hourly_rate numeric DEFAULT 0,
  tags text[] DEFAULT '{}'::text[],
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS projects (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  name text NOT NULL,
  description text,
  customer_id uuid,
  status text NOT NULL DEFAULT 'active'::text,
  budget numeric DEFAULT 0,
  actual_cost numeric DEFAULT 0,
  start_date date,
  end_date date,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  tenant_id uuid NOT NULL,
  color varchar(7) DEFAULT '#0066cc'::character varying,
  display_order varchar(50) DEFAULT '0'::character varying,
  progress integer DEFAULT 0,
  manager_id uuid,
  allow_subtasks boolean DEFAULT true,
  allow_recurrent_tasks boolean DEFAULT false,
  allow_milestones boolean DEFAULT true,
  allow_task_dependencies boolean DEFAULT true,
  allow_timesheets boolean DEFAULT false,
  allow_billable boolean DEFAULT false,
  privacy_visibility varchar(20) DEFAULT 'portal'::character varying,
  alias_name varchar(100),
  allocated_hours numeric DEFAULT 0,
  total_hours_spent numeric DEFAULT 0,
  remaining_hours numeric DEFAULT 0
);

CREATE TABLE IF NOT EXISTS promotions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  name text NOT NULL,
  description text,
  promo_type text NOT NULL,
  value numeric,
  product_id uuid,
  category text,
  customer_id uuid,
  start_date date NOT NULL,
  end_date date NOT NULL,
  min_quantity numeric DEFAULT 1,
  free_product_id uuid,
  free_product_qty numeric DEFAULT 1,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS prospects (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  name text NOT NULL,
  email text,
  phone text,
  address text,
  city text,
  postal_code text,
  country text,
  contact_name text,
  source text,
  status text DEFAULT 'new'::text,
  assigned_rep_id uuid,
  notes text,
  converted_customer_id uuid,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public_holidays (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  name text NOT NULL,
  holiday_date date NOT NULL,
  region text DEFAULT 'national'::text,
  country text DEFAULT 'FR'::text,
  is_working_day boolean DEFAULT false,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS purchase_credit_lines (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  purchase_credit_id uuid,
  description text NOT NULL,
  quantity numeric DEFAULT 1,
  unit_price numeric DEFAULT 0,
  vat_rate numeric DEFAULT 20.0,
  total numeric DEFAULT 0,
  vat_total numeric DEFAULT 0,
  line_order integer DEFAULT 0,
  created_at timestamptz DEFAULT now(),
  tenant_id uuid NOT NULL
);

CREATE TABLE IF NOT EXISTS purchase_credit_notes (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  number text NOT NULL,
  supplier_id uuid,
  supplier_name text,
  date date NOT NULL DEFAULT CURRENT_DATE,
  status text NOT NULL DEFAULT 'draft'::text,
  subtotal numeric DEFAULT 0,
  vat_total numeric DEFAULT 0,
  total numeric DEFAULT 0,
  reason text,
  purchase_invoice_id uuid,
  created_at timestamptz DEFAULT now(),
  tenant_id uuid NOT NULL,
  currency_code text DEFAULT 'EUR'::text,
  exchange_rate numeric DEFAULT 1.0,
  amount_untaxed_currency numeric,
  amount_tax_currency numeric,
  amount_total_currency numeric
);

CREATE TABLE IF NOT EXISTS purchase_invoice_lines (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  purchase_invoice_id uuid,
  product_id uuid,
  description text NOT NULL,
  quantity numeric DEFAULT 1,
  unit_price numeric DEFAULT 0,
  vat_rate numeric DEFAULT 20.0,
  total numeric DEFAULT 0,
  vat_total numeric DEFAULT 0,
  line_order integer DEFAULT 0,
  created_at timestamptz DEFAULT now(),
  tenant_id uuid NOT NULL
);

CREATE TABLE IF NOT EXISTS purchase_invoices (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  number text NOT NULL,
  supplier_id uuid,
  supplier_name text,
  date date NOT NULL DEFAULT CURRENT_DATE,
  due_date date NOT NULL,
  status text NOT NULL DEFAULT 'draft'::text,
  subtotal numeric DEFAULT 0,
  vat_total numeric DEFAULT 0,
  total numeric DEFAULT 0,
  amount_paid numeric DEFAULT 0,
  amount_due numeric DEFAULT 0,
  notes text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  tenant_id uuid NOT NULL,
  approval_status text DEFAULT 'pending'::text,
  approved_by uuid,
  approved_at timestamptz,
  fiscal_position_id uuid,
  payment_state text DEFAULT 'not_paid'::text,
  currency_code text DEFAULT 'EUR'::text,
  exchange_rate numeric DEFAULT 1.0,
  amount_untaxed_currency numeric,
  amount_tax_currency numeric,
  amount_total_currency numeric,
  transferred_entry_id uuid
);

CREATE TABLE IF NOT EXISTS purchase_order_lines (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  purchase_order_id uuid,
  product_id uuid,
  description text NOT NULL,
  quantity numeric NOT NULL DEFAULT 1,
  unit_price numeric NOT NULL DEFAULT 0,
  vat_rate numeric DEFAULT 0,
  line_total numeric DEFAULT 0,
  tenant_id uuid NOT NULL
);

CREATE TABLE IF NOT EXISTS purchase_orders (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  number text NOT NULL,
  supplier_id uuid,
  order_date date NOT NULL DEFAULT CURRENT_DATE,
  expected_date date,
  status text NOT NULL DEFAULT 'draft'::text,
  subtotal numeric DEFAULT 0,
  vat numeric DEFAULT 0,
  total numeric DEFAULT 0,
  notes text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  tenant_id uuid NOT NULL
);

CREATE TABLE IF NOT EXISTS purchase_request_lines (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  purchase_request_id uuid NOT NULL,
  product_id uuid,
  description text NOT NULL,
  quantity numeric NOT NULL DEFAULT 1,
  unit text,
  estimated_price numeric,
  preferred_supplier_id uuid,
  notes text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS purchase_requests (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  number text NOT NULL,
  requester text,
  department text,
  status text DEFAULT 'draft'::text,
  priority text DEFAULT 'normal'::text,
  expected_date date,
  notes text,
  approved_by text,
  approved_at timestamptz,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS quality_checks (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  product_id uuid NOT NULL,
  reference_type text DEFAULT 'goods_receipt'::text,
  reference_id uuid,
  status text DEFAULT 'pending'::text,
  checked_by text,
  checked_at timestamptz,
  notes text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS quote_lines (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  quote_id uuid,
  product_id uuid,
  description text NOT NULL,
  quantity numeric DEFAULT 1,
  unit_price numeric DEFAULT 0,
  vat_rate numeric DEFAULT 20.0,
  total numeric DEFAULT 0,
  vat_total numeric DEFAULT 0,
  line_order integer DEFAULT 0,
  created_at timestamptz DEFAULT now(),
  tenant_id uuid NOT NULL
);

CREATE TABLE IF NOT EXISTS quotes (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  number text NOT NULL,
  customer_id uuid,
  customer_name text,
  date date NOT NULL DEFAULT CURRENT_DATE,
  expiry_date date NOT NULL,
  status text NOT NULL DEFAULT 'draft'::text,
  subtotal numeric DEFAULT 0,
  vat_total numeric DEFAULT 0,
  total numeric DEFAULT 0,
  notes text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  tenant_id uuid NOT NULL,
  validation_status text DEFAULT 'draft'::text,
  transformed_to_order_id uuid,
  transformation_status text DEFAULT 'pending'::text
);

CREATE TABLE IF NOT EXISTS recurring_entries (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  name text NOT NULL,
  description text,
  journal_id text NOT NULL,
  journal_code text,
  frequency text NOT NULL DEFAULT 'monthly'::text,
  day_of_month integer NOT NULL DEFAULT 1,
  start_date date NOT NULL,
  end_date date,
  next_generation_date date NOT NULL,
  last_generation_date date,
  lines jsonb NOT NULL DEFAULT '[]'::jsonb,
  status text NOT NULL DEFAULT 'active'::text,
  total_debit numeric NOT NULL DEFAULT 0,
  total_credit numeric NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS recurring_invoice_templates (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  name text NOT NULL,
  customer_id uuid,
  frequency text DEFAULT 'monthly'::text,
  next_date date NOT NULL DEFAULT CURRENT_DATE,
  lines jsonb DEFAULT '[]'::jsonb,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS regularization_entries (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  type text NOT NULL,
  fiscal_year_id uuid,
  account_code text NOT NULL,
  third_party_code text,
  description text NOT NULL,
  invoice_number text,
  invoice_date date,
  invoice_amount numeric NOT NULL DEFAULT 0,
  start_date date NOT NULL,
  end_date date NOT NULL,
  amount numeric NOT NULL DEFAULT 0,
  used_amount numeric NOT NULL DEFAULT 0,
  remaining_amount numeric NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'pending'::text,
  journal_id text,
  journal_code text,
  created_entry_id uuid,
  extourne_entry_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS reimputation_logs (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  original_entry_id uuid,
  original_line_id uuid,
  reimputed_entry_id uuid,
  reimputed_line_id uuid,
  from_account text NOT NULL,
  to_account text NOT NULL,
  amount numeric NOT NULL DEFAULT 0,
  reason text,
  status text DEFAULT 'completed'::text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS reminder_levels (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  level integer NOT NULL,
  name text NOT NULL,
  template text,
  days_after_due integer NOT NULL DEFAULT 0,
  penalty_rate numeric DEFAULT 0,
  active boolean DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS reporting_plans (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  name text NOT NULL,
  report_type text NOT NULL,
  schedule text NOT NULL DEFAULT 'manual'::text,
  format text NOT NULL DEFAULT 'pdf'::text,
  recipients text,
  parameters jsonb DEFAULT '{}'::jsonb,
  last_generated timestamptz,
  active boolean DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS revision_cycles (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  name text NOT NULL,
  frequency text NOT NULL DEFAULT 'annual'::text,
  start_month integer NOT NULL DEFAULT 1,
  account_class text,
  active boolean DEFAULT true,
  last_run date,
  next_run date,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS rgpd_requests (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  request_type text NOT NULL,
  entity_type text NOT NULL,
  entity_id text,
  status text NOT NULL DEFAULT 'pending'::text,
  requested_by text,
  processed_by text,
  requested_at timestamptz NOT NULL DEFAULT now(),
  processed_at timestamptz,
  notes text
);

CREATE TABLE IF NOT EXISTS rh_dashboard_configs (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  user_email text NOT NULL,
  dashboard_type text NOT NULL,
  widgets jsonb DEFAULT '[]'::jsonb,
  filters jsonb DEFAULT '{}'::jsonb,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS rh_knowledge_base (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  title text NOT NULL,
  content text NOT NULL,
  category text,
  tags text[],
  author_id text,
  published boolean DEFAULT false,
  views integer DEFAULT 0,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS rh_reports (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  name text NOT NULL,
  report_type text NOT NULL,
  parameters jsonb DEFAULT '{}'::jsonb,
  chart_type text,
  data jsonb,
  data_calculated_at timestamptz,
  created_by text,
  shared boolean DEFAULT false,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS rh_requests (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  employee_id uuid NOT NULL,
  request_type text NOT NULL,
  subject text NOT NULL,
  description text,
  status text DEFAULT 'pending'::text,
  assigned_to text,
  response text,
  resolved_at timestamptz,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS routing_operations (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  routing_id uuid NOT NULL,
  sequence integer NOT NULL DEFAULT 10,
  name text NOT NULL,
  description text,
  work_center_id uuid,
  machine_id uuid,
  tooling_id uuid,
  setup_time_min integer DEFAULT 0,
  run_time_min integer DEFAULT 0,
  is_subcontracted boolean DEFAULT false,
  supplier_id uuid,
  st_unit text,
  st_quantity numeric DEFAULT 1,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS routings (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  code text NOT NULL,
  name text NOT NULL,
  description text,
  product_id uuid,
  version integer DEFAULT 1,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS salary_advances (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  employee_id uuid NOT NULL,
  amount numeric NOT NULL DEFAULT 0,
  advance_date date NOT NULL DEFAULT CURRENT_DATE,
  deduction_month date,
  status text DEFAULT 'pending'::text,
  notes text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS sales_order_lines (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  sales_order_id uuid,
  product_id uuid,
  description text NOT NULL,
  quantity numeric NOT NULL DEFAULT 1,
  unit_price numeric NOT NULL DEFAULT 0,
  vat_rate numeric DEFAULT 0,
  line_total numeric DEFAULT 0,
  tenant_id uuid NOT NULL,
  delivered_quantity numeric DEFAULT 0
);

CREATE TABLE IF NOT EXISTS sales_orders (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  number text NOT NULL,
  customer_id uuid,
  order_date date NOT NULL DEFAULT CURRENT_DATE,
  delivery_date date,
  status text NOT NULL DEFAULT 'draft'::text,
  subtotal numeric DEFAULT 0,
  vat numeric DEFAULT 0,
  total numeric DEFAULT 0,
  notes text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  tenant_id uuid NOT NULL,
  validation_status text DEFAULT 'draft'::text,
  quote_id uuid,
  fully_delivered boolean DEFAULT false,
  delivery_status text DEFAULT 'pending'::text
);

CREATE TABLE IF NOT EXISTS sales_representatives (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  name text NOT NULL,
  email text,
  phone text,
  commission_rate numeric DEFAULT 0,
  territory text,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS saved_filters (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  user_email text NOT NULL,
  page_name text NOT NULL,
  filter_name text NOT NULL,
  filter_criteria jsonb NOT NULL DEFAULT '{}'::jsonb,
  is_default boolean DEFAULT false,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS sepa_payment_orders (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  pay_run_id uuid,
  number text NOT NULL,
  execution_date date NOT NULL,
  total_amount numeric NOT NULL DEFAULT 0,
  currency text DEFAULT 'EUR'::text,
  employee_count integer DEFAULT 0,
  file_url text,
  file_generated_at timestamptz,
  status text DEFAULT 'draft'::text,
  transmitted_at timestamptz,
  processed_at timestamptz,
  notes text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS service_contracts (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  number text NOT NULL,
  customer_id uuid NOT NULL,
  name text NOT NULL,
  contract_type text,
  start_date date NOT NULL,
  end_date date,
  status text DEFAULT 'active'::text,
  sla_response_hours integer,
  sla_resolution_hours integer,
  coverage text,
  max_tickets integer,
  used_tickets integer DEFAULT 0,
  amount numeric,
  notes text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS service_ticket_messages (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  ticket_id uuid NOT NULL,
  author text NOT NULL,
  author_type text NOT NULL,
  message text NOT NULL,
  attachments jsonb,
  is_internal boolean DEFAULT false,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS service_tickets (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  number text NOT NULL,
  customer_id uuid NOT NULL,
  contact_id uuid,
  subject text NOT NULL,
  description text,
  category text,
  priority text DEFAULT 'normal'::text,
  status text DEFAULT 'open'::text,
  assigned_to text,
  sla_due_date timestamptz,
  first_response_at timestamptz,
  resolved_at timestamptz,
  closed_at timestamptz,
  satisfaction_rating integer,
  satisfaction_comment text,
  tags text[],
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS social_declarations (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  number text NOT NULL,
  declaration_type text NOT NULL,
  subtype text,
  period_month integer,
  period_year integer,
  period text,
  due_date date,
  status text DEFAULT 'draft'::text,
  file_url text,
  file_format text,
  generated_at timestamptz,
  transmitted_at timestamptz,
  response_code text,
  response_message text,
  anomalies jsonb DEFAULT '[]'::jsonb,
  amount numeric,
  employee_count integer,
  details jsonb DEFAULT '{}'::jsonb,
  notes text,
  created_at timestamptz DEFAULT now()
);

CREATE SEQUENCE IF NOT EXISTS sql_migrations_tracker_id_seq;

CREATE TABLE IF NOT EXISTS sql_migrations_tracker (
  id integer NOT NULL DEFAULT nextval('sql_migrations_tracker_id_seq'::regclass),
  filename text NOT NULL,
  executed_at timestamptz DEFAULT now(),
  status text DEFAULT 'success'::text,
  error_message text
);

CREATE TABLE IF NOT EXISTS st_orders (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  number text NOT NULL,
  supplier_id uuid NOT NULL,
  manufacturing_order_id uuid,
  routing_operation_id uuid,
  product_id uuid,
  quantity numeric NOT NULL DEFAULT 0,
  unit text DEFAULT 'unit'::text,
  unit_price numeric DEFAULT 0,
  total_price numeric DEFAULT 0,
  status text DEFAULT 'draft'::text,
  order_date date NOT NULL DEFAULT CURRENT_DATE,
  expected_date date,
  notes text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS st_receipt_lines (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  st_receipt_id uuid NOT NULL,
  product_id uuid NOT NULL,
  quantity numeric NOT NULL DEFAULT 0,
  unit text DEFAULT 'unit'::text,
  line_type text DEFAULT 'received'::text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS st_receipts (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  number text NOT NULL,
  st_order_id uuid NOT NULL,
  receipt_date date NOT NULL DEFAULT CURRENT_DATE,
  warehouse_id uuid,
  quantity_received numeric DEFAULT 0,
  quantity_returned numeric DEFAULT 0,
  status text DEFAULT 'pending'::text,
  notes text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS st_shipment_lines (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  st_shipment_id uuid NOT NULL,
  product_id uuid NOT NULL,
  quantity numeric NOT NULL DEFAULT 0,
  unit text DEFAULT 'unit'::text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS st_shipments (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  number text NOT NULL,
  st_order_id uuid NOT NULL,
  shipment_date date NOT NULL DEFAULT CURRENT_DATE,
  warehouse_id uuid,
  status text DEFAULT 'pending'::text,
  notes text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS staff_requirements (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  department text NOT NULL,
  min_staff integer NOT NULL DEFAULT 1,
  days_of_week text[] DEFAULT '{1,2,3,4,5}'::text[],
  start_date date,
  end_date date,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS standard_labels (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  label text NOT NULL,
  category text,
  created_at timestamptz DEFAULT now(),
  tenant_id uuid NOT NULL
);

CREATE TABLE IF NOT EXISTS stat_fields (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  entity_type text NOT NULL,
  entity_id text NOT NULL,
  field_name text NOT NULL,
  field_value text,
  field_type text NOT NULL DEFAULT 'text'::text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS stock_alerts (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  product_id uuid NOT NULL,
  warehouse_id uuid,
  alert_type text NOT NULL,
  threshold numeric,
  current_value numeric,
  status text DEFAULT 'active'::text,
  triggered_at timestamptz DEFAULT now(),
  resolved_at timestamptz,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS stock_movements (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  product_id uuid,
  type text,
  quantity numeric NOT NULL DEFAULT 0,
  reference text,
  date date NOT NULL DEFAULT CURRENT_DATE,
  created_at timestamptz DEFAULT now(),
  warehouse_id uuid,
  movement_type text,
  unit_cost numeric DEFAULT 0,
  reference_type text,
  reference_id uuid,
  movement_date date DEFAULT CURRENT_DATE,
  notes text,
  tenant_id uuid NOT NULL
);

CREATE TABLE IF NOT EXISTS stock_quantities (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  product_id uuid NOT NULL,
  warehouse_id uuid NOT NULL,
  quantity numeric NOT NULL DEFAULT 0,
  reserved_quantity numeric NOT NULL DEFAULT 0,
  min_quantity numeric DEFAULT 0,
  max_quantity numeric DEFAULT 0,
  reorder_point numeric DEFAULT 0,
  unit_cost numeric DEFAULT 0,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  tenant_id uuid NOT NULL,
  location_id uuid,
  incoming_quantity numeric DEFAULT 0
);

CREATE TABLE IF NOT EXISTS supplier_contacts (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  supplier_id uuid NOT NULL,
  name text NOT NULL,
  role text,
  email text,
  phone text,
  mobile text,
  is_default boolean DEFAULT false,
  active boolean DEFAULT true,
  notes text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS supplier_delivery_schedules (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  supplier_id uuid NOT NULL,
  product_id uuid NOT NULL,
  warehouse_id uuid,
  frequency text NOT NULL,
  monday_qty numeric DEFAULT 0,
  tuesday_qty numeric DEFAULT 0,
  wednesday_qty numeric DEFAULT 0,
  thursday_qty numeric DEFAULT 0,
  friday_qty numeric DEFAULT 0,
  saturday_qty numeric DEFAULT 0,
  sunday_qty numeric DEFAULT 0,
  start_date date NOT NULL DEFAULT CURRENT_DATE,
  end_date date,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS supplier_payments (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  number text NOT NULL,
  supplier_id uuid,
  purchase_invoice_id uuid,
  payment_date date NOT NULL DEFAULT CURRENT_DATE,
  amount numeric NOT NULL DEFAULT 0,
  method text,
  bank_account_id uuid,
  reference text,
  status text NOT NULL DEFAULT 'recorded'::text,
  created_at timestamptz DEFAULT now(),
  tenant_id uuid NOT NULL,
  currency_code text DEFAULT 'EUR'::text,
  exchange_rate numeric DEFAULT 1.0,
  amount_currency numeric,
  exchange_gain_loss numeric DEFAULT 0,
  transferred_entry_id uuid
);

CREATE TABLE IF NOT EXISTS supplier_price_list_lines (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  price_list_id uuid NOT NULL,
  product_id uuid NOT NULL,
  supplier_ref text,
  unit_price numeric NOT NULL,
  min_quantity numeric DEFAULT 1,
  discount_percent numeric DEFAULT 0,
  lead_time_days integer,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS supplier_price_lists (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  supplier_id uuid NOT NULL,
  name text NOT NULL,
  valid_from date NOT NULL DEFAULT CURRENT_DATE,
  valid_to date,
  currency_code text DEFAULT 'EUR'::text,
  min_quantity numeric DEFAULT 1,
  discount_percent numeric DEFAULT 0,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS suppliers (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  name text NOT NULL,
  email text,
  phone text,
  address text,
  city text,
  postal_code text,
  country text DEFAULT 'France'::text,
  vat_number text,
  contact_name text,
  balance numeric DEFAULT 0,
  payment_terms text DEFAULT '30 days'::text,
  currency text DEFAULT 'EUR'::text,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  tenant_id uuid NOT NULL,
  legal_form text,
  ape_code text,
  naf_code text,
  employee_count_range text,
  revenue_range text,
  payment_delay_avg integer,
  siret text,
  sector_code text,
  geographic_zone text,
  parent_id uuid,
  is_company boolean DEFAULT true,
  sales_rep_id uuid,
  currency_code text DEFAULT 'EUR'::text,
  bank_account_id uuid,
  price_list_id uuid,
  email_settings jsonb DEFAULT '{}'::jsonb
);

CREATE TABLE IF NOT EXISTS task_action_attachments (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  task_action_id uuid NOT NULL,
  task_id uuid NOT NULL,
  file_name varchar(255) NOT NULL,
  file_path varchar(500) NOT NULL,
  file_size bigint,
  mime_type varchar(100),
  uploader_id uuid,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS task_actions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  task_id uuid NOT NULL,
  title varchar(100) NOT NULL,
  weight_percentage integer DEFAULT 0,
  is_done boolean DEFAULT false,
  due_date date,
  notes text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS task_comments (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  task_id uuid NOT NULL,
  content text NOT NULL,
  comment_type varchar(20) DEFAULT 'general'::character varying,
  author_id uuid,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS task_documents (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  task_id uuid NOT NULL,
  project_id uuid,
  file_name varchar(255) NOT NULL,
  file_path varchar(500) NOT NULL,
  file_size bigint,
  mime_type varchar(100),
  uploader_id uuid,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS tax_cash_basis_entries (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  tax_id uuid,
  payment_id uuid,
  journal_entry_id uuid,
  base_amount numeric,
  tax_amount numeric,
  transition_date date,
  status text DEFAULT 'pending'::text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS tax_groups (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  name text NOT NULL,
  country_code text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS tax_payments (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  payment_number text NOT NULL,
  tax_type text NOT NULL,
  period_label text NOT NULL,
  period_start date NOT NULL,
  period_end date NOT NULL,
  amount numeric NOT NULL DEFAULT 0,
  payment_date date NOT NULL,
  payment_method text NOT NULL DEFAULT 'telepayment'::text,
  bank_account_id uuid,
  status text NOT NULL DEFAULT 'draft'::text,
  confirmation_number text,
  journal_entry_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS tax_rates (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  pack_code text NOT NULL,
  name text NOT NULL,
  category text NOT NULL,
  rate numeric NOT NULL,
  account_code text,
  is_default boolean NOT NULL DEFAULT false,
  effective_from date NOT NULL DEFAULT '1900-01-01'::date,
  effective_to date,
  created_at timestamptz DEFAULT now(),
  tenant_id uuid,
  account_collectee text,
  account_deductible text,
  type text DEFAULT 'CA3'::text,
  mode text DEFAULT 'debits'::text,
  amount_type text DEFAULT 'percent'::text,
  type_tax_use text DEFAULT 'none'::text,
  sequence integer DEFAULT 10,
  parent_tax_id uuid,
  tax_exigibility text DEFAULT 'on_invoice'::text,
  cash_basis_transition_account text,
  price_include boolean DEFAULT false,
  include_base_amount boolean DEFAULT false,
  is_base_affected boolean DEFAULT true,
  analytic boolean DEFAULT false,
  fixed_amount numeric
);

CREATE TABLE IF NOT EXISTS tax_repartition_lines (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  tax_id uuid NOT NULL,
  document_type text NOT NULL,
  repartition_type text NOT NULL,
  factor numeric DEFAULT 100,
  account_code text,
  tag_ids text[],
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS tenant_users (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid NOT NULL,
  auth_id uuid,
  email text NOT NULL,
  name text NOT NULL,
  role text NOT NULL DEFAULT 'viewer'::text,
  permissions jsonb DEFAULT '{}'::jsonb,
  status text NOT NULL DEFAULT 'pending'::text,
  invited_by uuid,
  invited_at timestamptz DEFAULT now(),
  accepted_at timestamptz,
  last_login timestamptz,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  valid_from date,
  valid_until date,
  module_roles jsonb DEFAULT '{}'::jsonb,
  guest_permissions jsonb DEFAULT '{}'::jsonb
);

CREATE TABLE IF NOT EXISTS tenants (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  name text NOT NULL,
  legal_name text,
  siren text,
  siret text,
  vat_number text,
  address text,
  city text,
  postal_code text,
  country text DEFAULT 'France'::text,
  currency text DEFAULT 'EUR'::text,
  phone text,
  email text,
  logo_url text,
  status text NOT NULL DEFAULT 'active'::text,
  plan text NOT NULL DEFAULT 'trial'::text,
  trial_ends_at timestamptz,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  country_code text,
  legislation_pack_code text,
  enabled_modules jsonb NOT NULL DEFAULT '["home", "accounting", "commercial", "treasury", "stock", "production", "hr", "dashboards", "reporting", "system"]'::jsonb
);

CREATE TABLE IF NOT EXISTS third_party_accounts (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  code text NOT NULL,
  account_general_code text,
  type text NOT NULL,
  name text NOT NULL,
  customer_id uuid,
  supplier_id uuid,
  employee_id uuid,
  balance numeric DEFAULT 0,
  lettrage_code text,
  currency text DEFAULT 'EUR'::text,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  tenant_id uuid NOT NULL,
  payment_term_id uuid,
  default_bank_account_id uuid,
  credit_limit numeric DEFAULT 0
);

CREATE TABLE IF NOT EXISTS tier_ribs (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
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

CREATE TABLE IF NOT EXISTS timesheets (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  employee_id uuid,
  date date NOT NULL DEFAULT CURRENT_DATE,
  hours numeric DEFAULT 0,
  description text,
  project_id uuid,
  status text NOT NULL DEFAULT 'pending'::text,
  created_at timestamptz DEFAULT now(),
  tenant_id uuid NOT NULL
);

CREATE TABLE IF NOT EXISTS toolings (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  code text NOT NULL,
  name text NOT NULL,
  machine_id uuid,
  max_pieces integer DEFAULT 0,
  initial_counter integer DEFAULT 0,
  current_counter integer DEFAULT 0,
  status text DEFAULT 'active'::text,
  notes text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS treasury_recurring (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  description text NOT NULL,
  bank_account_id uuid,
  amount numeric NOT NULL DEFAULT 0,
  type text NOT NULL,
  frequency text DEFAULT 'monthly'::text,
  next_date date NOT NULL DEFAULT CURRENT_DATE,
  end_date date,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS treasury_transfers (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  number text NOT NULL,
  from_account_id uuid NOT NULL,
  to_account_id uuid NOT NULL,
  amount numeric NOT NULL DEFAULT 0,
  transfer_date date NOT NULL DEFAULT CURRENT_DATE,
  value_date date,
  status text DEFAULT 'draft'::text,
  journal_entry_id uuid,
  notes text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS tvs_declarations (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  fiscal_year integer NOT NULL,
  vehicle_registration text NOT NULL,
  vehicle_type text,
  co2_emissions integer,
  first_registration_date date,
  amount_co2 numeric DEFAULT 0,
  amount_age numeric DEFAULT 0,
  amount_total numeric DEFAULT 0,
  status text DEFAULT 'draft'::text,
  filed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS users (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  auth_id uuid,
  name text NOT NULL,
  email text NOT NULL,
  role text NOT NULL DEFAULT 'viewer'::text,
  active boolean DEFAULT true,
  last_login timestamptz,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  tenant_id uuid
);

CREATE TABLE IF NOT EXISTS v_tenant_id (
  id uuid
);

CREATE TABLE IF NOT EXISTS value_date_tracking (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  bank_account_id uuid NOT NULL,
  transaction_id uuid,
  operation_date date NOT NULL,
  value_date date NOT NULL,
  amount numeric NOT NULL DEFAULT 0,
  transaction_type text,
  notes text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS vat_on_collections (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  fiscal_year_id uuid,
  period_label text NOT NULL,
  period_start date NOT NULL,
  period_end date NOT NULL,
  vat_base numeric NOT NULL DEFAULT 0,
  vat_rate numeric NOT NULL DEFAULT 0,
  vat_amount numeric NOT NULL DEFAULT 0,
  collected_amount numeric NOT NULL DEFAULT 0,
  uncollected_amount numeric NOT NULL DEFAULT 0,
  vat_collected numeric NOT NULL DEFAULT 0,
  vat_uncollected numeric NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'draft'::text,
  journal_entry_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS vat_returns (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  period_start date NOT NULL,
  period_end date NOT NULL,
  status text NOT NULL DEFAULT 'draft'::text,
  box1_output_vat numeric DEFAULT 0,
  box2_input_vat numeric DEFAULT 0,
  box3_vat_due numeric DEFAULT 0,
  box4_repayment_due numeric DEFAULT 0,
  box5_net_vat numeric DEFAULT 0,
  total_sales numeric DEFAULT 0,
  total_purchases numeric DEFAULT 0,
  submitted_date date,
  created_at timestamptz DEFAULT now(),
  tenant_id uuid NOT NULL,
  edi_tva_id text,
  edi_status text DEFAULT 'not_submitted'::text,
  edi_submitted_at timestamptz,
  edi_acknowledgment text,
  edi_acknowledged_at timestamptz,
  deposits_vat_collected numeric DEFAULT 0,
  deposits_vat_deductible numeric DEFAULT 0
);

CREATE TABLE IF NOT EXISTS warehouse_locations (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  warehouse_id uuid NOT NULL,
  zone text,
  aisle text,
  shelf text,
  code text NOT NULL,
  description text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS warehouse_users (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  warehouse_id uuid NOT NULL,
  user_email text NOT NULL,
  role text DEFAULT 'operator'::text,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS warehouses (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  code text NOT NULL,
  name text NOT NULL,
  address text,
  city text,
  postal_code text,
  country text DEFAULT 'France'::text,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  tenant_id uuid NOT NULL
);

CREATE TABLE IF NOT EXISTS work_centers (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  code text NOT NULL,
  name text NOT NULL,
  capacity_hours_per_day numeric DEFAULT 8,
  cost_per_hour numeric DEFAULT 0,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS work_hardship (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  employee_id uuid NOT NULL,
  exposure_type text NOT NULL,
  exposure_level text,
  start_date date,
  end_date date,
  points integer DEFAULT 0,
  notes text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS work_hardship_records (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  employee_id uuid NOT NULL,
  exposure_type text NOT NULL,
  exposure_level text NOT NULL,
  exposure_start date,
  exposure_end date,
  duration_months integer,
  points numeric DEFAULT 0,
  declaration_status text DEFAULT 'pending'::text,
  declared_at timestamptz,
  notes text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS work_stoppages (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id uuid,
  employee_id uuid NOT NULL,
  stoppage_type text NOT NULL,
  start_date date NOT NULL,
  end_date date,
  expected_end_date date,
  reprise_date date,
  reprise_type text,
  days_count numeric,
  working_days_count numeric,
  subrogation boolean DEFAULT false,
  net_guarantee boolean DEFAULT false,
  ijss_net_amount numeric DEFAULT 0,
  ijss_brut_amount numeric DEFAULT 0,
  ijss_daily_rate numeric DEFAULT 0,
  ijss_days_count integer DEFAULT 0,
  ijss_care_days integer DEFAULT 0,
  pas_days_count integer DEFAULT 0,
  employer_maintenance_amount numeric DEFAULT 0,
  employer_maintenance_rate numeric DEFAULT 100,
  bpij_number text,
  bpij_imported_at timestamptz,
  regularization_amount numeric DEFAULT 0,
  regularization_type text,
  medical_certificate_url text,
  notes text,
  status text DEFAULT 'active'::text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS workflows (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  tenant_id uuid,
  name text NOT NULL,
  description text,
  workflow_type text,
  schedule text,
  last_run timestamptz,
  status text DEFAULT 'active'::text,
  created_at timestamptz DEFAULT now()
);

-- ============================================
-- CONTRAINTES
-- ============================================
DO $$ BEGIN ALTER TABLE account_tag_mappings ADD CONSTRAINT account_tag_mappings_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE account_tags ADD CONSTRAINT account_tags_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE accounting_control_runs ADD CONSTRAINT accounting_control_runs_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE analytic_distribution_lines ADD CONSTRAINT analytic_distribution_lines_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE analytic_journal_codes ADD CONSTRAINT analytic_journal_codes_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE analytic_plans ADD CONSTRAINT analytic_plans_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE analytic_sections ADD CONSTRAINT analytic_sections_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE approval_workflows ADD CONSTRAINT approval_workflows_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE asset_batch_disposal_lines ADD CONSTRAINT asset_batch_disposal_lines_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE asset_batch_disposals ADD CONSTRAINT asset_batch_disposals_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE asset_depreciation_plans ADD CONSTRAINT asset_depreciation_plans_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE asset_depreciations ADD CONSTRAINT asset_depreciations_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE asset_documents ADD CONSTRAINT asset_documents_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE asset_families ADD CONSTRAINT asset_families_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE asset_free_fields ADD CONSTRAINT asset_free_fields_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE asset_revaluations ADD CONSTRAINT asset_revaluations_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE asset_split_components ADD CONSTRAINT asset_split_components_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE asset_splits ADD CONSTRAINT asset_splits_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE at_rates ADD CONSTRAINT at_rates_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE audit_log ADD CONSTRAINT audit_log_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE auto_label_rules ADD CONSTRAINT auto_label_rules_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bank_accounts ADD CONSTRAINT bank_accounts_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bank_connections ADD CONSTRAINT bank_connections_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bank_reconciliation_rules ADD CONSTRAINT bank_reconciliation_rules_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bank_rules ADD CONSTRAINT bank_rules_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bank_statement_imports ADD CONSTRAINT bank_statement_imports_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bank_statement_templates ADD CONSTRAINT bank_statement_templates_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bank_transactions ADD CONSTRAINT bank_transactions_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE banks ADD CONSTRAINT banks_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE batch_entry_sessions ADD CONSTRAINT batch_entry_sessions_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bdes_indicators ADD CONSTRAINT bdes_indicators_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bom_lines ADD CONSTRAINT bom_lines_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE boms ADD CONSTRAINT boms_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE budget_commitments ADD CONSTRAINT budget_commitments_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE budgets ADD CONSTRAINT budgets_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE career_history ADD CONSTRAINT career_history_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE carry_forward_log ADD CONSTRAINT carry_forward_log_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE cash_control_sessions ADD CONSTRAINT cash_control_sessions_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE chart_account_templates ADD CONSTRAINT chart_account_templates_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE chart_accounts ADD CONSTRAINT chart_accounts_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE check_books ADD CONSTRAINT check_books_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE checks ADD CONSTRAINT checks_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE cice_config ADD CONSTRAINT cice_config_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE collection_reminders ADD CONSTRAINT collection_reminders_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE compaction_logs ADD CONSTRAINT compaction_logs_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE company_settings ADD CONSTRAINT company_settings_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE consolidated_treasury ADD CONSTRAINT consolidated_treasury_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE contracts ADD CONSTRAINT contracts_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE corporate_tax_grid_lines ADD CONSTRAINT corporate_tax_grid_lines_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE corporate_tax_grids ADD CONSTRAINT corporate_tax_grids_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE cpf_accounts ADD CONSTRAINT cpf_accounts_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE cpf_transactions ADD CONSTRAINT cpf_transactions_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE credit_lines ADD CONSTRAINT credit_lines_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE credit_note_lines ADD CONSTRAINT credit_note_lines_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE credit_notes ADD CONSTRAINT credit_notes_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE crm_activities ADD CONSTRAINT crm_activities_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE crm_campaign_recipients ADD CONSTRAINT crm_campaign_recipients_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE crm_campaigns ADD CONSTRAINT crm_campaigns_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE crm_forecasts ADD CONSTRAINT crm_forecasts_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE crm_opportunities ADD CONSTRAINT crm_opportunities_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE crm_territories ADD CONSTRAINT crm_territories_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE currencies ADD CONSTRAINT currencies_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE currency_revaluations ADD CONSTRAINT currency_revaluations_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE custom_report_templates ADD CONSTRAINT custom_report_templates_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE customer_contacts ADD CONSTRAINT customer_contacts_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE customer_payments ADD CONSTRAINT customer_payments_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE customers ADD CONSTRAINT customers_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE dashboard_widgets ADD CONSTRAINT dashboard_widgets_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE deferred_printing_jobs ADD CONSTRAINT deferred_printing_jobs_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE delivery_note_lines ADD CONSTRAINT delivery_note_lines_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE delivery_notes ADD CONSTRAINT delivery_notes_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE delivery_schedules ADD CONSTRAINT delivery_schedules_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE disputes ADD CONSTRAINT disputes_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE distribution_grill_lines ADD CONSTRAINT distribution_grill_lines_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE distribution_grills ADD CONSTRAINT distribution_grills_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE document_charges ADD CONSTRAINT document_charges_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE document_distribution_logs ADD CONSTRAINT document_distribution_logs_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE document_shares ADD CONSTRAINT document_shares_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE document_templates ADD CONSTRAINT document_templates_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE document_transformations ADD CONSTRAINT document_transformations_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE dpae_records ADD CONSTRAINT dpae_records_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE dsn_declarations ADD CONSTRAINT dsn_declarations_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE electronic_signatures ADD CONSTRAINT electronic_signatures_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE employee_activity_logs ADD CONSTRAINT employee_activity_logs_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE employee_documents ADD CONSTRAINT employee_documents_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE employee_exit_processes ADD CONSTRAINT employee_exit_processes_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE employee_objectives ADD CONSTRAINT employee_objectives_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE employees ADD CONSTRAINT employees_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE entry_templates ADD CONSTRAINT entry_templates_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE etat_rapprochement ADD CONSTRAINT etat_rapprochement_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE exchange_gain_loss_entries ADD CONSTRAINT exchange_gain_loss_entries_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE exchange_rates ADD CONSTRAINT exchange_rates_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE expense_categories ADD CONSTRAINT expense_categories_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE expense_report_lines ADD CONSTRAINT expense_report_lines_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE expense_reports ADD CONSTRAINT expense_reports_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE extourne_log ADD CONSTRAINT extourne_log_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fec_attestations ADD CONSTRAINT fec_attestations_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fiscal_backups ADD CONSTRAINT fiscal_backups_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fiscal_periods ADD CONSTRAINT fiscal_periods_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fiscal_position_mappings ADD CONSTRAINT fiscal_position_mappings_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fiscal_positions ADD CONSTRAINT fiscal_positions_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fiscal_years ADD CONSTRAINT fiscal_years_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fixed_assets ADD CONSTRAINT fixed_assets_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fusion_logs ADD CONSTRAINT fusion_logs_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE future_accounting_movements ADD CONSTRAINT future_accounting_movements_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE goods_receipt_lines ADD CONSTRAINT goods_receipt_lines_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE goods_receipts ADD CONSTRAINT goods_receipts_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE grid_templates ADD CONSTRAINT grid_templates_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE honorarium_records ADD CONSTRAINT honorarium_records_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ifrs_adjustments ADD CONSTRAINT ifrs_adjustments_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ijss_history ADD CONSTRAINT ijss_history_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE interview_campaigns ADD CONSTRAINT interview_campaigns_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE interviews ADD CONSTRAINT interviews_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE investments ADD CONSTRAINT investments_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE invoice_lines ADD CONSTRAINT invoice_lines_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE invoices ADD CONSTRAINT invoices_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE journal_access_rights ADD CONSTRAINT journal_access_rights_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE journal_entries ADD CONSTRAINT journal_entries_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE journal_lines ADD CONSTRAINT journal_lines_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE journals ADD CONSTRAINT journals_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE justificatif_solde ADD CONSTRAINT justificatif_solde_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE knowledge_base_articles ADD CONSTRAINT knowledge_base_articles_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE leave_balances ADD CONSTRAINT leave_balances_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE leave_provisions ADD CONSTRAINT leave_provisions_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE leave_requests ADD CONSTRAINT leave_requests_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE leave_rules ADD CONSTRAINT leave_rules_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE legal_declarations ADD CONSTRAINT legal_declarations_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE legal_watch ADD CONSTRAINT legal_watch_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE legislation_packs ADD CONSTRAINT legislation_packs_pkey PRIMARY KEY (code); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE lettrage_differences ADD CONSTRAINT lettrage_differences_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE machines ADD CONSTRAINT machines_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE manufacturing_orders ADD CONSTRAINT manufacturing_orders_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE marking_types ADD CONSTRAINT marking_types_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE meal_voucher_config ADD CONSTRAINT meal_voucher_config_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE medical_exams ADD CONSTRAINT medical_exams_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE mirror_servers ADD CONSTRAINT mirror_servers_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE mirror_verification_details ADD CONSTRAINT mirror_verification_details_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE module_document_access_log ADD CONSTRAINT module_document_access_log_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE module_document_shares ADD CONSTRAINT module_document_shares_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE module_documents ADD CONSTRAINT module_documents_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE mrp_pending_docs ADD CONSTRAINT mrp_pending_docs_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE mrp_proposals ADD CONSTRAINT mrp_proposals_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE mrp_runs ADD CONSTRAINT mrp_runs_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE notification_email_queue ADD CONSTRAINT notification_email_queue_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE notification_preferences ADD CONSTRAINT notification_preferences_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE of_consumptions ADD CONSTRAINT of_consumptions_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE of_document_access ADD CONSTRAINT of_document_access_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE of_labels ADD CONSTRAINT of_labels_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE of_lots ADD CONSTRAINT of_lots_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE online_payments ADD CONSTRAINT online_payments_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE partner_bank_accounts ADD CONSTRAINT partner_bank_accounts_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE partner_categories ADD CONSTRAINT partner_categories_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE partner_category_mappings ADD CONSTRAINT partner_category_mappings_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE partner_contacts ADD CONSTRAINT partner_contacts_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE pas_rates ADD CONSTRAINT pas_rates_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE pay_recalls ADD CONSTRAINT pay_recalls_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE pay_runs ADD CONSTRAINT pay_runs_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE pay_slip_clarified ADD CONSTRAINT pay_slip_clarified_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE pay_slips ADD CONSTRAINT pay_slips_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE payment_orders ADD CONSTRAINT payment_orders_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE payment_promises ADD CONSTRAINT payment_promises_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE payment_templates_compta ADD CONSTRAINT payment_templates_compta_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE payment_terms ADD CONSTRAINT payment_terms_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE payroll_accounting_entries ADD CONSTRAINT payroll_accounting_entries_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE payroll_archives ADD CONSTRAINT payroll_archives_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE payroll_component_rates ADD CONSTRAINT payroll_component_rates_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE payroll_components ADD CONSTRAINT payroll_components_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE payroll_tax_grid_lines ADD CONSTRAINT payroll_tax_grid_lines_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE payroll_tax_grids ADD CONSTRAINT payroll_tax_grids_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE payroll_templates ADD CONSTRAINT payroll_templates_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE payroll_variable_elements ADD CONSTRAINT payroll_variable_elements_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE pick_list_lines ADD CONSTRAINT pick_list_lines_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE pick_lists ADD CONSTRAINT pick_lists_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE planning_slots ADD CONSTRAINT planning_slots_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE pos_sessions ADD CONSTRAINT pos_sessions_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE pos_terminals ADD CONSTRAINT pos_terminals_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE pos_ticket_lines ADD CONSTRAINT pos_ticket_lines_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE pos_tickets ADD CONSTRAINT pos_tickets_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE price_list_lines ADD CONSTRAINT price_list_lines_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE price_lists ADD CONSTRAINT price_lists_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE product_attributes ADD CONSTRAINT product_attributes_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE product_batches ADD CONSTRAINT product_batches_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE product_equivalences ADD CONSTRAINT product_equivalences_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE product_grid_combinations ADD CONSTRAINT product_grid_combinations_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE product_grids ADD CONSTRAINT product_grids_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE product_links ADD CONSTRAINT product_links_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE product_packagings ADD CONSTRAINT product_packagings_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE product_serial_numbers ADD CONSTRAINT product_serial_numbers_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE product_substitutes ADD CONSTRAINT product_substitutes_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE product_variants ADD CONSTRAINT product_variants_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE production_forecasts ADD CONSTRAINT production_forecasts_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE products ADD CONSTRAINT products_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE project_activity_log ADD CONSTRAINT project_activity_log_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE project_docs ADD CONSTRAINT project_docs_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE project_members ADD CONSTRAINT project_members_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE project_milestones ADD CONSTRAINT project_milestones_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE project_notifications ADD CONSTRAINT project_notifications_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE project_stages ADD CONSTRAINT project_stages_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE project_tags ADD CONSTRAINT project_tags_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE project_task_assignees ADD CONSTRAINT project_task_assignees_pkey PRIMARY KEY (task_id, employee_id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE project_task_dependencies ADD CONSTRAINT project_task_dependencies_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE project_task_tags ADD CONSTRAINT project_task_tags_pkey PRIMARY KEY (task_id, tag_id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE project_task_templates ADD CONSTRAINT project_task_templates_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE project_task_watchers ADD CONSTRAINT project_task_watchers_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE project_tasks ADD CONSTRAINT project_tasks_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE project_time_entries ADD CONSTRAINT project_time_entries_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE projects ADD CONSTRAINT projects_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE promotions ADD CONSTRAINT promotions_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE prospects ADD CONSTRAINT prospects_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE public_holidays ADD CONSTRAINT public_holidays_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE purchase_credit_lines ADD CONSTRAINT purchase_credit_lines_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE purchase_credit_notes ADD CONSTRAINT purchase_credit_notes_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE purchase_invoice_lines ADD CONSTRAINT purchase_invoice_lines_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE purchase_invoices ADD CONSTRAINT purchase_invoices_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE purchase_order_lines ADD CONSTRAINT purchase_order_lines_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE purchase_orders ADD CONSTRAINT purchase_orders_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE purchase_request_lines ADD CONSTRAINT purchase_request_lines_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE purchase_requests ADD CONSTRAINT purchase_requests_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE quality_checks ADD CONSTRAINT quality_checks_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE quote_lines ADD CONSTRAINT quote_lines_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE quotes ADD CONSTRAINT quotes_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE recurring_entries ADD CONSTRAINT recurring_entries_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE recurring_invoice_templates ADD CONSTRAINT recurring_invoice_templates_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE regularization_entries ADD CONSTRAINT regularization_entries_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE reimputation_logs ADD CONSTRAINT reimputation_logs_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE reminder_levels ADD CONSTRAINT reminder_levels_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE reporting_plans ADD CONSTRAINT reporting_plans_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE revision_cycles ADD CONSTRAINT revision_cycles_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE rgpd_requests ADD CONSTRAINT rgpd_requests_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE rh_dashboard_configs ADD CONSTRAINT rh_dashboard_configs_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE rh_knowledge_base ADD CONSTRAINT rh_knowledge_base_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE rh_reports ADD CONSTRAINT rh_reports_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE rh_requests ADD CONSTRAINT rh_requests_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE routing_operations ADD CONSTRAINT routing_operations_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE routings ADD CONSTRAINT routings_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE salary_advances ADD CONSTRAINT salary_advances_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE sales_order_lines ADD CONSTRAINT sales_order_lines_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE sales_orders ADD CONSTRAINT sales_orders_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE sales_representatives ADD CONSTRAINT sales_representatives_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE saved_filters ADD CONSTRAINT saved_filters_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE sepa_payment_orders ADD CONSTRAINT sepa_payment_orders_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE service_contracts ADD CONSTRAINT service_contracts_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE service_ticket_messages ADD CONSTRAINT service_ticket_messages_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE service_tickets ADD CONSTRAINT service_tickets_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE social_declarations ADD CONSTRAINT social_declarations_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE sql_migrations_tracker ADD CONSTRAINT sql_migrations_tracker_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE st_orders ADD CONSTRAINT st_orders_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE st_receipt_lines ADD CONSTRAINT st_receipt_lines_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE st_receipts ADD CONSTRAINT st_receipts_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE st_shipment_lines ADD CONSTRAINT st_shipment_lines_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE st_shipments ADD CONSTRAINT st_shipments_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE staff_requirements ADD CONSTRAINT staff_requirements_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE standard_labels ADD CONSTRAINT standard_labels_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE stat_fields ADD CONSTRAINT stat_fields_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE stock_alerts ADD CONSTRAINT stock_alerts_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE stock_movements ADD CONSTRAINT stock_movements_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE stock_quantities ADD CONSTRAINT stock_quantities_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE supplier_contacts ADD CONSTRAINT supplier_contacts_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE supplier_delivery_schedules ADD CONSTRAINT supplier_delivery_schedules_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE supplier_payments ADD CONSTRAINT supplier_payments_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE supplier_price_list_lines ADD CONSTRAINT supplier_price_list_lines_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE supplier_price_lists ADD CONSTRAINT supplier_price_lists_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE suppliers ADD CONSTRAINT suppliers_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE task_action_attachments ADD CONSTRAINT task_action_attachments_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE task_actions ADD CONSTRAINT task_actions_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE task_comments ADD CONSTRAINT task_comments_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE task_documents ADD CONSTRAINT task_documents_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE tax_cash_basis_entries ADD CONSTRAINT tax_cash_basis_entries_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE tax_groups ADD CONSTRAINT tax_groups_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE tax_payments ADD CONSTRAINT tax_payments_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE tax_rates ADD CONSTRAINT tax_rates_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE tax_repartition_lines ADD CONSTRAINT tax_repartition_lines_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE tenant_users ADD CONSTRAINT tenant_users_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE tenants ADD CONSTRAINT tenants_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE third_party_accounts ADD CONSTRAINT third_party_accounts_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE tier_ribs ADD CONSTRAINT tier_ribs_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE timesheets ADD CONSTRAINT timesheets_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE toolings ADD CONSTRAINT toolings_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE treasury_recurring ADD CONSTRAINT treasury_recurring_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE treasury_transfers ADD CONSTRAINT treasury_transfers_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE tvs_declarations ADD CONSTRAINT tvs_declarations_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE users ADD CONSTRAINT users_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE value_date_tracking ADD CONSTRAINT value_date_tracking_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE vat_on_collections ADD CONSTRAINT vat_on_collections_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE vat_returns ADD CONSTRAINT vat_returns_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE warehouse_locations ADD CONSTRAINT warehouse_locations_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE warehouse_users ADD CONSTRAINT warehouse_users_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE warehouses ADD CONSTRAINT warehouses_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE work_centers ADD CONSTRAINT work_centers_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE work_hardship ADD CONSTRAINT work_hardship_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE work_hardship_records ADD CONSTRAINT work_hardship_records_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE work_stoppages ADD CONSTRAINT work_stoppages_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE workflows ADD CONSTRAINT workflows_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE analytic_sections ADD CONSTRAINT analytic_sections_tenant_code_key UNIQUE (tenant_id, code); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE banks ADD CONSTRAINT banks_name_key UNIQUE (name); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE boms ADD CONSTRAINT boms_code_key UNIQUE (code); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE chart_account_templates ADD CONSTRAINT chart_account_templates_pack_code_code_key UNIQUE (pack_code, code); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE chart_accounts ADD CONSTRAINT chart_accounts_tenant_code_key UNIQUE (tenant_id, code); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE collection_reminders ADD CONSTRAINT collection_reminders_number_key UNIQUE (number); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE collection_reminders ADD CONSTRAINT collection_reminders_payment_link_token_key UNIQUE (payment_link_token); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE contracts ADD CONSTRAINT contracts_number_key UNIQUE (number); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE cpf_accounts ADD CONSTRAINT cpf_accounts_employee_unique UNIQUE (employee_id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE credit_notes ADD CONSTRAINT credit_notes_tenant_number_key UNIQUE (tenant_id, number); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE credit_notes ADD CONSTRAINT uniq_credit_note_number_tenant UNIQUE (tenant_id, number); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE currencies ADD CONSTRAINT currencies_code_unique UNIQUE (code); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE currencies ADD CONSTRAINT currencies_tenant_code_key UNIQUE (tenant_id, code); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE customer_payments ADD CONSTRAINT customer_payments_number_key UNIQUE (number); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE delivery_notes ADD CONSTRAINT delivery_notes_number_key UNIQUE (number); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fiscal_years ADD CONSTRAINT fiscal_years_tenant_code_key UNIQUE (tenant_id, code); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fixed_assets ADD CONSTRAINT fixed_assets_tenant_code_key UNIQUE (tenant_id, code); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE goods_receipts ADD CONSTRAINT goods_receipts_number_key UNIQUE (number); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE invoices ADD CONSTRAINT invoices_tenant_number_key UNIQUE (tenant_id, number); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE invoices ADD CONSTRAINT uniq_invoice_number_tenant UNIQUE (tenant_id, number); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE journal_access_rights ADD CONSTRAINT journal_access_rights_tenant_id_user_id_journal_code_key UNIQUE (tenant_id, user_id, journal_code); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE journal_entries ADD CONSTRAINT journal_entries_tenant_number_key UNIQUE (tenant_id, number); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE journal_entries ADD CONSTRAINT uniq_journal_entry_number_tenant UNIQUE (tenant_id, journal_code, number); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE journals ADD CONSTRAINT journals_tenant_code_key UNIQUE (tenant_id, code); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE leave_balances ADD CONSTRAINT leave_balances_employee_id_leave_type_year_key UNIQUE (employee_id, leave_type, year); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE legal_declarations ADD CONSTRAINT legal_declarations_number_key UNIQUE (number); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE manufacturing_orders ADD CONSTRAINT manufacturing_orders_number_key UNIQUE (number); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE marking_types ADD CONSTRAINT marking_types_tenant_id_code_key UNIQUE (tenant_id, code); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE module_document_shares ADD CONSTRAINT module_document_shares_share_token_key UNIQUE (share_token); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE mrp_runs ADD CONSTRAINT mrp_runs_run_number_key UNIQUE (run_number); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE notification_preferences ADD CONSTRAINT notification_preferences_tenant_id_employee_id_key UNIQUE (tenant_id, employee_id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE of_labels ADD CONSTRAINT of_labels_label_number_key UNIQUE (label_number); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE pay_runs ADD CONSTRAINT pay_runs_tenant_number_key UNIQUE (tenant_id, number); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE pay_slips ADD CONSTRAINT pay_slips_number_key UNIQUE (number); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE pay_slips ADD CONSTRAINT uniq_pay_slip_number_tenant UNIQUE (tenant_id, number); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE payment_orders ADD CONSTRAINT payment_orders_number_key UNIQUE (number); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE payment_terms ADD CONSTRAINT payment_terms_tenant_id_code_key UNIQUE (tenant_id, code); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE payroll_accounting_entries ADD CONSTRAINT payroll_accounting_entries_number_key UNIQUE (number); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE price_lists ADD CONSTRAINT price_lists_code_key UNIQUE (code); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE production_forecasts ADD CONSTRAINT production_forecasts_forecast_number_key UNIQUE (forecast_number); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE products ADD CONSTRAINT products_tenant_sku_key UNIQUE (tenant_id, sku); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE project_members ADD CONSTRAINT project_members_tenant_id_project_id_employee_id_key UNIQUE (tenant_id, project_id, employee_id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE project_task_watchers ADD CONSTRAINT project_task_watchers_task_id_employee_id_key UNIQUE (task_id, employee_id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE purchase_credit_notes ADD CONSTRAINT purchase_credit_notes_tenant_number_key UNIQUE (tenant_id, number); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE purchase_invoices ADD CONSTRAINT purchase_invoices_tenant_number_key UNIQUE (tenant_id, number); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE purchase_orders ADD CONSTRAINT purchase_orders_number_key UNIQUE (number); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE quotes ADD CONSTRAINT quotes_tenant_number_key UNIQUE (tenant_id, number); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE reminder_levels ADD CONSTRAINT reminder_levels_tenant_id_level_key UNIQUE (tenant_id, level); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE rh_dashboard_configs ADD CONSTRAINT rh_dashboard_configs_user_email_dashboard_type_key UNIQUE (user_email, dashboard_type); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE sales_orders ADD CONSTRAINT sales_orders_number_key UNIQUE (number); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE sql_migrations_tracker ADD CONSTRAINT sql_migrations_tracker_filename_key UNIQUE (filename); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE st_orders ADD CONSTRAINT st_orders_number_key UNIQUE (number); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE st_receipts ADD CONSTRAINT st_receipts_number_key UNIQUE (number); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE st_shipments ADD CONSTRAINT st_shipments_number_key UNIQUE (number); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE standard_labels ADD CONSTRAINT standard_labels_tenant_label_key UNIQUE (tenant_id, label); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE stat_fields ADD CONSTRAINT stat_fields_tenant_id_entity_type_entity_id_field_name_key UNIQUE (tenant_id, entity_type, entity_id, field_name); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE stock_quantities ADD CONSTRAINT stock_quantities_product_id_warehouse_id_key UNIQUE (product_id, warehouse_id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE supplier_payments ADD CONSTRAINT supplier_payments_number_key UNIQUE (number); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE tenant_users ADD CONSTRAINT tenant_users_tenant_id_email_key UNIQUE (tenant_id, email); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE third_party_accounts ADD CONSTRAINT third_party_accounts_tenant_code_key UNIQUE (tenant_id, code); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE users ADD CONSTRAINT users_email_key UNIQUE (email); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE warehouses ADD CONSTRAINT warehouses_code_key UNIQUE (code); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE account_tag_mappings ADD CONSTRAINT account_tag_mappings_tag_id_fkey FOREIGN KEY (tag_id) REFERENCES account_tags(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE account_tag_mappings ADD CONSTRAINT account_tag_mappings_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE account_tags ADD CONSTRAINT account_tags_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE accounting_control_runs ADD CONSTRAINT accounting_control_runs_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE analytic_distribution_lines ADD CONSTRAINT analytic_distribution_lines_journal_line_id_fkey FOREIGN KEY (journal_line_id) REFERENCES journal_lines(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE analytic_distribution_lines ADD CONSTRAINT analytic_distribution_lines_plan_id_fkey FOREIGN KEY (plan_id) REFERENCES analytic_plans(id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE analytic_distribution_lines ADD CONSTRAINT analytic_distribution_lines_section_id_fkey FOREIGN KEY (section_id) REFERENCES analytic_sections(id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE analytic_distribution_lines ADD CONSTRAINT analytic_distribution_lines_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE analytic_journal_codes ADD CONSTRAINT analytic_journal_codes_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE analytic_plans ADD CONSTRAINT analytic_plans_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE analytic_sections ADD CONSTRAINT analytic_sections_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES analytic_sections(id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE analytic_sections ADD CONSTRAINT analytic_sections_plan_id_fkey FOREIGN KEY (plan_id) REFERENCES analytic_plans(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE analytic_sections ADD CONSTRAINT analytic_sections_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE approval_workflows ADD CONSTRAINT approval_workflows_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE asset_batch_disposal_lines ADD CONSTRAINT asset_batch_disposal_lines_asset_id_fkey FOREIGN KEY (asset_id) REFERENCES fixed_assets(id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE asset_batch_disposal_lines ADD CONSTRAINT asset_batch_disposal_lines_batch_id_fkey FOREIGN KEY (batch_id) REFERENCES asset_batch_disposals(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE asset_depreciation_plans ADD CONSTRAINT asset_depreciation_plans_asset_id_fkey FOREIGN KEY (asset_id) REFERENCES fixed_assets(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE asset_depreciations ADD CONSTRAINT asset_depreciations_asset_id_fkey FOREIGN KEY (asset_id) REFERENCES fixed_assets(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE asset_depreciations ADD CONSTRAINT asset_depreciations_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE asset_documents ADD CONSTRAINT asset_documents_asset_id_fkey FOREIGN KEY (asset_id) REFERENCES fixed_assets(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE asset_families ADD CONSTRAINT asset_families_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES asset_families(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE asset_free_fields ADD CONSTRAINT asset_free_fields_asset_id_fkey FOREIGN KEY (asset_id) REFERENCES fixed_assets(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE asset_revaluations ADD CONSTRAINT asset_revaluations_asset_id_fkey FOREIGN KEY (asset_id) REFERENCES fixed_assets(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE asset_split_components ADD CONSTRAINT asset_split_components_new_asset_id_fkey FOREIGN KEY (new_asset_id) REFERENCES fixed_assets(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE asset_split_components ADD CONSTRAINT asset_split_components_split_id_fkey FOREIGN KEY (split_id) REFERENCES asset_splits(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE asset_splits ADD CONSTRAINT asset_splits_original_asset_id_fkey FOREIGN KEY (original_asset_id) REFERENCES fixed_assets(id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE at_rates ADD CONSTRAINT at_rates_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE at_rates ADD CONSTRAINT at_rates_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE audit_log ADD CONSTRAINT audit_log_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE audit_log ADD CONSTRAINT audit_log_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE auto_label_rules ADD CONSTRAINT auto_label_rules_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bank_accounts ADD CONSTRAINT bank_accounts_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bank_connections ADD CONSTRAINT bank_connections_bank_account_id_fkey FOREIGN KEY (bank_account_id) REFERENCES bank_accounts(id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bank_connections ADD CONSTRAINT bank_connections_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bank_reconciliation_rules ADD CONSTRAINT bank_reconciliation_rules_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bank_rules ADD CONSTRAINT bank_rules_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bank_statement_imports ADD CONSTRAINT bank_statement_imports_bank_account_id_fkey FOREIGN KEY (bank_account_id) REFERENCES bank_accounts(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bank_statement_imports ADD CONSTRAINT bank_statement_imports_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bank_statement_templates ADD CONSTRAINT bank_statement_templates_bank_id_fkey FOREIGN KEY (bank_id) REFERENCES banks(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bank_statement_templates ADD CONSTRAINT bank_statement_templates_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bank_transactions ADD CONSTRAINT bank_transactions_account_id_fkey FOREIGN KEY (account_id) REFERENCES bank_accounts(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bank_transactions ADD CONSTRAINT bank_transactions_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES invoices(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bank_transactions ADD CONSTRAINT bank_transactions_purchase_invoice_id_fkey FOREIGN KEY (purchase_invoice_id) REFERENCES purchase_invoices(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bank_transactions ADD CONSTRAINT bank_transactions_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE batch_entry_sessions ADD CONSTRAINT batch_entry_sessions_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bdes_indicators ADD CONSTRAINT bdes_indicators_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bom_lines ADD CONSTRAINT bom_lines_bom_id_fkey FOREIGN KEY (bom_id) REFERENCES boms(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bom_lines ADD CONSTRAINT bom_lines_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bom_lines ADD CONSTRAINT bom_lines_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE boms ADD CONSTRAINT boms_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE boms ADD CONSTRAINT boms_routing_id_fkey FOREIGN KEY (routing_id) REFERENCES routings(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE boms ADD CONSTRAINT boms_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE budget_commitments ADD CONSTRAINT budget_commitments_fiscal_year_id_fkey FOREIGN KEY (fiscal_year_id) REFERENCES fiscal_years(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE budget_commitments ADD CONSTRAINT budget_commitments_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE budget_commitments ADD CONSTRAINT budget_commitments_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE budgets ADD CONSTRAINT budgets_analytic_section_id_fkey FOREIGN KEY (analytic_section_id) REFERENCES analytic_sections(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE budgets ADD CONSTRAINT budgets_fiscal_year_id_fkey FOREIGN KEY (fiscal_year_id) REFERENCES fiscal_years(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE budgets ADD CONSTRAINT budgets_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE career_history ADD CONSTRAINT career_history_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE carry_forward_log ADD CONSTRAINT carry_forward_log_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE cash_control_sessions ADD CONSTRAINT cash_control_sessions_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE chart_account_templates ADD CONSTRAINT chart_account_templates_pack_code_fkey FOREIGN KEY (pack_code) REFERENCES legislation_packs(code) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE chart_accounts ADD CONSTRAINT chart_accounts_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES chart_accounts(id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE chart_accounts ADD CONSTRAINT chart_accounts_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE check_books ADD CONSTRAINT check_books_bank_account_id_fkey FOREIGN KEY (bank_account_id) REFERENCES bank_accounts(id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE check_books ADD CONSTRAINT check_books_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE checks ADD CONSTRAINT checks_check_book_id_fkey FOREIGN KEY (check_book_id) REFERENCES check_books(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE checks ADD CONSTRAINT checks_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE cice_config ADD CONSTRAINT cice_config_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE collection_reminders ADD CONSTRAINT collection_reminders_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE collection_reminders ADD CONSTRAINT collection_reminders_dispute_id_fkey FOREIGN KEY (dispute_id) REFERENCES disputes(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE collection_reminders ADD CONSTRAINT collection_reminders_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES invoices(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE collection_reminders ADD CONSTRAINT collection_reminders_promise_id_fkey FOREIGN KEY (promise_id) REFERENCES payment_promises(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE collection_reminders ADD CONSTRAINT collection_reminders_reminder_level_id_fkey FOREIGN KEY (reminder_level_id) REFERENCES reminder_levels(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE collection_reminders ADD CONSTRAINT collection_reminders_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE collection_reminders ADD CONSTRAINT collection_reminders_third_party_id_fkey FOREIGN KEY (third_party_id) REFERENCES third_party_accounts(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE compaction_logs ADD CONSTRAINT compaction_logs_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE company_settings ADD CONSTRAINT company_settings_legislation_pack_code_fkey FOREIGN KEY (legislation_pack_code) REFERENCES legislation_packs(code); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE company_settings ADD CONSTRAINT company_settings_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE contracts ADD CONSTRAINT contracts_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE contracts ADD CONSTRAINT contracts_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE corporate_tax_grid_lines ADD CONSTRAINT corporate_tax_grid_lines_grid_id_fkey FOREIGN KEY (grid_id) REFERENCES corporate_tax_grids(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE corporate_tax_grids ADD CONSTRAINT corporate_tax_grids_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE cpf_accounts ADD CONSTRAINT cpf_accounts_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE cpf_transactions ADD CONSTRAINT cpf_transactions_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE cpf_transactions ADD CONSTRAINT cpf_transactions_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE credit_lines ADD CONSTRAINT credit_lines_bank_account_id_fkey FOREIGN KEY (bank_account_id) REFERENCES bank_accounts(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE credit_note_lines ADD CONSTRAINT credit_note_lines_credit_note_id_fkey FOREIGN KEY (credit_note_id) REFERENCES credit_notes(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE credit_note_lines ADD CONSTRAINT credit_note_lines_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE credit_notes ADD CONSTRAINT credit_notes_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE credit_notes ADD CONSTRAINT credit_notes_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES invoices(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE credit_notes ADD CONSTRAINT credit_notes_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE crm_activities ADD CONSTRAINT crm_activities_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE crm_activities ADD CONSTRAINT crm_activities_opportunity_id_fkey FOREIGN KEY (opportunity_id) REFERENCES crm_opportunities(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE crm_activities ADD CONSTRAINT crm_activities_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE crm_campaign_recipients ADD CONSTRAINT crm_campaign_recipients_campaign_id_fkey FOREIGN KEY (campaign_id) REFERENCES crm_campaigns(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE crm_campaign_recipients ADD CONSTRAINT crm_campaign_recipients_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE crm_campaign_recipients ADD CONSTRAINT crm_campaign_recipients_prospect_id_fkey FOREIGN KEY (prospect_id) REFERENCES prospects(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE crm_campaign_recipients ADD CONSTRAINT crm_campaign_recipients_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE crm_campaigns ADD CONSTRAINT crm_campaigns_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE crm_forecasts ADD CONSTRAINT crm_forecasts_sales_rep_id_fkey FOREIGN KEY (sales_rep_id) REFERENCES sales_representatives(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE crm_forecasts ADD CONSTRAINT crm_forecasts_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE crm_opportunities ADD CONSTRAINT crm_opportunities_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE crm_opportunities ADD CONSTRAINT crm_opportunities_prospect_id_fkey FOREIGN KEY (prospect_id) REFERENCES prospects(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE crm_opportunities ADD CONSTRAINT crm_opportunities_sales_rep_id_fkey FOREIGN KEY (sales_rep_id) REFERENCES sales_representatives(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE crm_opportunities ADD CONSTRAINT crm_opportunities_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE crm_territories ADD CONSTRAINT crm_territories_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES crm_territories(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE crm_territories ADD CONSTRAINT crm_territories_sales_rep_id_fkey FOREIGN KEY (sales_rep_id) REFERENCES sales_representatives(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE crm_territories ADD CONSTRAINT crm_territories_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE currencies ADD CONSTRAINT currencies_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE currency_revaluations ADD CONSTRAINT currency_revaluations_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE custom_report_templates ADD CONSTRAINT custom_report_templates_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE customer_contacts ADD CONSTRAINT customer_contacts_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE customer_contacts ADD CONSTRAINT customer_contacts_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE customer_payments ADD CONSTRAINT customer_payments_bank_account_id_fkey FOREIGN KEY (bank_account_id) REFERENCES bank_accounts(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE customer_payments ADD CONSTRAINT customer_payments_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE customer_payments ADD CONSTRAINT customer_payments_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES invoices(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE customer_payments ADD CONSTRAINT customer_payments_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE customer_payments ADD CONSTRAINT customer_payments_transferred_entry_id_fkey FOREIGN KEY (transferred_entry_id) REFERENCES journal_entries(id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE customers ADD CONSTRAINT customers_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE dashboard_widgets ADD CONSTRAINT dashboard_widgets_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE deferred_printing_jobs ADD CONSTRAINT deferred_printing_jobs_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE delivery_note_lines ADD CONSTRAINT delivery_note_lines_delivery_note_id_fkey FOREIGN KEY (delivery_note_id) REFERENCES delivery_notes(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE delivery_note_lines ADD CONSTRAINT delivery_note_lines_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE delivery_note_lines ADD CONSTRAINT delivery_note_lines_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE delivery_notes ADD CONSTRAINT delivery_notes_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE delivery_notes ADD CONSTRAINT delivery_notes_sales_order_id_fkey FOREIGN KEY (sales_order_id) REFERENCES sales_orders(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE delivery_notes ADD CONSTRAINT delivery_notes_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE delivery_schedules ADD CONSTRAINT delivery_schedules_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE delivery_schedules ADD CONSTRAINT delivery_schedules_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE disputes ADD CONSTRAINT disputes_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE distribution_grill_lines ADD CONSTRAINT distribution_grill_lines_grill_id_fkey FOREIGN KEY (grill_id) REFERENCES distribution_grills(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE distribution_grill_lines ADD CONSTRAINT distribution_grill_lines_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE distribution_grills ADD CONSTRAINT distribution_grills_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE document_charges ADD CONSTRAINT document_charges_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE document_charges ADD CONSTRAINT document_charges_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE document_distribution_logs ADD CONSTRAINT document_distribution_logs_employee_document_id_fkey FOREIGN KEY (employee_document_id) REFERENCES employee_documents(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE document_distribution_logs ADD CONSTRAINT document_distribution_logs_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE document_distribution_logs ADD CONSTRAINT document_distribution_logs_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE document_shares ADD CONSTRAINT document_shares_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE document_transformations ADD CONSTRAINT document_transformations_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE dpae_records ADD CONSTRAINT dpae_records_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE electronic_signatures ADD CONSTRAINT electronic_signatures_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE employee_activity_logs ADD CONSTRAINT employee_activity_logs_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE employee_activity_logs ADD CONSTRAINT employee_activity_logs_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE employee_documents ADD CONSTRAINT employee_documents_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE employee_exit_processes ADD CONSTRAINT employee_exit_processes_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE employee_exit_processes ADD CONSTRAINT employee_exit_processes_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE employee_objectives ADD CONSTRAINT employee_objectives_campaign_id_fkey FOREIGN KEY (campaign_id) REFERENCES interview_campaigns(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE employee_objectives ADD CONSTRAINT employee_objectives_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE employee_objectives ADD CONSTRAINT employee_objectives_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE employees ADD CONSTRAINT employees_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE entry_templates ADD CONSTRAINT entry_templates_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE etat_rapprochement ADD CONSTRAINT etat_rapprochement_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE exchange_gain_loss_entries ADD CONSTRAINT exchange_gain_loss_entries_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE exchange_rates ADD CONSTRAINT exchange_rates_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE expense_categories ADD CONSTRAINT expense_categories_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE expense_report_lines ADD CONSTRAINT expense_report_lines_category_id_fkey FOREIGN KEY (category_id) REFERENCES expense_categories(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE expense_report_lines ADD CONSTRAINT expense_report_lines_expense_report_id_fkey FOREIGN KEY (expense_report_id) REFERENCES expense_reports(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE expense_reports ADD CONSTRAINT expense_reports_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE extourne_log ADD CONSTRAINT extourne_log_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fec_attestations ADD CONSTRAINT fec_attestations_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fiscal_backups ADD CONSTRAINT fiscal_backups_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fiscal_periods ADD CONSTRAINT fiscal_periods_fiscal_year_id_fkey FOREIGN KEY (fiscal_year_id) REFERENCES fiscal_years(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fiscal_periods ADD CONSTRAINT fiscal_periods_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fiscal_position_mappings ADD CONSTRAINT fiscal_position_mappings_fiscal_position_id_fkey FOREIGN KEY (fiscal_position_id) REFERENCES fiscal_positions(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fiscal_position_mappings ADD CONSTRAINT fiscal_position_mappings_source_tax_id_fkey FOREIGN KEY (source_tax_id) REFERENCES tax_rates(id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fiscal_position_mappings ADD CONSTRAINT fiscal_position_mappings_target_tax_id_fkey FOREIGN KEY (target_tax_id) REFERENCES tax_rates(id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fiscal_position_mappings ADD CONSTRAINT fiscal_position_mappings_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fiscal_positions ADD CONSTRAINT fiscal_positions_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fiscal_years ADD CONSTRAINT fiscal_years_closed_by_fkey FOREIGN KEY (closed_by) REFERENCES users(id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fiscal_years ADD CONSTRAINT fiscal_years_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fixed_assets ADD CONSTRAINT fixed_assets_family_id_fkey FOREIGN KEY (family_id) REFERENCES asset_families(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fixed_assets ADD CONSTRAINT fixed_assets_parent_asset_id_fkey FOREIGN KEY (parent_asset_id) REFERENCES fixed_assets(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fixed_assets ADD CONSTRAINT fixed_assets_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fusion_logs ADD CONSTRAINT fusion_logs_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE goods_receipt_lines ADD CONSTRAINT goods_receipt_lines_goods_receipt_id_fkey FOREIGN KEY (goods_receipt_id) REFERENCES goods_receipts(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE goods_receipt_lines ADD CONSTRAINT goods_receipt_lines_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE goods_receipt_lines ADD CONSTRAINT goods_receipt_lines_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE goods_receipts ADD CONSTRAINT goods_receipts_purchase_order_id_fkey FOREIGN KEY (purchase_order_id) REFERENCES purchase_orders(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE goods_receipts ADD CONSTRAINT goods_receipts_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE goods_receipts ADD CONSTRAINT goods_receipts_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE grid_templates ADD CONSTRAINT grid_templates_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE honorarium_records ADD CONSTRAINT honorarium_records_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE honorarium_records ADD CONSTRAINT honorarium_records_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ifrs_adjustments ADD CONSTRAINT ifrs_adjustments_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ijss_history ADD CONSTRAINT ijss_history_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ijss_history ADD CONSTRAINT ijss_history_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ijss_history ADD CONSTRAINT ijss_history_work_stoppage_id_fkey FOREIGN KEY (work_stoppage_id) REFERENCES work_stoppages(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE interview_campaigns ADD CONSTRAINT interview_campaigns_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE interviews ADD CONSTRAINT interviews_campaign_id_fkey FOREIGN KEY (campaign_id) REFERENCES interview_campaigns(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE interviews ADD CONSTRAINT interviews_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE invoice_lines ADD CONSTRAINT invoice_lines_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES invoices(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE invoice_lines ADD CONSTRAINT invoice_lines_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE invoice_lines ADD CONSTRAINT invoice_lines_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE invoices ADD CONSTRAINT invoices_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE invoices ADD CONSTRAINT invoices_fiscal_position_id_fkey FOREIGN KEY (fiscal_position_id) REFERENCES fiscal_positions(id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE invoices ADD CONSTRAINT invoices_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE invoices ADD CONSTRAINT invoices_transferred_entry_id_fkey FOREIGN KEY (transferred_entry_id) REFERENCES journal_entries(id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE journal_access_rights ADD CONSTRAINT journal_access_rights_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE journal_entries ADD CONSTRAINT journal_entries_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE journal_lines ADD CONSTRAINT journal_lines_journal_id_fkey FOREIGN KEY (journal_id) REFERENCES journal_entries(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE journal_lines ADD CONSTRAINT journal_lines_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE journals ADD CONSTRAINT journals_bank_account_id_fkey FOREIGN KEY (bank_account_id) REFERENCES bank_accounts(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE journals ADD CONSTRAINT journals_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE justificatif_solde ADD CONSTRAINT justificatif_solde_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE knowledge_base_articles ADD CONSTRAINT knowledge_base_articles_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE leave_balances ADD CONSTRAINT leave_balances_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE leave_balances ADD CONSTRAINT leave_balances_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE leave_provisions ADD CONSTRAINT leave_provisions_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE leave_provisions ADD CONSTRAINT leave_provisions_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE leave_requests ADD CONSTRAINT leave_requests_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES employees(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE leave_requests ADD CONSTRAINT leave_requests_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE leave_requests ADD CONSTRAINT leave_requests_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE leave_rules ADD CONSTRAINT leave_rules_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE legal_declarations ADD CONSTRAINT legal_declarations_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE legislation_packs ADD CONSTRAINT legislation_packs_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE lettrage_differences ADD CONSTRAINT lettrage_differences_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE machines ADD CONSTRAINT machines_work_center_id_fkey FOREIGN KEY (work_center_id) REFERENCES work_centers(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE manufacturing_orders ADD CONSTRAINT manufacturing_orders_bom_id_fkey FOREIGN KEY (bom_id) REFERENCES boms(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE manufacturing_orders ADD CONSTRAINT manufacturing_orders_parent_mo_id_fkey FOREIGN KEY (parent_mo_id) REFERENCES manufacturing_orders(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE manufacturing_orders ADD CONSTRAINT manufacturing_orders_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE manufacturing_orders ADD CONSTRAINT manufacturing_orders_routing_id_fkey FOREIGN KEY (routing_id) REFERENCES routings(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE manufacturing_orders ADD CONSTRAINT manufacturing_orders_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE manufacturing_orders ADD CONSTRAINT manufacturing_orders_warehouse_id_fkey FOREIGN KEY (warehouse_id) REFERENCES warehouses(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE marking_types ADD CONSTRAINT marking_types_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE meal_voucher_config ADD CONSTRAINT meal_voucher_config_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE medical_exams ADD CONSTRAINT medical_exams_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE medical_exams ADD CONSTRAINT medical_exams_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE mirror_servers ADD CONSTRAINT mirror_servers_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE mirror_verification_details ADD CONSTRAINT mirror_verification_details_mirror_server_id_fkey FOREIGN KEY (mirror_server_id) REFERENCES mirror_servers(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE mirror_verification_details ADD CONSTRAINT mirror_verification_details_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE module_document_access_log ADD CONSTRAINT module_document_access_log_document_id_fkey FOREIGN KEY (document_id) REFERENCES module_documents(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE module_document_access_log ADD CONSTRAINT module_document_access_log_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE module_document_access_log ADD CONSTRAINT module_document_access_log_user_id_fkey FOREIGN KEY (user_id) REFERENCES tenant_users(id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE module_document_shares ADD CONSTRAINT module_document_shares_created_by_fkey FOREIGN KEY (created_by) REFERENCES tenant_users(id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE module_document_shares ADD CONSTRAINT module_document_shares_document_id_fkey FOREIGN KEY (document_id) REFERENCES module_documents(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE module_document_shares ADD CONSTRAINT module_document_shares_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE module_documents ADD CONSTRAINT module_documents_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES tenant_users(id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE module_documents ADD CONSTRAINT module_documents_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE module_documents ADD CONSTRAINT module_documents_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES tenant_users(id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE mrp_pending_docs ADD CONSTRAINT mrp_pending_docs_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE mrp_proposals ADD CONSTRAINT mrp_proposals_bom_id_fkey FOREIGN KEY (bom_id) REFERENCES boms(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE mrp_proposals ADD CONSTRAINT mrp_proposals_mrp_run_id_fkey FOREIGN KEY (mrp_run_id) REFERENCES mrp_runs(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE mrp_proposals ADD CONSTRAINT mrp_proposals_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE mrp_proposals ADD CONSTRAINT mrp_proposals_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE notification_email_queue ADD CONSTRAINT notification_email_queue_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE notification_preferences ADD CONSTRAINT notification_preferences_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE notification_preferences ADD CONSTRAINT notification_preferences_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE of_consumptions ADD CONSTRAINT of_consumptions_manufacturing_order_id_fkey FOREIGN KEY (manufacturing_order_id) REFERENCES manufacturing_orders(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE of_consumptions ADD CONSTRAINT of_consumptions_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE of_document_access ADD CONSTRAINT of_document_access_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE of_labels ADD CONSTRAINT of_labels_manufacturing_order_id_fkey FOREIGN KEY (manufacturing_order_id) REFERENCES manufacturing_orders(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE of_labels ADD CONSTRAINT of_labels_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE of_lots ADD CONSTRAINT of_lots_manufacturing_order_id_fkey FOREIGN KEY (manufacturing_order_id) REFERENCES manufacturing_orders(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE of_lots ADD CONSTRAINT of_lots_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE online_payments ADD CONSTRAINT online_payments_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE online_payments ADD CONSTRAINT online_payments_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES invoices(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE online_payments ADD CONSTRAINT online_payments_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE partner_bank_accounts ADD CONSTRAINT partner_bank_accounts_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE partner_categories ADD CONSTRAINT partner_categories_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE partner_category_mappings ADD CONSTRAINT partner_category_mappings_category_id_fkey FOREIGN KEY (category_id) REFERENCES partner_categories(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE partner_category_mappings ADD CONSTRAINT partner_category_mappings_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE partner_contacts ADD CONSTRAINT partner_contacts_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE pas_rates ADD CONSTRAINT pas_rates_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE pas_rates ADD CONSTRAINT pas_rates_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE pay_recalls ADD CONSTRAINT pay_recalls_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE pay_runs ADD CONSTRAINT pay_runs_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE pay_slip_clarified ADD CONSTRAINT pay_slip_clarified_pay_slip_id_fkey FOREIGN KEY (pay_slip_id) REFERENCES pay_slips(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE pay_slip_clarified ADD CONSTRAINT pay_slip_clarified_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE pay_slips ADD CONSTRAINT pay_slips_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE pay_slips ADD CONSTRAINT pay_slips_pay_run_id_fkey FOREIGN KEY (pay_run_id) REFERENCES pay_runs(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE pay_slips ADD CONSTRAINT pay_slips_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE payment_orders ADD CONSTRAINT payment_orders_bank_account_id_fkey FOREIGN KEY (bank_account_id) REFERENCES bank_accounts(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE payment_orders ADD CONSTRAINT payment_orders_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE payment_orders ADD CONSTRAINT payment_orders_third_party_id_fkey FOREIGN KEY (third_party_id) REFERENCES third_party_accounts(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE payment_promises ADD CONSTRAINT payment_promises_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE payment_templates_compta ADD CONSTRAINT payment_templates_compta_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE payment_terms ADD CONSTRAINT payment_terms_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE payroll_accounting_entries ADD CONSTRAINT payroll_accounting_entries_journal_entry_id_fkey FOREIGN KEY (journal_entry_id) REFERENCES journal_entries(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE payroll_accounting_entries ADD CONSTRAINT payroll_accounting_entries_pay_run_id_fkey FOREIGN KEY (pay_run_id) REFERENCES pay_runs(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE payroll_accounting_entries ADD CONSTRAINT payroll_accounting_entries_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE payroll_archives ADD CONSTRAINT payroll_archives_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE payroll_component_rates ADD CONSTRAINT payroll_component_rates_component_id_fkey FOREIGN KEY (component_id) REFERENCES payroll_components(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE payroll_tax_grid_lines ADD CONSTRAINT payroll_tax_grid_lines_grid_id_fkey FOREIGN KEY (grid_id) REFERENCES payroll_tax_grids(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE payroll_tax_grids ADD CONSTRAINT payroll_tax_grids_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE payroll_variable_elements ADD CONSTRAINT payroll_variable_elements_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE payroll_variable_elements ADD CONSTRAINT payroll_variable_elements_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE pick_list_lines ADD CONSTRAINT pick_list_lines_location_id_fkey FOREIGN KEY (location_id) REFERENCES warehouse_locations(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE pick_list_lines ADD CONSTRAINT pick_list_lines_pick_list_id_fkey FOREIGN KEY (pick_list_id) REFERENCES pick_lists(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE pick_list_lines ADD CONSTRAINT pick_list_lines_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE pick_lists ADD CONSTRAINT pick_lists_warehouse_id_fkey FOREIGN KEY (warehouse_id) REFERENCES warehouses(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE planning_slots ADD CONSTRAINT planning_slots_machine_id_fkey FOREIGN KEY (machine_id) REFERENCES machines(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE planning_slots ADD CONSTRAINT planning_slots_manufacturing_order_id_fkey FOREIGN KEY (manufacturing_order_id) REFERENCES manufacturing_orders(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE planning_slots ADD CONSTRAINT planning_slots_routing_operation_id_fkey FOREIGN KEY (routing_operation_id) REFERENCES routing_operations(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE planning_slots ADD CONSTRAINT planning_slots_work_center_id_fkey FOREIGN KEY (work_center_id) REFERENCES work_centers(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE pos_sessions ADD CONSTRAINT pos_sessions_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE pos_sessions ADD CONSTRAINT pos_sessions_terminal_id_fkey FOREIGN KEY (terminal_id) REFERENCES pos_terminals(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE pos_terminals ADD CONSTRAINT pos_terminals_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE pos_terminals ADD CONSTRAINT pos_terminals_warehouse_id_fkey FOREIGN KEY (warehouse_id) REFERENCES warehouses(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE pos_ticket_lines ADD CONSTRAINT pos_ticket_lines_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE pos_ticket_lines ADD CONSTRAINT pos_ticket_lines_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE pos_ticket_lines ADD CONSTRAINT pos_ticket_lines_ticket_id_fkey FOREIGN KEY (ticket_id) REFERENCES pos_tickets(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE pos_tickets ADD CONSTRAINT pos_tickets_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE pos_tickets ADD CONSTRAINT pos_tickets_session_id_fkey FOREIGN KEY (session_id) REFERENCES pos_sessions(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE pos_tickets ADD CONSTRAINT pos_tickets_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE pos_tickets ADD CONSTRAINT pos_tickets_terminal_id_fkey FOREIGN KEY (terminal_id) REFERENCES pos_terminals(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE price_list_lines ADD CONSTRAINT price_list_lines_price_list_id_fkey FOREIGN KEY (price_list_id) REFERENCES price_lists(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE price_list_lines ADD CONSTRAINT price_list_lines_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE price_list_lines ADD CONSTRAINT price_list_lines_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE price_lists ADD CONSTRAINT price_lists_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE product_batches ADD CONSTRAINT product_batches_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE product_equivalences ADD CONSTRAINT product_equivalences_equivalent_product_id_fkey FOREIGN KEY (equivalent_product_id) REFERENCES products(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE product_equivalences ADD CONSTRAINT product_equivalences_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE product_grid_combinations ADD CONSTRAINT product_grid_combinations_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE product_grid_combinations ADD CONSTRAINT product_grid_combinations_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE product_grids ADD CONSTRAINT product_grids_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE product_grids ADD CONSTRAINT product_grids_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE product_links ADD CONSTRAINT product_links_linked_product_id_fkey FOREIGN KEY (linked_product_id) REFERENCES products(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE product_links ADD CONSTRAINT product_links_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE product_links ADD CONSTRAINT product_links_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE product_packagings ADD CONSTRAINT product_packagings_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE product_packagings ADD CONSTRAINT product_packagings_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE product_serial_numbers ADD CONSTRAINT product_serial_numbers_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE product_substitutes ADD CONSTRAINT product_substitutes_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE product_substitutes ADD CONSTRAINT product_substitutes_substitute_id_fkey FOREIGN KEY (substitute_id) REFERENCES products(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE product_variants ADD CONSTRAINT product_variants_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE production_forecasts ADD CONSTRAINT production_forecasts_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE products ADD CONSTRAINT products_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE project_activity_log ADD CONSTRAINT project_activity_log_project_id_fkey FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE project_activity_log ADD CONSTRAINT project_activity_log_task_id_fkey FOREIGN KEY (task_id) REFERENCES project_tasks(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE project_activity_log ADD CONSTRAINT project_activity_log_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE project_docs ADD CONSTRAINT project_docs_project_id_fkey FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE project_members ADD CONSTRAINT project_members_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE project_members ADD CONSTRAINT project_members_project_id_fkey FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE project_members ADD CONSTRAINT project_members_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE project_milestones ADD CONSTRAINT project_milestones_project_id_fkey FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE project_milestones ADD CONSTRAINT project_milestones_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE project_notifications ADD CONSTRAINT project_notifications_project_id_fkey FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE project_notifications ADD CONSTRAINT project_notifications_recipient_id_fkey FOREIGN KEY (recipient_id) REFERENCES employees(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE project_notifications ADD CONSTRAINT project_notifications_task_id_fkey FOREIGN KEY (task_id) REFERENCES project_tasks(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE project_notifications ADD CONSTRAINT project_notifications_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE project_stages ADD CONSTRAINT project_stages_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE project_tags ADD CONSTRAINT project_tags_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE project_task_assignees ADD CONSTRAINT project_task_assignees_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE project_task_assignees ADD CONSTRAINT project_task_assignees_task_id_fkey FOREIGN KEY (task_id) REFERENCES project_tasks(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE project_task_dependencies ADD CONSTRAINT project_task_dependencies_depends_on_task_id_fkey FOREIGN KEY (depends_on_task_id) REFERENCES project_tasks(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE project_task_dependencies ADD CONSTRAINT project_task_dependencies_task_id_fkey FOREIGN KEY (task_id) REFERENCES project_tasks(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE project_task_dependencies ADD CONSTRAINT project_task_dependencies_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE project_task_tags ADD CONSTRAINT project_task_tags_tag_id_fkey FOREIGN KEY (tag_id) REFERENCES project_tags(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE project_task_tags ADD CONSTRAINT project_task_tags_task_id_fkey FOREIGN KEY (task_id) REFERENCES project_tasks(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE project_task_tags ADD CONSTRAINT project_task_tags_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE project_task_templates ADD CONSTRAINT project_task_templates_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE project_task_watchers ADD CONSTRAINT project_task_watchers_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE project_task_watchers ADD CONSTRAINT project_task_watchers_task_id_fkey FOREIGN KEY (task_id) REFERENCES project_tasks(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE project_task_watchers ADD CONSTRAINT project_task_watchers_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE project_tasks ADD CONSTRAINT project_tasks_assignee_id_fkey FOREIGN KEY (assignee_id) REFERENCES employees(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE project_tasks ADD CONSTRAINT project_tasks_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES project_tasks(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE project_tasks ADD CONSTRAINT project_tasks_project_id_fkey FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE project_tasks ADD CONSTRAINT project_tasks_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE project_time_entries ADD CONSTRAINT project_time_entries_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE project_time_entries ADD CONSTRAINT project_time_entries_project_id_fkey FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE project_time_entries ADD CONSTRAINT project_time_entries_task_id_fkey FOREIGN KEY (task_id) REFERENCES project_tasks(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE project_time_entries ADD CONSTRAINT project_time_entries_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE projects ADD CONSTRAINT projects_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE projects ADD CONSTRAINT projects_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE promotions ADD CONSTRAINT promotions_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE promotions ADD CONSTRAINT promotions_free_product_id_fkey FOREIGN KEY (free_product_id) REFERENCES products(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE promotions ADD CONSTRAINT promotions_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE promotions ADD CONSTRAINT promotions_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE prospects ADD CONSTRAINT prospects_assigned_rep_id_fkey FOREIGN KEY (assigned_rep_id) REFERENCES sales_representatives(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE prospects ADD CONSTRAINT prospects_converted_customer_id_fkey FOREIGN KEY (converted_customer_id) REFERENCES customers(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE public_holidays ADD CONSTRAINT public_holidays_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE purchase_credit_lines ADD CONSTRAINT purchase_credit_lines_purchase_credit_id_fkey FOREIGN KEY (purchase_credit_id) REFERENCES purchase_credit_notes(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE purchase_credit_lines ADD CONSTRAINT purchase_credit_lines_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE purchase_credit_notes ADD CONSTRAINT purchase_credit_notes_purchase_invoice_id_fkey FOREIGN KEY (purchase_invoice_id) REFERENCES purchase_invoices(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE purchase_credit_notes ADD CONSTRAINT purchase_credit_notes_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE purchase_credit_notes ADD CONSTRAINT purchase_credit_notes_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE purchase_invoice_lines ADD CONSTRAINT purchase_invoice_lines_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE purchase_invoice_lines ADD CONSTRAINT purchase_invoice_lines_purchase_invoice_id_fkey FOREIGN KEY (purchase_invoice_id) REFERENCES purchase_invoices(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE purchase_invoice_lines ADD CONSTRAINT purchase_invoice_lines_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE purchase_invoices ADD CONSTRAINT purchase_invoices_fiscal_position_id_fkey FOREIGN KEY (fiscal_position_id) REFERENCES fiscal_positions(id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE purchase_invoices ADD CONSTRAINT purchase_invoices_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE purchase_invoices ADD CONSTRAINT purchase_invoices_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE purchase_invoices ADD CONSTRAINT purchase_invoices_transferred_entry_id_fkey FOREIGN KEY (transferred_entry_id) REFERENCES journal_entries(id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE purchase_order_lines ADD CONSTRAINT purchase_order_lines_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE purchase_order_lines ADD CONSTRAINT purchase_order_lines_purchase_order_id_fkey FOREIGN KEY (purchase_order_id) REFERENCES purchase_orders(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE purchase_order_lines ADD CONSTRAINT purchase_order_lines_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE purchase_orders ADD CONSTRAINT purchase_orders_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE purchase_orders ADD CONSTRAINT purchase_orders_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE purchase_request_lines ADD CONSTRAINT purchase_request_lines_preferred_supplier_id_fkey FOREIGN KEY (preferred_supplier_id) REFERENCES suppliers(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE purchase_request_lines ADD CONSTRAINT purchase_request_lines_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE purchase_request_lines ADD CONSTRAINT purchase_request_lines_purchase_request_id_fkey FOREIGN KEY (purchase_request_id) REFERENCES purchase_requests(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE purchase_request_lines ADD CONSTRAINT purchase_request_lines_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE purchase_requests ADD CONSTRAINT purchase_requests_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE quality_checks ADD CONSTRAINT quality_checks_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE quote_lines ADD CONSTRAINT quote_lines_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE quote_lines ADD CONSTRAINT quote_lines_quote_id_fkey FOREIGN KEY (quote_id) REFERENCES quotes(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE quote_lines ADD CONSTRAINT quote_lines_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE quotes ADD CONSTRAINT quotes_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE quotes ADD CONSTRAINT quotes_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE recurring_entries ADD CONSTRAINT recurring_entries_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE recurring_invoice_templates ADD CONSTRAINT recurring_invoice_templates_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE regularization_entries ADD CONSTRAINT regularization_entries_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE reimputation_logs ADD CONSTRAINT reimputation_logs_original_entry_id_fkey FOREIGN KEY (original_entry_id) REFERENCES journal_entries(id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE reimputation_logs ADD CONSTRAINT reimputation_logs_original_line_id_fkey FOREIGN KEY (original_line_id) REFERENCES journal_lines(id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE reimputation_logs ADD CONSTRAINT reimputation_logs_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE reminder_levels ADD CONSTRAINT reminder_levels_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE reporting_plans ADD CONSTRAINT reporting_plans_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE revision_cycles ADD CONSTRAINT revision_cycles_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE rgpd_requests ADD CONSTRAINT rgpd_requests_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE rh_dashboard_configs ADD CONSTRAINT rh_dashboard_configs_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE rh_knowledge_base ADD CONSTRAINT rh_knowledge_base_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE rh_reports ADD CONSTRAINT rh_reports_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE rh_requests ADD CONSTRAINT rh_requests_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE rh_requests ADD CONSTRAINT rh_requests_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE routing_operations ADD CONSTRAINT routing_operations_machine_id_fkey FOREIGN KEY (machine_id) REFERENCES machines(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE routing_operations ADD CONSTRAINT routing_operations_routing_id_fkey FOREIGN KEY (routing_id) REFERENCES routings(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE routing_operations ADD CONSTRAINT routing_operations_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE routing_operations ADD CONSTRAINT routing_operations_tooling_id_fkey FOREIGN KEY (tooling_id) REFERENCES toolings(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE routing_operations ADD CONSTRAINT routing_operations_work_center_id_fkey FOREIGN KEY (work_center_id) REFERENCES work_centers(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE routings ADD CONSTRAINT routings_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE salary_advances ADD CONSTRAINT salary_advances_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE sales_order_lines ADD CONSTRAINT sales_order_lines_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE sales_order_lines ADD CONSTRAINT sales_order_lines_sales_order_id_fkey FOREIGN KEY (sales_order_id) REFERENCES sales_orders(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE sales_order_lines ADD CONSTRAINT sales_order_lines_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE sales_orders ADD CONSTRAINT sales_orders_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE sales_orders ADD CONSTRAINT sales_orders_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE saved_filters ADD CONSTRAINT saved_filters_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE sepa_payment_orders ADD CONSTRAINT sepa_payment_orders_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE service_contracts ADD CONSTRAINT service_contracts_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE service_contracts ADD CONSTRAINT service_contracts_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE service_ticket_messages ADD CONSTRAINT service_ticket_messages_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE service_ticket_messages ADD CONSTRAINT service_ticket_messages_ticket_id_fkey FOREIGN KEY (ticket_id) REFERENCES service_tickets(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE service_tickets ADD CONSTRAINT service_tickets_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES customer_contacts(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE service_tickets ADD CONSTRAINT service_tickets_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE service_tickets ADD CONSTRAINT service_tickets_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE social_declarations ADD CONSTRAINT social_declarations_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE st_orders ADD CONSTRAINT st_orders_manufacturing_order_id_fkey FOREIGN KEY (manufacturing_order_id) REFERENCES manufacturing_orders(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE st_orders ADD CONSTRAINT st_orders_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE st_orders ADD CONSTRAINT st_orders_routing_operation_id_fkey FOREIGN KEY (routing_operation_id) REFERENCES routing_operations(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE st_orders ADD CONSTRAINT st_orders_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE st_receipt_lines ADD CONSTRAINT st_receipt_lines_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE st_receipt_lines ADD CONSTRAINT st_receipt_lines_st_receipt_id_fkey FOREIGN KEY (st_receipt_id) REFERENCES st_receipts(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE st_receipts ADD CONSTRAINT st_receipts_st_order_id_fkey FOREIGN KEY (st_order_id) REFERENCES st_orders(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE st_receipts ADD CONSTRAINT st_receipts_warehouse_id_fkey FOREIGN KEY (warehouse_id) REFERENCES warehouses(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE st_shipment_lines ADD CONSTRAINT st_shipment_lines_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE st_shipment_lines ADD CONSTRAINT st_shipment_lines_st_shipment_id_fkey FOREIGN KEY (st_shipment_id) REFERENCES st_shipments(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE st_shipments ADD CONSTRAINT st_shipments_st_order_id_fkey FOREIGN KEY (st_order_id) REFERENCES st_orders(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE st_shipments ADD CONSTRAINT st_shipments_warehouse_id_fkey FOREIGN KEY (warehouse_id) REFERENCES warehouses(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE staff_requirements ADD CONSTRAINT staff_requirements_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE standard_labels ADD CONSTRAINT standard_labels_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE stat_fields ADD CONSTRAINT stat_fields_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE stock_alerts ADD CONSTRAINT stock_alerts_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE stock_alerts ADD CONSTRAINT stock_alerts_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE stock_alerts ADD CONSTRAINT stock_alerts_warehouse_id_fkey FOREIGN KEY (warehouse_id) REFERENCES warehouses(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE stock_movements ADD CONSTRAINT stock_movements_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE stock_movements ADD CONSTRAINT stock_movements_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE stock_quantities ADD CONSTRAINT stock_quantities_location_id_fkey FOREIGN KEY (location_id) REFERENCES warehouse_locations(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE stock_quantities ADD CONSTRAINT stock_quantities_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE stock_quantities ADD CONSTRAINT stock_quantities_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE stock_quantities ADD CONSTRAINT stock_quantities_warehouse_id_fkey FOREIGN KEY (warehouse_id) REFERENCES warehouses(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE supplier_contacts ADD CONSTRAINT supplier_contacts_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE supplier_contacts ADD CONSTRAINT supplier_contacts_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE supplier_delivery_schedules ADD CONSTRAINT supplier_delivery_schedules_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE supplier_delivery_schedules ADD CONSTRAINT supplier_delivery_schedules_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE supplier_delivery_schedules ADD CONSTRAINT supplier_delivery_schedules_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE supplier_delivery_schedules ADD CONSTRAINT supplier_delivery_schedules_warehouse_id_fkey FOREIGN KEY (warehouse_id) REFERENCES warehouses(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE supplier_payments ADD CONSTRAINT supplier_payments_bank_account_id_fkey FOREIGN KEY (bank_account_id) REFERENCES bank_accounts(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE supplier_payments ADD CONSTRAINT supplier_payments_purchase_invoice_id_fkey FOREIGN KEY (purchase_invoice_id) REFERENCES purchase_invoices(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE supplier_payments ADD CONSTRAINT supplier_payments_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE supplier_payments ADD CONSTRAINT supplier_payments_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE supplier_payments ADD CONSTRAINT supplier_payments_transferred_entry_id_fkey FOREIGN KEY (transferred_entry_id) REFERENCES journal_entries(id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE supplier_price_list_lines ADD CONSTRAINT supplier_price_list_lines_price_list_id_fkey FOREIGN KEY (price_list_id) REFERENCES supplier_price_lists(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE supplier_price_list_lines ADD CONSTRAINT supplier_price_list_lines_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE supplier_price_list_lines ADD CONSTRAINT supplier_price_list_lines_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE supplier_price_lists ADD CONSTRAINT supplier_price_lists_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE supplier_price_lists ADD CONSTRAINT supplier_price_lists_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE suppliers ADD CONSTRAINT suppliers_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE task_action_attachments ADD CONSTRAINT task_action_attachments_task_action_id_fkey FOREIGN KEY (task_action_id) REFERENCES task_actions(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE task_action_attachments ADD CONSTRAINT task_action_attachments_task_id_fkey FOREIGN KEY (task_id) REFERENCES project_tasks(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE task_action_attachments ADD CONSTRAINT task_action_attachments_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE task_actions ADD CONSTRAINT task_actions_task_id_fkey FOREIGN KEY (task_id) REFERENCES project_tasks(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE task_actions ADD CONSTRAINT task_actions_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE task_comments ADD CONSTRAINT task_comments_task_id_fkey FOREIGN KEY (task_id) REFERENCES project_tasks(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE task_comments ADD CONSTRAINT task_comments_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE task_documents ADD CONSTRAINT task_documents_project_id_fkey FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE task_documents ADD CONSTRAINT task_documents_task_id_fkey FOREIGN KEY (task_id) REFERENCES project_tasks(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE task_documents ADD CONSTRAINT task_documents_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE tax_cash_basis_entries ADD CONSTRAINT tax_cash_basis_entries_tax_id_fkey FOREIGN KEY (tax_id) REFERENCES tax_rates(id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE tax_cash_basis_entries ADD CONSTRAINT tax_cash_basis_entries_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE tax_groups ADD CONSTRAINT tax_groups_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE tax_payments ADD CONSTRAINT tax_payments_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE tax_rates ADD CONSTRAINT tax_rates_pack_code_fkey FOREIGN KEY (pack_code) REFERENCES legislation_packs(code) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE tax_rates ADD CONSTRAINT tax_rates_parent_tax_id_fkey FOREIGN KEY (parent_tax_id) REFERENCES tax_rates(id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE tax_rates ADD CONSTRAINT tax_rates_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE tax_repartition_lines ADD CONSTRAINT tax_repartition_lines_tax_id_fkey FOREIGN KEY (tax_id) REFERENCES tax_rates(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE tax_repartition_lines ADD CONSTRAINT tax_repartition_lines_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE tenant_users ADD CONSTRAINT tenant_users_auth_id_fkey FOREIGN KEY (auth_id) REFERENCES auth.users(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE tenant_users ADD CONSTRAINT tenant_users_invited_by_fkey FOREIGN KEY (invited_by) REFERENCES tenant_users(id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE tenant_users ADD CONSTRAINT tenant_users_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE tenants ADD CONSTRAINT tenants_legislation_pack_code_fkey FOREIGN KEY (legislation_pack_code) REFERENCES legislation_packs(code); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE third_party_accounts ADD CONSTRAINT fk_tpa_payment_term FOREIGN KEY (payment_term_id) REFERENCES payment_terms(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE third_party_accounts ADD CONSTRAINT third_party_accounts_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE third_party_accounts ADD CONSTRAINT third_party_accounts_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES users(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE third_party_accounts ADD CONSTRAINT third_party_accounts_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE third_party_accounts ADD CONSTRAINT third_party_accounts_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE tier_ribs ADD CONSTRAINT tier_ribs_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE timesheets ADD CONSTRAINT timesheets_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE timesheets ADD CONSTRAINT timesheets_project_id_fkey FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE timesheets ADD CONSTRAINT timesheets_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE toolings ADD CONSTRAINT toolings_machine_id_fkey FOREIGN KEY (machine_id) REFERENCES machines(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE treasury_recurring ADD CONSTRAINT treasury_recurring_bank_account_id_fkey FOREIGN KEY (bank_account_id) REFERENCES bank_accounts(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE treasury_transfers ADD CONSTRAINT treasury_transfers_from_account_id_fkey FOREIGN KEY (from_account_id) REFERENCES bank_accounts(id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE treasury_transfers ADD CONSTRAINT treasury_transfers_to_account_id_fkey FOREIGN KEY (to_account_id) REFERENCES bank_accounts(id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE tvs_declarations ADD CONSTRAINT tvs_declarations_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE users ADD CONSTRAINT users_auth_id_fkey FOREIGN KEY (auth_id) REFERENCES auth.users(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE users ADD CONSTRAINT users_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE value_date_tracking ADD CONSTRAINT value_date_tracking_bank_account_id_fkey FOREIGN KEY (bank_account_id) REFERENCES bank_accounts(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE vat_on_collections ADD CONSTRAINT vat_on_collections_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE vat_returns ADD CONSTRAINT vat_returns_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE warehouse_locations ADD CONSTRAINT warehouse_locations_warehouse_id_fkey FOREIGN KEY (warehouse_id) REFERENCES warehouses(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE warehouse_users ADD CONSTRAINT warehouse_users_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE warehouse_users ADD CONSTRAINT warehouse_users_warehouse_id_fkey FOREIGN KEY (warehouse_id) REFERENCES warehouses(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE warehouses ADD CONSTRAINT warehouses_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE work_hardship ADD CONSTRAINT work_hardship_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE work_hardship_records ADD CONSTRAINT work_hardship_records_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE work_hardship_records ADD CONSTRAINT work_hardship_records_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE work_stoppages ADD CONSTRAINT work_stoppages_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE work_stoppages ADD CONSTRAINT work_stoppages_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE asset_batch_disposal_lines ADD CONSTRAINT asset_batch_disposal_lines_disposal_type_check CHECK ((disposal_type = ANY (ARRAY['sale'::text, 'scrapping'::text, 'donation'::text, 'transfer'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE asset_batch_disposals ADD CONSTRAINT asset_batch_disposals_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'processed'::text, 'cancelled'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE asset_depreciation_plans ADD CONSTRAINT asset_depreciation_plans_depreciation_method_check CHECK ((depreciation_method = ANY (ARRAY['linear'::text, 'degressive'::text, 'variable'::text, 'manual'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE asset_depreciation_plans ADD CONSTRAINT asset_depreciation_plans_plan_type_check CHECK ((plan_type = ANY (ARRAY['economic'::text, 'fiscal'::text, 'derogatory'::text, 'exceptional'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE asset_depreciations ADD CONSTRAINT asset_depreciations_depreciation_type_check CHECK ((depreciation_type = ANY (ARRAY['depreciation'::text, 'disposal'::text, 'dotation'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE asset_depreciations ADD CONSTRAINT asset_depreciations_period_check CHECK (((period >= 1) AND (period <= 12))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE asset_documents ADD CONSTRAINT asset_documents_document_type_check CHECK ((document_type = ANY (ARRAY['invoice'::text, 'contract'::text, 'photo'::text, 'other'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE asset_families ADD CONSTRAINT asset_families_default_method_check CHECK ((default_method = ANY (ARRAY['linear'::text, 'degressive'::text, 'variable'::text, 'manual'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE asset_free_fields ADD CONSTRAINT asset_free_fields_field_category_check CHECK ((field_category = ANY (ARRAY['free'::text, 'statistical'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE asset_free_fields ADD CONSTRAINT asset_free_fields_field_type_check CHECK ((field_type = ANY (ARRAY['text'::text, 'number'::text, 'date'::text, 'boolean'::text, 'select'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE audit_log ADD CONSTRAINT audit_log_action_check CHECK ((action = ANY (ARRAY['create'::text, 'update'::text, 'delete'::text, 'login'::text, 'logout'::text, 'transfer'::text, 'validate'::text, 'close'::text, 'export'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bank_accounts ADD CONSTRAINT bank_accounts_type_check CHECK ((type = ANY (ARRAY['chequing'::text, 'savings'::text, 'credit_card'::text, 'cash'::text, 'loan'::text, 'other'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bank_statement_templates ADD CONSTRAINT bank_statement_templates_validation_status_check CHECK ((validation_status = ANY (ARRAY['pending'::text, 'validated'::text, 'rejected'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE bank_transactions ADD CONSTRAINT bank_transactions_type_check CHECK ((type = ANY (ARRAY['debit'::text, 'credit'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE boms ADD CONSTRAINT boms_bom_type_check CHECK ((bom_type = ANY (ARRAY['standard'::text, 'amalgam'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE budget_commitments ADD CONSTRAINT budget_commitments_source_type_check CHECK ((source_type = ANY (ARRAY['manual'::text, 'purchase_order'::text, 'purchase_invoice'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE budget_commitments ADD CONSTRAINT budget_commitments_status_check CHECK ((status = ANY (ARRAY['active'::text, 'consumed'::text, 'cancelled'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE career_history ADD CONSTRAINT career_history_change_type_check CHECK ((change_type = ANY (ARRAY['hire'::text, 'promotion'::text, 'transfer'::text, 'salary_change'::text, 'departure'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE chart_account_templates ADD CONSTRAINT chart_account_templates_type_check CHECK ((type = ANY (ARRAY['asset'::text, 'liability'::text, 'equity'::text, 'income'::text, 'expense'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE chart_accounts ADD CONSTRAINT chart_accounts_type_check CHECK ((type = ANY (ARRAY['asset'::text, 'liability'::text, 'equity'::text, 'income'::text, 'expense'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE collection_reminders ADD CONSTRAINT collection_reminders_payment_status_check CHECK ((payment_status = ANY (ARRAY['unpaid'::text, 'pending'::text, 'paid'::text, 'expired'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE collection_reminders ADD CONSTRAINT collection_reminders_reminder_level_check CHECK ((reminder_level = ANY (ARRAY[1, 2, 3]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE collection_reminders ADD CONSTRAINT collection_reminders_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'sent'::text, 'paid'::text, 'cancelled'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE compaction_logs ADD CONSTRAINT compaction_logs_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'in_progress'::text, 'completed'::text, 'failed'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE company_settings ADD CONSTRAINT company_settings_accounting_standard_check CHECK ((accounting_standard = ANY (ARRAY['french_pcga'::text, 'ias_ifrs'::text, 'french_pcg'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE company_settings ADD CONSTRAINT company_settings_vat_method_check CHECK ((vat_method = ANY (ARRAY['debit'::text, 'encaissement'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE contracts ADD CONSTRAINT contracts_contract_type_check CHECK ((contract_type = ANY (ARRAY['cdi'::text, 'cdd'::text, 'apprentissage'::text, 'stage'::text, 'interim'::text, 'freelance'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE contracts ADD CONSTRAINT contracts_status_check CHECK ((status = ANY (ARRAY['active'::text, 'ended'::text, 'suspended'::text, 'terminated'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE corporate_tax_grid_lines ADD CONSTRAINT corporate_tax_grid_lines_base_type_check CHECK ((base_type = ANY (ARRAY['profit'::text, 'turnover'::text, 'property_value'::text, 'custom'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE corporate_tax_grid_lines ADD CONSTRAINT corporate_tax_grid_lines_line_type_check CHECK ((line_type = ANY (ARRAY['bracket'::text, 'flat'::text, 'percentage'::text, 'fixed_amount'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE corporate_tax_grids ADD CONSTRAINT corporate_tax_grids_source_check CHECK ((source = ANY (ARRAY['platform'::text, 'imported'::text, 'manual'::text, 'api'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE corporate_tax_grids ADD CONSTRAINT corporate_tax_grids_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'active'::text, 'archived'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE corporate_tax_grids ADD CONSTRAINT corporate_tax_grids_tax_type_check CHECK ((tax_type = ANY (ARRAY['corporate_income_tax'::text, 'minimum_tax'::text, 'turnover_tax'::text, 'withholding_tax'::text, 'property_tax'::text, 'other_corporate_tax'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE credit_lines ADD CONSTRAINT credit_lines_status_check CHECK ((status = ANY (ARRAY['active'::text, 'closed'::text, 'suspended'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE credit_lines ADD CONSTRAINT credit_lines_type_check CHECK ((type = ANY (ARRAY['credit_line'::text, 'loan'::text, 'overdraft'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE credit_notes ADD CONSTRAINT credit_notes_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'applied'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE customer_payments ADD CONSTRAINT customer_payments_method_check CHECK ((method = ANY (ARRAY['cash'::text, 'check'::text, 'transfer'::text, 'card'::text, 'direct_debit'::text, 'other'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE customer_payments ADD CONSTRAINT customer_payments_status_check CHECK ((status = ANY (ARRAY['recorded'::text, 'reconciled'::text, 'cancelled'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE dashboard_widgets ADD CONSTRAINT dashboard_widgets_size_check CHECK ((size = ANY (ARRAY['small'::text, 'medium'::text, 'large'::text, 'full'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE dashboard_widgets ADD CONSTRAINT dashboard_widgets_widget_type_check CHECK ((widget_type = ANY (ARRAY['chart'::text, 'table'::text, 'kpi'::text, 'alert'::text, 'custom'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE delivery_notes ADD CONSTRAINT delivery_notes_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'delivered'::text, 'returned'::text, 'cancelled'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE delivery_notes ADD CONSTRAINT delivery_notes_validation_status_check CHECK ((validation_status = ANY (ARRAY['draft'::text, 'validated'::text, 'transformed'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE delivery_schedules ADD CONSTRAINT delivery_schedules_frequency_check CHECK ((frequency = ANY (ARRAY['daily'::text, 'weekly'::text, 'monthly'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE disputes ADD CONSTRAINT disputes_status_check CHECK ((status = ANY (ARRAY['open'::text, 'under_review'::text, 'resolved'::text, 'rejected'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE document_distribution_logs ADD CONSTRAINT document_distribution_logs_status_check CHECK ((status = ANY (ARRAY['distributed'::text, 'acknowledged'::text, 'bounced'::text, 'failed'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE document_templates ADD CONSTRAINT document_templates_document_type_check CHECK ((document_type = ANY (ARRAY['invoice'::text, 'quote'::text, 'delivery_note'::text, 'credit_note'::text, 'purchase_order'::text, 'statement'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE dpae_records ADD CONSTRAINT dpae_records_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'transmitted'::text, 'accepted'::text, 'rejected'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE dsn_declarations ADD CONSTRAINT dsn_declarations_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'generated'::text, 'transmitted'::text, 'accepted'::text, 'rejected'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE dsn_declarations ADD CONSTRAINT dsn_declarations_type_check CHECK ((type = ANY (ARRAY['mensuelle'::text, 'arret'::text, 'reprise'::text, 'fin_contrat'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE employee_documents ADD CONSTRAINT employee_documents_document_type_check CHECK ((document_type = ANY (ARRAY['payslip'::text, 'contract'::text, 'dpae'::text, 'dsn'::text, 'certificate'::text, 'other'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE employee_exit_processes ADD CONSTRAINT employee_exit_processes_status_check CHECK ((status = ANY (ARRAY['in_progress'::text, 'completed'::text, 'cancelled'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE employee_objectives ADD CONSTRAINT employee_objectives_status_check CHECK ((status = ANY (ARRAY['active'::text, 'achieved'::text, 'missed'::text, 'cancelled'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE employees ADD CONSTRAINT employees_status_check CHECK ((status = ANY (ARRAY['active'::text, 'inactive'::text, 'on_leave'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE expense_reports ADD CONSTRAINT expense_reports_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'submitted'::text, 'approved'::text, 'rejected'::text, 'reimbursed'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fiscal_periods ADD CONSTRAINT fiscal_periods_status_check CHECK ((status = ANY (ARRAY['open'::text, 'closed'::text, 'locked'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fiscal_years ADD CONSTRAINT fiscal_years_status_check CHECK ((status = ANY (ARRAY['open'::text, 'closed'::text, 'locked'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fixed_assets ADD CONSTRAINT fixed_assets_asset_type_check CHECK ((asset_type = ANY (ARRAY['owned'::text, 'leased'::text, 'leasing'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE fixed_assets ADD CONSTRAINT fixed_assets_status_check CHECK ((status = ANY (ARRAY['active'::text, 'disposed'::text, 'fully_depreciated'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE future_accounting_movements ADD CONSTRAINT future_accounting_movements_movement_type_check CHECK ((movement_type = ANY (ARRAY['debit'::text, 'credit'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE future_accounting_movements ADD CONSTRAINT future_accounting_movements_source_type_check CHECK ((source_type = ANY (ARRAY['invoice'::text, 'purchase_invoice'::text, 'payroll'::text, 'loan'::text, 'manual'::text, 'recurring'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE goods_receipts ADD CONSTRAINT goods_receipts_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'received'::text, 'partial'::text, 'cancelled'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE honorarium_records ADD CONSTRAINT honorarium_records_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'paid'::text, 'accounted'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE interview_campaigns ADD CONSTRAINT interview_campaigns_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'active'::text, 'closed'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE interviews ADD CONSTRAINT interviews_rating_check CHECK (((rating >= 1) AND (rating <= 5))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE interviews ADD CONSTRAINT interviews_status_check CHECK ((status = ANY (ARRAY['scheduled'::text, 'conducted'::text, 'cancelled'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE interviews ADD CONSTRAINT interviews_type_check CHECK ((type = ANY (ARRAY['annual'::text, 'mid_year'::text, 'professional'::text, 'exit'::text, 'other'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE investments ADD CONSTRAINT investments_status_check CHECK ((status = ANY (ARRAY['active'::text, 'matured'::text, 'sold'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE investments ADD CONSTRAINT investments_type_check CHECK ((type = ANY (ARRAY['opcv'::text, 'bond'::text, 'stock'::text, 'term_deposit'::text, 'other'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE invoices ADD CONSTRAINT invoices_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'sent'::text, 'viewed'::text, 'paid'::text, 'overdue'::text, 'cancelled'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE invoices ADD CONSTRAINT invoices_validation_status_check CHECK ((validation_status = ANY (ARRAY['draft'::text, 'validated'::text, 'transformed'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE journal_entries ADD CONSTRAINT journal_entries_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'posted'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE journals ADD CONSTRAINT journals_access_level_check CHECK ((access_level = ANY (ARRAY['all'::text, 'restricted'::text, 'admin_only'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE journals ADD CONSTRAINT journals_status_check CHECK ((status = ANY (ARRAY['active'::text, 'inactive'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE journals ADD CONSTRAINT journals_type_check CHECK ((type = ANY (ARRAY['purchase'::text, 'sale'::text, 'bank'::text, 'cash'::text, 'general'::text, 'analytic'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE leave_provisions ADD CONSTRAINT leave_provisions_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'calculated'::text, 'posted'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE leave_requests ADD CONSTRAINT leave_requests_leave_type_check CHECK ((leave_type = ANY (ARRAY['annual'::text, 'sick'::text, 'maternity'::text, 'paternity'::text, 'unpaid'::text, 'other'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE leave_requests ADD CONSTRAINT leave_requests_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'cancelled'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE legal_declarations ADD CONSTRAINT legal_declarations_declaration_type_check CHECK ((declaration_type = ANY (ARRAY['dsn'::text, 'urssaf'::text, 'dgt'::text, 'ifrs'::text, 'other'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE legal_declarations ADD CONSTRAINT legal_declarations_period_month_check CHECK (((period_month >= 1) AND (period_month <= 12))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE legal_declarations ADD CONSTRAINT legal_declarations_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'submitted'::text, 'late'::text, 'cancelled'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE legal_watch ADD CONSTRAINT legal_watch_relevance_check CHECK ((relevance = ANY (ARRAY['info'::text, 'important'::text, 'critical'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE machines ADD CONSTRAINT machines_status_check CHECK ((status = ANY (ARRAY['active'::text, 'maintenance'::text, 'inactive'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE manufacturing_orders ADD CONSTRAINT manufacturing_orders_expiry_type_check CHECK ((expiry_type = ANY (ARRAY['DLUO'::text, 'DDM'::text, 'DLC'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE manufacturing_orders ADD CONSTRAINT manufacturing_orders_origin_check CHECK ((origin = ANY (ARRAY['manual'::text, 'mrp'::text, 'sub_level'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE manufacturing_orders ADD CONSTRAINT manufacturing_orders_status_check CHECK ((status = ANY (ARRAY['planned'::text, 'in_progress'::text, 'completed'::text, 'cancelled'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE mirror_servers ADD CONSTRAINT mirror_servers_install_platform_check CHECK ((install_platform = ANY (ARRAY['mac'::text, 'windows'::text, 'linux'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE mirror_servers ADD CONSTRAINT mirror_servers_install_status_check CHECK ((install_status = ANY (ARRAY['pending'::text, 'installed'::text, 'verified'::text, 'failed'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE mirror_servers ADD CONSTRAINT mirror_servers_status_check CHECK ((status = ANY (ARRAY['active'::text, 'inactive'::text, 'revoked'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE mrp_pending_docs ADD CONSTRAINT mrp_pending_docs_doc_type_check CHECK ((doc_type = ANY (ARRAY['purchase_order'::text, 'manufacturing_order'::text, 'subcontract_order'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE mrp_pending_docs ADD CONSTRAINT mrp_pending_docs_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'processed'::text, 'cancelled'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE mrp_proposals ADD CONSTRAINT mrp_proposals_proposal_type_check CHECK ((proposal_type = ANY (ARRAY['purchase'::text, 'manufacture'::text, 'subcontract'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE mrp_proposals ADD CONSTRAINT mrp_proposals_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'converted'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE mrp_runs ADD CONSTRAINT mrp_runs_status_check CHECK ((status = ANY (ARRAY['running'::text, 'completed'::text, 'cancelled'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE notification_email_queue ADD CONSTRAINT notification_email_queue_status_check CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'sent'::character varying, 'failed'::character varying, 'bounced'::character varying])::text[]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE notification_preferences ADD CONSTRAINT notification_preferences_digest_mode_check CHECK (((digest_mode)::text = ANY ((ARRAY['instant'::character varying, 'daily'::character varying, 'disabled'::character varying])::text[]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE of_lots ADD CONSTRAINT of_lots_expiry_type_check CHECK ((expiry_type = ANY (ARRAY['DLUO'::text, 'DDM'::text, 'DLC'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE pay_recalls ADD CONSTRAINT pay_recalls_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'processed'::text, 'cancelled'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE pay_runs ADD CONSTRAINT pay_runs_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'approved'::text, 'paid'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE pay_slips ADD CONSTRAINT pay_slips_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'approved'::text, 'paid'::text, 'cancelled'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE payment_orders ADD CONSTRAINT payment_orders_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'approved'::text, 'executed'::text, 'cancelled'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE payment_orders ADD CONSTRAINT payment_orders_type_check CHECK ((type = ANY (ARRAY['sepa_transfer'::text, 'check'::text, 'cash'::text, 'card'::text, 'other'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE payment_promises ADD CONSTRAINT payment_promises_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'kept'::text, 'broken'::text, 'cancelled'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE payment_terms ADD CONSTRAINT payment_terms_type_check CHECK ((type = ANY (ARRAY['fixed'::text, 'end_of_month'::text, 'split'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE payroll_accounting_entries ADD CONSTRAINT payroll_accounting_entries_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'transferred'::text, 'cancelled'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE payroll_archives ADD CONSTRAINT payroll_archives_archive_type_check CHECK ((archive_type = ANY (ARRAY['payslip'::text, 'dsn'::text, 'dpae'::text, 'contract'::text, 'other'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE payroll_components ADD CONSTRAINT payroll_components_calculation_type_check CHECK ((calculation_type = ANY (ARRAY['fixed'::text, 'percentage'::text, 'formula'::text, 'bracket'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE payroll_components ADD CONSTRAINT payroll_components_type_check CHECK ((type = ANY (ARRAY['gross'::text, 'deduction'::text, 'contribution'::text, 'tax'::text, 'net'::text, 'benefit'::text, 'information'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE payroll_tax_grid_lines ADD CONSTRAINT payroll_tax_grid_lines_base_type_check CHECK ((base_type = ANY (ARRAY['gross'::text, 'taxable_gross'::text, 'net'::text, 'total_gross'::text, 'custom'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE payroll_tax_grid_lines ADD CONSTRAINT payroll_tax_grid_lines_category_check CHECK ((category = ANY (ARRAY['social_security'::text, 'health'::text, 'retirement'::text, 'unemployment'::text, 'csg_crds'::text, 'its'::text, 'income_tax'::text, 'other_deduction'::text, 'other_income'::text, 'other_tax'::text, 'employer_charge'::text, 'employee_charge'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE payroll_tax_grid_lines ADD CONSTRAINT payroll_tax_grid_lines_line_type_check CHECK ((line_type = ANY (ARRAY['bracket'::text, 'flat'::text, 'percentage'::text, 'fixed_amount'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE payroll_tax_grids ADD CONSTRAINT payroll_tax_grids_grid_type_check CHECK ((grid_type = ANY (ARRAY['its'::text, 'employer_contribution'::text, 'employee_contribution'::text, 'income_tax'::text, 'other_deduction'::text, 'other_income'::text, 'composite'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE payroll_tax_grids ADD CONSTRAINT payroll_tax_grids_source_check CHECK ((source = ANY (ARRAY['platform'::text, 'imported'::text, 'manual'::text, 'api'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE payroll_tax_grids ADD CONSTRAINT payroll_tax_grids_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'active'::text, 'archived'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE payroll_templates ADD CONSTRAINT payroll_templates_category_check CHECK ((category = ANY (ARRAY['standard'::text, 'cadre'::text, 'non_cadre'::text, 'apprenti'::text, 'stagiaire'::text, 'interim'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE pick_lists ADD CONSTRAINT pick_lists_reference_type_check CHECK ((reference_type = ANY (ARRAY['sales_order'::text, 'delivery_note'::text, 'production'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE pick_lists ADD CONSTRAINT pick_lists_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'in_progress'::text, 'completed'::text, 'cancelled'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE planning_slots ADD CONSTRAINT planning_slots_status_check CHECK ((status = ANY (ARRAY['planned'::text, 'scheduled'::text, 'in_progress'::text, 'completed'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE price_lists ADD CONSTRAINT price_lists_type_check CHECK ((type = ANY (ARRAY['sales'::text, 'purchase'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE product_attributes ADD CONSTRAINT product_attributes_type_check CHECK ((type = ANY (ARRAY['select'::text, 'text'::text, 'number'::text, 'color'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE product_batches ADD CONSTRAINT product_batches_status_check CHECK ((status = ANY (ARRAY['active'::text, 'expired'::text, 'quarantine'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE product_serial_numbers ADD CONSTRAINT product_serial_numbers_status_check CHECK ((status = ANY (ARRAY['in_stock'::text, 'sold'::text, 'returned'::text, 'warranty'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE production_forecasts ADD CONSTRAINT production_forecasts_source_check CHECK ((source = ANY (ARRAY['manual'::text, 'invoice_import'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE products ADD CONSTRAINT products_type_check CHECK ((type = ANY (ARRAY['stock'::text, 'service'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE projects ADD CONSTRAINT projects_status_check CHECK ((status = ANY (ARRAY['active'::text, 'completed'::text, 'on_hold'::text, 'cancelled'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE prospects ADD CONSTRAINT prospects_status_check CHECK ((status = ANY (ARRAY['new'::text, 'contacted'::text, 'qualified'::text, 'converted'::text, 'lost'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE purchase_credit_notes ADD CONSTRAINT purchase_credit_notes_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'applied'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE purchase_invoices ADD CONSTRAINT purchase_invoices_approval_status_check CHECK ((approval_status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE purchase_invoices ADD CONSTRAINT purchase_invoices_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'sent'::text, 'viewed'::text, 'paid'::text, 'overdue'::text, 'cancelled'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE purchase_orders ADD CONSTRAINT purchase_orders_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'confirmed'::text, 'received'::text, 'cancelled'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE quality_checks ADD CONSTRAINT quality_checks_reference_type_check CHECK ((reference_type = ANY (ARRAY['goods_receipt'::text, 'delivery_note'::text, 'production'::text, 'manual'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE quality_checks ADD CONSTRAINT quality_checks_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'passed'::text, 'failed'::text, 'partial'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE quotes ADD CONSTRAINT quotes_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'sent'::text, 'accepted'::text, 'rejected'::text, 'expired'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE quotes ADD CONSTRAINT quotes_validation_status_check CHECK ((validation_status = ANY (ARRAY['draft'::text, 'validated'::text, 'transformed'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE recurring_invoice_templates ADD CONSTRAINT recurring_invoice_templates_frequency_check CHECK ((frequency = ANY (ARRAY['weekly'::text, 'monthly'::text, 'quarterly'::text, 'yearly'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE reminder_levels ADD CONSTRAINT reminder_levels_level_check CHECK (((level >= 1) AND (level <= 10))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE reporting_plans ADD CONSTRAINT reporting_plans_format_check CHECK ((format = ANY (ARRAY['pdf'::text, 'excel'::text, 'csv'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE reporting_plans ADD CONSTRAINT reporting_plans_report_type_check CHECK ((report_type = ANY (ARRAY['balance'::text, 'pnl'::text, 'cashflow'::text, 'vat'::text, 'custom'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE reporting_plans ADD CONSTRAINT reporting_plans_schedule_check CHECK ((schedule = ANY (ARRAY['manual'::text, 'monthly'::text, 'quarterly'::text, 'annual'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE revision_cycles ADD CONSTRAINT revision_cycles_frequency_check CHECK ((frequency = ANY (ARRAY['monthly'::text, 'quarterly'::text, 'annual'::text, 'custom'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE revision_cycles ADD CONSTRAINT revision_cycles_start_month_check CHECK (((start_month >= 1) AND (start_month <= 12))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE rgpd_requests ADD CONSTRAINT rgpd_requests_entity_type_check CHECK ((entity_type = ANY (ARRAY['customer'::text, 'supplier'::text, 'employee'::text, 'all'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE rgpd_requests ADD CONSTRAINT rgpd_requests_request_type_check CHECK ((request_type = ANY (ARRAY['export'::text, 'delete'::text, 'anonymize'::text, 'access'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE rgpd_requests ADD CONSTRAINT rgpd_requests_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'processing'::text, 'completed'::text, 'rejected'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE rh_requests ADD CONSTRAINT rh_requests_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'in_progress'::text, 'resolved'::text, 'rejected'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE salary_advances ADD CONSTRAINT salary_advances_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'deducted'::text, 'cancelled'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE sales_orders ADD CONSTRAINT sales_orders_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'confirmed'::text, 'delivered'::text, 'invoiced'::text, 'cancelled'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE sales_orders ADD CONSTRAINT sales_orders_validation_status_check CHECK ((validation_status = ANY (ARRAY['draft'::text, 'validated'::text, 'transformed'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE sepa_payment_orders ADD CONSTRAINT sepa_payment_orders_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'generated'::text, 'transmitted'::text, 'processed'::text, 'rejected'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE social_declarations ADD CONSTRAINT social_declarations_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'generated'::text, 'transmitted'::text, 'accepted'::text, 'rejected'::text, 'regularized'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE st_orders ADD CONSTRAINT st_orders_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'sent'::text, 'in_progress'::text, 'received'::text, 'cancelled'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE st_receipt_lines ADD CONSTRAINT st_receipt_lines_line_type_check CHECK ((line_type = ANY (ARRAY['received'::text, 'returned'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE st_receipts ADD CONSTRAINT st_receipts_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'received'::text, 'partial'::text, 'cancelled'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE st_shipments ADD CONSTRAINT st_shipments_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'shipped'::text, 'returned'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE stat_fields ADD CONSTRAINT stat_fields_entity_type_check CHECK ((entity_type = ANY (ARRAY['customer'::text, 'supplier'::text, 'product'::text, 'account'::text, 'journal'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE stat_fields ADD CONSTRAINT stat_fields_field_type_check CHECK ((field_type = ANY (ARRAY['text'::text, 'number'::text, 'date'::text, 'boolean'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE stock_movements ADD CONSTRAINT stock_movements_movement_type_check CHECK ((movement_type = ANY (ARRAY['in'::text, 'out'::text, 'transfer'::text, 'adjustment'::text, 'initial'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE stock_movements ADD CONSTRAINT stock_movements_type_check CHECK ((type = ANY (ARRAY['in'::text, 'out'::text, 'adjustment'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE supplier_payments ADD CONSTRAINT supplier_payments_method_check CHECK ((method = ANY (ARRAY['cash'::text, 'check'::text, 'transfer'::text, 'card'::text, 'direct_debit'::text, 'other'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE supplier_payments ADD CONSTRAINT supplier_payments_status_check CHECK ((status = ANY (ARRAY['recorded'::text, 'reconciled'::text, 'cancelled'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE tax_rates ADD CONSTRAINT tax_rates_category_check CHECK ((category = ANY (ARRAY['standard'::text, 'intermediate'::text, 'reduced'::text, 'super_reduced'::text, 'zero'::text, 'exempt'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE tenant_users ADD CONSTRAINT tenant_users_role_check CHECK ((role = ANY (ARRAY['admin'::text, 'accountant'::text, 'manager'::text, 'viewer'::text, 'auditor'::text, 'custom'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE tenant_users ADD CONSTRAINT tenant_users_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'active'::text, 'revoked'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE tenant_users ADD CONSTRAINT tenant_users_valid_period_check CHECK (((valid_until IS NULL) OR (valid_from IS NULL) OR (valid_until >= valid_from))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE tenants ADD CONSTRAINT tenants_plan_check CHECK ((plan = ANY (ARRAY['trial'::text, 'basic'::text, 'pro'::text, 'enterprise'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE tenants ADD CONSTRAINT tenants_status_check CHECK ((status = ANY (ARRAY['active'::text, 'suspended'::text, 'cancelled'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE third_party_accounts ADD CONSTRAINT third_party_accounts_type_check CHECK ((type = ANY (ARRAY['customer'::text, 'supplier'::text, 'employee'::text, 'other'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE timesheets ADD CONSTRAINT timesheets_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE toolings ADD CONSTRAINT toolings_status_check CHECK ((status = ANY (ARRAY['active'::text, 'worn'::text, 'inactive'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE treasury_recurring ADD CONSTRAINT treasury_recurring_frequency_check CHECK ((frequency = ANY (ARRAY['weekly'::text, 'monthly'::text, 'quarterly'::text, 'yearly'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE treasury_recurring ADD CONSTRAINT treasury_recurring_type_check CHECK ((type = ANY (ARRAY['incoming'::text, 'outgoing'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE treasury_transfers ADD CONSTRAINT treasury_transfers_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'executed'::text, 'cancelled'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE tvs_declarations ADD CONSTRAINT tvs_declarations_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'filed'::text, 'paid'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE users ADD CONSTRAINT users_role_check CHECK ((role = ANY (ARRAY['admin'::text, 'accountant'::text, 'manager'::text, 'viewer'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE value_date_tracking ADD CONSTRAINT value_date_tracking_transaction_type_check CHECK ((transaction_type = ANY (ARRAY['debit'::text, 'credit'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE vat_returns ADD CONSTRAINT vat_returns_edi_status_check CHECK ((edi_status = ANY (ARRAY['not_submitted'::text, 'preparing'::text, 'submitted'::text, 'acknowledged'::text, 'rejected'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE vat_returns ADD CONSTRAINT vat_returns_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'submitted'::text, 'paid'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE work_hardship ADD CONSTRAINT work_hardship_exposure_level_check CHECK ((exposure_level = ANY (ARRAY['low'::text, 'medium'::text, 'high'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE work_hardship_records ADD CONSTRAINT work_hardship_records_declaration_status_check CHECK ((declaration_status = ANY (ARRAY['pending'::text, 'declared'::text, 'rejected'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE work_stoppages ADD CONSTRAINT work_stoppages_status_check CHECK ((status = ANY (ARRAY['active'::text, 'closed'::text, 'regularized'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE workflows ADD CONSTRAINT workflows_status_check CHECK ((status = ANY (ARRAY['active'::text, 'inactive'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE workflows ADD CONSTRAINT workflows_workflow_type_check CHECK ((workflow_type = ANY (ARRAY['mrp'::text, 'forecast'::text, 'planning'::text, 'custom'::text]))); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ============================================
-- INDEX
-- ============================================
CREATE UNIQUE INDEX IF NOT EXISTS account_tag_mappings_pkey ON public.account_tag_mappings USING btree (id);
CREATE INDEX IF NOT EXISTS idx_account_tag_mappings_entity ON public.account_tag_mappings USING btree (entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_account_tag_mappings_tag ON public.account_tag_mappings USING btree (tag_id);
CREATE INDEX IF NOT EXISTS idx_account_tag_mappings_tenant ON public.account_tag_mappings USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS account_tags_pkey ON public.account_tags USING btree (id);
CREATE INDEX IF NOT EXISTS idx_account_tags_applicability ON public.account_tags USING btree (applicability);
CREATE INDEX IF NOT EXISTS idx_account_tags_tenant ON public.account_tags USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS accounting_control_runs_pkey ON public.accounting_control_runs USING btree (id);
CREATE INDEX IF NOT EXISTS idx_acct_control_runs_tenant ON public.accounting_control_runs USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_acct_control_runs_type ON public.accounting_control_runs USING btree (control_type);
CREATE UNIQUE INDEX IF NOT EXISTS analytic_distribution_lines_pkey ON public.analytic_distribution_lines USING btree (id);
CREATE INDEX IF NOT EXISTS idx_analytic_dist_line ON public.analytic_distribution_lines USING btree (journal_line_id);
CREATE INDEX IF NOT EXISTS idx_analytic_dist_line_plan ON public.analytic_distribution_lines USING btree (plan_id);
CREATE UNIQUE INDEX IF NOT EXISTS analytic_journal_codes_pkey ON public.analytic_journal_codes USING btree (id);
CREATE INDEX IF NOT EXISTS idx_analytic_journal_codes_code ON public.analytic_journal_codes USING btree (tenant_id, code);
CREATE INDEX IF NOT EXISTS idx_analytic_journal_codes_tenant ON public.analytic_journal_codes USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS analytic_plans_pkey ON public.analytic_plans USING btree (id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_analytic_plans_code ON public.analytic_plans USING btree (tenant_id, code);
CREATE INDEX IF NOT EXISTS idx_analytic_plans_tenant ON public.analytic_plans USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS analytic_sections_pkey ON public.analytic_sections USING btree (id);
CREATE UNIQUE INDEX IF NOT EXISTS analytic_sections_tenant_code_key ON public.analytic_sections USING btree (tenant_id, code);
CREATE INDEX IF NOT EXISTS idx_analytic_sections_tenant ON public.analytic_sections USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS approval_workflows_pkey ON public.approval_workflows USING btree (id);
CREATE UNIQUE INDEX IF NOT EXISTS asset_batch_disposal_lines_pkey ON public.asset_batch_disposal_lines USING btree (id);
CREATE INDEX IF NOT EXISTS idx_asset_batch_disposal_lines_tenant ON public.asset_batch_disposal_lines USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_batch_disposal_lines_batch ON public.asset_batch_disposal_lines USING btree (batch_id);
CREATE UNIQUE INDEX IF NOT EXISTS asset_batch_disposals_pkey ON public.asset_batch_disposals USING btree (id);
CREATE INDEX IF NOT EXISTS idx_asset_batch_disposals_number ON public.asset_batch_disposals USING btree (batch_number);
CREATE INDEX IF NOT EXISTS idx_asset_batch_disposals_tenant ON public.asset_batch_disposals USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS asset_depreciation_plans_pkey ON public.asset_depreciation_plans USING btree (id);
CREATE INDEX IF NOT EXISTS idx_asset_dep_plans_asset ON public.asset_depreciation_plans USING btree (asset_id);
CREATE INDEX IF NOT EXISTS idx_asset_dep_plans_type ON public.asset_depreciation_plans USING btree (plan_type);
CREATE INDEX IF NOT EXISTS idx_asset_depreciation_plans_tenant ON public.asset_depreciation_plans USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS asset_depreciations_pkey ON public.asset_depreciations USING btree (id);
CREATE INDEX IF NOT EXISTS idx_asset_depreciations_asset ON public.asset_depreciations USING btree (asset_id);
CREATE INDEX IF NOT EXISTS idx_asset_depreciations_tenant ON public.asset_depreciations USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS asset_documents_pkey ON public.asset_documents USING btree (id);
CREATE INDEX IF NOT EXISTS idx_asset_documents_asset ON public.asset_documents USING btree (asset_id);
CREATE INDEX IF NOT EXISTS idx_asset_documents_tenant ON public.asset_documents USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS asset_families_pkey ON public.asset_families USING btree (id);
CREATE INDEX IF NOT EXISTS idx_asset_families_code ON public.asset_families USING btree (code);
CREATE INDEX IF NOT EXISTS idx_asset_families_parent ON public.asset_families USING btree (parent_id);
CREATE INDEX IF NOT EXISTS idx_asset_families_tenant ON public.asset_families USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS asset_free_fields_pkey ON public.asset_free_fields USING btree (id);
CREATE INDEX IF NOT EXISTS idx_asset_free_fields_asset ON public.asset_free_fields USING btree (asset_id);
CREATE INDEX IF NOT EXISTS idx_asset_free_fields_key ON public.asset_free_fields USING btree (field_key);
CREATE INDEX IF NOT EXISTS idx_asset_free_fields_tenant ON public.asset_free_fields USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS asset_revaluations_pkey ON public.asset_revaluations USING btree (id);
CREATE INDEX IF NOT EXISTS idx_asset_revaluations_asset ON public.asset_revaluations USING btree (asset_id);
CREATE INDEX IF NOT EXISTS idx_asset_revaluations_tenant ON public.asset_revaluations USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS asset_split_components_pkey ON public.asset_split_components USING btree (id);
CREATE INDEX IF NOT EXISTS idx_asset_split_components_split ON public.asset_split_components USING btree (split_id);
CREATE INDEX IF NOT EXISTS idx_asset_split_components_tenant ON public.asset_split_components USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS asset_splits_pkey ON public.asset_splits USING btree (id);
CREATE INDEX IF NOT EXISTS idx_asset_splits_original ON public.asset_splits USING btree (original_asset_id);
CREATE INDEX IF NOT EXISTS idx_asset_splits_tenant ON public.asset_splits USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS at_rates_pkey ON public.at_rates USING btree (id);
CREATE INDEX IF NOT EXISTS idx_at_rates_employee ON public.at_rates USING btree (employee_id);
CREATE UNIQUE INDEX IF NOT EXISTS audit_log_pkey ON public.audit_log USING btree (id);
CREATE INDEX IF NOT EXISTS idx_audit_log_action ON public.audit_log USING btree (action);
CREATE INDEX IF NOT EXISTS idx_audit_log_created_at ON public.audit_log USING btree (created_at);
CREATE INDEX IF NOT EXISTS idx_audit_log_entity_type ON public.audit_log USING btree (entity_type);
CREATE INDEX IF NOT EXISTS idx_audit_log_tenant ON public.audit_log USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_user_id ON public.audit_log USING btree (user_id);
CREATE UNIQUE INDEX IF NOT EXISTS auto_label_rules_pkey ON public.auto_label_rules USING btree (id);
CREATE INDEX IF NOT EXISTS idx_auto_label_rules_active ON public.auto_label_rules USING btree (active);
CREATE INDEX IF NOT EXISTS idx_auto_label_rules_tenant ON public.auto_label_rules USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS bank_accounts_pkey ON public.bank_accounts USING btree (id);
CREATE INDEX IF NOT EXISTS idx_bank_accounts_tenant ON public.bank_accounts USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS bank_connections_pkey ON public.bank_connections USING btree (id);
CREATE INDEX IF NOT EXISTS idx_bank_connections_status ON public.bank_connections USING btree (status);
CREATE INDEX IF NOT EXISTS idx_bank_connections_tenant ON public.bank_connections USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS bank_reconciliation_rules_pkey ON public.bank_reconciliation_rules USING btree (id);
CREATE INDEX IF NOT EXISTS idx_bank_recon_rules_active ON public.bank_reconciliation_rules USING btree (active);
CREATE INDEX IF NOT EXISTS idx_bank_recon_rules_afb ON public.bank_reconciliation_rules USING btree (afb_code);
CREATE INDEX IF NOT EXISTS idx_bank_recon_rules_tenant ON public.bank_reconciliation_rules USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_bank_reconciliation_rules_tenant ON public.bank_reconciliation_rules USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS bank_rules_pkey ON public.bank_rules USING btree (id);
CREATE INDEX IF NOT EXISTS idx_bank_rules_tenant ON public.bank_rules USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS bank_statement_imports_pkey ON public.bank_statement_imports USING btree (id);
CREATE INDEX IF NOT EXISTS idx_bank_statement_imports_tenant ON public.bank_statement_imports USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_bank_stmt_imports_account ON public.bank_statement_imports USING btree (bank_account_id);
CREATE INDEX IF NOT EXISTS idx_bank_stmt_imports_status ON public.bank_statement_imports USING btree (status);
CREATE INDEX IF NOT EXISTS idx_bank_stmt_imports_tenant ON public.bank_statement_imports USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS bank_statement_templates_pkey ON public.bank_statement_templates USING btree (id);
CREATE INDEX IF NOT EXISTS idx_bank_stmt_templates_bank ON public.bank_statement_templates USING btree (tenant_id, bank_name);
CREATE INDEX IF NOT EXISTS idx_bank_stmt_templates_tenant ON public.bank_statement_templates USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_bank_stmt_templates_validated ON public.bank_statement_templates USING btree (bank_id) WHERE (validation_status = 'validated'::text);
CREATE UNIQUE INDEX IF NOT EXISTS bank_transactions_pkey ON public.bank_transactions USING btree (id);
CREATE INDEX IF NOT EXISTS idx_bank_transactions_account_id ON public.bank_transactions USING btree (account_id);
CREATE INDEX IF NOT EXISTS idx_bank_transactions_date ON public.bank_transactions USING btree (date);
CREATE INDEX IF NOT EXISTS idx_bank_transactions_reconciled ON public.bank_transactions USING btree (reconciled);
CREATE INDEX IF NOT EXISTS idx_bank_transactions_tenant ON public.bank_transactions USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS banks_name_key ON public.banks USING btree (name);
CREATE UNIQUE INDEX IF NOT EXISTS banks_pkey ON public.banks USING btree (id);
CREATE UNIQUE INDEX IF NOT EXISTS batch_entry_sessions_pkey ON public.batch_entry_sessions USING btree (id);
CREATE INDEX IF NOT EXISTS idx_batch_entry_tenant ON public.batch_entry_sessions USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS bdes_indicators_pkey ON public.bdes_indicators USING btree (id);
CREATE INDEX IF NOT EXISTS idx_bdes_category ON public.bdes_indicators USING btree (category);
CREATE INDEX IF NOT EXISTS idx_bdes_year ON public.bdes_indicators USING btree (year);
CREATE UNIQUE INDEX IF NOT EXISTS bom_lines_pkey ON public.bom_lines USING btree (id);
CREATE INDEX IF NOT EXISTS idx_bom_lines_bom ON public.bom_lines USING btree (bom_id);
CREATE INDEX IF NOT EXISTS idx_bom_lines_tenant ON public.bom_lines USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS boms_code_key ON public.boms USING btree (code);
CREATE UNIQUE INDEX IF NOT EXISTS boms_pkey ON public.boms USING btree (id);
CREATE INDEX IF NOT EXISTS idx_boms_tenant ON public.boms USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS budget_commitments_pkey ON public.budget_commitments USING btree (id);
CREATE INDEX IF NOT EXISTS idx_budget_commitments_account ON public.budget_commitments USING btree (account_code);
CREATE INDEX IF NOT EXISTS idx_budget_commitments_fiscal_year ON public.budget_commitments USING btree (fiscal_year_id);
CREATE INDEX IF NOT EXISTS idx_budget_commitments_status ON public.budget_commitments USING btree (status);
CREATE INDEX IF NOT EXISTS idx_budget_commitments_tenant ON public.budget_commitments USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS budgets_pkey ON public.budgets USING btree (id);
CREATE INDEX IF NOT EXISTS idx_budgets_tenant ON public.budgets USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS career_history_pkey ON public.career_history USING btree (id);
CREATE INDEX IF NOT EXISTS idx_career_history_dates ON public.career_history USING btree (start_date, end_date);
CREATE INDEX IF NOT EXISTS idx_career_history_employee ON public.career_history USING btree (employee_id);
CREATE INDEX IF NOT EXISTS idx_career_history_tenant ON public.career_history USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS carry_forward_log_pkey ON public.carry_forward_log USING btree (id);
CREATE INDEX IF NOT EXISTS idx_carry_forward_log_tenant ON public.carry_forward_log USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS cash_control_sessions_pkey ON public.cash_control_sessions USING btree (id);
CREATE INDEX IF NOT EXISTS idx_cash_control_date ON public.cash_control_sessions USING btree (session_date);
CREATE INDEX IF NOT EXISTS idx_cash_control_tenant ON public.cash_control_sessions USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS chart_account_templates_pack_code_code_key ON public.chart_account_templates USING btree (pack_code, code);
CREATE UNIQUE INDEX IF NOT EXISTS chart_account_templates_pkey ON public.chart_account_templates USING btree (id);
CREATE INDEX IF NOT EXISTS idx_chart_templates_pack ON public.chart_account_templates USING btree (pack_code);
CREATE UNIQUE INDEX IF NOT EXISTS chart_accounts_pkey ON public.chart_accounts USING btree (id);
CREATE UNIQUE INDEX IF NOT EXISTS chart_accounts_tenant_code_key ON public.chart_accounts USING btree (tenant_id, code);
CREATE INDEX IF NOT EXISTS idx_chart_accounts_tenant ON public.chart_accounts USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS check_books_pkey ON public.check_books USING btree (id);
CREATE INDEX IF NOT EXISTS idx_check_books_bank_account ON public.check_books USING btree (bank_account_id);
CREATE INDEX IF NOT EXISTS idx_check_books_status ON public.check_books USING btree (status);
CREATE INDEX IF NOT EXISTS idx_check_books_tenant ON public.check_books USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS checks_pkey ON public.checks USING btree (id);
CREATE INDEX IF NOT EXISTS idx_checks_check_book ON public.checks USING btree (check_book_id);
CREATE INDEX IF NOT EXISTS idx_checks_issue_date ON public.checks USING btree (issue_date);
CREATE INDEX IF NOT EXISTS idx_checks_status ON public.checks USING btree (status);
CREATE INDEX IF NOT EXISTS idx_checks_tenant ON public.checks USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS cice_config_pkey ON public.cice_config USING btree (id);
CREATE UNIQUE INDEX IF NOT EXISTS collection_reminders_number_key ON public.collection_reminders USING btree (number);
CREATE UNIQUE INDEX IF NOT EXISTS collection_reminders_payment_link_token_key ON public.collection_reminders USING btree (payment_link_token);
CREATE UNIQUE INDEX IF NOT EXISTS collection_reminders_pkey ON public.collection_reminders USING btree (id);
CREATE INDEX IF NOT EXISTS idx_collection_reminders_customer ON public.collection_reminders USING btree (customer_id);
CREATE INDEX IF NOT EXISTS idx_collection_reminders_link_token ON public.collection_reminders USING btree (payment_link_token) WHERE (payment_link_token IS NOT NULL);
CREATE INDEX IF NOT EXISTS idx_collection_reminders_payment_status ON public.collection_reminders USING btree (payment_status);
CREATE INDEX IF NOT EXISTS idx_collection_reminders_status ON public.collection_reminders USING btree (status);
CREATE INDEX IF NOT EXISTS idx_collection_reminders_tenant ON public.collection_reminders USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS compaction_logs_pkey ON public.compaction_logs USING btree (id);
CREATE INDEX IF NOT EXISTS idx_compaction_logs_tenant ON public.compaction_logs USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS company_settings_pkey ON public.company_settings USING btree (id);
CREATE INDEX IF NOT EXISTS idx_company_settings_tenant ON public.company_settings USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS consolidated_treasury_pkey ON public.consolidated_treasury USING btree (id);
CREATE INDEX IF NOT EXISTS idx_consolidated_treasury_date ON public.consolidated_treasury USING btree (consolidation_date);
CREATE INDEX IF NOT EXISTS idx_consolidated_treasury_tenant ON public.consolidated_treasury USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS contracts_number_key ON public.contracts USING btree (number);
CREATE UNIQUE INDEX IF NOT EXISTS contracts_pkey ON public.contracts USING btree (id);
CREATE INDEX IF NOT EXISTS idx_contracts_employee ON public.contracts USING btree (employee_id);
CREATE INDEX IF NOT EXISTS idx_contracts_status ON public.contracts USING btree (status);
CREATE INDEX IF NOT EXISTS idx_contracts_tenant ON public.contracts USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS corporate_tax_grid_lines_pkey ON public.corporate_tax_grid_lines USING btree (id);
CREATE INDEX IF NOT EXISTS idx_ctgl_grid ON public.corporate_tax_grid_lines USING btree (grid_id);
CREATE INDEX IF NOT EXISTS idx_ctgl_sort ON public.corporate_tax_grid_lines USING btree (grid_id, sort_order);
CREATE UNIQUE INDEX IF NOT EXISTS corporate_tax_grids_pkey ON public.corporate_tax_grids USING btree (id);
CREATE INDEX IF NOT EXISTS idx_ctg_active ON public.corporate_tax_grids USING btree (status) WHERE (status = 'active'::text);
CREATE INDEX IF NOT EXISTS idx_ctg_country ON public.corporate_tax_grids USING btree (country_code);
CREATE INDEX IF NOT EXISTS idx_ctg_tenant ON public.corporate_tax_grids USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS cpf_accounts_employee_unique ON public.cpf_accounts USING btree (employee_id);
CREATE UNIQUE INDEX IF NOT EXISTS cpf_accounts_pkey ON public.cpf_accounts USING btree (id);
CREATE INDEX IF NOT EXISTS idx_cpf_accounts_tenant ON public.cpf_accounts USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_cpf_employee ON public.cpf_accounts USING btree (employee_id);
CREATE UNIQUE INDEX IF NOT EXISTS cpf_transactions_pkey ON public.cpf_transactions USING btree (id);
CREATE INDEX IF NOT EXISTS idx_cpf_transactions_employee ON public.cpf_transactions USING btree (employee_id);
CREATE UNIQUE INDEX IF NOT EXISTS credit_lines_pkey ON public.credit_lines USING btree (id);
CREATE INDEX IF NOT EXISTS idx_credit_lines_name ON public.credit_lines USING btree (name);
CREATE INDEX IF NOT EXISTS idx_credit_lines_status ON public.credit_lines USING btree (status);
CREATE INDEX IF NOT EXISTS idx_credit_lines_tenant ON public.credit_lines USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS credit_note_lines_pkey ON public.credit_note_lines USING btree (id);
CREATE INDEX IF NOT EXISTS idx_credit_note_lines_credit_note_id ON public.credit_note_lines USING btree (credit_note_id);
CREATE INDEX IF NOT EXISTS idx_credit_note_lines_tenant ON public.credit_note_lines USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS credit_notes_pkey ON public.credit_notes USING btree (id);
CREATE UNIQUE INDEX IF NOT EXISTS credit_notes_tenant_number_key ON public.credit_notes USING btree (tenant_id, number);
CREATE INDEX IF NOT EXISTS idx_credit_notes_tenant ON public.credit_notes USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS uniq_credit_note_number_tenant ON public.credit_notes USING btree (tenant_id, number);
CREATE UNIQUE INDEX IF NOT EXISTS crm_activities_pkey ON public.crm_activities USING btree (id);
CREATE INDEX IF NOT EXISTS idx_act_customer ON public.crm_activities USING btree (customer_id);
CREATE INDEX IF NOT EXISTS idx_act_date ON public.crm_activities USING btree (scheduled_date);
CREATE INDEX IF NOT EXISTS idx_act_opp ON public.crm_activities USING btree (opportunity_id);
CREATE UNIQUE INDEX IF NOT EXISTS crm_campaign_recipients_pkey ON public.crm_campaign_recipients USING btree (id);
CREATE INDEX IF NOT EXISTS idx_cr_camp ON public.crm_campaign_recipients USING btree (campaign_id);
CREATE UNIQUE INDEX IF NOT EXISTS crm_campaigns_pkey ON public.crm_campaigns USING btree (id);
CREATE INDEX IF NOT EXISTS idx_camp_status ON public.crm_campaigns USING btree (status);
CREATE UNIQUE INDEX IF NOT EXISTS crm_forecasts_pkey ON public.crm_forecasts USING btree (id);
CREATE INDEX IF NOT EXISTS idx_fc_period ON public.crm_forecasts USING btree (period);
CREATE UNIQUE INDEX IF NOT EXISTS crm_opportunities_pkey ON public.crm_opportunities USING btree (id);
CREATE INDEX IF NOT EXISTS idx_opp_customer ON public.crm_opportunities USING btree (customer_id);
CREATE INDEX IF NOT EXISTS idx_opp_rep ON public.crm_opportunities USING btree (sales_rep_id);
CREATE INDEX IF NOT EXISTS idx_opp_stage ON public.crm_opportunities USING btree (stage);
CREATE UNIQUE INDEX IF NOT EXISTS crm_territories_pkey ON public.crm_territories USING btree (id);
CREATE INDEX IF NOT EXISTS idx_terr_parent ON public.crm_territories USING btree (parent_id);
CREATE UNIQUE INDEX IF NOT EXISTS currencies_code_unique ON public.currencies USING btree (code);
CREATE UNIQUE INDEX IF NOT EXISTS currencies_pkey ON public.currencies USING btree (id);
CREATE UNIQUE INDEX IF NOT EXISTS currencies_tenant_code_key ON public.currencies USING btree (tenant_id, code);
CREATE INDEX IF NOT EXISTS idx_currencies_tenant ON public.currencies USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS currency_revaluations_pkey ON public.currency_revaluations USING btree (id);
CREATE INDEX IF NOT EXISTS idx_currency_reval_period ON public.currency_revaluations USING btree (period_date);
CREATE INDEX IF NOT EXISTS idx_currency_reval_status ON public.currency_revaluations USING btree (status);
CREATE INDEX IF NOT EXISTS idx_currency_reval_tenant ON public.currency_revaluations USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_currency_revaluations_tenant ON public.currency_revaluations USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS custom_report_templates_pkey ON public.custom_report_templates USING btree (id);
CREATE INDEX IF NOT EXISTS idx_custom_reports_tenant ON public.custom_report_templates USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_custom_reports_type ON public.custom_report_templates USING btree (report_type);
CREATE UNIQUE INDEX IF NOT EXISTS customer_contacts_pkey ON public.customer_contacts USING btree (id);
CREATE INDEX IF NOT EXISTS idx_cc_customer ON public.customer_contacts USING btree (customer_id);
CREATE UNIQUE INDEX IF NOT EXISTS customer_payments_number_key ON public.customer_payments USING btree (number);
CREATE UNIQUE INDEX IF NOT EXISTS customer_payments_pkey ON public.customer_payments USING btree (id);
CREATE INDEX IF NOT EXISTS idx_customer_payments_customer ON public.customer_payments USING btree (customer_id);
CREATE INDEX IF NOT EXISTS idx_customer_payments_invoice ON public.customer_payments USING btree (invoice_id);
CREATE INDEX IF NOT EXISTS idx_customer_payments_tenant ON public.customer_payments USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS customers_pkey ON public.customers USING btree (id);
CREATE INDEX IF NOT EXISTS idx_customers_tenant ON public.customers USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS dashboard_widgets_pkey ON public.dashboard_widgets USING btree (id);
CREATE INDEX IF NOT EXISTS idx_dashboard_widgets_tenant ON public.dashboard_widgets USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_dashboard_widgets_user ON public.dashboard_widgets USING btree (user_id);
CREATE UNIQUE INDEX IF NOT EXISTS deferred_printing_jobs_pkey ON public.deferred_printing_jobs USING btree (id);
CREATE INDEX IF NOT EXISTS idx_deferred_print_scheduled ON public.deferred_printing_jobs USING btree (scheduled_date);
CREATE INDEX IF NOT EXISTS idx_deferred_print_status ON public.deferred_printing_jobs USING btree (status);
CREATE INDEX IF NOT EXISTS idx_deferred_print_tenant ON public.deferred_printing_jobs USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS delivery_note_lines_pkey ON public.delivery_note_lines USING btree (id);
CREATE INDEX IF NOT EXISTS idx_delivery_note_lines_dn ON public.delivery_note_lines USING btree (delivery_note_id);
CREATE INDEX IF NOT EXISTS idx_delivery_note_lines_tenant ON public.delivery_note_lines USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS delivery_notes_number_key ON public.delivery_notes USING btree (number);
CREATE UNIQUE INDEX IF NOT EXISTS delivery_notes_pkey ON public.delivery_notes USING btree (id);
CREATE INDEX IF NOT EXISTS idx_delivery_notes_customer ON public.delivery_notes USING btree (customer_id);
CREATE INDEX IF NOT EXISTS idx_delivery_notes_tenant ON public.delivery_notes USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS delivery_schedules_pkey ON public.delivery_schedules USING btree (id);
CREATE INDEX IF NOT EXISTS idx_delivery_schedules_customer ON public.delivery_schedules USING btree (customer_id);
CREATE INDEX IF NOT EXISTS idx_delivery_schedules_product ON public.delivery_schedules USING btree (product_id);
CREATE INDEX IF NOT EXISTS idx_delivery_schedules_tenant ON public.delivery_schedules USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS disputes_pkey ON public.disputes USING btree (id);
CREATE INDEX IF NOT EXISTS idx_disputes_status ON public.disputes USING btree (status);
CREATE INDEX IF NOT EXISTS idx_disputes_tenant ON public.disputes USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS distribution_grill_lines_pkey ON public.distribution_grill_lines USING btree (id);
CREATE INDEX IF NOT EXISTS idx_distribution_grill_lines_grill ON public.distribution_grill_lines USING btree (grill_id);
CREATE INDEX IF NOT EXISTS idx_distribution_grill_lines_tenant ON public.distribution_grill_lines USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS distribution_grills_pkey ON public.distribution_grills USING btree (id);
CREATE INDEX IF NOT EXISTS idx_distribution_grills_account ON public.distribution_grills USING btree (account_code);
CREATE INDEX IF NOT EXISTS idx_distribution_grills_tenant ON public.distribution_grills USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS document_charges_pkey ON public.document_charges USING btree (id);
CREATE INDEX IF NOT EXISTS idx_doc_charges_doc ON public.document_charges USING btree (document_type, document_id);
CREATE UNIQUE INDEX IF NOT EXISTS document_distribution_logs_pkey ON public.document_distribution_logs USING btree (id);
CREATE INDEX IF NOT EXISTS idx_dist_logs_batch ON public.document_distribution_logs USING btree (batch_id);
CREATE INDEX IF NOT EXISTS idx_dist_logs_employee ON public.document_distribution_logs USING btree (employee_id);
CREATE UNIQUE INDEX IF NOT EXISTS document_shares_pkey ON public.document_shares USING btree (id);
CREATE INDEX IF NOT EXISTS idx_ds_token ON public.document_shares USING btree (share_token);
CREATE UNIQUE INDEX IF NOT EXISTS document_templates_pkey ON public.document_templates USING btree (id);
CREATE INDEX IF NOT EXISTS idx_document_templates_tenant ON public.document_templates USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_document_templates_type ON public.document_templates USING btree (document_type);
CREATE UNIQUE INDEX IF NOT EXISTS document_transformations_pkey ON public.document_transformations USING btree (id);
CREATE INDEX IF NOT EXISTS idx_doc_trans_src ON public.document_transformations USING btree (source_type, source_id);
CREATE INDEX IF NOT EXISTS idx_doc_trans_tgt ON public.document_transformations USING btree (target_type, target_id);
CREATE UNIQUE INDEX IF NOT EXISTS dpae_records_pkey ON public.dpae_records USING btree (id);
CREATE INDEX IF NOT EXISTS idx_dpae_employee ON public.dpae_records USING btree (employee_id);
CREATE INDEX IF NOT EXISTS idx_dpae_records_tenant ON public.dpae_records USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_dpae_status ON public.dpae_records USING btree (status);
CREATE UNIQUE INDEX IF NOT EXISTS dsn_declarations_pkey ON public.dsn_declarations USING btree (id);
CREATE INDEX IF NOT EXISTS idx_dsn_declarations_tenant ON public.dsn_declarations USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_dsn_period ON public.dsn_declarations USING btree (period);
CREATE INDEX IF NOT EXISTS idx_dsn_status ON public.dsn_declarations USING btree (status);
CREATE UNIQUE INDEX IF NOT EXISTS electronic_signatures_pkey ON public.electronic_signatures USING btree (id);
CREATE INDEX IF NOT EXISTS idx_es_doc ON public.electronic_signatures USING btree (document_type, document_id);
CREATE UNIQUE INDEX IF NOT EXISTS employee_activity_logs_pkey ON public.employee_activity_logs USING btree (id);
CREATE INDEX IF NOT EXISTS idx_activity_logs_date ON public.employee_activity_logs USING btree (created_at);
CREATE INDEX IF NOT EXISTS idx_activity_logs_employee ON public.employee_activity_logs USING btree (employee_id);
CREATE INDEX IF NOT EXISTS idx_activity_logs_tenant ON public.employee_activity_logs USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_activity_logs_type ON public.employee_activity_logs USING btree (activity_type);
CREATE UNIQUE INDEX IF NOT EXISTS employee_documents_pkey ON public.employee_documents USING btree (id);
CREATE INDEX IF NOT EXISTS idx_emp_docs_employee ON public.employee_documents USING btree (employee_id);
CREATE INDEX IF NOT EXISTS idx_emp_docs_period ON public.employee_documents USING btree (period);
CREATE INDEX IF NOT EXISTS idx_emp_docs_type ON public.employee_documents USING btree (document_type);
CREATE INDEX IF NOT EXISTS idx_employee_documents_employee ON public.employee_documents USING btree (employee_id);
CREATE INDEX IF NOT EXISTS idx_employee_documents_tenant ON public.employee_documents USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS employee_exit_processes_pkey ON public.employee_exit_processes USING btree (id);
CREATE INDEX IF NOT EXISTS idx_exit_processes_employee ON public.employee_exit_processes USING btree (employee_id);
CREATE INDEX IF NOT EXISTS idx_exit_processes_status ON public.employee_exit_processes USING btree (status);
CREATE UNIQUE INDEX IF NOT EXISTS employee_objectives_pkey ON public.employee_objectives USING btree (id);
CREATE INDEX IF NOT EXISTS idx_objectives_campaign ON public.employee_objectives USING btree (campaign_id);
CREATE INDEX IF NOT EXISTS idx_objectives_employee ON public.employee_objectives USING btree (employee_id);
CREATE UNIQUE INDEX IF NOT EXISTS employees_pkey ON public.employees USING btree (id);
CREATE INDEX IF NOT EXISTS idx_employees_status ON public.employees USING btree (status);
CREATE INDEX IF NOT EXISTS idx_employees_tenant ON public.employees USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS entry_templates_pkey ON public.entry_templates USING btree (id);
CREATE INDEX IF NOT EXISTS idx_entry_templates_default ON public.entry_templates USING btree (is_default) WHERE (is_default = true);
CREATE INDEX IF NOT EXISTS idx_entry_templates_journal ON public.entry_templates USING btree (journal_code);
CREATE INDEX IF NOT EXISTS idx_entry_templates_tenant ON public.entry_templates USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS etat_rapprochement_pkey ON public.etat_rapprochement USING btree (id);
CREATE INDEX IF NOT EXISTS idx_etat_rapprochement_account ON public.etat_rapprochement USING btree (account_code);
CREATE INDEX IF NOT EXISTS idx_etat_rapprochement_tenant ON public.etat_rapprochement USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS exchange_gain_loss_entries_pkey ON public.exchange_gain_loss_entries USING btree (id);
CREATE INDEX IF NOT EXISTS idx_exchange_gain_loss_invoice ON public.exchange_gain_loss_entries USING btree (invoice_id);
CREATE INDEX IF NOT EXISTS idx_exchange_gain_loss_payment ON public.exchange_gain_loss_entries USING btree (payment_id);
CREATE INDEX IF NOT EXISTS idx_exchange_gain_loss_tenant ON public.exchange_gain_loss_entries USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS exchange_rates_pkey ON public.exchange_rates USING btree (id);
CREATE INDEX IF NOT EXISTS idx_exchange_rates_latest ON public.exchange_rates USING btree (tenant_id, base_currency, quote_currency, rate_date DESC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_exchange_rates_unique ON public.exchange_rates USING btree (tenant_id, base_currency, quote_currency, rate_date);
CREATE UNIQUE INDEX IF NOT EXISTS expense_categories_pkey ON public.expense_categories USING btree (id);
CREATE UNIQUE INDEX IF NOT EXISTS expense_report_lines_pkey ON public.expense_report_lines USING btree (id);
CREATE INDEX IF NOT EXISTS idx_expense_lines_report ON public.expense_report_lines USING btree (expense_report_id);
CREATE INDEX IF NOT EXISTS idx_expense_report_lines_tenant ON public.expense_report_lines USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS expense_reports_pkey ON public.expense_reports USING btree (id);
CREATE INDEX IF NOT EXISTS idx_expense_reports_employee ON public.expense_reports USING btree (employee_id);
CREATE INDEX IF NOT EXISTS idx_expense_reports_status ON public.expense_reports USING btree (status);
CREATE INDEX IF NOT EXISTS idx_expense_reports_tenant ON public.expense_reports USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS extourne_log_pkey ON public.extourne_log USING btree (id);
CREATE INDEX IF NOT EXISTS idx_extourne_log_original ON public.extourne_log USING btree (original_entry_id);
CREATE INDEX IF NOT EXISTS idx_extourne_log_tenant ON public.extourne_log USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS fec_attestations_pkey ON public.fec_attestations USING btree (id);
CREATE INDEX IF NOT EXISTS idx_fec_attest_tenant ON public.fec_attestations USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS fiscal_backups_pkey ON public.fiscal_backups USING btree (id);
CREATE INDEX IF NOT EXISTS idx_fiscal_backups_fiscal_year ON public.fiscal_backups USING btree (fiscal_year_id);
CREATE INDEX IF NOT EXISTS idx_fiscal_backups_tenant ON public.fiscal_backups USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS fiscal_periods_pkey ON public.fiscal_periods USING btree (id);
CREATE INDEX IF NOT EXISTS idx_fiscal_periods_tenant ON public.fiscal_periods USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_fiscal_periods_year ON public.fiscal_periods USING btree (fiscal_year_id);
CREATE UNIQUE INDEX IF NOT EXISTS fiscal_position_mappings_pkey ON public.fiscal_position_mappings USING btree (id);
CREATE INDEX IF NOT EXISTS idx_fiscal_mapping_position ON public.fiscal_position_mappings USING btree (fiscal_position_id);
CREATE INDEX IF NOT EXISTS idx_fiscal_mapping_tenant ON public.fiscal_position_mappings USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS fiscal_positions_pkey ON public.fiscal_positions USING btree (id);
CREATE INDEX IF NOT EXISTS idx_fiscal_positions_country ON public.fiscal_positions USING btree (country_code);
CREATE INDEX IF NOT EXISTS idx_fiscal_positions_tenant ON public.fiscal_positions USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS fiscal_years_pkey ON public.fiscal_years USING btree (id);
CREATE UNIQUE INDEX IF NOT EXISTS fiscal_years_tenant_code_key ON public.fiscal_years USING btree (tenant_id, code);
CREATE INDEX IF NOT EXISTS idx_fiscal_years_tenant ON public.fiscal_years USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS fixed_assets_pkey ON public.fixed_assets USING btree (id);
CREATE UNIQUE INDEX IF NOT EXISTS fixed_assets_tenant_code_key ON public.fixed_assets USING btree (tenant_id, code);
CREATE INDEX IF NOT EXISTS idx_fixed_assets_status ON public.fixed_assets USING btree (status);
CREATE INDEX IF NOT EXISTS idx_fixed_assets_tenant ON public.fixed_assets USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS fusion_logs_pkey ON public.fusion_logs USING btree (id);
CREATE INDEX IF NOT EXISTS idx_fusion_logs_target ON public.fusion_logs USING btree (target_account_code);
CREATE INDEX IF NOT EXISTS idx_fusion_logs_tenant ON public.fusion_logs USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS future_accounting_movements_pkey ON public.future_accounting_movements USING btree (id);
CREATE INDEX IF NOT EXISTS idx_future_accounting_movements_tenant ON public.future_accounting_movements USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_mcf_account ON public.future_accounting_movements USING btree (account_code);
CREATE INDEX IF NOT EXISTS idx_mcf_expected_date ON public.future_accounting_movements USING btree (expected_date);
CREATE INDEX IF NOT EXISTS idx_mcf_incorporated ON public.future_accounting_movements USING btree (incorporated);
CREATE UNIQUE INDEX IF NOT EXISTS goods_receipt_lines_pkey ON public.goods_receipt_lines USING btree (id);
CREATE INDEX IF NOT EXISTS idx_goods_receipt_lines_gr ON public.goods_receipt_lines USING btree (goods_receipt_id);
CREATE INDEX IF NOT EXISTS idx_goods_receipt_lines_tenant ON public.goods_receipt_lines USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS goods_receipts_number_key ON public.goods_receipts USING btree (number);
CREATE UNIQUE INDEX IF NOT EXISTS goods_receipts_pkey ON public.goods_receipts USING btree (id);
CREATE INDEX IF NOT EXISTS idx_goods_receipts_supplier ON public.goods_receipts USING btree (supplier_id);
CREATE INDEX IF NOT EXISTS idx_goods_receipts_tenant ON public.goods_receipts USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS grid_templates_pkey ON public.grid_templates USING btree (id);
CREATE INDEX IF NOT EXISTS idx_grid_templates_code ON public.grid_templates USING btree (tenant_id, code);
CREATE INDEX IF NOT EXISTS idx_grid_templates_tenant ON public.grid_templates USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS honorarium_records_pkey ON public.honorarium_records USING btree (id);
CREATE INDEX IF NOT EXISTS idx_ifrs_adj_tenant ON public.ifrs_adjustments USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS ifrs_adjustments_pkey ON public.ifrs_adjustments USING btree (id);
CREATE INDEX IF NOT EXISTS idx_ijss_history_employee ON public.ijss_history USING btree (employee_id);
CREATE INDEX IF NOT EXISTS idx_ijss_history_stoppage ON public.ijss_history USING btree (work_stoppage_id);
CREATE UNIQUE INDEX IF NOT EXISTS ijss_history_pkey ON public.ijss_history USING btree (id);
CREATE INDEX IF NOT EXISTS idx_interview_campaigns_status ON public.interview_campaigns USING btree (status);
CREATE UNIQUE INDEX IF NOT EXISTS interview_campaigns_pkey ON public.interview_campaigns USING btree (id);
CREATE INDEX IF NOT EXISTS idx_interviews_employee ON public.interviews USING btree (employee_id);
CREATE INDEX IF NOT EXISTS idx_interviews_tenant ON public.interviews USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS interviews_pkey ON public.interviews USING btree (id);
CREATE INDEX IF NOT EXISTS idx_investments_name ON public.investments USING btree (name);
CREATE INDEX IF NOT EXISTS idx_investments_status ON public.investments USING btree (status);
CREATE INDEX IF NOT EXISTS idx_investments_tenant ON public.investments USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS investments_pkey ON public.investments USING btree (id);
CREATE INDEX IF NOT EXISTS idx_invoice_lines_invoice_id ON public.invoice_lines USING btree (invoice_id);
CREATE INDEX IF NOT EXISTS idx_invoice_lines_tenant ON public.invoice_lines USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS invoice_lines_pkey ON public.invoice_lines USING btree (id);
CREATE INDEX IF NOT EXISTS idx_invoices_customer_id ON public.invoices USING btree (customer_id);
CREATE INDEX IF NOT EXISTS idx_invoices_date ON public.invoices USING btree (date);
CREATE INDEX IF NOT EXISTS idx_invoices_status ON public.invoices USING btree (status);
CREATE INDEX IF NOT EXISTS idx_invoices_tenant ON public.invoices USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS invoices_pkey ON public.invoices USING btree (id);
CREATE UNIQUE INDEX IF NOT EXISTS invoices_tenant_number_key ON public.invoices USING btree (tenant_id, number);
CREATE UNIQUE INDEX IF NOT EXISTS uniq_invoice_number_tenant ON public.invoices USING btree (tenant_id, number);
CREATE INDEX IF NOT EXISTS idx_journal_access_tenant ON public.journal_access_rights USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_journal_access_user ON public.journal_access_rights USING btree (user_id);
CREATE UNIQUE INDEX IF NOT EXISTS journal_access_rights_pkey ON public.journal_access_rights USING btree (id);
CREATE UNIQUE INDEX IF NOT EXISTS journal_access_rights_tenant_id_user_id_journal_code_key ON public.journal_access_rights USING btree (tenant_id, user_id, journal_code);
CREATE INDEX IF NOT EXISTS idx_journal_entries_date ON public.journal_entries USING btree (date);
CREATE INDEX IF NOT EXISTS idx_journal_entries_journal_code ON public.journal_entries USING btree (journal_code);
CREATE INDEX IF NOT EXISTS idx_journal_entries_period ON public.journal_entries USING btree (fiscal_period_id);
CREATE INDEX IF NOT EXISTS idx_journal_entries_piece ON public.journal_entries USING btree (piece_number);
CREATE INDEX IF NOT EXISTS idx_journal_entries_status ON public.journal_entries USING btree (status);
CREATE INDEX IF NOT EXISTS idx_journal_entries_tenant ON public.journal_entries USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS journal_entries_pkey ON public.journal_entries USING btree (id);
CREATE UNIQUE INDEX IF NOT EXISTS journal_entries_tenant_number_key ON public.journal_entries USING btree (tenant_id, number);
CREATE UNIQUE INDEX IF NOT EXISTS uniq_journal_entry_number_tenant ON public.journal_entries USING btree (tenant_id, journal_code, number);
CREATE INDEX IF NOT EXISTS idx_journal_lines_account_general ON public.journal_lines USING btree (account_general);
CREATE INDEX IF NOT EXISTS idx_journal_lines_account_tiers ON public.journal_lines USING btree (account_tiers);
CREATE INDEX IF NOT EXISTS idx_journal_lines_analytic ON public.journal_lines USING btree (analytic_section_id);
CREATE INDEX IF NOT EXISTS idx_journal_lines_journal_id ON public.journal_lines USING btree (journal_id);
CREATE INDEX IF NOT EXISTS idx_journal_lines_lettrage ON public.journal_lines USING btree (lettrage_code);
CREATE INDEX IF NOT EXISTS idx_journal_lines_marked_bap ON public.journal_lines USING btree (marked_bap) WHERE (marked_bap = true);
CREATE INDEX IF NOT EXISTS idx_journal_lines_tenant ON public.journal_lines USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS journal_lines_pkey ON public.journal_lines USING btree (id);
CREATE INDEX IF NOT EXISTS idx_journals_code ON public.journals USING btree (code);
CREATE INDEX IF NOT EXISTS idx_journals_tenant ON public.journals USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS journals_pkey ON public.journals USING btree (id);
CREATE UNIQUE INDEX IF NOT EXISTS journals_tenant_code_key ON public.journals USING btree (tenant_id, code);
CREATE INDEX IF NOT EXISTS idx_justificatif_solde_account ON public.justificatif_solde USING btree (account_code);
CREATE INDEX IF NOT EXISTS idx_justificatif_solde_tenant ON public.justificatif_solde USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS justificatif_solde_pkey ON public.justificatif_solde USING btree (id);
CREATE INDEX IF NOT EXISTS idx_kb_category ON public.knowledge_base_articles USING btree (category);
CREATE INDEX IF NOT EXISTS idx_kb_status ON public.knowledge_base_articles USING btree (status);
CREATE UNIQUE INDEX IF NOT EXISTS knowledge_base_articles_pkey ON public.knowledge_base_articles USING btree (id);
CREATE INDEX IF NOT EXISTS idx_leave_balances_employee ON public.leave_balances USING btree (employee_id);
CREATE INDEX IF NOT EXISTS idx_leave_balances_year ON public.leave_balances USING btree (year);
CREATE UNIQUE INDEX IF NOT EXISTS leave_balances_employee_id_leave_type_year_key ON public.leave_balances USING btree (employee_id, leave_type, year);
CREATE UNIQUE INDEX IF NOT EXISTS leave_balances_pkey ON public.leave_balances USING btree (id);
CREATE INDEX IF NOT EXISTS idx_leave_provisions_employee ON public.leave_provisions USING btree (employee_id);
CREATE INDEX IF NOT EXISTS idx_leave_provisions_period ON public.leave_provisions USING btree (period);
CREATE UNIQUE INDEX IF NOT EXISTS leave_provisions_pkey ON public.leave_provisions USING btree (id);
CREATE INDEX IF NOT EXISTS idx_leave_requests_employee ON public.leave_requests USING btree (employee_id);
CREATE INDEX IF NOT EXISTS idx_leave_requests_status ON public.leave_requests USING btree (status);
CREATE INDEX IF NOT EXISTS idx_leave_requests_tenant ON public.leave_requests USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS leave_requests_pkey ON public.leave_requests USING btree (id);
CREATE UNIQUE INDEX IF NOT EXISTS leave_rules_pkey ON public.leave_rules USING btree (id);
CREATE INDEX IF NOT EXISTS idx_legal_declarations_status ON public.legal_declarations USING btree (status);
CREATE INDEX IF NOT EXISTS idx_legal_declarations_tenant ON public.legal_declarations USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_legal_declarations_type ON public.legal_declarations USING btree (declaration_type);
CREATE UNIQUE INDEX IF NOT EXISTS legal_declarations_number_key ON public.legal_declarations USING btree (number);
CREATE UNIQUE INDEX IF NOT EXISTS legal_declarations_pkey ON public.legal_declarations USING btree (id);
CREATE INDEX IF NOT EXISTS idx_legal_watch_date ON public.legal_watch USING btree (published_date);
CREATE INDEX IF NOT EXISTS idx_legal_watch_tenant ON public.legal_watch USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS legal_watch_pkey ON public.legal_watch USING btree (id);
CREATE INDEX IF NOT EXISTS idx_legislation_packs_tenant ON public.legislation_packs USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS legislation_packs_pkey ON public.legislation_packs USING btree (code);
CREATE INDEX IF NOT EXISTS idx_lettrage_diff_tenant ON public.lettrage_differences USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS lettrage_differences_pkey ON public.lettrage_differences USING btree (id);
CREATE INDEX IF NOT EXISTS idx_machines_code ON public.machines USING btree (code);
CREATE INDEX IF NOT EXISTS idx_machines_tenant ON public.machines USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_machines_work_center ON public.machines USING btree (work_center_id);
CREATE UNIQUE INDEX IF NOT EXISTS machines_pkey ON public.machines USING btree (id);
CREATE INDEX IF NOT EXISTS idx_manufacturing_orders_bom ON public.manufacturing_orders USING btree (bom_id);
CREATE INDEX IF NOT EXISTS idx_manufacturing_orders_status ON public.manufacturing_orders USING btree (status);
CREATE INDEX IF NOT EXISTS idx_manufacturing_orders_tenant ON public.manufacturing_orders USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS manufacturing_orders_number_key ON public.manufacturing_orders USING btree (number);
CREATE UNIQUE INDEX IF NOT EXISTS manufacturing_orders_pkey ON public.manufacturing_orders USING btree (id);
CREATE INDEX IF NOT EXISTS idx_marking_types_tenant ON public.marking_types USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS marking_types_pkey ON public.marking_types USING btree (id);
CREATE UNIQUE INDEX IF NOT EXISTS marking_types_tenant_id_code_key ON public.marking_types USING btree (tenant_id, code);
CREATE UNIQUE INDEX IF NOT EXISTS meal_voucher_config_pkey ON public.meal_voucher_config USING btree (id);
CREATE INDEX IF NOT EXISTS idx_medical_exams_date ON public.medical_exams USING btree (scheduled_date);
CREATE INDEX IF NOT EXISTS idx_medical_exams_employee ON public.medical_exams USING btree (employee_id);
CREATE UNIQUE INDEX IF NOT EXISTS medical_exams_pkey ON public.medical_exams USING btree (id);
CREATE INDEX IF NOT EXISTS idx_mirror_servers_machine ON public.mirror_servers USING btree (machine_id);
CREATE INDEX IF NOT EXISTS idx_mirror_servers_tenant ON public.mirror_servers USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS mirror_servers_pkey ON public.mirror_servers USING btree (id);
CREATE INDEX IF NOT EXISTS idx_mirror_verification_details_tenant ON public.mirror_verification_details USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_mirror_verification_server ON public.mirror_verification_details USING btree (mirror_server_id);
CREATE INDEX IF NOT EXISTS idx_mirror_verification_tenant ON public.mirror_verification_details USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS mirror_verification_details_pkey ON public.mirror_verification_details USING btree (id);
CREATE INDEX IF NOT EXISTS idx_doc_access_log_doc ON public.module_document_access_log USING btree (document_id);
CREATE INDEX IF NOT EXISTS idx_doc_access_log_tenant ON public.module_document_access_log USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_doc_access_log_user ON public.module_document_access_log USING btree (user_id);
CREATE UNIQUE INDEX IF NOT EXISTS module_document_access_log_pkey ON public.module_document_access_log USING btree (id);
CREATE INDEX IF NOT EXISTS idx_doc_shares_doc ON public.module_document_shares USING btree (document_id);
CREATE INDEX IF NOT EXISTS idx_doc_shares_tenant ON public.module_document_shares USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_doc_shares_token ON public.module_document_shares USING btree (share_token);
CREATE UNIQUE INDEX IF NOT EXISTS module_document_shares_pkey ON public.module_document_shares USING btree (id);
CREATE UNIQUE INDEX IF NOT EXISTS module_document_shares_share_token_key ON public.module_document_shares USING btree (share_token);
CREATE INDEX IF NOT EXISTS idx_module_documents_confidentiality ON public.module_documents USING btree (confidentiality);
CREATE INDEX IF NOT EXISTS idx_module_documents_created ON public.module_documents USING btree (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_module_documents_entity ON public.module_documents USING btree (entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_module_documents_expires ON public.module_documents USING btree (expires_at);
CREATE INDEX IF NOT EXISTS idx_module_documents_module ON public.module_documents USING btree (module);
CREATE INDEX IF NOT EXISTS idx_module_documents_status ON public.module_documents USING btree (status);
CREATE INDEX IF NOT EXISTS idx_module_documents_tenant ON public.module_documents USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_module_documents_uploaded_by ON public.module_documents USING btree (uploaded_by);
CREATE UNIQUE INDEX IF NOT EXISTS module_documents_pkey ON public.module_documents USING btree (id);
CREATE INDEX IF NOT EXISTS idx_mrp_pending_docs_tenant ON public.mrp_pending_docs USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_mrp_pending_status ON public.mrp_pending_docs USING btree (status);
CREATE UNIQUE INDEX IF NOT EXISTS mrp_pending_docs_pkey ON public.mrp_pending_docs USING btree (id);
CREATE INDEX IF NOT EXISTS idx_mrp_proposals_product ON public.mrp_proposals USING btree (product_id);
CREATE INDEX IF NOT EXISTS idx_mrp_proposals_run ON public.mrp_proposals USING btree (mrp_run_id);
CREATE INDEX IF NOT EXISTS idx_mrp_proposals_status ON public.mrp_proposals USING btree (status);
CREATE INDEX IF NOT EXISTS idx_mrp_proposals_tenant ON public.mrp_proposals USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS mrp_proposals_pkey ON public.mrp_proposals USING btree (id);
CREATE INDEX IF NOT EXISTS idx_mrp_runs_date ON public.mrp_runs USING btree (run_date);
CREATE INDEX IF NOT EXISTS idx_mrp_runs_tenant ON public.mrp_runs USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS mrp_runs_pkey ON public.mrp_runs USING btree (id);
CREATE UNIQUE INDEX IF NOT EXISTS mrp_runs_run_number_key ON public.mrp_runs USING btree (run_number);
CREATE INDEX IF NOT EXISTS idx_email_queue_created ON public.notification_email_queue USING btree (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_email_queue_recipient ON public.notification_email_queue USING btree (recipient_email);
CREATE INDEX IF NOT EXISTS idx_email_queue_status ON public.notification_email_queue USING btree (status);
CREATE INDEX IF NOT EXISTS idx_email_queue_tenant ON public.notification_email_queue USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS notification_email_queue_pkey ON public.notification_email_queue USING btree (id);
CREATE INDEX IF NOT EXISTS idx_notif_prefs_employee ON public.notification_preferences USING btree (employee_id);
CREATE INDEX IF NOT EXISTS idx_notif_prefs_tenant ON public.notification_preferences USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS notification_preferences_pkey ON public.notification_preferences USING btree (id);
CREATE UNIQUE INDEX IF NOT EXISTS notification_preferences_tenant_id_employee_id_key ON public.notification_preferences USING btree (tenant_id, employee_id);
CREATE INDEX IF NOT EXISTS idx_of_consumptions_mo ON public.of_consumptions USING btree (manufacturing_order_id);
CREATE INDEX IF NOT EXISTS idx_of_consumptions_tenant ON public.of_consumptions USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS of_consumptions_pkey ON public.of_consumptions USING btree (id);
CREATE INDEX IF NOT EXISTS idx_of_doc_access_user ON public.of_document_access USING btree (user_id);
CREATE UNIQUE INDEX IF NOT EXISTS of_document_access_pkey ON public.of_document_access USING btree (id);
CREATE INDEX IF NOT EXISTS idx_of_labels_mo ON public.of_labels USING btree (manufacturing_order_id);
CREATE INDEX IF NOT EXISTS idx_of_labels_tenant ON public.of_labels USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS of_labels_label_number_key ON public.of_labels USING btree (label_number);
CREATE UNIQUE INDEX IF NOT EXISTS of_labels_pkey ON public.of_labels USING btree (id);
CREATE INDEX IF NOT EXISTS idx_of_lots_mo ON public.of_lots USING btree (manufacturing_order_id);
CREATE INDEX IF NOT EXISTS idx_of_lots_tenant ON public.of_lots USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS of_lots_pkey ON public.of_lots USING btree (id);
CREATE INDEX IF NOT EXISTS idx_op_invoice ON public.online_payments USING btree (invoice_id);
CREATE UNIQUE INDEX IF NOT EXISTS online_payments_pkey ON public.online_payments USING btree (id);
CREATE INDEX IF NOT EXISTS idx_partner_bank_accounts ON public.partner_bank_accounts USING btree (partner_type, partner_id);
CREATE INDEX IF NOT EXISTS idx_partner_bank_accounts_partner ON public.partner_bank_accounts USING btree (partner_id);
CREATE INDEX IF NOT EXISTS idx_partner_bank_accounts_tenant ON public.partner_bank_accounts USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS partner_bank_accounts_pkey ON public.partner_bank_accounts USING btree (id);
CREATE UNIQUE INDEX IF NOT EXISTS partner_categories_pkey ON public.partner_categories USING btree (id);
CREATE INDEX IF NOT EXISTS idx_partner_cat_mapping ON public.partner_category_mappings USING btree (partner_type, partner_id);
CREATE INDEX IF NOT EXISTS idx_partner_cat_mapping_cat ON public.partner_category_mappings USING btree (category_id);
CREATE UNIQUE INDEX IF NOT EXISTS partner_category_mappings_pkey ON public.partner_category_mappings USING btree (id);
CREATE INDEX IF NOT EXISTS idx_partner_contacts_partner ON public.partner_contacts USING btree (partner_type, partner_id);
CREATE UNIQUE INDEX IF NOT EXISTS partner_contacts_pkey ON public.partner_contacts USING btree (id);
CREATE INDEX IF NOT EXISTS idx_pas_rates_dates ON public.pas_rates USING btree (effective_date, expiry_date);
CREATE INDEX IF NOT EXISTS idx_pas_rates_employee ON public.pas_rates USING btree (employee_id);
CREATE UNIQUE INDEX IF NOT EXISTS pas_rates_pkey ON public.pas_rates USING btree (id);
CREATE INDEX IF NOT EXISTS idx_pay_recalls_employee ON public.pay_recalls USING btree (employee_id);
CREATE INDEX IF NOT EXISTS idx_pay_recalls_tenant ON public.pay_recalls USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS pay_recalls_pkey ON public.pay_recalls USING btree (id);
CREATE INDEX IF NOT EXISTS idx_pay_runs_status ON public.pay_runs USING btree (status);
CREATE INDEX IF NOT EXISTS idx_pay_runs_tenant ON public.pay_runs USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS pay_runs_pkey ON public.pay_runs USING btree (id);
CREATE UNIQUE INDEX IF NOT EXISTS pay_runs_tenant_number_key ON public.pay_runs USING btree (tenant_id, number);
CREATE INDEX IF NOT EXISTS idx_payslip_clarified_slip ON public.pay_slip_clarified USING btree (pay_slip_id);
CREATE UNIQUE INDEX IF NOT EXISTS pay_slip_clarified_pkey ON public.pay_slip_clarified USING btree (id);
CREATE INDEX IF NOT EXISTS idx_pay_slips_employee ON public.pay_slips USING btree (employee_id);
CREATE INDEX IF NOT EXISTS idx_pay_slips_pay_run ON public.pay_slips USING btree (pay_run_id);
CREATE INDEX IF NOT EXISTS idx_pay_slips_status ON public.pay_slips USING btree (status);
CREATE INDEX IF NOT EXISTS idx_pay_slips_tenant ON public.pay_slips USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS pay_slips_number_key ON public.pay_slips USING btree (number);
CREATE UNIQUE INDEX IF NOT EXISTS pay_slips_pkey ON public.pay_slips USING btree (id);
CREATE UNIQUE INDEX IF NOT EXISTS uniq_pay_slip_number_tenant ON public.pay_slips USING btree (tenant_id, number);
CREATE INDEX IF NOT EXISTS idx_payment_orders_bank ON public.payment_orders USING btree (bank_account_id);
CREATE INDEX IF NOT EXISTS idx_payment_orders_date ON public.payment_orders USING btree (payment_date);
CREATE INDEX IF NOT EXISTS idx_payment_orders_status ON public.payment_orders USING btree (status);
CREATE INDEX IF NOT EXISTS idx_payment_orders_tenant ON public.payment_orders USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS payment_orders_number_key ON public.payment_orders USING btree (number);
CREATE UNIQUE INDEX IF NOT EXISTS payment_orders_pkey ON public.payment_orders USING btree (id);
CREATE INDEX IF NOT EXISTS idx_payment_promises_date ON public.payment_promises USING btree (promised_date);
CREATE INDEX IF NOT EXISTS idx_payment_promises_status ON public.payment_promises USING btree (status);
CREATE INDEX IF NOT EXISTS idx_payment_promises_tenant ON public.payment_promises USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS payment_promises_pkey ON public.payment_promises USING btree (id);
CREATE INDEX IF NOT EXISTS idx_payment_templates_compta_code ON public.payment_templates_compta USING btree (tenant_id, code);
CREATE INDEX IF NOT EXISTS idx_payment_templates_compta_tenant ON public.payment_templates_compta USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS payment_templates_compta_pkey ON public.payment_templates_compta USING btree (id);
CREATE INDEX IF NOT EXISTS idx_payment_terms_active ON public.payment_terms USING btree (active);
CREATE INDEX IF NOT EXISTS idx_payment_terms_tenant ON public.payment_terms USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS payment_terms_pkey ON public.payment_terms USING btree (id);
CREATE UNIQUE INDEX IF NOT EXISTS payment_terms_tenant_id_code_key ON public.payment_terms USING btree (tenant_id, code);
CREATE INDEX IF NOT EXISTS idx_payroll_accounting_entries_tenant ON public.payroll_accounting_entries USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_payroll_acct_pay_run ON public.payroll_accounting_entries USING btree (pay_run_id);
CREATE INDEX IF NOT EXISTS idx_payroll_acct_status ON public.payroll_accounting_entries USING btree (status);
CREATE UNIQUE INDEX IF NOT EXISTS payroll_accounting_entries_number_key ON public.payroll_accounting_entries USING btree (number);
CREATE UNIQUE INDEX IF NOT EXISTS payroll_accounting_entries_pkey ON public.payroll_accounting_entries USING btree (id);
CREATE INDEX IF NOT EXISTS idx_payroll_archives_employee ON public.payroll_archives USING btree (employee_id);
CREATE INDEX IF NOT EXISTS idx_payroll_archives_period ON public.payroll_archives USING btree (period);
CREATE INDEX IF NOT EXISTS idx_payroll_archives_tenant ON public.payroll_archives USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS payroll_archives_pkey ON public.payroll_archives USING btree (id);
CREATE INDEX IF NOT EXISTS idx_payroll_component_rates_tenant ON public.payroll_component_rates USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_payroll_rates_component ON public.payroll_component_rates USING btree (component_id);
CREATE UNIQUE INDEX IF NOT EXISTS payroll_component_rates_pkey ON public.payroll_component_rates USING btree (id);
CREATE INDEX IF NOT EXISTS idx_payroll_components_code ON public.payroll_components USING btree (code);
CREATE INDEX IF NOT EXISTS idx_payroll_components_tenant ON public.payroll_components USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_payroll_components_type ON public.payroll_components USING btree (type);
CREATE UNIQUE INDEX IF NOT EXISTS payroll_components_pkey ON public.payroll_components USING btree (id);
CREATE INDEX IF NOT EXISTS idx_ptgl_grid ON public.payroll_tax_grid_lines USING btree (grid_id);
CREATE INDEX IF NOT EXISTS idx_ptgl_sort ON public.payroll_tax_grid_lines USING btree (grid_id, sort_order);
CREATE UNIQUE INDEX IF NOT EXISTS payroll_tax_grid_lines_pkey ON public.payroll_tax_grid_lines USING btree (id);
CREATE INDEX IF NOT EXISTS idx_ptg_active ON public.payroll_tax_grids USING btree (status) WHERE (status = 'active'::text);
CREATE INDEX IF NOT EXISTS idx_ptg_country ON public.payroll_tax_grids USING btree (country_code);
CREATE INDEX IF NOT EXISTS idx_ptg_tenant ON public.payroll_tax_grids USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_ptg_type ON public.payroll_tax_grids USING btree (grid_type);
CREATE UNIQUE INDEX IF NOT EXISTS payroll_tax_grids_pkey ON public.payroll_tax_grids USING btree (id);
CREATE INDEX IF NOT EXISTS idx_payroll_templates_name ON public.payroll_templates USING btree (name);
CREATE INDEX IF NOT EXISTS idx_payroll_templates_tenant ON public.payroll_templates USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS payroll_templates_pkey ON public.payroll_templates USING btree (id);
CREATE INDEX IF NOT EXISTS idx_variable_elements_employee ON public.payroll_variable_elements USING btree (employee_id);
CREATE INDEX IF NOT EXISTS idx_variable_elements_payrun ON public.payroll_variable_elements USING btree (pay_run_id);
CREATE INDEX IF NOT EXISTS idx_variable_elements_period ON public.payroll_variable_elements USING btree (period);
CREATE UNIQUE INDEX IF NOT EXISTS payroll_variable_elements_pkey ON public.payroll_variable_elements USING btree (id);
CREATE INDEX IF NOT EXISTS idx_pick_list_lines_pick ON public.pick_list_lines USING btree (pick_list_id);
CREATE INDEX IF NOT EXISTS idx_pick_list_lines_tenant ON public.pick_list_lines USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS pick_list_lines_pkey ON public.pick_list_lines USING btree (id);
CREATE INDEX IF NOT EXISTS idx_pick_lists_number ON public.pick_lists USING btree (number);
CREATE INDEX IF NOT EXISTS idx_pick_lists_status ON public.pick_lists USING btree (status);
CREATE INDEX IF NOT EXISTS idx_pick_lists_tenant ON public.pick_lists USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS pick_lists_pkey ON public.pick_lists USING btree (id);
CREATE INDEX IF NOT EXISTS idx_planning_dates ON public.planning_slots USING btree (planned_start, planned_end);
CREATE INDEX IF NOT EXISTS idx_planning_machine ON public.planning_slots USING btree (machine_id);
CREATE INDEX IF NOT EXISTS idx_planning_mo ON public.planning_slots USING btree (manufacturing_order_id);
CREATE INDEX IF NOT EXISTS idx_planning_slots_tenant ON public.planning_slots USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS planning_slots_pkey ON public.planning_slots USING btree (id);
CREATE INDEX IF NOT EXISTS idx_ps_status ON public.pos_sessions USING btree (status);
CREATE INDEX IF NOT EXISTS idx_ps_terminal ON public.pos_sessions USING btree (terminal_id);
CREATE UNIQUE INDEX IF NOT EXISTS pos_sessions_pkey ON public.pos_sessions USING btree (id);
CREATE UNIQUE INDEX IF NOT EXISTS pos_terminals_pkey ON public.pos_terminals USING btree (id);
CREATE INDEX IF NOT EXISTS idx_ptl_ticket ON public.pos_ticket_lines USING btree (ticket_id);
CREATE UNIQUE INDEX IF NOT EXISTS pos_ticket_lines_pkey ON public.pos_ticket_lines USING btree (id);
CREATE INDEX IF NOT EXISTS idx_pt_date ON public.pos_tickets USING btree (date);
CREATE INDEX IF NOT EXISTS idx_pt_session ON public.pos_tickets USING btree (session_id);
CREATE UNIQUE INDEX IF NOT EXISTS pos_tickets_pkey ON public.pos_tickets USING btree (id);
CREATE INDEX IF NOT EXISTS idx_price_list_lines_list ON public.price_list_lines USING btree (price_list_id);
CREATE INDEX IF NOT EXISTS idx_price_list_lines_tenant ON public.price_list_lines USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS price_list_lines_pkey ON public.price_list_lines USING btree (id);
CREATE INDEX IF NOT EXISTS idx_price_lists_tenant ON public.price_lists USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS price_lists_code_key ON public.price_lists USING btree (code);
CREATE UNIQUE INDEX IF NOT EXISTS price_lists_pkey ON public.price_lists USING btree (id);
CREATE INDEX IF NOT EXISTS idx_product_attributes_name ON public.product_attributes USING btree (name);
CREATE INDEX IF NOT EXISTS idx_product_attributes_tenant ON public.product_attributes USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS product_attributes_pkey ON public.product_attributes USING btree (id);
CREATE INDEX IF NOT EXISTS idx_product_batches_number ON public.product_batches USING btree (batch_number);
CREATE INDEX IF NOT EXISTS idx_product_batches_product ON public.product_batches USING btree (product_id);
CREATE INDEX IF NOT EXISTS idx_product_batches_tenant ON public.product_batches USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS product_batches_pkey ON public.product_batches USING btree (id);
CREATE INDEX IF NOT EXISTS idx_equiv_product ON public.product_equivalences USING btree (product_id);
CREATE UNIQUE INDEX IF NOT EXISTS product_equivalences_pkey ON public.product_equivalences USING btree (id);
CREATE INDEX IF NOT EXISTS idx_pgc_product ON public.product_grid_combinations USING btree (product_id);
CREATE UNIQUE INDEX IF NOT EXISTS product_grid_combinations_pkey ON public.product_grid_combinations USING btree (id);
CREATE INDEX IF NOT EXISTS idx_pg_product ON public.product_grids USING btree (product_id);
CREATE UNIQUE INDEX IF NOT EXISTS product_grids_pkey ON public.product_grids USING btree (id);
CREATE INDEX IF NOT EXISTS idx_pl_product ON public.product_links USING btree (product_id);
CREATE UNIQUE INDEX IF NOT EXISTS product_links_pkey ON public.product_links USING btree (id);
CREATE INDEX IF NOT EXISTS idx_pp_product ON public.product_packagings USING btree (product_id);
CREATE UNIQUE INDEX IF NOT EXISTS product_packagings_pkey ON public.product_packagings USING btree (id);
CREATE INDEX IF NOT EXISTS idx_product_serial_numbers_tenant ON public.product_serial_numbers USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_product_serials_number ON public.product_serial_numbers USING btree (serial_number);
CREATE INDEX IF NOT EXISTS idx_product_serials_product ON public.product_serial_numbers USING btree (product_id);
CREATE UNIQUE INDEX IF NOT EXISTS product_serial_numbers_pkey ON public.product_serial_numbers USING btree (id);
CREATE INDEX IF NOT EXISTS idx_product_substitutes_product ON public.product_substitutes USING btree (product_id);
CREATE INDEX IF NOT EXISTS idx_product_substitutes_tenant ON public.product_substitutes USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS product_substitutes_pkey ON public.product_substitutes USING btree (id);
CREATE INDEX IF NOT EXISTS idx_product_variants_product ON public.product_variants USING btree (product_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_sku ON public.product_variants USING btree (sku);
CREATE INDEX IF NOT EXISTS idx_product_variants_tenant ON public.product_variants USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS product_variants_pkey ON public.product_variants USING btree (id);
CREATE INDEX IF NOT EXISTS idx_forecasts_period ON public.production_forecasts USING btree (period);
CREATE INDEX IF NOT EXISTS idx_forecasts_product ON public.production_forecasts USING btree (product_id);
CREATE INDEX IF NOT EXISTS idx_production_forecasts_tenant ON public.production_forecasts USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS production_forecasts_forecast_number_key ON public.production_forecasts USING btree (forecast_number);
CREATE UNIQUE INDEX IF NOT EXISTS production_forecasts_pkey ON public.production_forecasts USING btree (id);
CREATE INDEX IF NOT EXISTS idx_products_tenant ON public.products USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS products_pkey ON public.products USING btree (id);
CREATE UNIQUE INDEX IF NOT EXISTS products_tenant_sku_key ON public.products USING btree (tenant_id, sku);
CREATE INDEX IF NOT EXISTS idx_activity_log_created ON public.project_activity_log USING btree (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_activity_log_project ON public.project_activity_log USING btree (project_id);
CREATE INDEX IF NOT EXISTS idx_activity_log_task ON public.project_activity_log USING btree (task_id);
CREATE INDEX IF NOT EXISTS idx_activity_log_tenant ON public.project_activity_log USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_activity_log_type ON public.project_activity_log USING btree (action_type);
CREATE UNIQUE INDEX IF NOT EXISTS project_activity_log_pkey ON public.project_activity_log USING btree (id);
CREATE INDEX IF NOT EXISTS idx_project_docs_project ON public.project_docs USING btree (project_id);
CREATE INDEX IF NOT EXISTS idx_project_docs_tenant ON public.project_docs USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_project_docs_updated ON public.project_docs USING btree (updated_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS project_docs_pkey ON public.project_docs USING btree (id);
CREATE INDEX IF NOT EXISTS idx_project_members_employee ON public.project_members USING btree (employee_id);
CREATE INDEX IF NOT EXISTS idx_project_members_project ON public.project_members USING btree (project_id);
CREATE INDEX IF NOT EXISTS idx_project_members_tenant ON public.project_members USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS project_members_pkey ON public.project_members USING btree (id);
CREATE UNIQUE INDEX IF NOT EXISTS project_members_tenant_id_project_id_employee_id_key ON public.project_members USING btree (tenant_id, project_id, employee_id);
CREATE INDEX IF NOT EXISTS idx_project_milestones_project ON public.project_milestones USING btree (project_id);
CREATE INDEX IF NOT EXISTS idx_project_milestones_tenant ON public.project_milestones USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS project_milestones_pkey ON public.project_milestones USING btree (id);
CREATE INDEX IF NOT EXISTS idx_notifications_created ON public.project_notifications USING btree (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notifications_recipient ON public.project_notifications USING btree (recipient_id);
CREATE INDEX IF NOT EXISTS idx_notifications_tenant ON public.project_notifications USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_notifications_unread ON public.project_notifications USING btree (recipient_id, is_read);
CREATE UNIQUE INDEX IF NOT EXISTS project_notifications_pkey ON public.project_notifications USING btree (id);
CREATE INDEX IF NOT EXISTS idx_project_stages_sequence ON public.project_stages USING btree (sequence);
CREATE INDEX IF NOT EXISTS idx_project_stages_tenant ON public.project_stages USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS project_stages_pkey ON public.project_stages USING btree (id);
CREATE INDEX IF NOT EXISTS idx_project_tags_tenant ON public.project_tags USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS project_tags_pkey ON public.project_tags USING btree (id);
CREATE UNIQUE INDEX IF NOT EXISTS project_task_assignees_pkey ON public.project_task_assignees USING btree (task_id, employee_id);
CREATE INDEX IF NOT EXISTS idx_project_task_dependencies_depends ON public.project_task_dependencies USING btree (depends_on_task_id);
CREATE INDEX IF NOT EXISTS idx_project_task_dependencies_task ON public.project_task_dependencies USING btree (task_id);
CREATE UNIQUE INDEX IF NOT EXISTS project_task_dependencies_pkey ON public.project_task_dependencies USING btree (id);
CREATE UNIQUE INDEX IF NOT EXISTS project_task_tags_pkey ON public.project_task_tags USING btree (task_id, tag_id);
CREATE INDEX IF NOT EXISTS idx_task_templates_tenant ON public.project_task_templates USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS project_task_templates_pkey ON public.project_task_templates USING btree (id);
CREATE INDEX IF NOT EXISTS idx_task_watchers_employee ON public.project_task_watchers USING btree (employee_id);
CREATE INDEX IF NOT EXISTS idx_task_watchers_task ON public.project_task_watchers USING btree (task_id);
CREATE UNIQUE INDEX IF NOT EXISTS project_task_watchers_pkey ON public.project_task_watchers USING btree (id);
CREATE UNIQUE INDEX IF NOT EXISTS project_task_watchers_task_id_employee_id_key ON public.project_task_watchers USING btree (task_id, employee_id);
CREATE INDEX IF NOT EXISTS idx_project_tasks_display_order ON public.project_tasks USING btree (display_order);
CREATE INDEX IF NOT EXISTS idx_project_tasks_parent ON public.project_tasks USING btree (parent_id);
CREATE INDEX IF NOT EXISTS idx_project_tasks_priority ON public.project_tasks USING btree (priority);
CREATE INDEX IF NOT EXISTS idx_project_tasks_project ON public.project_tasks USING btree (project_id);
CREATE INDEX IF NOT EXISTS idx_project_tasks_status ON public.project_tasks USING btree (status);
CREATE INDEX IF NOT EXISTS idx_project_tasks_tenant ON public.project_tasks USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS project_tasks_pkey ON public.project_tasks USING btree (id);
CREATE INDEX IF NOT EXISTS idx_time_entries_employee ON public.project_time_entries USING btree (employee_id);
CREATE INDEX IF NOT EXISTS idx_time_entries_project ON public.project_time_entries USING btree (project_id);
CREATE INDEX IF NOT EXISTS idx_time_entries_start ON public.project_time_entries USING btree (start_time);
CREATE INDEX IF NOT EXISTS idx_time_entries_task ON public.project_time_entries USING btree (task_id);
CREATE INDEX IF NOT EXISTS idx_time_entries_tenant ON public.project_time_entries USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS project_time_entries_pkey ON public.project_time_entries USING btree (id);
CREATE INDEX IF NOT EXISTS idx_projects_tenant ON public.projects USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS projects_pkey ON public.projects USING btree (id);
CREATE INDEX IF NOT EXISTS idx_promo_dates ON public.promotions USING btree (start_date, end_date);
CREATE UNIQUE INDEX IF NOT EXISTS promotions_pkey ON public.promotions USING btree (id);
CREATE INDEX IF NOT EXISTS idx_prospects_name ON public.prospects USING btree (name);
CREATE INDEX IF NOT EXISTS idx_prospects_status ON public.prospects USING btree (status);
CREATE INDEX IF NOT EXISTS idx_prospects_tenant ON public.prospects USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS prospects_pkey ON public.prospects USING btree (id);
CREATE INDEX IF NOT EXISTS idx_public_holidays_date ON public.public_holidays USING btree (holiday_date);
CREATE INDEX IF NOT EXISTS idx_public_holidays_region ON public.public_holidays USING btree (region);
CREATE UNIQUE INDEX IF NOT EXISTS public_holidays_pkey ON public.public_holidays USING btree (id);
CREATE INDEX IF NOT EXISTS idx_purchase_credit_lines_purchase_credit_id ON public.purchase_credit_lines USING btree (purchase_credit_id);
CREATE INDEX IF NOT EXISTS idx_purchase_credit_lines_tenant ON public.purchase_credit_lines USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS purchase_credit_lines_pkey ON public.purchase_credit_lines USING btree (id);
CREATE INDEX IF NOT EXISTS idx_purchase_credit_notes_tenant ON public.purchase_credit_notes USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS purchase_credit_notes_pkey ON public.purchase_credit_notes USING btree (id);
CREATE UNIQUE INDEX IF NOT EXISTS purchase_credit_notes_tenant_number_key ON public.purchase_credit_notes USING btree (tenant_id, number);
CREATE INDEX IF NOT EXISTS idx_purchase_invoice_lines_purchase_invoice_id ON public.purchase_invoice_lines USING btree (purchase_invoice_id);
CREATE INDEX IF NOT EXISTS idx_purchase_invoice_lines_tenant ON public.purchase_invoice_lines USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS purchase_invoice_lines_pkey ON public.purchase_invoice_lines USING btree (id);
CREATE INDEX IF NOT EXISTS idx_purchase_invoices_approval ON public.purchase_invoices USING btree (approval_status) WHERE (approval_status = 'pending'::text);
CREATE INDEX IF NOT EXISTS idx_purchase_invoices_status ON public.purchase_invoices USING btree (status);
CREATE INDEX IF NOT EXISTS idx_purchase_invoices_supplier_id ON public.purchase_invoices USING btree (supplier_id);
CREATE INDEX IF NOT EXISTS idx_purchase_invoices_tenant ON public.purchase_invoices USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS purchase_invoices_pkey ON public.purchase_invoices USING btree (id);
CREATE UNIQUE INDEX IF NOT EXISTS purchase_invoices_tenant_number_key ON public.purchase_invoices USING btree (tenant_id, number);
CREATE INDEX IF NOT EXISTS idx_purchase_order_lines_order ON public.purchase_order_lines USING btree (purchase_order_id);
CREATE INDEX IF NOT EXISTS idx_purchase_order_lines_tenant ON public.purchase_order_lines USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS purchase_order_lines_pkey ON public.purchase_order_lines USING btree (id);
CREATE INDEX IF NOT EXISTS idx_purchase_orders_supplier ON public.purchase_orders USING btree (supplier_id);
CREATE INDEX IF NOT EXISTS idx_purchase_orders_tenant ON public.purchase_orders USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS purchase_orders_number_key ON public.purchase_orders USING btree (number);
CREATE UNIQUE INDEX IF NOT EXISTS purchase_orders_pkey ON public.purchase_orders USING btree (id);
CREATE INDEX IF NOT EXISTS idx_prl_request ON public.purchase_request_lines USING btree (purchase_request_id);
CREATE UNIQUE INDEX IF NOT EXISTS purchase_request_lines_pkey ON public.purchase_request_lines USING btree (id);
CREATE INDEX IF NOT EXISTS idx_pr_number ON public.purchase_requests USING btree (number);
CREATE UNIQUE INDEX IF NOT EXISTS purchase_requests_pkey ON public.purchase_requests USING btree (id);
CREATE INDEX IF NOT EXISTS idx_quality_checks_product ON public.quality_checks USING btree (product_id);
CREATE INDEX IF NOT EXISTS idx_quality_checks_status ON public.quality_checks USING btree (status);
CREATE INDEX IF NOT EXISTS idx_quality_checks_tenant ON public.quality_checks USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS quality_checks_pkey ON public.quality_checks USING btree (id);
CREATE INDEX IF NOT EXISTS idx_quote_lines_quote_id ON public.quote_lines USING btree (quote_id);
CREATE INDEX IF NOT EXISTS idx_quote_lines_tenant ON public.quote_lines USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS quote_lines_pkey ON public.quote_lines USING btree (id);
CREATE INDEX IF NOT EXISTS idx_quotes_tenant ON public.quotes USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS quotes_pkey ON public.quotes USING btree (id);
CREATE UNIQUE INDEX IF NOT EXISTS quotes_tenant_number_key ON public.quotes USING btree (tenant_id, number);
CREATE INDEX IF NOT EXISTS idx_recurring_entries_next_gen ON public.recurring_entries USING btree (next_generation_date) WHERE (status = 'active'::text);
CREATE INDEX IF NOT EXISTS idx_recurring_entries_status ON public.recurring_entries USING btree (status);
CREATE INDEX IF NOT EXISTS idx_recurring_entries_tenant ON public.recurring_entries USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS recurring_entries_pkey ON public.recurring_entries USING btree (id);
CREATE INDEX IF NOT EXISTS idx_recurring_inv_templates_customer ON public.recurring_invoice_templates USING btree (customer_id);
CREATE INDEX IF NOT EXISTS idx_recurring_invoice_templates_tenant ON public.recurring_invoice_templates USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS recurring_invoice_templates_pkey ON public.recurring_invoice_templates USING btree (id);
CREATE INDEX IF NOT EXISTS idx_regularization_entries_tenant ON public.regularization_entries USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_regularization_fiscal_year ON public.regularization_entries USING btree (fiscal_year_id);
CREATE INDEX IF NOT EXISTS idx_regularization_status ON public.regularization_entries USING btree (status);
CREATE INDEX IF NOT EXISTS idx_regularization_tenant ON public.regularization_entries USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_regularization_type ON public.regularization_entries USING btree (type);
CREATE UNIQUE INDEX IF NOT EXISTS regularization_entries_pkey ON public.regularization_entries USING btree (id);
CREATE INDEX IF NOT EXISTS idx_reimputation_logs_entry ON public.reimputation_logs USING btree (tenant_id, original_entry_id);
CREATE INDEX IF NOT EXISTS idx_reimputation_logs_tenant ON public.reimputation_logs USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS reimputation_logs_pkey ON public.reimputation_logs USING btree (id);
CREATE INDEX IF NOT EXISTS idx_reminder_levels_active ON public.reminder_levels USING btree (active);
CREATE INDEX IF NOT EXISTS idx_reminder_levels_tenant ON public.reminder_levels USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS reminder_levels_pkey ON public.reminder_levels USING btree (id);
CREATE UNIQUE INDEX IF NOT EXISTS reminder_levels_tenant_id_level_key ON public.reminder_levels USING btree (tenant_id, level);
CREATE INDEX IF NOT EXISTS idx_reporting_plans_active ON public.reporting_plans USING btree (active);
CREATE INDEX IF NOT EXISTS idx_reporting_plans_tenant ON public.reporting_plans USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS reporting_plans_pkey ON public.reporting_plans USING btree (id);
CREATE INDEX IF NOT EXISTS idx_revision_cycles_active ON public.revision_cycles USING btree (active);
CREATE INDEX IF NOT EXISTS idx_revision_cycles_tenant ON public.revision_cycles USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS revision_cycles_pkey ON public.revision_cycles USING btree (id);
CREATE INDEX IF NOT EXISTS idx_rgpd_requests_status ON public.rgpd_requests USING btree (status);
CREATE INDEX IF NOT EXISTS idx_rgpd_requests_tenant ON public.rgpd_requests USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS rgpd_requests_pkey ON public.rgpd_requests USING btree (id);
CREATE INDEX IF NOT EXISTS idx_rh_dashboard_configs_tenant ON public.rh_dashboard_configs USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_rh_dashboard_configs_user ON public.rh_dashboard_configs USING btree (user_email);
CREATE UNIQUE INDEX IF NOT EXISTS rh_dashboard_configs_pkey ON public.rh_dashboard_configs USING btree (id);
CREATE UNIQUE INDEX IF NOT EXISTS rh_dashboard_configs_user_email_dashboard_type_key ON public.rh_dashboard_configs USING btree (user_email, dashboard_type);
CREATE INDEX IF NOT EXISTS idx_rh_kb_category ON public.rh_knowledge_base USING btree (category);
CREATE UNIQUE INDEX IF NOT EXISTS rh_knowledge_base_pkey ON public.rh_knowledge_base USING btree (id);
CREATE INDEX IF NOT EXISTS idx_rh_reports_shared ON public.rh_reports USING btree (shared);
CREATE INDEX IF NOT EXISTS idx_rh_reports_tenant ON public.rh_reports USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_rh_reports_type ON public.rh_reports USING btree (report_type);
CREATE UNIQUE INDEX IF NOT EXISTS rh_reports_pkey ON public.rh_reports USING btree (id);
CREATE INDEX IF NOT EXISTS idx_rh_requests_employee ON public.rh_requests USING btree (employee_id);
CREATE INDEX IF NOT EXISTS idx_rh_requests_status ON public.rh_requests USING btree (status);
CREATE UNIQUE INDEX IF NOT EXISTS rh_requests_pkey ON public.rh_requests USING btree (id);
CREATE INDEX IF NOT EXISTS idx_routing_operations_routing ON public.routing_operations USING btree (routing_id);
CREATE INDEX IF NOT EXISTS idx_routing_operations_sequence ON public.routing_operations USING btree (sequence);
CREATE INDEX IF NOT EXISTS idx_routing_operations_tenant ON public.routing_operations USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS routing_operations_pkey ON public.routing_operations USING btree (id);
CREATE INDEX IF NOT EXISTS idx_routings_code ON public.routings USING btree (code);
CREATE INDEX IF NOT EXISTS idx_routings_product ON public.routings USING btree (product_id);
CREATE INDEX IF NOT EXISTS idx_routings_tenant ON public.routings USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS routings_pkey ON public.routings USING btree (id);
CREATE INDEX IF NOT EXISTS idx_salary_advances_employee ON public.salary_advances USING btree (employee_id);
CREATE INDEX IF NOT EXISTS idx_salary_advances_status ON public.salary_advances USING btree (status);
CREATE INDEX IF NOT EXISTS idx_salary_advances_tenant ON public.salary_advances USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS salary_advances_pkey ON public.salary_advances USING btree (id);
CREATE INDEX IF NOT EXISTS idx_sales_order_lines_order ON public.sales_order_lines USING btree (sales_order_id);
CREATE INDEX IF NOT EXISTS idx_sales_order_lines_tenant ON public.sales_order_lines USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS sales_order_lines_pkey ON public.sales_order_lines USING btree (id);
CREATE INDEX IF NOT EXISTS idx_sales_orders_customer ON public.sales_orders USING btree (customer_id);
CREATE INDEX IF NOT EXISTS idx_sales_orders_status ON public.sales_orders USING btree (status);
CREATE INDEX IF NOT EXISTS idx_sales_orders_tenant ON public.sales_orders USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS sales_orders_number_key ON public.sales_orders USING btree (number);
CREATE UNIQUE INDEX IF NOT EXISTS sales_orders_pkey ON public.sales_orders USING btree (id);
CREATE INDEX IF NOT EXISTS idx_sales_representatives_tenant ON public.sales_representatives USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_sales_reps_name ON public.sales_representatives USING btree (name);
CREATE UNIQUE INDEX IF NOT EXISTS sales_representatives_pkey ON public.sales_representatives USING btree (id);
CREATE INDEX IF NOT EXISTS idx_sf_tenant ON public.saved_filters USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_sf_user_page ON public.saved_filters USING btree (user_email, page_name);
CREATE UNIQUE INDEX IF NOT EXISTS saved_filters_pkey ON public.saved_filters USING btree (id);
CREATE INDEX IF NOT EXISTS idx_sepa_orders_payrun ON public.sepa_payment_orders USING btree (pay_run_id);
CREATE UNIQUE INDEX IF NOT EXISTS sepa_payment_orders_pkey ON public.sepa_payment_orders USING btree (id);
CREATE INDEX IF NOT EXISTS idx_sc_customer ON public.service_contracts USING btree (customer_id);
CREATE UNIQUE INDEX IF NOT EXISTS service_contracts_pkey ON public.service_contracts USING btree (id);
CREATE INDEX IF NOT EXISTS idx_tm_ticket ON public.service_ticket_messages USING btree (ticket_id);
CREATE UNIQUE INDEX IF NOT EXISTS service_ticket_messages_pkey ON public.service_ticket_messages USING btree (id);
CREATE INDEX IF NOT EXISTS idx_tk_assigned ON public.service_tickets USING btree (assigned_to);
CREATE INDEX IF NOT EXISTS idx_tk_customer ON public.service_tickets USING btree (customer_id);
CREATE INDEX IF NOT EXISTS idx_tk_status ON public.service_tickets USING btree (status);
CREATE UNIQUE INDEX IF NOT EXISTS service_tickets_pkey ON public.service_tickets USING btree (id);
CREATE INDEX IF NOT EXISTS idx_social_declarations_period ON public.social_declarations USING btree (period);
CREATE INDEX IF NOT EXISTS idx_social_declarations_status ON public.social_declarations USING btree (status);
CREATE INDEX IF NOT EXISTS idx_social_declarations_type ON public.social_declarations USING btree (declaration_type);
CREATE UNIQUE INDEX IF NOT EXISTS social_declarations_pkey ON public.social_declarations USING btree (id);
CREATE UNIQUE INDEX IF NOT EXISTS sql_migrations_tracker_filename_key ON public.sql_migrations_tracker USING btree (filename);
CREATE UNIQUE INDEX IF NOT EXISTS sql_migrations_tracker_pkey ON public.sql_migrations_tracker USING btree (id);
CREATE INDEX IF NOT EXISTS idx_st_orders_mo ON public.st_orders USING btree (manufacturing_order_id);
CREATE INDEX IF NOT EXISTS idx_st_orders_status ON public.st_orders USING btree (status);
CREATE INDEX IF NOT EXISTS idx_st_orders_supplier ON public.st_orders USING btree (supplier_id);
CREATE INDEX IF NOT EXISTS idx_st_orders_tenant ON public.st_orders USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS st_orders_number_key ON public.st_orders USING btree (number);
CREATE UNIQUE INDEX IF NOT EXISTS st_orders_pkey ON public.st_orders USING btree (id);
CREATE INDEX IF NOT EXISTS idx_st_receipt_lines_receipt ON public.st_receipt_lines USING btree (st_receipt_id);
CREATE INDEX IF NOT EXISTS idx_st_receipt_lines_tenant ON public.st_receipt_lines USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS st_receipt_lines_pkey ON public.st_receipt_lines USING btree (id);
CREATE INDEX IF NOT EXISTS idx_st_receipts_order ON public.st_receipts USING btree (st_order_id);
CREATE INDEX IF NOT EXISTS idx_st_receipts_tenant ON public.st_receipts USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS st_receipts_number_key ON public.st_receipts USING btree (number);
CREATE UNIQUE INDEX IF NOT EXISTS st_receipts_pkey ON public.st_receipts USING btree (id);
CREATE INDEX IF NOT EXISTS idx_st_shipment_lines_shipment ON public.st_shipment_lines USING btree (st_shipment_id);
CREATE INDEX IF NOT EXISTS idx_st_shipment_lines_tenant ON public.st_shipment_lines USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS st_shipment_lines_pkey ON public.st_shipment_lines USING btree (id);
CREATE INDEX IF NOT EXISTS idx_st_shipments_order ON public.st_shipments USING btree (st_order_id);
CREATE INDEX IF NOT EXISTS idx_st_shipments_tenant ON public.st_shipments USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS st_shipments_number_key ON public.st_shipments USING btree (number);
CREATE UNIQUE INDEX IF NOT EXISTS st_shipments_pkey ON public.st_shipments USING btree (id);
CREATE UNIQUE INDEX IF NOT EXISTS staff_requirements_pkey ON public.staff_requirements USING btree (id);
CREATE INDEX IF NOT EXISTS idx_standard_labels_category ON public.standard_labels USING btree (tenant_id, category);
CREATE INDEX IF NOT EXISTS idx_standard_labels_tenant ON public.standard_labels USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS standard_labels_pkey ON public.standard_labels USING btree (id);
CREATE UNIQUE INDEX IF NOT EXISTS standard_labels_tenant_label_key ON public.standard_labels USING btree (tenant_id, label);
CREATE INDEX IF NOT EXISTS idx_stat_fields_entity ON public.stat_fields USING btree (entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_stat_fields_tenant ON public.stat_fields USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS stat_fields_pkey ON public.stat_fields USING btree (id);
CREATE UNIQUE INDEX IF NOT EXISTS stat_fields_tenant_id_entity_type_entity_id_field_name_key ON public.stat_fields USING btree (tenant_id, entity_type, entity_id, field_name);
CREATE INDEX IF NOT EXISTS idx_sa_product ON public.stock_alerts USING btree (product_id);
CREATE INDEX IF NOT EXISTS idx_sa_status ON public.stock_alerts USING btree (status);
CREATE UNIQUE INDEX IF NOT EXISTS stock_alerts_pkey ON public.stock_alerts USING btree (id);
CREATE INDEX IF NOT EXISTS idx_stock_movements_date ON public.stock_movements USING btree (movement_date);
CREATE INDEX IF NOT EXISTS idx_stock_movements_product ON public.stock_movements USING btree (product_id);
CREATE INDEX IF NOT EXISTS idx_stock_movements_product_id ON public.stock_movements USING btree (product_id);
CREATE INDEX IF NOT EXISTS idx_stock_movements_tenant ON public.stock_movements USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_stock_movements_warehouse ON public.stock_movements USING btree (warehouse_id);
CREATE UNIQUE INDEX IF NOT EXISTS stock_movements_pkey ON public.stock_movements USING btree (id);
CREATE INDEX IF NOT EXISTS idx_stock_quantities_product ON public.stock_quantities USING btree (product_id);
CREATE INDEX IF NOT EXISTS idx_stock_quantities_tenant ON public.stock_quantities USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_stock_quantities_warehouse ON public.stock_quantities USING btree (warehouse_id);
CREATE UNIQUE INDEX IF NOT EXISTS stock_quantities_pkey ON public.stock_quantities USING btree (id);
CREATE UNIQUE INDEX IF NOT EXISTS stock_quantities_product_id_warehouse_id_key ON public.stock_quantities USING btree (product_id, warehouse_id);
CREATE INDEX IF NOT EXISTS idx_sc_supplier ON public.supplier_contacts USING btree (supplier_id);
CREATE UNIQUE INDEX IF NOT EXISTS supplier_contacts_pkey ON public.supplier_contacts USING btree (id);
CREATE INDEX IF NOT EXISTS idx_sds_supplier ON public.supplier_delivery_schedules USING btree (supplier_id);
CREATE UNIQUE INDEX IF NOT EXISTS supplier_delivery_schedules_pkey ON public.supplier_delivery_schedules USING btree (id);
CREATE INDEX IF NOT EXISTS idx_supplier_payments_supplier ON public.supplier_payments USING btree (supplier_id);
CREATE INDEX IF NOT EXISTS idx_supplier_payments_tenant ON public.supplier_payments USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS supplier_payments_number_key ON public.supplier_payments USING btree (number);
CREATE UNIQUE INDEX IF NOT EXISTS supplier_payments_pkey ON public.supplier_payments USING btree (id);
CREATE INDEX IF NOT EXISTS idx_spll_pl ON public.supplier_price_list_lines USING btree (price_list_id);
CREATE INDEX IF NOT EXISTS idx_spll_product ON public.supplier_price_list_lines USING btree (product_id);
CREATE UNIQUE INDEX IF NOT EXISTS supplier_price_list_lines_pkey ON public.supplier_price_list_lines USING btree (id);
CREATE INDEX IF NOT EXISTS idx_spl_supplier ON public.supplier_price_lists USING btree (supplier_id);
CREATE UNIQUE INDEX IF NOT EXISTS supplier_price_lists_pkey ON public.supplier_price_lists USING btree (id);
CREATE INDEX IF NOT EXISTS idx_suppliers_tenant ON public.suppliers USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS suppliers_pkey ON public.suppliers USING btree (id);
CREATE INDEX IF NOT EXISTS idx_task_action_attachments_action ON public.task_action_attachments USING btree (task_action_id);
CREATE INDEX IF NOT EXISTS idx_task_action_attachments_task ON public.task_action_attachments USING btree (task_id);
CREATE UNIQUE INDEX IF NOT EXISTS task_action_attachments_pkey ON public.task_action_attachments USING btree (id);
CREATE INDEX IF NOT EXISTS idx_task_actions_task ON public.task_actions USING btree (task_id);
CREATE INDEX IF NOT EXISTS idx_task_actions_tenant ON public.task_actions USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS task_actions_pkey ON public.task_actions USING btree (id);
CREATE INDEX IF NOT EXISTS idx_task_comments_task ON public.task_comments USING btree (task_id);
CREATE INDEX IF NOT EXISTS idx_task_comments_tenant ON public.task_comments USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS task_comments_pkey ON public.task_comments USING btree (id);
CREATE INDEX IF NOT EXISTS idx_task_documents_task ON public.task_documents USING btree (task_id);
CREATE INDEX IF NOT EXISTS idx_task_documents_tenant ON public.task_documents USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS task_documents_pkey ON public.task_documents USING btree (id);
CREATE INDEX IF NOT EXISTS idx_tax_cash_basis_payment ON public.tax_cash_basis_entries USING btree (payment_id);
CREATE INDEX IF NOT EXISTS idx_tax_cash_basis_tax ON public.tax_cash_basis_entries USING btree (tax_id);
CREATE UNIQUE INDEX IF NOT EXISTS tax_cash_basis_entries_pkey ON public.tax_cash_basis_entries USING btree (id);
CREATE INDEX IF NOT EXISTS idx_tax_groups_tenant ON public.tax_groups USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS tax_groups_pkey ON public.tax_groups USING btree (id);
CREATE INDEX IF NOT EXISTS idx_tax_payments_tenant ON public.tax_payments USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_tax_payments_type ON public.tax_payments USING btree (tax_type);
CREATE UNIQUE INDEX IF NOT EXISTS tax_payments_pkey ON public.tax_payments USING btree (id);
CREATE INDEX IF NOT EXISTS idx_tax_rates_effective ON public.tax_rates USING btree (pack_code, effective_from, effective_to);
CREATE INDEX IF NOT EXISTS idx_tax_rates_pack ON public.tax_rates USING btree (pack_code);
CREATE INDEX IF NOT EXISTS idx_tax_rates_tenant ON public.tax_rates USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS tax_rates_pkey ON public.tax_rates USING btree (id);
CREATE INDEX IF NOT EXISTS idx_tax_repartition_tax ON public.tax_repartition_lines USING btree (tax_id);
CREATE UNIQUE INDEX IF NOT EXISTS tax_repartition_lines_pkey ON public.tax_repartition_lines USING btree (id);
CREATE INDEX IF NOT EXISTS idx_tenant_users_auth ON public.tenant_users USING btree (auth_id);
CREATE INDEX IF NOT EXISTS idx_tenant_users_email ON public.tenant_users USING btree (email);
CREATE INDEX IF NOT EXISTS idx_tenant_users_guest_perms ON public.tenant_users USING gin (guest_permissions);
CREATE INDEX IF NOT EXISTS idx_tenant_users_module_roles ON public.tenant_users USING gin (module_roles);
CREATE INDEX IF NOT EXISTS idx_tenant_users_tenant ON public.tenant_users USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS tenant_users_email_tenant_unique ON public.tenant_users USING btree (email, tenant_id) WHERE (email IS NOT NULL);
CREATE UNIQUE INDEX IF NOT EXISTS tenant_users_pkey ON public.tenant_users USING btree (id);
CREATE UNIQUE INDEX IF NOT EXISTS tenant_users_tenant_id_email_key ON public.tenant_users USING btree (tenant_id, email);
CREATE INDEX IF NOT EXISTS tenant_users_valid_until_idx ON public.tenant_users USING btree (valid_until) WHERE (valid_until IS NOT NULL);
CREATE INDEX IF NOT EXISTS idx_tenants_enabled_modules ON public.tenants USING gin (enabled_modules);
CREATE UNIQUE INDEX IF NOT EXISTS tenants_pkey ON public.tenants USING btree (id);
CREATE INDEX IF NOT EXISTS idx_third_party_accounts_tenant ON public.third_party_accounts USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_third_party_code ON public.third_party_accounts USING btree (code);
CREATE INDEX IF NOT EXISTS idx_third_party_type ON public.third_party_accounts USING btree (type);
CREATE UNIQUE INDEX IF NOT EXISTS third_party_accounts_pkey ON public.third_party_accounts USING btree (id);
CREATE UNIQUE INDEX IF NOT EXISTS third_party_accounts_tenant_code_key ON public.third_party_accounts USING btree (tenant_id, code);
CREATE INDEX IF NOT EXISTS idx_tier_ribs_tenant ON public.tier_ribs USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_tier_ribs_tp ON public.tier_ribs USING btree (third_party_account_id);
CREATE UNIQUE INDEX IF NOT EXISTS tier_ribs_pkey ON public.tier_ribs USING btree (id);
CREATE INDEX IF NOT EXISTS idx_timesheets_employee_id ON public.timesheets USING btree (employee_id);
CREATE INDEX IF NOT EXISTS idx_timesheets_status ON public.timesheets USING btree (status);
CREATE INDEX IF NOT EXISTS idx_timesheets_tenant ON public.timesheets USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS timesheets_pkey ON public.timesheets USING btree (id);
CREATE INDEX IF NOT EXISTS idx_toolings_code ON public.toolings USING btree (code);
CREATE INDEX IF NOT EXISTS idx_toolings_machine ON public.toolings USING btree (machine_id);
CREATE INDEX IF NOT EXISTS idx_toolings_tenant ON public.toolings USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS toolings_pkey ON public.toolings USING btree (id);
CREATE INDEX IF NOT EXISTS idx_treasury_recurring_next ON public.treasury_recurring USING btree (next_date);
CREATE INDEX IF NOT EXISTS idx_treasury_recurring_tenant ON public.treasury_recurring USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS treasury_recurring_pkey ON public.treasury_recurring USING btree (id);
CREATE INDEX IF NOT EXISTS idx_treasury_transfers_number ON public.treasury_transfers USING btree (number);
CREATE INDEX IF NOT EXISTS idx_treasury_transfers_status ON public.treasury_transfers USING btree (status);
CREATE INDEX IF NOT EXISTS idx_treasury_transfers_tenant ON public.treasury_transfers USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS treasury_transfers_pkey ON public.treasury_transfers USING btree (id);
CREATE INDEX IF NOT EXISTS idx_tvs_declarations_tenant ON public.tvs_declarations USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_tvs_fiscal_year ON public.tvs_declarations USING btree (fiscal_year);
CREATE INDEX IF NOT EXISTS idx_tvs_tenant ON public.tvs_declarations USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS tvs_declarations_pkey ON public.tvs_declarations USING btree (id);
CREATE INDEX IF NOT EXISTS idx_users_tenant ON public.users USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS users_email_key ON public.users USING btree (email);
CREATE UNIQUE INDEX IF NOT EXISTS users_pkey ON public.users USING btree (id);
CREATE INDEX IF NOT EXISTS idx_value_date_tracking_tenant ON public.value_date_tracking USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_value_dates_account ON public.value_date_tracking USING btree (bank_account_id);
CREATE INDEX IF NOT EXISTS idx_value_dates_value_date ON public.value_date_tracking USING btree (value_date);
CREATE UNIQUE INDEX IF NOT EXISTS value_date_tracking_pkey ON public.value_date_tracking USING btree (id);
CREATE INDEX IF NOT EXISTS idx_vat_collections_tenant ON public.vat_on_collections USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS vat_on_collections_pkey ON public.vat_on_collections USING btree (id);
CREATE INDEX IF NOT EXISTS idx_vat_returns_edi_status ON public.vat_returns USING btree (edi_status) WHERE (edi_status <> 'not_submitted'::text);
CREATE INDEX IF NOT EXISTS idx_vat_returns_tenant ON public.vat_returns USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS vat_returns_pkey ON public.vat_returns USING btree (id);
CREATE INDEX IF NOT EXISTS idx_warehouse_locations_code ON public.warehouse_locations USING btree (code);
CREATE INDEX IF NOT EXISTS idx_warehouse_locations_tenant ON public.warehouse_locations USING btree (tenant_id);
CREATE INDEX IF NOT EXISTS idx_warehouse_locations_wh ON public.warehouse_locations USING btree (warehouse_id);
CREATE UNIQUE INDEX IF NOT EXISTS warehouse_locations_pkey ON public.warehouse_locations USING btree (id);
CREATE INDEX IF NOT EXISTS idx_wu_user ON public.warehouse_users USING btree (user_email);
CREATE INDEX IF NOT EXISTS idx_wu_warehouse ON public.warehouse_users USING btree (warehouse_id);
CREATE UNIQUE INDEX IF NOT EXISTS warehouse_users_pkey ON public.warehouse_users USING btree (id);
CREATE INDEX IF NOT EXISTS idx_warehouses_tenant ON public.warehouses USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS warehouses_code_key ON public.warehouses USING btree (code);
CREATE UNIQUE INDEX IF NOT EXISTS warehouses_pkey ON public.warehouses USING btree (id);
CREATE INDEX IF NOT EXISTS idx_work_centers_code ON public.work_centers USING btree (code);
CREATE INDEX IF NOT EXISTS idx_work_centers_tenant ON public.work_centers USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS work_centers_pkey ON public.work_centers USING btree (id);
CREATE INDEX IF NOT EXISTS idx_work_hardship_employee ON public.work_hardship USING btree (employee_id);
CREATE INDEX IF NOT EXISTS idx_work_hardship_tenant ON public.work_hardship USING btree (tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS work_hardship_pkey ON public.work_hardship USING btree (id);
CREATE INDEX IF NOT EXISTS idx_hardship_employee ON public.work_hardship_records USING btree (employee_id);
CREATE INDEX IF NOT EXISTS idx_hardship_type ON public.work_hardship_records USING btree (exposure_type);
CREATE UNIQUE INDEX IF NOT EXISTS work_hardship_records_pkey ON public.work_hardship_records USING btree (id);
CREATE INDEX IF NOT EXISTS idx_work_stoppages_dates ON public.work_stoppages USING btree (start_date, end_date);
CREATE INDEX IF NOT EXISTS idx_work_stoppages_employee ON public.work_stoppages USING btree (employee_id);
CREATE INDEX IF NOT EXISTS idx_work_stoppages_type ON public.work_stoppages USING btree (stoppage_type);
CREATE UNIQUE INDEX IF NOT EXISTS work_stoppages_pkey ON public.work_stoppages USING btree (id);
CREATE UNIQUE INDEX IF NOT EXISTS workflows_pkey ON public.workflows USING btree (id);

-- ============================================
-- RLS
-- ============================================
ALTER TABLE account_tag_mappings ENABLE ROW LEVEL SECURITY;
ALTER TABLE account_tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE accounting_control_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE analytic_distribution_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE analytic_distribution_lines FORCE ROW LEVEL SECURITY;
ALTER TABLE analytic_journal_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE analytic_journal_codes FORCE ROW LEVEL SECURITY;
ALTER TABLE analytic_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE analytic_plans FORCE ROW LEVEL SECURITY;
ALTER TABLE analytic_sections ENABLE ROW LEVEL SECURITY;
ALTER TABLE analytic_sections FORCE ROW LEVEL SECURITY;
ALTER TABLE approval_workflows ENABLE ROW LEVEL SECURITY;
ALTER TABLE approval_workflows FORCE ROW LEVEL SECURITY;
ALTER TABLE asset_batch_disposal_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE asset_batch_disposal_lines FORCE ROW LEVEL SECURITY;
ALTER TABLE asset_batch_disposals ENABLE ROW LEVEL SECURITY;
ALTER TABLE asset_batch_disposals FORCE ROW LEVEL SECURITY;
ALTER TABLE asset_depreciation_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE asset_depreciation_plans FORCE ROW LEVEL SECURITY;
ALTER TABLE asset_depreciations ENABLE ROW LEVEL SECURITY;
ALTER TABLE asset_depreciations FORCE ROW LEVEL SECURITY;
ALTER TABLE asset_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE asset_documents FORCE ROW LEVEL SECURITY;
ALTER TABLE asset_families ENABLE ROW LEVEL SECURITY;
ALTER TABLE asset_families FORCE ROW LEVEL SECURITY;
ALTER TABLE asset_free_fields ENABLE ROW LEVEL SECURITY;
ALTER TABLE asset_free_fields FORCE ROW LEVEL SECURITY;
ALTER TABLE asset_revaluations ENABLE ROW LEVEL SECURITY;
ALTER TABLE asset_revaluations FORCE ROW LEVEL SECURITY;
ALTER TABLE asset_split_components ENABLE ROW LEVEL SECURITY;
ALTER TABLE asset_split_components FORCE ROW LEVEL SECURITY;
ALTER TABLE asset_splits ENABLE ROW LEVEL SECURITY;
ALTER TABLE asset_splits FORCE ROW LEVEL SECURITY;
ALTER TABLE at_rates ENABLE ROW LEVEL SECURITY;
ALTER TABLE at_rates FORCE ROW LEVEL SECURITY;
ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_log FORCE ROW LEVEL SECURITY;
ALTER TABLE auto_label_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE bank_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE bank_accounts FORCE ROW LEVEL SECURITY;
ALTER TABLE bank_connections ENABLE ROW LEVEL SECURITY;
ALTER TABLE bank_connections FORCE ROW LEVEL SECURITY;
ALTER TABLE bank_reconciliation_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE bank_reconciliation_rules FORCE ROW LEVEL SECURITY;
ALTER TABLE bank_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE bank_rules FORCE ROW LEVEL SECURITY;
ALTER TABLE bank_statement_imports ENABLE ROW LEVEL SECURITY;
ALTER TABLE bank_statement_imports FORCE ROW LEVEL SECURITY;
ALTER TABLE bank_statement_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE bank_statement_templates FORCE ROW LEVEL SECURITY;
ALTER TABLE bank_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE bank_transactions FORCE ROW LEVEL SECURITY;
ALTER TABLE banks ENABLE ROW LEVEL SECURITY;
ALTER TABLE batch_entry_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE bdes_indicators ENABLE ROW LEVEL SECURITY;
ALTER TABLE bdes_indicators FORCE ROW LEVEL SECURITY;
ALTER TABLE bom_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE bom_lines FORCE ROW LEVEL SECURITY;
ALTER TABLE boms ENABLE ROW LEVEL SECURITY;
ALTER TABLE boms FORCE ROW LEVEL SECURITY;
ALTER TABLE budget_commitments ENABLE ROW LEVEL SECURITY;
ALTER TABLE budget_commitments FORCE ROW LEVEL SECURITY;
ALTER TABLE budgets ENABLE ROW LEVEL SECURITY;
ALTER TABLE budgets FORCE ROW LEVEL SECURITY;
ALTER TABLE career_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE career_history FORCE ROW LEVEL SECURITY;
ALTER TABLE carry_forward_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE cash_control_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE chart_account_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE chart_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE chart_accounts FORCE ROW LEVEL SECURITY;
ALTER TABLE check_books ENABLE ROW LEVEL SECURITY;
ALTER TABLE check_books FORCE ROW LEVEL SECURITY;
ALTER TABLE checks ENABLE ROW LEVEL SECURITY;
ALTER TABLE checks FORCE ROW LEVEL SECURITY;
ALTER TABLE cice_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE cice_config FORCE ROW LEVEL SECURITY;
ALTER TABLE collection_reminders ENABLE ROW LEVEL SECURITY;
ALTER TABLE collection_reminders FORCE ROW LEVEL SECURITY;
ALTER TABLE compaction_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE company_settings FORCE ROW LEVEL SECURITY;
ALTER TABLE consolidated_treasury ENABLE ROW LEVEL SECURITY;
ALTER TABLE consolidated_treasury FORCE ROW LEVEL SECURITY;
ALTER TABLE contracts ENABLE ROW LEVEL SECURITY;
ALTER TABLE contracts FORCE ROW LEVEL SECURITY;
ALTER TABLE corporate_tax_grid_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE corporate_tax_grid_lines FORCE ROW LEVEL SECURITY;
ALTER TABLE corporate_tax_grids ENABLE ROW LEVEL SECURITY;
ALTER TABLE corporate_tax_grids FORCE ROW LEVEL SECURITY;
ALTER TABLE cpf_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE cpf_accounts FORCE ROW LEVEL SECURITY;
ALTER TABLE cpf_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE cpf_transactions FORCE ROW LEVEL SECURITY;
ALTER TABLE credit_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE credit_lines FORCE ROW LEVEL SECURITY;
ALTER TABLE credit_note_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE credit_note_lines FORCE ROW LEVEL SECURITY;
ALTER TABLE credit_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE credit_notes FORCE ROW LEVEL SECURITY;
ALTER TABLE crm_activities ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm_activities FORCE ROW LEVEL SECURITY;
ALTER TABLE crm_campaign_recipients ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm_campaign_recipients FORCE ROW LEVEL SECURITY;
ALTER TABLE crm_campaigns ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm_campaigns FORCE ROW LEVEL SECURITY;
ALTER TABLE crm_forecasts ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm_forecasts FORCE ROW LEVEL SECURITY;
ALTER TABLE crm_opportunities ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm_opportunities FORCE ROW LEVEL SECURITY;
ALTER TABLE crm_territories ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm_territories FORCE ROW LEVEL SECURITY;
ALTER TABLE currencies ENABLE ROW LEVEL SECURITY;
ALTER TABLE currency_revaluations ENABLE ROW LEVEL SECURITY;
ALTER TABLE currency_revaluations FORCE ROW LEVEL SECURITY;
ALTER TABLE custom_report_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE customer_contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE customer_contacts FORCE ROW LEVEL SECURITY;
ALTER TABLE customer_payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE customer_payments FORCE ROW LEVEL SECURITY;
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE customers FORCE ROW LEVEL SECURITY;
ALTER TABLE dashboard_widgets ENABLE ROW LEVEL SECURITY;
ALTER TABLE deferred_printing_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE delivery_note_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE delivery_note_lines FORCE ROW LEVEL SECURITY;
ALTER TABLE delivery_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE delivery_notes FORCE ROW LEVEL SECURITY;
ALTER TABLE delivery_schedules ENABLE ROW LEVEL SECURITY;
ALTER TABLE delivery_schedules FORCE ROW LEVEL SECURITY;
ALTER TABLE disputes ENABLE ROW LEVEL SECURITY;
ALTER TABLE distribution_grill_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE distribution_grill_lines FORCE ROW LEVEL SECURITY;
ALTER TABLE distribution_grills ENABLE ROW LEVEL SECURITY;
ALTER TABLE distribution_grills FORCE ROW LEVEL SECURITY;
ALTER TABLE document_charges ENABLE ROW LEVEL SECURITY;
ALTER TABLE document_charges FORCE ROW LEVEL SECURITY;
ALTER TABLE document_distribution_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE document_distribution_logs FORCE ROW LEVEL SECURITY;
ALTER TABLE document_shares ENABLE ROW LEVEL SECURITY;
ALTER TABLE document_shares FORCE ROW LEVEL SECURITY;
ALTER TABLE document_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE document_templates FORCE ROW LEVEL SECURITY;
ALTER TABLE document_transformations ENABLE ROW LEVEL SECURITY;
ALTER TABLE document_transformations FORCE ROW LEVEL SECURITY;
ALTER TABLE dpae_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE dpae_records FORCE ROW LEVEL SECURITY;
ALTER TABLE dsn_declarations ENABLE ROW LEVEL SECURITY;
ALTER TABLE dsn_declarations FORCE ROW LEVEL SECURITY;
ALTER TABLE electronic_signatures ENABLE ROW LEVEL SECURITY;
ALTER TABLE electronic_signatures FORCE ROW LEVEL SECURITY;
ALTER TABLE employee_activity_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE employee_activity_logs FORCE ROW LEVEL SECURITY;
ALTER TABLE employee_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE employee_documents FORCE ROW LEVEL SECURITY;
ALTER TABLE employee_exit_processes ENABLE ROW LEVEL SECURITY;
ALTER TABLE employee_exit_processes FORCE ROW LEVEL SECURITY;
ALTER TABLE employee_objectives ENABLE ROW LEVEL SECURITY;
ALTER TABLE employee_objectives FORCE ROW LEVEL SECURITY;
ALTER TABLE employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE employees FORCE ROW LEVEL SECURITY;
ALTER TABLE entry_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE entry_templates FORCE ROW LEVEL SECURITY;
ALTER TABLE etat_rapprochement ENABLE ROW LEVEL SECURITY;
ALTER TABLE exchange_gain_loss_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE exchange_gain_loss_entries FORCE ROW LEVEL SECURITY;
ALTER TABLE exchange_rates ENABLE ROW LEVEL SECURITY;
ALTER TABLE exchange_rates FORCE ROW LEVEL SECURITY;
ALTER TABLE expense_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE expense_categories FORCE ROW LEVEL SECURITY;
ALTER TABLE expense_report_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE expense_report_lines FORCE ROW LEVEL SECURITY;
ALTER TABLE expense_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE expense_reports FORCE ROW LEVEL SECURITY;
ALTER TABLE extourne_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE fec_attestations ENABLE ROW LEVEL SECURITY;
ALTER TABLE fiscal_backups ENABLE ROW LEVEL SECURITY;
ALTER TABLE fiscal_backups FORCE ROW LEVEL SECURITY;
ALTER TABLE fiscal_periods ENABLE ROW LEVEL SECURITY;
ALTER TABLE fiscal_periods FORCE ROW LEVEL SECURITY;
ALTER TABLE fiscal_position_mappings ENABLE ROW LEVEL SECURITY;
ALTER TABLE fiscal_positions ENABLE ROW LEVEL SECURITY;
ALTER TABLE fiscal_years ENABLE ROW LEVEL SECURITY;
ALTER TABLE fiscal_years FORCE ROW LEVEL SECURITY;
ALTER TABLE fixed_assets ENABLE ROW LEVEL SECURITY;
ALTER TABLE fixed_assets FORCE ROW LEVEL SECURITY;
ALTER TABLE fusion_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE future_accounting_movements ENABLE ROW LEVEL SECURITY;
ALTER TABLE future_accounting_movements FORCE ROW LEVEL SECURITY;
ALTER TABLE goods_receipt_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE goods_receipt_lines FORCE ROW LEVEL SECURITY;
ALTER TABLE goods_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE goods_receipts FORCE ROW LEVEL SECURITY;
ALTER TABLE grid_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE grid_templates FORCE ROW LEVEL SECURITY;
ALTER TABLE honorarium_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE honorarium_records FORCE ROW LEVEL SECURITY;
ALTER TABLE ifrs_adjustments ENABLE ROW LEVEL SECURITY;
ALTER TABLE ijss_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE ijss_history FORCE ROW LEVEL SECURITY;
ALTER TABLE interview_campaigns ENABLE ROW LEVEL SECURITY;
ALTER TABLE interview_campaigns FORCE ROW LEVEL SECURITY;
ALTER TABLE interviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE interviews FORCE ROW LEVEL SECURITY;
ALTER TABLE investments ENABLE ROW LEVEL SECURITY;
ALTER TABLE investments FORCE ROW LEVEL SECURITY;
ALTER TABLE invoice_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE invoice_lines FORCE ROW LEVEL SECURITY;
ALTER TABLE invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE invoices FORCE ROW LEVEL SECURITY;
ALTER TABLE journal_access_rights ENABLE ROW LEVEL SECURITY;
ALTER TABLE journal_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE journal_entries FORCE ROW LEVEL SECURITY;
ALTER TABLE journal_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE journal_lines FORCE ROW LEVEL SECURITY;
ALTER TABLE journals ENABLE ROW LEVEL SECURITY;
ALTER TABLE journals FORCE ROW LEVEL SECURITY;
ALTER TABLE justificatif_solde ENABLE ROW LEVEL SECURITY;
ALTER TABLE knowledge_base_articles ENABLE ROW LEVEL SECURITY;
ALTER TABLE knowledge_base_articles FORCE ROW LEVEL SECURITY;
ALTER TABLE leave_balances ENABLE ROW LEVEL SECURITY;
ALTER TABLE leave_balances FORCE ROW LEVEL SECURITY;
ALTER TABLE leave_provisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE leave_provisions FORCE ROW LEVEL SECURITY;
ALTER TABLE leave_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE leave_requests FORCE ROW LEVEL SECURITY;
ALTER TABLE leave_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE leave_rules FORCE ROW LEVEL SECURITY;
ALTER TABLE legal_declarations ENABLE ROW LEVEL SECURITY;
ALTER TABLE legal_declarations FORCE ROW LEVEL SECURITY;
ALTER TABLE legal_watch ENABLE ROW LEVEL SECURITY;
ALTER TABLE legal_watch FORCE ROW LEVEL SECURITY;
ALTER TABLE legislation_packs ENABLE ROW LEVEL SECURITY;
ALTER TABLE legislation_packs FORCE ROW LEVEL SECURITY;
ALTER TABLE lettrage_differences ENABLE ROW LEVEL SECURITY;
ALTER TABLE machines ENABLE ROW LEVEL SECURITY;
ALTER TABLE machines FORCE ROW LEVEL SECURITY;
ALTER TABLE manufacturing_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE manufacturing_orders FORCE ROW LEVEL SECURITY;
ALTER TABLE marking_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE meal_voucher_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE meal_voucher_config FORCE ROW LEVEL SECURITY;
ALTER TABLE medical_exams ENABLE ROW LEVEL SECURITY;
ALTER TABLE medical_exams FORCE ROW LEVEL SECURITY;
ALTER TABLE mirror_servers ENABLE ROW LEVEL SECURITY;
ALTER TABLE mirror_servers FORCE ROW LEVEL SECURITY;
ALTER TABLE mirror_verification_details ENABLE ROW LEVEL SECURITY;
ALTER TABLE mirror_verification_details FORCE ROW LEVEL SECURITY;
ALTER TABLE module_document_access_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE module_document_shares ENABLE ROW LEVEL SECURITY;
ALTER TABLE module_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE mrp_pending_docs ENABLE ROW LEVEL SECURITY;
ALTER TABLE mrp_pending_docs FORCE ROW LEVEL SECURITY;
ALTER TABLE mrp_proposals ENABLE ROW LEVEL SECURITY;
ALTER TABLE mrp_proposals FORCE ROW LEVEL SECURITY;
ALTER TABLE mrp_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE mrp_runs FORCE ROW LEVEL SECURITY;
ALTER TABLE notification_email_queue ENABLE ROW LEVEL SECURITY;
ALTER TABLE notification_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE of_consumptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE of_consumptions FORCE ROW LEVEL SECURITY;
ALTER TABLE of_document_access ENABLE ROW LEVEL SECURITY;
ALTER TABLE of_document_access FORCE ROW LEVEL SECURITY;
ALTER TABLE of_labels ENABLE ROW LEVEL SECURITY;
ALTER TABLE of_labels FORCE ROW LEVEL SECURITY;
ALTER TABLE of_lots ENABLE ROW LEVEL SECURITY;
ALTER TABLE of_lots FORCE ROW LEVEL SECURITY;
ALTER TABLE online_payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE online_payments FORCE ROW LEVEL SECURITY;
ALTER TABLE partner_bank_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE partner_bank_accounts FORCE ROW LEVEL SECURITY;
ALTER TABLE partner_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE partner_categories FORCE ROW LEVEL SECURITY;
ALTER TABLE partner_category_mappings ENABLE ROW LEVEL SECURITY;
ALTER TABLE partner_category_mappings FORCE ROW LEVEL SECURITY;
ALTER TABLE partner_contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE partner_contacts FORCE ROW LEVEL SECURITY;
ALTER TABLE pas_rates ENABLE ROW LEVEL SECURITY;
ALTER TABLE pas_rates FORCE ROW LEVEL SECURITY;
ALTER TABLE pay_recalls ENABLE ROW LEVEL SECURITY;
ALTER TABLE pay_recalls FORCE ROW LEVEL SECURITY;
ALTER TABLE pay_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE pay_runs FORCE ROW LEVEL SECURITY;
ALTER TABLE pay_slip_clarified ENABLE ROW LEVEL SECURITY;
ALTER TABLE pay_slip_clarified FORCE ROW LEVEL SECURITY;
ALTER TABLE pay_slips ENABLE ROW LEVEL SECURITY;
ALTER TABLE pay_slips FORCE ROW LEVEL SECURITY;
ALTER TABLE payment_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment_orders FORCE ROW LEVEL SECURITY;
ALTER TABLE payment_promises ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment_templates_compta ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment_templates_compta FORCE ROW LEVEL SECURITY;
ALTER TABLE payment_terms ENABLE ROW LEVEL SECURITY;
ALTER TABLE payroll_accounting_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE payroll_accounting_entries FORCE ROW LEVEL SECURITY;
ALTER TABLE payroll_archives ENABLE ROW LEVEL SECURITY;
ALTER TABLE payroll_archives FORCE ROW LEVEL SECURITY;
ALTER TABLE payroll_component_rates ENABLE ROW LEVEL SECURITY;
ALTER TABLE payroll_component_rates FORCE ROW LEVEL SECURITY;
ALTER TABLE payroll_components ENABLE ROW LEVEL SECURITY;
ALTER TABLE payroll_components FORCE ROW LEVEL SECURITY;
ALTER TABLE payroll_tax_grid_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE payroll_tax_grid_lines FORCE ROW LEVEL SECURITY;
ALTER TABLE payroll_tax_grids ENABLE ROW LEVEL SECURITY;
ALTER TABLE payroll_tax_grids FORCE ROW LEVEL SECURITY;
ALTER TABLE payroll_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE payroll_templates FORCE ROW LEVEL SECURITY;
ALTER TABLE payroll_variable_elements ENABLE ROW LEVEL SECURITY;
ALTER TABLE payroll_variable_elements FORCE ROW LEVEL SECURITY;
ALTER TABLE pick_list_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE pick_list_lines FORCE ROW LEVEL SECURITY;
ALTER TABLE pick_lists ENABLE ROW LEVEL SECURITY;
ALTER TABLE pick_lists FORCE ROW LEVEL SECURITY;
ALTER TABLE planning_slots ENABLE ROW LEVEL SECURITY;
ALTER TABLE planning_slots FORCE ROW LEVEL SECURITY;
ALTER TABLE pos_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE pos_sessions FORCE ROW LEVEL SECURITY;
ALTER TABLE pos_terminals ENABLE ROW LEVEL SECURITY;
ALTER TABLE pos_terminals FORCE ROW LEVEL SECURITY;
ALTER TABLE pos_ticket_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE pos_ticket_lines FORCE ROW LEVEL SECURITY;
ALTER TABLE pos_tickets ENABLE ROW LEVEL SECURITY;
ALTER TABLE pos_tickets FORCE ROW LEVEL SECURITY;
ALTER TABLE price_list_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE price_list_lines FORCE ROW LEVEL SECURITY;
ALTER TABLE price_lists ENABLE ROW LEVEL SECURITY;
ALTER TABLE price_lists FORCE ROW LEVEL SECURITY;
ALTER TABLE product_attributes ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_attributes FORCE ROW LEVEL SECURITY;
ALTER TABLE product_batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_batches FORCE ROW LEVEL SECURITY;
ALTER TABLE product_equivalences ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_equivalences FORCE ROW LEVEL SECURITY;
ALTER TABLE product_grid_combinations ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_grid_combinations FORCE ROW LEVEL SECURITY;
ALTER TABLE product_grids ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_grids FORCE ROW LEVEL SECURITY;
ALTER TABLE product_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_links FORCE ROW LEVEL SECURITY;
ALTER TABLE product_packagings ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_packagings FORCE ROW LEVEL SECURITY;
ALTER TABLE product_serial_numbers ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_serial_numbers FORCE ROW LEVEL SECURITY;
ALTER TABLE product_substitutes ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_substitutes FORCE ROW LEVEL SECURITY;
ALTER TABLE product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_variants FORCE ROW LEVEL SECURITY;
ALTER TABLE production_forecasts ENABLE ROW LEVEL SECURITY;
ALTER TABLE production_forecasts FORCE ROW LEVEL SECURITY;
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE products FORCE ROW LEVEL SECURITY;
ALTER TABLE project_activity_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE project_docs ENABLE ROW LEVEL SECURITY;
ALTER TABLE project_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE project_milestones ENABLE ROW LEVEL SECURITY;
ALTER TABLE project_notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE project_stages ENABLE ROW LEVEL SECURITY;
ALTER TABLE project_tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE project_task_assignees ENABLE ROW LEVEL SECURITY;
ALTER TABLE project_task_dependencies ENABLE ROW LEVEL SECURITY;
ALTER TABLE project_task_tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE project_task_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE project_task_watchers ENABLE ROW LEVEL SECURITY;
ALTER TABLE project_tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE project_time_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE projects FORCE ROW LEVEL SECURITY;
ALTER TABLE promotions ENABLE ROW LEVEL SECURITY;
ALTER TABLE promotions FORCE ROW LEVEL SECURITY;
ALTER TABLE prospects ENABLE ROW LEVEL SECURITY;
ALTER TABLE prospects FORCE ROW LEVEL SECURITY;
ALTER TABLE public_holidays ENABLE ROW LEVEL SECURITY;
ALTER TABLE public_holidays FORCE ROW LEVEL SECURITY;
ALTER TABLE purchase_credit_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE purchase_credit_lines FORCE ROW LEVEL SECURITY;
ALTER TABLE purchase_credit_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE purchase_credit_notes FORCE ROW LEVEL SECURITY;
ALTER TABLE purchase_invoice_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE purchase_invoice_lines FORCE ROW LEVEL SECURITY;
ALTER TABLE purchase_invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE purchase_invoices FORCE ROW LEVEL SECURITY;
ALTER TABLE purchase_order_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE purchase_order_lines FORCE ROW LEVEL SECURITY;
ALTER TABLE purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE purchase_orders FORCE ROW LEVEL SECURITY;
ALTER TABLE purchase_request_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE purchase_request_lines FORCE ROW LEVEL SECURITY;
ALTER TABLE purchase_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE purchase_requests FORCE ROW LEVEL SECURITY;
ALTER TABLE quality_checks ENABLE ROW LEVEL SECURITY;
ALTER TABLE quality_checks FORCE ROW LEVEL SECURITY;
ALTER TABLE quote_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE quote_lines FORCE ROW LEVEL SECURITY;
ALTER TABLE quotes ENABLE ROW LEVEL SECURITY;
ALTER TABLE quotes FORCE ROW LEVEL SECURITY;
ALTER TABLE recurring_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE recurring_invoice_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE recurring_invoice_templates FORCE ROW LEVEL SECURITY;
ALTER TABLE regularization_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE regularization_entries FORCE ROW LEVEL SECURITY;
ALTER TABLE reimputation_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE reimputation_logs FORCE ROW LEVEL SECURITY;
ALTER TABLE reminder_levels ENABLE ROW LEVEL SECURITY;
ALTER TABLE reporting_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE revision_cycles ENABLE ROW LEVEL SECURITY;
ALTER TABLE rgpd_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE rh_dashboard_configs ENABLE ROW LEVEL SECURITY;
ALTER TABLE rh_dashboard_configs FORCE ROW LEVEL SECURITY;
ALTER TABLE rh_knowledge_base ENABLE ROW LEVEL SECURITY;
ALTER TABLE rh_knowledge_base FORCE ROW LEVEL SECURITY;
ALTER TABLE rh_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE rh_reports FORCE ROW LEVEL SECURITY;
ALTER TABLE rh_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE rh_requests FORCE ROW LEVEL SECURITY;
ALTER TABLE routing_operations ENABLE ROW LEVEL SECURITY;
ALTER TABLE routing_operations FORCE ROW LEVEL SECURITY;
ALTER TABLE routings ENABLE ROW LEVEL SECURITY;
ALTER TABLE routings FORCE ROW LEVEL SECURITY;
ALTER TABLE salary_advances ENABLE ROW LEVEL SECURITY;
ALTER TABLE salary_advances FORCE ROW LEVEL SECURITY;
ALTER TABLE sales_order_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE sales_order_lines FORCE ROW LEVEL SECURITY;
ALTER TABLE sales_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE sales_orders FORCE ROW LEVEL SECURITY;
ALTER TABLE sales_representatives ENABLE ROW LEVEL SECURITY;
ALTER TABLE sales_representatives FORCE ROW LEVEL SECURITY;
ALTER TABLE saved_filters ENABLE ROW LEVEL SECURITY;
ALTER TABLE saved_filters FORCE ROW LEVEL SECURITY;
ALTER TABLE sepa_payment_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE sepa_payment_orders FORCE ROW LEVEL SECURITY;
ALTER TABLE service_contracts ENABLE ROW LEVEL SECURITY;
ALTER TABLE service_contracts FORCE ROW LEVEL SECURITY;
ALTER TABLE service_ticket_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE service_ticket_messages FORCE ROW LEVEL SECURITY;
ALTER TABLE service_tickets ENABLE ROW LEVEL SECURITY;
ALTER TABLE service_tickets FORCE ROW LEVEL SECURITY;
ALTER TABLE social_declarations ENABLE ROW LEVEL SECURITY;
ALTER TABLE social_declarations FORCE ROW LEVEL SECURITY;
ALTER TABLE st_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE st_orders FORCE ROW LEVEL SECURITY;
ALTER TABLE st_receipt_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE st_receipt_lines FORCE ROW LEVEL SECURITY;
ALTER TABLE st_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE st_receipts FORCE ROW LEVEL SECURITY;
ALTER TABLE st_shipment_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE st_shipment_lines FORCE ROW LEVEL SECURITY;
ALTER TABLE st_shipments ENABLE ROW LEVEL SECURITY;
ALTER TABLE st_shipments FORCE ROW LEVEL SECURITY;
ALTER TABLE staff_requirements ENABLE ROW LEVEL SECURITY;
ALTER TABLE staff_requirements FORCE ROW LEVEL SECURITY;
ALTER TABLE standard_labels ENABLE ROW LEVEL SECURITY;
ALTER TABLE standard_labels FORCE ROW LEVEL SECURITY;
ALTER TABLE stat_fields ENABLE ROW LEVEL SECURITY;
ALTER TABLE stock_alerts ENABLE ROW LEVEL SECURITY;
ALTER TABLE stock_alerts FORCE ROW LEVEL SECURITY;
ALTER TABLE stock_movements ENABLE ROW LEVEL SECURITY;
ALTER TABLE stock_movements FORCE ROW LEVEL SECURITY;
ALTER TABLE stock_quantities ENABLE ROW LEVEL SECURITY;
ALTER TABLE stock_quantities FORCE ROW LEVEL SECURITY;
ALTER TABLE supplier_contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE supplier_contacts FORCE ROW LEVEL SECURITY;
ALTER TABLE supplier_delivery_schedules ENABLE ROW LEVEL SECURITY;
ALTER TABLE supplier_delivery_schedules FORCE ROW LEVEL SECURITY;
ALTER TABLE supplier_payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE supplier_payments FORCE ROW LEVEL SECURITY;
ALTER TABLE supplier_price_list_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE supplier_price_list_lines FORCE ROW LEVEL SECURITY;
ALTER TABLE supplier_price_lists ENABLE ROW LEVEL SECURITY;
ALTER TABLE supplier_price_lists FORCE ROW LEVEL SECURITY;
ALTER TABLE suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE suppliers FORCE ROW LEVEL SECURITY;
ALTER TABLE task_action_attachments ENABLE ROW LEVEL SECURITY;
ALTER TABLE task_actions ENABLE ROW LEVEL SECURITY;
ALTER TABLE task_comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE task_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE tax_cash_basis_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE tax_cash_basis_entries FORCE ROW LEVEL SECURITY;
ALTER TABLE tax_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE tax_groups FORCE ROW LEVEL SECURITY;
ALTER TABLE tax_payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE tax_rates ENABLE ROW LEVEL SECURITY;
ALTER TABLE tax_rates FORCE ROW LEVEL SECURITY;
ALTER TABLE tax_repartition_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE tax_repartition_lines FORCE ROW LEVEL SECURITY;
ALTER TABLE tenant_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_users FORCE ROW LEVEL SECURITY;
ALTER TABLE tenants ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenants FORCE ROW LEVEL SECURITY;
ALTER TABLE third_party_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE third_party_accounts FORCE ROW LEVEL SECURITY;
ALTER TABLE tier_ribs ENABLE ROW LEVEL SECURITY;
ALTER TABLE timesheets ENABLE ROW LEVEL SECURITY;
ALTER TABLE timesheets FORCE ROW LEVEL SECURITY;
ALTER TABLE toolings ENABLE ROW LEVEL SECURITY;
ALTER TABLE toolings FORCE ROW LEVEL SECURITY;
ALTER TABLE treasury_recurring ENABLE ROW LEVEL SECURITY;
ALTER TABLE treasury_recurring FORCE ROW LEVEL SECURITY;
ALTER TABLE treasury_transfers ENABLE ROW LEVEL SECURITY;
ALTER TABLE treasury_transfers FORCE ROW LEVEL SECURITY;
ALTER TABLE tvs_declarations ENABLE ROW LEVEL SECURITY;
ALTER TABLE tvs_declarations FORCE ROW LEVEL SECURITY;
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE users FORCE ROW LEVEL SECURITY;
ALTER TABLE v_tenant_id ENABLE ROW LEVEL SECURITY;
ALTER TABLE value_date_tracking ENABLE ROW LEVEL SECURITY;
ALTER TABLE value_date_tracking FORCE ROW LEVEL SECURITY;
ALTER TABLE vat_on_collections ENABLE ROW LEVEL SECURITY;
ALTER TABLE vat_returns ENABLE ROW LEVEL SECURITY;
ALTER TABLE vat_returns FORCE ROW LEVEL SECURITY;
ALTER TABLE warehouse_locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE warehouse_locations FORCE ROW LEVEL SECURITY;
ALTER TABLE warehouse_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE warehouse_users FORCE ROW LEVEL SECURITY;
ALTER TABLE warehouses ENABLE ROW LEVEL SECURITY;
ALTER TABLE warehouses FORCE ROW LEVEL SECURITY;
ALTER TABLE work_centers ENABLE ROW LEVEL SECURITY;
ALTER TABLE work_centers FORCE ROW LEVEL SECURITY;
ALTER TABLE work_hardship ENABLE ROW LEVEL SECURITY;
ALTER TABLE work_hardship FORCE ROW LEVEL SECURITY;
ALTER TABLE work_hardship_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE work_hardship_records FORCE ROW LEVEL SECURITY;
ALTER TABLE work_stoppages ENABLE ROW LEVEL SECURITY;
ALTER TABLE work_stoppages FORCE ROW LEVEL SECURITY;
ALTER TABLE workflows ENABLE ROW LEVEL SECURITY;
ALTER TABLE workflows FORCE ROW LEVEL SECURITY;

-- ============================================
-- RLS POLICIES
-- ============================================
DROP POLICY IF EXISTS "tenant_delete_notifications" ON project_notifications;
CREATE POLICY "tenant_delete_notifications" ON project_notifications FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_notifications" ON project_notifications;
CREATE POLICY "tenant_insert_notifications" ON project_notifications FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_notifications" ON project_notifications;
CREATE POLICY "tenant_select_notifications" ON project_notifications FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_notifications" ON project_notifications;
CREATE POLICY "tenant_update_notifications" ON project_notifications FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_auto_label_rules" ON auto_label_rules;
CREATE POLICY "tenant_delete_auto_label_rules" ON auto_label_rules FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_auto_label_rules" ON auto_label_rules;
CREATE POLICY "tenant_insert_auto_label_rules" ON auto_label_rules FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_auto_label_rules" ON auto_label_rules;
CREATE POLICY "tenant_select_auto_label_rules" ON auto_label_rules FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_auto_label_rules" ON auto_label_rules;
CREATE POLICY "tenant_update_auto_label_rules" ON auto_label_rules FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "module_documents_delete" ON module_documents;
CREATE POLICY "module_documents_delete" ON module_documents FOR DELETE USING (((tenant_id = current_tenant_id()) AND ((current_user_role() = 'admin'::text) OR (has_module_access(module) AND (current_module_role(module) = ANY (ARRAY['project_director'::text, 'hr_director'::text, 'sales_director'::text, 'accountant'::text, 'treasurer'::text, 'warehouse_manager'::text, 'production_manager'::text]))))));
DROP POLICY IF EXISTS "module_documents_insert" ON module_documents;
CREATE POLICY "module_documents_insert" ON module_documents FOR INSERT WITH CHECK (((tenant_id = current_tenant_id()) AND (uploaded_by = current_tenant_user_id()) AND ((current_user_role() = 'admin'::text) OR (has_module_access(module) AND (current_module_role(module) <> 'guest'::text)))));
DROP POLICY IF EXISTS "module_documents_select" ON module_documents;
CREATE POLICY "module_documents_select" ON module_documents FOR SELECT USING (((tenant_id = current_tenant_id()) AND ((current_user_role() = 'admin'::text) OR has_module_access(module))));
DROP POLICY IF EXISTS "module_documents_update" ON module_documents;
CREATE POLICY "module_documents_update" ON module_documents FOR UPDATE USING (((tenant_id = current_tenant_id()) AND ((current_user_role() = 'admin'::text) OR (has_module_access(module) AND (current_module_role(module) = ANY (ARRAY['project_director'::text, 'project_manager'::text, 'hr_director'::text, 'hr_manager'::text, 'sales_director'::text, 'sales_rep'::text, 'accountant'::text, 'treasurer'::text, 'warehouse_manager'::text, 'production_manager'::text]))))));
DROP POLICY IF EXISTS "tenant_delete" ON asset_depreciations;
CREATE POLICY "tenant_delete" ON asset_depreciations FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_asset_depreciations" ON asset_depreciations;
CREATE POLICY "tenant_delete_asset_depreciations" ON asset_depreciations FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON asset_depreciations;
CREATE POLICY "tenant_insert" ON asset_depreciations FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_asset_depreciations" ON asset_depreciations;
CREATE POLICY "tenant_insert_asset_depreciations" ON asset_depreciations FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON asset_depreciations;
CREATE POLICY "tenant_select" ON asset_depreciations FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_asset_depreciations" ON asset_depreciations;
CREATE POLICY "tenant_select_asset_depreciations" ON asset_depreciations FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON asset_depreciations;
CREATE POLICY "tenant_update" ON asset_depreciations FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_asset_depreciations" ON asset_depreciations;
CREATE POLICY "tenant_update_asset_depreciations" ON asset_depreciations FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_carry_forward_log" ON carry_forward_log;
CREATE POLICY "tenant_insert_carry_forward_log" ON carry_forward_log FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_carry_forward_log" ON carry_forward_log;
CREATE POLICY "tenant_select_carry_forward_log" ON carry_forward_log FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_lettrage_diff" ON lettrage_differences;
CREATE POLICY "tenant_delete_lettrage_diff" ON lettrage_differences FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_lettrage_diff" ON lettrage_differences;
CREATE POLICY "tenant_insert_lettrage_diff" ON lettrage_differences FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_lettrage_diff" ON lettrage_differences;
CREATE POLICY "tenant_select_lettrage_diff" ON lettrage_differences FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_lettrage_diff" ON lettrage_differences;
CREATE POLICY "tenant_update_lettrage_diff" ON lettrage_differences FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "doc_access_log_insert" ON module_document_access_log;
CREATE POLICY "doc_access_log_insert" ON module_document_access_log FOR INSERT WITH CHECK (((tenant_id = current_tenant_id()) AND (user_id = current_tenant_user_id())));
DROP POLICY IF EXISTS "doc_access_log_select" ON module_document_access_log;
CREATE POLICY "doc_access_log_select" ON module_document_access_log FOR SELECT USING (((tenant_id = current_tenant_id()) AND ((current_user_role() = 'admin'::text) OR (user_id = current_tenant_user_id()))));
DROP POLICY IF EXISTS "tenant_insert_acct_control" ON accounting_control_runs;
CREATE POLICY "tenant_insert_acct_control" ON accounting_control_runs FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_acct_control" ON accounting_control_runs;
CREATE POLICY "tenant_select_acct_control" ON accounting_control_runs FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_cash_control" ON cash_control_sessions;
CREATE POLICY "tenant_delete_cash_control" ON cash_control_sessions FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_cash_control" ON cash_control_sessions;
CREATE POLICY "tenant_insert_cash_control" ON cash_control_sessions FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_cash_control" ON cash_control_sessions;
CREATE POLICY "tenant_select_cash_control" ON cash_control_sessions FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_cash_control" ON cash_control_sessions;
CREATE POLICY "tenant_update_cash_control" ON cash_control_sessions FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_fec_attest" ON fec_attestations;
CREATE POLICY "tenant_delete_fec_attest" ON fec_attestations FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_fec_attest" ON fec_attestations;
CREATE POLICY "tenant_insert_fec_attest" ON fec_attestations FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_fec_attest" ON fec_attestations;
CREATE POLICY "tenant_select_fec_attest" ON fec_attestations FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_custom_reports" ON custom_report_templates;
CREATE POLICY "tenant_delete_custom_reports" ON custom_report_templates FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_custom_reports" ON custom_report_templates;
CREATE POLICY "tenant_insert_custom_reports" ON custom_report_templates FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_custom_reports" ON custom_report_templates;
CREATE POLICY "tenant_select_custom_reports" ON custom_report_templates FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_custom_reports" ON custom_report_templates;
CREATE POLICY "tenant_update_custom_reports" ON custom_report_templates FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON company_settings;
CREATE POLICY "tenant_delete" ON company_settings FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_company_settings" ON company_settings;
CREATE POLICY "tenant_delete_company_settings" ON company_settings FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON company_settings;
CREATE POLICY "tenant_insert" ON company_settings FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_company_settings" ON company_settings;
CREATE POLICY "tenant_insert_company_settings" ON company_settings FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON company_settings;
CREATE POLICY "tenant_select" ON company_settings FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_company_settings" ON company_settings;
CREATE POLICY "tenant_select_company_settings" ON company_settings FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON company_settings;
CREATE POLICY "tenant_update" ON company_settings FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_company_settings" ON company_settings;
CREATE POLICY "tenant_update_company_settings" ON company_settings FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON customers;
CREATE POLICY "tenant_delete" ON customers FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_customers" ON customers;
CREATE POLICY "tenant_delete_customers" ON customers FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON customers;
CREATE POLICY "tenant_insert" ON customers FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_customers" ON customers;
CREATE POLICY "tenant_insert_customers" ON customers FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON customers;
CREATE POLICY "tenant_select" ON customers FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_customers" ON customers;
CREATE POLICY "tenant_select_customers" ON customers FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON customers;
CREATE POLICY "tenant_update" ON customers FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_customers" ON customers;
CREATE POLICY "tenant_update_customers" ON customers FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON credit_notes;
CREATE POLICY "tenant_delete" ON credit_notes FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_credit_notes" ON credit_notes;
CREATE POLICY "tenant_delete_credit_notes" ON credit_notes FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON credit_notes;
CREATE POLICY "tenant_insert" ON credit_notes FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_credit_notes" ON credit_notes;
CREATE POLICY "tenant_insert_credit_notes" ON credit_notes FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON credit_notes;
CREATE POLICY "tenant_select" ON credit_notes FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_credit_notes" ON credit_notes;
CREATE POLICY "tenant_select_credit_notes" ON credit_notes FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON credit_notes;
CREATE POLICY "tenant_update" ON credit_notes FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_credit_notes" ON credit_notes;
CREATE POLICY "tenant_update_credit_notes" ON credit_notes FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_deferred_print" ON deferred_printing_jobs;
CREATE POLICY "tenant_delete_deferred_print" ON deferred_printing_jobs FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_deferred_print" ON deferred_printing_jobs;
CREATE POLICY "tenant_insert_deferred_print" ON deferred_printing_jobs FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_deferred_print" ON deferred_printing_jobs;
CREATE POLICY "tenant_select_deferred_print" ON deferred_printing_jobs FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_deferred_print" ON deferred_printing_jobs;
CREATE POLICY "tenant_update_deferred_print" ON deferred_printing_jobs FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "project_members_delete" ON project_members;
CREATE POLICY "project_members_delete" ON project_members FOR DELETE USING ((tenant_id IN ( SELECT tu.tenant_id
   FROM tenant_users tu
  WHERE ((tu.auth_id = auth.uid()) AND (tu.status = 'active'::text) AND (tu.role = ANY (ARRAY['admin'::text, 'accountant'::text, 'manager'::text]))))));
DROP POLICY IF EXISTS "project_members_insert" ON project_members;
CREATE POLICY "project_members_insert" ON project_members FOR INSERT WITH CHECK ((tenant_id IN ( SELECT tu.tenant_id
   FROM tenant_users tu
  WHERE ((tu.auth_id = auth.uid()) AND (tu.status = 'active'::text) AND (tu.role = ANY (ARRAY['admin'::text, 'accountant'::text, 'manager'::text]))))));
DROP POLICY IF EXISTS "project_members_select" ON project_members;
CREATE POLICY "project_members_select" ON project_members FOR SELECT USING ((tenant_id IN ( SELECT tu.tenant_id
   FROM tenant_users tu
  WHERE ((tu.auth_id = auth.uid()) AND (tu.status = 'active'::text)))));
DROP POLICY IF EXISTS "project_members_update" ON project_members;
CREATE POLICY "project_members_update" ON project_members FOR UPDATE USING ((tenant_id IN ( SELECT tu.tenant_id
   FROM tenant_users tu
  WHERE ((tu.auth_id = auth.uid()) AND (tu.status = 'active'::text) AND (tu.role = ANY (ARRAY['admin'::text, 'accountant'::text, 'manager'::text]))))));
DROP POLICY IF EXISTS "tenant_delete" ON bank_accounts;
CREATE POLICY "tenant_delete" ON bank_accounts FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_bank_accounts" ON bank_accounts;
CREATE POLICY "tenant_delete_bank_accounts" ON bank_accounts FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON bank_accounts;
CREATE POLICY "tenant_insert" ON bank_accounts FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_bank_accounts" ON bank_accounts;
CREATE POLICY "tenant_insert_bank_accounts" ON bank_accounts FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON bank_accounts;
CREATE POLICY "tenant_select" ON bank_accounts FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_bank_accounts" ON bank_accounts;
CREATE POLICY "tenant_select_bank_accounts" ON bank_accounts FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON bank_accounts;
CREATE POLICY "tenant_update" ON bank_accounts FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_bank_accounts" ON bank_accounts;
CREATE POLICY "tenant_update_bank_accounts" ON bank_accounts FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON bank_transactions;
CREATE POLICY "tenant_delete" ON bank_transactions FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_bank_transactions" ON bank_transactions;
CREATE POLICY "tenant_delete_bank_transactions" ON bank_transactions FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON bank_transactions;
CREATE POLICY "tenant_insert" ON bank_transactions FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_bank_transactions" ON bank_transactions;
CREATE POLICY "tenant_insert_bank_transactions" ON bank_transactions FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON bank_transactions;
CREATE POLICY "tenant_select" ON bank_transactions FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_bank_transactions" ON bank_transactions;
CREATE POLICY "tenant_select_bank_transactions" ON bank_transactions FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON bank_transactions;
CREATE POLICY "tenant_update" ON bank_transactions FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_bank_transactions" ON bank_transactions;
CREATE POLICY "tenant_update_bank_transactions" ON bank_transactions FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON bank_rules;
CREATE POLICY "tenant_delete" ON bank_rules FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_bank_rules" ON bank_rules;
CREATE POLICY "tenant_delete_bank_rules" ON bank_rules FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON bank_rules;
CREATE POLICY "tenant_insert" ON bank_rules FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_bank_rules" ON bank_rules;
CREATE POLICY "tenant_insert_bank_rules" ON bank_rules FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON bank_rules;
CREATE POLICY "tenant_select" ON bank_rules FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_bank_rules" ON bank_rules;
CREATE POLICY "tenant_select_bank_rules" ON bank_rules FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON bank_rules;
CREATE POLICY "tenant_update" ON bank_rules FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_bank_rules" ON bank_rules;
CREATE POLICY "tenant_update_bank_rules" ON bank_rules FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON entry_templates;
CREATE POLICY "tenant_delete" ON entry_templates FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_entry_templates" ON entry_templates;
CREATE POLICY "tenant_delete_entry_templates" ON entry_templates FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON entry_templates;
CREATE POLICY "tenant_insert" ON entry_templates FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_entry_templates" ON entry_templates;
CREATE POLICY "tenant_insert_entry_templates" ON entry_templates FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON entry_templates;
CREATE POLICY "tenant_select" ON entry_templates FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_entry_templates" ON entry_templates;
CREATE POLICY "tenant_select_entry_templates" ON entry_templates FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON entry_templates;
CREATE POLICY "tenant_update" ON entry_templates FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_entry_templates" ON entry_templates;
CREATE POLICY "tenant_update_entry_templates" ON entry_templates FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_journal_access" ON journal_access_rights;
CREATE POLICY "tenant_delete_journal_access" ON journal_access_rights FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_journal_access" ON journal_access_rights;
CREATE POLICY "tenant_insert_journal_access" ON journal_access_rights FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_journal_access" ON journal_access_rights;
CREATE POLICY "tenant_select_journal_access" ON journal_access_rights FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_journal_access" ON journal_access_rights;
CREATE POLICY "tenant_update_journal_access" ON journal_access_rights FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_vat_collections" ON vat_on_collections;
CREATE POLICY "tenant_delete_vat_collections" ON vat_on_collections FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_vat_collections" ON vat_on_collections;
CREATE POLICY "tenant_insert_vat_collections" ON vat_on_collections FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_vat_collections" ON vat_on_collections;
CREATE POLICY "tenant_select_vat_collections" ON vat_on_collections FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_vat_collections" ON vat_on_collections;
CREATE POLICY "tenant_update_vat_collections" ON vat_on_collections FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_batch_entry" ON batch_entry_sessions;
CREATE POLICY "tenant_delete_batch_entry" ON batch_entry_sessions FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_batch_entry" ON batch_entry_sessions;
CREATE POLICY "tenant_insert_batch_entry" ON batch_entry_sessions FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_batch_entry" ON batch_entry_sessions;
CREATE POLICY "tenant_select_batch_entry" ON batch_entry_sessions FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_batch_entry" ON batch_entry_sessions;
CREATE POLICY "tenant_update_batch_entry" ON batch_entry_sessions FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_mirror_servers" ON mirror_servers;
CREATE POLICY "tenant_delete_mirror_servers" ON mirror_servers FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_mirror_servers" ON mirror_servers;
CREATE POLICY "tenant_insert_mirror_servers" ON mirror_servers FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_isolated_mirror_servers" ON mirror_servers;
CREATE POLICY "tenant_isolated_mirror_servers" ON mirror_servers FOR ALL USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_mirror_servers" ON mirror_servers;
CREATE POLICY "tenant_select_mirror_servers" ON mirror_servers FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_mirror_servers" ON mirror_servers;
CREATE POLICY "tenant_update_mirror_servers" ON mirror_servers FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_payment_terms" ON payment_terms;
CREATE POLICY "tenant_delete_payment_terms" ON payment_terms FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_payment_terms" ON payment_terms;
CREATE POLICY "tenant_insert_payment_terms" ON payment_terms FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_payment_terms" ON payment_terms;
CREATE POLICY "tenant_select_payment_terms" ON payment_terms FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_payment_terms" ON payment_terms;
CREATE POLICY "tenant_update_payment_terms" ON payment_terms FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON fixed_assets;
CREATE POLICY "tenant_delete" ON fixed_assets FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_fixed_assets" ON fixed_assets;
CREATE POLICY "tenant_delete_fixed_assets" ON fixed_assets FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON fixed_assets;
CREATE POLICY "tenant_insert" ON fixed_assets FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_fixed_assets" ON fixed_assets;
CREATE POLICY "tenant_insert_fixed_assets" ON fixed_assets FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON fixed_assets;
CREATE POLICY "tenant_select" ON fixed_assets FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_fixed_assets" ON fixed_assets;
CREATE POLICY "tenant_select_fixed_assets" ON fixed_assets FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON fixed_assets;
CREATE POLICY "tenant_update" ON fixed_assets FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_fixed_assets" ON fixed_assets;
CREATE POLICY "tenant_update_fixed_assets" ON fixed_assets FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_reminder_levels" ON reminder_levels;
CREATE POLICY "tenant_delete_reminder_levels" ON reminder_levels FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_reminder_levels" ON reminder_levels;
CREATE POLICY "tenant_insert_reminder_levels" ON reminder_levels FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_reminder_levels" ON reminder_levels;
CREATE POLICY "tenant_select_reminder_levels" ON reminder_levels FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_reminder_levels" ON reminder_levels;
CREATE POLICY "tenant_update_reminder_levels" ON reminder_levels FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON goods_receipt_lines;
CREATE POLICY "tenant_delete" ON goods_receipt_lines FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_goods_receipt_lines" ON goods_receipt_lines;
CREATE POLICY "tenant_delete_goods_receipt_lines" ON goods_receipt_lines FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON goods_receipt_lines;
CREATE POLICY "tenant_insert" ON goods_receipt_lines FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_goods_receipt_lines" ON goods_receipt_lines;
CREATE POLICY "tenant_insert_goods_receipt_lines" ON goods_receipt_lines FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON goods_receipt_lines;
CREATE POLICY "tenant_select" ON goods_receipt_lines FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_goods_receipt_lines" ON goods_receipt_lines;
CREATE POLICY "tenant_select_goods_receipt_lines" ON goods_receipt_lines FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON goods_receipt_lines;
CREATE POLICY "tenant_update" ON goods_receipt_lines FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_goods_receipt_lines" ON goods_receipt_lines;
CREATE POLICY "tenant_update_goods_receipt_lines" ON goods_receipt_lines FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON contracts;
CREATE POLICY "tenant_delete" ON contracts FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_contracts" ON contracts;
CREATE POLICY "tenant_delete_contracts" ON contracts FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON contracts;
CREATE POLICY "tenant_insert" ON contracts FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_contracts" ON contracts;
CREATE POLICY "tenant_insert_contracts" ON contracts FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON contracts;
CREATE POLICY "tenant_select" ON contracts FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_contracts" ON contracts;
CREATE POLICY "tenant_select_contracts" ON contracts FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON contracts;
CREATE POLICY "tenant_update" ON contracts FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_contracts" ON contracts;
CREATE POLICY "tenant_update_contracts" ON contracts FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON legal_declarations;
CREATE POLICY "tenant_delete" ON legal_declarations FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_legal_declarations" ON legal_declarations;
CREATE POLICY "tenant_delete_legal_declarations" ON legal_declarations FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON legal_declarations;
CREATE POLICY "tenant_insert" ON legal_declarations FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_legal_declarations" ON legal_declarations;
CREATE POLICY "tenant_insert_legal_declarations" ON legal_declarations FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON legal_declarations;
CREATE POLICY "tenant_select" ON legal_declarations FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_legal_declarations" ON legal_declarations;
CREATE POLICY "tenant_select_legal_declarations" ON legal_declarations FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON legal_declarations;
CREATE POLICY "tenant_update" ON legal_declarations FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_legal_declarations" ON legal_declarations;
CREATE POLICY "tenant_update_legal_declarations" ON legal_declarations FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_payment_promises" ON payment_promises;
CREATE POLICY "tenant_delete_payment_promises" ON payment_promises FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_payment_promises" ON payment_promises;
CREATE POLICY "tenant_insert_payment_promises" ON payment_promises FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_payment_promises" ON payment_promises;
CREATE POLICY "tenant_select_payment_promises" ON payment_promises FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_payment_promises" ON payment_promises;
CREATE POLICY "tenant_update_payment_promises" ON payment_promises FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_disputes" ON disputes;
CREATE POLICY "tenant_delete_disputes" ON disputes FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_disputes" ON disputes;
CREATE POLICY "tenant_insert_disputes" ON disputes FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_disputes" ON disputes;
CREATE POLICY "tenant_select_disputes" ON disputes FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_disputes" ON disputes;
CREATE POLICY "tenant_update_disputes" ON disputes FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON collection_reminders;
CREATE POLICY "tenant_delete" ON collection_reminders FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_collection_reminders" ON collection_reminders;
CREATE POLICY "tenant_delete_collection_reminders" ON collection_reminders FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON collection_reminders;
CREATE POLICY "tenant_insert" ON collection_reminders FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_collection_reminders" ON collection_reminders;
CREATE POLICY "tenant_insert_collection_reminders" ON collection_reminders FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON collection_reminders;
CREATE POLICY "tenant_select" ON collection_reminders FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_collection_reminders" ON collection_reminders;
CREATE POLICY "tenant_select_collection_reminders" ON collection_reminders FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON collection_reminders;
CREATE POLICY "tenant_update" ON collection_reminders FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_collection_reminders" ON collection_reminders;
CREATE POLICY "tenant_update_collection_reminders" ON collection_reminders FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_justificatif_solde" ON justificatif_solde;
CREATE POLICY "tenant_delete_justificatif_solde" ON justificatif_solde FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_justificatif_solde" ON justificatif_solde;
CREATE POLICY "tenant_insert_justificatif_solde" ON justificatif_solde FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_justificatif_solde" ON justificatif_solde;
CREATE POLICY "tenant_select_justificatif_solde" ON justificatif_solde FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_tenant_users" ON tenant_users;
CREATE POLICY "tenant_delete_tenant_users" ON tenant_users FOR DELETE USING (((tenant_id = current_tenant_id()) AND (current_user_role() = 'admin'::text)));
DROP POLICY IF EXISTS "tenant_insert_tenant_users" ON tenant_users;
CREATE POLICY "tenant_insert_tenant_users" ON tenant_users FOR INSERT WITH CHECK (((tenant_id = current_tenant_id()) AND (current_user_role() = 'admin'::text)));
DROP POLICY IF EXISTS "tenant_select_tenant_users" ON tenant_users;
CREATE POLICY "tenant_select_tenant_users" ON tenant_users FOR SELECT USING (((tenant_id = current_tenant_id()) OR ((auth_id = auth.uid()) AND (status = 'pending'::text))));
DROP POLICY IF EXISTS "tenant_update_tenant_users" ON tenant_users;
CREATE POLICY "tenant_update_tenant_users" ON tenant_users FOR UPDATE USING ((((tenant_id = current_tenant_id()) AND (current_user_role() = 'admin'::text)) OR (auth_id = auth.uid()))) WITH CHECK ((((tenant_id = current_tenant_id()) AND (current_user_role() = 'admin'::text)) OR (auth_id = auth.uid())));
DROP POLICY IF EXISTS "tenant_users_delete" ON tenant_users;
CREATE POLICY "tenant_users_delete" ON tenant_users FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_users_insert" ON tenant_users;
CREATE POLICY "tenant_users_insert" ON tenant_users FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_users_select" ON tenant_users;
CREATE POLICY "tenant_users_select" ON tenant_users FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_users_update" ON tenant_users;
CREATE POLICY "tenant_users_update" ON tenant_users FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON goods_receipts;
CREATE POLICY "tenant_delete" ON goods_receipts FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_goods_receipts" ON goods_receipts;
CREATE POLICY "tenant_delete_goods_receipts" ON goods_receipts FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON goods_receipts;
CREATE POLICY "tenant_insert" ON goods_receipts FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_goods_receipts" ON goods_receipts;
CREATE POLICY "tenant_insert_goods_receipts" ON goods_receipts FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON goods_receipts;
CREATE POLICY "tenant_select" ON goods_receipts FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_goods_receipts" ON goods_receipts;
CREATE POLICY "tenant_select_goods_receipts" ON goods_receipts FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON goods_receipts;
CREATE POLICY "tenant_update" ON goods_receipts FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_goods_receipts" ON goods_receipts;
CREATE POLICY "tenant_update_goods_receipts" ON goods_receipts FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_etat_rapprochement" ON etat_rapprochement;
CREATE POLICY "tenant_delete_etat_rapprochement" ON etat_rapprochement FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_etat_rapprochement" ON etat_rapprochement;
CREATE POLICY "tenant_insert_etat_rapprochement" ON etat_rapprochement FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_etat_rapprochement" ON etat_rapprochement;
CREATE POLICY "tenant_select_etat_rapprochement" ON etat_rapprochement FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON payment_orders;
CREATE POLICY "tenant_delete" ON payment_orders FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_payment_orders" ON payment_orders;
CREATE POLICY "tenant_delete_payment_orders" ON payment_orders FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON payment_orders;
CREATE POLICY "tenant_insert" ON payment_orders FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_payment_orders" ON payment_orders;
CREATE POLICY "tenant_insert_payment_orders" ON payment_orders FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON payment_orders;
CREATE POLICY "tenant_select" ON payment_orders FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_payment_orders" ON payment_orders;
CREATE POLICY "tenant_select_payment_orders" ON payment_orders FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON payment_orders;
CREATE POLICY "tenant_update" ON payment_orders FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_payment_orders" ON payment_orders;
CREATE POLICY "tenant_update_payment_orders" ON payment_orders FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON payroll_accounting_entries;
CREATE POLICY "tenant_delete" ON payroll_accounting_entries FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_payroll_accounting_entries" ON payroll_accounting_entries;
CREATE POLICY "tenant_delete_payroll_accounting_entries" ON payroll_accounting_entries FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON payroll_accounting_entries;
CREATE POLICY "tenant_insert" ON payroll_accounting_entries FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_payroll_accounting_entries" ON payroll_accounting_entries;
CREATE POLICY "tenant_insert_payroll_accounting_entries" ON payroll_accounting_entries FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON payroll_accounting_entries;
CREATE POLICY "tenant_select" ON payroll_accounting_entries FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_payroll_accounting_entries" ON payroll_accounting_entries;
CREATE POLICY "tenant_select_payroll_accounting_entries" ON payroll_accounting_entries FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON payroll_accounting_entries;
CREATE POLICY "tenant_update" ON payroll_accounting_entries FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_payroll_accounting_entries" ON payroll_accounting_entries;
CREATE POLICY "tenant_update_payroll_accounting_entries" ON payroll_accounting_entries FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "global_select_currencies" ON currencies;
CREATE POLICY "global_select_currencies" ON currencies FOR SELECT USING ((auth.uid() IS NOT NULL));
DROP POLICY IF EXISTS "tenant_delete" ON price_lists;
CREATE POLICY "tenant_delete" ON price_lists FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_price_lists" ON price_lists;
CREATE POLICY "tenant_delete_price_lists" ON price_lists FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON price_lists;
CREATE POLICY "tenant_insert" ON price_lists FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_price_lists" ON price_lists;
CREATE POLICY "tenant_insert_price_lists" ON price_lists FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON price_lists;
CREATE POLICY "tenant_select" ON price_lists FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_price_lists" ON price_lists;
CREATE POLICY "tenant_select_price_lists" ON price_lists FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON price_lists;
CREATE POLICY "tenant_update" ON price_lists FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_price_lists" ON price_lists;
CREATE POLICY "tenant_update_price_lists" ON price_lists FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON price_list_lines;
CREATE POLICY "tenant_delete" ON price_list_lines FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_price_list_lines" ON price_list_lines;
CREATE POLICY "tenant_delete_price_list_lines" ON price_list_lines FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON price_list_lines;
CREATE POLICY "tenant_insert" ON price_list_lines FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_price_list_lines" ON price_list_lines;
CREATE POLICY "tenant_insert_price_list_lines" ON price_list_lines FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON price_list_lines;
CREATE POLICY "tenant_select" ON price_list_lines FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_price_list_lines" ON price_list_lines;
CREATE POLICY "tenant_select_price_list_lines" ON price_list_lines FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON price_list_lines;
CREATE POLICY "tenant_update" ON price_list_lines FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_price_list_lines" ON price_list_lines;
CREATE POLICY "tenant_update_price_list_lines" ON price_list_lines FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON routing_operations;
CREATE POLICY "tenant_delete" ON routing_operations FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_routing_operations" ON routing_operations;
CREATE POLICY "tenant_delete_routing_operations" ON routing_operations FOR DELETE USING (((tenant_id = current_tenant_id()) AND can_perform('routing_operations'::text, 'delete'::text)));
DROP POLICY IF EXISTS "tenant_insert" ON routing_operations;
CREATE POLICY "tenant_insert" ON routing_operations FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_routing_operations" ON routing_operations;
CREATE POLICY "tenant_insert_routing_operations" ON routing_operations FOR INSERT WITH CHECK (((tenant_id = current_tenant_id()) AND can_perform('routing_operations'::text, 'insert'::text)));
DROP POLICY IF EXISTS "tenant_select" ON routing_operations;
CREATE POLICY "tenant_select" ON routing_operations FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_routing_operations" ON routing_operations;
CREATE POLICY "tenant_select_routing_operations" ON routing_operations FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON routing_operations;
CREATE POLICY "tenant_update" ON routing_operations FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_routing_operations" ON routing_operations;
CREATE POLICY "tenant_update_routing_operations" ON routing_operations FOR UPDATE USING (((tenant_id = current_tenant_id()) AND can_perform('routing_operations'::text, 'update'::text))) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON bom_lines;
CREATE POLICY "tenant_delete" ON bom_lines FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_bom_lines" ON bom_lines;
CREATE POLICY "tenant_delete_bom_lines" ON bom_lines FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON bom_lines;
CREATE POLICY "tenant_insert" ON bom_lines FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_bom_lines" ON bom_lines;
CREATE POLICY "tenant_insert_bom_lines" ON bom_lines FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON bom_lines;
CREATE POLICY "tenant_select" ON bom_lines FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_bom_lines" ON bom_lines;
CREATE POLICY "tenant_select_bom_lines" ON bom_lines FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON bom_lines;
CREATE POLICY "tenant_update" ON bom_lines FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_bom_lines" ON bom_lines;
CREATE POLICY "tenant_update_bom_lines" ON bom_lines FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON audit_log;
CREATE POLICY "tenant_delete" ON audit_log FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON audit_log;
CREATE POLICY "tenant_insert" ON audit_log FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_audit_log" ON audit_log;
CREATE POLICY "tenant_insert_audit_log" ON audit_log FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON audit_log;
CREATE POLICY "tenant_select" ON audit_log FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_audit_log" ON audit_log;
CREATE POLICY "tenant_select_audit_log" ON audit_log FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON audit_log;
CREATE POLICY "tenant_update" ON audit_log FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON of_labels;
CREATE POLICY "tenant_delete" ON of_labels FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_of_labels" ON of_labels;
CREATE POLICY "tenant_delete_of_labels" ON of_labels FOR DELETE USING (((tenant_id = current_tenant_id()) AND can_perform('of_labels'::text, 'delete'::text)));
DROP POLICY IF EXISTS "tenant_insert" ON of_labels;
CREATE POLICY "tenant_insert" ON of_labels FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_of_labels" ON of_labels;
CREATE POLICY "tenant_insert_of_labels" ON of_labels FOR INSERT WITH CHECK (((tenant_id = current_tenant_id()) AND can_perform('of_labels'::text, 'insert'::text)));
DROP POLICY IF EXISTS "tenant_select" ON of_labels;
CREATE POLICY "tenant_select" ON of_labels FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_of_labels" ON of_labels;
CREATE POLICY "tenant_select_of_labels" ON of_labels FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON of_labels;
CREATE POLICY "tenant_update" ON of_labels FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_of_labels" ON of_labels;
CREATE POLICY "tenant_update_of_labels" ON of_labels FOR UPDATE USING (((tenant_id = current_tenant_id()) AND can_perform('of_labels'::text, 'update'::text))) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON of_lots;
CREATE POLICY "tenant_delete" ON of_lots FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_of_lots" ON of_lots;
CREATE POLICY "tenant_delete_of_lots" ON of_lots FOR DELETE USING (((tenant_id = current_tenant_id()) AND can_perform('of_lots'::text, 'delete'::text)));
DROP POLICY IF EXISTS "tenant_insert" ON of_lots;
CREATE POLICY "tenant_insert" ON of_lots FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_of_lots" ON of_lots;
CREATE POLICY "tenant_insert_of_lots" ON of_lots FOR INSERT WITH CHECK (((tenant_id = current_tenant_id()) AND can_perform('of_lots'::text, 'insert'::text)));
DROP POLICY IF EXISTS "tenant_select" ON of_lots;
CREATE POLICY "tenant_select" ON of_lots FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_of_lots" ON of_lots;
CREATE POLICY "tenant_select_of_lots" ON of_lots FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON of_lots;
CREATE POLICY "tenant_update" ON of_lots FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_of_lots" ON of_lots;
CREATE POLICY "tenant_update_of_lots" ON of_lots FOR UPDATE USING (((tenant_id = current_tenant_id()) AND can_perform('of_lots'::text, 'update'::text))) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON stock_quantities;
CREATE POLICY "tenant_delete" ON stock_quantities FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_stock_quantities" ON stock_quantities;
CREATE POLICY "tenant_delete_stock_quantities" ON stock_quantities FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON stock_quantities;
CREATE POLICY "tenant_insert" ON stock_quantities FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_stock_quantities" ON stock_quantities;
CREATE POLICY "tenant_insert_stock_quantities" ON stock_quantities FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON stock_quantities;
CREATE POLICY "tenant_select" ON stock_quantities FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_stock_quantities" ON stock_quantities;
CREATE POLICY "tenant_select_stock_quantities" ON stock_quantities FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON stock_quantities;
CREATE POLICY "tenant_update" ON stock_quantities FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_stock_quantities" ON stock_quantities;
CREATE POLICY "tenant_update_stock_quantities" ON stock_quantities FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON stock_movements;
CREATE POLICY "tenant_delete" ON stock_movements FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_stock_movements" ON stock_movements;
CREATE POLICY "tenant_delete_stock_movements" ON stock_movements FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON stock_movements;
CREATE POLICY "tenant_insert" ON stock_movements FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_stock_movements" ON stock_movements;
CREATE POLICY "tenant_insert_stock_movements" ON stock_movements FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON stock_movements;
CREATE POLICY "tenant_select" ON stock_movements FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_stock_movements" ON stock_movements;
CREATE POLICY "tenant_select_stock_movements" ON stock_movements FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON stock_movements;
CREATE POLICY "tenant_update" ON stock_movements FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_stock_movements" ON stock_movements;
CREATE POLICY "tenant_update_stock_movements" ON stock_movements FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON of_consumptions;
CREATE POLICY "tenant_delete" ON of_consumptions FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_of_consumptions" ON of_consumptions;
CREATE POLICY "tenant_delete_of_consumptions" ON of_consumptions FOR DELETE USING (((tenant_id = current_tenant_id()) AND can_perform('of_consumptions'::text, 'delete'::text)));
DROP POLICY IF EXISTS "tenant_insert" ON of_consumptions;
CREATE POLICY "tenant_insert" ON of_consumptions FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_of_consumptions" ON of_consumptions;
CREATE POLICY "tenant_insert_of_consumptions" ON of_consumptions FOR INSERT WITH CHECK (((tenant_id = current_tenant_id()) AND can_perform('of_consumptions'::text, 'insert'::text)));
DROP POLICY IF EXISTS "tenant_select" ON of_consumptions;
CREATE POLICY "tenant_select" ON of_consumptions FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_of_consumptions" ON of_consumptions;
CREATE POLICY "tenant_select_of_consumptions" ON of_consumptions FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON of_consumptions;
CREATE POLICY "tenant_update" ON of_consumptions FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_of_consumptions" ON of_consumptions;
CREATE POLICY "tenant_update_of_consumptions" ON of_consumptions FOR UPDATE USING (((tenant_id = current_tenant_id()) AND can_perform('of_consumptions'::text, 'update'::text))) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON st_orders;
CREATE POLICY "tenant_delete" ON st_orders FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_st_orders" ON st_orders;
CREATE POLICY "tenant_delete_st_orders" ON st_orders FOR DELETE USING (((tenant_id = current_tenant_id()) AND can_perform('st_orders'::text, 'delete'::text)));
DROP POLICY IF EXISTS "tenant_insert" ON st_orders;
CREATE POLICY "tenant_insert" ON st_orders FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_st_orders" ON st_orders;
CREATE POLICY "tenant_insert_st_orders" ON st_orders FOR INSERT WITH CHECK (((tenant_id = current_tenant_id()) AND can_perform('st_orders'::text, 'insert'::text)));
DROP POLICY IF EXISTS "tenant_select" ON st_orders;
CREATE POLICY "tenant_select" ON st_orders FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_st_orders" ON st_orders;
CREATE POLICY "tenant_select_st_orders" ON st_orders FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON st_orders;
CREATE POLICY "tenant_update" ON st_orders FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_st_orders" ON st_orders;
CREATE POLICY "tenant_update_st_orders" ON st_orders FOR UPDATE USING (((tenant_id = current_tenant_id()) AND can_perform('st_orders'::text, 'update'::text))) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON manufacturing_orders;
CREATE POLICY "tenant_delete" ON manufacturing_orders FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_manufacturing_orders" ON manufacturing_orders;
CREATE POLICY "tenant_delete_manufacturing_orders" ON manufacturing_orders FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON manufacturing_orders;
CREATE POLICY "tenant_insert" ON manufacturing_orders FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_manufacturing_orders" ON manufacturing_orders;
CREATE POLICY "tenant_insert_manufacturing_orders" ON manufacturing_orders FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON manufacturing_orders;
CREATE POLICY "tenant_select" ON manufacturing_orders FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_manufacturing_orders" ON manufacturing_orders;
CREATE POLICY "tenant_select_manufacturing_orders" ON manufacturing_orders FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON manufacturing_orders;
CREATE POLICY "tenant_update" ON manufacturing_orders FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_manufacturing_orders" ON manufacturing_orders;
CREATE POLICY "tenant_update_manufacturing_orders" ON manufacturing_orders FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON boms;
CREATE POLICY "tenant_delete" ON boms FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_boms" ON boms;
CREATE POLICY "tenant_delete_boms" ON boms FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON boms;
CREATE POLICY "tenant_insert" ON boms FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_boms" ON boms;
CREATE POLICY "tenant_insert_boms" ON boms FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON boms;
CREATE POLICY "tenant_select" ON boms FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_boms" ON boms;
CREATE POLICY "tenant_select_boms" ON boms FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON boms;
CREATE POLICY "tenant_update" ON boms FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_boms" ON boms;
CREATE POLICY "tenant_update_boms" ON boms FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON products;
CREATE POLICY "tenant_delete" ON products FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_products" ON products;
CREATE POLICY "tenant_delete_products" ON products FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON products;
CREATE POLICY "tenant_insert" ON products FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_products" ON products;
CREATE POLICY "tenant_insert_products" ON products FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON products;
CREATE POLICY "tenant_select" ON products FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_products" ON products;
CREATE POLICY "tenant_select_products" ON products FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON products;
CREATE POLICY "tenant_update" ON products FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_products" ON products;
CREATE POLICY "tenant_update_products" ON products FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON st_shipments;
CREATE POLICY "tenant_delete" ON st_shipments FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_st_shipments" ON st_shipments;
CREATE POLICY "tenant_delete_st_shipments" ON st_shipments FOR DELETE USING (((tenant_id = current_tenant_id()) AND can_perform('st_shipments'::text, 'delete'::text)));
DROP POLICY IF EXISTS "tenant_insert" ON st_shipments;
CREATE POLICY "tenant_insert" ON st_shipments FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_st_shipments" ON st_shipments;
CREATE POLICY "tenant_insert_st_shipments" ON st_shipments FOR INSERT WITH CHECK (((tenant_id = current_tenant_id()) AND can_perform('st_shipments'::text, 'insert'::text)));
DROP POLICY IF EXISTS "tenant_select" ON st_shipments;
CREATE POLICY "tenant_select" ON st_shipments FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_st_shipments" ON st_shipments;
CREATE POLICY "tenant_select_st_shipments" ON st_shipments FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON st_shipments;
CREATE POLICY "tenant_update" ON st_shipments FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_st_shipments" ON st_shipments;
CREATE POLICY "tenant_update_st_shipments" ON st_shipments FOR UPDATE USING (((tenant_id = current_tenant_id()) AND can_perform('st_shipments'::text, 'update'::text))) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_revision_cycles" ON revision_cycles;
CREATE POLICY "tenant_delete_revision_cycles" ON revision_cycles FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_revision_cycles" ON revision_cycles;
CREATE POLICY "tenant_insert_revision_cycles" ON revision_cycles FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_revision_cycles" ON revision_cycles;
CREATE POLICY "tenant_select_revision_cycles" ON revision_cycles FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_revision_cycles" ON revision_cycles;
CREATE POLICY "tenant_update_revision_cycles" ON revision_cycles FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON st_shipment_lines;
CREATE POLICY "tenant_delete" ON st_shipment_lines FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_st_shipment_lines" ON st_shipment_lines;
CREATE POLICY "tenant_delete_st_shipment_lines" ON st_shipment_lines FOR DELETE USING (((tenant_id = current_tenant_id()) AND can_perform('st_shipment_lines'::text, 'delete'::text)));
DROP POLICY IF EXISTS "tenant_insert" ON st_shipment_lines;
CREATE POLICY "tenant_insert" ON st_shipment_lines FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_st_shipment_lines" ON st_shipment_lines;
CREATE POLICY "tenant_insert_st_shipment_lines" ON st_shipment_lines FOR INSERT WITH CHECK (((tenant_id = current_tenant_id()) AND can_perform('st_shipment_lines'::text, 'insert'::text)));
DROP POLICY IF EXISTS "tenant_select" ON st_shipment_lines;
CREATE POLICY "tenant_select" ON st_shipment_lines FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_st_shipment_lines" ON st_shipment_lines;
CREATE POLICY "tenant_select_st_shipment_lines" ON st_shipment_lines FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON st_shipment_lines;
CREATE POLICY "tenant_update" ON st_shipment_lines FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_st_shipment_lines" ON st_shipment_lines;
CREATE POLICY "tenant_update_st_shipment_lines" ON st_shipment_lines FOR UPDATE USING (((tenant_id = current_tenant_id()) AND can_perform('st_shipment_lines'::text, 'update'::text))) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_reporting_plans" ON reporting_plans;
CREATE POLICY "tenant_delete_reporting_plans" ON reporting_plans FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_reporting_plans" ON reporting_plans;
CREATE POLICY "tenant_insert_reporting_plans" ON reporting_plans FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_reporting_plans" ON reporting_plans;
CREATE POLICY "tenant_select_reporting_plans" ON reporting_plans FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_reporting_plans" ON reporting_plans;
CREATE POLICY "tenant_update_reporting_plans" ON reporting_plans FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON st_receipts;
CREATE POLICY "tenant_delete" ON st_receipts FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_st_receipts" ON st_receipts;
CREATE POLICY "tenant_delete_st_receipts" ON st_receipts FOR DELETE USING (((tenant_id = current_tenant_id()) AND can_perform('st_receipts'::text, 'delete'::text)));
DROP POLICY IF EXISTS "tenant_insert" ON st_receipts;
CREATE POLICY "tenant_insert" ON st_receipts FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_st_receipts" ON st_receipts;
CREATE POLICY "tenant_insert_st_receipts" ON st_receipts FOR INSERT WITH CHECK (((tenant_id = current_tenant_id()) AND can_perform('st_receipts'::text, 'insert'::text)));
DROP POLICY IF EXISTS "tenant_select" ON st_receipts;
CREATE POLICY "tenant_select" ON st_receipts FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_st_receipts" ON st_receipts;
CREATE POLICY "tenant_select_st_receipts" ON st_receipts FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON st_receipts;
CREATE POLICY "tenant_update" ON st_receipts FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_st_receipts" ON st_receipts;
CREATE POLICY "tenant_update_st_receipts" ON st_receipts FOR UPDATE USING (((tenant_id = current_tenant_id()) AND can_perform('st_receipts'::text, 'update'::text))) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON st_receipt_lines;
CREATE POLICY "tenant_delete" ON st_receipt_lines FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_st_receipt_lines" ON st_receipt_lines;
CREATE POLICY "tenant_delete_st_receipt_lines" ON st_receipt_lines FOR DELETE USING (((tenant_id = current_tenant_id()) AND can_perform('st_receipt_lines'::text, 'delete'::text)));
DROP POLICY IF EXISTS "tenant_insert" ON st_receipt_lines;
CREATE POLICY "tenant_insert" ON st_receipt_lines FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_st_receipt_lines" ON st_receipt_lines;
CREATE POLICY "tenant_insert_st_receipt_lines" ON st_receipt_lines FOR INSERT WITH CHECK (((tenant_id = current_tenant_id()) AND can_perform('st_receipt_lines'::text, 'insert'::text)));
DROP POLICY IF EXISTS "tenant_select" ON st_receipt_lines;
CREATE POLICY "tenant_select" ON st_receipt_lines FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_st_receipt_lines" ON st_receipt_lines;
CREATE POLICY "tenant_select_st_receipt_lines" ON st_receipt_lines FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON st_receipt_lines;
CREATE POLICY "tenant_update" ON st_receipt_lines FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_st_receipt_lines" ON st_receipt_lines;
CREATE POLICY "tenant_update_st_receipt_lines" ON st_receipt_lines FOR UPDATE USING (((tenant_id = current_tenant_id()) AND can_perform('st_receipt_lines'::text, 'update'::text))) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON mrp_runs;
CREATE POLICY "tenant_delete" ON mrp_runs FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_mrp_runs" ON mrp_runs;
CREATE POLICY "tenant_delete_mrp_runs" ON mrp_runs FOR DELETE USING (((tenant_id = current_tenant_id()) AND can_perform('mrp_runs'::text, 'delete'::text)));
DROP POLICY IF EXISTS "tenant_insert" ON mrp_runs;
CREATE POLICY "tenant_insert" ON mrp_runs FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_mrp_runs" ON mrp_runs;
CREATE POLICY "tenant_insert_mrp_runs" ON mrp_runs FOR INSERT WITH CHECK (((tenant_id = current_tenant_id()) AND can_perform('mrp_runs'::text, 'insert'::text)));
DROP POLICY IF EXISTS "tenant_select" ON mrp_runs;
CREATE POLICY "tenant_select" ON mrp_runs FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_mrp_runs" ON mrp_runs;
CREATE POLICY "tenant_select_mrp_runs" ON mrp_runs FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON mrp_runs;
CREATE POLICY "tenant_update" ON mrp_runs FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_mrp_runs" ON mrp_runs;
CREATE POLICY "tenant_update_mrp_runs" ON mrp_runs FOR UPDATE USING (((tenant_id = current_tenant_id()) AND can_perform('mrp_runs'::text, 'update'::text))) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON mrp_proposals;
CREATE POLICY "tenant_delete" ON mrp_proposals FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_mrp_proposals" ON mrp_proposals;
CREATE POLICY "tenant_delete_mrp_proposals" ON mrp_proposals FOR DELETE USING (((tenant_id = current_tenant_id()) AND can_perform('mrp_proposals'::text, 'delete'::text)));
DROP POLICY IF EXISTS "tenant_insert" ON mrp_proposals;
CREATE POLICY "tenant_insert" ON mrp_proposals FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_mrp_proposals" ON mrp_proposals;
CREATE POLICY "tenant_insert_mrp_proposals" ON mrp_proposals FOR INSERT WITH CHECK (((tenant_id = current_tenant_id()) AND can_perform('mrp_proposals'::text, 'insert'::text)));
DROP POLICY IF EXISTS "tenant_select" ON mrp_proposals;
CREATE POLICY "tenant_select" ON mrp_proposals FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_mrp_proposals" ON mrp_proposals;
CREATE POLICY "tenant_select_mrp_proposals" ON mrp_proposals FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON mrp_proposals;
CREATE POLICY "tenant_update" ON mrp_proposals FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_mrp_proposals" ON mrp_proposals;
CREATE POLICY "tenant_update_mrp_proposals" ON mrp_proposals FOR UPDATE USING (((tenant_id = current_tenant_id()) AND can_perform('mrp_proposals'::text, 'update'::text))) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON mrp_pending_docs;
CREATE POLICY "tenant_delete" ON mrp_pending_docs FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_mrp_pending_docs" ON mrp_pending_docs;
CREATE POLICY "tenant_delete_mrp_pending_docs" ON mrp_pending_docs FOR DELETE USING (((tenant_id = current_tenant_id()) AND can_perform('mrp_pending_docs'::text, 'delete'::text)));
DROP POLICY IF EXISTS "tenant_insert" ON mrp_pending_docs;
CREATE POLICY "tenant_insert" ON mrp_pending_docs FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_mrp_pending_docs" ON mrp_pending_docs;
CREATE POLICY "tenant_insert_mrp_pending_docs" ON mrp_pending_docs FOR INSERT WITH CHECK (((tenant_id = current_tenant_id()) AND can_perform('mrp_pending_docs'::text, 'insert'::text)));
DROP POLICY IF EXISTS "tenant_select" ON mrp_pending_docs;
CREATE POLICY "tenant_select" ON mrp_pending_docs FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_mrp_pending_docs" ON mrp_pending_docs;
CREATE POLICY "tenant_select_mrp_pending_docs" ON mrp_pending_docs FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON mrp_pending_docs;
CREATE POLICY "tenant_update" ON mrp_pending_docs FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_mrp_pending_docs" ON mrp_pending_docs;
CREATE POLICY "tenant_update_mrp_pending_docs" ON mrp_pending_docs FOR UPDATE USING (((tenant_id = current_tenant_id()) AND can_perform('mrp_pending_docs'::text, 'update'::text))) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_stat_fields" ON stat_fields;
CREATE POLICY "tenant_delete_stat_fields" ON stat_fields FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_stat_fields" ON stat_fields;
CREATE POLICY "tenant_insert_stat_fields" ON stat_fields FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_stat_fields" ON stat_fields;
CREATE POLICY "tenant_select_stat_fields" ON stat_fields FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_stat_fields" ON stat_fields;
CREATE POLICY "tenant_update_stat_fields" ON stat_fields FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON production_forecasts;
CREATE POLICY "tenant_delete" ON production_forecasts FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_production_forecasts" ON production_forecasts;
CREATE POLICY "tenant_delete_production_forecasts" ON production_forecasts FOR DELETE USING (((tenant_id = current_tenant_id()) AND can_perform('production_forecasts'::text, 'delete'::text)));
DROP POLICY IF EXISTS "tenant_insert" ON production_forecasts;
CREATE POLICY "tenant_insert" ON production_forecasts FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_production_forecasts" ON production_forecasts;
CREATE POLICY "tenant_insert_production_forecasts" ON production_forecasts FOR INSERT WITH CHECK (((tenant_id = current_tenant_id()) AND can_perform('production_forecasts'::text, 'insert'::text)));
DROP POLICY IF EXISTS "tenant_select" ON production_forecasts;
CREATE POLICY "tenant_select" ON production_forecasts FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_production_forecasts" ON production_forecasts;
CREATE POLICY "tenant_select_production_forecasts" ON production_forecasts FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON production_forecasts;
CREATE POLICY "tenant_update" ON production_forecasts FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_production_forecasts" ON production_forecasts;
CREATE POLICY "tenant_update_production_forecasts" ON production_forecasts FOR UPDATE USING (((tenant_id = current_tenant_id()) AND can_perform('production_forecasts'::text, 'update'::text))) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_dashboard_widgets" ON dashboard_widgets;
CREATE POLICY "tenant_delete_dashboard_widgets" ON dashboard_widgets FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_dashboard_widgets" ON dashboard_widgets;
CREATE POLICY "tenant_insert_dashboard_widgets" ON dashboard_widgets FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_dashboard_widgets" ON dashboard_widgets;
CREATE POLICY "tenant_select_dashboard_widgets" ON dashboard_widgets FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_dashboard_widgets" ON dashboard_widgets;
CREATE POLICY "tenant_update_dashboard_widgets" ON dashboard_widgets FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_recurring_entries" ON recurring_entries;
CREATE POLICY "tenant_delete_recurring_entries" ON recurring_entries FOR DELETE USING (((tenant_id = current_tenant_id()) AND can_perform('recurring_entries'::text, 'delete'::text)));
DROP POLICY IF EXISTS "tenant_insert_recurring_entries" ON recurring_entries;
CREATE POLICY "tenant_insert_recurring_entries" ON recurring_entries FOR INSERT WITH CHECK (((tenant_id = current_tenant_id()) AND can_perform('recurring_entries'::text, 'insert'::text)));
DROP POLICY IF EXISTS "tenant_select_recurring_entries" ON recurring_entries;
CREATE POLICY "tenant_select_recurring_entries" ON recurring_entries FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_recurring_entries" ON recurring_entries;
CREATE POLICY "tenant_update_recurring_entries" ON recurring_entries FOR UPDATE USING (((tenant_id = current_tenant_id()) AND can_perform('recurring_entries'::text, 'update'::text))) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "global_select_chart_account_templates" ON chart_account_templates;
CREATE POLICY "global_select_chart_account_templates" ON chart_account_templates FOR SELECT USING ((auth.uid() IS NOT NULL));
DROP POLICY IF EXISTS "tenant_insert_fusion_logs" ON fusion_logs;
CREATE POLICY "tenant_insert_fusion_logs" ON fusion_logs FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_fusion_logs" ON fusion_logs;
CREATE POLICY "tenant_select_fusion_logs" ON fusion_logs FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_bank_reconciliation_rules" ON bank_reconciliation_rules;
CREATE POLICY "tenant_delete_bank_reconciliation_rules" ON bank_reconciliation_rules FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_bank_reconciliation_rules" ON bank_reconciliation_rules;
CREATE POLICY "tenant_insert_bank_reconciliation_rules" ON bank_reconciliation_rules FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_bank_reconciliation_rules" ON bank_reconciliation_rules;
CREATE POLICY "tenant_select_bank_reconciliation_rules" ON bank_reconciliation_rules FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_bank_reconciliation_rules" ON bank_reconciliation_rules;
CREATE POLICY "tenant_update_bank_reconciliation_rules" ON bank_reconciliation_rules FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON product_serial_numbers;
CREATE POLICY "tenant_delete" ON product_serial_numbers FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_product_serial_numbers" ON product_serial_numbers;
CREATE POLICY "tenant_delete_product_serial_numbers" ON product_serial_numbers FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON product_serial_numbers;
CREATE POLICY "tenant_insert" ON product_serial_numbers FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_product_serial_numbers" ON product_serial_numbers;
CREATE POLICY "tenant_insert_product_serial_numbers" ON product_serial_numbers FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON product_serial_numbers;
CREATE POLICY "tenant_select" ON product_serial_numbers FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_product_serial_numbers" ON product_serial_numbers;
CREATE POLICY "tenant_select_product_serial_numbers" ON product_serial_numbers FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON product_serial_numbers;
CREATE POLICY "tenant_update" ON product_serial_numbers FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_product_serial_numbers" ON product_serial_numbers;
CREATE POLICY "tenant_update_product_serial_numbers" ON product_serial_numbers FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_bank_statement_imports" ON bank_statement_imports;
CREATE POLICY "tenant_delete_bank_statement_imports" ON bank_statement_imports FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_bank_statement_imports" ON bank_statement_imports;
CREATE POLICY "tenant_insert_bank_statement_imports" ON bank_statement_imports FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_bank_statement_imports" ON bank_statement_imports;
CREATE POLICY "tenant_select_bank_statement_imports" ON bank_statement_imports FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_bank_statement_imports" ON bank_statement_imports;
CREATE POLICY "tenant_update_bank_statement_imports" ON bank_statement_imports FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_compaction_logs" ON compaction_logs;
CREATE POLICY "tenant_insert_compaction_logs" ON compaction_logs FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_compaction_logs" ON compaction_logs;
CREATE POLICY "tenant_select_compaction_logs" ON compaction_logs FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON product_variants;
CREATE POLICY "tenant_delete" ON product_variants FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_product_variants" ON product_variants;
CREATE POLICY "tenant_delete_product_variants" ON product_variants FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON product_variants;
CREATE POLICY "tenant_insert" ON product_variants FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_product_variants" ON product_variants;
CREATE POLICY "tenant_insert_product_variants" ON product_variants FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON product_variants;
CREATE POLICY "tenant_select" ON product_variants FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_product_variants" ON product_variants;
CREATE POLICY "tenant_select_product_variants" ON product_variants FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON product_variants;
CREATE POLICY "tenant_update" ON product_variants FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_product_variants" ON product_variants;
CREATE POLICY "tenant_update_product_variants" ON product_variants FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON product_batches;
CREATE POLICY "tenant_delete" ON product_batches FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_product_batches" ON product_batches;
CREATE POLICY "tenant_delete_product_batches" ON product_batches FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON product_batches;
CREATE POLICY "tenant_insert" ON product_batches FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_product_batches" ON product_batches;
CREATE POLICY "tenant_insert_product_batches" ON product_batches FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON product_batches;
CREATE POLICY "tenant_select" ON product_batches FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_product_batches" ON product_batches;
CREATE POLICY "tenant_select_product_batches" ON product_batches FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON product_batches;
CREATE POLICY "tenant_update" ON product_batches FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_product_batches" ON product_batches;
CREATE POLICY "tenant_update_product_batches" ON product_batches FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON supplier_payments;
CREATE POLICY "tenant_delete" ON supplier_payments FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_supplier_payments" ON supplier_payments;
CREATE POLICY "tenant_delete_supplier_payments" ON supplier_payments FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON supplier_payments;
CREATE POLICY "tenant_insert" ON supplier_payments FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_supplier_payments" ON supplier_payments;
CREATE POLICY "tenant_insert_supplier_payments" ON supplier_payments FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON supplier_payments;
CREATE POLICY "tenant_select" ON supplier_payments FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_supplier_payments" ON supplier_payments;
CREATE POLICY "tenant_select_supplier_payments" ON supplier_payments FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON supplier_payments;
CREATE POLICY "tenant_update" ON supplier_payments FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_supplier_payments" ON supplier_payments;
CREATE POLICY "tenant_update_supplier_payments" ON supplier_payments FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON suppliers;
CREATE POLICY "tenant_delete" ON suppliers FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_suppliers" ON suppliers;
CREATE POLICY "tenant_delete_suppliers" ON suppliers FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON suppliers;
CREATE POLICY "tenant_insert" ON suppliers FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_suppliers" ON suppliers;
CREATE POLICY "tenant_insert_suppliers" ON suppliers FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON suppliers;
CREATE POLICY "tenant_select" ON suppliers FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_suppliers" ON suppliers;
CREATE POLICY "tenant_select_suppliers" ON suppliers FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON suppliers;
CREATE POLICY "tenant_update" ON suppliers FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_suppliers" ON suppliers;
CREATE POLICY "tenant_update_suppliers" ON suppliers FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON third_party_accounts;
CREATE POLICY "tenant_delete" ON third_party_accounts FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_third_party_accounts" ON third_party_accounts;
CREATE POLICY "tenant_delete_third_party_accounts" ON third_party_accounts FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON third_party_accounts;
CREATE POLICY "tenant_insert" ON third_party_accounts FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_third_party_accounts" ON third_party_accounts;
CREATE POLICY "tenant_insert_third_party_accounts" ON third_party_accounts FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON third_party_accounts;
CREATE POLICY "tenant_select" ON third_party_accounts FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_third_party_accounts" ON third_party_accounts;
CREATE POLICY "tenant_select_third_party_accounts" ON third_party_accounts FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON third_party_accounts;
CREATE POLICY "tenant_update" ON third_party_accounts FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_third_party_accounts" ON third_party_accounts;
CREATE POLICY "tenant_update_third_party_accounts" ON third_party_accounts FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON timesheets;
CREATE POLICY "tenant_delete" ON timesheets FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_timesheets" ON timesheets;
CREATE POLICY "tenant_delete_timesheets" ON timesheets FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON timesheets;
CREATE POLICY "tenant_insert" ON timesheets FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_timesheets" ON timesheets;
CREATE POLICY "tenant_insert_timesheets" ON timesheets FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON timesheets;
CREATE POLICY "tenant_select" ON timesheets FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_timesheets" ON timesheets;
CREATE POLICY "tenant_select_timesheets" ON timesheets FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON timesheets;
CREATE POLICY "tenant_update" ON timesheets FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_timesheets" ON timesheets;
CREATE POLICY "tenant_update_timesheets" ON timesheets FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON quality_checks;
CREATE POLICY "tenant_delete" ON quality_checks FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_quality_checks" ON quality_checks;
CREATE POLICY "tenant_delete_quality_checks" ON quality_checks FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON quality_checks;
CREATE POLICY "tenant_insert" ON quality_checks FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_quality_checks" ON quality_checks;
CREATE POLICY "tenant_insert_quality_checks" ON quality_checks FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON quality_checks;
CREATE POLICY "tenant_select" ON quality_checks FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_quality_checks" ON quality_checks;
CREATE POLICY "tenant_select_quality_checks" ON quality_checks FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON quality_checks;
CREATE POLICY "tenant_update" ON quality_checks FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_quality_checks" ON quality_checks;
CREATE POLICY "tenant_update_quality_checks" ON quality_checks FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON pick_list_lines;
CREATE POLICY "tenant_delete" ON pick_list_lines FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_pick_list_lines" ON pick_list_lines;
CREATE POLICY "tenant_delete_pick_list_lines" ON pick_list_lines FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON pick_list_lines;
CREATE POLICY "tenant_insert" ON pick_list_lines FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_pick_list_lines" ON pick_list_lines;
CREATE POLICY "tenant_insert_pick_list_lines" ON pick_list_lines FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON pick_list_lines;
CREATE POLICY "tenant_select" ON pick_list_lines FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_pick_list_lines" ON pick_list_lines;
CREATE POLICY "tenant_select_pick_list_lines" ON pick_list_lines FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON pick_list_lines;
CREATE POLICY "tenant_update" ON pick_list_lines FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_pick_list_lines" ON pick_list_lines;
CREATE POLICY "tenant_update_pick_list_lines" ON pick_list_lines FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON product_substitutes;
CREATE POLICY "tenant_delete" ON product_substitutes FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_product_substitutes" ON product_substitutes;
CREATE POLICY "tenant_delete_product_substitutes" ON product_substitutes FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON product_substitutes;
CREATE POLICY "tenant_insert" ON product_substitutes FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_product_substitutes" ON product_substitutes;
CREATE POLICY "tenant_insert_product_substitutes" ON product_substitutes FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON product_substitutes;
CREATE POLICY "tenant_select" ON product_substitutes FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_product_substitutes" ON product_substitutes;
CREATE POLICY "tenant_select_product_substitutes" ON product_substitutes FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON product_substitutes;
CREATE POLICY "tenant_update" ON product_substitutes FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_product_substitutes" ON product_substitutes;
CREATE POLICY "tenant_update_product_substitutes" ON product_substitutes FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON pick_lists;
CREATE POLICY "tenant_delete" ON pick_lists FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_pick_lists" ON pick_lists;
CREATE POLICY "tenant_delete_pick_lists" ON pick_lists FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON pick_lists;
CREATE POLICY "tenant_insert" ON pick_lists FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_pick_lists" ON pick_lists;
CREATE POLICY "tenant_insert_pick_lists" ON pick_lists FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON pick_lists;
CREATE POLICY "tenant_select" ON pick_lists FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_pick_lists" ON pick_lists;
CREATE POLICY "tenant_select_pick_lists" ON pick_lists FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON pick_lists;
CREATE POLICY "tenant_update" ON pick_lists FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_pick_lists" ON pick_lists;
CREATE POLICY "tenant_update_pick_lists" ON pick_lists FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_templates" ON project_task_templates;
CREATE POLICY "tenant_delete_templates" ON project_task_templates FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_templates" ON project_task_templates;
CREATE POLICY "tenant_insert_templates" ON project_task_templates FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_templates" ON project_task_templates;
CREATE POLICY "tenant_select_templates" ON project_task_templates FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_templates" ON project_task_templates;
CREATE POLICY "tenant_update_templates" ON project_task_templates FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "doc_shares_delete" ON module_document_shares;
CREATE POLICY "doc_shares_delete" ON module_document_shares FOR DELETE USING (((tenant_id = current_tenant_id()) AND ((current_user_role() = 'admin'::text) OR (created_by = current_tenant_user_id()))));
DROP POLICY IF EXISTS "doc_shares_insert" ON module_document_shares;
CREATE POLICY "doc_shares_insert" ON module_document_shares FOR INSERT WITH CHECK (((tenant_id = current_tenant_id()) AND (created_by = current_tenant_user_id())));
DROP POLICY IF EXISTS "doc_shares_select" ON module_document_shares;
CREATE POLICY "doc_shares_select" ON module_document_shares FOR SELECT USING (((tenant_id = current_tenant_id()) AND ((current_user_role() = 'admin'::text) OR (created_by = current_tenant_user_id()))));
DROP POLICY IF EXISTS "doc_shares_update" ON module_document_shares;
CREATE POLICY "doc_shares_update" ON module_document_shares FOR UPDATE USING (((tenant_id = current_tenant_id()) AND (created_by = current_tenant_user_id())));
DROP POLICY IF EXISTS "tenant_delete_ifrs_adj" ON ifrs_adjustments;
CREATE POLICY "tenant_delete_ifrs_adj" ON ifrs_adjustments FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_ifrs_adj" ON ifrs_adjustments;
CREATE POLICY "tenant_insert_ifrs_adj" ON ifrs_adjustments FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_ifrs_adj" ON ifrs_adjustments;
CREATE POLICY "tenant_select_ifrs_adj" ON ifrs_adjustments FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_ifrs_adj" ON ifrs_adjustments;
CREATE POLICY "tenant_update_ifrs_adj" ON ifrs_adjustments FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON asset_split_components;
CREATE POLICY "tenant_delete" ON asset_split_components FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_asset_split_components" ON asset_split_components;
CREATE POLICY "tenant_delete_asset_split_components" ON asset_split_components FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON asset_split_components;
CREATE POLICY "tenant_insert" ON asset_split_components FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_asset_split_components" ON asset_split_components;
CREATE POLICY "tenant_insert_asset_split_components" ON asset_split_components FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON asset_split_components;
CREATE POLICY "tenant_select" ON asset_split_components FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_asset_split_components" ON asset_split_components;
CREATE POLICY "tenant_select_asset_split_components" ON asset_split_components FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON asset_split_components;
CREATE POLICY "tenant_update" ON asset_split_components FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_asset_split_components" ON asset_split_components;
CREATE POLICY "tenant_update_asset_split_components" ON asset_split_components FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON budget_commitments;
CREATE POLICY "tenant_delete" ON budget_commitments FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_budget_commitments" ON budget_commitments;
CREATE POLICY "tenant_delete_budget_commitments" ON budget_commitments FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON budget_commitments;
CREATE POLICY "tenant_insert" ON budget_commitments FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_budget_commitments" ON budget_commitments;
CREATE POLICY "tenant_insert_budget_commitments" ON budget_commitments FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON budget_commitments;
CREATE POLICY "tenant_select" ON budget_commitments FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_budget_commitments" ON budget_commitments;
CREATE POLICY "tenant_select_budget_commitments" ON budget_commitments FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON budget_commitments;
CREATE POLICY "tenant_update" ON budget_commitments FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_budget_commitments" ON budget_commitments;
CREATE POLICY "tenant_update_budget_commitments" ON budget_commitments FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON sales_orders;
CREATE POLICY "tenant_delete" ON sales_orders FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_sales_orders" ON sales_orders;
CREATE POLICY "tenant_delete_sales_orders" ON sales_orders FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON sales_orders;
CREATE POLICY "tenant_insert" ON sales_orders FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_sales_orders" ON sales_orders;
CREATE POLICY "tenant_insert_sales_orders" ON sales_orders FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON sales_orders;
CREATE POLICY "tenant_select" ON sales_orders FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_sales_orders" ON sales_orders;
CREATE POLICY "tenant_select_sales_orders" ON sales_orders FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON sales_orders;
CREATE POLICY "tenant_update" ON sales_orders FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_sales_orders" ON sales_orders;
CREATE POLICY "tenant_update_sales_orders" ON sales_orders FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON sales_order_lines;
CREATE POLICY "tenant_delete" ON sales_order_lines FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_sales_order_lines" ON sales_order_lines;
CREATE POLICY "tenant_delete_sales_order_lines" ON sales_order_lines FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON sales_order_lines;
CREATE POLICY "tenant_insert" ON sales_order_lines FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_sales_order_lines" ON sales_order_lines;
CREATE POLICY "tenant_insert_sales_order_lines" ON sales_order_lines FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON sales_order_lines;
CREATE POLICY "tenant_select" ON sales_order_lines FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_sales_order_lines" ON sales_order_lines;
CREATE POLICY "tenant_select_sales_order_lines" ON sales_order_lines FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON sales_order_lines;
CREATE POLICY "tenant_update" ON sales_order_lines FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_sales_order_lines" ON sales_order_lines;
CREATE POLICY "tenant_update_sales_order_lines" ON sales_order_lines FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON delivery_notes;
CREATE POLICY "tenant_delete" ON delivery_notes FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_delivery_notes" ON delivery_notes;
CREATE POLICY "tenant_delete_delivery_notes" ON delivery_notes FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON delivery_notes;
CREATE POLICY "tenant_insert" ON delivery_notes FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_delivery_notes" ON delivery_notes;
CREATE POLICY "tenant_insert_delivery_notes" ON delivery_notes FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON delivery_notes;
CREATE POLICY "tenant_select" ON delivery_notes FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_delivery_notes" ON delivery_notes;
CREATE POLICY "tenant_select_delivery_notes" ON delivery_notes FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON delivery_notes;
CREATE POLICY "tenant_update" ON delivery_notes FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_delivery_notes" ON delivery_notes;
CREATE POLICY "tenant_update_delivery_notes" ON delivery_notes FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON delivery_note_lines;
CREATE POLICY "tenant_delete" ON delivery_note_lines FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_delivery_note_lines" ON delivery_note_lines;
CREATE POLICY "tenant_delete_delivery_note_lines" ON delivery_note_lines FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON delivery_note_lines;
CREATE POLICY "tenant_insert" ON delivery_note_lines FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_delivery_note_lines" ON delivery_note_lines;
CREATE POLICY "tenant_insert_delivery_note_lines" ON delivery_note_lines FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON delivery_note_lines;
CREATE POLICY "tenant_select" ON delivery_note_lines FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_delivery_note_lines" ON delivery_note_lines;
CREATE POLICY "tenant_select_delivery_note_lines" ON delivery_note_lines FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON delivery_note_lines;
CREATE POLICY "tenant_update" ON delivery_note_lines FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_delivery_note_lines" ON delivery_note_lines;
CREATE POLICY "tenant_update_delivery_note_lines" ON delivery_note_lines FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON customer_payments;
CREATE POLICY "tenant_delete" ON customer_payments FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_customer_payments" ON customer_payments;
CREATE POLICY "tenant_delete_customer_payments" ON customer_payments FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON customer_payments;
CREATE POLICY "tenant_insert" ON customer_payments FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_customer_payments" ON customer_payments;
CREATE POLICY "tenant_insert_customer_payments" ON customer_payments FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON customer_payments;
CREATE POLICY "tenant_select" ON customer_payments FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_customer_payments" ON customer_payments;
CREATE POLICY "tenant_select_customer_payments" ON customer_payments FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON customer_payments;
CREATE POLICY "tenant_update" ON customer_payments FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_customer_payments" ON customer_payments;
CREATE POLICY "tenant_update_customer_payments" ON customer_payments FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON purchase_orders;
CREATE POLICY "tenant_delete" ON purchase_orders FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_purchase_orders" ON purchase_orders;
CREATE POLICY "tenant_delete_purchase_orders" ON purchase_orders FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON purchase_orders;
CREATE POLICY "tenant_insert" ON purchase_orders FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_purchase_orders" ON purchase_orders;
CREATE POLICY "tenant_insert_purchase_orders" ON purchase_orders FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON purchase_orders;
CREATE POLICY "tenant_select" ON purchase_orders FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_purchase_orders" ON purchase_orders;
CREATE POLICY "tenant_select_purchase_orders" ON purchase_orders FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON purchase_orders;
CREATE POLICY "tenant_update" ON purchase_orders FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_purchase_orders" ON purchase_orders;
CREATE POLICY "tenant_update_purchase_orders" ON purchase_orders FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_extourne_log" ON extourne_log;
CREATE POLICY "tenant_insert_extourne_log" ON extourne_log FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_extourne_log" ON extourne_log;
CREATE POLICY "tenant_select_extourne_log" ON extourne_log FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_grid_templates" ON grid_templates;
CREATE POLICY "tenant_delete_grid_templates" ON grid_templates FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_grid_templates" ON grid_templates;
CREATE POLICY "tenant_insert_grid_templates" ON grid_templates FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_grid_templates" ON grid_templates;
CREATE POLICY "tenant_select_grid_templates" ON grid_templates FOR SELECT USING (((tenant_id = current_tenant_id()) OR (tenant_id IS NULL)));
DROP POLICY IF EXISTS "tenant_update_grid_templates" ON grid_templates;
CREATE POLICY "tenant_update_grid_templates" ON grid_templates FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_payment_templates_compta" ON payment_templates_compta;
CREATE POLICY "tenant_delete_payment_templates_compta" ON payment_templates_compta FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_payment_templates_compta" ON payment_templates_compta;
CREATE POLICY "tenant_insert_payment_templates_compta" ON payment_templates_compta FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_payment_templates_compta" ON payment_templates_compta;
CREATE POLICY "tenant_select_payment_templates_compta" ON payment_templates_compta FOR SELECT USING (((tenant_id = current_tenant_id()) OR (tenant_id IS NULL)));
DROP POLICY IF EXISTS "tenant_update_payment_templates_compta" ON payment_templates_compta;
CREATE POLICY "tenant_update_payment_templates_compta" ON payment_templates_compta FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_at_rates" ON at_rates;
CREATE POLICY "tenant_delete_at_rates" ON at_rates FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_at_rates" ON at_rates;
CREATE POLICY "tenant_insert_at_rates" ON at_rates FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_at_rates" ON at_rates;
CREATE POLICY "tenant_select_at_rates" ON at_rates FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_at_rates" ON at_rates;
CREATE POLICY "tenant_update_at_rates" ON at_rates FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_analytic_journal_codes" ON analytic_journal_codes;
CREATE POLICY "tenant_delete_analytic_journal_codes" ON analytic_journal_codes FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_analytic_journal_codes" ON analytic_journal_codes;
CREATE POLICY "tenant_insert_analytic_journal_codes" ON analytic_journal_codes FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_analytic_journal_codes" ON analytic_journal_codes;
CREATE POLICY "tenant_select_analytic_journal_codes" ON analytic_journal_codes FOR SELECT USING (((tenant_id = current_tenant_id()) OR (tenant_id IS NULL)));
DROP POLICY IF EXISTS "tenant_update_analytic_journal_codes" ON analytic_journal_codes;
CREATE POLICY "tenant_update_analytic_journal_codes" ON analytic_journal_codes FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON pay_runs;
CREATE POLICY "tenant_delete" ON pay_runs FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_pay_runs" ON pay_runs;
CREATE POLICY "tenant_delete_pay_runs" ON pay_runs FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON pay_runs;
CREATE POLICY "tenant_insert" ON pay_runs FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_pay_runs" ON pay_runs;
CREATE POLICY "tenant_insert_pay_runs" ON pay_runs FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON pay_runs;
CREATE POLICY "tenant_select" ON pay_runs FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_pay_runs" ON pay_runs;
CREATE POLICY "tenant_select_pay_runs" ON pay_runs FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON pay_runs;
CREATE POLICY "tenant_update" ON pay_runs FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_pay_runs" ON pay_runs;
CREATE POLICY "tenant_update_pay_runs" ON pay_runs FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_product_grid_combinations" ON product_grid_combinations;
CREATE POLICY "tenant_delete_product_grid_combinations" ON product_grid_combinations FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_product_grid_combinations" ON product_grid_combinations;
CREATE POLICY "tenant_insert_product_grid_combinations" ON product_grid_combinations FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_product_grid_combinations" ON product_grid_combinations;
CREATE POLICY "tenant_select_product_grid_combinations" ON product_grid_combinations FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_product_grid_combinations" ON product_grid_combinations;
CREATE POLICY "tenant_update_product_grid_combinations" ON product_grid_combinations FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "notif_prefs_insert" ON notification_preferences;
CREATE POLICY "notif_prefs_insert" ON notification_preferences FOR INSERT WITH CHECK ((tenant_id IN ( SELECT tu.tenant_id
   FROM tenant_users tu
  WHERE ((tu.auth_id = auth.uid()) AND (tu.status = 'active'::text)))));
DROP POLICY IF EXISTS "notif_prefs_select" ON notification_preferences;
CREATE POLICY "notif_prefs_select" ON notification_preferences FOR SELECT USING ((tenant_id IN ( SELECT tu.tenant_id
   FROM tenant_users tu
  WHERE ((tu.auth_id = auth.uid()) AND (tu.status = 'active'::text)))));
DROP POLICY IF EXISTS "notif_prefs_update" ON notification_preferences;
CREATE POLICY "notif_prefs_update" ON notification_preferences FOR UPDATE USING ((tenant_id IN ( SELECT tu.tenant_id
   FROM tenant_users tu
  WHERE ((tu.auth_id = auth.uid()) AND (tu.status = 'active'::text)))));
DROP POLICY IF EXISTS "tenant_delete_crm_opportunities" ON crm_opportunities;
CREATE POLICY "tenant_delete_crm_opportunities" ON crm_opportunities FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_crm_opportunities" ON crm_opportunities;
CREATE POLICY "tenant_insert_crm_opportunities" ON crm_opportunities FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_crm_opportunities" ON crm_opportunities;
CREATE POLICY "tenant_select_crm_opportunities" ON crm_opportunities FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_crm_opportunities" ON crm_opportunities;
CREATE POLICY "tenant_update_crm_opportunities" ON crm_opportunities FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON fiscal_periods;
CREATE POLICY "tenant_delete" ON fiscal_periods FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_fiscal_periods" ON fiscal_periods;
CREATE POLICY "tenant_delete_fiscal_periods" ON fiscal_periods FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON fiscal_periods;
CREATE POLICY "tenant_insert" ON fiscal_periods FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_fiscal_periods" ON fiscal_periods;
CREATE POLICY "tenant_insert_fiscal_periods" ON fiscal_periods FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON fiscal_periods;
CREATE POLICY "tenant_select" ON fiscal_periods FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_fiscal_periods" ON fiscal_periods;
CREATE POLICY "tenant_select_fiscal_periods" ON fiscal_periods FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON fiscal_periods;
CREATE POLICY "tenant_update" ON fiscal_periods FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_fiscal_periods" ON fiscal_periods;
CREATE POLICY "tenant_update_fiscal_periods" ON fiscal_periods FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_supplier_delivery_schedules" ON supplier_delivery_schedules;
CREATE POLICY "tenant_delete_supplier_delivery_schedules" ON supplier_delivery_schedules FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_supplier_delivery_schedules" ON supplier_delivery_schedules;
CREATE POLICY "tenant_insert_supplier_delivery_schedules" ON supplier_delivery_schedules FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_supplier_delivery_schedules" ON supplier_delivery_schedules;
CREATE POLICY "tenant_select_supplier_delivery_schedules" ON supplier_delivery_schedules FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_supplier_delivery_schedules" ON supplier_delivery_schedules;
CREATE POLICY "tenant_update_supplier_delivery_schedules" ON supplier_delivery_schedules FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON fiscal_years;
CREATE POLICY "tenant_delete" ON fiscal_years FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_fiscal_years" ON fiscal_years;
CREATE POLICY "tenant_delete_fiscal_years" ON fiscal_years FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON fiscal_years;
CREATE POLICY "tenant_insert" ON fiscal_years FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_fiscal_years" ON fiscal_years;
CREATE POLICY "tenant_insert_fiscal_years" ON fiscal_years FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON fiscal_years;
CREATE POLICY "tenant_select" ON fiscal_years FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_fiscal_years" ON fiscal_years;
CREATE POLICY "tenant_select_fiscal_years" ON fiscal_years FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON fiscal_years;
CREATE POLICY "tenant_update" ON fiscal_years FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_fiscal_years" ON fiscal_years;
CREATE POLICY "tenant_update_fiscal_years" ON fiscal_years FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON invoice_lines;
CREATE POLICY "tenant_delete" ON invoice_lines FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_invoice_lines" ON invoice_lines;
CREATE POLICY "tenant_delete_invoice_lines" ON invoice_lines FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON invoice_lines;
CREATE POLICY "tenant_insert" ON invoice_lines FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_invoice_lines" ON invoice_lines;
CREATE POLICY "tenant_insert_invoice_lines" ON invoice_lines FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON invoice_lines;
CREATE POLICY "tenant_select" ON invoice_lines FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_invoice_lines" ON invoice_lines;
CREATE POLICY "tenant_select_invoice_lines" ON invoice_lines FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON invoice_lines;
CREATE POLICY "tenant_update" ON invoice_lines FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_invoice_lines" ON invoice_lines;
CREATE POLICY "tenant_update_invoice_lines" ON invoice_lines FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "email_queue_insert" ON notification_email_queue;
CREATE POLICY "email_queue_insert" ON notification_email_queue FOR INSERT WITH CHECK ((tenant_id IN ( SELECT tu.tenant_id
   FROM tenant_users tu
  WHERE ((tu.auth_id = auth.uid()) AND (tu.status = 'active'::text)))));
DROP POLICY IF EXISTS "email_queue_select" ON notification_email_queue;
CREATE POLICY "email_queue_select" ON notification_email_queue FOR SELECT USING ((tenant_id IN ( SELECT tu.tenant_id
   FROM tenant_users tu
  WHERE ((tu.auth_id = auth.uid()) AND (tu.status = 'active'::text) AND (tu.role = 'admin'::text)))));
DROP POLICY IF EXISTS "tenant_delete" ON invoices;
CREATE POLICY "tenant_delete" ON invoices FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_invoices" ON invoices;
CREATE POLICY "tenant_delete_invoices" ON invoices FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON invoices;
CREATE POLICY "tenant_insert" ON invoices FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_invoices" ON invoices;
CREATE POLICY "tenant_insert_invoices" ON invoices FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON invoices;
CREATE POLICY "tenant_select" ON invoices FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_invoices" ON invoices;
CREATE POLICY "tenant_select_invoices" ON invoices FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON invoices;
CREATE POLICY "tenant_update" ON invoices FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_invoices" ON invoices;
CREATE POLICY "tenant_update_invoices" ON invoices FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON journal_entries;
CREATE POLICY "tenant_delete" ON journal_entries FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_journal_entries" ON journal_entries;
CREATE POLICY "tenant_delete_journal_entries" ON journal_entries FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON journal_entries;
CREATE POLICY "tenant_insert" ON journal_entries FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_journal_entries" ON journal_entries;
CREATE POLICY "tenant_insert_journal_entries" ON journal_entries FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON journal_entries;
CREATE POLICY "tenant_select" ON journal_entries FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_journal_entries" ON journal_entries;
CREATE POLICY "tenant_select_journal_entries" ON journal_entries FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON journal_entries;
CREATE POLICY "tenant_update" ON journal_entries FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_journal_entries" ON journal_entries;
CREATE POLICY "tenant_update_journal_entries" ON journal_entries FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON credit_note_lines;
CREATE POLICY "tenant_delete" ON credit_note_lines FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_credit_note_lines" ON credit_note_lines;
CREATE POLICY "tenant_delete_credit_note_lines" ON credit_note_lines FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON credit_note_lines;
CREATE POLICY "tenant_insert" ON credit_note_lines FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_credit_note_lines" ON credit_note_lines;
CREATE POLICY "tenant_insert_credit_note_lines" ON credit_note_lines FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON credit_note_lines;
CREATE POLICY "tenant_select" ON credit_note_lines FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_credit_note_lines" ON credit_note_lines;
CREATE POLICY "tenant_select_credit_note_lines" ON credit_note_lines FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON credit_note_lines;
CREATE POLICY "tenant_update" ON credit_note_lines FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_credit_note_lines" ON credit_note_lines;
CREATE POLICY "tenant_update_credit_note_lines" ON credit_note_lines FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "project_docs_tenant_delete" ON project_docs;
CREATE POLICY "project_docs_tenant_delete" ON project_docs FOR DELETE USING ((tenant_id = ( SELECT tenants.id
   FROM tenants
 LIMIT 1)));
DROP POLICY IF EXISTS "project_docs_tenant_insert" ON project_docs;
CREATE POLICY "project_docs_tenant_insert" ON project_docs FOR INSERT WITH CHECK ((tenant_id = ( SELECT tenants.id
   FROM tenants
 LIMIT 1)));
DROP POLICY IF EXISTS "project_docs_tenant_select" ON project_docs;
CREATE POLICY "project_docs_tenant_select" ON project_docs FOR SELECT USING ((tenant_id = ( SELECT tenants.id
   FROM tenants
 LIMIT 1)));
DROP POLICY IF EXISTS "project_docs_tenant_update" ON project_docs;
CREATE POLICY "project_docs_tenant_update" ON project_docs FOR UPDATE USING ((tenant_id = ( SELECT tenants.id
   FROM tenants
 LIMIT 1))) WITH CHECK ((tenant_id = ( SELECT tenants.id
   FROM tenants
 LIMIT 1)));
DROP POLICY IF EXISTS "tenant_delete" ON pay_slips;
CREATE POLICY "tenant_delete" ON pay_slips FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_pay_slips" ON pay_slips;
CREATE POLICY "tenant_delete_pay_slips" ON pay_slips FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON pay_slips;
CREATE POLICY "tenant_insert" ON pay_slips FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_pay_slips" ON pay_slips;
CREATE POLICY "tenant_insert_pay_slips" ON pay_slips FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON pay_slips;
CREATE POLICY "tenant_select" ON pay_slips FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_pay_slips" ON pay_slips;
CREATE POLICY "tenant_select_pay_slips" ON pay_slips FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON pay_slips;
CREATE POLICY "tenant_update" ON pay_slips FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_pay_slips" ON pay_slips;
CREATE POLICY "tenant_update_pay_slips" ON pay_slips FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON routings;
CREATE POLICY "tenant_delete" ON routings FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_routings" ON routings;
CREATE POLICY "tenant_delete_routings" ON routings FOR DELETE USING (((tenant_id = current_tenant_id()) AND can_perform('routings'::text, 'delete'::text)));
DROP POLICY IF EXISTS "tenant_insert" ON routings;
CREATE POLICY "tenant_insert" ON routings FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_routings" ON routings;
CREATE POLICY "tenant_insert_routings" ON routings FOR INSERT WITH CHECK (((tenant_id = current_tenant_id()) AND can_perform('routings'::text, 'insert'::text)));
DROP POLICY IF EXISTS "tenant_select" ON routings;
CREATE POLICY "tenant_select" ON routings FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_routings" ON routings;
CREATE POLICY "tenant_select_routings" ON routings FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON routings;
CREATE POLICY "tenant_update" ON routings FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_routings" ON routings;
CREATE POLICY "tenant_update_routings" ON routings FOR UPDATE USING (((tenant_id = current_tenant_id()) AND can_perform('routings'::text, 'update'::text))) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON work_centers;
CREATE POLICY "tenant_delete" ON work_centers FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_work_centers" ON work_centers;
CREATE POLICY "tenant_delete_work_centers" ON work_centers FOR DELETE USING (((tenant_id = current_tenant_id()) AND can_perform('work_centers'::text, 'delete'::text)));
DROP POLICY IF EXISTS "tenant_insert" ON work_centers;
CREATE POLICY "tenant_insert" ON work_centers FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_work_centers" ON work_centers;
CREATE POLICY "tenant_insert_work_centers" ON work_centers FOR INSERT WITH CHECK (((tenant_id = current_tenant_id()) AND can_perform('work_centers'::text, 'insert'::text)));
DROP POLICY IF EXISTS "tenant_select" ON work_centers;
CREATE POLICY "tenant_select" ON work_centers FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_work_centers" ON work_centers;
CREATE POLICY "tenant_select_work_centers" ON work_centers FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON work_centers;
CREATE POLICY "tenant_update" ON work_centers FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_work_centers" ON work_centers;
CREATE POLICY "tenant_update_work_centers" ON work_centers FOR UPDATE USING (((tenant_id = current_tenant_id()) AND can_perform('work_centers'::text, 'update'::text))) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON machines;
CREATE POLICY "tenant_delete" ON machines FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_machines" ON machines;
CREATE POLICY "tenant_delete_machines" ON machines FOR DELETE USING (((tenant_id = current_tenant_id()) AND can_perform('machines'::text, 'delete'::text)));
DROP POLICY IF EXISTS "tenant_insert" ON machines;
CREATE POLICY "tenant_insert" ON machines FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_machines" ON machines;
CREATE POLICY "tenant_insert_machines" ON machines FOR INSERT WITH CHECK (((tenant_id = current_tenant_id()) AND can_perform('machines'::text, 'insert'::text)));
DROP POLICY IF EXISTS "tenant_select" ON machines;
CREATE POLICY "tenant_select" ON machines FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_machines" ON machines;
CREATE POLICY "tenant_select_machines" ON machines FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON machines;
CREATE POLICY "tenant_update" ON machines FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_machines" ON machines;
CREATE POLICY "tenant_update_machines" ON machines FOR UPDATE USING (((tenant_id = current_tenant_id()) AND can_perform('machines'::text, 'update'::text))) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON purchase_invoice_lines;
CREATE POLICY "tenant_delete" ON purchase_invoice_lines FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_purchase_invoice_lines" ON purchase_invoice_lines;
CREATE POLICY "tenant_delete_purchase_invoice_lines" ON purchase_invoice_lines FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON purchase_invoice_lines;
CREATE POLICY "tenant_insert" ON purchase_invoice_lines FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_purchase_invoice_lines" ON purchase_invoice_lines;
CREATE POLICY "tenant_insert_purchase_invoice_lines" ON purchase_invoice_lines FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON purchase_invoice_lines;
CREATE POLICY "tenant_select" ON purchase_invoice_lines FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_purchase_invoice_lines" ON purchase_invoice_lines;
CREATE POLICY "tenant_select_purchase_invoice_lines" ON purchase_invoice_lines FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON purchase_invoice_lines;
CREATE POLICY "tenant_update" ON purchase_invoice_lines FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_purchase_invoice_lines" ON purchase_invoice_lines;
CREATE POLICY "tenant_update_purchase_invoice_lines" ON purchase_invoice_lines FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON toolings;
CREATE POLICY "tenant_delete" ON toolings FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_toolings" ON toolings;
CREATE POLICY "tenant_delete_toolings" ON toolings FOR DELETE USING (((tenant_id = current_tenant_id()) AND can_perform('toolings'::text, 'delete'::text)));
DROP POLICY IF EXISTS "tenant_insert" ON toolings;
CREATE POLICY "tenant_insert" ON toolings FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_toolings" ON toolings;
CREATE POLICY "tenant_insert_toolings" ON toolings FOR INSERT WITH CHECK (((tenant_id = current_tenant_id()) AND can_perform('toolings'::text, 'insert'::text)));
DROP POLICY IF EXISTS "tenant_select" ON toolings;
CREATE POLICY "tenant_select" ON toolings FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_toolings" ON toolings;
CREATE POLICY "tenant_select_toolings" ON toolings FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON toolings;
CREATE POLICY "tenant_update" ON toolings FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_toolings" ON toolings;
CREATE POLICY "tenant_update_toolings" ON toolings FOR UPDATE USING (((tenant_id = current_tenant_id()) AND can_perform('toolings'::text, 'update'::text))) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON purchase_invoices;
CREATE POLICY "tenant_delete" ON purchase_invoices FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_purchase_invoices" ON purchase_invoices;
CREATE POLICY "tenant_delete_purchase_invoices" ON purchase_invoices FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON purchase_invoices;
CREATE POLICY "tenant_insert" ON purchase_invoices FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_purchase_invoices" ON purchase_invoices;
CREATE POLICY "tenant_insert_purchase_invoices" ON purchase_invoices FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON purchase_invoices;
CREATE POLICY "tenant_select" ON purchase_invoices FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_purchase_invoices" ON purchase_invoices;
CREATE POLICY "tenant_select_purchase_invoices" ON purchase_invoices FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON purchase_invoices;
CREATE POLICY "tenant_update" ON purchase_invoices FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_purchase_invoices" ON purchase_invoices;
CREATE POLICY "tenant_update_purchase_invoices" ON purchase_invoices FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON quote_lines;
CREATE POLICY "tenant_delete" ON quote_lines FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_quote_lines" ON quote_lines;
CREATE POLICY "tenant_delete_quote_lines" ON quote_lines FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON quote_lines;
CREATE POLICY "tenant_insert" ON quote_lines FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_quote_lines" ON quote_lines;
CREATE POLICY "tenant_insert_quote_lines" ON quote_lines FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON quote_lines;
CREATE POLICY "tenant_select" ON quote_lines FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_quote_lines" ON quote_lines;
CREATE POLICY "tenant_select_quote_lines" ON quote_lines FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON quote_lines;
CREATE POLICY "tenant_update" ON quote_lines FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_quote_lines" ON quote_lines;
CREATE POLICY "tenant_update_quote_lines" ON quote_lines FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON purchase_credit_lines;
CREATE POLICY "tenant_delete" ON purchase_credit_lines FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_purchase_credit_lines" ON purchase_credit_lines;
CREATE POLICY "tenant_delete_purchase_credit_lines" ON purchase_credit_lines FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON purchase_credit_lines;
CREATE POLICY "tenant_insert" ON purchase_credit_lines FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_purchase_credit_lines" ON purchase_credit_lines;
CREATE POLICY "tenant_insert_purchase_credit_lines" ON purchase_credit_lines FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON purchase_credit_lines;
CREATE POLICY "tenant_select" ON purchase_credit_lines FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_purchase_credit_lines" ON purchase_credit_lines;
CREATE POLICY "tenant_select_purchase_credit_lines" ON purchase_credit_lines FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON purchase_credit_lines;
CREATE POLICY "tenant_update" ON purchase_credit_lines FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_purchase_credit_lines" ON purchase_credit_lines;
CREATE POLICY "tenant_update_purchase_credit_lines" ON purchase_credit_lines FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON quotes;
CREATE POLICY "tenant_delete" ON quotes FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_quotes" ON quotes;
CREATE POLICY "tenant_delete_quotes" ON quotes FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON quotes;
CREATE POLICY "tenant_insert" ON quotes FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_quotes" ON quotes;
CREATE POLICY "tenant_insert_quotes" ON quotes FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON quotes;
CREATE POLICY "tenant_select" ON quotes FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_quotes" ON quotes;
CREATE POLICY "tenant_select_quotes" ON quotes FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON quotes;
CREATE POLICY "tenant_update" ON quotes FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_quotes" ON quotes;
CREATE POLICY "tenant_update_quotes" ON quotes FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_crm_campaign_recipients" ON crm_campaign_recipients;
CREATE POLICY "tenant_delete_crm_campaign_recipients" ON crm_campaign_recipients FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_crm_campaign_recipients" ON crm_campaign_recipients;
CREATE POLICY "tenant_insert_crm_campaign_recipients" ON crm_campaign_recipients FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_crm_campaign_recipients" ON crm_campaign_recipients;
CREATE POLICY "tenant_select_crm_campaign_recipients" ON crm_campaign_recipients FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_crm_campaign_recipients" ON crm_campaign_recipients;
CREATE POLICY "tenant_update_crm_campaign_recipients" ON crm_campaign_recipients FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON planning_slots;
CREATE POLICY "tenant_delete" ON planning_slots FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_planning_slots" ON planning_slots;
CREATE POLICY "tenant_delete_planning_slots" ON planning_slots FOR DELETE USING (((tenant_id = current_tenant_id()) AND can_perform('planning_slots'::text, 'delete'::text)));
DROP POLICY IF EXISTS "tenant_insert" ON planning_slots;
CREATE POLICY "tenant_insert" ON planning_slots FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_planning_slots" ON planning_slots;
CREATE POLICY "tenant_insert_planning_slots" ON planning_slots FOR INSERT WITH CHECK (((tenant_id = current_tenant_id()) AND can_perform('planning_slots'::text, 'insert'::text)));
DROP POLICY IF EXISTS "tenant_select" ON planning_slots;
CREATE POLICY "tenant_select" ON planning_slots FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_planning_slots" ON planning_slots;
CREATE POLICY "tenant_select_planning_slots" ON planning_slots FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON planning_slots;
CREATE POLICY "tenant_update" ON planning_slots FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_planning_slots" ON planning_slots;
CREATE POLICY "tenant_update_planning_slots" ON planning_slots FOR UPDATE USING (((tenant_id = current_tenant_id()) AND can_perform('planning_slots'::text, 'update'::text))) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON career_history;
CREATE POLICY "tenant_delete" ON career_history FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_career_history" ON career_history;
CREATE POLICY "tenant_delete_career_history" ON career_history FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON career_history;
CREATE POLICY "tenant_insert" ON career_history FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_career_history" ON career_history;
CREATE POLICY "tenant_insert_career_history" ON career_history FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON career_history;
CREATE POLICY "tenant_select" ON career_history FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_career_history" ON career_history;
CREATE POLICY "tenant_select_career_history" ON career_history FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON career_history;
CREATE POLICY "tenant_update" ON career_history FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_career_history" ON career_history;
CREATE POLICY "tenant_update_career_history" ON career_history FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON expense_report_lines;
CREATE POLICY "tenant_delete" ON expense_report_lines FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_expense_report_lines" ON expense_report_lines;
CREATE POLICY "tenant_delete_expense_report_lines" ON expense_report_lines FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON expense_report_lines;
CREATE POLICY "tenant_insert" ON expense_report_lines FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_expense_report_lines" ON expense_report_lines;
CREATE POLICY "tenant_insert_expense_report_lines" ON expense_report_lines FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON expense_report_lines;
CREATE POLICY "tenant_select" ON expense_report_lines FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_expense_report_lines" ON expense_report_lines;
CREATE POLICY "tenant_select_expense_report_lines" ON expense_report_lines FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON expense_report_lines;
CREATE POLICY "tenant_update" ON expense_report_lines FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_expense_report_lines" ON expense_report_lines;
CREATE POLICY "tenant_update_expense_report_lines" ON expense_report_lines FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON expense_reports;
CREATE POLICY "tenant_delete" ON expense_reports FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_expense_reports" ON expense_reports;
CREATE POLICY "tenant_delete_expense_reports" ON expense_reports FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON expense_reports;
CREATE POLICY "tenant_insert" ON expense_reports FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_expense_reports" ON expense_reports;
CREATE POLICY "tenant_insert_expense_reports" ON expense_reports FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON expense_reports;
CREATE POLICY "tenant_select" ON expense_reports FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_expense_reports" ON expense_reports;
CREATE POLICY "tenant_select_expense_reports" ON expense_reports FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON expense_reports;
CREATE POLICY "tenant_update" ON expense_reports FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_expense_reports" ON expense_reports;
CREATE POLICY "tenant_update_expense_reports" ON expense_reports FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON product_equivalences;
CREATE POLICY "tenant_delete" ON product_equivalences FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_product_equivalences" ON product_equivalences;
CREATE POLICY "tenant_delete_product_equivalences" ON product_equivalences FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON product_equivalences;
CREATE POLICY "tenant_insert" ON product_equivalences FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_product_equivalences" ON product_equivalences;
CREATE POLICY "tenant_insert_product_equivalences" ON product_equivalences FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON product_equivalences;
CREATE POLICY "tenant_select" ON product_equivalences FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_product_equivalences" ON product_equivalences;
CREATE POLICY "tenant_select_product_equivalences" ON product_equivalences FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON product_equivalences;
CREATE POLICY "tenant_update" ON product_equivalences FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_product_equivalences" ON product_equivalences;
CREATE POLICY "tenant_update_product_equivalences" ON product_equivalences FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_rgpd_requests" ON rgpd_requests;
CREATE POLICY "tenant_insert_rgpd_requests" ON rgpd_requests FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_rgpd_requests" ON rgpd_requests;
CREATE POLICY "tenant_select_rgpd_requests" ON rgpd_requests FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_rgpd_requests" ON rgpd_requests;
CREATE POLICY "tenant_update_rgpd_requests" ON rgpd_requests FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "own_select_users" ON users;
CREATE POLICY "own_select_users" ON users FOR SELECT USING ((auth_id = auth.uid()));
DROP POLICY IF EXISTS "own_update_users" ON users;
CREATE POLICY "own_update_users" ON users FOR UPDATE USING ((auth_id = auth.uid())) WITH CHECK ((auth_id = auth.uid()));
DROP POLICY IF EXISTS "tenant_delete_users" ON users;
CREATE POLICY "tenant_delete_users" ON users FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_users" ON users;
CREATE POLICY "tenant_insert_users" ON users FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_users" ON users;
CREATE POLICY "tenant_select_users" ON users FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_users" ON users;
CREATE POLICY "tenant_update_users" ON users FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_employee_exit_processes" ON employee_exit_processes;
CREATE POLICY "tenant_delete_employee_exit_processes" ON employee_exit_processes FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_employee_exit_processes" ON employee_exit_processes;
CREATE POLICY "tenant_insert_employee_exit_processes" ON employee_exit_processes FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_employee_exit_processes" ON employee_exit_processes;
CREATE POLICY "tenant_select_employee_exit_processes" ON employee_exit_processes FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_employee_exit_processes" ON employee_exit_processes;
CREATE POLICY "tenant_update_employee_exit_processes" ON employee_exit_processes FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON vat_returns;
CREATE POLICY "tenant_delete" ON vat_returns FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_vat_returns" ON vat_returns;
CREATE POLICY "tenant_delete_vat_returns" ON vat_returns FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON vat_returns;
CREATE POLICY "tenant_insert" ON vat_returns FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_vat_returns" ON vat_returns;
CREATE POLICY "tenant_insert_vat_returns" ON vat_returns FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON vat_returns;
CREATE POLICY "tenant_select" ON vat_returns FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_vat_returns" ON vat_returns;
CREATE POLICY "tenant_select_vat_returns" ON vat_returns FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON vat_returns;
CREATE POLICY "tenant_update" ON vat_returns FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_vat_returns" ON vat_returns;
CREATE POLICY "tenant_update_vat_returns" ON vat_returns FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON warehouses;
CREATE POLICY "tenant_delete" ON warehouses FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_warehouses" ON warehouses;
CREATE POLICY "tenant_delete_warehouses" ON warehouses FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON warehouses;
CREATE POLICY "tenant_insert" ON warehouses FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_warehouses" ON warehouses;
CREATE POLICY "tenant_insert_warehouses" ON warehouses FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON warehouses;
CREATE POLICY "tenant_select" ON warehouses FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_warehouses" ON warehouses;
CREATE POLICY "tenant_select_warehouses" ON warehouses FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON warehouses;
CREATE POLICY "tenant_update" ON warehouses FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_warehouses" ON warehouses;
CREATE POLICY "tenant_update_warehouses" ON warehouses FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON delivery_schedules;
CREATE POLICY "tenant_delete" ON delivery_schedules FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_delivery_schedules" ON delivery_schedules;
CREATE POLICY "tenant_delete_delivery_schedules" ON delivery_schedules FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON delivery_schedules;
CREATE POLICY "tenant_insert" ON delivery_schedules FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_delivery_schedules" ON delivery_schedules;
CREATE POLICY "tenant_insert_delivery_schedules" ON delivery_schedules FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON delivery_schedules;
CREATE POLICY "tenant_select" ON delivery_schedules FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_delivery_schedules" ON delivery_schedules;
CREATE POLICY "tenant_select_delivery_schedules" ON delivery_schedules FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON delivery_schedules;
CREATE POLICY "tenant_update" ON delivery_schedules FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_delivery_schedules" ON delivery_schedules;
CREATE POLICY "tenant_update_delivery_schedules" ON delivery_schedules FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_crm_campaigns" ON crm_campaigns;
CREATE POLICY "tenant_delete_crm_campaigns" ON crm_campaigns FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_crm_campaigns" ON crm_campaigns;
CREATE POLICY "tenant_insert_crm_campaigns" ON crm_campaigns FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_crm_campaigns" ON crm_campaigns;
CREATE POLICY "tenant_select_crm_campaigns" ON crm_campaigns FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_crm_campaigns" ON crm_campaigns;
CREATE POLICY "tenant_update_crm_campaigns" ON crm_campaigns FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON recurring_invoice_templates;
CREATE POLICY "tenant_delete" ON recurring_invoice_templates FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_recurring_invoice_templates" ON recurring_invoice_templates;
CREATE POLICY "tenant_delete_recurring_invoice_templates" ON recurring_invoice_templates FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON recurring_invoice_templates;
CREATE POLICY "tenant_insert" ON recurring_invoice_templates FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_recurring_invoice_templates" ON recurring_invoice_templates;
CREATE POLICY "tenant_insert_recurring_invoice_templates" ON recurring_invoice_templates FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON recurring_invoice_templates;
CREATE POLICY "tenant_select" ON recurring_invoice_templates FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_recurring_invoice_templates" ON recurring_invoice_templates;
CREATE POLICY "tenant_select_recurring_invoice_templates" ON recurring_invoice_templates FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON recurring_invoice_templates;
CREATE POLICY "tenant_update" ON recurring_invoice_templates FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_recurring_invoice_templates" ON recurring_invoice_templates;
CREATE POLICY "tenant_update_recurring_invoice_templates" ON recurring_invoice_templates FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON treasury_transfers;
CREATE POLICY "tenant_delete" ON treasury_transfers FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_treasury_transfers" ON treasury_transfers;
CREATE POLICY "tenant_delete_treasury_transfers" ON treasury_transfers FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON treasury_transfers;
CREATE POLICY "tenant_insert" ON treasury_transfers FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_treasury_transfers" ON treasury_transfers;
CREATE POLICY "tenant_insert_treasury_transfers" ON treasury_transfers FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON treasury_transfers;
CREATE POLICY "tenant_select" ON treasury_transfers FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_treasury_transfers" ON treasury_transfers;
CREATE POLICY "tenant_select_treasury_transfers" ON treasury_transfers FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON treasury_transfers;
CREATE POLICY "tenant_update" ON treasury_transfers FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_treasury_transfers" ON treasury_transfers;
CREATE POLICY "tenant_update_treasury_transfers" ON treasury_transfers FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_honorarium_records" ON honorarium_records;
CREATE POLICY "tenant_delete_honorarium_records" ON honorarium_records FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_honorarium_records" ON honorarium_records;
CREATE POLICY "tenant_insert_honorarium_records" ON honorarium_records FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_honorarium_records" ON honorarium_records;
CREATE POLICY "tenant_select_honorarium_records" ON honorarium_records FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_honorarium_records" ON honorarium_records;
CREATE POLICY "tenant_update_honorarium_records" ON honorarium_records FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_employee_documents" ON employee_documents;
CREATE POLICY "tenant_delete_employee_documents" ON employee_documents FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_employee_documents" ON employee_documents;
CREATE POLICY "tenant_insert_employee_documents" ON employee_documents FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_employee_documents" ON employee_documents;
CREATE POLICY "tenant_select_employee_documents" ON employee_documents FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_employee_documents" ON employee_documents;
CREATE POLICY "tenant_update_employee_documents" ON employee_documents FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_document_transformations" ON document_transformations;
CREATE POLICY "tenant_delete_document_transformations" ON document_transformations FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_document_transformations" ON document_transformations;
CREATE POLICY "tenant_insert_document_transformations" ON document_transformations FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_document_transformations" ON document_transformations;
CREATE POLICY "tenant_select_document_transformations" ON document_transformations FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_document_transformations" ON document_transformations;
CREATE POLICY "tenant_update_document_transformations" ON document_transformations FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_employee_objectives" ON employee_objectives;
CREATE POLICY "tenant_delete_employee_objectives" ON employee_objectives FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_employee_objectives" ON employee_objectives;
CREATE POLICY "tenant_insert_employee_objectives" ON employee_objectives FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_employee_objectives" ON employee_objectives;
CREATE POLICY "tenant_select_employee_objectives" ON employee_objectives FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_employee_objectives" ON employee_objectives;
CREATE POLICY "tenant_update_employee_objectives" ON employee_objectives FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON credit_lines;
CREATE POLICY "tenant_delete" ON credit_lines FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_credit_lines" ON credit_lines;
CREATE POLICY "tenant_delete_credit_lines" ON credit_lines FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON credit_lines;
CREATE POLICY "tenant_insert" ON credit_lines FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_credit_lines" ON credit_lines;
CREATE POLICY "tenant_insert_credit_lines" ON credit_lines FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON credit_lines;
CREATE POLICY "tenant_select" ON credit_lines FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_credit_lines" ON credit_lines;
CREATE POLICY "tenant_select_credit_lines" ON credit_lines FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON credit_lines;
CREATE POLICY "tenant_update" ON credit_lines FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_credit_lines" ON credit_lines;
CREATE POLICY "tenant_update_credit_lines" ON credit_lines FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_rh_knowledge_base" ON rh_knowledge_base;
CREATE POLICY "tenant_delete_rh_knowledge_base" ON rh_knowledge_base FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_rh_knowledge_base" ON rh_knowledge_base;
CREATE POLICY "tenant_insert_rh_knowledge_base" ON rh_knowledge_base FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_rh_knowledge_base" ON rh_knowledge_base;
CREATE POLICY "tenant_select_rh_knowledge_base" ON rh_knowledge_base FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_rh_knowledge_base" ON rh_knowledge_base;
CREATE POLICY "tenant_update_rh_knowledge_base" ON rh_knowledge_base FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_pos_tickets" ON pos_tickets;
CREATE POLICY "tenant_delete_pos_tickets" ON pos_tickets FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_pos_tickets" ON pos_tickets;
CREATE POLICY "tenant_insert_pos_tickets" ON pos_tickets FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_pos_tickets" ON pos_tickets;
CREATE POLICY "tenant_select_pos_tickets" ON pos_tickets FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_pos_tickets" ON pos_tickets;
CREATE POLICY "tenant_update_pos_tickets" ON pos_tickets FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON investments;
CREATE POLICY "tenant_delete" ON investments FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_investments" ON investments;
CREATE POLICY "tenant_delete_investments" ON investments FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON investments;
CREATE POLICY "tenant_insert" ON investments FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_investments" ON investments;
CREATE POLICY "tenant_insert_investments" ON investments FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON investments;
CREATE POLICY "tenant_select" ON investments FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_investments" ON investments;
CREATE POLICY "tenant_select_investments" ON investments FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON investments;
CREATE POLICY "tenant_update" ON investments FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_investments" ON investments;
CREATE POLICY "tenant_update_investments" ON investments FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON workflows;
CREATE POLICY "tenant_delete" ON workflows FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_workflows" ON workflows;
CREATE POLICY "tenant_delete_workflows" ON workflows FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON workflows;
CREATE POLICY "tenant_insert" ON workflows FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_workflows" ON workflows;
CREATE POLICY "tenant_insert_workflows" ON workflows FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON workflows;
CREATE POLICY "tenant_select" ON workflows FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_workflows" ON workflows;
CREATE POLICY "tenant_select_workflows" ON workflows FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON workflows;
CREATE POLICY "tenant_update" ON workflows FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_workflows" ON workflows;
CREATE POLICY "tenant_update_workflows" ON workflows FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_exchange_gain_loss_entries" ON exchange_gain_loss_entries;
CREATE POLICY "tenant_delete_exchange_gain_loss_entries" ON exchange_gain_loss_entries FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_exchange_gain_loss_entries" ON exchange_gain_loss_entries;
CREATE POLICY "tenant_insert_exchange_gain_loss_entries" ON exchange_gain_loss_entries FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_exchange_gain_loss_entries" ON exchange_gain_loss_entries;
CREATE POLICY "tenant_select_exchange_gain_loss_entries" ON exchange_gain_loss_entries FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_exchange_gain_loss_entries" ON exchange_gain_loss_entries;
CREATE POLICY "tenant_update_exchange_gain_loss_entries" ON exchange_gain_loss_entries FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_payroll_variable_elements" ON payroll_variable_elements;
CREATE POLICY "tenant_delete_payroll_variable_elements" ON payroll_variable_elements FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_payroll_variable_elements" ON payroll_variable_elements;
CREATE POLICY "tenant_insert_payroll_variable_elements" ON payroll_variable_elements FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_payroll_variable_elements" ON payroll_variable_elements;
CREATE POLICY "tenant_select_payroll_variable_elements" ON payroll_variable_elements FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_payroll_variable_elements" ON payroll_variable_elements;
CREATE POLICY "tenant_update_payroll_variable_elements" ON payroll_variable_elements FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_partner_bank_accounts" ON partner_bank_accounts;
CREATE POLICY "tenant_delete_partner_bank_accounts" ON partner_bank_accounts FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_partner_bank_accounts" ON partner_bank_accounts;
CREATE POLICY "tenant_insert_partner_bank_accounts" ON partner_bank_accounts FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_partner_bank_accounts" ON partner_bank_accounts;
CREATE POLICY "tenant_select_partner_bank_accounts" ON partner_bank_accounts FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_partner_bank_accounts" ON partner_bank_accounts;
CREATE POLICY "tenant_update_partner_bank_accounts" ON partner_bank_accounts FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_partner_categories" ON partner_categories;
CREATE POLICY "tenant_delete_partner_categories" ON partner_categories FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_partner_categories" ON partner_categories;
CREATE POLICY "tenant_insert_partner_categories" ON partner_categories FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_partner_categories" ON partner_categories;
CREATE POLICY "tenant_select_partner_categories" ON partner_categories FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_partner_categories" ON partner_categories;
CREATE POLICY "tenant_update_partner_categories" ON partner_categories FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_activity" ON project_activity_log;
CREATE POLICY "tenant_delete_activity" ON project_activity_log FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_activity" ON project_activity_log;
CREATE POLICY "tenant_insert_activity" ON project_activity_log FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_activity" ON project_activity_log;
CREATE POLICY "tenant_select_activity" ON project_activity_log FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_tax_payments" ON tax_payments;
CREATE POLICY "tenant_delete_tax_payments" ON tax_payments FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_tax_payments" ON tax_payments;
CREATE POLICY "tenant_insert_tax_payments" ON tax_payments FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_tax_payments" ON tax_payments;
CREATE POLICY "tenant_select_tax_payments" ON tax_payments FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_tax_payments" ON tax_payments;
CREATE POLICY "tenant_update_tax_payments" ON tax_payments FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON asset_batch_disposal_lines;
CREATE POLICY "tenant_delete" ON asset_batch_disposal_lines FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_asset_batch_disposal_lines" ON asset_batch_disposal_lines;
CREATE POLICY "tenant_delete_asset_batch_disposal_lines" ON asset_batch_disposal_lines FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON asset_batch_disposal_lines;
CREATE POLICY "tenant_insert" ON asset_batch_disposal_lines FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_asset_batch_disposal_lines" ON asset_batch_disposal_lines;
CREATE POLICY "tenant_insert_asset_batch_disposal_lines" ON asset_batch_disposal_lines FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON asset_batch_disposal_lines;
CREATE POLICY "tenant_select" ON asset_batch_disposal_lines FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_asset_batch_disposal_lines" ON asset_batch_disposal_lines;
CREATE POLICY "tenant_select_asset_batch_disposal_lines" ON asset_batch_disposal_lines FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON asset_batch_disposal_lines;
CREATE POLICY "tenant_update" ON asset_batch_disposal_lines FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_asset_batch_disposal_lines" ON asset_batch_disposal_lines;
CREATE POLICY "tenant_update_asset_batch_disposal_lines" ON asset_batch_disposal_lines FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON analytic_sections;
CREATE POLICY "tenant_delete" ON analytic_sections FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_analytic_sections" ON analytic_sections;
CREATE POLICY "tenant_delete_analytic_sections" ON analytic_sections FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON analytic_sections;
CREATE POLICY "tenant_insert" ON analytic_sections FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_analytic_sections" ON analytic_sections;
CREATE POLICY "tenant_insert_analytic_sections" ON analytic_sections FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON analytic_sections;
CREATE POLICY "tenant_select" ON analytic_sections FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_analytic_sections" ON analytic_sections;
CREATE POLICY "tenant_select_analytic_sections" ON analytic_sections FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON analytic_sections;
CREATE POLICY "tenant_update" ON analytic_sections FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_analytic_sections" ON analytic_sections;
CREATE POLICY "tenant_update_analytic_sections" ON analytic_sections FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON budgets;
CREATE POLICY "tenant_delete" ON budgets FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_budgets" ON budgets;
CREATE POLICY "tenant_delete_budgets" ON budgets FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON budgets;
CREATE POLICY "tenant_insert" ON budgets FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_budgets" ON budgets;
CREATE POLICY "tenant_insert_budgets" ON budgets FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON budgets;
CREATE POLICY "tenant_select" ON budgets FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_budgets" ON budgets;
CREATE POLICY "tenant_select_budgets" ON budgets FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON budgets;
CREATE POLICY "tenant_update" ON budgets FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_budgets" ON budgets;
CREATE POLICY "tenant_update_budgets" ON budgets FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON purchase_order_lines;
CREATE POLICY "tenant_delete" ON purchase_order_lines FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_purchase_order_lines" ON purchase_order_lines;
CREATE POLICY "tenant_delete_purchase_order_lines" ON purchase_order_lines FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON purchase_order_lines;
CREATE POLICY "tenant_insert" ON purchase_order_lines FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_purchase_order_lines" ON purchase_order_lines;
CREATE POLICY "tenant_insert_purchase_order_lines" ON purchase_order_lines FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON purchase_order_lines;
CREATE POLICY "tenant_select" ON purchase_order_lines FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_purchase_order_lines" ON purchase_order_lines;
CREATE POLICY "tenant_select_purchase_order_lines" ON purchase_order_lines FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON purchase_order_lines;
CREATE POLICY "tenant_update" ON purchase_order_lines FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_purchase_order_lines" ON purchase_order_lines;
CREATE POLICY "tenant_update_purchase_order_lines" ON purchase_order_lines FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_crm_activities" ON crm_activities;
CREATE POLICY "tenant_delete_crm_activities" ON crm_activities FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_crm_activities" ON crm_activities;
CREATE POLICY "tenant_insert_crm_activities" ON crm_activities FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_crm_activities" ON crm_activities;
CREATE POLICY "tenant_select_crm_activities" ON crm_activities FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_crm_activities" ON crm_activities;
CREATE POLICY "tenant_update_crm_activities" ON crm_activities FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON chart_accounts;
CREATE POLICY "tenant_delete" ON chart_accounts FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_chart_accounts" ON chart_accounts;
CREATE POLICY "tenant_delete_chart_accounts" ON chart_accounts FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON chart_accounts;
CREATE POLICY "tenant_insert" ON chart_accounts FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_chart_accounts" ON chart_accounts;
CREATE POLICY "tenant_insert_chart_accounts" ON chart_accounts FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON chart_accounts;
CREATE POLICY "tenant_select" ON chart_accounts FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_chart_accounts" ON chart_accounts;
CREATE POLICY "tenant_select_chart_accounts" ON chart_accounts FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON chart_accounts;
CREATE POLICY "tenant_update" ON chart_accounts FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_chart_accounts" ON chart_accounts;
CREATE POLICY "tenant_update_chart_accounts" ON chart_accounts FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_marking_types" ON marking_types;
CREATE POLICY "tenant_delete_marking_types" ON marking_types FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_marking_types" ON marking_types;
CREATE POLICY "tenant_insert_marking_types" ON marking_types FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_marking_types" ON marking_types;
CREATE POLICY "tenant_select_marking_types" ON marking_types FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_marking_types" ON marking_types;
CREATE POLICY "tenant_update_marking_types" ON marking_types FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON leave_requests;
CREATE POLICY "tenant_delete" ON leave_requests FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_leave_requests" ON leave_requests;
CREATE POLICY "tenant_delete_leave_requests" ON leave_requests FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON leave_requests;
CREATE POLICY "tenant_insert" ON leave_requests FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_leave_requests" ON leave_requests;
CREATE POLICY "tenant_insert_leave_requests" ON leave_requests FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON leave_requests;
CREATE POLICY "tenant_select" ON leave_requests FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_leave_requests" ON leave_requests;
CREATE POLICY "tenant_select_leave_requests" ON leave_requests FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON leave_requests;
CREATE POLICY "tenant_update" ON leave_requests FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_leave_requests" ON leave_requests;
CREATE POLICY "tenant_update_leave_requests" ON leave_requests FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_tenants" ON tenants;
CREATE POLICY "tenant_delete_tenants" ON tenants FOR DELETE USING (((id = current_tenant_id()) AND (current_user_role() = 'admin'::text)));
DROP POLICY IF EXISTS "tenant_select_tenants" ON tenants;
CREATE POLICY "tenant_select_tenants" ON tenants FOR SELECT USING ((id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_tenants" ON tenants;
CREATE POLICY "tenant_update_tenants" ON tenants FOR UPDATE USING (((id = current_tenant_id()) AND (current_user_role() = 'admin'::text))) WITH CHECK (((id = current_tenant_id()) AND (current_user_role() = 'admin'::text)));
DROP POLICY IF EXISTS "tenants_select" ON tenants;
CREATE POLICY "tenants_select" ON tenants FOR SELECT USING ((id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON of_document_access;
CREATE POLICY "tenant_delete" ON of_document_access FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_of_document_access" ON of_document_access;
CREATE POLICY "tenant_delete_of_document_access" ON of_document_access FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON of_document_access;
CREATE POLICY "tenant_insert" ON of_document_access FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_of_document_access" ON of_document_access;
CREATE POLICY "tenant_insert_of_document_access" ON of_document_access FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON of_document_access;
CREATE POLICY "tenant_select" ON of_document_access FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_of_document_access" ON of_document_access;
CREATE POLICY "tenant_select_of_document_access" ON of_document_access FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON of_document_access;
CREATE POLICY "tenant_update" ON of_document_access FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_of_document_access" ON of_document_access;
CREATE POLICY "tenant_update_of_document_access" ON of_document_access FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_pos_terminals" ON pos_terminals;
CREATE POLICY "tenant_delete_pos_terminals" ON pos_terminals FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_pos_terminals" ON pos_terminals;
CREATE POLICY "tenant_insert_pos_terminals" ON pos_terminals FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_pos_terminals" ON pos_terminals;
CREATE POLICY "tenant_select_pos_terminals" ON pos_terminals FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_pos_terminals" ON pos_terminals;
CREATE POLICY "tenant_update_pos_terminals" ON pos_terminals FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_pos_ticket_lines" ON pos_ticket_lines;
CREATE POLICY "tenant_delete_pos_ticket_lines" ON pos_ticket_lines FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_pos_ticket_lines" ON pos_ticket_lines;
CREATE POLICY "tenant_insert_pos_ticket_lines" ON pos_ticket_lines FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_pos_ticket_lines" ON pos_ticket_lines;
CREATE POLICY "tenant_select_pos_ticket_lines" ON pos_ticket_lines FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_pos_ticket_lines" ON pos_ticket_lines;
CREATE POLICY "tenant_update_pos_ticket_lines" ON pos_ticket_lines FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON consolidated_treasury;
CREATE POLICY "tenant_delete" ON consolidated_treasury FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_consolidated_treasury" ON consolidated_treasury;
CREATE POLICY "tenant_delete_consolidated_treasury" ON consolidated_treasury FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON consolidated_treasury;
CREATE POLICY "tenant_insert" ON consolidated_treasury FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_consolidated_treasury" ON consolidated_treasury;
CREATE POLICY "tenant_insert_consolidated_treasury" ON consolidated_treasury FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON consolidated_treasury;
CREATE POLICY "tenant_select" ON consolidated_treasury FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_consolidated_treasury" ON consolidated_treasury;
CREATE POLICY "tenant_select_consolidated_treasury" ON consolidated_treasury FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON consolidated_treasury;
CREATE POLICY "tenant_update" ON consolidated_treasury FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_consolidated_treasury" ON consolidated_treasury;
CREATE POLICY "tenant_update_consolidated_treasury" ON consolidated_treasury FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_stock_alerts" ON stock_alerts;
CREATE POLICY "tenant_delete_stock_alerts" ON stock_alerts FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_stock_alerts" ON stock_alerts;
CREATE POLICY "tenant_insert_stock_alerts" ON stock_alerts FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_stock_alerts" ON stock_alerts;
CREATE POLICY "tenant_select_stock_alerts" ON stock_alerts FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_stock_alerts" ON stock_alerts;
CREATE POLICY "tenant_update_stock_alerts" ON stock_alerts FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_mirror_verification" ON mirror_verification_details;
CREATE POLICY "tenant_delete_mirror_verification" ON mirror_verification_details FOR DELETE USING ((EXISTS ( SELECT 1
   FROM mirror_servers ms
  WHERE ((ms.id = mirror_verification_details.mirror_server_id) AND (ms.tenant_id = current_tenant_id())))));
DROP POLICY IF EXISTS "tenant_delete_mirror_verification_details" ON mirror_verification_details;
CREATE POLICY "tenant_delete_mirror_verification_details" ON mirror_verification_details FOR DELETE USING (((tenant_id = current_tenant_id()) AND can_perform('mirror_verification_details'::text, 'delete'::text)));
DROP POLICY IF EXISTS "tenant_insert_mirror_verification" ON mirror_verification_details;
CREATE POLICY "tenant_insert_mirror_verification" ON mirror_verification_details FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM mirror_servers ms
  WHERE ((ms.id = mirror_verification_details.mirror_server_id) AND (ms.tenant_id = current_tenant_id())))));
DROP POLICY IF EXISTS "tenant_insert_mirror_verification_details" ON mirror_verification_details;
CREATE POLICY "tenant_insert_mirror_verification_details" ON mirror_verification_details FOR INSERT WITH CHECK (((tenant_id = current_tenant_id()) AND can_perform('mirror_verification_details'::text, 'insert'::text)));
DROP POLICY IF EXISTS "tenant_isolated_mirror_verification" ON mirror_verification_details;
CREATE POLICY "tenant_isolated_mirror_verification" ON mirror_verification_details FOR ALL USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_mirror_verification" ON mirror_verification_details;
CREATE POLICY "tenant_select_mirror_verification" ON mirror_verification_details FOR SELECT USING ((EXISTS ( SELECT 1
   FROM mirror_servers ms
  WHERE ((ms.id = mirror_verification_details.mirror_server_id) AND (ms.tenant_id = current_tenant_id())))));
DROP POLICY IF EXISTS "tenant_select_mirror_verification_details" ON mirror_verification_details;
CREATE POLICY "tenant_select_mirror_verification_details" ON mirror_verification_details FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_mirror_verification" ON mirror_verification_details;
CREATE POLICY "tenant_update_mirror_verification" ON mirror_verification_details FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM mirror_servers ms
  WHERE ((ms.id = mirror_verification_details.mirror_server_id) AND (ms.tenant_id = current_tenant_id())))));
DROP POLICY IF EXISTS "tenant_update_mirror_verification_details" ON mirror_verification_details;
CREATE POLICY "tenant_update_mirror_verification_details" ON mirror_verification_details FOR UPDATE USING (((tenant_id = current_tenant_id()) AND can_perform('mirror_verification_details'::text, 'update'::text))) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON payroll_component_rates;
CREATE POLICY "tenant_delete" ON payroll_component_rates FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_payroll_component_rates" ON payroll_component_rates;
CREATE POLICY "tenant_delete_payroll_component_rates" ON payroll_component_rates FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON payroll_component_rates;
CREATE POLICY "tenant_insert" ON payroll_component_rates FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_payroll_component_rates" ON payroll_component_rates;
CREATE POLICY "tenant_insert_payroll_component_rates" ON payroll_component_rates FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON payroll_component_rates;
CREATE POLICY "tenant_select" ON payroll_component_rates FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_payroll_component_rates" ON payroll_component_rates;
CREATE POLICY "tenant_select_payroll_component_rates" ON payroll_component_rates FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON payroll_component_rates;
CREATE POLICY "tenant_update" ON payroll_component_rates FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_payroll_component_rates" ON payroll_component_rates;
CREATE POLICY "tenant_update_payroll_component_rates" ON payroll_component_rates FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_supplier_contacts" ON supplier_contacts;
CREATE POLICY "tenant_delete_supplier_contacts" ON supplier_contacts FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_supplier_contacts" ON supplier_contacts;
CREATE POLICY "tenant_insert_supplier_contacts" ON supplier_contacts FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_supplier_contacts" ON supplier_contacts;
CREATE POLICY "tenant_select_supplier_contacts" ON supplier_contacts FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_supplier_contacts" ON supplier_contacts;
CREATE POLICY "tenant_update_supplier_contacts" ON supplier_contacts FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_product_grids" ON product_grids;
CREATE POLICY "tenant_delete_product_grids" ON product_grids FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_product_grids" ON product_grids;
CREATE POLICY "tenant_insert_product_grids" ON product_grids FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_product_grids" ON product_grids;
CREATE POLICY "tenant_select_product_grids" ON product_grids FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_product_grids" ON product_grids;
CREATE POLICY "tenant_update_product_grids" ON product_grids FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_product_links" ON product_links;
CREATE POLICY "tenant_delete_product_links" ON product_links FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_product_links" ON product_links;
CREATE POLICY "tenant_insert_product_links" ON product_links FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_product_links" ON product_links;
CREATE POLICY "tenant_select_product_links" ON product_links FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_product_links" ON product_links;
CREATE POLICY "tenant_update_product_links" ON product_links FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_fiscal_positions" ON fiscal_positions;
CREATE POLICY "tenant_delete_fiscal_positions" ON fiscal_positions FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_fiscal_positions" ON fiscal_positions;
CREATE POLICY "tenant_insert_fiscal_positions" ON fiscal_positions FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_fiscal_positions" ON fiscal_positions;
CREATE POLICY "tenant_select_fiscal_positions" ON fiscal_positions FOR SELECT USING (((tenant_id = current_tenant_id()) OR (tenant_id IS NULL)));
DROP POLICY IF EXISTS "tenant_update_fiscal_positions" ON fiscal_positions;
CREATE POLICY "tenant_update_fiscal_positions" ON fiscal_positions FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_supplier_price_list_lines" ON supplier_price_list_lines;
CREATE POLICY "tenant_delete_supplier_price_list_lines" ON supplier_price_list_lines FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_supplier_price_list_lines" ON supplier_price_list_lines;
CREATE POLICY "tenant_insert_supplier_price_list_lines" ON supplier_price_list_lines FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_supplier_price_list_lines" ON supplier_price_list_lines;
CREATE POLICY "tenant_select_supplier_price_list_lines" ON supplier_price_list_lines FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_supplier_price_list_lines" ON supplier_price_list_lines;
CREATE POLICY "tenant_update_supplier_price_list_lines" ON supplier_price_list_lines FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_tax_cash_basis_entries" ON tax_cash_basis_entries;
CREATE POLICY "tenant_delete_tax_cash_basis_entries" ON tax_cash_basis_entries FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_tax_cash_basis_entries" ON tax_cash_basis_entries;
CREATE POLICY "tenant_insert_tax_cash_basis_entries" ON tax_cash_basis_entries FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_tax_cash_basis_entries" ON tax_cash_basis_entries;
CREATE POLICY "tenant_select_tax_cash_basis_entries" ON tax_cash_basis_entries FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_tax_cash_basis_entries" ON tax_cash_basis_entries;
CREATE POLICY "tenant_update_tax_cash_basis_entries" ON tax_cash_basis_entries FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_tax_repartition_lines" ON tax_repartition_lines;
CREATE POLICY "tenant_delete_tax_repartition_lines" ON tax_repartition_lines FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_tax_repartition_lines" ON tax_repartition_lines;
CREATE POLICY "tenant_insert_tax_repartition_lines" ON tax_repartition_lines FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_tax_repartition_lines" ON tax_repartition_lines;
CREATE POLICY "tenant_select_tax_repartition_lines" ON tax_repartition_lines FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_tax_repartition_lines" ON tax_repartition_lines;
CREATE POLICY "tenant_update_tax_repartition_lines" ON tax_repartition_lines FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_account_tags" ON account_tags;
CREATE POLICY "tenant_delete_account_tags" ON account_tags FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_account_tags" ON account_tags;
CREATE POLICY "tenant_insert_account_tags" ON account_tags FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_account_tags" ON account_tags;
CREATE POLICY "tenant_select_account_tags" ON account_tags FOR SELECT USING (((tenant_id = current_tenant_id()) OR (tenant_id IS NULL)));
DROP POLICY IF EXISTS "tenant_update_account_tags" ON account_tags;
CREATE POLICY "tenant_update_account_tags" ON account_tags FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON dsn_declarations;
CREATE POLICY "tenant_delete" ON dsn_declarations FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_dsn_declarations" ON dsn_declarations;
CREATE POLICY "tenant_delete_dsn_declarations" ON dsn_declarations FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON dsn_declarations;
CREATE POLICY "tenant_insert" ON dsn_declarations FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_dsn_declarations" ON dsn_declarations;
CREATE POLICY "tenant_insert_dsn_declarations" ON dsn_declarations FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON dsn_declarations;
CREATE POLICY "tenant_select" ON dsn_declarations FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_dsn_declarations" ON dsn_declarations;
CREATE POLICY "tenant_select_dsn_declarations" ON dsn_declarations FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON dsn_declarations;
CREATE POLICY "tenant_update" ON dsn_declarations FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_dsn_declarations" ON dsn_declarations;
CREATE POLICY "tenant_update_dsn_declarations" ON dsn_declarations FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_fiscal_position_mappings" ON fiscal_position_mappings;
CREATE POLICY "tenant_delete_fiscal_position_mappings" ON fiscal_position_mappings FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_fiscal_position_mappings" ON fiscal_position_mappings;
CREATE POLICY "tenant_insert_fiscal_position_mappings" ON fiscal_position_mappings FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_fiscal_position_mappings" ON fiscal_position_mappings;
CREATE POLICY "tenant_select_fiscal_position_mappings" ON fiscal_position_mappings FOR SELECT USING (((tenant_id = current_tenant_id()) OR (tenant_id IS NULL)));
DROP POLICY IF EXISTS "tenant_update_fiscal_position_mappings" ON fiscal_position_mappings;
CREATE POLICY "tenant_update_fiscal_position_mappings" ON fiscal_position_mappings FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON dpae_records;
CREATE POLICY "tenant_delete" ON dpae_records FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_dpae_records" ON dpae_records;
CREATE POLICY "tenant_delete_dpae_records" ON dpae_records FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON dpae_records;
CREATE POLICY "tenant_insert" ON dpae_records FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_dpae_records" ON dpae_records;
CREATE POLICY "tenant_insert_dpae_records" ON dpae_records FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON dpae_records;
CREATE POLICY "tenant_select" ON dpae_records FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_dpae_records" ON dpae_records;
CREATE POLICY "tenant_select_dpae_records" ON dpae_records FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON dpae_records;
CREATE POLICY "tenant_update" ON dpae_records FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_dpae_records" ON dpae_records;
CREATE POLICY "tenant_update_dpae_records" ON dpae_records FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON cpf_accounts;
CREATE POLICY "tenant_delete" ON cpf_accounts FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_cpf_accounts" ON cpf_accounts;
CREATE POLICY "tenant_delete_cpf_accounts" ON cpf_accounts FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON cpf_accounts;
CREATE POLICY "tenant_insert" ON cpf_accounts FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_cpf_accounts" ON cpf_accounts;
CREATE POLICY "tenant_insert_cpf_accounts" ON cpf_accounts FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON cpf_accounts;
CREATE POLICY "tenant_select" ON cpf_accounts FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_cpf_accounts" ON cpf_accounts;
CREATE POLICY "tenant_select_cpf_accounts" ON cpf_accounts FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON cpf_accounts;
CREATE POLICY "tenant_update" ON cpf_accounts FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_cpf_accounts" ON cpf_accounts;
CREATE POLICY "tenant_update_cpf_accounts" ON cpf_accounts FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_bank_statement_templates" ON bank_statement_templates;
CREATE POLICY "tenant_delete_bank_statement_templates" ON bank_statement_templates FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_bank_statement_templates" ON bank_statement_templates;
CREATE POLICY "tenant_insert_bank_statement_templates" ON bank_statement_templates FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_bank_statement_templates" ON bank_statement_templates;
CREATE POLICY "tenant_select_bank_statement_templates" ON bank_statement_templates FOR SELECT USING (((tenant_id = current_tenant_id()) OR (tenant_id IS NULL)));
DROP POLICY IF EXISTS "tenant_update_bank_statement_templates" ON bank_statement_templates;
CREATE POLICY "tenant_update_bank_statement_templates" ON bank_statement_templates FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_account_tag_mappings" ON account_tag_mappings;
CREATE POLICY "tenant_delete_account_tag_mappings" ON account_tag_mappings FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_account_tag_mappings" ON account_tag_mappings;
CREATE POLICY "tenant_insert_account_tag_mappings" ON account_tag_mappings FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_account_tag_mappings" ON account_tag_mappings;
CREATE POLICY "tenant_select_account_tag_mappings" ON account_tag_mappings FOR SELECT USING (((tenant_id = current_tenant_id()) OR (tenant_id IS NULL)));
DROP POLICY IF EXISTS "tenant_update_account_tag_mappings" ON account_tag_mappings;
CREATE POLICY "tenant_update_account_tag_mappings" ON account_tag_mappings FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_partner_category_mappings" ON partner_category_mappings;
CREATE POLICY "tenant_delete_partner_category_mappings" ON partner_category_mappings FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_partner_category_mappings" ON partner_category_mappings;
CREATE POLICY "tenant_insert_partner_category_mappings" ON partner_category_mappings FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_partner_category_mappings" ON partner_category_mappings;
CREATE POLICY "tenant_select_partner_category_mappings" ON partner_category_mappings FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_partner_category_mappings" ON partner_category_mappings;
CREATE POLICY "tenant_update_partner_category_mappings" ON partner_category_mappings FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON legal_watch;
CREATE POLICY "tenant_delete" ON legal_watch FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_legal_watch" ON legal_watch;
CREATE POLICY "tenant_delete_legal_watch" ON legal_watch FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON legal_watch;
CREATE POLICY "tenant_insert" ON legal_watch FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_legal_watch" ON legal_watch;
CREATE POLICY "tenant_insert_legal_watch" ON legal_watch FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON legal_watch;
CREATE POLICY "tenant_select" ON legal_watch FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_legal_watch" ON legal_watch;
CREATE POLICY "tenant_select_legal_watch" ON legal_watch FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON legal_watch;
CREATE POLICY "tenant_update" ON legal_watch FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_legal_watch" ON legal_watch;
CREATE POLICY "tenant_update_legal_watch" ON legal_watch FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_analytic_distribution_lines" ON analytic_distribution_lines;
CREATE POLICY "tenant_delete_analytic_distribution_lines" ON analytic_distribution_lines FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_analytic_distribution_lines" ON analytic_distribution_lines;
CREATE POLICY "tenant_insert_analytic_distribution_lines" ON analytic_distribution_lines FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_isolated_analytic_dist_lines" ON analytic_distribution_lines;
CREATE POLICY "tenant_isolated_analytic_dist_lines" ON analytic_distribution_lines FOR ALL USING (((tenant_id IS NULL) OR (tenant_id = (current_setting('app.tenant_id'::text, true))::uuid))) WITH CHECK (((tenant_id IS NULL) OR (tenant_id = (current_setting('app.tenant_id'::text, true))::uuid)));
DROP POLICY IF EXISTS "tenant_select_analytic_distribution_lines" ON analytic_distribution_lines;
CREATE POLICY "tenant_select_analytic_distribution_lines" ON analytic_distribution_lines FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_analytic_distribution_lines" ON analytic_distribution_lines;
CREATE POLICY "tenant_update_analytic_distribution_lines" ON analytic_distribution_lines FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON journal_lines;
CREATE POLICY "tenant_delete" ON journal_lines FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_journal_lines" ON journal_lines;
CREATE POLICY "tenant_delete_journal_lines" ON journal_lines FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON journal_lines;
CREATE POLICY "tenant_insert" ON journal_lines FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_journal_lines" ON journal_lines;
CREATE POLICY "tenant_insert_journal_lines" ON journal_lines FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON journal_lines;
CREATE POLICY "tenant_select" ON journal_lines FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_journal_lines" ON journal_lines;
CREATE POLICY "tenant_select_journal_lines" ON journal_lines FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON journal_lines;
CREATE POLICY "tenant_update" ON journal_lines FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_journal_lines" ON journal_lines;
CREATE POLICY "tenant_update_journal_lines" ON journal_lines FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON asset_depreciation_plans;
CREATE POLICY "tenant_delete" ON asset_depreciation_plans FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_asset_depreciation_plans" ON asset_depreciation_plans;
CREATE POLICY "tenant_delete_asset_depreciation_plans" ON asset_depreciation_plans FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON asset_depreciation_plans;
CREATE POLICY "tenant_insert" ON asset_depreciation_plans FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_asset_depreciation_plans" ON asset_depreciation_plans;
CREATE POLICY "tenant_insert_asset_depreciation_plans" ON asset_depreciation_plans FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON asset_depreciation_plans;
CREATE POLICY "tenant_select" ON asset_depreciation_plans FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_asset_depreciation_plans" ON asset_depreciation_plans;
CREATE POLICY "tenant_select_asset_depreciation_plans" ON asset_depreciation_plans FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON asset_depreciation_plans;
CREATE POLICY "tenant_update" ON asset_depreciation_plans FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_asset_depreciation_plans" ON asset_depreciation_plans;
CREATE POLICY "tenant_update_asset_depreciation_plans" ON asset_depreciation_plans FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_exchange_rates" ON exchange_rates;
CREATE POLICY "tenant_delete_exchange_rates" ON exchange_rates FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_exchange_rates" ON exchange_rates;
CREATE POLICY "tenant_insert_exchange_rates" ON exchange_rates FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_exchange_rates" ON exchange_rates;
CREATE POLICY "tenant_select_exchange_rates" ON exchange_rates FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_exchange_rates" ON exchange_rates;
CREATE POLICY "tenant_update_exchange_rates" ON exchange_rates FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON asset_documents;
CREATE POLICY "tenant_delete" ON asset_documents FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_asset_documents" ON asset_documents;
CREATE POLICY "tenant_delete_asset_documents" ON asset_documents FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON asset_documents;
CREATE POLICY "tenant_insert" ON asset_documents FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_asset_documents" ON asset_documents;
CREATE POLICY "tenant_insert_asset_documents" ON asset_documents FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON asset_documents;
CREATE POLICY "tenant_select" ON asset_documents FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_asset_documents" ON asset_documents;
CREATE POLICY "tenant_select_asset_documents" ON asset_documents FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON asset_documents;
CREATE POLICY "tenant_update" ON asset_documents FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_asset_documents" ON asset_documents;
CREATE POLICY "tenant_update_asset_documents" ON asset_documents FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_payroll_tax_grids" ON payroll_tax_grids;
CREATE POLICY "tenant_delete_payroll_tax_grids" ON payroll_tax_grids FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_payroll_tax_grids" ON payroll_tax_grids;
CREATE POLICY "tenant_insert_payroll_tax_grids" ON payroll_tax_grids FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_payroll_tax_grids" ON payroll_tax_grids;
CREATE POLICY "tenant_select_payroll_tax_grids" ON payroll_tax_grids FOR SELECT USING (((tenant_id = current_tenant_id()) OR (tenant_id IS NULL)));
DROP POLICY IF EXISTS "tenant_update_payroll_tax_grids" ON payroll_tax_grids;
CREATE POLICY "tenant_update_payroll_tax_grids" ON payroll_tax_grids FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_payroll_tax_grid_lines" ON payroll_tax_grid_lines;
CREATE POLICY "tenant_delete_payroll_tax_grid_lines" ON payroll_tax_grid_lines FOR DELETE USING ((EXISTS ( SELECT 1
   FROM payroll_tax_grids g
  WHERE ((g.id = payroll_tax_grid_lines.grid_id) AND (g.tenant_id = current_tenant_id())))));
DROP POLICY IF EXISTS "tenant_insert_payroll_tax_grid_lines" ON payroll_tax_grid_lines;
CREATE POLICY "tenant_insert_payroll_tax_grid_lines" ON payroll_tax_grid_lines FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM payroll_tax_grids g
  WHERE ((g.id = payroll_tax_grid_lines.grid_id) AND (g.tenant_id = current_tenant_id())))));
DROP POLICY IF EXISTS "tenant_select_payroll_tax_grid_lines" ON payroll_tax_grid_lines;
CREATE POLICY "tenant_select_payroll_tax_grid_lines" ON payroll_tax_grid_lines FOR SELECT USING ((EXISTS ( SELECT 1
   FROM payroll_tax_grids g
  WHERE ((g.id = payroll_tax_grid_lines.grid_id) AND ((g.tenant_id = current_tenant_id()) OR (g.tenant_id IS NULL))))));
DROP POLICY IF EXISTS "tenant_update_payroll_tax_grid_lines" ON payroll_tax_grid_lines;
CREATE POLICY "tenant_update_payroll_tax_grid_lines" ON payroll_tax_grid_lines FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM payroll_tax_grids g
  WHERE ((g.id = payroll_tax_grid_lines.grid_id) AND (g.tenant_id = current_tenant_id())))));
DROP POLICY IF EXISTS "tenant_delete_analytic_plans" ON analytic_plans;
CREATE POLICY "tenant_delete_analytic_plans" ON analytic_plans FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_analytic_plans" ON analytic_plans;
CREATE POLICY "tenant_insert_analytic_plans" ON analytic_plans FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_analytic_plans" ON analytic_plans;
CREATE POLICY "tenant_select_analytic_plans" ON analytic_plans FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_analytic_plans" ON analytic_plans;
CREATE POLICY "tenant_update_analytic_plans" ON analytic_plans FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_fiscal_backups" ON fiscal_backups;
CREATE POLICY "tenant_delete_fiscal_backups" ON fiscal_backups FOR DELETE USING (((tenant_id = current_tenant_id()) AND can_perform('fiscal_backups'::text, 'delete'::text)));
DROP POLICY IF EXISTS "tenant_insert_fiscal_backups" ON fiscal_backups;
CREATE POLICY "tenant_insert_fiscal_backups" ON fiscal_backups FOR INSERT WITH CHECK (((tenant_id = current_tenant_id()) AND can_perform('fiscal_backups'::text, 'insert'::text)));
DROP POLICY IF EXISTS "tenant_select_fiscal_backups" ON fiscal_backups;
CREATE POLICY "tenant_select_fiscal_backups" ON fiscal_backups FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_fiscal_backups" ON fiscal_backups;
CREATE POLICY "tenant_update_fiscal_backups" ON fiscal_backups FOR UPDATE USING (((tenant_id = current_tenant_id()) AND can_perform('fiscal_backups'::text, 'update'::text))) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON asset_splits;
CREATE POLICY "tenant_delete" ON asset_splits FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_asset_splits" ON asset_splits;
CREATE POLICY "tenant_delete_asset_splits" ON asset_splits FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON asset_splits;
CREATE POLICY "tenant_insert" ON asset_splits FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_asset_splits" ON asset_splits;
CREATE POLICY "tenant_insert_asset_splits" ON asset_splits FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON asset_splits;
CREATE POLICY "tenant_select" ON asset_splits FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_asset_splits" ON asset_splits;
CREATE POLICY "tenant_select_asset_splits" ON asset_splits FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON asset_splits;
CREATE POLICY "tenant_update" ON asset_splits FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_asset_splits" ON asset_splits;
CREATE POLICY "tenant_update_asset_splits" ON asset_splits FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_currency_revaluations" ON currency_revaluations;
CREATE POLICY "tenant_delete_currency_revaluations" ON currency_revaluations FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_currency_revaluations" ON currency_revaluations;
CREATE POLICY "tenant_insert_currency_revaluations" ON currency_revaluations FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_currency_revaluations" ON currency_revaluations;
CREATE POLICY "tenant_select_currency_revaluations" ON currency_revaluations FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_currency_revaluations" ON currency_revaluations;
CREATE POLICY "tenant_update_currency_revaluations" ON currency_revaluations FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON document_templates;
CREATE POLICY "tenant_delete" ON document_templates FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_document_templates" ON document_templates;
CREATE POLICY "tenant_delete_document_templates" ON document_templates FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON document_templates;
CREATE POLICY "tenant_insert" ON document_templates FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_document_templates" ON document_templates;
CREATE POLICY "tenant_insert_document_templates" ON document_templates FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON document_templates;
CREATE POLICY "tenant_select" ON document_templates FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_document_templates" ON document_templates;
CREATE POLICY "tenant_select_document_templates" ON document_templates FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON document_templates;
CREATE POLICY "tenant_update" ON document_templates FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_document_templates" ON document_templates;
CREATE POLICY "tenant_update_document_templates" ON document_templates FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_corporate_tax_grids" ON corporate_tax_grids;
CREATE POLICY "tenant_delete_corporate_tax_grids" ON corporate_tax_grids FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_corporate_tax_grids" ON corporate_tax_grids;
CREATE POLICY "tenant_insert_corporate_tax_grids" ON corporate_tax_grids FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_corporate_tax_grids" ON corporate_tax_grids;
CREATE POLICY "tenant_select_corporate_tax_grids" ON corporate_tax_grids FOR SELECT USING (((tenant_id = current_tenant_id()) OR (tenant_id IS NULL)));
DROP POLICY IF EXISTS "tenant_update_corporate_tax_grids" ON corporate_tax_grids;
CREATE POLICY "tenant_update_corporate_tax_grids" ON corporate_tax_grids FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON purchase_credit_notes;
CREATE POLICY "tenant_delete" ON purchase_credit_notes FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_purchase_credit_notes" ON purchase_credit_notes;
CREATE POLICY "tenant_delete_purchase_credit_notes" ON purchase_credit_notes FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON purchase_credit_notes;
CREATE POLICY "tenant_insert" ON purchase_credit_notes FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_purchase_credit_notes" ON purchase_credit_notes;
CREATE POLICY "tenant_insert_purchase_credit_notes" ON purchase_credit_notes FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON purchase_credit_notes;
CREATE POLICY "tenant_select" ON purchase_credit_notes FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_purchase_credit_notes" ON purchase_credit_notes;
CREATE POLICY "tenant_select_purchase_credit_notes" ON purchase_credit_notes FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON purchase_credit_notes;
CREATE POLICY "tenant_update" ON purchase_credit_notes FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_purchase_credit_notes" ON purchase_credit_notes;
CREATE POLICY "tenant_update_purchase_credit_notes" ON purchase_credit_notes FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_corporate_tax_grid_lines" ON corporate_tax_grid_lines;
CREATE POLICY "tenant_delete_corporate_tax_grid_lines" ON corporate_tax_grid_lines FOR DELETE USING ((EXISTS ( SELECT 1
   FROM corporate_tax_grids g
  WHERE ((g.id = corporate_tax_grid_lines.grid_id) AND (g.tenant_id = current_tenant_id())))));
DROP POLICY IF EXISTS "tenant_insert_corporate_tax_grid_lines" ON corporate_tax_grid_lines;
CREATE POLICY "tenant_insert_corporate_tax_grid_lines" ON corporate_tax_grid_lines FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM corporate_tax_grids g
  WHERE ((g.id = corporate_tax_grid_lines.grid_id) AND (g.tenant_id = current_tenant_id())))));
DROP POLICY IF EXISTS "tenant_select_corporate_tax_grid_lines" ON corporate_tax_grid_lines;
CREATE POLICY "tenant_select_corporate_tax_grid_lines" ON corporate_tax_grid_lines FOR SELECT USING ((EXISTS ( SELECT 1
   FROM corporate_tax_grids g
  WHERE ((g.id = corporate_tax_grid_lines.grid_id) AND ((g.tenant_id = current_tenant_id()) OR (g.tenant_id IS NULL))))));
DROP POLICY IF EXISTS "tenant_update_corporate_tax_grid_lines" ON corporate_tax_grid_lines;
CREATE POLICY "tenant_update_corporate_tax_grid_lines" ON corporate_tax_grid_lines FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM corporate_tax_grids g
  WHERE ((g.id = corporate_tax_grid_lines.grid_id) AND (g.tenant_id = current_tenant_id())))));
DROP POLICY IF EXISTS "tenant_delete_tax_groups" ON tax_groups;
CREATE POLICY "tenant_delete_tax_groups" ON tax_groups FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_tax_groups" ON tax_groups;
CREATE POLICY "tenant_insert_tax_groups" ON tax_groups FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_tax_groups" ON tax_groups;
CREATE POLICY "tenant_select_tax_groups" ON tax_groups FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_tax_groups" ON tax_groups;
CREATE POLICY "tenant_update_tax_groups" ON tax_groups FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_check_books" ON check_books;
CREATE POLICY "tenant_delete_check_books" ON check_books FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_check_books" ON check_books;
CREATE POLICY "tenant_insert_check_books" ON check_books FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_check_books" ON check_books;
CREATE POLICY "tenant_select_check_books" ON check_books FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_check_books" ON check_books;
CREATE POLICY "tenant_update_check_books" ON check_books FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_checks" ON checks;
CREATE POLICY "tenant_delete_checks" ON checks FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_checks" ON checks;
CREATE POLICY "tenant_insert_checks" ON checks FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_checks" ON checks;
CREATE POLICY "tenant_select_checks" ON checks FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_checks" ON checks;
CREATE POLICY "tenant_update_checks" ON checks FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_crm_territories" ON crm_territories;
CREATE POLICY "tenant_delete_crm_territories" ON crm_territories FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_crm_territories" ON crm_territories;
CREATE POLICY "tenant_insert_crm_territories" ON crm_territories FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_crm_territories" ON crm_territories;
CREATE POLICY "tenant_select_crm_territories" ON crm_territories FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_crm_territories" ON crm_territories;
CREATE POLICY "tenant_update_crm_territories" ON crm_territories FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_crm_forecasts" ON crm_forecasts;
CREATE POLICY "tenant_delete_crm_forecasts" ON crm_forecasts FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_crm_forecasts" ON crm_forecasts;
CREATE POLICY "tenant_insert_crm_forecasts" ON crm_forecasts FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_crm_forecasts" ON crm_forecasts;
CREATE POLICY "tenant_select_crm_forecasts" ON crm_forecasts FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_crm_forecasts" ON crm_forecasts;
CREATE POLICY "tenant_update_crm_forecasts" ON crm_forecasts FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_service_tickets" ON service_tickets;
CREATE POLICY "tenant_delete_service_tickets" ON service_tickets FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_service_tickets" ON service_tickets;
CREATE POLICY "tenant_insert_service_tickets" ON service_tickets FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_service_tickets" ON service_tickets;
CREATE POLICY "tenant_select_service_tickets" ON service_tickets FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_service_tickets" ON service_tickets;
CREATE POLICY "tenant_update_service_tickets" ON service_tickets FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_service_ticket_messages" ON service_ticket_messages;
CREATE POLICY "tenant_delete_service_ticket_messages" ON service_ticket_messages FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_service_ticket_messages" ON service_ticket_messages;
CREATE POLICY "tenant_insert_service_ticket_messages" ON service_ticket_messages FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_service_ticket_messages" ON service_ticket_messages;
CREATE POLICY "tenant_select_service_ticket_messages" ON service_ticket_messages FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_service_ticket_messages" ON service_ticket_messages;
CREATE POLICY "tenant_update_service_ticket_messages" ON service_ticket_messages FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_service_contracts" ON service_contracts;
CREATE POLICY "tenant_delete_service_contracts" ON service_contracts FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_service_contracts" ON service_contracts;
CREATE POLICY "tenant_insert_service_contracts" ON service_contracts FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_service_contracts" ON service_contracts;
CREATE POLICY "tenant_select_service_contracts" ON service_contracts FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_service_contracts" ON service_contracts;
CREATE POLICY "tenant_update_service_contracts" ON service_contracts FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_knowledge_base_articles" ON knowledge_base_articles;
CREATE POLICY "tenant_delete_knowledge_base_articles" ON knowledge_base_articles FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_knowledge_base_articles" ON knowledge_base_articles;
CREATE POLICY "tenant_insert_knowledge_base_articles" ON knowledge_base_articles FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_knowledge_base_articles" ON knowledge_base_articles;
CREATE POLICY "tenant_select_knowledge_base_articles" ON knowledge_base_articles FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_knowledge_base_articles" ON knowledge_base_articles;
CREATE POLICY "tenant_update_knowledge_base_articles" ON knowledge_base_articles FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_electronic_signatures" ON electronic_signatures;
CREATE POLICY "tenant_delete_electronic_signatures" ON electronic_signatures FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_electronic_signatures" ON electronic_signatures;
CREATE POLICY "tenant_insert_electronic_signatures" ON electronic_signatures FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_electronic_signatures" ON electronic_signatures;
CREATE POLICY "tenant_select_electronic_signatures" ON electronic_signatures FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_electronic_signatures" ON electronic_signatures;
CREATE POLICY "tenant_update_electronic_signatures" ON electronic_signatures FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_pos_sessions" ON pos_sessions;
CREATE POLICY "tenant_delete_pos_sessions" ON pos_sessions FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_pos_sessions" ON pos_sessions;
CREATE POLICY "tenant_insert_pos_sessions" ON pos_sessions FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_pos_sessions" ON pos_sessions;
CREATE POLICY "tenant_select_pos_sessions" ON pos_sessions FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_pos_sessions" ON pos_sessions;
CREATE POLICY "tenant_update_pos_sessions" ON pos_sessions FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_online_payments" ON online_payments;
CREATE POLICY "tenant_delete_online_payments" ON online_payments FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_online_payments" ON online_payments;
CREATE POLICY "tenant_insert_online_payments" ON online_payments FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_online_payments" ON online_payments;
CREATE POLICY "tenant_select_online_payments" ON online_payments FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_online_payments" ON online_payments;
CREATE POLICY "tenant_update_online_payments" ON online_payments FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_document_shares" ON document_shares;
CREATE POLICY "tenant_delete_document_shares" ON document_shares FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_document_shares" ON document_shares;
CREATE POLICY "tenant_insert_document_shares" ON document_shares FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_document_shares" ON document_shares;
CREATE POLICY "tenant_select_document_shares" ON document_shares FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_document_shares" ON document_shares;
CREATE POLICY "tenant_update_document_shares" ON document_shares FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_leave_rules" ON leave_rules;
CREATE POLICY "tenant_delete_leave_rules" ON leave_rules FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_leave_rules" ON leave_rules;
CREATE POLICY "tenant_insert_leave_rules" ON leave_rules FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_leave_rules" ON leave_rules;
CREATE POLICY "tenant_select_leave_rules" ON leave_rules FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_leave_rules" ON leave_rules;
CREATE POLICY "tenant_update_leave_rules" ON leave_rules FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_leave_balances" ON leave_balances;
CREATE POLICY "tenant_delete_leave_balances" ON leave_balances FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_leave_balances" ON leave_balances;
CREATE POLICY "tenant_insert_leave_balances" ON leave_balances FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_leave_balances" ON leave_balances;
CREATE POLICY "tenant_select_leave_balances" ON leave_balances FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_leave_balances" ON leave_balances;
CREATE POLICY "tenant_update_leave_balances" ON leave_balances FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_sepa_payment_orders" ON sepa_payment_orders;
CREATE POLICY "tenant_delete_sepa_payment_orders" ON sepa_payment_orders FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_sepa_payment_orders" ON sepa_payment_orders;
CREATE POLICY "tenant_insert_sepa_payment_orders" ON sepa_payment_orders FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_sepa_payment_orders" ON sepa_payment_orders;
CREATE POLICY "tenant_select_sepa_payment_orders" ON sepa_payment_orders FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_sepa_payment_orders" ON sepa_payment_orders;
CREATE POLICY "tenant_update_sepa_payment_orders" ON sepa_payment_orders FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_pay_slip_clarified" ON pay_slip_clarified;
CREATE POLICY "tenant_delete_pay_slip_clarified" ON pay_slip_clarified FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_pay_slip_clarified" ON pay_slip_clarified;
CREATE POLICY "tenant_insert_pay_slip_clarified" ON pay_slip_clarified FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_pay_slip_clarified" ON pay_slip_clarified;
CREATE POLICY "tenant_select_pay_slip_clarified" ON pay_slip_clarified FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_pay_slip_clarified" ON pay_slip_clarified;
CREATE POLICY "tenant_update_pay_slip_clarified" ON pay_slip_clarified FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON projects;
CREATE POLICY "tenant_delete" ON projects FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_projects" ON projects;
CREATE POLICY "tenant_delete_projects" ON projects FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON projects;
CREATE POLICY "tenant_insert" ON projects FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_projects" ON projects;
CREATE POLICY "tenant_insert_projects" ON projects FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON projects;
CREATE POLICY "tenant_select" ON projects FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_projects" ON projects;
CREATE POLICY "tenant_select_projects" ON projects FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON projects;
CREATE POLICY "tenant_update" ON projects FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_projects" ON projects;
CREATE POLICY "tenant_update_projects" ON projects FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_work_stoppages" ON work_stoppages;
CREATE POLICY "tenant_delete_work_stoppages" ON work_stoppages FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_work_stoppages" ON work_stoppages;
CREATE POLICY "tenant_insert_work_stoppages" ON work_stoppages FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_work_stoppages" ON work_stoppages;
CREATE POLICY "tenant_select_work_stoppages" ON work_stoppages FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_work_stoppages" ON work_stoppages;
CREATE POLICY "tenant_update_work_stoppages" ON work_stoppages FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_ijss_history" ON ijss_history;
CREATE POLICY "tenant_delete_ijss_history" ON ijss_history FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_ijss_history" ON ijss_history;
CREATE POLICY "tenant_insert_ijss_history" ON ijss_history FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_ijss_history" ON ijss_history;
CREATE POLICY "tenant_select_ijss_history" ON ijss_history FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_ijss_history" ON ijss_history;
CREATE POLICY "tenant_update_ijss_history" ON ijss_history FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_work_hardship_records" ON work_hardship_records;
CREATE POLICY "tenant_delete_work_hardship_records" ON work_hardship_records FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_work_hardship_records" ON work_hardship_records;
CREATE POLICY "tenant_insert_work_hardship_records" ON work_hardship_records FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_work_hardship_records" ON work_hardship_records;
CREATE POLICY "tenant_select_work_hardship_records" ON work_hardship_records FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_work_hardship_records" ON work_hardship_records;
CREATE POLICY "tenant_update_work_hardship_records" ON work_hardship_records FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_cpf_transactions" ON cpf_transactions;
CREATE POLICY "tenant_delete_cpf_transactions" ON cpf_transactions FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_cpf_transactions" ON cpf_transactions;
CREATE POLICY "tenant_insert_cpf_transactions" ON cpf_transactions FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_cpf_transactions" ON cpf_transactions;
CREATE POLICY "tenant_select_cpf_transactions" ON cpf_transactions FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_cpf_transactions" ON cpf_transactions;
CREATE POLICY "tenant_update_cpf_transactions" ON cpf_transactions FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_medical_exams" ON medical_exams;
CREATE POLICY "tenant_delete_medical_exams" ON medical_exams FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_medical_exams" ON medical_exams;
CREATE POLICY "tenant_insert_medical_exams" ON medical_exams FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_medical_exams" ON medical_exams;
CREATE POLICY "tenant_select_medical_exams" ON medical_exams FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_medical_exams" ON medical_exams;
CREATE POLICY "tenant_update_medical_exams" ON medical_exams FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_expense_categories" ON expense_categories;
CREATE POLICY "tenant_delete_expense_categories" ON expense_categories FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_expense_categories" ON expense_categories;
CREATE POLICY "tenant_insert_expense_categories" ON expense_categories FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_expense_categories" ON expense_categories;
CREATE POLICY "tenant_select_expense_categories" ON expense_categories FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_expense_categories" ON expense_categories;
CREATE POLICY "tenant_update_expense_categories" ON expense_categories FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_interview_campaigns" ON interview_campaigns;
CREATE POLICY "tenant_delete_interview_campaigns" ON interview_campaigns FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_interview_campaigns" ON interview_campaigns;
CREATE POLICY "tenant_insert_interview_campaigns" ON interview_campaigns FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_interview_campaigns" ON interview_campaigns;
CREATE POLICY "tenant_select_interview_campaigns" ON interview_campaigns FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_interview_campaigns" ON interview_campaigns;
CREATE POLICY "tenant_update_interview_campaigns" ON interview_campaigns FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_cice_config" ON cice_config;
CREATE POLICY "tenant_delete_cice_config" ON cice_config FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_cice_config" ON cice_config;
CREATE POLICY "tenant_insert_cice_config" ON cice_config FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_cice_config" ON cice_config;
CREATE POLICY "tenant_select_cice_config" ON cice_config FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_cice_config" ON cice_config;
CREATE POLICY "tenant_update_cice_config" ON cice_config FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_document_distribution_logs" ON document_distribution_logs;
CREATE POLICY "tenant_delete_document_distribution_logs" ON document_distribution_logs FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_document_distribution_logs" ON document_distribution_logs;
CREATE POLICY "tenant_insert_document_distribution_logs" ON document_distribution_logs FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_document_distribution_logs" ON document_distribution_logs;
CREATE POLICY "tenant_select_document_distribution_logs" ON document_distribution_logs FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_document_distribution_logs" ON document_distribution_logs;
CREATE POLICY "tenant_update_document_distribution_logs" ON document_distribution_logs FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_rh_requests" ON rh_requests;
CREATE POLICY "tenant_delete_rh_requests" ON rh_requests FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_rh_requests" ON rh_requests;
CREATE POLICY "tenant_insert_rh_requests" ON rh_requests FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_rh_requests" ON rh_requests;
CREATE POLICY "tenant_select_rh_requests" ON rh_requests FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_rh_requests" ON rh_requests;
CREATE POLICY "tenant_update_rh_requests" ON rh_requests FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_tier_ribs" ON tier_ribs;
CREATE POLICY "tenant_delete_tier_ribs" ON tier_ribs FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_tier_ribs" ON tier_ribs;
CREATE POLICY "tenant_insert_tier_ribs" ON tier_ribs FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_tier_ribs" ON tier_ribs;
CREATE POLICY "tenant_select_tier_ribs" ON tier_ribs FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_tier_ribs" ON tier_ribs;
CREATE POLICY "tenant_update_tier_ribs" ON tier_ribs FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_approval_workflows" ON approval_workflows;
CREATE POLICY "tenant_delete_approval_workflows" ON approval_workflows FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_approval_workflows" ON approval_workflows;
CREATE POLICY "tenant_insert_approval_workflows" ON approval_workflows FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_approval_workflows" ON approval_workflows;
CREATE POLICY "tenant_select_approval_workflows" ON approval_workflows FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_approval_workflows" ON approval_workflows;
CREATE POLICY "tenant_update_approval_workflows" ON approval_workflows FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON asset_families;
CREATE POLICY "tenant_delete" ON asset_families FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_asset_families" ON asset_families;
CREATE POLICY "tenant_delete_asset_families" ON asset_families FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON asset_families;
CREATE POLICY "tenant_insert" ON asset_families FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_asset_families" ON asset_families;
CREATE POLICY "tenant_insert_asset_families" ON asset_families FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON asset_families;
CREATE POLICY "tenant_select" ON asset_families FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_asset_families" ON asset_families;
CREATE POLICY "tenant_select_asset_families" ON asset_families FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON asset_families;
CREATE POLICY "tenant_update" ON asset_families FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_asset_families" ON asset_families;
CREATE POLICY "tenant_update_asset_families" ON asset_families FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON asset_free_fields;
CREATE POLICY "tenant_delete" ON asset_free_fields FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_asset_free_fields" ON asset_free_fields;
CREATE POLICY "tenant_delete_asset_free_fields" ON asset_free_fields FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON asset_free_fields;
CREATE POLICY "tenant_insert" ON asset_free_fields FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_asset_free_fields" ON asset_free_fields;
CREATE POLICY "tenant_insert_asset_free_fields" ON asset_free_fields FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON asset_free_fields;
CREATE POLICY "tenant_select" ON asset_free_fields FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_asset_free_fields" ON asset_free_fields;
CREATE POLICY "tenant_select_asset_free_fields" ON asset_free_fields FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON asset_free_fields;
CREATE POLICY "tenant_update" ON asset_free_fields FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_asset_free_fields" ON asset_free_fields;
CREATE POLICY "tenant_update_asset_free_fields" ON asset_free_fields FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_bank_connections" ON bank_connections;
CREATE POLICY "tenant_delete_bank_connections" ON bank_connections FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_bank_connections" ON bank_connections;
CREATE POLICY "tenant_insert_bank_connections" ON bank_connections FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_bank_connections" ON bank_connections;
CREATE POLICY "tenant_select_bank_connections" ON bank_connections FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_bank_connections" ON bank_connections;
CREATE POLICY "tenant_update_bank_connections" ON bank_connections FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_bdes_indicators" ON bdes_indicators;
CREATE POLICY "tenant_delete_bdes_indicators" ON bdes_indicators FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_bdes_indicators" ON bdes_indicators;
CREATE POLICY "tenant_insert_bdes_indicators" ON bdes_indicators FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_bdes_indicators" ON bdes_indicators;
CREATE POLICY "tenant_select_bdes_indicators" ON bdes_indicators FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_bdes_indicators" ON bdes_indicators;
CREATE POLICY "tenant_update_bdes_indicators" ON bdes_indicators FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_customer_contacts" ON customer_contacts;
CREATE POLICY "tenant_delete_customer_contacts" ON customer_contacts FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_customer_contacts" ON customer_contacts;
CREATE POLICY "tenant_insert_customer_contacts" ON customer_contacts FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_customer_contacts" ON customer_contacts;
CREATE POLICY "tenant_select_customer_contacts" ON customer_contacts FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_customer_contacts" ON customer_contacts;
CREATE POLICY "tenant_update_customer_contacts" ON customer_contacts FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_distribution_grill_lines" ON distribution_grill_lines;
CREATE POLICY "tenant_delete_distribution_grill_lines" ON distribution_grill_lines FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_distribution_grill_lines" ON distribution_grill_lines;
CREATE POLICY "tenant_insert_distribution_grill_lines" ON distribution_grill_lines FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_distribution_grill_lines" ON distribution_grill_lines;
CREATE POLICY "tenant_select_distribution_grill_lines" ON distribution_grill_lines FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_distribution_grill_lines" ON distribution_grill_lines;
CREATE POLICY "tenant_update_distribution_grill_lines" ON distribution_grill_lines FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_distribution_grills" ON distribution_grills;
CREATE POLICY "tenant_delete_distribution_grills" ON distribution_grills FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_distribution_grills" ON distribution_grills;
CREATE POLICY "tenant_insert_distribution_grills" ON distribution_grills FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_distribution_grills" ON distribution_grills;
CREATE POLICY "tenant_select_distribution_grills" ON distribution_grills FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_distribution_grills" ON distribution_grills;
CREATE POLICY "tenant_update_distribution_grills" ON distribution_grills FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_document_charges" ON document_charges;
CREATE POLICY "tenant_delete_document_charges" ON document_charges FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_document_charges" ON document_charges;
CREATE POLICY "tenant_insert_document_charges" ON document_charges FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_document_charges" ON document_charges;
CREATE POLICY "tenant_select_document_charges" ON document_charges FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_document_charges" ON document_charges;
CREATE POLICY "tenant_update_document_charges" ON document_charges FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON future_accounting_movements;
CREATE POLICY "tenant_delete" ON future_accounting_movements FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_future_accounting_movements" ON future_accounting_movements;
CREATE POLICY "tenant_delete_future_accounting_movements" ON future_accounting_movements FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON future_accounting_movements;
CREATE POLICY "tenant_insert" ON future_accounting_movements FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_future_accounting_movements" ON future_accounting_movements;
CREATE POLICY "tenant_insert_future_accounting_movements" ON future_accounting_movements FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON future_accounting_movements;
CREATE POLICY "tenant_select" ON future_accounting_movements FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_future_accounting_movements" ON future_accounting_movements;
CREATE POLICY "tenant_select_future_accounting_movements" ON future_accounting_movements FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON future_accounting_movements;
CREATE POLICY "tenant_update" ON future_accounting_movements FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_future_accounting_movements" ON future_accounting_movements;
CREATE POLICY "tenant_update_future_accounting_movements" ON future_accounting_movements FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON interviews;
CREATE POLICY "tenant_delete" ON interviews FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_interviews" ON interviews;
CREATE POLICY "tenant_delete_interviews" ON interviews FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON interviews;
CREATE POLICY "tenant_insert" ON interviews FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_interviews" ON interviews;
CREATE POLICY "tenant_insert_interviews" ON interviews FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON interviews;
CREATE POLICY "tenant_select" ON interviews FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_interviews" ON interviews;
CREATE POLICY "tenant_select_interviews" ON interviews FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON interviews;
CREATE POLICY "tenant_update" ON interviews FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_interviews" ON interviews;
CREATE POLICY "tenant_update_interviews" ON interviews FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_leave_provisions" ON leave_provisions;
CREATE POLICY "tenant_delete_leave_provisions" ON leave_provisions FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_leave_provisions" ON leave_provisions;
CREATE POLICY "tenant_insert_leave_provisions" ON leave_provisions FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_leave_provisions" ON leave_provisions;
CREATE POLICY "tenant_select_leave_provisions" ON leave_provisions FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_leave_provisions" ON leave_provisions;
CREATE POLICY "tenant_update_leave_provisions" ON leave_provisions FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_meal_voucher_config" ON meal_voucher_config;
CREATE POLICY "tenant_delete_meal_voucher_config" ON meal_voucher_config FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_meal_voucher_config" ON meal_voucher_config;
CREATE POLICY "tenant_insert_meal_voucher_config" ON meal_voucher_config FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_meal_voucher_config" ON meal_voucher_config;
CREATE POLICY "tenant_select_meal_voucher_config" ON meal_voucher_config FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_meal_voucher_config" ON meal_voucher_config;
CREATE POLICY "tenant_update_meal_voucher_config" ON meal_voucher_config FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_partner_contacts" ON partner_contacts;
CREATE POLICY "tenant_delete_partner_contacts" ON partner_contacts FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_partner_contacts" ON partner_contacts;
CREATE POLICY "tenant_insert_partner_contacts" ON partner_contacts FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_partner_contacts" ON partner_contacts;
CREATE POLICY "tenant_select_partner_contacts" ON partner_contacts FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_partner_contacts" ON partner_contacts;
CREATE POLICY "tenant_update_partner_contacts" ON partner_contacts FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_pas_rates" ON pas_rates;
CREATE POLICY "tenant_delete_pas_rates" ON pas_rates FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_pas_rates" ON pas_rates;
CREATE POLICY "tenant_insert_pas_rates" ON pas_rates FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_pas_rates" ON pas_rates;
CREATE POLICY "tenant_select_pas_rates" ON pas_rates FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_pas_rates" ON pas_rates;
CREATE POLICY "tenant_update_pas_rates" ON pas_rates FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON pay_recalls;
CREATE POLICY "tenant_delete" ON pay_recalls FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_pay_recalls" ON pay_recalls;
CREATE POLICY "tenant_delete_pay_recalls" ON pay_recalls FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON pay_recalls;
CREATE POLICY "tenant_insert" ON pay_recalls FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_pay_recalls" ON pay_recalls;
CREATE POLICY "tenant_insert_pay_recalls" ON pay_recalls FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON pay_recalls;
CREATE POLICY "tenant_select" ON pay_recalls FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_pay_recalls" ON pay_recalls;
CREATE POLICY "tenant_select_pay_recalls" ON pay_recalls FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON pay_recalls;
CREATE POLICY "tenant_update" ON pay_recalls FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_pay_recalls" ON pay_recalls;
CREATE POLICY "tenant_update_pay_recalls" ON pay_recalls FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON payroll_archives;
CREATE POLICY "tenant_delete" ON payroll_archives FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_payroll_archives" ON payroll_archives;
CREATE POLICY "tenant_delete_payroll_archives" ON payroll_archives FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON payroll_archives;
CREATE POLICY "tenant_insert" ON payroll_archives FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_payroll_archives" ON payroll_archives;
CREATE POLICY "tenant_insert_payroll_archives" ON payroll_archives FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON payroll_archives;
CREATE POLICY "tenant_select" ON payroll_archives FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_payroll_archives" ON payroll_archives;
CREATE POLICY "tenant_select_payroll_archives" ON payroll_archives FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON payroll_archives;
CREATE POLICY "tenant_update" ON payroll_archives FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_payroll_archives" ON payroll_archives;
CREATE POLICY "tenant_update_payroll_archives" ON payroll_archives FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON payroll_components;
CREATE POLICY "tenant_delete" ON payroll_components FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_payroll_components" ON payroll_components;
CREATE POLICY "tenant_delete_payroll_components" ON payroll_components FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON payroll_components;
CREATE POLICY "tenant_insert" ON payroll_components FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_payroll_components" ON payroll_components;
CREATE POLICY "tenant_insert_payroll_components" ON payroll_components FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON payroll_components;
CREATE POLICY "tenant_select" ON payroll_components FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_payroll_components" ON payroll_components;
CREATE POLICY "tenant_select_payroll_components" ON payroll_components FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON payroll_components;
CREATE POLICY "tenant_update" ON payroll_components FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_payroll_components" ON payroll_components;
CREATE POLICY "tenant_update_payroll_components" ON payroll_components FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON payroll_templates;
CREATE POLICY "tenant_delete" ON payroll_templates FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_payroll_templates" ON payroll_templates;
CREATE POLICY "tenant_delete_payroll_templates" ON payroll_templates FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON payroll_templates;
CREATE POLICY "tenant_insert" ON payroll_templates FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_payroll_templates" ON payroll_templates;
CREATE POLICY "tenant_insert_payroll_templates" ON payroll_templates FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON payroll_templates;
CREATE POLICY "tenant_select" ON payroll_templates FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_payroll_templates" ON payroll_templates;
CREATE POLICY "tenant_select_payroll_templates" ON payroll_templates FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON payroll_templates;
CREATE POLICY "tenant_update" ON payroll_templates FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_payroll_templates" ON payroll_templates;
CREATE POLICY "tenant_update_payroll_templates" ON payroll_templates FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON product_attributes;
CREATE POLICY "tenant_delete" ON product_attributes FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_product_attributes" ON product_attributes;
CREATE POLICY "tenant_delete_product_attributes" ON product_attributes FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON product_attributes;
CREATE POLICY "tenant_insert" ON product_attributes FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_product_attributes" ON product_attributes;
CREATE POLICY "tenant_insert_product_attributes" ON product_attributes FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON product_attributes;
CREATE POLICY "tenant_select" ON product_attributes FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_product_attributes" ON product_attributes;
CREATE POLICY "tenant_select_product_attributes" ON product_attributes FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON product_attributes;
CREATE POLICY "tenant_update" ON product_attributes FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_product_attributes" ON product_attributes;
CREATE POLICY "tenant_update_product_attributes" ON product_attributes FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_product_packagings" ON product_packagings;
CREATE POLICY "tenant_delete_product_packagings" ON product_packagings FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_product_packagings" ON product_packagings;
CREATE POLICY "tenant_insert_product_packagings" ON product_packagings FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_product_packagings" ON product_packagings;
CREATE POLICY "tenant_select_product_packagings" ON product_packagings FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_product_packagings" ON product_packagings;
CREATE POLICY "tenant_update_product_packagings" ON product_packagings FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_promotions" ON promotions;
CREATE POLICY "tenant_delete_promotions" ON promotions FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_promotions" ON promotions;
CREATE POLICY "tenant_insert_promotions" ON promotions FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_promotions" ON promotions;
CREATE POLICY "tenant_select_promotions" ON promotions FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_promotions" ON promotions;
CREATE POLICY "tenant_update_promotions" ON promotions FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON prospects;
CREATE POLICY "tenant_delete" ON prospects FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_prospects" ON prospects;
CREATE POLICY "tenant_delete_prospects" ON prospects FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON prospects;
CREATE POLICY "tenant_insert" ON prospects FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_prospects" ON prospects;
CREATE POLICY "tenant_insert_prospects" ON prospects FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON prospects;
CREATE POLICY "tenant_select" ON prospects FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_prospects" ON prospects;
CREATE POLICY "tenant_select_prospects" ON prospects FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON prospects;
CREATE POLICY "tenant_update" ON prospects FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_prospects" ON prospects;
CREATE POLICY "tenant_update_prospects" ON prospects FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "global_select_public_holidays" ON public_holidays;
CREATE POLICY "global_select_public_holidays" ON public_holidays FOR SELECT USING ((auth.uid() IS NOT NULL));
DROP POLICY IF EXISTS "tenant_delete_purchase_request_lines" ON purchase_request_lines;
CREATE POLICY "tenant_delete_purchase_request_lines" ON purchase_request_lines FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_purchase_request_lines" ON purchase_request_lines;
CREATE POLICY "tenant_insert_purchase_request_lines" ON purchase_request_lines FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_purchase_request_lines" ON purchase_request_lines;
CREATE POLICY "tenant_select_purchase_request_lines" ON purchase_request_lines FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_purchase_request_lines" ON purchase_request_lines;
CREATE POLICY "tenant_update_purchase_request_lines" ON purchase_request_lines FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_purchase_requests" ON purchase_requests;
CREATE POLICY "tenant_delete_purchase_requests" ON purchase_requests FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_purchase_requests" ON purchase_requests;
CREATE POLICY "tenant_insert_purchase_requests" ON purchase_requests FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_purchase_requests" ON purchase_requests;
CREATE POLICY "tenant_select_purchase_requests" ON purchase_requests FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_purchase_requests" ON purchase_requests;
CREATE POLICY "tenant_update_purchase_requests" ON purchase_requests FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_regularization_entries" ON regularization_entries;
CREATE POLICY "tenant_delete_regularization_entries" ON regularization_entries FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_regularization_entries" ON regularization_entries;
CREATE POLICY "tenant_insert_regularization_entries" ON regularization_entries FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_regularization_entries" ON regularization_entries;
CREATE POLICY "tenant_select_regularization_entries" ON regularization_entries FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_regularization_entries" ON regularization_entries;
CREATE POLICY "tenant_update_regularization_entries" ON regularization_entries FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON salary_advances;
CREATE POLICY "tenant_delete" ON salary_advances FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_salary_advances" ON salary_advances;
CREATE POLICY "tenant_delete_salary_advances" ON salary_advances FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON salary_advances;
CREATE POLICY "tenant_insert" ON salary_advances FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_salary_advances" ON salary_advances;
CREATE POLICY "tenant_insert_salary_advances" ON salary_advances FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON salary_advances;
CREATE POLICY "tenant_select" ON salary_advances FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_salary_advances" ON salary_advances;
CREATE POLICY "tenant_select_salary_advances" ON salary_advances FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON salary_advances;
CREATE POLICY "tenant_update" ON salary_advances FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_salary_advances" ON salary_advances;
CREATE POLICY "tenant_update_salary_advances" ON salary_advances FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON sales_representatives;
CREATE POLICY "tenant_delete" ON sales_representatives FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_sales_representatives" ON sales_representatives;
CREATE POLICY "tenant_delete_sales_representatives" ON sales_representatives FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON sales_representatives;
CREATE POLICY "tenant_insert" ON sales_representatives FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_sales_representatives" ON sales_representatives;
CREATE POLICY "tenant_insert_sales_representatives" ON sales_representatives FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON sales_representatives;
CREATE POLICY "tenant_select" ON sales_representatives FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_sales_representatives" ON sales_representatives;
CREATE POLICY "tenant_select_sales_representatives" ON sales_representatives FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON sales_representatives;
CREATE POLICY "tenant_update" ON sales_representatives FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_sales_representatives" ON sales_representatives;
CREATE POLICY "tenant_update_sales_representatives" ON sales_representatives FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_saved_filters" ON saved_filters;
CREATE POLICY "tenant_delete_saved_filters" ON saved_filters FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_saved_filters" ON saved_filters;
CREATE POLICY "tenant_insert_saved_filters" ON saved_filters FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_saved_filters" ON saved_filters;
CREATE POLICY "tenant_select_saved_filters" ON saved_filters FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_saved_filters" ON saved_filters;
CREATE POLICY "tenant_update_saved_filters" ON saved_filters FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_social_declarations" ON social_declarations;
CREATE POLICY "tenant_delete_social_declarations" ON social_declarations FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_social_declarations" ON social_declarations;
CREATE POLICY "tenant_insert_social_declarations" ON social_declarations FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_social_declarations" ON social_declarations;
CREATE POLICY "tenant_select_social_declarations" ON social_declarations FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_social_declarations" ON social_declarations;
CREATE POLICY "tenant_update_social_declarations" ON social_declarations FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_staff_requirements" ON staff_requirements;
CREATE POLICY "tenant_delete_staff_requirements" ON staff_requirements FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_staff_requirements" ON staff_requirements;
CREATE POLICY "tenant_insert_staff_requirements" ON staff_requirements FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_staff_requirements" ON staff_requirements;
CREATE POLICY "tenant_select_staff_requirements" ON staff_requirements FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_staff_requirements" ON staff_requirements;
CREATE POLICY "tenant_update_staff_requirements" ON staff_requirements FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_warehouse_users" ON warehouse_users;
CREATE POLICY "tenant_delete_warehouse_users" ON warehouse_users FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_warehouse_users" ON warehouse_users;
CREATE POLICY "tenant_insert_warehouse_users" ON warehouse_users FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_warehouse_users" ON warehouse_users;
CREATE POLICY "tenant_select_warehouse_users" ON warehouse_users FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_warehouse_users" ON warehouse_users;
CREATE POLICY "tenant_update_warehouse_users" ON warehouse_users FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON work_hardship;
CREATE POLICY "tenant_delete" ON work_hardship FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_work_hardship" ON work_hardship;
CREATE POLICY "tenant_delete_work_hardship" ON work_hardship FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON work_hardship;
CREATE POLICY "tenant_insert" ON work_hardship FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_work_hardship" ON work_hardship;
CREATE POLICY "tenant_insert_work_hardship" ON work_hardship FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON work_hardship;
CREATE POLICY "tenant_select" ON work_hardship FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_work_hardship" ON work_hardship;
CREATE POLICY "tenant_select_work_hardship" ON work_hardship FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON work_hardship;
CREATE POLICY "tenant_update" ON work_hardship FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_work_hardship" ON work_hardship;
CREATE POLICY "tenant_update_work_hardship" ON work_hardship FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON standard_labels;
CREATE POLICY "tenant_delete" ON standard_labels FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_standard_labels" ON standard_labels;
CREATE POLICY "tenant_delete_standard_labels" ON standard_labels FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON standard_labels;
CREATE POLICY "tenant_insert" ON standard_labels FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_standard_labels" ON standard_labels;
CREATE POLICY "tenant_insert_standard_labels" ON standard_labels FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON standard_labels;
CREATE POLICY "tenant_select" ON standard_labels FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_standard_labels" ON standard_labels;
CREATE POLICY "tenant_select_standard_labels" ON standard_labels FOR SELECT USING (((tenant_id = current_tenant_id()) OR (tenant_id IS NULL)));
DROP POLICY IF EXISTS "tenant_update" ON standard_labels;
CREATE POLICY "tenant_update" ON standard_labels FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_standard_labels" ON standard_labels;
CREATE POLICY "tenant_update_standard_labels" ON standard_labels FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_rh_dashboard_configs" ON rh_dashboard_configs;
CREATE POLICY "tenant_delete_rh_dashboard_configs" ON rh_dashboard_configs FOR DELETE USING (((tenant_id = current_tenant_id()) AND can_perform('rh_dashboard_configs'::text, 'delete'::text)));
DROP POLICY IF EXISTS "tenant_insert_rh_dashboard_configs" ON rh_dashboard_configs;
CREATE POLICY "tenant_insert_rh_dashboard_configs" ON rh_dashboard_configs FOR INSERT WITH CHECK (((tenant_id = current_tenant_id()) AND can_perform('rh_dashboard_configs'::text, 'insert'::text)));
DROP POLICY IF EXISTS "tenant_select_rh_dashboard_configs" ON rh_dashboard_configs;
CREATE POLICY "tenant_select_rh_dashboard_configs" ON rh_dashboard_configs FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_rh_dashboard_configs" ON rh_dashboard_configs;
CREATE POLICY "tenant_update_rh_dashboard_configs" ON rh_dashboard_configs FOR UPDATE USING (((tenant_id = current_tenant_id()) AND can_perform('rh_dashboard_configs'::text, 'update'::text))) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_rh_reports" ON rh_reports;
CREATE POLICY "tenant_delete_rh_reports" ON rh_reports FOR DELETE USING (((tenant_id = current_tenant_id()) AND can_perform('rh_reports'::text, 'delete'::text)));
DROP POLICY IF EXISTS "tenant_insert_rh_reports" ON rh_reports;
CREATE POLICY "tenant_insert_rh_reports" ON rh_reports FOR INSERT WITH CHECK (((tenant_id = current_tenant_id()) AND can_perform('rh_reports'::text, 'insert'::text)));
DROP POLICY IF EXISTS "tenant_select_rh_reports" ON rh_reports;
CREATE POLICY "tenant_select_rh_reports" ON rh_reports FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_rh_reports" ON rh_reports;
CREATE POLICY "tenant_update_rh_reports" ON rh_reports FOR UPDATE USING (((tenant_id = current_tenant_id()) AND can_perform('rh_reports'::text, 'update'::text))) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON journals;
CREATE POLICY "tenant_delete" ON journals FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_journals" ON journals;
CREATE POLICY "tenant_delete_journals" ON journals FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON journals;
CREATE POLICY "tenant_insert" ON journals FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_journals" ON journals;
CREATE POLICY "tenant_insert_journals" ON journals FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON journals;
CREATE POLICY "tenant_select" ON journals FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_journals" ON journals;
CREATE POLICY "tenant_select_journals" ON journals FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON journals;
CREATE POLICY "tenant_update" ON journals FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_journals" ON journals;
CREATE POLICY "tenant_update_journals" ON journals FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_project_tasks" ON project_tasks;
CREATE POLICY "tenant_delete_project_tasks" ON project_tasks FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_project_tasks" ON project_tasks;
CREATE POLICY "tenant_insert_project_tasks" ON project_tasks FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_project_tasks" ON project_tasks;
CREATE POLICY "tenant_select_project_tasks" ON project_tasks FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_project_tasks" ON project_tasks;
CREATE POLICY "tenant_update_project_tasks" ON project_tasks FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_project_task_deps" ON project_task_dependencies;
CREATE POLICY "tenant_delete_project_task_deps" ON project_task_dependencies FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_project_task_deps" ON project_task_dependencies;
CREATE POLICY "tenant_insert_project_task_deps" ON project_task_dependencies FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_project_task_deps" ON project_task_dependencies;
CREATE POLICY "tenant_select_project_task_deps" ON project_task_dependencies FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_project_task_deps" ON project_task_dependencies;
CREATE POLICY "tenant_update_project_task_deps" ON project_task_dependencies FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_project_stages" ON project_stages;
CREATE POLICY "tenant_delete_project_stages" ON project_stages FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_project_stages" ON project_stages;
CREATE POLICY "tenant_insert_project_stages" ON project_stages FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_project_stages" ON project_stages;
CREATE POLICY "tenant_select_project_stages" ON project_stages FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_project_stages" ON project_stages;
CREATE POLICY "tenant_update_project_stages" ON project_stages FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_project_milestones" ON project_milestones;
CREATE POLICY "tenant_delete_project_milestones" ON project_milestones FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_project_milestones" ON project_milestones;
CREATE POLICY "tenant_insert_project_milestones" ON project_milestones FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_project_milestones" ON project_milestones;
CREATE POLICY "tenant_select_project_milestones" ON project_milestones FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_project_milestones" ON project_milestones;
CREATE POLICY "tenant_update_project_milestones" ON project_milestones FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_project_tags" ON project_tags;
CREATE POLICY "tenant_delete_project_tags" ON project_tags FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_project_tags" ON project_tags;
CREATE POLICY "tenant_insert_project_tags" ON project_tags FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_project_tags" ON project_tags;
CREATE POLICY "tenant_select_project_tags" ON project_tags FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_project_tags" ON project_tags;
CREATE POLICY "tenant_update_project_tags" ON project_tags FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_project_task_tags" ON project_task_tags;
CREATE POLICY "tenant_delete_project_task_tags" ON project_task_tags FOR DELETE USING ((EXISTS ( SELECT 1
   FROM project_tasks
  WHERE ((project_tasks.id = project_task_tags.task_id) AND (project_tasks.tenant_id = current_tenant_id())))));
DROP POLICY IF EXISTS "tenant_insert_project_task_tags" ON project_task_tags;
CREATE POLICY "tenant_insert_project_task_tags" ON project_task_tags FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM project_tasks
  WHERE ((project_tasks.id = project_task_tags.task_id) AND (project_tasks.tenant_id = current_tenant_id())))));
DROP POLICY IF EXISTS "tenant_select_project_task_tags" ON project_task_tags;
CREATE POLICY "tenant_select_project_task_tags" ON project_task_tags FOR SELECT USING ((EXISTS ( SELECT 1
   FROM project_tasks
  WHERE ((project_tasks.id = project_task_tags.task_id) AND (project_tasks.tenant_id = current_tenant_id())))));
DROP POLICY IF EXISTS "tenant_delete_reimputation_logs" ON reimputation_logs;
CREATE POLICY "tenant_delete_reimputation_logs" ON reimputation_logs FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_reimputation_logs" ON reimputation_logs;
CREATE POLICY "tenant_insert_reimputation_logs" ON reimputation_logs FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_reimputation_logs" ON reimputation_logs;
CREATE POLICY "tenant_select_reimputation_logs" ON reimputation_logs FOR SELECT USING (((tenant_id = current_tenant_id()) OR (tenant_id IS NULL)));
DROP POLICY IF EXISTS "tenant_update_reimputation_logs" ON reimputation_logs;
CREATE POLICY "tenant_update_reimputation_logs" ON reimputation_logs FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_watchers" ON project_task_watchers;
CREATE POLICY "tenant_delete_watchers" ON project_task_watchers FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_watchers" ON project_task_watchers;
CREATE POLICY "tenant_insert_watchers" ON project_task_watchers FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_watchers" ON project_task_watchers;
CREATE POLICY "tenant_select_watchers" ON project_task_watchers FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_time_entries" ON project_time_entries;
CREATE POLICY "tenant_delete_time_entries" ON project_time_entries FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_time_entries" ON project_time_entries;
CREATE POLICY "tenant_insert_time_entries" ON project_time_entries FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_time_entries" ON project_time_entries;
CREATE POLICY "tenant_select_time_entries" ON project_time_entries FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_time_entries" ON project_time_entries;
CREATE POLICY "tenant_update_time_entries" ON project_time_entries FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON asset_revaluations;
CREATE POLICY "tenant_delete" ON asset_revaluations FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_asset_revaluations" ON asset_revaluations;
CREATE POLICY "tenant_delete_asset_revaluations" ON asset_revaluations FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON asset_revaluations;
CREATE POLICY "tenant_insert" ON asset_revaluations FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_asset_revaluations" ON asset_revaluations;
CREATE POLICY "tenant_insert_asset_revaluations" ON asset_revaluations FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON asset_revaluations;
CREATE POLICY "tenant_select" ON asset_revaluations FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_asset_revaluations" ON asset_revaluations;
CREATE POLICY "tenant_select_asset_revaluations" ON asset_revaluations FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON asset_revaluations;
CREATE POLICY "tenant_update" ON asset_revaluations FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_asset_revaluations" ON asset_revaluations;
CREATE POLICY "tenant_update_asset_revaluations" ON asset_revaluations FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON asset_batch_disposals;
CREATE POLICY "tenant_delete" ON asset_batch_disposals FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_asset_batch_disposals" ON asset_batch_disposals;
CREATE POLICY "tenant_delete_asset_batch_disposals" ON asset_batch_disposals FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON asset_batch_disposals;
CREATE POLICY "tenant_insert" ON asset_batch_disposals FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_asset_batch_disposals" ON asset_batch_disposals;
CREATE POLICY "tenant_insert_asset_batch_disposals" ON asset_batch_disposals FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON asset_batch_disposals;
CREATE POLICY "tenant_select" ON asset_batch_disposals FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_asset_batch_disposals" ON asset_batch_disposals;
CREATE POLICY "tenant_select_asset_batch_disposals" ON asset_batch_disposals FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON asset_batch_disposals;
CREATE POLICY "tenant_update" ON asset_batch_disposals FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_asset_batch_disposals" ON asset_batch_disposals;
CREATE POLICY "tenant_update_asset_batch_disposals" ON asset_batch_disposals FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_employee_activity_logs" ON employee_activity_logs;
CREATE POLICY "tenant_delete_employee_activity_logs" ON employee_activity_logs FOR DELETE USING (((tenant_id = current_tenant_id()) AND can_perform('employee_activity_logs'::text, 'delete'::text)));
DROP POLICY IF EXISTS "tenant_insert_employee_activity_logs" ON employee_activity_logs;
CREATE POLICY "tenant_insert_employee_activity_logs" ON employee_activity_logs FOR INSERT WITH CHECK (((tenant_id = current_tenant_id()) AND can_perform('employee_activity_logs'::text, 'insert'::text)));
DROP POLICY IF EXISTS "tenant_select_employee_activity_logs" ON employee_activity_logs;
CREATE POLICY "tenant_select_employee_activity_logs" ON employee_activity_logs FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_employee_activity_logs" ON employee_activity_logs;
CREATE POLICY "tenant_update_employee_activity_logs" ON employee_activity_logs FOR UPDATE USING (((tenant_id = current_tenant_id()) AND can_perform('employee_activity_logs'::text, 'update'::text))) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "global_select_legislation_packs" ON legislation_packs;
CREATE POLICY "global_select_legislation_packs" ON legislation_packs FOR SELECT USING ((auth.uid() IS NOT NULL));
DROP POLICY IF EXISTS "global_select_tax_rates" ON tax_rates;
CREATE POLICY "global_select_tax_rates" ON tax_rates FOR SELECT USING ((auth.uid() IS NOT NULL));
DROP POLICY IF EXISTS "global_select_banks" ON banks;
CREATE POLICY "global_select_banks" ON banks FOR SELECT USING ((auth.uid() IS NOT NULL));
DROP POLICY IF EXISTS "tenant_delete_supplier_price_lists" ON supplier_price_lists;
CREATE POLICY "tenant_delete_supplier_price_lists" ON supplier_price_lists FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_supplier_price_lists" ON supplier_price_lists;
CREATE POLICY "tenant_insert_supplier_price_lists" ON supplier_price_lists FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_supplier_price_lists" ON supplier_price_lists;
CREATE POLICY "tenant_select_supplier_price_lists" ON supplier_price_lists FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_supplier_price_lists" ON supplier_price_lists;
CREATE POLICY "tenant_update_supplier_price_lists" ON supplier_price_lists FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON treasury_recurring;
CREATE POLICY "tenant_delete" ON treasury_recurring FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_treasury_recurring" ON treasury_recurring;
CREATE POLICY "tenant_delete_treasury_recurring" ON treasury_recurring FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON treasury_recurring;
CREATE POLICY "tenant_insert" ON treasury_recurring FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_treasury_recurring" ON treasury_recurring;
CREATE POLICY "tenant_insert_treasury_recurring" ON treasury_recurring FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON treasury_recurring;
CREATE POLICY "tenant_select" ON treasury_recurring FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_treasury_recurring" ON treasury_recurring;
CREATE POLICY "tenant_select_treasury_recurring" ON treasury_recurring FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON treasury_recurring;
CREATE POLICY "tenant_update" ON treasury_recurring FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_treasury_recurring" ON treasury_recurring;
CREATE POLICY "tenant_update_treasury_recurring" ON treasury_recurring FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_tvs_declarations" ON tvs_declarations;
CREATE POLICY "tenant_delete_tvs_declarations" ON tvs_declarations FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_tvs_declarations" ON tvs_declarations;
CREATE POLICY "tenant_insert_tvs_declarations" ON tvs_declarations FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_tvs_declarations" ON tvs_declarations;
CREATE POLICY "tenant_select_tvs_declarations" ON tvs_declarations FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_tvs_declarations" ON tvs_declarations;
CREATE POLICY "tenant_update_tvs_declarations" ON tvs_declarations FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON value_date_tracking;
CREATE POLICY "tenant_delete" ON value_date_tracking FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_value_date_tracking" ON value_date_tracking;
CREATE POLICY "tenant_delete_value_date_tracking" ON value_date_tracking FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON value_date_tracking;
CREATE POLICY "tenant_insert" ON value_date_tracking FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_value_date_tracking" ON value_date_tracking;
CREATE POLICY "tenant_insert_value_date_tracking" ON value_date_tracking FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON value_date_tracking;
CREATE POLICY "tenant_select" ON value_date_tracking FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_value_date_tracking" ON value_date_tracking;
CREATE POLICY "tenant_select_value_date_tracking" ON value_date_tracking FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON value_date_tracking;
CREATE POLICY "tenant_update" ON value_date_tracking FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_value_date_tracking" ON value_date_tracking;
CREATE POLICY "tenant_update_value_date_tracking" ON value_date_tracking FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON warehouse_locations;
CREATE POLICY "tenant_delete" ON warehouse_locations FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_warehouse_locations" ON warehouse_locations;
CREATE POLICY "tenant_delete_warehouse_locations" ON warehouse_locations FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON warehouse_locations;
CREATE POLICY "tenant_insert" ON warehouse_locations FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_warehouse_locations" ON warehouse_locations;
CREATE POLICY "tenant_insert_warehouse_locations" ON warehouse_locations FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON warehouse_locations;
CREATE POLICY "tenant_select" ON warehouse_locations FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_warehouse_locations" ON warehouse_locations;
CREATE POLICY "tenant_select_warehouse_locations" ON warehouse_locations FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON warehouse_locations;
CREATE POLICY "tenant_update" ON warehouse_locations FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_warehouse_locations" ON warehouse_locations;
CREATE POLICY "tenant_update_warehouse_locations" ON warehouse_locations FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete" ON employees;
CREATE POLICY "tenant_delete" ON employees FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_employees" ON employees;
CREATE POLICY "tenant_delete_employees" ON employees FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert" ON employees;
CREATE POLICY "tenant_insert" ON employees FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_employees" ON employees;
CREATE POLICY "tenant_insert_employees" ON employees FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select" ON employees;
CREATE POLICY "tenant_select" ON employees FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_employees" ON employees;
CREATE POLICY "tenant_select_employees" ON employees FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update" ON employees;
CREATE POLICY "tenant_update" ON employees FOR UPDATE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_employees" ON employees;
CREATE POLICY "tenant_update_employees" ON employees FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_project_task_assignees" ON project_task_assignees;
CREATE POLICY "tenant_delete_project_task_assignees" ON project_task_assignees FOR DELETE USING ((EXISTS ( SELECT 1
   FROM project_tasks
  WHERE ((project_tasks.id = project_task_assignees.task_id) AND (project_tasks.tenant_id = current_tenant_id())))));
DROP POLICY IF EXISTS "tenant_insert_project_task_assignees" ON project_task_assignees;
CREATE POLICY "tenant_insert_project_task_assignees" ON project_task_assignees FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM project_tasks
  WHERE ((project_tasks.id = project_task_assignees.task_id) AND (project_tasks.tenant_id = current_tenant_id())))));
DROP POLICY IF EXISTS "tenant_select_project_task_assignees" ON project_task_assignees;
CREATE POLICY "tenant_select_project_task_assignees" ON project_task_assignees FOR SELECT USING ((EXISTS ( SELECT 1
   FROM project_tasks
  WHERE ((project_tasks.id = project_task_assignees.task_id) AND (project_tasks.tenant_id = current_tenant_id())))));
DROP POLICY IF EXISTS "tenant_delete_task_actions" ON task_actions;
CREATE POLICY "tenant_delete_task_actions" ON task_actions FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_task_actions" ON task_actions;
CREATE POLICY "tenant_insert_task_actions" ON task_actions FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_task_actions" ON task_actions;
CREATE POLICY "tenant_select_task_actions" ON task_actions FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_task_actions" ON task_actions;
CREATE POLICY "tenant_update_task_actions" ON task_actions FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_task_action_att" ON task_action_attachments;
CREATE POLICY "tenant_delete_task_action_att" ON task_action_attachments FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_task_action_att" ON task_action_attachments;
CREATE POLICY "tenant_insert_task_action_att" ON task_action_attachments FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_task_action_att" ON task_action_attachments;
CREATE POLICY "tenant_select_task_action_att" ON task_action_attachments FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_task_action_att" ON task_action_attachments;
CREATE POLICY "tenant_update_task_action_att" ON task_action_attachments FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_task_documents" ON task_documents;
CREATE POLICY "tenant_delete_task_documents" ON task_documents FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_task_documents" ON task_documents;
CREATE POLICY "tenant_insert_task_documents" ON task_documents FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_task_documents" ON task_documents;
CREATE POLICY "tenant_select_task_documents" ON task_documents FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_task_documents" ON task_documents;
CREATE POLICY "tenant_update_task_documents" ON task_documents FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_delete_task_comments" ON task_comments;
CREATE POLICY "tenant_delete_task_comments" ON task_comments FOR DELETE USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_insert_task_comments" ON task_comments;
CREATE POLICY "tenant_insert_task_comments" ON task_comments FOR INSERT WITH CHECK ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_select_task_comments" ON task_comments;
CREATE POLICY "tenant_select_task_comments" ON task_comments FOR SELECT USING ((tenant_id = current_tenant_id()));
DROP POLICY IF EXISTS "tenant_update_task_comments" ON task_comments;
CREATE POLICY "tenant_update_task_comments" ON task_comments FOR UPDATE USING ((tenant_id = current_tenant_id())) WITH CHECK ((tenant_id = current_tenant_id()));

-- ============================================
-- VRAIES FONCTIONS
-- ============================================
CREATE OR REPLACE FUNCTION public.auth_email_exists(p_email text)
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'auth', 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM auth.users
    WHERE email = lower(trim(p_email))
  );
$function$;


CREATE OR REPLACE FUNCTION public.auto_revoke_expired_auditors()
 RETURNS integer
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH expired AS (
    UPDATE tenant_users
    SET status = 'revoked',
        updated_at = now()
    WHERE role = 'auditor'
      AND status = 'active'
      AND valid_until IS NOT NULL
      AND valid_until < CURRENT_DATE
    RETURNING id
  )
  SELECT count(*)::integer FROM expired;
$function$;


CREATE OR REPLACE FUNCTION public.bootstrap_tenant(p_tenant_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_tenant record;
  v_year int := EXTRACT(YEAR FROM CURRENT_DATE)::int;
  v_fy_id uuid;
  v_month int;
  v_period_start date;
  v_period_end date;
  v_labels text[] := ARRAY['Janvier','Fevrier','Mars','Avril','Mai','Juin','Juillet','Aout','Septembre','Octobre','Novembre','Decembre'];
BEGIN
  SELECT * INTO v_tenant FROM tenants WHERE id = p_tenant_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Tenant % not found', p_tenant_id;
  END IF;

  -- 1. CHART OF ACCOUNTS — seed directly via seed_standard_chart()
  IF NOT EXISTS (SELECT 1 FROM chart_accounts WHERE tenant_id = p_tenant_id) THEN
    PERFORM seed_standard_chart(p_tenant_id);
  END IF;

  -- 2. STANDARD JOURNALS
  INSERT INTO journals (code, name, type, account_counterpart, status, locked, tenant_id)
  VALUES
    ('VT', 'Journal des ventes',        'sale',     '411000', 'active', false, p_tenant_id),
    ('AC', 'Journal des achats',        'purchase', '401000', 'active', false, p_tenant_id),
    ('BQ', 'Journal de banque',         'bank',     '512000', 'active', false, p_tenant_id),
    ('CA', 'Journal de caisse',         'cash',     '530000', 'active', false, p_tenant_id),
    ('OD', 'Operations diverses',       'general',  NULL,     'active', false, p_tenant_id),
    ('AN', 'A-nouveaux',                'general',  NULL,     'active', false, p_tenant_id)
  ON CONFLICT (tenant_id, code) DO NOTHING;

  -- 3. DEFAULT CURRENCIES
  INSERT INTO currencies (code, name, symbol, exchange_rate, tenant_id)
  VALUES
    ('EUR', 'Euro',            '€', 1.0,    p_tenant_id),
    ('USD', 'Dollar US',       '$', 1.08,   p_tenant_id),
    ('GBP', 'Livre Sterling',  '£', 0.85,   p_tenant_id)
  ON CONFLICT (tenant_id, code) DO NOTHING;

  -- 4. FISCAL YEAR + 12 MONTHLY PERIODS (current year)
  IF NOT EXISTS (SELECT 1 FROM fiscal_years WHERE tenant_id = p_tenant_id AND code = 'FY' || v_year) THEN
    INSERT INTO fiscal_years (code, start_date, end_date, status, tenant_id)
    VALUES ('FY' || v_year, make_date(v_year, 1, 1), make_date(v_year, 12, 31), 'open', p_tenant_id)
    RETURNING id INTO v_fy_id;

    FOR v_month IN 1 .. 12 LOOP
      v_period_start := make_date(v_year, v_month, 1);
      v_period_end := (v_period_start + INTERVAL '1 month - 1 day')::date;
      INSERT INTO fiscal_periods (fiscal_year_id, period_number, period_label, start_date, end_date, status, tenant_id)
      VALUES (v_fy_id, v_month, v_labels[v_month] || ' ' || v_year, v_period_start, v_period_end, 'open', p_tenant_id);
    END LOOP;
  END IF;

  -- 5. COMPANY SETTINGS
  IF NOT EXISTS (SELECT 1 FROM company_settings WHERE tenant_id = p_tenant_id) THEN
    INSERT INTO company_settings (name, legal_name, vat_number, siret, address, city, postal_code, country, currency, fiscal_year_start, tenant_id)
    VALUES (
      v_tenant.name,
      COALESCE(v_tenant.legal_name, v_tenant.name),
      v_tenant.vat_number,
      v_tenant.siret,
      v_tenant.address,
      v_tenant.city,
      v_tenant.postal_code,
      COALESCE(v_tenant.country, 'France'),
      COALESCE(v_tenant.currency, 'EUR'),
      '01-01',
      p_tenant_id
    );
  END IF;
END;
$function$;


CREATE OR REPLACE FUNCTION public.can_perform(p_table text, p_action text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
AS $function$
  SELECT CASE
    WHEN current_user_role() = 'admin' THEN true
    WHEN current_user_role() = 'accountant' AND p_action IN ('select', 'insert', 'update') THEN true
    WHEN current_user_role() = 'accountant' AND p_action = 'delete' AND p_table IN ('journal_entries', 'journal_lines', 'invoice_lines', 'quote_lines', 'credit_note_lines') THEN true
    WHEN current_user_role() = 'manager' AND p_action = 'select' THEN true
    WHEN current_user_role() = 'manager' AND p_action IN ('insert', 'update') AND p_table IN ('invoices', 'invoice_lines', 'quotes', 'quote_lines', 'credit_notes', 'credit_note_lines', 'customers', 'products', 'delivery_notes', 'delivery_note_lines', 'sales_orders', 'sales_order_lines', 'purchase_orders', 'purchase_order_lines') THEN true
    WHEN current_user_role() = 'viewer' AND p_action = 'select' THEN true
    WHEN current_user_role() = 'custom' THEN
      COALESCE(
        (current_user_permissions() -> p_table ->> p_action)::boolean,
        false
      )
    ELSE false
  END
$function$;


CREATE OR REPLACE FUNCTION public.check_fiscal_period_open()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_period_status text;
  v_entry_date date;
BEGIN
  v_entry_date := COALESCE(NEW.date, OLD.date);

  SELECT fp.status INTO v_period_status
  FROM fiscal_periods fp
  JOIN fiscal_years fy ON fy.id = fp.fiscal_year_id
  WHERE fp.tenant_id = current_tenant_id()
    AND v_entry_date >= fp.start_date
    AND v_entry_date <= fp.end_date
  LIMIT 1;

  IF v_period_status = 'closed' THEN
    RAISE EXCEPTION 'Période fiscale close — écriture interdite (date=%)', v_entry_date;
  END IF;

  RETURN NEW;
END;
$function$;


CREATE OR REPLACE FUNCTION public.check_journal_entry_balance()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_total_debit numeric;
  v_total_credit numeric;
  v_entry_id uuid;
BEGIN
  v_entry_id := COALESCE(NEW.journal_id, OLD.journal_id);

  SELECT COALESCE(SUM(debit), 0), COALESCE(SUM(credit), 0)
  INTO v_total_debit, v_total_credit
  FROM journal_lines
  WHERE journal_id = v_entry_id;

  -- Tolérance de 0.01 pour les arrondis
  IF ABS(v_total_debit - v_total_credit) > 0.01 THEN
    RAISE EXCEPTION 'Écriture déséquilibrée: débit=%, crédit=% (écart=%)',
      v_total_debit, v_total_credit, ABS(v_total_debit - v_total_credit);
  END IF;

  -- Au moins une ligne avec un montant > 0
  IF v_total_debit = 0 AND v_total_credit = 0 THEN
    RAISE EXCEPTION 'Écriture vide: aucun montant sur les lignes';
  END IF;

  RETURN NEW;
END;
$function$;


CREATE OR REPLACE FUNCTION public.create_tenant_for_current_user(p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_tenant uuid;
  v_auth_id uuid := auth.uid();
  v_email text;
  v_name text;
  v_user_name text;
  v_enabled_modules text[];
BEGIN
  -- Vérifier que l'utilisateur est authentifié
  IF v_auth_id IS NULL THEN
    RAISE EXCEPTION 'Non authentifié';
  END IF;

  -- Extraire l'email depuis les métadonnées d'auth
  v_email := (
    SELECT COALESCE(
      (auth.jwt() ->> 'email'),
      (auth.jwt() -> 'user_metadata' ->> 'email')
    )
  );

  -- Nom d'affichage depuis les métadonnées
  v_user_name := COALESCE(
    (auth.jwt() -> 'user_metadata' ->> 'name'),
    (auth.jwt() -> 'user_metadata' ->> 'full_name'),
    v_email
  );

  -- Vérifier que l'utilisateur n'a pas déjà un tenant (optionnel: autoriser plusieurs)
  -- On autorise plusieurs tenants pour les cabinets comptables.

  -- Modules activés par défaut
  v_enabled_modules := COALESCE(
    (p_data ->> 'enabled_modules')::text[],
    ARRAY['home','accounting','commercial','treasury','stock','production','hr','dashboards','reporting','system']
  );

  -- 1. Créer le tenant
  INSERT INTO tenants (
    name, legal_name, siren, vat_number,
    address, city, postal_code, country, currency,
    email, phone, legislation_pack_code, country_code,
    enabled_modules, status, plan, trial_ends_at
  ) VALUES (
    p_data ->> 'name',
    COALESCE(p_data ->> 'legal_name', p_data ->> 'name'),
    p_data ->> 'siren',
    p_data ->> 'vat_number',
    p_data ->> 'address',
    p_data ->> 'city',
    p_data ->> 'postal_code',
    COALESCE(p_data ->> 'country', 'France'),
    COALESCE(p_data ->> 'currency', 'EUR'),
    COALESCE(p_data ->> 'email', v_email),
    p_data ->> 'phone',
    p_data ->> 'legislation_pack_code',
    p_data ->> 'legislation_pack_code',
    v_enabled_modules,
    'active',
    'trial',
    (NOW() + INTERVAL '30 days')::timestamptz
  )
  RETURNING id INTO v_tenant;

  -- 2. Créer le tenant_users (admin)
  INSERT INTO tenant_users (
    tenant_id, auth_id, email, name, role, permissions, status, accepted_at
  ) VALUES (
    v_tenant,
    v_auth_id,
    v_email,
    v_user_name,
    'admin',
    '{}'::jsonb,
    'active',
    NOW()
  );

  -- 3. Créer un employé (best-effort, non fatal)
  BEGIN
    INSERT INTO employees (
      tenant_id, name, email, position, department, hire_date, status
    ) VALUES (
      v_tenant,
      v_user_name,
      v_email,
      'Admin',
      'Direction',
      CURRENT_DATE,
      'active'
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Employee creation skipped: %', SQLERRM;
  END;

  -- 4. Bootstrap les données de référence (plan comptable, journaux, etc.)
  BEGIN
    PERFORM bootstrap_tenant(v_tenant);
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'bootstrap_tenant skipped: %', SQLERRM;
  END;

  -- Retourner le tenant créé
  RETURN jsonb_build_object(
    'success', true,
    'tenant_id', v_tenant
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM
  );
END;
$function$;


CREATE OR REPLACE FUNCTION public.current_guest_permissions()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
AS $function$
  SELECT guest_permissions FROM tenant_users
  WHERE auth_id = auth.uid()
    AND status = 'active'
    AND tenant_id = current_tenant_id()
  LIMIT 1
$function$;


CREATE OR REPLACE FUNCTION public.current_module_role(p_module text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
AS $function$
  SELECT (module_roles ->> p_module) FROM tenant_users
  WHERE auth_id = auth.uid()
    AND status = 'active'
    AND tenant_id = current_tenant_id()
  LIMIT 1
$function$;


CREATE OR REPLACE FUNCTION public.current_tenant_id()
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
AS $function$
  SELECT c.tid
  FROM (
    -- prio 1 : en-tête x-tenant-id (transmis par PostgREST)
    SELECT 1 AS prio,
           NULLIF(
             current_setting('request.headers', true)::json->>'x-tenant-id',
             ''
           )::uuid AS tid
    UNION ALL
    -- prio 2 : GUC de session (set_config via set_active_tenant)
    SELECT 2 AS prio,
           NULLIF(current_setting('app.active_tenant_id', true), '')::uuid AS tid
  ) c
  WHERE c.tid IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM tenant_users
      WHERE auth_id = auth.uid()
        AND status = 'active'
        AND tenant_id = c.tid
    )
  ORDER BY c.prio
  LIMIT 1
$function$;


CREATE OR REPLACE FUNCTION public.current_tenant_user_id()
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
AS $function$
  SELECT id FROM tenant_users
  WHERE auth_id = auth.uid()
    AND status = 'active'
    AND tenant_id = current_tenant_id()
  LIMIT 1
$function$;


CREATE OR REPLACE FUNCTION public.current_user_name(p_tenant_id uuid DEFAULT NULL::uuid)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_name TEXT;
  v_auth_uid UUID;
BEGIN
  -- Try app.user_name setting first (set by frontend if available)
  v_name := current_setting('app.user_name', true);
  IF v_name IS NOT NULL AND v_name <> '' THEN
    RETURN v_name;
  END IF;

  -- Get auth user id from JWT claim (set by PostgREST per request)
  v_auth_uid := auth.uid();
  IF v_auth_uid IS NULL THEN
    RETURN 'Unknown';
  END IF;

  -- Look up from tenant_users using auth.uid() and tenant_id
  -- Use NEW.tenant_id from trigger (passed as p_tenant_id) for reliability
  SELECT tu.name INTO v_name
  FROM tenant_users tu
  WHERE tu.auth_id = v_auth_uid
    AND tu.status = 'active'
    AND (p_tenant_id IS NULL OR tu.tenant_id = p_tenant_id)
  ORDER BY tu.last_login DESC NULLS LAST
  LIMIT 1;

  RETURN COALESCE(v_name, 'Unknown');
END;
$function$;


CREATE OR REPLACE FUNCTION public.current_user_permissions()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
AS $function$
  SELECT permissions FROM tenant_users
  WHERE auth_id = auth.uid()
    AND status = 'active'
    AND tenant_id = current_tenant_id()
  LIMIT 1
$function$;


CREATE OR REPLACE FUNCTION public.current_user_role()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
AS $function$
  SELECT role FROM tenant_users
  WHERE auth_id = auth.uid()
    AND status = 'active'
    AND tenant_id = current_tenant_id()
  LIMIT 1
$function$;


CREATE OR REPLACE FUNCTION public.decrement_stock(p_product_id uuid, p_qty numeric, p_warehouse_id uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_tid uuid := current_tenant_id();
  v_current numeric;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  -- Vérifier le stock disponible (avec verrou FOR UPDATE)
  SELECT stock_quantity INTO v_current
  FROM products
  WHERE id = p_product_id AND tenant_id = v_tid
  FOR UPDATE;

  IF v_current IS NULL THEN
    RAISE EXCEPTION 'Produit % non trouvé', p_product_id;
  END IF;

  IF v_current < p_qty THEN
    RAISE EXCEPTION 'Stock insuffisant: disponible=%, demandé=%', v_current, p_qty;
  END IF;

  -- Mettre à jour stock_quantities par entrepôt
  IF p_warehouse_id IS NOT NULL THEN
    UPDATE stock_quantities
      SET quantity = GREATEST(quantity - p_qty, 0), updated_at = NOW()
      WHERE product_id = p_product_id
        AND warehouse_id = p_warehouse_id
        AND tenant_id = v_tid;
  END IF;

  -- Mettre à jour le stock total
  UPDATE products
    SET stock_quantity = stock_quantity - p_qty,
        updated_at = NOW()
    WHERE id = p_product_id AND tenant_id = v_tid;
END;
$function$;


CREATE OR REPLACE FUNCTION public.fec_export(p_tenant_id uuid, p_start_date date, p_end_date date, p_offset integer DEFAULT 0, p_limit integer DEFAULT 1000)
 RETURNS TABLE(journal_code text, entry_number text, entry_date date, account_code text, account_label text, description text, debit numeric, credit numeric, piece_number text)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  RETURN QUERY
  SELECT
    je.journal_code::text,
    je.number::text,
    je.date,
    jl.account_code::text,
    COALESCE(ja.name, '')::text,
    COALESCE(jl.description, '')::text,
    jl.debit,
    jl.credit,
    COALESCE(je.piece_number, je.number)::text
  FROM journal_entries je
  JOIN journal_lines jl ON jl.journal_id = je.id AND jl.tenant_id = je.tenant_id
  LEFT JOIN chart_accounts ja ON ja.code = jl.account_code AND ja.tenant_id = je.tenant_id
  WHERE je.tenant_id = p_tenant_id
    AND je.status = 'posted'
    AND je.date >= p_start_date
    AND je.date <= p_end_date
  ORDER BY je.date, je.journal_code, je.number, jl.line_order
  OFFSET p_offset
  LIMIT p_limit;
END;
$function$;


CREATE OR REPLACE FUNCTION public.generate_recurring_entry(p_entry_id uuid, p_tenant_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_tid uuid := COALESCE(p_tenant_id, current_tenant_id());
  v_source journal_entries%ROWTYPE;
  v_source_lines journal_lines[] := ARRAY[]::journal_lines[];
  v_new_id uuid;
  v_line journal_lines%ROWTYPE;
  v_new_date date;
  v_number text;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  -- Charger l'écriture source
  SELECT * INTO v_source FROM journal_entries WHERE id = p_entry_id AND tenant_id = v_tid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Écriture source % non trouvée', p_entry_id;
  END IF;

  -- Calculer la nouvelle date (un mois plus tard)
  v_new_date := (v_source.date + INTERVAL '1 month')::date;

  -- Générer un nouveau numéro
  v_number := get_next_piece_number(v_source.journal_code);

  -- Créer la nouvelle écriture
  INSERT INTO journal_entries (
    tenant_id, number, date, journal_code, status,
    description, invoice_ref
  ) VALUES (
    v_tid, v_number, v_new_date, v_source.journal_code,
    'draft',
    '[Récurrent] ' || COALESCE(v_source.description, ''),
    v_source.invoice_ref
  )
  RETURNING id INTO v_new_id;

  -- Copier les lignes
  FOR v_line IN
    SELECT * FROM journal_lines WHERE journal_id = p_entry_id AND tenant_id = v_tid
  LOOP
    INSERT INTO journal_lines (
      tenant_id, journal_id, account_code, account_general,
      debit, credit, description, line_order
    ) VALUES (
      v_tid, v_new_id, v_line.account_code, v_line.account_general,
      v_line.debit, v_line.credit, v_line.description, v_line.line_order
    );
  END LOOP;

  RETURN jsonb_build_object('success', true, 'new_entry_id', v_new_id, 'number', v_number);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$function$;


CREATE OR REPLACE FUNCTION public.get_journal_entry_count(p_tenant_id uuid, p_start_date date DEFAULT NULL::date, p_end_date date DEFAULT NULL::date)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_count integer;
BEGIN
  SELECT COUNT(*) INTO v_count
  FROM journal_entries je
  WHERE je.tenant_id = p_tenant_id
    AND je.status IN ('posted', 'draft')
    AND (p_start_date IS NULL OR je.date >= p_start_date)
    AND (p_end_date IS NULL OR je.date <= p_end_date);
  RETURN v_count;
END;
$function$;


CREATE OR REPLACE FUNCTION public.get_next_piece_number(p_journal_code text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_next integer;
  v_padded text;
  v_tid uuid := current_tenant_id();
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  -- Verrou de ligne : incrément atomique, pas de doublon en concurrence
  UPDATE journals
    SET next_number = next_number + 1
    WHERE code = p_journal_code
      AND tenant_id = v_tid
    RETURNING next_number - 1 INTO v_next;

  IF v_next IS NULL THEN
    -- Journal non trouvé pour ce tenant : amorcer depuis `sequence` si présent
    SELECT COALESCE(j.sequence, 0) + 1 INTO v_next
    FROM journals j
    WHERE j.code = p_journal_code AND j.tenant_id = v_tid;

    IF v_next IS NULL THEN
      RAISE EXCEPTION 'Journal % introuvable pour le tenant actif', p_journal_code;
    END IF;

    UPDATE journals
      SET next_number = v_next + 1
      WHERE code = p_journal_code AND tenant_id = v_tid;
  END IF;

  v_padded := lpad(v_next::text, 4, '0');
  RETURN p_journal_code || '-' || v_padded;
END;
$function$;


CREATE OR REPLACE FUNCTION public.has_module_access(p_module text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
AS $function$
  SELECT
    current_user_role() = 'admin'
    OR (
      current_module_role(p_module) IS NOT NULL
      AND current_module_role(p_module) != ''
    )
$function$;


CREATE OR REPLACE FUNCTION public.has_module_permission(p_module text, p_permission text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
AS $function$
DECLARE
  v_role text;
  v_global_role text;
BEGIN
  v_global_role := current_user_role();
  -- Global admin: full access
  IF v_global_role = 'admin' THEN
    RETURN true;
  END IF;

  v_role := current_module_role(p_module);
  -- No module role = no access
  IF v_role IS NULL OR v_role = '' THEN
    RETURN false;
  END IF;

  -- Permission matrix by role
  RETURN CASE
    -- Directors: full access within module
    WHEN v_role IN ('project_director', 'hr_director', 'sales_director') THEN true
    -- Managers: create, edit, delete, approve, view
    WHEN v_role IN ('project_manager', 'hr_manager', 'sales_rep', 'accountant',
                     'treasurer', 'warehouse_manager', 'production_manager')
      THEN p_permission IN ('view', 'create', 'edit', 'delete', 'approve')
    -- Team members / employees: view, create, edit
    WHEN v_role IN ('team_member', 'hr_employee', 'sales_employee',
                     'stock_clerk', 'production_operator')
      THEN p_permission IN ('view', 'create', 'edit')
    -- Consultants: view, edit
    WHEN v_role = 'consultant' THEN p_permission IN ('view', 'edit')
    -- Auditors: view only
    WHEN v_role = 'auditor' THEN p_permission = 'view'
    -- Treasury viewer: view only
    WHEN v_role = 'treasury_viewer' THEN p_permission = 'view'
    -- Guests: view only (further restricted by guest_permissions)
    WHEN v_role = 'guest' THEN p_permission = 'view'
    -- Custom: view only by default
    WHEN v_role = 'custom' THEN p_permission = 'view'
    ELSE false
  END;
END;
$function$;


CREATE OR REPLACE FUNCTION public.increment_download_count(doc_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  UPDATE module_documents
  SET download_count = download_count + 1
  WHERE id = doc_id AND tenant_id = current_tenant_id();
END;
$function$;


CREATE OR REPLACE FUNCTION public.increment_stock(p_product_id uuid, p_qty numeric, p_warehouse_id uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_tid uuid := current_tenant_id();
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  -- Mettre à jour stock_quantities par entrepôt
  IF p_warehouse_id IS NOT NULL THEN
    UPDATE stock_quantities
      SET quantity = quantity + p_qty, updated_at = NOW()
      WHERE product_id = p_product_id
        AND warehouse_id = p_warehouse_id
        AND tenant_id = v_tid;

    -- Créer la ligne si elle n'existe pas
    IF NOT FOUND THEN
      INSERT INTO stock_quantities (tenant_id, product_id, warehouse_id, quantity)
      VALUES (v_tid, p_product_id, p_warehouse_id, p_qty)
      ON CONFLICT DO NOTHING;
    END IF;
  END IF;

  -- Mettre à jour le stock total sur products
  UPDATE products
    SET stock_quantity = COALESCE(stock_quantity, 0) + p_qty,
        updated_at = NOW()
    WHERE id = p_product_id AND tenant_id = v_tid;
END;
$function$;


CREATE OR REPLACE FUNCTION public.log_task_activity()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_user_name TEXT;
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  v_user_name := current_user_name(NEW.tenant_id);

  INSERT INTO project_activity_log (tenant_id, task_id, project_id, user_id, user_name, action_type, old_value, new_value, description)
  VALUES (
    NEW.tenant_id,
    NEW.id,
    NEW.project_id,
    v_user_id,
    v_user_name,
    CASE
      WHEN OLD.status IS DISTINCT FROM NEW.status THEN 'status_changed'
      WHEN OLD.priority IS DISTINCT FROM NEW.priority THEN 'priority_changed'
      WHEN OLD.assignee IS DISTINCT FROM NEW.assignee THEN 'assigned'
      WHEN OLD.title IS DISTINCT FROM NEW.title THEN 'title_changed'
      WHEN OLD.due_date IS DISTINCT FROM NEW.due_date THEN 'due_date_changed'
      WHEN OLD.progress IS DISTINCT FROM NEW.progress THEN 'progress_changed'
      ELSE 'updated'
    END,
    to_jsonb(OLD),
    to_jsonb(NEW),
    CASE
      WHEN OLD.status IS DISTINCT FROM NEW.status THEN 'Status changed from ' || COALESCE(OLD.status, 'none') || ' to ' || COALESCE(NEW.status, 'none')
      WHEN OLD.priority IS DISTINCT FROM NEW.priority THEN 'Priority changed from ' || COALESCE(OLD.priority, 'none') || ' to ' || COALESCE(NEW.priority, 'none')
      WHEN OLD.assignee IS DISTINCT FROM NEW.assignee THEN 'Assignee changed to ' || COALESCE(NEW.assignee, 'unassigned')
      ELSE 'Task updated'
    END
  );
  RETURN NEW;
END;
$function$;


CREATE OR REPLACE FUNCTION public.log_task_created()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_user_name TEXT;
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  v_user_name := current_user_name(NEW.tenant_id);

  INSERT INTO project_activity_log (tenant_id, task_id, project_id, user_id, user_name, action_type, description)
  VALUES (
    NEW.tenant_id,
    NEW.id,
    NEW.project_id,
    v_user_id,
    v_user_name,
    'created',
    'Task created: ' || NEW.title
  );
  RETURN NEW;
END;
$function$;


CREATE OR REPLACE FUNCTION public.post_journal_entry(p_entry jsonb, p_lines jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_tid uuid := current_tenant_id();
  v_entry_id uuid;
  v_line jsonb;
  v_number text;
  v_journal_code text;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  v_journal_code := p_entry ->> 'journal_code';

  -- Numérotation atomique si pas de numéro fourni
  IF p_entry ->> 'number' IS NULL OR p_entry ->> 'number' = '' THEN
    v_number := get_next_piece_number(v_journal_code);
  ELSE
    v_number := p_entry ->> 'number';
  END IF;

  -- 1. Insérer l'entête
  INSERT INTO journal_entries (
    tenant_id, number, date, journal_code, status,
    description, invoice_ref, piece_number
  ) VALUES (
    v_tid,
    v_number,
    (p_entry ->> 'date')::date,
    v_journal_code,
    COALESCE(p_entry ->> 'status', 'draft'),
    p_entry ->> 'description',
    p_entry ->> 'invoice_ref',
    v_number
  )
  RETURNING id INTO v_entry_id;

  -- 2. Insérer les lignes
  FOR v_line IN SELECT * FROM jsonb_array_elements(p_lines) LOOP
    INSERT INTO journal_lines (
      tenant_id, journal_id, account_code, account_general,
      debit, credit, description, line_order
    ) VALUES (
      v_tid,
      v_entry_id,
      v_line ->> 'account_code',
      v_line ->> 'account_general',
      COALESCE((v_line ->> 'debit')::numeric, 0),
      COALESCE((v_line ->> 'credit')::numeric, 0),
      v_line ->> 'description',
      COALESCE((v_line ->> 'line_order')::integer, 0)
    );
  END LOOP;

  -- Le trigger check_journal_entry_balance vérifie l'équilibre automatiquement

  RETURN jsonb_build_object('success', true, 'entry_id', v_entry_id, 'number', v_number);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$function$;


CREATE OR REPLACE FUNCTION public.prevent_posted_entry_modification()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  -- Une écriture validée (posted) ne peut être ni modifiée ni supprimée
  -- L'annulation passe par generateExtourne (création d'une écriture inverse)
  IF OLD.status = 'posted' THEN
    RAISE EXCEPTION 'Écriture % est validée (posted) — immuable. Utiliser l''extourne pour annuler.', OLD.id;
  END IF;
  RETURN NEW;
END;
$function$;


CREATE OR REPLACE FUNCTION public.prevent_role_escalation()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  -- If the updater is updating their own row and is NOT an admin
  IF auth.uid() = NEW.auth_id AND current_user_role() != 'admin' THEN
    IF NEW.role IS DISTINCT FROM OLD.role THEN
      RAISE EXCEPTION 'SECURITY: Cannot change own role';
    END IF;
    IF NEW.permissions IS DISTINCT FROM OLD.permissions THEN
      RAISE EXCEPTION 'SECURITY: Cannot change own permissions';
    END IF;
    IF NEW.status IS DISTINCT FROM OLD.status THEN
      RAISE EXCEPTION 'SECURITY: Cannot change own status';
    END IF;
    IF NEW.tenant_id IS DISTINCT FROM OLD.tenant_id THEN
      RAISE EXCEPTION 'SECURITY: Cannot change own tenant_id';
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;


CREATE OR REPLACE FUNCTION public.seed_standard_chart(p_tenant_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  INSERT INTO chart_accounts (code, name, type, balance, tenant_id)
  VALUES
    -- Classe 1 - Capitaux
    ('101000', 'Capital social', 'equity', 0, p_tenant_id),
    ('101100', 'Capital non appele', 'equity', 0, p_tenant_id),
    ('104000', 'Primes liees au capital social', 'equity', 0, p_tenant_id),
    ('106000', 'Reserves', 'equity', 0, p_tenant_id),
    ('106100', 'Reserve legale', 'equity', 0, p_tenant_id),
    ('106800', 'Autres reserves', 'equity', 0, p_tenant_id),
    ('108000', 'Compte de l exploitant', 'equity', 0, p_tenant_id),
    ('109000', 'Actionnaires - capital souscrit non appele', 'equity', 0, p_tenant_id),
    ('110000', 'Report a nouveau (solde crediteur)', 'equity', 0, p_tenant_id),
    ('119000', 'Report a nouveau (solde debiteur)', 'equity', 0, p_tenant_id),
    ('120000', 'Resultat de l exercice (benefice)', 'equity', 0, p_tenant_id),
    ('129000', 'Resultat de l exercice (perte)', 'equity', 0, p_tenant_id),
    ('151000', 'Provisions pour risques', 'liability', 0, p_tenant_id),
    ('153000', 'Provisions pour pensions', 'liability', 0, p_tenant_id),
    ('158000', 'Autres provisions pour charges', 'liability', 0, p_tenant_id),
    ('163000', 'Emprunts aupres des etablissements de credit', 'liability', 0, p_tenant_id),
    ('164000', 'Emprunts aupres des autres partenaires', 'liability', 0, p_tenant_id),
    ('165000', 'Depots et cautionnements recus', 'liability', 0, p_tenant_id),
    ('168000', 'Autres emprunts et dettes assimilees', 'liability', 0, p_tenant_id),
    ('171000', 'Dettes rattachees a des participations', 'liability', 0, p_tenant_id),
    ('181000', 'Comptes de liaison etablissements', 'liability', 0, p_tenant_id),
    ('186000', 'Biens en credit-bail', 'liability', 0, p_tenant_id),
    ('187000', 'Biens en credit-bail - contrepartie', 'liability', 0, p_tenant_id),
    ('188000', 'Biens en location-vente', 'liability', 0, p_tenant_id),
    ('189000', 'Biens en location-vente - contrepartie', 'liability', 0, p_tenant_id),
    -- Classe 2 - Immobilisations
    ('201000', 'Frais d etablissement', 'asset', 0, p_tenant_id),
    ('205000', 'Concessions, brevets, licences, logiciels', 'asset', 0, p_tenant_id),
    ('206000', 'Droit au bail', 'asset', 0, p_tenant_id),
    ('207000', 'Fonds commercial', 'asset', 0, p_tenant_id),
    ('208000', 'Autres immobilisations incorporelles', 'asset', 0, p_tenant_id),
    ('210000', 'Terrains', 'asset', 0, p_tenant_id),
    ('211000', 'Agencements et ameliororations de terrains', 'asset', 0, p_tenant_id),
    ('212000', 'Constructions', 'asset', 0, p_tenant_id),
    ('213000', 'Constructions sur sol d autrui', 'asset', 0, p_tenant_id),
    ('215000', 'Installations techniques, materiels et outillage', 'asset', 0, p_tenant_id),
    ('215400', 'Materiel industriel', 'asset', 0, p_tenant_id),
    ('218000', 'Materiel informatique', 'asset', 0, p_tenant_id),
    ('218100', 'Materiel de bureau et informatique', 'asset', 0, p_tenant_id),
    ('218200', 'Mobilier', 'asset', 0, p_tenant_id),
    ('218300', 'Materiel de bureau', 'asset', 0, p_tenant_id),
    ('218400', 'Materiel et outillage', 'asset', 0, p_tenant_id),
    ('218500', 'Embages et equipements', 'asset', 0, p_tenant_id),
    ('220000', 'Immobilisations corporelles en cours', 'asset', 0, p_tenant_id),
    ('230000', 'Immobilisations en cours - incorporelles', 'asset', 0, p_tenant_id),
    ('231000', 'Immobilisations en cours - corporelles', 'asset', 0, p_tenant_id),
    ('238000', 'Avances et acomptes verses sur commandes', 'asset', 0, p_tenant_id),
    ('240000', 'Participations et creances rattachees', 'asset', 0, p_tenant_id),
    ('250000', 'Titres de participation', 'asset', 0, p_tenant_id),
    ('260000', 'Titres immobilises', 'asset', 0, p_tenant_id),
    ('270000', 'Participations et creances rattachees (droit de propriete)', 'asset', 0, p_tenant_id),
    ('271000', 'Titres immobilises (droit de propriete)', 'asset', 0, p_tenant_id),
    ('275000', 'Depots et cautionnements verses', 'asset', 0, p_tenant_id),
    ('280000', 'Amortissements des immobilisations incorporelles', 'asset', 0, p_tenant_id),
    ('280500', 'Amortissements des concessions, brevets, licences, logiciels', 'asset', 0, p_tenant_id),
    ('281000', 'Amortissements des immobilisations corporelles', 'asset', 0, p_tenant_id),
    ('281200', 'Amortissements des constructions', 'asset', 0, p_tenant_id),
    ('281500', 'Amortissements des installations techniques', 'asset', 0, p_tenant_id),
    ('281800', 'Amortissements du materiel', 'asset', 0, p_tenant_id),
    ('290000', 'Depreciations des immobilisations incorporelles', 'asset', 0, p_tenant_id),
    ('291000', 'Depreciations des immobilisations corporelles', 'asset', 0, p_tenant_id),
    ('293000', 'Depreciations des immobilisations en cours', 'asset', 0, p_tenant_id),
    ('296000', 'Depreciations des participations et creances rattachees', 'asset', 0, p_tenant_id),
    ('297000', 'Depreciations des autres immobilisations financieres', 'asset', 0, p_tenant_id),
    -- Classe 3 - Stocks
    ('310000', 'Matieres premieres (et fournitures)', 'asset', 0, p_tenant_id),
    ('320000', 'Matieres consommables', 'asset', 0, p_tenant_id),
    ('321000', 'Matieres consommables', 'asset', 0, p_tenant_id),
    ('322000', 'Fournitures consommables', 'asset', 0, p_tenant_id),
    ('330000', 'En-cours de production de biens', 'asset', 0, p_tenant_id),
    ('340000', 'Etudes en cours', 'asset', 0, p_tenant_id),
    ('345000', 'Travaux en cours', 'asset', 0, p_tenant_id),
    ('350000', 'Produits intermediaires et finis', 'asset', 0, p_tenant_id),
    ('351000', 'Produits intermediaires', 'asset', 0, p_tenant_id),
    ('352000', 'Produits finis', 'asset', 0, p_tenant_id),
    ('354000', 'Produits residuels', 'asset', 0, p_tenant_id),
    ('355000', 'Produits finis (group A)', 'asset', 0, p_tenant_id),
    ('358000', 'Produits finis (group B)', 'asset', 0, p_tenant_id),
    ('360000', 'Stocks provenant d immobilisations', 'asset', 0, p_tenant_id),
    ('370000', 'Stocks de marchandises', 'asset', 0, p_tenant_id),
    ('371000', 'Marchandises (group A)', 'asset', 0, p_tenant_id),
    ('372000', 'Marchandises (group B)', 'asset', 0, p_tenant_id),
    ('380000', 'Stocks a tres rapide rotation', 'asset', 0, p_tenant_id),
    ('390000', 'Depreciations des stocks', 'asset', 0, p_tenant_id),
    ('391000', 'Depreciations des matieres premieres', 'asset', 0, p_tenant_id),
    ('392000', 'Depreciations des matieres consommables', 'asset', 0, p_tenant_id),
    ('393000', 'Depreciations des en-cours de production', 'asset', 0, p_tenant_id),
    ('395000', 'Depreciations des produits', 'asset', 0, p_tenant_id),
    ('397000', 'Depreciations des marchandises', 'asset', 0, p_tenant_id),
    -- Classe 4 - Tiers
    ('400000', 'Fournisseurs et comptes rattaches', 'liability', 0, p_tenant_id),
    ('401000', 'Fournisseurs', 'liability', 0, p_tenant_id),
    ('401100', 'Fournisseurs - achats de biens et services', 'liability', 0, p_tenant_id),
    ('401700', 'Fournisseurs - retenues de garantie', 'liability', 0, p_tenant_id),
    ('403000', 'Fournisseurs - effets a payer', 'liability', 0, p_tenant_id),
    ('404000', 'Fournisseurs d immobilisations', 'liability', 0, p_tenant_id),
    ('405000', 'Fournisseurs d immobilisations - effets a payer', 'liability', 0, p_tenant_id),
    ('408000', 'Fournisseurs - factures non parvenues', 'liability', 0, p_tenant_id),
    ('408100', 'Fournisseurs - factures non parvenues (biens et services)', 'liability', 0, p_tenant_id),
    ('408400', 'Fournisseurs - factures non parvenues (immobilisations)', 'liability', 0, p_tenant_id),
    ('409000', 'Fournisseurs debiteurs', 'asset', 0, p_tenant_id),
    ('409100', 'Fournisseurs - avances et acomptes verses', 'asset', 0, p_tenant_id),
    ('409600', 'Fournisseurs - avoirs a recevoir', 'asset', 0, p_tenant_id),
    ('409700', 'Fournisseurs - autres avoirs', 'asset', 0, p_tenant_id),
    ('410000', 'Clients et comptes rattaches', 'asset', 0, p_tenant_id),
    ('411000', 'Clients', 'asset', 0, p_tenant_id),
    ('411100', 'Clients - ventes de biens et services', 'asset', 0, p_tenant_id),
    ('411700', 'Clients - retenues de garantie', 'asset', 0, p_tenant_id),
    ('413000', 'Clients - effets a recevoir', 'asset', 0, p_tenant_id),
    ('416000', 'Clients douteux ou litigieux', 'asset', 0, p_tenant_id),
    ('417000', 'Clients - creances sur travaux non encore facturables', 'asset', 0, p_tenant_id),
    ('418000', 'Clients - produits non encore factures', 'asset', 0, p_tenant_id),
    ('419000', 'Clients crediteurs', 'liability', 0, p_tenant_id),
    ('419100', 'Clients - avances et acomptes recus', 'liability', 0, p_tenant_id),
    ('419600', 'Clients - avoirs a etablir', 'liability', 0, p_tenant_id),
    ('419700', 'Clients - autres avoirs a etablir', 'liability', 0, p_tenant_id),
    ('420000', 'Personnel et comptes rattaches', 'liability', 0, p_tenant_id),
    ('421000', 'Personnel - remunerations dues', 'liability', 0, p_tenant_id),
    ('422000', 'Comites d entreprise, d etablissement, etc.', 'liability', 0, p_tenant_id),
    ('424000', 'Participation des salaries aux resultats', 'liability', 0, p_tenant_id),
    ('425000', 'Personnel - avances et acomptes', 'asset', 0, p_tenant_id),
    ('426000', 'Personnel - depots', 'liability', 0, p_tenant_id),
    ('427000', 'Personnel - oppositions', 'liability', 0, p_tenant_id),
    ('428000', 'Personnel - charges a payer et produits a recevoir', 'liability', 0, p_tenant_id),
    ('428200', 'Conges payes', 'liability', 0, p_tenant_id),
    ('428400', 'Comptes courants des salaries', 'liability', 0, p_tenant_id),
    ('428600', 'Personnel - produits a recevoir', 'asset', 0, p_tenant_id),
    ('430000', 'Securite sociale et autres organismes sociaux', 'liability', 0, p_tenant_id),
    ('431000', 'Securite sociale', 'liability', 0, p_tenant_id),
    ('432000', 'Autres organismes sociaux', 'liability', 0, p_tenant_id),
    ('437000', 'Autres organismes sociaux', 'liability', 0, p_tenant_id),
    ('438000', 'Organismes sociaux - charges a payer et produits a recevoir', 'liability', 0, p_tenant_id),
    ('438200', 'Charges de securite sociale et de prevoyance', 'liability', 0, p_tenant_id),
    ('438600', 'Organismes sociaux - produits a recevoir', 'asset', 0, p_tenant_id),
    ('440000', 'Etat et autres collectivites publiques', 'liability', 0, p_tenant_id),
    ('441000', 'Etat - subventions a recevoir', 'asset', 0, p_tenant_id),
    ('442000', 'Etat - impots et taxes recuperables', 'asset', 0, p_tenant_id),
    ('443000', 'Operations particulieres avec l Etat', 'liability', 0, p_tenant_id),
    ('444000', 'Etat - impots sur les benefices', 'liability', 0, p_tenant_id),
    ('445000', 'Etat - taxes sur le chiffre d affaires', 'liability', 0, p_tenant_id),
    ('445200', 'TVA due intracommunautaire', 'liability', 0, p_tenant_id),
    ('445510', 'TVA a deduire (biens et services)', 'asset', 0, p_tenant_id),
    ('445560', 'TVA a dedeductible (autres biens et services)', 'asset', 0, p_tenant_id),
    ('445570', 'TVA deductible (immobilisations)', 'asset', 0, p_tenant_id),
    ('445620', 'TVA due (biens et services)', 'liability', 0, p_tenant_id),
    ('445660', 'TVA deductible', 'liability', 0, p_tenant_id),
    ('445670', 'TVA deductible (immobilisations)', 'liability', 0, p_tenant_id),
    ('445710', 'TVA collectee', 'liability', 0, p_tenant_id),
    ('445800', 'TVA a regulariser', 'liability', 0, p_tenant_id),
    ('447000', 'Autres impots, taxes et versements assimiles', 'liability', 0, p_tenant_id),
    ('448000', 'Etat - charges a payer et produits a recevoir', 'liability', 0, p_tenant_id),
    ('448200', 'Etat - charges a payer', 'liability', 0, p_tenant_id),
    ('448600', 'Etat - produits a recevoir', 'asset', 0, p_tenant_id),
    ('449000', 'Etat - subventions a reverser', 'liability', 0, p_tenant_id),
    ('450000', 'Groupes et associes', 'liability', 0, p_tenant_id),
    ('451000', 'Groupes', 'liability', 0, p_tenant_id),
    ('455000', 'Associes - comptes courants', 'liability', 0, p_tenant_id),
    ('456000', 'Associes - operations sur le capital', 'liability', 0, p_tenant_id),
    ('456100', 'Associes - apports en nature', 'liability', 0, p_tenant_id),
    ('456200', 'Associes - apports en numeraire', 'liability', 0, p_tenant_id),
    ('456300', 'Associes - versements restant a effectuer', 'liability', 0, p_tenant_id),
    ('456400', 'Associes - versements anticipes', 'asset', 0, p_tenant_id),
    ('457000', 'Associes - dividendes a payer', 'liability', 0, p_tenant_id),
    ('458000', 'Associes - operations faites en commun', 'liability', 0, p_tenant_id),
    ('460000', 'Debiteurs divers et crediteurs divers', 'asset', 0, p_tenant_id),
    ('461000', 'Debiteurs divers', 'asset', 0, p_tenant_id),
    ('462000', 'Crediteurs divers', 'liability', 0, p_tenant_id),
    ('463000', 'Debiteurs et crediteurs divers', 'asset', 0, p_tenant_id),
    ('464000', 'Debiteurs et crediteurs divers', 'liability', 0, p_tenant_id),
    ('465000', 'Comptes de liaison des etablissements', 'liability', 0, p_tenant_id),
    ('467000', 'Autres comptes debiteurs ou crediteurs', 'asset', 0, p_tenant_id),
    ('468000', 'Divers - charges a payer et produits a recevoir', 'liability', 0, p_tenant_id),
    ('468600', 'Divers - produits a recevoir', 'asset', 0, p_tenant_id),
    ('468700', 'Divers - charges a payer', 'liability', 0, p_tenant_id),
    ('470000', 'Comptes d attente', 'liability', 0, p_tenant_id),
    ('471000', 'Comptes d attente', 'liability', 0, p_tenant_id),
    ('480000', 'Comptes de regularisation', 'liability', 0, p_tenant_id),
    ('481000', 'Charges constatees d avance', 'asset', 0, p_tenant_id),
    ('486000', 'Charges reparties dans le temps', 'asset', 0, p_tenant_id),
    ('487000', 'Produits constates d avance', 'liability', 0, p_tenant_id),
    ('488000', 'Comptes de repartition periodique des charges et produits', 'liability', 0, p_tenant_id),
    ('490000', 'Depreciations des comptes de clients', 'asset', 0, p_tenant_id),
    ('491000', 'Depreciations des comptes de clients', 'asset', 0, p_tenant_id),
    ('495000', 'Depreciations des comptes de debiteurs divers', 'asset', 0, p_tenant_id),
    ('496000', 'Depreciations des creances diverses', 'asset', 0, p_tenant_id),
    -- Classe 5 - Comptes financiers
    ('500000', 'Valeurs mobilieres de placement', 'asset', 0, p_tenant_id),
    ('501000', 'Titres de placement', 'asset', 0, p_tenant_id),
    ('502000', 'Actions propres', 'asset', 0, p_tenant_id),
    ('503000', 'Actions', 'asset', 0, p_tenant_id),
    ('504000', 'Obligations', 'asset', 0, p_tenant_id),
    ('505000', 'Bons du Tresor et bons de caisse', 'asset', 0, p_tenant_id),
    ('506000', 'Obligations et bons emis par la societe', 'asset', 0, p_tenant_id),
    ('507000', 'Bons du Tresor et bons de caisse (emis par la societe)', 'asset', 0, p_tenant_id),
    ('508000', 'Autres valeurs mobilieres de placement', 'asset', 0, p_tenant_id),
    ('509000', 'Versements restant a effectuer sur VMP', 'liability', 0, p_tenant_id),
    ('510000', 'Banques, etablissements financiers et assimiles', 'asset', 0, p_tenant_id),
    ('511000', 'Valeurs a l encaissement', 'asset', 0, p_tenant_id),
    ('511100', 'Coupons echus non encaisses', 'asset', 0, p_tenant_id),
    ('511200', 'Dividendes a encaisser', 'asset', 0, p_tenant_id),
    ('511300', 'Effets a encaisser', 'asset', 0, p_tenant_id),
    ('511400', 'Effets a l encaissement', 'asset', 0, p_tenant_id),
    ('511500', 'Effets remis a l escompte', 'asset', 0, p_tenant_id),
    ('512000', 'Banque', 'asset', 0, p_tenant_id),
    ('512100', 'Comptes en monnaie nationale', 'asset', 0, p_tenant_id),
    ('512400', 'Comptes en devises', 'asset', 0, p_tenant_id),
    ('514000', 'Banques - etablissements financiers', 'asset', 0, p_tenant_id),
    ('515000', 'Caisses du Tresor et des PTT', 'asset', 0, p_tenant_id),
    ('516000', 'Societes de bourse', 'asset', 0, p_tenant_id),
    ('517000', 'Banques a l etranger', 'asset', 0, p_tenant_id),
    ('518000', 'Interets courus a payer', 'liability', 0, p_tenant_id),
    ('518100', 'Interets courus a payer (emprunts)', 'liability', 0, p_tenant_id),
    ('518600', 'Interets courus a recevoir', 'asset', 0, p_tenant_id),
    ('518800', 'Interets courus a payer (autres)', 'liability', 0, p_tenant_id),
    ('519000', 'Concours bancaires courants', 'liability', 0, p_tenant_id),
    ('519100', 'Credit de mobilisation de creances commerciales', 'liability', 0, p_tenant_id),
    ('519300', 'Mobilisation de creances nes a l etranger', 'liability', 0, p_tenant_id),
    ('519400', 'Autres concours bancaires courants', 'liability', 0, p_tenant_id),
    ('519500', 'Credit de mobilisation de creances commerciales (escompte)', 'liability', 0, p_tenant_id),
    ('519700', 'Autres concours bancaires courants', 'liability', 0, p_tenant_id),
    ('520000', 'Instruments de tresorerie', 'asset', 0, p_tenant_id),
    ('521000', 'Instruments de tresorerie - droits', 'asset', 0, p_tenant_id),
    ('522000', 'Instruments de tresorerie - obligations', 'liability', 0, p_tenant_id),
    ('530000', 'Caisse', 'asset', 0, p_tenant_id),
    ('531000', 'Caisse - siege social', 'asset', 0, p_tenant_id),
    ('532000', 'Caisse - succursale ou usine', 'asset', 0, p_tenant_id),
    ('535000', 'Caisse - etablissement a l etranger', 'asset', 0, p_tenant_id),
    ('540000', 'Regies d avances et accréditifs', 'asset', 0, p_tenant_id),
    ('550000', 'Caisse - monnaies etrangeres', 'asset', 0, p_tenant_id),
    ('580000', 'Virements internes', 'asset', 0, p_tenant_id),
    ('590000', 'Depreciations des comptes financiers', 'asset', 0, p_tenant_id),
    ('590100', 'Depreciations des VMP', 'asset', 0, p_tenant_id),
    ('590800', 'Depreciations des autres valeurs mobilieres', 'asset', 0, p_tenant_id),
    -- Classe 6 - Charges
    ('600000', 'Achats (sauf 603)', 'expense', 0, p_tenant_id),
    ('601000', 'Achats de matieres premieres', 'expense', 0, p_tenant_id),
    ('601100', 'Achats de matieres premieres (group A)', 'expense', 0, p_tenant_id),
    ('601200', 'Achats de matieres premieres (group B)', 'expense', 0, p_tenant_id),
    ('602000', 'Achats de matieres consommables', 'expense', 0, p_tenant_id),
    ('602100', 'Achats de matieres consommables', 'expense', 0, p_tenant_id),
    ('602200', 'Achats de fournitures consommables', 'expense', 0, p_tenant_id),
    ('602210', 'Achats de fournitures de bureau', 'expense', 0, p_tenant_id),
    ('602220', 'Achats de fournitures d atelier', 'expense', 0, p_tenant_id),
    ('602400', 'Achats de combustibles', 'expense', 0, p_tenant_id),
    ('602500', 'Achats de produits d entretien', 'expense', 0, p_tenant_id),
    ('602600', 'Achats de fournitures d emballage', 'expense', 0, p_tenant_id),
    ('603000', 'Variations des stocks', 'expense', 0, p_tenant_id),
    ('603100', 'Variation des stocks de matieres premieres', 'expense', 0, p_tenant_id),
    ('603200', 'Variation des stocks de matieres et fournitures consommables', 'expense', 0, p_tenant_id),
    ('603700', 'Variation des stocks de marchandises', 'expense', 0, p_tenant_id),
    ('604000', 'Achats d etudes et de prestations de services', 'expense', 0, p_tenant_id),
    ('605000', 'Achats de materiels, equipements et travaux', 'expense', 0, p_tenant_id),
    ('606000', 'Achats non stockes de matieres et fournitures', 'expense', 0, p_tenant_id),
    ('606100', 'Fournitures non stockables (eau, energie)', 'expense', 0, p_tenant_id),
    ('606110', 'Eau', 'expense', 0, p_tenant_id),
    ('606120', 'Energie (gaz, electricite)', 'expense', 0, p_tenant_id),
    ('606130', 'Carburants', 'expense', 0, p_tenant_id),
    ('606400', 'Fournitures d entretien non stockables', 'expense', 0, p_tenant_id),
    ('606410', 'Produits d entretien', 'expense', 0, p_tenant_id),
    ('606500', 'Fournitures de bureau', 'expense', 0, p_tenant_id),
    ('606600', 'Fournitures de bureau non stockables', 'expense', 0, p_tenant_id),
    ('606800', 'Autres achats non stockes de matieres et fournitures', 'expense', 0, p_tenant_id),
    ('607000', 'Achats de marchandises', 'expense', 0, p_tenant_id),
    ('607100', 'Achats de marchandises (group A)', 'expense', 0, p_tenant_id),
    ('607200', 'Achats de marchandises (group B)', 'expense', 0, p_tenant_id),
    ('608000', 'Frais accessoires d achats', 'expense', 0, p_tenant_id),
    ('608100', 'Frais accessoires d achats sur matieres premieres', 'expense', 0, p_tenant_id),
    ('608200', 'Frais accessoires d achats sur matieres consommables', 'expense', 0, p_tenant_id),
    ('608700', 'Frais accessoires d achats sur marchandises', 'expense', 0, p_tenant_id),
    ('609000', 'Rabais, remises et ristournes obtenus sur achats', 'expense', 0, p_tenant_id),
    ('609100', 'Rabais, remises et ristournes sur achats de matieres premieres', 'expense', 0, p_tenant_id),
    ('609400', 'Rabais, remises et ristournes sur achats d etudes et prestations', 'expense', 0, p_tenant_id),
    ('609600', 'Rabais, remises et ristournes sur achats non stockes', 'expense', 0, p_tenant_id),
    ('609700', 'Rabais, remises et ristournes sur achats de marchandises', 'expense', 0, p_tenant_id),
    ('609800', 'Rabais, remises et ristournes sur frais accessoires d achats', 'expense', 0, p_tenant_id),
    ('610000', 'Services exterieurs', 'expense', 0, p_tenant_id),
    ('611000', 'Sous-traitance generale', 'expense', 0, p_tenant_id),
    ('611100', 'Sous-traitance generale', 'expense', 0, p_tenant_id),
    ('611200', 'Sous-traitance generale (group B)', 'expense', 0, p_tenant_id),
    ('611400', 'Sous-traitance generale (autres)', 'expense', 0, p_tenant_id),
    ('612000', 'Redevances de credit-bail', 'expense', 0, p_tenant_id),
    ('612100', 'Redevances de credit-bail mobilier', 'expense', 0, p_tenant_id),
    ('612200', 'Redevances de credit-bail immobilier', 'expense', 0, p_tenant_id),
    ('612500', 'Redevances de contrats de location-vente', 'expense', 0, p_tenant_id),
    ('613000', 'Locations', 'expense', 0, p_tenant_id),
    ('613100', 'Locations de terrains', 'expense', 0, p_tenant_id),
    ('613200', 'Locations de constructions', 'expense', 0, p_tenant_id),
    ('613500', 'Locations de materiels et outillages', 'expense', 0, p_tenant_id),
    ('613600', 'Locations de materiels et outillages (group B)', 'expense', 0, p_tenant_id),
    ('614000', 'Charges locatives et de copropriete', 'expense', 0, p_tenant_id),
    ('615000', 'Entretien et reparations', 'expense', 0, p_tenant_id),
    ('615100', 'Entretien et reparations de biens immobiliers', 'expense', 0, p_tenant_id),
    ('615200', 'Entretien et reparations de biens mobiliers', 'expense', 0, p_tenant_id),
    ('615500', 'Entretien et reparations de materiels', 'expense', 0, p_tenant_id),
    ('615600', 'Entretien et reparations de materiels de transport', 'expense', 0, p_tenant_id),
    ('616000', 'Assurances', 'expense', 0, p_tenant_id),
    ('616100', 'Assurances multirisques', 'expense', 0, p_tenant_id),
    ('616200', 'Assurances obligatoires dommages construction', 'expense', 0, p_tenant_id),
    ('616300', 'Assurances transports', 'expense', 0, p_tenant_id),
    ('616360', 'Assurances transports (sur achats)', 'expense', 0, p_tenant_id),
    ('616370', 'Assurances transports (sur ventes)', 'expense', 0, p_tenant_id),
    ('616400', 'Assurances risques d exploitation', 'expense', 0, p_tenant_id),
    ('616500', 'Assurances automobiles', 'expense', 0, p_tenant_id),
    ('616600', 'Assurances personnels', 'expense', 0, p_tenant_id),
    ('616800', 'Autres assurances', 'expense', 0, p_tenant_id),
    ('617000', 'Etudes et recherches', 'expense', 0, p_tenant_id),
    ('618000', 'Documentation', 'expense', 0, p_tenant_id),
    ('618100', 'Documentation generale', 'expense', 0, p_tenant_id),
    ('618200', 'Documentation technique', 'expense', 0, p_tenant_id),
    ('618300', 'Documentation commerciale', 'expense', 0, p_tenant_id),
    ('618400', 'Documentation administrative', 'expense', 0, p_tenant_id),
    ('619000', 'Rabais, remises et ristournes obtenus sur services exterieurs', 'expense', 0, p_tenant_id),
    ('620000', 'Autres services exterieurs', 'expense', 0, p_tenant_id),
    ('621000', 'Personnel exterieur a l entreprise', 'expense', 0, p_tenant_id),
    ('621100', 'Personnel integre', 'expense', 0, p_tenant_id),
    ('621400', 'Personnel detache par d autres entreprises', 'expense', 0, p_tenant_id),
    ('621600', 'Personnel exterieur a l entreprise (autres)', 'expense', 0, p_tenant_id),
    ('622000', 'Remuneration d intermediaires et honoraires', 'expense', 0, p_tenant_id),
    ('622100', 'Honoraires (non retenus par la source)', 'expense', 0, p_tenant_id),
    ('622200', 'Commissions et courtages sur achats', 'expense', 0, p_tenant_id),
    ('622400', 'Commissions et courtages sur ventes', 'expense', 0, p_tenant_id),
    ('622500', 'Frais de recouvrement', 'expense', 0, p_tenant_id),
    ('622600', 'Frais d actes et de contentieux', 'expense', 0, p_tenant_id),
    ('622700', 'Frais de reunion, de reception et de representant', 'expense', 0, p_tenant_id),
    ('622800', 'Divers', 'expense', 0, p_tenant_id),
    ('623000', 'Publicite, publications, relations publiques', 'expense', 0, p_tenant_id),
    ('623100', 'Annonces et insertions', 'expense', 0, p_tenant_id),
    ('623200', 'Echantillons, catalogues et prospectus', 'expense', 0, p_tenant_id),
    ('623300', 'Foires et expositions', 'expense', 0, p_tenant_id),
    ('623400', 'Cadeaux a la clientele', 'expense', 0, p_tenant_id),
    ('623500', 'Primes', 'expense', 0, p_tenant_id),
    ('623600', 'Catalogues et imprimes', 'expense', 0, p_tenant_id),
    ('623700', 'Publicite directe', 'expense', 0, p_tenant_id),
    ('623800', 'Divers (pourboires, etc.)', 'expense', 0, p_tenant_id),
    ('624000', 'Transports de biens et transports collectifs du personnel', 'expense', 0, p_tenant_id),
    ('624100', 'Transports sur achats', 'expense', 0, p_tenant_id),
    ('624200', 'Transports sur ventes', 'expense', 0, p_tenant_id),
    ('624300', 'Transports entre etablissements', 'expense', 0, p_tenant_id),
    ('624400', 'Transports administratifs', 'expense', 0, p_tenant_id),
    ('624700', 'Transports collectifs du personnel', 'expense', 0, p_tenant_id),
    ('625000', 'Deplacements, missions et receptions', 'expense', 0, p_tenant_id),
    ('625100', 'Voyages et deplacements', 'expense', 0, p_tenant_id),
    ('625600', 'Missions', 'expense', 0, p_tenant_id),
    ('625700', 'Receptions', 'expense', 0, p_tenant_id),
    ('626000', 'Frais postaux et de telecommunications', 'expense', 0, p_tenant_id),
    ('626100', 'Frais postaux', 'expense', 0, p_tenant_id),
    ('626300', 'Frais de telecommunications', 'expense', 0, p_tenant_id),
    ('626500', 'Frais de telecommunications (autres)', 'expense', 0, p_tenant_id),
    ('627000', 'Services bancaires et assimiles', 'expense', 0, p_tenant_id),
    ('627100', 'Frais de tenue de compte', 'expense', 0, p_tenant_id),
    ('627200', 'Commissions sur acceptation et negociation de creances', 'expense', 0, p_tenant_id),
    ('627500', 'Commissions et frais sur encaissements', 'expense', 0, p_tenant_id),
    ('627600', 'Commissions et frais sur encaissements (autres)', 'expense', 0, p_tenant_id),
    ('627800', 'Autres frais et commissions sur prestations de services', 'expense', 0, p_tenant_id),
    ('628000', 'Divers', 'expense', 0, p_tenant_id),
    ('628100', 'Concours divers (cotisations, etc.)', 'expense', 0, p_tenant_id),
    ('628400', 'Frais de recrutement de personnel', 'expense', 0, p_tenant_id),
    ('629000', 'Rabais, remises et ristournes obtenus sur autres services exterieurs', 'expense', 0, p_tenant_id),
    ('630000', 'Autres charges', 'expense', 0, p_tenant_id),
    ('631000', 'Impots, taxes et versements assimiles sur remunerations', 'expense', 0, p_tenant_id),
    ('631100', 'Impots, taxes et versements assimiles sur remunerations (administrations)', 'expense', 0, p_tenant_id),
    ('631200', 'Impots, taxes et versements assimiles sur remunerations (autres organismes)', 'expense', 0, p_tenant_id),
    ('631300', 'Participation des employeurs a la formation professionnelle continue', 'expense', 0, p_tenant_id),
    ('631400', 'Participation des employeurs a l effort de construction', 'expense', 0, p_tenant_id),
    ('631600', 'Impots, taxes et versements assimiles sur remunerations (autres)', 'expense', 0, p_tenant_id),
    ('631800', 'Autres impots, taxes et versements assimiles sur remunerations', 'expense', 0, p_tenant_id),
    ('633000', 'Impots, taxes et versements assimiles sur immobilisations', 'expense', 0, p_tenant_id),
    ('635000', 'Impots, taxes et versements assimiles sur le chiffre d affaires', 'expense', 0, p_tenant_id),
    ('635100', 'Impots, taxes et versements assimiles sur le chiffre d affaires (TVA)', 'expense', 0, p_tenant_id),
    ('635200', 'Impots, taxes et versements assimiles sur le chiffre d affaires (autres)', 'expense', 0, p_tenant_id),
    ('635300', 'Impots, taxes et versements assimiles sur le chiffre d affaires (autres)', 'expense', 0, p_tenant_id),
    ('635400', 'Impots, taxes et versements assimiles sur le chiffre d affaires (autres)', 'expense', 0, p_tenant_id),
    ('635500', 'Impots, taxes et versements assimiles sur le chiffre d affaires (autres)', 'expense', 0, p_tenant_id),
    ('635800', 'Autres impots, taxes et versements assimiles sur le chiffre d affaires', 'expense', 0, p_tenant_id),
    ('636000', 'Impots, taxes et versements assimiles sur le capital', 'expense', 0, p_tenant_id),
    ('637000', 'Autres impots, taxes et versements assimiles', 'expense', 0, p_tenant_id),
    ('637100', 'Impots, taxes et versements assimiles (autres)', 'expense', 0, p_tenant_id),
    ('637200', 'Impots, taxes et versements assimiles (autres)', 'expense', 0, p_tenant_id),
    ('637300', 'Impots, taxes et versements assimiles (autres)', 'expense', 0, p_tenant_id),
    ('637400', 'Impots, taxes et versements assimiles (autres)', 'expense', 0, p_tenant_id),
    ('637800', 'Autres impots, taxes et versements assimiles', 'expense', 0, p_tenant_id),
    ('638000', 'Autres impots, taxes et versements assimiles', 'expense', 0, p_tenant_id),
    ('639000', 'Rabais, remises et ristournes obtenus sur autres charges externes', 'expense', 0, p_tenant_id),
    ('640000', 'Charges de personnel', 'expense', 0, p_tenant_id),
    ('641000', 'Remunerations du personnel', 'expense', 0, p_tenant_id),
    ('641100', 'Apprentis', 'expense', 0, p_tenant_id),
    ('641200', 'Stagiaires', 'expense', 0, p_tenant_id),
    ('641300', 'Remunerations du personnel (autres)', 'expense', 0, p_tenant_id),
    ('641400', 'Remunerations du personnel (autres)', 'expense', 0, p_tenant_id),
    ('641500', 'Remunerations du personnel (autres)', 'expense', 0, p_tenant_id),
    ('641600', 'Remunerations du personnel (autres)', 'expense', 0, p_tenant_id),
    ('641700', 'Remunerations du personnel (autres)', 'expense', 0, p_tenant_id),
    ('641800', 'Remunerations du personnel (autres)', 'expense', 0, p_tenant_id),
    ('642000', 'Remunerations du personnel de direction', 'expense', 0, p_tenant_id),
    ('643000', 'Remunerations du personnel de direction', 'expense', 0, p_tenant_id),
    ('644000', 'Remuneration du travail de l exploitant', 'expense', 0, p_tenant_id),
    ('645000', 'Charges sociales', 'expense', 0, p_tenant_id),
    ('645100', 'Cotisations a l URSSAF', 'expense', 0, p_tenant_id),
    ('645200', 'Cotisations aux mutuelles', 'expense', 0, p_tenant_id),
    ('645300', 'Cotisations caisses de retraite', 'expense', 0, p_tenant_id),
    ('645400', 'Cotisations aux ASSEDIC', 'expense', 0, p_tenant_id),
    ('645500', 'Prevoyances', 'expense', 0, p_tenant_id),
    ('645800', 'Cotisations aux autres organismes sociaux', 'expense', 0, p_tenant_id),
    ('646000', 'Cotisations sociales personnelles de l exploitant', 'expense', 0, p_tenant_id),
    ('647000', 'Autres charges sociales', 'expense', 0, p_tenant_id),
    ('647100', 'Prestations de retraites', 'expense', 0, p_tenant_id),
    ('647200', 'Prestations directes', 'expense', 0, p_tenant_id),
    ('647300', 'Prestations de retraites (autres)', 'expense', 0, p_tenant_id),
    ('647400', 'Prestations directes (autres)', 'expense', 0, p_tenant_id),
    ('647500', 'Medecine du travail, pharmacie', 'expense', 0, p_tenant_id),
    ('647800', 'Autres charges sociales', 'expense', 0, p_tenant_id),
    ('648000', 'Autres charges de personnel', 'expense', 0, p_tenant_id),
    ('649000', 'Rabais, remises et ristournes obtenus sur charges de personnel', 'expense', 0, p_tenant_id),
    ('650000', 'Autres charges de gestion courante', 'expense', 0, p_tenant_id),
    ('651000', 'Redevances pour concessions, brevets, licences, marques, procedes, logiciels', 'expense', 0, p_tenant_id),
    ('651100', 'Redevances pour concessions, brevets, licences, marques, procedes, logiciels', 'expense', 0, p_tenant_id),
    ('651600', 'Droits d auteur', 'expense', 0, p_tenant_id),
    ('651800', 'Autres redevances', 'expense', 0, p_tenant_id),
    ('653000', 'Jetons de presence', 'expense', 0, p_tenant_id),
    ('654000', 'Pertes sur creances irrecouvrables', 'expense', 0, p_tenant_id),
    ('654100', 'Pertes sur creances clients', 'expense', 0, p_tenant_id),
    ('654400', 'Pertes sur creances autres', 'expense', 0, p_tenant_id),
    ('655000', 'Quotes-parts de resultat sur operations faites en commun', 'expense', 0, p_tenant_id),
    ('655100', 'Quotes-parts de benefice', 'expense', 0, p_tenant_id),
    ('655200', 'Quotes-parts de pertes', 'expense', 0, p_tenant_id),
    ('656000', 'Pertes de change', 'expense', 0, p_tenant_id),
    ('656100', 'Pertes de change (autres)', 'expense', 0, p_tenant_id),
    ('656600', 'Pertes de change (autres)', 'expense', 0, p_tenant_id),
    ('656800', 'Ecarts de conversion - actif', 'expense', 0, p_tenant_id),
    ('657000', 'Charges de gestion courante (autres)', 'expense', 0, p_tenant_id),
    ('658000', 'Charges diverses de gestion courante', 'expense', 0, p_tenant_id),
    ('658100', 'Pertes sur operations a terme', 'expense', 0, p_tenant_id),
    ('658200', 'Pertes sur operations de change a terme', 'expense', 0, p_tenant_id),
    ('658600', 'Autres charges diverses de gestion courante', 'expense', 0, p_tenant_id),
    ('658800', 'Rabais, remises et ristournes obtenus sur autres charges de gestion courante', 'expense', 0, p_tenant_id),
    ('660000', 'Charges financieres', 'expense', 0, p_tenant_id),
    ('661000', 'Charges d interets', 'expense', 0, p_tenant_id),
    ('661100', 'Interets sur emprunts et dettes', 'expense', 0, p_tenant_id),
    ('661110', 'Interets sur emprunts', 'expense', 0, p_tenant_id),
    ('661120', 'Interets sur dettes financieres', 'expense', 0, p_tenant_id),
    ('661130', 'Interets sur comptes courants et depots crediteurs', 'expense', 0, p_tenant_id),
    ('661160', 'Interets bancaires et sur operations de financement', 'expense', 0, p_tenant_id),
    ('661170', 'Interets sur autres operations de financement', 'expense', 0, p_tenant_id),
    ('661180', 'Interets des obligations', 'expense', 0, p_tenant_id),
    ('661500', 'Interets bancaires et sur operations de financement (escompte)', 'expense', 0, p_tenant_id),
    ('661600', 'Interets sur autres operations de financement', 'expense', 0, p_tenant_id),
    ('661700', 'Interets sur autres operations de financement (autres)', 'expense', 0, p_tenant_id),
    ('661800', 'Interets sur autres operations de financement (autres)', 'expense', 0, p_tenant_id),
    ('662000', 'Pertes de change', 'expense', 0, p_tenant_id),
    ('664000', 'Pertes sur creances liees a des participations', 'expense', 0, p_tenant_id),
    ('665000', 'Escomptes accordes', 'expense', 0, p_tenant_id),
    ('666000', 'Pertes de change', 'expense', 0, p_tenant_id),
    ('667000', 'Charges nettes sur cessions d immobilisations financieres', 'expense', 0, p_tenant_id),
    ('668000', 'Autres charges financieres', 'expense', 0, p_tenant_id),
    ('668100', 'Interets sur obligations', 'expense', 0, p_tenant_id),
    ('668200', 'Interets sur bons de caisse', 'expense', 0, p_tenant_id),
    ('668400', 'Autres charges financieres (autres)', 'expense', 0, p_tenant_id),
    ('668800', 'Frais financiers sur emprunts', 'expense', 0, p_tenant_id),
    ('669000', 'Rabais, remises et ristournes obtenus sur charges financieres', 'expense', 0, p_tenant_id),
    ('670000', 'Charges exceptionnelles', 'expense', 0, p_tenant_id),
    ('671000', 'Charges exceptionnelles sur operations de gestion', 'expense', 0, p_tenant_id),
    ('671100', 'Penalites sur marches', 'expense', 0, p_tenant_id),
    ('671200', 'Penalites, amendes fiscales et penales', 'expense', 0, p_tenant_id),
    ('671300', 'Dons, liberalites', 'expense', 0, p_tenant_id),
    ('671400', 'Subventions accordees', 'expense', 0, p_tenant_id),
    ('671500', 'Rappels d impots (autres que sur le benefice)', 'expense', 0, p_tenant_id),
    ('671700', 'Rappels d impots (sur le benefice)', 'expense', 0, p_tenant_id),
    ('671800', 'Autres charges exceptionnelles', 'expense', 0, p_tenant_id),
    ('672000', 'Charges sur exercices anterieurs', 'expense', 0, p_tenant_id),
    ('672100', 'Charges sur exercices anterieurs (operations de gestion)', 'expense', 0, p_tenant_id),
    ('672200', 'Charges sur exercices anterieurs (operations de capital)', 'expense', 0, p_tenant_id),
    ('675000', 'Valeurs comptables des elements d actif cedes', 'expense', 0, p_tenant_id),
    ('675100', 'Immobilisations incorporelles', 'expense', 0, p_tenant_id),
    ('675200', 'Immobilisations corporelles', 'expense', 0, p_tenant_id),
    ('675300', 'Immobilisations financieres', 'expense', 0, p_tenant_id),
    ('675400', 'Stocks', 'expense', 0, p_tenant_id),
    ('675500', 'Autres elements d actif', 'expense', 0, p_tenant_id),
    ('675600', 'Actions propres', 'expense', 0, p_tenant_id),
    ('675800', 'Autres valeurs comptables des elements d actif cedes', 'expense', 0, p_tenant_id),
    ('676000', 'Pertes de change', 'expense', 0, p_tenant_id),
    ('678000', 'Autres charges exceptionnelles', 'expense', 0, p_tenant_id),
    ('678100', 'Bonis provenant de clauses d indexation', 'expense', 0, p_tenant_id),
    ('678200', 'Malis provenant de clauses d indexation', 'expense', 0, p_tenant_id),
    ('678300', 'Subventions d equilibrage', 'expense', 0, p_tenant_id),
    ('678400', 'Subventions d investissement a reprendre', 'expense', 0, p_tenant_id),
    ('678800', 'Autres charges exceptionnelles (autres)', 'expense', 0, p_tenant_id),
    ('679000', 'Rabais, remises et ristournes obtenus sur charges exceptionnelles', 'expense', 0, p_tenant_id),
    ('680000', 'Dotations aux amortissements et aux provisions', 'expense', 0, p_tenant_id),
    ('681000', 'Dotations aux amortissements et aux provisions - charges d exploitation', 'expense', 0, p_tenant_id),
    ('681100', 'Dotations aux amortissements sur immobilisations incorporelles', 'expense', 0, p_tenant_id),
    ('681110', 'Dotations aux amortissements des frais d etablissement', 'expense', 0, p_tenant_id),
    ('681120', 'Dotations aux amortissements des concessions, brevets, licences, logiciels', 'expense', 0, p_tenant_id),
    ('681150', 'Dotations aux amortissements des fonds commercial', 'expense', 0, p_tenant_id),
    ('681200', 'Dotations aux amortissements sur immobilisations corporelles', 'expense', 0, p_tenant_id),
    ('681210', 'Dotations aux amortissements des terrains', 'expense', 0, p_tenant_id),
    ('681220', 'Dotations aux amortissements des constructions', 'expense', 0, p_tenant_id),
    ('681230', 'Dotations aux amortissements des installations techniques', 'expense', 0, p_tenant_id),
    ('681240', 'Dotations aux amortissements du mobilier', 'expense', 0, p_tenant_id),
    ('681250', 'Dotations aux amortissements du materiel', 'expense', 0, p_tenant_id),
    ('681260', 'Dotations aux amortissements du materiel de transport', 'expense', 0, p_tenant_id),
    ('681700', 'Dotations aux amortissements des immobilisations en cours', 'expense', 0, p_tenant_id),
    ('681500', 'Dotations aux provisions pour risques d exploitation', 'expense', 0, p_tenant_id),
    ('681600', 'Dotations aux provisions pour depreciation des immobilisations incorporelles', 'expense', 0, p_tenant_id),
    ('681610', 'Dotations aux provisions pour depreciation des immobilisations corporelles', 'expense', 0, p_tenant_id),
    ('681620', 'Dotations aux provisions pour depreciation des stocks', 'expense', 0, p_tenant_id),
    ('681630', 'Dotations aux provisions pour depreciation des creances', 'expense', 0, p_tenant_id),
    ('681640', 'Dotations aux provisions pour depreciation des titres de placement', 'expense', 0, p_tenant_id),
    ('681650', 'Dotations aux provisions pour depreciation des autres elements d actif', 'expense', 0, p_tenant_id),
    ('681800', 'Autres dotations aux amortissements et aux provisions', 'expense', 0, p_tenant_id),
    ('681810', 'Dotations aux provisions pour risques et charges d exploitation', 'expense', 0, p_tenant_id),
    ('681820', 'Dotations aux provisions pour depreciation des actifs circulant', 'expense', 0, p_tenant_id),
    ('681830', 'Dotations aux provisions pour depreciation des comptes de tiers', 'expense', 0, p_tenant_id),
    ('681840', 'Dotations aux provisions pour depreciation des comptes financiers', 'expense', 0, p_tenant_id),
    ('681850', 'Dotations aux provisions pour depreciation des autres elements d actif', 'expense', 0, p_tenant_id),
    ('681860', 'Dotations aux provisions pour depreciation des autres elements d actif', 'expense', 0, p_tenant_id),
    ('681870', 'Dotations aux provisions pour depreciation des autres elements d actif', 'expense', 0, p_tenant_id),
    ('681880', 'Dotations aux provisions pour depreciation des autres elements d actif', 'expense', 0, p_tenant_id),
    ('681890', 'Dotations aux provisions pour depreciation des autres elements d actif', 'expense', 0, p_tenant_id),
    ('686000', 'Dotations aux amortissements et aux provisions - charges financieres', 'expense', 0, p_tenant_id),
    ('686100', 'Dotations aux amortissements des immobilisations financieres', 'expense', 0, p_tenant_id),
    ('686500', 'Dotations aux provisions pour risques financiers', 'expense', 0, p_tenant_id),
    ('686600', 'Dotations aux provisions pour depreciation des immobilisations financieres', 'expense', 0, p_tenant_id),
    ('686700', 'Dotations aux provisions pour depreciation des valeurs mobilieres de placement', 'expense', 0, p_tenant_id),
    ('686800', 'Autres dotations aux provisions financieres', 'expense', 0, p_tenant_id),
    ('687000', 'Dotations aux amortissements et aux provisions - charges exceptionnelles', 'expense', 0, p_tenant_id),
    ('687100', 'Dotations aux amortissements exceptionnels des immobilisations', 'expense', 0, p_tenant_id),
    ('687200', 'Dotations aux provisions reglementees (immobilisations)', 'expense', 0, p_tenant_id),
    ('687300', 'Dotations aux provisions reglementees (stocks)', 'expense', 0, p_tenant_id),
    ('687400', 'Dotations aux autres provisions reglementees', 'expense', 0, p_tenant_id),
    ('687500', 'Dotations aux provisions pour risques et charges exceptionnels', 'expense', 0, p_tenant_id),
    ('687600', 'Dotations aux provisions pour depreciation exceptionnelles', 'expense', 0, p_tenant_id),
    ('687700', 'Dotations aux autres provisions exceptionnelles', 'expense', 0, p_tenant_id),
    -- Classe 7 - Produits
    ('700000', 'Ventes de marchandises, production vendue (biens et services)', 'income', 0, p_tenant_id),
    ('701000', 'Ventes de produits finis', 'income', 0, p_tenant_id),
    ('701100', 'Ventes de produits finis (group A)', 'income', 0, p_tenant_id),
    ('701200', 'Ventes de produits finis (group B)', 'income', 0, p_tenant_id),
    ('702000', 'Ventes de produits intermediaires', 'income', 0, p_tenant_id),
    ('702100', 'Ventes de produits intermediaires (group A)', 'income', 0, p_tenant_id),
    ('702200', 'Ventes de produits intermediaires (group B)', 'income', 0, p_tenant_id),
    ('703000', 'Ventes de produits residuels', 'income', 0, p_tenant_id),
    ('704000', 'Travaux', 'income', 0, p_tenant_id),
    ('704100', 'Travaux de construction', 'income', 0, p_tenant_id),
    ('704200', 'Travaux de montage', 'income', 0, p_tenant_id),
    ('705000', 'Etudes', 'income', 0, p_tenant_id),
    ('706000', 'Prestations de services', 'income', 0, p_tenant_id),
    ('706100', 'Prestations de services (group A)', 'income', 0, p_tenant_id),
    ('706200', 'Prestations de services (group B)', 'income', 0, p_tenant_id),
    ('707000', 'Ventes de marchandises', 'income', 0, p_tenant_id),
    ('707100', 'Ventes de marchandises (group A)', 'income', 0, p_tenant_id),
    ('707200', 'Ventes de marchandises (group B)', 'income', 0, p_tenant_id),
    ('708000', 'Produits des activites annexes', 'income', 0, p_tenant_id),
    ('708100', 'Produits des services exploités dans l interet du personnel', 'income', 0, p_tenant_id),
    ('708200', 'Commissions et courtages', 'income', 0, p_tenant_id),
    ('708300', 'Locations diverses', 'income', 0, p_tenant_id),
    ('708400', 'Mise a disposition de personnel', 'income', 0, p_tenant_id),
    ('708500', 'Ports et frais accessoires factures', 'income', 0, p_tenant_id),
    ('708600', 'Bonis sur reprises de emballages consignés', 'income', 0, p_tenant_id),
    ('708800', 'Autres produits d activites annexes', 'income', 0, p_tenant_id),
    ('709000', 'Rabais, remises et ristournes accordes par l entreprise', 'income', 0, p_tenant_id),
    ('709100', 'Rabais, remises et ristournes sur ventes de produits finis', 'income', 0, p_tenant_id),
    ('709600', 'Rabais, remises et ristournes sur prestations de services', 'income', 0, p_tenant_id),
    ('709700', 'Rabais, remises et ristournes sur ventes de marchandises', 'income', 0, p_tenant_id),
    ('709800', 'Rabais, remises et ristournes sur produits des activites annexes', 'income', 0, p_tenant_id),
    ('710000', 'Variation des stocks et production stockee', 'income', 0, p_tenant_id),
    ('713000', 'Variation des stocks (en-cours de production, produits)', 'income', 0, p_tenant_id),
    ('713100', 'Variation des stocks de produits en cours', 'income', 0, p_tenant_id),
    ('713300', 'Variation des stocks de produits', 'income', 0, p_tenant_id),
    ('713400', 'Variation des stocks de services en cours', 'income', 0, p_tenant_id),
    ('713500', 'Variation des stocks de produits finis', 'income', 0, p_tenant_id),
    ('713600', 'Variation des stocks de produits residuels', 'income', 0, p_tenant_id),
    ('713700', 'Variation des stocks de marchandises', 'income', 0, p_tenant_id),
    ('720000', 'Production immobilisee', 'income', 0, p_tenant_id),
    ('721000', 'Production immobilisee - immobilisations incorporelles', 'income', 0, p_tenant_id),
    ('722000', 'Production immobilisee - immobilisations corporelles', 'income', 0, p_tenant_id),
    ('740000', 'Subventions d exploitation', 'income', 0, p_tenant_id),
    ('740100', 'Subventions d exploitation du budget de l Etat', 'income', 0, p_tenant_id),
    ('740200', 'Subventions d exploitation des collectivites locales', 'income', 0, p_tenant_id),
    ('740300', 'Subventions d exploitation des etablissements publics', 'income', 0, p_tenant_id),
    ('740400', 'Subventions d exploitation des entreprises publiques', 'income', 0, p_tenant_id),
    ('740500', 'Subventions d exploitation des autres organismes', 'income', 0, p_tenant_id),
    ('740600', 'Subventions d exploitation des autres organismes (autres)', 'income', 0, p_tenant_id),
    ('740700', 'Subventions d exploitation des autres organismes (autres)', 'income', 0, p_tenant_id),
    ('740800', 'Subventions d exploitation des autres organismes (autres)', 'income', 0, p_tenant_id),
    ('741000', 'Subventions d equilibrage', 'income', 0, p_tenant_id),
    ('748000', 'Autres subventions d exploitation', 'income', 0, p_tenant_id),
    ('750000', 'Autres produits de gestion courante', 'income', 0, p_tenant_id),
    ('751000', 'Redevances pour concessions, brevets, licences, marques, procedes, logiciels', 'income', 0, p_tenant_id),
    ('751100', 'Redevances pour concessions, brevets, licences, marques, procedes, logiciels', 'income', 0, p_tenant_id),
    ('751600', 'Droits d auteur', 'income', 0, p_tenant_id),
    ('751800', 'Autres redevances', 'income', 0, p_tenant_id),
    ('752000', 'Revenus des immeubles non affectes a l exploitation professionnelle', 'income', 0, p_tenant_id),
    ('753000', 'Jetons de presence et remuneration d administrateurs', 'income', 0, p_tenant_id),
    ('754000', 'Quotes-parts de resultat sur operations faites en commun', 'income', 0, p_tenant_id),
    ('754100', 'Quotes-parts de perte', 'income', 0, p_tenant_id),
    ('754200', 'Quotes-parts de benefice', 'income', 0, p_tenant_id),
    ('755000', 'Quotes-parts de perte sur operations faites en commun', 'income', 0, p_tenant_id),
    ('756000', 'Gains de change', 'income', 0, p_tenant_id),
    ('756100', 'Gains de change (autres)', 'income', 0, p_tenant_id),
    ('756600', 'Gains de change (autres)', 'income', 0, p_tenant_id),
    ('756800', 'Ecarts de conversion - passif', 'income', 0, p_tenant_id),
    ('757000', 'Produits de gestion courante (autres)', 'income', 0, p_tenant_id),
    ('758000', 'Produits divers de gestion courante', 'income', 0, p_tenant_id),
    ('758100', 'Gains sur operations a terme', 'income', 0, p_tenant_id),
    ('758200', 'Gains sur operations de change a terme', 'income', 0, p_tenant_id),
    ('758600', 'Autres produits divers de gestion courante', 'income', 0, p_tenant_id),
    ('758800', 'Rabais, remises et ristournes obtenus sur autres produits de gestion courante', 'income', 0, p_tenant_id),
    ('760000', 'Produits financiers', 'income', 0, p_tenant_id),
    ('761000', 'Produits de participations', 'income', 0, p_tenant_id),
    ('761100', 'Revenus des titres de participation', 'income', 0, p_tenant_id),
    ('761600', 'Revenus sur autres formes de participation', 'income', 0, p_tenant_id),
    ('761700', 'Quotes-parts de resultat sur operations faites en commun', 'income', 0, p_tenant_id),
    ('761800', 'Revenus des creances rattachees a des participations', 'income', 0, p_tenant_id),
    ('762000', 'Produits des autres immobilisations financieres', 'income', 0, p_tenant_id),
    ('762100', 'Revenus des titres immobilises', 'income', 0, p_tenant_id),
    ('762600', 'Revenus des pretes', 'income', 0, p_tenant_id),
    ('762700', 'Revenus des creances commerciales', 'income', 0, p_tenant_id),
    ('763000', 'Revenus des autres creances', 'income', 0, p_tenant_id),
    ('763100', 'Revenus des creances commerciales', 'income', 0, p_tenant_id),
    ('763200', 'Revenus des creances diverses', 'income', 0, p_tenant_id),
    ('764000', 'Revenus des valeurs mobilieres de placement', 'income', 0, p_tenant_id),
    ('764100', 'Revenus des actions', 'income', 0, p_tenant_id),
    ('764200', 'Revenus des obligations', 'income', 0, p_tenant_id),
    ('764300', 'Revenus des bons de caisse et du Tresor', 'income', 0, p_tenant_id),
    ('764400', 'Revenus des autres valeurs mobilieres de placement', 'income', 0, p_tenant_id),
    ('765000', 'Escomptes obtenus', 'income', 0, p_tenant_id),
    ('766000', 'Gains de change', 'income', 0, p_tenant_id),
    ('767000', 'Produits nets sur cessions d immobilisations financieres', 'income', 0, p_tenant_id),
    ('768000', 'Autres produits financiers', 'income', 0, p_tenant_id),
    ('768100', 'Interets sur obligations', 'income', 0, p_tenant_id),
    ('768200', 'Interets sur bons de caisse', 'income', 0, p_tenant_id),
    ('768400', 'Autres produits financiers (autres)', 'income', 0, p_tenant_id),
    ('768800', 'Produits des operations de financement', 'income', 0, p_tenant_id),
    ('769000', 'Rabais, remises et ristournes obtenus sur produits financiers', 'income', 0, p_tenant_id),
    ('770000', 'Produits exceptionnels', 'income', 0, p_tenant_id),
    ('771000', 'Produits exceptionnels sur operations de gestion', 'income', 0, p_tenant_id),
    ('771100', 'Dedommagements recus', 'income', 0, p_tenant_id),
    ('771200', 'Dégrèvements d impots', 'income', 0, p_tenant_id),
    ('771300', 'Liberalites recues', 'income', 0, p_tenant_id),
    ('771400', 'Subventions d equilibrage', 'income', 0, p_tenant_id),
    ('771500', 'Subventions d investissement', 'income', 0, p_tenant_id),
    ('771700', 'Rentrées sur creances amorties', 'income', 0, p_tenant_id),
    ('771800', 'Autres produits exceptionnels', 'income', 0, p_tenant_id),
    ('772000', 'Produits sur exercices anterieurs', 'income', 0, p_tenant_id),
    ('772100', 'Produits sur exercices anterieurs (operations de gestion)', 'income', 0, p_tenant_id),
    ('772200', 'Produits sur exercices anterieurs (operations de capital)', 'income', 0, p_tenant_id),
    ('775000', 'Produits des cessions d elements d actif', 'income', 0, p_tenant_id),
    ('775100', 'Immobilisations incorporelles', 'income', 0, p_tenant_id),
    ('775200', 'Immobilisations corporelles', 'income', 0, p_tenant_id),
    ('775300', 'Immobilisations financieres', 'income', 0, p_tenant_id),
    ('775400', 'Stocks', 'income', 0, p_tenant_id),
    ('775500', 'Autres elements d actif', 'income', 0, p_tenant_id),
    ('775600', 'Actions propres', 'income', 0, p_tenant_id),
    ('775800', 'Autres produits des cessions d elements d actif', 'income', 0, p_tenant_id),
    ('776000', 'Gains de change', 'income', 0, p_tenant_id),
    ('777000', 'Quotes-parts des subventions d investissement inscrites au resultat de l exercice', 'income', 0, p_tenant_id),
    ('778000', 'Autres produits exceptionnels', 'income', 0, p_tenant_id),
    ('778100', 'Bonis provenant de clauses d indexation', 'income', 0, p_tenant_id),
    ('778200', 'Malis provenant de clauses d indexation', 'income', 0, p_tenant_id),
    ('778300', 'Subventions d equilibrage', 'income', 0, p_tenant_id),
    ('778400', 'Subventions d investissement a reprendre', 'income', 0, p_tenant_id),
    ('778800', 'Autres produits exceptionnels (autres)', 'income', 0, p_tenant_id),
    ('779000', 'Rabais, remises et ristournes accordes sur produits exceptionnels', 'income', 0, p_tenant_id),
    ('780000', 'Reprises sur amortissements et provisions', 'income', 0, p_tenant_id),
    ('781000', 'Reprises sur amortissements et provisions - charges d exploitation', 'income', 0, p_tenant_id),
    ('781100', 'Reprises sur amortissements des immobilisations incorporelles', 'income', 0, p_tenant_id),
    ('781200', 'Reprises sur amortissements des immobilisations corporelles', 'income', 0, p_tenant_id),
    ('781500', 'Reprises sur provisions pour risques d exploitation', 'income', 0, p_tenant_id),
    ('781600', 'Reprises sur provisions pour depreciation des immobilisations incorporelles', 'income', 0, p_tenant_id),
    ('781610', 'Reprises sur provisions pour depreciation des immobilisations corporelles', 'income', 0, p_tenant_id),
    ('781620', 'Reprises sur provisions pour depreciation des stocks', 'income', 0, p_tenant_id),
    ('781630', 'Reprises sur provisions pour depreciation des creances', 'income', 0, p_tenant_id),
    ('781640', 'Reprises sur provisions pour depreciation des titres de placement', 'income', 0, p_tenant_id),
    ('781700', 'Reprises sur provisions pour depreciation des autres elements d actif', 'income', 0, p_tenant_id),
    ('781800', 'Autres reprises sur amortissements et provisions', 'income', 0, p_tenant_id),
    ('786000', 'Reprises sur amortissements et provisions - charges financieres', 'income', 0, p_tenant_id),
    ('786100', 'Reprises sur amortissements des immobilisations financieres', 'income', 0, p_tenant_id),
    ('786500', 'Reprises sur provisions pour risques financiers', 'income', 0, p_tenant_id),
    ('786600', 'Reprises sur provisions pour depreciation des immobilisations financieres', 'income', 0, p_tenant_id),
    ('786700', 'Reprises sur provisions pour depreciation des valeurs mobilieres de placement', 'income', 0, p_tenant_id),
    ('786800', 'Autres reprises sur provisions financieres', 'income', 0, p_tenant_id),
    ('787000', 'Reprises sur amortissements et provisions - charges exceptionnelles', 'income', 0, p_tenant_id),
    ('787100', 'Reprises sur amortissements exceptionnels des immobilisations', 'income', 0, p_tenant_id),
    ('787200', 'Reprises sur provisions reglementees (immobilisations)', 'income', 0, p_tenant_id),
    ('787300', 'Reprises sur provisions reglementees (stocks)', 'income', 0, p_tenant_id),
    ('787400', 'Reprises sur autres provisions reglementees', 'income', 0, p_tenant_id),
    ('787500', 'Reprises sur provisions pour risques et charges exceptionnels', 'income', 0, p_tenant_id),
    ('787600', 'Reprises sur provisions pour depreciation exceptionnelles', 'income', 0, p_tenant_id),
    ('787700', 'Reprises sur autres provisions exceptionnelles', 'income', 0, p_tenant_id),
    ('790000', 'Transferts de charges', 'income', 0, p_tenant_id),
    ('791000', 'Transferts de charges d exploitation', 'income', 0, p_tenant_id),
    ('796000', 'Transferts de charges financieres', 'income', 0, p_tenant_id),
    ('797000', 'Transferts de charges exceptionnelles', 'income', 0, p_tenant_id),
    -- Classe 8 - Comptes speciaux
    ('800000', 'Engagements financiers', 'liability', 0, p_tenant_id),
    ('801000', 'Engagements de garantie', 'liability', 0, p_tenant_id),
    ('801100', 'Avals, cautions, garanties', 'liability', 0, p_tenant_id),
    ('801400', 'Credits de signature par endossement', 'liability', 0, p_tenant_id),
    ('801700', 'Hypotèques', 'liability', 0, p_tenant_id),
    ('801800', 'Gages sur stocks', 'liability', 0, p_tenant_id),
    ('804000', 'Engagements financiers recus', 'asset', 0, p_tenant_id),
    ('804100', 'Avals, cautions, garanties recus', 'asset', 0, p_tenant_id),
    ('804400', 'Credits de signature par endossement recus', 'asset', 0, p_tenant_id),
    ('804500', 'Hypotèques recues', 'asset', 0, p_tenant_id),
    ('804800', 'Gages sur stocks recus', 'asset', 0, p_tenant_id),
    ('808000', 'Engagements divers', 'liability', 0, p_tenant_id),
    ('808100', 'Engagements divers donnes', 'liability', 0, p_tenant_id),
    ('808400', 'Engagements divers recus', 'asset', 0, p_tenant_id)
  ON CONFLICT (tenant_id, code) DO NOTHING;
END;
$function$;


CREATE OR REPLACE FUNCTION public.set_active_tenant(p_tenant_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  -- Validate that the caller is a member of this tenant
  IF NOT EXISTS (
    SELECT 1 FROM tenant_users
    WHERE auth_id = auth.uid()
      AND status = 'active'
      AND tenant_id = p_tenant_id
  ) THEN
    RAISE EXCEPTION 'User is not an active member of tenant %', p_tenant_id;
  END IF;

  PERFORM set_config('app.active_tenant_id', p_tenant_id::text, false);
END;
$function$;


CREATE OR REPLACE FUNCTION public.set_tenant_id()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF NEW.tenant_id IS NULL AND TG_TABLE_NAME != 'tenants' THEN
    NEW.tenant_id := current_tenant_id();
  END IF;
  RETURN NEW;
END;
$function$;


CREATE OR REPLACE FUNCTION public.set_user_name(p_name text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
  PERFORM set_config('app.user_name', COALESCE(p_name, 'Unknown'), false);
END;
$function$;


CREATE OR REPLACE FUNCTION public.update_stock_on_movement()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF NEW.movement_type = 'in' THEN
    PERFORM increment_stock(NEW.product_id, NEW.quantity, NEW.warehouse_id);
  ELSIF NEW.movement_type = 'out' THEN
    PERFORM decrement_stock(NEW.product_id, NEW.quantity, NEW.warehouse_id);
  ELSIF NEW.movement_type = 'adjustment' THEN
    -- Pour un ajustement, quantity est la nouvelle valeur absolue
    UPDATE products
      SET stock_quantity = NEW.quantity, updated_at = NOW()
      WHERE id = NEW.product_id AND tenant_id = current_tenant_id();
  END IF;
  RETURN NEW;
END;
$function$;


CREATE OR REPLACE FUNCTION public.update_tax_grid_timestamp()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$function$;


CREATE OR REPLACE FUNCTION public.update_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  new.updated_at = now();
  return new;
end;
$function$;


CREATE OR REPLACE FUNCTION public.update_updated_at_column()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$function$;


-- ============================================
-- VUES
-- ============================================
CREATE OR REPLACE VIEW balance_sheet AS  SELECT je.tenant_id,
    je.date,
    ja.code,
    ja.name,
    ja.type,
    COALESCE(sum(jl.debit), (0)::numeric) AS total_debit,
    COALESCE(sum(jl.credit), (0)::numeric) AS total_credit,
    (COALESCE(sum(jl.debit), (0)::numeric) - COALESCE(sum(jl.credit), (0)::numeric)) AS solde
   FROM ((journal_entries je
     JOIN journal_lines jl ON (((jl.journal_id = je.id) AND (jl.tenant_id = je.tenant_id))))
     JOIN chart_accounts ja ON (((ja.code = jl.account_code) AND (ja.tenant_id = je.tenant_id))))
  WHERE (je.status = ANY (ARRAY['posted'::text, 'draft'::text]))
  GROUP BY je.tenant_id, je.date, ja.code, ja.name, ja.type;;
CREATE OR REPLACE VIEW trial_balance AS  SELECT je.tenant_id,
    ja.code,
    ja.name,
    ja.type,
    COALESCE(sum(jl.debit), (0)::numeric) AS total_debit,
    COALESCE(sum(jl.credit), (0)::numeric) AS total_credit,
    (COALESCE(sum(jl.debit), (0)::numeric) - COALESCE(sum(jl.credit), (0)::numeric)) AS solde_debit,
    (COALESCE(sum(jl.credit), (0)::numeric) - COALESCE(sum(jl.debit), (0)::numeric)) AS solde_credit
   FROM ((journal_entries je
     JOIN journal_lines jl ON (((jl.journal_id = je.id) AND (jl.tenant_id = je.tenant_id))))
     JOIN chart_accounts ja ON (((ja.code = jl.account_code) AND (ja.tenant_id = je.tenant_id))))
  WHERE (je.status = ANY (ARRAY['posted'::text, 'draft'::text]))
  GROUP BY je.tenant_id, ja.code, ja.name, ja.type;;
CREATE OR REPLACE VIEW general_ledger AS  SELECT je.tenant_id,
    je.id AS entry_id,
    je.number AS entry_number,
    je.date,
    je.journal_code,
    je.status,
    je.description,
    jl.account_code,
    jl.description AS line_description,
    jl.debit,
    jl.credit,
    jl.line_order
   FROM (journal_entries je
     JOIN journal_lines jl ON (((jl.journal_id = je.id) AND (jl.tenant_id = je.tenant_id))))
  WHERE (je.status = ANY (ARRAY['posted'::text, 'draft'::text]));;
CREATE OR REPLACE VIEW vat_summary AS  SELECT i.tenant_id,
    i.id AS invoice_id,
    i.number AS invoice_number,
    i.date,
    il.vat_rate,
    sum((il.quantity * il.unit_price)) AS ht_amount,
    sum(((il.quantity * il.unit_price) * (il.vat_rate / (100)::numeric))) AS vat_amount,
    sum(((il.quantity * il.unit_price) * ((1)::numeric + (il.vat_rate / (100)::numeric)))) AS ttc_amount
   FROM (invoices i
     JOIN invoice_lines il ON (((il.invoice_id = i.id) AND (il.tenant_id = i.tenant_id))))
  WHERE (i.status <> 'cancelled'::text)
  GROUP BY i.tenant_id, i.id, i.number, i.date, il.vat_rate;;
CREATE OR REPLACE VIEW rls_audit AS  SELECT tablename,
    policyname,
    qual,
    with_check
   FROM pg_policies
  WHERE ((schemaname = 'public'::name) AND ((qual = 'true'::text) OR (with_check = 'true'::text) OR (qual = '(true)'::text) OR (with_check = '(true)'::text)))
  ORDER BY tablename;;

-- ============================================
-- TRIGGERS
-- ============================================
DROP TRIGGER IF EXISTS set_tenant_id_asset_depreciations ON asset_depreciations;
CREATE TRIGGER set_tenant_id_asset_depreciations BEFORE INSERT ON asset_depreciations EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS company_settings_updated_at ON company_settings;
CREATE TRIGGER company_settings_updated_at BEFORE UPDATE ON company_settings EXECUTE FUNCTION update_updated_at();
DROP TRIGGER IF EXISTS set_tenant_id_company_settings ON company_settings;
CREATE TRIGGER set_tenant_id_company_settings BEFORE INSERT ON company_settings EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS customers_updated_at ON customers;
CREATE TRIGGER customers_updated_at BEFORE UPDATE ON customers EXECUTE FUNCTION update_updated_at();
DROP TRIGGER IF EXISTS set_tenant_id_customers ON customers;
CREATE TRIGGER set_tenant_id_customers BEFORE INSERT ON customers EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_credit_notes ON credit_notes;
CREATE TRIGGER set_tenant_id_credit_notes BEFORE INSERT ON credit_notes EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS bank_accounts_updated_at ON bank_accounts;
CREATE TRIGGER bank_accounts_updated_at BEFORE UPDATE ON bank_accounts EXECUTE FUNCTION update_updated_at();
DROP TRIGGER IF EXISTS set_tenant_id_bank_accounts ON bank_accounts;
CREATE TRIGGER set_tenant_id_bank_accounts BEFORE INSERT ON bank_accounts EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_bank_transactions ON bank_transactions;
CREATE TRIGGER set_tenant_id_bank_transactions BEFORE INSERT ON bank_transactions EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_bank_rules ON bank_rules;
CREATE TRIGGER set_tenant_id_bank_rules BEFORE INSERT ON bank_rules EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_entry_templates ON entry_templates;
CREATE TRIGGER set_tenant_id_entry_templates BEFORE INSERT ON entry_templates EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_fixed_assets ON fixed_assets;
CREATE TRIGGER set_tenant_id_fixed_assets BEFORE INSERT ON fixed_assets EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_goods_receipt_lines ON goods_receipt_lines;
CREATE TRIGGER set_tenant_id_goods_receipt_lines BEFORE INSERT ON goods_receipt_lines EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_contracts ON contracts;
CREATE TRIGGER set_tenant_id_contracts BEFORE INSERT ON contracts EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_legal_declarations ON legal_declarations;
CREATE TRIGGER set_tenant_id_legal_declarations BEFORE INSERT ON legal_declarations EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_collection_reminders ON collection_reminders;
CREATE TRIGGER set_tenant_id_collection_reminders BEFORE INSERT ON collection_reminders EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS prevent_role_escalation ON tenant_users;
CREATE TRIGGER prevent_role_escalation BEFORE UPDATE ON tenant_users EXECUTE FUNCTION prevent_role_escalation();
DROP TRIGGER IF EXISTS set_tenant_id_currencies ON currencies;
CREATE TRIGGER set_tenant_id_currencies BEFORE INSERT ON currencies EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_goods_receipts ON goods_receipts;
CREATE TRIGGER set_tenant_id_goods_receipts BEFORE INSERT ON goods_receipts EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_payment_orders ON payment_orders;
CREATE TRIGGER set_tenant_id_payment_orders BEFORE INSERT ON payment_orders EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_payroll_accounting_entries ON payroll_accounting_entries;
CREATE TRIGGER set_tenant_id_payroll_accounting_entries BEFORE INSERT ON payroll_accounting_entries EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_routing_operations ON routing_operations;
CREATE TRIGGER set_tenant_id_routing_operations BEFORE INSERT ON routing_operations EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_stock_quantities ON stock_quantities;
CREATE TRIGGER set_tenant_id_stock_quantities BEFORE INSERT ON stock_quantities EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_stock_movements ON stock_movements;
CREATE TRIGGER set_tenant_id_stock_movements BEFORE INSERT ON stock_movements EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS update_stock_on_movement ON stock_movements;
CREATE TRIGGER update_stock_on_movement AFTER INSERT ON stock_movements EXECUTE FUNCTION update_stock_on_movement();
DROP TRIGGER IF EXISTS set_tenant_id_price_lists ON price_lists;
CREATE TRIGGER set_tenant_id_price_lists BEFORE INSERT ON price_lists EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_price_list_lines ON price_list_lines;
CREATE TRIGGER set_tenant_id_price_list_lines BEFORE INSERT ON price_list_lines EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_bom_lines ON bom_lines;
CREATE TRIGGER set_tenant_id_bom_lines BEFORE INSERT ON bom_lines EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_audit_log ON audit_log;
CREATE TRIGGER set_tenant_id_audit_log BEFORE INSERT ON audit_log EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_of_labels ON of_labels;
CREATE TRIGGER set_tenant_id_of_labels BEFORE INSERT ON of_labels EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_of_lots ON of_lots;
CREATE TRIGGER set_tenant_id_of_lots BEFORE INSERT ON of_lots EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_of_consumptions ON of_consumptions;
CREATE TRIGGER set_tenant_id_of_consumptions BEFORE INSERT ON of_consumptions EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_st_orders ON st_orders;
CREATE TRIGGER set_tenant_id_st_orders BEFORE INSERT ON st_orders EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_manufacturing_orders ON manufacturing_orders;
CREATE TRIGGER set_tenant_id_manufacturing_orders BEFORE INSERT ON manufacturing_orders EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_boms ON boms;
CREATE TRIGGER set_tenant_id_boms BEFORE INSERT ON boms EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS products_updated_at ON products;
CREATE TRIGGER products_updated_at BEFORE UPDATE ON products EXECUTE FUNCTION update_updated_at();
DROP TRIGGER IF EXISTS set_tenant_id_products ON products;
CREATE TRIGGER set_tenant_id_products BEFORE INSERT ON products EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_st_shipments ON st_shipments;
CREATE TRIGGER set_tenant_id_st_shipments BEFORE INSERT ON st_shipments EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_st_shipment_lines ON st_shipment_lines;
CREATE TRIGGER set_tenant_id_st_shipment_lines BEFORE INSERT ON st_shipment_lines EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_st_receipts ON st_receipts;
CREATE TRIGGER set_tenant_id_st_receipts BEFORE INSERT ON st_receipts EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_st_receipt_lines ON st_receipt_lines;
CREATE TRIGGER set_tenant_id_st_receipt_lines BEFORE INSERT ON st_receipt_lines EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_mrp_runs ON mrp_runs;
CREATE TRIGGER set_tenant_id_mrp_runs BEFORE INSERT ON mrp_runs EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_mrp_proposals ON mrp_proposals;
CREATE TRIGGER set_tenant_id_mrp_proposals BEFORE INSERT ON mrp_proposals EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_mrp_pending_docs ON mrp_pending_docs;
CREATE TRIGGER set_tenant_id_mrp_pending_docs BEFORE INSERT ON mrp_pending_docs EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_production_forecasts ON production_forecasts;
CREATE TRIGGER set_tenant_id_production_forecasts BEFORE INSERT ON production_forecasts EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_recurring_entries ON recurring_entries;
CREATE TRIGGER set_tenant_id_recurring_entries BEFORE INSERT ON recurring_entries EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_bank_reconciliation_rules ON bank_reconciliation_rules;
CREATE TRIGGER set_tenant_id_bank_reconciliation_rules BEFORE INSERT ON bank_reconciliation_rules EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_bank_statement_imports ON bank_statement_imports;
CREATE TRIGGER set_tenant_id_bank_statement_imports BEFORE INSERT ON bank_statement_imports EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_product_variants ON product_variants;
CREATE TRIGGER set_tenant_id_product_variants BEFORE INSERT ON product_variants EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_product_serial_numbers ON product_serial_numbers;
CREATE TRIGGER set_tenant_id_product_serial_numbers BEFORE INSERT ON product_serial_numbers EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_product_batches ON product_batches;
CREATE TRIGGER set_tenant_id_product_batches BEFORE INSERT ON product_batches EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_supplier_payments ON supplier_payments;
CREATE TRIGGER set_tenant_id_supplier_payments BEFORE INSERT ON supplier_payments EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_suppliers ON suppliers;
CREATE TRIGGER set_tenant_id_suppliers BEFORE INSERT ON suppliers EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS suppliers_updated_at ON suppliers;
CREATE TRIGGER suppliers_updated_at BEFORE UPDATE ON suppliers EXECUTE FUNCTION update_updated_at();
DROP TRIGGER IF EXISTS set_tenant_id_third_party_accounts ON third_party_accounts;
CREATE TRIGGER set_tenant_id_third_party_accounts BEFORE INSERT ON third_party_accounts EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_timesheets ON timesheets;
CREATE TRIGGER set_tenant_id_timesheets BEFORE INSERT ON timesheets EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_quality_checks ON quality_checks;
CREATE TRIGGER set_tenant_id_quality_checks BEFORE INSERT ON quality_checks EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_pick_lists ON pick_lists;
CREATE TRIGGER set_tenant_id_pick_lists BEFORE INSERT ON pick_lists EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_pick_list_lines ON pick_list_lines;
CREATE TRIGGER set_tenant_id_pick_list_lines BEFORE INSERT ON pick_list_lines EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_product_substitutes ON product_substitutes;
CREATE TRIGGER set_tenant_id_product_substitutes BEFORE INSERT ON product_substitutes EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS project_task_templates_updated_at ON project_task_templates;
CREATE TRIGGER project_task_templates_updated_at BEFORE UPDATE ON project_task_templates EXECUTE FUNCTION update_updated_at_column();
DROP TRIGGER IF EXISTS set_tenant_id_asset_split_components ON asset_split_components;
CREATE TRIGGER set_tenant_id_asset_split_components BEFORE INSERT ON asset_split_components EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_budget_commitments ON budget_commitments;
CREATE TRIGGER set_tenant_id_budget_commitments BEFORE INSERT ON budget_commitments EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_sales_orders ON sales_orders;
CREATE TRIGGER set_tenant_id_sales_orders BEFORE INSERT ON sales_orders EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_sales_order_lines ON sales_order_lines;
CREATE TRIGGER set_tenant_id_sales_order_lines BEFORE INSERT ON sales_order_lines EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_delivery_notes ON delivery_notes;
CREATE TRIGGER set_tenant_id_delivery_notes BEFORE INSERT ON delivery_notes EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_delivery_note_lines ON delivery_note_lines;
CREATE TRIGGER set_tenant_id_delivery_note_lines BEFORE INSERT ON delivery_note_lines EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_customer_payments ON customer_payments;
CREATE TRIGGER set_tenant_id_customer_payments BEFORE INSERT ON customer_payments EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_purchase_orders ON purchase_orders;
CREATE TRIGGER set_tenant_id_purchase_orders BEFORE INSERT ON purchase_orders EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_at_rates ON at_rates;
CREATE TRIGGER set_tenant_id_at_rates BEFORE INSERT ON at_rates EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_pay_runs ON pay_runs;
CREATE TRIGGER set_tenant_id_pay_runs BEFORE INSERT ON pay_runs EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_product_grid_combinations ON product_grid_combinations;
CREATE TRIGGER set_tenant_id_product_grid_combinations BEFORE INSERT ON product_grid_combinations EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_fiscal_periods ON fiscal_periods;
CREATE TRIGGER set_tenant_id_fiscal_periods BEFORE INSERT ON fiscal_periods EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_supplier_delivery_schedules ON supplier_delivery_schedules;
CREATE TRIGGER set_tenant_id_supplier_delivery_schedules BEFORE INSERT ON supplier_delivery_schedules EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_crm_opportunities ON crm_opportunities;
CREATE TRIGGER set_tenant_id_crm_opportunities BEFORE INSERT ON crm_opportunities EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_fiscal_years ON fiscal_years;
CREATE TRIGGER set_tenant_id_fiscal_years BEFORE INSERT ON fiscal_years EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_invoice_lines ON invoice_lines;
CREATE TRIGGER set_tenant_id_invoice_lines BEFORE INSERT ON invoice_lines EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS invoices_updated_at ON invoices;
CREATE TRIGGER invoices_updated_at BEFORE UPDATE ON invoices EXECUTE FUNCTION update_updated_at();
DROP TRIGGER IF EXISTS set_tenant_id_invoices ON invoices;
CREATE TRIGGER set_tenant_id_invoices BEFORE INSERT ON invoices EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS check_fiscal_period_open ON journal_entries;
CREATE TRIGGER check_fiscal_period_open BEFORE INSERT ON journal_entries EXECUTE FUNCTION check_fiscal_period_open();
DROP TRIGGER IF EXISTS check_fiscal_period_open ON journal_entries;
CREATE TRIGGER check_fiscal_period_open BEFORE UPDATE ON journal_entries EXECUTE FUNCTION check_fiscal_period_open();
DROP TRIGGER IF EXISTS journal_entries_updated_at ON journal_entries;
CREATE TRIGGER journal_entries_updated_at BEFORE UPDATE ON journal_entries EXECUTE FUNCTION update_updated_at();
DROP TRIGGER IF EXISTS prevent_posted_entry_modification ON journal_entries;
CREATE TRIGGER prevent_posted_entry_modification BEFORE DELETE ON journal_entries EXECUTE FUNCTION prevent_posted_entry_modification();
DROP TRIGGER IF EXISTS prevent_posted_entry_modification ON journal_entries;
CREATE TRIGGER prevent_posted_entry_modification BEFORE UPDATE ON journal_entries EXECUTE FUNCTION prevent_posted_entry_modification();
DROP TRIGGER IF EXISTS set_tenant_id_journal_entries ON journal_entries;
CREATE TRIGGER set_tenant_id_journal_entries BEFORE INSERT ON journal_entries EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_credit_note_lines ON credit_note_lines;
CREATE TRIGGER set_tenant_id_credit_note_lines BEFORE INSERT ON credit_note_lines EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_pay_slips ON pay_slips;
CREATE TRIGGER set_tenant_id_pay_slips BEFORE INSERT ON pay_slips EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_routings ON routings;
CREATE TRIGGER set_tenant_id_routings BEFORE INSERT ON routings EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_work_centers ON work_centers;
CREATE TRIGGER set_tenant_id_work_centers BEFORE INSERT ON work_centers EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_machines ON machines;
CREATE TRIGGER set_tenant_id_machines BEFORE INSERT ON machines EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_purchase_invoice_lines ON purchase_invoice_lines;
CREATE TRIGGER set_tenant_id_purchase_invoice_lines BEFORE INSERT ON purchase_invoice_lines EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS purchase_invoices_updated_at ON purchase_invoices;
CREATE TRIGGER purchase_invoices_updated_at BEFORE UPDATE ON purchase_invoices EXECUTE FUNCTION update_updated_at();
DROP TRIGGER IF EXISTS set_tenant_id_purchase_invoices ON purchase_invoices;
CREATE TRIGGER set_tenant_id_purchase_invoices BEFORE INSERT ON purchase_invoices EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_toolings ON toolings;
CREATE TRIGGER set_tenant_id_toolings BEFORE INSERT ON toolings EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_quote_lines ON quote_lines;
CREATE TRIGGER set_tenant_id_quote_lines BEFORE INSERT ON quote_lines EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_purchase_credit_lines ON purchase_credit_lines;
CREATE TRIGGER set_tenant_id_purchase_credit_lines BEFORE INSERT ON purchase_credit_lines EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_quotes ON quotes;
CREATE TRIGGER set_tenant_id_quotes BEFORE INSERT ON quotes EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_crm_campaign_recipients ON crm_campaign_recipients;
CREATE TRIGGER set_tenant_id_crm_campaign_recipients BEFORE INSERT ON crm_campaign_recipients EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_planning_slots ON planning_slots;
CREATE TRIGGER set_tenant_id_planning_slots BEFORE INSERT ON planning_slots EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_career_history ON career_history;
CREATE TRIGGER set_tenant_id_career_history BEFORE INSERT ON career_history EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_expense_report_lines ON expense_report_lines;
CREATE TRIGGER set_tenant_id_expense_report_lines BEFORE INSERT ON expense_report_lines EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_expense_reports ON expense_reports;
CREATE TRIGGER set_tenant_id_expense_reports BEFORE INSERT ON expense_reports EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_product_equivalences ON product_equivalences;
CREATE TRIGGER set_tenant_id_product_equivalences BEFORE INSERT ON product_equivalences EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_employee_exit_processes ON employee_exit_processes;
CREATE TRIGGER set_tenant_id_employee_exit_processes BEFORE INSERT ON employee_exit_processes EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_users ON users;
CREATE TRIGGER set_tenant_id_users BEFORE INSERT ON users EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS users_updated_at ON users;
CREATE TRIGGER users_updated_at BEFORE UPDATE ON users EXECUTE FUNCTION update_updated_at();
DROP TRIGGER IF EXISTS set_tenant_id_vat_returns ON vat_returns;
CREATE TRIGGER set_tenant_id_vat_returns BEFORE INSERT ON vat_returns EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_warehouses ON warehouses;
CREATE TRIGGER set_tenant_id_warehouses BEFORE INSERT ON warehouses EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_honorarium_records ON honorarium_records;
CREATE TRIGGER set_tenant_id_honorarium_records BEFORE INSERT ON honorarium_records EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_employee_documents ON employee_documents;
CREATE TRIGGER set_tenant_id_employee_documents BEFORE INSERT ON employee_documents EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_delivery_schedules ON delivery_schedules;
CREATE TRIGGER set_tenant_id_delivery_schedules BEFORE INSERT ON delivery_schedules EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_crm_campaigns ON crm_campaigns;
CREATE TRIGGER set_tenant_id_crm_campaigns BEFORE INSERT ON crm_campaigns EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_recurring_invoice_templates ON recurring_invoice_templates;
CREATE TRIGGER set_tenant_id_recurring_invoice_templates BEFORE INSERT ON recurring_invoice_templates EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_treasury_transfers ON treasury_transfers;
CREATE TRIGGER set_tenant_id_treasury_transfers BEFORE INSERT ON treasury_transfers EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_document_transformations ON document_transformations;
CREATE TRIGGER set_tenant_id_document_transformations BEFORE INSERT ON document_transformations EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_employee_objectives ON employee_objectives;
CREATE TRIGGER set_tenant_id_employee_objectives BEFORE INSERT ON employee_objectives EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_credit_lines ON credit_lines;
CREATE TRIGGER set_tenant_id_credit_lines BEFORE INSERT ON credit_lines EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_rh_knowledge_base ON rh_knowledge_base;
CREATE TRIGGER set_tenant_id_rh_knowledge_base BEFORE INSERT ON rh_knowledge_base EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_pos_tickets ON pos_tickets;
CREATE TRIGGER set_tenant_id_pos_tickets BEFORE INSERT ON pos_tickets EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_investments ON investments;
CREATE TRIGGER set_tenant_id_investments BEFORE INSERT ON investments EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_workflows ON workflows;
CREATE TRIGGER set_tenant_id_workflows BEFORE INSERT ON workflows EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_exchange_gain_loss_entries ON exchange_gain_loss_entries;
CREATE TRIGGER set_tenant_id_exchange_gain_loss_entries BEFORE INSERT ON exchange_gain_loss_entries EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_payroll_variable_elements ON payroll_variable_elements;
CREATE TRIGGER set_tenant_id_payroll_variable_elements BEFORE INSERT ON payroll_variable_elements EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_partner_bank_accounts ON partner_bank_accounts;
CREATE TRIGGER set_tenant_id_partner_bank_accounts BEFORE INSERT ON partner_bank_accounts EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_partner_categories ON partner_categories;
CREATE TRIGGER set_tenant_id_partner_categories BEFORE INSERT ON partner_categories EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_asset_batch_disposal_lines ON asset_batch_disposal_lines;
CREATE TRIGGER set_tenant_id_asset_batch_disposal_lines BEFORE INSERT ON asset_batch_disposal_lines EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_analytic_sections ON analytic_sections;
CREATE TRIGGER set_tenant_id_analytic_sections BEFORE INSERT ON analytic_sections EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_budgets ON budgets;
CREATE TRIGGER set_tenant_id_budgets BEFORE INSERT ON budgets EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_purchase_order_lines ON purchase_order_lines;
CREATE TRIGGER set_tenant_id_purchase_order_lines BEFORE INSERT ON purchase_order_lines EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_crm_activities ON crm_activities;
CREATE TRIGGER set_tenant_id_crm_activities BEFORE INSERT ON crm_activities EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_chart_accounts ON chart_accounts;
CREATE TRIGGER set_tenant_id_chart_accounts BEFORE INSERT ON chart_accounts EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_leave_requests ON leave_requests;
CREATE TRIGGER set_tenant_id_leave_requests BEFORE INSERT ON leave_requests EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_of_document_access ON of_document_access;
CREATE TRIGGER set_tenant_id_of_document_access BEFORE INSERT ON of_document_access EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_pos_terminals ON pos_terminals;
CREATE TRIGGER set_tenant_id_pos_terminals BEFORE INSERT ON pos_terminals EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_pos_ticket_lines ON pos_ticket_lines;
CREATE TRIGGER set_tenant_id_pos_ticket_lines BEFORE INSERT ON pos_ticket_lines EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_consolidated_treasury ON consolidated_treasury;
CREATE TRIGGER set_tenant_id_consolidated_treasury BEFORE INSERT ON consolidated_treasury EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_stock_alerts ON stock_alerts;
CREATE TRIGGER set_tenant_id_stock_alerts BEFORE INSERT ON stock_alerts EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_payroll_component_rates ON payroll_component_rates;
CREATE TRIGGER set_tenant_id_payroll_component_rates BEFORE INSERT ON payroll_component_rates EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_supplier_contacts ON supplier_contacts;
CREATE TRIGGER set_tenant_id_supplier_contacts BEFORE INSERT ON supplier_contacts EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_product_grids ON product_grids;
CREATE TRIGGER set_tenant_id_product_grids BEFORE INSERT ON product_grids EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_product_links ON product_links;
CREATE TRIGGER set_tenant_id_product_links BEFORE INSERT ON product_links EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_supplier_price_list_lines ON supplier_price_list_lines;
CREATE TRIGGER set_tenant_id_supplier_price_list_lines BEFORE INSERT ON supplier_price_list_lines EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_tax_cash_basis_entries ON tax_cash_basis_entries;
CREATE TRIGGER set_tenant_id_tax_cash_basis_entries BEFORE INSERT ON tax_cash_basis_entries EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_tax_repartition_lines ON tax_repartition_lines;
CREATE TRIGGER set_tenant_id_tax_repartition_lines BEFORE INSERT ON tax_repartition_lines EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_dsn_declarations ON dsn_declarations;
CREATE TRIGGER set_tenant_id_dsn_declarations BEFORE INSERT ON dsn_declarations EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_dpae_records ON dpae_records;
CREATE TRIGGER set_tenant_id_dpae_records BEFORE INSERT ON dpae_records EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_cpf_accounts ON cpf_accounts;
CREATE TRIGGER set_tenant_id_cpf_accounts BEFORE INSERT ON cpf_accounts EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_partner_category_mappings ON partner_category_mappings;
CREATE TRIGGER set_tenant_id_partner_category_mappings BEFORE INSERT ON partner_category_mappings EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_legal_watch ON legal_watch;
CREATE TRIGGER set_tenant_id_legal_watch BEFORE INSERT ON legal_watch EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_analytic_distribution_lines ON analytic_distribution_lines;
CREATE TRIGGER set_tenant_id_analytic_distribution_lines BEFORE INSERT ON analytic_distribution_lines EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS check_journal_entry_balance ON journal_lines;
CREATE TRIGGER check_journal_entry_balance AFTER INSERT ON journal_lines EXECUTE FUNCTION check_journal_entry_balance();
DROP TRIGGER IF EXISTS check_journal_entry_balance ON journal_lines;
CREATE TRIGGER check_journal_entry_balance AFTER DELETE ON journal_lines EXECUTE FUNCTION check_journal_entry_balance();
DROP TRIGGER IF EXISTS check_journal_entry_balance ON journal_lines;
CREATE TRIGGER check_journal_entry_balance AFTER UPDATE ON journal_lines EXECUTE FUNCTION check_journal_entry_balance();
DROP TRIGGER IF EXISTS set_tenant_id_journal_lines ON journal_lines;
CREATE TRIGGER set_tenant_id_journal_lines BEFORE INSERT ON journal_lines EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_asset_depreciation_plans ON asset_depreciation_plans;
CREATE TRIGGER set_tenant_id_asset_depreciation_plans BEFORE INSERT ON asset_depreciation_plans EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_exchange_rates ON exchange_rates;
CREATE TRIGGER set_tenant_id_exchange_rates BEFORE INSERT ON exchange_rates EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_asset_documents ON asset_documents;
CREATE TRIGGER set_tenant_id_asset_documents BEFORE INSERT ON asset_documents EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS trg_ptg_updated ON payroll_tax_grids;
CREATE TRIGGER trg_ptg_updated BEFORE UPDATE ON payroll_tax_grids EXECUTE FUNCTION update_tax_grid_timestamp();
DROP TRIGGER IF EXISTS set_tenant_id_analytic_plans ON analytic_plans;
CREATE TRIGGER set_tenant_id_analytic_plans BEFORE INSERT ON analytic_plans EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_fiscal_backups ON fiscal_backups;
CREATE TRIGGER set_tenant_id_fiscal_backups BEFORE INSERT ON fiscal_backups EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_asset_splits ON asset_splits;
CREATE TRIGGER set_tenant_id_asset_splits BEFORE INSERT ON asset_splits EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_currency_revaluations ON currency_revaluations;
CREATE TRIGGER set_tenant_id_currency_revaluations BEFORE INSERT ON currency_revaluations EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_document_templates ON document_templates;
CREATE TRIGGER set_tenant_id_document_templates BEFORE INSERT ON document_templates EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS trg_ctg_updated ON corporate_tax_grids;
CREATE TRIGGER trg_ctg_updated BEFORE UPDATE ON corporate_tax_grids EXECUTE FUNCTION update_tax_grid_timestamp();
DROP TRIGGER IF EXISTS set_tenant_id_purchase_credit_notes ON purchase_credit_notes;
CREATE TRIGGER set_tenant_id_purchase_credit_notes BEFORE INSERT ON purchase_credit_notes EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_tax_groups ON tax_groups;
CREATE TRIGGER set_tenant_id_tax_groups BEFORE INSERT ON tax_groups EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_check_books ON check_books;
CREATE TRIGGER set_tenant_id_check_books BEFORE INSERT ON check_books EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_checks ON checks;
CREATE TRIGGER set_tenant_id_checks BEFORE INSERT ON checks EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_crm_territories ON crm_territories;
CREATE TRIGGER set_tenant_id_crm_territories BEFORE INSERT ON crm_territories EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_crm_forecasts ON crm_forecasts;
CREATE TRIGGER set_tenant_id_crm_forecasts BEFORE INSERT ON crm_forecasts EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_service_tickets ON service_tickets;
CREATE TRIGGER set_tenant_id_service_tickets BEFORE INSERT ON service_tickets EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_service_ticket_messages ON service_ticket_messages;
CREATE TRIGGER set_tenant_id_service_ticket_messages BEFORE INSERT ON service_ticket_messages EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_service_contracts ON service_contracts;
CREATE TRIGGER set_tenant_id_service_contracts BEFORE INSERT ON service_contracts EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_knowledge_base_articles ON knowledge_base_articles;
CREATE TRIGGER set_tenant_id_knowledge_base_articles BEFORE INSERT ON knowledge_base_articles EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_electronic_signatures ON electronic_signatures;
CREATE TRIGGER set_tenant_id_electronic_signatures BEFORE INSERT ON electronic_signatures EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_pos_sessions ON pos_sessions;
CREATE TRIGGER set_tenant_id_pos_sessions BEFORE INSERT ON pos_sessions EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_online_payments ON online_payments;
CREATE TRIGGER set_tenant_id_online_payments BEFORE INSERT ON online_payments EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_document_shares ON document_shares;
CREATE TRIGGER set_tenant_id_document_shares BEFORE INSERT ON document_shares EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_leave_rules ON leave_rules;
CREATE TRIGGER set_tenant_id_leave_rules BEFORE INSERT ON leave_rules EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS projects_updated_at ON projects;
CREATE TRIGGER projects_updated_at BEFORE UPDATE ON projects EXECUTE FUNCTION update_updated_at();
DROP TRIGGER IF EXISTS set_tenant_id_projects ON projects;
CREATE TRIGGER set_tenant_id_projects BEFORE INSERT ON projects EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_leave_balances ON leave_balances;
CREATE TRIGGER set_tenant_id_leave_balances BEFORE INSERT ON leave_balances EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_sepa_payment_orders ON sepa_payment_orders;
CREATE TRIGGER set_tenant_id_sepa_payment_orders BEFORE INSERT ON sepa_payment_orders EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_pay_slip_clarified ON pay_slip_clarified;
CREATE TRIGGER set_tenant_id_pay_slip_clarified BEFORE INSERT ON pay_slip_clarified EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_work_stoppages ON work_stoppages;
CREATE TRIGGER set_tenant_id_work_stoppages BEFORE INSERT ON work_stoppages EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_ijss_history ON ijss_history;
CREATE TRIGGER set_tenant_id_ijss_history BEFORE INSERT ON ijss_history EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_work_hardship_records ON work_hardship_records;
CREATE TRIGGER set_tenant_id_work_hardship_records BEFORE INSERT ON work_hardship_records EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_cpf_transactions ON cpf_transactions;
CREATE TRIGGER set_tenant_id_cpf_transactions BEFORE INSERT ON cpf_transactions EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_medical_exams ON medical_exams;
CREATE TRIGGER set_tenant_id_medical_exams BEFORE INSERT ON medical_exams EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_expense_categories ON expense_categories;
CREATE TRIGGER set_tenant_id_expense_categories BEFORE INSERT ON expense_categories EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_interview_campaigns ON interview_campaigns;
CREATE TRIGGER set_tenant_id_interview_campaigns BEFORE INSERT ON interview_campaigns EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_cice_config ON cice_config;
CREATE TRIGGER set_tenant_id_cice_config BEFORE INSERT ON cice_config EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_document_distribution_logs ON document_distribution_logs;
CREATE TRIGGER set_tenant_id_document_distribution_logs BEFORE INSERT ON document_distribution_logs EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_rh_requests ON rh_requests;
CREATE TRIGGER set_tenant_id_rh_requests BEFORE INSERT ON rh_requests EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_approval_workflows ON approval_workflows;
CREATE TRIGGER set_tenant_id_approval_workflows BEFORE INSERT ON approval_workflows EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_asset_families ON asset_families;
CREATE TRIGGER set_tenant_id_asset_families BEFORE INSERT ON asset_families EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_asset_free_fields ON asset_free_fields;
CREATE TRIGGER set_tenant_id_asset_free_fields BEFORE INSERT ON asset_free_fields EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_bank_connections ON bank_connections;
CREATE TRIGGER set_tenant_id_bank_connections BEFORE INSERT ON bank_connections EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_bdes_indicators ON bdes_indicators;
CREATE TRIGGER set_tenant_id_bdes_indicators BEFORE INSERT ON bdes_indicators EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_customer_contacts ON customer_contacts;
CREATE TRIGGER set_tenant_id_customer_contacts BEFORE INSERT ON customer_contacts EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_distribution_grill_lines ON distribution_grill_lines;
CREATE TRIGGER set_tenant_id_distribution_grill_lines BEFORE INSERT ON distribution_grill_lines EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_distribution_grills ON distribution_grills;
CREATE TRIGGER set_tenant_id_distribution_grills BEFORE INSERT ON distribution_grills EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_document_charges ON document_charges;
CREATE TRIGGER set_tenant_id_document_charges BEFORE INSERT ON document_charges EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_future_accounting_movements ON future_accounting_movements;
CREATE TRIGGER set_tenant_id_future_accounting_movements BEFORE INSERT ON future_accounting_movements EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_interviews ON interviews;
CREATE TRIGGER set_tenant_id_interviews BEFORE INSERT ON interviews EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_leave_provisions ON leave_provisions;
CREATE TRIGGER set_tenant_id_leave_provisions BEFORE INSERT ON leave_provisions EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_meal_voucher_config ON meal_voucher_config;
CREATE TRIGGER set_tenant_id_meal_voucher_config BEFORE INSERT ON meal_voucher_config EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_partner_contacts ON partner_contacts;
CREATE TRIGGER set_tenant_id_partner_contacts BEFORE INSERT ON partner_contacts EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_pas_rates ON pas_rates;
CREATE TRIGGER set_tenant_id_pas_rates BEFORE INSERT ON pas_rates EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_pay_recalls ON pay_recalls;
CREATE TRIGGER set_tenant_id_pay_recalls BEFORE INSERT ON pay_recalls EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_payroll_archives ON payroll_archives;
CREATE TRIGGER set_tenant_id_payroll_archives BEFORE INSERT ON payroll_archives EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_payroll_components ON payroll_components;
CREATE TRIGGER set_tenant_id_payroll_components BEFORE INSERT ON payroll_components EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_payroll_templates ON payroll_templates;
CREATE TRIGGER set_tenant_id_payroll_templates BEFORE INSERT ON payroll_templates EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_product_attributes ON product_attributes;
CREATE TRIGGER set_tenant_id_product_attributes BEFORE INSERT ON product_attributes EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_product_packagings ON product_packagings;
CREATE TRIGGER set_tenant_id_product_packagings BEFORE INSERT ON product_packagings EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_promotions ON promotions;
CREATE TRIGGER set_tenant_id_promotions BEFORE INSERT ON promotions EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_prospects ON prospects;
CREATE TRIGGER set_tenant_id_prospects BEFORE INSERT ON prospects EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_public_holidays ON public_holidays;
CREATE TRIGGER set_tenant_id_public_holidays BEFORE INSERT ON public_holidays EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_purchase_request_lines ON purchase_request_lines;
CREATE TRIGGER set_tenant_id_purchase_request_lines BEFORE INSERT ON purchase_request_lines EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_purchase_requests ON purchase_requests;
CREATE TRIGGER set_tenant_id_purchase_requests BEFORE INSERT ON purchase_requests EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_regularization_entries ON regularization_entries;
CREATE TRIGGER set_tenant_id_regularization_entries BEFORE INSERT ON regularization_entries EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_salary_advances ON salary_advances;
CREATE TRIGGER set_tenant_id_salary_advances BEFORE INSERT ON salary_advances EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_sales_representatives ON sales_representatives;
CREATE TRIGGER set_tenant_id_sales_representatives BEFORE INSERT ON sales_representatives EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_saved_filters ON saved_filters;
CREATE TRIGGER set_tenant_id_saved_filters BEFORE INSERT ON saved_filters EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_social_declarations ON social_declarations;
CREATE TRIGGER set_tenant_id_social_declarations BEFORE INSERT ON social_declarations EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_staff_requirements ON staff_requirements;
CREATE TRIGGER set_tenant_id_staff_requirements BEFORE INSERT ON staff_requirements EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_warehouse_users ON warehouse_users;
CREATE TRIGGER set_tenant_id_warehouse_users BEFORE INSERT ON warehouse_users EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_work_hardship ON work_hardship;
CREATE TRIGGER set_tenant_id_work_hardship BEFORE INSERT ON work_hardship EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_standard_labels ON standard_labels;
CREATE TRIGGER set_tenant_id_standard_labels BEFORE INSERT ON standard_labels EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_journals ON journals;
CREATE TRIGGER set_tenant_id_journals BEFORE INSERT ON journals EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS project_tasks_activity_created ON project_tasks;
CREATE TRIGGER project_tasks_activity_created AFTER INSERT ON project_tasks EXECUTE FUNCTION log_task_created();
DROP TRIGGER IF EXISTS project_tasks_activity_log ON project_tasks;
CREATE TRIGGER project_tasks_activity_log AFTER UPDATE ON project_tasks EXECUTE FUNCTION log_task_activity();
DROP TRIGGER IF EXISTS project_tasks_updated_at ON project_tasks;
CREATE TRIGGER project_tasks_updated_at BEFORE UPDATE ON project_tasks EXECUTE FUNCTION update_updated_at_column();
DROP TRIGGER IF EXISTS project_stages_updated_at ON project_stages;
CREATE TRIGGER project_stages_updated_at BEFORE UPDATE ON project_stages EXECUTE FUNCTION update_updated_at_column();
DROP TRIGGER IF EXISTS project_milestones_updated_at ON project_milestones;
CREATE TRIGGER project_milestones_updated_at BEFORE UPDATE ON project_milestones EXECUTE FUNCTION update_updated_at_column();
DROP TRIGGER IF EXISTS project_time_entries_updated_at ON project_time_entries;
CREATE TRIGGER project_time_entries_updated_at BEFORE UPDATE ON project_time_entries EXECUTE FUNCTION update_updated_at_column();
DROP TRIGGER IF EXISTS set_tenant_id_asset_revaluations ON asset_revaluations;
CREATE TRIGGER set_tenant_id_asset_revaluations BEFORE INSERT ON asset_revaluations EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_asset_batch_disposals ON asset_batch_disposals;
CREATE TRIGGER set_tenant_id_asset_batch_disposals BEFORE INSERT ON asset_batch_disposals EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_supplier_price_lists ON supplier_price_lists;
CREATE TRIGGER set_tenant_id_supplier_price_lists BEFORE INSERT ON supplier_price_lists EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_treasury_recurring ON treasury_recurring;
CREATE TRIGGER set_tenant_id_treasury_recurring BEFORE INSERT ON treasury_recurring EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_tvs_declarations ON tvs_declarations;
CREATE TRIGGER set_tenant_id_tvs_declarations BEFORE INSERT ON tvs_declarations EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_value_date_tracking ON value_date_tracking;
CREATE TRIGGER set_tenant_id_value_date_tracking BEFORE INSERT ON value_date_tracking EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_warehouse_locations ON warehouse_locations;
CREATE TRIGGER set_tenant_id_warehouse_locations BEFORE INSERT ON warehouse_locations EXECUTE FUNCTION set_tenant_id();
DROP TRIGGER IF EXISTS set_tenant_id_employees ON employees;
CREATE TRIGGER set_tenant_id_employees BEFORE INSERT ON employees EXECUTE FUNCTION set_tenant_id();
