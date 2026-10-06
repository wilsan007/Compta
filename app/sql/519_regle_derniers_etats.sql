-- ============================================================
-- 519_regle_derniers_etats.sql — partie B, règles R-019, R-044, R-045, R-047
--   (les quatre dernières VIERGES de l'inventaire B.1)
--
-- Source : doc/audit/REFERENTIEL-CHAINAGES-TRANSVERSAUX-2026-09-24.md §B.2 (lignes 19, 44, 45, 47) ;
-- inventaire mesuré : doc/audit/plan6/B1-INVENTAIRE-62-REGLES-2026-10-05.md (⬜).
--
--   R-019 — `invoices.status = cancelled` → avoir ou contre-passation, sortie du lettrage,
--           régénération de la TVA, arrêt des relances ;
--   R-044 — `manufacturing_orders.status = in_progress` → consommation réelle, déclaration
--           de production, mise en en-cours ;
--   R-045 — `manufacturing_orders.status = planned` → réservation des composants,
--           engagement de capacité, réservation de trésorerie ;
--   R-047 — `stock_movements.movement_type = transfer` → transfert entre dépôts (deux
--           mouvements liés, valorisation conservée, biens en transit).
--
-- MESURÉ (B.1). Aucun déclencheur ne testait `invoices.cancelled`, `manufacturing_orders.
-- in_progress`/`planned`, ni `stock_movements.movement_type = transfer`.
--
-- CE QUE CE FICHIER FAIT — quatre maillons « événement » (accroches), idempotents :
--   * `invoices.cancelled` → `sale.invoice.cancelled` ;
--   * `manufacturing_orders.in_progress` / `.planned` → `production.order.*` ;
--   * `stock_movements.transfer` (à l'INSERT) → `stock.transfer`.
--
-- CE QUI RESTE À LA COORDINATION : la CONTRE-PASSATION comptable d'une facture (R-019) ;
-- la CONSOMMATION des composants et l'en-cours (R-044), la RÉSERVATION (R-045) et le
-- TRANSFERT de stock à DEUX mouvements liés (R-047) sont des effets de STOCK / COMPTABLES
-- partagés (R7, parties E) — l'événement en est l'accroche.
--
-- PRIORITÉ R7 : aucune fonction existante réécrite (maillons neufs `regle_*`).
-- ============================================================

INSERT INTO document_effects (tenant_id, document_type, evenement, effet,
                              ecrit_comptable, journal_code, touche_stock, touche_paie,
                              reversible, obligatoire, actif, note)
VALUES (NULL, 'invoices', 'cancelled', 'sale.invoice.cancelled',
        false, NULL, false, false, true, false, true, 'R-019 : facture client annulée. Partie B.'),
       (NULL, 'manufacturing_orders', 'planned', 'production.order.planned',
        false, NULL, false, false, true, false, true, 'R-045 : OF planifié. Partie B.'),
       (NULL, 'manufacturing_orders', 'in_progress', 'production.order.in_progress',
        false, NULL, true, false, true, false, true, 'R-044 : OF en cours. Partie B.'),
       (NULL, 'stock_movements', 'transfer', 'stock.transfer',
        false, NULL, true, false, true, false, true, 'R-047 : transfert entre dépôts. Partie B.')
ON CONFLICT DO NOTHING;

-- ── R-019 — facture client annulée ──
CREATE OR REPLACE FUNCTION public.regle_invoice_client_annulee()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $maillon$
DECLARE v_debut timestamptz := clock_timestamp();
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status OR NEW.status IS DISTINCT FROM 'cancelled' THEN
    RETURN NULL;
  END IF;
  IF NEW.tenant_id IS NULL THEN RETURN NULL; END IF;
  IF EXISTS (SELECT 1 FROM domain_events de
             WHERE de.tenant_id = NEW.tenant_id AND de.event_name = 'invoices.cancelled' AND de.aggregate_id = NEW.id) THEN
    RETURN NULL;
  END IF;
  IF NOT chain_avant(NEW.tenant_id, 'invoices', 'cancelled', 'sale.invoice.cancelled',
                     'invoices', NEW.id, NULL,
                     format('Facture %s : l''annulation n''a pas été tracée (règle sale.invoice.cancelled, module ventes).', NEW.number)) THEN
    RETURN NULL;
  END IF;
  PERFORM emit_domain_event(NEW.tenant_id, 'invoices.cancelled', 'invoices', NEW.id,
                            jsonb_build_object('number', NEW.number, 'customer_id', NEW.customer_id, 'total', NEW.total), NULL);
  PERFORM chain_apres(NEW.tenant_id, 'sale.invoice.cancelled', 'invoices', NEW.id, v_debut, 0, 'applique', NULL, NULL, NULL);
  RETURN NULL;
END $maillon$;

-- ── R-044 / R-045 — OF planifié / en cours ──
CREATE OR REPLACE FUNCTION public.regle_of_planifie_en_cours()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $maillon$
DECLARE
  v_debut timestamptz := clock_timestamp();
  v_event text;
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status OR NEW.status NOT IN ('planned', 'in_progress') THEN
    RETURN NULL;
  END IF;
  IF NEW.tenant_id IS NULL THEN RETURN NULL; END IF;
  v_event := 'manufacturing_orders.' || NEW.status;
  IF EXISTS (SELECT 1 FROM domain_events de
             WHERE de.tenant_id = NEW.tenant_id AND de.event_name = v_event AND de.aggregate_id = NEW.id) THEN
    RETURN NULL;
  END IF;
  IF NOT chain_avant(NEW.tenant_id, 'manufacturing_orders', NEW.status, 'production.order.' || NEW.status,
                     'manufacturing_orders', NEW.id, NULL,
                     format('Ordre de fabrication %s : l''état « %s » n''a pas été tracé (règle production.order.%s, module production).',
                            NEW.number, NEW.status, NEW.status)) THEN
    RETURN NULL;
  END IF;
  PERFORM emit_domain_event(NEW.tenant_id, v_event, 'manufacturing_orders', NEW.id,
                            jsonb_build_object('number', NEW.number, 'product_id', NEW.product_id,
                                               'quantity', NEW.quantity, 'status', NEW.status), NULL);
  PERFORM chain_apres(NEW.tenant_id, 'production.order.' || NEW.status, 'manufacturing_orders', NEW.id,
                      v_debut, 0, 'applique', NULL, NULL, NULL);
  RETURN NULL;
END $maillon$;

-- ── R-047 — transfert entre dépôts ──
CREATE OR REPLACE FUNCTION public.regle_stock_transfert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $maillon$
DECLARE v_debut timestamptz := clock_timestamp();
BEGIN
  IF NEW.movement_type IS DISTINCT FROM 'transfer' THEN
    RETURN NULL;
  END IF;
  IF NEW.tenant_id IS NULL THEN RETURN NULL; END IF;
  IF NOT chain_avant(NEW.tenant_id, 'stock_movements', 'transfer', 'stock.transfer',
                     'stock_movements', NEW.id, NULL,
                     format('Mouvement %s : le transfert n''a pas été tracé (règle stock.transfer, module stock).', NEW.id)) THEN
    RETURN NULL;
  END IF;
  PERFORM emit_domain_event(NEW.tenant_id, 'stock_movements.transfer', 'stock_movements', NEW.id,
                            jsonb_build_object('product_id', NEW.product_id, 'warehouse_id', NEW.warehouse_id,
                                               'quantity', NEW.quantity, 'reference', NEW.reference), NULL);
  PERFORM chain_apres(NEW.tenant_id, 'stock.transfer', 'stock_movements', NEW.id, v_debut, 0, 'applique', NULL, NULL, NULL);
  RETURN NULL;
END $maillon$;

-- ── Les déclencheurs (`zz_` : ils passent APRÈS les déclencheurs métier) ──
DROP TRIGGER IF EXISTS zz_b2r019_invoice_annulee ON invoices;
CREATE TRIGGER zz_b2r019_invoice_annulee AFTER UPDATE ON invoices
FOR EACH ROW EXECUTE FUNCTION public.regle_invoice_client_annulee();

DROP TRIGGER IF EXISTS zz_b2r044_r045_of_etat ON manufacturing_orders;
CREATE TRIGGER zz_b2r044_r045_of_etat AFTER UPDATE ON manufacturing_orders
FOR EACH ROW EXECUTE FUNCTION public.regle_of_planifie_en_cours();

DROP TRIGGER IF EXISTS zz_b2r047_stock_transfert ON stock_movements;
CREATE TRIGGER zz_b2r047_stock_transfert AFTER INSERT ON stock_movements
FOR EACH ROW EXECUTE FUNCTION public.regle_stock_transfert();

-- Ces maillons ne sont pas des points d'entrée (aucun EXECUTE pour les rôles applicatifs).
REVOKE ALL ON FUNCTION public.regle_invoice_client_annulee() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.regle_of_planifie_en_cours() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.regle_stock_transfert() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.regle_invoice_client_annulee() TO service_role;
GRANT EXECUTE ON FUNCTION public.regle_of_planifie_en_cours() TO service_role;
GRANT EXECUTE ON FUNCTION public.regle_stock_transfert() TO service_role;
