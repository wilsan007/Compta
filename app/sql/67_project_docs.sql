-- Project Docs table for collaborative documents within Project Management
-- Used by DocView component

CREATE TABLE IF NOT EXISTS project_docs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL,
  project_id UUID REFERENCES projects(id) ON DELETE CASCADE,
  title TEXT NOT NULL DEFAULT '',
  content TEXT NOT NULL DEFAULT '',
  created_by UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- RLS policies
ALTER TABLE project_docs ENABLE ROW LEVEL SECURITY;

CREATE POLICY project_docs_tenant_select
  ON project_docs FOR SELECT
  USING (tenant_id = (SELECT id FROM tenants LIMIT 1));

CREATE POLICY project_docs_tenant_insert
  ON project_docs FOR INSERT
  WITH CHECK (tenant_id = (SELECT id FROM tenants LIMIT 1));

CREATE POLICY project_docs_tenant_update
  ON project_docs FOR UPDATE
  USING (tenant_id = (SELECT id FROM tenants LIMIT 1))
  WITH CHECK (tenant_id = (SELECT id FROM tenants LIMIT 1));

CREATE POLICY project_docs_tenant_delete
  ON project_docs FOR DELETE
  USING (tenant_id = (SELECT id FROM tenants LIMIT 1));

-- Index for tenant + project filtering
CREATE INDEX IF NOT EXISTS idx_project_docs_tenant ON project_docs(tenant_id);
CREATE INDEX IF NOT EXISTS idx_project_docs_project ON project_docs(project_id);
CREATE INDEX IF NOT EXISTS idx_project_docs_updated ON project_docs(updated_at DESC);
