-- ============================================================
-- 384_resolve_account_tests.sql — LOT 1-B : la résolution d'un compte
--
--   T01  tenant_account_roles / tenant_journal_roles existent, sous RLS ;
--   T02  surcharge SOCIÉTÉ : tenant_account_roles l'emporte ;
--   T03  repli sur le RÔLE DU PACK (lignée) quand la société n'en a pas ;
--   T04  rôle non mappé → échec EXPLICITE ROLE_NON_MAPPE (jamais de silence) ;
--   T05  compte absent du plan → COMPTE_ABSENT ;
--   T06  resolve_journal rend un journal par son rôle ;
--   T07  le plan d'une AUTRE société ne peut pas être résolu (RLS).
--
-- Vu ROUGE avant la 384 : T01 (tables absentes), T02..T07 (fonctions absentes).
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '384', false);
DELETE FROM _audit_results WHERE file = '384';

-- ─────────────────────────────────────────────────────────────
-- T01 — les deux tables de surcharge, sous RLS
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v_n int; v_rls int; v_pol int;
BEGIN
  SELECT count(*) INTO v_n FROM information_schema.tables
   WHERE table_schema = 'public' AND table_name IN ('tenant_account_roles','tenant_journal_roles');
  SELECT count(*) INTO v_rls FROM pg_class
   WHERE relname IN ('tenant_account_roles','tenant_journal_roles') AND relrowsecurity;
  SELECT count(*) INTO v_pol FROM pg_policies
   WHERE tablename IN ('tenant_account_roles','tenant_journal_roles');
  PERFORM _rec('T01', 'les deux tables de surcharge existent et sont sous RLS',
    v_n = 2 AND v_rls = 2 AND v_pol >= 2,
    format('tables=%s (2) ; sous RLS=%s (2) ; politiques=%s', v_n, v_rls, v_pol));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T01', 'les deux tables de surcharge existent et sont sous RLS', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T02 — surcharge SOCIÉTÉ
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE t uuid; ac text; v text;
BEGIN
  t := _mk_tenant('RACCT');
  SELECT code INTO ac FROM chart_accounts WHERE tenant_id = t ORDER BY code LIMIT 1;
  INSERT INTO tenant_account_roles (tenant_id, role, account_code) VALUES (t, 'CLIENTS', ac)
    ON CONFLICT (tenant_id, role) DO UPDATE SET account_code = EXCLUDED.account_code;

  SELECT resolve_account(t, 'CLIENTS') INTO v;
  PERFORM _rec('T02', 'resolve_account lit d''abord la surcharge de la SOCIÉTÉ',
    v = ac, format('compte=%s (attendu %s)', v, ac));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T02', 'resolve_account lit d''abord la surcharge de la SOCIÉTÉ', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T03 — repli sur le rôle du PACK (lignée)
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE t uuid; ac text; v text;
BEGIN
  t := _mk_tenant('RACCT2');
  SELECT code INTO ac FROM chart_accounts WHERE tenant_id = t ORDER BY code LIMIT 1;
  UPDATE tenants SET legislation_pack_code = 'FR' WHERE id = t;
  INSERT INTO pack_account_roles (pack_code, role, account_code) VALUES ('FR', 'CLIENTS', ac)
    ON CONFLICT (pack_code, role) DO UPDATE SET account_code = EXCLUDED.account_code;

  SELECT resolve_account(t, 'CLIENTS') INTO v;
  PERFORM _rec('T03', 'sans surcharge société, resolve_account lit le rôle du PACK (lignée)',
    v = ac, format('compte=%s (attendu %s, depuis le pack FR)', v, ac));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T03', 'sans surcharge société, resolve_account lit le rôle du PACK (lignée)', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T04 — rôle non mappé : échec EXPLICITE
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE t uuid; msg text := '';
BEGIN
  t := _mk_tenant('RACCT3');
  BEGIN
    PERFORM resolve_account(t, 'COMPTE_ATTENTE');
  EXCEPTION WHEN OTHERS THEN msg := SQLERRM; END;
  PERFORM _rec('T04', 'un rôle non mappé échoue EXPLICITEMENT (ROLE_NON_MAPPE), jamais en silence',
    msg LIKE 'ROLE_NON_MAPPE%', format('message=%s', left(msg, 90)));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T04', 'un rôle non mappé échoue EXPLICITEMENT (ROLE_NON_MAPPE), jamais en silence', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T05 — compte absent du plan : COMPTE_ABSENT
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE t uuid; msg text := '';
BEGIN
  t := _mk_tenant('RACCT4');
  INSERT INTO tenant_account_roles (tenant_id, role, account_code) VALUES (t, 'CLIENTS', '999999')
    ON CONFLICT (tenant_id, role) DO UPDATE SET account_code = EXCLUDED.account_code;
  BEGIN
    PERFORM resolve_account(t, 'CLIENTS');
  EXCEPTION WHEN OTHERS THEN msg := SQLERRM; END;
  PERFORM _rec('T05', 'un rôle qui pointe un compte absent du plan échoue (COMPTE_ABSENT)',
    msg LIKE 'COMPTE_ABSENT%', format('message=%s', left(msg, 90)));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T05', 'un rôle qui pointe un compte absent du plan échoue (COMPTE_ABSENT)', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T06 — resolve_journal
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE t uuid; v text;
BEGIN
  t := _mk_tenant('RACCT5');
  INSERT INTO tenant_journal_roles (tenant_id, role, journal_code) VALUES (t, 'JOURNAL_VENTES', 'VT')
    ON CONFLICT (tenant_id, role) DO UPDATE SET journal_code = EXCLUDED.journal_code;
  SELECT resolve_journal(t, 'JOURNAL_VENTES') INTO v;
  PERFORM _rec('T06', 'resolve_journal rend le journal du rôle (surcharge société)',
    v = 'VT', format('journal=%s (VT attendu)', COALESCE(v, 'NULL')));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T06', 'resolve_journal rend le journal du rôle (surcharge société)', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T07 — une société ne peut PAS résoudre le plan d'une autre
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE ta uuid; tb uuid; msg text := 'aucune erreur';
BEGIN
  ta := _mk_tenant('RACCTA');
  tb := _mk_tenant('RACCTB');
  UPDATE tenants SET legislation_pack_code = 'FR' WHERE id = tb;
  PERFORM set_config('app.active_tenant_id', ta::text, false);
  PERFORM _as_user();
  BEGIN
    PERFORM resolve_account(tb, 'CLIENTS');
  EXCEPTION WHEN OTHERS THEN msg := SQLERRM; END;
  EXECUTE 'RESET ROLE';
  PERFORM _rec('T07', 'la RLS empêche une société de résoudre le plan d''une AUTRE',
    msg NOT LIKE 'aucune erreur%',
    format('message=%s', left(msg, 90)));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T07', 'la RLS empêche une société de résoudre le plan d''une AUTRE', false, SQLERRM);
END $$;

-- Nettoyage de la fixture
DELETE FROM tenant_account_roles  WHERE role IN ('CLIENTS','JOURNAL_VENTES');
DELETE FROM tenant_journal_roles  WHERE role = 'JOURNAL_VENTES';
DELETE FROM pack_account_roles    WHERE pack_code = 'FR' AND role = 'CLIENTS';
UPDATE tenants SET legislation_pack_code = NULL WHERE name IN ('RACCT2','RACCTB');

SELECT _audit_assert('384');
