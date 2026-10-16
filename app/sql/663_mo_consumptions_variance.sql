-- ============================================================
-- 663_mo_consumptions_variance.sql — PRD-06 / E.5 (partie E)
-- Numéro pris le 2026-10-11 par migration-numero.mjs (ligne « plan6 E (opérations) », branche plan6/e-operations).
--
-- `mo_consumptions` était la dernière **coquille** de PRD-06 : prévu vs réel,
-- matière par matière, sur un OF. Les deux moitiés existaient déjà séparément —
-- `manufacturing_requirements` (`302`) donne le **prévu** (nomenclature
-- explosée sur tous les niveaux), les mouvements de stock
-- (`reference_type = 'production'`) donnent le **réel** — mais **rien ne les
-- confrontait** : l'écart de matière ne se lisait nulle part.
--
-- On les branche :
--   · `refresh_mo_consumptions(of)` — recalcule et **fige** la comparaison, une
--     ligne par composant. Rejouable : on met à jour, on ne double pas ;
--   · `mo_consumption_variance(of)` — la lecture : prévu, réel, écart, écart %.
--
-- Les écarts **ne bougent aucun stock** : on ne fait que constater. Le réel
-- vient des mouvements, qui restent la seule vérité du stock.
-- ============================================================

-- Une ligne par (OF, composant). L'index unique est ce qui rend le
-- rafraîchissement **rejouable**. On nettoie d'abord d'éventuels doublons
-- laissés par une exécution antérieure, sinon l'index refuserait de se créer.
DELETE FROM public.mo_consumptions c
USING public.mo_consumptions d
WHERE c.id <> d.id
  AND c.tenant_id = d.tenant_id
  AND c.manufacturing_order_id = d.manufacturing_order_id
  AND c.product_id = d.product_id
  AND c.created_at > d.created_at;

CREATE UNIQUE INDEX IF NOT EXISTS mo_consumptions_mo_product_key
  ON public.mo_consumptions (tenant_id, manufacturing_order_id, product_id);

CREATE OR REPLACE FUNCTION public.refresh_mo_consumptions(p_mo_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tenant uuid := current_tenant_id();
  v_trouve boolean;
  v_n integer := 0;
BEGIN
  IF v_tenant IS NULL THEN
    RAISE EXCEPTION 'Tenant introuvable';
  END IF;

  SELECT true INTO v_trouve
  FROM public.manufacturing_orders
  WHERE id = p_mo_id AND tenant_id = v_tenant;

  IF v_trouve IS NULL THEN
    RAISE EXCEPTION 'OF introuvable';
  END IF;

  INSERT INTO public.mo_consumptions (
    tenant_id, manufacturing_order_id, product_id,
    theoretical_quantity, actual_quantity
  )
  SELECT
    v_tenant,
    p_mo_id,
    r.product_id,
    -- Le prévu : la nomenclature explosée, pour la quantité LANCÉE.
    r.quantity,
    -- Le réel : ce qui est réellement sorti du stock pour cet OF.
    COALESCE((
      SELECT sum(m.quantity)
      FROM public.stock_movements m
      WHERE m.tenant_id = v_tenant
        AND m.reference_type = 'production'
        AND m.reference_id = p_mo_id
        AND m.product_id = r.product_id
        AND m.movement_type = 'out'
    ), 0)
  FROM public.manufacturing_requirements(p_mo_id, v_tenant) r
  ON CONFLICT (tenant_id, manufacturing_order_id, product_id)
  DO UPDATE SET
    theoretical_quantity = EXCLUDED.theoretical_quantity,
    actual_quantity      = EXCLUDED.actual_quantity;

  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END $$;

CREATE OR REPLACE FUNCTION public.mo_consumption_variance(p_mo_id uuid)
RETURNS TABLE (
  product_id uuid,
  product_name text,
  theoretical_quantity numeric,
  actual_quantity numeric,
  variance_quantity numeric,
  variance_percent numeric
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT c.product_id,
         COALESCE(p.name, '—'),
         c.theoretical_quantity,
         c.actual_quantity,
         c.variance_quantity,
         CASE WHEN c.theoretical_quantity <> 0
              THEN round(c.variance_quantity * 100 / c.theoretical_quantity, 2)
              ELSE NULL END
  FROM public.mo_consumptions c
  LEFT JOIN public.products p ON p.id = c.product_id AND p.tenant_id = c.tenant_id
  WHERE c.manufacturing_order_id = p_mo_id
    AND c.tenant_id = current_tenant_id()
  ORDER BY abs(c.variance_quantity) DESC, p.name;
$$;

COMMENT ON FUNCTION public.refresh_mo_consumptions(uuid) IS
  'PRD-06 (663) : fige le prévu (nomenclature explosée) contre le réel (mouvements de production) pour un OF.';
COMMENT ON FUNCTION public.mo_consumption_variance(uuid) IS
  'PRD-06 (663) : écart de matière d''un OF — prévu, réel, écart et écart en %.';

REVOKE ALL ON FUNCTION public.refresh_mo_consumptions(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.mo_consumption_variance(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.refresh_mo_consumptions(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mo_consumption_variance(uuid) TO authenticated;

