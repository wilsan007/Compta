-- ============================================================
-- 653_reorder_suggestions.sql — STK-09 / E.3 (partie E)
-- Numéro pris le 2026-10-05 par migration-numero.mjs (ligne « plan6 E (opérations) », branche plan6/e-operations).
--
-- Constat : `reorder_rules` (produit, dépôt, minimum, maximum, multiple, délai,
-- actif) existe depuis la 125 mais **aucune requête ni fonction ne la lit** — la
-- coquille ORPH-02. L'écran de réappro s'appuie sur `stock_quantities.reorder_point`,
-- un simple seuil, sans maximum ni multiple de conditionnement.
--
-- Décision : une fonction de suggestion, côté base, qui applique la règle réelle —
--   · on ne propose que si le stock est **au niveau minimum ou en dessous** ;
--   · on remonte jusqu'au **maximum** ;
--   · on arrondit au **multiple de conditionnement** (on ne commande pas 43 si le
--     conditionnement est par 5).
-- Le stock lu est celui du dépôt de la règle ; une règle sans dépôt lit le stock
-- total de la société (règle « tous dépôts »).
-- ============================================================

CREATE OR REPLACE FUNCTION reorder_suggestions()
RETURNS TABLE(
  product_id uuid,
  product_name text,
  warehouse_id uuid,
  warehouse_name text,
  stock numeric,
  min_quantity numeric,
  max_quantity numeric,
  suggested_qty numeric
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT
    rr.product_id,
    p.name AS product_name,
    rr.warehouse_id,
    w.name AS warehouse_name,
    COALESCE(s.qty, 0) AS stock,
    rr.min_quantity,
    rr.max_quantity,
    CEIL((rr.max_quantity - COALESCE(s.qty, 0)) / COALESCE(NULLIF(rr.multiple_quantity, 0), 1))
      * COALESCE(NULLIF(rr.multiple_quantity, 0), 1) AS suggested_qty
  FROM reorder_rules rr
  JOIN products p ON p.id = rr.product_id AND p.tenant_id = rr.tenant_id
  LEFT JOIN warehouses w ON w.id = rr.warehouse_id AND w.tenant_id = rr.tenant_id
  LEFT JOIN LATERAL (
    SELECT CASE
      WHEN rr.warehouse_id IS NULL
      THEN (SELECT COALESCE(SUM(sq.quantity), 0) FROM stock_quantities sq
             WHERE sq.tenant_id = rr.tenant_id AND sq.product_id = rr.product_id)
      ELSE (SELECT COALESCE(SUM(sq.quantity), 0) FROM stock_quantities sq
             WHERE sq.tenant_id = rr.tenant_id AND sq.product_id = rr.product_id
               AND sq.warehouse_id = rr.warehouse_id)
    END AS qty
  ) s ON true
  WHERE rr.tenant_id = current_tenant_id()
    AND rr.is_active
    AND COALESCE(s.qty, 0) <= rr.min_quantity
  ORDER BY p.name;
$$;

COMMENT ON FUNCTION reorder_suggestions() IS
  'STK-09 (653) : suggestions de réapprovisionnement à partir de `reorder_rules` — proposées quand le stock est ≤ au minimum, remontées jusqu''au maximum, arrondies au multiple de conditionnement.';

REVOKE ALL ON FUNCTION reorder_suggestions() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION reorder_suggestions() TO authenticated;

