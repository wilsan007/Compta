-- ============================================================
-- 518_regle_rh_contrats_et_note_frais.sql — partie B, lot Paie/RH, R-031, R-037, R-038, R-039
--
-- Source : doc/audit/REFERENTIEL-CHAINAGES-TRANSVERSAUX-2026-09-24.md §B.2 (lignes 31, 37-39) ;
-- inventaire mesuré : doc/audit/plan6/B1-INVENTAIRE-62-REGLES-2026-10-05.md (R-031/037/038/039 = ⬜).
--
--   R-031 — `expense_reports.status = rejected` → libération de la réservation, retour
--           au salarié avec motif ;
--   R-037 — `contracts.status = ended / terminated` → solde de tout compte, DSN de fin
--           de contrat, restitution du matériel, révocation des accès, provision CP ;
--   R-038 — `contracts.status = suspended` → proratisation de la paie, arrêt des
--           accumulations, information RH ;
--   R-039 — `contracts.contract_type` (CDD, apprentissage, stage, interim, freelance) →
--           règles distinctes : échéance & prime de précarité, exonérations, gratification…
--
-- MESURÉ (B.1). `contracts` n'avait que `set_tenant_id` ; `expense_reports` ne testait
-- pas `rejected`. Ces états ne produisaient rien.
--
-- CE QUE CE FICHIER FAIT — maillons « événement » (accroches)
--   * `expense_reports.rejected` (R-031) ;
--   * `contracts.created` (R-039, avec le `contract_type` — le point d'accroche des
--     règles par type, qui restent à écrire côté paie) ;
--   * `contracts.ended` / `contracts.terminated` (R-037) et `contracts.suspended` (R-038).
--   IDEMPOTENTS (garde propre : pas de lien).
--
-- CE QUI RESTE À LA COORDINATION : le solde de tout compte / la DSN de fin de contrat /
-- la révocation des accès (R-037), la proratisation (R-038) et les règles PAR TYPE
-- (prime de précarité, exonérations, gratification — R-039) sont des effets de PAIE, à
-- écrire avec le moteur de paie (module paie/RH, R7) — l'événement en est l'accroche.
--
-- PRIORITÉ R7 : aucune fonction existante réécrite (maillons neufs `regle_rh_…`).
-- ============================================================

-- ── 1. Les contrats d'effet (L7 / M-05) ──
INSERT INTO document_effects (tenant_id, document_type, evenement, effet,
                              ecrit_comptable, journal_code, touche_stock, touche_paie,
                              reversible, obligatoire, actif, note)
VALUES (NULL, 'expense_reports', 'rejected', 'expense.report.rejected',
        false, NULL, false, false, true, false, true, 'R-031 : note de frais rejetée. Partie B, lot Paie/RH.'),
       (NULL, 'contracts', 'created', 'payroll.contract.created',
        false, NULL, false, true, true, false, true, 'R-039 : contrat créé — règles par type. Partie B, lot Paie/RH.'),
       (NULL, 'contracts', 'ended', 'payroll.contract.ended',
        false, NULL, false, true, true, false, true, 'R-037 : fin de contrat. Partie B, lot Paie/RH.'),
       (NULL, 'contracts', 'terminated', 'payroll.contract.terminated',
        false, NULL, false, true, true, false, true, 'R-037 : rupture de contrat. Partie B, lot Paie/RH.'),
       (NULL, 'contracts', 'suspended', 'payroll.contract.suspended',
        false, NULL, false, true, true, false, true, 'R-038 : contrat suspendu. Partie B, lot Paie/RH.')
ON CONFLICT DO NOTHING;

-- ── 2. R-031 — la note de frais rejetée ──
CREATE OR REPLACE FUNCTION public.regle_rh_note_frais_rejetee()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $maillon$
DECLARE
  v_debut timestamptz := clock_timestamp();
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status OR NEW.status IS DISTINCT FROM 'rejected' THEN
    RETURN NULL;
  END IF;
  IF NEW.tenant_id IS NULL THEN RETURN NULL; END IF;

  IF EXISTS (SELECT 1 FROM domain_events de
             WHERE de.tenant_id = NEW.tenant_id AND de.event_name = 'expense_reports.rejected' AND de.aggregate_id = NEW.id) THEN
    RETURN NULL;
  END IF;

  IF NOT chain_avant(NEW.tenant_id, 'expense_reports', 'rejected', 'expense.report.rejected',
                     'expense_reports', NEW.id, NULL,
                     format('Note de frais %s : le rejet n''a pas été tracé (règle expense.report.rejected, module paie/RH).',
                            NEW.number)) THEN
    RETURN NULL;
  END IF;

  PERFORM emit_domain_event(NEW.tenant_id, 'expense_reports.rejected', 'expense_reports', NEW.id,
                            jsonb_build_object('number', NEW.number, 'employee_id', NEW.employee_id,
                                               'total_amount', NEW.total_amount), NULL);

  PERFORM chain_apres(NEW.tenant_id, 'expense.report.rejected', 'expense_reports', NEW.id,
                      v_debut, 0, 'applique', NULL, NULL, NULL);
  RETURN NULL;
END $maillon$;

-- ── 3. R-037 / R-038 / R-039 — le contrat ──
CREATE OR REPLACE FUNCTION public.regle_rh_contrat()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $maillon$
DECLARE
  v_debut timestamptz := clock_timestamp();
  v_event text;
  v_effet text;
BEGIN
  IF NEW.tenant_id IS NULL THEN RETURN NULL; END IF;

  IF TG_OP = 'INSERT' THEN
    v_event := 'contracts.created'; v_effet := 'payroll.contract.created';   -- R-039
  ELSIF NEW.status IS DISTINCT FROM OLD.status AND NEW.status IN ('ended', 'terminated', 'suspended') THEN
    v_event := 'contracts.' || NEW.status; v_effet := 'payroll.contract.' || NEW.status;  -- R-037 / R-038
  ELSE
    RETURN NULL;
  END IF;

  IF EXISTS (SELECT 1 FROM domain_events de
             WHERE de.tenant_id = NEW.tenant_id AND de.event_name = v_event AND de.aggregate_id = NEW.id) THEN
    RETURN NULL;
  END IF;

  IF NOT chain_avant(NEW.tenant_id, 'contracts', COALESCE(NEW.status, 'created'), v_effet,
                     'contracts', NEW.id, NULL,
                     format('Contrat %s : l''état (« %s ») n''a pas été tracé (règle %s, module paie/RH).',
                            NEW.number, v_event, v_effet)) THEN
    RETURN NULL;
  END IF;

  PERFORM emit_domain_event(NEW.tenant_id, v_event, 'contracts', NEW.id,
                            jsonb_build_object('number', NEW.number, 'employee_id', NEW.employee_id,
                                               'contract_type', NEW.contract_type, 'status', NEW.status), NULL);

  PERFORM chain_apres(NEW.tenant_id, v_effet, 'contracts', NEW.id,
                      v_debut, 0, 'applique', NULL, NULL, NULL);
  RETURN NULL;
END $maillon$;

-- ── 4. Les déclencheurs (`zz_` : ils passent APRÈS les déclencheurs métier) ──
DROP TRIGGER IF EXISTS zz_b2r031_note_frais_rejetee ON expense_reports;
CREATE TRIGGER zz_b2r031_note_frais_rejetee
AFTER UPDATE ON expense_reports
FOR EACH ROW
EXECUTE FUNCTION public.regle_rh_note_frais_rejetee();

DROP TRIGGER IF EXISTS zz_b2r037_r039_contrat ON contracts;
CREATE TRIGGER zz_b2r037_r039_contrat
AFTER INSERT OR UPDATE ON contracts
FOR EACH ROW
EXECUTE FUNCTION public.regle_rh_contrat();

-- Ces maillons ne sont pas des points d'entrée (aucun EXECUTE pour les rôles applicatifs).
REVOKE ALL ON FUNCTION public.regle_rh_note_frais_rejetee() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.regle_rh_contrat() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.regle_rh_note_frais_rejetee() TO service_role;
GRANT EXECUTE ON FUNCTION public.regle_rh_contrat() TO service_role;
