-- ============================================================
-- 800 — Gestion de projets : UN vocabulaire de statut, un TAUX de réalisation
--       par action, et UN calcul d'avancement des tâches
--
-- Mesuré sur base neuve (437 migrations) le 24/10/2026 :
--
--   1. Deux vocabulaires de statut pour la même colonne. L'écran écrit `doing`
--      et `canceled` ; les douze fonctions de la base qui lisent
--      `project_tasks.status` comparent `in_progress` et `cancelled` (et
--      l'amorce écrit `completed`). Conséquences : le contrôle des dépendances
--      au démarrage (`check_task_dependencies_before_start`, WHEN status =
--      'in_progress') ne s'est JAMAIS déclenché depuis l'écran ; une sous-tâche
--      annulée depuis l'écran n'était pas comptée « terminée » ; et la
--      réouverture automatique d'une tâche (`auto_close_task_on_progress_100`)
--      écrivait `in_progress`, que l'écran ne sait pas afficher.
--      → La base garde SON vocabulaire (12 fonctions, des suites qui l'assertent)
--        et le normalise à l'entrée : `doing` → `in_progress`, `canceled` →
--        `cancelled`, `completed` → `done`. L'écran traduit à sa frontière
--        (`lib/taskStatus.ts`). Pas de CHECK : `calculate_project_profitability`
--        et `evaluate_business_alert_rules` comparent encore `completed`, et
--        une contrainte rendrait ces branches mortes (porte G :
--        check_trigger_reachability).
--
--   2. Une action était faite ou pas (`is_done`). Le tableau saisit désormais
--      un TAUX de réalisation (0–100) ; cocher vaut 100, décocher vaut 0, et
--      un taux de 100 coche l'action. Les deux colonnes restent cohérentes
--      par un déclencheur, pour les écrans et les appels qui n'écrivent que
--      l'une des deux.
--
--   3. Deux déclencheurs écrivaient `project_tasks.progress` de la même tâche
--      avec deux règles : les actions (`recalc_task_progress_on_action_change`)
--      et les sous-tâches (`recalc_parent_progress_on_subtask_change`). Une
--      tâche qui a les deux prenait la valeur du DERNIER qui écrivait.
--      → Une seule fonction, `pm_task_progress`, une seule règle :
--        * chaque ACTION pèse son `weight_percentage` (toutes à 0 : à parts
--          égales) et avance de son taux ;
--        * chaque SOUS-TÂCHE non liée à une action pèse sa charge
--          (`progress_weight`, la règle de la 303) et avance de sa progression ;
--          une sous-tâche ANNULÉE ne compte plus (elle bloquait le 100 %) ;
--        * une sous-tâche LIÉE à une action (`linked_action_id`) n'est pas
--          comptée deux fois : elle donne son taux à l'action ;
--        * quand une tâche a les deux, le bloc des actions compte pour autant
--          de parts qu'il a d'actions, et chaque sous-tâche non liée pour une
--          part ;
--        * sans action ni sous-tâche, la progression saisie à la main est
--          conservée (elle n'est plus remise à 0).
--      Toutes les actions à 100 % ⇒ la tâche à 100 % ⇒ elle remonte à sa mère
--      et au projet (déclencheurs existants, 303), qui excluent aussi les
--      annulées.
-- ============================================================

-- ---------------------------------------------------------------- 1. statuts
CREATE OR REPLACE FUNCTION public.pm_normalise_statut_tache()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
BEGIN
  NEW.status := CASE NEW.status
    WHEN 'doing' THEN 'in_progress'
    WHEN 'canceled' THEN 'cancelled'
    WHEN 'completed' THEN 'done'
    ELSE NEW.status
  END;
  RETURN NEW;
END $$;

-- « aa_ » : les déclencheurs BEFORE s'exécutent dans l'ordre alphabétique ;
-- celui-ci passe avant `auto_close_on_progress` et les gardes de statut.
DROP TRIGGER IF EXISTS aa_pm_normalise_statut ON public.project_tasks;
CREATE TRIGGER aa_pm_normalise_statut
  BEFORE INSERT OR UPDATE OF status ON public.project_tasks
  FOR EACH ROW EXECUTE FUNCTION public.pm_normalise_statut_tache();

-- Reprise : les lignes déjà écrites dans l'autre vocabulaire. Les avis aux
-- observateurs et le journal d'activité sont suspendus le temps de la reprise :
-- ce n'est pas un changement de statut, c'est le même statut mieux écrit.
DO $$
DECLARE trg text;
BEGIN
  FOREACH trg IN ARRAY ARRAY['notify_watchers_status', 'project_tasks_activity_log'] LOOP
    IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'public.project_tasks'::regclass AND tgname = trg) THEN
      EXECUTE format('ALTER TABLE public.project_tasks DISABLE TRIGGER %I', trg);
    END IF;
  END LOOP;
  UPDATE public.project_tasks SET status = status WHERE status IN ('doing', 'canceled', 'completed');
  FOREACH trg IN ARRAY ARRAY['notify_watchers_status', 'project_tasks_activity_log'] LOOP
    IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'public.project_tasks'::regclass AND tgname = trg) THEN
      EXECUTE format('ALTER TABLE public.project_tasks ENABLE TRIGGER %I', trg);
    END IF;
  END LOOP;
END $$;

-- ------------------------------------------------- 2. taux de réalisation d'une action
ALTER TABLE public.task_actions ADD COLUMN IF NOT EXISTS progress integer NOT NULL DEFAULT 0;
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'task_actions_progress_range') THEN
    ALTER TABLE public.task_actions
      ADD CONSTRAINT task_actions_progress_range CHECK (progress BETWEEN 0 AND 100);
  END IF;
END $$;
UPDATE public.task_actions SET progress = 100 WHERE is_done AND progress <> 100;

CREATE OR REPLACE FUNCTION public.pm_sync_action_done()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.is_done AND NEW.progress < 100 THEN
      NEW.progress := 100;                 -- créée cochée
    ELSE
      NEW.is_done := (NEW.progress = 100);
    END IF;
  ELSIF NEW.is_done IS DISTINCT FROM OLD.is_done AND NEW.progress IS NOT DISTINCT FROM OLD.progress THEN
    NEW.progress := CASE WHEN NEW.is_done THEN 100 ELSE 0 END;   -- on a coché / décoché
  ELSE
    NEW.is_done := (NEW.progress = 100);                         -- on a saisi un taux
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS aa_pm_sync_action_done ON public.task_actions;
CREATE TRIGGER aa_pm_sync_action_done
  BEFORE INSERT OR UPDATE OF is_done, progress ON public.task_actions
  FOR EACH ROW EXECUTE FUNCTION public.pm_sync_action_done();

-- ------------------------------------------------- 3. un seul calcul d'avancement
-- NULL = la tâche n'a ni action ni sous-tâche comptée : sa progression est saisie.
CREATE OR REPLACE FUNCTION public.pm_task_progress(p_task uuid, p_tenant uuid)
RETURNS integer LANGUAGE plpgsql STABLE SET search_path = public, pg_temp AS $$
DECLARE
  n_act integer; sum_w numeric; sum_wp numeric; p_act numeric;
  n_sub integer; sub_w numeric; sub_wp numeric; p_sub numeric;
BEGIN
  SELECT count(*), COALESCE(sum(weight_percentage), 0), COALESCE(sum(weight_percentage * progress), 0)
    INTO n_act, sum_w, sum_wp
    FROM task_actions WHERE task_id = p_task AND tenant_id = p_tenant;
  IF n_act > 0 THEN
    IF sum_w > 0 THEN
      p_act := sum_wp / sum_w;
    ELSE
      SELECT avg(progress) INTO p_act FROM task_actions WHERE task_id = p_task AND tenant_id = p_tenant;
    END IF;
  END IF;

  SELECT count(*),
         COALESCE(sum(progress_weight(t.effort_estimate_h, t.effort_spent_h)), 0),
         COALESCE(sum(t.progress * progress_weight(t.effort_estimate_h, t.effort_spent_h)), 0)
    INTO n_sub, sub_w, sub_wp
    FROM project_tasks t
   WHERE t.parent_id = p_task AND t.tenant_id = p_tenant
     AND t.status IS DISTINCT FROM 'cancelled'
     AND NOT EXISTS (SELECT 1 FROM task_actions a
                      WHERE a.id = t.linked_action_id AND a.task_id = p_task AND a.tenant_id = p_tenant);
  IF n_sub > 0 THEN p_sub := sub_wp / NULLIF(sub_w, 0); END IF;

  IF n_act > 0 AND n_sub > 0 THEN
    RETURN round((n_act * p_act + n_sub * COALESCE(p_sub, 0)) / (n_act + n_sub))::integer;
  ELSIF n_act > 0 THEN
    RETURN round(p_act)::integer;
  ELSIF n_sub > 0 THEN
    RETURN round(COALESCE(p_sub, 0))::integer;
  END IF;
  RETURN NULL;
END $$;

CREATE OR REPLACE FUNCTION public.pm_recalc_task_progress(p_task uuid, p_tenant uuid)
RETURNS void LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
DECLARE v integer;
BEGIN
  IF p_task IS NULL OR p_tenant IS NULL THEN RETURN; END IF;
  v := pm_task_progress(p_task, p_tenant);
  IF v IS NULL THEN RETURN; END IF;
  UPDATE project_tasks SET progress = v, updated_at = now()
   WHERE id = p_task AND tenant_id = p_tenant AND progress IS DISTINCT FROM v;
END $$;

REVOKE ALL ON FUNCTION public.pm_task_progress(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.pm_recalc_task_progress(uuid, uuid) FROM PUBLIC, anon, authenticated;

-- Actions → tâche
CREATE OR REPLACE FUNCTION public.recalc_task_progress_on_action_change()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF TG_OP = 'DELETE' OR (TG_OP = 'UPDATE' AND NEW.task_id IS DISTINCT FROM OLD.task_id) THEN
    PERFORM pm_recalc_task_progress(OLD.task_id, OLD.tenant_id);   -- la tâche quittée
  END IF;
  IF TG_OP <> 'DELETE' THEN
    PERFORM pm_recalc_task_progress(NEW.task_id, NEW.tenant_id);
  END IF;
  RETURN COALESCE(NEW, OLD);
END $$;

DROP TRIGGER IF EXISTS recalc_progress_on_action ON public.task_actions;
CREATE TRIGGER recalc_progress_on_action
  AFTER INSERT OR DELETE OR UPDATE OF is_done, progress, weight_percentage, task_id ON public.task_actions
  FOR EACH ROW EXECUTE FUNCTION public.recalc_task_progress_on_action_change();

-- Sous-tâches → tâche mère (compteurs conservés : subtask_count, subtask_done_count,
-- subtask_effective_hours sont lus par l'écran). Une sous-tâche liée à une action
-- donne sa progression à l'action, qui fait remonter la mère.
CREATE OR REPLACE FUNCTION public.recalc_parent_progress_on_subtask_change()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_parent_id uuid := COALESCE(NEW.parent_id, OLD.parent_id);
  v_tenant uuid := COALESCE(NEW.tenant_id, OLD.tenant_id);
BEGIN
  IF TG_OP <> 'DELETE' AND NEW.linked_action_id IS NOT NULL
     AND (TG_OP = 'INSERT' OR NEW.progress IS DISTINCT FROM OLD.progress) THEN
    UPDATE task_actions SET progress = NEW.progress
     WHERE id = NEW.linked_action_id AND tenant_id = v_tenant AND progress IS DISTINCT FROM NEW.progress;
  END IF;

  IF v_parent_id IS NULL THEN RETURN COALESCE(NEW, OLD); END IF;

  UPDATE project_tasks p
     SET subtask_count = s.n, subtask_done_count = s.done, subtask_effective_hours = s.spent
    FROM (SELECT count(*) AS n,
                 count(*) FILTER (WHERE t.status IN ('done', 'cancelled') OR t.is_closed = true) AS done,
                 COALESCE(sum(t.effort_spent_h), 0) AS spent
            FROM project_tasks t WHERE t.parent_id = v_parent_id AND t.tenant_id = v_tenant) s
   WHERE p.id = v_parent_id AND p.tenant_id = v_tenant
     AND (p.subtask_count, p.subtask_done_count, p.subtask_effective_hours)
         IS DISTINCT FROM (s.n, s.done, s.spent);

  PERFORM pm_recalc_task_progress(v_parent_id, v_tenant);
  -- une sous-tâche qui change de mère : l'ancienne mère aussi
  IF TG_OP = 'UPDATE' AND OLD.parent_id IS DISTINCT FROM NEW.parent_id AND OLD.parent_id IS NOT NULL THEN
    PERFORM pm_recalc_task_progress(OLD.parent_id, v_tenant);
  END IF;
  RETURN COALESCE(NEW, OLD);
END $$;

DROP TRIGGER IF EXISTS subtask_progress_rollup ON public.project_tasks;
CREATE TRIGGER subtask_progress_rollup
  AFTER INSERT OR DELETE OR UPDATE OF progress, status, is_closed, effort_spent_h, effort_estimate_h, parent_id, linked_action_id
  ON public.project_tasks
  FOR EACH ROW EXECUTE FUNCTION public.recalc_parent_progress_on_subtask_change();

-- Tâches → projet : les annulées ne bloquent plus le 100 %, et une tâche qui
-- change de projet fait recalculer les DEUX projets.
CREATE OR REPLACE FUNCTION public.pm_recalc_project_progress(p_project uuid, p_tenant uuid)
RETURNS void LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
DECLARE v integer;
BEGIN
  IF p_project IS NULL OR p_tenant IS NULL THEN RETURN; END IF;
  SELECT COALESCE(round(sum(t.progress * progress_weight(t.effort_estimate_h, t.effort_spent_h))
                        / NULLIF(sum(progress_weight(t.effort_estimate_h, t.effort_spent_h)), 0)), 0)::integer
    INTO v
    FROM project_tasks t
   WHERE t.project_id = p_project AND t.parent_id IS NULL AND t.tenant_id = p_tenant
     AND t.status IS DISTINCT FROM 'cancelled';
  UPDATE projects SET progress = v, updated_at = now()
   WHERE id = p_project AND tenant_id = p_tenant AND progress IS DISTINCT FROM v;
END $$;
REVOKE ALL ON FUNCTION public.pm_recalc_project_progress(uuid, uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.recalc_project_progress_on_task_change()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF TG_OP <> 'INSERT' THEN
    PERFORM pm_recalc_project_progress(OLD.project_id, OLD.tenant_id);
  END IF;
  IF TG_OP <> 'DELETE' AND (TG_OP = 'INSERT' OR NEW.project_id IS DISTINCT FROM OLD.project_id) THEN
    PERFORM pm_recalc_project_progress(NEW.project_id, NEW.tenant_id);
  END IF;
  RETURN COALESCE(NEW, OLD);
END $$;

DROP TRIGGER IF EXISTS recalc_project_progress ON public.project_tasks;
CREATE TRIGGER recalc_project_progress
  AFTER INSERT OR DELETE OR UPDATE OF progress, status, project_id, parent_id, effort_estimate_h, effort_spent_h
  ON public.project_tasks
  FOR EACH ROW EXECUTE FUNCTION public.recalc_project_progress_on_task_change();

-- Aucune de ces fonctions n'est une porte d'entrée : elles ne servent que les
-- déclencheurs (porte check_anon_grants).
DO $$
DECLARE f regprocedure;
BEGIN
  FOR f IN SELECT p.oid::regprocedure FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'public' AND p.proname LIKE 'pm\_%' LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated', f);
  END LOOP;
END $$;
