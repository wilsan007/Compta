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
-- SEC-03: Suppression du fallback "premier tenant".
--   Si aucun tenant n'est explicitement défini, renvoie NULL
--   → RLS bloque toutes les requêtes (fail-closed).
--
-- Ordre de résolution :
-- 1. En-tête x-tenant-id (request.headers, fiable derrière pooler)
-- 2. GUC app.active_tenant_id (set_config, session locale)
-- 3. NULL (aucun tenant → aucune donnée)
--
-- Dans les deux cas, valide que l'utilisateur est membre du tenant.
CREATE OR REPLACE FUNCTION current_tenant_id()
RETURNS uuid
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  WITH candidates AS (
    -- 1. En-tête x-tenant-id (transmis par PostgREST depuis le client)
    SELECT NULLIF(
      current_setting('request.headers', true)::json->>'x-tenant-id',
      ''
    )::uuid AS tid
    UNION ALL
    -- 2. GUC de session (set_config via set_active_tenant)
    SELECT NULLIF(current_setting('app.active_tenant_id', true), '')::uuid AS tid
  )
  SELECT c.tid
  FROM candidates c
  WHERE c.tid IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM tenant_users
      WHERE auth_id = auth.uid()
        AND status = 'active'
        AND tenant_id = c.tid
    )
  LIMIT 1
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
