-- ============================================================
-- 654_stock_count_cycles_engine.sql — STK-09 / E.3 (partie E)
-- Numéro pris le 2026-10-05 par migration-numero.mjs (ligne « plan6 E (opérations) », branche plan6/e-operations).
--
-- Constat : `stock_count_cycles` (planning de comptage : produit, dépôt, classe
-- A/B/C, fréquence, dernière et prochaine date) existe depuis la 125 mais **aucun
-- moteur ne l'exploite** — coquille ORPH-02. `calculate_inventory_variance` (103)
-- réconcilie le stock théorique et les mouvements ; il ne **compte** pas.
--
-- Décision : deux fonctions.
--   · `generate_count_list()`  : les articles **dus** (prochaine date ≤ aujourd'hui),
--     avec leur stock courant ;
--   · `record_stock_count(id, qty_comptée)` : l'écart (compté − stock) devient un
--     mouvement **valorisé** au CUMP, et les dates du cycle avancent.
--
-- Pourquoi 'in'/'out' et non 'adjustment' : le moteur de mouvement de la base
-- (`update_stock_on_movement`) ne traite 'adjustment' que sur `products.stock_quantity`,
-- **pas** sur `stock_quantities` par dépôt — un écart physique s'enregistre donc
-- comme une **entrée** (excédent) ou une **sortie** (manquant), ce qui met à jour
-- le stock par dépôt, le CUMP et l'écriture (101, 254). C'est aussi ce que la
-- tâche 2.8 a constaté (« la base les enregistre comme entrée ou sortie de l'écart »).
-- ============================================================

CREATE OR REPLACE FUNCTION generate_count_list()
RETURNS TABLE(
  cycle_id uuid,
  product_id uuid,
  product_name text,
  warehouse_id uuid,
  warehouse_name text,
  abc_class text,
  frequency_days int,
  last_count_date date,
  next_count_date date,
  current_stock numeric
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT
    cc.id AS cycle_id,
    cc.product_id,
    p.name AS product_name,
    cc.warehouse_id,
    w.name AS warehouse_name,
    cc.abc_class,
    cc.frequency_days,
    cc.last_count_date,
    cc.next_count_date,
    COALESCE((
      SELECT SUM(sq.quantity) FROM stock_quantities sq
      WHERE sq.tenant_id = cc.tenant_id
        AND sq.product_id = cc.product_id
        AND (cc.warehouse_id IS NULL OR sq.warehouse_id = cc.warehouse_id)
    ), 0) AS current_stock
  FROM stock_count_cycles cc
  JOIN products p ON p.id = cc.product_id AND p.tenant_id = cc.tenant_id
  LEFT JOIN warehouses w ON w.id = cc.warehouse_id AND w.tenant_id = cc.tenant_id
  WHERE cc.tenant_id = current_tenant_id()
    AND cc.is_active
    AND (cc.next_count_date IS NULL OR cc.next_count_date <= CURRENT_DATE)
  ORDER BY cc.abc_class, p.name;
$$;

CREATE OR REPLACE FUNCTION record_stock_count(p_cycle_id uuid, p_counted_qty numeric)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_cc stock_count_cycles%ROWTYPE;
  v_current numeric := 0;
  v_variance numeric;
  v_cost numeric := 0;
  v_wh uuid;
BEGIN
  SELECT * INTO v_cc FROM stock_count_cycles
  WHERE id = p_cycle_id AND tenant_id = v_tid FOR UPDATE;
  IF v_cc.id IS NULL THEN RAISE EXCEPTION 'Comptage introuvable'; END IF;

  SELECT COALESCE(SUM(sq.quantity), 0) INTO v_current
  FROM stock_quantities sq
  WHERE sq.tenant_id = v_tid AND sq.product_id = v_cc.product_id
    AND (v_cc.warehouse_id IS NULL OR sq.warehouse_id = v_cc.warehouse_id);

  v_variance := COALESCE(p_counted_qty, 0) - v_current;

  -- Dépôt du mouvement : celui du comptage, sinon le dépôt qui porte le plus de stock.
  v_wh := v_cc.warehouse_id;
  IF v_wh IS NULL THEN
    SELECT sq.warehouse_id INTO v_wh FROM stock_quantities sq
    WHERE sq.tenant_id = v_tid AND sq.product_id = v_cc.product_id
    ORDER BY sq.quantity DESC LIMIT 1;
  END IF;

  IF v_variance <> 0 THEN
    SELECT COALESCE(sq.unit_cost, 0) INTO v_cost FROM stock_quantities sq
    WHERE sq.tenant_id = v_tid AND sq.product_id = v_cc.product_id
      AND (v_wh IS NULL OR sq.warehouse_id = v_wh)
    ORDER BY sq.quantity DESC LIMIT 1;
    v_cost := COALESCE(v_cost, 0);

    -- Écart physique : entrée (excédent) ou sortie (manquant), valorisée au CUMP.
    INSERT INTO stock_movements
      (tenant_id, product_id, warehouse_id, type, movement_type, quantity, unit_cost,
       date, movement_date, reference_type, reference_id, notes)
    VALUES
      (v_tid, v_cc.product_id, v_wh,
       CASE WHEN v_variance > 0 THEN 'in' ELSE 'out' END,
       CASE WHEN v_variance > 0 THEN 'in' ELSE 'out' END,
       ABS(v_variance), v_cost, CURRENT_DATE, CURRENT_DATE,
       'stock_count', v_cc.id, 'Comptage cyclique — écart ' || v_variance);
  END IF;

  UPDATE stock_count_cycles
  SET last_count_date = CURRENT_DATE,
      next_count_date = CURRENT_DATE + COALESCE(frequency_days, 90)
  WHERE id = p_cycle_id AND tenant_id = v_tid;

  RETURN v_variance;
END;
$$;

COMMENT ON FUNCTION generate_count_list() IS
  'STK-09 (654) : la liste des articles dus au comptage cyclique (prochaine date ≤ aujourd''hui), avec leur stock courant.';
COMMENT ON FUNCTION record_stock_count(uuid, numeric) IS
  'STK-09 (654) : enregistre un comptage physique — l''écart (compté − stock) devient un mouvement valorisé (entrée/sortie), et les dates du cycle avancent. Renvoie l''écart.';

REVOKE ALL ON FUNCTION generate_count_list() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION record_stock_count(uuid, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION generate_count_list() TO authenticated;
GRANT EXECUTE ON FUNCTION record_stock_count(uuid, numeric) TO authenticated;


