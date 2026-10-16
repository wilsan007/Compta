-- ============================================================
-- 525_regle_r043_of_annule_contrepassation.sql — partie B, lot Production, règle R-043
--
-- Source : doc/audit/REFERENTIEL-CHAINAGES-TRANSVERSAUX-2026-09-24.md §B.2 (ligne 43) ;
-- inventaire mesuré : doc/audit/plan6/B1-INVENTAIRE-62-REGLES-2026-10-05.md (R-043 = 🟨).
--
-- R-043 — `manufacturing_orders.status = cancelled` → contre-passation des consommations,
-- libération des composants réservés, restitution du coût.
--
-- MESURÉ : la `519` a rendu l'état `cancelled` OBSERVABLE (événement). Ce fichier en fait
-- la CONTRE-PASSATION STOCK : chaque mouvement produit par l'OF est INVERSE.
--
-- CE QUE CE FICHIER FAIT — la contre-passation des mouvements de l'OF
--   * au passage d'un OF à `cancelled` : pour CHAQUE mouvement de stock de l'OF
--     (`reference_type = 'production'`, `reference_id = OF`), il produit le mouvement
--     INVERSE (`out` → `in`, `in` → `out`), **au même dépôt et au même coût** — la
--     contre-passation. Il LIE l'OF à ces mouvements et trace.
--   * IDEMPOTENT : la référence `ANN-OF-…` garde (un rejeu ne double pas).
--   * SANS mouvement produit (OF jamais démarré) : il trace `sans_effet` — aucune pièce
--     fantôme.
--
-- RÉCONCILIÉ AVEC MAIN (session d'intégration) — LES INVERSES ONT LEUR PROPRE reference_type.
-- Les mouvements inverses portent `reference_type = 'production_reversal'`, PAS `'production'`.
-- MESURÉ : la chaîne existante tient le modèle « UN jeu `production` par OF » — la clôture
-- (`81`/`229`, `create_stock_on_manufacturing_complete`) écrit ce jeu, et sa garde d'idempotence
-- (`229` T04 : « reclôturer un OF → refusé ») COMPTE ces mouvements. Écrire les inverses sous
-- `production` faisait compter à la 229 des entrées qu'elle n'attendait pas (2 au lieu de 1,
-- 30 au lieu de 10) : deux règles, deux jeux de mouvements, deux référence_types. La lecture
-- ci-dessous, elle, reste sur `production` — c'est bien le jeu de l'OF qu'il faut inverser.
--
-- CE QUI RESTE À LA COORDINATION : la LIBÉRATION DES COMPOSANTS RÉSERVÉS (réservations de
-- production : pas de table dédiée au schéma côté OF) et la RESTITUTION COMPTABLE du coût
-- (écriture inverse) — la contre-passation de STOCK est faite ici, la pièce comptable suit
-- la chaîne du stock (`create_journal_on_stock_movement`).
--
-- PRIORITÉ R7 : aucune fonction existante réécrite (maillon neuf `regle_r043_…`).
-- ============================================================

INSERT INTO document_effects (tenant_id, document_type, evenement, effet,
                              ecrit_comptable, journal_code, touche_stock, touche_paie,
                              reversible, obligatoire, actif, note)
VALUES (NULL, 'manufacturing_orders', 'cancelled_reversed', 'production.order.cancelled_reversed',
        false, NULL, true, false, true, false, true,
        'R-043 : OF annulé — contre-passation des mouvements de stock. Partie B, lot Production.')
ON CONFLICT DO NOTHING;

-- ── Le maillon : OF annulé → contre-passation des mouvements ──
CREATE OR REPLACE FUNCTION public.regle_r043_of_annule_contrepassation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $maillon$
DECLARE
  v_debut  timestamptz := clock_timestamp();
  v_ref    text;
  v_opp    text;
  v_new_id uuid;
  v_lignes integer := 0;
  v_m      record;
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status OR NEW.status IS DISTINCT FROM 'cancelled' THEN
    RETURN NULL;
  END IF;
  IF NEW.tenant_id IS NULL THEN RETURN NULL; END IF;

  -- Idempotence : les contre-passations de cet OF existent-elles déjà ?
  -- (reference_type DISTINCT de celui de la clôture : voir l'en-tête.)
  v_ref := 'ANN-OF-' || NEW.number;
  IF EXISTS (SELECT 1 FROM stock_movements sm
             WHERE sm.tenant_id = NEW.tenant_id AND sm.reference = v_ref
               AND sm.reference_type = 'production_reversal' AND sm.reference_id = NEW.id) THEN
    RETURN NULL;
  END IF;

  IF NOT chain_avant(NEW.tenant_id, 'manufacturing_orders', 'cancelled_reversed', 'production.order.cancelled_reversed',
                     'manufacturing_orders', NEW.id, NULL,
                     format('Ordre de fabrication %s : la contre-passation du stock n''a pas été produite (règle production.order.cancelled_reversed, module production).',
                            NEW.number)) THEN
    RETURN NULL;
  END IF;

  -- La CONTRE-PASSATION : un mouvement INVERSE par mouvement de l'OF.
  FOR v_m IN
    SELECT sm.product_id, sm.warehouse_id, sm.quantity, sm.unit_cost, sm.lot_id, sm.serial_id,
           sm.movement_type, sm.movement_date, sm.date
    FROM stock_movements sm
    WHERE sm.tenant_id = NEW.tenant_id AND sm.reference_type = 'production' AND sm.reference_id = NEW.id
  LOOP
    v_opp := CASE v_m.movement_type WHEN 'out' THEN 'in' WHEN 'in' THEN 'out' ELSE NULL END;
    IF v_opp IS NULL THEN CONTINUE; END IF;

    INSERT INTO stock_movements (
      tenant_id, product_id, warehouse_id, movement_type, type, quantity, unit_cost,
      lot_id, serial_id, reference, reference_type, reference_id, date, movement_date, notes
    ) VALUES (
      NEW.tenant_id, v_m.product_id, v_m.warehouse_id, v_opp, v_opp, v_m.quantity, v_m.unit_cost,
      v_m.lot_id, v_m.serial_id, v_ref, 'production_reversal', NEW.id,
      COALESCE(v_m.movement_date, v_m.date), COALESCE(v_m.movement_date, v_m.date),
      'Contre-passation OF ' || NEW.number
    ) RETURNING id INTO v_new_id;

    PERFORM link_documents(NEW.tenant_id, 'manufacturing_orders', NEW.id, 'stock_movements', v_new_id,
                           'production.order.cancelled_reversed', 'reversed_by',
                           jsonb_build_object('product_id', v_m.product_id, 'quantity', v_m.quantity,
                                              'reference', v_ref));
    v_lignes := v_lignes + 1;
  END LOOP;

  IF v_lignes = 0 THEN
    PERFORM chain_apres(NEW.tenant_id, 'production.order.cancelled_reversed', 'manufacturing_orders', NEW.id,
                        v_debut, 0, 'sans_effet', 'Aucun mouvement de stock pour cet OF : rien à contrepasser.', NULL, NULL);
    RETURN NULL;
  END IF;

  PERFORM emit_domain_event(NEW.tenant_id, 'manufacturing_orders.cancelled_reversed', 'manufacturing_orders', NEW.id,
                            jsonb_build_object('number', NEW.number, 'mouvements_inverses', v_lignes), NULL);

  PERFORM chain_apres(NEW.tenant_id, 'production.order.cancelled_reversed', 'manufacturing_orders', NEW.id,
                      v_debut, v_lignes, 'applique', NULL, NULL, NULL);
  RETURN NULL;
END $maillon$;

DROP TRIGGER IF EXISTS zz_b2r043_of_contrepassation ON manufacturing_orders;
CREATE TRIGGER zz_b2r043_of_contrepassation
AFTER UPDATE ON manufacturing_orders
FOR EACH ROW EXECUTE FUNCTION public.regle_r043_of_annule_contrepassation();

REVOKE ALL ON FUNCTION public.regle_r043_of_annule_contrepassation() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.regle_r043_of_annule_contrepassation() TO service_role;
