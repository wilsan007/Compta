-- ============================================
-- Phase 7C: Minor Fixes
-- Items 16-30: revision cycles, reporting plans, stat fields,
-- dashboard widgets, fusion comptes, compaction, RGPD
-- ============================================

-- ============================================
-- 1. REVISION_CYCLES — cycles de révision des comptes
-- ============================================
CREATE TABLE IF NOT EXISTS revision_cycles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  name text NOT NULL,
  frequency text NOT NULL DEFAULT 'annual' CHECK (frequency IN ('monthly', 'quarterly', 'annual', 'custom')),
  start_month int NOT NULL DEFAULT 1 CHECK (start_month >= 1 AND start_month <= 12),
  account_class text,
  active boolean DEFAULT true,
  last_run date,
  next_run date,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_revision_cycles_tenant ON revision_cycles(tenant_id);
CREATE INDEX IF NOT EXISTS idx_revision_cycles_active ON revision_cycles(active);

ALTER TABLE revision_cycles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_select_revision_cycles ON revision_cycles;
DROP POLICY IF EXISTS tenant_insert_revision_cycles ON revision_cycles;
DROP POLICY IF EXISTS tenant_update_revision_cycles ON revision_cycles;
DROP POLICY IF EXISTS tenant_delete_revision_cycles ON revision_cycles;
DO $$ BEGIN
  DROP POLICY IF EXISTS tenant_select_revision_cycles ON revision_cycles;
  CREATE POLICY tenant_select_revision_cycles ON revision_cycles FOR SELECT USING (tenant_id = current_tenant_id());
  DROP POLICY IF EXISTS tenant_insert_revision_cycles ON revision_cycles;
  CREATE POLICY tenant_insert_revision_cycles ON revision_cycles FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
  DROP POLICY IF EXISTS tenant_update_revision_cycles ON revision_cycles;
  CREATE POLICY tenant_update_revision_cycles ON revision_cycles FOR UPDATE USING (tenant_id = current_tenant_id());
  DROP POLICY IF EXISTS tenant_delete_revision_cycles ON revision_cycles;
  CREATE POLICY tenant_delete_revision_cycles ON revision_cycles FOR DELETE USING (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'revision_cycles RLS: %', SQLERRM; END $$;

-- ============================================
-- 2. REPORTING_PLANS — plans de reporting
-- ============================================
CREATE TABLE IF NOT EXISTS reporting_plans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  name text NOT NULL,
  report_type text NOT NULL CHECK (report_type IN ('balance', 'pnl', 'cashflow', 'vat', 'custom')),
  schedule text NOT NULL DEFAULT 'manual' CHECK (schedule IN ('manual', 'monthly', 'quarterly', 'annual')),
  format text NOT NULL DEFAULT 'pdf' CHECK (format IN ('pdf', 'excel', 'csv')),
  recipients text,
  parameters jsonb DEFAULT '{}',
  last_generated timestamptz,
  active boolean DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_reporting_plans_tenant ON reporting_plans(tenant_id);
CREATE INDEX IF NOT EXISTS idx_reporting_plans_active ON reporting_plans(active);

ALTER TABLE reporting_plans ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_select_reporting_plans ON reporting_plans;
DROP POLICY IF EXISTS tenant_insert_reporting_plans ON reporting_plans;
DROP POLICY IF EXISTS tenant_update_reporting_plans ON reporting_plans;
DROP POLICY IF EXISTS tenant_delete_reporting_plans ON reporting_plans;
DO $$ BEGIN
  DROP POLICY IF EXISTS tenant_select_reporting_plans ON reporting_plans;
  CREATE POLICY tenant_select_reporting_plans ON reporting_plans FOR SELECT USING (tenant_id = current_tenant_id());
  DROP POLICY IF EXISTS tenant_insert_reporting_plans ON reporting_plans;
  CREATE POLICY tenant_insert_reporting_plans ON reporting_plans FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
  DROP POLICY IF EXISTS tenant_update_reporting_plans ON reporting_plans;
  CREATE POLICY tenant_update_reporting_plans ON reporting_plans FOR UPDATE USING (tenant_id = current_tenant_id());
  DROP POLICY IF EXISTS tenant_delete_reporting_plans ON reporting_plans;
  CREATE POLICY tenant_delete_reporting_plans ON reporting_plans FOR DELETE USING (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'reporting_plans RLS: %', SQLERRM; END $$;

-- ============================================
-- 3. STAT_FIELDS — champs statistiques personnalisés
-- ============================================
CREATE TABLE IF NOT EXISTS stat_fields (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  entity_type text NOT NULL CHECK (entity_type IN ('customer', 'supplier', 'product', 'account', 'journal')),
  entity_id text NOT NULL,
  field_name text NOT NULL,
  field_value text,
  field_type text NOT NULL DEFAULT 'text' CHECK (field_type IN ('text', 'number', 'date', 'boolean')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(tenant_id, entity_type, entity_id, field_name)
);

CREATE INDEX IF NOT EXISTS idx_stat_fields_tenant ON stat_fields(tenant_id);
CREATE INDEX IF NOT EXISTS idx_stat_fields_entity ON stat_fields(entity_type, entity_id);

ALTER TABLE stat_fields ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_select_stat_fields ON stat_fields;
DROP POLICY IF EXISTS tenant_insert_stat_fields ON stat_fields;
DROP POLICY IF EXISTS tenant_update_stat_fields ON stat_fields;
DROP POLICY IF EXISTS tenant_delete_stat_fields ON stat_fields;
DO $$ BEGIN
  DROP POLICY IF EXISTS tenant_select_stat_fields ON stat_fields;
  CREATE POLICY tenant_select_stat_fields ON stat_fields FOR SELECT USING (tenant_id = current_tenant_id());
  DROP POLICY IF EXISTS tenant_insert_stat_fields ON stat_fields;
  CREATE POLICY tenant_insert_stat_fields ON stat_fields FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
  DROP POLICY IF EXISTS tenant_update_stat_fields ON stat_fields;
  CREATE POLICY tenant_update_stat_fields ON stat_fields FOR UPDATE USING (tenant_id = current_tenant_id());
  DROP POLICY IF EXISTS tenant_delete_stat_fields ON stat_fields;
  CREATE POLICY tenant_delete_stat_fields ON stat_fields FOR DELETE USING (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'stat_fields RLS: %', SQLERRM; END $$;

-- ============================================
-- 4. DASHBOARD_WIDGETS — widgets personnalisables
-- ============================================
CREATE TABLE IF NOT EXISTS dashboard_widgets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  user_id text NOT NULL,
  widget_type text NOT NULL CHECK (widget_type IN ('chart', 'table', 'kpi', 'alert', 'custom')),
  title text NOT NULL,
  config jsonb DEFAULT '{}',
  position int NOT NULL DEFAULT 0,
  size text NOT NULL DEFAULT 'medium' CHECK (size IN ('small', 'medium', 'large', 'full')),
  visible boolean DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_dashboard_widgets_tenant ON dashboard_widgets(tenant_id);
CREATE INDEX IF NOT EXISTS idx_dashboard_widgets_user ON dashboard_widgets(user_id);

ALTER TABLE dashboard_widgets ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_select_dashboard_widgets ON dashboard_widgets;
DROP POLICY IF EXISTS tenant_insert_dashboard_widgets ON dashboard_widgets;
DROP POLICY IF EXISTS tenant_update_dashboard_widgets ON dashboard_widgets;
DROP POLICY IF EXISTS tenant_delete_dashboard_widgets ON dashboard_widgets;
DO $$ BEGIN
  DROP POLICY IF EXISTS tenant_select_dashboard_widgets ON dashboard_widgets;
  CREATE POLICY tenant_select_dashboard_widgets ON dashboard_widgets FOR SELECT USING (tenant_id = current_tenant_id());
  DROP POLICY IF EXISTS tenant_insert_dashboard_widgets ON dashboard_widgets;
  CREATE POLICY tenant_insert_dashboard_widgets ON dashboard_widgets FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
  DROP POLICY IF EXISTS tenant_update_dashboard_widgets ON dashboard_widgets;
  CREATE POLICY tenant_update_dashboard_widgets ON dashboard_widgets FOR UPDATE USING (tenant_id = current_tenant_id());
  DROP POLICY IF EXISTS tenant_delete_dashboard_widgets ON dashboard_widgets;
  CREATE POLICY tenant_delete_dashboard_widgets ON dashboard_widgets FOR DELETE USING (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'dashboard_widgets RLS: %', SQLERRM; END $$;

-- ============================================
-- 5. FUSION_LOGS — journal des fusions de comptes
-- ============================================
CREATE TABLE IF NOT EXISTS fusion_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  source_account_code text NOT NULL,
  target_account_code text NOT NULL,
  lines_moved int NOT NULL DEFAULT 0,
  fused_by text,
  fused_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_fusion_logs_tenant ON fusion_logs(tenant_id);
CREATE INDEX IF NOT EXISTS idx_fusion_logs_target ON fusion_logs(target_account_code);

ALTER TABLE fusion_logs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_select_fusion_logs ON fusion_logs;
DROP POLICY IF EXISTS tenant_insert_fusion_logs ON fusion_logs;
DO $$ BEGIN
  CREATE POLICY tenant_select_fusion_logs ON fusion_logs FOR SELECT USING (tenant_id = current_tenant_id());
  CREATE POLICY tenant_insert_fusion_logs ON fusion_logs FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'fusion_logs RLS: %', SQLERRM; END $$;

-- ============================================
-- 6. COMPACTION_LOGS — journal des compactages
-- ============================================
CREATE TABLE IF NOT EXISTS compaction_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  fiscal_year_id uuid,
  entries_compacted int NOT NULL DEFAULT 0,
  lines_compacted int NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'completed' CHECK (status IN ('pending', 'in_progress', 'completed', 'failed')),
  compacted_by text,
  compacted_at timestamptz NOT NULL DEFAULT now(),
  details jsonb
);

CREATE INDEX IF NOT EXISTS idx_compaction_logs_tenant ON compaction_logs(tenant_id);

ALTER TABLE compaction_logs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_select_compaction_logs ON compaction_logs;
DROP POLICY IF EXISTS tenant_insert_compaction_logs ON compaction_logs;
DO $$ BEGIN
  CREATE POLICY tenant_select_compaction_logs ON compaction_logs FOR SELECT USING (tenant_id = current_tenant_id());
  CREATE POLICY tenant_insert_compaction_logs ON compaction_logs FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'compaction_logs RLS: %', SQLERRM; END $$;

-- ============================================
-- 7. RGPD_REQUESTS — demandes RGPD
-- ============================================
CREATE TABLE IF NOT EXISTS rgpd_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  request_type text NOT NULL CHECK (request_type IN ('export', 'delete', 'anonymize', 'access')),
  entity_type text NOT NULL CHECK (entity_type IN ('customer', 'supplier', 'employee', 'all')),
  entity_id text,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'rejected')),
  requested_by text,
  processed_by text,
  requested_at timestamptz NOT NULL DEFAULT now(),
  processed_at timestamptz,
  notes text
);

CREATE INDEX IF NOT EXISTS idx_rgpd_requests_tenant ON rgpd_requests(tenant_id);
CREATE INDEX IF NOT EXISTS idx_rgpd_requests_status ON rgpd_requests(status);

ALTER TABLE rgpd_requests ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_select_rgpd_requests ON rgpd_requests;
DROP POLICY IF EXISTS tenant_insert_rgpd_requests ON rgpd_requests;
DROP POLICY IF EXISTS tenant_update_rgpd_requests ON rgpd_requests;
DO $$ BEGIN
  DROP POLICY IF EXISTS tenant_select_rgpd_requests ON rgpd_requests;
  CREATE POLICY tenant_select_rgpd_requests ON rgpd_requests FOR SELECT USING (tenant_id = current_tenant_id());
  DROP POLICY IF EXISTS tenant_insert_rgpd_requests ON rgpd_requests;
  CREATE POLICY tenant_insert_rgpd_requests ON rgpd_requests FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
  DROP POLICY IF EXISTS tenant_update_rgpd_requests ON rgpd_requests;
  CREATE POLICY tenant_update_rgpd_requests ON rgpd_requests FOR UPDATE USING (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'rgpd_requests RLS: %', SQLERRM; END $$;

-- ============================================
-- 8. Add IFRS flag to journal_entries
-- ============================================
DO $$ BEGIN
  ALTER TABLE journal_entries ADD COLUMN IF NOT EXISTS ifrs_mode boolean DEFAULT false;
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'journal_entries ifrs_mode: %', SQLERRM; END $$;

-- ============================================
-- 9. Add balance columns to chart_accounts for list display
-- ============================================
DO $$ BEGIN
  ALTER TABLE chart_accounts ADD COLUMN IF NOT EXISTS current_debit numeric(14,2) DEFAULT 0;
  ALTER TABLE chart_accounts ADD COLUMN IF NOT EXISTS current_credit numeric(14,2) DEFAULT 0;
  ALTER TABLE chart_accounts ADD COLUMN IF NOT EXISTS current_balance numeric(14,2) DEFAULT 0;
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'chart_accounts balance columns: %', SQLERRM; END $$;
