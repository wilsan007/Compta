-- ============================================================
-- 517_regle_projets_cloture.sql — partie B, lot Projets, règles R-040, R-041, R-042
--
-- Source : doc/audit/REFERENTIEL-CHAINAGES-TRANSVERSAUX-2026-09-24.md §B.2 (lignes 40-42) ;
-- inventaire mesuré : doc/audit/plan6/B1-INVENTAIRE-62-REGLES-2026-10-05.md (R-040/041/042 = ⬜).
--
--   R-040 — `projects.status = completed` → clôture : encours (WIP), facturation
--           finale, retenue de garantie, libération des engagements, immobilisation ;
--   R-041 — `projects.status = cancelled` → contre-passation des coûts en attente,
--           libération des engagements, analyse d'écart ;
--   R-042 — `projects.status = on_hold` → alerte de dérive, blocage de la facturation
--           à l'avancement.
--
-- MESURÉ (B.1). `projects` n'avait que `projects_updated_at` + `set_tenant_id` : aucun
-- de ces trois états ne produisait quoi que ce soit.
--
-- CE QUE CE FICHIER FAIT — trois maillons « événement » (accroches)
--   * `completed` : émet `projects.completed` ;
--   * `cancelled` : émet `projects.cancelled` ;
--   * `on_hold`   : émet `projects.on_hold`.
--   IDEMPOTENTS (garde propre : pas de lien).
--
-- CE QUI RESTE À LA COORDINATION : le WIP / la facturation finale / la retenue de
-- garantie (R-040), la contre-passation des coûts (R-041), le blocage de facturation
-- (R-042) sont des effets comptables / métier — à faire avec le noyau et les écrans
-- projets (partie F), pas posés seuls.
--
-- PRIORITÉ R7 : aucune fonction existante réécrite (maillon neuf `regle_projet_…`).
-- ============================================================

-- ── 1. Les contrats d'effet (L7 / M-05) ──
INSERT INTO document_effects (tenant_id, document_type, evenement, effet,
                              ecrit_comptable, journal_code, touche_stock, touche_paie,
                              reversible, obligatoire, actif, note)
VALUES (NULL, 'projects', 'completed', 'project.completed',
        false, NULL, false, false, true, false, true, 'R-040 : clôture de projet. Partie B, lot Projets.'),
       (NULL, 'projects', 'cancelled', 'project.cancelled',
        false, NULL, false, false, true, false, true, 'R-041 : projet annulé. Partie B, lot Projets.'),
       (NULL, 'projects', 'on_hold', 'project.on_hold',
        false, NULL, false, false, true, false, true, 'R-042 : projet en attente. Partie B, lot Projets.')
ON CONFLICT DO NOTHING;

-- ── 2. Le maillon : état d'un projet → événement ──
CREATE OR REPLACE FUNCTION public.regle_projet_etat()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $maillon$
DECLARE
  v_debut timestamptz := clock_timestamp();
  v_event text;
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status OR NEW.status NOT IN ('completed', 'cancelled', 'on_hold') THEN
    RETURN NULL;
  END IF;
  IF NEW.tenant_id IS NULL THEN RETURN NULL; END IF;

  v_event := 'projects.' || NEW.status;

  IF EXISTS (SELECT 1 FROM domain_events de
             WHERE de.tenant_id = NEW.tenant_id AND de.event_name = v_event AND de.aggregate_id = NEW.id) THEN
    RETURN NULL;
  END IF;

  IF NOT chain_avant(NEW.tenant_id, 'projects', NEW.status, 'project.' || NEW.status,
                     'projects', NEW.id, NULL,
                     format('Projet %s : l''état « %s » n''a pas été tracé (règle project.%s, module projets).',
                            NEW.name, NEW.status, NEW.status)) THEN
    RETURN NULL;
  END IF;

  PERFORM emit_domain_event(NEW.tenant_id, v_event, 'projects', NEW.id,
                            jsonb_build_object('name', NEW.name, 'status', NEW.status), NULL);

  PERFORM chain_apres(NEW.tenant_id, 'project.' || NEW.status, 'projects', NEW.id,
                      v_debut, 0, 'applique', NULL, NULL, NULL);
  RETURN NULL;
END $maillon$;

-- ── 3. Le déclencheur (`zz_` : il passe APRÈS les déclencheurs métier) ──
DROP TRIGGER IF EXISTS zz_b2r040_r042_projet_etat ON projects;
CREATE TRIGGER zz_b2r040_r042_projet_etat
AFTER UPDATE ON projects
FOR EACH ROW
EXECUTE FUNCTION public.regle_projet_etat();

-- Le maillon n'est pas un point d'entrée (aucun EXECUTE pour les rôles applicatifs).
REVOKE ALL ON FUNCTION public.regle_projet_etat() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.regle_projet_etat() TO service_role;
