-- ============================================================
-- 270_anon_and_global_rows_write_closed_tests.sql — vague X1-urgent
-- (audit fonctionnel exécuté du 28/09/2026, défauts C1 et C2)
--
-- MESURÉ AVANT, sur base neuve (238 migrations, 0 erreur) :
--   * `anon` — le visiteur NON CONNECTÉ — détenait INSERT, UPDATE, DELETE et
--     TRUNCATE sur 72 tables de `public` (TRUNCATE ignore la RLS) ;
--   * `webhook_event_catalog_all` : `ALL USING (true) WITH CHECK (true)` —
--     n'importe qui modifiait, créait, supprimait le catalogue (C1) ;
--   * `payroll_legal_params_all` : `ALL USING (tenant_id IS NULL OR …)` — les
--     paramètres légaux GLOBAUX (SMIC, majoration, PMSS…) étaient réécrits par
--     un anonyme ou un lecteur, pour TOUTES les sociétés (C2) ;
--   * `banks` (référentiel global, sans société) : l'admin de n'importe quelle
--     société le modifiait pour toutes les autres.
--
-- Ce que ce fichier prouve :
--   T01 un anonyme ne modifie pas `webhook_event_catalog`             (C1)
--   T02 un anonyme ne réécrit pas le SMIC global                       (C2)
--   T03 un utilisateur connecté (admin de SA société) ne réécrit pas
--       une ligne GLOBALE de `payroll_legal_parameters`                (C2)
--   T04 … mais peut toujours poser SON paramètre de société, que la
--       base relit en priorité (non-régression)
--   T05 un lecteur ne pose pas de paramètre, même pour sa société
--   T06 l'admin d'une société ne modifie pas le référentiel `banks`
--   T07 `anon` ne détient plus aucun droit d'écriture ni TRUNCATE sur
--       les tables de `public`
--   T08 la lecture reste ouverte (catalogue, paramètres globaux,
--       banques) : rien n'a été fermé de trop
--
-- T01, T02, T03, T06, T07 sont ROUGES avant la 270.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '270', false);
DELETE FROM _audit_results WHERE file = '270';

-- T01 — anonyme sur le catalogue des événements
DO $$
DECLARE n int := 0; err text := '—';
BEGIN
  PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true);
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('role', 'anon', true);
  BEGIN
    UPDATE webhook_event_catalog SET is_active = is_active;
    GET DIAGNOSTICS n = ROW_COUNT;
  EXCEPTION WHEN insufficient_privilege THEN err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);
  PERFORM _rec('T01', 'un visiteur non connecté ne modifie pas webhook_event_catalog',
    n = 0, format('lignes modifiées=%s ; erreur=%s', n, err));
END $$;

-- T02 — anonyme sur le SMIC global
DO $$
DECLARE n int := 0; err text := '—';
BEGIN
  PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true);
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('role', 'anon', true);
  BEGIN
    UPDATE payroll_legal_parameters SET value = value WHERE tenant_id IS NULL AND code = 'SMIC_H';
    GET DIAGNOSTICS n = ROW_COUNT;
  EXCEPTION WHEN insufficient_privilege THEN err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);
  PERFORM _rec('T02', 'un visiteur non connecté ne réécrit pas le SMIC global',
    n = 0, format('lignes modifiées=%s ; erreur=%s', n, err));
END $$;

-- T03 à T06 — société de test
DO $$
DECLARE
  t uuid; v uuid; n int := 0; err text := '—'; code_ok boolean; lu numeric;
  n_ins int := 0; err_v text := '—'; n_bank int := 0; err_b text := '—';
BEGIN
  t := _mk_tenant('X1U270');

  -- T03 : admin connecté, ligne GLOBALE
  PERFORM _as_user();
  BEGIN
    UPDATE payroll_legal_parameters SET value = value WHERE tenant_id IS NULL AND code = 'SMIC_H';  -- valeur inchangée : un test rouge ne doit pas corrompre la base
    GET DIAGNOSTICS n = ROW_COUNT;
  EXCEPTION WHEN insufficient_privilege THEN err := SQLERRM;
  END;
  PERFORM _rec('T03', 'l''admin d''une société ne réécrit pas une ligne globale (SMIC_H)',
    n = 0, format('lignes globales modifiées=%s ; erreur=%s', n, err));

  -- T04 : admin connecté, SON paramètre
  BEGIN
    INSERT INTO payroll_legal_parameters (tenant_id, country_code, code, value, valid_from)
    SELECT t, country_code, 'MAJORATION_HEURES_SUP', 1.5, valid_from
    FROM payroll_legal_parameters WHERE tenant_id IS NULL AND code = 'MAJORATION_HEURES_SUP' LIMIT 1;
    code_ok := true;
  EXCEPTION WHEN OTHERS THEN code_ok := false; err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);
  SELECT value INTO lu FROM payroll_legal_parameters WHERE tenant_id = t AND code = 'MAJORATION_HEURES_SUP';
  PERFORM _rec('T04', 'l''admin pose toujours le paramètre de SA société',
    code_ok AND lu = 1.5, format('inséré=%s valeur=%s err=%s', code_ok, lu, err));

  -- T05 : lecteur de la même société
  INSERT INTO auth.users (id, email) VALUES (uuid_generate_v4(), 'lecteur270@audit.test') RETURNING id INTO v;
  INSERT INTO tenant_users (tenant_id, auth_id, email, name, role, status)
    VALUES (t, v, 'lecteur270@audit.test', 'Lecteur', 'viewer', 'active');
  PERFORM set_config('request.jwt.claim.sub', v::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v, 'role', 'authenticated')::text, true);
  PERFORM _as_user();
  BEGIN
    INSERT INTO payroll_legal_parameters (tenant_id, country_code, code, value, valid_from)
    VALUES (t, 'FR', 'PMSS', 1, DATE '2026-01-01');
    GET DIAGNOSTICS n_ins = ROW_COUNT;
  EXCEPTION WHEN insufficient_privilege THEN err_v := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);
  PERFORM _rec('T05', 'un lecteur ne pose pas de paramètre légal, même pour sa société',
    n_ins = 0, format('lignes insérées=%s ; erreur=%s', n_ins, err_v));

  -- T06 : l'admin et le référentiel global des banques
  SELECT auth_id INTO v FROM tenant_users WHERE tenant_id = t AND role = 'admin' LIMIT 1;
  PERFORM set_config('request.jwt.claim.sub', v::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v, 'role', 'authenticated')::text, true);
  INSERT INTO banks (name, country) VALUES ('Banque témoin 270', 'FR');
  PERFORM _as_user();
  BEGIN
    UPDATE banks SET name = 'Réécrite' WHERE name = 'Banque témoin 270';
    GET DIAGNOSTICS n_bank = ROW_COUNT;
  EXCEPTION WHEN insufficient_privilege THEN err_b := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);
  PERFORM _rec('T06', 'l''admin d''une société ne modifie pas le référentiel global des banques',
    n_bank = 0, format('lignes modifiées=%s ; erreur=%s', n_bank, err_b));
  DELETE FROM banks WHERE name IN ('Banque témoin 270', 'Réécrite');
END $$;

-- T07 — plus aucun droit d'écriture pour anon
DO $$
DECLARE nb int; liste text;
BEGIN
  SELECT count(DISTINCT c.oid), string_agg(DISTINCT c.relname, ', ')
    INTO nb, liste
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
  WHERE c.relkind IN ('r', 'p', 'v', 'm', 'f')
    AND c.relname NOT LIKE '\_%'   -- outillage de test (audit_helpers), jamais en production
    AND (has_table_privilege('anon', c.oid, 'INSERT') OR has_table_privilege('anon', c.oid, 'UPDATE')
      OR has_table_privilege('anon', c.oid, 'DELETE') OR has_table_privilege('anon', c.oid, 'TRUNCATE'));
  PERFORM _rec('T07', 'anon ne détient plus aucun droit d''écriture ni TRUNCATE dans public',
    nb = 0, format('%s relation(s) : %s', nb, left(coalesce(liste, '—'), 300)));
END $$;

-- T08 — la lecture n'a pas été fermée de trop
DO $$
DECLARE cat int; par int; bq int;
BEGIN
  PERFORM _mk_tenant('X1U270L');
  PERFORM _as_user();
  SELECT count(*) INTO cat FROM webhook_event_catalog;
  SELECT count(*) INTO par FROM payroll_legal_parameters WHERE tenant_id IS NULL;
  SELECT count(*) INTO bq FROM banks;
  PERFORM set_config('role', 'postgres', true);
  PERFORM _rec('T08', 'un utilisateur connecté lit toujours le catalogue et les paramètres globaux',
    cat > 0 AND par > 0, format('catalogue=%s paramètres globaux=%s banques=%s', cat, par, bq));
END $$;

SELECT _audit_assert('270');
