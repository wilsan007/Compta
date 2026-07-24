-- ============================================
-- AUDITOR ROLE + TEMPORAL ACCESS
-- ============================================
-- Adds 'auditor' as a valid role on tenant_users
-- and introduces valid_from / valid_until columns
-- to support time-limited access for auditors.
-- ============================================

-- 1. Add temporal columns to tenant_users
DO $$ BEGIN
  ALTER TABLE tenant_users ADD COLUMN IF NOT EXISTS valid_from date;
  ALTER TABLE tenant_users ADD COLUMN IF NOT EXISTS valid_until date;
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'tenant_users alters: %', SQLERRM; END $$;

-- 2. Add a CHECK constraint to ensure valid_until >= valid_from (if both set)
DO $$ BEGIN
  ALTER TABLE tenant_users
    ADD CONSTRAINT tenant_users_valid_period_check
    CHECK (valid_until IS NULL OR valid_from IS NULL OR valid_until >= valid_from);
EXCEPTION
  WHEN duplicate_object THEN
    RAISE NOTICE 'Constraint tenant_users_valid_period_check already exists';
  WHEN OTHERS THEN
    RAISE NOTICE 'Constraint creation: %', SQLERRM;
END $$;

-- 3. Add an index to quickly find expired auditors
CREATE INDEX IF NOT EXISTS tenant_users_valid_until_idx
  ON tenant_users (valid_until)
  WHERE valid_until IS NOT NULL;

-- 4. Create a function to auto-revoke expired auditors
--    Can be called from the app on login or via a scheduled job
CREATE OR REPLACE FUNCTION public.auto_revoke_expired_auditors()
RETURNS integer
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  WITH expired AS (
    UPDATE tenant_users
    SET status = 'revoked',
        updated_at = now()
    WHERE role = 'auditor'
      AND status = 'active'
      AND valid_until IS NOT NULL
      AND valid_until < CURRENT_DATE
    RETURNING id
  )
  SELECT count(*)::integer FROM expired;
$$;

GRANT EXECUTE ON FUNCTION public.auto_revoke_expired_auditors() TO authenticated;
GRANT EXECUTE ON FUNCTION public.auto_revoke_expired_auditors() TO service_role;
