-- ============================================
-- RECURRING ENTRIES (Écritures d'abonnement)
-- ============================================
-- Automatic recurring journal entries for rent,
-- insurance, depreciation, subscriptions, etc.
-- ============================================

CREATE TABLE IF NOT EXISTS recurring_entries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  name text NOT NULL,
  description text,
  journal_id text NOT NULL,
  journal_code text,
  frequency text NOT NULL DEFAULT 'monthly', -- weekly, monthly, quarterly, yearly
  day_of_month int NOT NULL DEFAULT 1, -- 1-28
  start_date date NOT NULL,
  end_date date,
  next_generation_date date NOT NULL,
  last_generation_date date,
  lines jsonb NOT NULL DEFAULT '[]'::jsonb, -- array of {account_code, description, debit, credit}
  status text NOT NULL DEFAULT 'active', -- active, paused, expired
  total_debit numeric(14,2) NOT NULL DEFAULT 0,
  total_credit numeric(14,2) NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_recurring_entries_tenant ON recurring_entries(tenant_id);
CREATE INDEX IF NOT EXISTS idx_recurring_entries_status ON recurring_entries(status);
CREATE INDEX IF NOT EXISTS idx_recurring_entries_next_gen ON recurring_entries(next_generation_date) WHERE status = 'active';

-- RLS
ALTER TABLE recurring_entries ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_select_recurring_entries ON recurring_entries
  FOR SELECT USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_insert_recurring_entries ON recurring_entries
  FOR INSERT WITH CHECK (tenant_id = current_tenant_id() AND can_perform('recurring_entries', 'insert'));
CREATE POLICY tenant_update_recurring_entries ON recurring_entries
  FOR UPDATE USING (tenant_id = current_tenant_id() AND can_perform('recurring_entries', 'update'))
  WITH CHECK (tenant_id = current_tenant_id());
CREATE POLICY tenant_delete_recurring_entries ON recurring_entries
  FOR DELETE USING (tenant_id = current_tenant_id() AND can_perform('recurring_entries', 'delete'));
