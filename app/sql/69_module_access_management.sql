-- ============================================
-- 69_module_access_management.sql
-- Module Access Management: module_roles + guest_permissions + helper functions + RLS
-- ============================================
-- This migration implements the granular module-based RBAC system.
-- It adds module_roles and guest_permissions columns to tenant_users,
-- creates helper functions for permission checks, and defines RLS policies.
--
-- Prerequisites:
--   - Tables tenant_users, tenants exist
--   - Functions current_tenant_id(), current_user_role() exist
-- ============================================

-- ============================================
-- 1. ADD module_roles + guest_permissions TO tenant_users
-- ============================================
ALTER TABLE tenant_users ADD COLUMN IF NOT EXISTS module_roles JSONB DEFAULT '{}';
ALTER TABLE tenant_users ADD COLUMN IF NOT EXISTS guest_permissions JSONB DEFAULT '{}';

-- ============================================
-- 2. HELPER FUNCTIONS
-- ============================================

-- current_module_role(module_name): returns the user's role in a specific module
-- Returns values like 'project_director', 'project_manager', 'team_member', 'consultant', 'guest',
-- 'accountant', 'auditor', 'hr_director', 'hr_manager', 'sales_director', 'treasurer', etc.
-- Returns NULL if the user has no role in that module.
CREATE OR REPLACE FUNCTION current_module_role(p_module text)
RETURNS text
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT (module_roles ->> p_module) FROM tenant_users
  WHERE auth_id = auth.uid()
    AND status = 'active'
    AND tenant_id = current_tenant_id()
  LIMIT 1
$$;

-- current_tenant_user_id(): returns the tenant_users.id for the current authenticated user
CREATE OR REPLACE FUNCTION current_tenant_user_id()
RETURNS uuid
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT id FROM tenant_users
  WHERE auth_id = auth.uid()
    AND status = 'active'
    AND tenant_id = current_tenant_id()
  LIMIT 1
$$;

-- current_guest_permissions(): returns the guest_permissions JSONB for the current user
-- Contains: { projectIds: [], views: { table, kanban, gantt, ... }, perProject: { tasks, documents, ... } }
CREATE OR REPLACE FUNCTION current_guest_permissions()
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT guest_permissions FROM tenant_users
  WHERE auth_id = auth.uid()
    AND status = 'active'
    AND tenant_id = current_tenant_id()
  LIMIT 1
$$;

-- has_module_access(module_name): boolean
-- Returns true if the user is admin OR has a non-empty module_roles entry for that module.
CREATE OR REPLACE FUNCTION has_module_access(p_module text)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT
    current_user_role() = 'admin'
    OR (
      current_module_role(p_module) IS NOT NULL
      AND current_module_role(p_module) != ''
    )
$$;

-- has_module_permission(module_name, permission): boolean
-- Checks if the user has a specific permission within a module.
-- Permissions: 'view', 'create', 'edit', 'delete', 'approve'
-- Admin = all permissions. Directors = all. Managers = create/edit/approve.
-- Team members = view/create/edit. Consultants = view/edit. Guests = view only.
CREATE OR REPLACE FUNCTION has_module_permission(p_module text, p_permission text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
AS $$
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
$$;

GRANT EXECUTE ON FUNCTION current_module_role(text) TO authenticated;
GRANT EXECUTE ON FUNCTION current_tenant_user_id() TO authenticated;
GRANT EXECUTE ON FUNCTION current_guest_permissions() TO authenticated;
GRANT EXECUTE ON FUNCTION has_module_access(text) TO authenticated;
GRANT EXECUTE ON FUNCTION has_module_permission(text, text) TO authenticated;

-- ============================================
-- 3. INDEXES for module_roles and guest_permissions
-- ============================================
CREATE INDEX IF NOT EXISTS idx_tenant_users_module_roles ON tenant_users USING gin (module_roles);
CREATE INDEX IF NOT EXISTS idx_tenant_users_guest_perms ON tenant_users USING gin (guest_permissions);

-- ============================================
-- 4. RLS POLICY: tenant_users can read their own module_roles
--    (Admins can read all tenant_users in their tenant)
-- ============================================
-- Note: RLS on tenant_users is already managed by existing policies.
-- The new columns inherit the existing row-level security.
-- No additional RLS policies needed here — the existing tenant_users RLS
-- already filters by tenant_id and role.

-- ============================================
-- 5. UPDATE EXISTING tenant_users: set default module_roles for admins
-- ============================================
-- Admins automatically get all module roles set to 'admin' equivalent
UPDATE tenant_users
SET module_roles = jsonb_build_object(
  'projectManagement', 'project_director',
  'accounting', 'accountant',
  'hr', 'hr_director',
  'commercial', 'sales_director',
  'treasury', 'treasurer',
  'stock', 'warehouse_manager',
  'production', 'production_manager'
)
WHERE role = 'admin' AND module_roles = '{}'::jsonb;
