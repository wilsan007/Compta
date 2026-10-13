-- ============================================================
-- 664_tenant_guard_mrp_capacity_tests.sql — R3 / ISO-01 (partie E)
--
-- Mesuré AVANT la 664 : `ci/check_tenant_guard.sql` refusait DEUX fonctions de
-- cette partie — `work_center_capacity` (657) et `run_mrp` (651). Toutes deux
-- prenaient la société du client, donc un appelant pouvait lire l'atelier, les
-- stocks et les commandes d'une société dont il n'est pas membre. T01 et T03
-- montrent le trou lui-même : ils exigent que la lecture ÉCHOUE.
--
-- Ces deux trous ont vécu des semaines sans être vus : les suites de 651 et 657
-- étaient vertes. Ce qui l'a vu, c'est la CI enfin déclenchée sur la branche
-- (R3) — les tests ne cherchent que ce qu'on leur a demandé de chercher.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '664', false);
DELETE FROM _audit_results WHERE file = '664';

-- Deux sociétés : l'étrangère d'abord, la nôtre ensuite — `_mk_tenant` laisse le
-- contexte sur la DERNIÈRE créée, donc l'appelant est membre de la seconde.
-- Chaque société a un centre de charge et un article.
CREATE OR REPLACE FUNCTION _mk664(p_nom text, OUT t uuid, OUT wc uuid, OUT p uuid) LANGUAGE plpgsql AS $$
BEGIN
  t := _mk_tenant(p_nom, false);
  INSERT INTO work_centers (tenant_id, code, name, capacity_hours_per_day, cost_per_hour, active)
  VALUES (t, 'WC-' || p_nom, 'Poste ' || p_nom, 8, 50, true) RETURNING id INTO wc;
  INSERT INTO products (tenant_id, name, sku, type, cost_price, safety_stock, lead_time_days)
  VALUES (t, 'Article ' || p_nom, 'SKU-' || p_nom, 'stock', 10, 0, 7) RETURNING id INTO p;
END $$;

-- Une commande ferme de 40, livrée dans l'horizon : un besoin net réel.
CREATE OR REPLACE FUNCTION _besoin664(p_t uuid, p_p uuid, p_qte numeric) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_so uuid;
BEGIN
  INSERT INTO sales_orders (tenant_id, number, status, delivery_date)
  VALUES (p_t, 'SO-' || p_p, 'confirmed', CURRENT_DATE + 5) RETURNING id INTO v_so;
  INSERT INTO sales_order_lines (tenant_id, sales_order_id, product_id, description, quantity, unit_price)
  VALUES (p_t, v_so, p_p, 'Ligne', p_qte, 10);
END $$;

-- T01 — le trou : lire la capacité d'un centre de charge d'une AUTRE société
DO $$
DECLARE tb uuid; wcb uuid; pb uuid; ta uuid; wca uuid; pa uuid;
        c numeric; v_state text; v_err text;
BEGIN
  SELECT * INTO tb, wcb, pb FROM _mk664('VAL664B01');  -- société étrangère
  SELECT * INTO ta, wca, pa FROM _mk664('VAL664A01');  -- l'appelant est ici
  BEGIN
    c := work_center_capacity(tb, wcb, CURRENT_DATE);
  EXCEPTION WHEN others THEN v_state := SQLSTATE; v_err := SQLERRM;
  END;
  PERFORM _rec('T01', 'work_center_capacity REFUSE le centre de charge d''une société dont l''appelant n''est pas membre',
    v_state = 'P0001',
    format('SQLSTATE=%s ; capacité lue=%s ; %s', COALESCE(v_state, 'aucune erreur — la lecture a réussi'),
           COALESCE(c::text, '—'), left(v_err, 70)));
END $$;

-- T02 — porte de non-régression : la société du contexte est toujours servie
DO $$
DECLARE t uuid; wc uuid; p uuid; c numeric;
BEGIN
  SELECT * INTO t, wc, p FROM _mk664('VAL664T02');
  c := work_center_capacity(t, wc, CURRENT_DATE);
  PERFORM _rec('T02', 'work_center_capacity sert toujours la société du contexte (8, sans calendrier)',
    c = 8, format('capacité=%s (8 attendu)', c));
END $$;

-- T03 — le trou, pire que T01 : le MRP d'une autre société
DO $$
DECLARE tb uuid; wcb uuid; pb uuid; ta uuid; wca uuid; pa uuid;
        n int; v_state text; v_err text;
BEGIN
  SELECT * INTO tb, wcb, pb FROM _mk664('VAL664B03');
  PERFORM _besoin664(tb, pb, 40);
  SELECT * INTO ta, wca, pa FROM _mk664('VAL664A03');
  BEGIN
    SELECT count(*) INTO n FROM run_mrp(tb, 365);
  EXCEPTION WHEN others THEN v_state := SQLSTATE; v_err := SQLERRM;
  END;
  PERFORM _rec('T03', 'run_mrp REFUSE de calculer les besoins d''une société dont l''appelant n''est pas membre',
    v_state = 'P0001',
    format('SQLSTATE=%s ; lignes lues=%s ; %s', COALESCE(v_state, 'aucune erreur — le calcul a réussi'),
           COALESCE(n::text, '—'), left(v_err, 70)));
END $$;

-- T04 — non-régression : le MRP de SA société, paramètre nommant le contexte
DO $$
DECLARE t uuid; wc uuid; p uuid; n int; g numeric;
BEGIN
  SELECT * INTO t, wc, p FROM _mk664('VAL664T04');
  PERFORM _besoin664(t, p, 40);
  SELECT count(*), COALESCE(SUM(gross_need), 0) INTO n, g FROM run_mrp(t, 365);
  PERFORM _rec('T04', 'run_mrp calcule toujours les besoins de la société du contexte (1 ligne, 40)',
    (n = 1 AND g = 40), format('lignes=%s, besoin brut=%s (1 et 40 attendus)', n, g));
END $$;

-- T05 — non-régression : sans paramètre, la société reste celle du contexte
DO $$
DECLARE t uuid; wc uuid; p uuid; n int; g numeric;
BEGIN
  SELECT * INTO t, wc, p FROM _mk664('VAL664T05');
  PERFORM _besoin664(t, p, 40);
  SELECT count(*), COALESCE(SUM(gross_need), 0) INTO n, g FROM run_mrp();
  PERFORM _rec('T05', 'run_mrp() sans paramètre prend la société du contexte (1 ligne, 40)',
    (n = 1 AND g = 40), format('lignes=%s, besoin brut=%s (1 et 40 attendus)', n, g));
END $$;

SELECT _audit_assert('664');
