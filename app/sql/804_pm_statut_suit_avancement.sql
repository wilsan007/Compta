-- ============================================================
-- 804 — Gestion de projets : le statut d'une tâche suit son avancement
--
-- Repris du tableau de wadashaqayn (compute_task_status) : quand l'avancement
-- d'une tâche est CALCULÉ (actions, sous-tâches — 800), son statut suit :
--   0 %        → « À faire »   (todo)
--   1 à 99 %   → « En cours »  (in_progress)
--   100 %      → « Terminé »   (déjà tenu par auto_close_task_on_progress_100)
-- Mesuré sur Supabase local le 25/10 : une tâche à 50 % (une action sur deux
-- cochée) restait « À faire » dans le tableau, le Kanban et le Gantt.
--
-- Améliorations sur wadashaqayn, qui écrasait tout statut :
--   * un statut posé à la main et qui dit autre chose que l'avancement —
--     bloqué, modifications demandées, approuvé, annulé — n'est JAMAIS écrasé ;
--   * une tâche dont l'avancement est SAISI (ni action ni sous-tâche) n'est pas
--     touchée (800 : pm_task_progress rend NULL) ;
--   * quitter « Terminé » rouvre la tâche (is_closed = false).
-- ============================================================

CREATE OR REPLACE FUNCTION public.pm_recalc_task_progress(p_task uuid, p_tenant uuid)
RETURNS void LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
DECLARE v integer; cur record; v_status text;
BEGIN
  IF p_task IS NULL OR p_tenant IS NULL THEN RETURN; END IF;
  v := pm_task_progress(p_task, p_tenant);
  IF v IS NULL THEN RETURN; END IF;
  SELECT progress, status, is_closed INTO cur FROM project_tasks WHERE id = p_task AND tenant_id = p_tenant;
  IF NOT FOUND THEN RETURN; END IF;
  v_status := CASE
    WHEN v = 100 THEN cur.status                                        -- auto_close_on_progress fera « done »
    WHEN v > 0 AND cur.status IN ('todo', 'done') THEN 'in_progress'
    WHEN v = 0 AND cur.status IN ('in_progress', 'done') THEN 'todo'
    ELSE cur.status
  END;
  IF cur.progress IS DISTINCT FROM v OR cur.status IS DISTINCT FROM v_status THEN
    UPDATE project_tasks
       SET progress = v,
           status = v_status,
           is_closed = CASE WHEN v_status <> 'done' AND cur.status = 'done' THEN false ELSE is_closed END,
           updated_at = now()
     WHERE id = p_task AND tenant_id = p_tenant;
  END IF;
END $$;

REVOKE ALL ON FUNCTION public.pm_recalc_task_progress(uuid, uuid) FROM PUBLIC, anon, authenticated;

-- Reprise : les tâches dont l'avancement est calculé prennent le statut qui lui
-- correspond. Les avis aux observateurs et le journal d'activité sont suspendus :
-- c'est une remise en cohérence, pas un geste d'un utilisateur.
DO $$
DECLARE trg text; r record;
BEGIN
  FOREACH trg IN ARRAY ARRAY['notify_watchers_status', 'project_tasks_activity_log'] LOOP
    IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'public.project_tasks'::regclass AND tgname = trg) THEN
      EXECUTE format('ALTER TABLE public.project_tasks DISABLE TRIGGER %I', trg);
    END IF;
  END LOOP;
  FOR r IN SELECT t.id, t.tenant_id FROM public.project_tasks t
            WHERE EXISTS (SELECT 1 FROM public.task_actions a WHERE a.task_id = t.id AND a.tenant_id = t.tenant_id)
               OR EXISTS (SELECT 1 FROM public.project_tasks c WHERE c.parent_id = t.id AND c.tenant_id = t.tenant_id) LOOP
    PERFORM public.pm_recalc_task_progress(r.id, r.tenant_id);
  END LOOP;
  FOREACH trg IN ARRAY ARRAY['notify_watchers_status', 'project_tasks_activity_log'] LOOP
    IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'public.project_tasks'::regclass AND tgname = trg) THEN
      EXECUTE format('ALTER TABLE public.project_tasks ENABLE TRIGGER %I', trg);
    END IF;
  END LOOP;
END $$;
