-- ============================================
-- FIX MULTI-TENANT UNIQUE CONSTRAINTS
-- Run this in Supabase Dashboard > SQL Editor
-- ============================================
-- PROBLEM: Many business tables declared columns as globally UNIQUE
-- (e.g. chart_accounts.code, journals.code, invoices.number...).
-- In a multi-tenant system this makes it impossible for two tenants
-- to both have code '512000' or invoice number 'FA-2025-001', etc.
--
-- FIX: Replace each global UNIQUE(col) with a per-tenant UNIQUE(tenant_id, col).
--
-- PREREQUISITE: multi_tenant_migration.sql must have been run first
-- (all these tables must already have a tenant_id column).
-- ============================================

-- --------------------------------------------
-- 1. Drop the FK that depends on journals(code)
-- --------------------------------------------
-- entry_templates.journal_code references journals(code). Once journals.code
-- is no longer globally unique, this FK can no longer exist as-is. We drop it;
-- tenant isolation + application logic enforce integrity instead.
DO $$ BEGIN
  ALTER TABLE entry_templates DROP CONSTRAINT IF EXISTS entry_templates_journal_code_fkey;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Skip drop entry_templates_journal_code_fkey: %', SQLERRM;
END $$;

-- --------------------------------------------
-- 2. Convert each global UNIQUE(col) -> UNIQUE(tenant_id, col)
-- --------------------------------------------
DO $$
DECLARE
  rec record;
  -- (table, unique_column) pairs to convert
  pairs text[][] := ARRAY[
    ARRAY['chart_accounts', 'code'],
    ARRAY['journals', 'code'],
    ARRAY['fiscal_years', 'code'],
    ARRAY['third_party_accounts', 'code'],
    ARRAY['analytic_sections', 'code'],
    ARRAY['standard_labels', 'label'],
    ARRAY['products', 'sku'],
    ARRAY['fixed_assets', 'code'],
    ARRAY['currencies', 'code'],
    ARRAY['invoices', 'number'],
    ARRAY['quotes', 'number'],
    ARRAY['credit_notes', 'number'],
    ARRAY['purchase_invoices', 'number'],
    ARRAY['purchase_credit_notes', 'number'],
    ARRAY['journal_entries', 'number'],
    ARRAY['pay_runs', 'number']
  ];
  tbl text;
  col text;
  old_constraint text;
  new_constraint text;
  i int;
BEGIN
  FOR i IN 1 .. array_length(pairs, 1) LOOP
    tbl := pairs[i][1];
    col := pairs[i][2];
    old_constraint := tbl || '_' || col || '_key';
    new_constraint := tbl || '_tenant_' || col || '_key';

    BEGIN
      -- Drop the old global unique constraint (default Postgres name <table>_<col>_key)
      EXECUTE format('ALTER TABLE %I DROP CONSTRAINT IF EXISTS %I', tbl, old_constraint);

      -- Also drop any other unique constraint on just that single column,
      -- in case it was named differently.
      FOR rec IN
        SELECT c.conname
        FROM pg_constraint c
        JOIN pg_class t ON t.oid = c.conrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        WHERE t.relname = tbl
          AND n.nspname = 'public'
          AND c.contype = 'u'
          AND array_length(c.conkey, 1) = 1
          AND (SELECT attname FROM pg_attribute WHERE attrelid = t.oid AND attnum = c.conkey[1]) = col
      LOOP
        EXECUTE format('ALTER TABLE %I DROP CONSTRAINT IF EXISTS %I', tbl, rec.conname);
      END LOOP;

      -- Add the new per-tenant composite unique constraint
      EXECUTE format(
        'ALTER TABLE %I ADD CONSTRAINT %I UNIQUE (tenant_id, %I)',
        tbl, new_constraint, col
      );

      RAISE NOTICE 'OK: %(% ) is now unique per tenant', tbl, col;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Skipping %.%: %', tbl, col, SQLERRM;
    END;
  END LOOP;
END $$;

-- ============================================
-- DONE
-- ============================================
-- After running this, two different tenants can independently use the same
-- account codes, journal codes, invoice numbers, SKUs, etc.
-- ============================================
