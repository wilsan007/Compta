-- ============================================================
-- 105_rls_tests.sql
-- SOC-02 / LOT0-04 : test générique d'isolation multi-tenant (RLS)
--
-- 1. Deux tenants A et B, un utilisateur actif dans chacun.
-- 2. Pour CHAQUE table publique portant tenant_id : une ligne est insérée
--    pour A et pour B (triggers et clés étrangères neutralisés, valeurs
--    générées pour les colonnes obligatoires).
-- 3. Sous le rôle `authenticated` (sans BYPASSRLS), connecté comme
--    l'utilisateur de A, aucune ligne de B ne doit être visible — y compris
--    quand l'en-tête x-tenant-id est falsifié pour désigner B.
-- 4. Échec si une table fuit, si une table n'a pas la RLS activée, ou si
--    une table n'a pas pu être alimentée (le test ne serait pas probant).
--
-- Exécuté par la CI (job db-integration) — jamais comme migration.
-- ============================================================

\set ON_ERROR_STOP on
\echo '=== LOT0-04 : isolation multi-tenant sur toutes les tables ==='

CREATE TEMP TABLE rls_test_tables (
  table_name text PRIMARY KEY,
  seeded boolean DEFAULT false,
  seed_error text,
  leak_count int,
  spoof_leak_count int,
  own_visible int
);
GRANT ALL ON rls_test_tables TO authenticated;

INSERT INTO rls_test_tables (table_name)
SELECT c.relname
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
WHERE c.relkind = 'r'
  AND EXISTS (SELECT 1 FROM information_schema.columns col
              WHERE col.table_schema = 'public' AND col.table_name = c.relname
                AND col.column_name = 'tenant_id')
  AND c.relname <> 'tenant_users';

-- Toute table avec tenant_id doit avoir la RLS activée
DO $$
DECLARE
  v_missing text;
BEGIN
  SELECT string_agg(t.table_name, ', ') INTO v_missing
  FROM rls_test_tables t JOIN pg_class c ON c.relname = t.table_name
  JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
  WHERE NOT c.relrowsecurity;
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL : RLS désactivée sur : %', v_missing;
  END IF;
END $$;

-- ------------------------------------------------------------
-- Nettoyage préalable (exécution précédente interrompue)
-- ------------------------------------------------------------
DO $$
DECLARE
  r RECORD;
BEGIN
  SET LOCAL session_replication_role = 'replica';
  FOR r IN SELECT table_name FROM rls_test_tables LOOP
    EXECUTE format('DELETE FROM public.%I WHERE tenant_id IN (%L, %L)', r.table_name,
                   'a0000000-0000-0000-0000-00000000000a', 'b0000000-0000-0000-0000-00000000000b');
  END LOOP;
  DELETE FROM tenant_users WHERE tenant_id IN ('a0000000-0000-0000-0000-00000000000a', 'b0000000-0000-0000-0000-00000000000b');
  DELETE FROM tenants WHERE id IN ('a0000000-0000-0000-0000-00000000000a', 'b0000000-0000-0000-0000-00000000000b');
  DELETE FROM auth.users WHERE id IN ('a1000000-0000-0000-0000-00000000000a', 'b1000000-0000-0000-0000-00000000000b');
END $$;

-- ------------------------------------------------------------
-- Préparation : tenants, utilisateurs, données
-- ------------------------------------------------------------
DO $$
DECLARE
  v_tenant_a uuid := 'a0000000-0000-0000-0000-00000000000a';
  v_tenant_b uuid := 'b0000000-0000-0000-0000-00000000000b';
  v_user_a uuid := 'a1000000-0000-0000-0000-00000000000a';
  v_user_b uuid := 'b1000000-0000-0000-0000-00000000000b';
  r RECORD;
  col RECORD;
  v_cols text;
  v_vals text;
  v_val text;
  v_tenant uuid;
BEGIN
  INSERT INTO auth.users (id, email) VALUES (v_user_a, 'rls-a@test.local'), (v_user_b, 'rls-b@test.local')
  ON CONFLICT (id) DO NOTHING;
  INSERT INTO tenants (id, name, country_code, created_at)
  VALUES (v_tenant_a, 'RLS Tenant A', 'FR', now()), (v_tenant_b, 'RLS Tenant B', 'FR', now())
  ON CONFLICT (id) DO NOTHING;
  INSERT INTO tenant_users (tenant_id, auth_id, email, name, role, status)
  VALUES (v_tenant_a, v_user_a, 'rls-a@test.local', 'RLS A', 'admin', 'active'),
         (v_tenant_b, v_user_b, 'rls-b@test.local', 'RLS B', 'admin', 'active');

  -- Neutraliser triggers et clés étrangères pour l'alimentation
  SET LOCAL session_replication_role = 'replica';

  FOR r IN SELECT table_name FROM rls_test_tables ORDER BY table_name LOOP
    FOREACH v_tenant IN ARRAY ARRAY[v_tenant_a, v_tenant_b] LOOP
      v_cols := 'tenant_id';
      v_vals := quote_literal(v_tenant) || '::uuid';
      FOR col IN
        SELECT a.attname, format_type(a.atttypid, a.atttypmod) AS typ, t.typtype,
               (SELECT (regexp_match(pg_get_constraintdef(k.oid), '''([^'']+)''::'))[1]
                FROM pg_constraint k
                WHERE k.conrelid = a.attrelid AND k.contype = 'c'
                  AND pg_get_constraintdef(k.oid) ~ ('\(' || a.attname || ' = ANY')
                LIMIT 1) AS allowed
        FROM pg_attribute a
        JOIN pg_type t ON t.oid = a.atttypid
        WHERE a.attrelid = ('public.' || quote_ident(r.table_name))::regclass
          AND a.attnum > 0 AND NOT a.attisdropped
          AND a.attnotnull AND NOT a.atthasdef AND a.attidentity = '' AND a.attgenerated = ''
          AND a.attname <> 'tenant_id'
      LOOP
        v_val := CASE
          WHEN col.allowed IS NOT NULL THEN quote_literal(col.allowed)
          WHEN col.attname ILIKE '%iban%' THEN quote_literal('FR7630006000011234567890189')
          WHEN col.attname ILIKE '%bic%' OR col.attname ILIKE '%swift%' THEN quote_literal('AGRIFRPP')
          WHEN col.attname ILIKE '%email%' THEN quote_literal('rls-' || substr(md5(random()::text), 1, 8) || '@test.local')
          WHEN col.typ = 'uuid' THEN 'gen_random_uuid()'
          WHEN col.typ ~ '^(text|character varying|character|citext)' THEN quote_literal('rls-' || substr(md5(random()::text), 1, 12))
          WHEN col.typ ~ '^(integer|bigint|smallint|numeric|real|double precision)' THEN '1'
          WHEN col.typ = 'boolean' THEN 'false'
          WHEN col.typ ~ '^(timestamp|date)' THEN 'now()'
          WHEN col.typ ~ '^time' THEN 'now()::time'
          WHEN col.typ IN ('jsonb', 'json') THEN quote_literal('{}')
          WHEN col.typ LIKE '%[]' THEN quote_literal('{}')
          WHEN col.typ = 'inet' THEN quote_literal('127.0.0.1')
          WHEN col.typtype = 'e' THEN (SELECT quote_literal(e.enumlabel) FROM pg_enum e
                                        JOIN pg_type ty ON ty.oid = e.enumtypid
                                        WHERE format_type(ty.oid, NULL) = col.typ
                                        ORDER BY e.enumsortorder LIMIT 1)
          ELSE 'NULL'
        END;
        v_cols := v_cols || ', ' || quote_ident(col.attname);
        v_vals := v_vals || ', ' || v_val || '::' || col.typ;
      END LOOP;

      BEGIN
        EXECUTE format('INSERT INTO public.%I (%s) VALUES (%s)', r.table_name, v_cols, v_vals);
      EXCEPTION WHEN OTHERS THEN
        UPDATE rls_test_tables SET seed_error = SQLERRM WHERE table_name = r.table_name;
      END;
    END LOOP;

    EXECUTE format('SELECT count(DISTINCT tenant_id) = 2 FROM public.%I WHERE tenant_id IN ($1, $2)', r.table_name)
      INTO v_val USING v_tenant_a, v_tenant_b;
    UPDATE rls_test_tables SET seeded = v_val::boolean WHERE table_name = r.table_name;
  END LOOP;
END $$;

-- ------------------------------------------------------------
-- H02 : rattacher chaque ligne fille à un parent de la MÊME société
--
-- Les colonnes uuid obligatoires sont alimentées par gen_random_uuid() : la
-- ligne fille pointe donc vers un parent qui n'existe pas. Or plusieurs tables
-- de lignes (invoice_lines, purchase_request_lines, pick_list_lines,
-- distribution_grill_lines, project_task_tags, crm_campaign_recipients,
-- service_ticket_messages) portent une politique RLS qui passe par le parent
-- (EXISTS sur invoices, pick_lists…) et ignore leur propre tenant_id : sans
-- parent, la ligne est invisible à sa propre société, et son `leak_count = 0`
-- est vrai pour la mauvaise raison — rien n'y est visible, ni les données de B,
-- ni les siennes. On recolle donc chaque clé étrangère simple vers la ligne
-- semée dans la table parente pour la même société.
-- ------------------------------------------------------------
DO $$
DECLARE
  v_tenant_a uuid := 'a0000000-0000-0000-0000-00000000000a';
  v_tenant_b uuid := 'b0000000-0000-0000-0000-00000000000b';
  fk RECORD;
  v_tenant uuid;
BEGIN
  SET LOCAL session_replication_role = 'replica';

  -- Depuis la 237, ces clés sont COMPOSITES `(tenant_id, colonne)` : la boucle
  -- ne cherchait que `array_length(conkey, 1) = 1` et ne recollait donc plus
  -- rien — sept tables de lignes restaient orphelines, donc invisibles à leur
  -- propre société, et la suite le signalait (à raison) sans pouvoir le
  -- réparer. Elle passe par `unnest(... ) WITH ORDINALITY` et recolle la
  -- colonne qui n'est PAS `tenant_id`, que la clé porte une ou deux colonnes.
  FOR fk IN
    SELECT ch.relname AS child_table, ca.attname AS child_col,
           pr.relname AS parent_table, pa.attname AS parent_col
    FROM pg_constraint c
    JOIN pg_class ch ON ch.oid = c.conrelid
    JOIN pg_class pr ON pr.oid = c.confrelid
    JOIN pg_namespace n ON n.oid = ch.relnamespace AND n.nspname = 'public'
    JOIN LATERAL (
      SELECT u.attnum AS catt, v.attnum AS patt
      FROM unnest(c.conkey) WITH ORDINALITY AS u(attnum, ord)
      JOIN unnest(c.confkey) WITH ORDINALITY AS v(attnum, ord) ON v.ord = u.ord
    ) k ON true
    JOIN pg_attribute ca ON ca.attrelid = c.conrelid AND ca.attnum = k.catt
    JOIN pg_attribute pa ON pa.attrelid = c.confrelid AND pa.attnum = k.patt
    WHERE c.contype = 'f'
      AND array_length(c.conkey, 1) <= 2
      AND ca.attname <> 'tenant_id'
      AND c.conrelid <> c.confrelid
      AND format_type(ca.atttypid, NULL) = 'uuid'
      AND ch.relname IN (SELECT table_name FROM rls_test_tables)
      AND pr.relname IN (SELECT table_name FROM rls_test_tables)
  LOOP
    FOREACH v_tenant IN ARRAY ARRAY[v_tenant_a, v_tenant_b] LOOP
      BEGIN
        EXECUTE format(
          'UPDATE public.%I SET %I = (SELECT p.%I FROM public.%I p WHERE p.tenant_id = %L LIMIT 1) WHERE tenant_id = %L',
          fk.child_table, fk.child_col, fk.parent_col, fk.parent_table, v_tenant, v_tenant);
      EXCEPTION WHEN OTHERS THEN
        -- contrainte d'unicité ou de cohérence : la ligne reste orpheline et
        -- le contrôle final (invisible à sa propre société) le signalera.
        NULL;
      END;
    END LOOP;
  END LOOP;
END $$;

-- ------------------------------------------------------------
-- Vérification sous le rôle authenticated, connecté comme l'utilisateur de A
-- ------------------------------------------------------------
BEGIN;
SELECT set_config('request.jwt.claim.sub', 'a1000000-0000-0000-0000-00000000000a', true);
SELECT set_config('request.jwt.claims', '{"sub":"a1000000-0000-0000-0000-00000000000a","role":"authenticated"}', true);
SET LOCAL ROLE authenticated;

DO $$
DECLARE
  r RECORD;
  v_n int;
BEGIN
  FOR r IN SELECT table_name FROM rls_test_tables WHERE seeded LOOP
    -- Contexte légitime : en-tête x-tenant-id = A
    PERFORM set_config('request.headers', '{"x-tenant-id":"a0000000-0000-0000-0000-00000000000a"}', true);
    EXECUTE format('SELECT count(*) FROM public.%I WHERE tenant_id = %L', r.table_name, 'b0000000-0000-0000-0000-00000000000b') INTO v_n;
    UPDATE rls_test_tables SET leak_count = v_n WHERE table_name = r.table_name;
    EXECUTE format('SELECT count(*) FROM public.%I WHERE tenant_id = %L', r.table_name, 'a0000000-0000-0000-0000-00000000000a') INTO v_n;
    UPDATE rls_test_tables SET own_visible = v_n WHERE table_name = r.table_name;

    -- En-tête falsifié : l'utilisateur de A désigne le tenant B
    PERFORM set_config('request.headers', '{"x-tenant-id":"b0000000-0000-0000-0000-00000000000b"}', true);
    EXECUTE format('SELECT count(*) FROM public.%I WHERE tenant_id = %L', r.table_name, 'b0000000-0000-0000-0000-00000000000b') INTO v_n;
    UPDATE rls_test_tables SET spoof_leak_count = v_n WHERE table_name = r.table_name;
  END LOOP;
END $$;

COMMIT;

-- ------------------------------------------------------------
-- Rapport
-- ------------------------------------------------------------
\echo 'Tables qui fuient (lignes du tenant B visibles par A) :'
SELECT table_name, leak_count, spoof_leak_count
FROM rls_test_tables
WHERE leak_count > 0 OR spoof_leak_count > 0
ORDER BY table_name;

\echo 'Tables non alimentées (test non probant) :'
SELECT table_name, left(seed_error, 120) AS erreur
FROM rls_test_tables WHERE NOT seeded ORDER BY table_name;

DO $$
DECLARE
  v_total int; v_seeded int; v_leaks int; v_unseeded int; v_own int; v_noms text;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE seeded),
         count(*) FILTER (WHERE leak_count > 0 OR spoof_leak_count > 0),
         count(*) FILTER (WHERE NOT seeded),
         count(*) FILTER (WHERE seeded AND own_visible > 0)
  INTO v_total, v_seeded, v_leaks, v_unseeded, v_own
  FROM rls_test_tables;

  RAISE NOTICE 'RLS : % tables, % alimentées, % visibles par leur propre tenant, % fuite(s)', v_total, v_seeded, v_own, v_leaks;

  -- H02 : une table qu'on ne voit PAS depuis sa propre société ne prouve rien.
  -- Son `leak_count = 0` est alors vrai pour la mauvaise raison (rien n'est
  -- visible, ni les données de B, ni les siennes) : le test serait vert sans
  -- avoir rien vérifié. Toute table dans ce cas fait échouer le contrôle.
  -- Le message NOMME les tables (24/09) : un « 7 tables invisibles » sans liste
  -- obligeait à instrumenter le test pour savoir lesquelles, et une suite qui ne
  -- dit pas ce qui échoue ne se répare pas.
  IF v_seeded > v_own THEN
    SELECT string_agg(table_name, ', ' ORDER BY table_name) INTO v_noms
    FROM rls_test_tables WHERE seeded AND own_visible = 0;
    RAISE EXCEPTION 'FAIL : % table(s) alimentée(s) invisible(s) à leur propre société — isolation non prouvée sur elles : %',
      v_seeded - v_own, v_noms;
  END IF;

  IF v_leaks > 0 THEN
    RAISE EXCEPTION 'FAIL : % table(s) laissent voir les données d''un autre tenant', v_leaks;
  END IF;
  IF v_unseeded > 0 THEN
    RAISE EXCEPTION 'FAIL : % table(s) non alimentée(s) — isolation non vérifiée', v_unseeded;
  END IF;
END $$;

-- ------------------------------------------------------------
-- Nettoyage
-- ------------------------------------------------------------
DO $$
DECLARE
  r RECORD;
BEGIN
  SET LOCAL session_replication_role = 'replica';
  FOR r IN SELECT table_name FROM rls_test_tables LOOP
    EXECUTE format('DELETE FROM public.%I WHERE tenant_id IN (%L, %L)', r.table_name,
                   'a0000000-0000-0000-0000-00000000000a', 'b0000000-0000-0000-0000-00000000000b');
  END LOOP;
  DELETE FROM tenant_users WHERE tenant_id IN ('a0000000-0000-0000-0000-00000000000a', 'b0000000-0000-0000-0000-00000000000b');
  DELETE FROM tenants WHERE id IN ('a0000000-0000-0000-0000-00000000000a', 'b0000000-0000-0000-0000-00000000000b');
  DELETE FROM auth.users WHERE id IN ('a1000000-0000-0000-0000-00000000000a', 'b1000000-0000-0000-0000-00000000000b');
END $$;

\echo '=== LOT0-04 : isolation vérifiée sur toutes les tables ==='
