-- ============================================================
-- 182_signup_provisioning_tests.sql — AUD-A01, lot B du plan correctif
--
-- Création d'une société par l'appel réel create_tenant_for_current_user,
-- puis contrôle de ce qu'elle a reçu. Sécurité de bootstrap_tenant.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '182', false);
DELETE FROM _audit_results WHERE file = '182';

-- S01 à S03 — une inscription produit une société utilisable
DO $$
DECLARE a uuid := uuid_generate_v4(); r jsonb; t uuid; nca int; jn text; nfy int; ncs int; missing text;
BEGIN
  INSERT INTO auth.users (id, email) VALUES (a, 'signup-' || a || '@audit.test');
  PERFORM set_config('request.jwt.claim.sub', a::text, false);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', a, 'role', 'authenticated', 'email', 'signup@audit.test', 'user_metadata', json_build_object('name', 'Admin'))::text, false);
  PERFORM set_config('app.active_tenant_id', '', false);
  PERFORM _as_user();

  r := create_tenant_for_current_user('{"name":"Société Signup","country":"France","currency":"EUR"}');
  t := (r->>'tenant_id')::uuid;
  PERFORM _rec('S01', 'l''inscription réussit', COALESCE((r->>'success')::boolean, false), r::text);

  PERFORM set_config('app.active_tenant_id', COALESCE(t::text, ''), false);
  SELECT count(*) INTO nca FROM chart_accounts WHERE tenant_id = t;
  SELECT string_agg(code, ',' ORDER BY code) INTO jn FROM journals WHERE tenant_id = t;
  SELECT count(*) INTO nfy FROM fiscal_years WHERE tenant_id = t AND status = 'open';
  SELECT count(*) INTO ncs FROM company_settings WHERE tenant_id = t;
  PERFORM _rec('S02', 'la société reçoit plan, journaux AC/AN/BQ/OD/VT, exercice ouvert et paramètres',
    nca > 0 AND jn ~ 'AC' AND jn ~ 'AN' AND jn ~ 'BQ' AND jn ~ 'OD' AND jn ~ 'VT' AND nfy > 0 AND ncs = 1,
    format('comptes=%s journaux=%s exercices ouverts=%s paramètres=%s', nca, COALESCE(jn, '∅'), nfy, ncs));

  -- Comptes que les écritures automatiques imputent : facture (411000, 707000, TVA collectée
  -- FR20 selon vat_account_mapping, repli 445710 — 4457000 avant la 187), achat (401000,
  -- 607000, TVA déductible FR20, repli 445660 — 4456000 avant la 187), règlement (512000),
  -- clôture (120000, 129000).
  SELECT string_agg(code, ', ' ORDER BY code) INTO missing
  FROM (VALUES ('411000'), ('707000'), ('401000'), ('607000'), ('512000'), ('120000'), ('129000'), ('445710'), ('445660'),
               ((SELECT account_code FROM vat_account_mapping WHERE vat_code = 'FR20' AND direction = 'collected'
                 AND tenant_id = '00000000-0000-0000-0000-000000000000')),
               ((SELECT account_code FROM vat_account_mapping WHERE vat_code = 'FR20' AND direction = 'deductible'
                 AND tenant_id = '00000000-0000-0000-0000-000000000000'))) v(code)
  WHERE code IS NOT NULL AND NOT EXISTS (SELECT 1 FROM chart_accounts ca WHERE ca.tenant_id = t AND ca.code = v.code);
  PERFORM _rec('S03', 'les comptes des écritures automatiques existent dans le plan semé', nca > 0 AND missing IS NULL,
    CASE WHEN nca = 0 THEN 'plan vide' ELSE 'absents : ' || COALESCE(missing, 'aucun') END);
END $$;

-- S04 — bootstrap_tenant refuse une société à laquelle l'appelant n'appartient pas.
-- Témoin obligatoire : le même appel sur SA propre société doit réussir, sinon un
-- refus ne prouve rien (bootstrap_tenant échouait alors pour tout le monde).
DO $$
DECLARE victim uuid := _mk_tenant('S04-victime'); attacker uuid; n_victim int; n_own int;
BEGIN
  DELETE FROM company_settings WHERE tenant_id = victim;
  attacker := _mk_tenant('S04-attaquant');
  DELETE FROM company_settings WHERE tenant_id = attacker;
  PERFORM _as_user();
  BEGIN PERFORM bootstrap_tenant(attacker); EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN PERFORM bootstrap_tenant(victim);   EXCEPTION WHEN OTHERS THEN NULL; END;
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*) INTO n_own FROM company_settings WHERE tenant_id = attacker;
  SELECT count(*) INTO n_victim FROM company_settings WHERE tenant_id = victim;
  PERFORM _rec('S04', 'bootstrap_tenant refusé sur la société d''un autre (témoin : accepté sur la sienne)',
    n_own = 1 AND n_victim = 0,
    CASE WHEN n_own = 0 THEN 'inconclusif : bootstrap_tenant échoue aussi sur la propre société de l''appelant'
         WHEN n_victim > 0 THEN 'paramètres société écrits chez la victime par un tiers'
         ELSE 'refusé chez la victime, accepté chez soi' END);
END $$;

-- S05 — bootstrap_tenant n'est pas exécutable sans être connecté
DO $$
BEGIN
  PERFORM _rec('S05', 'bootstrap_tenant non exécutable par anon',
    NOT has_function_privilege('anon', 'bootstrap_tenant(uuid)', 'EXECUTE'),
    CASE WHEN has_function_privilege('anon', 'bootstrap_tenant(uuid)', 'EXECUTE') THEN 'EXECUTE accordé à anon (via PUBLIC)' ELSE 'refusé' END);
END $$;

-- S06 — un échec d'inscription ne laisse pas de société à moitié créée
DO $$
DECLARE a uuid := uuid_generate_v4(); r jsonb; n int;
BEGIN
  INSERT INTO auth.users (id, email) VALUES (a, 'signup-ko-' || a || '@audit.test');
  PERFORM set_config('request.jwt.claim.sub', a::text, false);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, false);  -- pas d'e-mail
  PERFORM _as_user();
  r := create_tenant_for_current_user('{"name":"Société Incomplète"}');
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*) INTO n FROM tenants WHERE name = 'Société Incomplète';
  PERFORM _rec('S06', 'inscription en échec : aucune société résiduelle',
    NOT COALESCE((r->>'success')::boolean, true) AND n = 0, format('retour=%s sociétés résiduelles=%s', r, n));
END $$;

-- S07 — la devise choisie à l'inscription existe dans la société (AUD-B03)
DO $$
DECLARE a uuid := uuid_generate_v4(); r jsonb; t uuid; n int;
BEGIN
  INSERT INTO auth.users (id, email) VALUES (a, 'signup-dj-' || a || '@audit.test');
  PERFORM set_config('request.jwt.claim.sub', a::text, false);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated', 'email', 'dj@audit.test')::text, false);
  PERFORM set_config('app.active_tenant_id', '', false);
  PERFORM _as_user();
  r := create_tenant_for_current_user('{"name":"Société Djibouti","country":"Djibouti","currency":"DJF"}');
  t := (r->>'tenant_id')::uuid;
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*) INTO n FROM currencies WHERE tenant_id = t AND code = 'DJF';
  PERFORM _rec('S07', 'la devise de la société (DJF) est créée à l''inscription',
    COALESCE((r->>'success')::boolean, false) AND n = 1, format('success=%s devise DJF=%s', r->>'success', n));
END $$;

-- S08 — le contrôle de fin d'inscription nomme ce qui manque
DO $$
DECLARE t uuid := _mk_tenant('S08', false); msg text;
BEGIN
  DELETE FROM chart_accounts WHERE tenant_id = t;
  DELETE FROM journals WHERE tenant_id = t;
  DELETE FROM company_settings WHERE tenant_id = t;
  BEGIN
    PERFORM assert_tenant_ready(t);
    msg := 'aucune erreur levée';
  EXCEPTION WHEN OTHERS THEN msg := SQLERRM; END;
  PERFORM _rec('S08', 'assert_tenant_ready liste plan, journaux, exercice et paramètres manquants',
    msg ~ 'plan comptable' AND msg ~ 'journal VT' AND msg ~ 'exercice ouvert' AND msg ~ 'paramètres société', msg);
END $$;

SELECT _audit_assert('182');
