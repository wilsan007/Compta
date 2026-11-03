-- ============================================================
-- 805 — Gestion de projets : les responsables d'une tâche portent leur société
--
-- project_task_assignees (qui est en charge de quelle tâche) était la SEULE table
-- de la gestion de projets sans `tenant_id`. Elle n'était isolée que par une
-- politique « la tâche est de ma société ». Trois défauts en découlaient, mesurés
-- sur base neuve le 30/10 (suite 800, T27 → T30 rouges avant cette migration) :
--
--   1. le code qui la filtrait ou l'écrivait par société recevait 42703
--      (« column does not exist ») : changer le responsable d'une tâche depuis
--      l'écran échouait ;
--   2. aucune clé composite (ISO-02, 237) : un salarié d'UNE AUTRE société pouvait
--      être affecté à une tâche (T29 : « lignes écrites = 1 ») ;
--   3. aucune garde de rôle (PERM-01, 239) : un lecteur retirait des affectations
--      (T30 : « retraits = 2 »).
--
-- Cette migration :
--   * ajoute `tenant_id`, repris depuis la tâche, puis obligatoire ;
--   * le remplit à l'insertion quand l'appelant ne l'envoie pas (l'écran envoie
--     `task_id` + `employee_id`) — un déclencheur BEFORE INSERT, qui lit la tâche
--     avec les droits de l'appelant : une tâche qu'il ne voit pas ne donne aucune
--     société, donc l'écriture est refusée ;
--   * remplace les deux clés étrangères mono-colonne par des clés composites
--     `(tenant_id, task_id)` et `(tenant_id, employee_id)`, sous les mêmes noms
--     (des requêtes les désignent), toujours en cascade ;
--   * retire les affectations déjà incohérentes (salarié d'une autre société que
--     la tâche) — jamais plus d'une ligne par couple, et le nombre est publié ;
--   * remplace les trois politiques « la tâche est de ma société » par la garde de
--     société directe (et en ajoute une de mise à jour), et lie l'écriture à `can_perform('project_tasks', 'update')` :
--     affecter quelqu'un, c'est modifier la tâche.
--
-- Hors périmètre, constaté : `corporate_tax_grid_lines`, `payroll_tax_grid_lines`
-- et `intra_group_transactions` sont d'autres tables cloisonnées sans `tenant_id` ;
-- elles ne sont pas touchées ici.
-- ============================================================

ALTER TABLE public.project_task_assignees ADD COLUMN IF NOT EXISTS tenant_id uuid;

-- Reprise : la société de la tâche.
UPDATE public.project_task_assignees a
   SET tenant_id = t.tenant_id
  FROM public.project_tasks t
 WHERE t.id = a.task_id AND a.tenant_id IS NULL;

-- Les affectations d'un salarié d'une autre société que celle de la tâche ne
-- peuvent pas survivre à la clé composite : retirées, et comptées.
DO $$
DECLARE n integer;
BEGIN
  DELETE FROM public.project_task_assignees a
   USING public.employees e
   WHERE e.id = a.employee_id AND e.tenant_id IS DISTINCT FROM a.tenant_id;
  GET DIAGNOSTICS n = ROW_COUNT;
  RAISE NOTICE '805 : % affectation(s) d''un salarié d''une autre société retirée(s)', n;
END $$;

ALTER TABLE public.project_task_assignees ALTER COLUMN tenant_id SET NOT NULL;

-- À l'insertion sans société : celle de la tâche.
CREATE OR REPLACE FUNCTION public.pm_assignee_set_tenant()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
BEGIN
  IF NEW.tenant_id IS NULL THEN
    SELECT t.tenant_id INTO NEW.tenant_id FROM public.project_tasks t WHERE t.id = NEW.task_id;
  END IF;
  RETURN NEW;
END $$;

REVOKE ALL ON FUNCTION public.pm_assignee_set_tenant() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS aa_pm_assignee_set_tenant ON public.project_task_assignees;
CREATE TRIGGER aa_pm_assignee_set_tenant
  BEFORE INSERT ON public.project_task_assignees
  FOR EACH ROW EXECUTE FUNCTION public.pm_assignee_set_tenant();

-- Clés composites (ISO-02), sous les noms d'origine.
ALTER TABLE public.project_task_assignees
  DROP CONSTRAINT IF EXISTS project_task_assignees_task_id_fkey,
  DROP CONSTRAINT IF EXISTS project_task_assignees_employee_id_fkey,
  DROP CONSTRAINT IF EXISTS project_task_assignees_tenant_id_fkey;
ALTER TABLE public.project_task_assignees
  ADD CONSTRAINT project_task_assignees_tenant_id_fkey
    FOREIGN KEY (tenant_id) REFERENCES public.tenants (id) ON DELETE CASCADE,
  ADD CONSTRAINT project_task_assignees_task_id_fkey
    FOREIGN KEY (tenant_id, task_id) REFERENCES public.project_tasks (tenant_id, id) ON DELETE CASCADE,
  ADD CONSTRAINT project_task_assignees_employee_id_fkey
    FOREIGN KEY (tenant_id, employee_id) REFERENCES public.employees (tenant_id, id) ON DELETE CASCADE;

-- « Quelles tâches porte ce salarié ? » : la lecture de l'écran d'utilisation des ressources.
CREATE INDEX IF NOT EXISTS idx_project_task_assignees_tenant_employee
  ON public.project_task_assignees (tenant_id, employee_id);

-- Politiques : société directe, écriture gardée par le rôle.
DROP POLICY IF EXISTS tenant_select_project_task_assignees ON public.project_task_assignees;
DROP POLICY IF EXISTS tenant_insert_project_task_assignees ON public.project_task_assignees;
DROP POLICY IF EXISTS tenant_delete_project_task_assignees ON public.project_task_assignees;
DROP POLICY IF EXISTS tenant_update_project_task_assignees ON public.project_task_assignees;

CREATE POLICY tenant_select_project_task_assignees ON public.project_task_assignees
  FOR SELECT USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_insert_project_task_assignees ON public.project_task_assignees
  FOR INSERT WITH CHECK (tenant_id = current_tenant_id() AND can_perform('project_tasks', 'update'));
CREATE POLICY tenant_delete_project_task_assignees ON public.project_task_assignees
  FOR DELETE USING (tenant_id = current_tenant_id() AND can_perform('project_tasks', 'update'));
-- Les quatre commandes sont couvertes (la grille BT tient à moins de 4 pour suspect) ;
-- les clés composites interdisent de re-pointer une ligne hors de la société.
CREATE POLICY tenant_update_project_task_assignees ON public.project_task_assignees
  FOR UPDATE USING (tenant_id = current_tenant_id() AND can_perform('project_tasks', 'update'))
  WITH CHECK (tenant_id = current_tenant_id() AND can_perform('project_tasks', 'update'));

COMMENT ON COLUMN public.project_task_assignees.tenant_id IS
  '805 : société de l''affectation = celle de la tâche et du salarié (clés composites). Remplie par le déclencheur quand l''appelant ne l''envoie pas.';

-- PostgREST relit le schéma : la colonne est utilisable tout de suite (sans, le cache tenait l'ancienne table).
NOTIFY pgrst, 'reload schema';
