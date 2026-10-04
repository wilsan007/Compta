-- ============================================================
-- 280_stock_documents_with_lines_tests.sql — vague X4 (C8, M6, C9, C10, D-B)
-- (audit fonctionnel exécuté du 28/09/2026, partie 3)
--
-- MESURÉ AVANT (base neuve sans la 280) : T01–T10 ROUGES — le mouvement à
-- `type` seul était enregistré sans effet, la sortie de 5 000 acceptée, la
-- quantité posée sur la fiche, aucune fonction de commande/réception à lignes,
-- les totaux d'en-tête ceux saisis par l'écran, un lecteur écrivait les
-- réservations de stock.
--
--   T01 un mouvement à `type` seul (fiche article d'avant la 280) produit son
--       effet : movement_type aligné, stock +10
--   T02 une sortie de 5 000 sur 10 est refusée, le stock reste 10
--   T03 `type` et `movement_type` contradictoires : refusé
--   T04 un écran ne pose pas `products.stock_quantity` (création à 50, puis
--       modification) ; le moteur, lui, le met à jour
--   T05 D-B : un fantôme se rejoue (mouvement neuf, stock +) ou s'ignore ; un
--       inventaire fantôme ne se rejoue pas ; une décision ne se prend qu'une fois
--   T06 commande fournisseur : en-tête + lignes en un appel, totaux de la base
--       (240 + 48), montants saisis ignorés ; sans ligne : refusée
--   T07 réception depuis la commande : brouillon refusé ; confirmée → une ligne
--       au reste à recevoir ; « reçue » : +20 en stock ; plus rien à recevoir
--   T08 une commande reçue ne change plus ses lignes
--   T09 commande client : lignes, TVA et totaux calculés par la base
--   T10 un lecteur ne crée pas de commande et ne réécrit pas une réservation
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '280', false);
DELETE FROM _audit_results WHERE file = '280';

-- Société + dépôt + article (stock 10 @ 12 au dépôt, par le moteur) + fournisseur + client
CREATE OR REPLACE FUNCTION _mk280(p_nom text, OUT t uuid, OUT wh uuid, OUT prod uuid, OUT sup uuid, OUT cust uuid)
LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'RESET ROLE';
  t := _mk_tenant(p_nom);
  PERFORM ensure_standard_journals(t);
  INSERT INTO warehouses (tenant_id, code, name) VALUES (t, 'W-' || p_nom, 'Dépôt') RETURNING id INTO wh;
  INSERT INTO products (tenant_id, name, sku, type, sale_price, purchase_price, vat_rate)
    VALUES (t, 'Article ' || p_nom, 'SKU-' || p_nom, 'stock', 20, 12, 20) RETURNING id INTO prod;
  INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, movement_type, type, quantity, unit_cost, reference)
    VALUES (t, prod, wh, 'initial', 'initial', 10, 12, 'Stock initial');
  INSERT INTO suppliers (tenant_id, name) VALUES (t, 'Fournisseur ' || p_nom) RETURNING id INTO sup;
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client ' || p_nom) RETURNING id INTO cust;
END $$;

CREATE OR REPLACE FUNCTION _viewer280(p_t uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE u uuid := uuid_generate_v4();
BEGIN
  EXECUTE 'RESET ROLE';
  INSERT INTO auth.users (id, email) VALUES (u, 'lecteur-' || u || '@audit.test');
  INSERT INTO tenant_users (tenant_id, auth_id, email, name, role, status)
    VALUES (p_t, u, 'lecteur-' || u || '@audit.test', 'Lecteur', 'viewer', 'active');
  PERFORM set_config('request.jwt.claim.sub', u::text, false);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, false);
  PERFORM _as_user();
END $$;

-- T01 / T02 / T03
DO $$
DECLARE s record; q1 numeric; q2 numeric; mt text; e2 text; e3 text;
BEGIN
  s := _mk280('X4A');
  PERFORM _as_user();
  INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, type, quantity, unit_cost, reference)
    VALUES (s.t, s.prod, s.wh, 'in', 10, 12, 'E-type-seul');
  SELECT stock_quantity INTO q1 FROM products WHERE id = s.prod;
  SELECT movement_type INTO mt FROM stock_movements WHERE tenant_id = s.t AND reference = 'E-type-seul';
  BEGIN
    INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, type, quantity, reference)
      VALUES (s.t, s.prod, s.wh, 'out', 5000, 'S-trop');
  EXCEPTION WHEN OTHERS THEN e2 := SQLERRM;
  END;
  SELECT stock_quantity INTO q2 FROM products WHERE id = s.prod;
  BEGIN
    INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, type, movement_type, quantity, reference)
      VALUES (s.t, s.prod, s.wh, 'in', 'out', 1, 'Contradictoire');
  EXCEPTION WHEN OTHERS THEN e3 := SQLERRM;
  END;
  EXECUTE 'RESET ROLE';
  PERFORM _rec('T01', 'un mouvement à « type » seul produit son effet : movement_type aligné, stock 10 → 20',
    q1 = 20 AND mt = 'in', format('stock=%s movement_type=%s', q1, mt));
  PERFORM _rec('T02', 'une sortie de 5 000 sur 20 est refusée, le stock reste 20',
    e2 IS NOT NULL AND q2 = 20, format('refus=%s stock=%s', coalesce(e2, 'ACCEPTÉE'), q2));
  PERFORM _rec('T03', '« type » et « movement_type » contradictoires : refusé',
    e3 IS NOT NULL AND e3 ~* 'contradictoire', coalesce(e3, 'ACCEPTÉ'));
EXCEPTION WHEN OTHERS THEN
  -- Avant la 280, le mouvement à « type » seul faisait tomber la transaction
  -- (écriture ST sans ligne) : les trois verdicts sont rouges, nommés.
  EXECUTE 'RESET ROLE';
  PERFORM _rec('T01', 'un mouvement à « type » seul produit son effet : movement_type aligné, stock 10 → 20', false, SQLERRM);
  PERFORM _rec('T02', 'une sortie de 5 000 sur 20 est refusée, le stock reste 20', false, SQLERRM);
  PERFORM _rec('T03', '« type » et « movement_type » contradictoires : refusé', false, SQLERRM);
END $$;

-- T04 — la quantité en stock ne se saisit pas
DO $$
DECLARE s record; e_ins text; e_upd text; q numeric; q_moteur numeric;
BEGIN
  s := _mk280('X4B');
  PERFORM _as_user();
  BEGIN
    INSERT INTO products (tenant_id, name, sku, type, stock_quantity) VALUES (s.t, 'Posé à la main', 'MAIN', 'stock', 50);
  EXCEPTION WHEN OTHERS THEN e_ins := SQLERRM;
  END;
  BEGIN
    UPDATE products SET stock_quantity = 999 WHERE id = s.prod;
  EXCEPTION WHEN OTHERS THEN e_upd := SQLERRM;
  END;
  SELECT stock_quantity INTO q FROM products WHERE id = s.prod;
  INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, movement_type, quantity, unit_cost, reference)
    VALUES (s.t, s.prod, s.wh, 'in', 5, 12, 'E5');
  SELECT stock_quantity INTO q_moteur FROM products WHERE id = s.prod;
  EXECUTE 'RESET ROLE';
  PERFORM _rec('T04', 'un écran ne pose pas la quantité en stock (création à 50, modification à 999) ; le moteur la tient',
    e_ins IS NOT NULL AND e_upd IS NOT NULL AND q = 10 AND q_moteur = 15,
    format('création=%s | modification=%s | stock=%s puis %s', coalesce(e_ins, 'ACCEPTÉE'), coalesce(e_upd, 'ACCEPTÉE'), q, q_moteur));
END $$;

-- T05 — D-B : les fantômes se décident, un par un
DO $$
DECLARE s record; m_in uuid; m_adj uuid; ph_in uuid; ph_adj uuid; r jsonb; q0 numeric; q1 numeric;
  e_adj text; e_twice text; d_in text;
BEGIN
  s := _mk280('X4C');
  -- Fabriqué en propriétaire : un mouvement enregistré avant la 280, sans effet
  SET LOCAL session_replication_role = 'replica';
  INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, movement_type, type, quantity, unit_cost, reference)
    VALUES (s.t, s.prod, s.wh, 'in', 'in', 7, 12, 'Fantôme entrée') RETURNING id INTO m_in;
  INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, movement_type, type, quantity, reference)
    VALUES (s.t, s.prod, s.wh, 'adjustment', 'adjustment', 3, 'Fantôme inventaire') RETURNING id INTO m_adj;
  SET LOCAL session_replication_role = 'origin';
  INSERT INTO stock_movement_phantoms (tenant_id, movement_id, product_id, warehouse_id, type, quantity, unit_cost, reference)
    VALUES (s.t, m_in, s.prod, s.wh, 'in', 7, 12, 'Fantôme entrée') RETURNING id INTO ph_in;
  INSERT INTO stock_movement_phantoms (tenant_id, movement_id, product_id, warehouse_id, type, quantity, reference)
    VALUES (s.t, m_adj, s.prod, s.wh, 'adjustment', 3, 'Fantôme inventaire') RETURNING id INTO ph_adj;
  SELECT stock_quantity INTO q0 FROM products WHERE id = s.prod;
  PERFORM _as_user();
  r := resolve_stock_movement_phantom(ph_in, 'replayed');
  BEGIN
    PERFORM resolve_stock_movement_phantom(ph_adj, 'replayed');
  EXCEPTION WHEN OTHERS THEN e_adj := SQLERRM;
  END;
  PERFORM resolve_stock_movement_phantom(ph_adj, 'ignored');
  BEGIN
    PERFORM resolve_stock_movement_phantom(ph_in, 'ignored');
  EXCEPTION WHEN OTHERS THEN e_twice := SQLERRM;
  END;
  EXECUTE 'RESET ROLE';
  SELECT stock_quantity INTO q1 FROM products WHERE id = s.prod;
  SELECT decision INTO d_in FROM stock_movement_phantoms WHERE id = ph_in;
  PERFORM _rec('T05', 'D-B : le fantôme rejoué crée un mouvement neuf (+7), l''inventaire fantôme ne se rejoue pas, une décision ne se prend qu''une fois',
    q0 = 10 AND q1 = 17 AND (r->>'movement_id') IS NOT NULL AND d_in = 'replayed'
      AND e_adj ~* 'ne se rejoue pas' AND e_twice ~* 'déjà',
    format('stock %s → %s ; rejeu=%s ; inventaire=%s ; deuxième décision=%s', q0, q1, r, coalesce(e_adj, 'REJOUÉ'), coalesce(e_twice, 'ACCEPTÉE')));
EXCEPTION WHEN undefined_table OR undefined_function THEN
  EXECUTE 'RESET ROLE';
  PERFORM _rec('T05', 'D-B : le fantôme rejoué crée un mouvement neuf (+7), l''inventaire fantôme ne se rejoue pas, une décision ne se prend qu''une fois', false, SQLERRM);
END $$;

-- T06 / T07 / T08 — commande fournisseur et réception
DO $$
DECLARE s record; po purchase_orders; v record; e_vide text; e_brouillon text; gr goods_receipts;
  n_l int; q_l numeric; q0 numeric; q1 numeric; st_po text; e_encore text; e_lock text;
BEGIN
  s := _mk280('X4D');
  PERFORM _as_user();
  po := create_purchase_order(
    jsonb_build_object('number', 'CF-X4D', 'supplier_id', s.sup, 'order_date', '2026-09-01',
                       'subtotal', 999, 'vat', 999, 'total', 999),
    jsonb_build_array(jsonb_build_object('product_id', s.prod, 'description', 'Article', 'quantity', 20, 'unit_price', 12, 'vat_rate', 20)));
  SELECT subtotal, vat, total, (SELECT count(*) FROM purchase_order_lines WHERE purchase_order_id = po.id) n INTO v
  FROM purchase_orders WHERE id = po.id;
  BEGIN
    PERFORM create_purchase_order(jsonb_build_object('number', 'CF-VIDE', 'supplier_id', s.sup), '[]'::jsonb);
  EXCEPTION WHEN OTHERS THEN e_vide := SQLERRM;
  END;
  PERFORM _rec('T06', 'commande fournisseur : 1 ligne, totaux de la base 240 + 48 = 288 (999 saisis ignorés) ; sans ligne : refusée',
    v.n = 1 AND v.subtotal = 240 AND v.vat = 48 AND v.total = 288 AND e_vide ~* 'au moins une ligne',
    format('lignes=%s HT=%s TVA=%s TTC=%s ; vide=%s', v.n, v.subtotal, v.vat, v.total, coalesce(e_vide, 'ACCEPTÉE')));

  BEGIN
    PERFORM create_goods_receipt_from_order(po.id, 'BR-X4D-0', '2026-09-10', s.wh);
  EXCEPTION WHEN OTHERS THEN e_brouillon := SQLERRM;
  END;
  UPDATE purchase_orders SET status = 'confirmed' WHERE id = po.id;
  gr := create_goods_receipt_from_order(po.id, 'BR-X4D-1', '2026-09-10', s.wh);
  SELECT count(*), sum(quantity_received) INTO n_l, q_l FROM goods_receipt_lines WHERE goods_receipt_id = gr.id;
  SELECT stock_quantity INTO q0 FROM products WHERE id = s.prod;
  UPDATE goods_receipts SET status = 'received' WHERE id = gr.id;
  SELECT stock_quantity INTO q1 FROM products WHERE id = s.prod;
  SELECT status INTO st_po FROM purchase_orders WHERE id = po.id;
  BEGIN
    PERFORM create_goods_receipt_from_order(po.id, 'BR-X4D-2', '2026-09-11', s.wh);
  EXCEPTION WHEN OTHERS THEN e_encore := SQLERRM;
  END;
  BEGIN
    UPDATE purchase_order_lines SET quantity = 50 WHERE purchase_order_id = po.id;
  EXCEPTION WHEN OTHERS THEN e_lock := SQLERRM;
  END;
  EXECUTE 'RESET ROLE';
  PERFORM _rec('T07', 'réception depuis la commande : brouillon refusé ; confirmée → 1 ligne de 20 ; reçue : stock +20, commande reçue ; plus rien à recevoir',
    e_brouillon ~* 'confirmée' AND n_l = 1 AND q_l = 20 AND q1 = q0 + 20 AND st_po = 'received' AND e_encore ~* 'plus rien|reçue|received',
    format('brouillon=%s ; lignes=%s qté=%s ; stock %s → %s ; commande=%s ; encore=%s',
           coalesce(e_brouillon, 'ACCEPTÉ'), n_l, q_l, q0, q1, st_po, coalesce(e_encore, 'ACCEPTÉ')));
  PERFORM _rec('T08', 'une commande reçue ne change plus ses lignes',
    e_lock ~* 'ne se modifient plus', coalesce(e_lock, 'ACCEPTÉ'));
EXCEPTION WHEN undefined_function THEN
  EXECUTE 'RESET ROLE';
  PERFORM _rec('T06', 'commande fournisseur : 1 ligne, totaux de la base 240 + 48 = 288 (999 saisis ignorés) ; sans ligne : refusée', false, SQLERRM);
  PERFORM _rec('T07', 'réception depuis la commande : brouillon refusé ; confirmée → 1 ligne de 20 ; reçue : stock +20, commande reçue ; plus rien à recevoir', false, SQLERRM);
  PERFORM _rec('T08', 'une commande reçue ne change plus ses lignes', false, SQLERRM);
END $$;

-- T09 — commande client
DO $$
DECLARE s record; so sales_orders; v record;
BEGIN
  s := _mk280('X4E');
  PERFORM _as_user();
  so := create_sales_order(
    jsonb_build_object('number', 'CC-X4E', 'customer_id', s.cust, 'order_date', '2026-09-28', 'total', 1000),
    jsonb_build_array(
      jsonb_build_object('product_id', s.prod, 'description', '', 'quantity', 5, 'unit_price', 20, 'vat_rate', 20),
      jsonb_build_object('product_id', null, 'description', 'Port', 'quantity', 1, 'unit_price', 10, 'vat_rate', 5.5)));
  SELECT subtotal, vat, total, (SELECT count(*) FROM sales_order_lines WHERE sales_order_id = so.id) n,
         (SELECT description FROM sales_order_lines WHERE sales_order_id = so.id AND product_id IS NOT NULL) d INTO v
  FROM sales_orders WHERE id = so.id;
  EXECUTE 'RESET ROLE';
  PERFORM _rec('T09', 'commande client : 2 lignes, HT 110, TVA 20 + 0,55, TTC 130,55 ; libellé repris de l''article',
    v.n = 2 AND v.subtotal = 110 AND v.vat = 20.55 AND v.total = 130.55 AND v.d = 'Article X4E',
    format('lignes=%s HT=%s TVA=%s TTC=%s libellé=%s', v.n, v.subtotal, v.vat, v.total, v.d));
EXCEPTION WHEN undefined_function THEN
  EXECUTE 'RESET ROLE';
  PERFORM _rec('T09', 'commande client : 2 lignes, HT 110, TVA 20 + 0,55, TTC 130,55 ; libellé repris de l''article', false, SQLERRM);
END $$;

-- T10 — le lecteur
DO $$
DECLARE s record; e_po text; so uuid; n_upd int := -1;
BEGIN
  s := _mk280('X4F');
  INSERT INTO sales_orders (tenant_id, number, customer_id) VALUES (s.t, 'CC-X4F', s.cust) RETURNING id INTO so;
  INSERT INTO sales_order_lines (tenant_id, sales_order_id, product_id, description, quantity, unit_price)
    VALUES (s.t, so, s.prod, 'Article', 2, 20);
  UPDATE sales_orders SET status = 'confirmed' WHERE id = so;   -- pose la réservation
  PERFORM _viewer280(s.t);
  BEGIN
    PERFORM create_purchase_order(jsonb_build_object('number', 'CF-LEC', 'supplier_id', s.sup),
      jsonb_build_array(jsonb_build_object('product_id', s.prod, 'quantity', 1, 'unit_price', 1)));
  EXCEPTION WHEN OTHERS THEN e_po := SQLERRM;
  END;
  UPDATE stock_reservations SET quantity = 999 WHERE tenant_id = s.t;
  GET DIAGNOSTICS n_upd = ROW_COUNT;
  EXECUTE 'RESET ROLE';
  PERFORM _rec('T10', 'un lecteur ne crée pas de commande fournisseur et ne réécrit pas une réservation de stock',
    e_po IS NOT NULL AND n_upd = 0
      AND EXISTS (SELECT 1 FROM stock_reservations WHERE tenant_id = s.t)
      AND NOT EXISTS (SELECT 1 FROM stock_reservations WHERE tenant_id = s.t AND quantity = 999),
    format('commande=%s ; réservations réécrites=%s', coalesce(e_po, 'ACCEPTÉE'), n_upd));
EXCEPTION WHEN undefined_function THEN
  EXECUTE 'RESET ROLE';
  PERFORM _rec('T10', 'un lecteur ne crée pas de commande fournisseur et ne réécrit pas une réservation de stock', false, SQLERRM);
END $$;

DROP FUNCTION _mk280(text);
DROP FUNCTION _viewer280(uuid);
SELECT _audit_assert('280');
