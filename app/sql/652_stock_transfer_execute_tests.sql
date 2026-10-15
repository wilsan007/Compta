-- ============================================================
-- 652_stock_transfer_execute_tests.sql — STK-14 / E.2
--
-- Mesuré AVANT la 652 : `stock_transfers` n'avait aucun moteur — la table et ses
-- lignes existaient, mais rien ne bougeait le stock. Après : expédier sort la
-- quantité du dépôt source, réceptionner la fait entrer au dépôt destination.
-- ============================================================
\ir ci/audit_helpers.sql
\ir ci/ledger_fixture.sql
SELECT set_config('audit.file', '652', false);
DELETE FROM _audit_results WHERE file = '652';

CREATE OR REPLACE FUNCTION _mk652(p_nom text, OUT t uuid, OUT w1 uuid, OUT w2 uuid, OUT p uuid)
LANGUAGE plpgsql AS $$
BEGIN
  t := _mk_tenant(p_nom, false);
  PERFORM _ledger_fixture(t);
  INSERT INTO warehouses (tenant_id, code, name) VALUES (t, 'W1-' || p_nom, 'Source ' || p_nom) RETURNING id INTO w1;
  INSERT INTO warehouses (tenant_id, code, name) VALUES (t, 'W2-' || p_nom, 'Dest ' || p_nom) RETURNING id INTO w2;
  INSERT INTO products (tenant_id, name, sku, type, cost_price)
  VALUES (t, 'Article ' || p_nom, 'SKU-' || p_nom, 'stock', 10) RETURNING id INTO p;
END $$;

-- Entrée initiale de stock dans un dépôt (mouvement « in », le moteur fait le reste).
CREATE OR REPLACE FUNCTION _seed652(p_t uuid, p_p uuid, p_w uuid, p_qty numeric, p_cost numeric)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO stock_movements
    (tenant_id, product_id, warehouse_id, type, movement_type, quantity, unit_cost, date, movement_date, reference_type, notes)
  VALUES (p_t, p_p, p_w, 'in', 'in', p_qty, p_cost, CURRENT_DATE, CURRENT_DATE, 'seed652', 'entrée initiale');
END $$;

-- T01 — expédition puis réception : 30 de W1 vers W2
DO $$
DECLARE t uuid; w1 uuid; w2 uuid; p uuid; tr uuid; q1 numeric; q2 numeric; st text; n int;
BEGIN
  SELECT * INTO t, w1, w2, p FROM _mk652('VAL652T01');
  PERFORM _seed652(t, p, w1, 100, 10);
  INSERT INTO stock_transfers (tenant_id, transfer_number, from_warehouse_id, to_warehouse_id)
  VALUES (t, 'TR-T01', w1, w2) RETURNING id INTO tr;
  INSERT INTO stock_transfer_lines (tenant_id, transfer_id, product_id, quantity) VALUES (t, tr, p, 30);

  PERFORM ship_stock_transfer(tr);
  SELECT status INTO st FROM stock_transfers WHERE id = tr;
  SELECT COALESCE((SELECT quantity FROM stock_quantities WHERE tenant_id = t AND product_id = p AND warehouse_id = w1), 0) INTO q1;
  PERFORM _rec('T01a', 'expédition : 30 sortent du dépôt source, statut « in_transit »',
    (q1 = 70 AND st = 'in_transit'), format('source=%s (70 attendu), statut=%s', q1, st));

  PERFORM receive_stock_transfer(tr);
  SELECT status INTO st FROM stock_transfers WHERE id = tr;
  SELECT COALESCE((SELECT quantity FROM stock_quantities WHERE tenant_id = t AND product_id = p AND warehouse_id = w2), 0) INTO q2;
  SELECT count(*) INTO n FROM stock_movements WHERE tenant_id = t AND reference_type = 'stock_transfer' AND reference_id = tr;
  PERFORM _rec('T01b', 'réception : 30 entrent au dépôt destination, statut « received », 2 mouvements',
    (q2 = 30 AND st = 'received' AND n = 2), format('destination=%s (30 attendu), statut=%s, mouvements=%s (2 attendus)', q2, st, n));
END $$;

-- T02 — expédier un transfert déjà expédié est refusé
DO $$
DECLARE t uuid; w1 uuid; w2 uuid; p uuid; tr uuid; refus boolean := false;
BEGIN
  SELECT * INTO t, w1, w2, p FROM _mk652('VAL652T02');
  PERFORM _seed652(t, p, w1, 50, 10);
  INSERT INTO stock_transfers (tenant_id, transfer_number, from_warehouse_id, to_warehouse_id)
  VALUES (t, 'TR-T02', w1, w2) RETURNING id INTO tr;
  INSERT INTO stock_transfer_lines (tenant_id, transfer_id, product_id, quantity) VALUES (t, tr, p, 10);
  PERFORM ship_stock_transfer(tr);
  BEGIN PERFORM ship_stock_transfer(tr); EXCEPTION WHEN OTHERS THEN refus := true; END;
  PERFORM _rec('T02', 'un transfert déjà expédié ne peut pas être ré-expédié', refus, 'refus=' || refus);
END $$;

-- T03 — réceptionner avant toute expédition est refusé
DO $$
DECLARE t uuid; w1 uuid; w2 uuid; p uuid; tr uuid; refus boolean := false;
BEGIN
  SELECT * INTO t, w1, w2, p FROM _mk652('VAL652T03');
  PERFORM _seed652(t, p, w1, 50, 10);
  INSERT INTO stock_transfers (tenant_id, transfer_number, from_warehouse_id, to_warehouse_id)
  VALUES (t, 'TR-T03', w1, w2) RETURNING id INTO tr;
  INSERT INTO stock_transfer_lines (tenant_id, transfer_id, product_id, quantity) VALUES (t, tr, p, 10);
  BEGIN PERFORM receive_stock_transfer(tr); EXCEPTION WHEN OTHERS THEN refus := true; END;
  PERFORM _rec('T03', 'réceptionner un transfert non expédié est refusé', refus, 'refus=' || refus);
END $$;

-- T04 — un transfert dont la source et la destination sont le même dépôt est refusé
DO $$
DECLARE t uuid; w1 uuid; w2 uuid; p uuid; tr uuid; refus boolean := false;
BEGIN
  SELECT * INTO t, w1, w2, p FROM _mk652('VAL652T04');
  PERFORM _seed652(t, p, w1, 50, 10);
  INSERT INTO stock_transfers (tenant_id, transfer_number, from_warehouse_id, to_warehouse_id)
  VALUES (t, 'TR-T04', w1, w1) RETURNING id INTO tr;
  INSERT INTO stock_transfer_lines (tenant_id, transfer_id, product_id, quantity) VALUES (t, tr, p, 10);
  BEGIN PERFORM ship_stock_transfer(tr); EXCEPTION WHEN OTHERS THEN refus := true; END;
  PERFORM _rec('T04', 'dépôt de départ = dépôt d''arrivée est refusé', refus, 'refus=' || refus);
END $$;

SELECT _audit_assert('652');
