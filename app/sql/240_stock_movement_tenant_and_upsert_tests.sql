-- ============================================================
-- 240_stock_movement_tenant_and_upsert_tests.sql — S-08, S-09
--
-- Audit des modules hors comptabilité (23/09), § S-08 et S-09 :
--
--   S-08  `increment_stock` / `decrement_stock` prennent la société dans
--         `current_tenant_id()` — celle de la SESSION — et non dans le mouvement
--         qui les déclenche. Les deux fonctions sont appelées par le
--         déclencheur `update_stock_on_movement`, donc depuis des chemins
--         SECURITY DEFINER qui écrivent pour une société que la session n'a pas
--         forcément activée : le stock de la société du mouvement reste
--         inchangé, ou l'insertion échoue.
--
--   S-09  `increment_stock` fait d'abord un UPDATE, puis, s'il ne trouve rien,
--         `INSERT … ON CONFLICT DO NOTHING`. Deux entrées concurrentes sur la
--         même ligne de dépôt : la seconde voit « rien trouvé » (le UPDATE a
--         porté sur zéro ligne), insère, tombe sur le conflit et perd sa
--         quantité SANS BRUIT. Le stock global, lui, est bien incrémenté — les
--         deux compteurs divergent.
--
-- Mesuré sur base neuve à la 234 (migrations antérieures seules), AVANT la 240 :
--   T01/T02 ROUGES — le mouvement de la société A n'atteint pas les stocks de A
--   T03 ROUGE      — le corps de `increment_stock` contient bien DO NOTHING
--   T04 ROUGE      — une sortie supérieure au stock du dépôt passait en
--                    silence (GREATEST(quantity - p_qty, 0)) : le dépôt tombait
--                    à 0 pendant que le total de l'article baissait d'autant.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '240', false);
DELETE FROM _audit_results WHERE file = '240';

-- Société A : un dépôt, un article à 5, 100 en stock (dépôt et article d'accord)
CREATE OR REPLACE FUNCTION _mk_stock233(p_nom text, OUT t uuid, OUT wh uuid, OUT p uuid)
LANGUAGE plpgsql AS $$
BEGIN
  t := _mk_tenant(p_nom);
  PERFORM ensure_standard_journals(t);
  INSERT INTO warehouses (tenant_id, code, name) VALUES (t, 'W-' || p_nom, 'Dépôt ' || p_nom)
    RETURNING id INTO wh;
  INSERT INTO products (tenant_id, name, sku, type, cost_price, purchase_price)
    VALUES (t, 'Article ' || p_nom, 'A-' || p_nom, 'stock', 5, 5) RETURNING id INTO p;
  INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, movement_type, type,
    quantity, unit_cost, reference, movement_date, date)
  VALUES (t, p, wh, 'in', 'in', 100, 5, 'APPRO-' || p_nom, CURRENT_DATE, CURRENT_DATE);
END $$;

-- Écrit le mouvement comme le fait un chemin SECURITY DEFINER : pour la société
-- passée en paramètre, quelle que soit la société active de l'appelant.
CREATE OR REPLACE FUNCTION _mv_233(p_t uuid, p_p uuid, p_wh uuid, p_type text, p_qty numeric, p_cost numeric)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, movement_type, type,
    quantity, unit_cost, reference, movement_date, date)
  VALUES (p_t, p_p, p_wh, p_type, p_type, p_qty, p_cost,
    'HORS-SOCIETE-' || p_type, CURRENT_DATE, CURRENT_DATE);
END $$;
-- T01 — S-08 : une entrée de la société A écrite pendant que B est active
DO $$
DECLARE v record; qa numeric; whq numeric; ok boolean := false; err text := '—';
BEGIN
  v := _mk_stock233('T01');
  PERFORM _mk_tenant('T01B');            -- le contexte bascule sur la société B
  BEGIN
    PERFORM _mv_233(v.t, v.p, v.wh, 'in', 10, 5);
    ok := true;
  EXCEPTION WHEN OTHERS THEN err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);
  SELECT stock_quantity INTO qa FROM products WHERE id = v.p;
  SELECT quantity INTO whq FROM stock_quantities WHERE product_id = v.p AND warehouse_id = v.wh;
  PERFORM _rec('T01', 'entrée de la société A reçue pendant que B est active : 110 en stock, dans le dépôt de A',
    ok AND qa = 110 AND whq = 110,
    format('acceptée=%s article=%s (110 attendu) dépôt=%s (110 attendu) | %s', ok, qa, whq, left(err, 60)));
END $$;

-- T02 — S-08 (sortie) : le même chemin, en sortie
DO $$
DECLARE v record; qa numeric; whq numeric; ok boolean := false; err text := '—';
BEGIN
  v := _mk_stock233('T02');
  PERFORM _mk_tenant('T02B');
  BEGIN
    PERFORM _mv_233(v.t, v.p, v.wh, 'out', 10, NULL);
    ok := true;
  EXCEPTION WHEN OTHERS THEN err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);
  SELECT stock_quantity INTO qa FROM products WHERE id = v.p;
  SELECT quantity INTO whq FROM stock_quantities WHERE product_id = v.p AND warehouse_id = v.wh;
  PERFORM _rec('T02', 'sortie de la société A reçue pendant que B est active : 90 en stock, dans le dépôt de A',
    ok AND qa = 90 AND whq = 90,
    format('acceptée=%s article=%s (90 attendu) dépôt=%s (90 attendu) | %s', ok, qa, whq, left(err, 60)));
END $$;

-- T03 — S-09 : plus de perte silencieuse à l'insertion concurrente
DO $$
DECLARE src text; wrappers text;
BEGIN
  SELECT prosrc INTO src FROM pg_proc WHERE proname = '_stock_increment' LIMIT 1;
  SELECT COALESCE(string_agg(proname, ', '), '∅') INTO wrappers
  FROM pg_proc WHERE proname IN ('increment_stock', '_stock_increment')
    AND prosrc LIKE '%ON CONFLICT DO NOTHING%';
  PERFORM _rec('T03', 'l''entrée de stock additionne la quantité en cas de conflit (ON CONFLICT DO UPDATE, plus de DO NOTHING)',
    src IS NOT NULL AND src LIKE '%ON CONFLICT%' AND src LIKE '%DO UPDATE%' AND wrappers = '∅',
    format('concurrent=%s | additionne=%s | DO NOTHING restant dans : %s',
      (src LIKE '%ON CONFLICT%')::text, (src LIKE '%DO UPDATE%')::text, wrappers));
END $$;

-- T04 — S-05 (même famille) : une sortie supérieure au stock DU DÉPÔT ; le total
--       de l'article, lui, suffit — c'est là que le dépôt était rogné en silence.
DO $$
DECLARE v record; wh2 uuid; qa numeric; q1 numeric; q2 numeric; ok boolean := false; err text := '—';
BEGIN
  v := _mk_stock233('T04');
  INSERT INTO warehouses (tenant_id, code, name) VALUES (v.t, 'W2', 'Dépôt 2') RETURNING id INTO wh2;
  INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, movement_type, type,
    quantity, unit_cost, reference, movement_date, date)
  VALUES (v.t, v.p, wh2, 'in', 'in', 100, 5, 'APPRO-T04B', CURRENT_DATE, CURRENT_DATE);
  BEGIN
    PERFORM _mv_233(v.t, v.p, v.wh, 'out', 150, NULL);
  EXCEPTION WHEN OTHERS THEN ok := true; err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);
  SELECT stock_quantity INTO qa FROM products WHERE id = v.p;
  SELECT quantity INTO q1 FROM stock_quantities WHERE product_id = v.p AND warehouse_id = v.wh;
  SELECT quantity INTO q2 FROM stock_quantities WHERE product_id = v.p AND warehouse_id = wh2;
  PERFORM _rec('T04', 'sortie de 150 sur un dépôt de 100 (article à 200) : refusée, le dépôt ne tombe pas à 0',
    ok AND qa = 200 AND q1 = 100 AND q2 = 100 AND err LIKE '%insuffisant%',
    format('refusée=%s article=%s (200 attendu) dépôt1=%s dépôt2=%s (100/100 attendus) | %s',
           ok, qa, q1, q2, left(err, 80)));
END $$;

DROP FUNCTION _mv_233(uuid, uuid, uuid, text, numeric, numeric);
DROP FUNCTION _mk_stock233(text);
SELECT _audit_assert('240');

