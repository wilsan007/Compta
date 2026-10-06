-- ============================================================
-- 501_regle_ventes_commande_facturee.sql — partie B, lot Ventes, règle R-004
--
-- Source : doc/audit/REFERENTIEL-CHAINAGES-TRANSVERSAUX-2026-09-24.md §B.2 (ligne 4) ;
-- inventaire mesuré : doc/audit/plan6/B1-INVENTAIRE-62-REGLES-2026-10-05.md (R-004 = ⬜).
--
-- R-004 — « sales_orders.status = invoiced → rapprochement commande ↔ facture,
-- reliquat non facturé, clôture de la commande ».
--
-- MESURÉ (B.1). Aucun déclencheur sur `sales_orders` ne teste `invoiced`. La
-- liaison commande ↔ facture n'était donc écrite nulle part au niveau des liens de
-- chaîne, et le reliquat non facturé n'était calculé par personne.
--
-- CE QUE CE FICHIER FAIT
--   * au passage d'une commande à `invoiced` : il RAPPROCHE la commande de ses
--     factures (un lien `invoiced_by` par facture), CALCULE le reliquat non facturé
--     (commandé HT − facturé HT) et l'écrit dans l'événement ;
--   * il émet `sales_orders.invoiced` et trace l'entrée / la sortie du maillon ;
--   * il est IDEMPOTENT (`chain_avant` : un rejeu ne pose pas un second lien).
--
-- LE CHEMIN DE LIAISON, MESURÉ (il n'y en a qu'un de fiable) : une facture est
-- reliée à la commande par `invoice_lines.sales_order_line_id` (posé par l'écran
-- « BL → facture » quand la ligne du BL vient d'une ligne de commande). Le chemin
-- `invoices.sales_order_id` existe au schéma mais l'écran ne le renseigne pas ;
-- il est lu EN PLUS, au cas où un appel d'API le poserait.
--
-- CE QUE CE FICHIER NE FAIT PAS
--   * il ne change pas le STATUT de la commande (`invoiced` est déjà l'état
--     atteint — c'est le fait générateur) ;
--   * il ne referme pas l'écart de facturation : le reliquat est MESURÉ et dit,
--     pas corrigé (le corriger est un geste métier, pas un chaînage).
--
-- RAPPROCHEMENT vs R-006/R-019 : ce fichier ne fait que le lien et la mesure. La
-- sortie de stock (R-006) et la contre-passation d'avoir (R-019) restent ailleurs.
-- ============================================================

-- ── 1. Le contrat d'effet (L7 / M-05) ──
INSERT INTO document_effects (tenant_id, document_type, evenement, effet,
                              ecrit_comptable, journal_code, touche_stock, touche_paie,
                              reversible, obligatoire, actif, note)
VALUES (NULL, 'sales_orders', 'invoiced', 'sale.order.invoiced',
        false, NULL, false, false,
        true, false, true,
        'R-004 : la commande facturée se rapproche de ses factures, reliquat mesuré. Partie B, lot Ventes.')
ON CONFLICT DO NOTHING;

-- ── 2. Le maillon : commande facturée → rapprochement ──
CREATE OR REPLACE FUNCTION public.regle_r004_commande_facturee()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $maillon$
DECLARE
  v_debut    timestamptz := clock_timestamp();
  v_commande numeric := 0;
  v_facture  numeric := 0;
  v_reliquat numeric := 0;
  v_liens    integer := 0;
  v_f        record;
BEGIN
  -- Fait générateur : la commande vient de passer à « facturée » (et ne l'était pas).
  IF NEW.status IS NOT DISTINCT FROM OLD.status OR NEW.status IS DISTINCT FROM 'invoiced' THEN
    RETURN NULL;
  END IF;
  IF NEW.tenant_id IS NULL THEN
    RETURN NULL;
  END IF;

  -- Entrée du maillon — rejeu, contrat, drapeau.
  IF NOT chain_avant(NEW.tenant_id, 'sales_orders', 'invoiced', 'sale.order.invoiced',
                     'sales_orders', NEW.id, NULL,
                     format('Commande %s : le rapprochement avec ses factures n''a pas été produit (règle sale.order.invoiced, module ventes).',
                            NEW.number)) THEN
    RETURN NULL;
  END IF;

  -- Le COMMANDÉ HT : les lignes de la commande.
  SELECT COALESCE(sum(l.line_total), 0) INTO v_commande
  FROM sales_order_lines l
  WHERE l.sales_order_id = NEW.id AND l.tenant_id = NEW.tenant_id;

  -- Le FACTURÉ HT : les lignes de facture rattachées à une ligne de cette commande.
  SELECT COALESCE(sum(il.total), 0) INTO v_facture
  FROM invoice_lines il
  JOIN sales_order_lines sol ON sol.id = il.sales_order_line_id AND sol.tenant_id = il.tenant_id
  WHERE sol.sales_order_id = NEW.id AND sol.tenant_id = NEW.tenant_id;

  v_reliquat := v_commande - v_facture;

  -- Le RAPPROCHEMENT : un lien par facture rattachée (trois chemins lus, un seul suffit).
  FOR v_f IN
    SELECT DISTINCT i.id, i.number
    FROM invoices i
    WHERE i.tenant_id = NEW.tenant_id
      AND (i.sales_order_id = NEW.id
           OR i.delivery_note_id IN (SELECT dn.id FROM delivery_notes dn
                                     WHERE dn.tenant_id = NEW.tenant_id AND dn.sales_order_id = NEW.id)
           OR i.id IN (SELECT il.invoice_id FROM invoice_lines il
                       JOIN sales_order_lines sol ON sol.id = il.sales_order_line_id
                                                   AND sol.tenant_id = il.tenant_id
                       WHERE sol.sales_order_id = NEW.id AND sol.tenant_id = NEW.tenant_id))
    ORDER BY i.number
  LOOP
    PERFORM link_documents(NEW.tenant_id, 'sales_orders', NEW.id, 'invoices', v_f.id,
                           'sale.order.invoiced', 'invoiced_by',
                           jsonb_build_object('order_number', NEW.number, 'invoice_number', v_f.number));
    v_liens := v_liens + 1;
  END LOOP;

  -- L'ÉVÉNEMENT : le reliquat non facturé est MESURÉ et dit.
  PERFORM emit_domain_event(NEW.tenant_id, 'sales_orders.invoiced', 'sales_orders', NEW.id,
                            jsonb_build_object('commande_ht', v_commande, 'facture_ht', v_facture,
                                               'reliquat', v_reliquat, 'factures', v_liens), NULL);

  -- La mesure.
  PERFORM chain_apres(NEW.tenant_id, 'sale.order.invoiced', 'sales_orders', NEW.id,
                      v_debut, v_liens, 'applique', NULL, NULL, NULL);
  RETURN NULL;
END $maillon$;

-- ── 3. Le déclencheur (nommé `zz_` : il passe APRÈS les déclencheurs métier) ──
DROP TRIGGER IF EXISTS zz_b2r004_commande_facturee ON sales_orders;
CREATE TRIGGER zz_b2r004_commande_facturee
AFTER UPDATE ON sales_orders
FOR EACH ROW
EXECUTE FUNCTION public.regle_r004_commande_facturee();

-- Le maillon n'est pas un point d'entrée (aucun EXECUTE pour les rôles applicatifs).
REVOKE ALL ON FUNCTION public.regle_r004_commande_facturee() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.regle_r004_commande_facturee() TO service_role;
