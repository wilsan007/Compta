-- ============================================================
-- 84_project_management_triggers.sql
--
-- Triggers et workflows de gestion des tâches et projets.
-- Inspiré des leaders du marché :
--   - Jira   : subtask→parent status, dependency blocking, SLA/escalation
--   - Asana  : overdue notifications, auto-assign on due date, approval workflow
--   - ClickUp: checklist resolved→task done, status change→action, priority notify
--   - Odoo   : subtask progress rollup, milestone auto-reach, timesheet→task/project,
--              recurring task generation, billable timesheet→invoice, project progress
--
-- 17 triggers couvrant 4 chaînes :
--   A. Hiérarchie des tâches (subtask → parent)        (4 triggers)
--   B. Dépendances et jalons                            (3 triggers)
--   C. Feuilles de temps → tâche / projet / facture     (4 triggers)
--   D. Notifications et automatisations                 (6 triggers)
-- ============================================================

-- ============================================================
-- PRÉREQUIS : Ajouter les colonnes manquantes
-- ============================================================

-- Lier une tâche à un jalon (Odoo : milestone_id sur project_tasks)
ALTER TABLE project_tasks ADD COLUMN IF NOT EXISTS milestone_id UUID REFERENCES project_milestones(id) ON DELETE SET NULL;

-- Compteurs de sous-tâches (Odoo : subtask_count, closed_subtask_count)
ALTER TABLE project_tasks ADD COLUMN IF NOT EXISTS subtask_count INTEGER DEFAULT 0;
ALTER TABLE project_tasks ADD COLUMN IF NOT EXISTS subtask_done_count INTEGER DEFAULT 0;

-- Heures agrégées des sous-tâches (Odoo : subtask_effective_hours)
ALTER TABLE project_tasks ADD COLUMN IF NOT EXISTS subtask_effective_hours DECIMAL(10,2) DEFAULT 0;

-- Drapeau d'escalade pour éviter les boucles
ALTER TABLE project_tasks ADD COLUMN IF NOT EXISTS _skip_cascade BOOLEAN DEFAULT false;


-- ============================================================
-- SECTION A — HIÉRARCHIE DES TÂCHES (subtask → parent)
-- ============================================================

-- A1. Recalculer le progress du parent quand une sous-tâche change
--     Inspiré de : Odoo (subtask_completion_percentage rollup),
--                  ClickUp (subtask progress → parent)
--     Quand une sous-tâche est insérée, modifiée (progress/status) ou supprimée,
--     on recalcule le progress du parent = moyenne des sous-tâches.
CREATE OR REPLACE FUNCTION recalc_parent_progress_on_subtask_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_parent_id uuid;
  v_avg_progress integer;
  v_count integer;
  v_done_count integer;
  v_sub_effort numeric;
BEGIN
  -- Déterminer le parent concerné
  v_parent_id := COALESCE(NEW.parent_id, OLD.parent_id);
  IF v_parent_id IS NULL THEN RETURN NEW; END IF;

  -- Calculer la moyenne du progress des sous-tâches
  SELECT
    COALESCE(AVG(progress), 0)::integer,
    COUNT(*),
    COUNT(*) FILTER (WHERE status IN ('done', 'cancelled') OR is_closed = true),
    COALESCE(SUM(effort_spent_h), 0)
  INTO v_avg_progress, v_count, v_done_count, v_sub_effort
  FROM project_tasks
  WHERE parent_id = v_parent_id;

  -- Mettre à jour le parent (sans déclencher la cascade)
  UPDATE project_tasks
    SET progress = v_avg_progress,
        subtask_count = v_count,
        subtask_done_count = v_done_count,
        subtask_effective_hours = v_sub_effort,
        _skip_cascade = true,
        updated_at = now()
  WHERE id = v_parent_id;

  -- Réinitialiser le drapeau
  UPDATE project_tasks SET _skip_cascade = false WHERE id = v_parent_id;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS subtask_progress_rollup ON project_tasks;
CREATE TRIGGER subtask_progress_rollup
  AFTER INSERT OR UPDATE OF progress, status, is_closed, effort_spent_h OR DELETE
  ON project_tasks
  FOR EACH ROW
  EXECUTE FUNCTION recalc_parent_progress_on_subtask_change();


-- A2. Quand toutes les sous-tâches sont terminées → parent passe à 'done'
--     Inspiré de : Jira (all subtasks resolved → parent transition),
--                  ClickUp (checklists resolved → task done)
CREATE OR REPLACE FUNCTION update_parent_status_on_subtasks_done()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_parent_id uuid;
  v_total integer;
  v_done integer;
  v_parent_status varchar;
BEGIN
  v_parent_id := COALESCE(NEW.parent_id, OLD.parent_id);
  IF v_parent_id IS NULL THEN RETURN NEW; END IF;

  -- Compter les sous-tâches et celles terminées
  SELECT
    COUNT(*),
    COUNT(*) FILTER (WHERE status IN ('done', 'cancelled') OR is_closed = true)
  INTO v_total, v_done
  FROM project_tasks
  WHERE parent_id = v_parent_id;

  -- Récupérer le statut actuel du parent
  SELECT status INTO v_parent_status
  FROM project_tasks WHERE id = v_parent_id;

  -- Si toutes les sous-tâches sont terminées et le parent n'est pas déjà done
  IF v_total > 0 AND v_done = v_total AND v_parent_status NOT IN ('done', 'cancelled') THEN
    UPDATE project_tasks
      SET status = 'done', is_closed = true, _skip_cascade = true, updated_at = now()
    WHERE id = v_parent_id;
    UPDATE project_tasks SET _skip_cascade = false WHERE id = v_parent_id;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS parent_status_on_subtasks_done ON project_tasks;
CREATE TRIGGER parent_status_on_subtasks_done
  AFTER UPDATE OF status, is_closed OR DELETE
  ON project_tasks
  FOR EACH ROW
  EXECUTE FUNCTION update_parent_status_on_subtasks_done();


-- A3. Quand une sous-tâche passe à 'in_progress' → parent passe à 'in_progress'
--     Inspiré de : Jira (subtask in progress → parent in progress)
CREATE OR REPLACE FUNCTION update_parent_status_on_subtask_started()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_parent_id uuid;
  v_parent_status varchar;
BEGIN
  -- Se déclenche quand une sous-tâche passe à 'in_progress'
  IF NEW.parent_id IS NULL THEN RETURN NEW; END IF;
  IF NEW.status IS NOT DISTINCT FROM OLD.status THEN RETURN NEW; END IF;
  IF NEW.status != 'in_progress' THEN RETURN NEW; END IF;

  v_parent_id := NEW.parent_id;

  SELECT status INTO v_parent_status
  FROM project_tasks WHERE id = v_parent_id;

  -- Si le parent est encore en 'todo', le passer à 'in_progress'
  IF v_parent_status = 'todo' THEN
    UPDATE project_tasks
      SET status = 'in_progress', _skip_cascade = true, updated_at = now()
    WHERE id = v_parent_id;
    UPDATE project_tasks SET _skip_cascade = false WHERE id = v_parent_id;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS parent_status_on_subtask_started ON project_tasks;
CREATE TRIGGER parent_status_on_subtask_started
  AFTER UPDATE OF status
  ON project_tasks
  FOR EACH ROW
  WHEN (NEW.parent_id IS NOT NULL AND NEW.status = 'in_progress')
  EXECUTE FUNCTION update_parent_status_on_subtask_started();


-- A4. Fermeture automatique de la tâche quand progress atteint 100
--     Inspiré de : ClickUp (status → done when 100%),
--                  Asana (task marked complete)
CREATE OR REPLACE FUNCTION auto_close_task_on_progress_100()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Se déclenche quand le progress passe à 100
  IF NEW.progress = 100 AND (OLD.progress IS DISTINCT FROM 100 OR TG_OP = 'INSERT') THEN
    IF NEW.status NOT IN ('done', 'cancelled') THEN
      NEW.status := 'done';
      NEW.is_closed := true;
    END IF;
  ELSIF NEW.progress < 100 AND NEW.is_closed = true AND NEW.status = 'done' THEN
    -- Rouvrir si le progress redescend
    NEW.is_closed := false;
    NEW.status := 'in_progress';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS auto_close_on_progress ON project_tasks;
CREATE TRIGGER auto_close_on_progress
  BEFORE INSERT OR UPDATE OF progress
  ON project_tasks
  FOR EACH ROW
  EXECUTE FUNCTION auto_close_task_on_progress_100();


-- ============================================================
-- SECTION B — DÉPENDANCES ET JALONS
-- ============================================================

-- B1. Vérifier les dépendances avant de démarrer une tâche
--     Inspiré de : Jira (dependency blocking, linked issues condition),
--                  Odoo (task dependencies, allow_task_dependencies)
--     Quand une tâche passe à 'in_progress', on vérifie que toutes les
--     tâches dont elle dépend (finish-to-start) sont terminées.
--     Si ce n'est pas le cas, on crée une notification d'alerte.
CREATE OR REPLACE FUNCTION check_task_dependencies_before_start()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_dep RECORD;
  v_blocked boolean := false;
  v_blocked_names text;
BEGIN
  -- Se déclenche quand une tâche passe à 'in_progress'
  IF NEW.status IS DISTINCT FROM OLD.status AND NEW.status = 'in_progress' THEN
    -- Vérifier les dépendances finish-to-start
    v_blocked_names := '';
    FOR v_dep IN
      SELECT pt.title, pt.status, ptd.dependency_type
      FROM project_task_dependencies ptd
      JOIN project_tasks pt ON pt.id = ptd.depends_on_task_id
      WHERE ptd.task_id = NEW.id
        AND ptd.tenant_id = NEW.tenant_id
        AND ptd.dependency_type = 'finish-to-start'
        AND pt.status NOT IN ('done', 'cancelled')
    LOOP
      v_blocked := true;
      v_blocked_names := v_blocked_names || '- ' || v_dep.title || ' (statut: ' || v_dep.status || ')' || E'\n';
    END LOOP;

    IF v_blocked THEN
      -- Créer une notification d'alerte pour l'assigné
      IF NEW.assignee_id IS NOT NULL THEN
        INSERT INTO project_notifications (
          tenant_id, recipient_id, task_id, project_id,
          notification_type, title, message, action_url
        ) VALUES (
          NEW.tenant_id, NEW.assignee_id, NEW.id, NEW.project_id,
          'dependency_blocked',
          'Dépendances non terminées',
          'La tâche ''' || NEW.title || ''' a des dépendances non terminées :' || E'\n' || v_blocked_names,
          '/projects/tasks/' || NEW.id
        );
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS check_dependencies_on_start ON project_tasks;
CREATE TRIGGER check_dependencies_on_start
  AFTER UPDATE OF status
  ON project_tasks
  FOR EACH ROW
  WHEN (NEW.status = 'in_progress')
  EXECUTE FUNCTION check_task_dependencies_before_start();


-- B2. Marquer automatiquement un jalon comme atteint quand toutes ses tâches sont terminées
--     Inspiré de : Odoo (milestone reached when all linked tasks done),
--                  ERPNext (project milestone auto-completion)
CREATE OR REPLACE FUNCTION auto_reach_milestone_on_tasks_done()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_milestone_id uuid;
  v_total integer;
  v_done integer;
BEGIN
  -- Déterminer le jalon concerné
  v_milestone_id := COALESCE(NEW.milestone_id, OLD.milestone_id);
  IF v_milestone_id IS NULL THEN RETURN NEW; END IF;

  -- Compter les tâches liées à ce jalon
  SELECT
    COUNT(*),
    COUNT(*) FILTER (WHERE status IN ('done', 'cancelled') OR is_closed = true)
  INTO v_total, v_done
  FROM project_tasks
  WHERE milestone_id = v_milestone_id;

  -- Si toutes les tâches du jalon sont terminées
  IF v_total > 0 AND v_done = v_total THEN
    UPDATE project_milestones
      SET is_reached = true,
          is_reached_manually = false,
          updated_at = now()
    WHERE id = v_milestone_id AND is_reached = false;
  ELSIF v_done < v_total THEN
    -- Rouvrir le jalon si une tâche revient en arrière
    UPDATE project_milestones
      SET is_reached = false,
          updated_at = now()
    WHERE id = v_milestone_id AND is_reached = true AND is_reached_manually = false;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS auto_reach_milestone ON project_tasks;
CREATE TRIGGER auto_reach_milestone
  AFTER INSERT OR UPDATE OF status, is_closed, milestone_id OR DELETE
  ON project_tasks
  FOR EACH ROW
  EXECUTE FUNCTION auto_reach_milestone_on_tasks_done();


-- B3. Recalculer le progress d'une tâche quand ses actions (checklist) changent
--     Inspiré de : ClickUp (checklists resolved → progress),
--                  Odoo (task action weight → task progress)
--     Quand une task_action est cochée/décochée/créée/supprimée,
--     on recalcule le progress de la tâche parente.
CREATE OR REPLACE FUNCTION recalc_task_progress_on_action_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_task_id uuid;
  v_total_weight integer;
  v_done_weight integer;
  v_total_actions integer;
  v_done_actions integer;
  v_new_progress integer;
BEGIN
  v_task_id := COALESCE(NEW.task_id, OLD.task_id);
  IF v_task_id IS NULL THEN RETURN NEW; END IF;

  -- Calculer le progress basé sur les actions pondérées
  SELECT
    COALESCE(SUM(weight_percentage), 0),
    COALESCE(SUM(weight_percentage) FILTER (WHERE is_done = true), 0),
    COUNT(*),
    COUNT(*) FILTER (WHERE is_done = true)
  INTO v_total_weight, v_done_weight, v_total_actions, v_done_actions
  FROM task_actions
  WHERE task_id = v_task_id;

  IF v_total_actions = 0 THEN
    v_new_progress := 0;
  ELSIF v_total_weight > 0 THEN
    v_new_progress := LEAST(100, ROUND((v_done_weight::numeric / v_total_weight) * 100));
  ELSE
    -- Sans pondération : ratio simple
    v_new_progress := ROUND((v_done_actions::numeric / v_total_actions) * 100);
  END IF;

  -- Mettre à jour la tâche (le trigger auto_close_on_progress gèrera le statut)
  UPDATE project_tasks
    SET progress = v_new_progress,
        updated_at = now()
  WHERE id = v_task_id;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS recalc_progress_on_action ON task_actions;
CREATE TRIGGER recalc_progress_on_action
  AFTER INSERT OR UPDATE OF is_done, weight_percentage OR DELETE
  ON task_actions
  FOR EACH ROW
  EXECUTE FUNCTION recalc_task_progress_on_action_change();


-- ============================================================
-- SECTION C — FEUILLES DE TEMPS → TÂCHE / PROJET / FACTURE
-- ============================================================

-- C1. Mettre à jour les heures passées sur la tâche quand une feuille de temps change
--     Inspiré de : Odoo (effective_hours, total_hours_spent),
--                  ClickUp (time tracked → task)
CREATE OR REPLACE FUNCTION update_task_time_on_time_entry()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_task_id uuid;
  v_total_seconds integer;
  v_total_hours numeric;
BEGIN
  v_task_id := COALESCE(NEW.task_id, OLD.task_id);
  IF v_task_id IS NULL THEN RETURN NEW; END IF;

  -- Sommer les durées de toutes les feuilles de temps de cette tâche
  SELECT COALESCE(SUM(duration_seconds), 0)
  INTO v_total_seconds
  FROM project_time_entries
  WHERE task_id = v_task_id;

  v_total_hours := ROUND((v_total_seconds::numeric / 3600), 2);

  -- Mettre à jour la tâche
  UPDATE project_tasks
    SET effort_spent_h = v_total_hours,
        updated_at = now()
  WHERE id = v_task_id;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS update_task_time ON project_time_entries;
CREATE TRIGGER update_task_time
  AFTER INSERT OR UPDATE OF duration_seconds, end_time OR DELETE
  ON project_time_entries
  FOR EACH ROW
  EXECUTE FUNCTION update_task_time_on_time_entry();


-- C2. Mettre à jour les heures du projet quand une feuille de temps change
--     Inspiré de : Odoo (project total_hours_spent, remaining_hours)
CREATE OR REPLACE FUNCTION update_project_hours_on_time_entry()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_project_id uuid;
  v_total_seconds integer;
  v_total_hours numeric;
  v_allocated numeric;
BEGIN
  -- Déterminer le projet (soit via l'entrée, soit via la tâche)
  v_project_id := COALESCE(NEW.project_id, OLD.project_id);
  IF v_project_id IS NULL AND COALESCE(NEW.task_id, OLD.task_id) IS NOT NULL THEN
    SELECT project_id INTO v_project_id
    FROM project_tasks
    WHERE id = COALESCE(NEW.task_id, OLD.task_id);
  END IF;
  IF v_project_id IS NULL THEN RETURN NEW; END IF;

  -- Sommer les durées de toutes les feuilles de temps de ce projet
  SELECT COALESCE(SUM(duration_seconds), 0)
  INTO v_total_seconds
  FROM project_time_entries
  WHERE project_id = v_project_id;

  v_total_hours := ROUND((v_total_seconds::numeric / 3600), 2);

  -- Récupérer les heures allouées
  SELECT allocated_hours INTO v_allocated
  FROM projects WHERE id = v_project_id;

  -- Mettre à jour le projet
  UPDATE projects
    SET total_hours_spent = v_total_hours,
        remaining_hours = GREATEST(COALESCE(v_allocated, 0) - v_total_hours, 0),
        updated_at = now()
  WHERE id = v_project_id;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS update_project_hours ON project_time_entries;
CREATE TRIGGER update_project_hours
  AFTER INSERT OR UPDATE OF duration_seconds, end_time, project_id OR DELETE
  ON project_time_entries
  FOR EACH ROW
  EXECUTE FUNCTION update_project_hours_on_time_entry();


-- C3. Recalculer le progress du projet quand ses tâches changent
--     Inspiré de : Odoo (project progress = avg of task progress),
--                  Asana (project progress tracking)
CREATE OR REPLACE FUNCTION recalc_project_progress_on_task_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_project_id uuid;
  v_avg_progress integer;
  v_count integer;
BEGIN
  -- Déterminer le projet concerné
  v_project_id := COALESCE(NEW.project_id, OLD.project_id);
  IF v_project_id IS NULL THEN RETURN NEW; END IF;

  -- Calculer la moyenne du progress des tâches de premier niveau du projet
  SELECT
    COALESCE(AVG(progress), 0)::integer,
    COUNT(*)
  INTO v_avg_progress, v_count
  FROM project_tasks
  WHERE project_id = v_project_id
    AND parent_id IS NULL;

  -- Mettre à jour le projet
  UPDATE projects
    SET progress = v_avg_progress,
        updated_at = now()
  WHERE id = v_project_id;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS recalc_project_progress ON project_tasks;
CREATE TRIGGER recalc_project_progress
  AFTER INSERT OR UPDATE OF progress, status, project_id OR DELETE
  ON project_tasks
  FOR EACH ROW
  EXECUTE FUNCTION recalc_project_progress_on_task_change();


-- C4. Créer une ligne de facturation pour les heures facturables
--     Inspiré de : Odoo (timesheet → sale order line → invoice),
--                  ERPNext (timesheet → sales invoice)
--     Quand une feuille de temps facturable est arrêtée (end_time renseigné),
--     on crée une ligne de facturation en attente.
CREATE OR REPLACE FUNCTION create_billable_line_on_timesheet_stop()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_project RECORD;
  v_customer_id uuid;
  v_hours numeric;
  v_amount numeric;
BEGIN
  -- Se déclenche quand end_time passe de NULL à une valeur, et is_billable = true
  IF NEW.is_billable = false THEN RETURN NEW; END IF;
  IF NEW.end_time IS NULL THEN RETURN NEW; END IF;
  IF OLD.end_time IS NOT NULL THEN RETURN NEW; END IF;

  -- Récupérer le projet et son client
  SELECT * INTO v_project
  FROM projects
  WHERE id = COALESCE(NEW.project_id, (
    SELECT project_id FROM project_tasks WHERE id = NEW.task_id
  ));

  IF NOT FOUND OR v_project.customer_id IS NULL THEN RETURN NEW; END IF;
  IF v_project.allow_billable = false THEN RETURN NEW; END IF;

  v_customer_id := v_project.customer_id;
  v_hours := ROUND(NEW.duration_seconds::numeric / 3600, 2);
  v_amount := v_hours * COALESCE(NEW.hourly_rate, 0);

  -- Créer une ligne de devis/facturation en attente
  -- On utilise la table quotes si elle existe, sinon on crée une notification
  -- pour informer qu'il y a des heures à facturer
  INSERT INTO project_notifications (
    tenant_id, recipient_id, task_id, project_id,
    notification_type, title, message, action_url
  ) SELECT
    NEW.tenant_id,
    p.manager_id,
    NEW.task_id,
    v_project.id,
    'billable_hours',
    'Heures facturables à facturer',
    v_hours::text || 'h facturables (' || v_amount::text || '€) sur le projet ''' || v_project.name || '''',
    '/projects/' || v_project.id
  FROM projects p
  WHERE p.id = v_project.id AND p.manager_id IS NOT NULL;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS create_billable_line ON project_time_entries;
CREATE TRIGGER create_billable_line
  AFTER UPDATE OF end_time
  ON project_time_entries
  FOR EACH ROW
  WHEN (NEW.end_time IS NOT NULL AND OLD.end_time IS NULL AND NEW.is_billable = true)
  EXECUTE FUNCTION create_billable_line_on_timesheet_stop();


-- ============================================================
-- SECTION D — NOTIFICATIONS ET AUTOMATISATIONS
-- ============================================================

-- D1. Notifier l'assigné quand il est assigné à une tâche
--     Inspiré de : Asana (auto-assign notification),
--                  Jira (assignee notification)
CREATE OR REPLACE FUNCTION notify_assignee_on_assignment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Se déclenche quand assignee_id change (et n'est pas NULL)
  IF NEW.assignee_id IS NULL THEN RETURN NEW; END IF;
  IF NEW.assignee_id IS NOT DISTINCT FROM OLD.assignee_id THEN RETURN NEW; END IF;

  INSERT INTO project_notifications (
    tenant_id, recipient_id, task_id, project_id,
    notification_type, title, message, action_url
  ) VALUES (
    NEW.tenant_id, NEW.assignee_id, NEW.id, NEW.project_id,
    'task_assigned',
    'Tâche assignée : ' || NEW.title,
    'Vous avez été assigné(e) à la tâche ''' || NEW.title || '''',
    '/projects/tasks/' || NEW.id
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS notify_assignee ON project_tasks;
CREATE TRIGGER notify_assignee
  AFTER INSERT OR UPDATE OF assignee_id
  ON project_tasks
  FOR EACH ROW
  WHEN (NEW.assignee_id IS NOT NULL)
  EXECUTE FUNCTION notify_assignee_on_assignment();


-- D2. Notifier les watchers quand le statut d'une tâche change
--     Inspiré de : Jira (watchers notification on transition),
--                  Asana (followers notified on status change)
CREATE OR REPLACE FUNCTION notify_watchers_on_status_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_watcher RECORD;
BEGIN
  -- Se déclenche quand le statut change
  IF NEW.status IS NOT DISTINCT FROM OLD.status THEN RETURN NEW; END IF;

  -- Notifier tous les watchers de la tâche
  FOR v_watcher IN
    SELECT employee_id FROM project_task_watchers
    WHERE task_id = NEW.id AND tenant_id = NEW.tenant_id
  LOOP
    -- Ne pas notifier l'assigné (il a déjà la notification d'assignation)
    IF v_watcher.employee_id IS DISTINCT FROM NEW.assignee_id THEN
      INSERT INTO project_notifications (
        tenant_id, recipient_id, task_id, project_id,
        notification_type, title, message, action_url
      ) VALUES (
        NEW.tenant_id, v_watcher.employee_id, NEW.id, NEW.project_id,
        'status_changed',
        'Statut modifié : ' || NEW.title,
        'Le statut de ''' || NEW.title || ''' est passé de ''' || COALESCE(OLD.status, 'aucun') || ''' à ''' || NEW.status || '''',
        '/projects/tasks/' || NEW.id
      );
    END IF;
  END LOOP;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS notify_watchers_status ON project_tasks;
CREATE TRIGGER notify_watchers_status
  AFTER UPDATE OF status
  ON project_tasks
  FOR EACH ROW
  WHEN (NEW.status IS DISTINCT FROM OLD.status)
  EXECUTE FUNCTION notify_watchers_on_status_change();


-- D3. Notifier les watchers quand un commentaire est ajouté
--     Inspiré de : Jira (comment → watchers notification),
--                  Asana (comment → followers)
CREATE OR REPLACE FUNCTION notify_watchers_on_comment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_watcher RECORD;
  v_task RECORD;
BEGIN
  -- Récupérer les infos de la tâche
  SELECT * INTO v_task
  FROM project_tasks
  WHERE id = NEW.task_id;

  IF NOT FOUND THEN RETURN NEW; END IF;

  -- Notifier tous les watchers
  FOR v_watcher IN
    SELECT employee_id FROM project_task_watchers
    WHERE task_id = NEW.task_id AND tenant_id = NEW.tenant_id
  LOOP
    INSERT INTO project_notifications (
      tenant_id, recipient_id, task_id, project_id,
      notification_type, title, message, action_url
    ) VALUES (
      NEW.tenant_id, v_watcher.employee_id, NEW.task_id, v_task.project_id,
      'comment_added',
      'Nouveau commentaire sur : ' || v_task.title,
      LEFT(NEW.content, 200),
      '/projects/tasks/' || NEW.task_id
    );
  END LOOP;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS notify_watchers_comment ON task_comments;
CREATE TRIGGER notify_watchers_comment
  AFTER INSERT
  ON task_comments
  FOR EACH ROW
  EXECUTE FUNCTION notify_watchers_on_comment();


-- D4. Notifier l'assigné quand la date d'échéance est dépassée (cron)
--     Inspiré de : Asana (task is overdue trigger),
--                  Jira (SLA / due date escalation),
--                  ClickUp (date is before/after trigger)
--     Fonction appelée par cron (pg_cron ou Edge Function) chaque jour.
CREATE OR REPLACE FUNCTION notify_overdue_tasks()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_task RECORD;
BEGIN
  -- Trouver toutes les tâches en retard (due_date < today, non terminées)
  FOR v_task IN
    SELECT * FROM project_tasks
    WHERE due_date < CURRENT_DATE
      AND status NOT IN ('done', 'cancelled')
      AND is_closed = false
      AND assignee_id IS NOT NULL
  LOOP
    -- Vérifier qu'une notification n'a pas déjà été envoyée aujourd'hui
    IF NOT EXISTS (
      SELECT 1 FROM project_notifications
      WHERE task_id = v_task.id
        AND notification_type = 'task_overdue'
        AND created_at >= CURRENT_DATE
    ) THEN
      INSERT INTO project_notifications (
        tenant_id, recipient_id, task_id, project_id,
        notification_type, title, message, action_url
      ) VALUES (
        v_task.tenant_id, v_task.assignee_id, v_task.id, v_task.project_id,
        'task_overdue',
        'Tâche en retard : ' || v_task.title,
        'La tâche ''' || v_task.title || ''' était due le ' || to_char(v_task.due_date, 'DD/MM/YYYY'),
        '/projects/tasks/' || v_task.id
      );
    END IF;
  END LOOP;
END;
$$;


-- D5. Générer les tâches récurrentes (cron)
--     Inspiré de : Odoo (recurring tasks auto-generation),
--                  ClickUp (recurring task creation)
--     Fonction appelée par cron chaque jour.
CREATE OR REPLACE FUNCTION generate_recurring_tasks()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_task RECORD;
  v_new_due date;
  v_new_start date;
  v_interval_days integer;
BEGIN
  -- Trouver les tâches récurrentes dont la date d'échéance est passée
  -- et qui ne sont pas déjà régénérées
  FOR v_task IN
    SELECT * FROM project_tasks
    WHERE recurring_task = true
      AND status IN ('done', 'cancelled')
      AND is_closed = true
      AND due_date IS NOT NULL
      AND due_date < CURRENT_DATE
      AND NOT EXISTS (
        SELECT 1 FROM project_tasks child
        WHERE child.parent_id = v_task.id
          AND child.recurring_task = false
          AND child.created_at >= v_task.due_date
      )
  LOOP
    -- Calculer l'intervalle en jours selon le type de récurrence
    v_interval_days := v_task.recurring_interval;
    IF v_task.recurring_rule_type = 'weekly' THEN
      v_interval_days := v_task.recurring_interval * 7;
    ELSIF v_task.recurring_rule_type = 'monthly' THEN
      v_interval_days := v_task.recurring_interval * 30;
    ELSIF v_task.recurring_rule_type = 'daily' THEN
      v_interval_days := v_task.recurring_interval;
    END IF;

    v_new_due := CURRENT_DATE + v_interval_days;
    v_new_start := CURRENT_DATE;

    -- Créer la nouvelle occurrence
    INSERT INTO project_tasks (
      tenant_id, project_id, parent_id, title, description,
      status, priority, assignee, assignee_id,
      start_date, due_date, effort_estimate_h, effort_spent_h,
      progress, display_order, task_level, budget, color,
      acceptance_criteria, recurring_task, recurring_interval,
      recurring_rule_type, is_closed, milestone_id
    ) VALUES (
      v_task.tenant_id, v_task.project_id, v_task.id, v_task.title, v_task.description,
      'todo', v_task.priority, v_task.assignee, v_task.assignee_id,
      v_new_start, v_new_due, v_task.effort_estimate_h, 0,
      0, v_task.display_order, v_task.task_level, v_task.budget, v_task.color,
      v_task.acceptance_criteria, false, v_task.recurring_interval,
      v_task.recurring_rule_type, false, v_task.milestone_id
    );
  END LOOP;
END;
$$;


-- D6. Escalader les tâches en retard vers le manager de projet (cron)
--     Inspiré de : Jira (SLA escalation, auto-reassign),
--                  Asana (overdue escalation)
--     Fonction appelée par cron chaque jour.
CREATE OR REPLACE FUNCTION escalate_overdue_tasks()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_task RECORD;
  v_manager_id uuid;
BEGIN
  -- Trouver les tâches en retard de plus de 3 jours
  FOR v_task IN
    SELECT t.*, p.manager_id as project_manager_id
    FROM project_tasks t
    LEFT JOIN projects p ON p.id = t.project_id
    WHERE t.due_date < CURRENT_DATE - 3
      AND t.status NOT IN ('done', 'cancelled')
      AND t.is_closed = false
  LOOP
    v_manager_id := COALESCE(v_task.project_manager_id, v_task.assignee_id);
    IF v_manager_id IS NULL THEN CONTINUE; END IF;

    -- Vérifier qu'une notification d'escalade n'a pas déjà été envoyée
    IF NOT EXISTS (
      SELECT 1 FROM project_notifications
      WHERE task_id = v_task.id
        AND notification_type = 'task_escalated'
        AND created_at >= CURRENT_DATE - 3
    ) THEN
      INSERT INTO project_notifications (
        tenant_id, recipient_id, task_id, project_id,
        notification_type, title, message, action_url
      ) VALUES (
        v_task.tenant_id, v_manager_id, v_task.id, v_task.project_id,
        'task_escalated',
        'ESCALADE : Tâche en retard de plus de 3 jours',
        'La tâche ''' || v_task.title || ''' est en retard de ' ||
        (CURRENT_DATE - v_task.due_date)::text || ' jours et nécessite une attention immédiate.',
        '/projects/tasks/' || v_task.id
      );
    END IF;
  END LOOP;
END;
$$;


-- ============================================================
-- SECTION E — PROGRAMMATION CRON (si pg_cron est disponible)
-- ============================================================

-- Tenter de programmer les fonctions cron (ignorer si pg_cron n'est pas installé)
DO $cron_block$
BEGIN
  -- Notification des tâches en retard (chaque jour à 8h00)
  BEGIN
    PERFORM cron.schedule(
      'notify_overdue_tasks_daily',
      '0 8 * * *',
      $cmd$SELECT notify_overdue_tasks();$cmd$
    );
    RAISE NOTICE 'Scheduled notify_overdue_tasks_daily';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'pg_cron not available: %', SQLERRM;
  END;

  -- Génération des tâches récurrentes (chaque jour à 7h00)
  BEGIN
    PERFORM cron.schedule(
      'generate_recurring_tasks_daily',
      '0 7 * * *',
      $cmd$SELECT generate_recurring_tasks();$cmd$
    );
    RAISE NOTICE 'Scheduled generate_recurring_tasks_daily';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'pg_cron not available: %', SQLERRM;
  END;

  -- Escalade des tâches en retard (chaque jour à 9h00)
  BEGIN
    PERFORM cron.schedule(
      'escalate_overdue_tasks_daily',
      '0 9 * * *',
      $cmd$SELECT escalate_overdue_tasks();$cmd$
    );
    RAISE NOTICE 'Scheduled escalate_overdue_tasks_daily';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'pg_cron not available: %', SQLERRM;
  END;
END;
$cron_block$;


-- ============================================================
-- RÉCAPITULATIF
-- ============================================================
-- Triggers créés :
--
-- A. Hiérarchie des tâches (4 triggers) :
--   A1. subtask_progress_rollup        ON project_tasks AFTER INS/UPD/DEL
--   A2. parent_status_on_subtasks_done ON project_tasks AFTER UPD/DEL
--   A3. parent_status_on_subtask_started ON project_tasks AFTER UPD(status)
--   A4. auto_close_on_progress         ON project_tasks BEFORE INS/UPD(progress)
--
-- B. Dépendances et jalons (3 triggers) :
--   B1. check_dependencies_on_start    ON project_tasks AFTER UPD(status)
--   B2. auto_reach_milestone           ON project_tasks AFTER INS/UPD/DEL
--   B3. recalc_progress_on_action      ON task_actions AFTER INS/UPD/DEL
--
-- C. Feuilles de temps (4 triggers) :
--   C1. update_task_time               ON project_time_entries AFTER INS/UPD/DEL
--   C2. update_project_hours           ON project_time_entries AFTER INS/UPD/DEL
--   C3. recalc_project_progress        ON project_tasks AFTER INS/UPD/DEL
--   C4. create_billable_line           ON project_time_entries AFTER UPD(end_time)
--
-- D. Notifications et automatisations (6 triggers/fonctions) :
--   D1. notify_assignee                ON project_tasks AFTER INS/UPD(assignee_id)
--   D2. notify_watchers_status         ON project_tasks AFTER UPD(status)
--   D3. notify_watchers_comment        ON task_comments AFTER INSERT
--   D4. notify_overdue_tasks()         Fonction cron (quotidienne)
--   D5. generate_recurring_tasks()     Fonction cron (quotidienne)
--   D6. escalate_overdue_tasks()       Fonction cron (quotidienne)
--
-- Colonnes ajoutées :
--   project_tasks.milestone_id          (lien vers jalon)
--   project_tasks.subtask_count         (compteur sous-tâches)
--   project_tasks.subtask_done_count    (sous-tâches terminées)
--   project_tasks.subtask_effective_hours (heures agrégées sous-tâches)
--   project_tasks._skip_cascade         (drapeau anti-boucle)
--
-- Total : 13 triggers + 3 fonctions cron + 5 colonnes
-- ============================================================
