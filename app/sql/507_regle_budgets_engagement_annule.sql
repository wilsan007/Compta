-- ============================================================
-- 507_regle_budgets_engagement_annule.sql — partie B, lot Budgets, règle R-058
--
-- Source : doc/audit/REFERENTIEL-CHAINAGES-TRANSVERSAUX-2026-09-24.md §B.2 (ligne 58) ;
-- inventaire mesuré : doc/audit/plan6/B1-INVENTAIRE-62-REGLES-2026-10-05.md (R-058 = 🟨).
--
-- R-058 — `budget_commitments.status = cancelled` → « libération motivée, avec trace ».
--
-- MESURÉ (B.1, partielle). L'annulation d'un engagement EXISTE déjà — mais seulement
-- comme EFFET DE BORD : `sync_commitments_on_purchase_order` passe les engagements à
-- `cancelled` quand la COMMANDE est annulée. Rien ne TRACE l'annulation directe (une
-- annulation posée à la main, ou héritée) : pas d'événement, pas de trace de chaîne.
--
-- CE QUE CE FICHIER FAIT — la TRACE de l'annulation (maillon événement)
--   * au passage d'un engagement à `cancelled` : émet `budget_commitments.cancelled`
--     (numéro de la commande source, compte, montant, motif éventuel) et trace le
--     maillon. C'est le point d'accroche de la « trace motivée » que R-058 exige ;
--   * IDEMPOTENT (garde propre : ce maillon ne pose aucun lien).
--
-- CE QUE CE FICHIER NE FAIT PAS : il ne DÉCIDE pas de l'annulation (le geste reste
-- métier ou porté par R-012), il la rend observable.
--
-- PRIORITÉ R7 : aucune fonction existante réécrite.
-- ============================================================

-- ── 1. Le contrat d'effet (L7 / M-05) ──
INSERT INTO document_effects (tenant_id, document_type, evenement, effet,
                              ecrit_comptable, journal_code, touche_stock, touche_paie,
                              reversible, obligatoire, actif, note)
VALUES (NULL, 'budget_commitments', 'cancelled', 'budget.commitment.cancelled',
        false, NULL, false, false, true, false, true,
        'R-058 : engagement libéré (annulation) — trace motivée. Partie B, lot Budgets.')
ON CONFLICT DO NOTHING;

-- ── 2. Le maillon : engagement annulé → événement ──
CREATE OR REPLACE FUNCTION public.regle_r058_engagement_annule()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $maillon$
DECLARE
  v_debut timestamptz := clock_timestamp();
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status OR NEW.status IS DISTINCT FROM 'cancelled' THEN
    RETURN NULL;
  END IF;
  IF NEW.tenant_id IS NULL THEN RETURN NULL; END IF;

  -- Idempotence propre (ce maillon ne pose aucun lien).
  IF EXISTS (SELECT 1 FROM domain_events de
             WHERE de.tenant_id = NEW.tenant_id
               AND de.event_name = 'budget_commitments.cancelled'
               AND de.aggregate_id = NEW.id) THEN
    RETURN NULL;
  END IF;

  IF NOT chain_avant(NEW.tenant_id, 'budget_commitments', 'cancelled', 'budget.commitment.cancelled',
                     'budget_commitments', NEW.id, NULL,
                     format('Engagement %s : la libération n''a pas été tracée (règle budget.commitment.cancelled, module budgets).',
                            NEW.description)) THEN
    RETURN NULL;
  END IF;

  PERFORM emit_domain_event(NEW.tenant_id, 'budget_commitments.cancelled', 'budget_commitments', NEW.id,
                            jsonb_build_object('description', NEW.description, 'account_code', NEW.account_code,
                                               'amount', NEW.amount, 'source_type', NEW.source_type,
                                               'source_id', NEW.source_id, 'note', NEW.notes), NULL);

  PERFORM chain_apres(NEW.tenant_id, 'budget.commitment.cancelled', 'budget_commitments', NEW.id,
                      v_debut, 0, 'applique', NULL, NULL, NULL);
  RETURN NULL;
END $maillon$;

-- ── 3. Le déclencheur (`zz_` : il passe APRÈS les déclencheurs métier) ──
DROP TRIGGER IF EXISTS zz_b2r058_engagement_annule ON budget_commitments;
CREATE TRIGGER zz_b2r058_engagement_annule
AFTER UPDATE ON budget_commitments
FOR EACH ROW
EXECUTE FUNCTION public.regle_r058_engagement_annule();

-- Le maillon n'est pas un point d'entrée (aucun EXECUTE pour les rôles applicatifs).
REVOKE ALL ON FUNCTION public.regle_r058_engagement_annule() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.regle_r058_engagement_annule() TO service_role;
