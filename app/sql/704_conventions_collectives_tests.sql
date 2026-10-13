-- ============================================================
-- 704_conventions_collectives_tests.sql — F.7 / PAY-08 :
--   LES CONVENTIONS COLLECTIVES SONT BRANCHÉES, ET LE RATTACHEMENT EST VALIDÉ
--
--   T01  RLS FORCÉE sur les deux tables (le défaut ISO-04 que la grille BT
--        comptait : `relforcerowsecurity` était faux)
--   T02  affectation : une convention + sa classification s'attachent à un salarié
--   T03  refus : la convention d'une AUTRE société (AGREEMENT_NOT_FOUND)
--   T04  refus : une classification qui n'appartient PAS à la convention
--        (CLASSIFICATION_MISMATCH) — les clés composites garantissent la société,
--        pas la cohérence interne
--   T05  refus : un NON-administrateur (PAY_FORBIDDEN)
--   T06  retrait : passer NULL retire l'affectation
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '704', false);
DELETE FROM _audit_results WHERE file = '704';

-- Pose le contexte d'une société (son admin).
CREATE OR REPLACE FUNCTION _l704_act_as(p_tenant uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE u uuid;
BEGIN
  PERFORM set_config('app.active_tenant_id', p_tenant::text, false);
  SELECT auth_id INTO u FROM tenant_users
   WHERE tenant_id = p_tenant AND role = 'admin' ORDER BY created_at LIMIT 1;
  PERFORM set_config('request.jwt.claim.sub', u::text, false);
END $$;

-- T01 — la RLS est désormais FORCÉE sur les deux tables
DO $$
DECLARE v boolean;
BEGIN
  SELECT bool_and(relforcerowsecurity) INTO v
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
   WHERE c.relname IN ('collective_agreements', 'collective_classifications');
  PERFORM _rec('T01', 'RLS FORCÉE sur `collective_agreements` et `collective_classifications` (défaut ISO-04 corrigé)',
    v IS TRUE, format('relforcerowsecurity = %s pour les deux', COALESCE(v::text, 'NULL')));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T01', 'RLS forcée sur les deux tables', false, SQLERRM);
END $$;

-- T02 → T06 : un décor partagé (une convention, deux classifications, un salarié)
DO $$
DECLARE
  ta uuid; tb uuid; ag uuid; ag2 uuid; cl uuid; cl2 uuid; agb uuid; emp uuid;
  r jsonb; v_ag uuid; v_cl uuid; ok boolean;
BEGIN
  ta := _mk_tenant('F704A');
  INSERT INTO collective_agreements (tenant_id, idcc_code, name, application_date)
    VALUES (ta, '1234', 'CCN A', DATE '2026-01-01') RETURNING id INTO ag;
  INSERT INTO collective_agreements (tenant_id, idcc_code, name, application_date)
    VALUES (ta, '5678', 'CCN A bis', DATE '2026-01-01') RETURNING id INTO ag2;
  INSERT INTO collective_classifications (tenant_id, agreement_id, coefficient, minimum_monthly_salary)
    VALUES (ta, ag, 200, 1800) RETURNING id INTO cl;
  INSERT INTO collective_classifications (tenant_id, agreement_id, coefficient, minimum_monthly_salary)
    VALUES (ta, ag2, 250, 2000) RETURNING id INTO cl2;
  INSERT INTO employees (tenant_id, name, status) VALUES (ta, 'Jean Test', 'active') RETURNING id INTO emp;

  -- T02 — affectation valide
  r := set_employee_collective_agreement(emp, ag, cl);
  SELECT collective_agreement_id, classification_id INTO v_ag, v_cl FROM employees WHERE id = emp;
  PERFORM _rec('T02', 'affectation : la convention ET sa classification s''attachent au salarié',
    (r ->> 'success')::boolean AND v_ag = ag AND v_cl = cl,
    format('convention=%s classification=%s', v_ag, v_cl));

  -- T03 — la convention d'une AUTRE société est refusée
  tb := _mk_tenant('F704B');
  INSERT INTO collective_agreements (tenant_id, idcc_code, name, application_date)
    VALUES (tb, '9999', 'CCN B', DATE '2026-01-01') RETURNING id INTO agb;
  PERFORM _l704_act_as(ta);
  ok := false;
  BEGIN
    PERFORM set_employee_collective_agreement(emp, agb, NULL);
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM LIKE '%AGREEMENT_NOT_FOUND%'; END;
  PERFORM _rec('T03', 'refus : la convention d''une autre société (AGREEMENT_NOT_FOUND)', ok,
    format('refus nommé AGREEMENT_NOT_FOUND = %s', ok));

  -- T04 — une classification d'une AUTRE convention est refusée
  ok := false;
  BEGIN
    PERFORM set_employee_collective_agreement(emp, ag, cl2);   -- cl2 appartient à ag2
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM LIKE '%CLASSIFICATION_MISMATCH%'; END;
  PERFORM _rec('T04', 'refus : une classification qui n''appartient pas à la convention (CLASSIFICATION_MISMATCH)', ok,
    format('refus nommé CLASSIFICATION_MISMATCH = %s', ok));

  -- T05 — un non-administrateur est refusé
  DECLARE v uuid := gen_random_uuid(); BEGIN
    INSERT INTO auth.users (id, email) VALUES (v, 'viewer-' || v || '@audit.test');
    INSERT INTO tenant_users (tenant_id, auth_id, email, name, role, status)
    VALUES (ta, v, 'viewer@audit.test', 'Viewer', 'viewer', 'active');
    PERFORM set_config('app.active_tenant_id', ta::text, false);
    PERFORM set_config('request.jwt.claim.sub', v::text, false);
    ok := false;
    BEGIN
      PERFORM set_employee_collective_agreement(emp, ag, cl);
    EXCEPTION WHEN OTHERS THEN ok := SQLERRM LIKE '%PAY_FORBIDDEN%'; END;
    PERFORM _rec('T05', 'refus : seul un administrateur affecte une convention (PAY_FORBIDDEN)', ok,
      format('refus nommé PAY_FORBIDDEN = %s', ok));
  END;

  -- T06 — le retrait (NULL) détache l'affectation
  PERFORM _l704_act_as(ta);
  PERFORM set_employee_collective_agreement(emp, NULL, NULL);
  SELECT collective_agreement_id, classification_id INTO v_ag, v_cl FROM employees WHERE id = emp;
  PERFORM _rec('T06', 'retrait : passer NULL détache convention et classification',
    v_ag IS NULL AND v_cl IS NULL,
    format('convention=%s classification=%s (attendus NULL)', v_ag, v_cl));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T02', 'affectation valide', false, SQLERRM);
  PERFORM _rec('T03', 'refus convention étrangère', false, SQLERRM);
  PERFORM _rec('T04', 'refus classification incohérente', false, SQLERRM);
  PERFORM _rec('T05', 'refus non-admin', false, SQLERRM);
  PERFORM _rec('T06', 'retrait', false, SQLERRM);
END $$;

-- Garde-fou anti-faux-vert : la suite EXIGE ses 6 verdicts
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM _audit_results WHERE file = '704';
  IF n <> 6 THEN
    RAISE EXCEPTION '[704] % verdict(s) enregistré(s) au lieu de 6 — un scénario n''a pas été joué', n;
  END IF;
END $$;

SELECT _audit_assert('704');

