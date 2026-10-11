-- ============================================================
-- 516_regle_conformite_tva_retour.sql — partie B, lot Conformité, règles R-052 et R-053
--
-- Source : doc/audit/REFERENTIEL-CHAINAGES-TRANSVERSAUX-2026-09-24.md §B.2 (lignes 52-53) ;
-- inventaire mesuré : doc/audit/plan6/B1-INVENTAIRE-62-REGLES-2026-10-05.md (R-052/053 = ⬜).
--
--   R-052 — `vat_returns.status = submitted` → statut vis-à-vis de l'administration,
--           gel des écritures de la période, lien avec la déclaration transmise ;
--   R-053 — `vat_returns.status = paid` → écriture de paiement de la TVA, rapprochement
--           bancaire, lettrage du compte de TVA.
--
-- MESURÉ (B.1). `vat_returns` n'a que `set_tenant_id` + `trg_refuse_client_edi_stamp` :
-- soumettre ou payer une déclaration de TVA ne produisait RIEN (ni trace, ni événement).
--
-- CE QUE CE FICHIER FAIT — deux maillons « événement » (accroches)
--   * `submitted` : émet `vat_returns.submitted` ;
--   * `paid`      : émet `vat_returns.paid`.
--   IDEMPOTENTS (garde propre : pas de lien). L'écrit par le SERVEUR (comme `edi_status`,
--   la porte `trg_refuse_client_edi_stamp` s'applique à `edi_status`, pas au `status`).
--
-- CE QUI RESTE À LA COORDINATION : le **gel des écritures de la période** (R-052) est un
-- verrou comptable, et l'**écriture de paiement + lettrage du compte de TVA** (R-053) est
-- un travail comptable — à faire avec le noyau (R7).
--
-- PRIORITÉ R7 : aucune fonction existante réécrite (maillon neuf `regle_tva_retour_…`).
-- ============================================================

-- ── 1. Les contrats d'effet (L7 / M-05) ──
INSERT INTO document_effects (tenant_id, document_type, evenement, effet,
                              ecrit_comptable, journal_code, touche_stock, touche_paie,
                              reversible, obligatoire, actif, note)
VALUES (NULL, 'vat_returns', 'submitted', 'tax.vat_return.submitted',
        false, NULL, false, false, true, false, true,
        'R-052 : déclaration de TVA soumise — statut vis-à-vis de l''administration. Partie B, lot Conformité.'),
       (NULL, 'vat_returns', 'paid', 'tax.vat_return.paid',
        false, NULL, false, false, true, false, true,
        'R-053 : déclaration de TVA payée. Partie B, lot Conformité.')
ON CONFLICT DO NOTHING;

-- ── 2. Le maillon : état de la déclaration de TVA → événement ──
CREATE OR REPLACE FUNCTION public.regle_tva_retour_etat()
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
  IF NEW.status IS NOT DISTINCT FROM OLD.status OR NEW.status NOT IN ('submitted', 'paid') THEN
    RETURN NULL;
  END IF;
  IF NEW.tenant_id IS NULL THEN RETURN NULL; END IF;

  IF NEW.status = 'submitted' THEN
    v_effet := 'tax.vat_return.submitted'; v_event := 'vat_returns.submitted';
  ELSE
    v_effet := 'tax.vat_return.paid'; v_event := 'vat_returns.paid';
  END IF;

  IF EXISTS (SELECT 1 FROM domain_events de
             WHERE de.tenant_id = NEW.tenant_id AND de.event_name = v_event AND de.aggregate_id = NEW.id) THEN
    RETURN NULL;
  END IF;

  IF NOT chain_avant(NEW.tenant_id, 'vat_returns', NEW.status, v_effet,
                     'vat_returns', NEW.id, NULL,
                     format('Déclaration de TVA %s : l''état « %s » n''a pas été tracé (règle %s, module conformité).',
                            NEW.id, NEW.status, v_effet)) THEN
    RETURN NULL;
  END IF;

  PERFORM emit_domain_event(NEW.tenant_id, v_event, 'vat_returns', NEW.id,
                            jsonb_build_object('status', NEW.status, 'period_start', NEW.period_start,
                                               'period_end', NEW.period_end), NULL);

  PERFORM chain_apres(NEW.tenant_id, v_effet, 'vat_returns', NEW.id,
                      v_debut, 0, 'applique', NULL, NULL, NULL);
  RETURN NULL;
END $maillon$;

-- ── 3. Le déclencheur (`zz_` : il passe APRÈS les déclencheurs métier) ──
DROP TRIGGER IF EXISTS zz_b2r052_r053_tva_retour ON vat_returns;
CREATE TRIGGER zz_b2r052_r053_tva_retour
AFTER UPDATE ON vat_returns
FOR EACH ROW
EXECUTE FUNCTION public.regle_tva_retour_etat();

-- Le maillon n'est pas un point d'entrée (aucun EXECUTE pour les rôles applicatifs).
REVOKE ALL ON FUNCTION public.regle_tva_retour_etat() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.regle_tva_retour_etat() TO service_role;
