-- ============================================================
-- 314_delivery_stock_out_on_ship_or_deliver_tests.sql — B1 (ven-004, ven-005)
--
-- Recette /qa du 29/09/2026, écran Ventes → Bons de livraison :
--
--   ven-005 (critique) BL « En attente » → « Livré » : le statut était accepté
--           sans aucune sortie de stock. Le déclencheur n'écoutait que le
--           passage à « Expédié », donc sauter l'étape contournait le contrôle
--           de disponibilité et laissait la marchandise partir sans mouvement
--           (mesuré : 2 × Bien A, stock 50 → 50, aucune écriture).
--   ven-004 (haut)     BL avec un article ET un service → « Expédié » refusé :
--           « Stock insuffisant: disponible=0, demandé=1 ». La quantité du
--           SERVICE (stock 0, par nature) était contrôlée comme une sortie.
--
-- Mesuré sur base neuve à la 313, AVANT la 314 :
--   T01 ❌ « Livré » ne sort rien
--   T02 ❌ le service bloque l'expédition
--   T03 ✅ expédié puis livré : une seule sortie (non-régression 230)
--   T04 ✅ réexpédition refusée avec un message (non-régression 230)
--   T05a ✅ la base ne marque pas la commande livrée à la création du BL
--   T05b ❌ livrer le BL ne marque pas la commande livrée
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '314', false);
DELETE FROM _audit_results WHERE file = '314';

CREATE OR REPLACE FUNCTION _mk_vente314(p_nom text,
  OUT t uuid, OUT wh uuid, OUT c uuid, OUT p_stock uuid, OUT p_service uuid)
LANGUAGE plpgsql AS $$
BEGIN
  t := _mk_tenant(p_nom);
  PERFORM ensure_standard_journals(t);
  INSERT INTO warehouses (tenant_id, code, name) VALUES (t, 'W-' || p_nom, 'Dépôt') RETURNING id INTO wh;
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client ' || p_nom) RETURNING id INTO c;
  INSERT INTO products (tenant_id, name, sku, type, cost_price)
    VALUES (t, 'Article ' || p_nom, 'A-' || p_nom, 'stock', 5) RETURNING id INTO p_stock;
  INSERT INTO products (tenant_id, name, sku, type, cost_price)
    VALUES (t, 'Prestation ' || p_nom, 'S-' || p_nom, 'service', 0) RETURNING id INTO p_service;
  INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, movement_type, type, quantity, unit_cost, reference, movement_date, date)
    VALUES (t, p_stock, wh, 'in', 'in', 1000, 5, 'APPRO', CURRENT_DATE, CURRENT_DATE);
END $$;

-- Lignes : [{"produit": uuid|null, "description": text, "qte": nombre, "sol": uuid|null}]
CREATE OR REPLACE FUNCTION _mk_bl314(p_t uuid, p_c uuid, p_num text, p_lignes jsonb, p_so uuid DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE bl uuid; l jsonb;
BEGIN
  INSERT INTO delivery_notes (tenant_id, number, customer_id, sales_order_id, delivery_date, status)
  VALUES (p_t, p_num, p_c, p_so, CURRENT_DATE, 'pending') RETURNING id INTO bl;
  FOR l IN SELECT * FROM jsonb_array_elements(p_lignes) LOOP
    INSERT INTO delivery_note_lines (tenant_id, delivery_note_id, product_id, description, quantity, sales_order_line_id)
    VALUES (p_t, bl, NULLIF(l->>'produit', '')::uuid, l->>'description', (l->>'qte')::numeric, NULLIF(l->>'sol', '')::uuid);
  END LOOP;
  RETURN bl;
END $$;

-- T01 (ven-005) : « En attente » → « Livré » sort le stock, une fois.
DO $$
DECLARE v record; bl uuid; n int; q numeric; stock numeric;
BEGIN
  v := _mk_vente314('T01');
  bl := _mk_bl314(v.t, v.c, 'BL-B1-T01',
    jsonb_build_array(jsonb_build_object('produit', v.p_stock, 'description', 'Article livré', 'qte', 2)));
  PERFORM _as_user();
  UPDATE delivery_notes SET status = 'delivered' WHERE id = bl;
  PERFORM set_config('role', 'postgres', true);

  SELECT count(*), COALESCE(sum(quantity), 0) INTO n, q
  FROM stock_movements WHERE tenant_id = v.t AND reference_type = 'delivery_note' AND reference_id = bl;
  SELECT stock_quantity INTO stock FROM products WHERE id = v.p_stock;

  PERFORM _rec('T01', '« En attente » → « Livré » : une sortie de 2, stock 1000 → 998',
    n = 1 AND q = 2 AND stock = 998,
    format('sorties=%s (1 attendue) quantité=%s (2 attendue) stock=%s (998 attendu)', n, q, stock));
END $$;

-- T02 (ven-004) : un article et un service — l'article sort, le service ne
-- bloque rien et ne produit aucun mouvement.
DO $$
DECLARE v record; bl uuid; n_stock int; n_service int; refuse boolean := false; err text := '—';
BEGIN
  v := _mk_vente314('T02');
  bl := _mk_bl314(v.t, v.c, 'BL-B1-T02',
    jsonb_build_array(
      jsonb_build_object('produit', v.p_stock, 'description', 'Article livré', 'qte', 2),
      jsonb_build_object('produit', v.p_service, 'description', 'Prestation', 'qte', 1)));
  PERFORM _as_user();
  BEGIN
    UPDATE delivery_notes SET status = 'shipped' WHERE id = bl;
  EXCEPTION WHEN OTHERS THEN refuse := true; err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);

  SELECT count(*) FILTER (WHERE product_id = v.p_stock),
         count(*) FILTER (WHERE product_id = v.p_service)
    INTO n_stock, n_service
  FROM stock_movements WHERE tenant_id = v.t AND reference_type = 'delivery_note' AND reference_id = bl;

  PERFORM _rec('T02', 'BL article + service : l''article sort, le service ne bloque pas et ne sort rien',
    NOT refuse AND n_stock = 1 AND n_service = 0,
    format('refus=%s (%s) sorties article=%s (1 attendue) sorties service=%s (0 attendue)',
           refuse, left(err, 60), n_stock, n_service));
END $$;

-- T03 (non-régression 230/STK-01) : expédié puis livré ne sort qu'une fois.
DO $$
DECLARE v record; bl uuid; n int; q numeric;
BEGIN
  v := _mk_vente314('T03');
  bl := _mk_bl314(v.t, v.c, 'BL-B1-T03',
    jsonb_build_array(jsonb_build_object('produit', v.p_stock, 'description', 'Article livré', 'qte', 10)));
  PERFORM _as_user();
  UPDATE delivery_notes SET status = 'shipped' WHERE id = bl;
  UPDATE delivery_notes SET status = 'delivered' WHERE id = bl;
  PERFORM set_config('role', 'postgres', true);

  SELECT count(*), COALESCE(sum(quantity), 0) INTO n, q
  FROM stock_movements WHERE tenant_id = v.t AND reference_type = 'delivery_note' AND reference_id = bl;

  PERFORM _rec('T03', 'expédié puis livré : toujours une seule sortie de 10',
    n = 1 AND q = 10, format('sorties=%s (1 attendue) quantité=%s (10 attendue)', n, q));
END $$;

-- T04 (non-régression 230) : réexpédier un BL annulé est refusé, avec un message.
DO $$
DECLARE v record; bl uuid; n int; refuse boolean := false; err text := '—';
BEGIN
  v := _mk_vente314('T04');
  bl := _mk_bl314(v.t, v.c, 'BL-B1-T04',
    jsonb_build_array(jsonb_build_object('produit', v.p_stock, 'description', 'Article livré', 'qte', 10)));
  PERFORM _as_user();
  UPDATE delivery_notes SET status = 'shipped' WHERE id = bl;
  UPDATE delivery_notes SET status = 'cancelled' WHERE id = bl;
  BEGIN
    UPDATE delivery_notes SET status = 'shipped' WHERE id = bl;
  EXCEPTION WHEN OTHERS THEN refuse := true; err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);

  SELECT count(*) INTO n
  FROM stock_movements WHERE tenant_id = v.t AND reference_type = 'delivery_note' AND reference_id = bl;

  PERFORM _rec('T04', 'réexpédier un BL annulé : refus expliqué, un seul mouvement',
    refuse AND n = 1 AND err LIKE '%déjà expédié%',
    format('refus=%s sorties=%s (1 attendue) | message=%s', refuse, n, left(err, 70)));
END $$;

-- T05 (complément B1) : la commande ne se dit livrée qu'à la sortie réelle.
--      La création du BL (ce que fait le client) laisse la commande « en
--      attente » ; c'est l'expédition ou la livraison qui la déclare.
DO $$
DECLARE v record; so uuid; sol uuid; bl uuid; st text; ful boolean;
BEGIN
  v := _mk_vente314('T05');
  INSERT INTO sales_orders (tenant_id, number, customer_id, order_date, status)
  VALUES (v.t, 'CV-B1-T05', v.c, CURRENT_DATE, 'draft') RETURNING id INTO so;
  INSERT INTO sales_order_lines (tenant_id, sales_order_id, product_id, description, quantity, unit_price)
  VALUES (v.t, so, v.p_stock, 'Article', 2, 100) RETURNING id INTO sol;
  PERFORM _as_user();
  UPDATE sales_orders SET status = 'confirmed' WHERE id = so;
  PERFORM set_config('role', 'postgres', true);

  bl := _mk_bl314(v.t, v.c, 'BL-B1-T05',
    jsonb_build_array(jsonb_build_object('produit', v.p_stock, 'description', 'Article', 'qte', 2, 'sol', sol)), so);
  UPDATE sales_order_lines SET delivered_quantity = 2 WHERE id = sol;

  SELECT delivery_status, fully_delivered INTO st, ful FROM sales_orders WHERE id = so;
  PERFORM _rec('T05a', 'créer le BL ne déclare pas la commande livrée',
    st = 'pending' AND ful IS FALSE,
    format('delivery_status=%s (pending attendu) fully_delivered=%s (false attendu)', st, ful));

  PERFORM _as_user();
  UPDATE delivery_notes SET status = 'delivered' WHERE id = bl;
  PERFORM set_config('role', 'postgres', true);

  SELECT delivery_status, fully_delivered INTO st, ful FROM sales_orders WHERE id = so;
  PERFORM _rec('T05b', 'livrer le BL déclare la commande livrée',
    st = 'delivered' AND ful IS TRUE,
    format('delivery_status=%s (delivered attendu) fully_delivered=%s (true attendu)', st, ful));
END $$;

DROP FUNCTION _mk_bl314(uuid, uuid, text, jsonb, uuid);
DROP FUNCTION _mk_vente314(text);
SELECT _audit_assert('314');
