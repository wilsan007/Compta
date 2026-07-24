-- ============================================
-- PREVENT DUPLICATE AUTH USERS
-- ============================================
-- Provides a SECURITY DEFINER function to check if an email
-- already exists in auth.users, callable from both edge functions
-- (service role) and client-side RPC (anon role).
-- This prevents duplicate auth.users entries when inviting users
-- or signing up new tenant admins.
-- ============================================

-- Drop existing function if it exists (idempotent)
DROP FUNCTION IF EXISTS public.auth_email_exists(p_email text);

-- Create a SECURITY DEFINER function that checks auth.users
-- This bypasses RLS so both anon and authenticated roles can call it
CREATE OR REPLACE FUNCTION public.auth_email_exists(p_email text)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = auth, public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM auth.users
    WHERE email = lower(trim(p_email))
  );
$$;

-- Grant execute to anon (for signup pre-check) and authenticated (for invitation pre-check)
GRANT EXECUTE ON FUNCTION public.auth_email_exists(p_email text) TO anon;
GRANT EXECUTE ON FUNCTION public.auth_email_exists(p_email text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.auth_email_exists(p_email text) TO service_role;

-- ============================================
-- Also add a unique constraint on tenant_users (email, tenant_id)
-- to prevent duplicate invitations to the same tenant
-- (defense-in-depth, in case the application check is bypassed)
-- ============================================
DROP INDEX IF EXISTS tenant_users_email_tenant_unique;
CREATE UNIQUE INDEX tenant_users_email_tenant_unique
  ON tenant_users (email, tenant_id)
  WHERE email IS NOT NULL;
