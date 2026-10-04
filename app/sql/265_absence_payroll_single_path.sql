-- ============================================================
-- 265_absence_payroll_single_path.sql — W9 : UNE seule retenue
--                                        (TRV-11, TRV-12, TRV-13)
--
-- MESURÉ AVANT, sur base neuve (230 migrations, après 263 et 264) — et c'est le
-- piège que W9 devait désamorcer :
--
--   TRV-11  DEUX chemins de retenue coexistaient pour la même journée :
--           `deduct_unpaid_leave_on_approval` (congé sans solde approuvé) et
--           `deduct_unpaid_absence_on_timesheet_approval` (pointage d'absence
--           approuvé). Les réparer tous les deux sans les unifier aurait
--           **payé deux fois la même absence** ;
--   TRV-11 bis  le second chemin était de toute façon INERTE : il écrit
--           `element_type = 'unpaid_absence_deduction'` alors que
--           `calculate_payslip` ne lit que `'unpaid_leave_deduction'` — mesuré
--           dans le catalogue (`pg_get_functiondef(calculate_payslip)`). Un
--           troisième moteur qui ne dit pas son nom ;
--   TRV-12  rien ne savait revenir en arrière : annuler une absence laissait
--           l'élément de paie, et s'il était déjà intégré à un bulletin validé,
--           le net restait faux ;
--   TRV-13  une absence rétroactive sur une période de paie CLOSE écrivait son
--           élément dans le vide : la période ne serait plus jamais recalculée.
--
-- Ce que la 265 pose : **la paie d'absence se calcule depuis
-- `employee_absence_days`, et de nulle part ailleurs.** Les deux anciens
-- déclencheurs sont retirés ; leurs fonctions restent appelables mais délèguent.
-- ============================================================

-- ============================================================
-- 1. L'identifiant stable d'une journée d'absence
-- ============================================================
-- `payroll_variable_elements` porte l'index unique
-- `uniq_payroll_element_source (tenant, salarié, période, type, source,
-- source_id)` : `source_id` est un uuid, alors que la clé d'une journée est
-- `(société, salarié, jour)`. Il faut donc un identifiant **déterministe** :
-- recalculé à chaque `rebuild_absence_days`, il doit être IDENTIQUE, sinon
-- chaque recalcul créerait un nouvel élément (le doublon que RH-10 a fermé).
--
-- La colonne est GÉNÉRÉE, et son expression est immuable. Mesuré : la première
-- tentative, `uuid_generate_v5(…, day::text)`, est refusée par PostgreSQL —
-- « generation expression is not immutable » (un cast de `date` en texte dépend
-- de `DateStyle`). `md5` d'un entier de jours et de deux uuid l'est.
ALTER TABLE public.employee_absence_days
  ADD COLUMN IF NOT EXISTS day_uid uuid GENERATED ALWAYS AS (
    md5(tenant_id::text || ':' || employee_id::text
        || ':' || (day - DATE '2000-01-01')::text)::uuid
  ) STORED;

CREATE UNIQUE INDEX IF NOT EXISTS uniq_employee_absence_days_day_uid
  ON public.employee_absence_days (tenant_id, day_uid);

COMMENT ON COLUMN public.employee_absence_days.day_uid IS
  'W9 / TRV-11 — identifiant déterministe et stable d''une journée d''absence, pour `payroll_variable_elements.source_id`. Recalculer la journée ne crée pas un second élément.';

-- ============================================================
-- 2. TRV-11 — le producteur unique : une journée → au plus un élément
-- ============================================================
-- Le montant : le taux journalier de la société (`payroll_daily_rate`, RH-05).
-- Le type : `unpaid_leave_deduction`, celui que `calculate_payslip` retranche
-- réellement du brut.
CREATE OR REPLACE FUNCTION public.sync_absence_day_payroll(
  p_tenant   uuid,
  p_employee uuid,
  p_day      date
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_row        employee_absence_days;
  v_period     text;
  v_pay_run_id uuid;
  v_closed     boolean;
  v_rate       numeric;
  v_amount     numeric;
  v_element    uuid;
  v_desc       text;
BEGIN
  PERFORM assert_absence_tenant(p_tenant);

  SELECT d.* INTO v_row FROM employee_absence_days d
   WHERE d.tenant_id = p_tenant AND d.employee_id = p_employee AND d.day = p_day;
  IF NOT FOUND THEN
    RETURN NULL;                       -- rien à faire : la journée n'existe pas
  END IF;

  -- Un élément déjà INTÉGRÉ à un bulletin validé n'est jamais réécrit : c'est
  -- une pièce (même philosophie que les bulletins de la 256).
  IF EXISTS (SELECT 1 FROM payroll_variable_elements e
              WHERE e.tenant_id = p_tenant AND e.source = 'absence_day'
                AND e.source_id = v_row.day_uid
                AND COALESCE(e.integrated, false)) THEN
    RETURN NULL;
  END IF;

  -- La journée est payée : on retire un éventuel élément devenu faux.
  IF v_row.paid THEN
    DELETE FROM payroll_variable_elements
     WHERE tenant_id = p_tenant AND source = 'absence_day' AND source_id = v_row.day_uid
       AND COALESCE(integrated, false) = false;
    RETURN NULL;
  END IF;

  v_rate := payroll_daily_rate(p_tenant, p_employee);
  IF COALESCE(v_rate, 0) <= 0 THEN
    RETURN NULL;                       -- salarié sans salaire : rien à retenir
  END IF;
  -- Le TAUX garde la précision du diviseur (4 décimales, comme
  -- `payroll_daily_rate`) ; seule la SOMME due est arrondie au centime. Arrondir
  -- le taux à 2 décimales faisait perdre le diviseur exact que la 256 avait
  -- posé (115,3846 → 115,38), et le test T02 de la 256 l'a mesuré.
  v_amount := round(v_rate, 2);

  -- TRV-13 — si la période de la journée est CLOSE (`approved`, `closed`,
  -- `paid`), la retenue ne peut plus y entrer. Décision prise et écrite ici :
  -- elle est **régularisée sur la période ouverte courante** — jamais perdue,
  -- et jamais refusée au point d'empêcher la déclaration de l'absence.
  v_period := to_char(p_day, 'YYYY-MM');
  SELECT EXISTS (SELECT 1 FROM pay_runs pr
                  WHERE pr.tenant_id = p_tenant
                    AND to_char(pr.period_start, 'YYYY-MM') = v_period
                    AND pr.status NOT IN ('draft', 'processing', 'cancelled'))
    INTO v_closed;
  IF v_closed THEN
    v_period := to_char(CURRENT_DATE, 'YYYY-MM');
  END IF;

  SELECT pr.id INTO v_pay_run_id FROM pay_runs pr
   WHERE pr.tenant_id = p_tenant AND to_char(pr.period_start, 'YYYY-MM') = v_period
     AND pr.status IN ('draft', 'processing')
   ORDER BY pr.created_at DESC LIMIT 1;

  v_desc := CASE WHEN v_closed
                 THEN 'Régularisation absence ' || absence_kind_label(v_row.absence_kind)
                      || ' du ' || to_char(p_day, 'DD/MM/YYYY')
                 ELSE 'Absence ' || absence_kind_label(v_row.absence_kind)
                      || ' du ' || to_char(p_day, 'DD/MM/YYYY') END;

  INSERT INTO payroll_variable_elements
    (tenant_id, employee_id, pay_run_id, period, element_type, description,
     quantity, unit_price, amount, source, source_id, integrated)
  VALUES
    (p_tenant, p_employee, v_pay_run_id, v_period, 'unpaid_leave_deduction', v_desc,
     1, v_rate, v_amount, 'absence_day', v_row.day_uid, false)
  ON CONFLICT (tenant_id, employee_id, period, element_type, source, source_id)
  DO UPDATE SET amount      = EXCLUDED.amount,
                unit_price  = EXCLUDED.unit_price,
                description = EXCLUDED.description,
                pay_run_id  = COALESCE(EXCLUDED.pay_run_id, payroll_variable_elements.pay_run_id)
  RETURNING id INTO v_element;

  RETURN v_element;
END $$;

COMMENT ON FUNCTION public.sync_absence_day_payroll(uuid, uuid, date) IS
  'W9 / TRV-11 — LE producteur unique de la retenue d''absence : une journée du registre non payée donne au plus un élément `unpaid_leave_deduction`, identifié par `day_uid`. Période close → régularisation sur la période ouverte (TRV-13).';


-- ── TRV-12 — le retrait, et la contrepartie ─────────────────────────────────
-- Ce qui est DÉJÀ intégré à un bulletin validé ne se supprime pas : il se
-- contre-passe. Le schéma interdit les montants négatifs
-- (`payroll_variable_elements_amount_nonneg`) : l'inverse est donc un élément
-- **positif** du type que le moteur AJOUTE au brut — `pay_recall`, un rappel.
CREATE OR REPLACE FUNCTION public.remove_absence_day_payroll(
  p_tenant   uuid,
  p_employee uuid,
  p_day_uid  uuid
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_integrated record;
  v_n integer := 0;
BEGIN
  PERFORM assert_absence_tenant(p_tenant);

  FOR v_integrated IN
    SELECT e.amount, e.description
      FROM payroll_variable_elements e
     WHERE e.tenant_id = p_tenant AND e.employee_id = p_employee
       AND e.source = 'absence_day' AND e.source_id = p_day_uid
       AND COALESCE(e.integrated, false)
  LOOP
    INSERT INTO payroll_variable_elements
      (tenant_id, employee_id, pay_run_id, period, element_type, description,
       quantity, unit_price, amount, source, source_id, integrated)
    VALUES (p_tenant, p_employee, NULL, to_char(CURRENT_DATE, 'YYYY-MM'),
            'pay_recall',
            'Reprise d''absence annulée — ' || COALESCE(v_integrated.description, ''),
            1, v_integrated.amount, v_integrated.amount,
            'absence_day_reversal', p_day_uid, false)
    ON CONFLICT (tenant_id, employee_id, period, element_type, source, source_id)
    DO NOTHING;
    v_n := v_n + 1;
  END LOOP;

  DELETE FROM payroll_variable_elements
   WHERE tenant_id = p_tenant AND employee_id = p_employee
     AND source = 'absence_day' AND source_id = p_day_uid
     AND COALESCE(integrated, false) = false;

  RETURN v_n;
END $$;

COMMENT ON FUNCTION public.remove_absence_day_payroll(uuid, uuid, uuid) IS
  'W9 / TRV-12 — retirer la retenue d''une journée : l''élément non intégré est supprimé ; celui déjà intégré est contre-passé par un élément inverse positif (pay_recall).';

-- ── Le recalcul d'une plage, pour la reprise et pour les tests ─────────────
CREATE OR REPLACE FUNCTION public.sync_absence_to_payroll(
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
  r record;
  v_ctx uuid := current_tenant_id();
  v_n integer := 0;
BEGIN
  PERFORM assert_absence_tenant(p_tenant);
  IF p_to < p_from OR p_to - p_from > 400 THEN
    RAISE EXCEPTION 'sync_absence_to_payroll : plage invalide (% → %)', p_from, p_to
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  FOR r IN SELECT d.day, d.day_uid FROM employee_absence_days d
            WHERE d.tenant_id = p_tenant AND d.employee_id = p_employee
              AND d.day BETWEEN p_from AND p_to LOOP
    PERFORM sync_absence_day_payroll(p_tenant, p_employee, r.day);
    v_n := v_n + 1;
  END LOOP;

  -- Les journées qui ne sont plus au registre : leur retenue non intégrée part.
  FOR r IN SELECT e.source_id AS uid FROM payroll_variable_elements e
            WHERE e.tenant_id = p_tenant AND e.employee_id = p_employee
              AND e.source = 'absence_day'
              AND NOT EXISTS (SELECT 1 FROM employee_absence_days d
                               WHERE d.tenant_id = p_tenant AND d.employee_id = p_employee
                                 AND d.day_uid = e.source_id) LOOP
    PERFORM remove_absence_day_payroll(p_tenant, p_employee, r.uid);
  END LOOP;

  -- Le contexte n'est pas utilisé ici, mais la garde reste explicite pour la
  -- lecture : la fonction ne sort jamais de la société demandée.
  PERFORM 1 WHERE v_ctx IS NULL OR v_ctx = p_tenant;

  RETURN v_n;
END $$;

COMMENT ON FUNCTION public.sync_absence_to_payroll(uuid, uuid, date, date) IS
  'W9 / TRV-11 — recale la retenue de paie d''une plage d''absence : chaque journée non payée a son élément, chaque retenue orpheline est retirée.';

-- ── Le câblage : le registre EST la source, ses mouvements pilotent la paie ─
-- Le rebuild supprime puis réinsère : c'est le DELETE qui déclenche le retrait
-- (TRV-12) et l'INSERT qui déclenche la pose. Un seul chemin, pour tout le
-- monde — écran, import, correctif manuel.
CREATE OR REPLACE FUNCTION public.on_absence_day_payroll_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    PERFORM remove_absence_day_payroll(OLD.tenant_id, OLD.employee_id, OLD.day_uid);
    RETURN OLD;
  END IF;

  IF TG_OP = 'UPDATE' AND OLD.day_uid IS DISTINCT FROM NEW.day_uid THEN
    PERFORM remove_absence_day_payroll(OLD.tenant_id, OLD.employee_id, OLD.day_uid);
  END IF;

  PERFORM sync_absence_day_payroll(NEW.tenant_id, NEW.employee_id, NEW.day);
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS absence_day_payroll ON public.employee_absence_days;
CREATE TRIGGER absence_day_payroll
  AFTER INSERT OR UPDATE OF paid, absence_kind, day ON public.employee_absence_days
  FOR EACH ROW EXECUTE FUNCTION public.on_absence_day_payroll_change();

DROP TRIGGER IF EXISTS absence_day_payroll_delete ON public.employee_absence_days;
CREATE TRIGGER absence_day_payroll_delete
  AFTER DELETE ON public.employee_absence_days
  FOR EACH ROW EXECUTE FUNCTION public.on_absence_day_payroll_change();


-- ── TRV-11, le maillon manquant : un élément sans classeur ne serait LU par
--    aucun bulletin ─────────────────────────────────────────────────────────
-- MESURÉ : `calculate_payslip` ne lit les éléments variables que
-- `WHERE ve.pay_run_id = p_pay_run_id` — et **aucune** fonction du dépôt ne
-- rattache un élément à un classeur créé après lui (aucun `SET pay_run_id`
-- dans `sql/`). Un élément posé avant la création du classeur restait donc
-- orphelin : présent, invisible, jamais versé. C'est la perte silencieuse que
-- la doctrine du dépôt interdit — et elle frappait aussi les heures
-- supplémentaires, les notes de frais et les titres-restaurant.
CREATE OR REPLACE FUNCTION public.attach_pending_variables_to_pay_run()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  UPDATE payroll_variable_elements e
     SET pay_run_id = NEW.id
   WHERE e.tenant_id = NEW.tenant_id
     AND e.pay_run_id IS NULL
     AND e.period = to_char(NEW.period_start, 'YYYY-MM')
     AND COALESCE(e.integrated, false) = false;
  RETURN NEW;
END $$;

COMMENT ON FUNCTION public.attach_pending_variables_to_pay_run() IS
  'W9 / TRV-11 — rattache au classeur de paie les éléments variables du même mois qui n''en avaient pas encore : sans ce rattachement, `calculate_payslip` ne les lit jamais.';

DROP TRIGGER IF EXISTS attach_pending_variables ON public.pay_runs;
CREATE TRIGGER attach_pending_variables
  AFTER INSERT OR UPDATE OF period_start, status ON public.pay_runs
  FOR EACH ROW WHEN (NEW.status IN ('draft', 'processing'))
  EXECUTE FUNCTION public.attach_pending_variables_to_pay_run();

-- ============================================================
-- 3. Les deux anciens chemins sont DÉBRANCHÉS
-- ============================================================
-- C'est le cœur de TRV-11 : il ne suffit pas de réparer chaque chemin, il faut
-- qu'il n'en reste QU'UN. Les déclencheurs qui écrivaient des éléments de paie
-- depuis `leave_requests` et depuis `timesheets` sont retirés du dépôt.
--
-- Les fonctions restent (des appels directs peuvent exister), mais elles
-- DÉLÈGUENT au registre et n'écrivent plus rien elles-mêmes : rejouer l'ancien
-- chemin ne peut plus doubler la retenue.
DROP TRIGGER IF EXISTS deduct_unpaid_leave ON public.leave_requests;
DROP TRIGGER IF EXISTS deduct_unpaid_absence ON public.timesheets;

CREATE OR REPLACE FUNCTION public.deduct_unpaid_leave_on_approval()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Débranché par la 265 (TRV-11) : la paie d'absence vient du REGISTRE.
  -- L'appel est conservé pour ne pas casser un appelant, et il délègue.
  IF NEW.employee_id IS NOT NULL AND NEW.start_date IS NOT NULL THEN
    PERFORM sync_absence_to_payroll(NEW.tenant_id, NEW.employee_id, NEW.start_date,
                                    COALESCE(NEW.end_date, NEW.start_date));
  END IF;
  RETURN NEW;
END $$;

COMMENT ON FUNCTION public.deduct_unpaid_leave_on_approval() IS
  'DÉBRANCHÉ (265 / TRV-11) — délègue à `sync_absence_to_payroll`. Le déclencheur `deduct_unpaid_leave` a été retiré : la paie d''absence vient du registre, une seule fois.';

CREATE OR REPLACE FUNCTION public.deduct_unpaid_absence_on_timesheet_approval()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Débranché par la 265 (TRV-11). Son type d'élément
  -- (`unpaid_absence_deduction`) n'était de toute façon lu par aucun moteur :
  -- `calculate_payslip` ne connaît que `unpaid_leave_deduction`.
  IF NEW.employee_id IS NOT NULL AND NEW.date IS NOT NULL THEN
    PERFORM sync_absence_to_payroll(NEW.tenant_id, NEW.employee_id, NEW.date, NEW.date);
  END IF;
  RETURN NEW;
END $$;

COMMENT ON FUNCTION public.deduct_unpaid_absence_on_timesheet_approval() IS
  'DÉBRANCHÉ (265 / TRV-11) — délègue à `sync_absence_to_payroll`. Écrivait `unpaid_absence_deduction`, un type qu''aucun moteur de bulletin ne lit.';

-- ============================================================
-- 4. Droits
-- ============================================================
REVOKE ALL ON FUNCTION public.sync_absence_day_payroll(uuid, uuid, date) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.remove_absence_day_payroll(uuid, uuid, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.sync_absence_to_payroll(uuid, uuid, date, date) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.on_absence_day_payroll_change() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.attach_pending_variables_to_pay_run() FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.sync_absence_day_payroll(uuid, uuid, date) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.remove_absence_day_payroll(uuid, uuid, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.sync_absence_to_payroll(uuid, uuid, date, date) TO authenticated, service_role;

