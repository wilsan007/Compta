-- ============================================================
-- 160_remove_skip_cascade.sql
--
-- LOT7-06 : project_tasks._skip_cascade était posé à true puis remis à false
-- par les triggers de la migration 85, sans jamais être lu : chaque remontée
-- vers le parent faisait deux UPDATE au lieu d'un. La récursion vers les
-- ancêtres est voulue (avancement du grand-parent) et s'arrête d'elle-même
-- à la racine (parent_id NULL).
-- ============================================================
CREATE OR REPLACE FUNCTION public.recalc_parent_progress_on_subtask_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
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

  -- Mettre à jour le parent : la remontée continue vers les ancêtres et s'arrête à la racine
  UPDATE project_tasks
    SET progress = v_avg_progress,
        subtask_count = v_count,
        subtask_done_count = v_done_count,
        subtask_effective_hours = v_sub_effort,
        updated_at = now()
  WHERE id = v_parent_id;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.update_parent_status_on_subtasks_done()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
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
      SET status = 'done', is_closed = true, updated_at = now()
    WHERE id = v_parent_id;
  END IF;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.update_parent_status_on_subtask_started()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
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
      SET status = 'in_progress', updated_at = now()
    WHERE id = v_parent_id;
  END IF;

  RETURN NEW;
END;
$function$;

ALTER TABLE project_tasks DROP COLUMN IF EXISTS _skip_cascade;
