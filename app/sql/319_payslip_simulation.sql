-- ============================================================
-- 319_payslip_simulation.sql — lot C (paie), C2 / rh-005
--
-- Recette /qa du 29/09/2026. Le simulateur de paie recalculait tout en
-- TypeScript (`src/lib/payroll.ts`) : c'était un SECOND moteur, avec ses propres
-- taux. Mesuré par la recette : 2 500 € brut → 1 798,53 € de net au
-- simulateur, contre **1 919,53 €** au moteur de la base (bulletin d'or de la
-- 276) — 121,00 € d'écart. Le chômage salarial y était compté, la CRDS
-- absente, le net imposable confondu avec le net, aucun traitement cadre, et
-- le total patronal ne correspondait pas à la somme des rubriques.
--
-- Doctrine W5 — « un seul moteur par grandeur » : le simulateur APPELLE le
-- moteur. `simulate_payslip` est ce moteur en lecture.
--
-- Ce que fait cette migration — et RIEN d'autre :
--   1. le moteur de la paie devient `payroll_compute_slip`, les lignes de la
--      276 reprises mot pour mot, plus deux paramètres **par défaut**
--      (`p_gross_override`, `p_dry_run`) ;
--   2. `calculate_payslip` garde sa signature EXACTE — le test 243 T03 la
--      verrouille — et devient l'appelant mince du noyau ;
--   3. `simulate_payslip` appelle ce noyau en lecture et rend son jsonb.
--
-- Deux garde-fous du dépôt ont vu la première version, et il a fallu les
-- écouter (ils sont dans le message de ce commit) :
--   * **243 T03** verrouille la signature publique : ajouter des paramètres à
--     `calculate_payslip` elle-même aurait déplacé le verrou. D'où le noyau.
--   * **228 T06** refuse qu'une fonction de `public` soit exécutable par
--     PUBLIC : une fonction recréée sans ACL l'est. Les deux nouvelles sont
--     donc `REVOKE … FROM PUBLIC` + `GRANT` aux rôles de l'application.
--
-- Ce qui n'est PAS fait, et pourquoi :
--   * une simulation ne consomme aucun élément variable (les éléments ne sont
--     chargés que si `p_pay_run_id` est fourni) : elle simule un salaire, pas
--     un mois déjà saisi ;
--   * `src/lib/payroll.ts` reste en place tant que ses quatre fichiers de test
--     l'utilisent ; il n'est plus appelé par aucun écran. Le supprimer est un
--     chantier à part (noté au plan).
--
-- Preuves : sql/319_payslip_simulation_tests.sql (T01 à T06, 5 rouges avant),
-- et la suite 276 rejouée sans changement de résultat.
-- ============================================================

CREATE OR REPLACE FUNCTION public.payroll_compute_slip(p_employee_id uuid, p_period text, p_pay_run_id uuid DEFAULT NULL::uuid,
                                                             p_gross_override numeric DEFAULT NULL::numeric,
                                                             p_dry_run boolean DEFAULT false)
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
  -- X3/C6 (276) : RGDU 2026, taille de l'entreprise, catégorie du salarié
  v_smic_m numeric;
  v_rgdu_tmin numeric;
  v_rgdu_tdelta numeric;
  v_rgdu_p numeric;
  v_rgdu_mult numeric;
  v_rgdu_coef numeric := 0;
  v_rgdu_base numeric := 0;          -- cotisations patronales sur lesquelles la réduction s'impute
  v_big boolean := false;            -- effectif de 50 salariés et plus
  v_category text;
  v_line_rate_er numeric;
  v_contrib jsonb := '[]'::jsonb;    -- détail ligne à ligne (tests d'or, 0,01 €)
  v_elem RECORD;                     -- un élément variable, pour son détail
  v_pas_rate numeric;

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

  -- X1-271 (H10) : calculer un bulletin l'écrit ; un lecteur ne le relance pas.
  IF NOT can_perform('pay_slips', 'update') THEN
    RAISE EXCEPTION 'Permission refusée : calcul des bulletins (pay_slips.update)' USING ERRCODE = 'insufficient_privilege';
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
  v_smic_m := get_legal_parameter('SMIC_M', v_country_code, v_period_start, v_tid);
  v_rgdu_tmin := get_legal_parameter('RGDU_TMIN', v_country_code, v_period_start, v_tid);
  v_rgdu_p := get_legal_parameter('RGDU_P', v_country_code, v_period_start, v_tid);
  v_rgdu_mult := get_legal_parameter('RGDU_SMIC_MULTIPLE', v_country_code, v_period_start, v_tid);
  v_big := get_legal_parameter('EFFECTIF_50_PLUS', v_country_code, v_period_start, v_tid) >= 1;
  v_rgdu_tdelta := get_legal_parameter(CASE WHEN v_big THEN 'RGDU_TDELTA_GE50' ELSE 'RGDU_TDELTA_LT50' END,
                                       v_country_code, v_period_start, v_tid);
  v_category := COALESCE(v_emp.payroll_category, 'non_cadre');

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
  -- C2 (319) : en simulation, le salaire.simulé prime sur celui de la fiche ;
  -- sinon on retrouve exactement le calcul du bulletin.
  v_base_salary := COALESCE(p_gross_override, COALESCE(v_emp.base_salary, v_emp.salary), 0);
  v_total_gross := v_base_salary + v_overtime_pay + v_bonus + v_pay_recall
    - v_unpaid_leave_deduction;

  IF v_total_gross < 0 THEN
    v_total_gross := 0;
  END IF;

  -- ── Assiette plafonnée (PMSS) ──
  v_ceiling_base := LEAST(v_total_gross, v_pmss);

  -- ── Assiette CSG/CRDS ──
  -- 276 : l'abattement (98,25 %) ne porte que sur la part du brut dans la limite
  -- de 4 PMSS ; au-delà, l'assiette est de 100 % (URSSAF, taux 2026). Avant : tout
  -- le brut passait à 100 % dès 4 PMSS dépassé.
  v_csg_crds_base := round(LEAST(v_total_gross, v_csg_crds_multiple * v_pmss) * v_csg_crds_base_pct / 100
                     + GREATEST(0, v_total_gross - v_csg_crds_multiple * v_pmss), 2);

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
      -- 276 : conditions d'application de la ligne
      IF COALESCE(v_grid_line.applies_to, 'all') <> 'all' AND v_grid_line.applies_to <> v_category THEN CONTINUE; END IF;
      IF v_grid_line.company_size = 'lt50' AND v_big THEN CONTINUE; END IF;
      IF v_grid_line.company_size = 'ge50' AND NOT v_big THEN CONTINUE; END IF;
      IF v_grid_line.min_gross_pmss IS NOT NULL AND v_total_gross <= v_grid_line.min_gross_pmss * v_pmss THEN CONTINUE; END IF;

      -- Calcul de l'assiette selon base_type
      v_line_base := v_total_gross; -- défaut 'gross'

      -- Appliquer le plafond selon ceiling_type
      IF v_grid_line.ceiling_type IN ('pmss', 'multiple_pmss') THEN
        v_line_ceiling := v_pmss * COALESCE(v_grid_line.ceiling_multiplier, 1);
        v_line_base := LEAST(v_line_base, v_line_ceiling);
      ELSIF v_grid_line.ceiling_type = 'fixed' THEN
        v_line_base := LEAST(v_line_base, COALESCE(v_grid_line.ceiling_value, v_line_base));
      END IF;
      -- 276 : plancher (tranche 2 = de 1 à 8 PMSS) — `floor_multiplier` n'était pas lu
      IF COALESCE(v_grid_line.floor_multiplier, 0) > 0 THEN
        v_line_base := GREATEST(0, v_line_base - v_pmss * v_grid_line.floor_multiplier);
      END IF;

      -- 276 : taux patronal lu dans un paramètre de la société (AT/MP notifié)
      v_line_rate_er := CASE WHEN v_grid_line.rate_employer_param IS NOT NULL
                             THEN get_legal_parameter(v_grid_line.rate_employer_param, v_country_code, v_period_start, v_tid)
                             ELSE COALESCE(v_grid_line.rate_employer, 0) END;

      v_line_amount_emp := round(v_line_base * COALESCE(v_grid_line.rate_employee, 0) / 100, 2);
      v_line_amount_er := round(v_line_base * v_line_rate_er / 100, 2);

      IF v_grid_line.is_csg_crds THEN
        -- CSG/CRDS : assiette et taux propres ; comptées UNE fois (276 : elles
        -- entraient aussi dans les cotisations salariales, donc deux fois au net)
        v_line_base := v_csg_crds_base;
        v_line_amount_er := 0;
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
      ELSE
        v_ss_employee := v_ss_employee + v_line_amount_emp;
        v_ss_employer := v_ss_employer + v_line_amount_er;
        IF v_grid_line.eligible_reduction_generale THEN
          v_rgdu_base := v_rgdu_base + v_line_amount_er;
        END IF;
      END IF;

      v_contrib := v_contrib || jsonb_build_object(
        'label', v_grid_line.label, 'base', round(v_line_base, 2),
        'rate_employee', COALESCE(v_grid_line.rate_employee, 0), 'employee', v_line_amount_emp,
        'rate_employer', v_line_rate_er, 'employer', v_line_amount_er);
    END LOOP;

    -- ── Réduction générale : calculée UNE fois, imputée sur les cotisations éligibles ──
    -- 276 : elle était recalculée et retranchée à chaque ligne éligible.
    IF v_rgdu_mult > 0 AND v_smic_m > 0 AND v_total_gross > 0 THEN
      -- RGDU (LFSS 2025 art. 18, décret 2025-887) : Tmin + Tdelta × [½ × (3 Smic / rémunération − 1)]^P,
      -- due sous 3 Smic ; coefficient arrondi au dix-millième, plafonné à Tmin + Tdelta
      IF v_total_gross < v_rgdu_mult * v_smic_m THEN
        v_rgdu_coef := LEAST(v_rgdu_tmin + v_rgdu_tdelta,
          round(v_rgdu_tmin + v_rgdu_tdelta * power(0.5 * (v_rgdu_mult * v_smic_m / v_total_gross - 1), v_rgdu_p), 4));
        v_reduction_generale := LEAST(round(v_rgdu_coef * v_total_gross, 2), v_rgdu_base);
      END IF;
    ELSIF v_reduction_gen_t > 0 AND v_smic_m > 0 AND v_total_gross > 0 THEN
      -- Périodes antérieures à 2026 : formule historique du moteur, appliquée une fois
      v_reduction_generale := LEAST(round(
        v_reduction_gen_t * GREATEST(0, 1.3 * v_smic_m / v_total_gross - 1) / 100 * v_total_gross, 2), v_rgdu_base);
    END IF;
    v_ss_employer := GREATEST(0, v_ss_employer - v_reduction_generale);
  ELSE
    -- Fallback : taux légaux français 2025 si aucune grille configurée
    v_ss_employee := round(v_total_gross * 22.0 / 100, 2);  -- approximation légale
    v_ss_employer := round(v_total_gross * 42.0 / 100, 2);  -- approximation légale
    v_csg_deductible := round(v_csg_crds_base * v_csg_deductible_rate / 100, 2);
    v_csg_non_deductible := round(v_csg_crds_base * v_csg_non_deductible_rate / 100, 2);
    v_crds := round(v_csg_crds_base * v_crds_rate / 100, 2);
  END IF;

  v_csg_crds_total := v_csg_deductible + v_csg_non_deductible + v_crds;

-- ── Les ÉLÉMENTS VARIABLES au détail du bulletin ────────────────────────
--
-- Ils étaient calculés juste au-dessus, en agrégat (`SUM(CASE WHEN
-- ve.element_type = …)`), et jamais restitués ligne à ligne : le bulletin
-- disait le montant, sans dire d'où il venait. La suite 326 T05/T07 le
-- mesurait — « ligne=ABSENTE » pour un acompte de 300 € et pour un rappel
-- de 500 €, alors que les deux étaient bien appliqués au net.
--
-- Un bulletin doit DIRE d'où vient chaque euro : c'est la doctrine du
-- dépôt, et c'est ce qui permet à l'éditor de relire un bulletin sans
-- rouvrir la saisie. Le signe suit le sens de l'opération — un acompte et
-- un congé sans solde sortent du net, un rappel et un remboursement y
-- entrent.
FOR v_elem IN
  SELECT ve.element_type, ve.description, ve.amount
  FROM payroll_variable_elements ve
  -- MÊME CLAUSE que l'agrégat ci-dessus (l. 217-220), et c'est indispensable :
  -- sans `employee_id`, le bulletin afficherait les éléments variables d'un
  -- AUTRE salarié — et le test T06 (sans élément de ce type, le bulletin
  -- n'invente aucune ligne) ne le verrait pas. Les deux lectures ne peuvent
  -- pas diverger.
  WHERE ve.pay_run_id = p_pay_run_id
    AND ve.employee_id = p_employee_id
    AND ve.tenant_id = v_tid
    AND COALESCE(ve.integrated, false) = false
    AND ve.amount IS NOT NULL
    AND ve.amount <> 0
  ORDER BY ve.element_type, ve.id
LOOP
  v_contrib := v_contrib || jsonb_build_object(
    'type', v_elem.element_type,
    'label', v_elem.description,
    'base', round(v_total_gross, 2),
    'rate_employee', 0, 'employee', 0,
    'rate_employer', 0, 'employer', 0,
    'amount', CASE
                WHEN v_elem.element_type IN ('advance_deduction', 'unpaid_leave_deduction')
                  THEN -abs(v_elem.amount)
                ELSE abs(v_elem.amount)
              END);
END LOOP;


  -- ── Net social et net imposable ──
  -- 276 : le net imposable garde la CSG non déductible et la CRDS (il les
  -- retranchait) ; seule la CSG déductible en sort.
  v_net_social := round(v_total_gross - v_ss_employee, 2);
  v_net_taxable := round(v_total_gross - v_ss_employee - v_csg_deductible, 2);
  IF v_net_taxable < 0 THEN v_net_taxable := 0; END IF;

  -- ── Impôt sur le revenu (PAS) ──
  v_withholding_rate := COALESCE(v_emp.withholding_tax_rate, 0);
  v_withholding_source := COALESCE(v_emp.withholding_rate_source, CASE WHEN v_emp.withholding_tax_rate IS NOT NULL THEN 'dgfip' ELSE 'neutral' END);

  IF v_withholding_rate > 0 THEN
    v_income_tax := round(v_net_taxable * v_withholding_rate / 100, 2);
  ELSE
    -- 276 : taux par défaut = GRILLE (art. 204 H CGI), lue dans la grille de la
    -- période ; un taux fixe (TAUX_NEUTRE, 10 %) ne sert qu'à défaut de grille.
    SELECT rate_employee INTO v_pas_rate
    FROM payroll_tax_grid_lines
    WHERE grid_id = v_grid_id AND section = 'tax' AND category = 'income_tax' AND line_type = 'bracket'
      AND v_net_taxable >= COALESCE(min_amount, 0)
      AND (max_amount IS NULL OR v_net_taxable < max_amount)
    ORDER BY min_amount DESC
    LIMIT 1;
    v_withholding_rate := COALESCE(v_pas_rate, v_taux_neutre);
    v_withholding_source := CASE WHEN v_pas_rate IS NOT NULL THEN 'default_grid' ELSE 'neutral' END;
    v_income_tax := round(v_net_taxable * v_withholding_rate / 100, 2);
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

  -- C2 (319) : une simulation ne RIEN n'écrit — pas de bulletin, pas de
  -- bulletin clarifié, et les éléments variables ne sont pas marqués intégrés.
  IF NOT p_dry_run THEN
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
        'countryCode', v_country_code,
        'category', v_category,
        'rgduCoefficient', v_rgdu_coef,
        'contributions', v_contrib
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
        'countryCode', v_country_code,
        'category', v_category,
        'rgduCoefficient', v_rgdu_coef,
        'contributions', v_contrib
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
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'employee_id', p_employee_id,
    'period', p_period,
    'pay_slip_id', CASE WHEN p_dry_run THEN NULL ELSE v_payslip_id END,
    'simulated', p_dry_run,
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
    'country_code', v_country_code,
    'rgdu_coefficient', v_rgdu_coef,
    'contributions', v_contrib
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM
  );
END;
$function$;
-- ============================================================
-- Le noyau : le moteur de la 276, rendu simulable
-- ============================================================
-- `payroll_compute_slip` ci-dessus EST le moteur : les 553 lignes de
-- `calculate_payslip` (migration 276) reprises mot pour mot, à quatre endroits
-- près — la fonction renommée, deux paramètres par défaut de plus, le salaire
-- simulé qui prime, et les écritures passées derrière `IF NOT p_dry_run`.
-- La suite 276 (les trois bulletins d'or au centime) le prouve.

-- `calculate_payslip` garde sa signature EXACTE : le test 243 T03 la verrouille
-- (« une seule version, la légale »), et il a raison. Elle devient l'appelant
-- mince du noyau — il n'y a plus de moteur en double.
CREATE OR REPLACE FUNCTION public.calculate_payslip(
  p_employee_id uuid,
  p_period text,
  p_pay_run_id uuid DEFAULT NULL::uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  RETURN public.payroll_compute_slip(p_employee_id, p_period, p_pay_run_id, NULL, false);
END;
$function$;

-- ============================================================
-- La simulation : le moteur, en lecture
-- ============================================================
-- `p_gross` : le salaire brut mensuel simulé. `p_period` : la période de
-- référence (les paramètres légaux et la grille en dépendent) ; le mois en
-- cours par défaut. Renvoie le même jsonb que le calcul — `simulated: true`,
-- `pay_slip_id: null` — et n'écrit rien.
CREATE OR REPLACE FUNCTION public.simulate_payslip(
  p_employee_id uuid,
  p_gross numeric,
  p_period text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_period text := COALESCE(p_period, to_char(current_date, 'YYYY-MM'));
  v_res jsonb;
BEGIN
  IF p_employee_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Aucun salarié choisi', 'simulated', true);
  END IF;
  IF p_gross IS NULL OR p_gross < 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Salaire brut simulé absent ou négatif', 'simulated', true);
  END IF;

  v_res := public.payroll_compute_slip(
    p_employee_id, v_period, NULL,
    p_gross_override => p_gross,
    p_dry_run        => true
  );
  -- Le noyau rend toujours un verdict (il avale ses exceptions) : on ne le
  -- laisse pas passer sans nommer l'échec.
  IF COALESCE((v_res ->> 'success')::boolean, false) = false THEN
    RETURN jsonb_build_object('success', false, 'simulated', true, 'error',
      COALESCE(v_res ->> 'error', 'Le moteur de paie n''a pas répondu'));
  END IF;
  RETURN v_res || jsonb_build_object('simulated', true);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM, 'simulated', true);
END;
$function$;

COMMENT ON FUNCTION public.payroll_compute_slip(uuid, text, uuid, numeric, boolean) IS
  'C2 (319) — le moteur de la paie (ex- calculate_payslip, migration 276), rendu simulable : p_gross_override remplace le salaire de base, p_dry_run interdit toute écriture.';
COMMENT ON FUNCTION public.simulate_payslip(uuid, numeric, text) IS
  'C2 (319) — le simulateur de paie appelle le moteur en lecture : mêmes paramètres, même grille, aucune écriture. Doctrine W5 : un seul moteur par grandeur.';

-- Une fonction recréée perd ses droits (`CREATE OR REPLACE` réinitialise son
-- ACL) : `calculate_payslip` redeviendrait exécutable par PUBLIC, ce que le
-- test 228 T06 refuse. On lui rend donc explicitement les droits qu'elle
-- avait, et les deux nouvelles sont traitées de même : fermées au PUBLIC,
-- ouvertes aux seuls rôles de l'application.
REVOKE ALL ON FUNCTION public.calculate_payslip(uuid, text, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.payroll_compute_slip(uuid, text, uuid, numeric, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.simulate_payslip(uuid, numeric, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.calculate_payslip(uuid, text, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.payroll_compute_slip(uuid, text, uuid, numeric, boolean) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.simulate_payslip(uuid, numeric, text) TO authenticated, service_role;
