-- ============================================================
-- 343_hr_small_defects_tests.sql — tâche 2.4 (C5, C6)
--
--   T01  rh-002 : `CDI` s'enregistre `cdi` ; un type hors liste est refusé
--   T02  rh-001 : une date d'embauche en 2099 ou en 1900 est refusée, en français
--   T03  rh-003 : changer le salaire de la fiche change le salaire PAYÉ
--        (base_salary suit, le taux horaire aussi)
--   T04  C5 : les droits à congés sont au prorata des mois de présence
--        (embauche au 01/07 → 12,50 j ; année entière → 25 j ; avant
--        l'embauche → 0 j)
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '343', false);
DELETE FROM _audit_results WHERE file = '343';

-- ── T01 ──────────────────────────────────────────────────────
DO $$
DECLARE
  t uuid := _mk_tenant('P2C6T01', false);
  e uuid; v text; v_refus boolean := false;
BEGIN
  PERFORM _as_user();
  INSERT INTO employees (tenant_id, name, email, status, salary, contract_type)
  VALUES (t, 'Salarie C6T01', 'c6t01@audit.test', 'active', 2000, '  CDI ') RETURNING id INTO e;
  SELECT contract_type INTO v FROM employees WHERE id = e;
  BEGIN
    INSERT INTO employees (tenant_id, name, email, status, salary, contract_type)
    VALUES (t, 'Salarie C6T01b', 'c6t01b@audit.test', 'active', 2000, 'contrat bidon');
  EXCEPTION WHEN check_violation THEN v_refus := true;
  END;
  PERFORM _rec('T01', 'type de contrat : « CDI » s''enregistre « cdi », et un type hors liste est refusé',
    v = 'cdi' AND v_refus, format('enregistré=%s refus du type inconnu=%s', v, v_refus));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T01', 'T01 — le scénario n''a pas pu s''exécuter', false, SQLERRM);
END $$;

-- ── T02 ──────────────────────────────────────────────────────
DO $$
DECLARE
  t uuid := _mk_tenant('P2C6T02', false);
  v_futur text := ''; v_passe text := '';
BEGIN
  PERFORM _as_user();
  BEGIN
    INSERT INTO employees (tenant_id, name, email, status, salary, hire_date)
    VALUES (t, 'Salarie C6T02', 'c6t02@audit.test', 'active', 2000, DATE '2099-01-01');
  EXCEPTION WHEN check_violation THEN v_futur := SQLERRM;
  END;
  BEGIN
    INSERT INTO employees (tenant_id, name, email, status, salary, hire_date)
    VALUES (t, 'Salarie C6T02b', 'c6t02b@audit.test', 'active', 2000, DATE '1900-01-01');
  EXCEPTION WHEN check_violation THEN v_passe := SQLERRM;
  END;
  PERFORM _rec('T02', 'date d''embauche : 2099 et 1900 sont refusées, avec un message rédigé',
    v_futur LIKE 'Date d''embauche invalide%' AND v_passe LIKE 'Date d''embauche invalide%',
    format('2099 : %s | 1900 : %s', left(v_futur, 50), left(v_passe, 50)));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T02', 'T02 — le scénario n''a pas pu s''exécuter', false, SQLERRM);
END $$;

-- ── T03 ──────────────────────────────────────────────────────
DO $$
DECLARE
  t uuid := _mk_tenant('P2C6T03', false);
  e uuid; b numeric; taux numeric;
BEGIN
  PERFORM _as_user();
  INSERT INTO employees (tenant_id, name, email, status, salary, base_salary, weekly_hours)
  VALUES (t, 'Salarie C6T03', 'c6t03@audit.test', 'active', 2000, 2000, 35) RETURNING id INTO e;
  -- l'écran ne modifie QUE `salary`
  UPDATE employees SET salary = 3000 WHERE id = e AND tenant_id = t;
  SELECT base_salary INTO b FROM employees WHERE id = e;
  EXECUTE 'RESET ROLE';
  taux := payroll_hourly_rate(t, e);
  PERFORM _rec('T03', 'changer le salaire de la fiche change le salaire payé : base_salary suit (3 000 €), le taux horaire aussi (19,78 €)',
    b = 3000 AND taux BETWEEN 19.77 AND 19.79, format('base_salary=%s taux horaire=%s', b, taux));
EXCEPTION WHEN OTHERS THEN
  EXECUTE 'RESET ROLE';
  PERFORM _rec('T03', 'T03 — le scénario n''a pas pu s''exécuter', false, SQLERRM);
END $$;

-- ── T04 ──────────────────────────────────────────────────────
DO $$
DECLARE
  t uuid := _mk_tenant('P2C6T04', false);
  e1 uuid; e2 uuid; a_mi numeric; a_plein numeric; a_avant numeric; m_mi int;
BEGIN
  PERFORM _as_user();
  INSERT INTO employees (tenant_id, name, email, status, salary, hire_date)
  VALUES (t, 'Salarie C6T04', 'c6t04@audit.test', 'active', 2000, DATE '2025-07-01') RETURNING id INTO e1;
  INSERT INTO employees (tenant_id, name, email, status, salary, hire_date)
  VALUES (t, 'Salarie C6T04b', 'c6t04b@audit.test', 'active', 2000, DATE '2020-03-02') RETURNING id INTO e2;
  a_mi    := (calculate_leave_acquisition(e1, 2025) ->> 'acquired')::numeric;
  m_mi    := (calculate_leave_acquisition(e1, 2025) ->> 'months')::int;
  a_plein := (calculate_leave_acquisition(e2, 2025) ->> 'acquired')::numeric;
  a_avant := (calculate_leave_acquisition(e1, 2024) ->> 'acquired')::numeric;
  PERFORM _rec('T04', 'droits à congés au prorata : embauche au 01/07/2025 → 6 mois, 12,50 j ; année entière → 25 j ; année d''avant l''embauche → 0 j',
    a_mi = 12.50 AND m_mi = 6 AND a_plein = 25 AND a_avant = 0,
    format('mi-année=%s j (%s mois) | année entière=%s j | avant l''embauche=%s j', a_mi, m_mi, a_plein, a_avant));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T04', 'T04 — le scénario n''a pas pu s''exécuter', false, SQLERRM);
END $$;

SELECT _audit_assert('343');
