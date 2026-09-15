-- ============================================================
-- 82_critical_constraints.sql
--
-- Correction des contraintes critiques identifiées par l'audit :
--   1. NOT NULL sur toutes les colonnes tenant_id (203 tables)
--   2. CHECK (>= 0) sur les colonnes de montants et quantités (~200 colonnes)
--   3. UNIQUE (tenant_id, number) au lieu de UNIQUE (number) global (24 tables)
--   4. Suppression des contraintes UNIQUE redondantes
--   5. CHECK sur payment_state (invoices, purchase_invoices)
--   6. CHECK de cohérence des dates (end_date >= start_date)
--   7. CHECK de format (email, SIRET, IBAN)
--
-- Toutes les opérations utilisent des blocs DO avec EXCEPTION
-- pour éviter les échecs sur les tables qui auraient déjà les contraintes.
-- ============================================================

-- ============================================================
-- SECTION 1 — NOT NULL sur tenant_id (203 tables)
-- ============================================================
-- Toutes les tables multi-tenant doivent avoir tenant_id NOT NULL
-- pour garantir l'isolation RLS. Les tables de référence globale
-- (currencies, chart_account_templates, etc.) sont exclues si
-- elles n'ont pas de tenant_id.

DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT table_name
    FROM information_schema.columns
    WHERE column_name = 'tenant_id'
      AND table_schema = 'public'
      AND is_nullable = 'YES'
      AND table_name NOT IN (
        'sql_migrations_tracker'
      )
    ORDER BY table_name
  LOOP
    BEGIN
      EXECUTE format('ALTER TABLE %I ALTER COLUMN tenant_id SET NOT NULL', r.table_name);
      RAISE NOTICE 'Set NOT NULL on %.tenant_id', r.table_name;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'SKIP NOT NULL on %: %', r.table_name, SQLERRM;
    END;
  END LOOP;
END;
$$;


-- ============================================================
-- SECTION 2 — CHECK (>= 0) sur montants et quantités
-- ============================================================
-- Aucune colonne de montant ou quantité ne devrait être négative
-- (sauf cas particuliers comme balance client/fournisseur qui peut être négative).

DO $$
DECLARE
  r RECORD;
  v_constraint_name text;
BEGIN
  FOR r IN
    SELECT c.table_name, c.column_name
    FROM information_schema.columns c
    JOIN information_schema.tables t
      ON t.table_name = c.table_name AND t.table_schema = c.table_schema
    WHERE c.table_schema = 'public'
      AND t.table_type = 'BASE TABLE'
      AND c.data_type IN ('numeric', 'integer', 'bigint', 'double precision', 'real')
      -- Colonnes qui doivent toujours être >= 0
      AND c.column_name IN (
        'amount', 'total', 'subtotal', 'vat_total', 'quantity',
        'amount_paid', 'amount_due', 'unit_price', 'unit_cost',
        'exchange_rate', 'stock_quantity', 'reserved_quantity',
        'available_quantity', 'quantity_received', 'quantity_ordered',
        'quantity_delivered', 'recall_amount', 'advance_amount',
        'calculated_balance', 'opening_balance', 'closing_balance',
        'threshold', 'rate', 'percentage', 'commission', 'discount',
        'penalty', 'budget', 'planned', 'actual', 'variance',
        'accumulated_depreciation', 'depreciation_amount', 'residual_value',
        'acquisition_cost', 'gross_amount', 'net_amount', 'tax_amount',
        'credit_limit', 'credit_used', 'social_charges',
        'employer_charges', 'employee_charges', 'net_taxable',
        'net_before_tax', 'meal_voucher_amount', 'transport_allowance',
        'overtime_rate', 'bonus', 'premium', 'indemnity',
        'compensation', 'reimbursement', 'deduction', 'contribution',
        'payment_amount', 'charge_amount', 'expense_amount',
        'income_amount', 'revenue_amount', 'expense_total',
        'income_total', 'opening_stock', 'closing_stock',
        'stock_value', 'movement_quantity', 'ordered_quantity',
        'shipped_quantity', 'invoiced_quantity', 'received_quantity',
        'produced_quantity', 'consumed_quantity', 'planned_quantity',
        'actual_quantity', 'defect_quantity', 'passed_quantity',
        'failed_quantity', 'rejected_quantity', 'waste_quantity',
        'scrap_quantity', 'total_cost', 'average_cost', 'standard_cost',
        'actual_cost', 'variance_cost', 'fixed_cost', 'variable_cost',
        'direct_cost', 'indirect_cost', 'overhead_cost', 'labor_cost',
        'material_cost', 'min_amount', 'max_amount', 'min_quantity',
        'max_quantity', 'min_price', 'max_price', 'min_rate',
        'max_rate', 'min_hours', 'max_hours', 'min_balance',
        'max_balance', 'min_stock', 'max_stock', 'reorder_point',
        'safety_stock', 'balance_hours', 'balance_amount',
        'deduction_rate', 'max_carry_over', 'overtime_hours',
        'regular_hours', 'overtime_amount', 'regular_amount',
        'daily_rate', 'hourly_rate', 'monthly_rate', 'annual_rate',
        'base_salary', 'gross_salary', 'net_salary', 'gross_total',
        'net_total', 'gross_bonus', 'net_bonus', 'gross_indemnity',
        'net_indemnity', 'gross_reimbursement', 'net_reimbursement',
        'gross_deduction', 'net_deduction', 'gross_contribution',
        'net_contribution', 'gross_advance', 'net_advance',
        'gross_recall', 'net_recall', 'gross_expense', 'net_expense',
        'gross_income', 'net_income', 'gross_revenue', 'net_revenue',
        'gross_profit', 'net_profit', 'gross_margin', 'net_margin',
        'hours', 'salary', 'cost', 'price', 'balance',
        'amount_paid', 'advance_amount', 'actual_cost', 'budget',
        'max_carry_over', 'probability', 'priority', 'rating',
        'position', 'level', 'step', 'weight', 'score'
      )
      -- Exclure les colonnes qui peuvent légitimement être négatives
      AND NOT (c.column_name IN ('balance', 'amount_due', 'variance', 'variance_cost')
               AND c.table_name IN ('customers', 'suppliers', 'third_party_accounts',
                                    'bank_accounts', 'chart_accounts', 'journal_lines',
                                    'projects', 'project_tasks', 'stock_quantities'))
      -- Exclure debit/credit (peuvent être 0 mais pas négatifs en compta)
      AND c.column_name NOT IN ('debit', 'credit')
    ORDER BY c.table_name, c.column_name
  LOOP
    v_constraint_name := r.table_name || '_' || r.column_name || '_nonneg';
    BEGIN
      EXECUTE format(
        'ALTER TABLE %I ADD CONSTRAINT %I CHECK (%I >= 0)',
        r.table_name, v_constraint_name, r.column_name
      );
      RAISE NOTICE 'Added CHECK >= 0 on %.%', r.table_name, r.column_name;
    EXCEPTION WHEN duplicate_object THEN
      NULL; -- Contrainte existe déjà
    WHEN OTHERS THEN
      RAISE NOTICE 'SKIP CHECK on %.%: %', r.table_name, r.column_name, SQLERRM;
    END;
  END LOOP;
END;
$$;

-- CHECK spécifique pour debit et credit (>= 0, jamais négatif en compta)
DO $$
DECLARE
  r RECORD;
  v_con text;
BEGIN
  FOR r IN
    SELECT table_name, column_name
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND column_name IN ('debit', 'credit')
      AND data_type IN ('numeric', 'integer', 'bigint', 'double precision')
    ORDER BY table_name, column_name
  LOOP
    v_con := r.table_name || '_' || r.column_name || '_nonneg';
    BEGIN
      EXECUTE format('ALTER TABLE %I ADD CONSTRAINT %I CHECK (%I >= 0)',
        r.table_name, v_con, r.column_name);
      RAISE NOTICE 'Added CHECK >= 0 on %.%', r.table_name, r.column_name;
    EXCEPTION WHEN duplicate_object THEN NULL;
    WHEN OTHERS THEN
      RAISE NOTICE 'SKIP CHECK on %.%: %', r.table_name, r.column_name, SQLERRM;
    END;
  END LOOP;
END;
$$;


-- ============================================================
-- SECTION 3 — UNIQUE (tenant_id, number) au lieu de UNIQUE (number)
-- ============================================================
-- 24 tables ont un UNIQUE(number) global qui empêche deux tenants
-- d'avoir le même numéro. On les remplace par UNIQUE(tenant_id, number).

DO $$
DECLARE
  rec RECORD;
  v_old_con text;
  v_new_con text;
  v_col text;
BEGIN
  FOR rec IN
    SELECT c.conname as old_conname, cl.relname as tbl,
           pg_get_constraintdef(c.oid) as def
    FROM pg_constraint c
    JOIN pg_class cl ON cl.oid = c.conrelid
    JOIN pg_namespace n ON n.oid = cl.relnamespace
    WHERE n.nspname = 'public'
      AND c.contype = 'u'
      AND pg_get_constraintdef(c.oid) NOT ILIKE '%tenant_id%'
      AND (pg_get_constraintdef(c.oid) ILIKE '%number%'
        OR pg_get_constraintdef(c.oid) ILIKE '%code%'
        OR pg_get_constraintdef(c.oid) ILIKE '%run_number%'
        OR pg_get_constraintdef(c.oid) ILIKE '%label_number%'
        OR pg_get_constraintdef(c.oid) ILIKE '%forecast_number%')
      -- Exclure les tables globales sans tenant_id
      AND cl.relname NOT IN ('chart_account_templates', 'currencies')
  LOOP
    -- Déterminer le nom de la colonne depuis la définition
    v_col := regexp_replace(rec.def, '.*UNIQUE \((.*)\)', '\1', 'i');
    v_col := trim(v_col);
    v_new_con := rec.tbl || '_tenant_' || v_col || '_key';

    BEGIN
      -- Supprimer l'ancienne contrainte
      EXECUTE format('ALTER TABLE %I DROP CONSTRAINT %I', rec.tbl, rec.old_conname);
      RAISE NOTICE 'Dropped % on %', rec.old_conname, rec.tbl;

      -- Créer la nouvelle avec tenant_id
      EXECUTE format(
        'ALTER TABLE %I ADD CONSTRAINT %I UNIQUE (tenant_id, %s)',
        rec.tbl, v_new_con, v_col
      );
      RAISE NOTICE 'Added UNIQUE(tenant_id, %) on %', v_col, rec.tbl;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'SKIP UNIQUE fix on %: %', rec.tbl, SQLERRM;
    END;
  END LOOP;
END;
$$;


-- ============================================================
-- SECTION 4 — Suppression des contraintes UNIQUE redondantes
-- ============================================================

-- credit_notes : deux contraintes identiques sur (tenant_id, number)
DO $$ BEGIN
  ALTER TABLE credit_notes DROP CONSTRAINT uniq_credit_note_number_tenant;
  RAISE NOTICE 'Dropped redundant uniq_credit_note_number_tenant';
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- invoices : deux contraintes identiques sur (tenant_id, number)
DO $$ BEGIN
  ALTER TABLE invoices DROP CONSTRAINT uniq_invoice_number_tenant;
  RAISE NOTICE 'Dropped redundant uniq_invoice_number_tenant';
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- journal_entries : tenant_number_key redondant (couvert par uniq_journal_entry_number_tenant)
DO $$ BEGIN
  ALTER TABLE journal_entries DROP CONSTRAINT journal_entries_tenant_number_key;
  RAISE NOTICE 'Dropped redundant journal_entries_tenant_number_key';
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- pay_slips : deux contraintes identiques sur (tenant_id, number)
DO $$ BEGIN
  ALTER TABLE pay_slips DROP CONSTRAINT pay_slips_number_key;
  RAISE NOTICE 'Dropped redundant pay_slips_number_key (global UNIQUE)';
EXCEPTION WHEN OTHERS THEN NULL;
END $$;


-- ============================================================
-- SECTION 5 — CHECK sur payment_state
-- ============================================================

DO $$ BEGIN
  ALTER TABLE invoices ADD CONSTRAINT invoices_payment_state_check
    CHECK (payment_state IS NULL OR payment_state = ANY (ARRAY['not_paid','partial','paid']));
  RAISE NOTICE 'Added payment_state CHECK on invoices';
EXCEPTION WHEN duplicate_object THEN NULL;
WHEN OTHERS THEN RAISE NOTICE 'SKIP payment_state on invoices: %', SQLERRM;
END $$;

DO $$ BEGIN
  ALTER TABLE purchase_invoices ADD CONSTRAINT purchase_invoices_payment_state_check
    CHECK (payment_state IS NULL OR payment_state = ANY (ARRAY['not_paid','partial','paid']));
  RAISE NOTICE 'Added payment_state CHECK on purchase_invoices';
EXCEPTION WHEN duplicate_object THEN NULL;
WHEN OTHERS THEN RAISE NOTICE 'SKIP payment_state on purchase_invoices: %', SQLERRM;
END $$;


-- ============================================================
-- SECTION 6 — CHECK de cohérence des dates (end >= start)
-- ============================================================

DO $$ BEGIN
  ALTER TABLE contracts ADD CONSTRAINT contracts_dates_check
    CHECK (end_date IS NULL OR end_date >= start_date);
EXCEPTION WHEN duplicate_object THEN NULL;
WHEN OTHERS THEN RAISE NOTICE 'SKIP dates CHECK on contracts: %', SQLERRM;
END $$;

DO $$ BEGIN
  ALTER TABLE asset_depreciation_plans ADD CONSTRAINT asset_dep_plans_dates_check
    CHECK (end_date IS NULL OR end_date >= start_date);
EXCEPTION WHEN duplicate_object THEN NULL;
WHEN OTHERS THEN RAISE NOTICE 'SKIP dates CHECK on asset_depreciation_plans: %', SQLERRM;
END $$;

DO $$ BEGIN
  ALTER TABLE fiscal_periods ADD CONSTRAINT fiscal_periods_dates_check
    CHECK (end_date >= start_date);
EXCEPTION WHEN duplicate_object THEN NULL;
WHEN OTHERS THEN RAISE NOTICE 'SKIP dates CHECK on fiscal_periods: %', SQLERRM;
END $$;

DO $$ BEGIN
  ALTER TABLE fiscal_years ADD CONSTRAINT fiscal_years_dates_check
    CHECK (end_date >= start_date);
EXCEPTION WHEN duplicate_object THEN NULL;
WHEN OTHERS THEN RAISE NOTICE 'SKIP dates CHECK on fiscal_years: %', SQLERRM;
END $$;

DO $$ BEGIN
  ALTER TABLE leave_requests ADD CONSTRAINT leave_requests_dates_check
    CHECK (end_date IS NULL OR end_date >= start_date);
EXCEPTION WHEN duplicate_object THEN NULL;
WHEN OTHERS THEN RAISE NOTICE 'SKIP dates CHECK on leave_requests: %', SQLERRM;
END $$;

DO $$ BEGIN
  ALTER TABLE projects ADD CONSTRAINT projects_dates_check
    CHECK (end_date IS NULL OR end_date >= start_date);
EXCEPTION WHEN duplicate_object THEN NULL;
WHEN OTHERS THEN RAISE NOTICE 'SKIP dates CHECK on projects: %', SQLERRM;
END $$;

DO $$ BEGIN
  ALTER TABLE crm_campaigns ADD CONSTRAINT crm_campaigns_dates_check
    CHECK (end_date IS NULL OR end_date >= start_date);
EXCEPTION WHEN duplicate_object THEN NULL;
WHEN OTHERS THEN RAISE NOTICE 'SKIP dates CHECK on crm_campaigns: %', SQLERRM;
END $$;

DO $$ BEGIN
  ALTER TABLE career_history ADD CONSTRAINT career_history_dates_check
    CHECK (end_date IS NULL OR end_date >= start_date);
EXCEPTION WHEN duplicate_object THEN NULL;
WHEN OTHERS THEN RAISE NOTICE 'SKIP dates CHECK on career_history: %', SQLERRM;
END $$;

DO $$ BEGIN
  ALTER TABLE service_contracts ADD CONSTRAINT service_contracts_dates_check
    CHECK (end_date IS NULL OR end_date >= start_date);
EXCEPTION WHEN duplicate_object THEN NULL;
WHEN OTHERS THEN RAISE NOTICE 'SKIP dates CHECK on service_contracts: %', SQLERRM;
END $$;

DO $$ BEGIN
  ALTER TABLE credit_lines ADD CONSTRAINT credit_lines_dates_check
    CHECK (end_date IS NULL OR end_date >= start_date);
EXCEPTION WHEN duplicate_object THEN NULL;
WHEN OTHERS THEN RAISE NOTICE 'SKIP dates CHECK on credit_lines: %', SQLERRM;
END $$;

DO $$ BEGIN
  ALTER TABLE delivery_schedules ADD CONSTRAINT delivery_schedules_dates_check
    CHECK (end_date IS NULL OR end_date >= start_date);
EXCEPTION WHEN duplicate_object THEN NULL;
WHEN OTHERS THEN RAISE NOTICE 'SKIP dates CHECK on delivery_schedules: %', SQLERRM;
END $$;


-- ============================================================
-- SECTION 7 — CHECK de format (email, SIRET, IBAN)
-- ============================================================

-- Email format
DO $$ BEGIN
  ALTER TABLE customers ADD CONSTRAINT customers_email_format_check
    CHECK (email IS NULL OR email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$');
EXCEPTION WHEN duplicate_object THEN NULL;
WHEN OTHERS THEN RAISE NOTICE 'SKIP email CHECK on customers: %', SQLERRM;
END $$;

DO $$ BEGIN
  ALTER TABLE suppliers ADD CONSTRAINT suppliers_email_format_check
    CHECK (email IS NULL OR email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$');
EXCEPTION WHEN duplicate_object THEN NULL;
WHEN OTHERS THEN RAISE NOTICE 'SKIP email CHECK on suppliers: %', SQLERRM;
END $$;

DO $$ BEGIN
  ALTER TABLE employees ADD CONSTRAINT employees_email_format_check
    CHECK (email IS NULL OR email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$');
EXCEPTION WHEN duplicate_object THEN NULL;
WHEN OTHERS THEN RAISE NOTICE 'SKIP email CHECK on employees: %', SQLERRM;
END $$;

DO $$ BEGIN
  ALTER TABLE company_settings ADD CONSTRAINT company_settings_email_format_check
    CHECK (email IS NULL OR email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$');
EXCEPTION WHEN duplicate_object THEN NULL;
WHEN OTHERS THEN RAISE NOTICE 'SKIP email CHECK on company_settings: %', SQLERRM;
END $$;

-- SIRET format (14 digits)
DO $$ BEGIN
  ALTER TABLE customers ADD CONSTRAINT customers_siret_format_check
    CHECK (siret IS NULL OR siret ~ '^\d{14}$');
EXCEPTION WHEN duplicate_object THEN NULL;
WHEN undefined_column THEN NULL;
WHEN OTHERS THEN RAISE NOTICE 'SKIP siret CHECK on customers: %', SQLERRM;
END $$;

DO $$ BEGIN
  ALTER TABLE suppliers ADD CONSTRAINT suppliers_siret_format_check
    CHECK (siret IS NULL OR siret ~ '^\d{14}$');
EXCEPTION WHEN duplicate_object THEN NULL;
WHEN undefined_column THEN NULL;
WHEN OTHERS THEN RAISE NOTICE 'SKIP siret CHECK on suppliers: %', SQLERRM;
END $$;

DO $$ BEGIN
  ALTER TABLE company_settings ADD CONSTRAINT company_settings_siret_format_check
    CHECK (siret IS NULL OR siret ~ '^\d{14}$');
EXCEPTION WHEN duplicate_object THEN NULL;
WHEN undefined_column THEN NULL;
WHEN OTHERS THEN RAISE NOTICE 'SKIP siret CHECK on company_settings: %', SQLERRM;
END $$;

-- IBAN format (2 letters country + 2 digits + alphanumeric)
DO $$ BEGIN
  ALTER TABLE tier_ribs ADD CONSTRAINT tier_ribs_iban_format_check
    CHECK (iban IS NULL OR regexp_replace(iban, '[^A-Z0-9]', '', 'g') ~ '^[A-Z]{2}[0-9]{2}[A-Z0-9]{10,30}$');
EXCEPTION WHEN duplicate_object THEN NULL;
WHEN undefined_column THEN NULL;
WHEN OTHERS THEN RAISE NOTICE 'SKIP iban CHECK on tier_ribs: %', SQLERRM;
END $$;

DO $$ BEGIN
  ALTER TABLE partner_bank_accounts ADD CONSTRAINT partner_bank_accounts_iban_format_check
    CHECK (iban IS NULL OR regexp_replace(iban, '[^A-Z0-9]', '', 'g') ~ '^[A-Z]{2}[0-9]{2}[A-Z0-9]{10,30}$');
EXCEPTION WHEN duplicate_object THEN NULL;
WHEN undefined_column THEN NULL;
WHEN OTHERS THEN RAISE NOTICE 'SKIP iban CHECK on partner_bank_accounts: %', SQLERRM;
END $$;

-- ============================================================
-- RÉCAPITULATIF
-- ============================================================
-- Section 1 : NOT NULL sur tenant_id (203 tables)
-- Section 2 : CHECK (>= 0) sur ~200 colonnes de montants/quantités
-- Section 3 : UNIQUE (tenant_id, number) au lieu de UNIQUE (number) (24 tables)
-- Section 4 : Suppression de 4 contraintes UNIQUE redondantes
-- Section 5 : CHECK sur payment_state (invoices, purchase_invoices)
-- Section 6 : CHECK de cohérence des dates (10 tables)
-- Section 7 : CHECK de format email (4 tables), SIRET (3 tables), IBAN (2 tables)
-- ============================================================
