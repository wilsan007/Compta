-- ============================================================
-- 655_stock_by_location.sql — STK-11 / E.3 (partie E)
-- Numéro pris le 2026-10-05 par migration-numero.mjs (ligne « plan6 E (opérations) », branche plan6/e-operations).
--
-- Constat : `warehouse_locations` porte déjà l'arbre (`parent_id`), le type
-- (`location_type`) et la capacité (`max_weight`/`max_volume`/`max_pallets`), et
-- `stock_quantities.location_id` existe — mais **rien ne ventile le stock par
-- emplacement** : le stock est connu à l'entrepôt, jamais au casier.
--
-- Décision : une fonction de lecture qui ventile le stock par emplacement
-- (location_id NULL = « non affecté », le stock d'entrepôt). C'est le socle du
-- critère STK-11 (« la somme des emplacements = le stock entrepôt »).
-- ============================================================

CREATE OR REPLACE FUNCTION stock_by_location(p_warehouse_id uuid DEFAULT NULL)
RETURNS TABLE(
  product_id uuid,
  product_name text,
  warehouse_id uuid,
  location_id uuid,
  location_code text,
  location_type text,
  quantity numeric
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT
    sq.product_id,
    p.name AS product_name,
    sq.warehouse_id,
    sq.location_id,
    wl.code AS location_code,
    wl.location_type,
    SUM(sq.quantity) AS quantity
  FROM stock_quantities sq
  JOIN products p ON p.id = sq.product_id AND p.tenant_id = sq.tenant_id
  LEFT JOIN warehouse_locations wl ON wl.id = sq.location_id AND wl.tenant_id = sq.tenant_id
  WHERE sq.tenant_id = current_tenant_id()
    AND (p_warehouse_id IS NULL OR sq.warehouse_id = p_warehouse_id)
  GROUP BY sq.product_id, p.name, sq.warehouse_id, sq.location_id, wl.code, wl.location_type
  ORDER BY p.name, wl.code NULLS FIRST;
$$;

COMMENT ON FUNCTION stock_by_location(uuid) IS
  'STK-11 (655) : le stock d''un article ventilé par emplacement (location_id NULL = non affecté). La somme des lignes vaut le stock d''entrepôt.';

REVOKE ALL ON FUNCTION stock_by_location(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION stock_by_location(uuid) TO authenticated;

