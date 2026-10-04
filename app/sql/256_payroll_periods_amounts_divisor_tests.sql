-- ============================================================
-- 256_payroll_periods_amounts_divisor_tests.sql — vague W4 (RH-05 → RH-10)
--
-- Mesuré AVANT la 256, sur base neuve (255 migrations) :
--   RH-05  quatre conventions mensuelles coexistaient — `weekly_hours × 4,33`
--          (retard), `/ 30` (congé sans solde et absence), `/ 21` (front),
--          `/ 151,67` (heures supplémentaires) ;
--   RH-07  la note de frais entrait en paie par `Number(exp.amount)` : la
--          colonne n'existe pas sur `expense_reports`, donc 0 ;
--   RH-08  aucune écriture, aucune TVA : `total_vat` n'était lue par personne ;
--   RH-10  aucun index unique hors `id` sur `payroll_variable_elements` :
--          relancer un import doublait les éléments.
--
-- Ce que ce fichier prouve APRÈS la 256. Les deux défauts de FRONT (RH-06, les
-- bornes `-31` de février/avril/juin/septembre/novembre ; RH-09, le congé à
-- cheval sur deux mois) n'ont pas de scénario ici : ce sont des requêtes
-- PostgREST, et c'est `src/lib/__tests__/payrollPeriods.test.ts` et
-- `payroll-imports.test.ts` (Vitest) qui les mesurent, sur les appels réels.
-- ============================================================

\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '256', false);
DELETE FROM _audit_results WHERE file = '256';

-- ── T01 — un seul diviseur par société, avec un défaut calculé (RH-05) ──────
DO $$
DECLARE
  t uuid; e uuid; v_heures numeric; v_jours numeric; v_heures_soc numeric; v_jours_soc numeric;
BEGIN
  t := _mk_tenant('A256T01', false);
  INSERT INTO employees (tenant_id, name, email, status, salary, weekly_hours)
  VALUES (t, 'Amina T01', 'a256t01@audit.test', 'active', 3000, 35) RETURNING id INTO e;

  v_heures := payroll_divisor(t, 'heures');
  v_jours := payroll_divisor(t, 'jours');

  INSERT INTO payroll_legal_parameters (tenant_id, country_code, code, value, valid_from)
  VALUES (t, 'FR', 'DIVISEUR_HORAIRE_MENSUEL', 169, CURRENT_DATE - 1),
         (t, 'FR', 'DIVISEUR_JOURS_MENSUEL', 26, CURRENT_DATE - 1);
  v_heures_soc := payroll_divisor(t, 'heures');
  v_jours_soc := payroll_divisor(t, 'jours');

  PERFORM _rec('T01', 'un diviseur mensuel par société : 35 × 52 / 12 par défaut, le paramètre de la société l''emporte',
    v_heures = 151.6667 AND v_jours = 21.6667 AND v_heures_soc = 169 AND v_jours_soc = 26,
    format('heures défaut=%s (151,6667 attendu), jours défaut=%s (21,6667 attendu), après paramétrage heures=%s (169), jours=%s (26)',
           v_heures, v_jours, v_heures_soc, v_jours_soc));
END $$;

-- ── T02 — les trois chemins de la base lisent CE diviseur (RH-05) ───────────
DO $$
DECLARE
  t uuid; e uuid; r uuid; ts uuid; lr uuid; v_rule uuid;
  v_taux_retard numeric; v_taux_jour numeric; v_ot numeric; v_attendu numeric;
BEGIN
  t := _mk_tenant('A256T02', false);
  INSERT INTO employees (tenant_id, name, email, status, salary, weekly_hours)
  VALUES (t, 'Bilal T02', 'a256t02@audit.test', 'active', 3000, 35) RETURNING id INTO e;
  INSERT INTO payroll_legal_parameters (tenant_id, country_code, code, value, valid_from)
  VALUES (t, 'FR', 'DIVISEUR_HORAIRE_MENSUEL', 169, CURRENT_DATE - 1),
         (t, 'FR', 'DIVISEUR_JOURS_MENSUEL', 26, CURRENT_DATE - 1);

  INSERT INTO pay_runs (tenant_id, number, period_start, period_end, pay_date, status, gross_total, tax_total, net_total, employee_count)
  VALUES (t, 'PR-256T02', '2026-04-01', '2026-04-30', '2026-04-30', 'draft', 0, 0, 0, 1)
  RETURNING id INTO r;

  -- a) le RETARD : 60 min, seuil 15, grâce 5 → 40 min déductibles au taux horaire
  INSERT INTO timesheets (tenant_id, employee_id, date, hours, status, late_minutes)
  VALUES (t, e, '2026-04-10', 8, 'pending', 60) RETURNING id INTO ts;
  UPDATE timesheets SET status = 'approved' WHERE id = ts;

  -- b) le CONGÉ SANS SOLDE : 2 jours au taux journalier de la société
  INSERT INTO leave_rules (tenant_id, leave_type, label, affects_pay, deduction_rate, active)
  VALUES (t, 'unpaid', 'Congé sans solde', true, 100, true) RETURNING id INTO v_rule;
  INSERT INTO leave_requests (tenant_id, employee_id, leave_type, start_date, end_date, days, status)
  VALUES (t, e, 'unpaid', '2026-04-20', '2026-04-21', 2, 'pending') RETURNING id INTO lr;
  UPDATE leave_requests SET status = 'approved' WHERE id = lr;

  -- c) les HEURES SUPPLÉMENTAIRES : 1 h au taux de base × 1,25
  INSERT INTO overtime_tiers (tenant_id, from_hour, to_hour, rate_multiplier)
  VALUES (t, 35, 43, 1.25);

  SELECT unit_price INTO v_taux_retard FROM payroll_variable_elements
   WHERE tenant_id = t AND employee_id = e AND element_type = 'lateness_deduction';
  SELECT unit_price INTO v_taux_jour FROM payroll_variable_elements
   WHERE tenant_id = t AND employee_id = e AND element_type = 'unpaid_leave_deduction';

  -- 04/10/2026 (342) : `calculate_overtime_pay` est supprimée (second moteur, sans
  -- appelant). Le taux d'UNE heure sup se lit désormais par la porte de l'écran,
  -- `payroll_overtime_preview` — même grandeur, même attendu. Appel précédent :
  -- SELECT ot.gross_amount FROM calculate_overtime_pay(e, 1) ot LIMIT 1.
  v_ot := (payroll_overtime_preview(e, 1) ->> 'montant')::numeric;
  v_attendu := round(3000::numeric / 169 * 1.25, 4);

  PERFORM _rec('T02', 'retard, congé sans solde et heures supplémentaires lisent le diviseur de la société (169 / 26), pas 4,33 ni 30 ni 151,67',
    v_taux_retard IS NOT NULL AND abs(v_taux_retard - round(3000::numeric / 169, 4) / 60) < 0.000001
      AND v_taux_jour = round(3000::numeric / 26, 4)
      AND abs(v_ot - 3000::numeric / 169 * 1.25) < 0.01,
    format('taux retard/min=%s (attendu %s), taux jour=%s (attendu %s), 1 h supp=%s (attendu ≈ %s)',
           v_taux_retard, round(round(3000::numeric / 169, 4) / 60, 6), v_taux_jour,
           round(3000::numeric / 26, 4), v_ot, round(3000::numeric / 169 * 1.25, 4)));
END $$;
-- ── T03 — un seul élément de paie par document source (RH-10) ───────────────
DO $$
DECLARE
  t uuid; e uuid; v_src uuid := gen_random_uuid(); v_refus boolean := false; v_msg text;
  v_apres_1 int; v_apres_2 int; v_manuels int;
BEGIN
  t := _mk_tenant('A256T03', false);
  INSERT INTO employees (tenant_id, name, email, status, salary)
  VALUES (t, 'Chams T03', 'a256t03@audit.test', 'active', 3000) RETURNING id INTO e;

  INSERT INTO payroll_variable_elements (tenant_id, employee_id, period, element_type, amount, source, source_id)
  VALUES (t, e, '2026-04', 'expense_reimbursement', 120, 'expense_report', v_src);
  v_apres_1 := (SELECT count(*) FROM payroll_variable_elements WHERE tenant_id = t);

  -- Le MÊME document source, une seconde fois : refusé par la contrainte.
  BEGIN
    INSERT INTO payroll_variable_elements (tenant_id, employee_id, period, element_type, amount, source, source_id)
    VALUES (t, e, '2026-04', 'expense_reimbursement', 120, 'expense_report', v_src);
  EXCEPTION WHEN unique_violation THEN v_refus := true; v_msg := SQLERRM; END;

  -- Le même document, mais un AUTRE type d'élément : légitime (un pointage
  -- approuvé produit « heures » ET « heures supplémentaires »).
  INSERT INTO payroll_variable_elements (tenant_id, employee_id, period, element_type, amount, source, source_id)
  VALUES (t, e, '2026-04', 'overtime', 5, 'expense_report', v_src);
  v_apres_2 := (SELECT count(*) FROM payroll_variable_elements WHERE tenant_id = t);

  -- Une saisie manuelle (sans document source) reste librement duplicable.
  INSERT INTO payroll_variable_elements (tenant_id, employee_id, period, element_type, amount, source, source_id)
  VALUES (t, e, '2026-04', 'bonus', 100, 'manual', NULL),
         (t, e, '2026-04', 'bonus', 100, 'manual', NULL);
  v_manuels := (SELECT count(*) FROM payroll_variable_elements WHERE tenant_id = t AND source_id IS NULL);

  PERFORM _rec('T03', 'le même document source ne produit qu''un élément par type ; un autre type reste possible ; la saisie manuelle reste libre',
    v_apres_1 = 1 AND v_refus AND v_apres_2 = 2 AND v_manuels = 2,
    format('1er insert=%s, rejeu refusé=%s (%s), autre type ajouté → %s, saisies manuelles=%s',
           v_apres_1, v_refus, left(COALESCE(v_msg, ''), 70), v_apres_2, v_manuels));
END $$;

-- ── T04 — relancer l'import ne double plus (RH-10), mesuré PAR JOURNÉE ──────
-- DOCTRINE CHANGÉE PAR LA 265 (TRV-11), et le test est réécrit — pas vidé.
-- La 256 indexait l'élément de retenue sur le DOCUMENT source (`source_id` =
-- l'identifiant du congé) : trois jours de congé donnaient UNE ligne de 3 jours.
-- La 265 ramène la paie d'absence au REGISTRE : une ligne PAR JOURNÉE,
-- `source = 'absence_day'` et `source_id = day_uid` (identifiant stable du jour,
-- recalculé à l'identique). C'est ce qui permet d'annuler un seul jour, et ce
-- qui empêche la double retenue quand deux sources déclarent le même jour.
-- Ce qui est mesuré reste la même propriété : **rejouer ne double pas**.
DO $$
DECLARE
  t uuid; e uuid; lr uuid; v_n int; v_avant int;
BEGIN
  t := _mk_tenant('A256T04', false);
  INSERT INTO employees (tenant_id, name, email, status, salary)
  VALUES (t, 'Dalal T04', 'a256t04@audit.test', 'active', 2600) RETURNING id INTO e;
  INSERT INTO leave_rules (tenant_id, leave_type, label, affects_pay, deduction_rate, active)
  VALUES (t, 'unpaid', 'Congé sans solde', true, 100, true);

  INSERT INTO leave_requests (tenant_id, employee_id, leave_type, start_date, end_date, days, status)
  VALUES (t, e, 'unpaid', '2026-04-06', '2026-04-08', 3, 'pending') RETURNING id INTO lr;

  UPDATE leave_requests SET status = 'approved' WHERE id = lr;        -- 1er passage
  SELECT count(*) INTO v_avant FROM payroll_variable_elements
   WHERE tenant_id = t AND source = 'absence_day';

  -- Le congé est refusé puis approuvé de nouveau : l'import est rejoué.
  UPDATE leave_requests SET status = 'rejected' WHERE id = lr;
  UPDATE leave_requests SET status = 'approved' WHERE id = lr;
  SELECT count(*) INTO v_n FROM payroll_variable_elements
   WHERE tenant_id = t AND source = 'absence_day';

  PERFORM _rec('T04', 'approuver, refuser puis réapprouver un congé de 3 jours laisse 3 retenues (une par jour), pas 6',
    v_avant = 3 AND v_n = 3,
    format('éléments après le 1er passage=%s, après ré-approbation=%s (3 attendus : une par journée)',
           v_avant, v_n));
END $$;

-- ── T05 — la note de frais entre en paie pour son total (RH-07) ─────────────
DO $$
DECLARE
  t uuid; e uuid; er uuid; r uuid; v record;
BEGIN
  t := _mk_tenant('A256T05', true);
  INSERT INTO employees (tenant_id, name, email, status, salary)
  VALUES (t, 'Elias T05', 'a256t05@audit.test', 'active', 3000) RETURNING id INTO e;
  INSERT INTO pay_runs (tenant_id, number, period_start, period_end, pay_date, status, gross_total, tax_total, net_total, employee_count)
  VALUES (t, 'PR-256T05', '2026-04-01', '2026-04-30', '2026-04-30', 'draft', 0, 0, 0, 1)
  RETURNING id INTO r;

  -- La note porte sa période (avril) et a été VALIDÉE en mai : la période de
  -- paie est celle de la note, jamais celle de `submitted_at`.
  INSERT INTO expense_reports (tenant_id, employee_id, number, period, total_amount, total_vat, status, submitted_at)
  VALUES (t, e, 'NDF-256-T05', '2026-04', 120, 20, 'submitted', '2026-05-12T10:00:00Z')
  RETURNING id INTO er;

  UPDATE expense_reports SET status = 'approved' WHERE id = er;

  SELECT * INTO v FROM payroll_variable_elements WHERE tenant_id = t AND source_id = er;

  PERFORM _rec('T05', 'la note de frais entre en paie pour son total, au mois de la note — pas pour 0, et pas au mois de la validation',
    v.amount = 120 AND v.element_type = 'expense_reimbursement' AND v.period = '2026-04' AND v.pay_run_id = r,
    format('montant=%s (120 attendu), type=%s, période=%s (2026-04 attendue), lot d''avril=%s',
           v.amount, v.element_type, v.period, v.pay_run_id = r));
END $$;

-- ── T06 — la note de frais entre au grand livre (RH-08) ─────────────────────
DO $$
DECLARE
  t uuid; e uuid; er uuid; v_entry uuid; v_ref text; v_statut text;
  v_ht numeric; v_tva numeric; v_salarie numeric; v_equilibre boolean;
BEGIN
  t := _mk_tenant('A256T06', true);
  INSERT INTO employees (tenant_id, name, email, status, salary)
  VALUES (t, 'Fadouma T06', 'a256t06@audit.test', 'active', 3000) RETURNING id INTO e;

  INSERT INTO expense_reports (tenant_id, employee_id, number, period, total_amount, total_vat, status)
  VALUES (t, e, 'NDF-256-T06', '2026-04', 120, 20, 'submitted') RETURNING id INTO er;
  INSERT INTO expense_report_lines (tenant_id, expense_report_id, date, description, amount, vat_rate, vat_amount, amount_ttc)
  VALUES (t, er, '2026-04-08', 'Taxi client', 100, 20, 20, 120);

  UPDATE expense_reports SET status = 'approved' WHERE id = er;

  SELECT je.id, je.reference, je.status INTO v_entry, v_ref, v_statut
  FROM journal_entries je WHERE je.tenant_id = t AND je.reference = 'EXPENSE-NDF-256-T06';

  SELECT
    COALESCE(sum(l.debit)  FILTER (WHERE l.account_code = payroll_account(t, 'expense_reimbursement')), 0),
    COALESCE(sum(l.debit)  FILTER (WHERE l.account_code = (
      SELECT account_code FROM vat_account_mapping
      WHERE tenant_id = '00000000-0000-0000-0000-000000000000' AND direction = 'deductible'
        AND rate = 20 AND vat_code = vat_code_for_rate(20) LIMIT 1)), 0),
    COALESCE(sum(l.credit) FILTER (WHERE l.account_code = payroll_account(t, 'net')), 0),
    COALESCE(sum(l.debit), 0) = COALESCE(sum(l.credit), 0)
  INTO v_ht, v_tva, v_salarie, v_equilibre
  FROM journal_lines l WHERE l.journal_id = v_entry;

  PERFORM _rec('T06', 'l''écriture de la note de frais porte D charge HT, D TVA récupérable, C 421 (salarié), et elle est équilibrée',
    v_entry IS NOT NULL AND v_ref = 'EXPENSE-NDF-256-T06' AND v_statut = 'posted'
      AND v_ht = 100 AND v_tva = 20 AND v_salarie = 120 AND v_equilibre,
    format('écriture=%s référence=%s statut=%s, charge HT=%s (100), TVA=%s (20), salarié=%s (120), équilibrée=%s',
           v_entry IS NOT NULL, v_ref, v_statut, v_ht, v_tva, v_salarie, v_equilibre));
END $$;


-- ── T07 — la note de frais ne s'écrit qu'une fois (RH-08) ────────────────────
DO $$
DECLARE
  t uuid; e uuid; er uuid; v_elements int; v_ecritures int;
BEGIN
  t := _mk_tenant('A256T07', true);
  INSERT INTO employees (tenant_id, name, email, status, salary)
  VALUES (t, 'Ghislain T07', 'a256t07@audit.test', 'active', 3000) RETURNING id INTO e;

  INSERT INTO expense_reports (tenant_id, employee_id, number, period, total_amount, total_vat, status)
  VALUES (t, e, 'NDF-256-T07', '2026-04', 60, 0, 'submitted') RETURNING id INTO er;
  UPDATE expense_reports SET status = 'approved' WHERE id = er;

  -- La note est refusée puis approuvée de nouveau : l'écriture et l'élément
  -- sont déjà là, ils ne se dédoublent pas.
  UPDATE expense_reports SET status = 'rejected' WHERE id = er;
  UPDATE expense_reports SET status = 'approved' WHERE id = er;

  SELECT count(*) INTO v_elements FROM payroll_variable_elements WHERE tenant_id = t AND source_id = er;
  SELECT count(*) INTO v_ecritures FROM journal_entries je WHERE je.tenant_id = t AND je.reference = 'EXPENSE-NDF-256-T07';

  PERFORM _rec('T07', 'approuver, refuser puis réapprouver une note de frais laisse UNE écriture et UN élément',
    v_elements = 1 AND v_ecritures = 1,
    format('éléments de paie=%s (1 attendu), écritures=%s (1 attendue)', v_elements, v_ecritures));
END $$;

-- ── T08 — une TVA incohérente refuse la note, au lieu de la ventiler (RH-08) ─
DO $$
DECLARE
  t uuid; e uuid; er uuid; v_refus boolean := false; v_msg text;
  v_elements int; v_ecritures int;
BEGIN
  t := _mk_tenant('A256T08', false);
  INSERT INTO employees (tenant_id, name, email, status, salary)
  VALUES (t, 'Hawa T08', 'a256t08@audit.test', 'active', 3000) RETURNING id INTO e;

  INSERT INTO expense_reports (tenant_id, employee_id, number, period, total_amount, total_vat, status)
  VALUES (t, e, 'NDF-256-T08', '2026-04', 100, 150, 'submitted') RETURNING id INTO er;

  BEGIN
    UPDATE expense_reports SET status = 'approved' WHERE id = er;
  EXCEPTION WHEN check_violation THEN v_refus := true; v_msg := SQLERRM; END;

  SELECT count(*) INTO v_elements FROM payroll_variable_elements WHERE tenant_id = t AND source_id = er;
  SELECT count(*) INTO v_ecritures FROM journal_entries je WHERE je.tenant_id = t AND je.reference = 'EXPENSE-NDF-256-T08';

  PERFORM _rec('T08', 'une TVA récupérable supérieure au total fait refuser la note, sans élément ni écriture',
    v_refus AND v_elements = 0 AND v_ecritures = 0,
    format('refus=%s (%s), éléments=%s, écritures=%s',
           v_refus, left(COALESCE(v_msg, ''), 100), v_elements, v_ecritures));
END $$;

SELECT _audit_assert('256');


