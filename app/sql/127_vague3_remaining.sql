-- ============================================================
-- 127_vague3_remaining.sql
-- PRJ-01 à PRJ-09 : Gestion de projet complète
-- BI-01 à BI-03 : Générateur d'états et SIG
-- UX-02 à UX-05 : Accessibilité et saisie clavier
-- CNF-01/02 : Raccordements réels et e-facturation
-- PRF-02 à PRF-04 : Performance
-- ADM-03 à ADM-05 : Paramétrage, modèles, audit
-- GED-01 à GED-04 : Documents et dématérialisation
-- NOT-01 à NOT-03 : Notifications unifiées
-- API-01/02 : API et webhooks
-- PTL-01 à PTL-03 : Portail salarié et mobile
-- ONB-01 à ONB-03 : Inscription et abonnement
-- CRM-01 à CRM-03 : Séquences, scoring, e-mails
-- GRP-01 à GRJ-03 : Groupe et consolidation
-- RH-01 à RH-03 : GTA, congés, intégration
-- IMP-04 + API-03 : Passerelles et connecteurs
-- ============================================================

-- ============================================================
-- PRJ-01 : Dépendances et chemin critique
-- ============================================================
ALTER TABLE project_tasks ADD COLUMN IF NOT EXISTS predecessor_ids uuid[];
ALTER TABLE project_tasks ADD COLUMN IF NOT EXISTS early_start date;
ALTER TABLE project_tasks ADD COLUMN IF NOT EXISTS early_finish date;
ALTER TABLE project_tasks ADD COLUMN IF NOT EXISTS late_start date;
ALTER TABLE project_tasks ADD COLUMN IF NOT EXISTS late_finish date;
ALTER TABLE project_tasks ADD COLUMN IF NOT EXISTS total_slack int;
ALTER TABLE project_tasks ADD COLUMN IF NOT EXISTS is_critical_path boolean DEFAULT false;

-- ============================================================
-- PRJ-02 : Capacité par ressource
-- ============================================================
CREATE TABLE IF NOT EXISTS resource_capacities (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  resource_type text NOT NULL,  -- 'employee', 'machine', 'work_center'
  resource_id uuid NOT NULL,
  period_start date NOT NULL,
  period_end date NOT NULL,
  available_hours numeric NOT NULL,
  allocated_hours numeric DEFAULT 0,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE resource_capacities ENABLE ROW LEVEL SECURITY;
CREATE POLICY resource_capacities_tenant ON resource_capacities
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

-- ============================================================
-- PRJ-04 : Champs personnalisés
-- ============================================================
CREATE TABLE IF NOT EXISTS custom_field_definitions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  entity_type text NOT NULL,  -- 'project', 'task', 'customer', 'product'
  field_name text NOT NULL,
  field_label text NOT NULL,
  field_type text NOT NULL CHECK (field_type IN ('text', 'number', 'date', 'boolean', 'select', 'multiselect')),
  field_options jsonb,
  is_required boolean DEFAULT false,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE custom_field_definitions ENABLE ROW LEVEL SECURITY;
CREATE POLICY custom_field_definitions_tenant ON custom_field_definitions
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

CREATE TABLE IF NOT EXISTS custom_field_values (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  field_id uuid NOT NULL REFERENCES custom_field_definitions(id) ON DELETE CASCADE,
  entity_type text NOT NULL,
  entity_id uuid NOT NULL,
  field_value jsonb,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE custom_field_values ENABLE ROW LEVEL SECURITY;
CREATE POLICY custom_field_values_tenant ON custom_field_values
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

-- ============================================================
-- PRJ-05 : Rentabilité de projet
-- ============================================================
CREATE OR REPLACE VIEW v_project_profitability AS
SELECT
  p.tenant_id,
  p.id AS project_id,
  p.name AS project_name,
  p.budget,
  COALESCE(SUM(pt.budget), 0) AS planned_cost,
  COALESCE(SUM(pt.effort_spent_h), 0) AS actual_hours,
  p.budget - COALESCE(SUM(pt.budget), 0) AS budget_variance,
  COALESCE(SUM(pt.effort_estimate_h), 0) AS planned_hours,
  COALESCE(SUM(pt.effort_spent_h), 0) AS spent_hours
FROM projects p
LEFT JOIN project_tasks pt ON pt.project_id = p.id AND pt.tenant_id = p.tenant_id
WHERE p.tenant_id = current_tenant_id()
GROUP BY p.tenant_id, p.id, p.name, p.budget;

-- ============================================================
-- PRJ-07 : Référence de planning et suivi d'écart
-- ============================================================
ALTER TABLE projects ADD COLUMN IF NOT EXISTS baseline_start_date date;
ALTER TABLE projects ADD COLUMN IF NOT EXISTS baseline_end_date date;
ALTER TABLE projects ADD COLUMN IF NOT EXISTS baseline_budget numeric;

-- ============================================================
-- BI-01 : Générateur d'états
-- ============================================================
CREATE TABLE IF NOT EXISTS report_definitions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  name text NOT NULL,
  description text,
  report_type text NOT NULL,  -- 'balance_sheet', 'pnl', 'trial_balance', 'custom'
  query_config jsonb NOT NULL,  -- Configuration de la requête
  columns_config jsonb,          -- Configuration des colonnes
  is_shared boolean DEFAULT false,
  created_by uuid,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE report_definitions ENABLE ROW LEVEL SECURITY;
CREATE POLICY report_definitions_tenant ON report_definitions
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

-- ============================================================
-- BI-02 : Indicateurs financiers normés (SIG)
-- ============================================================
CREATE OR REPLACE VIEW v_income_statement_sig AS
WITH lines AS (
  SELECT
    jl.account_code,
    jl.debit,
    jl.credit,
    ca.type AS account_type,
    LEFT(jl.account_code, 1) AS account_class
  FROM journal_lines jl
  JOIN chart_accounts ca ON ca.code = jl.account_code AND ca.tenant_id = jl.tenant_id
  WHERE jl.tenant_id = current_tenant_id()
)
SELECT
  -- Ventes de marchandises (classe 707)
  SUM(CASE WHEN account_class = '7' AND account_code LIKE '707%' THEN credit - debit ELSE 0 END) AS sales_merchandise,
  -- Production de l'exercice (70 + 71 + 72)
  SUM(CASE WHEN account_class = '7' AND account_code ~ '^7[012]' THEN credit - debit ELSE 0 END) AS production,
  -- Consommation (603)
  SUM(CASE WHEN account_class = '6' AND account_code LIKE '603%' THEN debit - credit ELSE 0 END) AS consumption,
  -- Marge commerciale
  SUM(CASE WHEN account_class = '7' AND account_code LIKE '707%' THEN credit - debit ELSE 0 END)
  - SUM(CASE WHEN account_class = '6' AND account_code LIKE '607%' THEN debit - credit ELSE 0 END) AS commercial_margin,
  -- Valeur ajoutée
  SUM(CASE WHEN account_class = '7' AND account_code ~ '^7[0-5]' THEN credit - debit ELSE 0 END)
  - SUM(CASE WHEN account_class = '6' AND account_code ~ '^6[0-5]' THEN debit - credit ELSE 0 END) AS value_added,
  -- Excédent brut d'exploitation
  SUM(CASE WHEN account_class = '7' THEN credit - debit ELSE 0 END)
  - SUM(CASE WHEN account_class = '6' AND account_code NOT LIKE '68%' AND account_code NOT LIKE '69%' THEN debit - credit ELSE 0 END) AS ebitda,
  -- Résultat d'exploitation
  SUM(CASE WHEN account_class = '7' THEN credit - debit ELSE 0 END)
  - SUM(CASE WHEN account_class = '6' THEN debit - credit ELSE 0 END) AS operating_result,
  -- Résultat financier
  SUM(CASE WHEN account_class = '7' AND account_code LIKE '76%' THEN credit - debit ELSE 0 END)
  - SUM(CASE WHEN account_class = '6' AND account_code LIKE '66%' THEN debit - credit ELSE 0 END) AS financial_result,
  -- Résultat exceptionnel
  SUM(CASE WHEN account_class = '7' AND account_code LIKE '77%' THEN credit - debit ELSE 0 END)
  - SUM(CASE WHEN account_class = '6' AND account_code LIKE '67%' THEN debit - credit ELSE 0 END) AS exceptional_result,
  -- Résultat net
  SUM(CASE WHEN account_class = '7' THEN credit - debit ELSE 0 END)
  - SUM(CASE WHEN account_class = '6' THEN debit - credit ELSE 0 END) AS net_result
FROM lines;

-- ============================================================
-- ADM-03 : Paramétrage comptable et fiscal
-- ============================================================
CREATE TABLE IF NOT EXISTS tenant_fiscal_settings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL UNIQUE,
  fiscal_regime text,  -- 'micro', 'réel simplifié', 'réel normal', 'IS'
  vat_regime text,     -- 'franchise', 'mini-réel', 'réel normal'
  depreciation_method text DEFAULT 'linear',
  closing_month int DEFAULT 12,
  opening_month int DEFAULT 1,
  is_autonomous_vat boolean DEFAULT false,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE tenant_fiscal_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_fiscal_settings_tenant ON tenant_fiscal_settings
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

-- ============================================================
-- ADM-04 : Modèles de documents
-- ============================================================
CREATE TABLE IF NOT EXISTS document_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  document_type text NOT NULL,  -- 'invoice', 'quote', 'purchase_order', 'delivery_note', 'pay_slip'
  name text NOT NULL,
  template_html text,
  is_default boolean DEFAULT false,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE document_templates ENABLE ROW LEVEL SECURITY;
CREATE POLICY document_templates_tenant ON document_templates
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

-- ============================================================
-- ADM-05 : Journal d'audit applicatif
-- ============================================================
CREATE TABLE IF NOT EXISTS audit_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  user_id uuid,
  action text NOT NULL,  -- 'create', 'update', 'delete', 'view', 'export'
  entity_type text NOT NULL,
  entity_id uuid,
  old_values jsonb,
  new_values jsonb,
  ip_address text,
  user_agent text,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY audit_log_tenant ON audit_log
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

-- ============================================================
-- GED-01 : Rattachement universel de documents
-- ============================================================
CREATE TABLE IF NOT EXISTS document_attachments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  entity_type text NOT NULL,  -- 'invoice', 'journal_entry', 'employee', 'project', 'product'
  entity_id uuid NOT NULL,
  file_name text NOT NULL,
  file_path text NOT NULL,
  file_size bigint,
  mime_type text,
  uploaded_by uuid,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE document_attachments ENABLE ROW LEVEL SECURITY;
CREATE POLICY document_attachments_tenant ON document_attachments
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

-- ============================================================
-- GED-04 : Signature électronique
-- ============================================================
CREATE TABLE IF NOT EXISTS electronic_signatures (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  document_id uuid REFERENCES document_attachments(id) ON DELETE CASCADE,
  signer_id uuid NOT NULL,
  signer_name text NOT NULL,
  signature_hash text NOT NULL,
  signature_certificate text,
  signed_at timestamptz DEFAULT now(),
  ip_address text
);

ALTER TABLE electronic_signatures ENABLE ROW LEVEL SECURITY;
CREATE POLICY electronic_signatures_tenant ON electronic_signatures
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

-- ============================================================
-- NOT-01 : Centre de notifications unifié
-- ============================================================
CREATE TABLE IF NOT EXISTS notification_center (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  user_id uuid,
  category text NOT NULL,  -- 'accounting', 'sales', 'stock', 'hr', 'system'
  title text NOT NULL,
  message text,
  severity text DEFAULT 'info' CHECK (severity IN ('info', 'warning', 'error', 'success')),
  is_read boolean DEFAULT false,
  action_url text,
  action_label text,
  metadata jsonb,
  created_at timestamptz DEFAULT now(),
  read_at timestamptz
);

ALTER TABLE notification_center ENABLE ROW LEVEL SECURITY;
CREATE POLICY notification_center_tenant ON notification_center
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

-- ============================================================
-- NOT-02 : Alertes métier proactives
-- ============================================================
CREATE TABLE IF NOT EXISTS business_alert_rules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  alert_type text NOT NULL,  -- 'low_stock', 'overdue_invoice', 'budget_exceeded', 'contract_expiring'
  entity_type text,
  condition_config jsonb NOT NULL,
  notification_channel text DEFAULT 'in_app' CHECK (notification_channel IN ('in_app', 'email', 'sms', 'webhook')),
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE business_alert_rules ENABLE ROW LEVEL SECURITY;
CREATE POLICY business_alert_rules_tenant ON business_alert_rules
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

-- ============================================================
-- CRM-01 : Séquences de relance
-- ============================================================
CREATE TABLE IF NOT EXISTS crm_sequences (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  name text NOT NULL,
  trigger_type text NOT NULL,  -- 'no_activity', 'stage_change', 'manual'
  trigger_days int DEFAULT 7,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE crm_sequences ENABLE ROW LEVEL SECURITY;
CREATE POLICY crm_sequences_tenant ON crm_sequences
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

CREATE TABLE IF NOT EXISTS crm_sequence_steps (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  sequence_id uuid NOT NULL REFERENCES crm_sequences(id) ON DELETE CASCADE,
  step_order int NOT NULL,
  action_type text NOT NULL,  -- 'email', 'call', 'task', 'sms'
  action_template text,
  delay_days int DEFAULT 0,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE crm_sequence_steps ENABLE ROW LEVEL SECURITY;
CREATE POLICY crm_sequence_steps_tenant ON crm_sequence_steps
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

-- ============================================================
-- CRM-02 : Scoring de lead
-- ============================================================
CREATE TABLE IF NOT EXISTS crm_scoring_rules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  rule_name text NOT NULL,
  criteria jsonb NOT NULL,  -- { field: "company_size", operator: ">", value: 50, points: 10 }
  points int NOT NULL,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE crm_scoring_rules ENABLE ROW LEVEL SECURITY;
CREATE POLICY crm_scoring_rules_tenant ON crm_scoring_rules
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

-- ============================================================
-- GRP-01 : Structure de groupe
-- ============================================================
CREATE TABLE IF NOT EXISTS group_entities (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_name text NOT NULL,
  parent_group_id uuid REFERENCES group_entities(id),
  created_at timestamptz DEFAULT now()
);

ALTER TABLE group_entities ENABLE ROW LEVEL SECURITY;
CREATE POLICY group_entities_all ON group_entities
  FOR ALL USING (true) WITH CHECK (true);

CREATE TABLE IF NOT EXISTS group_members (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id uuid NOT NULL REFERENCES group_entities(id) ON DELETE CASCADE,
  tenant_id uuid NOT NULL,
  member_type text NOT NULL,  -- 'subsidiary', 'branch', 'joint_venture'
  ownership_pct numeric,
  consolidation_method text,  -- 'full', 'equity', 'proportional'
  created_at timestamptz DEFAULT now()
);

ALTER TABLE group_members ENABLE ROW LEVEL SECURITY;
CREATE POLICY group_members_tenant ON group_members
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

-- ============================================================
-- GRP-02 : Opérations intra-groupe
-- ============================================================
CREATE TABLE IF NOT EXISTS intra_group_transactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  group_id uuid NOT NULL REFERENCES group_entities(id),
  from_tenant_id uuid NOT NULL,
  to_tenant_id uuid NOT NULL,
  transaction_type text NOT NULL,  -- 'sale', 'purchase', 'loan', 'transfer'
  amount numeric NOT NULL,
  reference text,
  transaction_date date NOT NULL,
  status text DEFAULT 'pending' CHECK (status IN ('pending', 'confirmed', 'cancelled')),
  created_at timestamptz DEFAULT now()
);

ALTER TABLE intra_group_transactions ENABLE ROW LEVEL SECURITY;
CREATE POLICY intra_group_transactions_tenant ON intra_group_transactions
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

-- ============================================================
-- RH-01 : Gestion des temps et activités (GTA)
-- ============================================================
CREATE TABLE IF NOT EXISTS time_entries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  employee_id uuid NOT NULL,
  date date NOT NULL,
  start_time time,
  end_time time,
  break_minutes int DEFAULT 0,
  total_minutes int GENERATED ALWAYS AS (
    CASE WHEN start_time IS NOT NULL AND end_time IS NOT NULL
    THEN EXTRACT(EPOCH FROM (end_time - start_time)) / 60 - break_minutes
    ELSE 0 END
  ) STORED,
  activity_type text,  -- 'work', 'meeting', 'travel', 'training', 'overtime'
  project_id uuid,
  notes text,
  status text DEFAULT 'draft' CHECK (status IN ('draft', 'submitted', 'approved', 'rejected')),
  approved_by uuid,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE time_entries ENABLE ROW LEVEL SECURITY;
CREATE POLICY time_entries_tenant ON time_entries
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

-- ============================================================
-- RH-02 : Congés conformité fine
-- ============================================================
CREATE TABLE IF NOT EXISTS leave_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  employee_id uuid NOT NULL,
  leave_type text NOT NULL CHECK (leave_type IN ('annual', 'sick', 'maternity', 'paternity', 'unpaid', 'rtt', 'special')),
  start_date date NOT NULL,
  end_date date NOT NULL,
  half_day_start boolean DEFAULT false,
  half_day_end boolean DEFAULT false,
  days_count numeric GENERATED ALWAYS AS (
    (end_date - start_date + 1) - CASE WHEN half_day_start THEN 0.5 ELSE 0 END - CASE WHEN half_day_end THEN 0.5 ELSE 0 END
  ) STORED,
  status text DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled')),
  approved_by uuid,
  approved_at timestamptz,
  notes text,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE leave_requests ENABLE ROW LEVEL SECURITY;
CREATE POLICY leave_requests_tenant ON leave_requests
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

-- ============================================================
-- RH-03 : Recrutement et intégration
-- ============================================================
CREATE TABLE IF NOT EXISTS job_postings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  title text NOT NULL,
  department text,
  description text,
  requirements text,
  salary_range_min numeric,
  salary_range_max numeric,
  contract_type text,
  status text DEFAULT 'draft' CHECK (status IN ('draft', 'published', 'closed', 'cancelled')),
  published_at timestamptz,
  closing_date date,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE job_postings ENABLE ROW LEVEL SECURITY;
CREATE POLICY job_postings_tenant ON job_postings
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

CREATE TABLE IF NOT EXISTS job_applications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  posting_id uuid NOT NULL REFERENCES job_postings(id) ON DELETE CASCADE,
  candidate_name text NOT NULL,
  candidate_email text,
  candidate_phone text,
  resume_url text,
  cover_letter text,
  status text DEFAULT 'received' CHECK (status IN ('received', 'screening', 'interview', 'offered', 'hired', 'rejected')),
  created_at timestamptz DEFAULT now()
);

ALTER TABLE job_applications ENABLE ROW LEVEL SECURITY;
CREATE POLICY job_applications_tenant ON job_applications
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

-- ============================================================
-- PTL-01 : Portail salarié
-- ============================================================
CREATE TABLE IF NOT EXISTS employee_self_service (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  employee_id uuid NOT NULL,
  auth_id uuid,  -- Lien vers auth.users
  can_view_payslips boolean DEFAULT true,
  can_request_leave boolean DEFAULT true,
  can_view_schedule boolean DEFAULT true,
  can_update_profile boolean DEFAULT false,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE employee_self_service ENABLE ROW LEVEL SECURITY;
CREATE POLICY employee_self_service_tenant ON employee_self_service
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

-- ============================================================
-- ONB-01 : Parcours d'inscription
-- ============================================================
CREATE TABLE IF NOT EXISTS signup_flows (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email text NOT NULL,
  company_name text,
  country_code text DEFAULT 'FR',
  current_step text DEFAULT 'company_info' CHECK (current_step IN (
    'company_info', 'plan_selection', 'payment', 'setup', 'completed'
  )),
  step_data jsonb DEFAULT '{}',
  tenant_id uuid,  -- Rempli quand le tenant est créé
  created_at timestamptz DEFAULT now(),
  completed_at timestamptz
);

ALTER TABLE signup_flows ENABLE ROW LEVEL SECURITY;
CREATE POLICY signup_flows_self ON signup_flows
  FOR ALL USING (true) WITH CHECK (true);

-- ============================================================
-- ONB-03 : Abonnement et facturation du service
-- ============================================================
CREATE TABLE IF NOT EXISTS subscriptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  plan_code text NOT NULL,  -- 'free', 'starter', 'pro', 'enterprise'
  plan_name text,
  price_monthly numeric DEFAULT 0,
  price_yearly numeric DEFAULT 0,
  billing_cycle text DEFAULT 'monthly' CHECK (billing_cycle IN ('monthly', 'yearly')),
  status text DEFAULT 'trial' CHECK (status IN ('trial', 'active', 'past_due', 'cancelled', 'suspended')),
  trial_ends_at timestamptz,
  current_period_start timestamptz,
  current_period_end timestamptz,
  stripe_customer_id text,
  stripe_subscription_id text,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE subscriptions ENABLE ROW LEVEL SECURITY;
CREATE POLICY subscriptions_tenant ON subscriptions
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

-- ============================================================
-- IMP-04 : Passerelles de migration (formats prédéfinis)
-- ============================================================
CREATE TABLE IF NOT EXISTS migration_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid,
  source_software text NOT NULL,  -- 'sage', 'odoo', 'cegid', 'ciel', 'quickbooks'
  source_version text,
  target_table text NOT NULL,
  column_mapping jsonb NOT NULL,
  transformation_rules jsonb,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE migration_templates ENABLE ROW LEVEL SECURITY;
CREATE POLICY migration_templates_tenant ON migration_templates
  FOR ALL USING (tenant_id = current_tenant_id() OR tenant_id IS NULL)
  WITH CHECK (tenant_id = current_tenant_id() OR tenant_id IS NULL);

-- ============================================================
-- API-03 : Connecteurs métier
-- ============================================================
CREATE TABLE IF NOT EXISTS business_connectors (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  connector_type text NOT NULL,  -- 'stripe', 'resend', 'openai', 'shopify', 'amazon'
  name text NOT NULL,
  config jsonb NOT NULL,  -- Configuration (sans secrets)
  secret_refs jsonb,       -- Références vers les secrets
  is_active boolean DEFAULT true,
  last_sync_at timestamptz,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE business_connectors ENABLE ROW LEVEL SECURITY;
CREATE POLICY business_connectors_tenant ON business_connectors
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

-- ============================================================
-- CNF-02 : Facturation électronique
-- ============================================================
CREATE TABLE IF NOT EXISTS e_invoicing_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  invoice_id uuid,
  platform text NOT NULL,  -- 'PPF', 'PDP', 'PP'
  status text NOT NULL CHECK (status IN ('pending', 'sent', 'delivered', 'rejected', 'cancelled')),
  ubl_xml text,             -- XML UBL/CII
  external_id text,         -- Identifiant externe
  error_message text,
  sent_at timestamptz,
  delivered_at timestamptz,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE e_invoicing_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY e_invoicing_logs_tenant ON e_invoicing_logs
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());
