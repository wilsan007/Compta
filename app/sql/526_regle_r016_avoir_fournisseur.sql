-- ============================================================
-- 526_regle_r016_avoir_fournisseur.sql — partie B, lot Achats, règle R-016 (compléter)
--
-- Source : doc/audit/REFERENTIEL-CHAINAGES-TRANSVERSAUX-2026-09-24.md §B.2 (ligne 16) ;
-- inventaire mesuré : doc/audit/plan6/B1-INVENTAIRE-62-REGLES-2026-10-05.md (R-016 = 🟨).
--
-- R-016 — `purchase_invoices.status = cancelled` → contre-passation de la charge et de la
-- TVA, restitution du règlement, sortie du lettrage et de l'état de TVA.
--
-- MESURÉ : la `511` a rendu l'état `cancelled` OBSERVABLE (événement). Ce fichier en fait
-- l'EFFET principal : un **AVOIR FOURNISSEUR** né de la facture annulée.
--
-- CE QUE CE FICHIER FAIT — un maillon (avoir + lien)
--   * à l'annulation d'une facture fournisseur : crée un AVOIR FOURNISSEUR en brouillon
--     (`purchase_credit_notes`) qui reprend l'en-tête (fournisseur, montants), le LIE à la
--     facture (`reversed_by`), et émet l'événement ;
--   * IDEMPOTENT : si un avoir existe déjà pour cette facture, il ne fait rien.
--
-- LIMITE DITE : `purchase_credit_notes` n'a **PAS de table de lignes** (contrairement aux
-- avoirs clients) — l'avoir est donc en EN-TÊTE. La contre-passation comptable de la
-- charge et de la TVA est portée par la VALIDATION de l'avoir
-- (`purchase_credit_note_after_validate`), pas réécrite ici ; la RESTITUTION DU RÈGLEMENT
-- et la SORTIE DU LETTRAGE suivent la chaîne des règlements fournisseur.
--
-- PRIORITÉ R7 : aucune fonction existante réécrite (maillon neuf `regle_r016_…`).
-- ============================================================

-- ── 1. Le contrat d'effet + le registre des types (450) ──
INSERT INTO document_effects (tenant_id, document_type, evenement, effet,
                              ecrit_comptable, journal_code, touche_stock, touche_paie,
                              reversible, obligatoire, actif, note)
VALUES (NULL, 'purchase_invoices', 'cancelled', 'purchase.credit_note.from_invoice',
        false, NULL, false, false, true, false, true,
        'R-016 : facture fournisseur annulée — avoir fournisseur. Partie B, lot Achats.')
ON CONFLICT DO NOTHING;

INSERT INTO chain_document_types (code, table_name, ligne_table, libelle_fr)
VALUES ('purchase_credit_notes', 'purchase_credit_notes', NULL, 'Avoir fournisseur')
ON CONFLICT DO NOTHING;

-- ── 2. Le maillon : facture fournisseur annulée → avoir fournisseur ──
CREATE OR REPLACE FUNCTION public.regle_r016_avoir_fournisseur()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $maillon$
DECLARE
  v_debut timestamptz := clock_timestamp();
  v_pcn   uuid := gen_random_uuid();
  v_num   text;
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status OR NEW.status IS DISTINCT FROM 'cancelled' THEN
    RETURN NULL;
  END IF;
  IF NEW.tenant_id IS NULL THEN RETURN NULL; END IF;

  -- Idempotence : un avoir fournisseur existe déjà pour cette facture ?
  IF EXISTS (SELECT 1 FROM purchase_credit_notes pcn
             WHERE pcn.tenant_id = NEW.tenant_id AND pcn.purchase_invoice_id = NEW.id) THEN
    RETURN NULL;
  END IF;

  IF NOT chain_avant(NEW.tenant_id, 'purchase_invoices', 'cancelled', 'purchase.credit_note.from_invoice',
                     'purchase_invoices', NEW.id, NULL,
                     format('Facture fournisseur %s : l''avoir de contre-passation n''a pas été produit (règle purchase.credit_note.from_invoice, module achats).',
                            NEW.number)) THEN
    RETURN NULL;
  END IF;

  -- L'AVOIR FOURNISSEUR en brouillon (en-tête).
  v_num := draft_document_number('AVF', v_pcn);
  INSERT INTO purchase_credit_notes (id, tenant_id, number, supplier_id, supplier_name, date, status,
                                     subtotal, vat_total, total, reason, purchase_invoice_id, supplier_reference)
  VALUES (v_pcn, NEW.tenant_id, v_num, NEW.supplier_id, NEW.supplier_name, CURRENT_DATE, 'draft',
          COALESCE(NEW.subtotal, 0), COALESCE(NEW.vat_total, 0), COALESCE(NEW.total, 0),
          'Annulation facture ' || NEW.number, NEW.id, NEW.supplier_reference);

  -- Le LIEN facture fournisseur → avoir (la contre-passation, tracée).
  PERFORM link_documents(NEW.tenant_id, 'purchase_invoices', NEW.id, 'purchase_credit_notes', v_pcn,
                         'purchase.credit_note.from_invoice', 'reversed_by',
                         jsonb_build_object('invoice_number', NEW.number, 'credit_note_number', v_num));

  PERFORM emit_domain_event(NEW.tenant_id, 'purchase_credit_notes.created_from_invoice', 'purchase_invoices', NEW.id,
                            jsonb_build_object('invoice_number', NEW.number, 'credit_note_id', v_pcn,
                                               'credit_note_number', v_num), NULL);

  PERFORM chain_apres(NEW.tenant_id, 'purchase.credit_note.from_invoice', 'purchase_invoices', NEW.id,
                      v_debut, 1, 'applique', NULL, NULL, NULL);
  RETURN NULL;
END $maillon$;

DROP TRIGGER IF EXISTS zz_b2r016_avoir_fournisseur ON purchase_invoices;
CREATE TRIGGER zz_b2r016_avoir_fournisseur
AFTER UPDATE ON purchase_invoices
FOR EACH ROW EXECUTE FUNCTION public.regle_r016_avoir_fournisseur();

REVOKE ALL ON FUNCTION public.regle_r016_avoir_fournisseur() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.regle_r016_avoir_fournisseur() TO service_role;
