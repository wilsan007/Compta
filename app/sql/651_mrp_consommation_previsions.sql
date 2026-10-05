-- ============================================================
-- 651_mrp_consommation_previsions.sql — PRD-03 (partie E)
--
-- DÉCISION : la politique de consommation des prévisions.
--
-- Le moteur `run_mrp` (152) lit déjà trois sources — OF, commandes clients,
-- prévisions — et les ADDITIONNE. C'est un double comptage : une commande
-- ferme est comptée une fois comme commande et une fois dans la prévision de la
-- période. Le plan l'avait écrit (« nettes des commandes fermes de la période
-- pour éviter le double comptage »).
--
-- La pratique des leaders, mot pour mot :
--   · Sage  : « consommation des prévisions » — les commandes fermes consomment
--             la prévision de la période ;
--   · Odoo  : « consume forecast » — une commande ferme réduit la prévision de
--             la même période (fenêtre d'un seau, prolongeable à un seau voisin) ;
--   · SAP   : consumption of forecast (réduction de la prévision par les
--             commandes fermes dans le « planning time fence »).
--
-- Ce fichier ajoute deux paramètres, avec un défaut qui change le comportement
-- au plus juste :
--   · p_consume_forecast boolean DEFAULT true   — la politique standard ;
--   · p_consumption_window_days int DEFAULT 0   — jours de tolérance autour du
--     seau de prévision (0 = la période exacte ; les leaders laissent le choix).
--
-- Règle appliquée quand p_consume_forecast = true :
--   · une prévision vaut  max(0, prévision − commandes fermes de SA fenêtre) ;
--   · une commande ferme tombant dans la fenêtre d'une prévision n'est PAS
--     ajoutée séparément (elle a déjà consommé la prévision) ;
--   · une commande ferme hors de toute fenêtre de prévision reste un besoin.
-- Quand p_consume_forecast = false, on retrouve le comportement d'avant
-- (besoins + prévisions s'additionnent) — c'est la porte de non-régression.
--
-- Mesuré AVANT (politique historique) : prévision 100 + commande 40 = 140.
-- Après : 60 (la commande a consommé la prévision), et 140 si l'on remet
-- p_consume_forecast := false.
-- ============================================================

-- La 152 exposait `run_mrp(uuid, integer)`. Ajouter des paramètres CRÉE une
-- surcharge, il ne remplace pas la fonction : sans ce DROP, DEUX `run_mrp`
-- coexistent et l'appel à deux arguments devient ambigu
-- (« function run_mrp(uuid, integer) is not unique »). Leçon de la 316, qui a
-- fait le même DROP pour `calculate_stock_valuation`.
DROP FUNCTION IF EXISTS run_mrp(uuid, integer);

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
  v_tid uuid := COALESCE(p_tenant_id, current_tenant_id());
  v_horizon date := CURRENT_DATE + p_horizon_days;
BEGIN
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

COMMENT ON FUNCTION run_mrp(uuid, int, boolean, int) IS
  'PRD-03 (651) : calcul des besoins nets. Sources : OF, commandes clients confirmées, prévisions. p_consume_forecast (défaut true) applique la consommation des prévisions (Sage/Odoo) : une commande ferme de la période réduit la prévision et n''est pas comptée deux fois. p_consumption_window_days élargit la fenêtre de consommation de part et d''autre.';

-- ─────────────────────────────────────────────────────────────
-- Droits — une fonction recréée n'a plus les droits de l'ancienne (228, 152).
-- Une fonction neuve reçoit EXECUTE par défaut à PUBLIC : on le retire.
-- ─────────────────────────────────────────────────────────────
REVOKE ALL ON FUNCTION run_mrp(uuid, integer, boolean, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION run_mrp(uuid, integer, boolean, integer) TO authenticated;
