-- ============================================================
-- 224_payroll_payment_scope.sql — deux défauts du versement de la paie (212)
--
-- Trouvés en vérifiant R-04 en profondeur, mesurés sur base neuve.
--
-- 1. ISOLATION DES SOCIÉTÉS. `payroll_payment_inner` (ex-`post_payroll_payment`,
--    renommée par la 220) lit `pay_runs WHERE id = p_pay_run_id` SANS filtre de
--    société, en SECURITY DEFINER — donc hors RLS. La garde de permission
--    ajoutée par la 220 n'y change rien : `has_permission('payroll.pay')`
--    s'évalue dans la société de l'APPELANT. Un administrateur de la société A
--    qui passe l'uuid d'un lot de la société B comptabilisait la paie de B et
--    son versement dans les livres de B, et recevait ses montants en retour.
--    La RPC est exposée à `authenticated` (src/lib/queries/misc.ts).
--    `post_payroll_journal`, dans la 220 elle-même, contrôle la société : c'est
--    ce contrôle-là qui manquait ici.
--
-- 2. PÉRIMÈTRE « SOCIAL ». L'écriture de paie (191) crédite trois rôles
--    distincts — `employee_contrib`, `csg_crds`, `employer_contrib_payable` —
--    mais le versement débitait leur somme sur le seul compte du rôle
--    `employee_contrib`. Avec le mapping par défaut (les trois en 431000) cela
--    ne se voyait pas ; dès qu'une société sépare ses comptes (ce que
--    `payroll_account_mapping` existe pour permettre, et ce que les packs pays
--    du lot K feront), les autres dettes ne se soldaient jamais : 431000 en
--    solde débiteur, 437000 et 438600 toujours créditeurs. Le versement débite
--    désormais chaque compte de son propre montant, agrégé par compte — le
--    mapping par défaut donne donc toujours une seule ligne 431000.
--
-- Scénarios : sql/224_payroll_payment_scope_tests.sql (P17, P18, P19).
-- ============================================================

CREATE OR REPLACE FUNCTION public.payroll_payment_inner(
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
  v_soc_emp numeric; v_soc_csg numeric; v_soc_pat numeric;
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

  -- Isolation des sociétés : le lot doit appartenir à la société active.
  -- SECURITY DEFINER contourne RLS — sans ce filtre, n'importe quel uuid passe.
  IF current_tenant_id() IS NULL THEN
    RAISE EXCEPTION 'Aucune société active' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT * INTO v_run FROM pay_runs
  WHERE id = p_pay_run_id AND tenant_id = current_tenant_id() FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Lot de paie introuvable' USING ERRCODE = 'no_data_found';
  END IF;

  -- On ne paie que ce qui est comptabilisé : payroll_post_run est idempotente et
  -- refuse elle-même un lot en brouillon ou annulé.
  PERFORM payroll_post_run(p_pay_run_id);

  v_date := COALESCE(p_date, v_run.pay_date, CURRENT_DATE);
  SELECT * INTO v_tres FROM treasury_for_payment(v_run.tenant_id, p_bank_account_id, 'transfer');

  -- Les trois dettes sociales restent distinctes : ce sont trois rôles de comptes
  SELECT COALESCE(sum(s.net_salary), 0),
         COALESCE(sum(s.social_security_employee), 0),
         COALESCE(sum(COALESCE((s.calc_inputs->>'csgDeductible')::numeric, 0)
                    + COALESCE((s.calc_inputs->>'csgNonDeductible')::numeric, 0)
                    + COALESCE((s.calc_inputs->>'crds')::numeric, 0)), 0),
         COALESCE(sum(s.employer_contributions), 0),
         COALESCE(sum(s.income_tax), 0),
         COALESCE(sum(COALESCE((s.calc_inputs->>'advanceDeduction')::numeric, 0)), 0)
    INTO v_net, v_soc_emp, v_soc_csg, v_soc_pat, v_tax, v_adv_slips
  FROM pay_slips s WHERE s.pay_run_id = p_pay_run_id AND s.tenant_id = v_run.tenant_id;
  v_social := v_soc_emp + v_soc_csg + v_soc_pat;

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
    ELSIF v_sc = 'social' THEN
      -- une ligne par COMPTE de dette sociale : les trois rôles peuvent viser
      -- trois comptes différents ; avec le mapping par défaut ils n'en font qu'un
      v_order := 0;
      FOR v_slip IN
        SELECT payroll_account(v_run.tenant_id, d.role) AS compte, sum(d.montant) AS montant
        FROM (VALUES ('employee_contrib', v_soc_emp),
                     ('csg_crds', v_soc_csg),
                     ('employer_contrib_payable', v_soc_pat)) AS d(role, montant)
        WHERE d.montant > 0
        GROUP BY 1 ORDER BY 1
      LOOP
        INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general,
          debit, credit, description, line_order)
        VALUES (v_run.tenant_id, v_entry, v_slip.compte, v_slip.compte,
          v_slip.montant, 0, 'Organismes sociaux ' || v_run.number, v_order);
        v_order := v_order + 1;
      END LOOP;
    ELSE
      INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general,
        debit, credit, description, line_order)
      VALUES (v_run.tenant_id, v_entry,
        payroll_account(v_run.tenant_id, CASE v_sc WHEN 'tax' THEN 'withholding' ELSE 'advance' END),
        payroll_account(v_run.tenant_id, CASE v_sc WHEN 'tax' THEN 'withholding' ELSE 'advance' END),
        v_amount, 0,
        CASE v_sc WHEN 'tax' THEN 'Impôt retenu ' ELSE 'Acomptes ' END || v_run.number, 0);
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

REVOKE ALL ON FUNCTION public.payroll_payment_inner(uuid, uuid, date, text) FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION public.payroll_payment_inner(uuid, uuid, date, text) IS
  'Corps du versement de la paie : n''accepte qu''un lot de la société active (224). '
  'Ne pas appeler directement — passer par post_payroll_payment, qui garde payroll.pay (220).';
