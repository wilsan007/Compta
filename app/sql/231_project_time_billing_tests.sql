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
--
-- W8 (301, 28/09/2026) — la refacturation existe. `M-17-01` est fermé :
--   • M-17-01 mesure désormais ce que la refacturation doit produire — une
--     ligne de facture de 240 dans un brouillon du projet — et plus seulement
--     « au moins une ligne » ;
--   • T07 ajoute le chemin que le déclencheur ne voyait pas : la **saisie
--     directe** (formulaire « temps manuel », insertion avec `end_time` du
--     premier coup) n'arrête aucun chronomètre, donc aucun `UPDATE OF end_time` ;
--     avant le correctif, ces heures n'atteignaient rien non plus ;
--   • T08 mesure l'idempotence : un même temps arrêté deux fois n'est facturé
--     qu'une fois (index unique `(tenant_id, time_entry_id)`).
-- Les deux nouveaux scénarios sont vus **rouges avant** la 301 (colonne
-- `time_entry_id` absente, aucune ligne créée).
--
-- Ce que la 301 ne fait pas : le brouillon n'est **pas** validé automatiquement
-- (aucune écriture comptable n'est produite par un temps passé — T06 le tient),
-- et la ligne est au prix de la feuille de temps, à la TVA par défaut de la
-- société ; il n'y a pas de régénération ni de note d'honoraires groupée.
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

-- Saisie directe (« temps manuel ») : le `end_time` est là dès l'INSERT
CREATE OR REPLACE FUNCTION _saisie231(p_t uuid, p_pr uuid, p_tk uuid, p_emp uuid,
  p_taux numeric, p_heures numeric)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE te uuid; v_start timestamptz := now() - make_interval(secs => (p_heures * 3600));
BEGIN
  INSERT INTO project_time_entries (tenant_id, project_id, task_id, employee_id, start_time, end_time, duration_seconds, is_billable, hourly_rate)
  VALUES (p_t, p_pr, p_tk, p_emp, v_start, now(), (p_heures * 3600)::int, true, p_taux)
  RETURNING id INTO te;
  RETURN te;
END $$;

-- T01/T02/T06 : 3 h facturables à 80 — où vont-elles ?
DO $$
DECLARE v record; hrs numeric; n_notif int; n_inv int; n_draft int;
        n_line int; v_qty numeric; v_total numeric; n_je int;
BEGIN
  v := _mk_projet231('T01');
  PERFORM _as_user();
  PERFORM _pointer231(v.t, v.pr, v.tk, v.emp, 80);
  PERFORM set_config('role', 'postgres', true);

  SELECT total_hours_spent INTO hrs FROM projects WHERE id = v.pr;
  SELECT count(*) INTO n_notif FROM project_notifications WHERE tenant_id = v.t;
  SELECT count(*) INTO n_inv FROM invoices WHERE tenant_id = v.t;
  SELECT count(*) INTO n_draft FROM invoices
    WHERE tenant_id = v.t AND status = 'draft' AND validation_status = 'draft';
  SELECT count(*), COALESCE(sum(quantity), 0), COALESCE(sum(total), 0)
    INTO n_line, v_qty, v_total FROM invoice_lines WHERE tenant_id = v.t;
  SELECT count(*) INTO n_je FROM journal_entries WHERE tenant_id = v.t;

  PERFORM _rec('T01', '3 h pointées remontent dans les heures du projet',
    hrs = 3.00, format('heures du projet=%s (3,00 attendues)', COALESCE(hrs, 0)));

  -- Identifiant porté au registre : le couple (fichier, identifiant). Un « T02 »
  -- inscrit ici ne dispenserait pas le T02 des autres fichiers (AUD-X01).
  -- W8 : le scénario mesure la refacturation elle-même — 3 h × 80 = 240 sur une
  -- ligne rattachée à un brouillon du projet, et non « au moins une ligne ».
  PERFORM _rec('M-17-01', '3 h facturables à 80 atteignent une ligne de facture de 240, dans un brouillon du projet',
    n_line >= 1 AND v_qty = 3 AND v_total = 240 AND n_draft >= 1,
    format('lignes de facture=%s (au moins 1 attendue) dont quantité=%s montant=%s | factures=%s dont brouillons=%s | notifications=%s',
           n_line, v_qty, v_total, n_inv, n_draft, n_notif));

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

-- T07 : la saisie directe — le formulaire « temps manuel » insère la feuille avec
-- son `end_time` du premier coup : il n'y a aucun `UPDATE OF end_time`, donc le
-- déclencheur branché sur l'arrêt du chronomètre ne la voyait pas. 2 h à 120 = 240.
DO $$
DECLARE v record; n_line int; v_tot numeric;
BEGIN
  v := _mk_projet231('T07');
  PERFORM _as_user();
  BEGIN
    PERFORM _saisie231(v.t, v.pr, v.tk, v.emp, 120, 2);
    PERFORM set_config('role', 'postgres', true);
    SELECT count(*), COALESCE(sum(total), 0) INTO n_line, v_tot
      FROM invoice_lines WHERE tenant_id = v.t;
    PERFORM _rec('T07', 'une saisie manuelle facturable de 2 h à 120 atteint une ligne de 240',
      n_line = 1 AND v_tot = 240, format('lignes=%s montant=%s', n_line, v_tot));
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('role', 'postgres', true);
    PERFORM _rec('T07', 'une saisie manuelle facturable de 2 h à 120 atteint une ligne de 240', false, SQLERRM);
  END;
END $$;

-- T08 : idempotence. Rouvrir un temps (end_time remis à NULL) puis l'arrêter de
-- nouveau ne doit pas le facturer une seconde fois — c'est la garantie de
-- l'index unique (tenant_id, time_entry_id), pas une politesse du code.
DO $$
DECLARE v record; te uuid; n_line int;
BEGIN
  v := _mk_projet231('T08');
  PERFORM _as_user();
  BEGIN
    te := _pointer231(v.t, v.pr, v.tk, v.emp, 90);
    PERFORM set_config('role', 'postgres', true);
    UPDATE project_time_entries SET end_time = NULL WHERE id = te;
    PERFORM _as_user();
    UPDATE project_time_entries SET end_time = now(), duration_seconds = 7200 WHERE id = te;
    PERFORM set_config('role', 'postgres', true);
    SELECT count(*) INTO n_line FROM invoice_lines
      WHERE tenant_id = v.t AND time_entry_id = te;
    PERFORM _rec('T08', 'un même temps arrêté deux fois n''est facturé qu''une fois',
      n_line = 1, format('lignes rattachées à ce temps=%s (1 attendue)', n_line));
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('role', 'postgres', true);
    PERFORM _rec('T08', 'un même temps arrêté deux fois n''est facturé qu''une fois', false, SQLERRM);
  END;
END $$;

-- T09 : la chaîne de la suppression, dans les deux sens. Supprimer une feuille de
-- temps **en brouillon** retire sa ligne (on ne facture pas une heure qui n'existe
-- plus) ; une fois la facture **validée**, la même suppression est refusée par la
-- garde de la 190 (« Facture validée : ses lignes ne peuvent plus être modifiées »)
-- — la cascade de la clé étrangère ne contourne pas une pièce comptable.
DO $$
DECLARE v record; te uuid; n_avant int; n_apres int; n_valides int;
        refuse boolean := false; err text := '—';
BEGIN
  v := _mk_projet231('T09');
  PERFORM _as_user();
  BEGIN
    te := _pointer231(v.t, v.pr, v.tk, v.emp, 100);
    PERFORM set_config('role', 'postgres', true);
    SELECT count(*) INTO n_avant FROM invoice_lines WHERE tenant_id = v.t;
    DELETE FROM project_time_entries WHERE id = te;
    SELECT count(*) INTO n_apres FROM invoice_lines WHERE tenant_id = v.t;
    PERFORM _rec('T09', 'supprimer une feuille de temps en brouillon retire sa ligne facturable',
      n_avant = 1 AND n_apres = 0,
      format('lignes avant suppression=%s après=%s', n_avant, n_apres));
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('role', 'postgres', true);
    PERFORM _rec('T09', 'supprimer une feuille de temps en brouillon retire sa ligne facturable', false, SQLERRM);
  END;

  -- Deuxième temps, puis validation de la facture du projet : la suppression de
  -- l'heure facturée doit être refusée.
  BEGIN
    PERFORM _as_user();
    te := _pointer231(v.t, v.pr, v.tk, v.emp, 100);
    PERFORM set_config('role', 'postgres', true);
    UPDATE invoices SET validation_status = 'validated'
      WHERE tenant_id = v.t AND project_id = v.pr AND validation_status = 'draft';
    SELECT count(*) INTO n_valides FROM invoice_lines l
      JOIN invoices i ON i.id = l.invoice_id AND i.tenant_id = l.tenant_id
      WHERE l.tenant_id = v.t AND i.validation_status = 'validated';
    BEGIN
      DELETE FROM project_time_entries WHERE id = te;
    EXCEPTION WHEN OTHERS THEN refuse := true; err := SQLERRM;
    END;
    PERFORM _rec('T09b', 'une heure facturée ne se supprime plus : la pièce validée est protégée',
      refuse AND n_valides = 1,
      format('lignes sur facture validée=%s suppression refusée=%s | %s', n_valides, refuse, left(err, 90)));
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('role', 'postgres', true);
    PERFORM _rec('T09b', 'une heure facturée ne se supprime plus : la pièce validée est protégée', false, SQLERRM);
  END;
END $$;


DROP FUNCTION _pointer231(uuid, uuid, uuid, uuid, numeric);
DROP FUNCTION _saisie231(uuid, uuid, uuid, uuid, numeric, numeric);
DROP FUNCTION _mk_projet231(text, text);
SELECT _audit_assert('231');
