-- ============================================================
-- 801 — Gestion de projets : la période d'un élément ne sort pas de celle de
--       son parent, et un parent déplacé emmène ses enfants
--
-- Mesuré sur base neuve le 24/10/2026 : AUCUNE règle de dates sur
-- `project_tasks`, `task_actions` ni `projects`. Une sous-tâche pouvait finir
-- après sa mère, une tâche commencer avant son projet, une action échoir après
-- sa tâche — depuis le tableau comme depuis le Gantt.
--
-- Les règles (une borne absente — date NULL — ne contraint rien) :
--   R1  début ≤ fin, pour une tâche comme pour un projet ;
--   R2  une tâche reste dans la période de son PROJET ;
--   R3  une sous-tâche reste dans la période de sa tâche MÈRE ;
--   R4  l'échéance d'une action reste dans la période de sa tâche ;
--   R5  DÉPLACER un parent (début et fin décalés du même nombre de jours)
--       décale du même nombre de jours ses sous-tâches et ses actions — et,
--       pour un projet, ses tâches (qui emmènent les leurs) ;
--   R6  RÉDUIRE ou ÉTIRER un parent (début et fin décalés différemment) est
--       refusé s'il couperait un enfant : on ne tronque jamais en silence.
--
-- Les refus sont des exceptions lisibles (code P0001) : l'écran affiche le
-- message tel quel, le Gantt borne aussi la barre PENDANT le glissement.
-- Les lignes existantes hors bornes ne sont pas réécrites : elles seront
-- refusées à leur prochaine modification de dates (rien n'est déplacé d'office).
-- ============================================================

-- ------------------------------------------------------------ outils
-- Décalage d'un déplacement pur, NULL si ce n'est pas un déplacement pur.
CREATE OR REPLACE FUNCTION public.pm_pure_shift(o_start date, o_end date, n_start date, n_end date)
RETURNS integer LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    WHEN o_start IS NULL OR o_end IS NULL OR n_start IS NULL OR n_end IS NULL THEN NULL
    WHEN (n_start - o_start) = (n_end - o_end) AND (n_start - o_start) <> 0 THEN (n_start - o_start)
    ELSE NULL
  END
$$;

-- ------------------------------------------------------------ tâches
CREATE OR REPLACE FUNCTION public.pm_check_task_dates()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
DECLARE
  par record; prj record; v_shift integer; v_bad text;
BEGIN
  -- R1
  IF NEW.start_date IS NOT NULL AND NEW.due_date IS NOT NULL AND NEW.start_date > NEW.due_date THEN
    RAISE EXCEPTION 'La tâche « % » commence le % après sa fin (%).', NEW.title, NEW.start_date, NEW.due_date
      USING HINT = 'Choisissez une date de début antérieure ou égale à l''échéance.';
  END IF;

  -- R3
  IF NEW.parent_id IS NOT NULL THEN
    SELECT title, start_date, due_date INTO par
      FROM project_tasks WHERE id = NEW.parent_id AND tenant_id = NEW.tenant_id;
    IF FOUND THEN
      IF par.start_date IS NOT NULL AND NEW.start_date IS NOT NULL AND NEW.start_date < par.start_date THEN
        RAISE EXCEPTION 'La sous-tâche « % » ne peut pas commencer le % : sa tâche mère « % » commence le %.',
          NEW.title, NEW.start_date, par.title, par.start_date
          USING HINT = 'Une sous-tâche reste dans la période de sa tâche mère.';
      END IF;
      IF par.due_date IS NOT NULL AND NEW.due_date IS NOT NULL AND NEW.due_date > par.due_date THEN
        RAISE EXCEPTION 'La sous-tâche « % » ne peut pas finir le % : sa tâche mère « % » finit le %.',
          NEW.title, NEW.due_date, par.title, par.due_date
          USING HINT = 'Une sous-tâche reste dans la période de sa tâche mère.';
      END IF;
    END IF;
  END IF;

  -- R2
  IF NEW.project_id IS NOT NULL THEN
    SELECT name, start_date, end_date INTO prj
      FROM projects WHERE id = NEW.project_id AND tenant_id = NEW.tenant_id;
    IF FOUND THEN
      IF prj.start_date IS NOT NULL AND NEW.start_date IS NOT NULL AND NEW.start_date < prj.start_date THEN
        RAISE EXCEPTION 'La tâche « % » ne peut pas commencer le % : le projet « % » commence le %.',
          NEW.title, NEW.start_date, prj.name, prj.start_date
          USING HINT = 'Une tâche reste dans la période de son projet.';
      END IF;
      IF prj.end_date IS NOT NULL AND NEW.due_date IS NOT NULL AND NEW.due_date > prj.end_date THEN
        RAISE EXCEPTION 'La tâche « % » ne peut pas finir le % : le projet « % » finit le %.',
          NEW.title, NEW.due_date, prj.name, prj.end_date
          USING HINT = 'Une tâche reste dans la période de son projet.';
      END IF;
    END IF;
  END IF;

  -- R6 : un changement de période qui n'est pas un déplacement pur ne doit couper
  -- aucun enfant (un déplacement pur les emmène, R5).
  IF TG_OP = 'UPDATE'
     AND (NEW.start_date IS DISTINCT FROM OLD.start_date OR NEW.due_date IS DISTINCT FROM OLD.due_date)
     AND pm_pure_shift(OLD.start_date, OLD.due_date, NEW.start_date, NEW.due_date) IS NULL THEN
    SELECT string_agg('« ' || c.title || ' »', ', ') INTO v_bad
      FROM project_tasks c
     WHERE c.parent_id = NEW.id AND c.tenant_id = NEW.tenant_id
       AND ((NEW.start_date IS NOT NULL AND c.start_date IS NOT NULL AND c.start_date < NEW.start_date)
         OR (NEW.due_date IS NOT NULL AND c.due_date IS NOT NULL AND c.due_date > NEW.due_date));
    IF v_bad IS NOT NULL THEN
      RAISE EXCEPTION 'La tâche « % » ne peut pas couvrir du % au % : ses sous-tâches % en sortiraient.',
        NEW.title, NEW.start_date, NEW.due_date, v_bad
        USING HINT = 'Déplacez ou raccourcissez d''abord les sous-tâches, ou déplacez la tâche entière.';
    END IF;
    SELECT string_agg('« ' || a.title || ' »', ', ') INTO v_bad
      FROM task_actions a
     WHERE a.task_id = NEW.id AND a.tenant_id = NEW.tenant_id AND a.due_date IS NOT NULL
       AND ((NEW.start_date IS NOT NULL AND a.due_date < NEW.start_date)
         OR (NEW.due_date IS NOT NULL AND a.due_date > NEW.due_date));
    IF v_bad IS NOT NULL THEN
      RAISE EXCEPTION 'La tâche « % » ne peut pas couvrir du % au % : les échéances des actions % en sortiraient.',
        NEW.title, NEW.start_date, NEW.due_date, v_bad
        USING HINT = 'Changez d''abord l''échéance de ces actions.';
    END IF;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS pm_check_task_dates ON public.project_tasks;
CREATE TRIGGER pm_check_task_dates
  BEFORE INSERT OR UPDATE OF start_date, due_date, parent_id, project_id ON public.project_tasks
  FOR EACH ROW EXECUTE FUNCTION public.pm_check_task_dates();

-- R5 : la tâche a été déplacée d'un bloc → ses enfants suivent.
CREATE OR REPLACE FUNCTION public.pm_shift_task_children()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE d integer := pm_pure_shift(OLD.start_date, OLD.due_date, NEW.start_date, NEW.due_date); c record;
BEGIN
  IF d IS NULL THEN RETURN NEW; END IF;
  -- Dans l'ordre du décalage : en avançant, les plus tardives d'abord ; en
  -- reculant, les plus précoces d'abord. Une dépendance entre sœurs (802) n'est
  -- ainsi jamais violée à mi-parcours.
  -- Une boucle, pas un UPDATE en masse : PostgreSQL ne garantit pas l'ordre
  -- d'un UPDATE, et l'ordre compte dès que deux sœurs sont liées (802).
  FOR c IN SELECT id FROM project_tasks WHERE parent_id = NEW.id AND tenant_id = NEW.tenant_id
            ORDER BY CASE WHEN d > 0 THEN start_date END DESC NULLS LAST,
                     CASE WHEN d < 0 THEN start_date END ASC NULLS LAST, id LOOP
    UPDATE project_tasks SET start_date = start_date + d, due_date = due_date + d
     WHERE id = c.id AND tenant_id = NEW.tenant_id;
  END LOOP;
  UPDATE task_actions SET due_date = due_date + d
   WHERE task_id = NEW.id AND tenant_id = NEW.tenant_id AND due_date IS NOT NULL;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS pm_shift_task_children ON public.project_tasks;
CREATE TRIGGER pm_shift_task_children
  AFTER UPDATE OF start_date, due_date ON public.project_tasks
  FOR EACH ROW EXECUTE FUNCTION public.pm_shift_task_children();

-- ------------------------------------------------------------ actions (R4)
CREATE OR REPLACE FUNCTION public.pm_check_action_dates()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
DECLARE t record;
BEGIN
  IF NEW.due_date IS NULL THEN RETURN NEW; END IF;
  SELECT title, start_date, due_date INTO t FROM project_tasks WHERE id = NEW.task_id AND tenant_id = NEW.tenant_id;
  IF NOT FOUND THEN RETURN NEW; END IF;
  IF (t.start_date IS NOT NULL AND NEW.due_date < t.start_date)
     OR (t.due_date IS NOT NULL AND NEW.due_date > t.due_date) THEN
    RAISE EXCEPTION 'L''action « % » ne peut pas échoir le % : la tâche « % » court du % au %.',
      NEW.title, NEW.due_date, t.title, t.start_date, t.due_date
      USING HINT = 'L''échéance d''une action reste dans la période de sa tâche.';
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS pm_check_action_dates ON public.task_actions;
CREATE TRIGGER pm_check_action_dates
  BEFORE INSERT OR UPDATE OF due_date, task_id ON public.task_actions
  FOR EACH ROW EXECUTE FUNCTION public.pm_check_action_dates();

-- ------------------------------------------------------------ projets (R1, R5, R6)
CREATE OR REPLACE FUNCTION public.pm_check_project_dates()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
DECLARE v_bad text;
BEGIN
  IF NEW.start_date IS NOT NULL AND NEW.end_date IS NOT NULL AND NEW.start_date > NEW.end_date THEN
    RAISE EXCEPTION 'Le projet « % » commence le % après sa fin (%).', NEW.name, NEW.start_date, NEW.end_date;
  END IF;
  IF TG_OP = 'UPDATE'
     AND pm_pure_shift(OLD.start_date, OLD.end_date, NEW.start_date, NEW.end_date) IS NULL THEN
    SELECT string_agg('« ' || t.title || ' »', ', ') INTO v_bad
      FROM project_tasks t
     WHERE t.project_id = NEW.id AND t.tenant_id = NEW.tenant_id
       AND ((NEW.start_date IS NOT NULL AND t.start_date IS NOT NULL AND t.start_date < NEW.start_date)
         OR (NEW.end_date IS NOT NULL AND t.due_date IS NOT NULL AND t.due_date > NEW.end_date));
    IF v_bad IS NOT NULL THEN
      RAISE EXCEPTION 'Le projet « % » ne peut pas couvrir du % au % : les tâches % en sortiraient.',
        NEW.name, NEW.start_date, NEW.end_date, v_bad
        USING HINT = 'Déplacez ou raccourcissez d''abord ces tâches, ou déplacez le projet entier.';
    END IF;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS pm_check_project_dates ON public.projects;
CREATE TRIGGER pm_check_project_dates
  BEFORE INSERT OR UPDATE OF start_date, end_date ON public.projects
  FOR EACH ROW EXECUTE FUNCTION public.pm_check_project_dates();

CREATE OR REPLACE FUNCTION public.pm_shift_project_tasks()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE d integer := pm_pure_shift(OLD.start_date, OLD.end_date, NEW.start_date, NEW.end_date); c record;
BEGIN
  IF d IS NULL THEN RETURN NEW; END IF;
  -- seules les tâches de premier niveau : leurs sous-tâches suivent par R5
  FOR c IN SELECT id FROM project_tasks
            WHERE project_id = NEW.id AND parent_id IS NULL AND tenant_id = NEW.tenant_id
            ORDER BY CASE WHEN d > 0 THEN start_date END DESC NULLS LAST,
                     CASE WHEN d < 0 THEN start_date END ASC NULLS LAST, id LOOP
    UPDATE project_tasks SET start_date = start_date + d, due_date = due_date + d
     WHERE id = c.id AND tenant_id = NEW.tenant_id;
  END LOOP;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS pm_shift_project_tasks ON public.projects;
CREATE TRIGGER pm_shift_project_tasks
  AFTER UPDATE OF start_date, end_date ON public.projects
  FOR EACH ROW EXECUTE FUNCTION public.pm_shift_project_tasks();

REVOKE ALL ON FUNCTION public.pm_pure_shift(date, date, date, date) FROM PUBLIC, anon;

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
