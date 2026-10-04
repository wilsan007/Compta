-- ============================================================
-- 263_absence_registry_tests.sql — vague W9 (TRV-01, TRV-02, TRV-14, TRV-15)
--
-- Mesuré AVANT la 263, sur base neuve (228 migrations) :
--   * `to_regclass('public.employee_absence_days')` et
--     `to_regclass('public.absence_conflict_log')` rendaient **NULL** ;
--   * `SELECT leave_type, affects_pay FROM leave_rules` rendait
--     `annual|f  rtt|f  sick|f  unpaid|f` — `affects_pay` n'était posé par
--     personne, et l'écran des règles affichait donc « n'affecte pas la paie »
--     pour la règle qui la déduit ;
--   * `INSERT INTO leave_requests (..., leave_type => 'rtt', ...)` était refusé
--     par `leave_requests_leave_type_check` alors que `leave_rules` porte `rtt`
--     et que l'écran le propose : **l'UI offrait ce que la base refusait** ;
--   * aucune des quatre sources d'absence ne convergeait : approuver un congé
--     sans solde ne laissait aucune trace lisible par le pointage, les frais ou
--     les projets ;
--   * débiter un solde de congés était le travail du FRONT (deux requêtes
--     PostgREST), donc perdu au premier appel direct.
--
-- Ce fichier est l'acceptation de la migration 263. Les défauts de garde en
-- aval (pointage, heures supplémentaires, temps projet, frais, tâches) sont
-- mesurés par 264 ; la paie, par 265 ; les 34 assertions transverses, par 266.
-- ============================================================

\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '263', false);
DELETE FROM _audit_results WHERE file = '263';


-- ── A01 — TRV-01 : un congé approuvé entre au registre, un jour par ligne ───
DO $$
DECLARE
  t uuid; e uuid; lr uuid; v_n int; v_days date[]; v_kind text; v_origin text;
BEGIN
  t := _mk_tenant('A263T01', false);
  INSERT INTO employees (tenant_id, name, email, status, salary, weekly_hours)
  VALUES (t, 'Amina A01', 'a263a01@audit.test', 'active', 3000, 35) RETURNING id INTO e;

  INSERT INTO leave_requests (tenant_id, employee_id, leave_type, start_date, end_date, days, status)
  VALUES (t, e, 'annual', '2026-05-04', '2026-05-06', 3, 'pending') RETURNING id INTO lr;
  UPDATE leave_requests SET status = 'approved' WHERE id = lr;

  SELECT count(*) INTO v_n FROM employee_absence_days WHERE tenant_id = t AND employee_id = e;
  SELECT array_agg(day ORDER BY day) INTO v_days
    FROM employee_absence_days WHERE tenant_id = t AND employee_id = e;
  SELECT absence_kind, origin INTO v_kind, v_origin
    FROM employee_absence_days WHERE tenant_id = t AND employee_id = e
   ORDER BY day LIMIT 1;

  PERFORM _rec('A01', 'un congé approuvé entre au registre : une ligne par jour, un type, une provenance',
    v_n = 3 AND v_days = ARRAY['2026-05-04','2026-05-05','2026-05-06']::date[]
      AND v_kind = 'annual' AND v_origin = 'leave_request',
    format('avant la 263 la table n''existait pas ; après : %s jour(s) = %s, type=%s, provenance=%s',
           v_n, v_days, v_kind, v_origin));
END $$;

-- ── A02 — TRV-01 : les QUATRE sources convergent ────────────────────────────
DO $$
DECLARE
  t uuid; e uuid; v_kinds text[];
BEGIN
  t := _mk_tenant('A263T02', false);
  INSERT INTO employees (tenant_id, name, email, status, salary)
  VALUES (t, 'Bilal A02', 'a263a02@audit.test', 'active', 3000) RETURNING id INTO e;

  -- 1) congé (justificatif fourni : ce scénario mesure la convergence des
  --    sources, pas l'état de justification — c'est A07 qui le mesure)
  INSERT INTO leave_requests (tenant_id, employee_id, leave_type, start_date, end_date, days, status, reason)
  VALUES (t, e, 'unpaid', '2026-06-01', '2026-06-01', 1, 'approved', 'raison personnelle');
  -- 2) maladie
  INSERT INTO sick_leaves (tenant_id, employee_id, leave_type, start_date, end_date, medical_certificate_url)
  VALUES (t, e, 'sickness', '2026-06-02', '2026-06-02', 'certificat.pdf');
  -- 3) arrêt de travail
  INSERT INTO work_stoppages (tenant_id, employee_id, stoppage_type, start_date, end_date, medical_certificate_url)
  VALUES (t, e, 'chomage_technique', '2026-06-03', '2026-06-03', 'arret.pdf');
  -- 4) pointage d'absence — la colonne que PERSONNE n'alimentait
  INSERT INTO timesheets (tenant_id, employee_id, date, hours, status, absence_type, absence_reason)
  VALUES (t, e, '2026-06-04', 0, 'pending', 'mission', 'déplacement client');

  SELECT array_agg(absence_kind ORDER BY day) INTO v_kinds
    FROM employee_absence_days WHERE tenant_id = t AND employee_id = e;

  PERFORM _rec('A02', 'les quatre sources convergent : congé, maladie, arrêt de travail et pointage d''absence',
    v_kinds = ARRAY['unpaid','sick','stoppage','mission'],
    format('registre des 4 jours : %s', v_kinds));
END $$;

-- ── A03 — TRV-02 : deux sources le même jour, la priorité tranche ET journalise
DO $$
DECLARE
  t uuid; e uuid; lr uuid; v_kind text; v_conf int; v_kept text; v_dropped text;
BEGIN
  t := _mk_tenant('A263T03', false);
  INSERT INTO employees (tenant_id, name, email, status, salary)
  VALUES (t, 'Chams A03', 'a263a03@audit.test', 'active', 3000) RETURNING id INTO e;

  INSERT INTO leave_requests (tenant_id, employee_id, leave_type, start_date, end_date, days, status)
  VALUES (t, e, 'annual', '2026-07-06', '2026-07-06', 1, 'pending') RETURNING id INTO lr;
  UPDATE leave_requests SET status = 'approved' WHERE id = lr;
  -- La même journée, en maladie : la maladie prime (elle change la paie).
  INSERT INTO sick_leaves (tenant_id, employee_id, leave_type, start_date, end_date)
  VALUES (t, e, 'sickness', '2026-07-06', '2026-07-06');

  SELECT absence_kind INTO v_kind FROM employee_absence_days
   WHERE tenant_id = t AND employee_id = e AND day = '2026-07-06';
  SELECT count(*), max(kept_kind), max(dropped_kind) INTO v_conf, v_kept, v_dropped
    FROM absence_conflict_log WHERE tenant_id = t AND employee_id = e AND day = '2026-07-06';

  PERFORM _rec('A03', 'un jour porté par deux sources : la priorité tranche (sick > annual) ET le conflit est journalisé',
    v_kind = 'sick' AND v_conf = 1 AND v_kept = 'sick' AND v_dropped = 'annual',
    format('type retenu=%s (sick attendu), conflits journalisés=%s (kept=%s, dropped=%s) — avant la 263 : aucune détection',
           v_kind, v_conf, v_kept, v_dropped));
END $$;

-- ── A04 — l'annulation efface, le report de dates corrige (idempotence) ─────
-- C'est la propriété que le rebuild apporte : rien n'est incrémenté.
DO $$
DECLARE
  t uuid; e uuid; lr uuid; v_apres_approbation int; v_apres_annulation int;
  v_apres_report int; v_jours date[];
BEGIN
  t := _mk_tenant('A263T04', false);
  INSERT INTO employees (tenant_id, name, email, status, salary)
  VALUES (t, 'Dalia A04', 'a263a04@audit.test', 'active', 3000) RETURNING id INTO e;

  INSERT INTO leave_requests (tenant_id, employee_id, leave_type, start_date, end_date, days, status)
  VALUES (t, e, 'annual', '2026-05-11', '2026-05-13', 3, 'pending') RETURNING id INTO lr;
  UPDATE leave_requests SET status = 'approved' WHERE id = lr;
  SELECT count(*) INTO v_apres_approbation FROM employee_absence_days
   WHERE tenant_id = t AND employee_id = e;

  UPDATE leave_requests SET status = 'cancelled' WHERE id = lr;
  SELECT count(*) INTO v_apres_annulation FROM employee_absence_days
   WHERE tenant_id = t AND employee_id = e;

  -- Retour à « approuvé », puis report de trois jours : le registre doit suivre.
  UPDATE leave_requests SET status = 'approved' WHERE id = lr;
  UPDATE leave_requests SET start_date = '2026-05-18', end_date = '2026-05-20' WHERE id = lr;
  SELECT count(*), array_agg(day ORDER BY day) INTO v_apres_report, v_jours
    FROM employee_absence_days WHERE tenant_id = t AND employee_id = e;

  PERFORM _rec('A04', 'annuler un congé retire ses jours, et reporter ses dates les déplace : le registre est recalculé, pas incrémenté',
    v_apres_approbation = 3 AND v_apres_annulation = 0 AND v_apres_report = 3
      AND v_jours = ARRAY['2026-05-18','2026-05-19','2026-05-20']::date[],
    format('approuvé=%s, après annulation=%s, après report=%s %s', v_apres_approbation,
           v_apres_annulation, v_apres_report, v_jours));
END $$;

-- ── A05 — la table de vérité : ce que chaque type autorise et interdit ──────
DO $$
DECLARE
  t uuid; e uuid; v_annual employee_absence_days; v_unpaid employee_absence_days;
  v_mission employee_absence_days; v_sick employee_absence_days;
BEGIN
  t := _mk_tenant('A263T05', false);
  INSERT INTO employees (tenant_id, name, email, status, salary)
  VALUES (t, 'Emil A05', 'a263a05@audit.test', 'active', 3000) RETURNING id INTO e;

  INSERT INTO leave_requests (tenant_id, employee_id, leave_type, start_date, end_date, days, status)
  VALUES (t, e, 'annual', '2026-05-04', '2026-05-04', 1, 'approved'),
         (t, e, 'unpaid', '2026-05-05', '2026-05-05', 1, 'approved'),
         (t, e, 'mission', '2026-05-06', '2026-05-06', 1, 'approved');
  INSERT INTO sick_leaves (tenant_id, employee_id, leave_type, start_date, end_date)
  VALUES (t, e, 'sickness', '2026-05-07', '2026-05-07');

  SELECT * INTO v_annual  FROM employee_absence_days WHERE tenant_id=t AND employee_id=e AND day='2026-05-04';
  SELECT * INTO v_unpaid  FROM employee_absence_days WHERE tenant_id=t AND employee_id=e AND day='2026-05-05';
  SELECT * INTO v_mission FROM employee_absence_days WHERE tenant_id=t AND employee_id=e AND day='2026-05-06';
  SELECT * INTO v_sick    FROM employee_absence_days WHERE tenant_id=t AND employee_id=e AND day='2026-05-07';

  PERFORM _rec('A05', 'la table de vérité : congé payé et maladie bloquent mais paient, sans solde bloque et retient, mission n''interdit rien',
    v_annual.blocks_work AND v_annual.paid AND v_annual.pay_rule_code = 'leave_paid'
      AND NOT v_annual.allows_expenses
      AND v_unpaid.blocks_work AND NOT v_unpaid.paid AND v_unpaid.pay_rule_code = 'unpaid_deduction'
      AND v_sick.blocks_work AND v_sick.paid AND v_sick.pay_rule_code = 'sick_maintenance'
      AND NOT v_mission.blocks_work AND v_mission.allows_expenses AND v_mission.paid,
    format('annual(bloque=%s, paie=%s, code=%s) unpaid(bloque=%s, paie=%s, code=%s) sick(paie=%s, code=%s) mission(bloque=%s, frais=%s)',
           v_annual.blocks_work, v_annual.paid, v_annual.pay_rule_code,
           v_unpaid.blocks_work, v_unpaid.paid, v_unpaid.pay_rule_code,
           v_sick.paid, v_sick.pay_rule_code, v_mission.blocks_work, v_mission.allows_expenses));
END $$;

-- ── A06 — `affects_pay` est enfin LU : la règle de la société tranche ───────
DO $$
DECLARE
  t uuid; e uuid; v_sans boolean; v_avec boolean; v_code text;
BEGIN
  t := _mk_tenant('A263T06', false);
  INSERT INTO employees (tenant_id, name, email, status, salary)
  VALUES (t, 'Farid A06', 'a263a06@audit.test', 'active', 3000) RETURNING id INTO e;

  -- La règle GLOBALE (semée) dit : les congés payés ne retiennent rien.
  INSERT INTO leave_requests (tenant_id, employee_id, leave_type, start_date, end_date, days, status)
  VALUES (t, e, 'annual', '2026-05-04', '2026-05-04', 1, 'approved');
  SELECT paid INTO v_sans FROM employee_absence_days
   WHERE tenant_id=t AND employee_id=e AND day='2026-05-04';

  -- La société pose SA règle : chez elle, un congé payé non justifié retient.
  INSERT INTO leave_rules (tenant_id, leave_type, label, affects_pay, deduction_rate, active)
  VALUES (t, 'annual', 'Congés payés (règle société)', true, 100, true);
  UPDATE leave_requests SET status = 'pending' WHERE tenant_id=t AND employee_id=e;
  UPDATE leave_requests SET status = 'approved' WHERE tenant_id=t AND employee_id=e;

  SELECT paid, pay_rule_code INTO v_avec, v_code FROM employee_absence_days
   WHERE tenant_id=t AND employee_id=e AND day='2026-05-04';

  PERFORM _rec('A06', '`leave_rules.affects_pay` est enfin lu : la règle de la société change l''effet de paie du jour',
    v_sans = true AND v_avec = false AND v_code = 'unpaid_deduction',
    format('avant la règle de société : payé=%s ; après affects_pay=true : payé=%s (code=%s) — mesuré avant la 263 : affects_pay valait false pour les quatre règles, donc jamais lu',
           v_sans, v_avec, v_code));
END $$;


-- ── A07 — TRV-14 : le justificatif décide de l'état, et le délai tranche ────
DO $$
DECLARE
  t1 uuid; t2 uuid; e1 uuid; e2 uuid; v_old date := CURRENT_DATE - 60; v_recent date := CURRENT_DATE - 5;
  v_kind text; v_state text; v_kind2 text; v_state2 text; v_kind3 text; v_state3 text;
BEGIN
  -- Société 1 : délai par défaut (30 j). Un congé sans solde de 60 jours n'a
  -- plus de justificatif : il devient « unjustified ».
  t1 := _mk_tenant('A263T07A', false);
  INSERT INTO employees (tenant_id, name, email, status, salary)
  VALUES (t1, 'Ghada A07', 'a263a07a@audit.test', 'active', 3000) RETURNING id INTO e1;
  INSERT INTO leave_requests (tenant_id, employee_id, leave_type, start_date, end_date, days, status)
  VALUES (t1, e1, 'unpaid', v_old, v_old, 1, 'approved');
  SELECT absence_kind, justification_state INTO v_kind, v_state
    FROM employee_absence_days WHERE tenant_id=t1 AND employee_id=e1 AND day=v_old;
  -- Le même jour, mais justifié : il reste « unpaid » et « provided ».
  UPDATE leave_requests SET reason = 'déménagement' WHERE tenant_id=t1 AND employee_id=e1;
  SELECT absence_kind, justification_state INTO v_kind2, v_state2
    FROM employee_absence_days WHERE tenant_id=t1 AND employee_id=e1 AND day=v_old;
  -- Récent : le délai n'est pas écoulé, la pièce est encore attendue.
  INSERT INTO leave_requests (tenant_id, employee_id, leave_type, start_date, end_date, days, status)
  VALUES (t1, e1, 'unpaid', v_recent, v_recent, 1, 'approved');
  SELECT absence_kind, justification_state INTO v_kind3, v_state3
    FROM employee_absence_days WHERE tenant_id=t1 AND employee_id=e1 AND day=v_recent;

  PERFORM _rec('A07', 'TRV-14 : sans justificatif passé le délai le jour devient « unjustified », avec justificatif il reste « unpaid / provided », et récent il est « pending »',
    v_kind = 'unjustified' AND v_state = 'missing'
      AND v_kind2 = 'unpaid' AND v_state2 = 'provided'
      AND v_kind3 = 'unpaid' AND v_state3 = 'pending',
    format('60 j sans pièce : %s/%s ; avec pièce : %s/%s ; 5 j sans pièce : %s/%s',
           v_kind, v_state, v_kind2, v_state2, v_kind3, v_state3));
END $$;

-- ── A08 — le refus est RÉDIGÉ : il nomme le type, la date et le module ──────
DO $$
DECLARE
  t uuid; e uuid; v_ok boolean := false; v_msg text; v_libre boolean := true;
BEGIN
  t := _mk_tenant('A263T08', false);
  INSERT INTO employees (tenant_id, name, email, status, salary)
  VALUES (t, 'Hana A08', 'a263a08@audit.test', 'active', 3000) RETURNING id INTO e;
  INSERT INTO leave_requests (tenant_id, employee_id, leave_type, start_date, end_date, days, status, reason)
  VALUES (t, e, 'unpaid', '2026-06-15', '2026-06-15', 1, 'approved', 'raison personnelle');

  BEGIN
    PERFORM assert_not_absent(e, '2026-06-15', 'pointage');
  EXCEPTION WHEN check_violation THEN v_ok := true; v_msg := SQLERRM; END;

  -- Un jour sans absence ne refuse rien.
  BEGIN
    PERFORM assert_not_absent(e, '2026-06-16', 'pointage');
  EXCEPTION WHEN OTHERS THEN v_libre := false; END;

  PERFORM _rec('A08', 'TRV-03 : le refus nomme le type, la date et le module (« Absence « unpaid » (congé sans solde) le 15/06/2026 : pointage refusé ») et ne refuse rien hors absence',
    v_ok AND v_libre
      AND position('unpaid' IN v_msg) > 0
      AND position('congé sans solde' IN v_msg) > 0
      AND position('15/06/2026' IN v_msg) > 0
      AND position('pointage' IN v_msg) > 0,
    format('message rendu : « %s » (jour libre accepté : %s)', COALESCE(v_msg, '(aucune exception)'), v_libre));
END $$;

-- ── A09 — l'échappatoire : une dérogation VALIDÉE, jamais un identifiant nu ─
DO $$
DECLARE
  t uuid; e uuid; w uuid; v_nu boolean := false; v_valide boolean := false; v_msg text;
BEGIN
  t := _mk_tenant('A263T09', false);
  INSERT INTO employees (tenant_id, name, email, status, salary)
  VALUES (t, 'Idris A09', 'a263a09@audit.test', 'active', 3000) RETURNING id INTO e;
  INSERT INTO leave_requests (tenant_id, employee_id, leave_type, start_date, end_date, days, status)
  VALUES (t, e, 'annual', '2026-06-22', '2026-06-22', 1, 'approved');

  -- a) un identifiant inventé ne lève rien
  BEGIN
    PERFORM assert_not_absent(e, '2026-06-22', 'pointage', gen_random_uuid());
  EXCEPTION WHEN check_violation THEN v_nu := true; END;

  -- b) un workflow actif, approuvé pour CE salarié et CE jour, lève le refus
  INSERT INTO approval_workflows (tenant_id, name, entity_type, active, steps)
  VALUES (t, 'Astreinte inventaire', 'absence_override', true,
          jsonb_build_array(jsonb_build_object('employee_id', e::text, 'status', 'approved',
                                               'from', '2026-06-22', 'to', '2026-06-22')))
  RETURNING id INTO w;
  BEGIN
    PERFORM assert_not_absent(e, '2026-06-22', 'pointage', w);
    v_valide := true;
  EXCEPTION WHEN check_violation THEN v_valide := false; v_msg := SQLERRM; END;

  PERFORM _rec('A09', 'la dérogation n''est honorée que validée pour ce salarié et ce jour : un identifiant inventé refuse, un workflow approuvé autorise',
    v_nu AND v_valide,
    format('identifiant nu refusé=%s, workflow approuvé autorisé=%s %s', v_nu, v_valide, COALESCE(v_msg, '')));
END $$;


-- ── A10 — TRV-15 : le solde est débité en BASE, pas par l'écran ─────────────
DO $$
DECLARE
  t uuid; e uuid; lr uuid; v_pending_a numeric; v_taken_a numeric; v_remaining_a numeric;
  v_taken_apres_annulation numeric; v_pending_b numeric; v_taken_b numeric;
BEGIN
  t := _mk_tenant('A263T10', false);
  INSERT INTO employees (tenant_id, name, email, status, salary)
  VALUES (t, 'Jalil A10', 'a263a10@audit.test', 'active', 3000) RETURNING id INTO e;
  INSERT INTO leave_balances (tenant_id, employee_id, leave_type, year, acquired, taken, pending, remaining)
  VALUES (t, e, 'annual', 2026, 25, 0, 0, 25);

  -- a) la demande met le solde « en attente » — sans un seul appel d'écran
  INSERT INTO leave_requests (tenant_id, employee_id, leave_type, start_date, end_date, days, status)
  VALUES (t, e, 'annual', '2026-05-04', '2026-05-06', 3, 'pending') RETURNING id INTO lr;
  SELECT pending, taken, remaining INTO v_pending_a, v_taken_a, v_remaining_a
    FROM leave_balances WHERE tenant_id=t AND employee_id=e AND leave_type='annual' AND year=2026;

  -- b) l'approbation transfère « en attente » vers « pris »
  UPDATE leave_requests SET status = 'approved' WHERE id = lr;
  SELECT pending, taken INTO v_pending_b, v_taken_b
    FROM leave_balances WHERE tenant_id=t AND employee_id=e AND leave_type='annual' AND year=2026;

  -- c) l'annulation restitue
  UPDATE leave_requests SET status = 'cancelled' WHERE id = lr;
  SELECT taken INTO v_taken_apres_annulation
    FROM leave_balances WHERE tenant_id=t AND employee_id=e AND leave_type='annual' AND year=2026;

  PERFORM _rec('A10', 'TRV-15 : le solde passe de 0 à « en attente » à la demande, à « pris » à l''approbation, et revient à l''annulation — le tout en base',
    v_pending_a = 3 AND v_taken_a = 0 AND v_remaining_a = 22
      AND v_pending_b = 0 AND v_taken_b = 3
      AND v_taken_apres_annulation = 0,
    format('demande: pending=%s taken=%s remaining=%s ; approuvé: pending=%s taken=%s ; annulé: taken=%s',
           v_pending_a, v_taken_a, v_remaining_a, v_pending_b, v_taken_b, v_taken_apres_annulation));
END $$;

-- ── A11 — une absence ne se cumule pas avec un week-end ni un férié ─────────
DO $$
DECLARE
  t uuid; e uuid; v_lundi date := (date_trunc('week', CURRENT_DATE)::date - 14);
  v_dimanche date; v_vendredi date; v_total int; v_travailles int;
BEGIN
  t := _mk_tenant('A263T11', false);
  INSERT INTO employees (tenant_id, name, email, status, salary)
  VALUES (t, 'Karim A11', 'a263a11@audit.test', 'active', 3000) RETURNING id INTO e;
  v_dimanche := v_lundi + 6;
  v_vendredi := v_lundi + 4;
  -- Le vendredi est férié : « deux lignes pour un jour payé une fois ».
  INSERT INTO public_holidays (tenant_id, name, holiday_date, region, country, is_working_day)
  VALUES (t, 'Férié de test', v_vendredi, 'national', 'FR', false);

  INSERT INTO leave_requests (tenant_id, employee_id, leave_type, start_date, end_date, days, status)
  VALUES (t, e, 'annual', v_lundi, v_dimanche, 7, 'approved');

  SELECT count(*) INTO v_total FROM employee_absence_days
   WHERE tenant_id=t AND employee_id=e AND day BETWEEN v_lundi AND v_dimanche;
  v_travailles := absence_working_days(t, e, v_lundi, v_dimanche);

  PERFORM _rec('A11', 'absence_working_days ne compte ni le week-end ni le férié : 7 jours de registre n''en valent que 4 pour la paie',
    v_total = 7 AND v_travailles = 4 AND extract(isodow FROM v_lundi) = 1,
    format('du lundi %s au dimanche %s : %s jour(s) au registre, %s jour(s) payés (férié le %s)',
           v_lundi, v_dimanche, v_total, v_travailles, v_vendredi));
END $$;


-- ── A12 — isolation : la société voisine ne voit ni ne modifie le registre ──
DO $$
DECLARE
  ta uuid; tb uuid; ea uuid; eb uuid; v_vus int; v_refus boolean := false; v_msg text;
  v_existe int;
BEGIN
  ta := _mk_tenant('A263T12A', false);
  INSERT INTO employees (tenant_id, name, email, status, salary)
  VALUES (ta, 'Lina A12 de A', 'a263a12a@audit.test', 'active', 3000) RETURNING id INTO ea;
  INSERT INTO leave_requests (tenant_id, employee_id, leave_type, start_date, end_date, days, status)
  VALUES (ta, ea, 'annual', '2026-05-04', '2026-05-05', 2, 'approved');

  tb := _mk_tenant('A263T12B', false);
  INSERT INTO employees (tenant_id, name, email, status, salary)
  VALUES (tb, 'Marc A12 de B', 'a263a12b@audit.test', 'active', 3000) RETURNING id INTO eb;

  SELECT count(*) INTO v_existe FROM employee_absence_days WHERE tenant_id = ta;

  -- Sous le rôle `authenticated`, avec le contexte de B :
  PERFORM set_config('app.active_tenant_id', tb::text, false);
  PERFORM _as_user();
  SELECT count(*) INTO v_vus FROM employee_absence_days;

  -- Et B ne peut pas déclencher un recalcul chez A.
  PERFORM set_config('role', 'postgres', true);
  BEGIN
    PERFORM rebuild_absence_days(ta, ea, '2026-05-04', '2026-05-05');
    v_refus := false;
  EXCEPTION WHEN insufficient_privilege THEN v_refus := true; v_msg := SQLERRM;
  END;

  PERFORM _rec('A12', 'isolation : le registre de la société A est invisible depuis B (2 lignes existent, 0 vues), et B ne peut pas recalculer chez A',
    v_existe = 2 AND v_vus = 0 AND v_refus,
    format('lignes chez A=%s, vues depuis B=%s, recalcul refusé=%s %s', v_existe, v_vus, v_refus, COALESCE(v_msg, '')));
END $$;

-- ── A13 — l'UI offrait « RTT » et la base le refusait ──────────────────────
DO $$
DECLARE
  t uuid; e uuid; v_ok boolean := true; v_msg text; v_kind text;
BEGIN
  t := _mk_tenant('A263T13', false);
  INSERT INTO employees (tenant_id, name, email, status, salary)
  VALUES (t, 'Nadia A13', 'a263a13@audit.test', 'active', 3000) RETURNING id INTO e;
  BEGIN
    INSERT INTO leave_requests (tenant_id, employee_id, leave_type, start_date, end_date, days, status)
    VALUES (t, e, 'rtt', '2026-05-04', '2026-05-05', 2, 'approved');
  EXCEPTION WHEN check_violation THEN v_ok := false; v_msg := SQLERRM; END;

  SELECT absence_kind INTO v_kind FROM employee_absence_days
   WHERE tenant_id=t AND employee_id=e AND day='2026-05-04';

  PERFORM _rec('A13', 'une demande de RTT — que l''écran propose — est acceptée par la base et entre au registre comme « rtt »',
    v_ok AND v_kind = 'rtt',
    format('insertion RTT acceptée=%s, type au registre=%s %s', v_ok, v_kind, COALESCE(v_msg, '')));
END $$;

-- ── Le registre des verdicts ────────────────────────────────────────────────
SELECT _audit_assert('263');

