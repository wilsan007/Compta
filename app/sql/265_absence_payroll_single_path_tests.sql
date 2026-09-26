-- ============================================================
-- 265_absence_payroll_single_path_tests.sql — W9 (TRV-11, TRV-12, TRV-13)
--
-- Mesuré AVANT la 265, sur base neuve (230 migrations) :
--   * DEUX déclencheurs écrivaient une retenue pour la même journée —
--     `deduct_unpaid_leave` sur `leave_requests` et `deduct_unpaid_absence` sur
--     `timesheets` (`SELECT tgname FROM pg_trigger WHERE tgrelid IN
--     ('leave_requests'::regclass, 'timesheets'::regclass)` les rendait tous
--     les deux) ;
--   * le second écrivait `unpaid_absence_deduction`, un type que
--     `calculate_payslip` ne lit pas : il n'atteignait aucun bulletin ;
--   * rien ne savait défaire une retenue déjà intégrée à un bulletin validé ;
--   * une absence rétroactive sur une période de paie close écrivait son
--     élément sur une période qui ne serait plus jamais recalculée.
--
-- Ce que ce fichier prouve APRÈS la 265 : la paie d'absence vient du REGISTRE,
-- une fois par journée, et le montant se voit dans le bulletin.
-- ============================================================

\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '265', false);
DELETE FROM _audit_results WHERE file = '265';

-- ── C01 — TRV-11 : une journée d'absence donne UNE retenue, du bon type ────
DO $$
DECLARE
  t uuid; e uuid; v_n int; v_types text[]; v_sources text[]; v_jours int; v_taux numeric;
BEGIN
  t := _mk_tenant('A265T01', false);
  INSERT INTO employees (tenant_id, name, email, status, salary, base_salary, weekly_hours)
  VALUES (t, 'Amina C01', 'a265c01@audit.test', 'active', 2600, 2600, 35) RETURNING id INTO e;
  INSERT INTO payroll_legal_parameters (tenant_id, country_code, code, value, valid_from)
  VALUES (t, 'FR', 'DIVISEUR_JOURS_MENSUEL', 26, CURRENT_DATE - 1);

  INSERT INTO leave_requests (tenant_id, employee_id, leave_type, start_date, end_date, days, status, reason)
  VALUES (t, e, 'unpaid', '2026-05-04', '2026-05-05', 2, 'approved', 'raison personnelle');

  SELECT count(*), array_agg(DISTINCT element_type), array_agg(DISTINCT source)
    INTO v_n, v_types, v_sources
    FROM payroll_variable_elements WHERE tenant_id = t AND employee_id = e;
  SELECT count(*) INTO v_jours FROM employee_absence_days WHERE tenant_id = t AND employee_id = e;
  SELECT max(unit_price) INTO v_taux FROM payroll_variable_elements
   WHERE tenant_id = t AND employee_id = e AND element_type = 'unpaid_leave_deduction';

  PERFORM _rec('C01', 'TRV-11 : deux jours de congé sans solde donnent deux retenues (une par jour), du type que le moteur retranche, au taux journalier de la société',
    v_n = 2 AND v_jours = 2 AND v_types = ARRAY['unpaid_leave_deduction']::text[]
      AND v_sources = ARRAY['absence_day']::text[] AND v_taux = round(2600::numeric / 26, 2),
    format('jours au registre=%s, éléments=%s, types=%s, sources=%s, taux unitaire=%s (attendu %s)',
           v_jours, v_n, v_types, v_sources, v_taux, round(2600::numeric / 26, 2)));
END $$;

-- ── C02 — TRV-11 : deux sources pour la MÊME journée ne retiennent qu'une fois
DO $$
DECLARE
  t uuid; e uuid; v_n int; v_jours int; v_kind text; v_el text[];
BEGIN
  t := _mk_tenant('A265T02', false);
  INSERT INTO employees (tenant_id, name, email, status, salary, base_salary)
  VALUES (t, 'Bilal C02', 'a265c02@audit.test', 'active', 2600, 2600) RETURNING id INTO e;

  -- Le MÊME jour, déclaré deux fois : un congé sans solde ET un pointage
  -- d'absence non payé. Le registre n'en garde qu'un ; la paie aussi.
  INSERT INTO leave_requests (tenant_id, employee_id, leave_type, start_date, end_date, days, status, reason)
  VALUES (t, e, 'unpaid', '2026-05-11', '2026-05-11', 1, 'approved', 'raison');
  INSERT INTO timesheets (tenant_id, employee_id, date, hours, status, absence_type, absence_reason)
  VALUES (t, e, '2026-05-11', 0, 'approved', 'unpaid', 'raison');

  SELECT count(*) INTO v_jours FROM employee_absence_days WHERE tenant_id = t AND employee_id = e;
  SELECT absence_kind INTO v_kind FROM employee_absence_days
   WHERE tenant_id = t AND employee_id = e AND day = '2026-05-11';
  SELECT count(*), array_agg(DISTINCT element_type) INTO v_n, v_el
    FROM payroll_variable_elements WHERE tenant_id = t AND employee_id = e;

  PERFORM _rec('C02', 'TRV-11 : un jour déclaré par deux sources ne retient qu''UNE fois — c''est le piège que W9 devait désamorcer',
    v_jours = 1 AND v_n = 1 AND v_el = ARRAY['unpaid_leave_deduction']::text[],
    format('jours au registre=%s (1 attendu, type=%s), retenues=%s (1 attendue, types=%s)',
           v_jours, v_kind, v_n, v_el));
END $$;

-- ── C03 — TRV-11 : rejouer le recalcul ne double pas (day_uid stable) ──────
DO $$
DECLARE
  t uuid; e uuid; v_uid_avant uuid; v_uid_apres uuid; v_n int; v_somme numeric;
BEGIN
  t := _mk_tenant('A265T03', false);
  INSERT INTO employees (tenant_id, name, email, status, salary, base_salary)
  VALUES (t, 'Chams C03', 'a265c03@audit.test', 'active', 2600, 2600) RETURNING id INTO e;
  INSERT INTO leave_requests (tenant_id, employee_id, leave_type, start_date, end_date, days, status, reason)
  VALUES (t, e, 'unpaid', '2026-05-12', '2026-05-13', 2, 'approved', 'raison');
  INSERT INTO payroll_legal_parameters (tenant_id, country_code, code, value, valid_from)
  VALUES (t, 'FR', 'DIVISEUR_JOURS_MENSUEL', 26, CURRENT_DATE - 1);

  SELECT day_uid INTO v_uid_avant FROM employee_absence_days
   WHERE tenant_id = t AND employee_id = e AND day = '2026-05-12';

  -- Trois recalculs complets de la plage.
  PERFORM rebuild_absence_days(t, e, '2026-05-01', '2026-05-31');
  PERFORM rebuild_absence_days(t, e, '2026-05-01', '2026-05-31');
  PERFORM sync_absence_to_payroll(t, e, '2026-05-01', '2026-05-31');

  SELECT day_uid INTO v_uid_apres FROM employee_absence_days
   WHERE tenant_id = t AND employee_id = e AND day = '2026-05-12';
  SELECT count(*), COALESCE(sum(amount), 0) INTO v_n, v_somme
    FROM payroll_variable_elements WHERE tenant_id = t AND employee_id = e
     AND element_type = 'unpaid_leave_deduction';

  PERFORM _rec('C03', 'TRV-11 : l''identifiant de la journée est stable et trois recalculs ne créent pas un second élément',
    v_n = 2 AND v_uid_avant = v_uid_apres AND v_somme = round(2 * 2600::numeric / 26, 2),
    format('day_uid avant=%s après=%s ; éléments=%s (2 attendus) pour un total de %s',
           v_uid_avant, v_uid_apres, v_n, v_somme));
END $$;

-- ── C04 — un congé PAYÉ ne retient rien (aucun élément) ────────────────────
DO $$
DECLARE
  t uuid; e uuid; v_n int; v_paie boolean;
BEGIN
  t := _mk_tenant('A265T04', false);
  INSERT INTO employees (tenant_id, name, email, status, salary, base_salary)
  VALUES (t, 'Dalia C04', 'a265c04@audit.test', 'active', 2600, 2600) RETURNING id INTO e;
  INSERT INTO leave_requests (tenant_id, employee_id, leave_type, start_date, end_date, days, status)
  VALUES (t, e, 'annual', '2026-05-18', '2026-05-20', 3, 'approved');

  SELECT count(*) INTO v_n FROM payroll_variable_elements
   WHERE tenant_id = t AND employee_id = e AND element_type = 'unpaid_leave_deduction';
  SELECT bool_and(paid) INTO v_paie FROM employee_absence_days
   WHERE tenant_id = t AND employee_id = e;

  PERFORM _rec('C04', 'un congé payé marque les journées « payées » au registre et ne produit AUCUNE retenue',
    v_n = 0 AND v_paie = true,
    format('retenues=%s (0 attendue), journées payées=%s', v_n, v_paie));
END $$;

-- ── C05 — TRV-12 : annuler l'absence retire la retenue non intégrée ────────
DO $$
DECLARE
  t uuid; e uuid; lr uuid; v_avant int; v_apres int;
BEGIN
  t := _mk_tenant('A265T05', false);
  INSERT INTO employees (tenant_id, name, email, status, salary, base_salary)
  VALUES (t, 'Emil C05', 'a265c05@audit.test', 'active', 2600, 2600) RETURNING id INTO e;
  INSERT INTO leave_requests (tenant_id, employee_id, leave_type, start_date, end_date, days, status, reason)
  VALUES (t, e, 'unpaid', '2026-05-20', '2026-05-21', 2, 'approved', 'raison') RETURNING id INTO lr;

  SELECT count(*) INTO v_avant FROM payroll_variable_elements
   WHERE tenant_id = t AND employee_id = e AND element_type = 'unpaid_leave_deduction';

  UPDATE leave_requests SET status = 'cancelled' WHERE id = lr;

  SELECT count(*) INTO v_apres FROM payroll_variable_elements
   WHERE tenant_id = t AND employee_id = e AND element_type = 'unpaid_leave_deduction';

  PERFORM _rec('C05', 'TRV-12 : annuler une absence retire la retenue non encore intégrée (2 éléments → 0)',
    v_avant = 2 AND v_apres = 0,
    format('éléments avant=%s, après annulation=%s', v_avant, v_apres));
END $$;


-- ── C06 — TRV-12 : une retenue DÉJÀ INTÉGRÉE n'est pas effacée, elle est
--         contre-passée par un élément positif (le schéma interdit < 0) ─────
DO $$
DECLARE
  t uuid; e uuid; lr uuid; v_restant int; v_inverse int; v_montant numeric; v_type text;
BEGIN
  t := _mk_tenant('A265T06', false);
  INSERT INTO employees (tenant_id, name, email, status, salary, base_salary)
  VALUES (t, 'Farid C06', 'a265c06@audit.test', 'active', 2600, 2600) RETURNING id INTO e;
  INSERT INTO payroll_legal_parameters (tenant_id, country_code, code, value, valid_from)
  VALUES (t, 'FR', 'DIVISEUR_JOURS_MENSUEL', 26, CURRENT_DATE - 1);
  INSERT INTO leave_requests (tenant_id, employee_id, leave_type, start_date, end_date, days, status, reason)
  VALUES (t, e, 'unpaid', '2026-05-25', '2026-05-25', 1, 'approved', 'raison') RETURNING id INTO lr;

  -- La retenue entre dans un bulletin validé : elle devient une pièce.
  UPDATE payroll_variable_elements SET integrated = true
   WHERE tenant_id = t AND employee_id = e AND source = 'absence_day';

  UPDATE leave_requests SET status = 'cancelled' WHERE id = lr;

  SELECT count(*) INTO v_restant FROM payroll_variable_elements
   WHERE tenant_id = t AND employee_id = e AND source = 'absence_day';
  SELECT count(*), max(amount), max(element_type) INTO v_inverse, v_montant, v_type
    FROM payroll_variable_elements
   WHERE tenant_id = t AND employee_id = e AND source = 'absence_day_reversal';

  PERFORM _rec('C06', 'TRV-12 : une retenue déjà intégrée à un bulletin validé n''est jamais effacée ; un élément inverse POSITIF (pay_recall) la reprend',
    v_restant = 1 AND v_inverse = 1 AND v_type = 'pay_recall'
      AND v_montant = round(2600::numeric / 26, 2),
    format('retenue conservée=%s (1 attendue), éléments inverses=%s (type=%s, montant=%s)',
           v_restant, v_inverse, v_type, v_montant));
END $$;

-- ── C07 — TRV-13 : la période de paie close → régularisation sur la période
--         ouverte courante, jamais perdue, jamais refusée ───────────────────
DO $$
DECLARE
  t uuid; e uuid; v_periodes text[]; v_desc text; v_refus boolean := false;
BEGIN
  t := _mk_tenant('A265T07', false);
  INSERT INTO employees (tenant_id, name, email, status, salary, base_salary)
  VALUES (t, 'Ghada C07', 'a265c07@audit.test', 'active', 2600, 2600) RETURNING id INTO e;

  -- Le classeur de paie de mai 2026 est CLOS.
  INSERT INTO pay_runs (tenant_id, number, period_start, period_end, pay_date, status,
                        gross_total, tax_total, net_total, employee_count)
  VALUES (t, 'PR-C07', '2026-05-01', '2026-05-31', '2026-05-31', 'closed', 0, 0, 0, 1);

  BEGIN
    INSERT INTO leave_requests (tenant_id, employee_id, leave_type, start_date, end_date, days, status, reason)
    VALUES (t, e, 'unpaid', '2026-05-26', '2026-05-26', 1, 'approved', 'raison');
  EXCEPTION WHEN OTHERS THEN v_refus := true; END;

  SELECT array_agg(DISTINCT period), max(description) INTO v_periodes, v_desc
    FROM payroll_variable_elements WHERE tenant_id = t AND employee_id = e;

  PERFORM _rec('C07', 'TRV-13 : une absence sur une période de paie close n''est pas refusée — sa retenue est RÉGULARISÉE sur la période ouverte courante',
    NOT v_refus AND v_periodes = ARRAY[to_char(CURRENT_DATE, 'YYYY-MM')]::text[]
      AND position('Régularisation' IN COALESCE(v_desc, '')) > 0,
    format('déclaration refusée=%s, période(s)=%s (attendu %s), libellé=« %s »',
           v_refus, v_periodes, to_char(CURRENT_DATE, 'YYYY-MM'), COALESCE(v_desc, '')));
END $$;


-- ── C08 — TRV-11 : les deux anciens déclencheurs ne sont plus branchés ─────
DO $$
DECLARE
  v_deduit_leave int;
  v_deduit_absence int;
  v_registre int;
BEGIN
  SELECT count(*) INTO v_deduit_leave FROM pg_trigger
   WHERE tgrelid = 'leave_requests'::regclass AND tgname = 'deduct_unpaid_leave';
  SELECT count(*) INTO v_deduit_absence FROM pg_trigger
   WHERE tgrelid = 'timesheets'::regclass AND tgname = 'deduct_unpaid_absence';
  SELECT count(*) INTO v_registre FROM pg_trigger
   WHERE tgrelid = 'employee_absence_days'::regclass
     AND tgname IN ('absence_day_payroll', 'absence_day_payroll_delete');

  PERFORM _rec('C08', 'TRV-11 : les deux anciens chemins de retenue sont débranchés ; le registre est le seul producteur',
    v_deduit_leave = 0 AND v_deduit_absence = 0 AND v_registre = 2,
    format('deduct_unpaid_leave=%s, deduct_unpaid_absence=%s (0 attendus), déclencheurs du registre=%s (2 attendus)',
           v_deduit_leave, v_deduit_absence, v_registre));
END $$;

-- ── C09 — l'absence se VOIT dans le bulletin : le brut baisse d'un jour ────
DO $$
DECLARE
  t uuid; e uuid; r uuid; v_brut_plein numeric; v_brut_absence numeric;
  v_attendu numeric; v_rattaches int;
BEGIN
  t := _mk_tenant('A265T09', false);
  INSERT INTO employees (tenant_id, name, email, status, salary, base_salary, hire_date, employee_number)
  VALUES (t, 'Hana C09', 'a265c09@audit.test', 'active', 2600, 2600, '2020-01-01', 'C09')
  RETURNING id INTO e;
  INSERT INTO payroll_legal_parameters (tenant_id, country_code, code, value, valid_from)
  VALUES (t, 'FR', 'DIVISEUR_JOURS_MENSUEL', 26, CURRENT_DATE - 1);

  -- a) le classeur AVANT l'absence : le bulletin du salaire plein
  INSERT INTO pay_runs (tenant_id, number, period_start, period_end, pay_date, status,
                        gross_total, tax_total, net_total, employee_count)
  VALUES (t, 'PR-C09', '2026-07-01', '2026-07-31', '2026-07-31', 'draft', 0, 0, 0, 1)
  RETURNING id INTO r;
  SELECT (calculate_payslip(e, '2026-07', r) ->> 'total_gross')::numeric INTO v_brut_plein;
  DELETE FROM pay_slips WHERE tenant_id = t AND employee_id = e;

  -- b) une journée de congé sans solde, sur ce même classeur
  INSERT INTO leave_requests (tenant_id, employee_id, leave_type, start_date, end_date, days, status, reason)
  VALUES (t, e, 'unpaid', '2026-07-06', '2026-07-06', 1, 'approved', 'raison');
  SELECT count(*) INTO v_rattaches FROM payroll_variable_elements
   WHERE tenant_id = t AND employee_id = e AND source = 'absence_day' AND pay_run_id = r;

  SELECT (calculate_payslip(e, '2026-07', r) ->> 'total_gross')::numeric INTO v_brut_absence;
  v_attendu := round(2600::numeric - 2600::numeric / 26, 2);

  PERFORM _rec('C09', 'le montant de l''absence se VOIT dans le bulletin : le brut passe du salaire plein à salaire − 1 jour (un jour retenu une seule fois)',
    v_brut_plein = 2600 AND v_rattaches = 1 AND abs(v_brut_absence - v_attendu) < 0.01,
    format('brut sans absence=%s, élément rattaché au classeur=%s, brut avec 1 jour d''absence=%s (attendu %s)',
           v_brut_plein, v_rattaches, v_brut_absence, v_attendu));
END $$;

-- ── C10 — un élément posé AVANT le classeur n'est pas perdu : il est rattaché
DO $$
DECLARE
  t uuid; e uuid; r uuid; v_avant int; v_apres int;
BEGIN
  t := _mk_tenant('A265T10', false);
  INSERT INTO employees (tenant_id, name, email, status, salary, base_salary)
  VALUES (t, 'Idris C10', 'a265c10@audit.test', 'active', 2600, 2600) RETURNING id INTO e;

  -- L'absence est déclarée AVANT que le classeur du mois existe (le cas normal :
  -- on déclare un congé, la paie du mois vient après).
  INSERT INTO leave_requests (tenant_id, employee_id, leave_type, start_date, end_date, days, status, reason)
  VALUES (t, e, 'unpaid', '2026-08-03', '2026-08-03', 1, 'approved', 'raison');
  SELECT count(*) INTO v_avant FROM payroll_variable_elements
   WHERE tenant_id = t AND source = 'absence_day' AND pay_run_id IS NULL;

  -- Le classeur d'août est créé : l'élément doit être rattaché, sans double.
  INSERT INTO pay_runs (tenant_id, number, period_start, period_end, pay_date, status,
                        gross_total, tax_total, net_total, employee_count)
  VALUES (t, 'PR-C10', '2026-08-01', '2026-08-31', '2026-08-31', 'draft', 0, 0, 0, 1)
  RETURNING id INTO r;

  SELECT count(*) INTO v_apres FROM payroll_variable_elements
   WHERE tenant_id = t AND source = 'absence_day' AND pay_run_id = r;

  PERFORM _rec('C10', 'TRV-11 : un élément d''absence posé avant le classeur de paie y est rattaché à sa création — sans ce rattachement, aucun bulletin ne le lit (mesuré : calculate_payslip filtre par pay_run_id)',
    v_avant = 1 AND v_apres = 1,
    format('éléments en attente avant=%s, rattachés après création du classeur=%s', v_avant, v_apres));
END $$;

-- ── Le registre des verdicts ────────────────────────────────────────────────
SELECT _audit_assert('265');

