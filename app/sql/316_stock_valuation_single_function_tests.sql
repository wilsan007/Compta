-- ============================================================
-- 316_stock_valuation_single_function_tests.sql — D2 (stk-005)
--
-- Recette /qa du 29/09/2026, écran Stock → Inventaire, bouton « Valoriser le
-- stock » :
--   1. dépôt « Tous » : erreur d'ambiguïté — PostgREST ne sait pas choisir entre
--      `calculate_stock_valuation(p_method, p_warehouse_id)` et
--      `calculate_stock_valuation(p_tenant_id, p_method, p_date)` → 300,
--      « Aucune valorisation » ;
--   2. avec un dépôt : UNE seule ligne « — | 0 | 0,00 € | 5 600,00 € », identique
--      en FIFO comme en CUMP — 5 600 = Σ quantité × prix d'achat de la FICHE,
--      et non la valeur des couches (5 900 attendus).
--
-- Attendu (la seule vérité depuis la 254 : les couches portent le CUMP) :
-- une ligne par article, valorisée par les couches, et **une seule** fonction.
--
-- Mesuré sur base neuve à la 315, AVANT la 316 : T01 ❌ (les deux surcharges
-- cohabitent), T02 ❌ (l'appel à trois arguments ne se résout pas), T03 ❌.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '316', false);
DELETE FROM _audit_results WHERE file = '316';

CREATE OR REPLACE FUNCTION _mk_stock316(p_nom text, OUT t uuid, OUT wh uuid, OUT a1 uuid, OUT b uuid)
LANGUAGE plpgsql AS $$
BEGIN
  t := _mk_tenant(p_nom);
  INSERT INTO warehouses (tenant_id, code, name) VALUES (t, 'W-' || p_nom, 'Dépôt ' || p_nom) RETURNING id INTO wh;
  INSERT INTO products (tenant_id, name, sku, type, cost_price, stock_account_code)
    VALUES (t, 'A1 ' || p_nom, 'A1-' || p_nom, 'stock', 10, '310000') RETURNING id INTO a1;
  INSERT INTO products (tenant_id, name, sku, type, cost_price, stock_account_code)
    VALUES (t, 'B ' || p_nom, 'B-' || p_nom, 'stock', 4, '310000') RETURNING id INTO b;
END $$;

CREATE OR REPLACE FUNCTION _entree316(p_t uuid, p_wh uuid, p_p uuid, p_qte numeric, p_cout numeric, p_ref text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, movement_type, type,
                               quantity, unit_cost, reference, reference_type, movement_date, date)
  VALUES (p_t, p_p, p_wh, 'in', 'in', p_qte, p_cout, p_ref, 'goods_receipt', CURRENT_DATE, CURRENT_DATE);
END $$;

-- T01 : une ligne par article, valeur des couches.
--       A1 = 50 @ 10 puis 100 @ 14 → CUMP 1 900 / 150 = 12,666… → la couche
--       porte ce CUMP (254) : 150 × 12,666… = 1 900 ; B = 200 @ 4 = 800.
--       Total 2 700. La référence est la somme des couches — c'est l'ancre que
--       la recette donne elle-même (« = écran Quantités en stock, = couches de
--       valorisation ») ; le « 150 × 12 = 1 800 » du plan supposait un CUMP de
--       12, qui n'est pas celui de ces quantités.
DO $$
DECLARE v record; n int := 0; total numeric := 0; q_a1 numeric := 0; v_a1 numeric := 0;
        couches numeric := 0; couches_a1 numeric := 0; err text := '—';
BEGIN
  v := _mk_stock316('T01');
  PERFORM _entree316(v.t, v.wh, v.a1, 50, 10, 'APPRO-T01-A');
  PERFORM _entree316(v.t, v.wh, v.a1, 100, 14, 'APPRO-T01-B');
  PERFORM _entree316(v.t, v.wh, v.b, 200, 4, 'APPRO-T01-C');

  SELECT COALESCE(sum(remaining_qty * unit_cost), 0),
         COALESCE(sum(remaining_qty * unit_cost) FILTER (WHERE product_id = v.a1), 0)
  INTO couches, couches_a1
  FROM stock_valuation_layers
  WHERE tenant_id = v.t AND remaining_qty > 0;

  PERFORM set_config('app.active_tenant_id', v.t::text, false);
  BEGIN
    SELECT count(*), COALESCE(sum(total_value), 0),
           COALESCE(sum(quantity) FILTER (WHERE product_id = v.a1), 0),
           COALESCE(sum(total_value) FILTER (WHERE product_id = v.a1), 0)
    INTO n, total, q_a1, v_a1
    FROM calculate_stock_valuation('cump', NULL, CURRENT_DATE);
  EXCEPTION WHEN OTHERS THEN err := SQLERRM;
  END;

  PERFORM _rec('T01', 'une ligne par article, valeur lue sur les couches (A1 150 → 1 900 ; total 2 700)',
    n = 2 AND q_a1 = 150
      AND abs(v_a1 - couches_a1) < 0.01 AND abs(total - couches) < 0.01
      AND abs(v_a1 - 1900) < 0.01 AND abs(total - 2700) < 0.01,
    format('lignes=%s (2 attendues) A1 quantité=%s (150) valeur=%s (couches=%s, 1900 attendus) total=%s (couches=%s, 2700 attendus) | %s',
           n, q_a1, round(v_a1, 2), round(couches_a1, 2), round(total, 2), round(couches, 2), left(err, 70)));
END $$;

-- T02 : UNE seule fonction `calculate_stock_valuation` — c'est ce qui rendait
--       l'appel ambigu (300) pour PostgREST.
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n
  FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
  WHERE ns.nspname = 'public' AND p.proname = 'calculate_stock_valuation';

  PERFORM _rec('T02', 'une seule fonction calculate_stock_valuation (plus d''ambiguïté PostgREST)',
    n = 1, format('fonctions trouvées=%s (1 attendue)', n));
END $$;

-- T03 : un article sans quantité vivante n'apparaît pas (la recette voyait une
--       ligne « — | 0 | 0,00 € »).
DO $$
DECLARE v record; n int := 0; err text := '—';
BEGIN
  v := _mk_stock316('T03');
  PERFORM _entree316(v.t, v.wh, v.a1, 10, 10, 'APPRO-T03');
  -- puis on le sort entièrement
  INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, movement_type, type,
                               quantity, reference, reference_type, movement_date, date)
  VALUES (v.t, v.a1, v.wh, 'out', 'out', 10, 'BL-T03', 'delivery_note', CURRENT_DATE, CURRENT_DATE);

  PERFORM set_config('app.active_tenant_id', v.t::text, false);
  BEGIN
    SELECT count(*) INTO n FROM calculate_stock_valuation('cump', NULL, CURRENT_DATE);
  EXCEPTION WHEN OTHERS THEN err := SQLERRM;
  END;

  PERFORM _rec('T03', 'un article soldé n''apparaît pas dans la valorisation',
    err = '—' AND n = 0, format('lignes=%s (0 attendue) | %s', n, left(err, 70)));
END $$;

DROP FUNCTION _entree316(uuid, uuid, uuid, numeric, numeric, text);
DROP FUNCTION _mk_stock316(text);
SELECT _audit_assert('316');
