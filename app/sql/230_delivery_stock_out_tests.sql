-- ============================================================
-- 230_delivery_stock_out_tests.sql — M-06 : commande → livraison → stock
--
-- Le reste-à-faire demandait de revérifier la « double sortie de stock »
-- signalée par Gemini le 12/09, et les deux colonnes de réservation.
--
-- Mesuré sur base neuve à la 229, AVANT la 230 :
--   T01/T02 déjà verts  — la double sortie n'existe plus (STK-01 + index unique)
--   T03 rouge           — réexpédier un BL annulé rend un code d'erreur SQL brut
--   T04 déjà vert       — une seule colonne `reserved_quantity` subsiste, et le
--                         cycle réserver / libérer / re-réserver ne dérive pas
--   T05 ROUGE, bloquant — livrer une commande confirmée échouait toujours :
--                         release_stock_on_delivery écrit un statut de
--                         réservation que la contrainte CHECK refuse
--
-- Les scénarios verts avant correctif restent : ils gardent acquis ce qui l'est.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '230', false);
DELETE FROM _audit_results WHERE file = '230';

CREATE OR REPLACE FUNCTION _mk_vente230(p_nom text,
  OUT t uuid, OUT wh uuid, OUT c uuid, OUT p uuid)
LANGUAGE plpgsql AS $$
BEGIN
  t := _mk_tenant(p_nom);
  PERFORM ensure_standard_journals(t);
  INSERT INTO warehouses (tenant_id, code, name) VALUES (t, 'W-' || p_nom, 'Dépôt') RETURNING id INTO wh;
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client ' || p_nom) RETURNING id INTO c;
  INSERT INTO products (tenant_id, name, sku, type, cost_price)
    VALUES (t, 'Article ' || p_nom, 'A-' || p_nom, 'stock', 5) RETURNING id INTO p;
  INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, movement_type, type, quantity, unit_cost, reference, movement_date, date)
    VALUES (t, p, wh, 'in', 'in', 1000, 5, 'APPRO', CURRENT_DATE, CURRENT_DATE);
END $$;

CREATE OR REPLACE FUNCTION _mk_bl230(p_t uuid, p_c uuid, p_p uuid, p_num text, p_qte numeric)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE bl uuid;
BEGIN
  INSERT INTO delivery_notes (tenant_id, number, customer_id, delivery_date, status)
  VALUES (p_t, p_num, p_c, CURRENT_DATE, 'pending') RETURNING id INTO bl;
  INSERT INTO delivery_note_lines (tenant_id, delivery_note_id, product_id, description, quantity)
  VALUES (p_t, bl, p_p, 'Article livré', p_qte);
  RETURN bl;
END $$;

-- T01 : expédier sort le stock une fois, et la sortie pointe sur le BL
DO $$
DECLARE v record; bl uuid; n int; q numeric; n_lie int;
BEGIN
  v := _mk_vente230('T01');
  bl := _mk_bl230(v.t, v.c, v.p, 'BL-T01', 10);
  PERFORM _as_user();
  UPDATE delivery_notes SET status = 'shipped' WHERE id = bl;
  PERFORM set_config('role', 'postgres', true);

  SELECT count(*), COALESCE(sum(quantity), 0) INTO n, q
  FROM stock_movements WHERE tenant_id = v.t AND reference_type = 'delivery_note';
  SELECT count(*) INTO n_lie
  FROM stock_movements WHERE tenant_id = v.t AND reference_type = 'delivery_note' AND reference_id = bl;

  PERFORM _rec('T01', 'expédier un BL de 10 : une sortie de 10, rattachée au BL',
    n = 1 AND q = 10 AND n_lie = 1,
    format('sorties=%s (1 attendue) quantité=%s (10 attendue) rattachées au BL=%s (1 attendue)', n, q, n_lie));
END $$;

-- T02 : expédié → livré ne re-décrémente pas (non-régression STK-01)
DO $$
DECLARE v record; bl uuid; n int; q numeric;
BEGIN
  v := _mk_vente230('T02');
  bl := _mk_bl230(v.t, v.c, v.p, 'BL-T02', 10);
  PERFORM _as_user();
  UPDATE delivery_notes SET status = 'shipped' WHERE id = bl;
  UPDATE delivery_notes SET status = 'delivered' WHERE id = bl;
  PERFORM set_config('role', 'postgres', true);

  SELECT count(*), COALESCE(sum(quantity), 0) INTO n, q
  FROM stock_movements WHERE tenant_id = v.t AND reference_type = 'delivery_note';
  PERFORM _rec('T02', 'expédié puis livré : toujours une seule sortie de 10',
    n = 1 AND q = 10, format('sorties=%s (1 attendue) quantité=%s (10 attendue)', n, q));
END $$;

-- T03 : expédié → annulé → expédié. Chemin permis par la contrainte CHECK.
DO $$
DECLARE v record; bl uuid; n int; q numeric; refuse boolean := false; err text := '—';
BEGIN
  v := _mk_vente230('T03');
  bl := _mk_bl230(v.t, v.c, v.p, 'BL-T03', 10);
  PERFORM _as_user();
  UPDATE delivery_notes SET status = 'shipped' WHERE id = bl;
  UPDATE delivery_notes SET status = 'cancelled' WHERE id = bl;
  BEGIN
    UPDATE delivery_notes SET status = 'shipped' WHERE id = bl;
  EXCEPTION WHEN OTHERS THEN refuse := true; err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);

  SELECT count(*), COALESCE(sum(quantity), 0) INTO n, q
  FROM stock_movements WHERE tenant_id = v.t AND reference_type = 'delivery_note';
  PERFORM _rec('T03', 'réexpédier un BL annulé : refus expliqué, pas un code d''index, et toujours 10 sortis',
    refuse AND n = 1 AND q = 10 AND err LIKE '%déjà expédié%',
    format('refus=%s sorties=%s quantité=%s | message=%s', refuse, n, q, left(err, 70)));
END $$;

-- T04 : réserver, libérer, re-réserver — la réservation ne dérive pas.
--       Une seule colonne subsiste (`stock_quantities.reserved_quantity`) ;
--       `quantity_reserved`, citée par l'audit, n'existe plus.
DO $$
DECLARE v record; so uuid; resv numeric; n_act int; n_col int;
BEGIN
  v := _mk_vente230('T04');
  INSERT INTO sales_orders (tenant_id, number, customer_id, order_date, status)
  VALUES (v.t, 'CV-T04', v.c, CURRENT_DATE, 'draft') RETURNING id INTO so;
  INSERT INTO sales_order_lines (tenant_id, sales_order_id, product_id, description, quantity, unit_price)
  VALUES (v.t, so, v.p, 'Article', 10, 100);
  PERFORM _as_user();
  UPDATE sales_orders SET status = 'confirmed' WHERE id = so;
  UPDATE sales_orders SET status = 'cancelled' WHERE id = so;
  UPDATE sales_orders SET status = 'confirmed' WHERE id = so;
  PERFORM set_config('role', 'postgres', true);

  SELECT COALESCE(sum(reserved_quantity), 0) INTO resv FROM stock_quantities WHERE tenant_id = v.t AND product_id = v.p;
  SELECT count(*) INTO n_act FROM stock_reservations WHERE tenant_id = v.t AND reference_id = so AND status = 'active';
  SELECT count(*) INTO n_col FROM information_schema.columns
    WHERE column_name IN ('reserved_quantity', 'quantity_reserved') AND table_schema = 'public';

  PERFORM _rec('T04', 'commande confirmée, annulée, reconfirmée : 10 réservés, pas 20 ; une seule colonne de réservation',
    resv = 10 AND n_act = 1 AND n_col = 1,
    format('réservé=%s (10 attendu) réservations actives=%s (1 attendue) colonnes de réservation=%s (1 attendue)',
           resv, n_act, n_col));
END $$;

-- T05 : la livraison de la commande libère la réservation
DO $$
DECLARE v record; so uuid; resv numeric; n_act int; n_ful int; err text := '—';
BEGIN
  v := _mk_vente230('T05');
  INSERT INTO sales_orders (tenant_id, number, customer_id, order_date, status)
  VALUES (v.t, 'CV-T05', v.c, CURRENT_DATE, 'draft') RETURNING id INTO so;
  INSERT INTO sales_order_lines (tenant_id, sales_order_id, product_id, description, quantity, unit_price)
  VALUES (v.t, so, v.p, 'Article', 10, 100);
  PERFORM _as_user();
  UPDATE sales_orders SET status = 'confirmed' WHERE id = so;
  BEGIN
    UPDATE sales_orders SET status = 'delivered' WHERE id = so;
  EXCEPTION WHEN OTHERS THEN err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);

  SELECT COALESCE(sum(reserved_quantity), 0) INTO resv FROM stock_quantities WHERE tenant_id = v.t AND product_id = v.p;
  SELECT count(*) FILTER (WHERE status = 'active'), count(*) FILTER (WHERE status = 'consumed')
    INTO n_act, n_ful FROM stock_reservations WHERE tenant_id = v.t AND reference_id = so;

  PERFORM _rec('T05', 'commande livrée : la réservation est consommée, rien ne reste réservé',
    resv = 0 AND n_act = 0 AND n_ful = 1,
    format('réservé=%s (0 attendu) actives=%s (0 attendue) consommées=%s (1 attendue) | %s',
           resv, n_act, n_ful, left(err, 70)));
END $$;

DROP FUNCTION _mk_bl230(uuid, uuid, uuid, text, numeric);
DROP FUNCTION _mk_vente230(text);
SELECT _audit_assert('230');
