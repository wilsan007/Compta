-- ============================================================
-- 803 — Gestion de projets : pas d'action cochée sans document de preuve
--
-- Décision du 24/10/2026 (reprise du tableau de wadashaqayn) : une action ne
-- se coche que si au moins un document de preuve lui est joint
-- (`task_action_attachments`). wadashaqayn ne le tenait QUE dans l'écran (la
-- case grisée) ; un appel direct cochait sans preuve. La règle est ici tenue
-- par la base, l'écran ne fait que la montrer.
--
--   P1  cocher une action (is_done passe à vrai, ou taux à 100) exige une
--       pièce jointe à CETTE action ;
--   P2  créer une action déjà cochée est refusé (elle n'a pas encore de pièce) ;
--   P3  décocher reste libre ;
--   P4  l'achèvement PROPAGÉ par la base n'est pas un geste de l'utilisateur :
--       une sous-tâche liée qui atteint 100 % (800) coche son action par un
--       déclencheur. La règle ne s'applique qu'à l'écriture DIRECTE
--       (pg_trigger_depth() = 1), comme le garde de la 790.
-- ============================================================

CREATE OR REPLACE FUNCTION public.pm_preuve_action()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
BEGIN
  IF NOT NEW.is_done THEN RETURN NEW; END IF;                         -- P3
  IF TG_OP = 'UPDATE' AND OLD.is_done THEN RETURN NEW; END IF;        -- déjà cochée
  IF pg_trigger_depth() > 1 THEN RETURN NEW; END IF;                  -- P4
  IF TG_OP = 'INSERT' OR NOT EXISTS (
       SELECT 1 FROM task_action_attachments
        WHERE task_action_id = NEW.id AND tenant_id = NEW.tenant_id) THEN
    RAISE EXCEPTION 'Document requis : joignez au moins un document de preuve à l''action « % » avant de la valider.', NEW.title
      USING HINT = 'Ajoutez la preuve avec le bouton + de la case, puis cochez.';
  END IF;
  RETURN NEW;
END $$;

-- « ab_ » : après « aa_pm_sync_action_done » (800), qui fixe is_done à partir du
-- taux ; la règle voit donc l'état final de la ligne.
DROP TRIGGER IF EXISTS ab_pm_preuve_action ON public.task_actions;
CREATE TRIGGER ab_pm_preuve_action
  BEFORE INSERT OR UPDATE OF is_done, progress ON public.task_actions
  FOR EACH ROW EXECUTE FUNCTION public.pm_preuve_action();

REVOKE ALL ON FUNCTION public.pm_preuve_action() FROM PUBLIC, anon, authenticated;
