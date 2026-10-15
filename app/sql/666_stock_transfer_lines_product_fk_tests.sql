-- ============================================================
-- 666_stock_transfer_lines_product_fk_tests.sql — E.2 (partie E)
--
-- Mesuré AVANT la 666 : `stock_transfer_lines.product_id` n'avait aucune clé
-- étrangère — l'embed `products(name, sku)` de `/stock/transfers` répondait
-- PGRST200 (trouvé par `check-embeds`, étape que la CI n'atteignait pas).
-- T02 est la preuve de comportement : une ligne de transfert acceptait
-- l'article d'une autre société.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '666', false);
DELETE FROM _audit_results WHERE file = '666';

-- Une société, deux dépôts, un article, un transfert — de quoi poser une ligne.
CREATE OR REPLACE FUNCTION _mk666(p_nom text, OUT t uuid, OUT tr uuid, OUT p uuid)
LANGUAGE plpgsql AS $$
DECLARE w1 uuid; w2 uuid;
BEGIN
  t := _mk_tenant(p_nom, false);
  INSERT INTO warehouses (tenant_id, code, name) VALUES (t, 'W1-' || p_nom, 'Source ' || p_nom) RETURNING id INTO w1;
  INSERT INTO warehouses (tenant_id, code, name) VALUES (t, 'W2-' || p_nom, 'Dest ' || p_nom) RETURNING id INTO w2;
  INSERT INTO products (tenant_id, name, sku, type, cost_price)
  VALUES (t, 'Article ' || p_nom, 'SKU-' || p_nom, 'stock', 10) RETURNING id INTO p;
  INSERT INTO stock_transfers (tenant_id, transfer_number, from_warehouse_id, to_warehouse_id)
  VALUES (t, 'TR-' || p_nom, w1, w2) RETURNING id INTO tr;
END $$;

-- T01 — la clé étrangère de l'article est composite et existe
DO $$
DECLARE n int; mono int;
BEGIN
  SELECT count(*) INTO n
  FROM pg_constraint con
  WHERE con.conname = 'stock_transfer_lines_product_fk'
    AND con.contype = 'f'
    AND pg_get_constraintdef(con.oid) LIKE '%(tenant_id, product_id)%'
    AND pg_get_constraintdef(con.oid) LIKE '%products(tenant_id, id)%';

  SELECT count(*) INTO mono
  FROM pg_constraint con JOIN pg_class c ON c.oid = con.conrelid
  WHERE c.relname = 'stock_transfer_lines' AND con.contype = 'f'
    AND con.confrelid = 'public.products'::regclass
    AND array_length(con.conkey, 1) = 1;

  PERFORM _rec('T01', 'la ligne de transfert tient son article par une clé composite (tenant_id, product_id)',
    (n = 1 AND mono = 0), format('composite(s)=%s (1 attendu), mono-colonne(s)=%s (0 attendu)', n, mono));
END $$;

-- T02 — le comportement : l'article d'une autre société est refusé
DO $$
DECLARE tb uuid; trb uuid; pb uuid; ta uuid; tra uuid; pa uuid;
        v_state text; v_err text;
BEGIN
  SELECT * INTO tb, trb, pb FROM _mk666('VAL666B02');  -- société étrangère
  SELECT * INTO ta, tra, pa FROM _mk666('VAL666A02');  -- l'appelant est ici
  BEGIN
    INSERT INTO stock_transfer_lines (tenant_id, transfer_id, product_id, quantity)
    VALUES (ta, tra, pb, 5);   -- le transfert est celui de A, l'article celui de B
  EXCEPTION WHEN others THEN v_state := SQLSTATE; v_err := SQLERRM;
  END;
  PERFORM _rec('T02', 'une ligne de transfert ne peut pas porter l''article d''une autre société (23503)',
    v_state = '23503',
    format('SQLSTATE=%s ; %s', COALESCE(v_state, 'aucune erreur — la ligne a été acceptée'),
           left(COALESCE(v_err, ''), 80)));
END $$;

-- T03 — non-régression : l'article de sa propre société passe
DO $$
DECLARE t uuid; tr uuid; p uuid; n int;
BEGIN
  SELECT * INTO t, tr, p FROM _mk666('VAL666T03');
  INSERT INTO stock_transfer_lines (tenant_id, transfer_id, product_id, quantity) VALUES (t, tr, p, 30);
  SELECT count(*) INTO n FROM stock_transfer_lines WHERE tenant_id = t AND transfer_id = tr AND product_id = p;
  PERFORM _rec('T03', 'une ligne de transfert porte normalement l''article de sa société',
    n = 1, format('%s ligne(s) (1 attendue)', n));
END $$;

SELECT _audit_assert('666');
