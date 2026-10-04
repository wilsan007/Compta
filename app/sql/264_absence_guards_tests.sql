-- ============================================================
-- 264_absence_guards_tests.sql — W9 : les gardes en aval (TRV-03 → TRV-10, TRV-16)
--
-- Mesuré AVANT la 264, sur base neuve (229 migrations, après la 263) : le
-- registre existait, mais RIEN ne le lisait. Un salarié dont la journée était
-- au registre comme absence bloquante pouvait :
--   * pointer ses heures (`timesheets`), et les faire approuver — donc payer ;
--   * saisir du temps projet, qui peut finir FACTURÉ au client ;
--   * soumettre une ligne de frais pour la journée même ;
--   * recevoir une nouvelle tâche, et clore lui-même une tâche ;
-- et `expense_report_lines.date` n'était confrontée à rien.
--
-- Ce que ce fichier prouve APRÈS la 264 : chaque refus est une exception
-- RÉDIGÉE qui nomme le type d'absence, la date et le module — c'est ce que
-- l'écran affiche.
-- ============================================================

\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '264', false);
DELETE FROM _audit_results WHERE file = '264';

-- ── B01 — TRV-03 : le pointage d'un absent est refusé, l'absence est permise ─
DO $$
DECLARE
  t uuid; e uuid; v_refus boolean := false; v_msg text; v_libre boolean := true;
  v_absence boolean := true;
BEGIN
  t := _mk_tenant('A264T01', false);
  INSERT INTO employees (tenant_id, name, email, status, salary)
  VALUES (t, 'Awa B01', 'a264b01@audit.test', 'active', 3000) RETURNING id INTO e;
  INSERT INTO leave_requests (tenant_id, employee_id, leave_type, start_date, end_date, days, status)
  VALUES (t, e, 'annual', '2026-06-08', '2026-06-08', 1, 'approved');

  BEGIN
    INSERT INTO timesheets (tenant_id, employee_id, date, hours, status)
    VALUES (t, e, '2026-06-08', 8, 'pending');
  EXCEPTION WHEN check_violation THEN v_refus := true; v_msg := SQLERRM; END;

  -- Un jour sans absence : le pointage reste possible.
  BEGIN
    INSERT INTO timesheets (tenant_id, employee_id, date, hours, status)
    VALUES (t, e, '2026-06-09', 8, 'pending');
  EXCEPTION WHEN OTHERS THEN v_libre := false; END;

  -- La ligne qui PORTE l'absence (absence_type) n'est pas un pointage de travail.
  BEGIN
    INSERT INTO timesheets (tenant_id, employee_id, date, hours, status, absence_type, absence_reason)
    VALUES (t, e, '2026-06-10', 0, 'pending', 'unpaid', 'raison');
  EXCEPTION WHEN OTHERS THEN v_absence := false; END;

  PERFORM _rec('B01', 'TRV-03 : pointer un jour de congé est refusé avec un message rédigé, un jour libre et une ligne d''absence restent acceptés',
    v_refus AND v_libre AND v_absence
      AND position('annual' IN v_msg) > 0 AND position('08/06/2026' IN v_msg) > 0
      AND position('pointage' IN v_msg) > 0,
    format('refus=%s « %s » ; jour libre=%s ; ligne d''absence=%s',
           v_refus, COALESCE(v_msg, '(aucune exception)'), v_libre, v_absence));
END $$;

-- ── B02 — TRV-04 : un pointage saisi AVANT l'absence ne peut pas être approuvé
DO $$
DECLARE
  t uuid; e uuid; ts uuid; v_refus boolean := false; v_msg text; v_el int;
BEGIN
  t := _mk_tenant('A264T02', false);
  INSERT INTO employees (tenant_id, name, email, status, salary)
  VALUES (t, 'Bilal B02', 'a264b02@audit.test', 'active', 3000) RETURNING id INTO e;

  -- 1) le pointage est saisi d'abord (8 h + 2 h supplémentaires)
  INSERT INTO timesheets (tenant_id, employee_id, date, hours, status, overtime_minutes)
  VALUES (t, e, '2026-06-11', 8, 'pending', 120) RETURNING id INTO ts;
  -- 2) puis le congé est approuvé : la journée devient une absence bloquante
  INSERT INTO leave_requests (tenant_id, employee_id, leave_type, start_date, end_date, days, status)
  VALUES (t, e, 'annual', '2026-06-11', '2026-06-11', 1, 'approved');

  BEGIN
    UPDATE timesheets SET status = 'approved' WHERE id = ts;
  EXCEPTION WHEN check_violation THEN v_refus := true; v_msg := SQLERRM; END;

  SELECT count(*) INTO v_el FROM payroll_variable_elements
   WHERE tenant_id = t AND source_id = ts AND element_type IN ('timesheet_hours', 'overtime');

  PERFORM _rec('B02', 'TRV-04 : approuver un pointage de travail devenu jour d''absence est refusé, et aucune heure — supplémentaire comprise — n''atteint la paie',
    v_refus AND v_el = 0
      AND position('approbation du pointage' IN v_msg) > 0,
    format('approbation refusée=%s « %s », éléments de paie créés=%s (0 attendu)',
           v_refus, COALESCE(v_msg, ''), v_el));
END $$;

-- ── B03 — TRV-05 : le temps projet d'un absent est refusé ──────────────────
DO $$
DECLARE
  t uuid; e uuid; v_refus boolean := false; v_msg text; v_ok boolean := true;
BEGIN
  t := _mk_tenant('A264T03', false);
  INSERT INTO employees (tenant_id, name, email, status, salary)
  VALUES (t, 'Chams B03', 'a264b03@audit.test', 'active', 3000) RETURNING id INTO e;
  INSERT INTO leave_requests (tenant_id, employee_id, leave_type, start_date, end_date, days, status)
  VALUES (t, e, 'rtt', '2026-06-15', '2026-06-15', 1, 'approved');

  BEGIN
    INSERT INTO project_time_entries (tenant_id, employee_id, start_time, duration_seconds, is_billable)
    VALUES (t, e, '2026-06-15 09:00:00+00', 21600, true);
  EXCEPTION WHEN check_violation THEN v_refus := true; v_msg := SQLERRM; END;

  -- Un autre jour : le temps projet passe.
  BEGIN
    INSERT INTO project_time_entries (tenant_id, employee_id, start_time, duration_seconds, is_billable)
    VALUES (t, e, '2026-06-16 09:00:00+00', 21600, true);
  EXCEPTION WHEN OTHERS THEN v_ok := false; END;

  PERFORM _rec('B03', 'TRV-05 : le temps projet d''un jour d''absence est refusé avec la date nommée, et un autre jour reste accepté',
    v_refus AND v_ok AND position('temps projet' IN v_msg) > 0
      AND position('15/06/2026' IN v_msg) > 0,
    format('refus=%s « %s », autre jour accepté=%s', v_refus, COALESCE(v_msg, ''), v_ok));
END $$;

-- ── B04 — TRV-06 : une ligne de frais un jour d'absence est refusée ────────
DO $$
DECLARE
  t uuid; e uuid; er uuid; v_refus boolean := false; v_msg text; v_ok boolean := true;
  v_apres int;
BEGIN
  t := _mk_tenant('A264T04', false);
  INSERT INTO employees (tenant_id, name, email, status, salary)
  VALUES (t, 'Dalia B04', 'a264b04@audit.test', 'active', 3000) RETURNING id INTO e;
  INSERT INTO leave_requests (tenant_id, employee_id, leave_type, start_date, end_date, days, status)
  VALUES (t, e, 'unpaid', '2026-06-17', '2026-06-17', 1, 'approved');
  INSERT INTO expense_reports (tenant_id, employee_id, number, status)
  VALUES (t, e, 'NF-B04', 'draft') RETURNING id INTO er;

  BEGIN
    INSERT INTO expense_report_lines (tenant_id, expense_report_id, date, description, amount)
    VALUES (t, er, '2026-06-17', 'taxi', 42);
  EXCEPTION WHEN check_violation THEN v_refus := true; v_msg := SQLERRM; END;

  BEGIN
    INSERT INTO expense_report_lines (tenant_id, expense_report_id, date, description, amount)
    VALUES (t, er, '2026-06-18', 'taxi', 42);
  EXCEPTION WHEN OTHERS THEN v_ok := false; END;

  SELECT count(*) INTO v_apres FROM expense_report_lines WHERE tenant_id = t AND expense_report_id = er;

  PERFORM _rec('B04', 'TRV-06 : une ligne de frais au jour d''un congé sans solde est refusée (message rédigé), une autre journée passe',
    v_refus AND v_ok AND v_apres = 1 AND position('note de frais refusée' IN v_msg) > 0,
    format('refus=%s « %s », lignes enregistrées=%s (1 attendue)', v_refus, COALESCE(v_msg, ''), v_apres));
END $$;

-- ── B05 — TRV-06, la suite : la note soumise AVANT l'absence ne passe plus à
--         la soumission ni à l'approbation (l'ordre des faits est mesuré) ────
DO $$
DECLARE
  t uuid; e uuid; er uuid; v_refus_soumission boolean := false;
  v_refus_approbation boolean := false; v_msg text; v_statut text;
BEGIN
  t := _mk_tenant('A264T05', false);
  INSERT INTO employees (tenant_id, name, email, status, salary)
  VALUES (t, 'Emil B05', 'a264b05@audit.test', 'active', 3000) RETURNING id INTO e;
  INSERT INTO expense_reports (tenant_id, employee_id, number, status)
  VALUES (t, e, 'NF-B05', 'draft') RETURNING id INTO er;
  INSERT INTO expense_report_lines (tenant_id, expense_report_id, date, description, amount)
  VALUES (t, er, '2026-06-22', 'train', 90);

  -- Le congé est approuvé APRÈS la saisie de la note.
  INSERT INTO leave_requests (tenant_id, employee_id, leave_type, start_date, end_date, days, status)
  VALUES (t, e, 'annual', '2026-06-22', '2026-06-22', 1, 'approved');

  BEGIN
    UPDATE expense_reports SET status = 'submitted', submitted_at = now() WHERE id = er;
  EXCEPTION WHEN check_violation THEN v_refus_soumission := true; v_msg := SQLERRM; END;

  BEGIN
    UPDATE expense_reports SET status = 'approved', approved_at = now() WHERE id = er;
  EXCEPTION WHEN check_violation THEN v_refus_approbation := true; v_msg := SQLERRM; END;

  SELECT status INTO v_statut FROM expense_reports WHERE id = er;

  PERFORM _rec('B05', 'TRV-06 : une note saisie avant l''absence est refusée à la soumission COMME à l''approbation — le statut ne bouge pas',
    v_refus_soumission AND v_refus_approbation AND v_statut = 'draft',
    format('soumission refusée=%s, approbation refusée=%s, statut final=%s « %s »',
           v_refus_soumission, v_refus_approbation, v_statut, left(COALESCE(v_msg, ''), 120)));
END $$;


-- ── B06 — TRV-07 : on n'assigne pas une tâche à un salarié absent ──────────
DO $$
DECLARE
  t uuid; e uuid; v_absent boolean := false; v_msg text; v_ok boolean := true;
  v_futur boolean := true; v_refus_futur boolean := false;
BEGIN
  t := _mk_tenant('A264T06', false);
  INSERT INTO employees (tenant_id, name, email, status, salary)
  VALUES (t, 'Farid B06', 'a264b06@audit.test', 'active', 3000) RETURNING id INTO e;
  INSERT INTO leave_requests (tenant_id, employee_id, leave_type, start_date, end_date, days, status)
  VALUES (t, e, 'annual', '2026-06-24', '2026-06-24', 1, 'approved');

  -- a) assignation au jour de l'absence (start_date de la tâche)
  BEGIN
    INSERT INTO project_tasks (tenant_id, title, status, assignee_id, start_date)
    VALUES (t, 'Inventaire', 'todo', e, '2026-06-24');
  EXCEPTION WHEN check_violation THEN v_absent := true; v_msg := SQLERRM; END;

  -- b) une tâche d'un autre jour : acceptée
  BEGIN
    INSERT INTO project_tasks (tenant_id, title, status, assignee_id, start_date)
    VALUES (t, 'Inventaire', 'todo', e, '2026-06-25');
  EXCEPTION WHEN OTHERS THEN v_ok := false; END;

  -- c) une absence de juin n'interdit pas une tâche de septembre
  BEGIN
    INSERT INTO project_tasks (tenant_id, title, status, assignee_id, start_date)
    VALUES (t, 'Clôture septembre', 'todo', e, '2026-09-24');
  EXCEPTION WHEN OTHERS THEN v_futur := false; v_refus_futur := true; END;

  PERFORM _rec('B06', 'TRV-07 : assigner une tâche dont le jour de démarrage est une absence est refusé, un autre jour (même éloigné) reste accepté',
    v_absent AND v_ok AND v_futur AND position('affectation de tâche' IN v_msg) > 0,
    format('assignation au jour d''absence refusée=%s « %s » ; autre jour=%s ; jour éloigné=%s (refusé=%s)',
           v_absent, COALESCE(v_msg, ''), v_ok, v_futur, v_refus_futur));
END $$;

-- ── B07 — TRV-08 : l'absent ne clôt pas lui-même, un tiers le peut ─────────
DO $$
DECLARE
  t uuid; e uuid; pt uuid; a uuid; v_refus boolean := false; v_msg text;
  v_tiers boolean := false; v_statut text;
BEGIN
  t := _mk_tenant('A264T07', false);
  -- L'utilisateur connecté EST le salarié : c'est le cas que W9 doit refuser.
  SELECT tu.auth_id INTO a FROM tenant_users tu
   WHERE tu.tenant_id = t AND tu.status = 'active' LIMIT 1;
  INSERT INTO employees (tenant_id, name, email, status, salary, auth_user_id)
  VALUES (t, 'Ghada B07', 'a264b07@audit.test', 'active', 3000, a) RETURNING id INTO e;
  INSERT INTO leave_requests (tenant_id, employee_id, leave_type, start_date, end_date, days, status)
  VALUES (t, e, 'annual', CURRENT_DATE, CURRENT_DATE, 1, 'approved');
  -- La tâche est créée AVANT l'absence : c'est le cas réel du salarié qui tombe
  -- malade avec une tâche en cours.
  INSERT INTO project_tasks (tenant_id, title, status, assignee_id, start_date)
  VALUES (t, 'Rapport', 'todo', e, CURRENT_DATE - 30) RETURNING id INTO pt;

  PERFORM set_config('request.jwt.claim.sub', a::text, false);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', a)::text, false);

  BEGIN
    UPDATE project_tasks SET status = 'done' WHERE id = pt;
  EXCEPTION WHEN check_violation THEN v_refus := true; v_msg := SQLERRM; END;

  -- Un TIERS (un autre utilisateur) peut clore à sa place.
  PERFORM set_config('request.jwt.claim.sub', gen_random_uuid()::text, false);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', gen_random_uuid())::text, false);
  BEGIN
    UPDATE project_tasks SET status = 'done' WHERE id = pt;
    v_tiers := true;
  EXCEPTION WHEN OTHERS THEN v_tiers := false; END;
  SELECT status INTO v_statut FROM project_tasks WHERE id = pt;

  PERFORM set_config('request.jwt.claim.sub', a::text, false);
  PERFORM _rec('B07', 'TRV-08 : l''absent ne peut pas clore lui-même sa tâche ; un tiers le peut et la tâche passe à « done »',
    v_refus AND v_tiers AND v_statut = 'done'
      AND position('clôture de tâche' IN v_msg) > 0,
    format('clôture par l''absent refusée=%s « %s » ; clôture par un tiers=%s ; statut=%s',
           v_refus, COALESCE(v_msg, ''), v_tiers, v_statut));
END $$;


-- ── B08 — TRV-10 : une mission n'interdit rien, et la dépense est MARQUÉE ──
DO $$
DECLARE
  t uuid; e uuid; er uuid; v_ok boolean := true; v_msg text; v_marquees int;
BEGIN
  t := _mk_tenant('A264T08', false);
  INSERT INTO employees (tenant_id, name, email, status, salary)
  VALUES (t, 'Hana B08', 'a264b08@audit.test', 'active', 3000) RETURNING id INTO e;
  INSERT INTO leave_requests (tenant_id, employee_id, leave_type, start_date, end_date, days, status, reason)
  VALUES (t, e, 'mission', '2026-06-26', '2026-06-26', 1, 'approved', 'salon client');
  INSERT INTO expense_reports (tenant_id, employee_id, number, status)
  VALUES (t, e, 'NF-B08', 'draft') RETURNING id INTO er;

  BEGIN
    INSERT INTO expense_report_lines (tenant_id, expense_report_id, date, description, amount)
    VALUES (t, er, '2026-06-26', 'train', 120);
  EXCEPTION WHEN OTHERS THEN v_ok := false; v_msg := SQLERRM; END;

  SELECT count(*) INTO v_marquees FROM expense_report_lines l
   WHERE l.tenant_id = t AND l.expense_report_id = er
     AND l.mission_absence_day = '2026-06-26'
     AND l.mission_absence_employee_id = e;

  PERFORM _rec('B08', 'TRV-10 : une mission n''interdit ni les frais ni le temps, et la ligne de frais porte la mission qui l''autorise',
    v_ok AND v_marquees = 1,
    format('ligne acceptée=%s (motif si refus : %s), lignes marquées par la mission=%s (1 attendue)',
           v_ok, COALESCE(v_msg, '—'), v_marquees));
END $$;

-- ── B09 — TRV-16 : le filet NOMME les données saisies avant le registre ────
DO $$
DECLARE
  t uuid; e uuid; et uuid; er uuid; v_types text[]; v_n int; v_propre int;
BEGIN
  t := _mk_tenant('A264T09', false);
  INSERT INTO employees (tenant_id, name, email, status, salary)
  VALUES (t, 'Idris B09', 'a264b09@audit.test', 'active', 3000) RETURNING id INTO e;
  INSERT INTO employees (tenant_id, name, email, status, salary)
  VALUES (t, 'Sara B09 témoin', 'a264b09b@audit.test', 'active', 3000) RETURNING id INTO et;

  -- Trois données saisies AVANT que l'absence existe : les gardes ne pouvaient
  -- pas les refuser, c'est exactement ce que le filet doit retrouver.
  -- 04/10/2026 (340) : 7 h, l'horaire prévu d'un salarié à 35 h. Avec 8 h, la base
  -- mesure désormais 1 h supplémentaire et le contrôle nomme — à raison — une
  -- QUATRIÈME incohérence (`heures_supplementaires`). Verdict précédent : 8 h.
  INSERT INTO timesheets (tenant_id, employee_id, date, hours, status)
  VALUES (t, e, '2026-06-29', 7, 'pending');
  INSERT INTO project_time_entries (tenant_id, employee_id, start_time, duration_seconds, is_billable)
  VALUES (t, e, '2026-06-29 09:00:00+00', 3600, true);
  INSERT INTO expense_reports (tenant_id, employee_id, number, status)
  VALUES (t, e, 'NF-B09', 'draft') RETURNING id INTO er;
  INSERT INTO expense_report_lines (tenant_id, expense_report_id, date, description, amount)
  VALUES (t, er, '2026-06-29', 'taxi', 30);

  -- …puis le congé est approuvé : le registre les rend incohérents.
  INSERT INTO leave_requests (tenant_id, employee_id, leave_type, start_date, end_date, days, status)
  VALUES (t, e, 'annual', '2026-06-29', '2026-06-29', 1, 'approved');

  SELECT array_agg(DISTINCT c.conflict_type ORDER BY c.conflict_type), count(*)
    INTO v_types, v_n
    FROM check_absence_conflicts(t, '2026-06-29', '2026-06-29') c;

  -- Le jour suivant est propre : le contrôle n'invente rien.
  SELECT count(*) INTO v_propre FROM check_absence_conflicts(t, '2026-06-30', '2026-06-30');

  PERFORM _rec('B09', 'TRV-16 : le contrôle nomme les trois incohérences (pointage, temps facturable, frais) et n''invente rien sur un jour propre',
    v_types = ARRAY['frais','pointage','temps_facturable']::text[] AND v_propre = 0,
    format('types trouvés=%s (%s ligne(s)), jour propre=%s', v_types, v_n, v_propre));
END $$;


-- ── B10 — TRV-16 : le passage quotidien prévient les administrateurs ───────
DO $$
DECLARE
  t uuid; e uuid; v_total int; v_notifs int;
BEGIN
  t := _mk_tenant('A264T10', false);
  INSERT INTO employees (tenant_id, name, email, status, salary)
  VALUES (t, 'Jalil B10', 'a264b10@audit.test', 'active', 3000) RETURNING id INTO e;
  INSERT INTO timesheets (tenant_id, employee_id, date, hours, status)
  VALUES (t, e, CURRENT_DATE, 8, 'pending');
  INSERT INTO leave_requests (tenant_id, employee_id, leave_type, start_date, end_date, days, status)
  VALUES (t, e, 'annual', CURRENT_DATE, CURRENT_DATE, 1, 'approved');

  v_total := run_absence_integrity_check(CURRENT_DATE, CURRENT_DATE);
  SELECT count(*) INTO v_notifs FROM notifications n
   WHERE n.tenant_id = t AND n.category = 'hr' AND n.severity = 'warning';

  PERFORM _rec('B10', 'TRV-16 : le passage quotidien compte les anomalies et écrit une notification d''avertissement aux administrateurs',
    v_total >= 1 AND v_notifs >= 1,
    format('anomalies comptées=%s, notifications écrites=%s', v_total, v_notifs));
END $$;

-- ── B11 — isolation : les anomalies d'une société ne se lisent pas depuis une
--         autre, et le contrôle d'une société étrangère est refusé ─────────
DO $$
DECLARE
  ta uuid; tb uuid; ea uuid; eb uuid; v_vus int; v_refus boolean := false; v_msg text;
BEGIN
  ta := _mk_tenant('A264T11A', false);
  INSERT INTO employees (tenant_id, name, email, status, salary)
  VALUES (ta, 'Lina B11 de A', 'a264b11a@audit.test', 'active', 3000) RETURNING id INTO ea;
  INSERT INTO timesheets (tenant_id, employee_id, date, hours, status)
  VALUES (ta, ea, '2026-07-06', 8, 'pending');
  INSERT INTO leave_requests (tenant_id, employee_id, leave_type, start_date, end_date, days, status)
  VALUES (ta, ea, 'annual', '2026-07-06', '2026-07-06', 1, 'approved');

  tb := _mk_tenant('A264T11B', false);
  INSERT INTO employees (tenant_id, name, email, status, salary)
  VALUES (tb, 'Marc B11 de B', 'a264b11b@audit.test', 'active', 3000) RETURNING id INTO eb;

  PERFORM set_config('app.active_tenant_id', tb::text, false);
  PERFORM _as_user();
  SELECT count(*) INTO v_vus FROM absence_conflicts_current('2026-07-01', '2026-07-31');

  PERFORM set_config('role', 'postgres', true);
  BEGIN
    PERFORM count(*) FROM check_absence_conflicts(ta, '2026-07-01', '2026-07-31');
    v_refus := false;
  EXCEPTION WHEN insufficient_privilege THEN v_refus := true; v_msg := SQLERRM;
  END;

  PERFORM _rec('B11', 'isolation : une société voit 0 anomalie chez elle et ne peut pas lire celles de sa voisine',
    v_vus = 0 AND v_refus,
    format('anomalies vues depuis B=%s, lecture chez A refusée=%s %s', v_vus, v_refus, COALESCE(v_msg, '')));
END $$;

-- ── Le registre des verdicts ────────────────────────────────────────────────
SELECT _audit_assert('264');

