-- ============================================================
-- 510_regle_achats_commande_recue.sql — partie B, lot Achats, règle R-011 (compléter)
--
-- Source : doc/audit/REFERENTIEL-CHAINAGES-TRANSVERSAUX-2026-09-24.md §B.2 (ligne 11) ;
-- inventaire mesuré : doc/audit/plan6/B1-INVENTAIRE-62-REGLES-2026-10-05.md (R-011 = 🟨).
--
-- R-011 — `purchase_orders.status = received` → « rapprochement commande ↔ réception,
-- consommation de l'engagement, écart de prix d'achat ».
--
-- MESURÉ (B.1, partielle). Deux morceaux existaient : le statut de la commande est posé
-- par `update_po_status_on_receipt` (réception → commande reçue/partielle), et
-- l'engagement se consomme à l'APPROBATION DE LA FACTURE
-- (`consume_commitment_on_purchase_invoice`). Mais **aucun LIEN commande ↔ réception**
-- n'était écrit, et l'écart reçu/commandé n'était mesuré par personne.
--
-- CE QUE CE FICHIER FAIT — le RAPPROCHEMENT et la MESURE (maillon)
--   * à la commande passée à `received` : lie la commande à CHAQUE réception qui la
--     solde (un lien `created_from` par réception) et MESURE l'écart de quantité
--     (commandé vs reçu), écrit dans l'événement ;
--   * émet `purchase_orders.received` et trace le maillon ; IDEMPOTENT.
--
-- CE QUI EST DÉJÀ FAIT AILLEURS (et n'est pas refait)
--   * la CONSOMMATION de l'engagement : `consume_commitment_on_purchase_invoice`
--     (règle R-057, à l'approbation de la facture) ;
--   * l'ÉCART DE PRIX D'ACHAT : c'est le rôle de `perform_three_way_match`
--     (`price_mismatch`). Les lignes de réception ne portent pas de coût
--     (`goods_receipt_lines` n'a pas de `unit_cost`) : l'écart de prix se lit au
--     rapprochement facture ↔ commande, pas ici.
--
-- PRIORITÉ R7 : aucune fonction existante réécrite (maillon neuf `regle_r011_…`).
-- ============================================================

-- ── 1. Le contrat d'effet (L7 / M-05) ──
INSERT INTO document_effects (tenant_id, document_type, evenement, effet,
                              ecrit_comptable, journal_code, touche_stock, touche_paie,
                              reversible, obligatoire, actif, note)
VALUES (NULL, 'purchase_orders', 'received', 'purchase.order.received',
        false, NULL, false, false, true, false, true,
        'R-011 : commande reçue — rapprochement avec ses réceptions, écart de quantité. Partie B, lot Achats.')
ON CONFLICT DO NOTHING;

-- ── 1bis. Le registre des types de document (450) : `purchase_orders` doit y être ──
-- `link_documents` refuse un type non inscrit (règle 450). `purchase_orders` n'y
-- figurait pas : la commande d'achat ne pouvait être l'AMONT d'aucun maillon.
INSERT INTO chain_document_types (code, table_name, ligne_table, libelle_fr)
VALUES ('purchase_orders', 'purchase_orders', 'purchase_order_lines', 'Commande fournisseur')
ON CONFLICT DO NOTHING;

-- ── 2. Le maillon : commande reçue → rapprochement ──
CREATE OR REPLACE FUNCTION public.regle_r011_commande_recue()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $maillon$
DECLARE
  v_debut    timestamptz := clock_timestamp();
  v_cmd      numeric := 0;
  v_recu     numeric := 0;
  v_liens    integer := 0;
  v_f        record;
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status OR NEW.status IS DISTINCT FROM 'received' THEN
    RETURN NULL;
  END IF;
  IF NEW.tenant_id IS NULL THEN RETURN NULL; END IF;

  -- Entrée du maillon — rejeu (ce maillon pose des liens), contrat, drapeau.
  IF NOT chain_avant(NEW.tenant_id, 'purchase_orders', 'received', 'purchase.order.received',
                     'purchase_orders', NEW.id, NULL,
                     format('Commande %s : le rapprochement avec ses réceptions n''a pas été produit (règle purchase.order.received, module achats).',
                            NEW.number)) THEN
    RETURN NULL;
  END IF;

  -- Le COMMANDÉ et le REÇU (quantités).
  SELECT COALESCE(sum(quantity), 0) INTO v_cmd
  FROM purchase_order_lines WHERE purchase_order_id = NEW.id AND tenant_id = NEW.tenant_id;

  SELECT COALESCE(sum(grl.quantity_received), 0) INTO v_recu
  FROM goods_receipt_lines grl
  JOIN goods_receipts gr ON gr.id = grl.goods_receipt_id AND gr.tenant_id = grl.tenant_id
  WHERE gr.purchase_order_id = NEW.id AND gr.tenant_id = NEW.tenant_id
    AND gr.status = 'received';

  -- Le RAPPROCHEMENT : un lien par réception qui solde la commande.
  FOR v_f IN
    SELECT gr.id, gr.number
    FROM goods_receipts gr
    WHERE gr.tenant_id = NEW.tenant_id AND gr.purchase_order_id = NEW.id
    ORDER BY gr.number
  LOOP
    PERFORM link_documents(NEW.tenant_id, 'purchase_orders', NEW.id, 'goods_receipts', v_f.id,
                           'purchase.order.received', 'created_from',
                           jsonb_build_object('order_number', NEW.number, 'receipt_number', v_f.number));
    v_liens := v_liens + 1;
  END LOOP;

  PERFORM emit_domain_event(NEW.tenant_id, 'purchase_orders.received', 'purchase_orders', NEW.id,
                            jsonb_build_object('order_number', NEW.number, 'commande_qte', v_cmd,
                                               'recu_qte', v_recu, 'ecart_qte', v_cmd - v_recu,
                                               'receptions', v_liens), NULL);

  PERFORM chain_apres(NEW.tenant_id, 'purchase.order.received', 'purchase_orders', NEW.id,
                      v_debut, v_liens, 'applique', NULL, NULL, NULL);
  RETURN NULL;
END $maillon$;

-- ── 3. Le déclencheur (`zz_` : il passe APRÈS les déclencheurs métier) ──
DROP TRIGGER IF EXISTS zz_b2r011_commande_recue ON purchase_orders;
CREATE TRIGGER zz_b2r011_commande_recue
AFTER UPDATE ON purchase_orders
FOR EACH ROW
EXECUTE FUNCTION public.regle_r011_commande_recue();

-- Le maillon n'est pas un point d'entrée (aucun EXECUTE pour les rôles applicatifs).
REVOKE ALL ON FUNCTION public.regle_r011_commande_recue() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.regle_r011_commande_recue() TO service_role;
