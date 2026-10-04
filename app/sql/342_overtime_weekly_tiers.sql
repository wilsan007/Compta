-- ════════════════════════════════════════════════════════════════════════════
-- 342 — Partie 2, tâche 2.3 : les heures supplémentaires par TRANCHES sur la
--       semaine civile, la réduction de cotisations salariales, et UN moteur
--
-- ⚠️ NE PAS DÉPLOYER avant la signature de l'expert-comptable (D-G), comme les
--    276 et 341 : ce fichier modifie le calcul du bulletin.
-- ════════════════════════════════════════════════════════════════════════════
--
-- LE DÉFAUT, MESURÉ. Depuis la W5 (260), chaque heure supplémentaire est payée
-- au taux de la PREMIÈRE tranche, quel que soit le nombre d'heures de la
-- semaine : 15 h sup en une semaine étaient toutes majorées de 25 %. Aucune
-- réduction de cotisations n'était appliquée. Et `calculate_overtime_pay`
-- (tranches + un plafond de 7 500 € écrit en dur, année lue sur CURRENT_DATE)
-- n'avait plus AUCUN appelant : un second moteur, mort.
--
-- LA SOURCE (relevée le 04/10/2026) : service-public.gouv.fr, fiche F2391
-- « Heures supplémentaires d'un salarié du secteur privé », vérifiée le
-- 08/06/2026 — https://www.service-public.gouv.fr/particuliers/vosdroits/F2391
--   * « En l'absence de dispositions conventionnelles, les heures accomplies
--     au-delà de la durée légale hebdomadaire sont majorées de : 25 % pour les
--     8 premières heures supplémentaires travaillées dans la même semaine (de
--     la 36e à la 43e heure), 50 % pour les heures suivantes. »
--   * « Les heures supplémentaires sont décomptées par semaine civile, du lundi
--     0 heure au dimanche 24 heures. »
--   * Une convention peut fixer d'autres taux ; « chaque taux est au minimum
--     fixé à 10 % ».
--   * « Les heures supplémentaires effectuées sont exonérées des cotisations
--     salariales d'assurance vieillesse de base et complémentaire dans la
--     limite de 11,31 % du salaire. »
--   * Impôt : exonération « dans une limite de 7 500 € par an ».
--
-- CE QUE FAIT CE FICHIER.
--   1. Trois paramètres légaux datés et sourcés ; la majoration existante
--      (`MAJORATION_HEURES_SUP`, 1,25) reçoit sa source.
--   2. `payroll_overtime_week_refresh` : pour un salarié et une semaine civile,
--      répartit les heures sup des pointages APPROUVÉS (dans l'ordre des jours)
--      entre les tranches, et réécrit le montant des éléments de paie non encore
--      intégrés. Tranches : celles de la société (`overtime_tiers`) si elle en
--      a ; sinon 8 h à la majoration de la société, puis la seconde majoration.
--   3. `sync_timesheet_to_payroll` (corps de la 260, relevé en base) appelle ce
--      recalcul après chaque approbation.
--   4. `payroll_compute_slip` (corps relevé en base, 341 comprise) applique la
--      réduction de cotisations salariales sur les heures sup.
--   5. `calculate_overtime_pay` est SUPPRIMÉE : un seul moteur.
--
-- CE QU'IL NE FAIT PAS — écrit pour que personne ne le croie fait :
--   * Le SEUIL reste journalier (heures du jour − horaire prévu, 340). Le droit
--     décompte à la SEMAINE : une semaine de 10 h + 4 h + … qui ne dépasse pas
--     35 h ne devrait rien produire. Le corriger demande des semaines saisies
--     en entier — une feuille isolée ne dit pas ce qui a été fait les autres
--     jours. Les TRANCHES, elles, sont bien décidées sur le cumul hebdomadaire.
--   * L'exonération d'IMPÔT (7 500 € par an) n'est pas codée : la base exacte
--     (« net fiscal » des heures sup) n'a pas pu être établie à la source. Le
--     net imposable n'est donc pas réduit. À trancher avec l'expert.
--   * La réduction salariale est appliquée au taux plafond (11,31 %), sans
--     recalculer le taux réel de vieillesse du salarié — exact tant que ses
--     cotisations de vieillesse atteignent ce plafond, à confirmer au-delà.
--   * Le repos compensateur et le contingent annuel ne sont pas traités.
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1. Paramètres ─────────────────────────────────────────────────────────
INSERT INTO public.payroll_legal_parameters (tenant_id, country_code, code, value, valid_from, valid_to, source)
SELECT NULL, 'FR', p.code, p.value, DATE '2026-01-01', NULL, p.source
FROM (VALUES
  ('HEURES_SUP_TRANCHE_1_HEURES',         8,     '[SP-F2391] 25 % pour les 8 premières heures supplémentaires de la semaine (36e à 43e heure)'),
  ('MAJORATION_HEURES_SUP_2',             1.50,  '[SP-F2391] 50 % pour les heures suivantes (à partir de la 44e heure), à défaut de convention'),
  ('HEURES_SUP_REDUCTION_SALARIALE_PCT',  11.31, '[SP-F2391] exonération des cotisations salariales d''assurance vieillesse de base et complémentaire, dans la limite de 11,31 % du salaire')
) AS p(code, value, source)
WHERE NOT EXISTS (SELECT 1 FROM payroll_legal_parameters x
                  WHERE x.tenant_id IS NULL AND x.country_code = 'FR' AND x.code = p.code AND x.valid_from = DATE '2026-01-01');

UPDATE public.payroll_legal_parameters
   SET source = '[SP-F2391] 25 % pour les 8 premières heures supplémentaires de la semaine, à défaut de convention'
 WHERE tenant_id IS NULL AND country_code = 'FR' AND code = 'MAJORATION_HEURES_SUP'
   AND btrim(COALESCE(source, '')) = '';

-- ── 2. Le recalcul d'une semaine ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.payroll_overtime_week_refresh(
  p_tenant uuid,
  p_employee_id uuid,
  p_date date
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_lundi date := date_trunc('week', p_date)::date;   -- semaine civile : lundi → dimanche
  v_base numeric := COALESCE(payroll_hourly_rate(p_tenant, p_employee_id), 0);
  v_a_tranches boolean;
  v_seuil_1 numeric;
  v_maj_1 numeric;
  v_maj_2 numeric;
  v_cumul numeric := 0;      -- heures sup déjà comptées dans la semaine
  v_ts record;
  v_tier record;
  v_h numeric;               -- heures sup du pointage
  v_reste numeric;
  v_debut numeric;           -- position de la tranche dans le cumul hebdomadaire
  v_part numeric;
  v_montant numeric;
  v_n integer := 0;
BEGIN
  IF p_tenant IS NULL OR p_employee_id IS NULL OR p_date IS NULL OR v_base <= 0 THEN
    RETURN 0;
  END IF;

  SELECT EXISTS (SELECT 1 FROM overtime_tiers ot WHERE ot.tenant_id = p_tenant) INTO v_a_tranches;
  v_seuil_1 := COALESCE(NULLIF(get_legal_parameter('HEURES_SUP_TRANCHE_1_HEURES', 'FR', p_date, p_tenant), 0), 8);
  v_maj_1 := overtime_majoration(p_tenant);
  v_maj_2 := COALESCE(NULLIF(get_legal_parameter('MAJORATION_HEURES_SUP_2', 'FR', p_date, p_tenant), 0), v_maj_1);

  FOR v_ts IN
    SELECT t.id, round(COALESCE(t.overtime_minutes, 0) / 60.0, 2) AS heures
    FROM timesheets t
    WHERE t.tenant_id = p_tenant AND t.employee_id = p_employee_id
      AND t.status = 'approved'
      AND t.date BETWEEN v_lundi AND v_lundi + 6
      AND COALESCE(t.overtime_minutes, 0) > 0
    ORDER BY t.date, t.created_at, t.id
  LOOP
    v_h := v_ts.heures;
    v_reste := v_h;
    v_montant := 0;

    IF v_a_tranches THEN
      -- Tranches de la société. Chacune couvre (to_hour − from_hour + 1) heures
      -- sup de la semaine, à la suite l'une de l'autre : la tranche occupe
      -- l'intervalle [v_debut, v_debut + taille) du cumul hebdomadaire, et le
      -- pointage l'intervalle [v_cumul, v_cumul + v_h). On paie leur RECOUVREMENT.
      -- Une tranche sans borne haute couvre tout le reste.
      v_debut := 0;
      FOR v_tier IN
        SELECT ot.to_hour - ot.from_hour + 1 AS taille, ot.rate_multiplier
        FROM overtime_tiers ot WHERE ot.tenant_id = p_tenant ORDER BY ot.from_hour
      LOOP
        v_part := GREATEST(
          LEAST(v_cumul + v_h, COALESCE(v_debut + v_tier.taille, v_cumul + v_h))
          - GREATEST(v_cumul, v_debut), 0);
        v_montant := v_montant + v_part * round(v_base * v_tier.rate_multiplier, 4);
        v_reste := v_reste - v_part;
        EXIT WHEN v_tier.taille IS NULL;
        v_debut := v_debut + v_tier.taille;
      END LOOP;
      -- Au-delà de la dernière tranche bornée : son taux continue de s'appliquer.
      IF v_reste > 0 THEN
        v_montant := v_montant + v_reste * round(v_base * (
          SELECT ot.rate_multiplier FROM overtime_tiers ot
          WHERE ot.tenant_id = p_tenant ORDER BY ot.from_hour DESC LIMIT 1), 4);
      END IF;
    ELSE
      -- Régime légal : v_seuil_1 heures à la première majoration, puis la seconde.
      v_part := LEAST(v_reste, GREATEST(v_seuil_1 - v_cumul, 0));
      v_montant := v_part * round(v_base * v_maj_1, 4)
                 + (v_reste - v_part) * round(v_base * v_maj_2, 4);
    END IF;

    UPDATE payroll_variable_elements e
       SET quantity = v_h,
           amount = round(v_montant, 2),
           unit_price = CASE WHEN v_h > 0 THEN round(v_montant / v_h, 4) ELSE 0 END
     WHERE e.tenant_id = p_tenant AND e.source_id = v_ts.id
       AND e.element_type = 'overtime'
       AND COALESCE(e.integrated, false) = false;
    IF FOUND THEN v_n := v_n + 1; END IF;

    v_cumul := v_cumul + v_h;
  END LOOP;

  RETURN v_n;
END $fn$;

COMMENT ON FUNCTION public.payroll_overtime_week_refresh(uuid, uuid, date) IS
  '342 — répartit les heures supplémentaires d''un salarié entre les tranches, sur le cumul de la semaine civile (lundi → dimanche), et réécrit le montant des éléments de paie non intégrés. Tranches de la société (overtime_tiers) si elle en a, sinon le régime légal paramétré. Appelée par sync_timesheet_to_payroll.';

REVOKE ALL ON FUNCTION public.payroll_overtime_week_refresh(uuid, uuid, date) FROM PUBLIC, anon, authenticated;

-- ── 3. L'approbation d'un pointage recalcule sa semaine ───────────────────
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
  v_taux numeric := 0;
  v_montant numeric := 0;
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

    -- RH-04 : les heures supplémentaires sont celles que le pointage a mesurées
    -- sur l'horaire prévu. Un seul seuil, celui de la 104.
    v_overtime_hours := ROUND(COALESCE(NEW.overtime_minutes, 0) / 60.0, 2);
    IF v_overtime_hours > 0 THEN
      SELECT a.unit_price, a.amount INTO v_taux, v_montant
      FROM payroll_overtime_amount(NEW.tenant_id, NEW.employee_id, v_overtime_hours) a;
    END IF;

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

    -- Heures supplémentaires du jour : quantité ET montant (jamais 0)
    IF v_overtime_hours > 0 THEN
      IF EXISTS (SELECT 1 FROM payroll_variable_elements
                 WHERE tenant_id = NEW.tenant_id AND source_id = NEW.id
                   AND element_type = 'overtime') THEN
        UPDATE payroll_variable_elements
           SET quantity = v_overtime_hours,
               unit_price = v_taux,
               amount = v_montant,
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
          'overtime', 'Heures supp ' || to_char(NEW.date, 'DD/MM'), v_overtime_hours, v_taux, v_montant,
          'timesheet', NEW.id, false)
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

    -- 342 : les tranches se décident sur le CUMUL de la semaine civile. On
    -- recalcule donc toute la semaine du salarié : approuver le vendredi avant
    -- le lundi ne doit pas changer le résultat.
    PERFORM payroll_overtime_week_refresh(NEW.tenant_id, NEW.employee_id, NEW.date);
  END IF;

  RETURN NEW;
END $function$;


-- ── 4. Le bulletin applique la réduction de cotisations salariales ────────
CREATE OR REPLACE FUNCTION public.payroll_compute_slip(p_employee_id uuid, p_period text, p_pay_run_id uuid DEFAULT NULL::uuid, p_gross_override numeric DEFAULT NULL::numeric, p_dry_run boolean DEFAULT false)
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
  v_pas_rate numeric;
  v_elem RECORD;                     -- un élément variable, pour son détail (319)

  -- Éléments variables
  v_overtime_pay numeric := 0;
  v_overtime_hours numeric := 0;
  v_hs_reduction_pct numeric := 0;  -- 342 : taux de la réduction salariale sur les heures sup
  v_hs_reduction numeric := 0;      -- 342 : son montant
  v_bonus numeric := 0;
  v_advance_deduction numeric := 0;
  v_pay_recall numeric := 0;
  v_expense_reimbursement numeric := 0;
  v_unpaid_leave_deduction numeric := 0;
  v_other_deductions numeric := 0;
  v_meal_vouchers numeric := 0;
  v_transport_allowance numeric := 0;
  -- 341 : titres-restaurant et transport, traités selon leur régime social
  v_tr_exo_max numeric := 0;        -- plafond d'exonération de la part patronale, par titre
  v_tr_part_patronale numeric := 0; -- part de l'employeur (information : hors brut si exonérée)
  v_tr_reintegre numeric := 0;      -- fraction de la part patronale au-delà des limites
  v_tp_exo_pct numeric := 0;        -- part du coût de l'abonnement exonérée (%)
  v_tp_reintegre numeric := 0;      -- fraction de la prise en charge au-delà de cette part

  -- Brut
  v_base_salary numeric;
  v_total_gross numeric;
  -- 320 : prorata d'entrée / sortie — jours de présence / jours du mois
  v_prorata numeric := 1;
  v_presence_debut date;
  v_presence_fin date;
  v_jours_presence int;
  v_jours_periode int;

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

    -- 341 — Titres-restaurant. Un élément porte : quantity = nombre de titres,
    -- unit_price = valeur du titre, amount = PART SALARIALE. La part patronale
    -- (valeur − part salariale) est exonérée si elle reste entre 50 % et 60 % de
    -- la valeur du titre ET sous le plafond par titre (TITRE_RESTAURANT_EXO_MAX).
    -- Ce qui dépasse la plus basse des deux limites (60 %, plafond) est réintégré
    -- dans le brut. Sans quantité ni valeur, rien ne peut être mesuré : rien n'est
    -- réintégré. Une part patronale INFÉRIEURE à 50 % fait perdre l'exonération :
    -- la totalité de la participation entre dans l'assiette (voir ci-dessous).
    v_tr_exo_max := COALESCE(get_legal_parameter('TITRE_RESTAURANT_EXO_MAX', v_country_code, v_period_start, v_tid), 0);
    v_tp_exo_pct := COALESCE(get_legal_parameter('TRANSPORT_PUBLIC_EXO_PCT', v_country_code, v_period_start, v_tid), 0);

    SELECT
      COALESCE(SUM(CASE WHEN ve.element_type = 'meal_vouchers' AND COALESCE(ve.quantity, 0) > 0 AND COALESCE(ve.unit_price, 0) > 0
                        THEN GREATEST(ve.quantity * ve.unit_price - COALESCE(ve.amount, 0), 0) ELSE 0 END), 0),
      COALESCE(SUM(CASE WHEN ve.element_type = 'meal_vouchers' AND COALESCE(ve.quantity, 0) > 0 AND COALESCE(ve.unit_price, 0) > 0 AND v_tr_exo_max > 0
                        THEN CASE
                               -- Part patronale INFÉRIEURE à 50 % de la valeur du titre : la
                               -- TOTALITÉ de la participation est réintégrée dans l'assiette
                               -- (BOSS, mise à jour du 16/03/2023). Tolérance d'un demi-centime.
                               WHEN ve.quantity * ve.unit_price - COALESCE(ve.amount, 0) > 0
                                AND ve.quantity * ve.unit_price - COALESCE(ve.amount, 0)
                                    < 0.50 * ve.quantity * ve.unit_price - 0.005
                               THEN ve.quantity * ve.unit_price - COALESCE(ve.amount, 0)
                               -- Sinon : seule la fraction au-delà de min(60 %, plafond).
                               ELSE GREATEST(ve.quantity * ve.unit_price - COALESCE(ve.amount, 0)
                                             - ve.quantity * LEAST(v_tr_exo_max, 0.60 * ve.unit_price), 0)
                             END
                        ELSE 0 END), 0),
      -- Transport : quantity × unit_price = coût de l'abonnement, amount = prise
      -- en charge. Sans coût renseigné, la prise en charge est tenue pour exonérée.
      COALESCE(SUM(CASE WHEN ve.element_type = 'transport_allowance' AND COALESCE(ve.quantity, 0) > 0 AND COALESCE(ve.unit_price, 0) > 0 AND v_tp_exo_pct > 0
                        THEN GREATEST(COALESCE(ve.amount, 0) - ve.quantity * ve.unit_price * v_tp_exo_pct / 100, 0) ELSE 0 END), 0)
    INTO v_tr_part_patronale, v_tr_reintegre, v_tp_reintegre
    FROM payroll_variable_elements ve
    WHERE ve.pay_run_id = p_pay_run_id
      AND ve.employee_id = p_employee_id
      AND ve.tenant_id = v_tid
      AND COALESCE(ve.integrated, false) = false;
    v_tr_part_patronale := round(v_tr_part_patronale, 2);
    v_tr_reintegre := round(v_tr_reintegre, 2);
    v_tp_reintegre := round(v_tp_reintegre, 2);

    -- Compter les éléments variables pour l'affichage UI
    SELECT count(*) INTO v_ve_count
    FROM payroll_variable_elements ve
    WHERE ve.pay_run_id = p_pay_run_id
      AND ve.employee_id = p_employee_id
      AND ve.tenant_id = v_tid
      AND COALESCE(ve.integrated, false) = false;
  END IF;

  -- ── Prorata d'entrée / sortie (320) ──
  -- Un salarié embauché ou sorti en cours de mois est payé au prorata de
  -- son temps de présence dans le mois. C'est une obligation légale (Code du
  -- travail, art. L1234-9 à L1234-13) et la pratique de tous les produits du
  -- marché (Sage 100 §12, Odoo `hr.payslip`).
  --
  -- La règle : rapport des jours de présence AU NOMBRE DE JOURS DU MOIS — pas
  -- un trentième : février a 28 jours. Le rapport est arrondi à 6 décimales
  -- (il n'a pas de fin), le brut reste au centime.
  --
  -- Ne sont proratisés ni le rappel, ni les heures supplémentaires, ni les
  -- remboursements : ce ne sont pas des salaires dus au prorata du mois.
  v_prorata := 1;
  v_presence_debut := GREATEST(v_period_start, COALESCE(v_emp.hire_date, v_period_start));
  v_presence_fin := LEAST((v_period_start + INTERVAL '1 month - 1 day')::date,
                         COALESCE(v_emp.contract_end_date,
                                  (v_period_start + INTERVAL '1 month - 1 day')::date));
  v_jours_periode := EXTRACT(DAY FROM (v_period_start + INTERVAL '1 month - 1 day'))::int;
  IF v_presence_fin < v_presence_debut THEN
    v_prorata := 0;   -- contrat entièrement hors de la période : rien à payer
  ELSIF (v_presence_debut > v_period_start
      OR v_presence_fin < (v_period_start + INTERVAL '1 month - 1 day')::date)
       AND v_jours_periode > 0 THEN
    v_jours_presence := (v_presence_fin - v_presence_debut) + 1;
    v_prorata := round(v_jours_presence::numeric / v_jours_periode, 6);
  END IF;

  -- ── Calcul du brut ──
  -- C2 (319) : en simulation, le salaire.simulé prime sur celui de la fiche ;
  -- sinon on retrouve exactement le calcul du bulletin.
  v_base_salary := round(COALESCE(p_gross_override, COALESCE(v_emp.base_salary, v_emp.salary), 0) * v_prorata, 2);
  -- 341 : seules les fractions NON exonérées entrent dans le brut.
  v_total_gross := v_base_salary + v_overtime_pay + v_bonus + v_pay_recall
    - v_unpaid_leave_deduction + v_tr_reintegre + v_tp_reintegre;

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
  -- Repris de la 319, qui les calculait déjà mais ne les restituait pas ligne
  -- à ligne : le bulletin disait le montant, sans dire d'où il venait, et la
  -- suite 326 mesurait « ligne=ABSENTE » pour un acompte comme pour un rappel
  -- alors que les deux étaient bien appliqués au net.
  --
  -- ⚠️ La 319 définit `calculate_payslip`, mais elle n'est plus qu'un ENVELOPPE
  -- qui délègue ici (`payroll_compute_slip`) : un correctif écrit dans son
  -- corps ne s'exécute plus jamais. C'est ce qui rendait 326 T05/T07 rouges
  -- malgré le correctif — il était au bon endroit, dans une fonction morte.
  -- La clause de filtrage est celle de l'agrégat plus haut, à l'identique.
  FOR v_elem IN
    SELECT ve.element_type, ve.description, ve.amount
    FROM payroll_variable_elements ve
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
      -- Le signe suit le sens de l'opération : un acompte et un congé sans
      -- solde sortent du net, un rappel et un remboursement y entrent.
      'amount', CASE
                  WHEN v_elem.element_type IN ('advance_deduction', 'unpaid_leave_deduction')
                    THEN -abs(v_elem.amount)
                  ELSE abs(v_elem.amount)
                END);
  END LOOP;

  -- 342 — Réduction de cotisations salariales sur les heures supplémentaires :
  -- elles sont exonérées des cotisations salariales d'assurance vieillesse de
  -- base et complémentaire, dans la limite d'un taux (HEURES_SUP_REDUCTION_SALARIALE_PCT,
  -- 11,31 %). La réduction ne peut pas dépasser les cotisations salariales dues.
  v_hs_reduction_pct := COALESCE(get_legal_parameter('HEURES_SUP_REDUCTION_SALARIALE_PCT', v_country_code, v_period_start, v_tid), 0);
  IF v_overtime_pay > 0 AND v_hs_reduction_pct > 0 THEN
    v_hs_reduction := LEAST(round(v_overtime_pay * v_hs_reduction_pct / 100, 2), GREATEST(v_ss_employee, 0));
    v_ss_employee := round(v_ss_employee - v_hs_reduction, 2);
  END IF;

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

  -- 341 — Net à payer :
  --   * la part SALARIALE des titres-restaurant est une retenue (elle était
  --     AJOUTÉE au net : le salarié était payé pour ses propres titres) ;
  --   * la fraction réintégrée de la part patronale a été soumise à cotisations
  --     par le brut, mais elle n'est pas versée en argent : elle est retirée ;
  --   * la prise en charge du transport est versée ; sa fraction réintégrée est
  --     déjà dans le brut, donc elle n'est pas comptée deux fois.
  v_net_payable := round(v_total_gross - v_total_deductions + v_expense_reimbursement
    - v_meal_vouchers - v_tr_reintegre
    + (v_transport_allowance - v_tp_reintegre), 2);

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
  || CASE WHEN v_meal_vouchers > 0 THEN jsonb_build_array(jsonb_build_object('label', 'Titres-restaurant (part salariale)', 'amount', -v_meal_vouchers, 'type', 'meal_vouchers')) ELSE '[]'::jsonb END
  || CASE WHEN v_transport_allowance > 0 THEN jsonb_build_array(jsonb_build_object('label', 'Prise en charge transport (exonérée)', 'amount', v_transport_allowance - v_tp_reintegre, 'type', 'transport')) ELSE '[]'::jsonb END
  || CASE WHEN v_tr_reintegre > 0 THEN jsonb_build_array(jsonb_build_object('label', 'Titres-restaurant : part patronale au-delà de la limite d''exonération (soumise)', 'amount', v_tr_reintegre, 'type', 'meal_vouchers_reintegrated')) ELSE '[]'::jsonb END
  || CASE WHEN v_tp_reintegre > 0 THEN jsonb_build_array(jsonb_build_object('label', 'Transport : prise en charge au-delà de la part exonérée (soumise)', 'amount', v_tp_reintegre, 'type', 'transport_reintegrated')) ELSE '[]'::jsonb END;

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
    'overtimeContributionRelief', v_hs_reduction,
    'bonus', v_bonus,
    'total_gross', v_total_gross,
    'mealVouchers', v_meal_vouchers,
    'mealVouchersEmployerShare', v_tr_part_patronale,
    'mealVouchersReintegrated', v_tr_reintegre,
    'transportAllowance', v_transport_allowance,
    'transportReintegrated', v_tp_reintegre,
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
    'proration', v_prorata,
    'prorationDays', v_jours_presence,
    'prorationPeriodDays', v_jours_periode,
    'contributions', v_contrib
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM
  );
END;
$function$;


-- ── 5. Un seul moteur ─────────────────────────────────────────────────────
-- `calculate_overtime_pay` n'avait plus d'appelant (mesuré : 0 dans src/, 0 dans
-- les fonctions de la base) et portait un plafond et une année en dur.
DROP FUNCTION IF EXISTS public.calculate_overtime_pay(uuid, numeric, numeric);
