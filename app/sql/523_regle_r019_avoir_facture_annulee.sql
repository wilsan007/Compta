-- ============================================================
-- 523_regle_r019_avoir_facture_annulee.sql — partie B, lot Ventes, règle R-019 (compléter)
--
-- Source : doc/audit/REFERENTIEL-CHAINAGES-TRANSVERSAUX-2026-09-24.md §B.2 (ligne 19) ;
-- inventaire mesuré : doc/audit/plan6/B1-INVENTAIRE-62-REGLES-2026-10-05.md (R-019 = ⬜/🟨).
--
-- R-019 — `invoices.status = cancelled` → « avoir ou contre-passation, sortie du lettrage,
-- régénération de la TVA, arrêt des relances ».
--
-- MESURÉ : la `519` a rendu l'état `cancelled` OBSERVABLE (événement). Ce fichier en fait
-- l'EFFET principal : un **AVOIR** (crédit note) né de la facture annulée, et l'**ARRÊT
-- DES RELANCES**. La contre-passation comptable de l'avoir est portée par la chaîne de
-- l'avoir (`chain_l1_credit_note_entry`, à sa validation), pas réécrite ici.
--
-- CE QUE CE FICHIER FAIT — un maillon (liens + écritures métier)
--   * à l'annulation d'une facture : crée un AVOIR en brouillon qui la reprend (en-tête +
--     lignes), le LIE à la facture (`reversed_by`), et ANNULE les relances ouvertes de la
--     facture (`collection_reminders` → `cancelled`, ce qui déclenche R-060/R-061) ;
--   * IDEMPOTENT : si un avoir existe déjà pour cette facture, il ne fait rien.
--
-- CE QUI RESTE À LA COORDINATION : la SORTIE DU LETTRAGE et la RÉGÉNÉRATION DE LA TVA
-- sont portées par la validation de l'avoir (chaîne existante) ; elles ne sont pas refaites
-- ici. La contre-passation d'écriture est celle de l'avoir validé.
--
-- PRIORITÉ R7 : aucune fonction existante réécrite (maillon neuf `regle_r019_…`).
-- ============================================================

INSERT INTO document_effects (tenant_id, document_type, evenement, effet,
                              ecrit_comptable, journal_code, touche_stock, touche_paie,
                              reversible, obligatoire, actif, note)
VALUES (NULL, 'invoices', 'cancelled', 'sale.credit_note.from_invoice',
        false, NULL, false, false, true, false, true,
        'R-019 : facture client annulée — avoir + arrêt des relances. Partie B, lot Ventes.')
ON CONFLICT DO NOTHING;

-- ── Le maillon : facture annulée → avoir + arrêt des relances ──
CREATE OR REPLACE FUNCTION public.regle_r019_avoir_facture_annulee()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $maillon$
DECLARE
  v_debut    timestamptz := clock_timestamp();
  v_cn       uuid := gen_random_uuid();
  v_num      text;
  v_relances integer := 0;
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status OR NEW.status IS DISTINCT FROM 'cancelled' THEN
    RETURN NULL;
  END IF;
  IF NEW.tenant_id IS NULL THEN RETURN NULL; END IF;

  -- Idempotence : un avoir existe déjà pour cette facture ?
  IF EXISTS (SELECT 1 FROM credit_notes cn
             WHERE cn.tenant_id = NEW.tenant_id AND (cn.invoice_id = NEW.id OR cn.source_invoice_id = NEW.id)
               AND cn.status IS DISTINCT FROM 'cancelled') THEN
    RETURN NULL;
  END IF;

  -- Entrée du maillon (rejeu par le lien, contrat, drapeau).
  IF NOT chain_avant(NEW.tenant_id, 'invoices', 'cancelled', 'sale.credit_note.from_invoice',
                     'invoices', NEW.id, NULL,
                     format('Facture %s : l''avoir de contre-passation n''a pas été produit (règle sale.credit_note.from_invoice, module ventes).',
                            NEW.number)) THEN
    RETURN NULL;
  END IF;

  -- 1. L'AVOIR en brouillon, qui reprend l'en-tête de la facture.
  v_num := draft_document_number('AV', v_cn);
  INSERT INTO credit_notes (id, tenant_id, number, customer_id, customer_name, date, status,
                            subtotal, vat_total, total, reason, invoice_id, source_invoice_id)
  VALUES (v_cn, NEW.tenant_id, v_num, NEW.customer_id, NEW.customer_name, CURRENT_DATE, 'draft',
          COALESCE(NEW.subtotal, 0), COALESCE(NEW.vat_total, 0), COALESCE(NEW.total, 0),
          'Annulation facture ' || NEW.number, NEW.id, NEW.id);

  -- 2. Les LIGNES, reprises de la facture.
  INSERT INTO credit_note_lines (tenant_id, credit_note_id, product_id, description, quantity,
                                 unit_price, vat_rate, total, vat_total, vat_amount, line_order)
  SELECT NEW.tenant_id, v_cn, il.product_id, il.description, il.quantity, il.unit_price, il.vat_rate,
         COALESCE(il.total, 0), COALESCE(il.vat_total, 0),
         COALESCE(il.vat_total, round(COALESCE(il.quantity, 0) * COALESCE(il.unit_price, 0) * COALESCE(il.vat_rate, 0) / 100, 2)),
         COALESCE(il.line_order, 0)
  FROM invoice_lines il
  WHERE il.invoice_id = NEW.id AND il.tenant_id = NEW.tenant_id;

  -- 3. Le LIEN facture → avoir (la contre-passation, tracée).
  PERFORM link_documents(NEW.tenant_id, 'invoices', NEW.id, 'credit_notes', v_cn,
                         'sale.credit_note.from_invoice', 'reversed_by',
                         jsonb_build_object('invoice_number', NEW.number, 'credit_note_number', v_num));

  -- 4. L'ARRÊT DES RELANCES : les relances ouvertes de la facture sont annulées
  --    (ce qui déclenche R-060/R-061 et leurs événements).
  UPDATE collection_reminders
  SET status = 'cancelled'
  WHERE tenant_id = NEW.tenant_id AND invoice_id = NEW.id
    AND status IN ('draft', 'pending', 'sent');
  GET DIAGNOSTICS v_relances = ROW_COUNT;

  PERFORM emit_domain_event(NEW.tenant_id, 'credit_notes.created_from_invoice', 'invoices', NEW.id,
                            jsonb_build_object('invoice_number', NEW.number, 'credit_note_id', v_cn,
                                               'credit_note_number', v_num, 'relances_annulees', v_relances), NULL);

  PERFORM chain_apres(NEW.tenant_id, 'sale.credit_note.from_invoice', 'invoices', NEW.id,
                      v_debut, 1, 'applique', NULL, NULL, NULL);
  RETURN NULL;
END $maillon$;

DROP TRIGGER IF EXISTS zz_b2r019_avoir_facture_annulee ON invoices;
CREATE TRIGGER zz_b2r019_avoir_facture_annulee
AFTER UPDATE ON invoices
FOR EACH ROW EXECUTE FUNCTION public.regle_r019_avoir_facture_annulee();

REVOKE ALL ON FUNCTION public.regle_r019_avoir_facture_annulee() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.regle_r019_avoir_facture_annulee() TO service_role;
