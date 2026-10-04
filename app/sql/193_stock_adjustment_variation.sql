-- ============================================================
-- 193_stock_adjustment_variation.sql — lot G du plan correctif (vague V3)
--
-- AUD-G05 (C14 du suivi) — prouvé par G05 de sql/192_purchases_treasury_tests.sql.
-- Un mouvement « adjustment » porte la quantité ABSOLUE constatée à l'inventaire.
-- update_stock_on_movement la recopiait dans products.stock_quantity sans toucher
-- au stock du dépôt ni aux couches de valorisation, et l'écriture de stock, faute de
-- coût, n'était jamais passée : 10 u. en stock, inventaire à 7 → fiche article 7,
-- dépôt 10, compte 310000 inchangé.
--
-- Correctif : à l'insertion, l'ajustement devient une entrée ou une sortie de la
-- DIFFÉRENCE avec le stock détenu. Stock par dépôt, couches FIFO, CUMP et écriture
-- ST suivent alors les chemins « in » / « out » déjà prouvés (suites 173, 177).
-- La hausse est valorisée au coût moyen du dépôt ; la baisse, au coût du stock
-- consommé. La trace de l'inventaire reste dans notes et reference_type.
-- ============================================================

CREATE OR REPLACE FUNCTION stock_adjustment_to_delta()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_current numeric; v_cost numeric; v_delta numeric;
BEGIN
  IF NEW.movement_type IS DISTINCT FROM 'adjustment' THEN RETURN NEW; END IF;

  IF NEW.warehouse_id IS NOT NULL THEN
    SELECT COALESCE(sum(quantity), 0),
           sum(quantity * COALESCE(unit_cost, 0)) / NULLIF(sum(quantity), 0)
      INTO v_current, v_cost
    FROM stock_quantities
    WHERE product_id = NEW.product_id AND warehouse_id = NEW.warehouse_id AND tenant_id = NEW.tenant_id;
  ELSE
    SELECT COALESCE(stock_quantity, 0) INTO v_current
    FROM products WHERE id = NEW.product_id AND tenant_id = NEW.tenant_id;
    SELECT sum(quantity * COALESCE(unit_cost, 0)) / NULLIF(sum(quantity), 0) INTO v_cost
    FROM stock_quantities WHERE product_id = NEW.product_id AND tenant_id = NEW.tenant_id;
  END IF;
  IF COALESCE(v_cost, 0) = 0 THEN
    SELECT NULLIF(cost_price, 0) INTO v_cost FROM products WHERE id = NEW.product_id AND tenant_id = NEW.tenant_id;
  END IF;

  v_delta := COALESCE(NEW.quantity, 0) - COALESCE(v_current, 0);
  NEW.notes := concat_ws(' — ', NULLIF(NEW.notes, ''),
                         format('Inventaire : %s constaté pour %s en stock', NEW.quantity, COALESCE(v_current, 0)));
  NEW.reference_type := COALESCE(NEW.reference_type, 'inventory_adjustment');

  IF v_delta >= 0 THEN
    NEW.movement_type := 'in';
    NEW.type := 'in';
    NEW.quantity := v_delta;
    NEW.unit_cost := COALESCE(NULLIF(NEW.unit_cost, 0), v_cost);
  ELSE
    NEW.movement_type := 'out';
    NEW.type := 'out';
    NEW.quantity := -v_delta;
    NEW.unit_cost := NULL;  -- une sortie est valorisée par le stock consommé
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS tg_stock_adjustment_to_delta ON stock_movements;
CREATE TRIGGER tg_stock_adjustment_to_delta
  BEFORE INSERT ON stock_movements
  FOR EACH ROW EXECUTE FUNCTION stock_adjustment_to_delta();
