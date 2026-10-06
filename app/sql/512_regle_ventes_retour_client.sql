-- ============================================================
-- 512_regle_ventes_retour_client.sql — partie B, lot Ventes, règle R-007
--
-- Source : doc/audit/REFERENTIEL-CHAINAGES-TRANSVERSAUX-2026-09-24.md §B.2 (ligne 7) ;
-- inventaire mesuré : doc/audit/plan6/B1-INVENTAIRE-62-REGLES-2026-10-05.md (R-007 = ⬜).
--
-- R-007 — `delivery_notes.status = returned` → « retour client : entrée en stock ou en
-- quarantaine, avoir, contrôle qualité, réintégration du coût ».
--
-- MESURÉ (B.1). Aucun déclencheur sur `delivery_notes` ne testait `returned` : un BL
-- marqué « retourné » ne ré-entrait RIEN en stock (la marchandise restait « sortie »).
--
-- CE QUE CE FICHIER FAIT — la RÉINTÉGRATION (maillon)
--   * au passage d'un BL à `returned` : pour CHAQUE sortie de stock d'origine de ce bon
--     (mouvement `out` de référence `delivery_note`), il produit un mouvement `in` qui
--     RÉINTÈGRE la marchandise — **au même dépôt** et **au même coût** que la sortie
--     (réintégration du coût, pas une nouvelle valorisation) ;
--   * il LIE le BL aux mouvements d'entrée et émet `delivery_notes.returned` ; il est
--     IDEMPOTENT (un rejeu ne ré-intègre pas deux fois : la référence `RET-BL-…` garde).
--
-- GARDE DE SENS (dite). S'il n'existe AUCUNE sortie pour ce bon, la règle ne produit
-- rien : on ne crée pas de stock pour une marchandise qui n'est jamais partie. Le BL est
-- alors simplement tracé « rien à réintégrer » — jamais une entrée fantôme.
--
-- CE QUI RESTE À LA COORDINATION
--   * l'AVOIR client (contre-passation TVA / lettrage) : c'est le rôle de R-019 / de
--     l'avoir client (`credit_notes`), pas d'un mouvement de stock ;
--   * la QUARANTAINE (un dépôt de quarantaine) : le schéma n'a pas de dépôt de
--     quarantaine normé ; la réintégration va au dépôt d'origine. Choix dit.
--
-- PRIORITÉ R7 : aucune fonction existante réécrite (maillon neuf `regle_r007_…`).
-- ============================================================

-- ── 1. Le contrat d'effet (L7 / M-05) ──
INSERT INTO document_effects (tenant_id, document_type, evenement, effet,
                              ecrit_comptable, journal_code, touche_stock, touche_paie,
                              reversible, obligatoire, actif, note)
VALUES (NULL, 'delivery_notes', 'returned', 'sale.delivery.returned',
        false, NULL, true, false, true, false, true,
        'R-007 : retour client — réintégration au dépôt d''origine, au coût de sortie. Partie B, lot Ventes.')
ON CONFLICT DO NOTHING;

-- ── 2. Le maillon : BL retourné → réintégration au dépôt d'origine ──
CREATE OR REPLACE FUNCTION public.regle_r007_retour_client()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $maillon$
DECLARE
  v_debut  timestamptz := clock_timestamp();
  v_ref    text;
  v_entree uuid;
  v_lignes integer := 0;
  v_s      record;
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status OR NEW.status IS DISTINCT FROM 'returned' THEN
    RETURN NULL;
  END IF;
  IF NEW.tenant_id IS NULL THEN RETURN NULL; END IF;

  -- Guarde de sens + idempotence : les entrées de retour de ce bon existent-elles déjà ?
  v_ref := 'RET-' || NEW.number;
  IF EXISTS (SELECT 1 FROM stock_movements sm
             WHERE sm.tenant_id = NEW.tenant_id AND sm.reference = v_ref
               AND sm.reference_type = 'delivery_note' AND sm.reference_id = NEW.id) THEN
    RETURN NULL;
  END IF;

  -- Entrée du maillon (rejeu par le lien, contrat, drapeau).
  IF NOT chain_avant(NEW.tenant_id, 'delivery_notes', 'returned', 'sale.delivery.returned',
                     'delivery_notes', NEW.id, NULL,
                     format('BL %s : l''entrée en stock du retour n''a pas été produite (règle sale.delivery.returned, module ventes).',
                            NEW.number)) THEN
    RETURN NULL;
  END IF;

  -- Réintégration : une entrée par SORTIE d'origine, même dépôt, même coût.
  FOR v_s IN
    SELECT sm.product_id, sm.warehouse_id, sm.quantity, sm.unit_cost, sm.lot_id, sm.serial_id
    FROM stock_movements sm
    WHERE sm.tenant_id = NEW.tenant_id AND sm.reference_type = 'delivery_note'
      AND sm.reference_id = NEW.id AND sm.movement_type = 'out'
  LOOP
    INSERT INTO stock_movements (
      tenant_id, product_id, warehouse_id, movement_type, type, quantity, unit_cost,
      lot_id, serial_id, reference, reference_type, reference_id, date, movement_date, notes
    ) VALUES (
      NEW.tenant_id, v_s.product_id, v_s.warehouse_id, 'in', 'in', v_s.quantity, v_s.unit_cost,
      v_s.lot_id, v_s.serial_id, v_ref, 'delivery_note', NEW.id,
      COALESCE(NEW.delivery_date, CURRENT_DATE), COALESCE(NEW.delivery_date, CURRENT_DATE),
      'Retour client - BL ' || NEW.number
    ) RETURNING id INTO v_entree;

    PERFORM link_documents(NEW.tenant_id, 'delivery_notes', NEW.id, 'stock_movements', v_entree,
                           'sale.delivery.returned', 'reversed_by',
                           jsonb_build_object('product_id', v_s.product_id, 'quantity', v_s.quantity,
                                              'warehouse_id', v_s.warehouse_id, 'reference', v_ref));
    v_lignes := v_lignes + 1;
  END LOOP;

  -- Aucune sortie d'origine : rien à réintégrer — on ne crée pas de stock fantôme.
  IF v_lignes = 0 THEN
    PERFORM chain_apres(NEW.tenant_id, 'sale.delivery.returned', 'delivery_notes', NEW.id,
                        v_debut, 0, 'sans_effet', 'Aucune sortie d''origine : rien à réintégrer.', NULL, NULL);
    RETURN NULL;
  END IF;

  PERFORM emit_domain_event(NEW.tenant_id, 'delivery_notes.returned', 'delivery_notes', NEW.id,
                            jsonb_build_object('number', NEW.number, 'entrees', v_lignes,
                                               'sales_order_id', NEW.sales_order_id), NULL);

  PERFORM chain_apres(NEW.tenant_id, 'sale.delivery.returned', 'delivery_notes', NEW.id,
                      v_debut, v_lignes, 'applique', NULL, NULL, NULL);
  RETURN NULL;
END $maillon$;

-- ── 3. Le déclencheur (`zz_` : il passe APRÈS les déclencheurs métier) ──
DROP TRIGGER IF EXISTS zz_b2r007_retour_client ON delivery_notes;
CREATE TRIGGER zz_b2r007_retour_client
AFTER UPDATE ON delivery_notes
FOR EACH ROW
EXECUTE FUNCTION public.regle_r007_retour_client();

-- Le maillon n'est pas un point d'entrée (aucun EXECUTE pour les rôles applicatifs).
REVOKE ALL ON FUNCTION public.regle_r007_retour_client() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.regle_r007_retour_client() TO service_role;
