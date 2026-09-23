-- ============================================================
-- 243_payroll_and_employee_name_tests.sql — RH-01, RH-02, RH-03, RH-04
--
-- Audit des modules hors comptabilité (23/09), § RH et § Paie :
--
--   RH-01  Les 17 écrans RH affichent `employees.first_name` + `last_name`
--          (CPFPage, CareerHistoryPage, MedicalExamsPage, Phase4Pages…), deux
--          colonnes qu'AUCUN chemin n'alimente : les fiches sont créées avec
--          `name` (« Amina Waberi ») et les écrans affichent « null null ».
--   RH-02  Deux `calculate_payslip` coexistent : `(uuid, text)` — la version à
--          taux fictifs 22 % / 10 % / 42 % de la 87 — et `(uuid, text, uuid)`
--          — le moteur légal de la 153. L'écran appelle la RPC sans
--          `p_pay_run_id` quand aucun lot n'est choisi (businessFunctions.ts) :
--          PostgREST résout alors la surcharge à deux arguments, donc les taux
--          fictifs.
--   RH-03  `sync_timesheet_to_payroll` ne vérifie pas si l'élément de paie
--          existe déjà : approuver, dé-approuver, réapprouver un pointage
--          duplique les heures à chaque passage.
--   RH-04  Les heures supplémentaires sont calculées DEUX fois, de deux façons
--          contradictoires : `calculate_lateness_on_timesheet` les mesure sur
--          l'horaire prévu (`overtime_minutes`), et `sync_timesheet_to_payroll`
--          les recalcule en « heures au-delà de 7 h par jour ». Le moteur de
--          paie, lui, additionne les DEUX quantités (`element_type IN
--          ('overtime', 'timesheet_hours')`) : une journée de 9 h donnait
--          « overtimeHours = 11 » dans le bulletin.
--
-- Mesuré sur base neuve à la 234 (migrations antérieures seules), AVANT la 243 : T01 à T05 rouges.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '243', false);
DELETE FROM _audit_results WHERE file = '243';

-- Société, salarié à 3 000, un pointage de 9 h dont 60 min supplémentaires,
-- un lot de paie du mois
CREATE OR REPLACE FUNCTION _mk_rh236(p_nom text, OUT t uuid, OUT e uuid, OUT r uuid, OUT ts uuid)
LANGUAGE plpgsql AS $$
BEGIN
  t := _mk_tenant(p_nom);
  INSERT INTO employees (tenant_id, name, email, status, salary)
  VALUES (t, 'Amina Waberi ' || p_nom, lower(p_nom) || '@audit.test', 'active', 3000)
  RETURNING id INTO e;
  INSERT INTO pay_runs (tenant_id, number, period_start, period_end, pay_date, status, gross_total, tax_total, net_total, employee_count)
  VALUES (t, 'PR-' || p_nom, '2026-03-01', '2026-03-31', '2026-03-31', 'draft', 0, 0, 0, 1)
  RETURNING id INTO r;
  INSERT INTO timesheets (tenant_id, employee_id, date, hours, status)
  VALUES (t, e, '2026-03-10', 9, 'pending') RETURNING id INTO ts;
  UPDATE timesheets SET overtime_minutes = 60 WHERE id = ts;
END $$;

-- T01 — RH-01 : la fiche salarié alimente les deux colonnes des écrans
DO $$
DECLARE v record; fn text; ln text; nm text;
BEGIN
  v := _mk_rh236('T01');
  SELECT first_name, last_name, name INTO fn, ln, nm FROM employees WHERE id = v.e;
  PERFORM _rec('T01', 'fiche créée avec « name » seul : first_name et last_name remplis pour les écrans RH',
    fn = 'Amina' AND ln = 'Waberi T01' AND nm = 'Amina Waberi T01',
    format('first_name=%s last_name=%s name=%s', COALESCE(fn, 'NULL'), COALESCE(ln, 'NULL'), COALESCE(nm, 'NULL')));
END $$;

-- T02 — RH-01 (reprise) : plus aucune fiche avec un nom et deux colonnes vides
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM employees
  WHERE COALESCE(btrim(first_name), '') = ''
    AND COALESCE(btrim(last_name), '') = ''
    AND COALESCE(btrim(name), '') <> '';
  PERFORM _rec('T02', 'aucune fiche salarié sans prénom ni nom alors qu''elle porte un nom (reprise incluse)',
    n = 0, format('fiches incomplètes=%s (0 attendue)', n));
END $$;

-- T03 — RH-02 : une seule version de calculate_payslip, la légale
DO $$
DECLARE n int; args text; src text;
BEGIN
  SELECT count(*), string_agg(pg_get_function_identity_arguments(oid), ' | '), string_agg(prosrc, ' ')
    INTO n, args, src
  FROM pg_proc WHERE proname = 'calculate_payslip';
  PERFORM _rec('T03', 'calculate_payslip n''existe qu''en version légale (uuid, text, uuid) — les taux 22/10/42 % sont inatteignables',
    n = 1 AND args = 'p_employee_id uuid, p_period text, p_pay_run_id uuid'
      AND src NOT LIKE '%0.22%' AND src NOT LIKE '%0.42%',
    format('surcharges=%s | %s | taux fictifs présents=%s', n, COALESCE(args, '∅'),
      (src LIKE '%0.22%' OR src LIKE '%0.42%')::text));
END $$;

-- T04 — RH-03 : réapprouver un pointage ne duplique pas les heures
DO $$
DECLARE v record; n int; n_ot int; n_h int;
BEGIN
  v := _mk_rh236('T04');
  UPDATE timesheets SET status = 'approved' WHERE id = v.ts;   -- 1re approbation
  UPDATE timesheets SET status = 'pending' WHERE id = v.ts;
  UPDATE timesheets SET status = 'approved' WHERE id = v.ts;   -- réapprobation
  SELECT count(*),
         count(*) FILTER (WHERE element_type = 'overtime'),
         count(*) FILTER (WHERE element_type = 'timesheet_hours')
    INTO n, n_ot, n_h
  FROM payroll_variable_elements WHERE tenant_id = v.t AND source_id = v.ts;
  PERFORM _rec('T04', 'pointage approuvé deux fois : une ligne d''heures et une d''heures supplémentaires, pas quatre',
    n = 2 AND n_ot = 1 AND n_h = 1,
    format('éléments=%s (2 attendus) heures supp=%s (1 attendue) heures=%s (1 attendue)', n, n_ot, n_h));
END $$;

-- T05 — RH-04 : une seule mesure des heures supplémentaires
DO $$
DECLARE v record; q_ot numeric; q_h numeric;
BEGIN
  v := _mk_rh236('T05');
  UPDATE timesheets SET status = 'approved' WHERE id = v.ts;
  SELECT COALESCE(sum(quantity) FILTER (WHERE element_type = 'overtime'), 0),
         COALESCE(sum(quantity) FILTER (WHERE element_type = 'timesheet_hours'), 0)
    INTO q_ot, q_h
  FROM payroll_variable_elements WHERE tenant_id = v.t AND source_id = v.ts;
  PERFORM _rec('T05', 'pointage de 9 h dont 60 min supplémentaires : 1 h supplémentaire (et non 2 h ni 11 h)',
    q_ot = 1 AND q_h = 9,
    format('heures supp=%s (1 attendue) heures travaillées=%s (9 attendues)', q_ot, q_h));
END $$;

DROP FUNCTION _mk_rh236(text);
SELECT _audit_assert('243');
