-- ============================================================
-- 802 — Gestion de projets : « B commence après A », entre tâches et entre
--       projets — liens tenus par la base, successeur reporté automatiquement
--
-- Mesuré sur base neuve le 24/10/2026 :
--   * `project_task_dependencies` existe (FK composites, RLS) mais AUCUN écran
--     ne l'écrit et AUCUNE règle ne la lit, sauf une notification au passage à
--     « en cours » (qui, avant la 800, ne se déclenchait jamais) ;
--   * rien n'empêchait un lien de soi à soi, un doublon, une boucle A → B → A,
--     ni un lien entre une tâche et sa propre sous-tâche (contradictoire avec la
--     801 : l'enfant serait à la fois dans la période du parent et après elle) ;
--   * entre PROJETS, aucun lien possible.
--
-- Les règles :
--   D1  un lien est refusé s'il est réflexif, en double, s'il ferme une boucle,
--       ou s'il relie une tâche à l'un de ses ancêtres ou descendants ;
--   D2  quatre types, comme les outils de planification : fin→début (le défaut,
--       « B commence le lendemain de la fin de A » + `lag_days`), début→début,
--       fin→fin, début→fin ;
--   D3  REPORT AUTOMATIQUE : quand A bouge ou s'allonge, ou quand le lien est
--       créé, B est décalé d'un bloc juste assez pour respecter le lien — avec
--       ses enfants (801 R5) et ses propres successeurs, en cascade. Si le
--       report sortait B de la période de son parent, TOUT est refusé (801) ;
--   D4  déplacer B AVANT ce que permet A est refusé (le Gantt borne la barre) ;
--   D5  mêmes règles entre projets (`project_dependencies`, fin→début + délai).
-- ============================================================

-- ------------------------------------------------------------ calcul de l'écart
-- Nombre de jours dont le successeur doit avancer (0 si le lien est respecté).
CREATE OR REPLACE FUNCTION public.pm_dependency_gap(
  p_type text, p_lag integer, pred_start date, pred_end date, succ_start date, succ_end date)
RETURNS integer LANGUAGE sql IMMUTABLE AS $$
  SELECT GREATEST(0, COALESCE(CASE p_type
    WHEN 'start-to-start'   THEN (pred_start + COALESCE(p_lag, 0)) - succ_start
    WHEN 'finish-to-finish' THEN (pred_end   + COALESCE(p_lag, 0)) - succ_end
    WHEN 'start-to-finish'  THEN (pred_start + COALESCE(p_lag, 0)) - succ_end
    ELSE                         (pred_end + 1 + COALESCE(p_lag, 0)) - succ_start
  END, 0))
$$;

-- ------------------------------------------------------------ table des tâches : D1, D2
-- Une auto-dépendance est invalide par nature (et contredite par la 801) : on la
-- retire AVANT de poser la contrainte, sinon toute base existante qui en porte
-- bloquerait la migration. Mesuré sur la base d'audit migrée le 25/10 : 2 lignes
-- réflexives y bloquaient `project_task_dependencies_no_self`.
DELETE FROM public.project_task_dependencies WHERE task_id = depends_on_task_id;
UPDATE public.project_task_dependencies SET dependency_type = replace(dependency_type, '_', '-')
 WHERE dependency_type LIKE '%\_%';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'project_task_dependencies_type_check') THEN
    ALTER TABLE public.project_task_dependencies ADD CONSTRAINT project_task_dependencies_type_check
      CHECK (dependency_type IN ('finish-to-start', 'start-to-start', 'finish-to-finish', 'start-to-finish'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'project_task_dependencies_no_self') THEN
    ALTER TABLE public.project_task_dependencies ADD CONSTRAINT project_task_dependencies_no_self
      CHECK (task_id <> depends_on_task_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'project_task_dependencies_lag_nonneg') THEN
    ALTER TABLE public.project_task_dependencies ADD CONSTRAINT project_task_dependencies_lag_nonneg
      CHECK (lag_days IS NULL OR lag_days >= 0);
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.pm_check_task_dependency()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE pred_title text; succ_title text;
BEGIN
  SELECT title INTO pred_title FROM project_tasks WHERE id = NEW.depends_on_task_id AND tenant_id = NEW.tenant_id;
  SELECT title INTO succ_title FROM project_tasks WHERE id = NEW.task_id AND tenant_id = NEW.tenant_id;

  IF EXISTS (SELECT 1 FROM project_task_dependencies
              WHERE tenant_id = NEW.tenant_id AND task_id = NEW.task_id
                AND depends_on_task_id = NEW.depends_on_task_id AND id <> NEW.id) THEN
    RAISE EXCEPTION '« % » dépend déjà de « % ».', succ_title, pred_title;
  END IF;

  -- boucle : le successeur atteint-il déjà le prédécesseur en suivant les liens ?
  IF EXISTS (
    WITH RECURSIVE aval(id) AS (
      SELECT NEW.task_id
      UNION
      SELECT d.task_id FROM project_task_dependencies d JOIN aval ON d.depends_on_task_id = aval.id
       WHERE d.tenant_id = NEW.tenant_id AND d.id <> NEW.id)
    SELECT 1 FROM aval WHERE id = NEW.depends_on_task_id) THEN
    RAISE EXCEPTION 'Lier « % » après « % » fermerait une boucle : « % » attend déjà, directement ou non, « % ».',
      succ_title, pred_title, pred_title, succ_title
      USING HINT = 'Une chaîne de liens ne peut pas revenir à son point de départ.';
  END IF;

  -- parenté : une tâche ne peut pas attendre son ancêtre ni son descendant
  IF EXISTS (
    WITH RECURSIVE anc(id, depth) AS (
      SELECT parent_id, 1 FROM project_tasks WHERE id = NEW.task_id AND tenant_id = NEW.tenant_id
      UNION ALL
      SELECT t.parent_id, anc.depth + 1 FROM project_tasks t JOIN anc ON t.id = anc.id
       WHERE t.tenant_id = NEW.tenant_id AND anc.depth < 50)
    SELECT 1 FROM anc WHERE id = NEW.depends_on_task_id)
  OR EXISTS (
    WITH RECURSIVE anc(id, depth) AS (
      SELECT parent_id, 1 FROM project_tasks WHERE id = NEW.depends_on_task_id AND tenant_id = NEW.tenant_id
      UNION ALL
      SELECT t.parent_id, anc.depth + 1 FROM project_tasks t JOIN anc ON t.id = anc.id
       WHERE t.tenant_id = NEW.tenant_id AND anc.depth < 50)
    SELECT 1 FROM anc WHERE id = NEW.task_id) THEN
    RAISE EXCEPTION '« % » et « % » sont dans la même branche (tâche et sous-tâche) : elles ne peuvent pas se suivre.',
      succ_title, pred_title
      USING HINT = 'Une sous-tâche vit dans la période de sa tâche mère ; liez plutôt des tâches sœurs ou de branches différentes.';
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS pm_check_task_dependency ON public.project_task_dependencies;
CREATE TRIGGER pm_check_task_dependency
  BEFORE INSERT OR UPDATE ON public.project_task_dependencies
  FOR EACH ROW EXECUTE FUNCTION public.pm_check_task_dependency();

-- ------------------------------------------------------------ D3 : report des tâches
CREATE OR REPLACE FUNCTION public.pm_enforce_task_successors(p_task uuid, p_tenant uuid)
RETURNS void LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
DECLARE r record; pr record; sc record; gap integer;
BEGIN
  FOR r IN SELECT task_id, dependency_type, lag_days FROM project_task_dependencies
            WHERE depends_on_task_id = p_task AND tenant_id = p_tenant ORDER BY created_at, id LOOP
    SELECT start_date, due_date INTO pr FROM project_tasks WHERE id = p_task AND tenant_id = p_tenant;
    SELECT start_date, due_date INTO sc FROM project_tasks WHERE id = r.task_id AND tenant_id = p_tenant;
    gap := pm_dependency_gap(r.dependency_type, r.lag_days, pr.start_date, pr.due_date, sc.start_date, sc.due_date);
    IF gap > 0 THEN
      UPDATE project_tasks SET start_date = start_date + gap, due_date = due_date + gap
       WHERE id = r.task_id AND tenant_id = p_tenant;
    END IF;
  END LOOP;
END $$;
REVOKE ALL ON FUNCTION public.pm_enforce_task_successors(uuid, uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.pm_after_task_dates_for_dependencies()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  PERFORM pm_enforce_task_successors(NEW.id, NEW.tenant_id);
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS pm_enforce_task_successors ON public.project_tasks;
CREATE TRIGGER pm_enforce_task_successors
  AFTER UPDATE OF start_date, due_date ON public.project_tasks
  FOR EACH ROW EXECUTE FUNCTION public.pm_after_task_dates_for_dependencies();

CREATE OR REPLACE FUNCTION public.pm_after_task_dependency_change()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  PERFORM pm_enforce_task_successors(NEW.depends_on_task_id, NEW.tenant_id);
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS pm_after_task_dependency_change ON public.project_task_dependencies;
CREATE TRIGGER pm_after_task_dependency_change
  AFTER INSERT OR UPDATE ON public.project_task_dependencies
  FOR EACH ROW EXECUTE FUNCTION public.pm_after_task_dependency_change();

-- ------------------------------------------------------------ D4 : pas avant le prédécesseur
CREATE OR REPLACE FUNCTION public.pm_check_task_predecessors()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
DECLARE r record;
BEGIN
  FOR r IN SELECT d.dependency_type, d.lag_days, p.title, p.start_date, p.due_date
             FROM project_task_dependencies d
             JOIN project_tasks p ON p.id = d.depends_on_task_id AND p.tenant_id = d.tenant_id
            WHERE d.task_id = NEW.id AND d.tenant_id = NEW.tenant_id LOOP
    IF pm_dependency_gap(r.dependency_type, r.lag_days, r.start_date, r.due_date, NEW.start_date, NEW.due_date) > 0 THEN
      RAISE EXCEPTION 'La tâche « % » ne peut pas être placée du % au % : elle attend « % » (du % au %).',
        NEW.title, NEW.start_date, NEW.due_date, r.title, r.start_date, r.due_date
        USING HINT = 'Déplacez la tâche après son prédécesseur, ou supprimez le lien.';
    END IF;
  END LOOP;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS pm_check_task_predecessors ON public.project_tasks;
CREATE TRIGGER pm_check_task_predecessors
  BEFORE UPDATE OF start_date, due_date ON public.project_tasks
  FOR EACH ROW EXECUTE FUNCTION public.pm_check_task_predecessors();

-- ------------------------------------------------------------ D5 : entre projets
CREATE TABLE IF NOT EXISTS public.project_dependencies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  project_id uuid NOT NULL,
  depends_on_project_id uuid NOT NULL,
  lag_days integer NOT NULL DEFAULT 0 CHECK (lag_days >= 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT project_dependencies_no_self CHECK (project_id <> depends_on_project_id),
  CONSTRAINT project_dependencies_project_fkey FOREIGN KEY (tenant_id, project_id)
    REFERENCES public.projects (tenant_id, id) ON DELETE CASCADE,
  CONSTRAINT project_dependencies_depends_on_fkey FOREIGN KEY (tenant_id, depends_on_project_id)
    REFERENCES public.projects (tenant_id, id) ON DELETE CASCADE,
  CONSTRAINT project_dependencies_unique UNIQUE (tenant_id, project_id, depends_on_project_id)
);
CREATE INDEX IF NOT EXISTS idx_project_dependencies_depends ON public.project_dependencies (tenant_id, depends_on_project_id);

ALTER TABLE public.project_dependencies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.project_dependencies FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_select_project_deps ON public.project_dependencies;
DROP POLICY IF EXISTS tenant_insert_project_deps ON public.project_dependencies;
DROP POLICY IF EXISTS tenant_update_project_deps ON public.project_dependencies;
DROP POLICY IF EXISTS tenant_delete_project_deps ON public.project_dependencies;
CREATE POLICY tenant_select_project_deps ON public.project_dependencies FOR SELECT
  USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_insert_project_deps ON public.project_dependencies FOR INSERT
  WITH CHECK (tenant_id = current_tenant_id());
CREATE POLICY tenant_update_project_deps ON public.project_dependencies FOR UPDATE
  USING (tenant_id = current_tenant_id()) WITH CHECK (tenant_id = current_tenant_id());
CREATE POLICY tenant_delete_project_deps ON public.project_dependencies FOR DELETE
  USING (tenant_id = current_tenant_id());

REVOKE ALL ON public.project_dependencies FROM PUBLIC, anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.project_dependencies TO authenticated;
GRANT ALL ON public.project_dependencies TO service_role;

DROP TRIGGER IF EXISTS set_tenant_id_project_dependencies ON public.project_dependencies;
CREATE TRIGGER set_tenant_id_project_dependencies
  BEFORE INSERT ON public.project_dependencies
  FOR EACH ROW EXECUTE FUNCTION public.set_tenant_id();

CREATE OR REPLACE FUNCTION public.pm_check_project_dependency()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE pred_name text; succ_name text;
BEGIN
  SELECT name INTO pred_name FROM projects WHERE id = NEW.depends_on_project_id AND tenant_id = NEW.tenant_id;
  SELECT name INTO succ_name FROM projects WHERE id = NEW.project_id AND tenant_id = NEW.tenant_id;
  IF EXISTS (
    WITH RECURSIVE aval(id) AS (
      SELECT NEW.project_id
      UNION
      SELECT d.project_id FROM project_dependencies d JOIN aval ON d.depends_on_project_id = aval.id
       WHERE d.tenant_id = NEW.tenant_id AND d.id <> NEW.id)
    SELECT 1 FROM aval WHERE id = NEW.depends_on_project_id) THEN
    RAISE EXCEPTION 'Lier le projet « % » après « % » fermerait une boucle.', succ_name, pred_name
      USING HINT = 'Une chaîne de liens ne peut pas revenir à son point de départ.';
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS pm_check_project_dependency ON public.project_dependencies;
CREATE TRIGGER pm_check_project_dependency
  BEFORE INSERT OR UPDATE ON public.project_dependencies
  FOR EACH ROW EXECUTE FUNCTION public.pm_check_project_dependency();

CREATE OR REPLACE FUNCTION public.pm_enforce_project_successors(p_project uuid, p_tenant uuid)
RETURNS void LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
DECLARE r record; pr record; sc record; gap integer;
BEGIN
  FOR r IN SELECT project_id, lag_days FROM project_dependencies
            WHERE depends_on_project_id = p_project AND tenant_id = p_tenant ORDER BY created_at, id LOOP
    SELECT start_date, end_date INTO pr FROM projects WHERE id = p_project AND tenant_id = p_tenant;
    SELECT start_date, end_date INTO sc FROM projects WHERE id = r.project_id AND tenant_id = p_tenant;
    gap := pm_dependency_gap('finish-to-start', r.lag_days, pr.start_date, pr.end_date, sc.start_date, sc.end_date);
    IF gap > 0 THEN
      UPDATE projects SET start_date = start_date + gap, end_date = end_date + gap
       WHERE id = r.project_id AND tenant_id = p_tenant;
    END IF;
  END LOOP;
END $$;
REVOKE ALL ON FUNCTION public.pm_enforce_project_successors(uuid, uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.pm_after_project_dates_for_dependencies()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  PERFORM pm_enforce_project_successors(NEW.id, NEW.tenant_id);
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS pm_enforce_project_successors ON public.projects;
CREATE TRIGGER pm_enforce_project_successors
  AFTER UPDATE OF start_date, end_date ON public.projects
  FOR EACH ROW EXECUTE FUNCTION public.pm_after_project_dates_for_dependencies();

CREATE OR REPLACE FUNCTION public.pm_after_project_dependency_change()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  PERFORM pm_enforce_project_successors(NEW.depends_on_project_id, NEW.tenant_id);
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS pm_after_project_dependency_change ON public.project_dependencies;
CREATE TRIGGER pm_after_project_dependency_change
  AFTER INSERT OR UPDATE ON public.project_dependencies
  FOR EACH ROW EXECUTE FUNCTION public.pm_after_project_dependency_change();

CREATE OR REPLACE FUNCTION public.pm_check_project_predecessors()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
DECLARE r record;
BEGIN
  FOR r IN SELECT d.lag_days, p.name, p.start_date, p.end_date
             FROM project_dependencies d
             JOIN projects p ON p.id = d.depends_on_project_id AND p.tenant_id = d.tenant_id
            WHERE d.project_id = NEW.id AND d.tenant_id = NEW.tenant_id LOOP
    IF pm_dependency_gap('finish-to-start', r.lag_days, r.start_date, r.end_date, NEW.start_date, NEW.end_date) > 0 THEN
      RAISE EXCEPTION 'Le projet « % » ne peut pas commencer le % : il attend la fin du projet « % » (le %).',
        NEW.name, NEW.start_date, r.name, r.end_date
        USING HINT = 'Déplacez le projet après son prédécesseur, ou supprimez le lien.';
    END IF;
  END LOOP;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS pm_check_project_predecessors ON public.projects;
CREATE TRIGGER pm_check_project_predecessors
  BEFORE UPDATE OF start_date, end_date ON public.projects
  FOR EACH ROW EXECUTE FUNCTION public.pm_check_project_predecessors();

REVOKE ALL ON FUNCTION public.pm_dependency_gap(text, integer, date, date, date, date) FROM PUBLIC, anon;

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

-- Les déclencheurs de CONTRÔLE (801 pm_check_task_dates, pm_check_project_dates ;
-- 802 pm_check_task_predecessors, pm_check_project_predecessors) s'exécutent avec
-- les droits de l'utilisateur : ils doivent pouvoir appeler ces deux calculs PURS
-- (aucune lecture, aucune écriture). Mesuré sur Supabase local le 24/10 : sans ce
-- droit, tout déplacement de tâche depuis l'écran était refusé (42501) — la CI ne
-- le voyait pas, elle joue en superutilisateur (suite 800, T22, joue en
-- `authenticated`).
GRANT EXECUTE ON FUNCTION public.pm_pure_shift(date, date, date, date) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.pm_dependency_gap(text, integer, date, date, date, date) TO authenticated, service_role;
