-- ============================================================
-- 303_project_progress_and_cycle.sql — W8 (M-17) :
-- un seul calcul d'avancement (pondéré) et anti-cycle des tâches
--
-- Deux défauts prouvés par `303_project_progress_and_cycle_tests.sql`, vus
-- **rouges avant** ce fichier :
--
--   PROJ-02 🟠 Deux calculs concurrents pour la même grandeur :
--             `recalc_parent_progress_on_subtask_change` (parent ← enfants) et
--             `recalc_project_progress_on_task_change` (projet ← tâches de
--             premier niveau) faisaient chacun une **moyenne simple**. Mesuré :
--             une sous-tâche de 10 h à 100 % et une de 90 h à 0 % donnaient
--             **50 %** — alors qu'une heure pèse moins que quatre-vingt-dix.
--   PROJ-03 🟠 Aucune garde : une tâche pouvait être **son propre parent**
--             (refusée seulement par « stack depth limit exceeded », la
--             récursion des treize déclencheurs épuisant la pile) ni former un
--             cycle A → B → A (accepté, mesuré).
--
-- UNE SEULE RÈGLE. Le poids d'une tâche vit dans `progress_weight` (heures
-- prévues, à défaut heures passées, à défaut 1), et **les deux** remontées
-- l'appellent : le parent comme le projet appliquent la même moyenne pondérée.
-- L'avancement n'est donc plus « deux calculs » mais une règle et des niveaux.
--
-- LES LIMITES, DITES.
--   • Une tâche sans heure prévue ni passée pèse 1 : sans estimation, le poids
--     est neutre — c'est le seul choix qui ne fausse pas les autres.
--   • Le jeu de sous-tâches moyenné ne change pas (brouillons et annulées
--     comprises, comme avant) : la vague corrige le **poids**, pas le périmètre.
--   • La garde anti-cycle remonte la chaîne des ancêtres (100 niveaux au plus) ;
--     au-delà, la hiérarchie est refusée plutôt que de risquer la récursion.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Une seule règle de pondération
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.progress_weight(p_estimate numeric, p_spent numeric)
RETURNS numeric
LANGUAGE sql IMMUTABLE
AS $$
  -- Le poids d'une tâche dans la moyenne : ses heures prévues, à défaut ses
  -- heures passées, à défaut 1 (neutre). Jamais négatif ni nul.
  SELECT GREATEST(COALESCE(NULLIF(p_estimate, 0), NULLIF(p_spent, 0), 1), 0.0001)
$$;

REVOKE EXECUTE ON FUNCTION public.progress_weight(numeric, numeric) FROM PUBLIC, anon;

-- ------------------------------------------------------------
-- 2. La remontée vers le parent, pondérée (160 : la remontée continue vers les
--    ancêtres et s'arrête à la racine)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.recalc_parent_progress_on_subtask_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_parent_id uuid;
  v_tenant uuid;
  v_avg_progress integer;
  v_count integer;
  v_done_count integer;
  v_sub_effort numeric;
BEGIN
  v_parent_id := COALESCE(NEW.parent_id, OLD.parent_id);
  IF v_parent_id IS NULL THEN RETURN NEW; END IF;
  v_tenant := COALESCE(NEW.tenant_id, OLD.tenant_id);

  -- Moyenne **pondérée** par les heures prévues (même règle que le projet)
  SELECT
    COALESCE(round(sum(t.progress * public.progress_weight(t.effort_estimate_h, t.effort_spent_h))
                   / NULLIF(sum(public.progress_weight(t.effort_estimate_h, t.effort_spent_h)), 0)), 0)::integer,
    COUNT(*),
    COUNT(*) FILTER (WHERE t.status IN ('done', 'cancelled') OR t.is_closed = true),
    COALESCE(SUM(t.effort_spent_h), 0)
  INTO v_avg_progress, v_count, v_done_count, v_sub_effort
  FROM public.project_tasks t
  WHERE t.parent_id = v_parent_id AND t.tenant_id = v_tenant;

  -- Mettre à jour le parent : la remontée continue vers les ancêtres et
  -- s'arrête à la racine (parent_id NULL).
  UPDATE public.project_tasks
    SET progress = v_avg_progress,
        subtask_count = v_count,
        subtask_done_count = v_done_count,
        subtask_effective_hours = v_sub_effort,
        updated_at = now()
  WHERE id = v_parent_id AND tenant_id = v_tenant;

  RETURN NEW;
END;
$function$;

-- ------------------------------------------------------------
-- 3. Le projet, même règle (tâches de premier niveau)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.recalc_project_progress_on_task_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_project_id uuid;
  v_tenant uuid;
  v_avg_progress integer;
BEGIN
  v_project_id := COALESCE(NEW.project_id, OLD.project_id);
  IF v_project_id IS NULL THEN RETURN NEW; END IF;
  v_tenant := COALESCE(NEW.tenant_id, OLD.tenant_id);

  -- Même pondération que la remontée vers le parent : une règle, deux niveaux.
  SELECT COALESCE(round(sum(t.progress * public.progress_weight(t.effort_estimate_h, t.effort_spent_h))
                        / NULLIF(sum(public.progress_weight(t.effort_estimate_h, t.effort_spent_h)), 0)), 0)::integer
  INTO v_avg_progress
  FROM public.project_tasks t
  WHERE t.project_id = v_project_id
    AND t.parent_id IS NULL
    AND t.tenant_id = v_tenant;

  UPDATE public.projects
    SET progress = v_avg_progress,
        updated_at = now()
  WHERE id = v_project_id AND tenant_id = v_tenant;

  RETURN NEW;
END;
$$;

-- ------------------------------------------------------------
-- 4. La garde anti-cycle (PROJ-03)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.check_task_parent_cycle()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_courant uuid;
  v_ancetre uuid;
  v_tenant uuid;
  v_profondeur int := 0;
BEGIN
  IF NEW.parent_id IS NULL THEN RETURN NEW; END IF;

  IF NEW.parent_id = NEW.id THEN
    RAISE EXCEPTION 'Une tâche ne peut pas être son propre parent (%)', NEW.id
      USING ERRCODE = '23514';
  END IF;

  -- Remonter la chaîne des ancêtres : si on retombe sur la tâche modifiée,
  -- c'est un cycle. La profondeur est bornée : treize déclencheurs se
  -- réécrivent en cascade sur cette table, une chaîne sans fin épuiserait la pile.
  v_courant := NEW.parent_id;
  WHILE v_courant IS NOT NULL LOOP
    v_profondeur := v_profondeur + 1;
    IF v_profondeur > 100 THEN
      RAISE EXCEPTION 'Hiérarchie de tâches trop profonde (plus de 100 niveaux) pour %', NEW.id
        USING ERRCODE = '23514';
    END IF;

    SELECT t.parent_id, t.tenant_id INTO v_ancetre, v_tenant
    FROM public.project_tasks t WHERE t.id = v_courant;

    EXIT WHEN v_ancetre IS NULL;
    IF v_ancetre = NEW.id THEN
      RAISE EXCEPTION 'Cycle de tâches refusé : % est déjà un descendant de %', NEW.parent_id, NEW.id
        USING ERRCODE = '23514';
    END IF;
    v_courant := v_ancetre;
  END LOOP;

  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.check_task_parent_cycle() FROM PUBLIC, anon;

DROP TRIGGER IF EXISTS check_task_parent_cycle ON public.project_tasks;
CREATE TRIGGER check_task_parent_cycle
  BEFORE INSERT OR UPDATE OF parent_id
  ON public.project_tasks
  FOR EACH ROW
  EXECUTE FUNCTION public.check_task_parent_cycle();

-- ------------------------------------------------------------
-- 5. Reprise : les avancements déjà calculés à la moyenne simple sont
--    recalculés à la moyenne pondérée. Seules les lignes dont la valeur change
--    sont touchées — la reprise ne réveille pas les autres déclencheurs sur des
--    valeurs justes.
-- ------------------------------------------------------------
WITH pondere AS (
  SELECT t.parent_id AS id,
         round(sum(t.progress * public.progress_weight(t.effort_estimate_h, t.effort_spent_h))
               / NULLIF(sum(public.progress_weight(t.effort_estimate_h, t.effort_spent_h)), 0))::integer AS p
  FROM public.project_tasks t
  WHERE t.parent_id IS NOT NULL
  GROUP BY t.parent_id
)
UPDATE public.project_tasks c SET progress = p.p
FROM pondere p
WHERE c.id = p.id AND c.progress IS DISTINCT FROM p.p;

WITH pondere AS (
  SELECT t.project_id AS id,
         round(sum(t.progress * public.progress_weight(t.effort_estimate_h, t.effort_spent_h))
               / NULLIF(sum(public.progress_weight(t.effort_estimate_h, t.effort_spent_h)), 0))::integer AS p
  FROM public.project_tasks t
  WHERE t.parent_id IS NULL AND t.project_id IS NOT NULL
  GROUP BY t.project_id
)
UPDATE public.projects pr SET progress = p.p
FROM pondere p
WHERE pr.id = p.id AND pr.progress IS DISTINCT FROM p.p;

