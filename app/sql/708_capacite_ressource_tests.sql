-- ============================================================
-- 708_capacite_ressource_tests.sql — F.5 / PRJ-02 :
--   UNE CAPACITÉ PAR PÉRIODE, PAS DEUX QUI SE CHEVAUCHENT
--
--   T01  RLS FORCÉE sur `resource_capacities`
--   T02  une capacité valide s'enregistre (35 h/semaine sur janvier)
--   T03  refus : plus de 168 h par semaine (CHECK)
--   T04  refus : une période à l'envers (CHECK)
--   T05  refus : une capacité QUI SE CHEVAUCHE pour le même salarié
--        (CAPACITY_OVERLAP — la règle qu'aucune clé ni CHECK ne peut tenir)
--   T06  refus : le salarié d'une AUTRE société (clé composite, 23503)
--   T07  contre-épreuve : des périodes ADJACENTES (non chevauchantes) passent
--   T08  le visiteur (`anon`) n'a aucun droit
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '708', false);
DELETE FROM _audit_results WHERE file = '708';

DO $$
DECLARE v boolean;
BEGIN
  SELECT relforcerowsecurity INTO v FROM pg_class
   WHERE relname = 'resource_capacities';
  PERFORM _rec('T01', 'RLS FORCÉE sur `resource_capacities`',
    v IS TRUE, format('relforcerowsecurity = %s', COALESCE(v::text, 'NULL')));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T01', 'RLS forcée', false, SQLERRM);
END $$;

DO $$
DECLARE privs text;
BEGIN
  SELECT string_agg(DISTINCT privilege_type, ',') INTO privs
    FROM information_schema.role_table_grants
   WHERE grantee = 'anon' AND table_name = 'resource_capacities';
  PERFORM _rec('T08', 'le visiteur (`anon`) n''a AUCUN droit sur les capacités',
    privs IS NULL, format('droits d''anon = %s', COALESCE(privs, 'aucun')));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T08', 'anon sans droits', false, SQLERRM);
END $$;

-- T02 → T07 : un décor partagé (un salarié, sa capacité, une seconde société)
DO $$
DECLARE
  ta uuid; tb uuid; emp uuid; empb uuid; n int; ok boolean;
BEGIN
  ta := _mk_tenant('F708A');
  INSERT INTO employees (tenant_id, name, status) VALUES (ta, 'Alice Capacité', 'active')
    RETURNING id INTO emp;
  tb := _mk_tenant('F708B');
  INSERT INTO employees (tenant_id, name, status) VALUES (tb, 'Bob Autre', 'active')
    RETURNING id INTO empb;

  -- T02 — une capacité valide
  INSERT INTO resource_capacities (tenant_id, employee_id, period_start, period_end, weekly_hours)
    VALUES (ta, emp, DATE '2026-01-01', DATE '2026-01-31', 35);
  SELECT count(*) INTO n FROM resource_capacities WHERE employee_id = emp;
  PERFORM _rec('T02', 'une capacité valide s''enregistre (35 h/semaine sur janvier)',
    n = 1, format('capacités du salarié = %s (attendu 1)', n));

  -- T03 — plus de 168 h par semaine
  ok := false;
  BEGIN
    INSERT INTO resource_capacities (tenant_id, employee_id, period_start, period_end, weekly_hours)
      VALUES (ta, emp, DATE '2026-03-01', DATE '2026-03-31', 200);
  EXCEPTION WHEN OTHERS THEN ok := SQLSTATE = '23514'; END;
  PERFORM _rec('T03', 'refus : plus de 168 heures par semaine (CHECK)', ok,
    format('check_violation 23514 obtenue = %s', ok));

  -- T04 — période à l'envers
  ok := false;
  BEGIN
    INSERT INTO resource_capacities (tenant_id, employee_id, period_start, period_end, weekly_hours)
      VALUES (ta, emp, DATE '2026-04-30', DATE '2026-04-01', 20);
  EXCEPTION WHEN OTHERS THEN ok := SQLSTATE = '23514'; END;
  PERFORM _rec('T04', 'refus : une période à l''envers (fin avant début, CHECK)', ok,
    format('check_violation 23514 obtenue = %s', ok));

  -- T05 — chevauchement (janvier est déjà couvert)
  ok := false;
  BEGIN
    INSERT INTO resource_capacities (tenant_id, employee_id, period_start, period_end, weekly_hours)
      VALUES (ta, emp, DATE '2026-01-15', DATE '2026-02-15', 20);
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM LIKE '%CAPACITY_OVERLAP%'; END;
  PERFORM _rec('T05', 'refus : une capacité QUI SE CHEVAUCHE pour le même salarié (CAPACITY_OVERLAP)', ok,
    format('refus nommé CAPACITY_OVERLAP = %s', ok));

  -- T06 — le salarié d'une autre société
  ok := false;
  BEGIN
    INSERT INTO resource_capacities (tenant_id, employee_id, period_start, period_end, weekly_hours)
      VALUES (ta, empb, DATE '2026-05-01', DATE '2026-05-31', 35);
  EXCEPTION WHEN OTHERS THEN ok := SQLSTATE = '23503'; END;
  PERFORM _rec('T06', 'refus : le salarié d''une AUTRE société (clé composite, ISO-02)', ok,
    format('foreign_key_violation 23503 obtenue = %s', ok));

  -- T07 — contre-épreuve : une période ADJACENTE (février) passe
  INSERT INTO resource_capacities (tenant_id, employee_id, period_start, period_end, weekly_hours)
    VALUES (ta, emp, DATE '2026-02-01', DATE '2026-02-28', 28);
  SELECT count(*) INTO n FROM resource_capacities WHERE employee_id = emp;
  PERFORM _rec('T07', 'contre-épreuve : une période ADJACENTE (février) est acceptée',
    n = 2, format('capacités du salarié = %s (attendu 2)', n));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T02', 'capacité valide', false, SQLERRM);
  PERFORM _rec('T03', 'plus de 168 h', false, SQLERRM);
  PERFORM _rec('T04', 'période à l''envers', false, SQLERRM);
  PERFORM _rec('T05', 'chevauchement', false, SQLERRM);
  PERFORM _rec('T06', 'salarié d''une autre société', false, SQLERRM);
  PERFORM _rec('T07', 'période adjacente', false, SQLERRM);
END $$;

-- Garde-fou anti-faux-vert : la suite EXIGE ses 8 verdicts
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM _audit_results WHERE file = '708';
  IF n <> 8 THEN
    RAISE EXCEPTION '[708] % verdict(s) enregistré(s) au lieu de 8 — un scénario n''a pas été joué', n;
  END IF;
END $$;

SELECT _audit_assert('708');

