-- ============================================================
-- 513_regle_ventes_bl_transforme.sql — partie B, lot Ventes, règle R-009
--
-- Source : doc/audit/REFERENTIEL-CHAINAGES-TRANSVERSAUX-2026-09-24.md §B.2 (ligne 9) ;
-- inventaire mesuré : doc/audit/plan6/B1-INVENTAIRE-62-REGLES-2026-10-05.md (R-009 = ⬜).
--
-- R-009 — `delivery_notes.validation_status = draft / transformed` → « interdire toute
-- sortie de stock sur un brouillon ; lier au document transformé ».
--
-- MESURÉ (B.1). Aucun déclencheur ne testait `validation_status` sur `delivery_notes`.
--
-- CE QUE CE FICHIER FAIT — la partie SÛRE : le LIEN au document transformé
--   * au passage d'un BL à `validation_status = 'transformed'` : il LIE le BL aux
--     factures nées de lui (`invoices.delivery_note_id` = le BL), un lien
--     `invoiced_by` par facture, et émet `delivery_notes.transformed` ;
--   * IDEMPOTENT (les liens le gardent : `chain_deja_fait` lit `document_links`).
--
-- CE QUI EST LAISSÉ À LA COORDINATION (et pourquoi) — la GARDE
--   « interdire toute sortie de stock sur un brouillon » (refuser `shipped`/`delivered`
--   tant que `validation_status = 'draft'`) **n'est PAS posée** : le flux actuel
--   (écran `transformSalesOrderToDeliveryNote` puis expédition) crée des BL avec
--   `validation_status = 'draft'` par défaut et les EXPÉDIE — la garde, seule,
--   bloquerait toutes les expéditions et ferait rougir les suites de stock (230,
--   242, 314, 419). Elle n'a de sens qu'**avec** l'écran qui valide le BL avant de
--   l'expédier (partie E, R7). Décision dite, pas subie.
--
-- PRIORITÉ R7 : aucune fonction existante réécrite (maillon neuf `regle_r009_…`).
-- ============================================================

-- ── 1. Le contrat d'effet (L7 / M-05) ──
INSERT INTO document_effects (tenant_id, document_type, evenement, effet,
                              ecrit_comptable, journal_code, touche_stock, touche_paie,
                              reversible, obligatoire, actif, note)
VALUES (NULL, 'delivery_notes', 'transformed', 'sale.delivery.transformed',
        false, NULL, false, false, true, false, true,
        'R-009 : BL transformé — lien vers les factures nées de lui. Partie B, lot Ventes.')
ON CONFLICT DO NOTHING;

-- ── 2. Le maillon : BL transformé → lien aux factures ──
CREATE OR REPLACE FUNCTION public.regle_r009_bl_transforme()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $maillon$
DECLARE
  v_debut timestamptz := clock_timestamp();
  v_liens integer := 0;
  v_f     record;
BEGIN
  IF NEW.validation_status IS NOT DISTINCT FROM OLD.validation_status
     OR NEW.validation_status IS DISTINCT FROM 'transformed' THEN
    RETURN NULL;
  END IF;
  IF NEW.tenant_id IS NULL THEN RETURN NULL; END IF;

  -- Entrée du maillon — rejeu (ce maillon pose des liens), contrat, drapeau.
  IF NOT chain_avant(NEW.tenant_id, 'delivery_notes', 'transformed', 'sale.delivery.transformed',
                     'delivery_notes', NEW.id, NULL,
                     format('BL %s : le lien vers sa facture n''a pas été posé (règle sale.delivery.transformed, module ventes).',
                            NEW.number)) THEN
    RETURN NULL;
  END IF;

  -- Le lien au document transformé : une facture née de ce BL.
  FOR v_f IN
    SELECT i.id, i.number FROM invoices i
    WHERE i.tenant_id = NEW.tenant_id AND i.delivery_note_id = NEW.id
    ORDER BY i.number
  LOOP
    PERFORM link_documents(NEW.tenant_id, 'delivery_notes', NEW.id, 'invoices', v_f.id,
                           'sale.delivery.transformed', 'invoiced_by',
                           jsonb_build_object('delivery_number', NEW.number, 'invoice_number', v_f.number));
    v_liens := v_liens + 1;
  END LOOP;

  IF v_liens = 0 THEN
    PERFORM chain_apres(NEW.tenant_id, 'sale.delivery.transformed', 'delivery_notes', NEW.id,
                        v_debut, 0, 'sans_effet', 'Aucune facture née de ce BL : rien à lier.', NULL, NULL);
    RETURN NULL;
  END IF;

  PERFORM emit_domain_event(NEW.tenant_id, 'delivery_notes.transformed', 'delivery_notes', NEW.id,
                            jsonb_build_object('number', NEW.number, 'factures', v_liens), NULL);

  PERFORM chain_apres(NEW.tenant_id, 'sale.delivery.transformed', 'delivery_notes', NEW.id,
                      v_debut, v_liens, 'applique', NULL, NULL, NULL);
  RETURN NULL;
END $maillon$;

-- ── 3. Le déclencheur (`zz_` : il passe APRÈS les déclencheurs métier) ──
DROP TRIGGER IF EXISTS zz_b2r009_bl_transforme ON delivery_notes;
CREATE TRIGGER zz_b2r009_bl_transforme
AFTER UPDATE ON delivery_notes
FOR EACH ROW
EXECUTE FUNCTION public.regle_r009_bl_transforme();

-- Le maillon n'est pas un point d'entrée (aucun EXECUTE pour les rôles applicatifs).
REVOKE ALL ON FUNCTION public.regle_r009_bl_transforme() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.regle_r009_bl_transforme() TO service_role;
