-- 71_notification_email_system.sql
-- Notification email queue + user notification preferences
-- Part of the centralized notification system using Resend API

-- ============================================================
-- 1. Table: notification_email_queue
--    Tracks all outgoing notification emails for audit/debug
-- ============================================================
CREATE TABLE IF NOT EXISTS notification_email_queue (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
  recipient_email VARCHAR(255) NOT NULL,
  recipient_name VARCHAR(255),
  notification_type VARCHAR(50) NOT NULL,
  subject VARCHAR(500) NOT NULL,
  status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'sent', 'failed', 'bounced')),
  resend_id VARCHAR(255),
  error_message TEXT,
  sent_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_email_queue_tenant ON notification_email_queue(tenant_id);
CREATE INDEX IF NOT EXISTS idx_email_queue_recipient ON notification_email_queue(recipient_email);
CREATE INDEX IF NOT EXISTS idx_email_queue_status ON notification_email_queue(status);
CREATE INDEX IF NOT EXISTS idx_email_queue_created ON notification_email_queue(created_at DESC);

-- ============================================================
-- 2. Table: notification_preferences
--    Per-user email notification preferences
--    Controls which notification types trigger an email
-- ============================================================
CREATE TABLE IF NOT EXISTS notification_preferences (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  employee_id UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  -- Global toggle
  email_enabled BOOLEAN DEFAULT true,
  -- Per-type toggles (JSONB): { "task_assigned": true, "task_overdue": true, ... }
  -- If a type is not in the JSON, it falls back to the default for that type
  email_types JSONB DEFAULT '{}',
  -- Digest mode: 'instant' (send immediately), 'daily' (daily digest), 'disabled'
  digest_mode VARCHAR(20) DEFAULT 'instant' CHECK (digest_mode IN ('instant', 'daily', 'disabled')),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(tenant_id, employee_id)
);

CREATE INDEX IF NOT EXISTS idx_notif_prefs_tenant ON notification_preferences(tenant_id);
CREATE INDEX IF NOT EXISTS idx_notif_prefs_employee ON notification_preferences(employee_id);

-- ============================================================
-- 3. RLS Policies
-- ============================================================
ALTER TABLE notification_email_queue ENABLE ROW LEVEL SECURITY;
ALTER TABLE notification_preferences ENABLE ROW LEVEL SECURITY;

-- Email queue: only admins can view, system can insert
CREATE POLICY email_queue_select ON notification_email_queue
  FOR SELECT TO authenticated
  USING (
    tenant_id IN (
      SELECT tu.tenant_id FROM tenant_users tu
      WHERE tu.auth_id = auth.uid() AND tu.status = 'active' AND tu.role = 'admin'
    )
  );

CREATE POLICY email_queue_insert ON notification_email_queue
  FOR INSERT TO authenticated
  WITH CHECK (
    tenant_id IN (
      SELECT tu.tenant_id FROM tenant_users tu
      WHERE tu.auth_id = auth.uid() AND tu.status = 'active'
    )
  );

-- Notification preferences: users can read/update their own, admins can read all
CREATE POLICY notif_prefs_select ON notification_preferences
  FOR SELECT TO authenticated
  USING (
    tenant_id IN (
      SELECT tu.tenant_id FROM tenant_users tu
      WHERE tu.auth_id = auth.uid() AND tu.status = 'active'
    )
  );

CREATE POLICY notif_prefs_insert ON notification_preferences
  FOR INSERT TO authenticated
  WITH CHECK (
    tenant_id IN (
      SELECT tu.tenant_id FROM tenant_users tu
      WHERE tu.auth_id = auth.uid() AND tu.status = 'active'
    )
  );

CREATE POLICY notif_prefs_update ON notification_preferences
  FOR UPDATE TO authenticated
  USING (
    tenant_id IN (
      SELECT tu.tenant_id FROM tenant_users tu
      WHERE tu.auth_id = auth.uid() AND tu.status = 'active'
    )
  );

-- ============================================================
-- 4. Add notification_type values to project_notifications
--    (extend the existing VARCHAR(50) column with new types)
--    No schema change needed — just documenting the new values
-- ============================================================
-- Extended notification types:
--   CRITICAL (email by default):
--     task_assigned, task_overdue, due_date_approaching,
--     payment_overdue, stock_critical, invitation_pending
--   IMPORTANT (email optional):
--     status_changed, mention, budget_exceeded, approval_request,
--     project_member_added
--   INFORMATIONAL (in-app only):
--     comment_added, watcher_update, stock_warning,
--     task_completed, progress_changed
