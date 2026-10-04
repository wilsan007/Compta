-- ============================================================
-- 303_project_progress_and_cycle_tests.sql — W8 (M-17) :
-- avancement pondéré (un seul calcul) et anti-cycle des tâches
--
--   PROJ-02 🟠 `recalc_project_progress_on_task_change` fait la **moyenne non
--             pondérée** des tâches de premier niveau — une tâche d'une heure
--             pèse autant qu'une de cent jours — et
--             `recalc_parent_progress_on_subtask_change` calcule l'avancement
--             d'un parent avec **la même moyenne non pondérée**, sans référence
--             commune : deux calculs concurrents pour une même grandeur.
--   PROJ-03 🟠 Rien n'empêche une tâche d'être **son propre parent**, ni une
--             chaîne A → B → A. Treize déclencheurs se réécrivent en cascade sur
--             `project_tasks` : un cycle produit une remontée sans garde.
--
-- Les scénarios mesurent l'avancement **attendu** (10 %, pas 50 %) et le refus
-- des cycles. T03 et T06 sont des non-régressions (hiérarchie légitime, remontée
-- vers le parent et le projet).
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '303', false);
DELETE FROM _audit_results WHERE file = '303';

DROP FUNCTION IF EXISTS _proj303(text);
CREATE OR REPLACE FUNCTION _proj303(p_nom text, OUT out_tenant uuid, OUT out_projet uuid)
LANGUAGE plpgsql AS $$
BEGIN
  out_tenant := _mk_tenant(p_nom);
  INSERT INTO projects (tenant_id, name, status) VALUES (out_tenant, 'Projet ' || p_nom, 'active')
    RETURNING id INTO out_projet;
END $$;

DROP FUNCTION IF EXISTS _tache303(uuid, uuid, text, numeric, integer, uuid);
CREATE OR REPLACE FUNCTION _tache303(p_t uuid, p_pr uuid, p_titre text,
  p_effort numeric, p_progress integer, p_parent uuid DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v uuid;
BEGIN
  INSERT INTO project_tasks (tenant_id, project_id, title, status, effort_estimate_h, progress, parent_id)
  VALUES (p_t, p_pr, p_titre, 'in_progress', p_effort, p_progress, p_parent)
  RETURNING id INTO v;
  RETURN v;
END $$;

-- T01 — PROJ-03 : une tâche ne peut pas être son propre parent.
DO $$
DECLARE t uuid; pr uuid; v_id uuid := uuid_generate_v4();
        refuse boolean := false; err text := '—';
BEGIN
  SELECT out_tenant, out_projet INTO t, pr FROM _proj303('PJ01');
  BEGIN
    INSERT INTO project_tasks (id, tenant_id, project_id, title, status, parent_id)
    VALUES (v_id, t, pr, 'Auto-parent', 'todo', v_id);
  EXCEPTION WHEN OTHERS THEN refuse := true; err := SQLERRM;
  END;
  PERFORM _rec('T01', 'une tâche ne peut pas être son propre parent',
    refuse AND err NOT LIKE '%stack depth%',
    format('refus=%s | %s', refuse, left(err, 100)));
END $$;

-- T02 — PROJ-03 : A → B puis B → A est refusé (le cycle n'entre pas en base).
DO $$
DECLARE t uuid; pr uuid; a uuid; b uuid;
        refuse boolean := false; err text := '—'; parent_apres uuid;
BEGIN
  SELECT out_tenant, out_projet INTO t, pr FROM _proj303('PJ02');
  a := _tache303(t, pr, 'A', 1, 0);
  b := _tache303(t, pr, 'B', 1, 0, a);
  BEGIN
    UPDATE project_tasks SET parent_id = b WHERE id = a;
  EXCEPTION WHEN OTHERS THEN refuse := true; err := SQLERRM;
  END;
  SELECT parent_id INTO parent_apres FROM project_tasks WHERE id = a;
  PERFORM _rec('T02', 'un cycle de tâches (A → B → A) est refusé, la hiérarchie reste saine',
    refuse AND parent_apres IS NULL,
    format('refus=%s ; parent de A après=%s (NULL attendu) | %s', refuse, parent_apres, left(err, 90)));
END $$;

-- T03 — non-régression : une hiérarchie légitime fonctionne (3 niveaux).
DO $$
DECLARE t uuid; pr uuid; t1 uuid; t2 uuid; t3 uuid; p2 integer; p3 integer;
BEGIN
  SELECT out_tenant, out_projet INTO t, pr FROM _proj303('PJ03');
  t1 := _tache303(t, pr, 'Niveau 1', 10, 0);
  t2 := _tache303(t, pr, 'Niveau 2', 10, 0, t1);
  t3 := _tache303(t, pr, 'Niveau 3', 10, 0, t2);
  UPDATE project_tasks SET progress = 60 WHERE id = t3;
  SELECT progress INTO p2 FROM project_tasks WHERE id = t2;
  SELECT progress INTO p3 FROM project_tasks WHERE id = t1;
  PERFORM _rec('T03', 'une hiérarchie légitime remonte : 60 % au niveau 3 → 60 % au niveau 2 → 60 % au niveau 1',
    p2 = 60 AND p3 = 60, format('niveau 2=%s niveau 1=%s (60 attendus)', p2, p3));
END $$;

-- T04 — PROJ-02 : l'avancement du parent est **pondéré** par les heures prévues.
-- Une sous-tâche de 10 h à 100 % et une de 90 h à 0 % font 10 %, pas 50 %.
DO $$
DECLARE t uuid; pr uuid; parent uuid; c1 uuid; c2 uuid; p integer; n int; d int; h numeric;
BEGIN
  SELECT out_tenant, out_projet INTO t, pr FROM _proj303('PJ04');
  parent := _tache303(t, pr, 'Lot parent', 100, 0);
  c1 := _tache303(t, pr, 'Petite tâche (10 h)', 10, 100, parent);
  c2 := _tache303(t, pr, 'Grosse tâche (90 h)', 90, 0, parent);
  SELECT progress, subtask_count, subtask_done_count, subtask_effective_hours
    INTO p, n, d, h FROM project_tasks WHERE id = parent;
  PERFORM _rec('T04', 'avancement du parent pondéré par les heures prévues : 10 % (et non 50 %)',
    p = 10 AND n = 2 AND d = 1,
    format('avancement du parent=%s (10 attendu, moyenne simple=50) ; sous-tâches=%s dont terminées=%s', p, n, d));
END $$;

-- T05 — PROJ-02 : le projet suit **la même règle** que le parent. Deux tâches de
-- premier niveau, 10 h à 100 % et 90 h à 0 % → projet 10 %.
DO $$
DECLARE t uuid; pr uuid; a uuid; b uuid; p integer;
BEGIN
  SELECT out_tenant, out_projet INTO t, pr FROM _proj303('PJ05');
  a := _tache303(t, pr, 'Petite tâche (10 h)', 10, 100);
  b := _tache303(t, pr, 'Grosse tâche (90 h)', 90, 0);
  SELECT progress INTO p FROM projects WHERE id = pr;
  PERFORM _rec('T05', 'avancement du projet pondéré par les heures : 10 % (même règle que le parent)',
    p = 10, format('avancement du projet=%s (10 attendu, moyenne simple=50)', p));
END $$;

-- T06 — non-régression : une modification profonde remonte au parent **et** au
-- projet dans le même geste.
DO $$
DECLARE t uuid; pr uuid; parent uuid; enfant uuid; pp integer; pj integer;
BEGIN
  SELECT out_tenant, out_projet INTO t, pr FROM _proj303('PJ06');
  parent := _tache303(t, pr, 'Tâche unique', 10, 0);
  enfant := _tache303(t, pr, 'Sous-tâche', 10, 0, parent);
  UPDATE project_tasks SET progress = 75 WHERE id = enfant;
  SELECT progress INTO pp FROM project_tasks WHERE id = parent;
  SELECT progress INTO pj FROM projects WHERE id = pr;
  PERFORM _rec('T06', 'une sous-tâche à 75 % remonte au parent et au projet',
    pp = 75 AND pj = 75, format('parent=%s projet=%s (75 attendus)', pp, pj));
END $$;

DROP FUNCTION _tache303(uuid, uuid, text, numeric, integer, uuid);
DROP FUNCTION _proj303(text);
SELECT _audit_assert('303');

