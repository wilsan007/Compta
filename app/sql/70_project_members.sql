-- 70_project_members.sql
-- Project Members table — link employees to projects with roles
-- Part of project management module

-- ============================================================
-- 1. Table: project_members
-- ============================================================
CREATE TABLE IF NOT EXISTS project_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  employee_id UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  role VARCHAR(50) NOT NULL DEFAULT 'team_member',
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(tenant_id, project_id, employee_id)
);

-- ============================================================
-- 2. Indexes
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_project_members_tenant ON project_members(tenant_id);
CREATE INDEX IF NOT EXISTS idx_project_members_project ON project_members(project_id);
CREATE INDEX IF NOT EXISTS idx_project_members_employee ON project_members(employee_id);

-- ============================================================
-- 3. RLS Policies
-- ============================================================
ALTER TABLE project_members ENABLE ROW LEVEL SECURITY;

-- SELECT: users with access to the tenant can see project members
DROP POLICY IF EXISTS "project_members_select" ON project_members;
CREATE POLICY project_members_select ON project_members
  FOR SELECT TO authenticated
  USING (
    tenant_id IN (
      SELECT tu.tenant_id FROM tenant_users tu
      WHERE tu.auth_id = auth.uid() AND tu.status = 'active'
    )
  );

-- INSERT: only admins and project managers can add members
DROP POLICY IF EXISTS "project_members_insert" ON project_members;
CREATE POLICY project_members_insert ON project_members
  FOR INSERT TO authenticated
  WITH CHECK (
    tenant_id IN (
      SELECT tu.tenant_id FROM tenant_users tu
      WHERE tu.auth_id = auth.uid()
        AND tu.status = 'active'
        AND tu.role IN ('admin', 'accountant', 'manager')
    )
  );

-- UPDATE: only admins and project managers can update member roles
DROP POLICY IF EXISTS "project_members_update" ON project_members;
CREATE POLICY project_members_update ON project_members
  FOR UPDATE TO authenticated
  USING (
    tenant_id IN (
      SELECT tu.tenant_id FROM tenant_users tu
      WHERE tu.auth_id = auth.uid()
        AND tu.status = 'active'
        AND tu.role IN ('admin', 'accountant', 'manager')
    )
  );

-- DELETE: only admins can remove members
DROP POLICY IF EXISTS "project_members_delete" ON project_members;
CREATE POLICY project_members_delete ON project_members
  FOR DELETE TO authenticated
  USING (
    tenant_id IN (
      SELECT tu.tenant_id FROM tenant_users tu
      WHERE tu.auth_id = auth.uid()
        AND tu.status = 'active'
        AND tu.role IN ('admin', 'accountant', 'manager')
    )
  );
