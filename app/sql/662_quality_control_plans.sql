-- ============================================================
-- 662_quality_control_plans.sql — STK-13 / E.5 (partie E)
-- Numéro pris le 2026-10-11 par migration-numero.mjs (ligne « plan6 E (opérations) », branche plan6/e-operations).
--
-- `quality_control_plans` et `quality_control_points` étaient des **coquilles**
-- (depuis la 125) : l'écran `/stock/quality-checks` enregistre bien les
-- *contrôles* (`quality_checks`), mais **rien** ne disait quel contrôle
-- appliquer ni sur combien d'unités. C'est exactement ce que ces deux tables
-- décrivent — on les branche :
--   · `quality_plan_for(article)` — le plan applicable : celui de l'article
--     s'il existe, sinon le plan **générique** (`product_id IS NULL`) ;
--   · `quality_sample_size(plan, quantité du lot)` — la taille de
--     l'échantillon, selon la méthode du plan (`rate` = pourcentage,
--     `systematic`/`table` = tout le lot) ;
--   · `quality_plan_points(plan)` — les points de contrôle du plan ;
--   · `evaluate_quality_point(point, valeur)` — la valeur est-elle dans la
--     tolérance (`measure` / `binary` / `visual`) ?
-- ============================================================

-- Le plan applicable : le plan propre à l'article gagne, sinon le générique.
-- `is_product_specific` dit lequel des deux a répondu — l'écran peut alors
-- annoncer « plan de l'article » ou « plan générique », jamais l'un pour l'autre.
CREATE OR REPLACE FUNCTION public.quality_plan_for(p_product_id uuid)
RETURNS TABLE (
  plan_id uuid,
  plan_name text,
  sampling_method text,
  sampling_rate numeric,
  is_product_specific boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT p.id,
         p.name,
         COALESCE(p.sampling_method, 'systematic'),
         COALESCE(p.sampling_rate, 100),
         (p.product_id IS NOT NULL AND p.product_id = p_product_id)
  FROM public.quality_control_plans p
  WHERE p.tenant_id = current_tenant_id()
    AND COALESCE(p.is_active, true)
    AND (p.product_id = p_product_id OR p.product_id IS NULL)
  ORDER BY (p.product_id IS NOT NULL AND p.product_id = p_product_id) DESC, p.created_at DESC
  LIMIT 1;
$$;

-- La taille de l'échantillon : le plan dit *comment* échantillonner, cette
-- fonction le chiffre. `rate` = un pourcentage du lot ; `systematic` et
-- `table` contrôlent tout le lot (le plan de contrôle détaillé reste à la
-- charge de l'opérateur, on ne l'invente pas).
CREATE OR REPLACE FUNCTION public.quality_sample_size(p_plan_id uuid, p_lot_quantity numeric)
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT CASE
    WHEN COALESCE(p_lot_quantity, 0) <= 0 THEN 0
    WHEN COALESCE(p.sampling_method, 'systematic') = 'rate'
      THEN LEAST(ceil(p_lot_quantity * COALESCE(p.sampling_rate, 100) / 100.0), p_lot_quantity)
    ELSE p_lot_quantity
  END
  FROM public.quality_control_plans p
  WHERE p.id = p_plan_id AND p.tenant_id = current_tenant_id();
$$;

CREATE OR REPLACE FUNCTION public.quality_plan_points(p_plan_id uuid)
RETURNS TABLE (
  point_id uuid,
  point_name text,
  check_type text,
  tolerance_min numeric,
  tolerance_max numeric,
  unit text,
  is_mandatory boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT c.id, c.name, c.check_type, c.tolerance_min, c.tolerance_max, c.unit,
         COALESCE(c.is_mandatory, true)
  FROM public.quality_control_points c
  WHERE c.plan_id = p_plan_id AND c.tenant_id = current_tenant_id()
  ORDER BY COALESCE(c.is_mandatory, true) DESC, c.name;
$$;

-- Évaluer une valeur sur un point : bornes ouvertes quand une tolérance est
-- NULL (une seule borne, ou aucune = « on mesure, on ne juge pas »). Un point
-- `visual` n'a pas de tolérance chiffrée : l'opérateur juge, on ne fait que
-- constater qu'il a saisi quelque chose.
CREATE OR REPLACE FUNCTION public.evaluate_quality_point(p_point_id uuid, p_value numeric)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_point public.quality_control_points%ROWTYPE;
BEGIN
  SELECT * INTO v_point
  FROM public.quality_control_points
  WHERE id = p_point_id AND tenant_id = current_tenant_id();

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Point de contrôle introuvable';
  END IF;

  IF v_point.check_type = 'visual' THEN
    RETURN jsonb_build_object(
      'ok', p_value IS NOT NULL,
      'check_type', 'visual',
      'unit', v_point.unit,
      'value', p_value
    );
  END IF;

  RETURN jsonb_build_object(
    'ok', (v_point.tolerance_min IS NULL OR p_value >= v_point.tolerance_min)
      AND (v_point.tolerance_max IS NULL OR p_value <= v_point.tolerance_max),
    'check_type', v_point.check_type,
    'min', v_point.tolerance_min,
    'max', v_point.tolerance_max,
    'unit', v_point.unit,
    'value', p_value
  );
END $$;

COMMENT ON FUNCTION public.quality_plan_for(uuid) IS
  'STK-13 (662) : le plan de contrôle applicable à un article — le sien, sinon le plan générique.';
COMMENT ON FUNCTION public.quality_sample_size(uuid, numeric) IS
  'STK-13 (662) : taille de l''échantillon selon la méthode du plan (rate = %, systematic/table = tout le lot).';
COMMENT ON FUNCTION public.quality_plan_points(uuid) IS
  'STK-13 (662) : les points de contrôle d''un plan, obligatoires d''abord.';
COMMENT ON FUNCTION public.evaluate_quality_point(uuid, numeric) IS
  'STK-13 (662) : la valeur est-elle dans la tolérance du point ? (measure / binary / visual)';

REVOKE ALL ON FUNCTION public.quality_plan_for(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.quality_sample_size(uuid, numeric) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.quality_plan_points(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.evaluate_quality_point(uuid, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.quality_plan_for(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.quality_sample_size(uuid, numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION public.quality_plan_points(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.evaluate_quality_point(uuid, numeric) TO authenticated;

