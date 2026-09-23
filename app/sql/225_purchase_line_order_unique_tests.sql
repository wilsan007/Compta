-- ============================================================
-- 225_purchase_line_order_unique_tests.sql — ordre total des lignes (R-06)
--
-- G06e — deux lignes du même ordre : refusées par l'index unique.
--        Avant la 225 : acceptées, et la réception de 4 comptée 3 + 3 = 6.
-- G06f — la mise à jour qui efface l'ordre le voit réattribué.
--        Avant la 225 : line_order retombait à NULL (trigger BEFORE INSERT seul).
-- G06g — ordre total même à égalité : l'uuid départage, 3 + 1 et jamais 3 + 3.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '225', false);
DELETE FROM _audit_results WHERE file = '225';

-- Commande confirmée, sans ligne
CREATE OR REPLACE FUNCTION _mk_po225(t uuid, s uuid, p_num text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE po uuid;
BEGIN
  INSERT INTO purchase_orders (tenant_id, supplier_id, number, order_date, status)
  VALUES (t, s, p_num, '2026-03-01', 'confirmed') RETURNING id INTO po;
  RETURN po;
END $$;

-- G06e — deux lignes du même ordre : refusées
DO $$
DECLARE t uuid := _mk_tenant('G06E'); s uuid; p uuid; po uuid; refuse boolean := false; err text := '—'; n int;
BEGIN
  INSERT INTO suppliers (tenant_id, name) VALUES (t, 'Fournisseur G06e') RETURNING id INTO s;
  INSERT INTO products (tenant_id, name, sku, type) VALUES (t, 'Article', 'G06E-1', 'stock') RETURNING id INTO p;
  PERFORM _as_user();
  po := _mk_po225(t, s, 'PO-G06E');
  INSERT INTO purchase_order_lines (tenant_id, purchase_order_id, product_id, description, quantity, unit_price, line_order)
  VALUES (t, po, p, 'L1', 3, 10, 1);
  BEGIN
    INSERT INTO purchase_order_lines (tenant_id, purchase_order_id, product_id, description, quantity, unit_price, line_order)
    VALUES (t, po, p, 'L2', 3, 10, 1);
  EXCEPTION WHEN OTHERS THEN refuse := true; err := SQLERRM;
  END;
  SELECT count(*) INTO n FROM purchase_order_lines WHERE purchase_order_id = po;
  PERFORM _rec('G06e', 'deux lignes d''une même commande ne peuvent pas porter le même ordre',
    refuse AND n = 1, format('refus=%s lignes=%s | %s', refuse, n, left(err, 110)));
END $$;

-- G06f — la mise à jour qui efface l'ordre le voit réattribué
DO $$
DECLARE t uuid := _mk_tenant('G06F'); s uuid; p uuid; po uuid; l1 uuid; l2 uuid; o1 int; o2 int;
BEGIN
  INSERT INTO suppliers (tenant_id, name) VALUES (t, 'Fournisseur G06f') RETURNING id INTO s;
  INSERT INTO products (tenant_id, name, sku, type) VALUES (t, 'Article', 'G06F-1', 'stock') RETURNING id INTO p;
  PERFORM _as_user();
  po := _mk_po225(t, s, 'PO-G06F');
  INSERT INTO purchase_order_lines (tenant_id, purchase_order_id, product_id, description, quantity, unit_price)
  VALUES (t, po, p, 'L1', 3, 10) RETURNING id INTO l1;
  INSERT INTO purchase_order_lines (tenant_id, purchase_order_id, product_id, description, quantity, unit_price)
  VALUES (t, po, p, 'L2', 3, 10) RETURNING id INTO l2;
  UPDATE purchase_order_lines SET line_order = NULL WHERE id = l2;
  SELECT line_order INTO o1 FROM purchase_order_lines WHERE id = l1;
  SELECT line_order INTO o2 FROM purchase_order_lines WHERE id = l2;
  PERFORM _rec('G06f', 'mise à jour effaçant l''ordre : il est réattribué, jamais laissé vide',
    o1 = 1 AND o2 IS NOT NULL AND o2 <> o1,
    format('ligne 1=%s ligne 2=%s', o1, COALESCE(o2::text, 'NULL')));
END $$;

-- G06g — ordre total même à égalité : l'index est retiré le temps du scénario,
--        pour rejouer exactement ce qu'une base d'avant la 225 contenait
DO $$
DECLARE t uuid := _mk_tenant('G06G'); s uuid; p uuid; po uuid; l1 uuid; l2 uuid; gr uuid;
        q1 numeric; q2 numeric; v_index boolean;
BEGIN
  INSERT INTO suppliers (tenant_id, name) VALUES (t, 'Fournisseur G06g') RETURNING id INTO s;
  INSERT INTO products (tenant_id, name, sku, type) VALUES (t, 'Article', 'G06G-1', 'stock') RETURNING id INTO p;
  PERFORM _as_user();
  po := _mk_po225(t, s, 'PO-G06G');
  INSERT INTO purchase_order_lines (tenant_id, purchase_order_id, product_id, description, quantity, unit_price, line_order)
  VALUES (t, po, p, 'L1', 3, 10, 1) RETURNING id INTO l1;
  INSERT INTO purchase_order_lines (tenant_id, purchase_order_id, product_id, description, quantity, unit_price, line_order)
  VALUES (t, po, p, 'L2', 3, 10, 2) RETURNING id INTO l2;
  INSERT INTO goods_receipts (tenant_id, purchase_order_id, number, receipt_date, status)
  VALUES (t, po, 'GR-G06G', '2026-03-05', 'received') RETURNING id INTO gr;
  INSERT INTO goods_receipt_lines (tenant_id, goods_receipt_id, product_id, description, quantity_ordered, quantity_received)
  VALUES (t, gr, p, 'Article', 6, 4);

  SELECT EXISTS (SELECT 1 FROM pg_class WHERE relname = 'uq_purchase_order_lines_line_order') INTO v_index;
  PERFORM set_config('role', 'postgres', true);
  EXECUTE 'DROP INDEX IF EXISTS uq_purchase_order_lines_line_order';
  UPDATE purchase_order_lines SET line_order = 1 WHERE id = l2;

  SELECT quantity_received(pol) INTO q1 FROM purchase_order_lines pol WHERE id = l1;
  SELECT quantity_received(pol) INTO q2 FROM purchase_order_lines pol WHERE id = l2;

  UPDATE purchase_order_lines SET line_order = 2 WHERE id = l2;
  IF v_index THEN
    EXECUTE 'CREATE UNIQUE INDEX uq_purchase_order_lines_line_order '
         || 'ON purchase_order_lines (tenant_id, purchase_order_id, line_order) '
         || 'WHERE purchase_order_id IS NOT NULL AND line_order IS NOT NULL';
  END IF;

  PERFORM _rec('G06g', 'à ordre égal, la réception de 4 se répartit 3 + 1 : jamais comptée deux fois',
    q1 + q2 = 4, format('ligne 1=%s ligne 2=%s total=%s (4 reçus)', q1, q2, q1 + q2));
END $$;

DROP FUNCTION _mk_po225(uuid, uuid, text);
SELECT _audit_assert('225');
