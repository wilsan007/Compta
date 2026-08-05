-- ============================================================
-- Migration 71: Fix activity log user_name (was showing "Inconnu")
-- ============================================================
-- Root cause: SQL triggers used current_setting('app.user_name', true)
-- which was never set by the frontend, resulting in NULL user_name.
-- Fix: Look up user name from tenant_users using auth.uid() + NEW.tenant_id.
-- ============================================================

-- ============================================================
-- 1. Helper function: get current user name from tenant_users
--    Uses p_tenant_id from the trigger's NEW record (not current_tenant_id()
--    which may be NULL in trigger context due to connection pooling)
-- ============================================================
CREATE OR REPLACE FUNCTION current_user_name(p_tenant_id UUID DEFAULT NULL)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
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
$$;

GRANT EXECUTE ON FUNCTION current_user_name(UUID) TO authenticated;

-- ============================================================
-- 1b. Function: set_user_name (called from frontend after login)
--     Sets app.user_name session var so triggers can access it
-- ============================================================
CREATE OR REPLACE FUNCTION set_user_name(p_name TEXT)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
BEGIN
  PERFORM set_config('app.user_name', COALESCE(p_name, 'Unknown'), false);
END;
$$;

GRANT EXECUTE ON FUNCTION set_user_name(TEXT) TO authenticated;

-- ============================================================
-- 2. Fix trigger: log_task_activity (AFTER UPDATE)
--    Uses NEW.tenant_id for user lookup instead of current_tenant_id()
-- ============================================================
CREATE OR REPLACE FUNCTION log_task_activity()
RETURNS TRIGGER AS $$
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
$$ LANGUAGE plpgsql;

-- ============================================================
-- 3. Fix trigger: log_task_created (AFTER INSERT)
--    Uses NEW.tenant_id for user lookup instead of current_tenant_id()
-- ============================================================
CREATE OR REPLACE FUNCTION log_task_created()
RETURNS TRIGGER AS $$
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
$$ LANGUAGE plpgsql;

-- ============================================================
-- 4. Backfill: Update existing NULL/empty user_name entries
--    Try to recover user names from tenant_users
-- ============================================================
UPDATE project_activity_log al
SET user_name = tu.name,
    user_id = tu.auth_id
FROM tenant_users tu
WHERE (al.user_name IS NULL OR al.user_name = '' OR al.user_name = 'Unknown')
  AND tu.tenant_id = al.tenant_id
  AND tu.status = 'active'
  AND tu.auth_id = al.user_id;

-- For entries where user_id is also NULL, set to 'Unknown'
UPDATE project_activity_log
SET user_name = 'Unknown'
WHERE user_name IS NULL OR user_name = '';
