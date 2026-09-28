-- ============================================================
-- 270_manufacturing_multilevel_and_variances_tests.sql — W8 (M-08) :
-- nomenclature multi-niveaux, écarts de quantité et de coût, date de l'OF
--
-- Les trois défauts de production restants du plan correctif :
--
--   PROD-01 🟠 `create_stock_on_manufacturing_complete` lit `bom_lines`
--             **à un seul niveau** (`WHERE bl.bom_id = NEW.bom_id`) : un
--             composant lui-même fabriqué n'est pas explosé. L'atelier consomme
--             la pièce intermédiaire — qui n'a jamais été fabriquée ni stockée.
--   PROD-02 🟠 `qty_produced` est **écrasée** par la quantité lancée moins les
--             rebuts : un écart de production déclaré est effacé, et un rebut
--             supérieur au lancé est silencieusement ramené à zéro. Aucun écart
--             de coût n'est écrit (`cost_variance` n'existe pas).
--   PROD-03 🟡 L'écriture et les mouvements sont datés de `CURRENT_DATE` : un OF
--             clôturé en retard tombe dans le mauvais exercice.
--
-- Chaque scénario mesure un chiffre, pas une intention. Les non-régressions de
-- la 229 (rebuts, double clôture) sont rejouées en T08.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '302', false);
DELETE FROM _audit_results WHERE file = '302';

-- Société + journaux d'atelier, puis dépôt de la société
DROP FUNCTION IF EXISTS _prod270_tenant(text);
DROP FUNCTION IF EXISTS _prod270_wh(uuid);
DROP FUNCTION IF EXISTS _prod270_article(uuid, text, numeric);
DROP FUNCTION IF EXISTS _prod270_bom(uuid, uuid, text, jsonb);
DROP FUNCTION IF EXISTS _prod270_stock(uuid, uuid, uuid, numeric, numeric);
DROP FUNCTION IF EXISTS _prod270_of(uuid, uuid, uuid, uuid, numeric, text, date, numeric, numeric);
DROP FUNCTION IF EXISTS _prod270_sortie(uuid, uuid, uuid);
CREATE OR REPLACE FUNCTION _prod270_tenant(p_nom text) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE t uuid;
BEGIN
  t := _mk_tenant(p_nom);
  PERFORM ensure_standard_journals(t);
  INSERT INTO warehouses (tenant_id, code, name) VALUES (t, 'W-' || p_nom, 'Dépôt ' || p_nom);
  RETURN t;
END $$;

CREATE OR REPLACE FUNCTION _prod270_wh(p_t uuid) RETURNS uuid
LANGUAGE sql AS $$ SELECT id FROM warehouses WHERE tenant_id = p_t LIMIT 1 $$;

-- Article d'atelier : p_cout = prix de revient de référence (cost_price)
CREATE OR REPLACE FUNCTION _prod270_article(p_t uuid, p_nom text, p_cout numeric)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v uuid;
BEGIN
  INSERT INTO products (tenant_id, name, sku, type, cost_price)
    VALUES (p_t, p_nom, left(replace(p_nom, ' ', '-'), 20) || '-' || left(uuid_generate_v4()::text, 4), 'stock', p_cout)
    RETURNING id INTO v;
  RETURN v;
END $$;

-- Nomenclature : une ligne par composant (quantité par unité de produit fini,
-- et prix standard de la ligne)
CREATE OR REPLACE FUNCTION _prod270_bom(p_t uuid, p_pf uuid, p_nom text, p_lignes jsonb)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE b uuid;
BEGIN
  INSERT INTO boms (tenant_id, code, name, product_id, quantity)
    VALUES (p_t, 'B-' || p_nom, 'Nomenclature ' || p_nom, p_pf, 1) RETURNING id INTO b;
  INSERT INTO bom_lines (tenant_id, bom_id, product_id, quantity, unit_cost)
  SELECT p_t, b, (x->>'produit')::uuid, (x->>'qte')::numeric, NULLIF((x->>'std')::numeric, 0)
  FROM jsonb_array_elements(p_lignes) x;
  RETURN b;
END $$;

-- Approvisionnement hors production (reference_type NULL)
CREATE OR REPLACE FUNCTION _prod270_stock(p_t uuid, p_wh uuid, p_p uuid, p_qte numeric, p_cout numeric)
RETURNS void LANGUAGE sql AS $$
  INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, movement_type, type,
                               quantity, unit_cost, reference, movement_date, date)
  VALUES (p_t, p_p, p_wh, 'in', 'in', p_qte, p_cout, 'APPRO-' || left(p_p::text, 8), CURRENT_DATE, CURRENT_DATE)
$$;

-- Ordre de fabrication (prêt à clôturer)
CREATE OR REPLACE FUNCTION _prod270_of(p_t uuid, p_wh uuid, p_pf uuid, p_bom uuid,
  p_qte numeric, p_nom text, p_end date DEFAULT NULL, p_declare numeric DEFAULT NULL,
  p_rebut numeric DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE mo uuid;
BEGIN
  INSERT INTO manufacturing_orders (tenant_id, number, bom_id, product_id, quantity, status,
                                    warehouse_id, end_date, qty_produced, qty_scrapped)
  VALUES (p_t, 'OF-' || p_nom, p_bom, p_pf, p_qte, 'planned', p_wh, p_end, p_declare, p_rebut)
  RETURNING id INTO mo;
  RETURN mo;
END $$;

-- Sortie de stock d'un composant, par produit, pour un OF donné
CREATE OR REPLACE FUNCTION _prod270_sortie(p_t uuid, p_mo uuid, p_produit uuid)
RETURNS numeric LANGUAGE sql AS $$
  SELECT COALESCE(sum(quantity), 0) FROM stock_movements
  WHERE tenant_id = p_t AND reference_type = 'production' AND reference_id = p_mo
    AND product_id = p_produit AND movement_type = 'out'
$$;


-- T01 — PROD-01 : deux niveaux. PF ← 1 × SF, SF ← 2 × MP. OF de 10 PF :
-- 20 MP doivent sortir, et **aucun** mouvement de SF (il n'est jamais fabriqué).
DO $$
DECLARE t uuid; wh uuid; mp uuid; sf uuid; pf uuid; b_sf uuid; b_pf uuid; mo uuid;
        q_mp numeric; q_sf numeric; err text := '—';
BEGIN
  t := _prod270_tenant('P01'); wh := _prod270_wh(t);
  mp := _prod270_article(t, 'MP P01', 5);
  sf := _prod270_article(t, 'Sous-ensemble P01', 0);
  pf := _prod270_article(t, 'Produit fini P01', 0);
  b_sf := _prod270_bom(t, sf, 'SF P01', jsonb_build_array(jsonb_build_object('produit', mp, 'qte', 2, 'std', 5)));
  b_pf := _prod270_bom(t, pf, 'PF P01', jsonb_build_array(jsonb_build_object('produit', sf, 'qte', 1, 'std', 0)));
  PERFORM _prod270_stock(t, wh, mp, 1000, 5);
  mo := _prod270_of(t, wh, pf, b_pf, 10, 'P01');
  PERFORM _as_user();
  BEGIN
    UPDATE manufacturing_orders SET status = 'completed' WHERE id = mo;
  EXCEPTION WHEN OTHERS THEN err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);

  q_mp := _prod270_sortie(t, mo, mp);
  q_sf := _prod270_sortie(t, mo, sf);
  PERFORM _rec('T01', 'nomenclature à deux niveaux : 10 PF consomment 20 MP, jamais le sous-ensemble',
    q_mp = 20 AND q_sf = 0,
    format('MP sorties=%s (20 attendues) ; SF sorties=%s (0 attendue — il n''est pas fabriqué) | %s', q_mp, q_sf, left(err, 80)));
END $$;

-- T02 — PROD-01 : trois niveaux. PF ← 1 × SF, SF ← 3 × SS, SS ← 2 × MP.
-- OF de 10 PF : 10 × 3 × 2 = 60 MP.
DO $$
DECLARE t uuid; wh uuid; mp uuid; ss uuid; sf uuid; pf uuid;
        b_ss uuid; b_sf uuid; b_pf uuid; mo uuid; q_mp numeric; q_ss numeric; q_sf numeric;
        err text := '—';
BEGIN
  t := _prod270_tenant('P02'); wh := _prod270_wh(t);
  mp := _prod270_article(t, 'MP P02', 4);
  ss := _prod270_article(t, 'Sous-sous-ensemble P02', 0);
  sf := _prod270_article(t, 'Sous-ensemble P02', 0);
  pf := _prod270_article(t, 'Produit fini P02', 0);
  b_ss := _prod270_bom(t, ss, 'SS P02', jsonb_build_array(jsonb_build_object('produit', mp, 'qte', 2, 'std', 4)));
  b_sf := _prod270_bom(t, sf, 'SF P02', jsonb_build_array(jsonb_build_object('produit', ss, 'qte', 3, 'std', 0)));
  b_pf := _prod270_bom(t, pf, 'PF P02', jsonb_build_array(jsonb_build_object('produit', sf, 'qte', 1, 'std', 0)));
  PERFORM _prod270_stock(t, wh, mp, 1000, 4);
  mo := _prod270_of(t, wh, pf, b_pf, 10, 'P02');
  PERFORM _as_user();
  BEGIN
    UPDATE manufacturing_orders SET status = 'completed' WHERE id = mo;
  EXCEPTION WHEN OTHERS THEN err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);

  q_mp := _prod270_sortie(t, mo, mp);
  q_ss := _prod270_sortie(t, mo, ss);
  q_sf := _prod270_sortie(t, mo, sf);
  PERFORM _rec('T02', 'nomenclature à trois niveaux : 10 PF consomment 60 MP (10 × 3 × 2)',
    q_mp = 60 AND q_ss = 0 AND q_sf = 0,
    format('MP=%s (60 attendues) SS=%s (0) SF=%s (0) | %s', q_mp, q_ss, q_sf, left(err, 80)));
END $$;

-- T03 — PROD-01 : une nomenclature qui boucle ne boucle pas dans l'atelier.
-- PF ← 1 × SF, SF ← 1 × MP, MP ← 1 × SF (cycle). L'explosion s'arrête au
-- composant déjà rencontré : 10 MP sortis, clôture acceptée.
DO $$
DECLARE t uuid; wh uuid; mp uuid; sf uuid; pf uuid;
        b_mp uuid; b_sf uuid; b_pf uuid; mo uuid; q_mp numeric; ok boolean := false; err text := '—';
BEGIN
  t := _prod270_tenant('P03'); wh := _prod270_wh(t);
  mp := _prod270_article(t, 'MP P03', 3);
  sf := _prod270_article(t, 'Sous-ensemble P03', 0);
  pf := _prod270_article(t, 'Produit fini P03', 0);
  b_mp := _prod270_bom(t, mp, 'MP P03', jsonb_build_array(jsonb_build_object('produit', sf, 'qte', 1, 'std', 0)));
  b_sf := _prod270_bom(t, sf, 'SF P03', jsonb_build_array(jsonb_build_object('produit', mp, 'qte', 1, 'std', 3)));
  b_pf := _prod270_bom(t, pf, 'PF P03', jsonb_build_array(jsonb_build_object('produit', sf, 'qte', 1, 'std', 0)));
  PERFORM _prod270_stock(t, wh, mp, 1000, 3);
  mo := _prod270_of(t, wh, pf, b_pf, 10, 'P03');
  PERFORM _as_user();
  BEGIN
    UPDATE manufacturing_orders SET status = 'completed' WHERE id = mo;
    ok := true;
  EXCEPTION WHEN OTHERS THEN err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);
  q_mp := _prod270_sortie(t, mo, mp);
  PERFORM _rec('T03', 'une nomenclature cyclique ne récurse pas sans fin : clôture acceptée, MP comptée une fois',
    ok AND q_mp = 10, format('clôture=%s MP=%s (10 attendues) | %s', ok, q_mp, left(err, 90)));
END $$;

-- T04 — PROD-02 : un écart de production **déclaré** est respecté.
-- 100 lancées, 8 rebutées, 88 déclarées bonnes (écart 4 non déclaré) :
-- qty_produced doit valoir 88, pas 92.
DO $$
DECLARE t uuid; wh uuid; mp uuid; pf uuid; b uuid; mo uuid; qp numeric; q_in numeric;
BEGIN
  t := _prod270_tenant('P04'); wh := _prod270_wh(t);
  mp := _prod270_article(t, 'MP P04', 5);
  pf := _prod270_article(t, 'Produit fini P04', 0);
  b := _prod270_bom(t, pf, 'PF P04', jsonb_build_array(jsonb_build_object('produit', mp, 'qte', 1, 'std', 5)));
  PERFORM _prod270_stock(t, wh, mp, 1000, 5);
  mo := _prod270_of(t, wh, pf, b, 100, 'P04', NULL, 88, 8);
  PERFORM _as_user();
  UPDATE manufacturing_orders SET status = 'completed' WHERE id = mo;
  PERFORM set_config('role', 'postgres', true);
  SELECT qty_produced INTO qp FROM manufacturing_orders WHERE id = mo;
  SELECT COALESCE(sum(quantity), 0) INTO q_in FROM stock_movements
    WHERE tenant_id = t AND reference_type = 'production' AND reference_id = mo AND movement_type = 'in';
  PERFORM _rec('T04', 'la quantité produite déclarée (88) est respectée, l''écart (4) n''est pas effacé',
    qp = 88 AND q_in = 88,
    format('qty_produced=%s (88 attendues) entrées en stock=%s (88 attendues)', qp, q_in));
END $$;

-- T05 — PROD-02 : un rebut supérieur à la quantité lancée est refusé (il était
-- ramené à zéro en silence, et l'OF entrait 0 pièce en stock sans rien dire).
DO $$
DECLARE t uuid; wh uuid; mp uuid; pf uuid; b uuid; mo uuid; refuse boolean := false; err text := '—';
BEGIN
  t := _prod270_tenant('P05'); wh := _prod270_wh(t);
  mp := _prod270_article(t, 'MP P05', 5);
  pf := _prod270_article(t, 'Produit fini P05', 0);
  b := _prod270_bom(t, pf, 'PF P05', jsonb_build_array(jsonb_build_object('produit', mp, 'qte', 1, 'std', 5)));
  PERFORM _prod270_stock(t, wh, mp, 1000, 5);
  mo := _prod270_of(t, wh, pf, b, 100, 'P05', NULL, NULL, 150);
  PERFORM _as_user();
  BEGIN
    UPDATE manufacturing_orders SET status = 'completed' WHERE id = mo;
  EXCEPTION WHEN OTHERS THEN refuse := true; err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);
  PERFORM _rec('T05', 'un rebut (150) supérieur au lancé (100) est refusé, pas ramené à zéro',
    refuse, format('refus=%s | %s', refuse, left(err, 100)));
END $$;

-- T06 — PROD-02 : l'écart de coût est chiffré. Nomenclature à 5,00 de standard
-- par pièce, matière approvisionnée à 6,00 : 10 pièces → standard 50,00,
-- réel 60,00, écart −10,00 (le standard est dépassé).
DO $$
DECLARE t uuid; wh uuid; mp uuid; pf uuid; b uuid; mo uuid; v numeric; j jsonb;
BEGIN
  v := NULL;
  BEGIN
    t := _prod270_tenant('P06'); wh := _prod270_wh(t);
    mp := _prod270_article(t, 'MP P06', 6);
    pf := _prod270_article(t, 'Produit fini P06', 0);
    b := _prod270_bom(t, pf, 'PF P06', jsonb_build_array(jsonb_build_object('produit', mp, 'qte', 1, 'std', 5)));
    PERFORM _prod270_stock(t, wh, mp, 1000, 6);
    mo := _prod270_of(t, wh, pf, b, 10, 'P06');
    PERFORM _as_user();
    UPDATE manufacturing_orders SET status = 'completed' WHERE id = mo;
    PERFORM set_config('role', 'postgres', true);
    SELECT cost_variance INTO v FROM manufacturing_orders WHERE id = mo;
    j := calculate_manufacturing_cost(mo, t);
    PERFORM _rec('T06', 'écart de coût écrit et rendu : 50,00 de standard contre 60,00 de réel → −10,00',
      v = -10 AND (j->>'cost_variance')::numeric = -10 AND (j->>'cost_standard')::numeric = 50,
      format('cost_variance=%s (attendu −10) ; rendu : écart=%s standard=%s', v, j->>'cost_variance', j->>'cost_standard'));
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('role', 'postgres', true);
    PERFORM _rec('T06', 'écart de coût écrit et rendu : 50,00 de standard contre 60,00 de réel → −10,00', false, SQLERRM);
  END;
END $$;


-- T07 — PROD-03 : les mouvements et l'écriture portent la date de l'OF, pas
-- celle du jour où on le clôture.
DO $$
DECLARE t uuid; wh uuid; mp uuid; pf uuid; b uuid; mo uuid;
        d_mvt date; d_max date; d_je date;
BEGIN
  t := _prod270_tenant('P07'); wh := _prod270_wh(t);
  mp := _prod270_article(t, 'MP P07', 5);
  pf := _prod270_article(t, 'Produit fini P07', 0);
  b := _prod270_bom(t, pf, 'PF P07', jsonb_build_array(jsonb_build_object('produit', mp, 'qte', 1, 'std', 5)));
  PERFORM _prod270_stock(t, wh, mp, 1000, 5);
  mo := _prod270_of(t, wh, pf, b, 5, 'P07', '2026-03-15'::date);
  PERFORM _as_user();
  UPDATE manufacturing_orders SET status = 'completed' WHERE id = mo;
  PERFORM set_config('role', 'postgres', true);
  SELECT min(movement_date), max(movement_date) INTO d_mvt, d_max
  FROM stock_movements WHERE tenant_id = t AND reference_type = 'production' AND reference_id = mo;
  SELECT date INTO d_je FROM journal_entries WHERE tenant_id = t AND reference = 'JE-OF-OF-P07';
  PERFORM _rec('T07', 'un OF daté du 15/03 se clôture au 15/03 : mouvements et écriture datés de l''OF',
    d_mvt = '2026-03-15' AND d_max = '2026-03-15' AND d_je = '2026-03-15',
    format('mouvements %s → %s (15/03 attendu) ; écriture=%s', d_mvt, d_max, d_je));
END $$;

-- T08 — non-régression de la 229 : rebut simple, nomenclature à un niveau.
-- 100 lancées, 10 rebutées → 90 en stock, coût réparti sur les 90.
DO $$
DECLARE t uuid; wh uuid; mp uuid; pf uuid; b uuid; mo uuid; q_in numeric; uc numeric;
BEGIN
  t := _prod270_tenant('P08'); wh := _prod270_wh(t);
  mp := _prod270_article(t, 'MP P08', 5);
  pf := _prod270_article(t, 'Produit fini P08', 0);
  b := _prod270_bom(t, pf, 'PF P08', jsonb_build_array(jsonb_build_object('produit', mp, 'qte', 2, 'std', 5)));
  PERFORM _prod270_stock(t, wh, mp, 1000, 5);
  mo := _prod270_of(t, wh, pf, b, 100, 'P08', NULL, NULL, 10);
  PERFORM _as_user();
  UPDATE manufacturing_orders SET status = 'completed' WHERE id = mo;
  PERFORM set_config('role', 'postgres', true);
  SELECT COALESCE(sum(quantity), 0) INTO q_in FROM stock_movements
    WHERE tenant_id = t AND reference_type = 'production' AND reference_id = mo
      AND movement_type = 'in' AND product_id = pf;
  SELECT unit_cost INTO uc FROM manufacturing_orders WHERE id = mo;
  PERFORM _rec('T08', 'non-régression 229 : 100 lancées dont 10 rebutées → 90 entrées, coût unitaire sur 90',
    q_in = 90 AND round(uc, 2) = 11.11,
    format('entrées=%s (90 attendues) coût unitaire=%s (11,11 attendu)', q_in, round(uc, 2)));
END $$;

DROP FUNCTION _prod270_sortie(uuid, uuid, uuid);
DROP FUNCTION _prod270_of(uuid, uuid, uuid, uuid, numeric, text, date, numeric, numeric);
DROP FUNCTION _prod270_stock(uuid, uuid, uuid, numeric, numeric);
DROP FUNCTION _prod270_bom(uuid, uuid, text, jsonb);
DROP FUNCTION _prod270_article(uuid, text, numeric);
DROP FUNCTION _prod270_wh(uuid);
DROP FUNCTION _prod270_tenant(text);
SELECT _audit_assert('302');
