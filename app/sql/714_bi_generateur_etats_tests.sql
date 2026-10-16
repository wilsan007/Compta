-- ============================================================
-- 714_bi_generateur_etats_tests.sql — F.6 / BI-01 :
--   LE GÉNÉRATEUR D'ÉTATS, CONTRAINT ET OPPOSABLE
--
--   T01  RLS FORCED, index de société, 4 politiques par table
--   T02  `anon` ne lit pas
--   T03  les trois commandes d'ÉCRITURE portent `can_perform`
--   T04  un LECTEUR n'écrit pas ; un administrateur écrit
--   T05  le rôle FIN : le comptable insère et modifie
--   T06  CHECK report_type (valeur hors liste refusée)
--   T07  CHECK category (valeur hors liste refusée)
--   T08  CHECK page_orientation / page_size (NULL OK, invalide refusé)
--   T09  CHECK name (vide refusé, > 200 refusé)
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '714', false);
DELETE FROM _audit_results WHERE file = '714';

-- T01 : RLS FORCED + index de société + 4 politiques
DO $$
DECLARE v boolean; n bigint;
BEGIN
  SELECT COUNT(*) INTO n FROM pg_policies
   WHERE tablename = 'custom_report_templates' AND schemaname = 'public';
  PERFORM _rec('T01a', 'custom_report_templates : 4 politiques', n = 4,
    format('politiques = %s (attendu 4)', n));

  SELECT COUNT(*) INTO n FROM pg_policies
   WHERE tablename = 'reporting_plans' AND schemaname = 'public';
  PERFORM _rec('T01b', 'reporting_plans : 4 politiques', n = 4,
    format('politiques = %s (attendu 4)', n));

  SELECT relforcerowsecurity INTO v FROM pg_class
   WHERE relname = 'custom_report_templates';
  PERFORM _rec('T01c', 'custom_report_templates : RLS FORCED', v, NULL);

  SELECT relforcerowsecurity INTO v FROM pg_class
   WHERE relname = 'reporting_plans';
  PERFORM _rec('T01d', 'reporting_plans : RLS FORCED', v, NULL);

  SELECT COUNT(*) INTO n FROM pg_indexes
   WHERE tablename = 'custom_report_templates' AND indexdef LIKE '%tenant_id%';
  PERFORM _rec('T01e', 'custom_report_templates : index tenant_id', n = 1,
    format('index tenant_id = %s (attendu 1)', n));

  SELECT COUNT(*) INTO n FROM pg_indexes
   WHERE tablename = 'reporting_plans' AND indexdef LIKE '%tenant_id%';
  PERFORM _rec('T01f', 'reporting_plans : index tenant_id', n = 1,
    format('index tenant_id = %s (attendu 1)', n));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T01a', 'RLS / index / politiques', false, SQLERRM);
END $$;

-- T02 : anon n'a aucun droit sur les deux tables (statique, comme 713 :
-- on ne peut pas appeler _rec() sous anon — la table de verdicts est protégée)
DO $$
DECLARE v_tab int;
BEGIN
  SELECT count(*) INTO v_tab FROM information_schema.role_table_grants
   WHERE table_name IN ('custom_report_templates', 'reporting_plans')
     AND grantee = 'anon';
  PERFORM _rec('T02', 'anon ne lit pas, n''écrit pas (0 droit sur les 2 tables)',
    v_tab = 0,
    format('droits de table du visiteur = %s (attendu 0)', v_tab));
END $$;

-- T03 : INSERT/UPDATE/DELETE portent can_perform (les deux tables)
DO $$
DECLARE v bigint;
BEGIN
  SELECT COUNT(*) INTO v FROM pg_policies
   WHERE tablename = 'custom_report_templates' AND cmd = 'INSERT'
     AND (COALESCE(with_check,'') LIKE '%can_perform%'
          OR COALESCE(qual,'') LIKE '%can_perform%');
  PERFORM _rec('T03a', 'crt INSERT porte can_perform', v = 1,
    format('INSERT can_perform = %s (attendu 1)', v));

  SELECT COUNT(*) INTO v FROM pg_policies
   WHERE tablename = 'custom_report_templates' AND cmd = 'UPDATE'
     AND COALESCE(qual,'') LIKE '%can_perform%';
  PERFORM _rec('T03b', 'crt UPDATE porte can_perform', v = 1,
    format('UPDATE can_perform = %s (attendu 1)', v));

  SELECT COUNT(*) INTO v FROM pg_policies
   WHERE tablename = 'custom_report_templates' AND cmd = 'DELETE'
     AND COALESCE(qual,'') LIKE '%can_perform%';
  PERFORM _rec('T03c', 'crt DELETE porte can_perform', v = 1,
    format('DELETE can_perform = %s (attendu 1)', v));

  SELECT COUNT(*) INTO v FROM pg_policies
   WHERE tablename = 'reporting_plans' AND cmd = 'INSERT'
     AND (COALESCE(with_check,'') LIKE '%can_perform%'
          OR COALESCE(qual,'') LIKE '%can_perform%');
  PERFORM _rec('T03d', 'reporting_plans INSERT porte can_perform', v = 1,
    format('INSERT can_perform = %s (attendu 1)', v));

  SELECT COUNT(*) INTO v FROM pg_policies
   WHERE tablename = 'reporting_plans' AND cmd = 'UPDATE'
     AND COALESCE(qual,'') LIKE '%can_perform%';
  PERFORM _rec('T03e', 'reporting_plans UPDATE porte can_perform', v = 1,
    format('UPDATE can_perform = %s (attendu 1)', v));

  SELECT COUNT(*) INTO v FROM pg_policies
   WHERE tablename = 'reporting_plans' AND cmd = 'DELETE'
     AND COALESCE(qual,'') LIKE '%can_perform%';
  PERFORM _rec('T03f', 'reporting_plans DELETE porte can_perform', v = 1,
    format('DELETE can_perform = %s (attendu 1)', v));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T03a', 'can_perform sur les 3 commandes', false, SQLERRM);
END $$;


-- T04 : lecteur n'écrit pas ; admin écrit (sous authenticated)
DO $$
DECLARE
  ta uuid; aAdmin uuid; aLect uuid;
  v_ok boolean; v_id uuid; n bigint;
BEGIN
  ta := _mk_tenant('F714A');
  SELECT auth_id INTO aAdmin FROM tenant_users
   WHERE tenant_id = ta AND name = 'Admin' LIMIT 1;
  aLect := uuid_generate_v4();
  INSERT INTO auth.users (id, email) VALUES (aLect, 'lecteur714@audit.test');
  INSERT INTO tenant_users (tenant_id, auth_id, email, name, role, status, created_at)
    VALUES (ta, aLect, 'lecteur714@audit.test', 'Lecteur', 'viewer', 'active', now());

  -- LECTEUR : INSERT refusé
  PERFORM set_config('request.jwt.claim.sub', aLect::text, true);
  PERFORM set_config('request.headers',
    json_build_object('x-tenant-id', ta::text)::text, false);
  PERFORM _as_user();
  BEGIN
    INSERT INTO custom_report_templates (tenant_id, name, report_type, category)
      VALUES (ta, 'Test lecteur', 'trial_balance', 'accounting');
    v_ok := false;
  EXCEPTION WHEN OTHERS THEN v_ok := true;
  END;
  PERFORM _rec('T04a', 'LECTEUR ne peut PAS inserer un rapport', v_ok, NULL);

  -- ADMIN : INSERT OK
  PERFORM set_config('request.jwt.claim.sub', aAdmin::text, true);
  BEGIN
    INSERT INTO custom_report_templates (tenant_id, name, report_type, category)
      VALUES (ta, 'Rapport admin', 'trial_balance', 'accounting')
      RETURNING id INTO v_id;
    v_ok := true;
  EXCEPTION WHEN OTHERS THEN
    v_ok := false; v_id := NULL;
  END;
  SELECT COUNT(*) INTO n FROM custom_report_templates
   WHERE id = v_id AND tenant_id = ta;
  PERFORM _rec('T04b', 'ADMIN peut inserer un rapport', v_ok AND n = 1,
    format('insert ok = %s, lignes = %s', v_ok, n));

  -- LECTEUR : DELETE n'atteint rien (RLS silencieuse — la preuve est que
  -- la ligne SURVIT, pas qu'une exception est levée)
  PERFORM set_config('request.jwt.claim.sub', aLect::text, true);
  BEGIN
    DELETE FROM custom_report_templates WHERE id = v_id;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  SELECT COUNT(*) INTO n FROM custom_report_templates WHERE id = v_id;
  PERFORM _rec('T04c', 'LECTEUR ne peut PAS supprimer un rapport (ligne survit)',
    n = 1, format('lignes restantes = %s (attendu 1)', n));

  PERFORM set_config('request.jwt.claim.sub', '', true);
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T04a', 'lecteur/admin', false, SQLERRM);
END $$;


-- T05 : comptable insère et modifie (sous authenticated)
DO $$
DECLARE
  ta uuid; aCompta uuid; v_ok boolean; v_id uuid; n bigint;
BEGIN
  ta := _mk_tenant('F714B');
  aCompta := uuid_generate_v4();
  INSERT INTO auth.users (id, email) VALUES (aCompta, 'compta714@audit.test');
  INSERT INTO tenant_users (tenant_id, auth_id, email, name, role, status, created_at)
    VALUES (ta, aCompta, 'compta714@audit.test', 'Compta', 'accountant', 'active', now());

  PERFORM set_config('request.jwt.claim.sub', aCompta::text, true);
  PERFORM set_config('request.headers',
    json_build_object('x-tenant-id', ta::text)::text, false);
  PERFORM _as_user();

  BEGIN
    INSERT INTO custom_report_templates (tenant_id, name, report_type, category)
      VALUES (ta, 'Compta rapport', 'general_ledger', 'accounting')
      RETURNING id INTO v_id;
    v_ok := true;
  EXCEPTION WHEN OTHERS THEN
    v_ok := false; v_id := NULL;
  END;
  SELECT COUNT(*) INTO n FROM custom_report_templates WHERE id = v_id;
  PERFORM _rec('T05a', 'COMPTABLE peut inserer', v_ok AND n = 1,
    format('insert ok = %s, lignes = %s', v_ok, n));

  BEGIN
    UPDATE custom_report_templates SET name = 'Compta rapport v2' WHERE id = v_id;
    v_ok := true;
  EXCEPTION WHEN OTHERS THEN v_ok := false;
  END;
  SELECT name = 'Compta rapport v2' INTO v_ok FROM custom_report_templates WHERE id = v_id;
  PERFORM _rec('T05b', 'COMPTABLE peut modifier', v_ok, NULL);

  PERFORM set_config('request.jwt.claim.sub', '', true);
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T05a', 'comptable', false, SQLERRM);
END $$;


-- T06→T09 : CHECK constraints (report_type, category, orientation/size, name)
DO $$
DECLARE
  ta uuid; aAdmin uuid; v_ok boolean;
BEGIN
  ta := _mk_tenant('F714C');
  SELECT auth_id INTO aAdmin FROM tenant_users
   WHERE tenant_id = ta AND name = 'Admin' LIMIT 1;
  PERFORM set_config('request.jwt.claim.sub', aAdmin::text, true);
  PERFORM set_config('request.headers',
    json_build_object('x-tenant-id', ta::text)::text, false);
  PERFORM _as_user();

  -- T06 : report_type hors liste refusé
  BEGIN
    INSERT INTO custom_report_templates (tenant_id, name, report_type, category)
      VALUES (ta, 'Bad type', 'INVALID_TYPE', 'accounting');
    v_ok := false;
  EXCEPTION WHEN check_violation THEN v_ok := true;
  WHEN OTHERS THEN v_ok := true;
  END;
  PERFORM _rec('T06', 'CHECK report_type refuse INVALID_TYPE', v_ok, NULL);

  -- T07 : category hors liste refusée
  BEGIN
    INSERT INTO custom_report_templates (tenant_id, name, report_type, category)
      VALUES (ta, 'Bad cat', 'trial_balance', 'INVALID_CATEGORY');
    v_ok := false;
  EXCEPTION WHEN check_violation THEN v_ok := true;
  WHEN OTHERS THEN v_ok := true;
  END;
  PERFORM _rec('T07', 'CHECK category refuse INVALID_CATEGORY', v_ok, NULL);

  -- T08a : orientation / taille NULL acceptés
  BEGIN
    INSERT INTO custom_report_templates
      (tenant_id, name, report_type, category, page_orientation, page_size)
      VALUES (ta, 'Nulls OK', 'trial_balance', 'accounting', NULL, NULL);
    v_ok := true;
  EXCEPTION WHEN OTHERS THEN v_ok := false;
  END;
  PERFORM _rec('T08a', 'page_orientation / page_size NULL acceptes', v_ok, NULL);

  -- T08b : orientation invalide refusée
  BEGIN
    INSERT INTO custom_report_templates
      (tenant_id, name, report_type, category, page_orientation)
      VALUES (ta, 'Bad orient', 'trial_balance', 'accounting', 'INVALID');
    v_ok := false;
  EXCEPTION WHEN check_violation THEN v_ok := true;
  WHEN OTHERS THEN v_ok := true;
  END;
  PERFORM _rec('T08b', 'CHECK page_orientation refuse INVALID', v_ok, NULL);

  -- T08c : page_size invalide refusée
  BEGIN
    INSERT INTO custom_report_templates
      (tenant_id, name, report_type, category, page_size)
      VALUES (ta, 'Bad size', 'trial_balance', 'accounting', 'INVALID');
    v_ok := false;
  EXCEPTION WHEN check_violation THEN v_ok := true;
  WHEN OTHERS THEN v_ok := true;
  END;
  PERFORM _rec('T08c', 'CHECK page_size refuse INVALID', v_ok, NULL);

  -- T09a : nom vide refusé
  BEGIN
    INSERT INTO custom_report_templates (tenant_id, name, report_type, category)
      VALUES (ta, '', 'trial_balance', 'accounting');
    v_ok := false;
  EXCEPTION WHEN check_violation THEN v_ok := true;
  WHEN OTHERS THEN v_ok := true;
  END;
  PERFORM _rec('T09a', 'CHECK name refuse vide', v_ok, NULL);

  -- T09b : nom trop long (201) refusé
  BEGIN
    INSERT INTO custom_report_templates (tenant_id, name, report_type, category)
      VALUES (ta, repeat('x', 201), 'trial_balance', 'accounting');
    v_ok := false;
  EXCEPTION WHEN check_violation THEN v_ok := true;
  WHEN OTHERS THEN v_ok := true;
  END;
  PERFORM _rec('T09b', 'CHECK name refuse > 200 caracteres', v_ok, NULL);

  PERFORM set_config('request.jwt.claim.sub', '', true);
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T06', 'CHECK constraints', false, SQLERRM);
END $$;

-- Bilan
SELECT _audit_assert('714');

RESET role;
