-- ============================================================
-- 38_security_fix_mirror_and_bank_templates_rls.sql
--
-- Fixes three critical RLS policy vulnerabilities:
-- 1. mirror_servers: allow_all → tenant-isolated (was exposing all tenants' server IPs, machine names, configs)
-- 2. mirror_verification_details: allow_all → tenant-isolated via join to mirror_servers
-- 3. bank_statement_templates: auth.uid() → current_tenant_id() (was broken — auth.uid() ≠ tenant_id)
--
-- Also fixes mirror_servers.tenant_id type: text → uuid
-- ============================================================

-- ============================================
-- 1. FIX mirror_servers RLS
-- ============================================

-- Fix tenant_id type from text to uuid (if not already done)
DO $$
BEGIN
  -- Check if tenant_id is text (not uuid)
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'mirror_servers' AND column_name = 'tenant_id'
      AND data_type = 'text'
  ) THEN
    -- Remove the UNIQUE constraint that uses tenant_id
    ALTER TABLE mirror_servers DROP CONSTRAINT IF EXISTS mirror_servers_tenant_id_key;
    -- Cast text to uuid (will fail if invalid UUIDs exist — that's OK, they shouldn't)
    ALTER TABLE mirror_servers ALTER COLUMN tenant_id TYPE uuid USING tenant_id::uuid;
    -- Recreate unique constraint
    ALTER TABLE mirror_servers ADD CONSTRAINT mirror_servers_tenant_id_key UNIQUE (tenant_id);
    RAISE NOTICE 'Fixed mirror_servers.tenant_id type: text → uuid';
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Could not fix mirror_servers.tenant_id type: %', SQLERRM;
END $$;

-- Enable and force RLS
ALTER TABLE mirror_servers ENABLE ROW LEVEL SECURITY;
ALTER TABLE mirror_servers FORCE ROW LEVEL SECURITY;

-- Drop all existing policies
DROP POLICY IF EXISTS allow_all_mirror_servers ON mirror_servers;
DROP POLICY IF EXISTS tenant_select_mirror_servers ON mirror_servers;
DROP POLICY IF EXISTS tenant_insert_mirror_servers ON mirror_servers;
DROP POLICY IF EXISTS tenant_update_mirror_servers ON mirror_servers;
DROP POLICY IF EXISTS tenant_delete_mirror_servers ON mirror_servers;

-- Create tenant-isolated policies
DO $$ BEGIN
  CREATE POLICY tenant_select_mirror_servers ON mirror_servers
    FOR SELECT USING (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'select policy: %', SQLERRM; END $$;

DO $$ BEGIN
  CREATE POLICY tenant_insert_mirror_servers ON mirror_servers
    FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'insert policy: %', SQLERRM; END $$;

DO $$ BEGIN
  CREATE POLICY tenant_update_mirror_servers ON mirror_servers
    FOR UPDATE USING (tenant_id = current_tenant_id())
    WITH CHECK (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'update policy: %', SQLERRM; END $$;

DO $$ BEGIN
  CREATE POLICY tenant_delete_mirror_servers ON mirror_servers
    FOR DELETE USING (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'delete policy: %', SQLERRM; END $$;

-- ============================================
-- 2. FIX mirror_verification_details RLS
-- ============================================

ALTER TABLE mirror_verification_details ENABLE ROW LEVEL SECURITY;
ALTER TABLE mirror_verification_details FORCE ROW LEVEL SECURITY;

-- Drop all existing policies
DROP POLICY IF EXISTS allow_all_mirror_verification ON mirror_verification_details;
DROP POLICY IF EXISTS tenant_select_mirror_verification ON mirror_verification_details;
DROP POLICY IF EXISTS tenant_insert_mirror_verification ON mirror_verification_details;
DROP POLICY IF EXISTS tenant_update_mirror_verification ON mirror_verification_details;
DROP POLICY IF EXISTS tenant_delete_mirror_verification ON mirror_verification_details;

-- Create tenant-isolated policies via join to mirror_servers
DO $$ BEGIN
  CREATE POLICY tenant_select_mirror_verification ON mirror_verification_details
    FOR SELECT USING (EXISTS (
      SELECT 1 FROM mirror_servers ms
      WHERE ms.id = mirror_server_id AND ms.tenant_id = current_tenant_id()
    ));
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'select policy: %', SQLERRM; END $$;

DO $$ BEGIN
  CREATE POLICY tenant_insert_mirror_verification ON mirror_verification_details
    FOR INSERT WITH CHECK (EXISTS (
      SELECT 1 FROM mirror_servers ms
      WHERE ms.id = mirror_server_id AND ms.tenant_id = current_tenant_id()
    ));
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'insert policy: %', SQLERRM; END $$;

DO $$ BEGIN
  CREATE POLICY tenant_update_mirror_verification ON mirror_verification_details
    FOR UPDATE USING (EXISTS (
      SELECT 1 FROM mirror_servers ms
      WHERE ms.id = mirror_server_id AND ms.tenant_id = current_tenant_id()
    ));
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'update policy: %', SQLERRM; END $$;

DO $$ BEGIN
  CREATE POLICY tenant_delete_mirror_verification ON mirror_verification_details
    FOR DELETE USING (EXISTS (
      SELECT 1 FROM mirror_servers ms
      WHERE ms.id = mirror_server_id AND ms.tenant_id = current_tenant_id()
    ));
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'delete policy: %', SQLERRM; END $$;

-- ============================================
-- 3. FIX bank_statement_templates RLS
-- ============================================
-- The old policy used auth.uid() which returns the Supabase auth user ID,
-- NOT the tenant_id. This means no tenant could see their own templates
-- (unless by coincidence their tenant_id equaled their auth.uid()).
-- The tenant_id IS NULL clause allowed anyone to see null-tenant templates.

ALTER TABLE bank_statement_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE bank_statement_templates FORCE ROW LEVEL SECURITY;

-- Drop old broken policy
DROP POLICY IF EXISTS bank_stmt_templates_tenant_isolation ON bank_statement_templates;
DROP POLICY IF EXISTS tenant_select_bank_statement_templates ON bank_statement_templates;
DROP POLICY IF EXISTS tenant_insert_bank_statement_templates ON bank_statement_templates;
DROP POLICY IF EXISTS tenant_update_bank_statement_templates ON bank_statement_templates;
DROP POLICY IF EXISTS tenant_delete_bank_statement_templates ON bank_statement_templates;

-- Create correct tenant-isolated policies using current_tenant_id()
DO $$ BEGIN
  CREATE POLICY tenant_select_bank_statement_templates ON bank_statement_templates
    FOR SELECT USING (tenant_id = current_tenant_id() OR tenant_id IS NULL);
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'select policy: %', SQLERRM; END $$;

DO $$ BEGIN
  CREATE POLICY tenant_insert_bank_statement_templates ON bank_statement_templates
    FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'insert policy: %', SQLERRM; END $$;

DO $$ BEGIN
  CREATE POLICY tenant_update_bank_statement_templates ON bank_statement_templates
    FOR UPDATE USING (tenant_id = current_tenant_id())
    WITH CHECK (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'update policy: %', SQLERRM; END $$;

DO $$ BEGIN
  CREATE POLICY tenant_delete_bank_statement_templates ON bank_statement_templates
    FOR DELETE USING (tenant_id = current_tenant_id());
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'delete policy: %', SQLERRM; END $$;

-- ============================================
-- 4. VERIFICATION
-- ============================================
-- After execution, these should return ZERO rows:
-- SELECT tablename, policyname FROM pg_policies WHERE policyname LIKE 'allow_all_%';
-- SELECT tablename, policyname FROM pg_policies WHERE qual LIKE '%auth.uid()%' AND tablename NOT IN ('tenant_users');
