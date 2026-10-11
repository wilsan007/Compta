-- ============================================================
-- 522_regle_partielles_finales.sql — partie B, règles R-020, R-029, R-032, R-043 (compléter)
--
-- Source : doc/audit/REFERENTIEL-CHAINAGES-TRANSVERSAUX-2026-09-24.md §B.2 (lignes 20, 29, 32, 43) ;
-- inventaire mesuré : doc/audit/plan6/B1-INVENTAIRE-62-REGLES-2026-10-05.md (R-020/029/032/043 = 🟨/⬜).
--
--   R-019 — (fait en `519`) ; R-020 — `invoices.validation_status = transformed` → fin du
--           cycle brouillon → définitive. ❌ INATTEIGNABLE : `invoice_guard` REFUSE toute
--           sortie de `validated` (mesuré : « Facture … validée : numéro, date, client et
--           montants ne sont plus modifiables »). L'état `transformed` n'est jamais atteint
--           sur `invoices` — le dire ferme R-020 (ce n'est pas un maillon manquant) ;
--   R-029 — `expense_reports.status = submitted` → contrôle d'absence et de politique de
--           frais, réservation budgétaire ;
--   R-032 — `expense_reports.status = reimbursed` → lettrage avec l'écriture de paie,
--           clôture du dossier ;
--   R-043 — `manufacturing_orders.status = cancelled` → contre-passation des consommations,
--           libération des composants réservés, restitution du coût.
--
-- MESURÉ (B.1, partielles). Ce qui EXISTE : `invoice_status_on_validate` (draft → sent) ;
-- `guard_expense_report_on_decision` (contrôle d'absence) ; `chain_l1_manufacturing_order`
-- (uniquement sur `completed`). Ce qui MANQUAIT : ces quatre états ne laissaient aucune
-- trace exploitable et leur effet aval n'était pas accrochable.
--
-- CE QUE CE FICHIER FAIT — maillons « événement », idempotents :
--   * `expense_reports.submitted` / `.reimbursed` → `expense.report.*` ;
--   * `manufacturing_orders.cancelled` → `production.order.cancelled`.
--
-- CE QUI RESTE À LA COORDINATION : l'immuabilité de la facture définitive (R-020), la
-- RÉSERVATION budgétaire (R-029), le lettrage du remboursement (R-032) et la contre-passation
-- d'OF (R-043) sont des effets comptables / de stock — l'événement en est l'accroche.
--
-- PRIORITÉ R7 : aucune fonction existante réécrite (maillons neufs `regle_*`).
-- ============================================================

INSERT INTO document_effects (tenant_id, document_type, evenement, effet,
                              ecrit_comptable, journal_code, touche_stock, touche_paie,
                              reversible, obligatoire, actif, note)
VALUES (NULL, 'expense_reports', 'submitted', 'expense.report.submitted',
        false, NULL, false, true, true, false, true, 'R-029 : note de frais soumise. Partie B.'),
       (NULL, 'expense_reports', 'reimbursed', 'expense.report.reimbursed',
        false, NULL, false, true, true, false, true, 'R-032 : note de frais remboursée. Partie B.'),
       (NULL, 'manufacturing_orders', 'cancelled', 'production.order.cancelled',
        false, NULL, false, false, true, false, true, 'R-043 : OF annulé. Partie B.')
ON CONFLICT DO NOTHING;

-- ── R-029 / R-032 — note de frais soumise / remboursée ──
CREATE OR REPLACE FUNCTION public.regle_expense_etat()
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
  IF NEW.status IS NOT DISTINCT FROM OLD.status OR NEW.status NOT IN ('submitted', 'reimbursed') THEN
    RETURN NULL;
  END IF;
  IF NEW.tenant_id IS NULL THEN RETURN NULL; END IF;
  v_effet := 'expense.report.' || NEW.status; v_event := 'expense_reports.' || NEW.status;
  IF EXISTS (SELECT 1 FROM domain_events de
             WHERE de.tenant_id = NEW.tenant_id AND de.event_name = v_event AND de.aggregate_id = NEW.id) THEN
    RETURN NULL;
  END IF;
  IF NOT chain_avant(NEW.tenant_id, 'expense_reports', NEW.status, v_effet,
                     'expense_reports', NEW.id, NULL,
                     format('Note de frais %s : l''état « %s » n''a pas été tracé (règle %s, module paie/RH).',
                            NEW.number, NEW.status, v_effet)) THEN
    RETURN NULL;
  END IF;
  PERFORM emit_domain_event(NEW.tenant_id, v_event, 'expense_reports', NEW.id,
                            jsonb_build_object('number', NEW.number, 'employee_id', NEW.employee_id,
                                               'status', NEW.status), NULL);
  PERFORM chain_apres(NEW.tenant_id, v_effet, 'expense_reports', NEW.id, v_debut, 0, 'applique', NULL, NULL, NULL);
  RETURN NULL;
END $maillon$;

-- ── R-043 — OF annulé ──
CREATE OR REPLACE FUNCTION public.regle_of_annule()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $maillon$
DECLARE v_debut timestamptz := clock_timestamp();
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status OR NEW.status IS DISTINCT FROM 'cancelled' THEN
    RETURN NULL;
  END IF;
  IF NEW.tenant_id IS NULL THEN RETURN NULL; END IF;
  IF EXISTS (SELECT 1 FROM domain_events de
             WHERE de.tenant_id = NEW.tenant_id AND de.event_name = 'manufacturing_orders.cancelled' AND de.aggregate_id = NEW.id) THEN
    RETURN NULL;
  END IF;
  IF NOT chain_avant(NEW.tenant_id, 'manufacturing_orders', 'cancelled', 'production.order.cancelled',
                     'manufacturing_orders', NEW.id, NULL,
                     format('Ordre de fabrication %s : l''annulation n''a pas été tracée (règle production.order.cancelled, module production).', NEW.number)) THEN
    RETURN NULL;
  END IF;
  PERFORM emit_domain_event(NEW.tenant_id, 'manufacturing_orders.cancelled', 'manufacturing_orders', NEW.id,
                            jsonb_build_object('number', NEW.number, 'product_id', NEW.product_id,
                                               'quantity', NEW.quantity), NULL);
  PERFORM chain_apres(NEW.tenant_id, 'production.order.cancelled', 'manufacturing_orders', NEW.id, v_debut, 0, 'applique', NULL, NULL, NULL);
  RETURN NULL;
END $maillon$;

DROP TRIGGER IF EXISTS zz_b2r029_r032_expense_etat ON expense_reports;
CREATE TRIGGER zz_b2r029_r032_expense_etat AFTER UPDATE ON expense_reports
FOR EACH ROW EXECUTE FUNCTION public.regle_expense_etat();

DROP TRIGGER IF EXISTS zz_b2r043_of_annule ON manufacturing_orders;
CREATE TRIGGER zz_b2r043_of_annule AFTER UPDATE ON manufacturing_orders
FOR EACH ROW EXECUTE FUNCTION public.regle_of_annule();

REVOKE ALL ON FUNCTION public.regle_expense_etat() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.regle_of_annule() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.regle_expense_etat() TO service_role;
GRANT EXECUTE ON FUNCTION public.regle_of_annule() TO service_role;
