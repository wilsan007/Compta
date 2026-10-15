-- ============================================================
-- 664_tenant_guard_mrp_capacity.sql — R3 / ISO-01 (partie E)
-- Numéro pris le 2026-10-11 par migration-numero.mjs (ligne « plan6 E (opérations) », branche plan6/e-operations).
--
-- DEUX VRAIS TROUS DE SÉCURITÉ, trouvés par la CI le jour où elle a enfin
-- tourné sur la branche (R3). Le contrôle `ci/check_tenant_guard.sql` refuse une
-- fonction `SECURITY DEFINER`, exécutable par `authenticated`, prenant un `uuid`
-- et agissant au nom d’une société **sans vérifier que l’appelant en est membre**.
-- Deux fonctions de cette partie échouaient :
--
--   • `work_center_capacity(p_tenant, p_work_center, p_day)` (657) — lisait le
--     calendrier et la capacité d’un centre de charge d’une AUTRE société :
--     `p_tenant` venait du client. N’importe quel utilisateur connecté pouvait
--     sonder l’atelier d’une société voisine.
--
--   • `run_mrp(p_tenant_id, …)` (651) — pire : sa société venait du PARAMÈTRE
--     (`COALESCE(p_tenant_id, current_tenant_id())`, dans cet ordre). Le contrôle
--     retire précisément ce motif avant d’analyser — parce qu’une garde que
--     l’appelant peut écraser n’en est pas une. On pouvait donc demander le MRP
--     d’une autre société et lire ses besoins, ses stocks et ses commandes.
--
-- Les deux sont recréées ici avec une garde **qui ne dépend pas du paramètre** :
-- la société du contexte l’emporte, et un paramètre étranger lève.
--
-- Forme choisie : une migration de correction (comme la 658 pour
-- `distribute_landed_cost`), pas une réécriture de 651/657 — une migration
-- publiée reste lisible telle qu’elle a été jouée.
-- ============================================================
CREATE OR REPLACE FUNCTION run_mrp(
  p_tenant_id uuid DEFAULT NULL,
  p_horizon_days int DEFAULT 90,
  p_consume_forecast boolean DEFAULT true,
  p_consumption_window_days int DEFAULT 0
)
RETURNS TABLE(
  product_id uuid,
  product_name text,
  gross_need numeric,
  stock_available numeric,
  open_purchase_qty numeric,
  open_production_qty numeric,
  net_need numeric,
  suggested_qty numeric,
  suggested_date date,
  low_level_code int,
  source text,
  need_date date,
  is_late boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := COALESCE(current_tenant_id(), p_tenant_id);
  v_horizon date := CURRENT_DATE + p_horizon_days;
BEGIN
  -- ISO-01 — garde de société. La société venait du PARAMÈTRE
  -- (`COALESCE(p_tenant_id, current_tenant_id())`) : l'appelant connecté
  -- pouvait donc demander le MRP d'une AUTRE société et lire ses besoins, ses
  -- stocks et ses commandes. Trouvé par `ci/check_tenant_guard.sql` le
  -- 11/10/2026, dès que la CI a tourné sur cette branche (R3) — les suites
  -- étaient vertes, la porte était fermée.
  IF current_tenant_id() IS NOT NULL
     AND p_tenant_id IS NOT NULL
     AND p_tenant_id <> current_tenant_id() THEN
    RAISE EXCEPTION 'Société % hors de votre périmètre', p_tenant_id;
  END IF;
  DROP TABLE IF EXISTS _mrp_needs;
  CREATE TEMP TABLE _mrp_needs AS
  SELECT
    exp.product_id,
    exp.gross_need,
    exp.low_level_code,
    mo.start_date AS need_date,
    'manufacturing_order' AS source
  FROM manufacturing_orders mo
  CROSS JOIN LATERAL explode_bom_recursive(v_tid, mo.bom_id, mo.quantity) exp
  WHERE mo.tenant_id = v_tid AND mo.status IN ('planned', 'in_progress');

  IF p_consume_forecast THEN
    -- Prévisions NETTES : la commande ferme de la période consomme la prévision.
    INSERT INTO _mrp_needs
    SELECT
      pf.product_id,
      GREATEST(0, pf.forecasted_quantity - COALESCE(firm.qty, 0)) AS gross_need,
      0 AS low_level_code,
      pf.start_date AS need_date,
      'forecast' AS source
    FROM production_forecasts pf
    LEFT JOIN LATERAL (
      SELECT SUM(sol.quantity) AS qty
      FROM sales_orders so
      JOIN sales_order_lines sol ON sol.sales_order_id = so.id AND sol.tenant_id = v_tid
      WHERE so.tenant_id = v_tid
        AND so.status IN ('confirmed', 'in_progress')
        AND sol.product_id = pf.product_id
        AND COALESCE(so.delivery_date, CURRENT_DATE)
            BETWEEN (COALESCE(pf.start_date, CURRENT_DATE) - p_consumption_window_days)
                AND (COALESCE(pf.end_date, pf.start_date, CURRENT_DATE) + p_consumption_window_days)
    ) firm ON true
    WHERE pf.tenant_id = v_tid
      AND COALESCE(pf.start_date, CURRENT_DATE) <= v_horizon;

    -- Commandes fermes NON consommées par une prévision (hors de toute fenêtre).
    INSERT INTO _mrp_needs
    SELECT
      sol.product_id,
      sol.quantity AS gross_need,
      0 AS low_level_code,
      so.delivery_date AS need_date,
      'sales_order' AS source
    FROM sales_orders so
    JOIN sales_order_lines sol ON sol.sales_order_id = so.id AND sol.tenant_id = v_tid
    WHERE so.tenant_id = v_tid AND so.status IN ('confirmed', 'in_progress')
      AND COALESCE(so.delivery_date, CURRENT_DATE) <= v_horizon
      AND NOT EXISTS (
        SELECT 1 FROM production_forecasts pf
        WHERE pf.tenant_id = v_tid
          AND pf.product_id = sol.product_id
          AND COALESCE(so.delivery_date, CURRENT_DATE)
              BETWEEN (COALESCE(pf.start_date, CURRENT_DATE) - p_consumption_window_days)
                  AND (COALESCE(pf.end_date, pf.start_date, CURRENT_DATE) + p_consumption_window_days)
      );
  ELSE
    -- Politique brute (comportement d'avant) : besoins + prévisions s'additionnent.
    INSERT INTO _mrp_needs
    SELECT
      sol.product_id,
      sol.quantity AS gross_need,
      0 AS low_level_code,
      so.delivery_date AS need_date,
      'sales_order' AS source
    FROM sales_orders so
    JOIN sales_order_lines sol ON sol.sales_order_id = so.id AND sol.tenant_id = v_tid
    WHERE so.tenant_id = v_tid AND so.status IN ('confirmed', 'in_progress')
      AND COALESCE(so.delivery_date, CURRENT_DATE) <= v_horizon;

    INSERT INTO _mrp_needs
    SELECT
      pf.product_id,
      pf.forecasted_quantity AS gross_need,
      0 AS low_level_code,
      pf.start_date AS need_date,
      'forecast' AS source
    FROM production_forecasts pf
    WHERE pf.tenant_id = v_tid
      AND COALESCE(pf.start_date, CURRENT_DATE) <= v_horizon;
  END IF;

  RETURN QUERY
  WITH aggregated_needs AS (
    SELECT
      n.product_id,
      SUM(n.gross_need) AS total_gross_need,
      MAX(n.low_level_code) AS low_level_code,
      MIN(n.need_date) AS earliest_need_date
    FROM _mrp_needs n
    GROUP BY n.product_id
  ),
  stock_info AS (
    SELECT sq.product_id, COALESCE(SUM(sq.quantity), 0) AS stock_qty
    FROM stock_quantities sq
    WHERE sq.tenant_id = v_tid
    GROUP BY sq.product_id
  ),
  open_po AS (
    SELECT
      pol.product_id,
      SUM(pol.quantity - COALESCE(grl.qty_received, 0)) AS open_qty
    FROM purchase_order_lines pol
    JOIN purchase_orders po ON po.id = pol.purchase_order_id AND po.tenant_id = pol.tenant_id
    LEFT JOIN LATERAL (
      SELECT SUM(grl2.quantity_received) AS qty_received
      FROM goods_receipt_lines grl2
      JOIN goods_receipts gr ON gr.id = grl2.goods_receipt_id AND gr.tenant_id = grl2.tenant_id
      WHERE gr.purchase_order_id = po.id
        AND gr.tenant_id = v_tid
        AND grl2.product_id = pol.product_id
        AND gr.status = 'received'
    ) grl ON true
    WHERE po.tenant_id = v_tid AND po.status IN ('draft', 'sent')
    GROUP BY pol.product_id
  ),
  open_mo AS (
    SELECT
      mo.product_id,
      SUM(mo.quantity - COALESCE(mo.qty_produced, 0)) AS open_qty
    FROM manufacturing_orders mo
    WHERE mo.tenant_id = v_tid AND mo.status IN ('planned', 'in_progress')
    GROUP BY mo.product_id
  )
  SELECT
    a.product_id,
    p.name AS product_name,
    a.total_gross_need AS gross_need,
    COALESCE(s.stock_qty, 0) AS stock_available,
    COALESCE(po.open_qty, 0) AS open_purchase_qty,
    COALESCE(mo.open_qty, 0) AS open_production_qty,
    GREATEST(0, a.total_gross_need + COALESCE(p.safety_stock, 0) - COALESCE(s.stock_qty, 0) - COALESCE(po.open_qty, 0) - COALESCE(mo.open_qty, 0)) AS net_need,
    CASE
      WHEN GREATEST(0, a.total_gross_need + COALESCE(p.safety_stock, 0) - COALESCE(s.stock_qty, 0) - COALESCE(po.open_qty, 0) - COALESCE(mo.open_qty, 0)) > 0
      THEN GREATEST(
        CEIL(GREATEST(0, a.total_gross_need + COALESCE(p.safety_stock, 0) - COALESCE(s.stock_qty, 0) - COALESCE(po.open_qty, 0) - COALESCE(mo.open_qty, 0)) / COALESCE(p.qty_multiple, 1)) * COALESCE(p.qty_multiple, 1),
        COALESCE(p.min_order_qty, 0)
      )
      ELSE 0
    END AS suggested_qty,
    CASE
      WHEN a.earliest_need_date IS NOT NULL
      THEN (a.earliest_need_date - COALESCE(p.lead_time_days, 7))
      ELSE (CURRENT_DATE + COALESCE(p.lead_time_days, 7))
    END::date AS suggested_date,
    a.low_level_code,
    'mrp'::text AS source,
    a.earliest_need_date,
    CASE
      WHEN a.earliest_need_date IS NOT NULL
       AND (a.earliest_need_date - COALESCE(p.lead_time_days, 7)) < CURRENT_DATE
      THEN true
      ELSE false
    END AS is_late
  FROM aggregated_needs a
  JOIN products p ON p.id = a.product_id AND p.tenant_id = v_tid
  LEFT JOIN stock_info s ON s.product_id = a.product_id
  LEFT JOIN open_po po ON po.product_id = a.product_id
  LEFT JOIN open_mo mo ON mo.product_id = a.product_id
  WHERE a.total_gross_need > 0
  ORDER BY a.low_level_code, a.product_id;

  DROP TABLE IF EXISTS _mrp_needs;
END;
$$;

-- ────────────────────────────────────────────────────────────
-- 2. run_mrp (651) — la société vient du contexte, plus du client
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION work_center_capacity(
  p_tenant uuid,
  p_work_center uuid,
  p_day date
)
RETURNS numeric
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_cal record;
  v_cap numeric;
BEGIN
  -- ISO-01 — garde de société. Sans elle, cette fonction lit le calendrier et
  -- la capacité d'un centre de charge d'une AUTRE société : `p_tenant` vient du
  -- client (RPC PostgREST). Trouvé par `ci/check_tenant_guard.sql` le 11/10/2026.
  IF current_tenant_id() IS NOT NULL AND p_tenant <> current_tenant_id() THEN
    RAISE EXCEPTION 'Société % hors de votre périmètre', p_tenant;
  END IF;
  IF p_tenant IS NULL OR p_work_center IS NULL OR p_day IS NULL THEN
    RETURN 0;
  END IF;

  SELECT * INTO v_cal FROM work_center_calendars c
  WHERE c.tenant_id = p_tenant AND c.work_center_id = p_work_center AND c.date = p_day
  LIMIT 1;
  IF FOUND THEN
    IF COALESCE(v_cal.is_closed, false) OR COALESCE(v_cal.is_holiday, false) THEN
      RETURN 0;
    END IF;
    RETURN COALESCE(v_cal.available_hours, 0);
  END IF;

  SELECT COALESCE(wc.capacity_hours_per_day, 0) INTO v_cap FROM work_centers wc
  WHERE wc.id = p_work_center AND wc.tenant_id = p_tenant;
  RETURN COALESCE(v_cap, 0);
END $fn$;
-- ────────────────────────────────────────────────────────────
-- Droits — une fonction recréée retrouve les droits de l’ancienne, on les
-- réaffirme pour que le contrôle de garde l’examine (228, 152).
-- ────────────────────────────────────────────────────────────
REVOKE ALL ON FUNCTION run_mrp(uuid, integer, boolean, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION run_mrp(uuid, integer, boolean, integer) TO authenticated;
REVOKE ALL ON FUNCTION work_center_capacity(uuid, uuid, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION work_center_capacity(uuid, uuid, date) TO authenticated;

COMMENT ON FUNCTION work_center_capacity(uuid, uuid, date) IS
  'PRD-07 (657) : heures disponibles d’un centre de charge pour un jour — calendrier s’il existe, sinon capacité par défaut. Garde de société (664).';
COMMENT ON FUNCTION run_mrp(uuid, int, boolean, int) IS
  'PRD-03 (651) : calcul des besoins nets. La société vient du contexte d’appel, jamais du paramètre (664).';