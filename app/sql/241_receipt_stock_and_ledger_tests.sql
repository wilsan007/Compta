-- ============================================================
-- 241_receipt_stock_and_ledger_tests.sql — S-01, S-02, S-03, S-04, S-10, S-11
--
-- Audit des modules hors comptabilité (23/09), § Achats → stock et § Stock :
--
--   S-04  `goods_receipts` n'a PAS de colonne dépôt : la réception ne sait pas
--         où elle entre (défaut de structure, prouvé par le catalogue).
--   S-01  Le mouvement d'entrée créé par `create_stock_on_goods_receipt` ne
--         porte pas de dépôt : le stock par dépôt n'est jamais alimenté.
--   S-02  Il ne porte pas de coût : aucune couche de valorisation, donc un
--         stock valorisé à zéro.
--   S-03  Sans coût, `create_journal_on_stock_movement` sort par la première
--         porte (`IF v_unit_cost IS NULL THEN RETURN NEW`) : AUCUNE écriture.
--   S-10  Les comptes de stock et de variation sont codés en dur (310000 /
--         603000) dans l'écriture de mouvement ; `products.stock_account_code`
--         et les comptes de la famille d'articles sont ignorés, alors que
--         `resolve_stock_account` / `resolve_variation_account` existent
--         depuis la 125 et ne sont appelés nulle part.
--   S-11  `check_tracking_on_stock_movement` écrit un AVERTISSEMENT au lieu de
--         refuser : un article suivi en lot ou en numéro de série peut entrer
--         et sortir sans lot, la traçabilité est décorative.
--
-- Mesuré sur base neuve à la 234 (migrations antérieures seules), AVANT la 241 : T01 à T03 et T06 rouges
-- (stock de dépôt 0, aucune couche, aucune écriture, mouvement sans lot
-- accepté), T05 rouge (compte 310000/603000 au lieu des comptes résolus).
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '241', false);
DELETE FROM _audit_results WHERE file = '241';

-- Société, dépôt, fournisseur, article (coût de revient 40, prix d'achat 45),
-- commande de 10 à p_prix
CREATE OR REPLACE FUNCTION _mk_achat234(p_nom text, p_prix numeric,
  OUT t uuid, OUT wh uuid, OUT p uuid, OUT sup uuid, OUT po uuid)
LANGUAGE plpgsql AS $$
BEGIN
  t := _mk_tenant(p_nom);
  PERFORM ensure_standard_journals(t);
  INSERT INTO warehouses (tenant_id, code, name) VALUES (t, 'W-' || p_nom, 'Dépôt ' || p_nom)
    RETURNING id INTO wh;
  INSERT INTO suppliers (tenant_id, name) VALUES (t, 'Fournisseur ' || p_nom) RETURNING id INTO sup;
  INSERT INTO products (tenant_id, name, sku, type, cost_price, purchase_price)
    VALUES (t, 'Article ' || p_nom, 'A-' || p_nom, 'stock', 40, 45) RETURNING id INTO p;
  INSERT INTO purchase_orders (tenant_id, number, supplier_id, order_date, status)
    VALUES (t, 'CA-' || p_nom, sup, CURRENT_DATE, 'confirmed') RETURNING id INTO po;
  INSERT INTO purchase_order_lines (tenant_id, purchase_order_id, product_id, description, quantity, unit_price)
    VALUES (t, po, p, 'Article ' || p_nom, 10, p_prix);
END $$;

-- Réception de 10 (dépôt facultatif : la colonne n'existe pas avant la 241, on
-- passe donc par du SQL dynamique pour que le scénario ROUGE soit enregistré
-- au lieu de faire échouer le fichier entier).
CREATE OR REPLACE FUNCTION _reception234(p_t uuid, p_sup uuid, p_po uuid, p_p uuid, p_wh uuid,
  p_num text, p_qte numeric, p_lot uuid DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE gr uuid;
BEGIN
  EXECUTE 'INSERT INTO goods_receipts (tenant_id, number, supplier_id, purchase_order_id, warehouse_id, receipt_date, status)
           VALUES ($1, $2, $3, $4, $5, CURRENT_DATE, $6) RETURNING id'
    USING p_t, 'BR-' || p_num, p_sup, p_po, p_wh, 'pending' INTO gr;
  INSERT INTO goods_receipt_lines (tenant_id, goods_receipt_id, product_id, description,
    quantity_ordered, quantity_received, lot_id)
  VALUES (p_t, gr, p_p, 'Article reçu', p_qte, p_qte, p_lot);
  UPDATE goods_receipts SET status = 'received' WHERE id = gr;
  RETURN gr;
END $$;

-- T01 — S-04 + S-01 : la réception nomme son dépôt, et l'entrée s'y impute
DO $$
DECLARE v record; qa numeric; whq numeric; ok boolean := false; err text := '—';
BEGIN
  v := _mk_achat234('T01', 7);
  BEGIN PERFORM _reception234(v.t, v.sup, v.po, v.p, v.wh, 'T01', 10); ok := true;
  EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM set_config('role', 'postgres', true);
  SELECT stock_quantity INTO qa FROM products WHERE id = v.p;
  SELECT quantity INTO whq FROM stock_quantities WHERE product_id = v.p AND warehouse_id = v.wh;
  PERFORM _rec('T01', 'réception de 10 dans son dépôt : 10 dans le dépôt ET 10 sur l''article',
    ok AND qa = 10 AND whq = 10,
    format('réception=%s article=%s (10 attendu) dépôt=%s (10 attendu) | %s', ok, qa, whq, left(err, 70)));
END $$;

-- T02 — S-02 : la couche de valorisation est créée au prix d'achat
DO $$
DECLARE v record; n int; rest numeric; val numeric; uc numeric; err text := '—';
BEGIN
  v := _mk_achat234('T02', 7);
  BEGIN PERFORM _reception234(v.t, v.sup, v.po, v.p, v.wh, 'T02', 10);
  EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*), COALESCE(sum(remaining_qty), 0), COALESCE(sum(value), 0), COALESCE(max(unit_cost), 0)
    INTO n, rest, val, uc FROM stock_valuation_layers WHERE product_id = v.p;
  PERFORM _rec('T02', '10 reçus à 7 : une couche de 10 restants, valorisée 70',
    n = 1 AND rest = 10 AND val = 70 AND uc = 7,
    format('couches=%s restants=%s valeur=%s coût=%s | %s', n, rest, val, uc, left(err, 70)));
END $$;

-- T03 — S-03 : la réception produit son écriture, équilibrée, dans le journal des stocks
DO $$
DECLARE v record; n int; d numeric; c numeric; st text; err text := '—';
BEGIN
  v := _mk_achat234('T03', 7);
  BEGIN PERFORM _reception234(v.t, v.sup, v.po, v.p, v.wh, 'T03', 10);
  EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM set_config('role', 'postgres', true);
  SELECT count(DISTINCT je.id),
         COALESCE(sum(jl.debit) FILTER (WHERE jl.account_code = '310000'), 0),
         COALESCE(sum(jl.credit) FILTER (WHERE jl.account_code = '603000'), 0),
         min(je.status)
    INTO n, d, c, st
  FROM journal_entries je JOIN journal_lines jl ON jl.journal_id = je.id
  WHERE je.tenant_id = v.t AND je.journal_code = 'ST';
  PERFORM _rec('T03', 'réception de 70 : une écriture ST comptabilisée, D 310000 70 = C 603000 70',
    n = 1 AND d = 70 AND c = 70 AND st = 'posted',
    format('écritures=%s D310000=%s C603000=%s statut=%s | %s', n, d, c, st, left(err, 70)));
END $$;

-- T04 — S-04 : sans dépôt nommé, la réception se rabat sur le dépôt de la société
DO $$
DECLARE v record; qa numeric; whq numeric; err text := '—';
BEGIN
  v := _mk_achat234('T04', 7);
  BEGIN PERFORM _reception234(v.t, v.sup, v.po, v.p, NULL, 'T04', 10);
  EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM set_config('role', 'postgres', true);
  SELECT stock_quantity INTO qa FROM products WHERE id = v.p;
  SELECT COALESCE(sum(quantity), 0) INTO whq FROM stock_quantities WHERE product_id = v.p AND warehouse_id = v.wh;
  PERFORM _rec('T04', 'réception sans dépôt nommé : repli sur le dépôt de la société, 10 en dépôt',
    qa = 10 AND whq = 10,
    format('article=%s (10 attendu) dépôt=%s (10 attendu) | %s', qa, whq, left(err, 70)));
END $$;

-- T05 — S-10 : les comptes viennent de l'article et de sa famille d'articles.
--       Les codes 603200 / 603100 sont choisis parce qu'ils existent au plan
--       standard ET sont distincts des valeurs codées en dur : l'assertion
--       porte sur la résolution, pas sur la nature des comptes.
DO $$
DECLARE v record; cat uuid; rs text; rv text; d numeric; c numeric; err text := '—';
BEGIN
  v := _mk_achat234('T05', 7);
  INSERT INTO product_categories (tenant_id, name, variation_account_code)
    VALUES (v.t, 'Famille T05', '603100') RETURNING id INTO cat;
  UPDATE products SET category_id = cat, stock_account_code = '603200' WHERE id = v.p;
  rs := resolve_stock_account(v.p);
  rv := resolve_variation_account(v.p);
  BEGIN PERFORM _reception234(v.t, v.sup, v.po, v.p, v.wh, 'T05', 10);
  EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM set_config('role', 'postgres', true);
  SELECT COALESCE(sum(jl.debit) FILTER (WHERE jl.account_code = '603200'), 0),
         COALESCE(sum(jl.credit) FILTER (WHERE jl.account_code = '603100'), 0)
    INTO d, c
  FROM journal_entries je JOIN journal_lines jl ON jl.journal_id = je.id
  WHERE je.tenant_id = v.t AND je.journal_code = 'ST';
  PERFORM _rec('T05', 'comptes de stock (603200) et de variation (603100) résolus depuis l''article et sa famille',
    rs = '603200' AND rv = '603100' AND d = 70 AND c = 70,
    format('resolve_stock=%s resolve_variation=%s | D603200=%s C603100=%s | %s', rs, rv, d, c, left(err, 70)));
END $$;

-- T06 — S-11 : un mouvement d'article suivi sans lot est refusé
DO $$
DECLARE v record; ok boolean := false; err text := '—'; n int;
BEGIN
  v := _mk_achat234('T06', 7);
  UPDATE products SET tracking = 'lot' WHERE id = v.p;
  BEGIN
    INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, movement_type, type,
      quantity, unit_cost, reference, movement_date, date)
    VALUES (v.t, v.p, v.wh, 'in', 'in', 5, 7, 'SANS-LOT', CURRENT_DATE, CURRENT_DATE);
  EXCEPTION WHEN OTHERS THEN ok := true; err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);
  SELECT COALESCE(stock_quantity, 0) INTO n FROM products WHERE id = v.p;
  PERFORM _rec('T06', 'article suivi en lot, entrée sans lot : refusée, rien n''entre en stock',
    ok AND n = 0 AND err LIKE '%lot%',
    format('refusée=%s article=%s (0 attendu) | %s', ok, n, left(err, 90)));
END $$;

-- T07 — S-11 : le lot de la ligne de réception suit le mouvement
DO $$
DECLARE v record; lot uuid := gen_random_uuid(); mv record; err text := '—';
BEGIN
  v := _mk_achat234('T07', 7);
  UPDATE products SET tracking = 'lot' WHERE id = v.p;
  BEGIN PERFORM _reception234(v.t, v.sup, v.po, v.p, v.wh, 'T07', 10, lot);
  EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM set_config('role', 'postgres', true);
  SELECT lot_id, quantity INTO mv FROM stock_movements WHERE product_id = v.p AND reference_type = 'goods_receipt';
  PERFORM _rec('T07', 'réception d''un article suivi, lot renseigné sur la ligne : le mouvement porte le lot',
    mv.lot_id = lot AND mv.quantity = 10,
    format('lot du mouvement=%s (attendu %s) quantité=%s | %s',
           COALESCE(mv.lot_id::text, 'NULL'), lot, mv.quantity, left(err, 70)));
END $$;

DROP FUNCTION _reception234(uuid, uuid, uuid, uuid, uuid, text, numeric, uuid);
DROP FUNCTION _mk_achat234(text, numeric);
SELECT _audit_assert('241');
