-- 66_project_management_sprint1.sql
-- Sprint 1: ClickUp feature gaps — Time Tracking, Watchers, Activity Log, Templates, Notifications
-- Source: CLICKUP-REFERENCE-GESTION-PROJET.md

-- ============================================================
-- 1. Table: project_time_entries (Time Tracking / Timer)
-- ============================================================
CREATE TABLE IF NOT EXISTS project_time_entries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  task_id UUID REFERENCES project_tasks(id) ON DELETE CASCADE,
  project_id UUID REFERENCES projects(id) ON DELETE SET NULL,
  employee_id UUID REFERENCES employees(id) ON DELETE SET NULL,
  start_time TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  end_time TIMESTAMPTZ,
  duration_seconds INTEGER DEFAULT 0,
  description TEXT,
  is_billable BOOLEAN DEFAULT false,
  hourly_rate DECIMAL(10,2) DEFAULT 0,
  tags TEXT[] DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_time_entries_task ON project_time_entries(task_id);
CREATE INDEX IF NOT EXISTS idx_time_entries_tenant ON project_time_entries(tenant_id);
CREATE INDEX IF NOT EXISTS idx_time_entries_employee ON project_time_entries(employee_id);
CREATE INDEX IF NOT EXISTS idx_time_entries_project ON project_time_entries(project_id);
CREATE INDEX IF NOT EXISTS idx_time_entries_start ON project_time_entries(start_time);

-- ============================================================
-- 2. Table: project_task_watchers (Observateurs)
-- ============================================================
CREATE TABLE IF NOT EXISTS project_task_watchers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  task_id UUID NOT NULL REFERENCES project_tasks(id) ON DELETE CASCADE,
  employee_id UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(task_id, employee_id)
);

CREATE INDEX IF NOT EXISTS idx_task_watchers_task ON project_task_watchers(task_id);
CREATE INDEX IF NOT EXISTS idx_task_watchers_employee ON project_task_watchers(employee_id);

-- ============================================================
-- 3. Table: project_activity_log (Fil d'activité)
-- ============================================================
CREATE TABLE IF NOT EXISTS project_activity_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  task_id UUID REFERENCES project_tasks(id) ON DELETE CASCADE,
  project_id UUID REFERENCES projects(id) ON DELETE SET NULL,
  user_id UUID,
  user_name VARCHAR(200),
  action_type VARCHAR(50) NOT NULL,
  old_value JSONB,
  new_value JSONB,
  description TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_activity_log_task ON project_activity_log(task_id);
CREATE INDEX IF NOT EXISTS idx_activity_log_tenant ON project_activity_log(tenant_id);
CREATE INDEX IF NOT EXISTS idx_activity_log_project ON project_activity_log(project_id);
CREATE INDEX IF NOT EXISTS idx_activity_log_created ON project_activity_log(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_activity_log_type ON project_activity_log(action_type);

-- ============================================================
-- 4. Table: project_task_templates (Modèles de tâches)
-- ============================================================
CREATE TABLE IF NOT EXISTS project_task_templates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  name VARCHAR(200) NOT NULL,
  description TEXT,
  default_status VARCHAR(20) DEFAULT 'todo',
  default_priority VARCHAR(20) DEFAULT 'medium',
  default_assignee_id UUID,
  default_tags TEXT[] DEFAULT '{}',
  default_effort_estimate DECIMAL(5,1) DEFAULT 0,
  default_budget DECIMAL(12,2) DEFAULT 0,
  checklist_template JSONB DEFAULT '[]',
  subtasks_template JSONB DEFAULT '[]',
  is_public BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_task_templates_tenant ON project_task_templates(tenant_id);

-- ============================================================
-- 5. Table: project_notifications (Inbox/Notifications)
-- ============================================================
CREATE TABLE IF NOT EXISTS project_notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  recipient_id UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  task_id UUID REFERENCES project_tasks(id) ON DELETE CASCADE,
  project_id UUID REFERENCES projects(id) ON DELETE SET NULL,
  notification_type VARCHAR(50) NOT NULL,
  title VARCHAR(255) NOT NULL,
  message TEXT,
  is_read BOOLEAN DEFAULT false,
  action_url VARCHAR(500),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_notifications_recipient ON project_notifications(recipient_id);
CREATE INDEX IF NOT EXISTS idx_notifications_tenant ON project_notifications(tenant_id);
CREATE INDEX IF NOT EXISTS idx_notifications_unread ON project_notifications(recipient_id, is_read);
CREATE INDEX IF NOT EXISTS idx_notifications_created ON project_notifications(created_at DESC);

-- ============================================================
-- 6. RLS Policies
-- ============================================================
ALTER TABLE project_time_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE project_task_watchers ENABLE ROW LEVEL SECURITY;
ALTER TABLE project_activity_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE project_task_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE project_notifications ENABLE ROW LEVEL SECURITY;

-- project_time_entries policies
DO $$ BEGIN
  CREATE POLICY tenant_select_time_entries ON project_time_entries FOR SELECT USING (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'select policy: %', SQLERRM; END $$;
DO $$ BEGIN
  CREATE POLICY tenant_insert_time_entries ON project_time_entries FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'insert policy: %', SQLERRM; END $$;
DO $$ BEGIN
  CREATE POLICY tenant_update_time_entries ON project_time_entries FOR UPDATE USING (tenant_id = current_tenant_id()) WITH CHECK (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'update policy: %', SQLERRM; END $$;
DO $$ BEGIN
  CREATE POLICY tenant_delete_time_entries ON project_time_entries FOR DELETE USING (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'delete policy: %', SQLERRM; END $$;

-- project_task_watchers policies
DO $$ BEGIN
  CREATE POLICY tenant_select_watchers ON project_task_watchers FOR SELECT USING (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'select policy: %', SQLERRM; END $$;
DO $$ BEGIN
  CREATE POLICY tenant_insert_watchers ON project_task_watchers FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'insert policy: %', SQLERRM; END $$;
DO $$ BEGIN
  CREATE POLICY tenant_delete_watchers ON project_task_watchers FOR DELETE USING (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'delete policy: %', SQLERRM; END $$;

-- project_activity_log policies
DO $$ BEGIN
  CREATE POLICY tenant_select_activity ON project_activity_log FOR SELECT USING (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'select policy: %', SQLERRM; END $$;
DO $$ BEGIN
  CREATE POLICY tenant_insert_activity ON project_activity_log FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'insert policy: %', SQLERRM; END $$;
DO $$ BEGIN
  CREATE POLICY tenant_delete_activity ON project_activity_log FOR DELETE USING (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'delete policy: %', SQLERRM; END $$;

-- project_task_templates policies
DO $$ BEGIN
  CREATE POLICY tenant_select_templates ON project_task_templates FOR SELECT USING (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'select policy: %', SQLERRM; END $$;
DO $$ BEGIN
  CREATE POLICY tenant_insert_templates ON project_task_templates FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'insert policy: %', SQLERRM; END $$;
DO $$ BEGIN
  CREATE POLICY tenant_update_templates ON project_task_templates FOR UPDATE USING (tenant_id = current_tenant_id()) WITH CHECK (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'update policy: %', SQLERRM; END $$;
DO $$ BEGIN
  CREATE POLICY tenant_delete_templates ON project_task_templates FOR DELETE USING (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'delete policy: %', SQLERRM; END $$;

-- project_notifications policies
DO $$ BEGIN
  CREATE POLICY tenant_select_notifications ON project_notifications FOR SELECT USING (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'select policy: %', SQLERRM; END $$;
DO $$ BEGIN
  CREATE POLICY tenant_insert_notifications ON project_notifications FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'insert policy: %', SQLERRM; END $$;
DO $$ BEGIN
  CREATE POLICY tenant_update_notifications ON project_notifications FOR UPDATE USING (tenant_id = current_tenant_id()) WITH CHECK (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'update policy: %', SQLERRM; END $$;
DO $$ BEGIN
  CREATE POLICY tenant_delete_notifications ON project_notifications FOR DELETE USING (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'delete policy: %', SQLERRM; END $$;

-- ============================================================
-- 7. Triggers for updated_at
-- ============================================================
DROP TRIGGER IF EXISTS project_time_entries_updated_at ON project_time_entries;
CREATE TRIGGER project_time_entries_updated_at BEFORE UPDATE ON project_time_entries FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
DROP TRIGGER IF EXISTS project_task_templates_updated_at ON project_task_templates;
CREATE TRIGGER project_task_templates_updated_at BEFORE UPDATE ON project_task_templates FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================
-- 8. Trigger: Auto-log activity on task update
-- ============================================================
CREATE OR REPLACE FUNCTION log_task_activity()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO project_activity_log (tenant_id, task_id, project_id, user_name, action_type, old_value, new_value, description)
  VALUES (
    NEW.tenant_id,
    NEW.id,
    NEW.project_id,
    current_setting('app.user_name', true),
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

DROP TRIGGER IF EXISTS project_tasks_activity_log ON project_tasks;
CREATE TRIGGER project_tasks_activity_log AFTER UPDATE ON project_tasks FOR EACH ROW EXECUTE FUNCTION log_task_activity();

-- ============================================================
-- 9. Trigger: Auto-log activity on task creation
-- ============================================================
CREATE OR REPLACE FUNCTION log_task_created()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO project_activity_log (tenant_id, task_id, project_id, user_name, action_type, description)
  VALUES (
    NEW.tenant_id,
    NEW.id,
    NEW.project_id,
    current_setting('app.user_name', true),
    'created',
    'Task created: ' || NEW.title
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS project_tasks_activity_created ON project_tasks;
CREATE TRIGGER project_tasks_activity_created AFTER INSERT ON project_tasks FOR EACH ROW EXECUTE FUNCTION log_task_created();
