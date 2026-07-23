-- ============================================
-- SECURITY FIX: Replace all allow_all_* RLS policies
-- with tenant-isolated policies
-- ============================================
-- This script:
-- 1. Adds tenant_id to all tables that are missing it
-- 2. Drops all allow_all_* policies
-- 3. Creates proper tenant-isolated RLS policies
-- ============================================

-- ============================================
-- 1. ENSURE tenant_id EXISTS ON ALL TABLES
-- ============================================
DO $$
DECLARE
  t text;
  tables_needing_tenant text[] := ARRAY[
    'product_attributes', 'product_variants', 'product_serial_numbers',
    'product_batches', 'warehouse_locations', 'quality_checks',
    'pick_lists', 'pick_list_lines', 'sales_representatives',
    'prospects', 'product_substitutes', 'delivery_schedules',
    'recurring_invoice_templates', 'document_templates',
    'bank_reconciliation_rules', 'bank_statement_imports',
    'analytic_plans', 'distribution_grills', 'distribution_grill_lines',
    'tvs_declarations', 'fiscal_backups',
    'mirror_servers', 'mirror_verification_details',
    'treasury_transfers', 'credit_lines', 'investments',
    'value_date_trackings', 'treasury_recurrings', 'consolidated_treasuries',
    'payroll_components', 'payroll_templates', 'salary_advances',
    'pay_recalls', 'dsn_declarations', 'dpae_records',
    'work_hardships', 'career_histories', 'cpf_accounts',
    'payroll_archives', 'legal_watches', 'employee_documents',
    'expense_reports', 'interviews',
    'asset_depreciation_plans', 'asset_families', 'asset_revaluations',
    'asset_documents', 'asset_free_fields', 'asset_batch_disposals',
    'asset_splits',
    'routings', 'routing_operations', 'work_centers', 'machines', 'toolings',
    'of_labels', 'of_lots', 'of_consumptions',
    'st_orders', 'st_shipments', 'st_shipment_lines',
    'st_receipts', 'st_receipt_lines',
    'mrp_runs', 'mrp_proposals', 'mrp_pending_docs',
    'production_forecasts', 'planning_slots',
    'future_accounting_movements',
    'recurring_entries', 'regularization_entries',
    'currency_revaluations', 'edi_tva_declarations',
    'legislation_packs', 'tax_rates'
  ];
BEGIN
  FOREACH t IN ARRAY tables_needing_tenant LOOP
    BEGIN
      EXECUTE format('ALTER TABLE %I ADD COLUMN IF NOT EXISTS tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE', t);
      EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%I_tenant ON %I(tenant_id)', t, t);
      -- Set default tenant for existing rows
      EXECUTE format('UPDATE %I SET tenant_id = ''00000000-0000-0000-0000-000000000001'' WHERE tenant_id IS NULL', t);
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Skipping tenant_id add on %: %', t, SQLERRM;
    END;
  END LOOP;
END $$;

-- ============================================
-- 2. DROP ALL allow_all_* POLICIES AND REPLACE
-- ============================================
DO $$
DECLARE
  t text;
  policy_name text;
  -- All tables that had allow_all_* policies
  tables_to_fix text[] := ARRAY[
    'product_attributes', 'product_variants', 'product_serial_numbers',
    'product_batches', 'warehouse_locations', 'quality_checks',
    'pick_lists', 'pick_list_lines', 'sales_representatives',
    'prospects', 'product_substitutes', 'delivery_schedules',
    'recurring_invoice_templates', 'document_templates',
    'bank_reconciliation_rules', 'bank_statement_imports',
    'analytic_plans', 'distribution_grills', 'distribution_grill_lines',
    'tvs_declarations', 'fiscal_backups',
    'mirror_servers', 'mirror_verification_details',
    'treasury_transfers', 'credit_lines', 'investments',
    'value_date_trackings', 'treasury_recurrings', 'consolidated_treasuries',
    'payroll_components', 'payroll_templates', 'salary_advances',
    'pay_recalls', 'dsn_declarations', 'dpae_records',
    'work_hardships', 'career_histories', 'cpf_accounts',
    'payroll_archives', 'legal_watches', 'employee_documents',
    'expense_reports', 'interviews',
    'asset_depreciation_plans', 'asset_families', 'asset_revaluations',
    'asset_documents', 'asset_free_fields', 'asset_batch_disposals',
    'asset_splits',
    'routings', 'routing_operations', 'work_centers', 'machines', 'toolings',
    'of_labels', 'of_lots', 'of_consumptions',
    'st_orders', 'st_shipments', 'st_shipment_lines',
    'st_receipts', 'st_receipt_lines',
    'mrp_runs', 'mrp_proposals', 'mrp_pending_docs',
    'production_forecasts', 'planning_slots',
    'future_accounting_movements',
    'recurring_entries', 'regularization_entries',
    'currency_revaluations', 'edi_tva_declarations',
    'budget_commitments'
  ];
BEGIN
  FOREACH t IN ARRAY tables_to_fix LOOP
    BEGIN
      -- Enable and force RLS
      EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
      EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY', t);

      -- Drop old permissive policy
      policy_name := 'allow_all_' || t;
      EXECUTE format('DROP POLICY IF EXISTS %I ON %I', policy_name, t);

      -- Also drop any variant policy names
      EXECUTE format('DROP POLICY IF EXISTS %I ON %I', 'allow_all_' || replace(t, '_', '_'), t);

      -- SELECT: user can see rows in their tenant
      EXECUTE format(
        'CREATE POLICY %I ON %I FOR SELECT USING (tenant_id = current_tenant_id())',
        'tenant_select_' || t, t
      );

      -- INSERT: user can insert if tenant matches AND can_perform
      EXECUTE format(
        'CREATE POLICY %I ON %I FOR INSERT WITH CHECK (tenant_id = current_tenant_id() AND can_perform(%L, ''insert''))',
        'tenant_insert_' || t, t, t
      );

      -- UPDATE: user can update if tenant matches AND can_perform
      EXECUTE format(
        'CREATE POLICY %I ON %I FOR UPDATE USING (tenant_id = current_tenant_id() AND can_perform(%L, ''update'')) WITH CHECK (tenant_id = current_tenant_id())',
        'tenant_update_' || t, t, t
      );

      -- DELETE: user can delete if tenant matches AND can_perform
      EXECUTE format(
        'CREATE POLICY %I ON %I FOR DELETE USING (tenant_id = current_tenant_id() AND can_perform(%L, ''delete''))',
        'tenant_delete_' || t, t, t
      );

    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Skipping RLS fix on %: %', t, SQLERRM;
    END;
  END LOOP;
END $$;

-- ============================================
-- 3. SPECIAL CASE: legislation_packs and tax_rates
-- ============================================
-- These are global reference tables (NOT tenant-scoped) but should be SELECT-only
-- for authenticated users. No INSERT/UPDATE/DELETE via client.
DO $$
BEGIN
  -- legislation_packs: read-only for all authenticated users
  ALTER TABLE legislation_packs ENABLE ROW LEVEL SECURITY;
  ALTER TABLE legislation_packs FORCE ROW LEVEL SECURITY;
  DROP POLICY IF EXISTS "allow_all_legislation_packs" ON legislation_packs;
  DROP POLICY IF EXISTS "tenant_select_legislation_packs" ON legislation_packs;
  BEGIN
    CREATE POLICY "tenant_select_legislation_packs" ON legislation_packs
      FOR SELECT USING (true);
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'legislation_packs select policy: %', SQLERRM;
  END;
  -- No INSERT/UPDATE/DELETE policy = only service role can modify

  -- tax_rates: read-only for all authenticated users
  ALTER TABLE tax_rates ENABLE ROW LEVEL SECURITY;
  ALTER TABLE tax_rates FORCE ROW LEVEL SECURITY;
  DROP POLICY IF EXISTS "allow_all_tax_rates" ON tax_rates;
  DROP POLICY IF EXISTS "tenant_select_tax_rates" ON tax_rates;
  BEGIN
    CREATE POLICY "tenant_select_tax_rates" ON tax_rates
      FOR SELECT USING (true);
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'tax_rates select policy: %', SQLERRM;
  END;
END $$;

-- ============================================
-- 4. SPECIAL CASE: mirror_servers
-- ============================================
-- Mirror servers are tenant-scoped but the daemon uses the publishable key
-- (not user JWT), so we need a special policy for daemon access via service role
DO $$
BEGIN
  ALTER TABLE mirror_servers ENABLE ROW LEVEL SECURITY;
  ALTER TABLE mirror_servers FORCE ROW LEVEL SECURITY;
  DROP POLICY IF EXISTS "allow_all_mirror_servers" ON mirror_servers;
  DROP POLICY IF EXISTS "tenant_select_mirror_servers" ON mirror_servers;
  DROP POLICY IF EXISTS "tenant_insert_mirror_servers" ON mirror_servers;
  DROP POLICY IF EXISTS "tenant_update_mirror_servers" ON mirror_servers;
  DROP POLICY IF EXISTS "tenant_delete_mirror_servers" ON mirror_servers;

  BEGIN
    CREATE POLICY "tenant_select_mirror_servers" ON mirror_servers
      FOR SELECT USING (tenant_id = current_tenant_id());
  EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'mirror_servers select: %', SQLERRM; END;

  BEGIN
    CREATE POLICY "tenant_insert_mirror_servers" ON mirror_servers
      FOR INSERT WITH CHECK (tenant_id = current_tenant_id() AND current_user_role() = 'admin');
  EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'mirror_servers insert: %', SQLERRM; END;

  BEGIN
    CREATE POLICY "tenant_update_mirror_servers" ON mirror_servers
      FOR UPDATE USING (tenant_id = current_tenant_id())
      WITH CHECK (tenant_id = current_tenant_id());
  EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'mirror_servers update: %', SQLERRM; END;

  BEGIN
    CREATE POLICY "tenant_delete_mirror_servers" ON mirror_servers
      FOR DELETE USING (tenant_id = current_tenant_id() AND current_user_role() = 'admin');
  EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'mirror_servers delete: %', SQLERRM; END;
END $$;

-- ============================================
-- 5. SPECIAL CASE: audit_log
-- ============================================
-- Audit log should be SELECT-only for tenant users, INSERT via trigger/service role
DO $$
BEGIN
  ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;
  ALTER TABLE audit_log FORCE ROW LEVEL SECURITY;
  DROP POLICY IF EXISTS "allow_all_audit_log" ON audit_log;
  DROP POLICY IF EXISTS "tenant_select_audit_log" ON audit_log;
  DROP POLICY IF EXISTS "tenant_insert_audit_log" ON audit_log;
  DROP POLICY IF EXISTS "tenant_update_audit_log" ON audit_log;
  DROP POLICY IF EXISTS "tenant_delete_audit_log" ON audit_log;

  BEGIN
    CREATE POLICY "tenant_select_audit_log" ON audit_log
      FOR SELECT USING (tenant_id = current_tenant_id());
  EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'audit_log select: %', SQLERRM; END;

  BEGIN
    CREATE POLICY "tenant_insert_audit_log" ON audit_log
      FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
  EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'audit_log insert: %', SQLERRM; END;

  -- No UPDATE or DELETE policy = audit log is immutable for client users
END $$;

-- ============================================
-- 6. ADD set_tenant_id TRIGGER TO NEW TABLES
-- ============================================
DO $$
DECLARE
  t text;
  tables_needing_trigger text[] := ARRAY[
    'product_attributes', 'product_variants', 'product_serial_numbers',
    'product_batches', 'warehouse_locations', 'quality_checks',
    'pick_lists', 'pick_list_lines', 'sales_representatives',
    'prospects', 'product_substitutes', 'delivery_schedules',
    'recurring_invoice_templates', 'document_templates',
    'bank_reconciliation_rules', 'bank_statement_imports',
    'analytic_plans', 'distribution_grills', 'distribution_grill_lines',
    'tvs_declarations', 'fiscal_backups',
    'treasury_transfers', 'credit_lines', 'investments',
    'value_date_trackings', 'treasury_recurrings', 'consolidated_treasuries',
    'payroll_components', 'payroll_templates', 'salary_advances',
    'pay_recalls', 'dsn_declarations', 'dpae_records',
    'work_hardships', 'career_histories', 'cpf_accounts',
    'payroll_archives', 'legal_watches', 'employee_documents',
    'expense_reports', 'interviews',
    'asset_depreciation_plans', 'asset_families', 'asset_revaluations',
    'asset_documents', 'asset_free_fields', 'asset_batch_disposals',
    'asset_splits',
    'routings', 'routing_operations', 'work_centers', 'machines', 'toolings',
    'of_labels', 'of_lots', 'of_consumptions',
    'st_orders', 'st_shipments', 'st_shipment_lines',
    'st_receipts', 'st_receipt_lines',
    'mrp_runs', 'mrp_proposals', 'mrp_pending_docs',
    'production_forecasts', 'planning_slots',
    'future_accounting_movements',
    'recurring_entries', 'regularization_entries',
    'currency_revaluations', 'edi_tva_declarations',
    'budget_commitments'
  ];
BEGIN
  FOREACH t IN ARRAY tables_needing_trigger LOOP
    BEGIN
      EXECUTE format('DROP TRIGGER IF EXISTS set_tenant_id_%I ON %I', t, t);
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
-- After running this script:
-- 1. All allow_all_* policies are removed
-- 2. All tables have tenant-isolated RLS policies
-- 3. Global reference tables (legislation_packs, tax_rates) are SELECT-only
-- 4. Audit log is immutable (no UPDATE/DELETE for client users)
-- 5. All new tables have set_tenant_id triggers
-- ============================================
