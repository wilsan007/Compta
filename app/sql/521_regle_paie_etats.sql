-- ============================================================
-- 521_regle_paie_etats.sql — partie B, lot Paie/RH, règles R-025, R-026, R-028 (compléter)
--
-- Source : doc/audit/REFERENTIEL-CHAINAGES-TRANSVERSAUX-2026-09-24.md §B.2 (lignes 25-28) ;
-- inventaire mesuré : doc/audit/plan6/B1-INVENTAIRE-62-REGLES-2026-10-05.md (R-025/026/028 = 🟨).
--
--   R-025 — `pay_runs.status = approved` → gel des bulletins, écriture de paie, ordre de
--           virement, alimentation de la DSN ;
--   R-026 — `pay_slips.status = approved` → immuabilité du bulletin, cumuls, archivage ;
--   R-028 — `pay_slips.status = paid` → écriture de règlement, rapprochement, clôture du lot.
--
-- MESURÉ (B.1, partielles). Ce qui EXISTE : `pay_run_require_slips_before_approval` (garde),
-- les cumuls (`payroll_cumulative_follow_slip`), le recalcul des totaux, et l'écriture —
-- posée au passage du LOT à `paid` (`create_journal_on_payroll_validate`), la DSN au
-- `closed` (`generate_dsn_on_payrun_close`). Ce qui MANQUAIT : l'ÉTAT `approved` (du lot
-- comme du bulletin) ne laissait AUCUNE trace exploitable.
--
-- CE QUE CE FICHIER FAIT — trois maillons « événement », idempotents
--   * `pay_runs.approved`  → `payroll.run.approved` ;   (accroche : gel, DSN)
--   * `pay_slips.approved` → `payroll.slip.approved` ;  (accroche : immuabilité, archivage)
--   * `pay_slips.paid`     → `payroll.slip.paid`.       (accroche : règlement, rapprochement)
--
-- CE QUI RESTE À LA COORDINATION — le TROU DE PAIE, dit : déplacer l'**écriture de paie**
-- du `paid` du lot vers son `approved` réécrirait `create_journal_on_payroll_validate`
-- (fonction EXISTANTE, R7) et changerait le comportement de paie à chaque release. C'est
-- une décision de paie à prendre avec l'expert-comptable (D-G) et le noyau — pas posée ici.
--
-- PRIORITÉ R7 : aucune fonction existante réécrite (maillons neufs `regle_paie_…`).
-- ============================================================

INSERT INTO document_effects (tenant_id, document_type, evenement, effet,
                              ecrit_comptable, journal_code, touche_stock, touche_paie,
                              reversible, obligatoire, actif, note)
VALUES (NULL, 'pay_runs', 'approved', 'payroll.run.approved',
        false, NULL, false, true, true, false, true, 'R-025 : lot de paie approuvé. Partie B, lot Paie/RH.'),
       (NULL, 'pay_slips', 'approved', 'payroll.slip.approved',
        false, NULL, false, true, true, false, true, 'R-026 : bulletin approuvé. Partie B, lot Paie/RH.'),
       (NULL, 'pay_slips', 'paid', 'payroll.slip.paid',
        false, NULL, false, true, true, false, true, 'R-028 : bulletin payé. Partie B, lot Paie/RH.')
ON CONFLICT DO NOTHING;

-- ── R-025 — lot de paie approuvé ──
CREATE OR REPLACE FUNCTION public.regle_paie_run_approuve()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $maillon$
DECLARE v_debut timestamptz := clock_timestamp();
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status OR NEW.status IS DISTINCT FROM 'approved' THEN
    RETURN NULL;
  END IF;
  IF NEW.tenant_id IS NULL THEN RETURN NULL; END IF;
  IF EXISTS (SELECT 1 FROM domain_events de
             WHERE de.tenant_id = NEW.tenant_id AND de.event_name = 'pay_runs.approved' AND de.aggregate_id = NEW.id) THEN
    RETURN NULL;
  END IF;
  IF NOT chain_avant(NEW.tenant_id, 'pay_runs', 'approved', 'payroll.run.approved',
                     'pay_runs', NEW.id, NULL,
                     format('Lot de paie %s : l''approbation n''a pas été tracée (règle payroll.run.approved, module paie).', NEW.number)) THEN
    RETURN NULL;
  END IF;
  PERFORM emit_domain_event(NEW.tenant_id, 'pay_runs.approved', 'pay_runs', NEW.id,
                            jsonb_build_object('number', NEW.number, 'period_start', NEW.period_start,
                                               'period_end', NEW.period_end), NULL);
  PERFORM chain_apres(NEW.tenant_id, 'payroll.run.approved', 'pay_runs', NEW.id, v_debut, 0, 'applique', NULL, NULL, NULL);
  RETURN NULL;
END $maillon$;

-- ── R-026 / R-028 — bulletin approuvé / payé ──
CREATE OR REPLACE FUNCTION public.regle_paie_slip_etat()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $maillon$
DECLARE
  v_debut timestamptz := clock_timestamp();
  v_effet text;
  v_event text;
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status OR NEW.status NOT IN ('approved', 'paid') THEN
    RETURN NULL;
  END IF;
  IF NEW.tenant_id IS NULL THEN RETURN NULL; END IF;

  v_effet := 'payroll.slip.' || NEW.status; v_event := 'pay_slips.' || NEW.status;

  IF EXISTS (SELECT 1 FROM domain_events de
             WHERE de.tenant_id = NEW.tenant_id AND de.event_name = v_event AND de.aggregate_id = NEW.id) THEN
    RETURN NULL;
  END IF;

  IF NOT chain_avant(NEW.tenant_id, 'pay_slips', NEW.status, v_effet,
                     'pay_slips', NEW.id, NULL,
                     format('Bulletin %s : l''état « %s » n''a pas été tracé (règle %s, module paie).',
                            NEW.number, NEW.status, v_effet)) THEN
    RETURN NULL;
  END IF;

  PERFORM emit_domain_event(NEW.tenant_id, v_event, 'pay_slips', NEW.id,
                            jsonb_build_object('number', NEW.number, 'employee_id', NEW.employee_id,
                                               'status', NEW.status), NULL);

  PERFORM chain_apres(NEW.tenant_id, v_effet, 'pay_slips', NEW.id, v_debut, 0, 'applique', NULL, NULL, NULL);
  RETURN NULL;
END $maillon$;

DROP TRIGGER IF EXISTS zz_b2r025_paie_run_approuve ON pay_runs;
CREATE TRIGGER zz_b2r025_paie_run_approuve
AFTER UPDATE ON pay_runs
FOR EACH ROW EXECUTE FUNCTION public.regle_paie_run_approuve();

DROP TRIGGER IF EXISTS zz_b2r026_r028_paie_slip_etat ON pay_slips;
CREATE TRIGGER zz_b2r026_r028_paie_slip_etat
AFTER UPDATE ON pay_slips
FOR EACH ROW EXECUTE FUNCTION public.regle_paie_slip_etat();

REVOKE ALL ON FUNCTION public.regle_paie_run_approuve() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.regle_paie_slip_etat() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.regle_paie_run_approuve() TO service_role;
GRANT EXECUTE ON FUNCTION public.regle_paie_slip_etat() TO service_role;
