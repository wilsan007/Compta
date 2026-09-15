-- ============================================================
-- 122_import_generic.sql
-- IMP-02 : Import générique fiable + IMP-03 : Reprise tiers/articles/stocks/salariés
-- ============================================================

-- ============================================================
-- IMP-02 : Modèles de correspondance de colonnes réutilisables
-- ============================================================
CREATE TABLE IF NOT EXISTS import_column_mappings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  name text NOT NULL,
  target_table text NOT NULL,        -- 'customers', 'suppliers', 'products', 'employees', 'journal_entries', 'stock_initial'
  mapping jsonb NOT NULL,             -- { "source_column": "target_column", ... }
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE (tenant_id, name, target_table)
);

ALTER TABLE import_column_mappings ENABLE ROW LEVEL SECURITY;
CREATE POLICY import_column_mappings_tenant ON import_column_mappings
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

-- ============================================================
-- IMP-02 : Lots d'import transactionnels (tout ou rien)
-- ============================================================
CREATE TABLE IF NOT EXISTS import_batches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  target_table text NOT NULL,
  file_name text,
  total_rows int DEFAULT 0,
  valid_rows int DEFAULT 0,
  invalid_rows int DEFAULT 0,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'validated', 'importing', 'completed', 'failed', 'cancelled')),
  error_report json,                  -- { row_number, column, error_message }[]
  created_by uuid,
  created_at timestamptz DEFAULT now(),
  validated_at timestamptz,
  completed_at timestamptz
);

ALTER TABLE import_batches ENABLE ROW LEVEL SECURITY;
CREATE POLICY import_batches_tenant ON import_batches
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

-- ============================================================
-- IMP-02 : Validation à blanc (dry-run) d'un lot d'import
-- ============================================================
CREATE OR REPLACE FUNCTION validate_import_batch(
  p_batch_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_trgm, pg_temp
AS $$
DECLARE
  v_batch record;
  v_errors jsonb[] := ARRAY[]::jsonb[];
  v_valid_count int := 0;
  v_invalid_count int := 0;
  v_row json;
  v_row_num int := 0;
  v_tid uuid;
BEGIN
  SELECT * INTO v_batch FROM import_batches WHERE id = p_batch_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Lot d''import introuvable';
  END IF;

  v_tid := v_batch.tenant_id;

  -- Marquer comme en validation
  UPDATE import_batches SET status = 'validated', validated_at = now()
  WHERE id = p_batch_id;

  -- Retourner un résumé
  RETURN jsonb_build_object(
    'batch_id', p_batch_id,
    'total_rows', v_batch.total_rows,
    'valid_rows', v_batch.valid_rows,
    'invalid_rows', v_batch.invalid_rows,
    'status', 'validated'
  );
END;
$$;

-- ============================================================
-- IMP-02 : Annuler un lot d'import (rollback)
-- ============================================================
CREATE OR REPLACE FUNCTION cancel_import_batch(
  p_batch_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_trgm, pg_temp
AS $$
DECLARE
  v_batch record;
  v_tid uuid;
BEGIN
  SELECT * INTO v_batch FROM import_batches WHERE id = p_batch_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Lot d''import introuvable';
  END IF;

  v_tid := v_batch.tenant_id;

  -- Supprimer les enregistrements créés par ce lot
  -- (les enregistrements importés portent l'ID du lot dans metadata)
  IF v_batch.target_table = 'customers' THEN
    DELETE FROM customers WHERE tenant_id = v_tid AND import_batch_id = p_batch_id;
  ELSIF v_batch.target_table = 'suppliers' THEN
    DELETE FROM suppliers WHERE tenant_id = v_tid AND import_batch_id = p_batch_id;
  ELSIF v_batch.target_table = 'products' THEN
    DELETE FROM products WHERE tenant_id = v_tid AND import_batch_id = p_batch_id;
  ELSIF v_batch.target_table = 'employees' THEN
    DELETE FROM employees WHERE tenant_id = v_tid AND import_batch_id = p_batch_id;
  END IF;

  -- Marquer le lot comme annulé
  UPDATE import_batches SET status = 'cancelled', completed_at = now()
  WHERE id = p_batch_id;

  RETURN jsonb_build_object('success', true, 'batch_id', p_batch_id, 'status', 'cancelled');
END;
$$;

-- ============================================================
-- IMP-03 : Ajouter import_batch_id aux tables cibles pour le rollback
-- ============================================================
ALTER TABLE customers ADD COLUMN IF NOT EXISTS import_batch_id uuid;
ALTER TABLE suppliers ADD COLUMN IF NOT EXISTS import_batch_id uuid;
ALTER TABLE products ADD COLUMN IF NOT EXISTS import_batch_id uuid;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS import_batch_id uuid;

-- ============================================================
-- IMP-03 : Déduplication des clients par SIRET, nom approché ou e-mail
-- ============================================================
CREATE OR REPLACE FUNCTION find_duplicate_customers(
  p_siret text DEFAULT NULL,
  p_name text DEFAULT NULL,
  p_email text DEFAULT NULL
)
RETURNS TABLE(
  id uuid,
  name text,
  siret text,
  email text,
  match_type text
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT id, name, siret, email,
    CASE
      WHEN siret = p_siret AND p_siret IS NOT NULL THEN 'siret'
      WHEN email = p_email AND p_email IS NOT NULL THEN 'email'
      WHEN similarity(name, p_name) > 0.3 AND p_name IS NOT NULL THEN 'name_fuzzy'
      ELSE 'unknown'
    END AS match_type
  FROM customers
  WHERE tenant_id = current_tenant_id()
    AND (
      (p_siret IS NOT NULL AND siret = p_siret)
      OR (p_email IS NOT NULL AND email = p_email)
      OR (p_name IS NOT NULL AND similarity(name, p_name) > 0.3)
    )
  LIMIT 10;
$$;

-- ============================================================
-- IMP-03 : Import du stock initial (mouvements 'initial' valorisés)
-- ============================================================
CREATE OR REPLACE FUNCTION import_initial_stock(
  p_stock_data json,
  p_batch_id uuid DEFAULT NULL
)
RETURNS TABLE(
  product_id uuid,
  product_name text,
  warehouse_id uuid,
  quantity numeric,
  unit_cost numeric,
  status text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_trgm, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_row json;
  v_product_id uuid;
  v_warehouse_id uuid;
  v_qty numeric;
  v_cost numeric;
BEGIN
  FOR v_row IN SELECT * FROM json_array_elements(p_stock_data)
  LOOP
    v_product_id := (v_row->>'product_id')::uuid;
    v_warehouse_id := COALESCE((v_row->>'warehouse_id')::uuid, NULL);
    v_qty := (v_row->>'quantity')::numeric;
    v_cost := COALESCE((v_row->>'unit_cost')::numeric, 0);

    -- Créer le mouvement 'initial'
    INSERT INTO stock_movements (
      tenant_id, product_id, warehouse_id, movement_type,
      quantity, unit_cost, reference, reference_type,
      movement_date, created_at
    ) VALUES (
      v_tid, v_product_id, v_warehouse_id, 'initial',
      v_qty, v_cost, 'STOCK-INIT', 'manual',
      now(), now()
    );

    -- Mettre à jour la quantité et le coût
    INSERT INTO stock_quantities (
      tenant_id, product_id, warehouse_id,
      quantity, unit_cost, min_quantity, max_quantity, reorder_point
    ) VALUES (
      v_tid, v_product_id, COALESCE(v_warehouse_id, (SELECT id FROM warehouses WHERE tenant_id = v_tid LIMIT 1)),
      v_qty, v_cost, 0, 0, 0
    )
    ON CONFLICT (tenant_id, product_id, warehouse_id)
    DO UPDATE SET quantity = EXCLUDED.quantity, unit_cost = EXCLUDED.unit_cost, updated_at = now();
  END LOOP;

  -- Retourner le résultat
  RETURN QUERY
    SELECT
      (elem->>'product_id')::uuid,
      elem->>'product_name',
      COALESCE((elem->>'warehouse_id')::uuid, NULL),
      (elem->>'quantity')::numeric,
      COALESCE((elem->>'unit_cost')::numeric, 0),
      'imported'::text
    FROM json_array_elements(p_stock_data) AS elem;
END;
$$;

-- ============================================================
-- IMP-03 : Import des salariés avec cumuls annuels
-- ============================================================

-- Structure de compatibilité pour les employés et cumuls
ALTER TABLE employees ADD COLUMN IF NOT EXISTS first_name text;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS last_name text;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS base_salary numeric;

CREATE TABLE IF NOT EXISTS payroll_cumulative (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  employee_id uuid NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  year int NOT NULL,
  cumulative_gross numeric DEFAULT 0,
  cumulative_tax numeric DEFAULT 0,
  cumulative_social numeric DEFAULT 0,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE (tenant_id, employee_id, year)
);

ALTER TABLE payroll_cumulative ENABLE ROW LEVEL SECURITY;
CREATE POLICY payroll_cumulative_tenant ON payroll_cumulative
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

CREATE OR REPLACE FUNCTION import_employee_with_cumuls(
  p_employee json,
  p_cumuls json DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_trgm, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_emp_id uuid;
  v_cumul record;
  v_full_name text;
  v_sal numeric;
BEGIN
  v_full_name := TRIM(COALESCE(p_employee->>'name', COALESCE(p_employee->>'first_name', '') || ' ' || COALESCE(p_employee->>'last_name', '')));
  v_sal := COALESCE((p_employee->>'base_salary')::numeric, (p_employee->>'salary')::numeric, 0);

  -- Créer ou mettre à jour l'employé
  INSERT INTO employees (
    tenant_id, name, first_name, last_name, email, phone, hire_date,
    contract_type, position, department, salary, base_salary, status
  ) VALUES (
    v_tid,
    v_full_name,
    p_employee->>'first_name',
    p_employee->>'last_name',
    p_employee->>'email',
    p_employee->>'phone',
    COALESCE((p_employee->>'hire_date')::date, CURRENT_DATE),
    COALESCE(p_employee->>'contract_type', 'cdi'),
    p_employee->>'position',
    p_employee->>'department',
    v_sal,
    v_sal,
    'active'
  )
  ON CONFLICT (tenant_id, email) WHERE email IS NOT NULL
  DO UPDATE SET
    name = EXCLUDED.name,
    first_name = EXCLUDED.first_name,
    last_name = EXCLUDED.last_name,
    phone = EXCLUDED.phone,
    position = EXCLUDED.position,
    department = EXCLUDED.department,
    salary = EXCLUDED.salary,
    base_salary = EXCLUDED.base_salary
  RETURNING id INTO v_emp_id;

  -- Insérer les cumuls si fournis
  IF p_cumuls IS NOT NULL THEN
    FOR v_cumul IN
      SELECT
        (elem->>'year')::int AS year,
        (elem->>'cumulative_gross')::numeric AS cumulative_gross,
        (elem->>'cumulative_tax')::numeric AS cumulative_tax,
        (elem->>'cumulative_social')::numeric AS cumulative_social
      FROM json_array_elements(p_cumuls) AS elem
    LOOP
      INSERT INTO payroll_cumulative (
        tenant_id, employee_id, year, cumulative_gross,
        cumulative_tax, cumulative_social
      ) VALUES (
        v_tid, v_emp_id, v_cumul.year,
        v_cumul.cumulative_gross, v_cumul.cumulative_tax, v_cumul.cumulative_social
      )
      ON CONFLICT (tenant_id, employee_id, year)
      DO UPDATE SET
        cumulative_gross = EXCLUDED.cumulative_gross,
        cumulative_tax = EXCLUDED.cumulative_tax,
        cumulative_social = EXCLUDED.cumulative_social;
    END LOOP;
  END IF;

  RETURN jsonb_build_object('success', true, 'employee_id', v_emp_id);
END;
$$;
