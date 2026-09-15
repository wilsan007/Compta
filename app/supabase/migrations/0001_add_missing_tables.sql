-- ============================================
-- Migration: Tables manquantes pour Edge Functions
-- Date: 2026-09-09
-- Description: Crée les tables requises par les Edge Functions
--              qui n'existaient pas dans le schéma initial
-- ============================================

-- ============================================
-- Table: profiles (utilisée par auth-signup)
-- ============================================
CREATE TABLE IF NOT EXISTS profiles (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  auth_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
  email text NOT NULL,
  name text,
  avatar_url text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_profiles_email ON profiles(email);
CREATE INDEX IF NOT EXISTS idx_profiles_auth_id ON profiles(auth_id);

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own profile" ON profiles
  FOR SELECT USING (auth_id = auth.uid());
CREATE POLICY "Users can update own profile" ON profiles
  FOR UPDATE USING (auth_id = auth.uid());
CREATE POLICY "Users can insert own profile" ON profiles
  FOR INSERT WITH CHECK (auth_id = auth.uid());

GRANT SELECT, INSERT, UPDATE, DELETE ON profiles TO authenticated, anon, service_role;

-- ============================================
-- Table: webhook_endpoints (utilisée par outgoing-webhooks)
-- ============================================
CREATE TABLE IF NOT EXISTS webhook_endpoints (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  url text NOT NULL,
  secret text,
  active_events jsonb NOT NULL DEFAULT '[]'::jsonb,
  active boolean NOT NULL DEFAULT true,
  description text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_webhook_endpoints_tenant ON webhook_endpoints(tenant_id);
CREATE INDEX IF NOT EXISTS idx_webhook_endpoints_active ON webhook_endpoints(active);

ALTER TABLE webhook_endpoints ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Tenant members can view webhooks" ON webhook_endpoints
  FOR SELECT USING (tenant_id IN (
    SELECT tenant_id FROM tenant_users WHERE auth_id = auth.uid() AND status = 'active'
  ));
CREATE POLICY "Tenant admins can manage webhooks" ON webhook_endpoints
  FOR ALL USING (
    tenant_id IN (
      SELECT tenant_id FROM tenant_users
      WHERE auth_id = auth.uid() AND status = 'active' AND role IN ('admin', 'owner')
    )
  );

GRANT SELECT, INSERT, UPDATE, DELETE ON webhook_endpoints TO authenticated, service_role;

-- ============================================
-- Table: webhook_delivery_logs (utilisée par outgoing-webhooks)
-- ============================================
CREATE TABLE IF NOT EXISTS webhook_delivery_logs (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  url text NOT NULL,
  event text NOT NULL,
  status text NOT NULL DEFAULT 'pending',
  attempt integer NOT NULL DEFAULT 1,
  response_code integer,
  response_body text,
  error text,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_webhook_delivery_logs_tenant ON webhook_delivery_logs(tenant_id);
CREATE INDEX IF NOT EXISTS idx_webhook_delivery_logs_status ON webhook_delivery_logs(status);

ALTER TABLE webhook_delivery_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Tenant members can view delivery logs" ON webhook_delivery_logs
  FOR SELECT USING (tenant_id IN (
    SELECT tenant_id FROM tenant_users WHERE auth_id = auth.uid() AND status = 'active'
  ));

GRANT SELECT, INSERT ON webhook_delivery_logs TO authenticated, service_role;

-- ============================================
-- Function: auth_email_exists (utilisée par create-user)
-- ============================================
CREATE OR REPLACE FUNCTION auth_email_exists(p_email text)
RETURNS boolean
LANGUAGE sql SECURITY DEFINER
AS $$
  SELECT EXISTS (
    SELECT 1 FROM auth.users WHERE email = p_email
  )
$$;

GRANT EXECUTE ON FUNCTION auth_email_exists(text) TO authenticated, anon, service_role;
