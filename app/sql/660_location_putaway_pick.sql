-- ============================================================
-- 660_location_putaway_pick.sql — STK-11 / E.3 (partie E)
-- Numéro pris le 2026-10-11 par migration-numero.mjs (ligne « plan6 E (opérations) », branche plan6/e-operations).
--
-- Rangement (*put-away*) et prélèvement (*removal*) — les deux règles du plan
-- pour un entrepôt :
--   · `suggest_putaway_location` : où ranger un article reçu — d'abord un casier
--     qui le contient **déjà** (on regroupe), sinon un casier de type `storage`
--     vide, sinon le casier de stockage le moins occupé ;
--   · `suggest_pick_location` : où prélever — le casier qui en détient **le plus**
--     (on ne disperse pas les prélèvements).
-- Elles s'appuient sur les affectations de la 659 (`stock_location_assignments`).
-- ============================================================

CREATE OR REPLACE FUNCTION suggest_putaway_location(p_product_id uuid, p_warehouse_id uuid)
RETURNS TABLE(location_id uuid, location_code text, reason text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH locs AS (
    SELECT l.id, l.code,
           (SELECT COALESCE(SUM(a.quantity), 0) FROM stock_location_assignments a
             WHERE a.tenant_id = l.tenant_id AND a.location_id = l.id AND a.product_id = p_product_id) AS holds_product,
           (SELECT COUNT(*) FROM stock_location_assignments a
             WHERE a.tenant_id = l.tenant_id AND a.location_id = l.id) AS nb_assignments
    FROM warehouse_locations l
    WHERE l.tenant_id = current_tenant_id()
      AND l.warehouse_id = p_warehouse_id
      AND COALESCE(l.location_type, 'storage') = 'storage'
  )
  SELECT id, code,
         CASE WHEN holds_product > 0 THEN 'consolidate'
              WHEN nb_assignments = 0 THEN 'empty'
              ELSE 'least_loaded' END AS reason
  FROM locs
  ORDER BY (holds_product > 0) DESC, (nb_assignments = 0) DESC, nb_assignments ASC, code
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION suggest_pick_location(p_product_id uuid, p_warehouse_id uuid)
RETURNS TABLE(location_id uuid, location_code text, quantity numeric)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT a.location_id, l.code, a.quantity
  FROM stock_location_assignments a
  JOIN warehouse_locations l ON l.id = a.location_id AND l.tenant_id = a.tenant_id
  WHERE a.tenant_id = current_tenant_id()
    AND a.product_id = p_product_id
    AND a.warehouse_id = p_warehouse_id
    AND a.quantity > 0
  ORDER BY a.quantity DESC, l.code
  LIMIT 1;
$$;

COMMENT ON FUNCTION suggest_putaway_location(uuid, uuid) IS
  'STK-11 (660) : où ranger un article reçu — casier qui le contient déjà, sinon casier de stockage vide, sinon le moins occupé.';
COMMENT ON FUNCTION suggest_pick_location(uuid, uuid) IS
  'STK-11 (660) : où prélever un article — le casier qui en détient le plus.';

REVOKE ALL ON FUNCTION suggest_putaway_location(uuid, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION suggest_pick_location(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION suggest_putaway_location(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION suggest_pick_location(uuid, uuid) TO authenticated;

