-- ============================================================
-- 263_absence_registry.sql — vague W9 : le registre d'absence
--                              (TRV-01, TRV-02, TRV-14, TRV-15)
--
-- MESURÉ AVANT, sur base neuve (228 migrations) :
--
--   TRV-01  quatre sources d'absence vivent côte à côte sans converger :
--           `leave_requests` (congés/RTT/sans solde), `sick_leaves`
--           (maladie/AT/maternité), `work_stoppages` (arrêt de travail) et
--           `timesheets.absence_type` — cette dernière colonne existe depuis la
--           104 et **personne ne l'écrit** (0 occurrence dans `app/src`).
--           Aucune n'est lisible par les autres modules ;
--   TRV-02  deux sources le même jour ne sont arbitrées par personne ;
--   TRV-14  `leave_rules.requires_justification` et
--           `leave_rules.affects_pay` ne sont **jamais** lus :
--           `SELECT leave_type, affects_pay FROM leave_rules` rendait
--           `annual|f  rtt|f  sick|f  unpaid|f` ;
--   TRV-15  `leave_balances` n'est traversée par aucun scénario : le débit à
--           l'approbation est fait par le FRONT (deux allers-retours
--           PostgREST), donc perdu au premier appel direct, et la restitution à
--           l'annulation ne connaissait que le cas `pending`.
--
-- Et un défaut de cohérence UI/base mesuré sur le schéma :
--   `leave_requests_leave_type_check` n'accepte que
--   (annual, sick, maternity, paternity, unpaid, other) alors que
--   `leave_rules` porte `rtt` et que l'écran propose RTT / Récupération /
--   Personnel / Mission : **l'UI offrait ce que la base refusait.**
--
-- Ce que cette migration pose :
--   1. `employee_absence_days` — une vérité par jour et par salarié ;
--   2. `absence_conflict_log` — le conflit est journalisé, jamais arbitré en
--      silence ;
--   3. quatre déclencheurs qui convergent vers `rebuild_absence_days()`,
--      **idempotente** (elle supprime puis re-remplit la plage) : c'est elle qui
--      rend l'annulation correcte ;
--   4. l'API de lecture écrite une fois et utilisée partout
--      (`absence_kind_on`, `is_employee_absent`, `assert_not_absent`,
--      `assert_can_claim_expense`, `absence_summary`, `absence_working_days`) ;
--   5. TRV-15 : le solde de congés est débité **en base** à l'approbation et
--      restitué à l'annulation/rejet, quel que soit le chemin d'écriture.
--
-- Aucun des défauts ci-dessus n'est « corrigé » par un `WHERE` posé dans un
-- écran : les gardes vivent en base (W9 s'appuie sur W1 : ISO-01, ISO-02).
-- ============================================================

-- ============================================================
-- 1. L'UI offrait des types de congé que la base refusait
-- ============================================================
-- Aligner le CHECK sur les règles réellement paramétrables (`leave_rules`)
-- et sur la table de vérité de W9 : un écran qui propose « RTT » ne peut plus
-- se heurter à un `check_violation` sans rapport avec ce qu'il affiche.
ALTER TABLE public.leave_requests DROP CONSTRAINT IF EXISTS leave_requests_leave_type_check;
ALTER TABLE public.leave_requests ADD CONSTRAINT leave_requests_leave_type_check
  CHECK (leave_type IN ('annual', 'rtt', 'recovery', 'sick', 'maternity',
                        'paternity', 'parental', 'unpaid', 'personal',
                        'mission', 'other'));

COMMENT ON CONSTRAINT leave_requests_leave_type_check ON public.leave_requests IS
  'W9 — les types que l''écran propose : congés payés, RTT, récupération, maladie, maternité/paternité/parental, sans solde, personnel, mission, autre.';


-- ============================================================
-- 2. Le registre : une vérité par jour et par salarié
-- ============================================================
CREATE TABLE IF NOT EXISTS public.employee_absence_days (
  tenant_id           uuid NOT NULL,
  employee_id         uuid NOT NULL,
  day                 date NOT NULL,
  absence_kind        text NOT NULL,
  origin              text NOT NULL,
  origin_id           uuid,
  justification_state text NOT NULL DEFAULT 'pending',
  blocks_work         boolean NOT NULL DEFAULT true,
  allows_expenses     boolean NOT NULL DEFAULT false,
  paid                boolean NOT NULL DEFAULT false,
  pay_rule_code       text,
  created_at          timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT employee_absence_days_pkey PRIMARY KEY (tenant_id, employee_id, day),
  CONSTRAINT employee_absence_days_kind_check CHECK (absence_kind IN
    ('annual', 'rtt', 'sick', 'work_accident', 'maternity', 'unpaid',
     'personal', 'mission', 'stoppage', 'unjustified')),
  CONSTRAINT employee_absence_days_origin_check CHECK (origin IN
    ('leave_request', 'sick_leaf', 'work_stoppage', 'timesheet')),
  CONSTRAINT employee_absence_days_justification_check CHECK (justification_state IN
    ('pending', 'provided', 'missing')),
  CONSTRAINT employee_absence_days_employee_fkey FOREIGN KEY (tenant_id, employee_id)
    REFERENCES public.employees (tenant_id, id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_employee_absence_days_employee_day
  ON public.employee_absence_days (tenant_id, employee_id, day);

CREATE INDEX IF NOT EXISTS idx_employee_absence_days_kind
  ON public.employee_absence_days (tenant_id, absence_kind, day);

COMMENT ON TABLE public.employee_absence_days IS
  'W9 — le registre unique : un jour, un salarié, une vérité. Alimenté par les quatre sources (congé, maladie, arrêt de travail, pointage d''absence) et lu par tous les modules.';
COMMENT ON COLUMN public.employee_absence_days.absence_kind IS
  'Type retenu après résolution des conflits : annual|rtt|sick|work_accident|maternity|unpaid|personal|mission|stoppage|unjustified.';
COMMENT ON COLUMN public.employee_absence_days.blocks_work IS
  'true : pointage, heures supplémentaires et temps projet sont refusés ce jour-là (mission = false).';
COMMENT ON COLUMN public.employee_absence_days.allows_expenses IS
  'true seulement pour une mission : la note de frais du jour reste recevable.';
COMMENT ON COLUMN public.employee_absence_days.pay_rule_code IS
  'Règle de paie applicable : leave_paid | unpaid_deduction | sick_maintenance | work_accident_maintenance | maternity_maintenance | stoppage_maintenance.';

CREATE TABLE IF NOT EXISTS public.absence_conflict_log (
  id             uuid NOT NULL DEFAULT gen_random_uuid(),
  tenant_id      uuid NOT NULL,
  employee_id    uuid NOT NULL,
  day            date NOT NULL,
  kept_kind      text NOT NULL,
  kept_origin    text NOT NULL,
  dropped_kind   text NOT NULL,
  dropped_origin text NOT NULL,
  detected_at    timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT absence_conflict_log_pkey PRIMARY KEY (id),
  CONSTRAINT absence_conflict_log_employee_fkey FOREIGN KEY (tenant_id, employee_id)
    REFERENCES public.employees (tenant_id, id) ON DELETE CASCADE,
  -- Rejouer `rebuild_absence_days` ne réécrit pas deux fois le même arbitrage,
  -- mais l'historique des arbitrages est conservé (jamais purgé par le rebuild).
  CONSTRAINT absence_conflict_log_unique UNIQUE
    (tenant_id, employee_id, day, kept_kind, kept_origin, dropped_kind, dropped_origin)
);

COMMENT ON TABLE public.absence_conflict_log IS
  'W9 / TRV-02 — deux sources le même jour : la priorité tranche ET le conflit est journalisé (jamais arbitré en silence).';

-- ── RLS : même modèle que le reste du schéma (société courante) ──────────────
ALTER TABLE public.employee_absence_days ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.absence_conflict_log  ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS employee_absence_days_tenant ON public.employee_absence_days;
CREATE POLICY employee_absence_days_tenant ON public.employee_absence_days
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

DROP POLICY IF EXISTS absence_conflict_log_tenant ON public.absence_conflict_log;
CREATE POLICY absence_conflict_log_tenant ON public.absence_conflict_log
  FOR SELECT USING (tenant_id = current_tenant_id());

-- Le registre est en LECTURE pour les écrans ; il s'écrit par les fonctions
-- (SECURITY DEFINER) et jamais « à la main » depuis PostgREST.
REVOKE ALL ON public.employee_absence_days FROM PUBLIC, anon;
REVOKE ALL ON public.absence_conflict_log  FROM PUBLIC, anon;
GRANT SELECT ON public.employee_absence_days TO authenticated, service_role;
GRANT INSERT, UPDATE, DELETE ON public.employee_absence_days TO service_role;
GRANT SELECT ON public.absence_conflict_log TO authenticated, service_role;

-- ============================================================
-- 3. Classification : priorité d'un type, effets d'un type
-- ============================================================

-- Priorité mesurée par la table de vérité de W9 (§3.2 du plan) :
--   work_accident > sick > maternity > stoppage > unpaid > personal/unjustified
--   > annual/rtt > mission.
-- Un accident du travail prime sur une maladie, une maladie sur un congé payé :
-- la paie ne doit jamais avoir à choisir toute seule, et le choix le plus
-- protecteur pour le salarié (AT/maladie) l'emporte.
CREATE OR REPLACE FUNCTION public.absence_kind_priority(p_kind text)
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE p_kind
    WHEN 'work_accident' THEN 90
    WHEN 'sick'          THEN 80
    WHEN 'maternity'     THEN 70
    WHEN 'stoppage'      THEN 60
    WHEN 'unpaid'        THEN 50
    WHEN 'personal'      THEN 45
    WHEN 'unjustified'   THEN 45
    WHEN 'annual'        THEN 30
    WHEN 'rtt'           THEN 25
    WHEN 'mission'       THEN 10
    ELSE 0 END
$$;

COMMENT ON FUNCTION public.absence_kind_priority(text) IS
  'W9 / TRV-02 — ordre de résolution d''un jour porté par deux sources.';

-- Effets d'un type quand aucune règle de société ne le surcharge.
-- Ligne par ligne, la table de vérité W9 (§3.3).
CREATE OR REPLACE FUNCTION public.absence_kind_flags(
  p_kind text,
  OUT blocks_work boolean,
  OUT allows_expenses boolean,
  OUT paid boolean,
  OUT pay_rule_code text
)
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT x.blocks_work, x.allows_expenses, x.paid, x.pay_rule_code
  FROM (VALUES
    ('annual',        true,  false, true,  'leave_paid'),
    ('rtt',           true,  false, true,  'leave_paid'),
    ('sick',          true,  false, true,  'sick_maintenance'),
    ('work_accident', true,  false, true,  'work_accident_maintenance'),
    ('maternity',     true,  false, true,  'maternity_maintenance'),
    ('stoppage',      true,  false, true,  'stoppage_maintenance'),
    ('unpaid',        true,  false, false, 'unpaid_deduction'),
    ('personal',      true,  false, false, 'unpaid_deduction'),
    ('unjustified',   true,  false, false, 'unpaid_deduction'),
    -- Mission : c'est un déplacement professionnel, pas une absence. Le
    -- confondre avec une absence était le contresens à éviter (télétravail
    -- compris : ni l'un ni l'autre ne bloque le travail).
    ('mission',       false, true,  true,  'leave_paid')
  ) AS x(kind, blocks_work, allows_expenses, paid, pay_rule_code)
  WHERE x.kind = p_kind;
$$;

COMMENT ON FUNCTION public.absence_kind_flags(text) IS
  'W9 — ce qu''un jour d''absence autorise et interdit, par défaut : blocks_work, allows_expenses, paid, pay_rule_code.';

-- La règle de société qui surcharge les défauts, s'il y en a une.
-- `leave_rules.affects_pay` devient enfin LUE : une règle qui l'a à true rend
-- le jour non payé (retenue), quelle que soit sa nature.
CREATE OR REPLACE FUNCTION public.absence_leave_rule(p_tenant uuid, p_leave_type text)
RETURNS TABLE (affects_pay boolean, requires_justification boolean, deduction_rate numeric,
               count_method text, rule_id uuid)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  PERFORM assert_absence_tenant(p_tenant);
  RETURN QUERY
  SELECT COALESCE(r.affects_pay, false),
         COALESCE(r.requires_justification, false),
         COALESCE(r.deduction_rate, 100),
         COALESCE(r.count_method, 'working_days'),
         r.id
  FROM leave_rules r
  WHERE r.leave_type = p_leave_type
    AND r.active = true
    AND (r.tenant_id = p_tenant OR r.tenant_id IS NULL)
  -- NULLS LAST : la règle GLOBALE a `tenant_id IS NULL`, et un tri DESC place
  -- les NULL en PREMIER par défaut — la règle globale l'emporterait alors sur
  -- celle de la société. Mesuré : avec `affects_pay = true` posé par la
  -- société, le jour restait payé (A06 rouge) jusqu'à ce correctif.
  ORDER BY (r.tenant_id = p_tenant) DESC NULLS LAST, r.created_at DESC NULLS LAST
  LIMIT 1;
END $$;

COMMENT ON FUNCTION public.absence_leave_rule(uuid, text) IS
  'W9 — la règle paramétrée d''un type de congé (société d''abord, puis le socle global).';

-- Délai après lequel une absence sans justificatif devient « non justifiée ».
-- Paramétrable par société (payroll_legal_parameters), 30 jours par défaut.
CREATE OR REPLACE FUNCTION public.absence_justification_delay(p_tenant uuid)
RETURNS integer
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v numeric;
BEGIN
  PERFORM assert_absence_tenant(p_tenant);
  v := NULLIF(get_legal_parameter('ABSENCE_JUSTIFICATION_DELAY_DAYS', 'FR', CURRENT_DATE, p_tenant), 0);
  IF v IS NOT NULL AND v > 0 THEN
    RETURN v::integer;
  END IF;
  RETURN 30;
END $$;

COMMENT ON FUNCTION public.absence_justification_delay(uuid) IS
  'W9 / TRV-14 — délai (jours) avant qu''une absence sans justificatif ne devienne « unjustified ». Paramètre ABSENCE_JUSTIFICATION_DELAY_DAYS, 30 par défaut.';

-- ── La garde de société partagée (ISO-01, règle 2 de ci/check_tenant_guard) ──
-- Toute fonction exposée qui prend une société en paramètre la traverse. Elle
-- n'écarte pas le cas du déclencheur (où `current_tenant_id()` est NULL, faute
-- de jeton) : le déclencheur a déjà posé la société du mouvement.
CREATE OR REPLACE FUNCTION public.assert_absence_tenant(p_tenant uuid)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_ctx uuid := current_tenant_id();
BEGIN
  IF p_tenant IS NULL THEN
    RAISE EXCEPTION 'Société obligatoire' USING ERRCODE = 'null_value_not_allowed';
  END IF;
  IF v_ctx IS NOT NULL AND v_ctx <> p_tenant THEN
    RAISE EXCEPTION 'Société % hors du contexte courant %', p_tenant, v_ctx
      USING ERRCODE = 'insufficient_privilege';
  END IF;
END $$;

COMMENT ON FUNCTION public.assert_absence_tenant(uuid) IS
  'W9 — garde de société : refuse d''agir au nom d''une société dont l''appelant n''est pas membre (ISO-01).';


-- ============================================================
-- 4. La brique d'alimentation : idempotente, à l'échelle de la plage
-- ============================================================
-- Elle SUPPRIME la plage puis la RE-REMPLIT à partir des quatre sources. C'est
-- ce qui rend correctes l'annulation, la correction de dates et la
-- régularisation : rien n'est incrémenté, tout est recalculé.
CREATE OR REPLACE FUNCTION public.rebuild_absence_days(
  p_tenant   uuid,
  p_employee uuid,
  p_from     date,
  p_to       date
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_from  date;
  v_to    date;
  v_delay integer;
  v_count integer := 0;
BEGIN
  -- ── Garde de société (ISO-01, règle 2 de ci/check_tenant_guard) ───────────
  IF p_employee IS NULL OR p_from IS NULL OR p_to IS NULL THEN
    RAISE EXCEPTION 'rebuild_absence_days : salarié et bornes sont obligatoires'
      USING ERRCODE = 'null_value_not_allowed';
  END IF;
  PERFORM assert_absence_tenant(p_tenant);
  IF NOT EXISTS (SELECT 1 FROM employees e WHERE e.id = p_employee AND e.tenant_id = p_tenant) THEN
    RAISE EXCEPTION 'rebuild_absence_days : salarié % absent de la société %', p_employee, p_tenant
      USING ERRCODE = 'foreign_key_violation';
  END IF;

  v_from := p_from;
  v_to   := p_to;
  IF v_to < v_from THEN
    RAISE EXCEPTION 'rebuild_absence_days : borne de fin % antérieure au début %', v_to, v_from
      USING ERRCODE = 'invalid_parameter_value';
  END IF;
  -- Une plage raisonnable : un congé de trois ans ne se recopie pas en une fois.
  IF v_to - v_from > 400 THEN
    RAISE EXCEPTION 'rebuild_absence_days : plage de % jours refusée (400 maximum)', v_to - v_from
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  v_delay := absence_justification_delay(p_tenant);

  -- ── Reprise : la plage est recalculée, jamais incrémentée ────────────────
  DELETE FROM employee_absence_days
   WHERE tenant_id = p_tenant AND employee_id = p_employee
     AND day BETWEEN v_from AND v_to;


  -- ── Les candidats des quatre sources, un par jour et par source ──────────
  WITH src AS (
    -- 1) Les congés approuvés (`leave_requests`)
    SELECT gs::date                                      AS day,
           CASE lr.leave_type
             WHEN 'annual'    THEN 'annual'
             WHEN 'rtt'       THEN 'rtt'
             WHEN 'recovery'  THEN 'rtt'
             WHEN 'sick'      THEN 'sick'
             WHEN 'maternity' THEN 'maternity'
             WHEN 'paternity' THEN 'maternity'
             WHEN 'parental'  THEN 'maternity'
             WHEN 'unpaid'    THEN 'unpaid'
             WHEN 'mission'   THEN 'mission'
             ELSE 'personal'
           END                                           AS kind,
           'leave_request'::text                         AS origin,
           lr.id                                         AS origin_id,
           (lr.reason IS NOT NULL AND btrim(lr.reason) <> '') AS has_proof,
           COALESCE(r.requires_justification, false)     AS needs_proof,
           COALESCE(r.affects_pay, false)                AS affects_pay
      FROM leave_requests lr
      LEFT JOIN LATERAL absence_leave_rule(p_tenant, lr.leave_type) r ON true
      CROSS JOIN LATERAL generate_series(
        GREATEST(lr.start_date, v_from),
        LEAST(COALESCE(lr.end_date, lr.start_date), v_to),
        interval '1 day') gs
     WHERE lr.tenant_id = p_tenant AND lr.employee_id = p_employee
       AND lr.status = 'approved'

    UNION ALL

    -- 2) Les arrêts de maladie (`sick_leaves`) — y compris « closed » : un
    --    arrêt terminé reste une absence pour les jours qu'il a couverts.
    SELECT gs::date,
           CASE sl.leave_type
             WHEN 'work_accident' THEN 'work_accident'
             WHEN 'sickness'      THEN 'sick'
             ELSE 'maternity'
           END,
           'sick_leaf'::text,
           sl.id,
           (sl.medical_certificate_url IS NOT NULL AND btrim(sl.medical_certificate_url) <> ''),
           true,
           false
      FROM sick_leaves sl
      CROSS JOIN LATERAL generate_series(
        GREATEST(sl.start_date, v_from),
        LEAST(sl.end_date, v_to),
        interval '1 day') gs
     WHERE sl.tenant_id = p_tenant AND sl.employee_id = p_employee
       AND sl.status IN ('active', 'closed')

    UNION ALL

    -- 3) Les arrêts de travail (`work_stoppages`) — une borne ouverte vaut un
    --    jour, jamais l'infini : un arrêt sans fin ne bloque pas l'avenir.
    SELECT gs::date,
           'stoppage'::text,
           'work_stoppage'::text,
           ws.id,
           (ws.medical_certificate_url IS NOT NULL AND btrim(ws.medical_certificate_url) <> ''),
           true,
           false
      FROM work_stoppages ws
      CROSS JOIN LATERAL generate_series(
        GREATEST(ws.start_date, v_from),
        LEAST(COALESCE(ws.end_date, ws.reprise_date, ws.start_date), v_to),
        interval '1 day') gs
     WHERE ws.tenant_id = p_tenant AND ws.employee_id = p_employee
       AND COALESCE(ws.status, 'active') NOT IN ('cancelled', 'rejected')

    UNION ALL

    -- 4) Le pointage d'absence (`timesheets.absence_type`) — la colonne que
    --    personne n'alimentait. Elle devient la quatrième source.
    SELECT ts.date,
           CASE ts.absence_type
             WHEN 'sick'     THEN 'sick'
             WHEN 'unpaid'   THEN 'unpaid'
             WHEN 'personal' THEN 'personal'
             WHEN 'mission'  THEN 'mission'
             ELSE 'personal'
           END,
           'timesheet'::text,
           ts.id,
           (ts.absence_reason IS NOT NULL AND btrim(ts.absence_reason) <> ''),
           (ts.absence_type IN ('unpaid', 'personal')),
           (ts.absence_type = 'unpaid')
      FROM timesheets ts
     WHERE ts.tenant_id = p_tenant AND ts.employee_id = p_employee
       AND ts.date BETWEEN v_from AND v_to
       AND COALESCE(ts.absence_type, 'none') <> 'none'
  ),

  -- ── Un seul gagnant par jour : priorité, puis provenance, puis source ─────
  ranked AS (
    SELECT s.*,
           row_number() OVER (
             PARTITION BY s.day
             ORDER BY absence_kind_priority(s.kind) DESC,
                      CASE s.origin WHEN 'work_stoppage' THEN 4
                                    WHEN 'sick_leaf'     THEN 3
                                    WHEN 'timesheet'     THEN 2
                                    ELSE 1 END DESC,
                      s.origin_id
           ) AS rk
      FROM src s
  ),
  kept AS (SELECT * FROM ranked WHERE rk = 1),
  -- ── Les perdants, journalisés (TRV-02) ───────────────────────────────────
  lost AS (
    SELECT r.* FROM ranked r JOIN kept k ON k.day = r.day WHERE r.rk > 1
  ),
  logged AS (
    INSERT INTO absence_conflict_log
      (tenant_id, employee_id, day, kept_kind, kept_origin, dropped_kind, dropped_origin)
    SELECT p_tenant, p_employee, l.day, k.kind, k.origin, l.kind, l.origin
      FROM lost l JOIN kept k ON k.day = l.day
    ON CONFLICT (tenant_id, employee_id, day, kept_kind, kept_origin, dropped_kind, dropped_origin)
    DO NOTHING
    RETURNING 1
  ),
  -- ── La ligne de registre ──────────────────────────────────────────────────
  final AS (
    SELECT k.day,
           -- TRV-14 : une absence que la règle soumet à justificatif et qui
           -- n'en a pas, passée le délai, devient « unjustified ».
           --
           -- LIMITE DÉLIBÉRÉE ET DITE. La requalification ne touche QUE les
           -- types déjà non payés (`unpaid`, `personal`) : elle change le
           -- libellé et l''alerte RH, jamais le montant. Une maladie sans
           -- certificat n''est PAS transformée en absence non justifiée :
           -- cela changerait la paie d''un maintien en retenue, rétroactivement
           -- et en silence — exactement le défaut que W9 corrige. Pour ces
           -- types, la pièce manquante est portée par `justification_state`
           -- (« missing »), que l'écran d'anomalies RH affiche.
           CASE WHEN k.needs_proof AND NOT k.has_proof
                     AND k.day < CURRENT_DATE - v_delay
                     AND k.kind IN ('unpaid', 'personal')
                THEN 'unjustified'
                ELSE k.kind END AS kind,
           k.origin,
           k.origin_id,
           CASE WHEN k.has_proof THEN 'provided'
                WHEN k.needs_proof AND k.day < CURRENT_DATE - v_delay THEN 'missing'
                ELSE 'pending' END AS justification_state,
           k.affects_pay
      FROM kept k
  )
  INSERT INTO employee_absence_days
    (tenant_id, employee_id, day, absence_kind, origin, origin_id,
     justification_state, blocks_work, allows_expenses, paid, pay_rule_code)
  SELECT p_tenant, p_employee, f.day, f.kind, f.origin, f.origin_id,
         f.justification_state,
         -- Un jour de mission non justifié passé le délai perd ses tolérances.
         CASE WHEN f.kind = 'mission' AND f.justification_state <> 'missing'
              THEN false ELSE true END,
         (f.kind = 'mission' AND f.justification_state <> 'missing'),
         CASE WHEN f.kind IN ('unpaid', 'personal', 'unjustified') THEN false
              WHEN f.affects_pay THEN false
              ELSE true END,
         CASE WHEN f.kind IN ('unpaid', 'personal', 'unjustified') OR f.affects_pay
              THEN 'unpaid_deduction'
              ELSE (SELECT x.pay_rule_code FROM absence_kind_flags(f.kind) x) END
    FROM final f;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END $$;

COMMENT ON FUNCTION public.rebuild_absence_days(uuid, uuid, date, date) IS
  'W9 — recalcule la plage du registre d''absence à partir des quatre sources. Idempotente : supprime puis re-remplit, donc l''annulation et la correction de dates sont exactes.';



-- ============================================================
-- 5. Les quatre sources convergent (TRV-01)
-- ============================================================
-- Chacune appelle `rebuild_absence_days` sur la plage concernée — l'union de
-- l'ancienne et de la nouvelle, pour qu'un changement de dates ou d'état
-- efface ce qui n'est plus vrai.

CREATE OR REPLACE FUNCTION public.sync_absence_from_leave_request()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_from date;
  v_to   date;
BEGIN
  IF NEW.employee_id IS NULL OR NEW.tenant_id IS NULL THEN RETURN NEW; END IF;

  v_from := LEAST(COALESCE(OLD.start_date, NEW.start_date), NEW.start_date);
  v_to   := GREATEST(COALESCE(OLD.end_date, OLD.start_date, NEW.end_date, NEW.start_date),
                     COALESCE(NEW.end_date, NEW.start_date));
  PERFORM rebuild_absence_days(NEW.tenant_id, NEW.employee_id, v_from, v_to);

  -- Le salarié a changé : l'ancien doit perdre ses jours.
  IF TG_OP = 'UPDATE' AND OLD.employee_id IS DISTINCT FROM NEW.employee_id
     AND OLD.employee_id IS NOT NULL THEN
    PERFORM rebuild_absence_days(OLD.tenant_id, OLD.employee_id,
                                 OLD.start_date, COALESCE(OLD.end_date, OLD.start_date));
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS sync_absence_from_leave_request ON public.leave_requests;
CREATE TRIGGER sync_absence_from_leave_request
  -- `reason` fait partie de la liste : c'est le justificatif d'un congé, et
  -- l'arrivée d'un justificatif doit faire repasser le jour de « missing » à
  -- « provided ». Sans cette colonne, A07 restait rouge.
  AFTER INSERT OR UPDATE OF status, start_date, end_date, leave_type, employee_id, reason
  ON public.leave_requests
  FOR EACH ROW EXECUTE FUNCTION public.sync_absence_from_leave_request();

CREATE OR REPLACE FUNCTION public.sync_absence_from_sick_leave()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_from date;
  v_to   date;
BEGIN
  IF NEW.employee_id IS NULL OR NEW.tenant_id IS NULL THEN RETURN NEW; END IF;

  v_from := LEAST(COALESCE(OLD.start_date, NEW.start_date), NEW.start_date);
  v_to   := GREATEST(COALESCE(OLD.end_date, NEW.end_date), NEW.end_date);
  PERFORM rebuild_absence_days(NEW.tenant_id, NEW.employee_id, v_from, v_to);
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS sync_absence_from_sick_leave ON public.sick_leaves;
CREATE TRIGGER sync_absence_from_sick_leave
  AFTER INSERT OR UPDATE OF status, start_date, end_date, leave_type, employee_id, medical_certificate_url
  ON public.sick_leaves
  FOR EACH ROW EXECUTE FUNCTION public.sync_absence_from_sick_leave();

CREATE OR REPLACE FUNCTION public.sync_absence_from_stoppage()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_from date;
  v_to   date;
BEGIN
  IF NEW.employee_id IS NULL OR NEW.tenant_id IS NULL THEN RETURN NEW; END IF;

  v_from := LEAST(COALESCE(OLD.start_date, NEW.start_date), NEW.start_date);
  v_to   := GREATEST(COALESCE(OLD.end_date, OLD.reprise_date, OLD.start_date,
                              NEW.end_date, NEW.reprise_date, NEW.start_date),
                     COALESCE(NEW.end_date, NEW.reprise_date, NEW.start_date));
  PERFORM rebuild_absence_days(NEW.tenant_id, NEW.employee_id, v_from, v_to);
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS sync_absence_from_stoppage ON public.work_stoppages;
CREATE TRIGGER sync_absence_from_stoppage
  AFTER INSERT OR UPDATE OF status, start_date, end_date, reprise_date, employee_id, medical_certificate_url
  ON public.work_stoppages
  FOR EACH ROW EXECUTE FUNCTION public.sync_absence_from_stoppage();

CREATE OR REPLACE FUNCTION public.sync_absence_from_timesheet()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.employee_id IS NULL OR NEW.tenant_id IS NULL OR NEW.date IS NULL THEN RETURN NEW; END IF;

  PERFORM rebuild_absence_days(NEW.tenant_id, NEW.employee_id, NEW.date, NEW.date);

  IF TG_OP = 'UPDATE' AND OLD.date IS DISTINCT FROM NEW.date AND OLD.employee_id IS NOT NULL THEN
    PERFORM rebuild_absence_days(OLD.tenant_id, OLD.employee_id, OLD.date, OLD.date);
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS sync_absence_from_timesheet ON public.timesheets;
CREATE TRIGGER sync_absence_from_timesheet
  AFTER INSERT OR UPDATE OF absence_type, date, employee_id, absence_reason
  ON public.timesheets
  FOR EACH ROW EXECUTE FUNCTION public.sync_absence_from_timesheet();


-- ============================================================
-- 6. L'API de lecture, écrite UNE fois et utilisée partout
-- ============================================================

-- Le libellé français du type — le refus doit nommer ce qu'il refuse.
CREATE OR REPLACE FUNCTION public.absence_kind_label(p_kind text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE p_kind
    WHEN 'annual'        THEN 'congé payé'
    WHEN 'rtt'           THEN 'RTT / récupération'
    WHEN 'sick'          THEN 'maladie'
    WHEN 'work_accident' THEN 'accident du travail'
    WHEN 'maternity'     THEN 'maternité / paternité'
    WHEN 'unpaid'        THEN 'congé sans solde'
    WHEN 'personal'      THEN 'absence personnelle'
    WHEN 'mission'       THEN 'mission'
    WHEN 'stoppage'      THEN 'arrêt de travail'
    WHEN 'unjustified'   THEN 'absence non justifiée'
    ELSE p_kind END
$$;

-- La question simple : que se passe-t-il ce jour-là ?
CREATE OR REPLACE FUNCTION public.absence_kind_on(p_tenant uuid, p_employee uuid, p_day date)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_kind text;
BEGIN
  PERFORM assert_absence_tenant(p_tenant);
  SELECT d.absence_kind INTO v_kind FROM employee_absence_days d
   WHERE d.tenant_id = p_tenant AND d.employee_id = p_employee AND d.day = p_day;
  RETURN v_kind;
END $$;

-- Le test rapide pour les gardes : le travail est-il bloqué ce jour-là ?
CREATE OR REPLACE FUNCTION public.absence_blocks_work_on(p_tenant uuid, p_employee uuid, p_day date)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_blocks boolean;
BEGIN
  PERFORM assert_absence_tenant(p_tenant);
  SELECT d.blocks_work INTO v_blocks FROM employee_absence_days d
   WHERE d.tenant_id = p_tenant AND d.employee_id = p_employee AND d.day = p_day;
  RETURN COALESCE(v_blocks, false);
END $$;

CREATE OR REPLACE FUNCTION public.is_employee_absent(p_employee uuid, p_day date)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT COALESCE((SELECT d.blocks_work FROM employee_absence_days d
                    WHERE d.employee_id = p_employee AND d.day = p_day
                      AND d.tenant_id = current_tenant_id()), false)
$$;

CREATE OR REPLACE FUNCTION public.absence_allows_expenses_on(p_tenant uuid, p_employee uuid, p_day date)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_allows boolean;
BEGIN
  PERFORM assert_absence_tenant(p_tenant);
  SELECT d.allows_expenses INTO v_allows FROM employee_absence_days d
   WHERE d.tenant_id = p_tenant AND d.employee_id = p_employee AND d.day = p_day;
  -- Hors absence, les frais restent possibles : c'est le défaut.
  RETURN COALESCE(v_allows, true);
END $$;

-- Les jours d'absence qui COMPTENT pour la paie : ni week-end, ni férié.
-- « Une absence ne se cumule pas avec un férié : deux lignes pour un jour payé
-- une fois » (plan W9 §3.7).
CREATE OR REPLACE FUNCTION public.absence_working_days(
  p_tenant uuid, p_employee uuid, p_from date, p_to date
)
RETURNS integer
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_n integer;
BEGIN
  PERFORM assert_absence_tenant(p_tenant);
  SELECT count(*)::integer INTO v_n
    FROM employee_absence_days d
   WHERE d.tenant_id = p_tenant AND d.employee_id = p_employee
     AND d.day BETWEEN p_from AND p_to
     AND extract(isodow FROM d.day) BETWEEN 1 AND 5
     AND NOT EXISTS (
       SELECT 1 FROM public_holidays h
        WHERE h.holiday_date = d.day
          AND COALESCE(h.is_working_day, false) = false
          AND (h.tenant_id = p_tenant OR h.tenant_id IS NULL));
  RETURN v_n;
END $$;

COMMENT ON FUNCTION public.absence_working_days(uuid, uuid, date, date) IS
  'W9 / TRV-11 — les jours du registre qui comptent pour la paie : hors week-end et hors férié non travaillé.';

-- Dérogation accordée à l'avance (astreinte, intervention urgente) : portée par
-- un workflow VALIDÉ pour ce jour et ce salarié. Un identifiant inventé
-- n'autorise rien.
CREATE OR REPLACE FUNCTION public.absence_override_valid(
  p_workflow_id uuid, p_tenant uuid, p_employee uuid, p_day date
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_ok boolean;
BEGIN
  PERFORM assert_absence_tenant(p_tenant);
  SELECT p_workflow_id IS NOT NULL AND EXISTS (
    SELECT 1
      FROM approval_workflows w
     WHERE w.id = p_workflow_id
       AND w.tenant_id = p_tenant
       AND w.active = true
       AND w.entity_type = 'absence_override'
       AND EXISTS (
         SELECT 1 FROM jsonb_array_elements(COALESCE(w.steps, '[]'::jsonb)) s
          WHERE s->>'employee_id' = p_employee::text
            AND s->>'status' = 'approved'
            AND (s->>'from')::date <= p_day
            AND COALESCE((s->>'to')::date, (s->>'from')::date) >= p_day))
    INTO v_ok;
  RETURN COALESCE(v_ok, false);
END $$;

COMMENT ON FUNCTION public.absence_override_valid(uuid, uuid, uuid, date) IS
  'W9 §3.6 — une dérogation n''est honorée que si le workflow est actif et approuvé pour CE salarié et CE jour.';

-- ── Le refus RÉDIGÉ (W9 : « jamais un silence ») ────────────────────────────
-- Le message nomme le type, la date et le module : c'est ce que l'écran
-- affiche. Un test qui se contente d'un `check_violation` anonyme ne prouve
-- rien sur ce que l'utilisateur voit.
CREATE OR REPLACE FUNCTION public.assert_not_absent(
  p_employee uuid,
  p_day      date,
  p_context  text,
  p_override_workflow_id uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tenant uuid;
  v_row    employee_absence_days;
BEGIN
  IF p_employee IS NULL OR p_day IS NULL THEN RETURN; END IF;

  v_tenant := current_tenant_id();
  SELECT d.* INTO v_row
    FROM employee_absence_days d
   WHERE d.employee_id = p_employee
     AND d.day = p_day
     AND d.tenant_id = COALESCE(v_tenant, d.tenant_id)
   LIMIT 1;

  IF NOT FOUND OR NOT v_row.blocks_work THEN RETURN; END IF;

  -- L'échappatoire est DANS le modèle : une dérogation dûment validée.
  IF absence_override_valid(p_override_workflow_id,
                            COALESCE(v_tenant, v_row.tenant_id), p_employee, p_day) THEN
    RETURN;
  END IF;

  RAISE EXCEPTION 'Absence « % » (%) le % : % refusé (%s).',
    v_row.absence_kind, absence_kind_label(v_row.absence_kind),
    to_char(p_day, 'DD/MM/YYYY'), COALESCE(p_context, 'traitement'), v_row.origin
    USING ERRCODE = 'check_violation',
          HINT = 'Une dérogation validée (approval_workflows, entity_type = absence_override) lève ce refus.';
END $$;

COMMENT ON FUNCTION public.assert_not_absent(uuid, date, text, uuid) IS
  'W9 — lève une exception RÉDIGÉE si le jour est une absence bloquante : le message nomme le type, la date et le module.';

-- Les frais : refusés un jour d'absence, sauf mission (qui les autorise).
CREATE OR REPLACE FUNCTION public.assert_can_claim_expense(
  p_employee uuid,
  p_day      date,
  p_override_workflow_id uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tenant uuid := current_tenant_id();
  v_row    employee_absence_days;
BEGIN
  IF p_employee IS NULL OR p_day IS NULL THEN RETURN; END IF;

  SELECT d.* INTO v_row
    FROM employee_absence_days d
   WHERE d.employee_id = p_employee AND d.day = p_day
     AND d.tenant_id = COALESCE(v_tenant, d.tenant_id)
   LIMIT 1;

  IF NOT FOUND OR v_row.allows_expenses THEN RETURN; END IF;

  IF absence_override_valid(p_override_workflow_id,
                            COALESCE(v_tenant, v_row.tenant_id), p_employee, p_day) THEN
    RETURN;
  END IF;

  RAISE EXCEPTION 'Absence « % » (%) le % : note de frais refusée (%s).',
    v_row.absence_kind, absence_kind_label(v_row.absence_kind),
    to_char(p_day, 'DD/MM/YYYY'), v_row.origin
    USING ERRCODE = 'check_violation',
          HINT = 'Seule une mission autorise une note de frais un jour d''absence.';
END $$;

COMMENT ON FUNCTION public.assert_can_claim_expense(uuid, date, uuid) IS
  'W9 / TRV-06, TRV-10 — une note de frais est refusée un jour d''absence, sauf mission (allows_expenses).';


-- ── Pour les écrans : le calendrier d'absence du salarié ────────────────────
-- Le front lit par cette fonction, jamais « en recopiant » la logique de
-- priorité : la société vient du jeton (current_tenant_id()).
CREATE OR REPLACE FUNCTION public.absence_calendar(
  p_employee uuid DEFAULT NULL,
  p_from     date DEFAULT (date_trunc('month', CURRENT_DATE))::date,
  p_to       date DEFAULT NULL
)
RETURNS TABLE (employee_id uuid, employee_name text, day date, absence_kind text,
               absence_label text, origin text, justification_state text,
               blocks_work boolean, allows_expenses boolean, paid boolean,
               pay_rule_code text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tenant uuid := current_tenant_id();
  v_to     date := COALESCE(p_to, (date_trunc('month', CURRENT_DATE) + interval '1 month - 1 day')::date);
BEGIN
  IF v_tenant IS NULL THEN
    RAISE EXCEPTION 'absence_calendar : aucune société active' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF v_to < p_from OR v_to - p_from > 400 THEN
    RAISE EXCEPTION 'absence_calendar : plage invalide (% → %)', p_from, v_to
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  RETURN QUERY
  SELECT d.employee_id, e.name, d.day, d.absence_kind,
         absence_kind_label(d.absence_kind) AS label,
         d.origin, d.justification_state, d.blocks_work, d.allows_expenses,
         d.paid, d.pay_rule_code
    FROM employee_absence_days d
    JOIN employees e ON e.id = d.employee_id AND e.tenant_id = d.tenant_id
   WHERE d.tenant_id = v_tenant
     AND d.day BETWEEN p_from AND v_to
     AND (p_employee IS NULL OR d.employee_id = p_employee)
   ORDER BY d.day, e.name;
END $$;

COMMENT ON FUNCTION public.absence_calendar(uuid, date, date) IS
  'W9 — le calendrier d''absence de la société active, pour les écrans (calendrier RH, contrôle de paie).';

-- Le résumé chiffré d'une plage : ce que l'écran et le contrôle de paie lisent.
CREATE OR REPLACE FUNCTION public.absence_summary(
  p_tenant uuid, p_employee uuid, p_from date, p_to date
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v jsonb;
BEGIN
  PERFORM assert_absence_tenant(p_tenant);
  SELECT jsonb_build_object(
    'employee_id', p_employee,
    'from', p_from,
    'to', p_to,
    'days_total', (SELECT count(*) FROM employee_absence_days d
                    WHERE d.tenant_id = p_tenant AND d.employee_id = p_employee
                      AND d.day BETWEEN p_from AND p_to),
    'days_paid', (SELECT count(*) FROM employee_absence_days d
                   WHERE d.tenant_id = p_tenant AND d.employee_id = p_employee
                     AND d.day BETWEEN p_from AND p_to AND d.paid),
    'days_unpaid', (SELECT count(*) FROM employee_absence_days d
                     WHERE d.tenant_id = p_tenant AND d.employee_id = p_employee
                       AND d.day BETWEEN p_from AND p_to AND NOT d.paid),
    'working_days', absence_working_days(p_tenant, p_employee, p_from, p_to),
    'unjustified_days', (SELECT count(*) FROM employee_absence_days d
                          WHERE d.tenant_id = p_tenant AND d.employee_id = p_employee
                            AND d.day BETWEEN p_from AND p_to
                            AND d.absence_kind = 'unjustified'),
    'by_kind', COALESCE((SELECT jsonb_object_agg(k.absence_kind, k.n)
                          FROM (SELECT d.absence_kind, count(*) AS n
                                  FROM employee_absence_days d
                                 WHERE d.tenant_id = p_tenant AND d.employee_id = p_employee
                                   AND d.day BETWEEN p_from AND p_to
                                 GROUP BY d.absence_kind) k), '{}'::jsonb))
    INTO v;
  RETURN v;
END $$;

COMMENT ON FUNCTION public.absence_summary(uuid, uuid, date, date) IS
  'W9 — le résumé du registre : jours totaux, payés, non payés, travaillés, non justifiés, et la répartition par type.';


-- ============================================================
-- 7. TRV-15 — le solde de congés : débité à l'approbation, restitué
--     à l'annulation, recalculable
-- ============================================================
-- Le mouvement vit en base, jamais dans l'écran : c'est ce qui le rend vrai
-- quel que soit le chemin d'écriture (appel direct compris). `remaining` est
-- toujours recalculé, jamais incrémenté à la main.

-- Les types qui touchent un SOLDES de congés (table de vérité W9 §3.3 :
-- maladie, sans solde et mission n'ont « aucun effet » sur le solde).
CREATE OR REPLACE FUNCTION public.leave_type_affects_balance(p_leave_type text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT COALESCE(p_leave_type IN ('annual', 'rtt', 'recovery'), false)
$$;

CREATE OR REPLACE FUNCTION public.apply_leave_balance_movement()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_old_pending numeric := 0;
  v_old_taken   numeric := 0;
  v_new_pending numeric := 0;
  v_new_taken   numeric := 0;
  v_same_type   boolean;
BEGIN
  IF NEW.employee_id IS NULL OR NEW.tenant_id IS NULL THEN RETURN NEW; END IF;

  IF leave_type_affects_balance(NEW.leave_type) THEN
    v_new_pending := CASE WHEN NEW.status = 'pending'  THEN COALESCE(NEW.days, 0) ELSE 0 END;
    v_new_taken   := CASE WHEN NEW.status = 'approved' THEN COALESCE(NEW.days, 0) ELSE 0 END;
  END IF;

  v_same_type := (TG_OP = 'INSERT') OR (OLD.leave_type IS NOT DISTINCT FROM NEW.leave_type);

  IF TG_OP = 'UPDATE' AND NOT v_same_type THEN
    IF leave_type_affects_balance(OLD.leave_type) THEN
      v_old_pending := CASE WHEN OLD.status = 'pending'  THEN COALESCE(OLD.days, 0) ELSE 0 END;
      v_old_taken   := CASE WHEN OLD.status = 'approved' THEN COALESCE(OLD.days, 0) ELSE 0 END;
    END IF;
    -- Deux soldes distincts : l'ancien est débité en sens inverse.
    PERFORM move_leave_balance(OLD.tenant_id, OLD.employee_id, OLD.leave_type,
                               OLD.start_date, -v_old_taken, -v_old_pending);
    PERFORM move_leave_balance(NEW.tenant_id, NEW.employee_id, NEW.leave_type,
                               NEW.start_date, v_new_taken, v_new_pending);
    RETURN NEW;
  END IF;

  IF v_same_type AND TG_OP = 'UPDATE' THEN
    IF leave_type_affects_balance(OLD.leave_type) THEN
      v_old_pending := CASE WHEN OLD.status = 'pending'  THEN COALESCE(OLD.days, 0) ELSE 0 END;
      v_old_taken   := CASE WHEN OLD.status = 'approved' THEN COALESCE(OLD.days, 0) ELSE 0 END;
    END IF;
  END IF;

  -- Rien n'a bougé : ne pas réécrire le solde pour rien.
  IF TG_OP = 'UPDATE'
     AND v_old_pending = v_new_pending AND v_old_taken = v_new_taken
     AND OLD.start_date = NEW.start_date THEN
    RETURN NEW;
  END IF;

  PERFORM move_leave_balance(NEW.tenant_id, NEW.employee_id, NEW.leave_type, NEW.start_date,
                             v_new_taken - v_old_taken, v_new_pending - v_old_pending);
  RETURN NEW;
END $$;

COMMENT ON FUNCTION public.apply_leave_balance_movement() IS
  'W9 / TRV-15 — le mouvement de solde d''un congé : pending à la demande, taken à l''approbation, restitution à l''annulation. En base, donc vrai pour tout chemin d''écriture.';


-- Le mouvement élémentaire : un delta de « pris » et un delta de « en attente ».
-- `remaining` est TOUJOURS recalculé, jamais incrémenté à la main.
CREATE OR REPLACE FUNCTION public.move_leave_balance(
  p_tenant uuid, p_employee uuid, p_leave_type text, p_ref_date date,
  p_taken_delta numeric, p_pending_delta numeric
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_year integer;
BEGIN
  IF NOT leave_type_affects_balance(p_leave_type) THEN RETURN; END IF;
  IF COALESCE(p_taken_delta, 0) = 0 AND COALESCE(p_pending_delta, 0) = 0 THEN RETURN; END IF;
  PERFORM assert_absence_tenant(p_tenant);
  v_year := extract(year FROM COALESCE(p_ref_date, CURRENT_DATE))::integer;

  INSERT INTO leave_balances
    (tenant_id, employee_id, leave_type, year, acquired, taken, pending, remaining)
  VALUES (p_tenant, p_employee, p_leave_type, v_year, 0,
          COALESCE(p_taken_delta, 0), COALESCE(p_pending_delta, 0), 0)
  ON CONFLICT (employee_id, leave_type, year) DO UPDATE
    SET taken   = COALESCE(leave_balances.taken, 0) + EXCLUDED.taken,
        pending = COALESCE(leave_balances.pending, 0) + EXCLUDED.pending,
        updated_at = now();

  -- Une restitution ne rend jamais « pris » ni « en attente » négatifs.
  UPDATE leave_balances b
     SET taken   = GREATEST(COALESCE(b.taken, 0), 0),
         pending = GREATEST(COALESCE(b.pending, 0), 0)
   WHERE b.tenant_id = p_tenant AND b.employee_id = p_employee
     AND b.leave_type = p_leave_type AND b.year = v_year;

  UPDATE leave_balances b
     SET remaining = COALESCE(b.acquired, 0) + COALESCE(b.carry_over, 0)
                     - COALESCE(b.taken, 0) - COALESCE(b.pending, 0),
         updated_at = now()
   WHERE b.tenant_id = p_tenant AND b.employee_id = p_employee
     AND b.leave_type = p_leave_type AND b.year = v_year;
END $$;

COMMENT ON FUNCTION public.move_leave_balance(uuid, uuid, text, date, numeric, numeric) IS
  'W9 / TRV-15 — déplace un solde de congés par deltas et recalcule `remaining`.';

-- « Recalculable par rebuild » : le solde est reconstruit depuis les demandes.
CREATE OR REPLACE FUNCTION public.rebuild_leave_balances(
  p_tenant uuid, p_employee uuid, p_year integer
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_n   integer := 0;
  r     record;
BEGIN
  PERFORM assert_absence_tenant(p_tenant);

  FOR r IN
    SELECT lr.leave_type AS lt,
           COALESCE(SUM(CASE WHEN lr.status = 'approved' THEN COALESCE(lr.days, 0) ELSE 0 END), 0) AS taken,
           COALESCE(SUM(CASE WHEN lr.status = 'pending'  THEN COALESCE(lr.days, 0) ELSE 0 END), 0) AS pending
      FROM leave_requests lr
     WHERE lr.tenant_id = p_tenant AND lr.employee_id = p_employee
       AND extract(year FROM lr.start_date)::integer = p_year
       AND leave_type_affects_balance(lr.leave_type)
     GROUP BY lr.leave_type
  LOOP
    PERFORM move_leave_balance(p_tenant, p_employee, r.lt, make_date(p_year, 1, 1),
                               -COALESCE((SELECT b.taken FROM leave_balances b
                                           WHERE b.tenant_id = p_tenant AND b.employee_id = p_employee
                                             AND b.leave_type = r.lt AND b.year = p_year), 0)
                               + r.taken,
                               -COALESCE((SELECT b.pending FROM leave_balances b
                                           WHERE b.tenant_id = p_tenant AND b.employee_id = p_employee
                                             AND b.leave_type = r.lt AND b.year = p_year), 0)
                               + r.pending);
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END $$;

COMMENT ON FUNCTION public.rebuild_leave_balances(uuid, uuid, integer) IS
  'W9 / TRV-15 — reconstruit les soldes (taken/pending) d''une année depuis les demandes, sans repartir de l''historique incrémental.';

DROP TRIGGER IF EXISTS apply_leave_balance ON public.leave_requests;
CREATE TRIGGER apply_leave_balance
  AFTER INSERT OR UPDATE OF status, days, start_date, leave_type, employee_id
  ON public.leave_requests
  FOR EACH ROW EXECUTE FUNCTION public.apply_leave_balance_movement();


-- ============================================================
-- 8. `affects_pay` : l'écran des règles disait une chose fausse
-- ============================================================
-- MESURÉ : les quatre règles semées portaient `affects_pay = false`, y compris
-- « Congé sans solde » — dont le seul effet en paie EST la retenue. L'écran
-- « Règles de congés » affichait donc « n'affecte pas la paie » pour la règle
-- qui la déduit. Le socle global est corrigé ici ; une société qui a sa propre
-- règle garde la sienne (c'est un choix explicite, pas un défaut).
UPDATE leave_rules
   SET affects_pay = true
 WHERE tenant_id IS NULL AND leave_type IN ('unpaid', 'personal') AND affects_pay = false;

-- ============================================================
-- 9. Droits : rien pour le visiteur non connecté (H09)
-- ============================================================
REVOKE ALL ON FUNCTION public.absence_kind_priority(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.absence_kind_flags(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.absence_kind_label(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.absence_leave_rule(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.absence_justification_delay(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.assert_absence_tenant(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.rebuild_absence_days(uuid, uuid, date, date) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.absence_kind_on(uuid, uuid, date) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.absence_blocks_work_on(uuid, uuid, date) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.is_employee_absent(uuid, date) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.absence_allows_expenses_on(uuid, uuid, date) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.absence_working_days(uuid, uuid, date, date) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.absence_override_valid(uuid, uuid, uuid, date) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.assert_not_absent(uuid, date, text, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.assert_can_claim_expense(uuid, date, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.absence_calendar(uuid, date, date) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.absence_summary(uuid, uuid, date, date) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.leave_type_affects_balance(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.move_leave_balance(uuid, uuid, text, date, numeric, numeric) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.rebuild_leave_balances(uuid, uuid, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.apply_leave_balance_movement() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.sync_absence_from_leave_request() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.sync_absence_from_sick_leave() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.sync_absence_from_stoppage() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.sync_absence_from_timesheet() FROM PUBLIC, anon;

-- Ce que les ÉCRANS appellent (RPC PostgREST) et ce que les gardes appellent.
GRANT EXECUTE ON FUNCTION public.absence_kind_priority(text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.absence_kind_flags(text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.absence_kind_label(text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.absence_leave_rule(uuid, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.absence_justification_delay(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.assert_absence_tenant(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.rebuild_absence_days(uuid, uuid, date, date) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.absence_kind_on(uuid, uuid, date) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.absence_blocks_work_on(uuid, uuid, date) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_employee_absent(uuid, date) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.absence_allows_expenses_on(uuid, uuid, date) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.absence_working_days(uuid, uuid, date, date) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.absence_override_valid(uuid, uuid, uuid, date) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.assert_not_absent(uuid, date, text, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.assert_can_claim_expense(uuid, date, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.absence_calendar(uuid, date, date) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.absence_summary(uuid, uuid, date, date) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.leave_type_affects_balance(text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.move_leave_balance(uuid, uuid, text, date, numeric, numeric) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.rebuild_leave_balances(uuid, uuid, integer) TO authenticated, service_role;

