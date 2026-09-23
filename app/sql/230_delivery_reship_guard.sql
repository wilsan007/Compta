-- ============================================================
-- 230_delivery_reship_guard.sql — réexpédier un BL : un message, pas un code SQL
--
-- M-06 du reste-à-faire demandait de revérifier la « double sortie de stock »
-- signalée le 12 septembre. Mesuré sur base neuve à la 229 : elle n'existe plus.
-- La 96 (STK-01) a restreint le déclenchement à draft/confirmed → shipped, et
-- `uq_stock_movement_source` bloque le reste — parce que ce déclencheur-là, lui,
-- renseigne `reference_id` (c'est son absence qui laissait passer la production,
-- cf. 229).
--
-- Reste un défaut d'un autre ordre : le chemin expédié → annulé → expédié est
-- permis par la contrainte CHECK des statuts, donc atteignable depuis l'écran,
-- et il remonte à l'utilisateur :
--     duplicate key value violates unique constraint "uq_stock_movement_source"
-- L'index sauve le stock ; il n'explique rien. On refuse explicitement, dans les
-- mêmes termes que la 229, avant d'atteindre l'index.
--
-- Hors périmètre, inscrit au registre : annuler un BL expédié ne contrepasse pas
-- la sortie de stock (même manque que pour l'OF, M-06/M-08 suite).
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
BEGIN
  -- STK-01 : Déclencher uniquement au passage de draft/confirmed → shipped
  -- (pas sur shipped → delivered, qui ne doit pas re-décrémenter le stock)
  IF OLD.status NOT IN ('shipped', 'delivered') AND NEW.status = 'shipped' THEN

    -- M-06 : un BL annulé puis réexpédié retombait sur l'index unique. Le stock
    -- était sauf, le message était un code d'erreur PostgreSQL.
    SELECT count(*) INTO v_deja
    FROM stock_movements
    WHERE tenant_id = NEW.tenant_id AND reference_type = 'delivery_note' AND reference_id = NEW.id;

    IF v_deja > 0 THEN
      RAISE EXCEPTION 'BL % déjà expédié : sa sortie de stock existe. Contrepasser avant de réexpédier.', NEW.number
        USING ERRCODE = '23505';
    END IF;

    FOR v_line IN SELECT * FROM delivery_note_lines WHERE delivery_note_id = NEW.id AND tenant_id = NEW.tenant_id AND quantity > 0 LOOP
      INSERT INTO stock_movements (tenant_id, product_id, movement_type, type, quantity, reference, reference_type, reference_id, date, movement_date, notes)
      VALUES (NEW.tenant_id, v_line.product_id, 'out', 'out', v_line.quantity, 'BL-' || NEW.number, 'delivery_note', NEW.id, NEW.delivery_date, NEW.delivery_date, v_line.description);
    END LOOP;
  END IF;
  RETURN NEW;
END;
$$;

-- ------------------------------------------------------------
-- M-06, second défaut — trouvé en exécutant le scénario T05 :
-- livrer une commande confirmée échouait TOUJOURS, sur toutes les données.
--
--   release_stock_on_delivery écrit `status = 'fulfilled'`
--   stock_reservations_status_check n'admet que
--     'active', 'released', 'consumed', 'cancelled'
--
-- Résultat : « new row for relation "stock_reservations" violates check
-- constraint ». Le passage d'une commande à « livrée » était impossible dès
-- lors qu'elle avait été confirmée, donc réservée. Aucun test ne passait par
-- là : la 173 vérifie la valorisation du stock, pas le cycle de réservation.
--
-- 'consumed' est le statut juste : la réservation n'est pas relâchée, elle est
-- consommée par la sortie de stock. 'released' reste celui de l'annulation.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION release_stock_on_delivery()
RETURNS trigger
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
      SET status = 'consumed', updated_at = now()
      WHERE id = v_reservation.id;
    END LOOP;
  END IF;
  RETURN NEW;
END;
$$;
