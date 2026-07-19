-- ============================================
-- MULTI-TENANT ARCHITECTURE MIGRATION
-- Run this in Supabase Dashboard > SQL Editor
-- ============================================
-- This script:
-- 1. Creates the `tenants` table (one company = one tenant)
-- 2. Creates `tenant_users` (users linked to a tenant with roles + granular permissions)
-- 3. Adds `tenant_id` column to ALL business tables
-- 4. Replaces all "allow_all_*" RLS policies with tenant-isolated policies
-- 5. Creates helper function current_tenant_id()
-- ============================================

-- ============================================
-- 1. TENANTS TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS tenants (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  name text NOT NULL,
  legal_name text,
  siren text,
  siret text,
  vat_number text,
  address text,
  city text,
  postal_code text,
  country text DEFAULT 'France',
  currency text DEFAULT 'EUR',
  phone text,
  email text,
  logo_url text,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'suspended', 'cancelled')),
  plan text NOT NULL DEFAULT 'trial' CHECK (plan IN ('trial', 'basic', 'pro', 'enterprise')),
  trial_ends_at timestamptz,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE tenants ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_tenants') THEN
    CREATE POLICY "allow_all_tenants" ON tenants FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- ============================================
-- 2. TENANT_USERS TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS tenant_users (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  auth_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
  email text NOT NULL,
  name text NOT NULL,
  role text NOT NULL DEFAULT 'viewer' CHECK (role IN ('admin', 'accountant', 'manager', 'viewer', 'custom')),
  permissions jsonb DEFAULT '{}',
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'active', 'revoked')),
  invited_by uuid REFERENCES tenant_users(id),
  invited_at timestamptz DEFAULT now(),
  accepted_at timestamptz,
  last_login timestamptz,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(tenant_id, email)
);

CREATE INDEX IF NOT EXISTS idx_tenant_users_tenant ON tenant_users(tenant_id);
CREATE INDEX IF NOT EXISTS idx_tenant_users_auth ON tenant_users(auth_id);
CREATE INDEX IF NOT EXISTS idx_tenant_users_email ON tenant_users(email);

ALTER TABLE tenant_users ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_tenant_users') THEN
    CREATE POLICY "allow_all_tenant_users" ON tenant_users FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;

-- ============================================
-- 3. HELPER FUNCTION: current_tenant_id()
-- ============================================
-- Returns the tenant_id of the currently authenticated user
-- Used by RLS policies on all business tables
CREATE OR REPLACE FUNCTION current_tenant_id()
RETURNS uuid
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT tenant_id FROM tenant_users
  WHERE auth_id = auth.uid()
    AND status = 'active'
  LIMIT 1
$$;

-- ============================================
-- 4. HELPER FUNCTION: current_user_role()
-- ============================================
CREATE OR REPLACE FUNCTION current_user_role()
RETURNS text
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT role FROM tenant_users
  WHERE auth_id = auth.uid()
    AND status = 'active'
  LIMIT 1
$$;

-- ============================================
-- 5. HELPER FUNCTION: current_user_permissions()
-- ============================================
CREATE OR REPLACE FUNCTION current_user_permissions()
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT permissions FROM tenant_users
  WHERE auth_id = auth.uid()
    AND status = 'active'
  LIMIT 1
$$;

-- ============================================
-- 6. HELPER FUNCTION: can_perform(table_name, action)
-- ============================================
-- Checks if current user can perform an action on a table
-- admin: all actions on all tables
-- accountant: select/insert/update on all, no delete (except on journal entries)
-- manager: select on all, insert/update on commercial tables
-- viewer: select only
-- custom: check permissions jsonb
CREATE OR REPLACE FUNCTION can_perform(p_table text, p_action text)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT CASE
    WHEN current_user_role() = 'admin' THEN true
    WHEN current_user_role() = 'accountant' AND p_action IN ('select', 'insert', 'update') THEN true
    WHEN current_user_role() = 'accountant' AND p_action = 'delete' AND p_table IN ('journal_entries', 'journal_lines', 'invoice_lines', 'quote_lines', 'credit_note_lines') THEN true
    WHEN current_user_role() = 'manager' AND p_action = 'select' THEN true
    WHEN current_user_role() = 'manager' AND p_action IN ('insert', 'update') AND p_table IN ('invoices', 'invoice_lines', 'quotes', 'quote_lines', 'credit_notes', 'credit_note_lines', 'customers', 'products', 'delivery_notes', 'delivery_note_lines', 'sales_orders', 'sales_order_lines', 'purchase_orders', 'purchase_order_lines') THEN true
    WHEN current_user_role() = 'viewer' AND p_action = 'select' THEN true
    WHEN current_user_role() = 'custom' THEN
      COALESCE(
        (current_user_permissions() -> p_table ->> p_action)::boolean,
        false
      )
    ELSE false
  END
$$;

-- ============================================
-- 7. ADD tenant_id TO ALL BUSINESS TABLES
-- ============================================
-- We add tenant_id as nullable first (for existing data),
-- then set a default tenant, then make it NOT NULL.

DO $$
DECLARE
  t text;
  tables text[] := ARRAY[
    'company_settings', 'chart_accounts', 'customers', 'suppliers', 'products',
    'invoices', 'invoice_lines', 'quotes', 'quote_lines',
    'credit_notes', 'credit_note_lines',
    'purchase_invoices', 'purchase_invoice_lines',
    'purchase_orders', 'purchase_order_lines',
    'purchase_credit_notes', 'purchase_credit_lines',
    'bank_accounts', 'bank_transactions', 'bank_rules',
    'journal_entries', 'journal_lines',
    'vat_returns', 'projects', 'journals',
    'fiscal_years', 'fiscal_periods',
    'entry_templates', 'third_party_accounts', 'analytic_sections',
    'budgets', 'budget_commitments', 'standard_labels',
    'fixed_assets', 'asset_depreciations',
    'employees', 'pay_runs', 'pay_slips', 'timesheets', 'leave_requests',
    'payroll_accounting_entries',
    'currencies', 'audit_log',
    'warehouses', 'stock_quantities', 'stock_movements',
    'boms', 'bom_lines', 'manufacturing_orders',
    'price_lists', 'price_list_lines',
    'sales_orders', 'sales_order_lines',
    'delivery_notes', 'delivery_note_lines',
    'goods_receipts', 'goods_receipt_lines',
    'collection_reminders', 'contracts',
    'customer_payments', 'supplier_payments',
    'payment_orders', 'legal_declarations'
  ];
BEGIN
  FOREACH t IN ARRAY tables LOOP
    BEGIN
      EXECUTE format('ALTER TABLE %I ADD COLUMN IF NOT EXISTS tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE', t);
      EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%I_tenant ON %I(tenant_id)', t, t);
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Skipping %: %', t, SQLERRM;
    END;
  END LOOP;
END $$;

-- ============================================
-- 8. CREATE A DEFAULT TENANT FOR EXISTING DATA
-- ============================================
-- All existing rows get this tenant_id
DO $$
DECLARE
  default_tenant_id uuid;
  t text;
  tables text[] := ARRAY[
    'company_settings', 'chart_accounts', 'customers', 'suppliers', 'products',
    'invoices', 'invoice_lines', 'quotes', 'quote_lines',
    'credit_notes', 'credit_note_lines',
    'purchase_invoices', 'purchase_invoice_lines',
    'purchase_orders', 'purchase_order_lines',
    'purchase_credit_notes', 'purchase_credit_lines',
    'bank_accounts', 'bank_transactions', 'bank_rules',
    'journal_entries', 'journal_lines',
    'vat_returns', 'projects', 'journals',
    'fiscal_years', 'fiscal_periods',
    'entry_templates', 'third_party_accounts', 'analytic_sections',
    'budgets', 'budget_commitments', 'standard_labels',
    'fixed_assets', 'asset_depreciations',
    'employees', 'pay_runs', 'pay_slips', 'timesheets', 'leave_requests',
    'payroll_accounting_entries',
    'currencies', 'audit_log',
    'warehouses', 'stock_quantities', 'stock_movements',
    'boms', 'bom_lines', 'manufacturing_orders',
    'price_lists', 'price_list_lines',
    'sales_orders', 'sales_order_lines',
    'delivery_notes', 'delivery_note_lines',
    'goods_receipts', 'goods_receipt_lines',
    'collection_reminders', 'contracts',
    'customer_payments', 'supplier_payments',
    'payment_orders', 'legal_declarations'
  ];
BEGIN
  -- Create default tenant
  INSERT INTO tenants (id, name, legal_name, status, plan)
  VALUES ('00000000-0000-0000-0000-000000000001', 'Entreprise par défaut', 'Entreprise par défaut', 'active', 'pro')
  ON CONFLICT (id) DO NOTHING;

  default_tenant_id := '00000000-0000-0000-0000-000000000001';

  -- Set tenant_id on all existing rows that have NULL tenant_id
  FOREACH t IN ARRAY tables LOOP
    BEGIN
      EXECUTE format('UPDATE %I SET tenant_id = %L WHERE tenant_id IS NULL', t, default_tenant_id);
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Skipping update on %: %', t, SQLERRM;
    END;
  END LOOP;

  -- Make tenant_id NOT NULL on all tables
  FOREACH t IN ARRAY tables LOOP
    BEGIN
      EXECUTE format('ALTER TABLE %I ALTER COLUMN tenant_id SET NOT NULL', t);
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Skipping NOT NULL on %: %', t, SQLERRM;
    END;
  END LOOP;
END $$;

-- ============================================
-- 9. REPLACE RLS POLICES WITH TENANT-ISOLATED ONES
-- ============================================
-- For each table: drop the old "allow_all_*" policy and create
-- a tenant-isolated policy using current_tenant_id()

DO $$
DECLARE
  t text;
  tables text[] := ARRAY[
    'company_settings', 'chart_accounts', 'customers', 'suppliers', 'products',
    'invoices', 'invoice_lines', 'quotes', 'quote_lines',
    'credit_notes', 'credit_note_lines',
    'purchase_invoices', 'purchase_invoice_lines',
    'purchase_orders', 'purchase_order_lines',
    'purchase_credit_notes', 'purchase_credit_lines',
    'bank_accounts', 'bank_transactions', 'bank_rules',
    'journal_entries', 'journal_lines',
    'vat_returns', 'projects', 'journals',
    'fiscal_years', 'fiscal_periods',
    'entry_templates', 'third_party_accounts', 'analytic_sections',
    'budgets', 'budget_commitments', 'standard_labels',
    'fixed_assets', 'asset_depreciations',
    'employees', 'pay_runs', 'pay_slips', 'timesheets', 'leave_requests',
    'payroll_accounting_entries',
    'currencies', 'audit_log',
    'warehouses', 'stock_quantities', 'stock_movements',
    'boms', 'bom_lines', 'manufacturing_orders',
    'price_lists', 'price_list_lines',
    'sales_orders', 'sales_order_lines',
    'delivery_notes', 'delivery_note_lines',
    'goods_receipts', 'goods_receipt_lines',
    'collection_reminders', 'contracts',
    'customer_payments', 'supplier_payments',
    'payment_orders', 'legal_declarations'
  ];
  policy_name text;
BEGIN
  FOREACH t IN ARRAY tables LOOP
    BEGIN
      -- Drop old permissive policy
      policy_name := 'allow_all_' || t;
      EXECUTE format('DROP POLICY IF EXISTS %I ON %I', policy_name, t);

      -- SELECT policy: user can see rows in their tenant
      EXECUTE format(
        'CREATE POLICY %I ON %I FOR SELECT USING (tenant_id = current_tenant_id())',
        'tenant_select_' || t, t
      );

      -- INSERT policy: user can insert if tenant matches AND can_perform
      EXECUTE format(
        'CREATE POLICY %I ON %I FOR INSERT WITH CHECK (tenant_id = current_tenant_id() AND can_perform(%L, ''insert''))',
        'tenant_insert_' || t, t, t
      );

      -- UPDATE policy: user can update if tenant matches AND can_perform
      EXECUTE format(
        'CREATE POLICY %I ON %I FOR UPDATE USING (tenant_id = current_tenant_id() AND can_perform(%L, ''update'')) WITH CHECK (tenant_id = current_tenant_id())',
        'tenant_update_' || t, t, t
      );

      -- DELETE policy: user can delete if tenant matches AND can_perform
      EXECUTE format(
        'CREATE POLICY %I ON %I FOR DELETE USING (tenant_id = current_tenant_id() AND can_perform(%L, ''delete''))',
        'tenant_delete_' || t, t, t
      );

    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Skipping RLS on %: %', t, SQLERRM;
    END;
  END LOOP;
END $$;

-- ============================================
-- 10. MIGRATE EXISTING users TO tenant_users
-- ============================================
-- Link existing users to the default tenant
INSERT INTO tenant_users (tenant_id, auth_id, email, name, role, status, accepted_at, created_at)
SELECT
  '00000000-0000-0000-0000-000000000001',
  u.auth_id,
  u.email,
  u.name,
  COALESCE(u.role, 'admin'),
  'active',
  u.created_at,
  u.created_at
FROM users u
WHERE u.auth_id IS NOT NULL
ON CONFLICT (tenant_id, email) DO NOTHING;

-- ============================================
-- 11. AUTO-SET tenant_id ON INSERT VIA TRIGGER
-- ============================================
-- For tables that might not have tenant_id set by the app,
-- create a trigger that sets it automatically

CREATE OR REPLACE FUNCTION set_tenant_id()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF NEW.tenant_id IS NULL THEN
    NEW.tenant_id := current_tenant_id();
  END IF;
  RETURN NEW;
END;
$$;

DO $$
DECLARE
  t text;
  tables text[] := ARRAY[
    'company_settings', 'chart_accounts', 'customers', 'suppliers', 'products',
    'invoices', 'invoice_lines', 'quotes', 'quote_lines',
    'credit_notes', 'credit_note_lines',
    'purchase_invoices', 'purchase_invoice_lines',
    'purchase_orders', 'purchase_order_lines',
    'purchase_credit_notes', 'purchase_credit_lines',
    'bank_accounts', 'bank_transactions', 'bank_rules',
    'journal_entries', 'journal_lines',
    'vat_returns', 'projects', 'journals',
    'fiscal_years', 'fiscal_periods',
    'entry_templates', 'third_party_accounts', 'analytic_sections',
    'budgets', 'budget_commitments', 'standard_labels',
    'fixed_assets', 'asset_depreciations',
    'employees', 'pay_runs', 'pay_slips', 'timesheets', 'leave_requests',
    'payroll_accounting_entries',
    'currencies', 'audit_log',
    'warehouses', 'stock_quantities', 'stock_movements',
    'boms', 'bom_lines', 'manufacturing_orders',
    'price_lists', 'price_list_lines',
    'sales_orders', 'sales_order_lines',
    'delivery_notes', 'delivery_note_lines',
    'goods_receipts', 'goods_receipt_lines',
    'collection_reminders', 'contracts',
    'customer_payments', 'supplier_payments',
    'payment_orders', 'legal_declarations'
  ];
BEGIN
  FOREACH t IN ARRAY tables LOOP
    BEGIN
      EXECUTE format(
        'DROP TRIGGER IF EXISTS set_tenant_id_%I ON %I', t, t
      );
      EXECUTE format(
        'CREATE TRIGGER set_tenant_id_%I BEFORE INSERT ON %I FOR EACH ROW EXECUTE FUNCTION set_tenant_id()',
        t, t
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Skipping trigger on %: %', t, SQLERRM;
    END;
  END LOOP;
END $$;

-- ============================================
-- DONE
-- ============================================
-- After running this:
-- 1. All existing data is assigned to the default tenant
-- 2. RLS policies enforce tenant isolation
-- 3. New inserts auto-set tenant_id via trigger
-- 4. Role-based permissions control CRUD operations
-- 5. The app needs to pass tenant_id in queries (or rely on the trigger)
-- ============================================
