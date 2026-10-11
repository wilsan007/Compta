-- ============================================================
-- 520_regle_paiements_annules.sql — partie B, lot Trésorerie, règles R-023 et R-024 (compléter)
--
-- Source : doc/audit/REFERENTIEL-CHAINAGES-TRANSVERSAUX-2026-09-24.md §B.2 (lignes 23-24) ;
-- inventaire mesuré : doc/audit/plan6/B1-INVENTAIRE-62-REGLES-2026-10-05.md (R-023/024 = 🟨).
--
--   R-023 — `customer_payments.status = cancelled` → délettrage, réouverture de la
--           facture, remise en relance ;
--   R-024 — `supplier_payments.status = cancelled` → délettrage, réouverture de la dette,
--           restitution du prévisionnel.
--
-- MESURÉ (B.1, partielle). La RÉOUVERTURE existe DÉJÀ : `update_invoice_on_customer_payment`
-- et `update_invoice_on_supplier_payment` (IU) appellent `refresh_invoice_settlement`, qui
-- recalcule reste dû / statut / lettrage — donc annuler un règlement rouvre bien la pièce.
-- Ce qui MANQUAIT : la TRACE de l'annulation (aucun événement) et l'accroche de RELANCE.
--
-- CE QUE CE FICHIER FAIT — deux maillons « événement », idempotents
--   * `customer_payments.cancelled` → `sale.payment.cancelled` ;
--   * `supplier_payments.cancelled` → `purchase.payment.cancelled`.
--   L'événement est le point d'accroche de la REMISE EN RELANCE (R-059, module ventes).
--
-- CE QUI RESTE (déjà fait ailleurs, non refait) : la réouverture / le délettrage
-- (`refresh_invoice_settlement`, existant) ; la restitution du prévisionnel de trésorerie.
--
-- PRIORITÉ R7 : aucune fonction existante réécrite (maillons neufs `regle_*`).
-- ============================================================

INSERT INTO document_effects (tenant_id, document_type, evenement, effet,
                              ecrit_comptable, journal_code, touche_stock, touche_paie,
                              reversible, obligatoire, actif, note)
VALUES (NULL, 'customer_payments', 'cancelled', 'sale.payment.cancelled',
        false, NULL, false, false, true, false, true, 'R-023 : règlement client annulé. Partie B, lot Trésorerie.'),
       (NULL, 'supplier_payments', 'cancelled', 'purchase.payment.cancelled',
        false, NULL, false, false, true, false, true, 'R-024 : règlement fournisseur annulé. Partie B, lot Trésorerie.')
ON CONFLICT DO NOTHING;

CREATE OR REPLACE FUNCTION public.regle_paiement_annule()
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
  IF NEW.status IS NOT DISTINCT FROM OLD.status OR NEW.status IS DISTINCT FROM 'cancelled' THEN
    RETURN NULL;
  END IF;
  IF NEW.tenant_id IS NULL THEN RETURN NULL; END IF;

  IF TG_TABLE_NAME = 'customer_payments' THEN
    v_event := 'customer_payments.cancelled'; v_effet := 'sale.payment.cancelled';
  ELSE
    v_event := 'supplier_payments.cancelled'; v_effet := 'purchase.payment.cancelled';
  END IF;

  IF EXISTS (SELECT 1 FROM domain_events de
             WHERE de.tenant_id = NEW.tenant_id AND de.event_name = v_event AND de.aggregate_id = NEW.id) THEN
    RETURN NULL;
  END IF;

  IF NOT chain_avant(NEW.tenant_id, TG_TABLE_NAME, 'cancelled', v_effet,
                     TG_TABLE_NAME, NEW.id, NULL,
                     format('Règlement %s : l''annulation n''a pas été tracée (règle %s, module trésorerie).',
                            NEW.number, v_effet)) THEN
    RETURN NULL;
  END IF;

  PERFORM emit_domain_event(NEW.tenant_id, v_event, TG_TABLE_NAME, NEW.id,
                            jsonb_build_object('number', NEW.number, 'status', NEW.status,
                                               'amount', NEW.amount), NULL);

  PERFORM chain_apres(NEW.tenant_id, v_effet, TG_TABLE_NAME, NEW.id,
                      v_debut, 0, 'applique', NULL, NULL, NULL);
  RETURN NULL;
END $maillon$;

DROP TRIGGER IF EXISTS zz_b2r023_paiement_client_annule ON customer_payments;
CREATE TRIGGER zz_b2r023_paiement_client_annule
AFTER UPDATE ON customer_payments
FOR EACH ROW EXECUTE FUNCTION public.regle_paiement_annule();

DROP TRIGGER IF EXISTS zz_b2r024_paiement_fournisseur_annule ON supplier_payments;
CREATE TRIGGER zz_b2r024_paiement_fournisseur_annule
AFTER UPDATE ON supplier_payments
FOR EACH ROW EXECUTE FUNCTION public.regle_paiement_annule();

REVOKE ALL ON FUNCTION public.regle_paiement_annule() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.regle_paiement_annule() TO service_role;
