-- ============================================================
-- 212_payroll_payment.sql — R-04 : paiement de la paie
--
-- La 191 comptabilise la paie (charges et dettes) mais jamais son paiement :
-- les dettes 421 (salariés), 431 (organismes), 447 (impôt retenu) restaient
-- ouvertes indéfiniment et la trésorerie ne bougeait pas.
--
-- Cette migration ajoute post_payroll_payment(lot, compte bancaire, date,
-- périmètre) : une écriture de trésorerie par périmètre, idempotente
--   net       D 421 par salarié (auxiliaire) / C 512x   puis lettrage du 421
--   social    D 431                          / C 512x
--   tax       D 447                          / C 512x
--   advances  D 425                          / C 512x   (acomptes versés)
-- Le lot passe à « payé » quand tous les périmètres dus sont versés.
--
-- Deux défauts trouvés en écrivant les scénarios (212_payroll_payment_tests) :
--   - pay_runs n'acceptait que draft/approved/paid, alors que le code fait
--     passer un lot par « processing » (intégration des acomptes) et parle de
--     « closed » / « cancelled » (191) : tout passage à processing échouait ;
--   - integrate_salary_advances_on_payrun écrivait le statut « processed »,
--     absent de salary_advances_status_check : dès qu'un acompte était en
--     attente sur la période, le passage du lot à « processing » échouait.
--
-- Comptes issus de payroll_account_mapping (191) : le lot K les remplacera par
-- les rôles de comptes du pack pays.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Statuts réellement utilisés par le code
-- ------------------------------------------------------------
ALTER TABLE pay_runs DROP CONSTRAINT IF EXISTS pay_runs_status_check;
ALTER TABLE pay_runs ADD CONSTRAINT pay_runs_status_check
  CHECK (status IN ('draft', 'processing', 'approved', 'closed', 'paid', 'cancelled'));

-- ------------------------------------------------------------
-- 2. Intégration des acomptes : statut valide et pas de doublon
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION integrate_salary_advances_on_payrun()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_adv RECORD; v_period text;
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status AND NEW.status = 'processing' THEN
    v_period := to_char(NEW.period_start, 'YYYY-MM');
    FOR v_adv IN SELECT * FROM salary_advances
      WHERE tenant_id = NEW.tenant_id AND status = 'pending'
        AND deduction_month IS NOT NULL
        AND to_char(deduction_month, 'YYYY-MM') = v_period
    LOOP
      -- un acompte déjà intégré à ce lot ne l'est pas deux fois
      IF NOT EXISTS (SELECT 1 FROM payroll_variable_elements
                     WHERE tenant_id = NEW.tenant_id AND pay_run_id = NEW.id
                       AND element_type = 'advance_deduction' AND source_id = v_adv.id) THEN
        INSERT INTO payroll_variable_elements (tenant_id, employee_id, pay_run_id, period, element_type,
          description, amount, source, source_id, integrated)
        VALUES (NEW.tenant_id, v_adv.employee_id, NEW.id, v_period, 'advance_deduction',
          'Acompte du ' || v_adv.advance_date, v_adv.amount, 'salary_advance', v_adv.id, false);
      END IF;
      -- « processed » n'existe pas : salary_advances_status_check n'accepte que
      -- pending, deducted et cancelled — l'acompte est retenu sur le bulletin
      UPDATE salary_advances SET status = 'deducted' WHERE id = v_adv.id;
    END LOOP;
  END IF;
  RETURN NEW;
END $$;

-- ------------------------------------------------------------
-- 3. Écriture de paie : auxiliaire salarié sur 421 et 425
--    (les autres lignes restent agrégées par compte, comme dans la 191)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.payroll_post_run(p_run uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_run pay_runs%ROWTYPE;
  v_existing uuid;
  v_slip record;
  v_ci jsonb;
  v_csg numeric; v_adv numeric; v_rest numeric; v_exp numeric; v_meal numeric; v_transp numeric;
  v_d numeric; v_c numeric;
  v_tiers text;
  v_rows jsonb := '[]'::jsonb;
  v_entry uuid;
  v_gross numeric := 0; v_employer numeric := 0; v_employee numeric := 0; v_net numeric := 0;
  v_n int := 0;
BEGIN
  SELECT * INTO v_run FROM pay_runs WHERE id = p_run FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Lot de paie introuvable' USING ERRCODE = 'no_data_found';
  END IF;

  -- Idempotence : l'écriture du lot existe déjà
  SELECT journal_entry_id INTO v_existing FROM payroll_accounting_entries
  WHERE pay_run_id = p_run AND journal_entry_id IS NOT NULL AND status <> 'cancelled' LIMIT 1;
  IF v_existing IS NULL THEN
    SELECT id INTO v_existing FROM journal_entries
    WHERE tenant_id = v_run.tenant_id AND reference = 'PAYROLL-' || v_run.number LIMIT 1;
  END IF;
  IF v_existing IS NOT NULL THEN
    RETURN jsonb_build_object('success', true, 'entry_id', v_existing, 'already_posted', true);
  END IF;

  IF v_run.status NOT IN ('approved', 'closed', 'paid') THEN
    RAISE EXCEPTION 'Lot de paie % %', v_run.number,
      CASE v_run.status
        WHEN 'draft' THEN 'en brouillon : approuvez-le avant de le comptabiliser'
        WHEN 'cancelled' THEN 'annulé : rien à comptabiliser'
        ELSE 'non approuvé (statut ' || v_run.status || ') : approuvez-le avant de le comptabiliser' END
      USING ERRCODE = 'check_violation';
  END IF;

  FOR v_slip IN
    SELECT * FROM pay_slips WHERE pay_run_id = p_run AND tenant_id = v_run.tenant_id ORDER BY number, id
  LOOP
    v_n := v_n + 1;
    v_ci := COALESCE(v_slip.calc_inputs, '{}'::jsonb);
    v_csg := COALESCE((v_ci->>'csgDeductible')::numeric, 0) + COALESCE((v_ci->>'csgNonDeductible')::numeric, 0)
           + COALESCE((v_ci->>'crds')::numeric, 0);
    v_adv := COALESCE((v_ci->>'advanceDeduction')::numeric, 0);
    -- other_deductions regroupe CSG/CRDS, acompte et autres retenues (calculate_payslip)
    v_rest := COALESCE(v_slip.other_deductions, 0) - v_csg - v_adv;
    v_exp := COALESCE((v_ci->>'expenseReimbursement')::numeric, 0);
    v_meal := COALESCE((v_ci->>'mealVouchers')::numeric, 0);
    v_transp := COALESCE((v_ci->>'transportAllowance')::numeric, 0);

    v_d := COALESCE(v_slip.total_gross, 0) + COALESCE(v_slip.employer_contributions, 0) + v_exp + v_meal + v_transp;
    v_c := COALESCE(v_slip.social_security_employee, 0) + v_csg + COALESCE(v_slip.income_tax, 0) + v_adv + v_rest
         + COALESCE(v_slip.employer_contributions, 0) + COALESCE(v_slip.net_salary, 0);
    IF v_rest < 0 OR v_d <> v_c THEN
      RAISE EXCEPTION 'Bulletin % incohérent : brut % − retenues % + indemnités % ≠ net % (écart %) — recalculez-le avant de comptabiliser',
        v_slip.number, COALESCE(v_slip.total_gross, 0),
        COALESCE(v_slip.social_security_employee, 0) + COALESCE(v_slip.income_tax, 0) + COALESCE(v_slip.other_deductions, 0),
        v_exp + v_meal + v_transp, COALESCE(v_slip.net_salary, 0), v_d - v_c
        USING ERRCODE = 'check_violation';
    END IF;

    -- auxiliaire du salarié : le 421 et le 425 se lettrent salarié par salarié
    SELECT COALESCE(e.employee_number, left(e.id::text, 8)) INTO v_tiers
    FROM employees e WHERE e.id = v_slip.employee_id AND e.tenant_id = v_run.tenant_id;

    v_rows := v_rows || jsonb_build_array(
      jsonb_build_object('role', 'gross',                    'd', v_slip.total_gross,              'c', 0),
      jsonb_build_object('role', 'employer_contrib',         'd', v_slip.employer_contributions,   'c', 0),
      jsonb_build_object('role', 'expense_reimbursement',    'd', v_exp,                           'c', 0),
      jsonb_build_object('role', 'meal_vouchers',            'd', v_meal,                          'c', 0),
      jsonb_build_object('role', 'transport',                'd', v_transp,                        'c', 0),
      jsonb_build_object('role', 'employee_contrib',         'd', 0, 'c', v_slip.social_security_employee),
      jsonb_build_object('role', 'csg_crds',                 'd', 0, 'c', v_csg),
      jsonb_build_object('role', 'employer_contrib_payable', 'd', 0, 'c', v_slip.employer_contributions),
      jsonb_build_object('role', 'withholding',              'd', 0, 'c', v_slip.income_tax),
      jsonb_build_object('role', 'advance',                  'd', 0, 'c', v_adv,    'tiers', v_tiers),
      jsonb_build_object('role', 'other_deduction',          'd', 0, 'c', v_rest),
      jsonb_build_object('role', 'net',                      'd', 0, 'c', v_slip.net_salary, 'tiers', v_tiers));

    v_gross := v_gross + COALESCE(v_slip.total_gross, 0);
    v_employer := v_employer + COALESCE(v_slip.employer_contributions, 0);
    v_employee := v_employee + COALESCE(v_slip.total_deductions, 0);
    v_net := v_net + COALESCE(v_slip.net_salary, 0);
  END LOOP;

  IF v_n = 0 THEN
    RAISE EXCEPTION 'Lot de paie % sans bulletin : rien à comptabiliser', v_run.number USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO journals (tenant_id, code, name, type, status, locked, next_number)
  VALUES (v_run.tenant_id, 'PAIE', 'Journal de paie', 'general', 'active', false, 1)
  ON CONFLICT (tenant_id, code) DO NOTHING;

  INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description, reference, piece_number)
  VALUES (v_run.tenant_id, 'JE-PAIE-' || v_run.number, COALESCE(v_run.period_end, v_run.pay_date), 'PAIE', 'draft',
          'Paie ' || v_run.number, 'PAYROLL-' || v_run.number, v_run.number)
  RETURNING id INTO v_entry;

  -- Une ligne par compte et par sens : débits d'abord, puis crédits
  INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, account_tiers,
    debit, credit, description, line_order)
  SELECT v_run.tenant_id, v_entry, x.account, x.account, x.tiers,
         CASE WHEN x.side = 'D' THEN x.amount ELSE 0 END, CASE WHEN x.side = 'C' THEN x.amount ELSE 0 END,
         'Paie ' || v_run.number || COALESCE(' — ' || x.tiers, ''),
         row_number() OVER (ORDER BY x.side DESC, x.account, x.tiers)
  FROM (
    SELECT payroll_account(v_run.tenant_id, r.role) AS account,
           CASE WHEN r.d > 0 THEN 'D' ELSE 'C' END AS side,
           r.tiers,
           sum(r.d + r.c) AS amount
    FROM jsonb_to_recordset(v_rows) AS r(role text, d numeric, c numeric, tiers text)
    WHERE COALESCE(r.d, 0) + COALESCE(r.c, 0) > 0
    GROUP BY 1, 2, 3
  ) x;

  UPDATE journal_entries SET status = 'posted' WHERE id = v_entry;

  INSERT INTO payroll_accounting_entries (tenant_id, number, pay_run_id, period_date, gross_total,
    employer_contributions_total, employee_deductions_total, net_total, journal_entry_id, status)
  VALUES (v_run.tenant_id, 'PAIE-' || v_run.number, p_run, COALESCE(v_run.period_end, v_run.pay_date), v_gross,
    v_employer, v_employee, v_net, v_entry, 'transferred');

  UPDATE pay_slips SET journal_entry_id = v_entry, journal_posted = true
  WHERE pay_run_id = p_run AND tenant_id = v_run.tenant_id;

  RETURN jsonb_build_object('success', true, 'entry_id', v_entry, 'already_posted', false);
END $$;
REVOKE ALL ON FUNCTION payroll_post_run(uuid) FROM PUBLIC, anon, authenticated;

-- ------------------------------------------------------------
-- 4. Paiement de la paie
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION post_payroll_payment(
  p_pay_run_id uuid,
  p_bank_account_id uuid DEFAULT NULL,
  p_date date DEFAULT NULL,
  p_scope text DEFAULT 'all')
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_run pay_runs%ROWTYPE;
  v_scope text := lower(COALESCE(p_scope, 'all'));
  v_date date;
  v_tres record;
  v_net numeric; v_social numeric; v_tax numeric; v_adv_slips numeric; v_adv numeric;
  v_amount numeric;
  v_scopes text[] := ARRAY['net', 'social', 'tax', 'advances'];
  v_sc text;
  v_entry uuid; v_ref text; v_existing uuid;
  v_entries jsonb := '[]'::jsonb;
  v_already jsonb := '[]'::jsonb;
  v_remaining jsonb := '[]'::jsonb;
  v_slip record; v_order int;
  v_lines uuid[]; v_d numeric; v_c numeric; v_open int; v_code text;
BEGIN
  IF v_scope NOT IN ('net', 'social', 'tax', 'advances', 'all') THEN
    RAISE EXCEPTION 'Périmètre de paiement inconnu (%) : net, social, tax, advances ou all', p_scope
      USING ERRCODE = 'check_violation';
  END IF;

  SELECT * INTO v_run FROM pay_runs WHERE id = p_pay_run_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Lot de paie introuvable' USING ERRCODE = 'no_data_found';
  END IF;

  -- On ne paie que ce qui est comptabilisé : payroll_post_run est idempotente et
  -- refuse elle-même un lot en brouillon ou annulé.
  PERFORM payroll_post_run(p_pay_run_id);

  v_date := COALESCE(p_date, v_run.pay_date, CURRENT_DATE);
  SELECT * INTO v_tres FROM treasury_for_payment(v_run.tenant_id, p_bank_account_id, 'transfer');

  SELECT COALESCE(sum(s.net_salary), 0),
         COALESCE(sum(s.social_security_employee
                    + COALESCE((s.calc_inputs->>'csgDeductible')::numeric, 0)
                    + COALESCE((s.calc_inputs->>'csgNonDeductible')::numeric, 0)
                    + COALESCE((s.calc_inputs->>'crds')::numeric, 0)
                    + s.employer_contributions), 0),
         COALESCE(sum(s.income_tax), 0),
         COALESCE(sum(COALESCE((s.calc_inputs->>'advanceDeduction')::numeric, 0)), 0)
    INTO v_net, v_social, v_tax, v_adv_slips
  FROM pay_slips s WHERE s.pay_run_id = p_pay_run_id AND s.tenant_id = v_run.tenant_id;

  -- Acomptes réellement enregistrés pour la période (à défaut, ce que les
  -- bulletins ont retenu : un acompte versé hors suivi reste à comptabiliser)
  SELECT COALESCE(sum(amount), 0) INTO v_adv FROM salary_advances
  WHERE tenant_id = v_run.tenant_id AND deduction_month IS NOT NULL
    AND to_char(deduction_month, 'YYYY-MM') = to_char(v_run.period_start, 'YYYY-MM')
    AND status IN ('pending', 'deducted');
  IF v_adv = 0 THEN v_adv := v_adv_slips; END IF;

  FOREACH v_sc IN ARRAY v_scopes LOOP
    v_amount := CASE v_sc WHEN 'net' THEN v_net WHEN 'social' THEN v_social
                          WHEN 'tax' THEN v_tax ELSE v_adv END;
    CONTINUE WHEN v_amount <= 0;

    v_ref := 'PAYPAY-' || v_run.number || '-' || v_sc;
    SELECT id INTO v_existing FROM journal_entries
    WHERE tenant_id = v_run.tenant_id AND reference = v_ref LIMIT 1;

    IF v_existing IS NOT NULL THEN
      v_already := v_already || jsonb_build_array(jsonb_build_object('scope', v_sc, 'entry_id', v_existing));
      CONTINUE;
    END IF;

    IF v_scope <> 'all' AND v_scope <> v_sc THEN
      v_remaining := v_remaining || jsonb_build_array(jsonb_build_object('scope', v_sc, 'amount', v_amount));
      CONTINUE;
    END IF;

    INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description, reference, piece_number)
    VALUES (v_run.tenant_id, 'JE-' || v_ref, v_date, v_tres.journal_code, 'draft',
            CASE v_sc
              WHEN 'net' THEN 'Versement des salaires ' || v_run.number
              WHEN 'social' THEN 'Paiement des organismes sociaux ' || v_run.number
              WHEN 'tax' THEN 'Paiement de l''impôt retenu à la source ' || v_run.number
              ELSE 'Acomptes versés au personnel ' || v_run.number END,
            v_ref, v_run.number)
    RETURNING id INTO v_entry;

    IF v_sc = 'net' THEN
      -- une ligne par salarié : le 421 se lettre salarié par salarié
      v_order := 0;
      FOR v_slip IN
        SELECT s.net_salary, e.employee_number, e.id AS employee_id, e.name
        FROM pay_slips s LEFT JOIN employees e ON e.id = s.employee_id AND e.tenant_id = s.tenant_id
        WHERE s.pay_run_id = p_pay_run_id AND s.tenant_id = v_run.tenant_id AND COALESCE(s.net_salary, 0) > 0
        ORDER BY s.number, s.id
      LOOP
        INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, account_tiers,
          debit, credit, description, line_order)
        VALUES (v_run.tenant_id, v_entry, payroll_account(v_run.tenant_id, 'net'),
          payroll_account(v_run.tenant_id, 'net'),
          COALESCE(v_slip.employee_number, left(v_slip.employee_id::text, 8)),
          v_slip.net_salary, 0, 'Salaire net ' || COALESCE(v_slip.name, '') || ' — ' || v_run.number, v_order);
        v_order := v_order + 1;
      END LOOP;
    ELSE
      INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general,
        debit, credit, description, line_order)
      VALUES (v_run.tenant_id, v_entry,
        payroll_account(v_run.tenant_id, CASE v_sc WHEN 'social' THEN 'employee_contrib'
                                                   WHEN 'tax' THEN 'withholding' ELSE 'advance' END),
        payroll_account(v_run.tenant_id, CASE v_sc WHEN 'social' THEN 'employee_contrib'
                                                   WHEN 'tax' THEN 'withholding' ELSE 'advance' END),
        v_amount, 0,
        CASE v_sc WHEN 'social' THEN 'Organismes sociaux ' WHEN 'tax' THEN 'Impôt retenu ' ELSE 'Acomptes ' END
          || v_run.number, 0);
      v_order := 1;
    END IF;

    INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general,
      debit, credit, description, line_order)
    VALUES (v_run.tenant_id, v_entry, v_tres.account_code, v_tres.account_code,
      0, v_amount, 'Paiement paie ' || v_run.number, v_order);

    UPDATE journal_entries SET status = 'posted' WHERE id = v_entry;
    v_entries := v_entries || jsonb_build_array(jsonb_build_object('scope', v_sc, 'entry_id', v_entry, 'amount', v_amount));

    IF v_sc = 'advances' THEN
      UPDATE salary_advances SET status = 'deducted'
      WHERE tenant_id = v_run.tenant_id AND status = 'pending' AND deduction_month IS NOT NULL
        AND to_char(deduction_month, 'YYYY-MM') = to_char(v_run.period_start, 'YYYY-MM');
    END IF;

    -- 421 soldé (écriture de paie + versement) → lettrage
    IF v_sc = 'net' THEN
      SELECT array_agg(jl.id), COALESCE(sum(jl.debit), 0), COALESCE(sum(jl.credit), 0),
             count(*) FILTER (WHERE jl.lettrage_code IS NULL)
        INTO v_lines, v_d, v_c, v_open
      FROM journal_lines jl
      WHERE jl.tenant_id = v_run.tenant_id
        AND jl.account_code = payroll_account(v_run.tenant_id, 'net')
        AND jl.journal_id IN (SELECT id FROM journal_entries
                              WHERE tenant_id = v_run.tenant_id
                                AND reference IN ('PAYROLL-' || v_run.number, v_ref));
      IF v_open = COALESCE(array_length(v_lines, 1), 0) AND v_open > 1 AND v_d = v_c THEN
        v_code := next_lettrage_code_for(v_run.tenant_id);
        UPDATE journal_lines SET lettrage_code = v_code, lettrage_date = v_date WHERE id = ANY(v_lines);
      END IF;
    END IF;
  END LOOP;

  -- Périmètres dus mais pas encore payés
  v_remaining := '[]'::jsonb;
  FOREACH v_sc IN ARRAY v_scopes LOOP
    v_amount := CASE v_sc WHEN 'net' THEN v_net WHEN 'social' THEN v_social
                          WHEN 'tax' THEN v_tax ELSE v_adv END;
    CONTINUE WHEN v_amount <= 0;
    IF NOT EXISTS (SELECT 1 FROM journal_entries WHERE tenant_id = v_run.tenant_id
                   AND reference = 'PAYPAY-' || v_run.number || '-' || v_sc) THEN
      v_remaining := v_remaining || jsonb_build_array(jsonb_build_object('scope', v_sc, 'amount', v_amount));
    END IF;
  END LOOP;

  IF jsonb_array_length(v_remaining) = 0 AND v_run.status <> 'paid' THEN
    UPDATE pay_runs SET status = 'paid' WHERE id = p_pay_run_id;
  END IF;

  RETURN jsonb_build_object('success', true, 'pay_run_id', p_pay_run_id, 'date', v_date,
    'entries', v_entries, 'already_paid', v_already, 'remaining', v_remaining);
END $$;

REVOKE ALL ON FUNCTION post_payroll_payment(uuid, uuid, date, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION post_payroll_payment(uuid, uuid, date, text) TO authenticated;

COMMENT ON FUNCTION post_payroll_payment(uuid, uuid, date, text) IS
  'R-04 : paie payée. Périmètres net (421 par salarié, lettré), social (431), tax (447), advances (425), ou all. Idempotente par référence PAYPAY-<lot>-<périmètre>.';
