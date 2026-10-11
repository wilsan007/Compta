-- ============================================================
-- 659_stock_location_assignments.sql — STK-11 / E.3 (partie E)
-- Numéro pris le 2026-10-11 par migration-numero.mjs (ligne « plan6 E (opérations) », branche plan6/e-operations).
--
-- Décision — **le moteur de mouvement reste INCHANGÉ.** Le stock d'un entrepôt
-- reste la vérité de `stock_quantities` (une ligne par article et par dépôt) : ce
-- moteur porte le CUMP, les déclencheurs et leur ordre, et le toucher mettrait en
-- jeu **tout** le stock. Le **casier** est une **affectation** d'une partie de ce
-- stock : une table qui dit « tant de cet article est au casier B3 ».
--   · la somme des affectations d'un couple (article, dépôt) ne peut **pas**
--     dépasser le stock du dépôt — refus explicite sinon ;
--   · `location_stock()` rend la ventilation : chaque casier, plus la part
--     **non affectée** (`location_id` NULL) — et la somme vaut le stock d'entrepôt.
-- C'est le critère STK-11 (« le stock d'un article se ventile par emplacement et
-- la somme est égale au stock entrepôt »), **sans risque** pour le stock existant.
-- ============================================================

CREATE TABLE IF NOT EXISTS stock_location_assignments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  product_id uuid NOT NULL,
  warehouse_id uuid NOT NULL,
  location_id uuid NOT NULL,
  quantity numeric NOT NULL DEFAULT 0 CHECK (quantity >= 0),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE (product_id, warehouse_id, location_id)
);

ALTER TABLE stock_location_assignments ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS stock_location_assignments_tenant ON stock_location_assignments;
CREATE POLICY stock_location_assignments_tenant ON stock_location_assignments
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

-- Clés étrangères composites (doctrine 237) — posées si les cibles le permettent.
DO $$ BEGIN
  ALTER TABLE stock_location_assignments
    ADD CONSTRAINT sla_location_fk FOREIGN KEY (location_id, tenant_id)
    REFERENCES warehouse_locations(id, tenant_id) ON DELETE CASCADE;
EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN
  ALTER TABLE stock_location_assignments
    ADD CONSTRAINT sla_warehouse_fk FOREIGN KEY (warehouse_id, tenant_id)
    REFERENCES warehouses(id, tenant_id) ON DELETE CASCADE;
EXCEPTION WHEN others THEN NULL; END $$;

-- Affecte (ou réaffecte) une quantité d'un article à un casier. La somme des
-- affectations d'un couple (article, dépôt) ne peut pas dépasser le stock du dépôt.
CREATE OR REPLACE FUNCTION assign_stock_to_location(
  p_product_id uuid,
  p_warehouse_id uuid,
  p_location_id uuid,
  p_quantity numeric
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_stock numeric := 0;
  v_other numeric := 0;
BEGIN
  IF v_tid IS NULL THEN RAISE EXCEPTION 'Aucun tenant actif'; END IF;
  IF COALESCE(p_quantity, 0) < 0 THEN RAISE EXCEPTION 'Quantité négative'; END IF;

  SELECT COALESCE(SUM(quantity), 0) INTO v_stock FROM stock_quantities
  WHERE tenant_id = v_tid AND product_id = p_product_id AND warehouse_id = p_warehouse_id;

  SELECT COALESCE(SUM(quantity), 0) INTO v_other FROM stock_location_assignments
  WHERE tenant_id = v_tid AND product_id = p_product_id AND warehouse_id = p_warehouse_id
    AND location_id <> p_location_id;

  IF v_other + COALESCE(p_quantity, 0) > COALESCE(v_stock, 0) THEN
    RAISE EXCEPTION 'Affectation refusée : % (autres casiers) + % dépasse le stock du dépôt (%)',
      v_other, COALESCE(p_quantity, 0), COALESCE(v_stock, 0);
  END IF;

  INSERT INTO stock_location_assignments (tenant_id, product_id, warehouse_id, location_id, quantity)
  VALUES (v_tid, p_product_id, p_warehouse_id, p_location_id, COALESCE(p_quantity, 0))
  ON CONFLICT (product_id, warehouse_id, location_id)
  DO UPDATE SET quantity = EXCLUDED.quantity, updated_at = now();
END $$;

-- La ventilation du stock : chaque casier, plus la part non affectée.
CREATE OR REPLACE FUNCTION location_stock(p_warehouse_id uuid DEFAULT NULL)
RETURNS TABLE(
  product_id uuid,
  product_name text,
  warehouse_id uuid,
  location_id uuid,
  location_code text,
  quantity numeric,
  assigned boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH assigned AS (
    SELECT a.product_id, a.warehouse_id, a.location_id, a.quantity
    FROM stock_location_assignments a
    WHERE a.tenant_id = current_tenant_id()
      AND (p_warehouse_id IS NULL OR a.warehouse_id = p_warehouse_id)
  ),
  unassigned AS (
    SELECT sq.product_id, sq.warehouse_id, NULL::uuid AS location_id,
           GREATEST(COALESCE(sq.quantity, 0) - COALESCE((
             SELECT SUM(x.quantity) FROM assigned x
             WHERE x.product_id = sq.product_id AND x.warehouse_id = sq.warehouse_id
           ), 0), 0) AS quantity
    FROM stock_quantities sq
    WHERE sq.tenant_id = current_tenant_id()
      AND (p_warehouse_id IS NULL OR sq.warehouse_id = p_warehouse_id)
  )
  SELECT u.product_id, p.name AS product_name, u.warehouse_id, u.location_id,
         wl.code AS location_code, u.quantity, (u.location_id IS NOT NULL) AS assigned
  FROM (SELECT * FROM assigned UNION ALL SELECT * FROM unassigned) u
  JOIN products p ON p.id = u.product_id AND p.tenant_id = current_tenant_id()
  LEFT JOIN warehouse_locations wl ON wl.id = u.location_id AND wl.tenant_id = current_tenant_id()
  WHERE u.quantity > 0
  ORDER BY p.name, wl.code NULLS FIRST;
$$;

COMMENT ON FUNCTION assign_stock_to_location(uuid, uuid, uuid, numeric) IS
  'STK-11 (659) : affecte une quantité d''un article à un casier. La somme des affectations d''un couple (article, dépôt) ne peut pas dépasser le stock du dépôt.';
COMMENT ON FUNCTION location_stock(uuid) IS
  'STK-11 (659) : le stock ventilé par casier (et la part non affectée). La somme des lignes vaut le stock d''entrepôt.';

REVOKE ALL ON FUNCTION assign_stock_to_location(uuid, uuid, uuid, numeric) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION location_stock(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION assign_stock_to_location(uuid, uuid, uuid, numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION location_stock(uuid) TO authenticated;


