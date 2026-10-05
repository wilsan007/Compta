-- ============================================================
-- 652_stock_transfer_execute.sql — STK-14 / E.2 (partie E)
-- Numéro pris le 2026-10-05 par migration-numero.mjs (ligne « plan6 E (opérations) », branche plan6/e-operations).
--
-- Constat : `stock_transfers` et `stock_transfer_lines` existaient depuis la 125
-- avec leur RLS et la vue `v_stock_in_transit`, mais AUCUN moteur ne les
-- exécutait — ni fonction, ni requête, ni écran. Un transfert saisi ne bougeait
-- rien : c'était une coquille (ORPH-02).
--
-- Décision : deux étapes, comme le modèle le prévoit (statut `pending` →
-- `in_transit` → `received`), chacune atomique et adossée au moteur unique de
-- mouvement (`update_stock_on_movement`, `update_cump_on_movement`,
-- `create_journal_on_stock_movement` — 101 et 254) :
--   · `ship_stock_transfer(id)`    : sort la quantité du dépôt source (mouvement
--                                    « out », statut `in_transit`) ;
--   · `receive_stock_transfer(id)` : la fait entrer au dépôt destination
--                                    (mouvement « in »), au coût de la sortie.
-- Pendant le transit, le stock reste détenu par l'entreprise — c'est ce que la
-- vue `v_stock_in_transit` mesure et que la comptabilité valorise (254).
-- ============================================================

CREATE OR REPLACE FUNCTION ship_stock_transfer(p_transfer_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_tr stock_transfers%ROWTYPE;
  v_line record;
  v_cost numeric;
BEGIN
  SELECT * INTO v_tr FROM stock_transfers
  WHERE id = p_transfer_id AND tenant_id = v_tid FOR UPDATE;
  IF v_tr.id IS NULL THEN RAISE EXCEPTION 'Transfert introuvable'; END IF;
  IF v_tr.status <> 'pending' THEN
    RAISE EXCEPTION 'Transfert % non expédiable (statut « % »)', v_tr.transfer_number, v_tr.status;
  END IF;
  IF v_tr.from_warehouse_id = v_tr.to_warehouse_id THEN
    RAISE EXCEPTION 'Dépôt de départ et d''arrivée identiques';
  END IF;

  FOR v_line IN
    SELECT * FROM stock_transfer_lines WHERE transfer_id = p_transfer_id AND tenant_id = v_tid
  LOOP
    -- Coût de la sortie : celui de la ligne, sinon le CUMP courant du dépôt source.
    SELECT COALESCE(v_line.unit_cost,
                    (SELECT sq.unit_cost FROM stock_quantities sq
                      WHERE sq.tenant_id = v_tid AND sq.product_id = v_line.product_id
                        AND sq.warehouse_id = v_tr.from_warehouse_id), 0)
    INTO v_cost;

    INSERT INTO stock_movements
      (tenant_id, product_id, warehouse_id, type, movement_type, quantity, unit_cost,
       date, movement_date, reference_type, reference_id, notes)
    VALUES
      (v_tid, v_line.product_id, v_tr.from_warehouse_id, 'out', 'out', v_line.quantity, v_cost,
       COALESCE(v_tr.shipment_date, CURRENT_DATE), COALESCE(v_tr.shipment_date, CURRENT_DATE),
       'stock_transfer', v_tr.id, 'Transfert ' || v_tr.transfer_number || ' — sortie');
  END LOOP;

  UPDATE stock_transfers
  SET status = 'in_transit', shipment_date = COALESCE(shipment_date, CURRENT_DATE)
  WHERE id = p_transfer_id AND tenant_id = v_tid;
END;
$$;

CREATE OR REPLACE FUNCTION receive_stock_transfer(p_transfer_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_tr stock_transfers%ROWTYPE;
  v_line record;
  v_cost numeric;
BEGIN
  SELECT * INTO v_tr FROM stock_transfers
  WHERE id = p_transfer_id AND tenant_id = v_tid FOR UPDATE;
  IF v_tr.id IS NULL THEN RAISE EXCEPTION 'Transfert introuvable'; END IF;
  IF v_tr.status <> 'in_transit' THEN
    RAISE EXCEPTION 'Transfert % non réceptionnable (statut « % »)', v_tr.transfer_number, v_tr.status;
  END IF;

  FOR v_line IN
    SELECT * FROM stock_transfer_lines WHERE transfer_id = p_transfer_id AND tenant_id = v_tid
  LOOP
    -- Le coût d'entrée est celui de la sortie : c'est la valeur déjà écrite au
    -- grand livre par la sortie (254). À défaut, le coût de la ligne.
    SELECT COALESCE(
             (SELECT sm.unit_cost FROM stock_movements sm
               WHERE sm.tenant_id = v_tid AND sm.reference_type = 'stock_transfer'
                 AND sm.reference_id = v_tr.id AND sm.product_id = v_line.product_id
                 AND sm.movement_type = 'out'
               ORDER BY sm.created_at DESC LIMIT 1),
             v_line.unit_cost, 0)
    INTO v_cost;

    INSERT INTO stock_movements
      (tenant_id, product_id, warehouse_id, type, movement_type, quantity, unit_cost,
       date, movement_date, reference_type, reference_id, notes)
    VALUES
      (v_tid, v_line.product_id, v_tr.to_warehouse_id, 'in', 'in', v_line.quantity, v_cost,
       COALESCE(v_tr.expected_receipt_date, CURRENT_DATE), COALESCE(v_tr.expected_receipt_date, CURRENT_DATE),
       'stock_transfer', v_tr.id, 'Transfert ' || v_tr.transfer_number || ' — entrée');
  END LOOP;

  UPDATE stock_transfers
  SET status = 'received', actual_receipt_date = COALESCE(actual_receipt_date, CURRENT_DATE)
  WHERE id = p_transfer_id AND tenant_id = v_tid;
END;
$$;

COMMENT ON FUNCTION ship_stock_transfer(uuid) IS
  'STK-14 (652) : expédie un transfert inter-dépôts — sort la quantité du dépôt source (mouvement « out », statut « in_transit »). Le stock reste détenu par l''entreprise (vue v_stock_in_transit).';
COMMENT ON FUNCTION receive_stock_transfer(uuid) IS
  'STK-14 (652) : réceptionne un transfert — fait entrer la quantité au dépôt destination (mouvement « in »), au coût de la sortie (statut « received »).';

REVOKE ALL ON FUNCTION ship_stock_transfer(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION receive_stock_transfer(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION ship_stock_transfer(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION receive_stock_transfer(uuid) TO authenticated;

