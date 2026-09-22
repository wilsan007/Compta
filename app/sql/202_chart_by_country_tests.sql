-- ============================================================
-- 202_chart_by_country_tests.sql — plan comptable par pays (migration 201)
--
-- Tout le fichier s'exécute dans une transaction annulée : le plan de Djibouti
-- fictif publié ici ne doit pas rester dans la base.
-- ============================================================
BEGIN;
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '202', true);
DELETE FROM _audit_results WHERE file = '202';

-- Utilisateur connecté (et, si demandé, administrateur de la plateforme)
CREATE OR REPLACE FUNCTION pg_temp._login(p_admin boolean) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE a uuid := gen_random_uuid();
BEGIN
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO auth.users (id, email) VALUES (a, 'p-' || a || '@audit.test');
  IF p_admin THEN INSERT INTO platform_admins (auth_id) VALUES (a); END IF;
  PERFORM set_config('request.jwt.claim.sub', a::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated',
    'email', 'p@audit.test', 'user_metadata', json_build_object('name', 'Test'))::text, true);
  PERFORM set_config('app.active_tenant_id', '', true);
  RETURN a;
END $$;

-- Inscription comme l'application, résultat jsonb
CREATE OR REPLACE FUNCTION pg_temp._signup(p_name text, p_country text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE r jsonb;
BEGIN
  PERFORM pg_temp._login(false);
  PERFORM set_config('role', 'authenticated', true);
  r := create_tenant_for_current_user(jsonb_build_object('name', p_name, 'country', p_country));
  PERFORM set_config('role', 'postgres', true);
  RETURN r;
END $$;

CREATE TEMP TABLE _p (k text PRIMARY KEY, v text);
GRANT ALL ON _p TO PUBLIC;

-- CP01 — France : PCG, définitif
DO $$
DECLARE r jsonb := pg_temp._signup('P01 France', 'France'); t uuid := (r->>'tenant_id')::uuid; tt record; n int;
BEGIN
  SELECT * INTO tt FROM tenants WHERE id = t;
  SELECT count(*) INTO n FROM chart_accounts WHERE tenant_id = t;
  INSERT INTO _p VALUES ('fr', t::text);
  PERFORM _rec('CP01', 'France : PCG (pack FR) définitif',
    COALESCE((r->>'success')::boolean, false) AND tt.chart_pack_code = 'FR' AND NOT tt.chart_provisional AND n > 600,
    format('success=%s pack=%s provisoire=%s comptes=%s %s', r->>'success', tt.chart_pack_code, tt.chart_provisional, n, COALESCE(r->>'error', '')));
END $$;

-- CP02 — Djibouti sans plan publié : PCG provisoire, devise DJF, code pays DJ
DO $$
DECLARE r jsonb := pg_temp._signup('P02 Djibouti', 'Djibouti'); t uuid := (r->>'tenant_id')::uuid; tt record; n int;
BEGIN
  SELECT * INTO tt FROM tenants WHERE id = t;
  SELECT count(*) INTO n FROM chart_accounts WHERE tenant_id = t;
  INSERT INTO _p VALUES ('dj1', t::text);
  PERFORM _rec('CP02', 'Djibouti sans plan publié : PCG provisoire, DJF, code DJ',
    COALESCE((r->>'success')::boolean, false) AND tt.chart_pack_code = 'FR' AND tt.chart_provisional
      AND tt.country_code = 'DJ' AND tt.currency = 'DJF' AND n > 600,
    format('success=%s pack=%s provisoire=%s pays=%s devise=%s comptes=%s %s', r->>'success', tt.chart_pack_code,
      tt.chart_provisional, tt.country_code, tt.currency, n, COALESCE(r->>'error', '')));
END $$;

-- CP03 — autre pays : inscription refusée, rien de créé
DO $$
DECLARE r jsonb := pg_temp._signup('P03 Maroc', 'Maroc'); n int;
BEGIN
  SELECT count(*) INTO n FROM tenants WHERE name = 'P03 Maroc';
  PERFORM _rec('CP03', 'Maroc : PAYS_NON_DISPONIBLE, aucune société créée',
    NOT COALESCE((r->>'success')::boolean, true) AND r->>'error' = 'PAYS_NON_DISPONIBLE' AND n = 0,
    format('réponse=%s sociétés=%s', r::text, n));
END $$;

-- CP04 — pays proposés à l'inscription : France et Djibouti seulement
DO $$
DECLARE v text;
BEGIN
  PERFORM pg_temp._login(false);
  PERFORM set_config('role', 'authenticated', true);
  SELECT string_agg(country_code || ':' || pack_code || ':' || provisional, ',' ORDER BY country_code) INTO v
  FROM available_signup_countries();
  PERFORM set_config('role', 'postgres', true);
  PERFORM _rec('CP04', 'pays disponibles = DJ (provisoire) et FR', v = 'DJ:FR:true,FR:FR:false', v);
END $$;

-- Plan de Djibouti fictif : plan de P01 sans 627000 ni 208000, libellés préfixés, + 471900
DO $$
DECLARE t uuid := (SELECT v FROM _p WHERE k = 'fr')::uuid; rows jsonb;
BEGIN
  SELECT jsonb_agg(jsonb_build_object('code', code, 'name', 'DJ ' || name, 'type', type) ORDER BY code) INTO rows
  FROM chart_accounts WHERE tenant_id = t AND code NOT IN ('627000', '208000');
  rows := rows || jsonb_build_array(jsonb_build_object('code', '471900', 'name', 'DJ Compte d''attente', 'type', 'liability'));
  INSERT INTO _p VALUES ('rows', rows::text);
END $$;

-- CP05 — un utilisateur ordinaire ne peut ni téléverser ni publier
DO $$
DECLARE m1 text := 'accepté'; m2 text := 'accepté';
BEGIN
  PERFORM pg_temp._login(false);
  PERFORM set_config('role', 'authenticated', true);
  BEGIN PERFORM upload_chart_pack('DJ', (SELECT v FROM _p WHERE k = 'rows')::jsonb); EXCEPTION WHEN OTHERS THEN m1 := SQLERRM; END;
  BEGIN PERFORM publish_chart_pack('DJ'); EXCEPTION WHEN OTHERS THEN m2 := SQLERRM; END;
  PERFORM set_config('role', 'postgres', true);
  PERFORM _rec('CP05', 'téléversement et publication refusés hors administrateur',
    m1 ~ 'ACCES_REFUSE' AND m2 ~ 'ACCES_REFUSE', m1 || ' | ' || m2);
END $$;

-- CP06 — fichier invalide : erreurs par ligne, rien d'écrit
DO $$
DECLARE r jsonb; n int;
BEGIN
  PERFORM pg_temp._login(true);
  PERFORM set_config('role', 'authenticated', true);
  r := upload_chart_pack('DJ', '[{"code":"411000","name":"Clients","type":"asset"},
                                  {"code":"4 11","name":"","type":"actif"},
                                  {"code":"411000","name":"Doublon","type":"asset"}]');
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*) INTO n FROM chart_account_templates WHERE pack_code = 'DJ';
  PERFORM _rec('CP06', 'fichier invalide : erreurs listées (code, libellé, type, doublon), rien écrit',
    NOT (r->>'success')::boolean AND jsonb_array_length(r->'errors') >= 4 AND n = 0, r::text);
END $$;

-- CP07 — plan incomplet : téléversé en brouillon, publication refusée avec la liste
DO $$
DECLARE rows jsonb; r jsonb; m text := 'publié';
BEGIN
  SELECT jsonb_agg(e) INTO rows FROM jsonb_array_elements((SELECT v FROM _p WHERE k = 'rows')::jsonb) e
  WHERE e->>'code' NOT IN ('411000', '512000');
  PERFORM pg_temp._login(true);
  PERFORM set_config('role', 'authenticated', true);
  r := upload_chart_pack('DJ', rows);
  BEGIN PERFORM publish_chart_pack('DJ'); EXCEPTION WHEN OTHERS THEN m := SQLERRM; END;
  PERFORM set_config('role', 'postgres', true);
  PERFORM _rec('CP07', 'plan sans 411000/512000 : publication refusée en nommant les comptes',
    (r->>'success')::boolean AND r->'missing_required' ? '411000' AND m ~ 'COMPTES_MANQUANTS' AND m ~ '411000' AND m ~ '512000'
      AND (SELECT status FROM chart_pack_status WHERE pack_code = 'DJ') = 'draft',
    m);
END $$;

-- Deux sociétés djiboutiennes provisoires : dj1 (P02) avec un brouillon sur 627000,
-- dj2 avec une écriture validée
DO $$
DECLARE r jsonb := pg_temp._signup('P09 Djibouti validée', 'Djibouti'); t2 uuid := (r->>'tenant_id')::uuid;
        t1 uuid := (SELECT v FROM _p WHERE k = 'dj1')::uuid; e uuid;
BEGIN
  INSERT INTO _p VALUES ('dj2', t2::text);
  PERFORM set_config('app.active_tenant_id', t1::text, true);
  e := _entry(t1, 'P10-BROUILLON', CURRENT_DATE, '[{"a":"627000","d":10},{"a":"512000","c":10}]', false);
  INSERT INTO _p VALUES ('draft', e::text);
  PERFORM set_config('app.active_tenant_id', t2::text, true);
  PERFORM _entry(t2, 'P09-VALIDEE', CURRENT_DATE, '[{"a":"512000","d":100},{"a":"411000","c":100}]', true);
END $$;

-- CP08 — plan complet publié : dj1 basculée automatiquement
DO $$
DECLARE r jsonb; t1 uuid := (SELECT v FROM _p WHERE k = 'dj1')::uuid; tt record; nm text; has_new boolean; has_old boolean;
BEGIN
  PERFORM pg_temp._login(true);
  PERFORM set_config('role', 'authenticated', true);
  PERFORM upload_chart_pack('DJ', (SELECT v FROM _p WHERE k = 'rows')::jsonb);
  r := publish_chart_pack('DJ');
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO _p VALUES ('publish', r::text);
  SELECT * INTO tt FROM tenants WHERE id = t1;
  SELECT name INTO nm FROM chart_accounts WHERE tenant_id = t1 AND code = '411000';
  has_new := EXISTS (SELECT 1 FROM chart_accounts WHERE tenant_id = t1 AND code = '471900');
  has_old := EXISTS (SELECT 1 FROM chart_accounts WHERE tenant_id = t1 AND code = '208000');
  PERFORM _rec('CP08', 'publication : société provisoire sans écriture validée basculée sur le plan DJ',
    tt.chart_pack_code = 'DJ' AND NOT tt.chart_provisional AND nm LIKE 'DJ %' AND has_new AND NOT has_old,
    format('pack=%s provisoire=%s 411000=%s 471900=%s 208000=%s', tt.chart_pack_code, tt.chart_provisional, nm, has_new, has_old));
END $$;

-- CP09 — société avec écriture validée : non basculée, signalée
DO $$
DECLARE t2 uuid := (SELECT v FROM _p WHERE k = 'dj2')::uuid; tt record; r jsonb := (SELECT v FROM _p WHERE k = 'publish')::jsonb;
BEGIN
  SELECT * INTO tt FROM tenants WHERE id = t2;
  PERFORM _rec('CP09', 'société à écriture validée : reste au PCG provisoire, signalée',
    tt.chart_pack_code = 'FR' AND tt.chart_provisional
      AND EXISTS (SELECT 1 FROM jsonb_array_elements(r->'tenants') x
                  WHERE x->>'tenant_id' = t2::text AND x->>'reason' = 'ecritures_validees'),
    format('pack=%s provisoire=%s', tt.chart_pack_code, tt.chart_provisional));
END $$;

-- CP10 — compte FR utilisé par un brouillon : fermé (pas supprimé), validation refusée
DO $$
DECLARE t1 uuid := (SELECT v FROM _p WHERE k = 'dj1')::uuid; dep boolean; m text := 'validé';
BEGIN
  SELECT deprecated INTO dep FROM chart_accounts WHERE tenant_id = t1 AND code = '627000';
  -- Validation par l'administrateur de la société : seul le compte fermé doit bloquer
  PERFORM set_config('request.jwt.claim.sub', (SELECT auth_id::text FROM tenant_users WHERE tenant_id = t1 LIMIT 1), true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', (SELECT auth_id FROM tenant_users WHERE tenant_id = t1 LIMIT 1),
    'role', 'authenticated')::text, true);
  PERFORM set_config('app.active_tenant_id', t1::text, true);
  BEGIN
    UPDATE journal_entries SET status = 'posted' WHERE id = (SELECT v FROM _p WHERE k = 'draft')::uuid;
  EXCEPTION WHEN OTHERS THEN m := SQLERRM; END;
  PERFORM _rec('CP10', 'compte FR d''un brouillon fermé, pas supprimé ; validation refusée pour ce motif',
    dep IS TRUE AND m ~ '627000' AND m ~ 'fermé', format('627000 déprécié=%s validation=%s', dep, m));
END $$;

-- CP11 — nouvelle inscription à Djibouti après publication : plan DJ directement
DO $$
DECLARE r jsonb := pg_temp._signup('P11 Djibouti', 'Djibouti'); t uuid := (r->>'tenant_id')::uuid; tt record; nm text;
BEGIN
  SELECT * INTO tt FROM tenants WHERE id = t;
  SELECT name INTO nm FROM chart_accounts WHERE tenant_id = t AND code = '411000';
  PERFORM _rec('CP11', 'après publication, Djibouti reçoit le plan DJ (définitif)',
    COALESCE((r->>'success')::boolean, false) AND tt.chart_pack_code = 'DJ' AND NOT tt.chart_provisional AND nm LIKE 'DJ %',
    format('success=%s pack=%s provisoire=%s 411000=%s %s', r->>'success', tt.chart_pack_code, tt.chart_provisional, nm, COALESCE(r->>'error', '')));
END $$;

-- CP12 — un plan publié est immuable
DO $$
DECLARE m text := 'remplacé';
BEGIN
  PERFORM pg_temp._login(true);
  PERFORM set_config('role', 'authenticated', true);
  BEGIN PERFORM upload_chart_pack('DJ', (SELECT v FROM _p WHERE k = 'rows')::jsonb); EXCEPTION WHEN OTHERS THEN m := SQLERRM; END;
  PERFORM set_config('role', 'postgres', true);
  PERFORM _rec('CP12', 'plan publié non remplaçable', m ~ 'PACK_PUBLIE', m);
END $$;

-- CP13 — le PCG français n'est pas remplaçable par téléversement
DO $$
DECLARE m text := 'remplacé';
BEGIN
  PERFORM pg_temp._login(true);
  PERFORM set_config('role', 'authenticated', true);
  BEGIN PERFORM upload_chart_pack('FR', (SELECT v FROM _p WHERE k = 'rows')::jsonb); EXCEPTION WHEN OTHERS THEN m := SQLERRM; END;
  PERFORM set_config('role', 'postgres', true);
  PERFORM _rec('CP13', 'pack FR protégé', m ~ 'PACK_PROTEGE', m);
END $$;

SELECT _audit_assert('202');
ROLLBACK;
