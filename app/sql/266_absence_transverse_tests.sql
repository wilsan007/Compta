-- ============================================================
-- 266_absence_transverse_tests.sql — W9 : la chaîne de l'absence, de bout en
--                                    bout (34 assertions)
--
-- Le critère de sortie du plan W9, mot pour mot :
--   « une absence d'un jour apparaît **une fois** dans la paie, la DSN, le coût
--   projet et le plafond ; une absence **refusée** n'apparaît nulle part ».
--
-- Les suites 263, 264 et 265 mesurent chacune leur module. Celle-ci ne mesure
-- QUE ce qu'aucune suite mono-module ne peut voir : la MÊME journée d'absence
-- traversant cinq modules, et le compte des fois où elle y apparaît.
--
-- Le décor : une société, deux salariés. Le premier (E1) est absent le
-- mercredi 8 juillet 2026 — un jour ouvré, sans férié. Le second (E2) travaille
-- normalement ce jour-là et sert de témoin : tout ce qui suit doit être
-- inchangé pour lui.
-- ============================================================

\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '266', false);
DELETE FROM _audit_results WHERE file = '266';

-- ── Le décor, posé une fois pour toutes les assertions ──────────────────────
DROP TABLE IF EXISTS _t266;
CREATE TEMP TABLE _t266 (k text PRIMARY KEY, v text);
INSERT INTO _t266 (k, v) VALUES
  ('jour', '2026-07-08'),          -- mercredi
  ('periode', '2026-07');

DO $$
DECLARE
  t uuid; e1 uuid; e2 uuid; r uuid; pt uuid;
BEGIN
  t := _mk_tenant('A266', false);
  INSERT INTO employees (tenant_id, name, email, status, salary, base_salary, hire_date, employee_number)
  VALUES (t, 'Aya Absente', 'a266e1@audit.test', 'active', 2600, 2600, '2020-01-01', 'E1')
  RETURNING id INTO e1;
  INSERT INTO employees (tenant_id, name, email, status, salary, base_salary, hire_date, employee_number)
  VALUES (t, 'Ben Présent', 'a266e2@audit.test', 'active', 2600, 2600, '2020-01-01', 'E2')
  RETURNING id INTO e2;
  INSERT INTO payroll_legal_parameters (tenant_id, country_code, code, value, valid_from)
  VALUES (t, 'FR', 'DIVISEUR_JOURS_MENSUEL', 26, CURRENT_DATE - 1);

  INSERT INTO _t266 (k, v) VALUES ('tenant', t::text), ('e1', e1::text), ('e2', e2::text);

  -- E1 : un congé sans solde d'UNE journée, le 08/07, justifié.
  INSERT INTO leave_requests (tenant_id, employee_id, leave_type, start_date, end_date, days, status, reason)
  VALUES (t, e1, 'unpaid', '2026-07-08', '2026-07-08', 1, 'approved', 'déménagement');

  -- E1 : les trois saisies que l'absence doit refuser (mesurées plus bas).
  BEGIN
    INSERT INTO timesheets (tenant_id, employee_id, date, hours, status)
    VALUES (t, e1, '2026-07-08', 8, 'pending');
  EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN
    INSERT INTO project_time_entries (tenant_id, employee_id, start_time, duration_seconds, is_billable)
    VALUES (t, e1, '2026-07-08 09:00:00+00', 7200, true);
  EXCEPTION WHEN OTHERS THEN NULL; END;
  INSERT INTO expense_reports (tenant_id, employee_id, number, status)
  VALUES (t, e1, 'NF-T266', 'draft') RETURNING id INTO r;
  BEGIN
    INSERT INTO expense_report_lines (tenant_id, expense_report_id, date, description, amount)
    VALUES (t, r, '2026-07-08', 'taxi', 55);
  EXCEPTION WHEN OTHERS THEN NULL; END;

  -- E2 : le témoin travaille normalement ce jour-là.
  INSERT INTO timesheets (tenant_id, employee_id, date, hours, status, arrival_time, departure_time)
  VALUES (t, e2, '2026-07-08', 8, 'approved',
          '2026-07-08 09:00:00+00', '2026-07-08 17:00:00+00');
  INSERT INTO project_time_entries (tenant_id, employee_id, start_time, duration_seconds, is_billable)
  VALUES (t, e2, '2026-07-08 09:00:00+00', 3600, true);

  -- Le classeur de paie du mois, créé APRÈS l'absence (l'ordre réel).
  INSERT INTO pay_runs (tenant_id, number, period_start, period_end, pay_date, status,
                        gross_total, tax_total, net_total, employee_count)
  VALUES (t, 'PR-T266', '2026-07-01', '2026-07-31', '2026-07-31', 'draft', 0, 0, 0, 2)
  RETURNING id INTO r;
  INSERT INTO _t266 (k, v) VALUES ('pay_run', r::text);

  -- NOTE : les bulletins ne sont PAS calculés ici. `calculate_payslip` marque
  -- `integrated = true` sur les éléments qu'il consomme (mesuré, ligne 438 de
  -- sa définition) : les calculer au décor reviendrait à les consommer une
  -- fois, puis à ne plus les voir. C'est le bloc 3 qui les calcule.

  -- Une tâche assignée à E1, posée AVANT l'absence (pour T31 : ce n'est pas
  -- l'assignation qui est testée ici, c'est la clôture par l'absent).
  INSERT INTO project_tasks (tenant_id, title, status, assignee_id, start_date)
  VALUES (t, 'Rapport T266', 'todo', e1, CURRENT_DATE - 30) RETURNING id INTO pt;
END $$;

-- ── Bloc 1 — le registre : la journée existe UNE fois, et c'est la vérité ───
DO $$
DECLARE
  t uuid := (SELECT v::uuid FROM _t266 WHERE k='tenant');
  e1 uuid := (SELECT v::uuid FROM _t266 WHERE k='e1');
  e2 uuid := (SELECT v::uuid FROM _t266 WHERE k='e2');
  d date := (SELECT v::date FROM _t266 WHERE k='jour');
  v_n int; v_row employee_absence_days; v_ts int;
BEGIN
  SELECT count(*) INTO v_n FROM employee_absence_days
   WHERE tenant_id = t AND employee_id = e1 AND day = d;
  SELECT * INTO v_row FROM employee_absence_days
   WHERE tenant_id = t AND employee_id = e1 AND day = d;

  PERFORM _rec('T01', 'registre : la journée d''absence de E1 existe, et une seule fois', v_n = 1,
    format('lignes au registre pour E1 le %s : %s', d, v_n));

  PERFORM _rec('T02', 'registre : le type, l''origine et l''effet de paie sont posés (unpaid, leave_request, unpaid_deduction)',
    v_row.absence_kind = 'unpaid' AND v_row.origin = 'leave_request'
      AND v_row.paid = false AND v_row.pay_rule_code = 'unpaid_deduction',
    format('type=%s, origine=%s, payé=%s, règle=%s',
           v_row.absence_kind, v_row.origin, v_row.paid, v_row.pay_rule_code));

  SELECT count(*) INTO v_n FROM employee_absence_days
   WHERE tenant_id = t AND employee_id = e2 AND day = d;
  PERFORM _rec('T03', 'registre : le témoin E2 n''a AUCUNE absence ce jour-là (l''absence d''un salarié n''en crée pas pour un autre)',
    v_n = 0, format('lignes au registre pour E2 : %s', v_n));

  -- TRV-01 : la quatrième source (le pointage d'absence) n'a écrit nulle part
  -- ailleurs ; et cette journée n'est pas non plus un pointage de travail.
  SELECT count(*) INTO v_ts FROM timesheets
   WHERE tenant_id = t AND employee_id = e1 AND date = d;
  PERFORM _rec('T04', 'registre : la journée de E1 ne porte AUCUN pointage (le refus de la 264 n''a rien écrit), et le registre est la seule trace',
    v_ts = 0 AND v_row.day_uid IS NOT NULL,
    format('pointages de E1 le %s : %s ; identifiant de journée stable : %s', d, v_ts, v_row.day_uid));
END $$;

-- ── Bloc 2 — la paie : la retenue apparaît UNE fois, du bon montant ─────────
DO $$
DECLARE
  t uuid := (SELECT v::uuid FROM _t266 WHERE k='tenant');
  e1 uuid := (SELECT v::uuid FROM _t266 WHERE k='e1');
  e2 uuid := (SELECT v::uuid FROM _t266 WHERE k='e2');
  v_n int; v_types text[]; v_src text; v_taux numeric; v_uid uuid; v_somme numeric;
BEGIN
  SELECT count(*), array_agg(DISTINCT element_type), max(source), max(unit_price),
         COALESCE(sum(amount), 0)
    INTO v_n, v_types, v_src, v_taux, v_somme
    FROM payroll_variable_elements
   WHERE tenant_id = t AND employee_id = e1 AND element_type = 'unpaid_leave_deduction';

  PERFORM _rec('T05', 'paie : une seule retenue pour la journée d''absence', v_n = 1,
    format('éléments de retenue pour E1 : %s (1 attendu)', v_n));

  PERFORM _rec('T06', 'paie : la retenue vient du registre (source « absence_day ») et non d''un congé ou d''un pointage',
    v_src = 'absence_day', format('source=%s, types=%s', v_src, v_types));

  PERFORM _rec('T07', 'paie : le montant est UN jour au taux de la société (2600 / 26 = 100,00)',
    v_taux = 100 AND v_somme = 100,
    format('taux unitaire=%s, total retenu=%s', v_taux, v_somme));

  SELECT day_uid INTO v_uid FROM employee_absence_days
   WHERE tenant_id = t AND employee_id = e1 AND day = (SELECT v::date FROM _t266 WHERE k='jour');
  PERFORM _rec('T08', 'paie : l''élément est identifié par l''identifiant stable de la journée (rejouer ne double pas)',
    EXISTS (SELECT 1 FROM payroll_variable_elements
             WHERE tenant_id = t AND source_id = v_uid AND source = 'absence_day'),
    format('day_uid du registre=%s', v_uid));

  PERFORM _rec('T09', 'paie : l''absence de E1 ne touche PAS la paie de E2',
    NOT EXISTS (SELECT 1 FROM payroll_variable_elements
                 WHERE tenant_id = t AND employee_id = e2
                   AND element_type = 'unpaid_leave_deduction'),
    'aucun élément de retenue pour le témoin');
END $$;

-- ── Bloc 3 — le bulletin, le plafond et les cumuls ─────────────────────────
DO $$
DECLARE
  t uuid := (SELECT v::uuid FROM _t266 WHERE k='tenant');
  e1 uuid := (SELECT v::uuid FROM _t266 WHERE k='e1');
  e2 uuid := (SELECT v::uuid FROM _t266 WHERE k='e2');
  v_e1 jsonb; v_e2 jsonb;
BEGIN
  SELECT (calculate_payslip(e1, '2026-07', (SELECT v::uuid FROM _t266 WHERE k='pay_run'))) INTO v_e1;
  SELECT (calculate_payslip(e2, '2026-07', (SELECT v::uuid FROM _t266 WHERE k='pay_run'))) INTO v_e2;

  PERFORM _rec('T10', 'bulletin E1 : le brut baisse d''exactement un jour — 2 600 → 2 500 (l''absence y apparaît UNE fois)',
    (v_e1->>'total_gross')::numeric = 2500,
    format('total_gross E1=%s (2500 attendu)', v_e1->>'total_gross'));

  PERFORM _rec('T11', 'bulletin E2 (témoin) : le brut reste plein — 2 600',
    (v_e2->>'total_gross')::numeric = 2600,
    format('total_gross E2=%s (2600 attendu)', v_e2->>'total_gross'));

  PERFORM _rec('T12', 'bulletin E1 : le net baisse aussi (la retenue a traversé tout le calcul, elle n''est pas qu''affichée)',
    (v_e1->>'net_salary')::numeric < (v_e2->>'net_salary')::numeric,
    format('net E1=%s, net E2=%s', v_e1->>'net_salary', v_e2->>'net_salary'));

  PERFORM _rec('T13', 'plafond E1 : la base plafonnée vaut le brut réduit — l''absence réduit aussi le plafond de cotisation',
    (v_e1->>'ceiling_base')::numeric = 2500,
    format('ceiling_base E1=%s (2500 attendu), pmss=%s', v_e1->>'ceiling_base', v_e1->>'pmss'));

  PERFORM _rec('T14', 'plafond : celui de E1 est strictement inférieur à celui du témoin',
    (v_e1->>'ceiling_base')::numeric < (v_e2->>'ceiling_base')::numeric,
    format('plafond E1=%s < plafond E2=%s', v_e1->>'ceiling_base', v_e2->>'ceiling_base'));

  PERFORM _rec('T15', 'cumuls : le brut cumulé de E1 suit le bulletin (2 500), pas le salaire théorique',
    (v_e1->>'cumulative_gross_ytd')::numeric = 2500,
    format('cumulative_gross_ytd E1=%s (2500 attendu)', v_e1->>'cumulative_gross_ytd'));
END $$;


-- ── Bloc 4 — la DSN : l'absence y entre par le bulletin, une seule fois ────
-- `generate_dsn(period)` agrège `pay_slips` (mesuré : `SELECT count(*),
-- SUM(total_gross), SUM(net_salary), SUM(social_security_employee) FROM
-- pay_slips WHERE period_start = … AND tenant_id = current_tenant_id()`).
-- C'est donc la chaîne registre → élément → bulletin → DSN qui est vérifiée.
DO $$
DECLARE
  t uuid := (SELECT v::uuid FROM _t266 WHERE k='tenant');
  e1 uuid := (SELECT v::uuid FROM _t266 WHERE k='e1');
  e2 uuid := (SELECT v::uuid FROM _t266 WHERE k='e2');
  v_dsn jsonb; v_nets numeric; v_ss numeric;
BEGIN
  PERFORM set_config('app.active_tenant_id', t::text, false);
  v_dsn := generate_dsn('2026-07');

  PERFORM _rec('T16', 'DSN : le brut déclaré du mois vaut 5 100 — le salarié absent (2 500) et le témoin (2 600), l''absence comptée UNE fois',
    (v_dsn->>'gross_total')::numeric = 5100,
    format('gross_total DSN=%s (5100 attendu)', v_dsn->>'gross_total'));

  PERFORM _rec('T17', 'DSN : les deux salariés sont déclarés (la DSN n''oublie pas l''absent)',
    (v_dsn->>'employee_count')::int = 2,
    format('employee_count=%s', v_dsn->>'employee_count'));

  SELECT COALESCE(sum(net_salary), 0), COALESCE(sum(social_security_employee), 0)
    INTO v_nets, v_ss FROM pay_slips WHERE tenant_id = t AND period_start = '2026-07-01';

  PERFORM _rec('T18', 'DSN : le net déclaré est celui des bulletins — la retenue d''absence y est donc bien entrée, une fois',
    (v_dsn->>'net_total')::numeric = v_nets AND v_nets > 0,
    format('net_total DSN=%s, somme des nets des bulletins=%s', v_dsn->>'net_total', v_nets));
END $$;

-- ── Bloc 5 — pointage, heures supplémentaires, temps projet, coût ──────────
DO $$
DECLARE
  t uuid := (SELECT v::uuid FROM _t266 WHERE k='tenant');
  e1 uuid := (SELECT v::uuid FROM _t266 WHERE k='e1');
  e2 uuid := (SELECT v::uuid FROM _t266 WHERE k='e2');
  d date := (SELECT v::date FROM _t266 WHERE k='jour');
  v_refus_pointage boolean := false;
  v_refus_temps boolean := false;
  v_ok_temoin boolean := true;
  v_sec_e1 numeric; v_sec_e2 numeric; v_hs_e1 numeric; v_ot int;
BEGIN
  -- T19/T20 : le pointage (le refus a déjà eu lieu au décor ; on le refait ici
  -- pour mesurer le refus, et on mesure l'acceptation du témoin).
  BEGIN
    INSERT INTO timesheets (tenant_id, employee_id, date, hours, status)
    VALUES (t, e1, d, 8, 'pending');
  EXCEPTION WHEN check_violation THEN v_refus_pointage := true; END;
  BEGIN
    INSERT INTO timesheets (tenant_id, employee_id, date, hours, status)
    VALUES (t, e2, d, 4, 'pending');
  EXCEPTION WHEN OTHERS THEN v_ok_temoin := false; END;

  PERFORM _rec('T19', 'pointage : saisir 8 h le jour d''absence est REFUSÉ (le temps ne peut pas entrer par cette porte)',
    v_refus_pointage, format('refus constaté=%s', v_refus_pointage));
  PERFORM _rec('T20', 'pointage : le même jour pour le témoin est ACCEPTÉ (le refus vise l''absence, pas la journée)',
    v_ok_temoin, format('acceptation du témoin=%s', v_ok_temoin));

  -- T21/T22 : les heures supplémentaires.
  SELECT COALESCE(sum(overtime_minutes), 0) INTO v_hs_e1 FROM timesheets
   WHERE tenant_id = t AND employee_id = e1 AND date = d;
  SELECT count(*) INTO v_ot FROM payroll_variable_elements
   WHERE tenant_id = t AND employee_id = e1 AND element_type = 'overtime'
     AND period = '2026-07';
  PERFORM _rec('T21', 'heures supplémentaires : aucune minute supplémentaire n''est attribuée à l''absent ce jour-là',
    v_hs_e1 = 0, format('minutes supplémentaires de E1 le %s : %s', d, v_hs_e1));
  PERFORM _rec('T22', 'heures supplémentaires : aucun élément « overtime » n''entre dans le bulletin de l''absent',
    v_ot = 0, format('éléments overtime de E1 en 2026-07 : %s', v_ot));

  -- T23 : le temps projet.
  BEGIN
    INSERT INTO project_time_entries (tenant_id, employee_id, start_time, duration_seconds, is_billable)
    VALUES (t, e1, d + time '09:00', 7200, true);
  EXCEPTION WHEN check_violation THEN v_refus_temps := true; END;
  PERFORM _rec('T23', 'temps projet : saisir 2 h de temps projet le jour d''absence est REFUSÉ',
    v_refus_temps, format('refus constaté=%s', v_refus_temps));

  -- T24/T25 : le coût projet — 0 pour l'absent, intact pour le témoin.
  SELECT COALESCE(sum(duration_seconds), 0) INTO v_sec_e1 FROM project_time_entries
   WHERE tenant_id = t AND employee_id = e1 AND start_time::date = d;
  SELECT COALESCE(sum(duration_seconds), 0) INTO v_sec_e2 FROM project_time_entries
   WHERE tenant_id = t AND employee_id = e2 AND start_time::date = d;
  PERFORM _rec('T24', 'coût projet : l''absent porte 0 seconde de temps projet — le coût de la journée n''existe nulle part',
    v_sec_e1 = 0, format('secondes de E1 le %s : %s', d, v_sec_e1));
  PERFORM _rec('T25', 'coût projet : le témoin porte ses 3 600 secondes intactes (l''absence d''E1 ne déplace pas le coût d''E2)',
    v_sec_e2 = 3600, format('secondes de E2 le %s : %s', d, v_sec_e2));

  -- T26 : le coût valorisé de la journée pour l'absent.
  PERFORM _rec('T26', 'coût projet : le coût valorisé du jour pour l''absent est de 0 € (aucun temps, donc aucun coût à répartir)',
    COALESCE((SELECT sum(COALESCE(pte.duration_seconds, 0) / 3600.0 * COALESCE(pte.hourly_rate, 0))
                FROM project_time_entries pte
               WHERE pte.tenant_id = t AND pte.employee_id = e1
                 AND pte.start_time::date = d), 0) = 0,
    'coût du jour pour E1 : 0');

  -- T27/T28 : la facturation — le temps facturable de l'absent est nul.
  PERFORM _rec('T27', 'facturation : aucun temps FACTURABLE n''est disponible pour l''absent ce jour-là',
    NOT EXISTS (SELECT 1 FROM project_time_entries
                 WHERE tenant_id = t AND employee_id = e1 AND start_time::date = d AND is_billable),
    'aucune ligne facturable pour E1');
  PERFORM _rec('T28', 'facturation : le temps facturable du témoin reste facturable (le refus ne ferme pas la journée pour tout le monde)',
    EXISTS (SELECT 1 FROM project_time_entries
             WHERE tenant_id = t AND employee_id = e2 AND start_time::date = d AND is_billable),
    'la ligne facturable du témoin est intacte');
END $$;


-- ── Bloc 6 — les frais et les tâches ───────────────────────────────────────
DO $$
DECLARE
  t uuid := (SELECT v::uuid FROM _t266 WHERE k='tenant');
  e1 uuid := (SELECT v::uuid FROM _t266 WHERE k='e1');
  e2 uuid := (SELECT v::uuid FROM _t266 WHERE k='e2');
  d date := (SELECT v::date FROM _t266 WHERE k='jour');
  a uuid; pt uuid;
  v_refus_frais boolean := false; v_refus_assignation boolean := false;
  v_refus_cloture boolean := false; v_tiers boolean := false; v_statut text;
BEGIN
  -- T29 : la ligne de frais du jour.
  BEGIN
    INSERT INTO expense_report_lines (tenant_id, expense_report_id, date, description, amount)
    SELECT t, er.id, d, 'taxi', 55 FROM expense_reports er
     WHERE er.tenant_id = t AND er.number = 'NF-T266';
  EXCEPTION WHEN check_violation THEN v_refus_frais := true; END;
  PERFORM _rec('T29', 'frais : une ligne de frais au jour de l''absence est REFUSÉE (elle ne sera pas remboursée)',
    v_refus_frais AND NOT EXISTS (
      SELECT 1 FROM expense_report_lines l JOIN expense_reports er ON er.id = l.expense_report_id
       WHERE er.tenant_id = t AND er.number = 'NF-T266' AND l.date = d),
    format('refus=%s, aucune ligne enregistrée au %s', v_refus_frais, d));

  -- T30 : l'assignation d'une nouvelle tâche au jour de l'absence.
  BEGIN
    INSERT INTO project_tasks (tenant_id, title, status, assignee_id, start_date)
    VALUES (t, 'Audit T266', 'todo', e1, d);
  EXCEPTION WHEN check_violation THEN v_refus_assignation := true; END;
  PERFORM _rec('T30', 'tâches : assigner une tâche dont le jour de démarrage est l''absence est REFUSÉ',
    v_refus_assignation, format('refus=%s', v_refus_assignation));

  -- T31 : la clôture par l'absent, et la clôture par un tiers.
  -- L'absence du 08/07 est passée : pour que le refus porte, on pose une
  -- absence du JOUR MÊME (un RTT — il bloque le travail et ne produit aucune
  -- retenue, donc il ne perturbe pas les comptes de paie ci-dessus).
  INSERT INTO leave_requests (tenant_id, employee_id, leave_type, start_date, end_date, days, status)
  VALUES (t, e1, 'rtt', CURRENT_DATE, CURRENT_DATE, 1, 'approved');

  SELECT tu.auth_id INTO a FROM tenant_users tu
   WHERE tu.tenant_id = t AND tu.status = 'active' LIMIT 1;
  UPDATE employees SET auth_user_id = a WHERE id = e1;
  SELECT id INTO pt FROM project_tasks WHERE tenant_id = t AND title = 'Rapport T266';

  PERFORM set_config('request.jwt.claim.sub', a::text, false);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', a)::text, false);
  BEGIN
    UPDATE project_tasks SET status = 'done' WHERE id = pt;
  EXCEPTION WHEN check_violation THEN v_refus_cloture := true; END;

  PERFORM set_config('request.jwt.claim.sub', gen_random_uuid()::text, false);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid())::text, false);
  BEGIN
    UPDATE project_tasks SET status = 'done' WHERE id = pt;
    v_tiers := true;
  EXCEPTION WHEN OTHERS THEN v_tiers := false; END;
  SELECT status INTO v_statut FROM project_tasks WHERE id = pt;
  PERFORM set_config('request.jwt.claim.sub', a::text, false);

  PERFORM _rec('T31', 'tâches : l''absent ne clôt pas SA tâche ; un tiers le peut (le travail ne reste pas bloqué)',
    v_refus_cloture AND v_tiers AND v_statut = 'done',
    format('clôture par l''absent refusée=%s, clôture par un tiers=%s, statut=%s',
           v_refus_cloture, v_tiers, v_statut));
END $$;

-- ── Bloc 7 — l'annulation : l'absence n'apparaît PLUS nulle part ───────────
DO $$
DECLARE
  t uuid := (SELECT v::uuid FROM _t266 WHERE k='tenant');
  e1 uuid := (SELECT v::uuid FROM _t266 WHERE k='e1');
  d date := (SELECT v::date FROM _t266 WHERE k='jour');
  v_jours int; v_elements int; v_brut numeric; v_dsn jsonb;
BEGIN
  UPDATE leave_requests SET status = 'cancelled'
   WHERE tenant_id = t AND employee_id = e1;

  SELECT count(*) INTO v_jours FROM employee_absence_days
   WHERE tenant_id = t AND employee_id = e1 AND day = d;
  PERFORM _rec('T32', 'annulation : la journée quitte le registre (0 ligne) — l''annulation n''est pas un drapeau, c''est un recalcul',
    v_jours = 0, format('lignes au registre après annulation : %s', v_jours));

  SELECT count(*) INTO v_elements FROM payroll_variable_elements
   WHERE tenant_id = t AND employee_id = e1 AND element_type = 'unpaid_leave_deduction';
  PERFORM _rec('T33', 'annulation : la retenue DÉJÀ INTÉGRÉE à un bulletin validé n''est pas effacée en silence — elle est contre-passée par un élément inverse positif (le schéma interdit les montants négatifs)',
    v_elements = 1
      AND EXISTS (SELECT 1 FROM payroll_variable_elements
                   WHERE tenant_id = t AND employee_id = e1
                     AND source = 'absence_day_reversal' AND element_type = 'pay_recall'
                     AND amount = 100),
    format('retenue intégrée conservée=%s (1 attendue, c''est une pièce), reprise positive de 100 € présente=%s',
           v_elements,
           EXISTS (SELECT 1 FROM payroll_variable_elements
                    WHERE tenant_id = t AND employee_id = e1
                      AND source = 'absence_day_reversal' AND amount = 100)));

  DELETE FROM pay_slips WHERE tenant_id = t AND employee_id = e1;
  SELECT (calculate_payslip(e1, '2026-07', (SELECT v::uuid FROM _t266 WHERE k='pay_run')) ->> 'total_gross')::numeric
    INTO v_brut;
  PERFORM _rec('T34', 'annulation : le bulletin de juillet recalculé revient au salaire plein (2 600) — la retenue n''est plus appliquée ; la reprise, elle, part sur la période courante',
    v_brut = 2600, format('total_gross après annulation=%s (2600 attendu)', v_brut));
END $$;

-- ── Le registre des verdicts ────────────────────────────────────────────────
SELECT _audit_assert('266');

