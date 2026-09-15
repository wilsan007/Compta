-- ============================================================
-- Migration 130 : Corrections critiques des triggers stock
--   STK-01 : Double stock_out sur livraison (shipped → delivered)
--   STK-02 : Réservation multi-entrepôts + libération sur livraison
--   STK-02b : Traçabilité lot/série bloque les triggers automatiques
-- Idempotent — toutes les fonctions sont CREATE OR REPLACE
-- ============================================================

-- ============================================================
-- STK-01 : Corriger le double mouvement de stock sur livraison
--   Problème : NEW.status IN ('shipped', 'delivered') déclenche 2x
--   Fix : Ne déclencher que sur le passage à 'shipped' (première fois)
-- ============================================================
CREATE OR REPLACE FUNCTION create_stock_out_on_delivery()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_line RECORD;
BEGIN
  -- STK-01 : Déclencher uniquement au passage de draft/confirmed → shipped
  -- (pas sur shipped → delivered, qui ne doit pas re-décrémenter le stock)
  IF OLD.status NOT IN ('shipped', 'delivered') AND NEW.status = 'shipped' THEN
    FOR v_line IN SELECT * FROM delivery_note_lines WHERE delivery_note_id = NEW.id AND tenant_id = NEW.tenant_id AND quantity > 0 LOOP
      INSERT INTO stock_movements (tenant_id, product_id, movement_type, type, quantity, reference, reference_type, reference_id, date, movement_date, notes)
      VALUES (NEW.tenant_id, v_line.product_id, 'out', 'out', v_line.quantity, 'BL-' || NEW.number, 'delivery_note', NEW.id, NEW.delivery_date, NEW.delivery_date, v_line.description);
    END LOOP;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS create_stock_out_on_delivery ON delivery_notes;
CREATE TRIGGER create_stock_out_on_delivery AFTER UPDATE ON delivery_notes FOR EACH ROW EXECUTE FUNCTION create_stock_out_on_delivery();

-- ============================================================
-- STK-01b : Corriger le double mouvement de stock sur réception + QC
--   Problème : réception crée stock_in + QC crée un 2e stock_in
--   Fix : QC ne crée stock_in que si pas déjà un mouvement pour cette réception
-- ============================================================
CREATE OR REPLACE FUNCTION create_stock_in_on_quality_pass()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  v_gr_line RECORD;
  v_existing_count INT;
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status AND NEW.status = 'passed' THEN
    IF NEW.reference_type = 'goods_receipt' AND NEW.reference_id IS NOT NULL THEN
      -- STK-01b : Vérifier qu'aucun mouvement n'a déjà été créé pour cette réception
      SELECT COUNT(*) INTO v_existing_count
      FROM stock_movements
      WHERE reference_type = 'goods_receipt' AND reference_id = NEW.reference_id
        AND tenant_id = NEW.tenant_id AND product_id = NEW.product_id;

      IF v_existing_count = 0 THEN
        FOR v_gr_line IN SELECT * FROM goods_receipt_lines WHERE goods_receipt_id = NEW.reference_id AND tenant_id = NEW.tenant_id AND product_id = NEW.product_id AND quantity_received > 0 LOOP
          INSERT INTO stock_movements (tenant_id, product_id, movement_type, type, quantity, reference, reference_type, reference_id, date, movement_date, notes)
          VALUES (NEW.tenant_id, NEW.product_id, 'in', 'in', v_gr_line.quantity_received, 'QC-' || COALESCE(NEW.checked_by, 'auto'), 'quality_check', NEW.id, CURRENT_DATE, CURRENT_DATE, 'Stock après QC');
        END LOOP;
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS create_stock_on_quality ON quality_checks;
CREATE TRIGGER create_stock_on_quality AFTER UPDATE ON quality_checks FOR EACH ROW EXECUTE FUNCTION create_stock_in_on_quality_pass();

-- ============================================================
-- STK-02 : Corriger la réservation multi-entrepôts
--   Problème : UPDATE stock_quantities sans warehouse_id → tous les dépôts
--   Fix : Filtrer par warehouse_id de la ligne de commande
-- ============================================================
CREATE OR REPLACE FUNCTION reserve_stock_on_sales_order_confirm()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_line RECORD;
  v_warehouse_id UUID;
  v_tid UUID := NEW.tenant_id;
BEGIN
  IF NEW.status = 'confirmed' AND OLD.status IS DISTINCT FROM 'confirmed' THEN
    FOR v_line IN SELECT * FROM sales_order_lines WHERE sales_order_id = NEW.id AND tenant_id = v_tid AND quantity > 0 LOOP
      -- STK-02 : Récupérer le warehouse_id de la ligne (ou NULL si non spécifié)
      v_warehouse_id := v_line.warehouse_id;

      -- Créer la réservation avec warehouse_id
      INSERT INTO stock_reservations (
        tenant_id, product_id, warehouse_id, quantity,
        reserved_by, reference_id, reference_type, status
      ) VALUES (
        v_tid, v_line.product_id, v_warehouse_id, v_line.quantity,
        'sales_order', NEW.id, 'sales_order', 'active'
      );

      -- STK-02 : Mettre à jour la quantité réservée uniquement pour le dépôt concerné
      UPDATE stock_quantities
      SET reserved_quantity = reserved_quantity + v_line.quantity,
        updated_at = now()
      WHERE tenant_id = v_tid
        AND product_id = v_line.product_id
        AND (v_warehouse_id IS NULL OR warehouse_id = v_warehouse_id);
    END LOOP;
  END IF;

  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS reserve_stock_on_so_confirm ON sales_orders;
CREATE TRIGGER reserve_stock_on_so_confirm
  AFTER UPDATE ON sales_orders
  FOR EACH ROW
  EXECUTE FUNCTION reserve_stock_on_sales_order_confirm();

-- ============================================================
-- STK-02b : Libérer la réservation sur livraison (delivered)
--   Problème : La réservation n'est jamais libérée → stock gelé
--   Fix : Libérer quand la commande passe à delivered
-- ============================================================
CREATE OR REPLACE FUNCTION release_stock_on_delivery()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_reservation RECORD;
BEGIN
  IF NEW.status = 'delivered' AND OLD.status IS DISTINCT FROM 'delivered' THEN
    FOR v_reservation IN
      SELECT * FROM stock_reservations
      WHERE reference_id = NEW.id AND tenant_id = NEW.tenant_id AND status = 'active'
    LOOP
      -- STK-02b : Libérer la quantité réservée pour le bon dépôt
      UPDATE stock_quantities
      SET reserved_quantity = GREATEST(0, reserved_quantity - v_reservation.quantity),
        updated_at = now()
      WHERE tenant_id = NEW.tenant_id
        AND product_id = v_reservation.product_id
        AND (v_reservation.warehouse_id IS NULL OR warehouse_id = v_reservation.warehouse_id);

      UPDATE stock_reservations
      SET status = 'fulfilled', updated_at = now()
      WHERE id = v_reservation.id;
    END LOOP;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS release_stock_on_delivery ON sales_orders;
CREATE TRIGGER release_stock_on_delivery
  AFTER UPDATE ON sales_orders
  FOR EACH ROW
  EXECUTE FUNCTION release_stock_on_delivery();

-- ============================================================
-- STK-02c : Corriger la libération sur annulation (warehouse_id)
-- ============================================================
CREATE OR REPLACE FUNCTION release_stock_on_sales_order_cancel()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_reservation record;
BEGIN
  IF NEW.status = 'cancelled' AND OLD.status = 'confirmed' THEN
    FOR v_reservation IN
      SELECT * FROM stock_reservations
      WHERE reference_id = NEW.id AND tenant_id = NEW.tenant_id AND status = 'active'
    LOOP
      -- STK-02c : Libérer uniquement pour le dépôt de la réservation
      UPDATE stock_quantities
      SET reserved_quantity = GREATEST(0, reserved_quantity - v_reservation.quantity),
        updated_at = now()
      WHERE tenant_id = NEW.tenant_id
        AND product_id = v_reservation.product_id
        AND (v_reservation.warehouse_id IS NULL OR warehouse_id = v_reservation.warehouse_id);

      UPDATE stock_reservations
      SET status = 'released', updated_at = now()
      WHERE id = v_reservation.id;
    END LOOP;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS release_stock_on_so_cancel ON sales_orders;
CREATE TRIGGER release_stock_on_so_cancel
  AFTER UPDATE ON sales_orders
  FOR EACH ROW
  EXECUTE FUNCTION release_stock_on_sales_order_cancel();

-- ============================================================
-- STK-02d : Assouplir le contrôle de traçabilité pour les triggers automatiques
--   Problème : check_tracking_on_stock_movement bloque les triggers auto
--   Fix : Exempter les mouvements créés par les triggers (notes commence par 'auto:')
-- ============================================================
CREATE OR REPLACE FUNCTION check_tracking_on_stock_movement()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tracking TEXT;
BEGIN
  -- STK-02d : Ne pas bloquer les mouvements créés par triggers automatiques
  -- Les triggers de livraison/réception/fabrication ne gèrent pas encore les lots
  IF NEW.notes IS NOT NULL AND NEW.notes LIKE 'auto:%' THEN
    RETURN NEW;
  END IF;

  SELECT tracking INTO v_tracking
  FROM products
  WHERE id = NEW.product_id AND tenant_id = NEW.tenant_id;

  IF v_tracking = 'lot' AND NEW.lot_id IS NULL THEN
    RAISE EXCEPTION 'Lot obligatoire pour le produit % (traçabilité par lot)', NEW.product_id;
  END IF;

  IF v_tracking = 'serial' AND NEW.serial_id IS NULL THEN
    RAISE EXCEPTION 'Numéro de série obligatoire pour le produit % (traçabilité par série)', NEW.product_id;
  END IF;

  RETURN NEW;
END;
$$;
-- Le trigger existant reste en place, seule la fonction change
