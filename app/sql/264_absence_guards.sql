-- ============================================================
-- 264_absence_guards.sql — W9 : les gardes en aval et le contrôle quotidien
--                           (TRV-03 → TRV-10, TRV-16)
--
-- MESURÉ AVANT, sur base neuve (229 migrations, après la 263) :
--   TRV-03  un salarié en congé pouvait pointer ses heures du jour : le
--           déclencheur `calculate_lateness` calculait, rien ne regardait
--           l'absence ;
--   TRV-04  les heures supplémentaires du même jour étaient calculées et
--           approuvées, donc versées ;
--   TRV-05  du temps projet pouvait être saisi un jour d'absence — et ce
--           temps finit FACTURÉ au client ;
--   TRV-06  `expense_report_lines.date` n'était confrontée à rien : frais
--           remboursés pour une journée de congé sans solde ;
--   TRV-07  une tâche pouvait être assignée à un salarié absent ;
--   TRV-08  l'absent pouvait clore lui-même sa tâche ;
--   TRV-09  le temps facturable d'un absent n'était filtré par personne ;
--   TRV-16  aucun filet : une donnée saisie avant la mise en place du
--           registre (ou par un chemin détourné) ne se voyait nulle part.
--
-- La 263 a posé la vérité ; la 264 la rend OPPOSABLE. Chaque refus est une
-- exception RÉDIGÉE (elle nomme le type d'absence, la date et le module), donc
-- lisible par l'écran — jamais un silence.
-- ============================================================

-- ============================================================
-- 1. TRV-10 — la ligne de frais d'une mission porte la mission
-- ============================================================
-- Le plan écrit « `mission_absence_id` ». La clé d'une journée d'absence est
-- `(société, salarié, jour)` : un identifiant seul ne l'identifierait pas.
-- Deux colonnes et une clé composite disent la même chose **sans ambiguïté**,
-- et la ligne de frais reste rattachable à la mission qui l'autorise.
ALTER TABLE public.expense_report_lines
  ADD COLUMN IF NOT EXISTS mission_absence_day date,
  ADD COLUMN IF NOT EXISTS mission_absence_employee_id uuid;

ALTER TABLE public.expense_report_lines
  DROP CONSTRAINT IF EXISTS expense_report_lines_mission_fkey;
ALTER TABLE public.expense_report_lines
  ADD CONSTRAINT expense_report_lines_mission_fkey
  FOREIGN KEY (tenant_id, mission_absence_employee_id, mission_absence_day)
  REFERENCES public.employee_absence_days (tenant_id, employee_id, day)
  ON DELETE SET NULL (mission_absence_employee_id, mission_absence_day);

COMMENT ON COLUMN public.expense_report_lines.mission_absence_day IS
  'W9 / TRV-10 — si la ligne est portée par une MISSION, le jour d''absence correspondant. La preuve que la dépense était autorisée.';

CREATE INDEX IF NOT EXISTS idx_expense_report_lines_mission
  ON public.expense_report_lines (tenant_id, mission_absence_employee_id, mission_absence_day);

-- ============================================================
-- 2. TRV-03 / TRV-04 — le pointage d'un absent est refusé
-- ============================================================
-- « Une ligne qui déclare l'absence n'est pas un pointage de travail » : c'est
-- la distinction qui rend la quatrième source possible sans se bloquer elle-même.
CREATE OR REPLACE FUNCTION public.guard_timesheet_on_absence()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.employee_id IS NULL OR NEW.date IS NULL THEN RETURN NEW; END IF;
  -- La ligne qui PORTE l'absence est légitime.
  IF COALESCE(NEW.absence_type, 'none') <> 'none' THEN RETURN NEW; END IF;
  -- Une ligne sans travail n'est pas un pointage à refuser.
  IF COALESCE(NEW.hours, 0) <= 0 AND NEW.arrival_time IS NULL
     AND NEW.departure_time IS NULL AND COALESCE(NEW.overtime_minutes, 0) <= 0 THEN
    RETURN NEW;
  END IF;
  PERFORM assert_not_absent(NEW.employee_id, NEW.date, 'pointage');
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS guard_timesheet_on_absence ON public.timesheets;
CREATE TRIGGER guard_timesheet_on_absence
  BEFORE INSERT OR UPDATE OF hours, arrival_time, departure_time, overtime_minutes,
                             date, employee_id, absence_type
  ON public.timesheets
  FOR EACH ROW EXECUTE FUNCTION public.guard_timesheet_on_absence();

-- TRV-04, la suite : même saisi avant l'absence, un pointage de travail ne peut
-- pas être APPROUVÉ un jour d'absence bloquante. Sans cette garde, la ligne
-- préexistante rejouerait la paie (`sync_timesheet_to_payroll` en lisant
-- `overtime_minutes`), et les heures supplémentaires seraient versées.
CREATE OR REPLACE FUNCTION public.guard_timesheet_approval_on_absence()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.status = 'approved' AND OLD.status IS DISTINCT FROM 'approved'
     AND COALESCE(NEW.absence_type, 'none') = 'none'
     AND (COALESCE(NEW.hours, 0) > 0 OR COALESCE(NEW.overtime_minutes, 0) > 0) THEN
    PERFORM assert_not_absent(NEW.employee_id, NEW.date, 'approbation du pointage');
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS guard_timesheet_approval_on_absence ON public.timesheets;
CREATE TRIGGER guard_timesheet_approval_on_absence
  BEFORE UPDATE OF status ON public.timesheets
  FOR EACH ROW EXECUTE FUNCTION public.guard_timesheet_approval_on_absence();

-- ============================================================
-- 3. TRV-05 — le temps projet d'un absent est refusé
-- ============================================================
-- C'est le chemin le plus coûteux : ce temps peut finir sur une facture
-- (TRV-09) et alimenter le chiffre d'affaires avec des heures non travaillées.
CREATE OR REPLACE FUNCTION public.guard_project_time_on_absence()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.employee_id IS NULL THEN RETURN NEW; END IF;
  PERFORM assert_not_absent(NEW.employee_id, COALESCE(NEW.start_time::date, CURRENT_DATE),
                            'temps projet');
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS guard_project_time_on_absence ON public.project_time_entries;
CREATE TRIGGER guard_project_time_on_absence
  BEFORE INSERT OR UPDATE OF start_time, end_time, employee_id
  ON public.project_time_entries
  FOR EACH ROW EXECUTE FUNCTION public.guard_project_time_on_absence();

-- ============================================================
-- 4. TRV-06 / TRV-10 — les frais d'un absent, sauf mission
-- ============================================================
-- Vérifié à l'insertion/modification de la ligne ET à la soumission comme à
-- l'approbation de la note : une ligne peut être saisie avant l'absence, puis
-- devenir indue parce que le congé a été approuvé entre-temps.
CREATE OR REPLACE FUNCTION public.guard_expense_line_on_absence()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_employee uuid;
  v_kind text;
  v_allows boolean;
BEGIN
  IF NEW.expense_report_id IS NULL OR NEW.date IS NULL THEN RETURN NEW; END IF;

  SELECT er.employee_id INTO v_employee
    FROM expense_reports er
   WHERE er.id = NEW.expense_report_id AND er.tenant_id = NEW.tenant_id;
  IF v_employee IS NULL THEN RETURN NEW; END IF;

  v_kind := absence_kind_on(NEW.tenant_id, v_employee, NEW.date);
  IF v_kind IS NULL THEN
    NEW.mission_absence_day := NULL;
    NEW.mission_absence_employee_id := NULL;
    RETURN NEW;
  END IF;

  v_allows := absence_allows_expenses_on(NEW.tenant_id, v_employee, NEW.date);
  IF NOT v_allows THEN
    PERFORM assert_can_claim_expense(v_employee, NEW.date);
  END IF;

  -- TRV-10 : une dépense autorisée par une MISSION est marquée comme telle —
  -- c'est la preuve, opposable, que le jour l'autorisait.
  IF v_kind = 'mission' THEN
    NEW.mission_absence_day := NEW.date;
    NEW.mission_absence_employee_id := v_employee;
  ELSE
    NEW.mission_absence_day := NULL;
    NEW.mission_absence_employee_id := NULL;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS guard_expense_line_on_absence ON public.expense_report_lines;
CREATE TRIGGER guard_expense_line_on_absence
  BEFORE INSERT OR UPDATE OF date, expense_report_id, amount
  ON public.expense_report_lines
  FOR EACH ROW EXECUTE FUNCTION public.guard_expense_line_on_absence();

-- À la soumission et à l'approbation : on recontrôle TOUTES les lignes, parce
-- qu'une absence peut avoir été approuvée après la saisie de la note.
CREATE OR REPLACE FUNCTION public.guard_expense_report_on_decision()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  r record;
BEGIN
  IF NEW.status IN ('submitted', 'approved') AND NEW.status IS DISTINCT FROM OLD.status THEN
    FOR r IN SELECT l.date AS d FROM expense_report_lines l
              WHERE l.expense_report_id = NEW.id AND l.tenant_id = NEW.tenant_id
              ORDER BY l.date LOOP
      PERFORM assert_can_claim_expense(NEW.employee_id, r.d);
    END LOOP;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS guard_expense_report_on_decision ON public.expense_reports;
CREATE TRIGGER guard_expense_report_on_decision
  BEFORE UPDATE OF status ON public.expense_reports
  FOR EACH ROW EXECUTE FUNCTION public.guard_expense_report_on_decision();


-- ============================================================
-- 5. TRV-07 / TRV-08 — les tâches
-- ============================================================
-- TRV-07 : on n'assigne pas une tâche à quelqu'un dont le jour de démarrage est
-- un jour d'absence bloquante. La date examinée est celle de la tâche quand elle
-- est posée (une absence de juin n'interdit pas une tâche de juillet), sinon
-- aujourd'hui.
CREATE OR REPLACE FUNCTION public.guard_task_assignee_on_absence()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.assignee_id IS NULL THEN RETURN NEW; END IF;
  PERFORM assert_not_absent(NEW.assignee_id, COALESCE(NEW.start_date, CURRENT_DATE),
                            'affectation de tâche');
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS guard_task_assignee_on_absence ON public.project_tasks;
CREATE TRIGGER guard_task_assignee_on_absence
  BEFORE INSERT OR UPDATE OF assignee_id, start_date
  ON public.project_tasks
  FOR EACH ROW EXECUTE FUNCTION public.guard_task_assignee_on_absence();

-- TRV-08 : un salarié absent ne peut pas clore LUI-MÊME sa tâche. Un tiers le
-- peut — c'est le RH ou le chef de projet qui corrige — et le journal
-- d'activité enregistre qui l'a fait (`project_activity_log`, déclencheur
-- existant `log_task_activity`).
CREATE OR REPLACE FUNCTION public.guard_task_close_by_absent()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_writer uuid;
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status OR NEW.status <> 'done' THEN
    RETURN NEW;
  END IF;
  IF NEW.assignee_id IS NULL THEN RETURN NEW; END IF;

  -- Qui écrit ? L'utilisateur connecté, rapproché de son dossier salarié.
  SELECT e.id INTO v_writer
    FROM employees e
   WHERE e.tenant_id = NEW.tenant_id AND e.auth_user_id = auth.uid();

  IF v_writer IS NULL OR v_writer <> NEW.assignee_id THEN
    RETURN NEW;   -- un tiers peut clore : le refus ne vise que l'absent.
  END IF;
  PERFORM assert_not_absent(v_writer, CURRENT_DATE, 'clôture de tâche');
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS guard_task_close_by_absent ON public.project_tasks;
CREATE TRIGGER guard_task_close_by_absent
  BEFORE UPDATE OF status ON public.project_tasks
  FOR EACH ROW EXECUTE FUNCTION public.guard_task_close_by_absent();


-- ============================================================
-- 6. TRV-16 — le contrôle d'intégrité quotidien
-- ============================================================
-- Sans ce filet, une donnée saisie AVANT la mise en place du registre — ou par
-- un chemin détourné (script, import, correctif manuel) — ne se verrait nulle
-- part. Le contrôle ne répare rien : il NOMME.
CREATE OR REPLACE FUNCTION public.check_absence_conflicts(
  p_tenant uuid,
  p_from   date DEFAULT (CURRENT_DATE - 30),
  p_to     date DEFAULT CURRENT_DATE
)
RETURNS TABLE (tenant_id uuid, employee_id uuid, employee_name text, day date,
               absence_kind text, conflict_type text, detail text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  PERFORM assert_absence_tenant(p_tenant);
  RETURN QUERY
  SELECT d.tenant_id, d.employee_id, e.name, d.day, d.absence_kind,
         c.conflict_type, c.detail
    FROM employee_absence_days d
    JOIN employees e ON e.id = d.employee_id AND e.tenant_id = d.tenant_id
    CROSS JOIN LATERAL (
      -- Un pointage de travail un jour d'absence bloquante
      SELECT 'pointage'::text AS conflict_type,
             format('pointage de %s h (%s)', COALESCE(ts.hours, 0), ts.status) AS detail
        FROM timesheets ts
       WHERE ts.tenant_id = d.tenant_id AND ts.employee_id = d.employee_id
         AND ts.date = d.day AND COALESCE(ts.absence_type, 'none') = 'none'
         AND COALESCE(ts.hours, 0) > 0 AND d.blocks_work
      UNION ALL
      -- Des heures supplémentaires le même jour
      SELECT 'heures_supplementaires',
             format('%s min supplémentaires', ts.overtime_minutes)
        FROM timesheets ts
       WHERE ts.tenant_id = d.tenant_id AND ts.employee_id = d.employee_id
         AND ts.date = d.day AND COALESCE(ts.overtime_minutes, 0) > 0 AND d.blocks_work
      UNION ALL
      -- Du temps projet : facturable (TRV-09) ou non
      SELECT CASE WHEN pte.is_billable THEN 'temps_facturable' ELSE 'temps_projet' END,
             format('%s s, facturable=%s', COALESCE(pte.duration_seconds, 0),
                    COALESCE(pte.is_billable, false))
        FROM project_time_entries pte
       WHERE pte.tenant_id = d.tenant_id AND pte.employee_id = d.employee_id
         AND pte.start_time::date = d.day AND d.blocks_work
      UNION ALL
      -- Une ligne de frais un jour qui ne les autorise pas
      SELECT 'frais',
             format('ligne de frais de %s (%s)', l.amount, COALESCE(l.description, ''))
        FROM expense_report_lines l
        JOIN expense_reports er ON er.id = l.expense_report_id AND er.tenant_id = l.tenant_id
       WHERE er.tenant_id = d.tenant_id AND er.employee_id = d.employee_id
         AND l.date = d.day AND NOT d.allows_expenses
    ) c
   WHERE d.tenant_id = p_tenant AND d.day BETWEEN p_from AND p_to
   ORDER BY d.day, e.name, c.conflict_type;
END $$;

COMMENT ON FUNCTION public.check_absence_conflicts(uuid, date, date) IS
  'W9 / TRV-16 — les jours qui portent une absence ET un pointage, des heures supplémentaires, du temps projet ou une ligne de frais. Le contrôle NOMME, il ne répare pas.';

-- La porte du front : la société active, bornée à 400 jours.
CREATE OR REPLACE FUNCTION public.absence_conflicts_current(
  p_from date DEFAULT (CURRENT_DATE - 30),
  p_to   date DEFAULT CURRENT_DATE
)
RETURNS TABLE (employee_id uuid, employee_name text, day date, absence_kind text,
               conflict_type text, detail text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tenant uuid := current_tenant_id();
BEGIN
  IF v_tenant IS NULL THEN
    RAISE EXCEPTION 'absence_conflicts_current : aucune société active'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_to < p_from OR p_to - p_from > 400 THEN
    RAISE EXCEPTION 'absence_conflicts_current : plage invalide (% → %)', p_from, p_to
      USING ERRCODE = 'invalid_parameter_value';
  END IF;
  RETURN QUERY
  SELECT c.employee_id, c.employee_name, c.day, c.absence_kind, c.conflict_type, c.detail
    FROM check_absence_conflicts(v_tenant, p_from, p_to) c;
END $$;

COMMENT ON FUNCTION public.absence_conflicts_current(date, date) IS
  'W9 — les anomalies d''absence de la société active, pour l''écran « Anomalies ».';

-- Le passage quotidien : il écrit une notification aux administrateurs de
-- chaque société concernée et rend le nombre d'anomalies trouvées.
CREATE OR REPLACE FUNCTION public.run_absence_integrity_check(
  p_from date DEFAULT (CURRENT_DATE - 30),
  p_to   date DEFAULT CURRENT_DATE
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  t record;
  v_n integer;
  v_ctx uuid := current_tenant_id();
  v_total integer := 0;
BEGIN
  -- Avec un contexte (un utilisateur connecté), on ne voit que SA société :
  -- la garde de `check_absence_conflicts` n'est jamais contournée. Sans
  -- contexte — le passage planifié — on parcourt les sociétés concernées.
  FOR t IN SELECT DISTINCT d.tenant_id
             FROM employee_absence_days d
            WHERE d.day BETWEEN p_from AND p_to
              AND (v_ctx IS NULL OR d.tenant_id = v_ctx) LOOP
    SELECT count(*) INTO v_n FROM check_absence_conflicts(t.tenant_id, p_from, p_to);
    IF v_n > 0 THEN
      INSERT INTO notifications (tenant_id, user_id, category, severity, title, message, link)
      SELECT t.tenant_id, tu.auth_id, 'hr', 'warning',
             'Anomalies d''absence à traiter',
             v_n || ' jour(s) d''absence portent aussi un pointage, du temps projet ou une ligne de frais.',
             '/hr/absence-anomalies'
        FROM tenant_users tu
       WHERE tu.tenant_id = t.tenant_id AND tu.status = 'active'
         AND tu.role IN ('admin', 'owner', 'manager');
      v_total := v_total + v_n;
    END IF;
  END LOOP;
  RETURN v_total;
END $$;

COMMENT ON FUNCTION public.run_absence_integrity_check(date, date) IS
  'W9 / TRV-16 — le passage quotidien : compte les anomalies et prévient les administrateurs (notifications).';


-- ── Le rendez-vous quotidien (même garde que les autres jobs du dépôt) ──────
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    RAISE NOTICE 'pg_cron absent : le contrôle quotidien des anomalies d''absence ne sera pas planifié (l''activer dans Dashboard > Database > Extensions, puis rejouer la 264).';
  ELSE
    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'absence-integrity-daily') THEN
      PERFORM cron.unschedule('absence-integrity-daily');
    END IF;
    PERFORM cron.schedule(
      'absence-integrity-daily',
      '15 7 * * *',
      $cron$ SELECT public.run_absence_integrity_check(); $cron$
    );
    RAISE NOTICE 'Job absence-integrity-daily planifié (chaque jour à 07:15 UTC).';
  END IF;
END $$;

-- ============================================================
-- 7. Droits
-- ============================================================
REVOKE ALL ON FUNCTION public.guard_timesheet_on_absence() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.guard_timesheet_approval_on_absence() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.guard_project_time_on_absence() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.guard_expense_line_on_absence() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.guard_expense_report_on_decision() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.guard_task_assignee_on_absence() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.guard_task_close_by_absent() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.check_absence_conflicts(uuid, date, date) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.absence_conflicts_current(date, date) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.run_absence_integrity_check(date, date) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.check_absence_conflicts(uuid, date, date) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.absence_conflicts_current(date, date) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.run_absence_integrity_check(date, date) TO authenticated, service_role;

