-- ============================================================
-- 224_payroll_payment_scope_tests.sql — deux défauts du versement de la paie
--
-- P17 : un utilisateur d'une société ne verse pas la paie d'une AUTRE société.
--       Avant la 224 : écritures créées dans les livres de l'autre société et
--       montants renvoyés à l'appelant (la garde `payroll.pay` de la 220
--       s'évalue dans la société de l'appelant, pas dans celle du lot).
-- P18 : trois comptes de dettes sociales distincts sont tous soldés.
--       Avant la 224 : 431000 = −1 460, 437000 = +1 260, 438600 = +200.
-- P19 : non-régression du mapping par défaut — une seule ligne 431000 de 3 720.
--
-- Bulletin type (212) : brut 3 000, cotisations salariales 400, CSG/CRDS 200,
-- impôt 60 → net 2 340 ; charges patronales 1 260.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '224', false);
DELETE FROM _audit_results WHERE file = '224';

CREATE OR REPLACE FUNCTION _mk_run224(p_t uuid, p_number text, p_slips int DEFAULT 2)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE r uuid; e uuid; i int;
BEGIN
  INSERT INTO pay_runs (tenant_id, number, period_start, period_end, pay_date, status,
    gross_total, tax_total, net_total, employee_count)
  VALUES (p_t, p_number, '2026-03-01', '2026-03-31', '2026-03-31', 'draft',
    3000 * p_slips, 660 * p_slips, 2340 * p_slips, p_slips)
  RETURNING id INTO r;
  FOR i IN 1..p_slips LOOP
    INSERT INTO employees (tenant_id, name, email, status, employee_number)
    VALUES (p_t, 'Salarié ' || i, lower(p_number) || '-' || i || '@audit.test', 'active', p_number || '-S' || i)
    RETURNING id INTO e;
    INSERT INTO pay_slips (tenant_id, number, pay_run_id, employee_id, period_start, period_end,
      gross_salary, total_gross, social_security_employee, income_tax, other_deductions, total_deductions,
      net_salary, employer_contributions, status, calc_inputs)
    VALUES (p_t, p_number || '-BS' || i, r, e, '2026-03-01', '2026-03-31',
      3000, 3000, 400, 60, 200, 660, 2340, 1260, 'draft',
      jsonb_build_object('csgDeductible', 120, 'csgNonDeductible', 60, 'crds', 20,
                         'advanceDeduction', 0, 'otherDeductions', 0));
  END LOOP;
  UPDATE pay_runs SET status = 'approved' WHERE id = r;
  RETURN r;
END $$;

-- P17 — isolation des sociétés : payer la paie d'une autre société est refusé
DO $$
DECLARE tb uuid; ta uuid; r uuid; res jsonb; n int; err text := '—'; refuse boolean := false;
BEGIN
  tb := _mk_tenant('P17B');                  -- société B : son lot de paie
  r := _mk_run224(tb, 'PR17B', 2);
  ta := _mk_tenant('P17A');                  -- société A : le contexte bascule sur A
  PERFORM _as_user();
  BEGIN
    res := post_payroll_payment(r, NULL, DATE '2026-03-31', 'net');
  EXCEPTION WHEN OTHERS THEN refuse := true; err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);   -- compter sans RLS, sinon B est invisible
  SELECT count(*) INTO n FROM journal_entries WHERE tenant_id = tb AND reference LIKE 'PAYPAY-%';
  PERFORM _rec('P17', 'un utilisateur de la société A ne verse pas la paie d''un lot de la société B',
    refuse AND n = 0,
    format('refus=%s écritures créées chez B=%s | %s | retour=%s',
           refuse, n, left(err, 90), left(COALESCE(res::text, '—'), 90)));
END $$;

-- P18 — trois comptes de dettes sociales distincts : tous soldés par le versement
DO $$
DECLARE t uuid := _mk_tenant('P18'); r uuid; res jsonb; v record; err text := '—';
BEGIN
  INSERT INTO payroll_account_mapping (tenant_id, role, account_code) VALUES
    (t, 'employer_contrib_payable', '437000'),
    (t, 'csg_crds', '438600');
  r := _mk_run224(t, 'PR18', 1);
  PERFORM _as_user();
  BEGIN
    res := post_payroll_payment(r, NULL, DATE '2026-03-31', 'social');
  EXCEPTION WHEN OTHERS THEN err := SQLERRM;
  END;
  SELECT COALESCE(sum(credit - debit) FILTER (WHERE account_code = '431000'), 0) AS s431,
         COALESCE(sum(credit - debit) FILTER (WHERE account_code = '437000'), 0) AS s437,
         COALESCE(sum(credit - debit) FILTER (WHERE account_code = '438600'), 0) AS s4386,
         COALESCE(sum(credit) FILTER (WHERE account_code = '512000'), 0) AS c512
    INTO v FROM journal_lines WHERE tenant_id = t;
  PERFORM _rec('P18', 'cotisations 400 en 431000, CSG 200 en 438600, patronales 1 260 en 437000 : les trois soldés',
    v.s431 = 0 AND v.s437 = 0 AND v.s4386 = 0 AND v.c512 = 1860,
    format('solde 431000=%s 437000=%s 438600=%s ; banque créditée=%s (1 860 attendu) | %s',
           v.s431, v.s437, v.s4386, v.c512, left(err, 80)));
END $$;

-- P19 — non-régression : mapping par défaut, une seule ligne 431000 de 3 720
DO $$
DECLARE t uuid := _mk_tenant('P19'); r uuid; res jsonb; v record; err text := '—';
BEGIN
  r := _mk_run224(t, 'PR19', 2);
  PERFORM _as_user();
  BEGIN
    res := post_payroll_payment(r, NULL, DATE '2026-03-31', 'social');
  EXCEPTION WHEN OTHERS THEN err := SQLERRM;
  END;
  SELECT COALESCE(sum(jl.debit) FILTER (WHERE jl.account_code = '431000'), 0) AS d431,
         count(*) FILTER (WHERE jl.account_code = '431000') AS n431,
         COALESCE(sum(jl.credit) FILTER (WHERE jl.account_code = '512000'), 0) AS c512
    INTO v FROM journal_lines jl JOIN journal_entries je ON je.id = jl.journal_id
    WHERE je.tenant_id = t AND je.reference = 'PAYPAY-PR19-social';
  PERFORM _rec('P19', 'mapping par défaut : (400 + 200 + 1 260) × 2 = 3 720 en une seule ligne 431000',
    v.d431 = 3720 AND v.n431 = 1 AND v.c512 = 3720,
    format('D431000=%s en %s ligne(s) ; C512000=%s | %s', v.d431, v.n431, v.c512, left(err, 80)));
END $$;

DROP FUNCTION _mk_run224(uuid, text, int);
SELECT _audit_assert('224');
