-- Table des serveurs miroirs enregistrés
-- Un seul serveur miroir par tenant
-- Run this in Supabase Dashboard > SQL Editor

CREATE TABLE IF NOT EXISTS mirror_servers (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id text NOT NULL,
  machine_id text NOT NULL,
  machine_name text NOT NULL,
  os text,
  ip_address text,
  mirror_dir text,
  registered_at timestamptz DEFAULT now(),
  last_heartbeat timestamptz DEFAULT now(),
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'revoked')),
  config jsonb,
  UNIQUE(tenant_id)
);

CREATE INDEX IF NOT EXISTS idx_mirror_servers_tenant ON mirror_servers(tenant_id);
CREATE INDEX IF NOT EXISTS idx_mirror_servers_machine ON mirror_servers(machine_id);

ALTER TABLE mirror_servers ENABLE ROW LEVEL SECURITY;
ALTER TABLE mirror_servers FORCE ROW LEVEL SECURITY;

-- Drop any old allow_all policy
DROP POLICY IF EXISTS allow_all_mirror_servers ON mirror_servers;

-- Tenant-isolated policies (see migration 38 for details)
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
