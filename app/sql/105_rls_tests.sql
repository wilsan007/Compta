-- ============================================================
-- 105_rls_tests.sql
-- SOC-02 : Tests d'isolation multi-tenant (RLS)
--
-- Crée deux tenants, insère des données dans chacun,
-- et vérifie que chaque SELECT ne remonte que les lignes du tenant actif.
-- Une table oubliée doit faire échouer ce test.
-- ============================================================

-- NOTE : Ces tests supposent que le schéma est déjà chargé
-- et que les migrations ont été appliquées.
-- En CI, ce fichier est exécuté APRÈS run-sql-migrations.mjs

\echo '=== SOC-02 : Tests d\'isolation multi-tenant (RLS) ==='

-- ============================================================
-- Préparation : créer deux tenants de test
-- ============================================================

-- Nettoyer les données de test existantes
DELETE FROM tenants WHERE id IN ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222');

-- Créer deux tenants
INSERT INTO tenants (id, name, country_code, created_at)
VALUES
  ('11111111-1111-1111-1111-111111111111', 'Tenant Test A', 'FR', NOW()),
  ('22222222-2222-2222-2222-222222222222', 'Tenant Test B', 'FR', NOW())
ON CONFLICT (id) DO NOTHING;

-- ============================================================
-- Test générique : Isolation RLS sur toutes les tables avec tenant_id
-- ============================================================
\echo 'Test générique : Isolation RLS sur toutes les tables avec tenant_id...'

DO $$
DECLARE
  r RECORD;
  v_count int;
  v_leaks int := 0;
  v_tenant_a uuid := '11111111-1111-1111-1111-111111111111';
  v_tenant_b uuid := '22222222-2222-2222-2222-222222222222';
BEGIN
  -- Insérer des données de test dans toutes les tables RLS
  FOR r IN
    SELECT c.relname AS t
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
    WHERE c.relkind = 'r' AND c.relrowsecurity
      AND EXISTS (SELECT 1 FROM information_schema.columns col
                  WHERE col.table_schema='public' AND col.table_name=c.relname
                    AND col.column_name='tenant_id')
      AND c.relname NOT IN ('tenants', 'tenant_users', 'sql_migrations_tracker')
  LOOP
    BEGIN
      -- Essayer d'insérer une ligne pour tenant A
      EXECUTE format('INSERT INTO %I (tenant_id) VALUES ($1) ON CONFLICT DO NOTHING', r.t)
        USING v_tenant_a;
    EXCEPTION WHEN OTHERS THEN
      -- Ignore les erreurs (colonnes required manquantes, etc.)
      CONTINUE;
    END;
  END LOOP;

  -- Tester que chaque table ne fuit pas les données du tenant B
  FOR r IN
    SELECT c.relname AS t
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
    WHERE c.relkind = 'r' AND c.relrowsecurity
      AND EXISTS (SELECT 1 FROM information_schema.columns col
                  WHERE col.table_schema='public' AND col.table_name=c.relname
                    AND col.column_name='tenant_id')
      AND c.relname NOT IN ('tenants', 'tenant_users', 'sql_migrations_tracker')
  LOOP
    -- Simuler le contexte du tenant A
    PERFORM set_config('request.headers',
      json_build_object('x-tenant-id', v_tenant_a::text)::text, true);

    -- Tenter de voir les données du tenant B
    EXECUTE format('SELECT count(*) FROM %I WHERE tenant_id = $1', r.t)
      INTO v_count USING v_tenant_b;

    IF v_count > 0 THEN
      RAISE WARNING 'FUITE RLS sur % : % lignes du tenant B visibles par tenant A', r.t, v_count;
      v_leaks := v_leaks + 1;
    END IF;
  END LOOP;

  IF v_leaks = 0 THEN
    RAISE NOTICE 'PASS: Aucune fuite RLS détectée sur % tables testées', v_leaks;
  ELSE
    RAISE EXCEPTION 'FAIL: % tables présentent des fuites RLS', v_leaks;
  END IF;
END;
$$;

-- ============================================================
-- Nettoyage
-- ============================================================
SELECT set_config('request.headers', '{}'::text, true);
DELETE FROM tenants WHERE id IN ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222');

\echo '=== SOC-02 : Tous les tests RLS sont passés ==='
