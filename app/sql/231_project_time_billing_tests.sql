-- ============================================================
-- 231_project_time_billing_tests.sql — M-17 : temps passés et refacturation
--
-- Le reste-à-faire demandait : « refacturation des temps → facture ; aucune
-- écriture directe ». Mesuré sur base neuve à la 230, AVANT la 231 :
--
--   T01 vert   — le temps remonte bien dans les heures du projet
--   M-17-01 ROUGE — 3 h facturables à 80 ne produisent ni facture ni ligne de
--                facture, seulement une notification. La fonction s'appelle
--                pourtant `create_billable_line`. Manque de fonction, inscrit
--                au registre sous M-17-01 : ce scénario reste rouge jusqu'à
--                ce que les heures atteignent une facture.
--   T03 ROUGE  — un temps de la société B visant le projet de la société A est
--                accepté
--   T04 ROUGE  — et le nom du projet de A se retrouve dans une notification de B
--   T05 ROUGE  — le montant est libellé « € » quelle que soit la devise
--   T06 vert   — aucune écriture comptable n'est générée par un temps passé
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '231', false);
DELETE FROM _audit_results WHERE file = '231';

CREATE OR REPLACE FUNCTION _mk_projet231(p_nom text, p_devise text DEFAULT 'EUR',
  OUT t uuid, OUT c uuid, OUT pr uuid, OUT tk uuid, OUT emp uuid, OUT mgr uuid)
LANGUAGE plpgsql AS $$
BEGIN
  t := _mk_tenant(p_nom);
  PERFORM ensure_standard_journals(t);
  UPDATE company_settings SET currency = p_devise WHERE tenant_id = t;
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client ' || p_nom) RETURNING id INTO c;
  INSERT INTO employees (tenant_id, name, first_name, last_name, email, hire_date, status)
    VALUES (t, 'Salarié ' || p_nom, 'Sal', p_nom, lower(p_nom) || '-sal@audit.test', CURRENT_DATE, 'active')
    RETURNING id INTO emp;
  INSERT INTO employees (tenant_id, name, first_name, last_name, email, hire_date, status)
    VALUES (t, 'Chef ' || p_nom, 'Chef', p_nom, lower(p_nom) || '-chef@audit.test', CURRENT_DATE, 'active')
    RETURNING id INTO mgr;
  INSERT INTO projects (tenant_id, name, customer_id, status, allow_billable, allow_timesheets, manager_id)
    VALUES (t, 'Chantier ' || p_nom, c, 'active', true, true, mgr) RETURNING id INTO pr;
  INSERT INTO project_tasks (tenant_id, project_id, title, status)
    VALUES (t, pr, 'Tâche ' || p_nom, 'todo') RETURNING id INTO tk;
END $$;

-- Saisir 3 h facturables à 80 : démarrer puis arrêter le chronomètre
CREATE OR REPLACE FUNCTION _pointer231(p_t uuid, p_pr uuid, p_tk uuid, p_emp uuid, p_taux numeric)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE te uuid;
BEGIN
  INSERT INTO project_time_entries (tenant_id, project_id, task_id, employee_id, start_time, end_time, duration_seconds, is_billable, hourly_rate)
  VALUES (p_t, p_pr, p_tk, p_emp, now() - interval '3 hours', NULL, 0, true, p_taux) RETURNING id INTO te;
  UPDATE project_time_entries SET end_time = now(), duration_seconds = 10800 WHERE id = te;
  RETURN te;
END $$;

-- T01/T02/T06 : 3 h facturables à 80 — où vont-elles ?
DO $$
DECLARE v record; hrs numeric; n_notif int; n_inv int; n_line int; n_je int;
BEGIN
  v := _mk_projet231('T01');
  PERFORM _as_user();
  PERFORM _pointer231(v.t, v.pr, v.tk, v.emp, 80);
  PERFORM set_config('role', 'postgres', true);

  SELECT total_hours_spent INTO hrs FROM projects WHERE id = v.pr;
  SELECT count(*) INTO n_notif FROM project_notifications WHERE tenant_id = v.t;
  SELECT count(*) INTO n_inv FROM invoices WHERE tenant_id = v.t;
  SELECT count(*) INTO n_line FROM invoice_lines WHERE tenant_id = v.t;
  SELECT count(*) INTO n_je FROM journal_entries WHERE tenant_id = v.t;

  PERFORM _rec('T01', '3 h pointées remontent dans les heures du projet',
    hrs = 3.00, format('heures du projet=%s (3,00 attendues)', COALESCE(hrs, 0)));

  -- Identifiant porté au registre : `_audit_expected` a pour clé le seul
  -- test_id, sans le nom du fichier. Un « T02 » y dispenserait le T02 de tous
  -- les autres fichiers.
  PERFORM _rec('M-17-01', '3 h facturables à 80 atteignent une ligne de facture de 240',
    n_line >= 1,
    format('lignes de facture=%s (au moins 1 attendue) factures=%s notifications=%s — la fonction create_billable_line ne crée qu''une notification',
           n_line, n_inv, n_notif));

  PERFORM _rec('T06', 'un temps passé ne génère aucune écriture comptable directe',
    n_je = 0, format('écritures=%s (0 attendue)', n_je));
END $$;

-- T03/T04 : le temps de la société B vise le projet de la société A
DO $$
DECLARE va record; vb record; te uuid;
        refuse boolean := false; err text := '—';
        n_chez_a int; n_chez_b int; fuite int;
BEGIN
  va := _mk_projet231('T03A');
  vb := _mk_projet231('T03B');       -- le contexte bascule sur la société B
  PERFORM _as_user();
  BEGIN
    INSERT INTO project_time_entries (tenant_id, project_id, employee_id, start_time, end_time, duration_seconds, is_billable, hourly_rate)
    VALUES (vb.t, va.pr, vb.emp, now() - interval '1 hour', NULL, 0, true, 99) RETURNING id INTO te;
    UPDATE project_time_entries SET end_time = now(), duration_seconds = 3600 WHERE id = te;
  EXCEPTION WHEN OTHERS THEN refuse := true; err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);

  SELECT count(*) INTO n_chez_a FROM project_notifications WHERE tenant_id = va.t;
  SELECT count(*) INTO n_chez_b FROM project_notifications WHERE tenant_id = vb.t;
  SELECT count(*) INTO fuite FROM project_notifications
    WHERE tenant_id = vb.t AND message LIKE '%Chantier T03A%';

  PERFORM _rec('T03', 'pointer sur le projet d''une autre société : refusé',
    refuse, format('refus=%s | %s', refuse, left(err, 80)));

  PERFORM _rec('T04', 'le nom du projet de A n''apparaît dans aucune notification de B',
    fuite = 0 AND n_chez_b = 0,
    format('notifications chez B citant le projet de A=%s (0 attendue) notifications chez B=%s chez A=%s',
           fuite, n_chez_b, n_chez_a));
END $$;

-- T05 : une société en francs de Djibouti ne compte pas en euros
DO $$
DECLARE v record; msg text;
BEGIN
  v := _mk_projet231('T05', 'DJF');
  PERFORM _as_user();
  PERFORM _pointer231(v.t, v.pr, v.tk, v.emp, 1000);
  PERFORM set_config('role', 'postgres', true);

  SELECT message INTO msg FROM project_notifications WHERE tenant_id = v.t LIMIT 1;
  PERFORM _rec('T05', 'le montant facturable est libellé dans la devise de la société, pas en euros',
    msg IS NOT NULL AND msg LIKE '%DJF%' AND msg NOT LIKE '%€%',
    format('message=%s', COALESCE(left(msg, 90), '(aucune notification)')));
END $$;

DROP FUNCTION _pointer231(uuid, uuid, uuid, uuid, numeric);
DROP FUNCTION _mk_projet231(text, text);
SELECT _audit_assert('231');
