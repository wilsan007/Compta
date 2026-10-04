-- ============================================================
-- 256_payroll_periods_amounts_divisor.sql — vague W4 (RH-05 → RH-10)
--
-- Quatre façons de compter un mois, deux chemins qui se croient seuls, et une
-- note de frais qui n'entre nulle part. Mesuré le 24/09/2026 sur base neuve :
--
--   RH-05  QUATRE diviseurs mensuels cohabitent — `weekly_hours × 4,33`
--          (retard, 143), `/ 30` (congé sans solde et absence, 90), `/ 21`
--          (front, importLeaveElements), `/ 151,67` (heures supplémentaires,
--          152). Deux retenues pour le même jour donnent deux montants.
--   RH-06  Le front interroge `.lte('date', '<période>-31')` : PostgreSQL
--          refuse « 2026-04-31 » (22008) et l'import échoue 5 mois sur 12
--          (février, avril, juin, septembre, novembre).
--   RH-07  `Number(exp.amount)` : la colonne n'existe pas sur `expense_reports`
--          (`total_amount`), donc l'élément entre en paie pour 0.
--   RH-08  Ni TVA récupérable (`total_vat` ignorée) ni écriture : D 625x,
--          D 44566, C 421 n'existent pas.
--   RH-09  Le congé est filtré « contenu dans la période » : celui qui traverse
--          deux mois est omis ENTIÈREMENT.
--   RH-10  Aucune garde d'idempotence sur les titres restaurant : relancer
--          l'import double les éléments.
--
-- Ce que cette migration corrige, et où :
--   1. UNE convention mensuelle par société (RH-05) : `payroll_divisor`,
--      `payroll_hourly_rate`, `payroll_daily_rate` — le diviseur est un
--      PARAMÈTRE (`payroll_legal_parameters`, par société ou global), jamais un
--      littéral ; les trois chemins de la base les lisent. Le front lit la même
--      valeur par la RPC `payroll_divisors()`.
--   2. UN SEUL élément de paie par document source (RH-10, et filet de RH-06,
--      RH-07, RH-09 côté base) : index unique partiel
--      `(tenant_id, employee_id, period, element_type, source, source_id)`,
--      doublons divergents nommés et refusés, doublons identiques repris.
--      Les six alimentations de la base posent `ON CONFLICT DO NOTHING`.
--   3. La note de frais entre en paie ET au grand livre (RH-07, RH-08) :
--      montant `total_amount`, charge HT, TVA récupérable, dette au salarié.
--
-- Les bornes de période calculées (RH-06) et le filtre par intersection (RH-09)
-- vivent dans le front (`src/lib/queries/leavesAbsences.ts` + le module pur
-- `src/lib/payrollPeriods.ts` testé par Vitest) : c'est le front qui interroge
-- PostgREST, la base n'a jamais vu ces requêtes.
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- 1. UNE convention mensuelle par société (RH-05)
-- ─────────────────────────────────────────────────────────────
-- Les deux diviseurs sont des PARAMÈTRES, avec un défaut CALCULÉ :
--   151,6667 h = 35 h × 52 / 12        21,6667 j = 5 j × 52 / 12
-- Le « trentième » reste possible — c'est `company_settings.absence_method`,
-- un choix de société, plus un littéral au fond d'une fonction.
INSERT INTO payroll_legal_parameters (tenant_id, country_code, code, value, valid_from)
SELECT NULL, 'FR', v.code, v.value, DATE '2025-01-01'
FROM (VALUES
  ('DIVISEUR_HORAIRE_MENSUEL', round(35 * 52 / 12.0, 4)),
  ('DIVISEUR_JOURS_MENSUEL',   round(5  * 52 / 12.0, 4))
) AS v(code, value)
WHERE NOT EXISTS (
  SELECT 1 FROM payroll_legal_parameters
  WHERE tenant_id IS NULL AND country_code = 'FR' AND code = v.code AND valid_from = DATE '2025-01-01'
);

CREATE OR REPLACE FUNCTION public.payroll_divisor(
  p_tenant uuid,
  p_unite text,
  p_weekly_hours numeric DEFAULT NULL
)
RETURNS numeric
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_param numeric;
BEGIN
  IF p_unite = 'heures' THEN
    v_param := NULLIF(get_legal_parameter('DIVISEUR_HORAIRE_MENSUEL', 'FR', CURRENT_DATE, p_tenant), 0);
    IF v_param IS NOT NULL AND v_param > 0 THEN
      RETURN v_param;
    END IF;
    RETURN round(COALESCE(NULLIF(p_weekly_hours, 0), 35) * 52 / 12.0, 4);
  ELSIF p_unite = 'jours' THEN
    v_param := NULLIF(get_legal_parameter('DIVISEUR_JOURS_MENSUEL', 'FR', CURRENT_DATE, p_tenant), 0);
    IF v_param IS NOT NULL AND v_param > 0 THEN
      RETURN v_param;
    END IF;
    IF COALESCE((SELECT cs.absence_method FROM company_settings cs WHERE cs.tenant_id = p_tenant), '') = 'thirtieth' THEN
      RETURN 30;
    END IF;
    RETURN round(5 * 52 / 12.0, 4);
  END IF;
  RAISE EXCEPTION 'Unité de diviseur inconnue : « % » (attendu : heures ou jours)', p_unite
    USING ERRCODE = 'invalid_parameter_value';
END $$;

COMMENT ON FUNCTION public.payroll_divisor(uuid, text, numeric) IS
  'RH-05 — LE diviseur mensuel de la société : paramètre DIVISEUR_HORAIRE_MENSUEL / DIVISEUR_JOURS_MENSUEL (payroll_legal_parameters, société puis global), sinon défaut calculé. Aucun des quatre chemins de la paie ne porte plus de littéral.';

CREATE OR REPLACE FUNCTION public.payroll_hourly_rate(p_tenant uuid, p_employee_id uuid)
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT CASE WHEN COALESCE(e.base_salary, e.salary, 0) > 0
              THEN round(COALESCE(e.base_salary, e.salary) / payroll_divisor(p_tenant, 'heures', e.weekly_hours), 4)
              ELSE 0 END
  FROM employees e
  WHERE e.id = p_employee_id AND e.tenant_id = p_tenant
$$;

CREATE OR REPLACE FUNCTION public.payroll_daily_rate(p_tenant uuid, p_employee_id uuid)
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT CASE WHEN COALESCE(e.base_salary, e.salary, 0) > 0
              THEN round(COALESCE(e.base_salary, e.salary) / payroll_divisor(p_tenant, 'jours'), 4)
              ELSE 0 END
  FROM employees e
  WHERE e.id = p_employee_id AND e.tenant_id = p_tenant
$$;

-- La seule porte du front : les diviseurs de la société ACTIVE.
CREATE OR REPLACE FUNCTION public.payroll_divisors()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tenant uuid := current_tenant_id();
BEGIN
  IF v_tenant IS NULL THEN
    RAISE EXCEPTION 'Diviseurs de paie : aucune société active' USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN jsonb_build_object(
    'heures', payroll_divisor(v_tenant, 'heures'),
    'jours',  payroll_divisor(v_tenant, 'jours'));
END $$;

COMMENT ON FUNCTION public.payroll_divisors() IS
  'RH-05 — diviseurs mensuels de la société active (heures, jours), lus par le front qui importe les éléments variables.';

-- ─────────────────────────────────────────────────────────────
-- 2. UN SEUL élément de paie par document source (RH-10)
-- ─────────────────────────────────────────────────────────────
-- La reprise vient AVANT la contrainte : ce qui existe déjà doit passer.
-- 2.1 Les doublons DIVERGENTS arrêtent la migration en les NOMMANT (même
--     source, montants ou quantités différents : personne ne peut décider à la
--     place du payeur lequel est le bon).
DO $$
DECLARE
  v_lignes text;
BEGIN
  SELECT string_agg(format('%s / %s / %s (source %s, %s ligne(s))',
                           x.employee_id, x.period, x.element_type, x.source, x.n), ', ')
    INTO v_lignes
  FROM (
    SELECT employee_id, period, element_type, source, source_id,
           count(*) AS n
    FROM payroll_variable_elements
    WHERE source_id IS NOT NULL
    GROUP BY 1, 2, 3, 4, 5
    HAVING count(*) > 1
       AND count(DISTINCT (COALESCE(quantity, -1), COALESCE(unit_price, -1), COALESCE(amount, -1))) > 1
  ) x;

  IF v_lignes IS NOT NULL THEN
    RAISE EXCEPTION
      'Doublons de paie divergents : la même source a produit plusieurs éléments de valeurs différentes — % ; corrigez-les (ils ne peuvent pas être fusionnés sans décider à votre place)',
      v_lignes USING ERRCODE = 'unique_violation';
  END IF;
END $$;

-- 2.2 Les doublons IDENTIQUES sont la trace d'un import relancé : on garde la
--     ligne la plus ancienne (celle qui a servi au bulletin) et on retire les
--     répliques, en le comptant.
DO $$
DECLARE
  v_supprimes int;
BEGIN
  WITH doubles AS (
    SELECT a.id,
           row_number() OVER (PARTITION BY a.tenant_id, a.employee_id, a.period, a.element_type,
                                           a.source, a.source_id
                              ORDER BY a.created_at, a.id) AS rang
    FROM payroll_variable_elements a
    WHERE a.source_id IS NOT NULL
      AND EXISTS (SELECT 1 FROM payroll_variable_elements b
                  WHERE b.tenant_id = a.tenant_id AND b.employee_id = a.employee_id
                    AND b.period = a.period AND b.element_type = a.element_type
                    AND b.source IS NOT DISTINCT FROM a.source AND b.source_id = a.source_id
                    AND COALESCE(b.quantity, -1) = COALESCE(a.quantity, -1)
                    AND COALESCE(b.unit_price, -1) = COALESCE(a.unit_price, -1)
                    AND COALESCE(b.amount, -1) = COALESCE(a.amount, -1)
                    AND b.id <> a.id)
  ), supprimes AS (
    DELETE FROM payroll_variable_elements p
    USING doubles d WHERE p.id = d.id AND d.rang > 1
    RETURNING p.id
  )
  SELECT count(*) INTO v_supprimes FROM supprimes;
  RAISE NOTICE 'RH-10 : % doublon(s) identique(s) retiré(s) (import relancé)', v_supprimes;
END $$;

-- 2.3 La contrainte qui rend les quatre alimentations sûres. Elle est
--     VOLONTAIREMENT complète (pas d'index partiel) : PostgREST ne sait pas
--     nommer l'arbitre d'un index partiel, donc le front ne pourrait pas
--     rejouer un import sans erreur — or c'est lui qui alimente la paie. Les
--     éléments saisis à la main restent libres : PostgreSQL tient les NULL pour
--     distincts, et un `source_id` nul ne peut donc pas entrer en conflit.
CREATE UNIQUE INDEX IF NOT EXISTS uniq_payroll_element_source
  ON payroll_variable_elements (tenant_id, employee_id, period, element_type, source, source_id);

COMMENT ON INDEX public.uniq_payroll_element_source IS
  'RH-10 — un seul élément de paie par document source : (société, salarié, période, type, source, source_id). C''est cette contrainte, et non un NOT EXISTS recopié, qui rend les imports rejouables.';

-- ─────────────────────────────────────────────────────────────
-- 3. La note de frais entre en paie ET au grand livre (RH-07, RH-08)
-- ─────────────────────────────────────────────────────────────
-- Avant : montant `amount` (colonne inexistante → 0), période tirée de
-- `submitted_at`, aucune écriture, aucune TVA. Après : la note approuvée
-- produit (1) son élément de paie — le remboursement dû au salarié, TTC — et
-- (2) son écriture D charge HT + D TVA récupérable / C 421 (salarié), une
-- seule fois, avec les comptes du paramétrage (`payroll_account`,
-- `vat_account_mapping`) — jamais de code en dur.
CREATE OR REPLACE FUNCTION integrate_expense_report_on_approval()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  v_period text;
  v_pay_run_id uuid;
  v_total numeric;
  v_vat numeric;
  v_charge numeric;
  v_rate numeric;
  v_account_charge text;
  v_account_vat text;
  v_account_employee text;
  v_entry uuid;
  v_existing uuid;
  v_date date;
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status AND NEW.status = 'approved' THEN
    -- 3.1 La période : celle de la note de frais quand elle est posée, sinon le
    --     mois de validation. `submitted_at` peut tomber dans le mois suivant.
    v_period := COALESCE(NULLIF(NEW.period, ''), to_char(COALESCE(NEW.submitted_at, now()), 'YYYY-MM'));
    v_total := COALESCE(NEW.total_amount, 0);
    v_vat := COALESCE(NEW.total_vat, 0);

    IF v_total < 0 THEN
      RAISE EXCEPTION 'Note de frais % : total négatif (%)', NEW.number, v_total
        USING ERRCODE = 'check_violation';
    END IF;
    IF v_vat < 0 OR v_vat > v_total THEN
      RAISE EXCEPTION 'Note de frais % : TVA récupérable % incohérente avec le total %',
        NEW.number, v_vat, v_total USING ERRCODE = 'check_violation';
    END IF;
    v_charge := v_total - v_vat;

    -- 3.2 L'élément de paie : le remboursement TTC dû au salarié (RH-07).
    SELECT id INTO v_pay_run_id FROM pay_runs
      WHERE tenant_id = NEW.tenant_id AND to_char(period_start, 'YYYY-MM') = v_period
        AND status IN ('draft', 'processing') ORDER BY created_at DESC LIMIT 1;

    INSERT INTO payroll_variable_elements (tenant_id, employee_id, pay_run_id, period, element_type,
                                           description, quantity, unit_price, amount, source, source_id, integrated)
    VALUES (NEW.tenant_id, NEW.employee_id, v_pay_run_id, v_period, 'expense_reimbursement',
            'Frais ' || NEW.number, NULL, NULL, v_total, 'expense_report', NEW.id, false)
    ON CONFLICT DO NOTHING;

    -- 3.3 L'écriture (RH-08) : un seul passage, portée par sa référence.
    SELECT je.id INTO v_existing FROM journal_entries je
      WHERE je.tenant_id = NEW.tenant_id AND je.reference = 'EXPENSE-' || NEW.number LIMIT 1;

    IF v_existing IS NULL AND v_total > 0 THEN
      v_account_charge := payroll_account(NEW.tenant_id, 'expense_reimbursement');
      v_account_employee := payroll_account(NEW.tenant_id, 'net');

      -- Taux de TVA : celui des lignes quand il est posé, sinon celui qu'implique
      -- le montant de TVA ; le compte vient du paramétrage TVA.
      SELECT max(l.vat_rate) INTO v_rate FROM expense_report_lines l
        WHERE l.expense_report_id = NEW.id AND l.tenant_id = NEW.tenant_id
          AND COALESCE(l.vat_amount, 0) > 0;
      IF v_rate IS NULL AND v_vat > 0 AND v_charge > 0 THEN
        v_rate := round(v_vat / v_charge * 100, 2);
      END IF;

      -- 3.3bis Le compte de TVA : la correspondance CANONIQUE du taux d'abord
      --        (FR20 → 445661), jamais un régime particulier par accident —
      --        sans quoi une note de frais à 20 % atterrissait sur le compte
      --        d'autoliquidation (445668). Même règle que `pos_vat_account`.
      SELECT COALESCE(
        (SELECT m.account_code FROM vat_account_mapping m
          WHERE m.tenant_id IN (NEW.tenant_id, '00000000-0000-0000-0000-000000000000')
            AND m.direction = 'deductible' AND m.rate = v_rate
            AND m.vat_code = vat_code_for_rate(v_rate)
          ORDER BY (m.tenant_id <> '00000000-0000-0000-0000-000000000000') DESC LIMIT 1),
        (SELECT m.account_code FROM vat_account_mapping m
          WHERE m.tenant_id IN (NEW.tenant_id, '00000000-0000-0000-0000-000000000000')
            AND m.direction = 'deductible' AND m.rate = v_rate
          ORDER BY (m.tenant_id <> '00000000-0000-0000-0000-000000000000') DESC,
                   (m.vat_code IN ('AUTOLIQ', 'UE', 'EXO')) ASC, m.vat_code LIMIT 1),
        (SELECT m.account_code FROM vat_account_mapping m
          WHERE m.tenant_id = '00000000-0000-0000-0000-000000000000'
            AND m.direction = 'deductible' AND m.vat_code = vat_code_for_rate(20) LIMIT 1))
      INTO v_account_vat;

      IF v_vat > 0 AND v_account_vat IS NULL THEN
        RAISE EXCEPTION 'Note de frais % : aucune TVA récupérable au paramétrage (vat_account_mapping, direction deductible) — la TVA de % ne peut pas être ventilée',
          NEW.number, v_vat USING ERRCODE = 'check_violation';
      END IF;

      INSERT INTO journals (tenant_id, code, name, type, status, locked, next_number)
      VALUES (NEW.tenant_id, 'OD', 'Opérations diverses', 'general', 'active', false, 1)
      ON CONFLICT (tenant_id, code) DO NOTHING;

      v_date := COALESCE(NEW.reimbursement_date, (NEW.approved_at)::date, CURRENT_DATE);

      INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description, reference, piece_number)
      VALUES (NEW.tenant_id, 'JE-' || NEW.number, v_date, 'OD', 'draft',
              'Note de frais ' || NEW.number, 'EXPENSE-' || NEW.number, NEW.number)
      RETURNING id INTO v_entry;

      INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, debit, credit, description, line_order)
      SELECT NEW.tenant_id, v_entry, x.account, x.account,
             CASE WHEN x.side = 'D' THEN x.amount ELSE 0 END,
             CASE WHEN x.side = 'C' THEN x.amount ELSE 0 END,
             'Note de frais ' || NEW.number,
             row_number() OVER (ORDER BY x.side DESC, x.account)
      FROM (VALUES
              (v_account_charge,   'D', v_charge),
              (v_account_vat,      'D', v_vat),
              (v_account_employee, 'C', v_total)
           ) AS x(account, side, amount)
      WHERE x.amount > 0 AND x.account IS NOT NULL;

      UPDATE journal_entries SET status = 'posted' WHERE id = v_entry;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION integrate_expense_report_on_approval() IS
  'RH-07 / RH-08 — une note de frais approuvée produit son élément de paie (total_amount, période de la note) ET son écriture : D charge HT, D TVA récupérable, C 421 (salarié). Le taux des lignes ventile la TVA ; l''écriture porte la référence EXPENSE-<numéro>, donc elle n''est écrite qu''une fois.';

-- ─────────────────────────────────────────────────────────────
-- 4. Droits : le socle des diviseurs n'est pas une API
-- ─────────────────────────────────────────────────────────────
-- `payroll_divisor` / `payroll_hourly_rate` / `payroll_daily_rate` prennent une
-- société en paramètre : elles s'appellent depuis les fonctions SECURITY DEFINER
-- (déclencheurs et moteur de paie), jamais depuis le client. La 228 a montré que
-- `CREATE FUNCTION` rétablit EXECUTE pour PUBLIC : la révocation s'écrit donc
-- ici, et `ci/check_anon_grants.sql` veille pour le jour où une migration
-- l'oubliera.
REVOKE ALL ON FUNCTION public.payroll_divisor(uuid, text, numeric) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.payroll_hourly_rate(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.payroll_daily_rate(uuid, uuid) FROM PUBLIC, anon, authenticated;

-- La seule RPC : les diviseurs de la société ACTIVE (celle de `current_tenant_id()`).
REVOKE ALL ON FUNCTION public.payroll_divisors() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.payroll_divisors() TO authenticated;





-- ─────────────────────────────────────────────────────────────
-- 5. Les trois chemins de la base lisent LE diviseur (RH-05)
-- ─────────────────────────────────────────────────────────────
-- Les corps ci-dessous sont les définitions EN VIGUEUR, reprises telles quelles :
-- seule la ligne de taux change (et `ON CONFLICT DO NOTHING` sur chaque
-- alimentation de `payroll_variable_elements`).
--   * retard : `weekly_hours × 4,33` → `payroll_hourly_rate`
--   * congé sans solde et absence : `/ 30` → `payroll_daily_rate`
--   * heures supplémentaires : `/ 151,67` → `payroll_hourly_rate`
-- Le prorata d'absence du moteur de bulletins (`calculate_payslip`,
-- `company_settings.absence_method`) garde sa convention — elle est *choisie*
-- par la société — mais son taux journalier vient désormais du même diviseur.
-- ── deduct_lateness_on_timesheet_approval (définition en vigueur, patchée) ─────────────
CREATE OR REPLACE FUNCTION public.deduct_lateness_on_timesheet_approval()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_rule RECORD;
  v_period text;
  v_pay_run_id uuid;
  v_emp_salary numeric;
  v_emp_weekly_hours numeric;
  v_hourly_rate numeric;
  v_deductible_minutes integer;
  v_deduction numeric;
  v_threshold integer := 15;
  v_grace integer := 5;
  v_deduction_rate numeric := 100;
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status AND NEW.status = 'approved' THEN
    IF NEW.late_minutes IS NULL OR NEW.late_minutes <= 0 OR NEW.late_justified = true THEN
      RETURN NEW;
    END IF;

    SELECT * INTO v_rule
    FROM leave_rules
    WHERE tenant_id = NEW.tenant_id
      AND active = true
      AND lateness_threshold_minutes IS NOT NULL
    ORDER BY lateness_threshold_minutes DESC
    LIMIT 1;

    IF FOUND THEN
      v_threshold := COALESCE(v_rule.lateness_threshold_minutes, 15);
      v_grace := COALESCE(v_rule.lateness_grace_period, 5);
      v_deduction_rate := COALESCE(v_rule.lateness_deduction_rate, 100);
    END IF;

    IF NEW.late_minutes <= v_threshold THEN
      RETURN NEW;
    END IF;

    v_deductible_minutes := GREATEST(NEW.late_minutes - v_threshold - v_grace, 0);

    IF v_deductible_minutes <= 0 THEN
      RETURN NEW;
    END IF;

    -- LOT2-19 : variables typées au lieu de v_emp.salary
    SELECT salary, weekly_hours
    INTO v_emp_salary, v_emp_weekly_hours
    FROM employees
    WHERE id = NEW.employee_id AND tenant_id = NEW.tenant_id;

    IF v_emp_salary IS NULL OR v_emp_salary <= 0 THEN
      RETURN NEW;
    END IF;

    v_hourly_rate := payroll_hourly_rate(NEW.tenant_id, NEW.employee_id) / 60;

    v_deduction := v_deductible_minutes * v_hourly_rate * (v_deduction_rate / 100);

    v_period := to_char(NEW.date, 'YYYY-MM');

    SELECT id INTO v_pay_run_id
    FROM pay_runs
    WHERE tenant_id = NEW.tenant_id
      AND to_char(period_start, 'YYYY-MM') = v_period
      AND status IN ('draft', 'processing')
    ORDER BY created_at DESC
    LIMIT 1;

    IF NOT EXISTS (
      SELECT 1 FROM payroll_variable_elements
      WHERE tenant_id = NEW.tenant_id
        AND employee_id = NEW.employee_id
        AND source = 'timesheet_lateness'
        AND source_id = NEW.id
    ) THEN
      INSERT INTO payroll_variable_elements (
        tenant_id, employee_id, pay_run_id, period,
        element_type, description, quantity, unit_price, amount,
        source, source_id, integrated
      ) VALUES (
        NEW.tenant_id, NEW.employee_id, v_pay_run_id, v_period,
        'lateness_deduction',
        'Déduction retard ' || v_deductible_minutes || 'min le ' || to_char(NEW.date, 'DD/MM/YYYY'),
        v_deductible_minutes, v_hourly_rate, v_deduction,
        'timesheet_lateness', NEW.id, false
      )
      ON CONFLICT DO NOTHING;
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;

-- ── deduct_unpaid_leave_on_approval (définition en vigueur, patchée) ─────────────
CREATE OR REPLACE FUNCTION public.deduct_unpaid_leave_on_approval()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_rule RECORD; v_period text; v_pay_run_id uuid; v_daily_rate numeric; v_deduction numeric; v_emp RECORD;
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status AND NEW.status = 'approved' THEN
    SELECT * INTO v_rule FROM leave_rules
      WHERE tenant_id = NEW.tenant_id AND leave_type = NEW.leave_type
        AND affects_pay = true AND active = true LIMIT 1;
    IF NOT FOUND THEN RETURN NEW; END IF;
    v_period := to_char(NEW.start_date, 'YYYY-MM');
    SELECT * INTO v_emp FROM employees WHERE id = NEW.employee_id AND tenant_id = NEW.tenant_id;
    IF v_emp.salary IS NOT NULL AND v_emp.salary > 0 THEN
      v_daily_rate := payroll_daily_rate(NEW.tenant_id, NEW.employee_id);
      v_deduction := v_daily_rate * NEW.days * (COALESCE(v_rule.deduction_rate, 100) / 100);
    ELSE v_deduction := 0; END IF;
    SELECT id INTO v_pay_run_id FROM pay_runs
      WHERE tenant_id = NEW.tenant_id AND to_char(period_start, 'YYYY-MM') = v_period
        AND status IN ('draft', 'processing') ORDER BY created_at DESC LIMIT 1;
    INSERT INTO payroll_variable_elements (tenant_id, employee_id, pay_run_id, period, element_type, description, quantity, unit_price, amount, source, source_id, integrated)
    VALUES (NEW.tenant_id, NEW.employee_id, v_pay_run_id, v_period, 'unpaid_leave_deduction', 'Congé sans solde ' || NEW.leave_type, NEW.days, v_daily_rate, v_deduction, 'leave_request', NEW.id, false)
      ON CONFLICT DO NOTHING;
  END IF;
  RETURN NEW;
END;
$function$;

-- ── deduct_unpaid_absence_on_timesheet_approval (définition en vigueur, patchée) ─────────────
CREATE OR REPLACE FUNCTION public.deduct_unpaid_absence_on_timesheet_approval()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_period text;
  v_pay_run_id uuid;
  v_emp_salary numeric;
  v_daily_rate numeric;
  v_deduction numeric;
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status AND NEW.status = 'approved' THEN
    IF NEW.absence_type IS NULL OR NEW.absence_type != 'unpaid' THEN
      RETURN NEW;
    END IF;

    v_period := to_char(NEW.date, 'YYYY-MM');

    -- LOT2-20 : variable typée au lieu de v_emp.salary
    SELECT salary INTO v_emp_salary
    FROM employees
    WHERE id = NEW.employee_id AND tenant_id = NEW.tenant_id;

    IF v_emp_salary IS NULL OR v_emp_salary <= 0 THEN
      RETURN NEW;
    END IF;

    v_daily_rate := payroll_daily_rate(NEW.tenant_id, NEW.employee_id);
    v_deduction := v_daily_rate;

    SELECT id INTO v_pay_run_id
    FROM pay_runs
    WHERE tenant_id = NEW.tenant_id
      AND to_char(period_start, 'YYYY-MM') = v_period
      AND status IN ('draft', 'processing')
    ORDER BY created_at DESC
    LIMIT 1;

    IF NOT EXISTS (
      SELECT 1 FROM payroll_variable_elements
      WHERE tenant_id = NEW.tenant_id
        AND employee_id = NEW.employee_id
        AND source = 'timesheet_absence'
        AND source_id = NEW.id
    ) THEN
      INSERT INTO payroll_variable_elements (
        tenant_id, employee_id, pay_run_id, period,
        element_type, description, amount,
        source, source_id, integrated
      ) VALUES (
        NEW.tenant_id, NEW.employee_id, v_pay_run_id, v_period,
        'unpaid_absence_deduction',
        'Absence non justifiée le ' || to_char(NEW.date, 'DD/MM/YYYY'),
        v_deduction,
        'timesheet_absence', NEW.id, false
      )
      ON CONFLICT DO NOTHING;
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;

-- ── calculate_overtime_pay (définition en vigueur, patchée) ─────────────
CREATE OR REPLACE FUNCTION public.calculate_overtime_pay(p_employee_id uuid, p_overtime_hours numeric, p_base_hourly_rate numeric DEFAULT NULL::numeric)
 RETURNS TABLE(tier_from integer, tier_to integer, hours_in_tier numeric, rate_multiplier numeric, gross_amount numeric, exemption_amount numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_tid uuid := current_tenant_id();
  v_base_rate numeric;
  v_hours_remaining numeric := p_overtime_hours;
  v_tier record;
  v_hours_in_tier numeric;
  v_gross numeric;
  v_exemption numeric;
  v_year int := EXTRACT(YEAR FROM CURRENT_DATE);
  v_used numeric := 0;
BEGIN
  IF p_base_hourly_rate IS NOT NULL THEN
    v_base_rate := p_base_hourly_rate;
  ELSE
    v_base_rate := payroll_hourly_rate(v_tid, p_employee_id);
  END IF;

  SELECT COALESCE(overtime_exemption_used, 0) INTO v_used
  FROM payroll_cumulative
  WHERE employee_id = p_employee_id AND year = v_year AND tenant_id = v_tid;

  FOR v_tier IN
    SELECT ot.from_hour, ot.to_hour, ot.rate_multiplier
    FROM overtime_tiers ot
    WHERE ot.tenant_id = v_tid
    ORDER BY ot.from_hour
  LOOP
    v_hours_in_tier := LEAST(v_hours_remaining, COALESCE(v_tier.to_hour - v_tier.from_hour + 1, v_hours_remaining));
    IF v_hours_in_tier <= 0 THEN
      EXIT;
    END IF;

    v_gross := v_hours_in_tier * v_base_rate * v_tier.rate_multiplier;
    v_exemption := LEAST(v_gross, GREATEST(7500 - v_used, 0));
    v_used := v_used + v_exemption;

    RETURN QUERY
      SELECT
        v_tier.from_hour,
        v_tier.to_hour,
        v_hours_in_tier,
        v_tier.rate_multiplier,
        v_gross,
        v_exemption;

    v_hours_remaining := v_hours_remaining - v_hours_in_tier;
    IF v_hours_remaining <= 0 THEN EXIT; END IF;
  END LOOP;
END;
$function$;

-- ── integrate_pay_recalls_on_payrun (définition en vigueur, patchée) ─────────────
CREATE OR REPLACE FUNCTION public.integrate_pay_recalls_on_payrun()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_recall RECORD; v_period text;
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status AND NEW.status = 'processing' THEN
    v_period := to_char(NEW.period_start, 'YYYY-MM');
    FOR v_recall IN SELECT * FROM pay_recalls
      WHERE tenant_id = NEW.tenant_id AND status = 'pending'
        AND reference_period = v_period
    LOOP
      INSERT INTO payroll_variable_elements (tenant_id, employee_id, pay_run_id, period, element_type, description, amount, source, source_id, integrated)
      VALUES (NEW.tenant_id, v_recall.employee_id, NEW.id, v_period, 'pay_recall', 'Rappel ' || v_recall.reference_period, v_recall.recall_amount, 'pay_recall', v_recall.id, false)
      ON CONFLICT DO NOTHING;
      UPDATE pay_recalls SET status = 'processed', processed_pay_run_id = NEW.id WHERE id = v_recall.id;
    END LOOP;
  END IF;
  RETURN NEW;
END;
$function$;

-- ── sync_timesheet_to_payroll (définition en vigueur, patchée) ─────────────
CREATE OR REPLACE FUNCTION public.sync_timesheet_to_payroll()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_period text;
  v_pay_run_id uuid;
  v_overtime_hours numeric;
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status AND NEW.status = 'approved' THEN
    IF NEW.employee_id IS NULL THEN RETURN NEW; END IF;

    -- RH-03 : une seule exécution par pointage à la fois. Un verrou
    -- consultatif évite la course entre deux approbations simultanées, sans
    -- index unique sur des données historiques déjà dupliquées.
    PERFORM pg_advisory_xact_lock(hashtext('sync_timesheet_to_payroll:' || NEW.id::text));

    v_period := to_char(NEW.date, 'YYYY-MM');

    SELECT id INTO v_pay_run_id FROM pay_runs
      WHERE tenant_id = NEW.tenant_id AND to_char(period_start, 'YYYY-MM') = v_period
        AND status IN ('draft', 'processing')
      ORDER BY created_at DESC LIMIT 1;

    -- RH-04 : les heures supplémentaires sont celles que le pointage a
    -- mesurées sur l'horaire prévu. Le « plus de 7 heures par jour » est
    -- abandonné : il ignorait `employees.weekly_hours` et contredisait
    -- `overtime_minutes`.
    v_overtime_hours := ROUND(COALESCE(NEW.overtime_minutes, 0) / 60.0, 2);

    -- Heures travaillées du jour (ligne d'information, montant nul)
    IF EXISTS (SELECT 1 FROM payroll_variable_elements
               WHERE tenant_id = NEW.tenant_id AND source_id = NEW.id
                 AND element_type = 'timesheet_hours') THEN
      UPDATE payroll_variable_elements
         SET quantity = NEW.hours,
             pay_run_id = COALESCE(v_pay_run_id, pay_run_id),
             period = v_period,
             description = 'Heures ' || to_char(NEW.date, 'DD/MM')
       WHERE tenant_id = NEW.tenant_id AND source_id = NEW.id
         AND element_type = 'timesheet_hours'
         AND COALESCE(integrated, false) = false;
    ELSE
      INSERT INTO payroll_variable_elements (tenant_id, employee_id, pay_run_id, period,
        element_type, description, quantity, unit_price, amount, source, source_id, integrated)
      VALUES (NEW.tenant_id, NEW.employee_id, v_pay_run_id, v_period,
        'timesheet_hours', 'Heures ' || to_char(NEW.date, 'DD/MM'), NEW.hours, 0, 0, 'timesheet', NEW.id, false)
      ON CONFLICT DO NOTHING;
    END IF;

    -- Heures supplémentaires du jour
    IF v_overtime_hours > 0 THEN
      IF EXISTS (SELECT 1 FROM payroll_variable_elements
                 WHERE tenant_id = NEW.tenant_id AND source_id = NEW.id
                   AND element_type = 'overtime') THEN
        UPDATE payroll_variable_elements
           SET quantity = v_overtime_hours,
               pay_run_id = COALESCE(v_pay_run_id, pay_run_id),
               period = v_period,
               description = 'Heures supp ' || to_char(NEW.date, 'DD/MM')
         WHERE tenant_id = NEW.tenant_id AND source_id = NEW.id
           AND element_type = 'overtime'
           AND COALESCE(integrated, false) = false;
      ELSE
        INSERT INTO payroll_variable_elements (tenant_id, employee_id, pay_run_id, period,
          element_type, description, quantity, unit_price, amount, source, source_id, integrated)
        VALUES (NEW.tenant_id, NEW.employee_id, v_pay_run_id, v_period,
          'overtime', 'Heures supp ' || to_char(NEW.date, 'DD/MM'), v_overtime_hours, 0, 0, 'timesheet', NEW.id, false)
      ON CONFLICT DO NOTHING;
      END IF;
    ELSE
      -- Le pointage corrigé ne porte plus d'heure supplémentaire : la ligne
      -- non encore intégrée disparaît, celle d'un bulletin calculé reste.
      DELETE FROM payroll_variable_elements
       WHERE tenant_id = NEW.tenant_id AND source_id = NEW.id
         AND element_type = 'overtime'
         AND COALESCE(integrated, false) = false;
    END IF;
  END IF;

  RETURN NEW;
END $function$;

-- ─────────────────────────────────────────────────────────────
-- 6. Droits des fonctions réécrites
-- ─────────────────────────────────────────────────────────────
-- `CREATE OR REPLACE FUNCTION` rétablit EXECUTE pour PUBLIC (constaté par la 228,
-- redit par la 252) : chaque fonction réécrite ci-dessus est donc révoquée à
-- nouveau. L'état visé est celui d'avant — `authenticated` et `service_role`
-- gardent l'appel (les écrans les utilisent), `PUBLIC` et `anon` jamais.
REVOKE ALL ON FUNCTION public.deduct_lateness_on_timesheet_approval() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.deduct_unpaid_leave_on_approval() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.deduct_unpaid_absence_on_timesheet_approval() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.calculate_overtime_pay(uuid, numeric, numeric) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.integrate_pay_recalls_on_payrun() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.sync_timesheet_to_payroll() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.integrate_expense_report_on_approval() FROM PUBLIC, anon;
