-- ============================================================
-- 140_fix_cump_initialization.sql
-- LOT4-03 : CUMP initialisé à 0 à la première entrée
--
-- Problème : increment_stock créait la ligne stock_quantities avec
-- unit_cost = cost_price (souvent 0), puis update_cump calculait
-- CUMP = (Q × 0 + Q × P) / (2Q) = P/2 au lieu de P.
--
-- Fix : increment_stock accepte p_unit_cost et l'utilise à l'insertion.
-- update_stock_on_movement passe NEW.unit_cost.
-- ============================================================

-- 1. Réécrire increment_stock avec p_unit_cost
DROP FUNCTION IF EXISTS increment_stock(uuid, numeric, uuid) CASCADE;
CREATE OR REPLACE FUNCTION increment_stock(
  p_product_id uuid,
  p_qty numeric,
  p_warehouse_id uuid DEFAULT NULL,
  p_unit_cost numeric DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_product_cost numeric;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  -- Récupérer le coût de revient du produit si p_unit_cost n'est pas fourni
  IF p_unit_cost IS NULL THEN
    SELECT COALESCE(cost_price, 0) INTO v_product_cost
    FROM products
    WHERE id = p_product_id AND tenant_id = v_tid;
    p_unit_cost := COALESCE(v_product_cost, 0);
  END IF;

  -- Mettre à jour stock_quantities par entrepôt
  IF p_warehouse_id IS NOT NULL THEN
    UPDATE stock_quantities
      SET quantity = quantity + p_qty, updated_at = NOW()
      WHERE product_id = p_product_id
        AND warehouse_id = p_warehouse_id
        AND tenant_id = v_tid;

    -- Créer la ligne si elle n'existe pas avec unit_cost = p_unit_cost
    IF NOT FOUND THEN
      INSERT INTO stock_quantities (tenant_id, product_id, warehouse_id, quantity, unit_cost)
      VALUES (v_tid, p_product_id, p_warehouse_id, p_qty, p_unit_cost)
      ON CONFLICT DO NOTHING;
    END IF;
  END IF;

  -- Mettre à jour le stock total sur products
  UPDATE products
    SET stock_quantity = COALESCE(stock_quantity, 0) + p_qty,
        updated_at = NOW()
    WHERE id = p_product_id AND tenant_id = v_tid;
END;
$$;

-- 2. Réécrire update_stock_on_movement pour passer NEW.unit_cost
CREATE OR REPLACE FUNCTION update_stock_on_movement()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.movement_type = 'in' THEN
    PERFORM increment_stock(NEW.product_id, NEW.quantity, NEW.warehouse_id, NEW.unit_cost);
  ELSIF NEW.movement_type = 'out' THEN
    PERFORM decrement_stock(NEW.product_id, NEW.quantity, NEW.warehouse_id);
  ELSIF NEW.movement_type = 'adjustment' THEN
    -- Pour un ajustement, quantity est la nouvelle valeur absolue
    UPDATE products
      SET stock_quantity = NEW.quantity, updated_at = NOW()
      WHERE id = NEW.product_id AND tenant_id = NEW.tenant_id;
  ELSIF NEW.movement_type = 'initial' THEN
    -- LOT1-02 : 'initial' initialise le stock avec le coût fourni
    PERFORM increment_stock(NEW.product_id, NEW.quantity, NEW.warehouse_id, NEW.unit_cost);
  END IF;
  RETURN NEW;
END;
$$;

-- 3. Réécrire update_cump_on_movement pour gérer le cas de la première entrée
-- (ligne inexistante → créer avec unit_cost = NEW.unit_cost)
CREATE OR REPLACE FUNCTION update_cump_on_movement()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  v_qty numeric;
  v_cost numeric;
  v_new_cump numeric;
  v_tid uuid := NEW.tenant_id;
  v_exists boolean;
BEGIN
  -- Ne traiter que les entrées avec un coût positif
  IF NEW.movement_type NOT IN ('in', 'initial') OR COALESCE(NEW.unit_cost, 0) <= 0 THEN
    RETURN NEW;
  END IF;

  -- Vérifier si la ligne existe
  SELECT EXISTS(
    SELECT 1 FROM stock_quantities
    WHERE product_id = NEW.product_id AND warehouse_id = NEW.warehouse_id
      AND tenant_id = v_tid
  ) INTO v_exists;

  IF NOT v_exists THEN
    -- La ligne sera créée par increment_stock (trigger update_stock_on_movement)
    -- avec unit_cost = NEW.unit_cost. Le CUMP = NEW.unit_cost, rien à faire.
    RETURN NEW;
  END IF;

  -- Verrouiller la ligne pour sérialiser les entrées concurrentes
  SELECT COALESCE(quantity, 0), COALESCE(unit_cost, 0)
  INTO v_qty, v_cost
  FROM stock_quantities
  WHERE product_id = NEW.product_id AND warehouse_id = NEW.warehouse_id
    AND tenant_id = v_tid
  FOR UPDATE;

  -- CUMP = (valeur détenue + valeur entrante) / (quantité détenue + quantité entrante)
  v_new_cump := (v_qty * v_cost + NEW.quantity * NEW.unit_cost)
                / NULLIF(v_qty + NEW.quantity, 0);

  UPDATE stock_quantities
  SET unit_cost = COALESCE(v_new_cump, v_cost)
  WHERE product_id = NEW.product_id AND warehouse_id = NEW.warehouse_id
    AND tenant_id = v_tid;

  RETURN NEW;
END;
$$;
