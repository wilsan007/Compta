-- Migration 94: Fix Supabase Advisor security issues
--
-- Issues fixed:
--   1. RLS disabled on public.sql_migrations_tracker
--   2. SECURITY DEFINER view: public.rls_audit
--   3. SECURITY DEFINER view: public.balance_sheet
--   4. SECURITY DEFINER view: public.trial_balance
--   5. SECURITY DEFINER view: public.general_ledger
--   6. SECURITY DEFINER view: public.vat_summary
--
-- Root cause for views 3-6:
--   These views GROUP BY tenant_id but do NOT filter by current_tenant_id().
--   With the default SECURITY DEFINER property, they bypass RLS on underlying
--   tables, so any authenticated user can read financial data of ALL tenants.
--   Fix: recreate with security_invoker = true (PG15+) so RLS on underlying
--   tables is respected, AND add a current_tenant_id() filter as defense-in-depth.
--
-- Root cause for rls_audit:
--   Exposes internal RLS policy definitions to all authenticated users.
--   Fix: restrict to service_role only (admin tool, not for end users).

-- ============================================================================
-- 1. Enable RLS on sql_migrations_tracker (no tenant_id — admin-only table)
-- ============================================================================
ALTER TABLE public.sql_migrations_tracker ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sql_migrations_tracker FORCE ROW LEVEL SECURITY;

-- This table has no tenant_id (it tracks schema migrations, not business data).
-- Only service_role should access it. Deny authenticated/anon entirely.
DROP POLICY IF EXISTS sql_migrations_tracker_service_role ON public.sql_migrations_tracker;
DROP POLICY IF EXISTS sql_migrations_tracker_deny_all ON public.sql_migrations_tracker;

CREATE POLICY sql_migrations_tracker_service_role
  ON public.sql_migrations_tracker
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- No policy for authenticated/anon → implicit deny (fail-closed).

-- ============================================================================
-- 2. Fix rls_audit view — restrict to service_role only
-- ============================================================================
-- Recreate with security_invoker so it respects caller permissions
DROP VIEW IF EXISTS public.rls_audit;
CREATE VIEW public.rls_audit AS
SELECT
    tablename,
    policyname,
    qual,
    with_check
FROM pg_policies
WHERE schemaname = 'public'::name
  AND (qual = 'true'::text
       OR with_check = 'true'::text
       OR qual = '(true)'::text
       OR with_check = '(true)'::text)
ORDER BY tablename;

ALTER VIEW public.rls_audit SET (security_invoker = true);
-- Revoke AFTER recreate in case schema defaults granted access
REVOKE ALL ON public.rls_audit FROM authenticated;
REVOKE ALL ON public.rls_audit FROM anon;
GRANT SELECT ON public.rls_audit TO service_role;
-- Explicitly do NOT grant to authenticated or anon.

-- ============================================================================
-- 3. Fix balance_sheet view — add tenant filter + security_invoker
-- ============================================================================
DROP VIEW IF EXISTS public.balance_sheet;
CREATE VIEW public.balance_sheet AS
SELECT
    je.tenant_id,
    je.date,
    ja.code,
    ja.name,
    ja.type,
    COALESCE(sum(jl.debit), 0::numeric) AS total_debit,
    COALESCE(sum(jl.credit), 0::numeric) AS total_credit,
    COALESCE(sum(jl.debit), 0::numeric) - COALESCE(sum(jl.credit), 0::numeric) AS solde
FROM journal_entries je
    JOIN journal_lines jl ON jl.journal_id = je.id AND jl.tenant_id = je.tenant_id
    JOIN chart_accounts ja ON ja.code = jl.account_code AND ja.tenant_id = je.tenant_id
WHERE je.status = ANY (ARRAY['posted'::text, 'draft'::text])
  AND je.tenant_id = public.current_tenant_id()
GROUP BY je.tenant_id, je.date, ja.code, ja.name, ja.type;

ALTER VIEW public.balance_sheet SET (security_invoker = true);
GRANT SELECT ON public.balance_sheet TO authenticated;

-- ============================================================================
-- 4. Fix trial_balance view — add tenant filter + security_invoker
-- ============================================================================
DROP VIEW IF EXISTS public.trial_balance;
CREATE VIEW public.trial_balance AS
SELECT
    je.tenant_id,
    ja.code,
    ja.name,
    ja.type,
    COALESCE(sum(jl.debit), 0::numeric) AS total_debit,
    COALESCE(sum(jl.credit), 0::numeric) AS total_credit,
    COALESCE(sum(jl.debit), 0::numeric) - COALESCE(sum(jl.credit), 0::numeric) AS solde_debit,
    COALESCE(sum(jl.credit), 0::numeric) - COALESCE(sum(jl.debit), 0::numeric) AS solde_credit
FROM journal_entries je
    JOIN journal_lines jl ON jl.journal_id = je.id AND jl.tenant_id = je.tenant_id
    JOIN chart_accounts ja ON ja.code = jl.account_code AND ja.tenant_id = je.tenant_id
WHERE je.status = ANY (ARRAY['posted'::text, 'draft'::text])
  AND je.tenant_id = public.current_tenant_id()
GROUP BY je.tenant_id, ja.code, ja.name, ja.type;

ALTER VIEW public.trial_balance SET (security_invoker = true);
GRANT SELECT ON public.trial_balance TO authenticated;

-- ============================================================================
-- 5. Fix general_ledger view — add tenant filter + security_invoker
-- ============================================================================
DROP VIEW IF EXISTS public.general_ledger;
CREATE VIEW public.general_ledger AS
SELECT
    je.tenant_id,
    je.id AS entry_id,
    je.number AS entry_number,
    je.date,
    je.journal_code,
    je.status,
    je.description,
    jl.account_code,
    jl.description AS line_description,
    jl.debit,
    jl.credit,
    jl.line_order
FROM journal_entries je
    JOIN journal_lines jl ON jl.journal_id = je.id AND jl.tenant_id = je.tenant_id
WHERE je.status = ANY (ARRAY['posted'::text, 'draft'::text])
  AND je.tenant_id = public.current_tenant_id();

ALTER VIEW public.general_ledger SET (security_invoker = true);
GRANT SELECT ON public.general_ledger TO authenticated;

-- ============================================================================
-- 6. Fix vat_summary view — add tenant filter + security_invoker
-- ============================================================================
DROP VIEW IF EXISTS public.vat_summary;
CREATE VIEW public.vat_summary AS
SELECT
    i.tenant_id,
    i.id AS invoice_id,
    i.number AS invoice_number,
    i.date,
    il.vat_rate,
    sum(il.quantity * il.unit_price) AS ht_amount,
    sum(il.quantity * il.unit_price * (il.vat_rate / 100::numeric)) AS vat_amount,
    sum(il.quantity * il.unit_price * (1::numeric + il.vat_rate / 100::numeric)) AS ttc_amount
FROM invoices i
    JOIN invoice_lines il ON il.invoice_id = i.id AND il.tenant_id = i.tenant_id
WHERE i.status <> 'cancelled'::text
  AND i.tenant_id = public.current_tenant_id()
GROUP BY i.tenant_id, i.id, i.number, i.date, il.vat_rate;

ALTER VIEW public.vat_summary SET (security_invoker = true);
GRANT SELECT ON public.vat_summary TO authenticated;

-- ============================================================================
-- 7. Revoke excessive grants on views (views are read-only)
-- ============================================================================
-- Supabase auto-grants ALL privileges to authenticated on view creation.
-- Views should be SELECT-only — no INSERT/UPDATE/DELETE/TRUNCATE.
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.balance_sheet FROM authenticated;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.trial_balance FROM authenticated;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.general_ledger FROM authenticated;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.vat_summary FROM authenticated;

-- ============================================================================
-- Verification queries (run manually to confirm)
-- ============================================================================
-- SELECT relname, relrowsecurity, relforcerowsecurity FROM pg_class WHERE relname='sql_migrations_tracker';
-- SELECT relname, reloptions FROM pg_class c JOIN pg_namespace n ON c.relnamespace=n.oid WHERE n.nspname='public' AND c.relkind='v';
-- SELECT table_name, grantee, privilege_type FROM information_schema.role_table_grants WHERE table_schema = 'public' AND table_name IN ('balance_sheet', 'trial_balance', 'general_ledger', 'vat_summary', 'rls_audit') ORDER BY table_name, grantee;
