-- ═══════════════════════════════════════════════════════════════════════════
-- 765_chain_l16_cump_ecriture_tests.sql — P10 : CUMP ↔ écriture comptable
-- ═══════════════════════════════════════════════════════════════════════════
-- Ce que cette suite ÉPROUVE :
--   T01  LE BUG FIX : `distribute_landed_cost` trouve les mouvements
--        `goods_receipt` (avant 765, le filtre `'receipt'` ne trouvait rien) ;
--   T02  LE MAILLON : un lien `landed_costs → stock_movements` est créé avec
--        l'effet `stock.landed_cost.distributed` ;
--   T03  LA GARDE : une `landed_costs` reliée ne se supprime pas
--        (CHAIN_DELETE_REFUSED) ;
--   T04  NON-RÉGRESSION : une `landed_costs` SANS lien se supprime ;
--   T05  COUVERTURE : `landed_costs` porte sa garde de suppression ;
--   T06  LA CUMP : le coût unitaire de `stock_quantités` est ajusté après
--        répartition des frais accessoires.
-- ═══════════════════════════════════════════════════════════════════════════
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '765', false);
DELETE FROM _audit_results WHERE file = '765';

-- ─────────────────────────────────────────────────────────────────────────────
-- Harnais : société + dépôt + fournisseur + article + commande + réception
-- (même scénario que la 241, simplifié pour la CUMP)
-- ─────────────────────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS _mk_cump_env(text, numeric);
CREATE OR REPLACE FUNCTION _mk_cump_env(p_nom text, p_prix numeric,
  OUT t uuid, OUT wh uuid, OUT p uuid, OUT sup uuid, OUT po uuid, OUT gr uuid)
LANGUAGE plpgsql AS $$
BEGIN
  t := _mk_tenant(p_nom);
  PERFORM ensure_standard_journals(t);
  INSERT INTO warehouses (tenant_id, code, name)
    VALUES (t, 'W-' || p_nom, 'Dépôt ' || p_nom) RETURNING id INTO wh;
  INSERT INTO suppliers (tenant_id, name)
    VALUES (t, 'Fournisseur ' || p_nom) RETURNING id INTO sup;
  INSERT INTO products (tenant_id, name, sku, type, cost_price, purchase_price)
    VALUES (t, 'Article ' || p_nom, 'A-' || p_nom, 'stock', 40, p_prix)
    RETURNING id INTO p;
  INSERT INTO purchase_orders (tenant_id, number, supplier_id, order_date, status)
    VALUES (t, 'CA-' || p_nom, sup, CURRENT_DATE, 'confirmed')
    RETURNING id INTO po;
  INSERT INTO purchase_order_lines (tenant_id, purchase_order_id, product_id,
    description, quantity, unit_price)
    VALUES (t, po, p, 'Article ' || p_nom, 10, p_prix);
  -- La réception → le déclencheur 241 crée les mouvements (reference_type = 'goods_receipt')
  INSERT INTO goods_receipts (tenant_id, number, supplier_id, purchase_order_id,
    warehouse_id, receipt_date, status)
    VALUES (t, 'BR-' || p_nom, sup, po, wh, CURRENT_DATE, 'pending')
    RETURNING id INTO gr;
  INSERT INTO goods_receipt_lines (tenant_id, goods_receipt_id, product_id,
    description, quantity_ordered, quantity_received)
    VALUES (t, gr, p, 'Article reçu', 10, 10);
  UPDATE goods_receipts SET status = 'received' WHERE id = gr;
END $$;

-- ── T01 — LE BUG FIX : distribute_landed_cost trouve les goods_receipts ───
DO $$
DECLARE v record; lc_id uuid; result jsonb; n int; err text := '—';
BEGIN
  v := _mk_cump_env('T01', 50);
  PERFORM set_config('app.current_tenant', v.t::text, false);
  INSERT INTO landed_costs (tenant_id, supplier_id, total_amount, distribution_method)
    VALUES (v.t, v.sup, 100, 'value') RETURNING id INTO lc_id;
  BEGIN
    result := distribute_landed_cost(lc_id);
  EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  SELECT count(*) INTO n FROM landed_cost_lines WHERE landed_cost_id = lc_id;
  PERFORM _rec('T01', 'distribute_landed_cost trouve les mouvements goods_receipt (bug fix)',
    result->>'success' = 'true' AND n > 0,
    format('result=%s lignes=%s err=%s', result, n, left(err, 70)));
END $$;

-- ── T02 — LE MAILLON : lien landed_costs → stock_movements ───────────────
DO $$
DECLARE v record; lc_id uuid; n int; effet text;
BEGIN
  v := _mk_cump_env('T02', 50);
  PERFORM set_config('app.current_tenant', v.t::text, false);
  INSERT INTO landed_costs (tenant_id, supplier_id, total_amount, distribution_method)
    VALUES (v.t, v.sup, 100, 'value') RETURNING id INTO lc_id;
  PERFORM distribute_landed_cost(lc_id);
  SELECT count(*) INTO n FROM document_links dl
   WHERE dl.tenant_id = v.t AND dl.amont_type = 'landed_costs' AND dl.amont_id = lc_id
     AND dl.effet = 'stock.landed_cost.distributed' AND dl.etat = 'actif';
  SELECT dl.effet INTO effet FROM document_links dl
   WHERE dl.tenant_id = v.t AND dl.amont_type = 'landed_costs' AND dl.amont_id = lc_id
     AND dl.effet = 'stock.landed_cost.distributed' LIMIT 1;
  PERFORM _rec('T02', 'lien chaîne landed_costs → stock_movements créé (effet stock.landed_cost.distributed)',
    n > 0 AND effet = 'stock.landed_cost.distributed',
    format('liens actifs=%s effet=%s', n, COALESCE(effet, '(aucun)')));
END $$;

-- ── T03 — LA GARDE : une landed_cost reliée ne se supprime pas ────────────
DO $$
DECLARE v record; lc_id uuid; result jsonb; v1 text; n int;
BEGIN
  v := _mk_cump_env('T03', 50);
  PERFORM set_config('app.current_tenant', v.t::text, false);
  INSERT INTO landed_costs (tenant_id, supplier_id, total_amount, distribution_method)
    VALUES (v.t, v.sup, 100, 'value') RETURNING id INTO lc_id;
  PERFORM distribute_landed_cost(lc_id);
  PERFORM set_config('role', 'none', true);
  BEGIN
    DELETE FROM landed_costs WHERE id = lc_id;
    v1 := 'supprimé !';
  EXCEPTION
    WHEN foreign_key_violation THEN
      v1 := CASE WHEN SQLERRM = 'CHAIN_DELETE_REFUSED' THEN 'refusé (chaîne)' ELSE 'refusé : ' || SQLERRM END;
    WHEN OTHERS THEN v1 := 'refusé : ' || SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*) INTO n FROM landed_costs WHERE id = lc_id;
  PERFORM _rec('T03', 'une landed_cost reliée ne se supprime pas (CHAIN_DELETE_REFUSED)',
    v1 = 'refusé (chaîne)' AND n = 1,
    format('verdict=%s landed_costs restantes=%s', v1, n));
END $$;

-- ── T04 — NON-RÉGRESSION : une landed_cost SANS lien se supprime ─────────
DO $$
DECLARE v record; lc_id uuid; n int;
BEGIN
  v := _mk_cump_env('T04', 50);
  PERFORM set_config('app.current_tenant', v.t::text, false);
  INSERT INTO landed_costs (tenant_id, supplier_id, total_amount, distribution_method)
    VALUES (v.t, v.sup, 100, 'value') RETURNING id INTO lc_id;
  PERFORM set_config('role', 'none', true);
  DELETE FROM landed_costs WHERE id = lc_id;
  SELECT count(*) INTO n FROM landed_costs WHERE id = lc_id;
  PERFORM _rec('T04', 'une landed_cost SANS lien se supprime (non-régression)',
    n = 0, format('landed_costs restantes=%s', n));
END $$;

-- ── T05 — COUVERTURE : landed_costs porte sa garde ───────────────────────
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM pg_trigger
   WHERE tgrelid = 'public.landed_costs'::regclass
     AND tgname = 'zz_garde_p5_suppression' AND tgenabled <> 'D';
  PERFORM _rec('T05', 'landed_costs porte sa garde de suppression (couverture 764)',
    n = 1, format('gardes=%s (1 attendu)', n));
END $$;

-- ── T06 — LA CUMP : le coût unitaire est ajusté ──────────────────────────
DO $$
DECLARE v record; lc_id uuid; result jsonb; uc_before numeric; uc_after numeric;
BEGIN
  v := _mk_cump_env('T06', 50);
  PERFORM set_config('app.current_tenant', v.t::text, false);
  SELECT COALESCE(unit_cost, 0) INTO uc_before
    FROM stock_quantities WHERE product_id = v.p AND tenant_id = v.t;
  INSERT INTO landed_costs (tenant_id, supplier_id, total_amount, distribution_method)
    VALUES (v.t, v.sup, 100, 'value') RETURNING id INTO lc_id;
  result := distribute_landed_cost(lc_id);
  SELECT COALESCE(unit_cost, 0) INTO uc_after
    FROM stock_quantities WHERE product_id = v.p AND tenant_id = v.t;
  PERFORM _rec('T06', 'la CUMP ajuste le coût unitaire de stock_quantities (frais répartis)',
    uc_after > uc_before,
    format('coût avant=%s après=%s (delta=%s)', uc_before, uc_after, uc_after - uc_before));
END $$;

-- ── Le VERDICT (G5 : toute suite rend un verdict) ─────────────────────────
SELECT _audit_assert('765');