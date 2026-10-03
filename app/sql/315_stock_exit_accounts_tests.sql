-- ============================================================
-- 315_stock_exit_accounts_tests.sql — D1 (stk-012)
--
-- Recette /qa du 29/09/2026, produit fini vendu en caisse : la sortie était
-- passée en matières — JE-STK-… **D 603000 88 / C 310000 88** — alors que
-- l'entrée de ce produit (l'OF-2026-000002) l'avait porté en 355000 contre
-- 713500. Résultat mesuré : 355000 restait à 440 pour un stock de 308, et
-- 310000 était diminué de 132 € de matières qui n'avaient pas bougé.
--
-- La règle : le compte d'une sortie est **celui de l'entrée qui a nourri la
-- couche consommée** (produits finis 355/7135, marchandises 37/6037, matières
-- 31/6031 — la distinction vient de l'entrée, pas du nom de l'article).
--
-- Mesuré sur base neuve à la 314, AVANT la 315 : T01 ❌ (la sortie part en
-- 310000/603000 : le compte de l'article, figé à sa création).
-- T02 est une non-régression : une marchandise doit continuer d'être sortie
-- sur les comptes de son entrée.
--
-- L'écriture de production (D 355000 / C 713500, référence `JE-OF-<numéro>`)
-- est reproduite ici telle que la 302 l'écrit : le scénario reste sur le seul
-- défaut mesuré, sans rejouer la chaîne de fabrication (couverte par la 302).
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '315', false);
DELETE FROM _audit_results WHERE file = '315';

CREATE OR REPLACE FUNCTION _mk_vente315(p_nom text,
  OUT t uuid, OUT wh uuid, OUT pf uuid, OUT mp uuid)
LANGUAGE plpgsql AS $$
BEGIN
  t := _mk_tenant(p_nom);
  PERFORM ensure_standard_journals(t);
  INSERT INTO warehouses (tenant_id, code, name) VALUES (t, 'W-' || p_nom, 'Dépôt') RETURNING id INTO wh;
  INSERT INTO products (tenant_id, name, sku, type, cost_price, stock_account_code)
    VALUES (t, 'Produit fini ' || p_nom, 'PF-' || p_nom, 'stock', 44, '310000') RETURNING id INTO pf;
  INSERT INTO products (tenant_id, name, sku, type, cost_price, stock_account_code)
    VALUES (t, 'Marchandise ' || p_nom, 'MP-' || p_nom, 'stock', 12, '370000') RETURNING id INTO mp;
END $$;

-- Entrée de production : le mouvement 'in' ET l'écriture de l'OF, ce que la 302 écrit
CREATE OR REPLACE FUNCTION _entree_production315(p_t uuid, p_wh uuid, p_pf uuid,
  p_qte numeric, p_cout numeric, p_num text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE m uuid; e uuid; total numeric := p_qte * p_cout;
BEGIN
  INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, movement_type, type,
                               quantity, unit_cost, reference, reference_type, movement_date, date)
  VALUES (p_t, p_pf, p_wh, 'in', 'in', p_qte, p_cout, p_num, 'production', CURRENT_DATE, CURRENT_DATE)
  RETURNING id INTO m;

  INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description, reference)
  VALUES (p_t, 'JE-OF-' || p_num, CURRENT_DATE, 'OF', 'draft', 'Production OF ' || p_num, 'JE-OF-' || p_num)
  RETURNING id INTO e;

  INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, debit, credit, description, line_order)
  VALUES
    (p_t, e, '355000', '355000', total, 0, 'Entrée produit fini — ' || p_num, 0),
    (p_t, e, '713500', '713500', 0, total, 'Production stockée — ' || p_num, 1);

  UPDATE journal_entries SET status = 'posted' WHERE id = e;
  RETURN m;
END $$;

-- Entrée d'achat : le déclencheur ST écrit lui-même l'écriture (D stock / C variation)
CREATE OR REPLACE FUNCTION _entree_achat315(p_t uuid, p_wh uuid, p_mp uuid,
  p_qte numeric, p_cout numeric, p_ref text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE m uuid;
BEGIN
  INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, movement_type, type,
                               quantity, unit_cost, reference, reference_type, movement_date, date)
  VALUES (p_t, p_mp, p_wh, 'in', 'in', p_qte, p_cout, p_ref, 'goods_receipt', CURRENT_DATE, CURRENT_DATE)
  RETURNING id INTO m;
  RETURN m;
END $$;

-- T01 (stk-012) : la sortie d'un produit fini suit le compte de son entrée.
DO $$
DECLARE v record; m uuid; code_d text; code_c text; mt numeric; mtc numeric; n310 int;
BEGIN
  v := _mk_vente315('T01');
  PERFORM _entree_production315(v.t, v.wh, v.pf, 10, 44, 'OF-T01');   -- 10 × 44 = 440 en 355000/713500

  PERFORM _as_user();
  INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, movement_type, type,
                               quantity, reference, reference_type, movement_date, date)
  VALUES (v.t, v.pf, v.wh, 'out', 'out', 2, 'TK-T01', 'pos_ticket', CURRENT_DATE, CURRENT_DATE)
  RETURNING id INTO m;
  PERFORM set_config('role', 'postgres', true);

  SELECT jl.account_code, jl.debit INTO code_d, mt
  FROM journal_lines jl JOIN journal_entries je ON je.id = jl.journal_id
  WHERE je.piece_number = 'STK-' || m::text AND jl.debit > 0
  ORDER BY jl.line_order LIMIT 1;

  SELECT jl.account_code, jl.credit INTO code_c, mtc
  FROM journal_lines jl JOIN journal_entries je ON je.id = jl.journal_id
  WHERE je.piece_number = 'STK-' || m::text AND jl.credit > 0
  ORDER BY jl.line_order LIMIT 1;

  SELECT count(*) INTO n310
  FROM journal_lines jl JOIN journal_entries je ON je.id = jl.journal_id
  WHERE je.piece_number = 'STK-' || m::text AND jl.account_code = '310000';

  PERFORM _rec('T01', 'sortie d''un produit fini : 713500 D 88 / 355000 C 88, 310000 intouché',
    code_d = '713500' AND mt = 88 AND code_c = '355000' AND mtc = 88 AND n310 = 0,
    format('débit=%s %s (713500 / 88 attendus) crédit=%s %s (355000 / 88 attendus) lignes en 310000=%s (0 attendue)',
           code_d, mt, code_c, mtc, n310));
END $$;

-- T02 (non-régression) : une marchandise sort sur les comptes de son entrée.
DO $$
DECLARE v record; m uuid; code_d text; code_c text; mt numeric; mtc numeric;
BEGIN
  v := _mk_vente315('T02');
  PERFORM _entree_achat315(v.t, v.wh, v.mp, 10, 12, 'APPRO-T02');   -- écriture de réception : D 370000 / C 603000

  PERFORM _as_user();
  INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, movement_type, type,
                               quantity, reference, reference_type, movement_date, date)
  VALUES (v.t, v.mp, v.wh, 'out', 'out', 5, 'BL-T02', 'delivery_note', CURRENT_DATE, CURRENT_DATE)
  RETURNING id INTO m;
  PERFORM set_config('role', 'postgres', true);

  SELECT jl.account_code, jl.debit INTO code_d, mt
  FROM journal_lines jl JOIN journal_entries je ON je.id = jl.journal_id
  WHERE je.piece_number = 'STK-' || m::text AND jl.debit > 0
  ORDER BY jl.line_order LIMIT 1;

  SELECT jl.account_code, jl.credit INTO code_c, mtc
  FROM journal_lines jl JOIN journal_entries je ON je.id = jl.journal_id
  WHERE je.piece_number = 'STK-' || m::text AND jl.credit > 0
  ORDER BY jl.line_order LIMIT 1;

  PERFORM _rec('T02', 'marchandise : sortie sur les comptes de la réception (603000 D 60 / 370000 C 60)',
    code_d = '603000' AND mt = 60 AND code_c = '370000' AND mtc = 60,
    format('débit=%s %s (603000 / 60 attendus) crédit=%s %s (370000 / 60 attendus)', code_d, mt, code_c, mtc));
END $$;

DROP FUNCTION _entree_achat315(uuid, uuid, uuid, numeric, numeric, text);
DROP FUNCTION _entree_production315(uuid, uuid, uuid, numeric, numeric, text);
DROP FUNCTION _mk_vente315(text);
SELECT _audit_assert('315');
