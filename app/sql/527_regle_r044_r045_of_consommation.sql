-- ============================================================
-- 527_regle_r044_r045_of_consommation.sql — partie B, lot Production, règles R-045 et R-044
--
-- Source : doc/audit/REFERENTIEL-CHAINAGES-TRANSVERSAUX-2026-09-24.md §B.2 (lignes 44-45) ;
-- inventaire mesuré : doc/audit/plan6/B1-INVENTAIRE-62-REGLES-2026-10-05.md (R-044/045 = 🟨/⬜).
--
--   R-045 — `manufacturing_orders.status = planned` → RÉSERVATION des composants,
--           engagement de capacité, réservation de trésorerie ;
--   R-044 — `manufacturing_orders.status = in_progress` → CONSOMMATION réelle des
--           composants, déclaration de production, mise en en-cours.
--
-- MESURÉ : la `519` a rendu les états OBSERVABLES (événements). Ce fichier en fait les
-- EFFETS de stock : **réservation** des composants (planifié), puis **consommation** (en cours).
--
-- CE QUE CE FICHIER FAIT — deux maillons (stock)
--   * `planned` : pour CHAQUE composant de la nomenclature de l'OF, crée une RÉSERVATION
--     (`stock_reservations`, `reference_type = 'manufacturing_order'`), quantité =
--     qty nomenclature × qty OF × (1 + rebut) ;
--   * `in_progress` : CONSOMME les composants — un mouvement de stock `out` par composant
--     (référence `OF-…`, `reference_type = 'production'`) — et passe les réservations de
--     l'OF à `consumed` ;
--   * IDEMPOTENTS (réservations / mouvements existants gardent).
--
-- CE QUI RESTE À LA COORDINATION : l'engagement de CAPACITÉ (pas de table côté OF) et la
-- réservation de TRÉSORERIE (prévisionnel) ne sont pas posés ici. La contre-passation d'une
-- consommation est couverte par R-043 (annulation d'OF, `ANN-OF-…`).
--
-- PRIORITÉ R7 : aucune fonction existante réécrite (maillons neufs `regle_r044_r045_…`).
-- ============================================================

INSERT INTO document_effects (tenant_id, document_type, evenement, effet,
                              ecrit_comptable, journal_code, touche_stock, touche_paie,
                              reversible, obligatoire, actif, note)
VALUES (NULL, 'manufacturing_orders', 'planned', 'production.order.components_reserved',
        false, NULL, true, false, true, false, true,
        'R-045 : OF planifié — réservation des composants. Partie B, lot Production.'),
       (NULL, 'manufacturing_orders', 'in_progress', 'production.order.components_consumed',
        false, NULL, true, false, true, false, true,
        'R-044 : OF en cours — consommation des composants. Partie B, lot Production.')
ON CONFLICT DO NOTHING;

-- ── R-045 — OF planifié → réservation des composants ──
CREATE OR REPLACE FUNCTION public.regle_r045_reserver_composants()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $maillon$
DECLARE
  v_debut timestamptz := clock_timestamp();
  v_lignes integer := 0;
  v_l      record;
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status OR NEW.status IS DISTINCT FROM 'planned' THEN
    RETURN NULL;
  END IF;
  IF NEW.tenant_id IS NULL OR NEW.bom_id IS NULL THEN RETURN NULL; END IF;

  IF EXISTS (SELECT 1 FROM stock_reservations sr
             WHERE sr.tenant_id = NEW.tenant_id AND sr.reference_type = 'manufacturing_order'
               AND sr.reference_id = NEW.id) THEN
    RETURN NULL;
  END IF;

  IF NOT chain_avant(NEW.tenant_id, 'manufacturing_orders', 'planned', 'production.order.components_reserved',
                     'manufacturing_orders', NEW.id, NULL,
                     format('OF %s : la réservation des composants n''a pas été produite (règle production.order.components_reserved, module production).', NEW.number)) THEN
    RETURN NULL;
  END IF;

  FOR v_l IN
    SELECT bl.product_id, bl.quantity, COALESCE(bl.scrap_rate, 0) AS scrap_rate
    FROM bom_lines bl WHERE bl.bom_id = NEW.bom_id AND bl.tenant_id = NEW.tenant_id
  LOOP
    INSERT INTO stock_reservations (tenant_id, product_id, warehouse_id, quantity, reserved_by,
                                    reference_type, reference_id, status)
    VALUES (NEW.tenant_id, v_l.product_id, NEW.warehouse_id,
            round(v_l.quantity * NEW.quantity * (1 + v_l.scrap_rate / 100.0), 4),
            'manufacturing_order', 'manufacturing_order', NEW.id, 'active');
    v_lignes := v_lignes + 1;
  END LOOP;

  IF v_lignes = 0 THEN
    PERFORM chain_apres(NEW.tenant_id, 'production.order.components_reserved', 'manufacturing_orders', NEW.id,
                        v_debut, 0, 'sans_effet', 'Nomenclature vide : rien à réserver.', NULL, NULL);
    RETURN NULL;
  END IF;

  PERFORM emit_domain_event(NEW.tenant_id, 'manufacturing_orders.components_reserved', 'manufacturing_orders', NEW.id,
                            jsonb_build_object('number', NEW.number, 'composants', v_lignes), NULL);
  PERFORM chain_apres(NEW.tenant_id, 'production.order.components_reserved', 'manufacturing_orders', NEW.id,
                      v_debut, v_lignes, 'applique', NULL, NULL, NULL);
  RETURN NULL;
END $maillon$;

-- ── R-044 — OF en cours → consommation des composants ──
CREATE OR REPLACE FUNCTION public.regle_r044_consommer_composants()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $maillon$
DECLARE
  v_debut timestamptz := clock_timestamp();
  v_lignes integer := 0;
  v_wh    uuid;
  v_mvt   uuid;
  v_l     record;
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status OR NEW.status IS DISTINCT FROM 'in_progress' THEN
    RETURN NULL;
  END IF;
  IF NEW.tenant_id IS NULL OR NEW.bom_id IS NULL THEN RETURN NULL; END IF;

  IF EXISTS (SELECT 1 FROM stock_movements sm
             WHERE sm.tenant_id = NEW.tenant_id AND sm.reference = 'OF-' || NEW.number
               AND sm.reference_type = 'production' AND sm.reference_id = NEW.id) THEN
    RETURN NULL;
  END IF;

  IF NOT chain_avant(NEW.tenant_id, 'manufacturing_orders', 'in_progress', 'production.order.components_consumed',
                     'manufacturing_orders', NEW.id, NULL,
                     format('OF %s : la consommation des composants n''a pas été produite (règle production.order.components_consumed, module production).', NEW.number)) THEN
    RETURN NULL;
  END IF;

  v_wh := COALESCE(NEW.warehouse_id, resolve_default_warehouse(NEW.tenant_id));

  FOR v_l IN
    SELECT bl.product_id, bl.quantity, COALESCE(bl.scrap_rate, 0) AS scrap_rate
    FROM bom_lines bl WHERE bl.bom_id = NEW.bom_id AND bl.tenant_id = NEW.tenant_id
  LOOP
    INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, movement_type, type, quantity,
                                 reference, reference_type, reference_id, date, movement_date, notes)
    VALUES (NEW.tenant_id, v_l.product_id, v_wh, 'out', 'out',
            round(v_l.quantity * NEW.quantity * (1 + v_l.scrap_rate / 100.0), 4),
            'OF-' || NEW.number, 'production', NEW.id, CURRENT_DATE, CURRENT_DATE,
            'Consommation OF ' || NEW.number)
    RETURNING id INTO v_mvt;

    PERFORM link_documents(NEW.tenant_id, 'manufacturing_orders', NEW.id, 'stock_movements', v_mvt,
                           'production.order.components_consumed', 'consumed_by_absence',
                           jsonb_build_object('product_id', v_l.product_id, 'reference', 'OF-' || NEW.number));
    v_lignes := v_lignes + 1;
  END LOOP;

  -- Les réservations de l'OF passent à « consumed ».
  UPDATE stock_reservations SET status = 'consumed', updated_at = now()
  WHERE tenant_id = NEW.tenant_id AND reference_type = 'manufacturing_order'
    AND reference_id = NEW.id AND status = 'active';

  IF v_lignes = 0 THEN
    PERFORM chain_apres(NEW.tenant_id, 'production.order.components_consumed', 'manufacturing_orders', NEW.id,
                        v_debut, 0, 'sans_effet', 'Nomenclature vide : rien à consommer.', NULL, NULL);
    RETURN NULL;
  END IF;

  PERFORM emit_domain_event(NEW.tenant_id, 'manufacturing_orders.components_consumed', 'manufacturing_orders', NEW.id,
                            jsonb_build_object('number', NEW.number, 'composants', v_lignes), NULL);
  PERFORM chain_apres(NEW.tenant_id, 'production.order.components_consumed', 'manufacturing_orders', NEW.id,
                      v_debut, v_lignes, 'applique', NULL, NULL, NULL);
  RETURN NULL;
END $maillon$;

DROP TRIGGER IF EXISTS zz_b2r045_reserver_composants ON manufacturing_orders;
CREATE TRIGGER zz_b2r045_reserver_composants
AFTER UPDATE ON manufacturing_orders
FOR EACH ROW EXECUTE FUNCTION public.regle_r045_reserver_composants();

DROP TRIGGER IF EXISTS zz_b2r044_consommer_composants ON manufacturing_orders;
CREATE TRIGGER zz_b2r044_consommer_composants
AFTER UPDATE ON manufacturing_orders
FOR EACH ROW EXECUTE FUNCTION public.regle_r044_consommer_composants();

REVOKE ALL ON FUNCTION public.regle_r045_reserver_composants() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.regle_r044_consommer_composants() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.regle_r045_reserver_composants() TO service_role;
GRANT EXECUTE ON FUNCTION public.regle_r044_consommer_composants() TO service_role;
