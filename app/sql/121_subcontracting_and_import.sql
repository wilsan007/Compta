-- ============================================================
-- 121_subcontracting_and_import.sql
-- PRD-09 : Sous-traitance de production + IMP-01 : Reprise de données
-- ============================================================

-- ============================================================
-- PRD-09 : Sous-traitance — Triggers métier
-- ============================================================

-- Expédition chez le sous-traitant → mouvement 'out' vers stock chez tiers
CREATE OR REPLACE FUNCTION st_shipment_stock_out()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_line record;
  v_product_id uuid;
  v_unit_cost numeric;
  v_tid uuid := NEW.tenant_id;
BEGIN
  IF NEW.status <> 'shipped' THEN
    RETURN NEW;
  END IF;

  -- Pour chaque ligne d'expédition, créer un mouvement de stock sortant
  FOR v_line IN
    SELECT * FROM st_shipment_lines
    WHERE st_shipment_id = NEW.id AND tenant_id = v_tid
  LOOP
    -- Récupérer le produit et le coût unitaire
    SELECT product_id INTO v_product_id
    FROM st_orders
    WHERE id = NEW.st_order_id AND tenant_id = v_tid;

    SELECT unit_cost INTO v_unit_cost
    FROM stock_quantities
    WHERE tenant_id = v_tid AND product_id = v_product_id
    LIMIT 1;

    -- Mouvement de stock 'out' vers le sous-traitant
    INSERT INTO stock_movements (
      tenant_id, product_id, warehouse_id, movement_type,
      quantity, unit_cost, reference, reference_type, movement_date, notes, created_at
    ) VALUES (
      v_tid, v_product_id, NULL, 'out',
      v_line.quantity, COALESCE(v_unit_cost, 0),
      'ST-' || NEW.number, 'manual', now(),
      'Expédition sous-traitance', now()
    );

    -- Décrémenter le stock physique
    UPDATE stock_quantities
    SET quantity = quantity - v_line.quantity, updated_at = now()
    WHERE tenant_id = v_tid AND product_id = v_product_id;
  END LOOP;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS st_shipment_stock_out_trigger ON st_shipments;
CREATE TRIGGER st_shipment_stock_out_trigger
  AFTER UPDATE ON st_shipments
  FOR EACH ROW
  EXECUTE FUNCTION st_shipment_stock_out();

-- Réception du sous-traitant → mouvement 'in' valorisé matière + façon
CREATE OR REPLACE FUNCTION st_receipt_stock_in()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_line record;
  v_product_id uuid;
  v_material_cost numeric := 0;
  v_subcontracting_cost numeric := 0;
  v_total_cost numeric;
  v_tid uuid := NEW.tenant_id;
  v_order record;
BEGIN
  IF NEW.status <> 'received' THEN
    RETURN NEW;
  END IF;

  -- Récupérer l'ordre de sous-traitance
  SELECT * INTO v_order FROM st_orders WHERE id = NEW.st_order_id AND tenant_id = v_tid;

  FOR v_line IN
    SELECT * FROM st_receipt_lines
    WHERE st_receipt_id = NEW.id AND tenant_id = v_tid
  LOOP
    -- Coût matière = coût unitaire du stock × quantité reçue
    SELECT unit_cost INTO v_material_cost
    FROM stock_quantities
    WHERE tenant_id = v_tid AND product_id = v_order.product_id
    LIMIT 1;

    -- Coût façon = coût de l'opération sous-traitée
    v_subcontracting_cost := COALESCE(v_order.unit_price, 0) * v_line.quantity;

    -- Coût total = matière + façon
    v_total_cost := COALESCE(v_material_cost, 0) + v_subcontracting_cost;
    v_product_id := v_order.product_id;

    -- Mouvement de stock 'in' valorisé
    INSERT INTO stock_movements (
      tenant_id, product_id, warehouse_id, movement_type,
      quantity, unit_cost, reference, reference_type, movement_date, notes, created_at
    ) VALUES (
      v_tid, v_product_id, NULL, 'in',
      v_line.quantity, v_total_cost / v_line.quantity,
      'ST-REC-' || NEW.number, 'goods_receipt', now(),
      'Réception sous-traitance', now()
    );

    -- Incrémenter le stock
    UPDATE stock_quantities
    SET quantity = quantity + v_line.quantity,
      unit_cost = v_total_cost / v_line.quantity,
      updated_at = now()
    WHERE tenant_id = v_tid AND product_id = v_product_id;
  END LOOP;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS st_receipt_stock_in_trigger ON st_receipts;
CREATE TRIGGER st_receipt_stock_in_trigger
  AFTER UPDATE ON st_receipts
  FOR EACH ROW
  EXECUTE FUNCTION st_receipt_stock_in();

-- ============================================================
-- PRD-09 : État du stock détenu chez les tiers
-- ============================================================
CREATE OR REPLACE FUNCTION get_stock_at_subcontractors()
RETURNS TABLE(
  product_id uuid,
  product_name text,
  subcontractor_id uuid,
  subcontractor_name text,
  quantity_out numeric,
  quantity_received numeric,
  quantity_at_subcontractor numeric,
  material_value numeric
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, extensions, pg_temp
AS $$
  WITH sent AS (
    SELECT
      so.product_id,
      so.supplier_id,
      SUM(sl.quantity) AS qty_out
    FROM st_orders so
    JOIN st_shipments sh ON sh.st_order_id = so.id AND sh.tenant_id = so.tenant_id
    JOIN st_shipment_lines sl ON sl.st_shipment_id = sh.id AND sl.tenant_id = so.tenant_id
    WHERE so.tenant_id = current_tenant_id() AND sh.status = 'shipped'
    GROUP BY so.product_id, so.supplier_id
  ),
  received AS (
    SELECT
      so.product_id,
      so.supplier_id,
      SUM(rl.quantity) AS qty_in
    FROM st_orders so
    JOIN st_receipts rc ON rc.st_order_id = so.id AND rc.tenant_id = so.tenant_id
    JOIN st_receipt_lines rl ON rl.st_receipt_id = rc.id AND rl.tenant_id = so.tenant_id
    WHERE so.tenant_id = current_tenant_id() AND rc.status = 'received'
    GROUP BY so.product_id, so.supplier_id
  )
  SELECT
    s.product_id,
    p.name,
    s.supplier_id,
    sup.name,
    s.qty_out,
    COALESCE(r.qty_in, 0),
    s.qty_out - COALESCE(r.qty_in, 0),
    (s.qty_out - COALESCE(r.qty_in, 0)) * COALESCE(sq.unit_cost, 0)
  FROM sent s
  LEFT JOIN received r ON r.product_id = s.product_id AND r.supplier_id = s.supplier_id
  JOIN products p ON p.id = s.product_id AND p.tenant_id = current_tenant_id()
  LEFT JOIN suppliers sup ON sup.id = s.supplier_id AND sup.tenant_id = current_tenant_id()
  LEFT JOIN stock_quantities sq ON sq.product_id = s.product_id AND sq.tenant_id = current_tenant_id()
  WHERE s.qty_out - COALESCE(r.qty_in, 0) > 0
  ORDER BY p.name;
$$;

-- ============================================================
-- IMP-01 : Table de suivi des imports de données
-- ============================================================
CREATE TABLE IF NOT EXISTS data_import_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  import_type text NOT NULL CHECK (import_type IN ('balance', 'fec', 'customers', 'suppliers', 'products', 'invoices', 'journal_entries', 'stock', 'employees')),
  file_name text,
  file_size bigint,
  total_rows int DEFAULT 0,
  imported_rows int DEFAULT 0,
  rejected_rows int DEFAULT 0,
  error_details json,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'in_progress', 'completed', 'failed', 'partial')),
  started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE data_import_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY data_import_logs_tenant ON data_import_logs
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

-- ============================================================
-- IMP-01 : Import de balance d'ouverture avec contrôle d'équilibre
-- ============================================================
CREATE OR REPLACE FUNCTION import_opening_balance(
  p_balance_data json
)
RETURNS TABLE(
  account_code text,
  account_name text,
  debit numeric,
  credit numeric,
  is_balanced boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_total_debit numeric := 0;
  v_total_credit numeric := 0;
  v_je_id uuid;
  v_row record;
  v_line_num int := 1;
BEGIN
  -- Calculer les totaux
  SELECT
    COALESCE(SUM((elem->>'debit')::numeric), 0),
    COALESCE(SUM((elem->>'credit')::numeric), 0)
  INTO v_total_debit, v_total_credit
  FROM json_array_elements(p_balance_data) AS elem;

  -- Vérifier l'équilibre
  IF ABS(v_total_debit - v_total_credit) > 0.01 THEN
    RAISE EXCEPTION 'Balance non équilibrée : débit % ≠ crédit %', v_total_debit, v_total_credit;
  END IF;

  -- Créer l'écriture d'à-nouveau
  INSERT INTO journal_entries (
    tenant_id, journal_code, number, date, description, status, created_at
  ) VALUES (
    v_tid, 'AN', 'AN-' || EXTRACT(YEAR FROM CURRENT_DATE),
    DATE_TRUNC('year', CURRENT_DATE),
    'À-nouveaux d''ouverture', 'draft', now()
  )
  RETURNING id INTO v_je_id;

  -- Insérer les lignes
  FOR v_row IN
    SELECT
      elem->>'account_code' AS account_code,
      elem->>'account_name' AS account_name,
      COALESCE((elem->>'debit')::numeric, 0) AS debit,
      COALESCE((elem->>'credit')::numeric, 0) AS credit
    FROM json_array_elements(p_balance_data) AS elem
  LOOP
    INSERT INTO journal_lines (
      tenant_id, journal_id, account_code, account_name, debit, credit, line_order, created_at
    ) VALUES (
      v_tid, v_je_id, v_row.account_code, v_row.account_name,
      v_row.debit, v_row.credit, v_line_num, now()
    );
    v_line_num := v_line_num + 1;
  END LOOP;

  -- Poster l'écriture
  UPDATE journal_entries SET status = 'posted' WHERE id = v_je_id;

  -- Retourner le résultat
  RETURN QUERY
    SELECT
      elem->>'account_code' AS account_code,
      elem->>'account_name' AS account_name,
      COALESCE((elem->>'debit')::numeric, 0) AS debit,
      COALESCE((elem->>'credit')::numeric, 0) AS credit,
      true AS is_balanced
    FROM json_array_elements(p_balance_data) AS elem;
END;
$$;
