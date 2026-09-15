-- ============================================================
-- ci/00_supabase_stubs.sql
--
-- LOT0-03 / LOT0-04 : le job db-integration tourne sur un PostgreSQL 16 nu.
-- Le schéma et les migrations référencent les objets fournis par Supabase
-- (schémas auth et storage, rôles anon/authenticated/service_role,
-- auth.uid(), auth.jwt()…). Ce fichier les simule, à charger AVANT
-- 00_schema_dump.sql. Ne jamais l'exécuter sur une base Supabase réelle.
-- ============================================================

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'auth')
     AND EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                 WHERE n.nspname = 'auth' AND p.proname = 'uid' AND p.prosrc NOT LIKE '%request.jwt.claim.sub%') THEN
    RAISE EXCEPTION 'Base Supabase réelle détectée — stubs refusés';
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN CREATE ROLE service_role NOLOGIN BYPASSRLS; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'supabase_admin') THEN CREATE ROLE supabase_admin NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'supabase_auth_admin') THEN CREATE ROLE supabase_auth_admin NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'supabase_storage_admin') THEN CREATE ROLE supabase_storage_admin NOLOGIN; END IF;
END $$;

CREATE SCHEMA IF NOT EXISTS auth;
CREATE SCHEMA IF NOT EXISTS storage;
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE SCHEMA IF NOT EXISTS cron;
CREATE SCHEMA IF NOT EXISTS net;
CREATE SCHEMA IF NOT EXISTS vault;

GRANT USAGE ON SCHEMA public, auth, storage TO anon, authenticated, service_role;

CREATE TABLE IF NOT EXISTS auth.users (
  instance_id uuid,
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  aud varchar(255),
  role varchar(255),
  email varchar(255),
  encrypted_password varchar(255),
  email_confirmed_at timestamptz,
  last_sign_in_at timestamptz,
  raw_app_meta_data jsonb DEFAULT '{}'::jsonb,
  raw_user_meta_data jsonb DEFAULT '{}'::jsonb,
  is_super_admin boolean,
  phone text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  deleted_at timestamptz
);

-- Identité simulée : lue depuis les claims JWT posés par set_config, comme PostgREST
CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT nullif(coalesce(current_setting('request.jwt.claim.sub', true),
                         (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')), '')::uuid
$$;
CREATE OR REPLACE FUNCTION auth.role() RETURNS text LANGUAGE sql STABLE AS $$
  SELECT coalesce(current_setting('request.jwt.claim.role', true),
                  (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'))
$$;
CREATE OR REPLACE FUNCTION auth.email() RETURNS text LANGUAGE sql STABLE AS $$
  SELECT coalesce(current_setting('request.jwt.claim.email', true),
                  (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'email'))
$$;
CREATE OR REPLACE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb
$$;

CREATE TABLE IF NOT EXISTS storage.buckets (
  id text PRIMARY KEY,
  name text NOT NULL,
  owner uuid,
  public boolean DEFAULT false,
  file_size_limit bigint,
  allowed_mime_types text[],
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
CREATE TABLE IF NOT EXISTS storage.objects (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  bucket_id text REFERENCES storage.buckets(id),
  name text,
  owner uuid,
  metadata jsonb,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
CREATE OR REPLACE FUNCTION storage.foldername(name text) RETURNS text[] LANGUAGE sql IMMUTABLE AS $$
  SELECT (string_to_array(name, '/'))[1:array_length(string_to_array(name, '/'), 1) - 1]
$$;
CREATE OR REPLACE FUNCTION storage.filename(name text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT (string_to_array(name, '/'))[array_length(string_to_array(name, '/'), 1)]
$$;

-- pg_cron et pg_net ne sont pas disponibles sur PostgreSQL nu : planification sans effet
CREATE TABLE IF NOT EXISTS cron.job (jobid bigserial PRIMARY KEY, jobname text UNIQUE, schedule text, command text);
CREATE OR REPLACE FUNCTION cron.schedule(job_name text, schedule text, command text) RETURNS bigint LANGUAGE sql AS $$
  INSERT INTO cron.job (jobname, schedule, command) VALUES (job_name, schedule, command)
  ON CONFLICT (jobname) DO UPDATE SET schedule = EXCLUDED.schedule, command = EXCLUDED.command
  RETURNING jobid
$$;
CREATE OR REPLACE FUNCTION cron.unschedule(job_name text) RETURNS boolean LANGUAGE sql AS $$
  WITH d AS (DELETE FROM cron.job WHERE jobname = job_name RETURNING 1) SELECT EXISTS (SELECT 1 FROM d)
$$;
CREATE OR REPLACE FUNCTION net.http_post(url text, body jsonb DEFAULT '{}'::jsonb, params jsonb DEFAULT '{}'::jsonb,
  headers jsonb DEFAULT '{}'::jsonb, timeout_milliseconds integer DEFAULT 5000) RETURNS bigint LANGUAGE sql AS $$ SELECT 0::bigint $$;

-- Privilèges par défaut de Supabase sur le schéma public (les tables créées ensuite en héritent)
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO anon, authenticated, service_role;
GRANT SELECT ON auth.users TO authenticated, service_role;
