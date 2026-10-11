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
-- RÉCONCILIÉ AVEC MAIN (session d'intégration) — LA CONSOMMATION PHYSIQUE A DÉJÀ UN
-- PROPRIÉTAIRE. La consommation des composants — un mouvement `out` par composant de la
-- nomenclature, PLUS l'écriture 601000 / 310000 — est produite par la chaîne EXISTANTE à la
-- CLÔTURE : `81` / `229`, `create_stock_on_manufacturing_complete()`, trigger
-- `trg_manufacturing_complete_stock` (mouvements `reference_type = 'production'`,
-- `reference_id = OF`).
--
-- Cette chaîne garde son idempotence en COMPTANT ces mouvements :
--   `229` : `IF v_deja > 0 THEN RAISE EXCEPTION 'OF % déjà clôturé …'` — et la `302` de même.
-- Écrire ici une SECONDE fois la consommation produirait donc DEUX fautes :
--   1. la clôture (`in_progress` → `completed`) serait REFUSÉE (23505 « OF … déjà clôturé ») ;
--   2. la sortie serait DOUBLÉE (les composants sortis deux fois).
-- Le contrat de l'écran `08_prod_treso` (M04) dit lequel des deux écrit : « OF terminé :
-- +10 produits finis, −20 composants » — UNE consommation, à la clôture.
--
-- CE FICHIER NE LA DUPLIQUE DONC PAS. R-044 garde ce qui lui revient en propre :
--   * `planned` → RÉSERVATION des composants (R-045) — maillon NEUF, aucun recouvrement ;
--   * `in_progress` → SOLDAGE des réservations de l'OF (`consumed`) + TRACE de l'état.
-- La consommation physique reste celle de la clôture ; elle est tracée ici comme telle.
--
-- CE QUI RESTE À LA COORDINATION : l'engagement de CAPACITÉ (pas de table côté OF) et la
-- réservation de TRÉSORERIE (prévisionnel) ne sont pas posés ici. La contre-passation d'une
-- consommation est couverte par R-043 (annulation d'OF, `ANN-OF-…`) — qui inverse les
-- mouvements `production` de l'OF, donc ceux de la clôture.
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

-- ── R-044 — OF en cours → les RÉSERVATIONS sont soldées (la sortie appartient à la clôture) ──
-- NE PAS écrire ici les mouvements de consommation : voir l'en-tête. La chaîne `81` / `229`
-- les produit à la CLÔTURE, et compte les mouvements `production` de l'OF pour son idempotence
-- — une seconde écriture ferait REFUSER la clôture et DOUBLERAIT la sortie.
CREATE OR REPLACE FUNCTION public.regle_r044_consommer_composants()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $maillon$
DECLARE
  v_debut   timestamptz := clock_timestamp();
  v_soldees integer := 0;
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status OR NEW.status IS DISTINCT FROM 'in_progress' THEN
    RETURN NULL;
  END IF;
  IF NEW.tenant_id IS NULL THEN RETURN NULL; END IF;

  IF NOT chain_avant(NEW.tenant_id, 'manufacturing_orders', 'in_progress', 'production.order.components_consumed',
                     'manufacturing_orders', NEW.id, NULL,
                     format('OF %s : la consommation des composants n''a pas été produite (règle production.order.components_consumed, module production).', NEW.number)) THEN
    RETURN NULL;
  END IF;

  -- Le fait propre à l'état « en cours » : les RÉSERVATIONS posées par R-045 sont SOLDÉES.
  -- La sortie de stock, elle, reste produite par la clôture (81/229) — voir l'en-tête.
  UPDATE stock_reservations SET status = 'consumed', updated_at = now()
  WHERE tenant_id = NEW.tenant_id AND reference_type = 'manufacturing_order'
    AND reference_id = NEW.id AND status = 'active';
  GET DIAGNOSTICS v_soldees = ROW_COUNT;

  PERFORM emit_domain_event(NEW.tenant_id, 'manufacturing_orders.components_consumed', 'manufacturing_orders', NEW.id,
                            jsonb_build_object('number', NEW.number, 'reservations_soldees', v_soldees,
                                               'consommation_physique', 'cloture (81/229)'), NULL);

  IF v_soldees = 0 THEN
    PERFORM chain_apres(NEW.tenant_id, 'production.order.components_consumed', 'manufacturing_orders', NEW.id,
                        v_debut, 0, 'sans_effet',
                        'Aucune réservation à solder (OF sans nomenclature, ou réservations déjà soldées).', NULL, NULL);
    RETURN NULL;
  END IF;

  PERFORM chain_apres(NEW.tenant_id, 'production.order.components_consumed', 'manufacturing_orders', NEW.id,
                      v_debut, v_soldees, 'applique',
                      format('La consommation physique est produite à la clôture par la chaîne existante (81/229) ; ici : %s réservation(s) soldée(s).', v_soldees),
                      NULL, NULL);
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
