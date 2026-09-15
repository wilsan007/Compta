-- ============================================================
-- 111_stock_valuation.sql
-- STK-02 + STK-03 + STK-04 : Valorisation du stock unifiée
--
-- STK-02 : CUMP incrémental (trigger AFTER INSERT)
-- STK-03 : Couches persistantes (stock_valuation_layers) pour FIFO/LIFO
-- STK-04 : Fonction de valorisation unique avec date
-- ============================================================

-- ============================================================
-- STK-02 : Trigger CUMP incrémental
-- ============================================================
DROP FUNCTION IF EXISTS update_cump_on_movement() CASCADE;
CREATE OR REPLACE FUNCTION update_cump_on_movement()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  v_qty numeric;
  v_cost numeric;
  v_new_cump numeric;
BEGIN
  -- Ne traiter que les entrées avec un coût positif
  IF NEW.movement_type NOT IN ('in', 'initial') OR COALESCE(NEW.unit_cost, 0) <= 0 THEN
    RETURN NEW;
  END IF;

  -- Verrouiller la ligne pour sérialiser les entrées concurrentes
  SELECT COALESCE(quantity, 0), COALESCE(unit_cost, 0)
  INTO v_qty, v_cost
  FROM stock_quantities
  WHERE product_id = NEW.product_id AND warehouse_id = NEW.warehouse_id
    AND tenant_id = NEW.tenant_id
  FOR UPDATE;

  -- CUMP = (valeur détenue + valeur entrante) / (quantité détenue + quantité entrante)
  v_new_cump := (v_qty * v_cost + NEW.quantity * NEW.unit_cost)
                / NULLIF(v_qty + NEW.quantity, 0);

  UPDATE stock_quantities
  SET unit_cost = COALESCE(v_new_cump, v_cost)
  WHERE product_id = NEW.product_id AND warehouse_id = NEW.warehouse_id
    AND tenant_id = NEW.tenant_id;

  RETURN NEW;
END;
$$;

-- Trigger CUMP (AFTER INSERT sur stock_movements)
DROP TRIGGER IF EXISTS update_cump ON stock_movements;
CREATE TRIGGER update_cump AFTER INSERT ON stock_movements
  FOR EACH ROW EXECUTE FUNCTION update_cump_on_movement();

-- ============================================================
-- STK-03 : Couches persistantes (stock_valuation_layers)
-- ============================================================
CREATE TABLE IF NOT EXISTS stock_valuation_layers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  product_id uuid NOT NULL,
  warehouse_id uuid,
  movement_id uuid NOT NULL,
  quantity numeric NOT NULL,          -- + entrée, − sortie
  remaining_qty numeric NOT NULL,     -- consommé au fil des sorties
  unit_cost numeric NOT NULL,
  value numeric NOT NULL,
  created_at timestamptz DEFAULT NOW()
);

ALTER TABLE stock_valuation_layers ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS svl_tenant_select ON stock_valuation_layers;
CREATE POLICY svl_tenant_select ON stock_valuation_layers
  FOR SELECT USING (tenant_id = current_tenant_id());
DROP POLICY IF EXISTS svl_tenant_all ON stock_valuation_layers;
CREATE POLICY svl_tenant_all ON stock_valuation_layers
  FOR ALL USING (tenant_id = current_tenant_id()) WITH CHECK (tenant_id = current_tenant_id());

CREATE INDEX IF NOT EXISTS idx_svl_fifo
  ON stock_valuation_layers (tenant_id, product_id, warehouse_id, created_at)
  WHERE remaining_qty > 0;

CREATE INDEX IF NOT EXISTS idx_svl_lifo
  ON stock_valuation_layers (tenant_id, product_id, warehouse_id, created_at DESC)
  WHERE remaining_qty > 0;

-- Trigger : créer une couche à chaque entrée
DROP FUNCTION IF EXISTS create_valuation_layer_on_entry() CASCADE;
CREATE OR REPLACE FUNCTION create_valuation_layer_on_entry()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.movement_type IN ('in', 'initial') AND COALESCE(NEW.unit_cost, 0) > 0 THEN
    INSERT INTO stock_valuation_layers (
      tenant_id, product_id, warehouse_id, movement_id,
      quantity, remaining_qty, unit_cost, value
    ) VALUES (
      NEW.tenant_id, NEW.product_id, NEW.warehouse_id, NEW.id,
      NEW.quantity, NEW.quantity, NEW.unit_cost, NEW.quantity * NEW.unit_cost
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_create_valuation_layer ON stock_movements;
CREATE TRIGGER trg_create_valuation_layer AFTER INSERT ON stock_movements
  FOR EACH ROW EXECUTE FUNCTION create_valuation_layer_on_entry();

-- Trigger : consommer les couches à chaque sortie
DROP FUNCTION IF EXISTS consume_valuation_layers_on_exit() CASCADE;
CREATE OR REPLACE FUNCTION consume_valuation_layers_on_exit()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  v_remaining_to_consume numeric := abs(NEW.quantity);
  v_layer RECORD;
  v_consumed numeric;
  v_method text := 'cump';  -- par défaut ; sera paramétrable
BEGIN
  IF NEW.movement_type NOT IN ('out') THEN
    RETURN NEW;
  END IF;

  -- Consommer les couches selon la méthode (FIFO = ordre croissant, LIFO = décroissant)
  FOR v_layer IN
    SELECT * FROM stock_valuation_layers
    WHERE tenant_id = NEW.tenant_id
      AND product_id = NEW.product_id
      AND COALESCE(warehouse_id, NEW.warehouse_id) = NEW.warehouse_id
      AND remaining_qty > 0
    ORDER BY
      CASE WHEN v_method = 'lifo' THEN created_at END DESC,
      CASE WHEN v_method = 'fifo' THEN created_at END ASC
    FOR UPDATE
  LOOP
    EXIT WHEN v_remaining_to_consume <= 0;
    v_consumed := LEAST(v_remaining_to_consume, v_layer.remaining_qty);
    UPDATE stock_valuation_layers
    SET remaining_qty = remaining_qty - v_consumed,
        value = (remaining_qty - v_consumed) * unit_cost
    WHERE id = v_layer.id;
    v_remaining_to_consume := v_remaining_to_consume - v_consumed;
  END LOOP;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_consume_valuation_layers ON stock_movements;
CREATE TRIGGER trg_consume_valuation_layers AFTER INSERT ON stock_movements
  FOR EACH ROW EXECUTE FUNCTION consume_valuation_layers_on_exit();

-- ============================================================
-- STK-04 : Fonction de valorisation unique avec date
-- ============================================================

-- Paramètre du dossier : méthode de valorisation
ALTER TABLE company_settings ADD COLUMN IF NOT EXISTS stock_valuation_method text
  DEFAULT 'cump' CHECK (stock_valuation_method IN ('cump', 'fifo', 'lifo'));

-- Fonction de valorisation unique
DROP FUNCTION IF EXISTS calculate_stock_valuation_at_date(uuid, date) CASCADE;
CREATE OR REPLACE FUNCTION calculate_stock_valuation_at_date(
  p_tenant_id uuid DEFAULT NULL,
  p_date date DEFAULT CURRENT_DATE,
  p_method text DEFAULT NULL
)
RETURNS TABLE(
  product_id uuid,
  product_name text,
  warehouse_id uuid,
  quantity numeric,
  unit_cost numeric,
  total_value numeric,
  method text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := COALESCE(p_tenant_id, current_tenant_id());
  v_method text;
BEGIN
  -- Récupérer la méthode depuis les paramètres du dossier
  SELECT COALESCE(p_method, cs.stock_valuation_method, 'cump')
  INTO v_method
  FROM company_settings cs
  WHERE cs.tenant_id = v_tid
  LIMIT 1;

  v_method := COALESCE(v_method, 'cump');

  IF v_method = 'cump' THEN
    -- CUMP : lire stock_quantities (mis à jour par le trigger STK-02)
    -- mais recalculer la quantité à la date p_date par rejeu
    RETURN QUERY
    SELECT
      sq.product_id,
      p.name AS product_name,
      sq.warehouse_id,
      COALESCE((
        SELECT SUM(CASE WHEN sm.movement_type IN ('in', 'initial') THEN sm.quantity
                        WHEN sm.movement_type = 'out' THEN -sm.quantity
                        WHEN sm.movement_type = 'adjustment' AND sm.quantity > 0 THEN sm.quantity
                        WHEN sm.movement_type = 'adjustment' AND sm.quantity < 0 THEN -abs(sm.quantity)
                        ELSE 0 END)
        FROM stock_movements sm
        WHERE sm.tenant_id = v_tid
          AND sm.product_id = sq.product_id
          AND sm.warehouse_id = sq.warehouse_id
          AND COALESCE(sm.movement_date, sm.date) <= p_date
      ), 0) AS quantity,
      sq.unit_cost,
      COALESCE((
        SELECT SUM(CASE WHEN sm.movement_type IN ('in', 'initial') THEN sm.quantity
                        WHEN sm.movement_type = 'out' THEN -sm.quantity
                        WHEN sm.movement_type = 'adjustment' AND sm.quantity > 0 THEN sm.quantity
                        WHEN sm.movement_type = 'adjustment' AND sm.quantity < 0 THEN -abs(sm.quantity)
                        ELSE 0 END)
        FROM stock_movements sm
        WHERE sm.tenant_id = v_tid
          AND sm.product_id = sq.product_id
          AND sm.warehouse_id = sq.warehouse_id
          AND COALESCE(sm.movement_date, sm.date) <= p_date
      ), 0) * sq.unit_cost AS total_value,
      'cump'::text AS method
    FROM stock_quantities sq
    JOIN products p ON p.id = sq.product_id AND p.tenant_id = sq.tenant_id
    WHERE sq.tenant_id = v_tid;

  ELSIF v_method IN ('fifo', 'lifo') THEN
    -- FIFO/LIFO : utiliser les couches persistantes
    RETURN QUERY
    SELECT
      svl.product_id,
      p.name AS product_name,
      svl.warehouse_id,
      SUM(svl.remaining_qty) AS quantity,
      CASE WHEN SUM(svl.remaining_qty) > 0
        THEN SUM(svl.remaining_qty * svl.unit_cost) / SUM(svl.remaining_qty)
        ELSE 0
      END AS unit_cost,
      SUM(svl.remaining_qty * svl.unit_cost) AS total_value,
      v_method::text AS method
    FROM stock_valuation_layers svl
    JOIN products p ON p.id = svl.product_id AND p.tenant_id = svl.tenant_id
    WHERE svl.tenant_id = v_tid
      AND svl.created_at <= p_date
      AND svl.remaining_qty > 0
    GROUP BY svl.product_id, p.name, svl.warehouse_id;

  ELSE
    -- Fallback CUMP
    RETURN QUERY
    SELECT
      sq.product_id,
      p.name AS product_name,
      sq.warehouse_id,
      sq.quantity,
      sq.unit_cost,
      sq.quantity * sq.unit_cost AS total_value,
      'cump'::text AS method
    FROM stock_quantities sq
    JOIN products p ON p.id = sq.product_id AND p.tenant_id = sq.tenant_id
    WHERE sq.tenant_id = v_tid
      AND sq.quantity > 0;
  END IF;
END;
$$;

-- ============================================================
-- STK-04 : Supprimer l'ancienne get_stock_valuation (redondante)
-- On la remplace par un wrapper vers la nouvelle fonction
-- ============================================================
DROP FUNCTION IF EXISTS get_stock_valuation(uuid, date) CASCADE;
CREATE OR REPLACE FUNCTION get_stock_valuation(
  p_tenant_id uuid DEFAULT NULL,
  p_date date DEFAULT CURRENT_DATE
)
RETURNS TABLE(
  product_id uuid,
  product_name text,
  warehouse_id uuid,
  quantity numeric,
  unit_cost numeric,
  total_value numeric,
  method text
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT * FROM calculate_stock_valuation_at_date(p_tenant_id, p_date);
$$;
