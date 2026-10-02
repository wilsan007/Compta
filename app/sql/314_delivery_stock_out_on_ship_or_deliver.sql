-- ============================================================
-- 314_delivery_stock_out_on_ship_or_deliver.sql — B1 (ven-004, ven-005)
--
-- Recette /qa du 29/09/2026, écran Ventes → Bons de livraison. Deux défauts du
-- même déclencheur `create_stock_out_on_delivery` (dernière écriture : 242).
--
--   ven-005 (critique) Il n'écoutait que le passage à « Expédié » (STK-01, 133 :
--     `NEW.status = 'shipped'`). L'écran laisse choisir « Livré » directement :
--     le statut était accepté, aucune sortie n'était écrite, et le contrôle de
--     disponibilité du dépôt était donc contourné par un simple choix dans la
--     liste. Mesuré : bon de 2 articles, stock 1000 → 1000, 0 mouvement.
--
--   ven-004 (haut) Il sortait TOUTES les lignes, prestations comprises. Une
--     prestation n'a pas de stock : le contrôle du mouvement refusait
--     l'expédition avec « Stock insuffisant: disponible=0, demandé=1 », le « 1 »
--     étant la quantité de la prestation. Tout bon mêlant article et service
--     était donc intransportable.
--
-- Mesuré sur base neuve à la 313, avant ce fichier (suite 314) :
--   T01 ❌ « Livré » ne sort rien        T02 ❌ le service bloque l'expédition
--   T05b ❌ la commande n'est pas déclarée livrée à l'expédition
--   T03/T04/T05a ✅ (non-régressions 230/253 conservées)
--
-- CORRECTIFS
--   1. La sortie se déclenche au passage de tout état antérieur (pending,
--      cancelled…) vers « Expédié » **ou** « Livré » : les deux chemins de
--      l'écran sortent la marchandise, une seule fois par bon.
--   2. Seules les lignes rattachées à un article de type `stock` produisent un
--      mouvement ; une prestation part sans sortie, et sans passer par le
--      contrôle de disponibilité.
--   3. Le garde de réexpédition (23505) et la libération de la réservation
--      (S-07, 242) sont conservés à l'identique.
--
-- COMPLÉMENT, même chaîne : la commande se déclarait livrée dès la CRÉATION du
-- bon (`delivery_status`, `fully_delivered` — écrits par l'écran, misc.ts). Elle
-- ne l'est plus que lorsque la marchandise sort ; c'est ici que ces colonnes se
-- posent, et l'écran ne les écrit plus.
--
-- Hors périmètre, sans effet mesuré : la réservation d'une ligne de prestation
-- (créée par la confirmation, 242) reste active — un service n'a pas de stock à
-- réserver ; `release_stock_on_delivery` la consommera si la commande passe à
-- `status = 'delivered'`.
-- ============================================================
CREATE OR REPLACE FUNCTION create_stock_out_on_delivery()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_line RECORD;
  v_deja int;
  v_wh uuid;
  v_libere numeric;
  v_tout_livre boolean;
BEGIN
  -- B1 (ven-005) : la marchandise sort dès qu'elle part — « Expédié » comme
  -- « Livré » — mais une seule fois par bon (STK-01 conservé).
  IF OLD.status NOT IN ('shipped', 'delivered') AND NEW.status IN ('shipped', 'delivered') THEN

    -- M-06 : un BL annulé puis réexpédié retombait sur l'index unique. Le stock
    -- était sauf, le message était un code d'erreur PostgreSQL.
    SELECT count(*) INTO v_deja
    FROM stock_movements
    WHERE tenant_id = NEW.tenant_id AND reference_type = 'delivery_note' AND reference_id = NEW.id;

    IF v_deja > 0 THEN
      RAISE EXCEPTION 'BL % déjà expédié : sa sortie de stock existe. Contrepasser avant de réexpédier.', NEW.number
        USING ERRCODE = '23505';
    END IF;

    FOR v_line IN
      SELECT l.*, p.type AS produit_type
      FROM delivery_note_lines l
      LEFT JOIN products p ON p.id = l.product_id AND p.tenant_id = l.tenant_id
      WHERE l.delivery_note_id = NEW.id AND l.tenant_id = NEW.tenant_id AND l.quantity > 0
    LOOP
      -- B1 (ven-004) : une prestation — ou une ligne libre, sans article — n'a
      -- pas de stock. Elle part sans mouvement, et sans passer par le contrôle
      -- de disponibilité qui refusait tout le bon.
      IF v_line.product_id IS NULL OR COALESCE(v_line.produit_type, 'stock') <> 'stock' THEN
        CONTINUE;
      END IF;

      -- S-05 : le dépôt de la sortie — réservation de la commande, dépôt qui
      -- peut servir la ligne, dépôt de la société
      v_wh := resolve_delivery_warehouse(NEW.tenant_id, NEW.sales_order_id, v_line.product_id, v_line.quantity);

      INSERT INTO stock_movements (
        tenant_id, product_id, warehouse_id, movement_type, type, quantity,
        lot_id, serial_id,
        reference, reference_type, reference_id, date, movement_date, notes
      ) VALUES (
        NEW.tenant_id, v_line.product_id, v_wh, 'out', 'out', v_line.quantity,
        v_line.lot_id, v_line.serial_id,
        'BL-' || NEW.number, 'delivery_note', NEW.id, NEW.delivery_date, NEW.delivery_date, v_line.description
      );

      -- S-07 : la marchandise est partie, la réservation de la commande l'est
      -- aussi, à hauteur de la ligne livrée
      v_libere := _release_sales_order_reservation(NEW.tenant_id, NEW.sales_order_id, v_line.product_id, v_line.quantity);
    END LOOP;

    -- B1, complément : la commande ne se dit livrée qu'une fois la marchandise
    -- sortie. Posé ici — et nulle part ailleurs : l'écran n'écrit plus ces
    -- colonnes (une colonne dénormalisée ne se lit pas sans être tenue ailleurs).
    IF NEW.sales_order_id IS NOT NULL THEN
      SELECT bool_and(COALESCE(l.delivered_quantity, 0) >= l.quantity) INTO v_tout_livre
      FROM sales_order_lines l
      WHERE l.tenant_id = NEW.tenant_id AND l.sales_order_id = NEW.sales_order_id;

      IF v_tout_livre IS NOT NULL THEN
        UPDATE sales_orders
        SET delivery_status = CASE WHEN v_tout_livre THEN 'delivered' ELSE 'partial' END,
            fully_delivered = v_tout_livre,
            updated_at = now()
        WHERE id = NEW.sales_order_id AND tenant_id = NEW.tenant_id;
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END $$;

GRANT EXECUTE ON FUNCTION create_stock_out_on_delivery() TO service_role;
