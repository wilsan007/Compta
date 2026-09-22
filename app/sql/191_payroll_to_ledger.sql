-- ============================================================
-- 191_payroll_to_ledger.sql — lot F du plan correctif du 21/09
-- (doc/audit/PLAN-CORRECTIF-AUDIT-2026-09-21.md, vague V3)
--
-- Défauts prouvés par sql/181_payroll_to_ledger_tests.sql :
--   AUD-F02  l'écriture de paie était construite par le front depuis les totaux
--            du lot (cotisations salariales absentes : 4 260 ≠ 3 600), en double
--            avec le trigger du passage à « payé », qui la laissait en brouillard
--            dans OD avec l'impôt retenu au 431 (P01, P02, P04 à P07)
--   AUD-F03  comptes 641/645/421/431 codés en dur (P03)
--
-- Une seule fonction, payroll_post_run, écrit l'écriture de paie : depuis les
-- rubriques des bulletins, au journal PAIE, idempotente. Le bouton du front
-- (RPC post_payroll_journal) et le passage du lot à « payé » l'appellent.
--
-- Les comptes par défaut sont ceux du PCG français. Chaque société peut les
-- remplacer (payroll_account_mapping) ; le lot K les remplacera par le pack pays.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Comptes par rubrique (AUD-F03)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS payroll_account_mapping (
  id           uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id    uuid REFERENCES tenants(id) ON DELETE CASCADE,
  role         text NOT NULL CHECK (role IN (
                 'gross', 'employer_contrib', 'expense_reimbursement', 'meal_vouchers', 'transport',
                 'employee_contrib', 'csg_crds', 'employer_contrib_payable', 'withholding',
                 'advance', 'other_deduction', 'net')),
  account_code text NOT NULL,
  created_at   timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE payroll_account_mapping IS
  'AUD-F03 — compte comptable de chaque rubrique de paie. tenant_id NULL : valeur par défaut ; une ligne de la société la remplace.';
CREATE UNIQUE INDEX IF NOT EXISTS uniq_payroll_account_mapping
  ON payroll_account_mapping (COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), role);

ALTER TABLE payroll_account_mapping ENABLE ROW LEVEL SECURITY;
ALTER TABLE payroll_account_mapping FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS payroll_account_mapping_select ON payroll_account_mapping;
CREATE POLICY payroll_account_mapping_select ON payroll_account_mapping
  FOR SELECT USING (tenant_id IS NULL OR tenant_id = current_tenant_id());
DROP POLICY IF EXISTS payroll_account_mapping_write ON payroll_account_mapping;
CREATE POLICY payroll_account_mapping_write ON payroll_account_mapping
  FOR ALL USING (tenant_id = current_tenant_id()) WITH CHECK (tenant_id = current_tenant_id());
GRANT SELECT, INSERT, UPDATE, DELETE ON payroll_account_mapping TO authenticated;

DROP TRIGGER IF EXISTS set_tenant_id_payroll_account_mapping ON payroll_account_mapping;
CREATE TRIGGER set_tenant_id_payroll_account_mapping
  BEFORE INSERT ON payroll_account_mapping
  FOR EACH ROW EXECUTE FUNCTION set_tenant_id();

INSERT INTO payroll_account_mapping (tenant_id, role, account_code) VALUES
  (NULL, 'gross',                    '641000'),
  (NULL, 'employer_contrib',         '645000'),
  (NULL, 'expense_reimbursement',    '625100'),
  (NULL, 'meal_vouchers',            '647800'),
  (NULL, 'transport',                '641400'),
  (NULL, 'employee_contrib',         '431000'),
  (NULL, 'csg_crds',                 '431000'),
  (NULL, 'employer_contrib_payable', '431000'),
  (NULL, 'withholding',              '447000'),
  (NULL, 'advance',                  '425000'),
  (NULL, 'other_deduction',          '427000'),
  (NULL, 'net',                      '421000')
ON CONFLICT DO NOTHING;

CREATE OR REPLACE FUNCTION payroll_account(p_tenant uuid, p_role text)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT account_code FROM payroll_account_mapping
  WHERE role = p_role AND (tenant_id = p_tenant OR tenant_id IS NULL)
  ORDER BY tenant_id NULLS LAST
  LIMIT 1
$$;
REVOKE ALL ON FUNCTION payroll_account(uuid, text) FROM PUBLIC, anon, authenticated;

-- ------------------------------------------------------------
-- 2. Écriture de paie depuis les bulletins (AUD-F02)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION payroll_post_run(p_run uuid)
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
      jsonb_build_object('role', 'advance',                  'd', 0, 'c', v_adv),
      jsonb_build_object('role', 'other_deduction',          'd', 0, 'c', v_rest),
      jsonb_build_object('role', 'net',                      'd', 0, 'c', v_slip.net_salary));

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
  INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, debit, credit, description, line_order)
  SELECT v_run.tenant_id, v_entry, x.account, x.account,
         CASE WHEN x.side = 'D' THEN x.amount ELSE 0 END, CASE WHEN x.side = 'C' THEN x.amount ELSE 0 END,
         'Paie ' || v_run.number, row_number() OVER (ORDER BY x.side DESC, x.account)
  FROM (
    SELECT payroll_account(v_run.tenant_id, r.role) AS account,
           CASE WHEN r.d > 0 THEN 'D' ELSE 'C' END AS side,
           sum(r.d + r.c) AS amount
    FROM jsonb_to_recordset(v_rows) AS r(role text, d numeric, c numeric)
    WHERE COALESCE(r.d, 0) + COALESCE(r.c, 0) > 0
    GROUP BY 1, 2
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

-- RPC du bouton « Générer l'écriture de paie »
CREATE OR REPLACE FUNCTION post_payroll_journal(p_pay_run_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF current_tenant_id() IS NULL OR NOT EXISTS (
       SELECT 1 FROM pay_runs WHERE id = p_pay_run_id AND tenant_id = current_tenant_id()) THEN
    RAISE EXCEPTION 'Lot de paie introuvable' USING ERRCODE = 'no_data_found';
  END IF;
  RETURN payroll_post_run(p_pay_run_id);
END $$;
REVOKE ALL ON FUNCTION post_payroll_journal(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION post_payroll_journal(uuid) TO authenticated;

-- Passage du lot à « payé » : même écriture, si le bouton ne l'a pas déjà produite
CREATE OR REPLACE FUNCTION public.create_journal_on_payroll_validate()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.status = 'paid' AND OLD.status IS DISTINCT FROM 'paid' THEN
    PERFORM payroll_post_run(NEW.id);
  END IF;
  RETURN NEW;
END $$;
