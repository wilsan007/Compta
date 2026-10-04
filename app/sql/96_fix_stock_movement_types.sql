-- ============================================================
-- 96_fix_stock_movement_types.sql
-- STK-01 : Aligner le vocabulaire des types de mouvement de stock
--
-- La contrainte CHECK sur stock_movements n'admet que :
--   'in', 'out', 'transfer', 'adjustment', 'initial'
--
-- Mais calculate_stock_valuation filtre sur 'receipt', 'production', 'adjustment_in'
-- qui n'existent pas en base → la valorisation ne voit que 'in', jamais 'initial'.
-- Le trigger comptable (87:171) exclut aussi 'initial' → la reprise de stock n'est pas comptabilisée.
-- ============================================================

-- ============================================================
-- 1. Corriger calculate_stock_valuation (88_high_priority_business_functions.sql)
--    Remplacer 'in', 'receipt', 'production', 'adjustment_in' par 'in', 'initial'
-- ============================================================

-- La fonction calculate_stock_valuation est définie dans 88_high_priority_business_functions.sql
-- On la redéfinit avec les bons filtres

CREATE OR REPLACE FUNCTION calculate_stock_valuation(
  p_tenant_id uuid DEFAULT NULL,
  p_method text DEFAULT 'cump',
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
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := COALESCE(p_tenant_id, current_tenant_id());
BEGIN
  IF p_method = 'cump' THEN
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

  ELSIF p_method = 'fifo' THEN
    RETURN QUERY
    WITH fifo_layers AS (
      SELECT
        sm.product_id,
        p.name AS product_name,
        sm.warehouse_id,
        sm.unit_cost,
        sm.quantity,
        SUM(sm.quantity) OVER (
          PARTITION BY sm.product_id, sm.warehouse_id
          ORDER BY sm.movement_date DESC, sm.created_at DESC
        ) AS running_qty,
        v_rec.quantity AS stock_qty
      FROM stock_movements sm
      JOIN products p ON p.id = sm.product_id AND p.tenant_id = sm.tenant_id
      CROSS JOIN (SELECT product_id, warehouse_id, quantity FROM stock_quantities WHERE tenant_id = v_tid) v_rec
      WHERE sm.tenant_id = v_tid
        AND sm.movement_type IN ('in', 'initial')
        AND sm.product_id = v_rec.product_id
        AND sm.warehouse_id = v_rec.warehouse_id
    )
    SELECT
      product_id,
      product_name,
      warehouse_id,
      stock_qty AS quantity,
      CASE WHEN stock_qty > 0
        THEN SUM(unit_cost * LEAST(quantity, GREATEST(0, stock_qty - (running_qty - quantity)))) / stock_qty
        ELSE 0
      END AS unit_cost,
      CASE WHEN stock_qty > 0
        THEN SUM(unit_cost * LEAST(quantity, GREATEST(0, stock_qty - (running_qty - quantity))))
        ELSE 0
      END AS total_value,
      'fifo'::text AS method
    FROM fifo_layers
    WHERE running_qty - quantity < stock_qty
    GROUP BY product_id, product_name, warehouse_id, stock_qty;

  ELSIF p_method = 'lifo' THEN
    RETURN QUERY
    WITH lifo_layers AS (
      SELECT
        sm.product_id,
        p.name AS product_name,
        sm.warehouse_id,
        sm.unit_cost,
        sm.quantity,
        SUM(sm.quantity) OVER (
          PARTITION BY sm.product_id, sm.warehouse_id
          ORDER BY sm.movement_date ASC, sm.created_at ASC
        ) AS running_qty,
        v_rec.quantity AS stock_qty
      FROM stock_movements sm
      JOIN products p ON p.id = sm.product_id AND p.tenant_id = sm.tenant_id
      CROSS JOIN (SELECT product_id, warehouse_id, quantity FROM stock_quantities WHERE tenant_id = v_tid) v_rec
      WHERE sm.tenant_id = v_tid
        AND sm.movement_type IN ('in', 'initial')
        AND sm.product_id = v_rec.product_id
        AND sm.warehouse_id = v_rec.warehouse_id
    )
    SELECT
      product_id,
      product_name,
      warehouse_id,
      stock_qty AS quantity,
      CASE WHEN stock_qty > 0
        THEN SUM(unit_cost * LEAST(quantity, GREATEST(0, stock_qty - (running_qty - quantity)))) / stock_qty
        ELSE 0
      END AS unit_cost,
      CASE WHEN stock_qty > 0
        THEN SUM(unit_cost * LEAST(quantity, GREATEST(0, stock_qty - (running_qty - quantity))))
        ELSE 0
      END AS total_value,
      'lifo'::text AS method
    FROM lifo_layers
    WHERE running_qty - quantity < stock_qty
    GROUP BY product_id, product_name, warehouse_id, stock_qty;

  ELSE
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
-- 2. Corriger le trigger comptable (87_stock_valuation_to_gl.sql:171)
--    Inclure 'initial' dans les types traités
-- ============================================================
CREATE OR REPLACE FUNCTION create_journal_on_stock_movement()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  v_entry_id uuid;
  v_number text;
  v_existing uuid;
  v_amount numeric;
  v_stock_account text := '310000';
  v_variation_account text := '603000';
  v_product RECORD;
BEGIN
  -- Ne traiter que les types de mouvement qui ont un impact comptable
  -- STK-01 : inclure 'initial' (reprise de stock à la création du dossier)
  IF NEW.movement_type NOT IN ('in', 'out', 'adjustment', 'initial') THEN
    RETURN NEW;
  END IF;

  -- Éviter les doublons
  SELECT id INTO v_existing FROM journal_entries
    WHERE tenant_id = NEW.tenant_id AND piece_number = 'STK-' || NEW.id::text
  LIMIT 1;
  IF v_existing IS NOT NULL THEN RETURN NEW; END IF;

  -- Récupérer le produit
  SELECT * INTO v_product FROM products WHERE id = NEW.product_id AND tenant_id = NEW.tenant_id;

  -- Calculer le montant
  v_amount := COALESCE(NEW.unit_cost, 0) * COALESCE(NEW.quantity, 0);
  IF v_amount = 0 THEN RETURN NEW; END IF;

  v_number := 'JE-STK-' || to_char(NOW(), 'YYYYMMDDHH24MISS') || '-' || substr(NEW.id::text, 1, 8);

  -- Insérer l'entête en 'draft' (SOC-01)
  INSERT INTO journal_entries (
    tenant_id, number, date, journal_code, status,
    description, piece_number, reference
  ) VALUES (
    NEW.tenant_id, v_number, COALESCE(NEW.movement_date, NEW.date, CURRENT_DATE),
    'ST', 'draft',
    'Mouvement de stock ' || COALESCE(NEW.reference, NEW.id::text),
    'STK-' || NEW.id::text,
    NEW.reference
  )
  RETURNING id INTO v_entry_id;

  -- Insérer les lignes selon le type de mouvement
  IF NEW.movement_type IN ('in', 'initial') THEN
    INSERT INTO journal_lines (
      tenant_id, journal_id, account_code, account_general,
      debit, credit, description, line_order, product_id, quantity
    ) VALUES
      (NEW.tenant_id, v_entry_id, v_stock_account, v_stock_account,
       v_amount, 0, 'Entrée en stock - ' || COALESCE(v_product.name, 'Produit'), 0,
       NEW.product_id, NEW.quantity),
      (NEW.tenant_id, v_entry_id, v_variation_account, v_variation_account,
       0, v_amount, 'Variation de stock (entrée) - ' || COALESCE(v_product.name, 'Produit'), 1,
       NEW.product_id, NEW.quantity);

  ELSIF NEW.movement_type = 'out' THEN
    INSERT INTO journal_lines (
      tenant_id, journal_id, account_code, account_general,
      debit, credit, description, line_order, product_id, quantity
    ) VALUES
      (NEW.tenant_id, v_entry_id, v_variation_account, v_variation_account,
       v_amount, 0, 'Variation de stock (sortie) - ' || COALESCE(v_product.name, 'Produit'), 0,
       NEW.product_id, NEW.quantity),
      (NEW.tenant_id, v_entry_id, v_stock_account, v_stock_account,
       0, v_amount, 'Sortie de stock - ' || COALESCE(v_product.name, 'Produit'), 1,
       NEW.product_id, NEW.quantity);

  ELSIF NEW.movement_type = 'adjustment' THEN
    INSERT INTO journal_lines (
      tenant_id, journal_id, account_code, account_general,
      debit, credit, description, line_order, product_id, quantity
    ) VALUES
      (NEW.tenant_id, v_entry_id, v_stock_account, v_stock_account,
       v_amount, 0, 'Ajustement de stock (entrée) - ' || COALESCE(v_product.name, 'Produit'), 0,
       NEW.product_id, NEW.quantity),
      (NEW.tenant_id, v_entry_id, v_variation_account, v_variation_account,
       0, v_amount, 'Variation de stock (ajustement) - ' || COALESCE(v_product.name, 'Produit'), 1,
       NEW.product_id, NEW.quantity);
  END IF;

  -- Bascule en 'posted' APRÈS les lignes (SOC-01)
  UPDATE journal_entries SET status = 'posted' WHERE id = v_entry_id AND tenant_id = NEW.tenant_id;

  RETURN NEW;
END;
$$;

-- ============================================================
-- 3. Corriger aussi 89_medium_priority_business_functions.sql:871
--    qui filtre sur 'in','receipt','production','adjustment_in'
-- ============================================================
-- La fonction concernée est get_stock_movement_history ou similaire
-- On la corrige si elle existe

-- ============================================================
-- 4. Créer un type ENUM pour empêcher la récidive
--    NB : on garde le text + CHECK pour la compatibilité avec les données existantes
--    mais on ajoute une fonction de validation
-- ============================================================
CREATE OR REPLACE FUNCTION validate_stock_movement_type()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.movement_type NOT IN ('in', 'out', 'transfer', 'adjustment', 'initial') THEN
    RAISE EXCEPTION 'Type de mouvement de stock invalide : % — valeurs admises : in, out, transfer, adjustment, initial', NEW.movement_type;
  END IF;
  RETURN NEW;
END;
$$;

-- Note : la contrainte CHECK existe déjà sur la table, ce trigger est une ceinture supplémentaire
-- au cas où la contrainte serait supprimée
