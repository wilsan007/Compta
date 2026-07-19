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
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_mirror_servers') THEN
    CREATE POLICY "allow_all_mirror_servers" ON mirror_servers FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;
