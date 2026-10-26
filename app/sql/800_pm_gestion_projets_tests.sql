-- ============================================================
-- 800_pm_gestion_projets_tests.sql — 800, 801, 802 : statuts, progression,
-- bornes de dates et dépendances de la gestion de projets
--
--   800  un vocabulaire de statut ; taux de réalisation par action ; UNE règle
--        d'avancement (actions + sous-tâches) qui remonte à la mère et au projet
--   801  un enfant reste dans la période de son parent ; un parent déplacé
--        emmène ses enfants ; on ne coupe jamais un enfant en silence
--   802  liens « B après A » entre tâches et entre projets : refus des liens
--        absurdes, report automatique du successeur, refus de le placer avant
--   803  pas d'action cochée sans document de preuve (sauf achèvement propagé)
--   804  le statut suit l'avancement calculé (sans écraser bloqué, approuvé…)
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '800', false);
DELETE FROM _audit_results WHERE file = '800';

DROP FUNCTION IF EXISTS _pj800(text, date, date);
CREATE OR REPLACE FUNCTION _pj800(p_nom text, p_debut date DEFAULT NULL, p_fin date DEFAULT NULL,
  OUT out_tenant uuid, OUT out_projet uuid)
LANGUAGE plpgsql AS $$
BEGIN
  out_tenant := _mk_tenant(p_nom);
  INSERT INTO projects (tenant_id, name, status, start_date, end_date)
  VALUES (out_tenant, 'Projet ' || p_nom, 'active', p_debut, p_fin) RETURNING id INTO out_projet;
END $$;

DROP FUNCTION IF EXISTS _t800(uuid, uuid, text, date, date, uuid, numeric);
CREATE OR REPLACE FUNCTION _t800(p_t uuid, p_pr uuid, p_titre text, p_debut date, p_fin date,
  p_parent uuid DEFAULT NULL, p_effort numeric DEFAULT 1)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v uuid;
BEGIN
  INSERT INTO project_tasks (tenant_id, project_id, title, status, start_date, due_date, parent_id, effort_estimate_h)
  VALUES (p_t, p_pr, p_titre, 'todo', p_debut, p_fin, p_parent, p_effort) RETURNING id INTO v;
  RETURN v;
END $$;

DROP FUNCTION IF EXISTS _a800(uuid, uuid, text, integer, integer);
-- Une action de test porte toujours son document de preuve (803 : pas de coche
-- sans preuve) ; elle est créée à 0 puis portée au taux voulu, comme à l'écran.
-- Les scénarios de la 803 (T23 →) créent leurs actions SANS ce helper.
DROP FUNCTION IF EXISTS _preuve800(uuid, uuid);
CREATE OR REPLACE FUNCTION _preuve800(p_t uuid, p_action uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO task_action_attachments (tenant_id, task_action_id, task_id, file_name, file_path)
  SELECT p_t, a.id, a.task_id, 'preuve.pdf', p_t || '/actions/' || a.id || '/preuve.pdf'
    FROM task_actions a WHERE a.id = p_action;
END $$;

CREATE OR REPLACE FUNCTION _a800(p_t uuid, p_task uuid, p_titre text, p_poids integer, p_taux integer DEFAULT 0)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v uuid;
BEGIN
  INSERT INTO task_actions (tenant_id, task_id, title, weight_percentage, progress)
  VALUES (p_t, p_task, p_titre, p_poids, 0) RETURNING id INTO v;
  PERFORM _preuve800(p_t, v);
  IF p_taux > 0 THEN UPDATE task_actions SET progress = p_taux WHERE id = v; END IF;
  RETURN v;
END $$;

-- ============================================================ 800 — statuts
-- T01 — l'écran écrit « doing » / « canceled » / « completed » : la base range
-- son propre vocabulaire, que ses douze fonctions comparent.
DO $$
DECLARE t uuid; pr uuid; a uuid; b uuid; c uuid; sa text; sb text; sc text;
BEGIN
  SELECT out_tenant, out_projet INTO t, pr FROM _pj800('ST01');
  a := _t800(t, pr, 'A', NULL, NULL); b := _t800(t, pr, 'B', NULL, NULL); c := _t800(t, pr, 'C', NULL, NULL);
  UPDATE project_tasks SET status = 'doing' WHERE id = a;
  UPDATE project_tasks SET status = 'canceled' WHERE id = b;
  UPDATE project_tasks SET status = 'completed' WHERE id = c;
  SELECT status INTO sa FROM project_tasks WHERE id = a;
  SELECT status INTO sb FROM project_tasks WHERE id = b;
  SELECT status INTO sc FROM project_tasks WHERE id = c;
  PERFORM _rec('T01', 'doing/canceled/completed sont rangés in_progress/cancelled/done',
    sa = 'in_progress' AND sb = 'cancelled' AND sc = 'done', format('%s / %s / %s', sa, sb, sc));
END $$;

-- T02 — une sous-tâche annulée depuis l'écran compte comme close pour la mère.
DO $$
DECLARE t uuid; pr uuid; m uuid; s1 uuid; s2 uuid; n integer; d integer;
BEGIN
  SELECT out_tenant, out_projet INTO t, pr FROM _pj800('ST02');
  m := _t800(t, pr, 'Mère', NULL, NULL);
  s1 := _t800(t, pr, 'S1', NULL, NULL, m); s2 := _t800(t, pr, 'S2', NULL, NULL, m);
  UPDATE project_tasks SET status = 'canceled' WHERE id = s1;
  SELECT subtask_count, subtask_done_count INTO n, d FROM project_tasks WHERE id = m;
  PERFORM _rec('T02', 'une sous-tâche « canceled » compte parmi les closes', n = 2 AND d = 1,
    format('sous-tâches=%s closes=%s (2/1 attendus)', n, d));
END $$;

-- ============================================================ 800 — taux et progression
-- T03 — deux actions de même poids, l'une à 60 % : la tâche avance de 30 %.
DO $$
DECLARE t uuid; pr uuid; k uuid; p integer;
BEGIN
  SELECT out_tenant, out_projet INTO t, pr FROM _pj800('PR03');
  k := _t800(t, pr, 'Tâche', NULL, NULL);
  PERFORM _a800(t, k, 'A1', 50, 60);
  PERFORM _a800(t, k, 'A2', 50, 0);
  SELECT progress INTO p FROM project_tasks WHERE id = k;
  PERFORM _rec('T03', 'le taux d''une action fait avancer la tâche au prorata (50×60 % + 50×0 % → 30 %)',
    p = 30, format('progression=%s (30 attendus)', p));
END $$;

-- T04 — un taux de 100 coche l'action ; cocher donne 100 ; décocher donne 0.
DO $$
DECLARE t uuid; pr uuid; k uuid; a uuid; b uuid; ad boolean; bp integer; bp2 integer;
BEGIN
  SELECT out_tenant, out_projet INTO t, pr FROM _pj800('PR04');
  k := _t800(t, pr, 'Tâche', NULL, NULL);
  a := _a800(t, k, 'A', 50, 0); b := _a800(t, k, 'B', 50, 20);
  UPDATE task_actions SET progress = 100 WHERE id = a;
  UPDATE task_actions SET is_done = true WHERE id = b;
  SELECT is_done INTO ad FROM task_actions WHERE id = a;
  SELECT progress INTO bp FROM task_actions WHERE id = b;
  UPDATE task_actions SET is_done = false WHERE id = b;
  SELECT progress INTO bp2 FROM task_actions WHERE id = b;
  PERFORM _rec('T04', 'taux 100 ⇒ cochée ; cochée ⇒ 100 ; décochée ⇒ 0',
    ad AND bp = 100 AND bp2 = 0, format('A cochée=%s, B cochée→%s, décochée→%s', ad, bp, bp2));
END $$;

-- T05 — toutes les actions exécutées ⇒ la tâche est pleine, close, et le projet suit.
DO $$
DECLARE t uuid; pr uuid; k uuid; p integer; s text; pp integer;
BEGIN
  SELECT out_tenant, out_projet INTO t, pr FROM _pj800('PR05');
  k := _t800(t, pr, 'Seule tâche', NULL, NULL);
  PERFORM _a800(t, k, 'A', 30, 0); PERFORM _a800(t, k, 'B', 70, 0);
  UPDATE task_actions SET is_done = true WHERE task_id = k;
  SELECT progress, status INTO p, s FROM project_tasks WHERE id = k;
  SELECT progress INTO pp FROM projects WHERE id = pr;
  PERFORM _rec('T05', 'toutes les actions faites ⇒ tâche 100 % et close ⇒ projet 100 %',
    p = 100 AND s = 'done' AND pp = 100, format('tâche=%s %s, projet=%s', p, s, pp));
END $$;

-- T06 — une tâche avec actions ET sous-tâche : plus d'écrasement, une règle.
-- 1 action à 100 % + 1 sous-tâche à 0 % ⇒ (1×100 + 1×0) / 2 = 50 %.
DO $$
DECLARE t uuid; pr uuid; m uuid; s uuid; p integer; p2 integer;
BEGIN
  SELECT out_tenant, out_projet INTO t, pr FROM _pj800('PR06');
  m := _t800(t, pr, 'Mère', NULL, NULL);
  PERFORM _a800(t, m, 'A', 100, 100);
  s := _t800(t, pr, 'Sous-tâche', NULL, NULL, m);
  UPDATE project_tasks SET progress = 0 WHERE id = s;
  SELECT progress INTO p FROM project_tasks WHERE id = m;
  UPDATE project_tasks SET progress = 100 WHERE id = s;
  SELECT progress INTO p2 FROM project_tasks WHERE id = m;
  PERFORM _rec('T06', 'actions + sous-tâche : une seule règle (50 %, puis 100 % quand la sous-tâche finit)',
    p = 50 AND p2 = 100, format('mère=%s puis %s (50 puis 100 attendus)', p, p2));
END $$;

-- T07 — une sous-tâche LIÉE à une action donne son taux à l'action, et n'est
-- pas comptée deux fois.
DO $$
DECLARE t uuid; pr uuid; m uuid; a uuid; s uuid; ap integer; p integer;
BEGIN
  SELECT out_tenant, out_projet INTO t, pr FROM _pj800('PR07');
  m := _t800(t, pr, 'Mère', NULL, NULL);
  a := _a800(t, m, 'Livrer', 100, 0);
  s := _t800(t, pr, 'Réaliser la livraison', NULL, NULL, m);
  UPDATE project_tasks SET linked_action_id = a WHERE id = s;
  UPDATE project_tasks SET progress = 40 WHERE id = s;
  SELECT progress INTO ap FROM task_actions WHERE id = a;
  SELECT progress INTO p FROM project_tasks WHERE id = m;
  PERFORM _rec('T07', 'sous-tâche liée à 40 % ⇒ action à 40 % ⇒ mère à 40 % (pas de double compte)',
    ap = 40 AND p = 40, format('action=%s mère=%s (40/40 attendus)', ap, p));
END $$;

-- T08 — une sous-tâche annulée ne bloque plus le 100 % de la mère.
DO $$
DECLARE t uuid; pr uuid; m uuid; s1 uuid; s2 uuid; p integer;
BEGIN
  SELECT out_tenant, out_projet INTO t, pr FROM _pj800('PR08');
  m := _t800(t, pr, 'Mère', NULL, NULL);
  s1 := _t800(t, pr, 'Faite', NULL, NULL, m); s2 := _t800(t, pr, 'Abandonnée', NULL, NULL, m);
  UPDATE project_tasks SET progress = 100 WHERE id = s1;
  UPDATE project_tasks SET status = 'canceled' WHERE id = s2;
  SELECT progress INTO p FROM project_tasks WHERE id = m;
  PERFORM _rec('T08', 'faite + annulée ⇒ mère à 100 %', p = 100, format('mère=%s (100 attendus)', p));
END $$;

-- T09 — sans action ni sous-tâche, la progression saisie n'est pas écrasée.
DO $$
DECLARE t uuid; pr uuid; k uuid; a uuid; p integer;
BEGIN
  SELECT out_tenant, out_projet INTO t, pr FROM _pj800('PR09');
  k := _t800(t, pr, 'Saisie', NULL, NULL);
  UPDATE project_tasks SET progress = 35 WHERE id = k;
  a := _a800(t, _t800(t, pr, 'Autre', NULL, NULL), 'X', 10, 0);  -- une action ailleurs
  UPDATE task_actions SET progress = 50 WHERE id = a;
  SELECT progress INTO p FROM project_tasks WHERE id = k;
  PERFORM _rec('T09', 'une tâche sans élément garde sa progression saisie', p = 35, format('progression=%s (35)', p));
END $$;

-- ============================================================ 801 — bornes de dates
-- T10 — une sous-tâche ne sort pas de sa mère (début comme fin).
DO $$
DECLARE t uuid; pr uuid; m uuid; r1 boolean := false; r2 boolean := false; e text := '—';
BEGIN
  SELECT out_tenant, out_projet INTO t, pr FROM _pj800('BD10');
  m := _t800(t, pr, 'Mère', '2026-03-01', '2026-03-31');
  BEGIN PERFORM _t800(t, pr, 'Trop tôt', '2026-02-27', '2026-03-05', m);
  EXCEPTION WHEN OTHERS THEN r1 := true; e := SQLERRM; END;
  BEGIN PERFORM _t800(t, pr, 'Trop tard', '2026-03-20', '2026-04-02', m);
  EXCEPTION WHEN OTHERS THEN r2 := true; END;
  PERFORM _rec('T10', 'une sous-tâche hors de la période de sa mère est refusée', r1 AND r2,
    format('début refusé=%s fin refusée=%s | %s', r1, r2, left(e, 90)));
END $$;

-- T11 — une tâche ne sort pas de son projet ; l'échéance d'une action ne sort
-- pas de sa tâche.
DO $$
DECLARE t uuid; pr uuid; k uuid; r1 boolean := false; r2 boolean := false;
BEGIN
  SELECT out_tenant, out_projet INTO t, pr FROM _pj800('BD11', '2026-01-01', '2026-06-30');
  BEGIN PERFORM _t800(t, pr, 'Hors projet', '2026-06-01', '2026-07-15');
  EXCEPTION WHEN OTHERS THEN r1 := true; END;
  k := _t800(t, pr, 'Dans le projet', '2026-02-01', '2026-02-28');
  BEGIN INSERT INTO task_actions (tenant_id, task_id, title, weight_percentage, due_date)
        VALUES (t, k, 'Trop tard', 10, '2026-03-05');
  EXCEPTION WHEN OTHERS THEN r2 := true; END;
  PERFORM _rec('T11', 'tâche hors projet et action hors tâche refusées', r1 AND r2,
    format('tâche refusée=%s action refusée=%s', r1, r2));
END $$;

-- T12 — déplacer une mère de 5 jours emmène ses sous-tâches et ses actions.
DO $$
DECLARE t uuid; pr uuid; m uuid; s uuid; a uuid; sd date; se date; ad date;
BEGIN
  SELECT out_tenant, out_projet INTO t, pr FROM _pj800('BD12', '2026-01-01', '2026-12-31');
  m := _t800(t, pr, 'Mère', '2026-03-01', '2026-03-31');
  s := _t800(t, pr, 'Fille', '2026-03-10', '2026-03-20', m);
  INSERT INTO task_actions (tenant_id, task_id, title, weight_percentage, due_date)
  VALUES (t, m, 'Jalon', 10, '2026-03-31') RETURNING id INTO a;
  UPDATE project_tasks SET start_date = '2026-03-06', due_date = '2026-04-05' WHERE id = m;
  SELECT start_date, due_date INTO sd, se FROM project_tasks WHERE id = s;
  SELECT due_date INTO ad FROM task_actions WHERE id = a;
  PERFORM _rec('T12', 'mère déplacée de +5 j ⇒ sous-tâche et action déplacées de +5 j',
    sd = '2026-03-15' AND se = '2026-03-25' AND ad = '2026-04-05',
    format('fille %s→%s, action %s', sd, se, ad));
END $$;

-- T13 — raccourcir une mère qui couperait sa fille est refusé (rien n'est tronqué).
DO $$
DECLARE t uuid; pr uuid; m uuid; refuse boolean := false; fin date;
BEGIN
  SELECT out_tenant, out_projet INTO t, pr FROM _pj800('BD13');
  m := _t800(t, pr, 'Mère', '2026-03-01', '2026-03-31');
  PERFORM _t800(t, pr, 'Fille', '2026-03-20', '2026-03-30', m);
  BEGIN UPDATE project_tasks SET due_date = '2026-03-25' WHERE id = m;
  EXCEPTION WHEN OTHERS THEN refuse := true; END;
  SELECT due_date INTO fin FROM project_tasks WHERE id = m;
  PERFORM _rec('T13', 'raccourcir une mère qui couperait une sous-tâche est refusé',
    refuse AND fin = '2026-03-31', format('refus=%s fin=%s', refuse, fin));
END $$;

-- T14 — déplacer un projet emmène ses tâches ET leurs sous-tâches ; le
-- raccourcir sous une tâche est refusé.
DO $$
DECLARE t uuid; pr uuid; k uuid; s uuid; kd date; sd date; refuse boolean := false;
BEGIN
  SELECT out_tenant, out_projet INTO t, pr FROM _pj800('BD14', '2026-01-01', '2026-01-31');
  k := _t800(t, pr, 'Tâche', '2026-01-10', '2026-01-20');
  s := _t800(t, pr, 'Sous-tâche', '2026-01-12', '2026-01-15', k);
  UPDATE projects SET start_date = '2026-01-11', end_date = '2026-02-10' WHERE id = pr;
  SELECT start_date INTO kd FROM project_tasks WHERE id = k;
  SELECT start_date INTO sd FROM project_tasks WHERE id = s;
  BEGIN UPDATE projects SET end_date = '2026-01-25' WHERE id = pr;
  EXCEPTION WHEN OTHERS THEN refuse := true; END;
  PERFORM _rec('T14', 'projet +10 j ⇒ tâche et sous-tâche +10 j ; raccourcir sous une tâche refusé',
    kd = '2026-01-20' AND sd = '2026-01-22' AND refuse, format('tâche=%s sous-tâche=%s refus=%s', kd, sd, refuse));
END $$;

-- ============================================================ 802 — dépendances
-- T15 — créer « B après A » quand B chevauche A : B est reporté au lendemain de
-- la fin de A, durée conservée.
DO $$
DECLARE t uuid; pr uuid; a uuid; b uuid; bs date; be date;
BEGIN
  SELECT out_tenant, out_projet INTO t, pr FROM _pj800('DP15');
  a := _t800(t, pr, 'A', '2026-05-01', '2026-05-10');
  b := _t800(t, pr, 'B', '2026-05-05', '2026-05-08');
  INSERT INTO project_task_dependencies (tenant_id, task_id, depends_on_task_id) VALUES (t, b, a);
  SELECT start_date, due_date INTO bs, be FROM project_tasks WHERE id = b;
  PERFORM _rec('T15', 'un lien créé reporte B au lendemain de la fin de A (durée gardée)',
    bs = '2026-05-11' AND be = '2026-05-14', format('B %s→%s (11→14 attendus)', bs, be));
END $$;

-- T16 — A s'allonge de 3 jours : B, sa sous-tâche, et C (qui attend B) suivent.
DO $$
DECLARE t uuid; pr uuid; a uuid; b uuid; bb uuid; c uuid; bs date; bbs date; cs date;
BEGIN
  SELECT out_tenant, out_projet INTO t, pr FROM _pj800('DP16');
  a := _t800(t, pr, 'A', '2026-05-01', '2026-05-10');
  b := _t800(t, pr, 'B', '2026-05-11', '2026-05-20');
  bb := _t800(t, pr, 'B.1', '2026-05-12', '2026-05-14', b);
  c := _t800(t, pr, 'C', '2026-05-21', '2026-05-25');
  INSERT INTO project_task_dependencies (tenant_id, task_id, depends_on_task_id) VALUES (t, b, a), (t, c, b);
  UPDATE project_tasks SET due_date = '2026-05-13' WHERE id = a;
  SELECT start_date INTO bs FROM project_tasks WHERE id = b;
  SELECT start_date INTO bbs FROM project_tasks WHERE id = bb;
  SELECT start_date INTO cs FROM project_tasks WHERE id = c;
  PERFORM _rec('T16', 'A +3 j ⇒ B, sa sous-tâche et C reportés de +3 j, en cascade',
    bs = '2026-05-14' AND bbs = '2026-05-15' AND cs = '2026-05-24', format('B=%s B.1=%s C=%s', bs, bbs, cs));
END $$;

-- T17 — placer B avant la fin de A est refusé ; reculer A ne tire pas B.
DO $$
DECLARE t uuid; pr uuid; a uuid; b uuid; refuse boolean := false; bs date;
BEGIN
  SELECT out_tenant, out_projet INTO t, pr FROM _pj800('DP17');
  a := _t800(t, pr, 'A', '2026-05-01', '2026-05-10');
  b := _t800(t, pr, 'B', '2026-05-11', '2026-05-15');
  INSERT INTO project_task_dependencies (tenant_id, task_id, depends_on_task_id) VALUES (t, b, a);
  BEGIN UPDATE project_tasks SET start_date = '2026-05-08', due_date = '2026-05-12' WHERE id = b;
  EXCEPTION WHEN OTHERS THEN refuse := true; END;
  UPDATE project_tasks SET start_date = '2026-04-25', due_date = '2026-05-04' WHERE id = a;
  SELECT start_date INTO bs FROM project_tasks WHERE id = b;
  PERFORM _rec('T17', 'B avant la fin de A refusé ; A reculé ne déplace pas B',
    refuse AND bs = '2026-05-11', format('refus=%s B=%s', refuse, bs));
END $$;

-- T18 — liens absurdes refusés : soi-même, doublon, boucle, mère/fille.
DO $$
DECLARE t uuid; pr uuid; a uuid; b uuid; c uuid; m uuid; f uuid;
        r_self boolean := false; r_dup boolean := false; r_loop boolean := false; r_fam boolean := false;
BEGIN
  SELECT out_tenant, out_projet INTO t, pr FROM _pj800('DP18');
  a := _t800(t, pr, 'A', '2026-05-01', '2026-05-02');
  b := _t800(t, pr, 'B', '2026-05-03', '2026-05-04');
  c := _t800(t, pr, 'C', '2026-05-05', '2026-05-06');
  m := _t800(t, pr, 'Mère', '2026-06-01', '2026-06-30');
  f := _t800(t, pr, 'Fille', '2026-06-02', '2026-06-03', m);
  INSERT INTO project_task_dependencies (tenant_id, task_id, depends_on_task_id) VALUES (t, b, a), (t, c, b);
  BEGIN INSERT INTO project_task_dependencies (tenant_id, task_id, depends_on_task_id) VALUES (t, a, a);
  EXCEPTION WHEN OTHERS THEN r_self := true; END;
  BEGIN INSERT INTO project_task_dependencies (tenant_id, task_id, depends_on_task_id) VALUES (t, b, a);
  EXCEPTION WHEN OTHERS THEN r_dup := true; END;
  BEGIN INSERT INTO project_task_dependencies (tenant_id, task_id, depends_on_task_id) VALUES (t, a, c);
  EXCEPTION WHEN OTHERS THEN r_loop := true; END;
  BEGIN INSERT INTO project_task_dependencies (tenant_id, task_id, depends_on_task_id) VALUES (t, f, m);
  EXCEPTION WHEN OTHERS THEN r_fam := true; END;
  PERFORM _rec('T18', 'lien réflexif, en double, en boucle (A→B→C→A) ou mère→fille refusé',
    r_self AND r_dup AND r_loop AND r_fam,
    format('soi=%s doublon=%s boucle=%s famille=%s', r_self, r_dup, r_loop, r_fam));
END $$;

-- T19 — un report qui sortirait B de sa mère est refusé, et RIEN ne bouge.
DO $$
DECLARE t uuid; pr uuid; m uuid; a uuid; b uuid; refuse boolean := false; ae date; bs date;
BEGIN
  SELECT out_tenant, out_projet INTO t, pr FROM _pj800('DP19');
  m := _t800(t, pr, 'Mère', '2026-05-01', '2026-05-31');
  a := _t800(t, pr, 'A', '2026-05-01', '2026-05-10', m);
  b := _t800(t, pr, 'B', '2026-05-11', '2026-05-25', m);
  INSERT INTO project_task_dependencies (tenant_id, task_id, depends_on_task_id) VALUES (t, b, a);
  BEGIN UPDATE project_tasks SET due_date = '2026-05-20' WHERE id = a;
  EXCEPTION WHEN OTHERS THEN refuse := true; END;
  SELECT due_date INTO ae FROM project_tasks WHERE id = a;
  SELECT start_date INTO bs FROM project_tasks WHERE id = b;
  PERFORM _rec('T19', 'un report qui sortirait B de sa mère est refusé, A et B restent en place',
    refuse AND ae = '2026-05-10' AND bs = '2026-05-11', format('refus=%s A fin=%s B début=%s', refuse, ae, bs));
END $$;

-- T20 — entre projets : le lien reporte le projet successeur, ses tâches suivent ;
-- une boucle est refusée.
DO $$
DECLARE t uuid; p1 uuid; p2 uuid; k uuid; p2s date; ks date; refuse boolean := false;
BEGIN
  SELECT out_tenant, out_projet INTO t, p1 FROM _pj800('DP20', '2026-01-01', '2026-01-31');
  INSERT INTO projects (tenant_id, name, status, start_date, end_date)
  VALUES (t, 'Phase 2', 'active', '2026-01-20', '2026-02-20') RETURNING id INTO p2;
  k := _t800(t, p2, 'Tâche de phase 2', '2026-01-20', '2026-01-25');
  INSERT INTO project_dependencies (tenant_id, project_id, depends_on_project_id) VALUES (t, p2, p1);
  SELECT start_date INTO p2s FROM projects WHERE id = p2;
  SELECT start_date INTO ks FROM project_tasks WHERE id = k;
  BEGIN INSERT INTO project_dependencies (tenant_id, project_id, depends_on_project_id) VALUES (t, p1, p2);
  EXCEPTION WHEN OTHERS THEN refuse := true; END;
  PERFORM _rec('T20', 'projet 2 après projet 1 : reporté au 01/02 avec ses tâches ; boucle refusée',
    p2s = '2026-02-01' AND ks = '2026-02-01' AND refuse, format('projet 2=%s tâche=%s boucle refusée=%s', p2s, ks, refuse));
END $$;

-- T21 — la nouvelle table est cloisonnée comme les autres (RLS activée et forcée).
DO $$
DECLARE rls boolean; forced boolean; pol integer;
BEGIN
  SELECT relrowsecurity, relforcerowsecurity INTO rls, forced FROM pg_class WHERE oid = 'public.project_dependencies'::regclass;
  SELECT count(*) INTO pol FROM pg_policies WHERE tablename = 'project_dependencies';
  PERFORM _rec('T21', 'project_dependencies : RLS activée, forcée, 4 politiques de société',
    rls AND forced AND pol = 4, format('rls=%s forcée=%s politiques=%s', rls, forced, pol));
END $$;

-- ============================================================ 803 — preuve obligatoire
-- T23 — cocher une action sans document est refusé ; avec un document, accepté.
DO $$
DECLARE t uuid; pr uuid; k uuid; a uuid; refuse boolean := false; err text := '—'; fait boolean;
BEGIN
  SELECT out_tenant, out_projet INTO t, pr FROM _pj800('PV23');
  k := _t800(t, pr, 'Tâche', NULL, NULL);
  INSERT INTO task_actions (tenant_id, task_id, title, weight_percentage) VALUES (t, k, 'Signer', 100) RETURNING id INTO a;
  BEGIN UPDATE task_actions SET is_done = true WHERE id = a;
  EXCEPTION WHEN OTHERS THEN refuse := true; err := SQLERRM; END;
  PERFORM _preuve800(t, a);
  UPDATE task_actions SET is_done = true WHERE id = a;
  SELECT is_done INTO fait FROM task_actions WHERE id = a;
  PERFORM _rec('T23', 'sans document : coche refusée ; avec document : coche acceptée',
    refuse AND fait, format('refus=%s cochée ensuite=%s | %s', refuse, fait, left(err, 80)));
END $$;

-- T24 — le taux à 100 compte comme une coche ; créer une action déjà cochée est
-- refusé ; décocher reste libre.
DO $$
DECLARE t uuid; pr uuid; k uuid; a uuid; r_taux boolean := false; r_creee boolean := false; libre boolean;
BEGIN
  SELECT out_tenant, out_projet INTO t, pr FROM _pj800('PV24');
  k := _t800(t, pr, 'Tâche', NULL, NULL);
  INSERT INTO task_actions (tenant_id, task_id, title, weight_percentage) VALUES (t, k, 'Livrer', 100) RETURNING id INTO a;
  BEGIN UPDATE task_actions SET progress = 100 WHERE id = a;
  EXCEPTION WHEN OTHERS THEN r_taux := true; END;
  BEGIN INSERT INTO task_actions (tenant_id, task_id, title, weight_percentage, is_done) VALUES (t, k, 'Déjà faite', 10, true);
  EXCEPTION WHEN OTHERS THEN r_creee := true; END;
  PERFORM _preuve800(t, a);
  UPDATE task_actions SET is_done = true WHERE id = a;
  UPDATE task_actions SET is_done = false WHERE id = a;
  SELECT NOT is_done INTO libre FROM task_actions WHERE id = a;
  PERFORM _rec('T24', 'taux 100 sans preuve refusé, action créée cochée refusée, décocher libre',
    r_taux AND r_creee AND libre, format('taux=%s créée=%s décochée=%s', r_taux, r_creee, libre));
END $$;

-- T25 — l'achèvement PROPAGÉ (sous-tâche liée à 100 %) n'est pas un geste de
-- l'utilisateur : il coche l'action sans preuve, et la mère avance.
DO $$
DECLARE t uuid; pr uuid; m uuid; a uuid; s uuid; fait boolean; p integer;
BEGIN
  SELECT out_tenant, out_projet INTO t, pr FROM _pj800('PV25');
  m := _t800(t, pr, 'Mère', NULL, NULL);
  INSERT INTO task_actions (tenant_id, task_id, title, weight_percentage) VALUES (t, m, 'Livrer', 100) RETURNING id INTO a;
  s := _t800(t, pr, 'Réaliser', NULL, NULL, m);
  UPDATE project_tasks SET linked_action_id = a WHERE id = s;
  UPDATE project_tasks SET progress = 100 WHERE id = s;
  SELECT is_done INTO fait FROM task_actions WHERE id = a;
  SELECT progress INTO p FROM project_tasks WHERE id = m;
  PERFORM _rec('T25', 'sous-tâche liée à 100 % : l''action se coche sans preuve, la mère passe à 100 %',
    fait AND p = 100, format('action cochée=%s mère=%s', fait, p));
END $$;

-- ============================================================ 804 — le statut suit l'avancement
-- T26 — 0 % → à faire, 50 % → en cours, 100 % → terminé, retour à 0 % → à faire ;
-- un statut posé à la main (bloqué) n'est pas écrasé.
DO $$
DECLARE t uuid; pr uuid; k uuid; b uuid; a1 uuid; a2 uuid; s0 text; s50 text; s100 text; sback text; sbloq text;
BEGIN
  SELECT out_tenant, out_projet INTO t, pr FROM _pj800('ST26');
  k := _t800(t, pr, 'Tâche', NULL, NULL);
  a1 := _a800(t, k, 'A', 50, 0); a2 := _a800(t, k, 'B', 50, 0);
  SELECT status INTO s0 FROM project_tasks WHERE id = k;
  UPDATE task_actions SET is_done = true WHERE id = a1;
  SELECT status INTO s50 FROM project_tasks WHERE id = k;
  UPDATE task_actions SET is_done = true WHERE id = a2;
  SELECT status INTO s100 FROM project_tasks WHERE id = k;
  UPDATE task_actions SET is_done = false WHERE task_id = k;
  SELECT status INTO sback FROM project_tasks WHERE id = k;
  b := _t800(t, pr, 'Bloquée', NULL, NULL);
  UPDATE project_tasks SET status = 'blocked' WHERE id = b;
  PERFORM _a800(t, b, 'X', 100, 0);
  UPDATE task_actions SET progress = 40 WHERE task_id = b;
  SELECT status INTO sbloq FROM project_tasks WHERE id = b;
  PERFORM _rec('T26', 'statut : todo → in_progress → done → todo selon l''avancement ; « bloqué » reste bloqué',
    s0 = 'todo' AND s50 = 'in_progress' AND s100 = 'done' AND sback = 'todo' AND sbloq = 'blocked',
    format('0%%=%s 50%%=%s 100%%=%s retour=%s bloquée=%s', s0, s50, s100, sback, sbloq));
END $$;

-- T22 — LE CHEMIN DE L'ÉCRAN : le même déplacement, joué en `authenticated`
-- (sous RLS, avec les droits d'un utilisateur). Les contrôles de dates s'exécutent
-- avec SES droits : mesuré sur Supabase local le 24/10, ils appelaient deux calculs
-- dont le droit d'exécution lui avait été retiré — tout déplacement depuis l'écran
-- était refusé (42501), alors que T12 à T19, joués en superutilisateur, étaient verts.
--
-- ⚠️ Deux sessions, et ce n'est pas un détail : PL/pgSQL vérifie le droit
-- d'exécuter une fonction quand il PRÉPARE l'expression, une fois par session.
-- Si un déclencheur a déjà tourné en superutilisateur dans la session (ne
-- serait-ce que les INSERT de préparation), le droit n'est plus revérifié et le
-- scénario reste vert sans lui (mesuré : vert avec le droit retiré). La
-- préparation se fait donc ici, le déplacement dans une session NEUVE.
DROP TABLE IF EXISTS _ctx800;
CREATE TABLE _ctx800 (t uuid, auth uuid, a uuid, f uuid, b uuid);
DO $$
DECLARE t uuid; pr uuid; a uuid; b uuid; f uuid;
BEGIN
  SELECT out_tenant, out_projet INTO t, pr FROM _pj800('RL22', '2026-01-01', '2026-12-31');
  a := _t800(t, pr, 'A', '2026-05-01', '2026-05-10');
  f := _t800(t, pr, 'A.1', '2026-05-02', '2026-05-05', a);
  b := _t800(t, pr, 'B', '2026-05-11', '2026-05-20');
  INSERT INTO project_task_dependencies (tenant_id, task_id, depends_on_task_id) VALUES (t, b, a);
  INSERT INTO _ctx800 SELECT t, (SELECT auth_id FROM tenant_users WHERE tenant_id = t LIMIT 1), a, f, b;
END $$;

\connect
SELECT set_config('audit.file', '800', false);
SELECT t AS ctx_t, auth AS ctx_auth, a AS ctx_a FROM _ctx800 \gset
SELECT set_config('request.jwt.claim.sub', :'ctx_auth', false);
SELECT set_config('request.jwt.claims', json_build_object('sub', :'ctx_auth', 'role', 'authenticated')::text, false);
SELECT set_active_tenant(:'ctx_t');
SELECT set_config('t800.a', :'ctx_a', false);
SET ROLE authenticated;
DO $$
BEGIN
  UPDATE project_tasks SET start_date = '2026-05-04', due_date = '2026-05-13'
   WHERE id = current_setting('t800.a')::uuid;
  PERFORM set_config('t800.err', '', false);
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('t800.err', SQLERRM, false);
END $$;
RESET ROLE;

DO $$
DECLARE c record; err text := current_setting('t800.err', true); bs date; fs date;
BEGIN
  SELECT * INTO c FROM _ctx800;
  SELECT start_date INTO fs FROM project_tasks WHERE id = c.f;
  SELECT start_date INTO bs FROM project_tasks WHERE id = c.b;
  PERFORM _rec('T22', 'en authenticated, session neuve : déplacer A emmène sa sous-tâche et reporte B (le chemin de l''écran)',
    coalesce(err, '') = '' AND fs = '2026-05-05' AND bs = '2026-05-14',
    format('erreur=%s A.1=%s B=%s', coalesce(nullif(err, ''), '—'), fs, bs));
END $$;
DROP TABLE _ctx800;

DROP FUNCTION _a800(uuid, uuid, text, integer, integer);
DROP FUNCTION _preuve800(uuid, uuid);
DROP FUNCTION _t800(uuid, uuid, text, date, date, uuid, numeric);
DROP FUNCTION _pj800(text, date, date);
SELECT _audit_assert('800');
