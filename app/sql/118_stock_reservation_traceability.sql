-- ============================================================
-- 118_stock_reservation_traceability.sql
-- STK-05 : Réservations de stock + STK-06 : Traçabilité série/lot
-- ============================================================

-- ============================================================
-- STK-05 : Réservations de stock
-- ============================================================
-- LOT1-03 : reserved_quantity existe déjà dans le schéma d'origine.
-- On ne crée pas de colonne quantity_reserved redondante.

-- Colonne générée : quantity_available = quantity - reserved_quantity
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'stock_quantities' AND column_name = 'quantity_available'
  ) THEN
    ALTER TABLE stock_quantities
      ADD COLUMN quantity_available numeric GENERATED ALWAYS AS (quantity - reserved_quantity) STORED;
  END IF;
EXCEPTION WHEN OTHERS THEN
  -- Si la colonne existe déjà ou ne peut pas être générée, on continue
  NULL;
END $$;

-- ============================================================
-- STK-05 : Table des réservations de stock
-- ============================================================
CREATE TABLE IF NOT EXISTS stock_reservations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  product_id uuid NOT NULL,
  warehouse_id uuid,
  quantity numeric NOT NULL,
  reserved_by text NOT NULL DEFAULT 'sales_order',
  reference_id uuid,           -- ID de la commande/OF qui a réservé
  reference_type text NOT NULL DEFAULT 'sales_order'
    CHECK (reference_type IN ('sales_order', 'manufacturing_order', 'manual')),
  status text NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'released', 'consumed', 'cancelled')),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE stock_reservations ENABLE ROW LEVEL SECURITY;
CREATE POLICY stock_reservations_tenant ON stock_reservations
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

CREATE INDEX IF NOT EXISTS idx_stock_reservations_product
  ON stock_reservations (tenant_id, product_id, status);

-- ============================================================
-- STK-05 : Trigger de réservation à la confirmation de commande
-- ============================================================
CREATE OR REPLACE FUNCTION reserve_stock_on_sales_order_confirm()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_line record;
  v_available numeric;
  v_tid uuid := NEW.tenant_id;
BEGIN
  IF NEW.status <> 'confirmed' THEN
    RETURN NEW;
  END IF;

  IF OLD.status = 'confirmed' AND NEW.status = 'confirmed' THEN
    RETURN NEW; -- déjà confirmée
  END IF;

  -- Pour chaque ligne de commande, réserver le stock
  FOR v_line IN
    SELECT * FROM sales_order_lines
    WHERE sales_order_id = NEW.id AND tenant_id = v_tid
  LOOP
    -- Vérifier la disponibilité avec verrou de ligne
    SELECT quantity - COALESCE(reserved_quantity, 0) INTO v_available
    FROM stock_quantities
    WHERE tenant_id = v_tid AND product_id = v_line.product_id
    FOR UPDATE;

    IF v_available IS NULL OR v_available < v_line.quantity THEN
      -- Stock insuffisant : libérer les réservations déjà faites et bloquer
      DELETE FROM stock_reservations
      WHERE reference_id = NEW.id AND tenant_id = v_tid;
      RAISE EXCEPTION
        'Stock insuffisant pour le produit % : disponible %, demandé %',
        v_line.product_id, COALESCE(v_available, 0), v_line.quantity;
    END IF;

    -- Créer la réservation
    INSERT INTO stock_reservations (
      tenant_id, product_id, warehouse_id, quantity,
      reserved_by, reference_id, reference_type, status
    ) VALUES (
      v_tid, v_line.product_id, NULL, v_line.quantity,
      'sales_order', NEW.id, 'sales_order', 'active'
    );

    -- Mettre à jour la quantité réservée
    UPDATE stock_quantities
    SET reserved_quantity = COALESCE(reserved_quantity, 0) + v_line.quantity,
        updated_at = now()
    WHERE tenant_id = v_tid AND product_id = v_line.product_id;
  END LOOP;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS reserve_stock_on_so_confirm ON sales_orders;
CREATE TRIGGER reserve_stock_on_so_confirm
  AFTER UPDATE ON sales_orders
  FOR EACH ROW
  EXECUTE FUNCTION reserve_stock_on_sales_order_confirm();

-- ============================================================
-- STK-05 : Libérer la réservation à l'annulation
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
    -- Libérer les réservations
    FOR v_reservation IN
      SELECT * FROM stock_reservations
      WHERE reference_id = NEW.id AND tenant_id = NEW.tenant_id AND status = 'active'
    LOOP
      UPDATE stock_quantities
      SET reserved_quantity = GREATEST(0, COALESCE(reserved_quantity, 0) - v_reservation.quantity),
          updated_at = now()
      WHERE tenant_id = NEW.tenant_id AND product_id = v_reservation.product_id;

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
-- STK-06 : Traçabilité série et lot
-- ============================================================
ALTER TABLE stock_movements ADD COLUMN IF NOT EXISTS lot_id uuid;
ALTER TABLE stock_movements ADD COLUMN IF NOT EXISTS serial_id uuid;

ALTER TABLE products ADD COLUMN IF NOT EXISTS tracking text
  DEFAULT 'none' CHECK (tracking IN ('none', 'lot', 'serial'));

-- ============================================================
-- STK-06 : Trigger de contrôle du lot/série à la saisie
-- ============================================================
CREATE OR REPLACE FUNCTION check_tracking_on_stock_movement()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tracking text;
BEGIN
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

DROP TRIGGER IF EXISTS check_tracking_on_sm ON stock_movements;
CREATE TRIGGER check_tracking_on_sm
  BEFORE INSERT ON stock_movements
  FOR EACH ROW
  EXECUTE FUNCTION check_tracking_on_stock_movement();

-- ============================================================
-- STK-06 : Traçabilité descendante (lot → clients livrés)
-- ============================================================
CREATE OR REPLACE FUNCTION trace_lot_downstream(p_lot_id uuid)
RETURNS TABLE(
  product_id uuid,
  product_name text,
  movement_type text,
  movement_date timestamptz,
  quantity numeric,
  reference text,
  customer_id uuid,
  customer_name text
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT
    sm.product_id,
    p.name,
    sm.movement_type,
    sm.created_at,
    sm.quantity,
    sm.reference,
    so.customer_id,
    c.name
  FROM stock_movements sm
  JOIN products p ON p.id = sm.product_id AND p.tenant_id = sm.tenant_id
  LEFT JOIN sales_order_lines sol ON sol.product_id = sm.product_id
  LEFT JOIN sales_orders so ON so.id = sol.sales_order_id AND so.tenant_id = sm.tenant_id
  LEFT JOIN customers c ON c.id = so.customer_id AND c.tenant_id = sm.tenant_id
  WHERE sm.lot_id = p_lot_id AND sm.tenant_id = current_tenant_id()
  ORDER BY sm.created_at DESC;
$$;

-- ============================================================
-- STK-06 : Traçabilité ascendante (lot matière → OF → produits finis → clients)
-- ============================================================
-- Ajouter lot_id à of_consumptions pour la traçabilité ascendante
ALTER TABLE of_consumptions ADD COLUMN IF NOT EXISTS lot_id uuid;

CREATE OR REPLACE FUNCTION trace_lot_upstream(p_lot_id uuid)
RETURNS TABLE(
  manufacturing_order_id uuid,
  mo_number text,
  product_id uuid,
  product_name text,
  quantity_produced numeric,
  customer_id uuid,
  customer_name text
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  WITH of_consumption AS (
    SELECT DISTINCT ofc.manufacturing_order_id
    FROM of_consumptions ofc
    WHERE ofc.lot_id = p_lot_id AND ofc.tenant_id = current_tenant_id()
  )
  SELECT
    mo.id,
    mo.number,
    mo.product_id,
    p.name,
    mo.quantity,
    so.customer_id,
    c.name
  FROM of_consumption oc
  JOIN manufacturing_orders mo ON mo.id = oc.manufacturing_order_id AND mo.tenant_id = current_tenant_id()
  JOIN products p ON p.id = mo.product_id AND p.tenant_id = current_tenant_id()
  LEFT JOIN sales_order_lines sol ON sol.product_id = mo.product_id
  LEFT JOIN sales_orders so ON so.id = sol.sales_order_id AND so.tenant_id = current_tenant_id()
  LEFT JOIN customers c ON c.id = so.customer_id AND c.tenant_id = current_tenant_id()
  ORDER BY mo.created_at DESC;
$$;
