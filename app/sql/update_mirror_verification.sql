-- Mise à jour de la table mirror_servers pour la vérification post-installation
-- Run this in Supabase Dashboard > SQL Editor

ALTER TABLE mirror_servers ADD COLUMN IF NOT EXISTS install_status text DEFAULT 'pending' 
  CHECK (install_status IN ('pending', 'installed', 'verified', 'failed'));

ALTER TABLE mirror_servers ADD COLUMN IF NOT EXISTS verification_data jsonb;
ALTER TABLE mirror_servers ADD COLUMN IF NOT EXISTS verified_at timestamptz;
ALTER TABLE mirror_servers ADD COLUMN IF NOT EXISTS install_token text;
ALTER TABLE mirror_servers ADD COLUMN IF NOT EXISTS install_platform text CHECK (install_platform IN ('mac', 'windows', 'linux'));

-- Table pour tracer la vérification détaillée table par table
CREATE TABLE IF NOT EXISTS mirror_verification_details (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  mirror_server_id uuid REFERENCES mirror_servers(id) ON DELETE CASCADE,
  table_name text NOT NULL,
  cloud_rows integer NOT NULL DEFAULT 0,
  local_rows integer NOT NULL DEFAULT 0,
  match boolean NOT NULL DEFAULT false,
  verified_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_mirror_verification_server ON mirror_verification_details(mirror_server_id);

ALTER TABLE mirror_verification_details ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'allow_all_mirror_verification') THEN
    CREATE POLICY "allow_all_mirror_verification" ON mirror_verification_details FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;
