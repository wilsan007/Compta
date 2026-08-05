-- 65_project_management.sql
-- Sprint 1: Project Management & Task Management — Fondation SQL
-- Source: Project & Task Management reference (section 25.3 + 27.4)

-- ============================================================
-- 1. Étendre la table projects existante
-- ============================================================
ALTER TABLE projects ADD COLUMN IF NOT EXISTS color VARCHAR(7) DEFAULT '#0066cc';
ALTER TABLE projects ADD COLUMN IF NOT EXISTS display_order VARCHAR(50) DEFAULT '0';
ALTER TABLE projects ADD COLUMN IF NOT EXISTS progress INTEGER DEFAULT 0;
ALTER TABLE projects ADD COLUMN IF NOT EXISTS manager_id UUID;
ALTER TABLE projects ADD COLUMN IF NOT EXISTS allow_subtasks BOOLEAN DEFAULT true;
ALTER TABLE projects ADD COLUMN IF NOT EXISTS allow_recurrent_tasks BOOLEAN DEFAULT false;
ALTER TABLE projects ADD COLUMN IF NOT EXISTS allow_milestones BOOLEAN DEFAULT true;
ALTER TABLE projects ADD COLUMN IF NOT EXISTS allow_task_dependencies BOOLEAN DEFAULT true;
ALTER TABLE projects ADD COLUMN IF NOT EXISTS allow_timesheets BOOLEAN DEFAULT false;
ALTER TABLE projects ADD COLUMN IF NOT EXISTS allow_billable BOOLEAN DEFAULT false;
ALTER TABLE projects ADD COLUMN IF NOT EXISTS privacy_visibility VARCHAR(20) DEFAULT 'portal';
ALTER TABLE projects ADD COLUMN IF NOT EXISTS alias_name VARCHAR(100);
ALTER TABLE projects ADD COLUMN IF NOT EXISTS allocated_hours DECIMAL(10,2) DEFAULT 0;
ALTER TABLE projects ADD COLUMN IF NOT EXISTS total_hours_spent DECIMAL(10,2) DEFAULT 0;
ALTER TABLE projects ADD COLUMN IF NOT EXISTS remaining_hours DECIMAL(10,2) DEFAULT 0;

-- ============================================================
-- 2. Table: project_tasks
-- ============================================================
CREATE TABLE IF NOT EXISTS project_tasks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  project_id UUID REFERENCES projects(id) ON DELETE SET NULL,
  parent_id UUID REFERENCES project_tasks(id) ON DELETE CASCADE,
  title VARCHAR(200) NOT NULL,
  description TEXT,
  status VARCHAR(20) NOT NULL DEFAULT 'todo',
  priority VARCHAR(20) NOT NULL DEFAULT 'medium',
  assignee VARCHAR(200),
  assignee_id UUID REFERENCES employees(id) ON DELETE SET NULL,
  start_date DATE,
  due_date DATE,
  effort_estimate_h DECIMAL(5,1) DEFAULT 0,
  effort_spent_h DECIMAL(5,1) DEFAULT 0,
  progress INTEGER DEFAULT 0,
  display_order VARCHAR(50) NOT NULL DEFAULT '0',
  task_level INTEGER DEFAULT 0,
  budget DECIMAL(12,2) DEFAULT 0,
  color INTEGER DEFAULT 0,
  acceptance_criteria TEXT,
  recurring_task BOOLEAN DEFAULT false,
  recurring_interval INTEGER DEFAULT 1,
  recurring_rule_type VARCHAR(20) DEFAULT 'weekly',
  is_closed BOOLEAN DEFAULT false,
  linked_action_id UUID,
  production_order_id UUID,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 3. Table: project_task_dependencies
-- ============================================================
CREATE TABLE IF NOT EXISTS project_task_dependencies (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  task_id UUID NOT NULL REFERENCES project_tasks(id) ON DELETE CASCADE,
  depends_on_task_id UUID NOT NULL REFERENCES project_tasks(id) ON DELETE CASCADE,
  dependency_type VARCHAR(30) NOT NULL DEFAULT 'finish-to-start',
  lag_days INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 4. Table: project_stages
-- ============================================================
CREATE TABLE IF NOT EXISTS project_stages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  name VARCHAR(100) NOT NULL,
  sequence INTEGER DEFAULT 0,
  fold BOOLEAN DEFAULT false,
  case_default BOOLEAN DEFAULT false,
  mail_template_id UUID,
  legend_priority VARCHAR(200),
  legend_blocked VARCHAR(200),
  legend_done VARCHAR(200),
  legend_normal VARCHAR(200),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 5. Table: project_milestones
-- ============================================================
CREATE TABLE IF NOT EXISTS project_milestones (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  name VARCHAR(255) NOT NULL,
  deadline DATE,
  is_reached BOOLEAN DEFAULT false,
  is_reached_manually BOOLEAN DEFAULT false,
  sale_line_id UUID,
  sale_line_qty_percentage DECIMAL(5,2) DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 6. Table: project_tags
-- ============================================================
CREATE TABLE IF NOT EXISTS project_tags (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  name VARCHAR(100) NOT NULL,
  color INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 7. Table: project_task_tags (junction M2M)
-- ============================================================
CREATE TABLE IF NOT EXISTS project_task_tags (
  task_id UUID NOT NULL REFERENCES project_tasks(id) ON DELETE CASCADE,
  tag_id UUID NOT NULL REFERENCES project_tags(id) ON DELETE CASCADE,
  PRIMARY KEY (task_id, tag_id)
);

-- ============================================================
-- 8. Table: project_task_assignees (junction multi-assignation)
-- ============================================================
CREATE TABLE IF NOT EXISTS project_task_assignees (
  task_id UUID NOT NULL REFERENCES project_tasks(id) ON DELETE CASCADE,
  employee_id UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  PRIMARY KEY (task_id, employee_id)
);

-- ============================================================
-- 9. Table: task_actions
-- ============================================================
CREATE TABLE IF NOT EXISTS task_actions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  task_id UUID NOT NULL REFERENCES project_tasks(id) ON DELETE CASCADE,
  title VARCHAR(100) NOT NULL,
  weight_percentage INTEGER DEFAULT 0,
  is_done BOOLEAN DEFAULT false,
  due_date DATE,
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 10. Table: task_action_attachments
-- ============================================================
CREATE TABLE IF NOT EXISTS task_action_attachments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  task_action_id UUID NOT NULL REFERENCES task_actions(id) ON DELETE CASCADE,
  task_id UUID NOT NULL REFERENCES project_tasks(id) ON DELETE CASCADE,
  file_name VARCHAR(255) NOT NULL,
  file_path VARCHAR(500) NOT NULL,
  file_size BIGINT,
  mime_type VARCHAR(100),
  uploader_id UUID,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 11. Table: task_documents
-- ============================================================
CREATE TABLE IF NOT EXISTS task_documents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  task_id UUID NOT NULL REFERENCES project_tasks(id) ON DELETE CASCADE,
  project_id UUID REFERENCES projects(id) ON DELETE SET NULL,
  file_name VARCHAR(255) NOT NULL,
  file_path VARCHAR(500) NOT NULL,
  file_size BIGINT,
  mime_type VARCHAR(100),
  uploader_id UUID,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 12. Table: task_comments
-- ============================================================
CREATE TABLE IF NOT EXISTS task_comments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  task_id UUID NOT NULL REFERENCES project_tasks(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  comment_type VARCHAR(20) DEFAULT 'general',
  author_id UUID,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 13. Indexes
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_project_tasks_tenant ON project_tasks(tenant_id);
CREATE INDEX IF NOT EXISTS idx_project_tasks_project ON project_tasks(project_id);
CREATE INDEX IF NOT EXISTS idx_project_tasks_parent ON project_tasks(parent_id);
CREATE INDEX IF NOT EXISTS idx_project_tasks_display_order ON project_tasks(display_order);
CREATE INDEX IF NOT EXISTS idx_project_tasks_status ON project_tasks(status);
CREATE INDEX IF NOT EXISTS idx_project_tasks_priority ON project_tasks(priority);

CREATE INDEX IF NOT EXISTS idx_project_task_dependencies_task ON project_task_dependencies(task_id);
CREATE INDEX IF NOT EXISTS idx_project_task_dependencies_depends ON project_task_dependencies(depends_on_task_id);

CREATE INDEX IF NOT EXISTS idx_project_stages_tenant ON project_stages(tenant_id);
CREATE INDEX IF NOT EXISTS idx_project_stages_sequence ON project_stages(sequence);

CREATE INDEX IF NOT EXISTS idx_project_milestones_project ON project_milestones(project_id);
CREATE INDEX IF NOT EXISTS idx_project_milestones_tenant ON project_milestones(tenant_id);

CREATE INDEX IF NOT EXISTS idx_project_tags_tenant ON project_tags(tenant_id);

CREATE INDEX IF NOT EXISTS idx_task_actions_task ON task_actions(task_id);
CREATE INDEX IF NOT EXISTS idx_task_actions_tenant ON task_actions(tenant_id);

CREATE INDEX IF NOT EXISTS idx_task_action_attachments_action ON task_action_attachments(task_action_id);
CREATE INDEX IF NOT EXISTS idx_task_action_attachments_task ON task_action_attachments(task_id);

CREATE INDEX IF NOT EXISTS idx_task_documents_task ON task_documents(task_id);
CREATE INDEX IF NOT EXISTS idx_task_documents_tenant ON task_documents(tenant_id);

CREATE INDEX IF NOT EXISTS idx_task_comments_task ON task_comments(task_id);
CREATE INDEX IF NOT EXISTS idx_task_comments_tenant ON task_comments(tenant_id);

-- ============================================================
-- 14. RLS Policies
-- ============================================================
ALTER TABLE project_tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE project_task_dependencies ENABLE ROW LEVEL SECURITY;
ALTER TABLE project_stages ENABLE ROW LEVEL SECURITY;
ALTER TABLE project_milestones ENABLE ROW LEVEL SECURITY;
ALTER TABLE project_tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE project_task_tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE project_task_assignees ENABLE ROW LEVEL SECURITY;
ALTER TABLE task_actions ENABLE ROW LEVEL SECURITY;
ALTER TABLE task_action_attachments ENABLE ROW LEVEL SECURITY;
ALTER TABLE task_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE task_comments ENABLE ROW LEVEL SECURITY;

-- project_tasks policies
DO $$ BEGIN
  CREATE POLICY tenant_select_project_tasks ON project_tasks FOR SELECT USING (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'select policy: %', SQLERRM; END $$;
DO $$ BEGIN
  CREATE POLICY tenant_insert_project_tasks ON project_tasks FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'insert policy: %', SQLERRM; END $$;
DO $$ BEGIN
  CREATE POLICY tenant_update_project_tasks ON project_tasks FOR UPDATE USING (tenant_id = current_tenant_id()) WITH CHECK (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'update policy: %', SQLERRM; END $$;
DO $$ BEGIN
  CREATE POLICY tenant_delete_project_tasks ON project_tasks FOR DELETE USING (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'delete policy: %', SQLERRM; END $$;

-- project_task_dependencies policies
DO $$ BEGIN
  CREATE POLICY tenant_select_project_task_deps ON project_task_dependencies FOR SELECT USING (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'select policy: %', SQLERRM; END $$;
DO $$ BEGIN
  CREATE POLICY tenant_insert_project_task_deps ON project_task_dependencies FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'insert policy: %', SQLERRM; END $$;
DO $$ BEGIN
  CREATE POLICY tenant_update_project_task_deps ON project_task_dependencies FOR UPDATE USING (tenant_id = current_tenant_id()) WITH CHECK (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'update policy: %', SQLERRM; END $$;
DO $$ BEGIN
  CREATE POLICY tenant_delete_project_task_deps ON project_task_dependencies FOR DELETE USING (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'delete policy: %', SQLERRM; END $$;

-- project_stages policies
DO $$ BEGIN
  CREATE POLICY tenant_select_project_stages ON project_stages FOR SELECT USING (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'select policy: %', SQLERRM; END $$;
DO $$ BEGIN
  CREATE POLICY tenant_insert_project_stages ON project_stages FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'insert policy: %', SQLERRM; END $$;
DO $$ BEGIN
  CREATE POLICY tenant_update_project_stages ON project_stages FOR UPDATE USING (tenant_id = current_tenant_id()) WITH CHECK (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'update policy: %', SQLERRM; END $$;
DO $$ BEGIN
  CREATE POLICY tenant_delete_project_stages ON project_stages FOR DELETE USING (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'delete policy: %', SQLERRM; END $$;

-- project_milestones policies
DO $$ BEGIN
  CREATE POLICY tenant_select_project_milestones ON project_milestones FOR SELECT USING (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'select policy: %', SQLERRM; END $$;
DO $$ BEGIN
  CREATE POLICY tenant_insert_project_milestones ON project_milestones FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'insert policy: %', SQLERRM; END $$;
DO $$ BEGIN
  CREATE POLICY tenant_update_project_milestones ON project_milestones FOR UPDATE USING (tenant_id = current_tenant_id()) WITH CHECK (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'update policy: %', SQLERRM; END $$;
DO $$ BEGIN
  CREATE POLICY tenant_delete_project_milestones ON project_milestones FOR DELETE USING (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'delete policy: %', SQLERRM; END $$;

-- project_tags policies
DO $$ BEGIN
  CREATE POLICY tenant_select_project_tags ON project_tags FOR SELECT USING (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'select policy: %', SQLERRM; END $$;
DO $$ BEGIN
  CREATE POLICY tenant_insert_project_tags ON project_tags FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'insert policy: %', SQLERRM; END $$;
DO $$ BEGIN
  CREATE POLICY tenant_update_project_tags ON project_tags FOR UPDATE USING (tenant_id = current_tenant_id()) WITH CHECK (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'update policy: %', SQLERRM; END $$;
DO $$ BEGIN
  CREATE POLICY tenant_delete_project_tags ON project_tags FOR DELETE USING (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'delete policy: %', SQLERRM; END $$;

-- project_task_tags policies (inherit from parent project_tasks)
DO $$ BEGIN
  CREATE POLICY tenant_select_project_task_tags ON project_task_tags FOR SELECT USING (
    EXISTS (SELECT 1 FROM project_tasks WHERE project_tasks.id = project_task_tags.task_id AND project_tasks.tenant_id = current_tenant_id())
  );
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'select policy: %', SQLERRM; END $$;
DO $$ BEGIN
  CREATE POLICY tenant_insert_project_task_tags ON project_task_tags FOR INSERT WITH CHECK (
    EXISTS (SELECT 1 FROM project_tasks WHERE project_tasks.id = project_task_tags.task_id AND project_tasks.tenant_id = current_tenant_id())
  );
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'insert policy: %', SQLERRM; END $$;
DO $$ BEGIN
  CREATE POLICY tenant_delete_project_task_tags ON project_task_tags FOR DELETE USING (
    EXISTS (SELECT 1 FROM project_tasks WHERE project_tasks.id = project_task_tags.task_id AND project_tasks.tenant_id = current_tenant_id())
  );
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'delete policy: %', SQLERRM; END $$;

-- project_task_assignees policies
DO $$ BEGIN
  CREATE POLICY tenant_select_project_task_assignees ON project_task_assignees FOR SELECT USING (
    EXISTS (SELECT 1 FROM project_tasks WHERE project_tasks.id = project_task_assignees.task_id AND project_tasks.tenant_id = current_tenant_id())
  );
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'select policy: %', SQLERRM; END $$;
DO $$ BEGIN
  CREATE POLICY tenant_insert_project_task_assignees ON project_task_assignees FOR INSERT WITH CHECK (
    EXISTS (SELECT 1 FROM project_tasks WHERE project_tasks.id = project_task_assignees.task_id AND project_tasks.tenant_id = current_tenant_id())
  );
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'insert policy: %', SQLERRM; END $$;
DO $$ BEGIN
  CREATE POLICY tenant_delete_project_task_assignees ON project_task_assignees FOR DELETE USING (
    EXISTS (SELECT 1 FROM project_tasks WHERE project_tasks.id = project_task_assignees.task_id AND project_tasks.tenant_id = current_tenant_id())
  );
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'delete policy: %', SQLERRM; END $$;

-- task_actions policies
DO $$ BEGIN
  CREATE POLICY tenant_select_task_actions ON task_actions FOR SELECT USING (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'select policy: %', SQLERRM; END $$;
DO $$ BEGIN
  CREATE POLICY tenant_insert_task_actions ON task_actions FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'insert policy: %', SQLERRM; END $$;
DO $$ BEGIN
  CREATE POLICY tenant_update_task_actions ON task_actions FOR UPDATE USING (tenant_id = current_tenant_id()) WITH CHECK (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'update policy: %', SQLERRM; END $$;
DO $$ BEGIN
  CREATE POLICY tenant_delete_task_actions ON task_actions FOR DELETE USING (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'delete policy: %', SQLERRM; END $$;

-- task_action_attachments policies
DO $$ BEGIN
  CREATE POLICY tenant_select_task_action_att ON task_action_attachments FOR SELECT USING (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'select policy: %', SQLERRM; END $$;
DO $$ BEGIN
  CREATE POLICY tenant_insert_task_action_att ON task_action_attachments FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'insert policy: %', SQLERRM; END $$;
DO $$ BEGIN
  CREATE POLICY tenant_update_task_action_att ON task_action_attachments FOR UPDATE USING (tenant_id = current_tenant_id()) WITH CHECK (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'update policy: %', SQLERRM; END $$;
DO $$ BEGIN
  CREATE POLICY tenant_delete_task_action_att ON task_action_attachments FOR DELETE USING (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'delete policy: %', SQLERRM; END $$;

-- task_documents policies
DO $$ BEGIN
  CREATE POLICY tenant_select_task_documents ON task_documents FOR SELECT USING (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'select policy: %', SQLERRM; END $$;
DO $$ BEGIN
  CREATE POLICY tenant_insert_task_documents ON task_documents FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'insert policy: %', SQLERRM; END $$;
DO $$ BEGIN
  CREATE POLICY tenant_update_task_documents ON task_documents FOR UPDATE USING (tenant_id = current_tenant_id()) WITH CHECK (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'update policy: %', SQLERRM; END $$;
DO $$ BEGIN
  CREATE POLICY tenant_delete_task_documents ON task_documents FOR DELETE USING (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'delete policy: %', SQLERRM; END $$;

-- task_comments policies
DO $$ BEGIN
  CREATE POLICY tenant_select_task_comments ON task_comments FOR SELECT USING (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'select policy: %', SQLERRM; END $$;
DO $$ BEGIN
  CREATE POLICY tenant_insert_task_comments ON task_comments FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'insert policy: %', SQLERRM; END $$;
DO $$ BEGIN
  CREATE POLICY tenant_update_task_comments ON task_comments FOR UPDATE USING (tenant_id = current_tenant_id()) WITH CHECK (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'update policy: %', SQLERRM; END $$;
DO $$ BEGIN
  CREATE POLICY tenant_delete_task_comments ON task_comments FOR DELETE USING (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'delete policy: %', SQLERRM; END $$;

-- ============================================================
-- 15. Triggers updated_at
-- ============================================================
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS project_tasks_updated_at ON project_tasks;
CREATE TRIGGER project_tasks_updated_at BEFORE UPDATE ON project_tasks FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
DROP TRIGGER IF EXISTS project_stages_updated_at ON project_stages;
CREATE TRIGGER project_stages_updated_at BEFORE UPDATE ON project_stages FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
DROP TRIGGER IF EXISTS project_milestones_updated_at ON project_milestones;
CREATE TRIGGER project_milestones_updated_at BEFORE UPDATE ON project_milestones FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================
-- 16. Seed default stages
-- (Removed — tables only, no seed data)
-- ============================================================
