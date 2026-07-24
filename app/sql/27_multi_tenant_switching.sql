-- ============================================
-- MULTI-TENANT SWITCHING FIX
-- Fixes current_tenant_id() to respect the active tenant
-- selected by the user (stored via set_config()).
-- ============================================
-- Problem: current_tenant_id() used LIMIT 1, which always
-- returned the first tenant — breaking multi-tenant users.
--
-- Solution: The app sets the active tenant via a custom
-- GUC (Grand Unified Configuration) parameter using
-- set_config('app.active_tenant_id', uuid, false).
-- The function checks this first, then falls back to
-- the first available tenant.
-- ============================================

-- IMPORTANT: Use CREATE OR REPLACE (not DROP) because RLS policies
-- depend on these functions. DROP would require CASCADE which would
-- delete all tenant-isolation policies on every business table.

-- ============================================
-- current_tenant_id(): returns the active tenant
-- ============================================
-- 1. Check if app.active_tenant_id is set (via set_config)
-- 2. Validate that the user is actually a member of that tenant
-- 3. Fall back to the first active tenant for this user
CREATE OR REPLACE FUNCTION current_tenant_id()
RETURNS uuid
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  WITH active_tenant AS (
    -- Try the GUC first
    SELECT NULLIF(current_setting('app.active_tenant_id', true), '')::uuid AS tid
  )
  SELECT COALESCE(
    -- If GUC is set AND user is a member of that tenant, use it
    (SELECT at.tid FROM active_tenant at
     WHERE at.tid IS NOT NULL
       AND EXISTS (
         SELECT 1 FROM tenant_users
         WHERE auth_id = auth.uid()
           AND status = 'active'
           AND tenant_id = at.tid
       )),
    -- Otherwise return the first active tenant for this user
    (SELECT tenant_id FROM tenant_users
     WHERE auth_id = auth.uid()
       AND status = 'active'
     ORDER BY created_at ASC
     LIMIT 1)
  )
$$;

-- ============================================
-- current_user_role(): returns the role in the active tenant
-- ============================================
CREATE OR REPLACE FUNCTION current_user_role()
RETURNS text
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT role FROM tenant_users
  WHERE auth_id = auth.uid()
    AND status = 'active'
    AND tenant_id = current_tenant_id()
  LIMIT 1
$$;

-- ============================================
-- current_user_permissions(): returns permissions in the active tenant
-- ============================================
CREATE OR REPLACE FUNCTION current_user_permissions()
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT permissions FROM tenant_users
  WHERE auth_id = auth.uid()
    AND status = 'active'
    AND tenant_id = current_tenant_id()
  LIMIT 1
$$;

-- ============================================
-- Helper: set_active_tenant(uuid)
-- ============================================
-- Can be called by the app to set the active tenant for the
-- current database session (affects RLS policies).
-- Usage: SELECT set_active_tenant('uuid-here');
CREATE OR REPLACE FUNCTION set_active_tenant(p_tenant_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
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
$$;

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION set_active_tenant(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION current_tenant_id() TO authenticated;
GRANT EXECUTE ON FUNCTION current_user_role() TO authenticated;
GRANT EXECUTE ON FUNCTION current_user_permissions() TO authenticated;
