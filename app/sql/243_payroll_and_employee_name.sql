-- ============================================================
-- 243_payroll_and_employee_name.sql — RH-01, RH-02, RH-03, RH-04
--
-- Audit des modules hors comptabilité (23/09), § RH (17 écrans) et § Paie.
-- Mesuré sur base neuve à la 234 (migrations antérieures seules), scénarios T01 → T05 de
-- `243_payroll_and_employee_name_tests.sql` :
--
--   RH-01  Les écrans RH affichent « ${employees.first_name} ${employees.
--          last_name} » (CPFPage:84, CareerHistoryPage:95, MedicalExamsPage:97,
--          Phase4Pages:105…). Aucun chemin n'écrit ces colonnes : la fiche est
--          créée avec `name` (« Amina Waberi T01 »), et l'écran affiche
--          « null null ». Mesuré : 9 fiches déjà incomplètes dans une base
--          neuve, parce que les suites de paie créent des salariés par `name`.
--   RH-02  DEUX `calculate_payslip` cohabitent : `(uuid, text)` — la version à
--          taux fictifs (22 % salarié, 10 % d'impôt, 42 % patronal) de la 87 —
--          et `(uuid, text, uuid)` — le moteur légal de la 153. L'écran omet
--          `p_pay_run_id` quand aucun lot n'est choisi (businessFunctions.ts:18)
--          et PostgREST résout alors la surcharge à DEUX arguments : les taux
--          fictifs étaient atteignables en production.
--   RH-03  `sync_timesheet_to_payroll` insérait ses éléments sans regarder
--          s'ils existaient : une seconde approbation du même pointage créait
--          4 lignes au lieu de 2, et une troisième 6.
--   RH-04  Deux calculs contradictoires des heures supplémentaires : le
--          pointage les mesure sur l'horaire prévu (`overtime_minutes`), le
--          déclencheur les recalculait en « heures au-delà de 7 par jour »
--          (constante qui ignore `employees.weekly_hours`). Le bulletin
--          additionne les deux quantités (`element_type IN ('overtime',
--          'timesheet_hours')`) : 11 h d'heures supplémentaires pour une
--          journée de 9 h.
--
-- CORRECTIFS
--   1. Un déclencheur remplit `first_name`/`last_name` à partir de `name` (et
--      l'inverse quand le nom manque), quelle que soit la porte d'entrée, et
--      les fiches existantes sont reprises (RH-01).
--   2. `calculate_payslip(uuid, text)` est supprimée : il ne reste que le
--      moteur légal, que PostgREST atteint aussi pour un appel à deux
--      arguments (le troisième porte une valeur par défaut) (RH-02).
--   3. Le déclencheur de pointage met à jour la ligne existante au lieu d'en
--      créer une seconde, sous un verrou consultatif par pointage (RH-03).
--   4. Une seule mesure des heures supplémentaires : `timesheet_minutes` du
--      pointage, converti en heures. La ligne « Heures travaillées » reste
--      (elle est traduite dans les trois langues), mais n'entre plus dans le
--      total des heures supplémentaires du bulletin (RH-04).
-- ============================================================

-- ------------------------------------------------------------
-- 1. La fiche salarié a toujours un prénom et un nom (RH-01)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION sync_employee_name_fields()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_first text := NULLIF(btrim(COALESCE(NEW.first_name, '')), '');
  v_last  text := NULLIF(btrim(COALESCE(NEW.last_name, '')), '');
  v_name  text := NULLIF(btrim(COALESCE(NEW.name, '')), '');
  v_pos   int;
BEGIN
  IF v_first IS NULL AND v_last IS NULL AND v_name IS NOT NULL THEN
    v_pos := position(' ' in v_name);
    IF v_pos = 0 THEN
      NEW.first_name := v_name;
    ELSE
      NEW.first_name := substr(v_name, 1, v_pos - 1);
      NEW.last_name := NULLIF(btrim(substr(v_name, v_pos + 1)), '');
    END IF;
  ELSIF v_name IS NULL AND (v_first IS NOT NULL OR v_last IS NOT NULL) THEN
    NEW.name := btrim(COALESCE(v_first, '') || ' ' || COALESCE(v_last, ''));
  END IF;

  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS sync_employee_name_fields ON employees;
CREATE TRIGGER sync_employee_name_fields
  BEFORE INSERT OR UPDATE ON employees
  FOR EACH ROW EXECUTE FUNCTION sync_employee_name_fields();

-- Reprise des fiches existantes
UPDATE employees
   SET first_name = split_part(btrim(name), ' ', 1),
       last_name = NULLIF(btrim(substr(btrim(name), length(split_part(btrim(name), ' ', 1)) + 1)), '')
 WHERE COALESCE(btrim(first_name), '') = ''
   AND COALESCE(btrim(last_name), '') = ''
   AND COALESCE(btrim(name), '') <> '';

-- ------------------------------------------------------------
-- 2. Une seule version de la paie (RH-02)
--    La 89 avait déjà supprimé cette surcharge ; la 188 (resynchronisation du
--    schéma de production) l'a rapportée de la production. C'est donc ici
--    qu'il faut la retirer pour de bon — et le contrôle de la suite 236 veille.
-- ------------------------------------------------------------
DROP FUNCTION IF EXISTS calculate_payslip(uuid, text);

-- ------------------------------------------------------------
-- 3. Le pointage alimente la paie une fois, et une seule (RH-03, RH-04)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION sync_timesheet_to_payroll()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
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
        'timesheet_hours', 'Heures ' || to_char(NEW.date, 'DD/MM'), NEW.hours, 0, 0, 'timesheet', NEW.id, false);
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
          'overtime', 'Heures supp ' || to_char(NEW.date, 'DD/MM'), v_overtime_hours, 0, 0, 'timesheet', NEW.id, false);
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
END $$;

REVOKE ALL ON FUNCTION sync_employee_name_fields() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION sync_employee_name_fields() TO service_role;
GRANT EXECUTE ON FUNCTION sync_timesheet_to_payroll() TO service_role;

-- ------------------------------------------------------------
-- 4. Le bulletin ne compte plus les heures supplémentaires deux fois (RH-04)
--    Corps repris VERBATIM de la version en vigueur (153, repris par 191 puis
--    212) : la seule ligne modifiée est l'agrégat `v_overtime_hours`, qui
--    additionnait les quantités de 'overtime' ET de 'timesheet_hours'. Le
--    reste — PMSS, CSG/CRDS, plafond, réduction générale, cumuls, clarifiée —
--    est identique au caractère près, pour que la comparaison soit lisible.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.calculate_payslip(p_employee_id uuid, p_period text, p_pay_run_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_tid uuid := current_tenant_id();
  v_emp RECORD;
  v_period_start date;
  v_period_end date;
  v_period_year int;
  v_period_month int;

  -- Paramètres légaux
  v_pmss numeric;
  v_csg_deductible_rate numeric;
  v_csg_non_deductible_rate numeric;
  v_crds_rate numeric;
  v_csg_crds_base_pct numeric;
  v_csg_crds_multiple numeric;
  v_taux_neutre numeric;
  v_reduction_gen_t numeric;

  -- Éléments variables
  v_overtime_pay numeric := 0;
  v_overtime_hours numeric := 0;
  v_bonus numeric := 0;
  v_advance_deduction numeric := 0;
  v_pay_recall numeric := 0;
  v_expense_reimbursement numeric := 0;
  v_unpaid_leave_deduction numeric := 0;
  v_other_deductions numeric := 0;
  v_meal_vouchers numeric := 0;
  v_transport_allowance numeric := 0;

  -- Brut
  v_base_salary numeric;
  v_total_gross numeric;

  -- Cotisations
  v_ss_employee numeric := 0;       -- cotisations salariales (sécu + retraite + chômage + santé)
  v_ss_employer numeric := 0;       -- cotisations patronales
  v_csg_deductible numeric := 0;
  v_csg_non_deductible numeric := 0;
  v_crds numeric := 0;
  v_csg_crds_total numeric := 0;
  v_reduction_generale numeric := 0;

  -- Assiettes
  v_csg_crds_base numeric;          -- assiette CSG/CRDS
  v_ceiling_base numeric;           -- assiette plafonnée (PMSS)
  v_net_social numeric;             -- net social (brut - cotisations déductibles)
  v_net_taxable numeric;            -- net imposable
  v_income_tax numeric;
  v_total_deductions numeric;
  v_net_payable numeric;

  -- Grille fiscale
  v_grid_id uuid;
  v_grid_version text;
  v_grid_line RECORD;
  v_line_amount_emp numeric;
  v_line_amount_er numeric;
  v_line_base numeric;
  v_line_ceiling numeric;
  v_cumulative_used numeric;
  v_cumulative_available numeric;

  -- Cumuls
  v_cum_gross_ytd numeric := 0;
  v_cum_ceiling_base_ytd numeric := 0;
  v_ve_count int := 0;             -- nombre d'éléments variables intégrés

  -- Avecholding tax
  v_withholding_rate numeric;
  v_withholding_source text;

  -- Numérotation
  v_payslip_number text;
  v_payslip_id uuid;
  v_clarified_id uuid;
  v_line_order int;
  v_slip_lines jsonb := '[]'::jsonb;

  -- Pays du tenant
  v_country_code text := 'FR';
  v_tenant RECORD;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  -- Charger l'employé
  SELECT * INTO v_emp FROM employees WHERE id = p_employee_id AND tenant_id = v_tid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Employé non trouvé: %', p_employee_id;
  END IF;

  -- Calculer les bornes de période
  v_period_start := (p_period || '-01')::date;
  v_period_end := (v_period_start + INTERVAL '1 month - 1 day')::date;
  v_period_year := EXTRACT(YEAR FROM v_period_start)::int;
  v_period_month := EXTRACT(MONTH FROM v_period_start)::int;

  -- Pays du tenant
  SELECT country_code, legislation_pack_code INTO v_tenant
  FROM tenants WHERE id = v_tid;
  IF v_tenant.country_code IS NOT NULL THEN
    v_country_code := v_tenant.country_code;
  ELSIF v_tenant.legislation_pack_code IS NOT NULL THEN
    v_country_code := v_tenant.legislation_pack_code;
  END IF;

  -- ── Charger les paramètres légaux ──
  v_pmss := get_legal_parameter('PMSS', v_country_code, v_period_start, v_tid);
  v_csg_deductible_rate := get_legal_parameter('CSG_DEDUCTIBLE', v_country_code, v_period_start, v_tid);
  v_csg_non_deductible_rate := get_legal_parameter('CSG_NON_DEDUCTIBLE', v_country_code, v_period_start, v_tid);
  v_crds_rate := get_legal_parameter('CRDS', v_country_code, v_period_start, v_tid);
  v_csg_crds_base_pct := get_legal_parameter('CSG_CRDS_BASE', v_country_code, v_period_start, v_tid);
  v_csg_crds_multiple := get_legal_parameter('CGSS_BASE_MULTIPLE', v_country_code, v_period_start, v_tid);
  v_taux_neutre := get_legal_parameter('TAUX_NEUTRE', v_country_code, v_period_start, v_tid);
  v_reduction_gen_t := get_legal_parameter('REDUCTION_GEN_T', v_country_code, v_period_start, v_tid);

  -- ── Éléments variables (si pay_run_id fourni) ──
  IF p_pay_run_id IS NOT NULL THEN
    SELECT
      COALESCE(SUM(CASE WHEN ve.element_type = 'overtime' THEN COALESCE(ve.amount, 0) ELSE 0 END), 0),
      -- RH-04 : les heures supplementaires ne sont comptees qu'une fois, par la
      -- ligne 'overtime' mesuree au pointage. 'timesheet_hours' reste la ligne
      -- d'heures travaillees, mais n'entre plus dans ce total (11 h pour 9 h
      -- faites).
      COALESCE(SUM(CASE WHEN ve.element_type = 'overtime' THEN COALESCE(ve.quantity, 0) ELSE 0 END), 0),
      COALESCE(SUM(CASE WHEN ve.element_type = 'bonus' THEN COALESCE(ve.amount, 0) ELSE 0 END), 0),
      COALESCE(SUM(CASE WHEN ve.element_type = 'advance_deduction' THEN COALESCE(ve.amount, 0) ELSE 0 END), 0),
      COALESCE(SUM(CASE WHEN ve.element_type = 'pay_recall' THEN COALESCE(ve.amount, 0) ELSE 0 END), 0),
      COALESCE(SUM(CASE WHEN ve.element_type = 'expense_reimbursement' THEN COALESCE(ve.amount, 0) ELSE 0 END), 0),
      COALESCE(SUM(CASE WHEN ve.element_type = 'unpaid_leave_deduction' THEN COALESCE(ve.amount, 0) ELSE 0 END), 0),
      COALESCE(SUM(CASE WHEN ve.element_type IN ('other_deductions', 'other') THEN COALESCE(ve.amount, 0) ELSE 0 END), 0),
      COALESCE(SUM(CASE WHEN ve.element_type = 'meal_vouchers' THEN COALESCE(ve.amount, 0) ELSE 0 END), 0),
      COALESCE(SUM(CASE WHEN ve.element_type = 'transport_allowance' THEN COALESCE(ve.amount, 0) ELSE 0 END), 0)
    INTO v_overtime_pay, v_overtime_hours, v_bonus, v_advance_deduction,
         v_pay_recall, v_expense_reimbursement, v_unpaid_leave_deduction,
         v_other_deductions, v_meal_vouchers, v_transport_allowance
    FROM payroll_variable_elements ve
    WHERE ve.pay_run_id = p_pay_run_id
      AND ve.employee_id = p_employee_id
      AND ve.tenant_id = v_tid
      AND COALESCE(ve.integrated, false) = false;

    -- Compter les éléments variables pour l'affichage UI
    SELECT count(*) INTO v_ve_count
    FROM payroll_variable_elements ve
    WHERE ve.pay_run_id = p_pay_run_id
      AND ve.employee_id = p_employee_id
      AND ve.tenant_id = v_tid
      AND COALESCE(ve.integrated, false) = false;
  END IF;

  -- ── Calcul du brut ──
  v_base_salary := COALESCE(COALESCE(v_emp.base_salary, v_emp.salary), 0);
  v_total_gross := v_base_salary + v_overtime_pay + v_bonus + v_pay_recall
    - v_unpaid_leave_deduction;

  IF v_total_gross < 0 THEN
    v_total_gross := 0;
  END IF;

  -- ── Assiette plafonnée (PMSS) ──
  v_ceiling_base := LEAST(v_total_gross, v_pmss);

  -- ── Assiette CSG/CRDS ──
  -- 98,25 % du brut si brut <= 4 × PMSS, sinon 100 %
  IF v_total_gross <= v_csg_crds_multiple * v_pmss THEN
    v_csg_crds_base := v_total_gross * v_csg_crds_base_pct / 100;
  ELSE
    v_csg_crds_base := v_total_gross;
  END IF;

  -- ── Charger la grille fiscale active ──
  SELECT g.id INTO v_grid_id
  FROM payroll_tax_grids g
  WHERE (g.tenant_id = v_tid OR g.tenant_id IS NULL)
    AND g.country_code = v_country_code
    AND g.status = 'active'
    AND g.effective_from <= v_period_start
    AND COALESCE(g.effective_to, '9999-12-31'::date) >= v_period_end
  ORDER BY g.tenant_id NULLS LAST, g.created_at DESC
  LIMIT 1;

  v_grid_version := COALESCE(v_grid_id::text, 'fallback');

  -- ── Calcul des cotisations via la grille ──
  IF v_grid_id IS NOT NULL THEN
    FOR v_grid_line IN
      SELECT * FROM payroll_tax_grid_lines
      WHERE grid_id = v_grid_id
        AND COALESCE(section, 'contribution') IN ('contribution', 'employer')
      ORDER BY sort_order
    LOOP
      -- Calcul de l'assiette selon base_type
      v_line_base := v_total_gross; -- défaut 'gross'

      -- Appliquer le plafond selon ceiling_type
      IF v_grid_line.ceiling_type = 'pmss' THEN
        v_line_ceiling := v_pmss * COALESCE(v_grid_line.ceiling_multiplier, 1);
        v_line_base := LEAST(v_line_base, v_line_ceiling);
      ELSIF v_grid_line.ceiling_type = 'multiple_pmss' THEN
        v_line_ceiling := v_pmss * COALESCE(v_grid_line.ceiling_multiplier, 1);
        v_line_base := LEAST(v_line_base, v_line_ceiling);
      ELSIF v_grid_line.ceiling_type = 'fixed' THEN
        v_line_base := LEAST(v_line_base, COALESCE(v_grid_line.ceiling_value, v_line_base));
      END IF;

      -- Montants
      v_line_amount_emp := round(v_line_base * COALESCE(v_grid_line.rate_employee, 0) / 100, 2);
      v_line_amount_er := round(v_line_base * COALESCE(v_grid_line.rate_employer, 0) / 100, 2);

      -- CSG/CRDS : assiette spécifique
      IF v_grid_line.is_csg_crds THEN
        v_line_base := v_csg_crds_base;
        IF v_grid_line.csg_type = 'deductible' THEN
          v_csg_deductible := round(v_csg_crds_base * v_csg_deductible_rate / 100, 2);
          v_line_amount_emp := v_csg_deductible;
        ELSIF v_grid_line.csg_type = 'non_deductible' THEN
          v_csg_non_deductible := round(v_csg_crds_base * v_csg_non_deductible_rate / 100, 2);
          v_line_amount_emp := v_csg_non_deductible;
        ELSIF v_grid_line.csg_type = 'crds' THEN
          v_crds := round(v_csg_crds_base * v_crds_rate / 100, 2);
          v_line_amount_emp := v_crds;
        END IF;
      END IF;

      v_ss_employee := v_ss_employee + v_line_amount_emp;
      v_ss_employer := v_ss_employer + v_line_amount_er;

      -- Réduction générale
      IF v_grid_line.eligible_reduction_generale AND v_reduction_gen_t > 0 THEN
        -- Coefficient Fillon simplifié : T × (1,3 × SMIC / brut - 1) plafonné à T
        v_reduction_generale := round(
          v_reduction_gen_t * GREATEST(0, 1.3 * get_legal_parameter('SMIC_M', v_country_code, v_period_start, v_tid) / NULLIF(v_total_gross, 0) - 1) / 100 * v_total_gross,
          2
        );
        v_reduction_generale := LEAST(v_reduction_generale, v_ss_employer);
        v_ss_employer := GREATEST(0, v_ss_employer - v_reduction_generale);
      END IF;
    END LOOP;
  ELSE
    -- Fallback : taux légaux français 2025 si aucune grille configurée
    v_ss_employee := round(v_total_gross * 22.0 / 100, 2);  -- approximation légale
    v_ss_employer := round(v_total_gross * 42.0 / 100, 2);  -- approximation légale
    v_csg_deductible := round(v_csg_crds_base * v_csg_deductible_rate / 100, 2);
    v_csg_non_deductible := round(v_csg_crds_base * v_csg_non_deductible_rate / 100, 2);
    v_crds := round(v_csg_crds_base * v_crds_rate / 100, 2);
  END IF;

  v_csg_crds_total := v_csg_deductible + v_csg_non_deductible + v_crds;

  -- ── Net social et net imposable ──
  v_net_social := round(v_total_gross - v_ss_employee - v_csg_deductible, 2);
  v_net_taxable := round(v_net_social - v_csg_non_deductible - v_crds, 2);
  IF v_net_taxable < 0 THEN v_net_taxable := 0; END IF;

  -- ── Impôt sur le revenu (PAS) ──
  v_withholding_rate := COALESCE(v_emp.withholding_tax_rate, 0);
  v_withholding_source := COALESCE(v_emp.withholding_rate_source, CASE WHEN v_emp.withholding_tax_rate IS NOT NULL THEN 'dgfip' ELSE 'neutral' END);

  IF v_withholding_rate > 0 THEN
    v_income_tax := round(v_net_taxable * v_withholding_rate / 100, 2);
  ELSE
    -- Taux neutre par défaut
    v_income_tax := round(v_net_taxable * v_taux_neutre / 100, 2);
  END IF;

  -- ── Total déductions et net à payer ──
  v_total_deductions := round(v_ss_employee + v_csg_crds_total + v_income_tax
    + v_advance_deduction + v_other_deductions, 2);

  v_net_payable := round(v_total_gross - v_total_deductions + v_expense_reimbursement
    + v_meal_vouchers + v_transport_allowance, 2);

  -- ── Cumuls YTD (régularisation progressive) ──
  SELECT COALESCE(SUM(gross), 0), COALESCE(SUM(ceiling_base), 0)
  INTO v_cum_gross_ytd, v_cum_ceiling_base_ytd
  FROM payroll_cumulative
  WHERE employee_id = p_employee_id
    AND tenant_id = v_tid
    AND year = v_period_year
    AND month < v_period_month;

  -- ── Mettre à jour les cumuls ──
  PERFORM upsert_payroll_cumulative(
    p_employee_id, v_period_year, v_period_month,
    v_total_gross, v_net_taxable, v_ceiling_base, v_pmss - v_ceiling_base,
    v_net_taxable, v_net_social,
    v_ss_employee, v_ss_employer,
    v_income_tax, v_csg_deductible, v_csg_non_deductible, v_crds,
    v_reduction_generale
  );

  -- ── Construire les lignes de détail pour audit ──
  v_slip_lines := jsonb_build_array(
    jsonb_build_object('label', 'Salaire de base', 'amount', v_base_salary, 'type', 'gross'),
    jsonb_build_object('label', 'Heures supplémentaires', 'amount', v_overtime_pay, 'type', 'overtime')
  )
  || CASE WHEN v_bonus > 0 THEN jsonb_build_array(jsonb_build_object('label', 'Prime', 'amount', v_bonus, 'type', 'bonus')) ELSE '[]'::jsonb END
  || CASE WHEN v_pay_recall <> 0 THEN jsonb_build_array(jsonb_build_object('label', 'Rappel de paie', 'amount', v_pay_recall, 'type', 'pay_recall')) ELSE '[]'::jsonb END
  || jsonb_build_array(
    jsonb_build_object('label', 'Cotisations sociales', 'amount', -v_ss_employee, 'type', 'social_charges'),
    jsonb_build_object('label', 'CSG/CRDS', 'amount', -v_csg_crds_total, 'type', 'csg_crds'),
    jsonb_build_object('label', 'Impôt sur le revenu (PAS)', 'amount', -v_income_tax, 'type', 'income_tax')
  )
  || CASE WHEN v_advance_deduction > 0 THEN jsonb_build_array(jsonb_build_object('label', 'Acompte sur salaire', 'amount', -v_advance_deduction, 'type', 'advance_deduction')) ELSE '[]'::jsonb END
  || CASE WHEN v_unpaid_leave_deduction > 0 THEN jsonb_build_array(jsonb_build_object('label', 'Congé sans solde', 'amount', -v_unpaid_leave_deduction, 'type', 'unpaid_leave_deduction')) ELSE '[]'::jsonb END
  || CASE WHEN v_other_deductions > 0 THEN jsonb_build_array(jsonb_build_object('label', 'Autres déductions', 'amount', -v_other_deductions, 'type', 'other_deductions')) ELSE '[]'::jsonb END
  || CASE WHEN v_expense_reimbursement > 0 THEN jsonb_build_array(jsonb_build_object('label', 'Remboursement de frais', 'amount', v_expense_reimbursement, 'type', 'expense_reimbursement')) ELSE '[]'::jsonb END
  || CASE WHEN v_meal_vouchers > 0 THEN jsonb_build_array(jsonb_build_object('label', 'Titres-restaurant', 'amount', v_meal_vouchers, 'type', 'meal_vouchers')) ELSE '[]'::jsonb END
  || CASE WHEN v_transport_allowance > 0 THEN jsonb_build_array(jsonb_build_object('label', 'Indemnité transport', 'amount', v_transport_allowance, 'type', 'transport')) ELSE '[]'::jsonb END;

  -- ── Créer ou mettre à jour le bulletin ──
  -- Chercher un bulletin existant pour cet employé et cette période
  SELECT id INTO v_payslip_id
  FROM pay_slips
  WHERE employee_id = p_employee_id
    AND tenant_id = v_tid
    AND period_start = v_period_start
  LIMIT 1;

  v_payslip_number := COALESCE(
    (SELECT number FROM pay_slips WHERE id = v_payslip_id),
    'BS-' || p_period || '-' || lpad(substr(p_employee_id::text, 1, 4), 4, '0')
  );

  IF v_payslip_id IS NOT NULL THEN
    UPDATE pay_slips SET
      gross_salary = v_base_salary,
      overtime_pay = v_overtime_pay,
      bonus = v_bonus,
      total_gross = v_total_gross,
      social_security_employee = v_ss_employee,
      income_tax = v_income_tax,
      other_deductions = v_csg_crds_total + v_advance_deduction + v_other_deductions,
      total_deductions = v_total_deductions,
      net_salary = v_net_payable,
      employer_contributions = v_ss_employer,
      calc_inputs = jsonb_build_object(
        'gridVersion', v_grid_version,
        'pmss', v_pmss,
        'ceilingBase', v_ceiling_base,
        'csgDeductible', v_csg_deductible,
        'csgNonDeductible', v_csg_non_deductible,
        'crds', v_crds,
        'netSocial', v_net_social,
        'netTaxable', v_net_taxable,
        'reductionGenerale', v_reduction_generale,
        'withholdingRate', v_withholding_rate,
        'withholdingSource', v_withholding_source,
        'overtimeHours', v_overtime_hours,
        'mealVouchers', v_meal_vouchers,
        'transportAllowance', v_transport_allowance,
        'advanceDeduction', v_advance_deduction,
        'payRecall', v_pay_recall,
        'expenseReimbursement', v_expense_reimbursement,
        'unpaidLeaveDeduction', v_unpaid_leave_deduction,
        'otherDeductions', v_other_deductions,
        'cumulativeGrossYTD', v_cum_gross_ytd + v_total_gross,
        'cumulativeCeilingBaseYTD', v_cum_ceiling_base_ytd + v_ceiling_base,
        'variableElementCount', v_ve_count,
        'countryCode', v_country_code
      )
    WHERE id = v_payslip_id AND tenant_id = v_tid;
  ELSE
    INSERT INTO pay_slips (
      tenant_id, number, pay_run_id, employee_id,
      period_start, period_end,
      gross_salary, overtime_pay, bonus, total_gross,
      social_security_employee, income_tax, other_deductions, total_deductions,
      net_salary, employer_contributions, status,
      calc_inputs
    ) VALUES (
      v_tid, v_payslip_number, p_pay_run_id, p_employee_id,
      v_period_start, v_period_end,
      v_base_salary, v_overtime_pay, v_bonus, v_total_gross,
      v_ss_employee, v_income_tax, v_csg_crds_total + v_advance_deduction + v_other_deductions, v_total_deductions,
      v_net_payable, v_ss_employer, 'draft',
      jsonb_build_object(
        'gridVersion', v_grid_version,
        'pmss', v_pmss,
        'ceilingBase', v_ceiling_base,
        'csgDeductible', v_csg_deductible,
        'csgNonDeductible', v_csg_non_deductible,
        'crds', v_crds,
        'netSocial', v_net_social,
        'netTaxable', v_net_taxable,
        'reductionGenerale', v_reduction_generale,
        'withholdingRate', v_withholding_rate,
        'withholdingSource', v_withholding_source,
        'overtimeHours', v_overtime_hours,
        'mealVouchers', v_meal_vouchers,
        'transportAllowance', v_transport_allowance,
        'advanceDeduction', v_advance_deduction,
        'payRecall', v_pay_recall,
        'expenseReimbursement', v_expense_reimbursement,
        'unpaidLeaveDeduction', v_unpaid_leave_deduction,
        'otherDeductions', v_other_deductions,
        'cumulativeGrossYTD', v_cum_gross_ytd + v_total_gross,
        'cumulativeCeilingBaseYTD', v_cum_ceiling_base_ytd + v_ceiling_base,
        'variableElementCount', v_ve_count,
        'countryCode', v_country_code
      )
    )
    RETURNING id INTO v_payslip_id;
  END IF;

  -- ── Créer ou mettre à jour pay_slip_clarified ──
  INSERT INTO pay_slip_clarified (
    tenant_id, pay_slip_id, employee_id, period,
    gross_salary, social_charges_employee, social_charges_employer,
    income_tax, net_before_tax, net_after_tax, total_deductions, lines
  ) VALUES (
    v_tid, v_payslip_id, p_employee_id, p_period,
    v_total_gross, v_ss_employee, v_ss_employer,
    v_income_tax, v_net_social, v_net_payable, v_total_deductions, v_slip_lines
  )
  ON CONFLICT (pay_slip_id) DO UPDATE SET
    gross_salary = EXCLUDED.gross_salary,
    social_charges_employee = EXCLUDED.social_charges_employee,
    social_charges_employer = EXCLUDED.social_charges_employer,
    income_tax = EXCLUDED.income_tax,
    net_before_tax = EXCLUDED.net_before_tax,
    net_after_tax = EXCLUDED.net_after_tax,
    total_deductions = EXCLUDED.total_deductions,
    lines = EXCLUDED.lines;

  -- ── Marquer les éléments variables comme intégrés ──
  IF p_pay_run_id IS NOT NULL THEN
    UPDATE payroll_variable_elements
    SET integrated = true
    WHERE pay_run_id = p_pay_run_id
      AND employee_id = p_employee_id
      AND tenant_id = v_tid;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'employee_id', p_employee_id,
    'period', p_period,
    'pay_slip_id', v_payslip_id,
    'gross_salary', v_base_salary,
    'overtime_pay', v_overtime_pay,
    'bonus', v_bonus,
    'total_gross', v_total_gross,
    'social_security_employee', v_ss_employee,
    'csg_deductible', v_csg_deductible,
    'csg_non_deductible', v_csg_non_deductible,
    'crds', v_crds,
    'csg_crds_total', v_csg_crds_total,
    'income_tax', v_income_tax,
    'other_deductions', v_csg_crds_total + v_advance_deduction + v_other_deductions,
    'total_deductions', v_total_deductions,
    'net_salary', v_net_payable,
    'employer_contributions', v_ss_employer,
    'net_social', v_net_social,
    'net_taxable', v_net_taxable,
    'ceiling_base', v_ceiling_base,
    'pmss', v_pmss,
    'reduction_generale', v_reduction_generale,
    'withholding_rate', v_withholding_rate,
    'withholding_source', v_withholding_source,
    'grid_version', v_grid_version,
    'cumulative_gross_ytd', v_cum_gross_ytd + v_total_gross,
    'cumulative_ceiling_base_ytd', v_cum_ceiling_base_ytd + v_ceiling_base,
    'country_code', v_country_code
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION calculate_payslip(uuid, text, uuid) TO authenticated, service_role;
