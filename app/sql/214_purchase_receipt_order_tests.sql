-- ============================================================
-- 214_purchase_receipt_order_tests.sql — R-06 (phase 1 du reste-à-faire du 22/09)
--
-- `quantity_received` (195) solde les lignes d'une commande portant le même
-- article **dans l'ordre de leur `id`** (uuid tiré au hasard) : la ligne servie
-- en premier par une réception partielle était donc arbitraire, et les reliquats
-- par ligne pouvaient changer d'un tirage à l'autre. `purchase_order_lines`
-- n'a pas de colonne d'ordre : la 214 en ajoute une (`line_order`), remplie à
-- la création, et l'allocation la suit.
--
-- G06b — deux lignes du même article, dont l'ordre d'`id` est l'inverse de
--        l'ordre de saisie : la réception partielle sert la première ligne
--        saisie (line_order 1), pas celle dont l'uuid est le plus petit.
-- G06c — lignes créées sans ordre explicite : `line_order` est attribué dans
--        l'ordre d'insertion, et c'est lui qui décide (vérifié sur les données,
--        pas sur les uuid).
-- G06d — le plafond par ligne reste appliqué (une ligne ne reçoit jamais plus
--        que sa quantité commandée).
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '214', false);
DELETE FROM _audit_results WHERE file = '214';

CREATE OR REPLACE FUNCTION _mk_po214(t uuid, s uuid, p uuid)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE po uuid;
BEGIN
  INSERT INTO purchase_orders (tenant_id, number, supplier_id, status)
  VALUES (t, 'CF-214-' || left(t::text, 8), s, 'confirmed') RETURNING id INTO po;
  RETURN po;
END $$;

CREATE OR REPLACE FUNCTION _recv214(t uuid, s uuid, po uuid, p uuid, qty numeric)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE g uuid;
BEGIN
  INSERT INTO goods_receipts (tenant_id, number, supplier_id, purchase_order_id, status)
  VALUES (t, 'BR-214-' || left(gen_random_uuid()::text, 8), s, po, 'pending') RETURNING id INTO g;
  INSERT INTO goods_receipt_lines (tenant_id, goods_receipt_id, product_id, description, quantity_ordered, quantity_received)
  VALUES (t, g, p, 'Composant', qty, qty);
  UPDATE goods_receipts SET status = 'partial' WHERE id = g;
  RETURN g;
END $$;

CREATE OR REPLACE FUNCTION _recu214(l uuid)
RETURNS numeric LANGUAGE plpgsql AS $$
DECLARE v numeric;
BEGIN
  EXECUTE 'SELECT quantity_received(l) FROM purchase_order_lines l WHERE id = $1' INTO v USING l;
  RETURN COALESCE(v, -1);
END $$;

-- G06b — l'ordre de saisie (line_order) prime sur l'ordre des uuid
DO $$
DECLARE t uuid := _mk_tenant('G06B'); s uuid; p uuid; po uuid; a uuid; b uuid;
  l_id_petit uuid; l_id_grand uuid; r_petit numeric; r_grand numeric;
BEGIN
  INSERT INTO suppliers (tenant_id, name) VALUES (t, 'Fournisseur G06b') RETURNING id INTO s;
  INSERT INTO products (tenant_id, name, sku, type) VALUES (t, 'Composant', 'SKU-G06B-' || left(gen_random_uuid()::text, 8), 'stock') RETURNING id INTO p;
  PERFORM _as_user();
  BEGIN
    po := _mk_po214(t, s, p);
    -- deux lignes du même article ; l'uuid le plus petit va à la ligne saisie en SECOND,
    -- pour que l'allocation par uuid et l'allocation par line_order se contredisent
    a := gen_random_uuid(); b := gen_random_uuid();
    l_id_petit := LEAST(a, b); l_id_grand := GREATEST(a, b);

    INSERT INTO purchase_order_lines (id, tenant_id, purchase_order_id, product_id, description, quantity, unit_price, line_order)
    VALUES (l_id_petit, t, po, p, 'Saisie 2e', 10, 1, 2);
    INSERT INTO purchase_order_lines (id, tenant_id, purchase_order_id, product_id, description, quantity, unit_price, line_order)
    VALUES (l_id_grand, t, po, p, 'Saisie 1re', 5, 1, 1);

    PERFORM _recv214(t, s, po, p, 4::numeric);
    r_grand := _recu214(l_id_grand);   -- line_order 1 → doit être servie
    r_petit := _recu214(l_id_petit);   -- line_order 2 → ne doit rien recevoir
    PERFORM _rec('G06b', 'réception de 4 : la ligne saisie en premier (line_order 1) est servie, pas le plus petit uuid',
      r_grand = 4 AND r_petit = 0, format('line_order 1 : %s ; line_order 2 : %s', r_grand, r_petit));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('G06b', 'réception de 4 : la ligne saisie en premier (line_order 1) est servie, pas le plus petit uuid', false, SQLERRM);
  END;
END $$;

-- G06c — sans ordre explicite, line_order suit l'ordre d'insertion et décide de l'allocation
DO $$
DECLARE t uuid := _mk_tenant('G06C'); s uuid; p uuid; po uuid;
  l1 uuid; l2 uuid; o1 int; o2 int; r1 numeric; r2 numeric; servi uuid;
BEGIN
  INSERT INTO suppliers (tenant_id, name) VALUES (t, 'Fournisseur G06c') RETURNING id INTO s;
  INSERT INTO products (tenant_id, name, sku, type) VALUES (t, 'Composant', 'SKU-G06C', 'stock') RETURNING id INTO p;
  PERFORM _as_user();
  BEGIN
    po := _mk_po214(t, s, p);
    INSERT INTO purchase_order_lines (tenant_id, purchase_order_id, product_id, description, quantity, unit_price)
    VALUES (t, po, p, 'Première', 10, 1) RETURNING id INTO l1;
    INSERT INTO purchase_order_lines (tenant_id, purchase_order_id, product_id, description, quantity, unit_price)
    VALUES (t, po, p, 'Seconde', 5, 1) RETURNING id INTO l2;
    SELECT line_order INTO o1 FROM purchase_order_lines WHERE id = l1;
    SELECT line_order INTO o2 FROM purchase_order_lines WHERE id = l2;

    PERFORM _recv214(t, s, po, p, 3);
    r1 := _recu214(l1); r2 := _recu214(l2);
    servi := CASE WHEN r1 > 0 THEN l1 WHEN r2 > 0 THEN l2 END;

    PERFORM _rec('G06c', 'sans ordre explicite : line_order attribué dans l''ordre d''insertion et c''est lui qui décide',
      o1 = 1 AND o2 = 2 AND servi = l1 AND r1 = 3 AND r2 = 0,
      format('ordres=%s/%s ; reçus=%s/%s ; servie=%s', o1, o2, r1, r2, servi));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('G06c', 'sans ordre explicite : line_order attribué dans l''ordre d''insertion et c''est lui qui décide', false, SQLERRM);
  END;
END $$;

-- G06d — le plafond par ligne reste appliqué : jamais plus que la quantité commandée
DO $$
DECLARE t uuid := _mk_tenant('G06D'); s uuid; p uuid; po uuid; l1 uuid; l2 uuid; r1 numeric; r2 numeric; tot numeric;
BEGIN
  INSERT INTO suppliers (tenant_id, name) VALUES (t, 'Fournisseur G06d') RETURNING id INTO s;
  INSERT INTO products (tenant_id, name, sku, type) VALUES (t, 'Composant', 'SKU-G06D', 'stock') RETURNING id INTO p;
  PERFORM _as_user();
  BEGIN
    po := _mk_po214(t, s, p);
    INSERT INTO purchase_order_lines (tenant_id, purchase_order_id, product_id, description, quantity, unit_price, line_order)
    VALUES (t, po, p, 'Première', 3, 1, 1) RETURNING id INTO l1;
    INSERT INTO purchase_order_lines (tenant_id, purchase_order_id, product_id, description, quantity, unit_price, line_order)
    VALUES (t, po, p, 'Seconde', 3, 1, 2) RETURNING id INTO l2;

    PERFORM _recv214(t, s, po, p, 5);
    r1 := _recu214(l1); r2 := _recu214(l2);
    tot := r1 + r2;
    PERFORM _rec('G06d', 'réception de 5 sur deux lignes de 3 : plafonnée à 3 puis 2, jamais plus que commandé',
      r1 = 3 AND r2 = 2 AND tot = 5, format('première=%s seconde=%s total=%s', r1, r2, tot));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('G06d', 'réception de 5 sur deux lignes de 3 : plafonnée à 3 puis 2, jamais plus que commandé', false, SQLERRM);
  END;
END $$;

DROP FUNCTION _mk_po214(uuid, uuid, uuid);
DROP FUNCTION _recv214(uuid, uuid, uuid, uuid, numeric);
DROP FUNCTION _recu214(uuid);

SELECT _audit_assert('214');