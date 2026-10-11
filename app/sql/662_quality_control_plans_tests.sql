-- ============================================================
-- 662_quality_control_plans_tests.sql — STK-13 / E.5
--
-- Mesuré AVANT la 662 : les plans de contrôle ne répondaient à rien — on ne
-- pouvait pas dire quel plan s'applique à un article, ni sur combien d'unités
-- contrôler. Après : le plan applicable, la taille de l'échantillon et le
-- verdict d'un point sont calculés.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '662', false);
DELETE FROM _audit_results WHERE file = '662';

CREATE OR REPLACE FUNCTION _mk662(p_nom text, OUT t uuid, OUT p uuid, OUT generique uuid, OUT specifique uuid) LANGUAGE plpgsql AS $$
BEGIN
  t := _mk_tenant(p_nom, false);
  INSERT INTO products (tenant_id, name, sku, type, cost_price) VALUES (t, 'Art ' || p_nom, 'SKU-' || p_nom, 'stock', 10) RETURNING id INTO p;
  INSERT INTO quality_control_plans (tenant_id, product_id, name, is_active, sampling_method, sampling_rate)
    VALUES (t, NULL, 'Générique ' || p_nom, true, 'systematic', 100) RETURNING id INTO generique;
  INSERT INTO quality_control_plans (tenant_id, product_id, name, is_active, sampling_method, sampling_rate)
    VALUES (t, p, 'Article ' || p_nom, true, 'rate', 10) RETURNING id INTO specifique;
END $$;

-- T01 — sans plan, aucun plan ne s'applique
DO $$
DECLARE t uuid; p uuid; g uuid; s uuid; n bigint;
BEGIN
  SELECT * INTO t, p, g, s FROM _mk662('VAL662T01');
  DELETE FROM quality_control_plans WHERE tenant_id = t;
  SELECT count(*) INTO n FROM quality_plan_for(p);
  PERFORM _rec('T01', 'sans plan, aucun plan ne s''applique', (n = 0), format('plans trouvés = %s (0)', n));
END $$;

-- T02 — le plan générique s'applique à tout article
DO $$
DECLARE t uuid; p uuid; g uuid; s uuid; r record;
BEGIN
  SELECT * INTO t, p, g, s FROM _mk662('VAL662T02');
  DELETE FROM quality_control_plans WHERE id = s;
  SELECT * INTO r FROM quality_plan_for(p);
  PERFORM _rec('T02', 'le plan générique s''applique à tout article (is_product_specific = false)',
    (r.plan_id = g AND r.is_product_specific = false),
    format('plan=%s, spécifique=%s (générique / false)', r.plan_id = g, r.is_product_specific));
END $$;

-- T03 — le plan de l'article gagne sur le générique
DO $$
DECLARE t uuid; p uuid; g uuid; s uuid; r record;
BEGIN
  SELECT * INTO t, p, g, s FROM _mk662('VAL662T03');
  SELECT * INTO r FROM quality_plan_for(p);
  PERFORM _rec('T03', 'le plan de l''article gagne sur le plan générique',
    (r.plan_id = s AND r.is_product_specific = true),
    format('plan=%s, spécifique=%s (article / true)', r.plan_id = s, r.is_product_specific));
END $$;

-- T04 — l'échantillonnage : un pourcentage, ou tout le lot
DO $$
DECLARE t uuid; p uuid; g uuid; s uuid; v_rate numeric; v_sys numeric;
BEGIN
  SELECT * INTO t, p, g, s FROM _mk662('VAL662T04');
  v_rate := quality_sample_size(s, 250);   -- 10 % de 250 = 25
  v_sys  := quality_sample_size(g, 250);   -- systématique = tout le lot
  PERFORM _rec('T04', 'échantillonnage : 10 % de 250 = 25, et « systématique » = tout le lot',
    (v_rate = 25 AND v_sys = 250),
    format('rate=%s (25), systematic=%s (250)', v_rate, v_sys));
END $$;

-- T05 — le verdict d'un point : mesure hors tolérance, et point visuel
DO $$
DECLARE t uuid; p uuid; g uuid; s uuid; pt uuid; vis uuid; ok_dans boolean; ok_hors boolean; ok_vis boolean;
BEGIN
  SELECT * INTO t, p, g, s FROM _mk662('VAL662T05');
  INSERT INTO quality_control_points (tenant_id, plan_id, name, check_type, tolerance_min, tolerance_max, unit)
    VALUES (t, g, 'Épaisseur', 'measure', 9.5, 10.5, 'mm') RETURNING id INTO pt;
  INSERT INTO quality_control_points (tenant_id, plan_id, name, check_type)
    VALUES (t, g, 'Aspect', 'visual') RETURNING id INTO vis;
  ok_dans := (evaluate_quality_point(pt, 10) ->> 'ok')::boolean;
  ok_hors := (evaluate_quality_point(pt, 11) ->> 'ok')::boolean;
  ok_vis  := (evaluate_quality_point(vis, 1) ->> 'ok')::boolean;
  PERFORM _rec('T05', 'un point « mesure » juge la tolérance, un point « visuel » constate la saisie',
    (ok_dans AND NOT ok_hors AND ok_vis),
    format('dans=%s (true), hors=%s (false), visuel=%s (true)', ok_dans, ok_hors, ok_vis));
END $$;

SELECT _audit_assert('662');
