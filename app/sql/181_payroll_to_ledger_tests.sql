-- ============================================================
-- 181_payroll_to_ledger_tests.sql — AUD-A01, lot F du plan correctif
--
-- Jusqu'à V2, P01/P02 rejouaient la charge utile de misc.ts:generatePayrollJournal
-- (écriture construite par le front depuis les totaux du lot de paie, sans les
-- cotisations salariales : 4 260 ≠ 3 600). AUD-F02 remplace ce bouton par la RPC
-- serveur post_payroll_journal(pay_run_id), construite depuis les rubriques des
-- bulletins : P01/P02 sont réécrits sur cette RPC, comme annoncé.
--
-- Bulletin type (brut 3 000) : cotisations salariales 400, CSG/CRDS 200,
-- impôt retenu 60 → net 2 340 ; charges patronales 1 260.
-- Écriture attendue : D 641 3 000 + D 645 1 260 = C 421 2 340 + C 431 1 860 + C 447 60.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '181', false);
DELETE FROM _audit_results WHERE file = '181';

-- Lot de paie approuvé avec un bulletin type, ou deux
CREATE OR REPLACE FUNCTION _mk_pay_run(p_t uuid, p_number text, p_status text DEFAULT 'approved', p_slips int DEFAULT 1,
  p_net numeric DEFAULT 2340)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE r uuid; e uuid;
BEGIN
  INSERT INTO pay_runs (tenant_id, number, period_start, period_end, pay_date, status, gross_total, tax_total, net_total, employee_count)
  VALUES (p_t, p_number, '2026-03-01', '2026-03-31', '2026-03-31', 'draft', 3000 * p_slips, 660 * p_slips, p_net * p_slips, p_slips)
  RETURNING id INTO r;
  FOR i IN 1..p_slips LOOP
    INSERT INTO employees (tenant_id, name, email, status) VALUES (p_t, 'Salarié ' || i, p_number || '-' || i || '@audit.test', 'active')
    RETURNING id INTO e;
    INSERT INTO pay_slips (tenant_id, number, pay_run_id, employee_id, period_start, period_end,
      gross_salary, total_gross, social_security_employee, income_tax, other_deductions, total_deductions,
      net_salary, employer_contributions, status, calc_inputs)
    VALUES (p_t, p_number || '-BS' || i, r, e, '2026-03-01', '2026-03-31',
      3000, 3000, 400, 60, 200, 660, p_net, 1260, 'draft',
      '{"csgDeductible": 120, "csgNonDeductible": 60, "crds": 20, "advanceDeduction": 0, "otherDeductions": 0}');
  END LOOP;
  IF p_status <> 'draft' THEN UPDATE pay_runs SET status = p_status WHERE id = r; END IF;
  RETURN r;
END $$;

-- P01 — le bouton « Générer l'écriture de paie » : écriture validée et équilibrée, rubrique par rubrique
DO $$ DECLARE t uuid := _mk_tenant('P01'); r uuid; res jsonb; e uuid; v record; BEGIN
  PERFORM _as_user();
  BEGIN
    r := _mk_pay_run(t, 'PR1');
    res := post_payroll_journal(r);
    e := (res->>'entry_id')::uuid;
    SELECT je.status, je.journal_code,
           sum(jl.debit) FILTER (WHERE jl.account_code = '641000') d641, sum(jl.debit) FILTER (WHERE jl.account_code = '645000') d645,
           sum(jl.credit) FILTER (WHERE jl.account_code = '421000') c421, sum(jl.credit) FILTER (WHERE jl.account_code = '431000') c431,
           sum(jl.credit) FILTER (WHERE jl.account_code = '447000') c447, sum(jl.debit) d, sum(jl.credit) c
      INTO v FROM journal_entries je JOIN journal_lines jl ON jl.journal_id = je.id WHERE je.id = e GROUP BY je.status, je.journal_code;
    PERFORM _rec('P01', 'écriture de paie validée : D 641 3 000 + D 645 1 260 = C 421 2 340 + C 431 1 860 + C 447 60',
      v.status = 'posted' AND v.d641 = 3000 AND v.d645 = 1260 AND v.c421 = 2340 AND v.c431 = 1860 AND v.c447 = 60 AND v.d = 4260 AND v.c = 4260,
      format('%s | statut=%s D641=%s D645=%s C421=%s C431=%s C447=%s D=%s C=%s', res, v.status, v.d641, v.d645, v.c421, v.c431, v.c447, v.d, v.c));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('P01', 'écriture de paie validée : D 641 3 000 + D 645 1 260 = C 421 2 340 + C 431 1 860 + C 447 60', false, SQLERRM); END;
END $$;

-- P02 — journal PAIE, idempotence, bulletins rattachés
DO $$ DECLARE t uuid := _mk_tenant('P02'); r uuid; r1 jsonb; r2 jsonb; n int; jc text; linked int; BEGIN
  PERFORM _as_user();
  BEGIN
    r := _mk_pay_run(t, 'PR2', 'approved', 2);
    r1 := post_payroll_journal(r);
    r2 := post_payroll_journal(r);
    SELECT count(*) INTO n FROM journal_entries WHERE tenant_id = t AND journal_code = 'PAIE';
    SELECT journal_code INTO jc FROM journal_entries WHERE id = (r1->>'entry_id')::uuid;
    SELECT count(*) INTO linked FROM pay_slips WHERE pay_run_id = r AND journal_entry_id = (r1->>'entry_id')::uuid AND journal_posted;
    PERFORM _rec('P02', 'journal PAIE, 2e appel sans doublon, 2 bulletins rattachés à l''écriture',
      jc = 'PAIE' AND n = 1 AND r1->>'entry_id' = r2->>'entry_id' AND linked = 2,
      format('journal=%s écritures=%s même écriture=%s bulletins rattachés=%s', jc, n, r1->>'entry_id' = r2->>'entry_id', linked));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('P02', 'journal PAIE, 2e appel sans doublon, 2 bulletins rattachés à l''écriture', false, SQLERRM); END;
END $$;

-- P03 — AUD-F03 : comptes par rubrique, propres à la société
DO $$ DECLARE t uuid := _mk_tenant('P03'); r uuid; res jsonb; d6451 numeric; BEGIN
  BEGIN
    EXECUTE 'INSERT INTO payroll_account_mapping (tenant_id, role, account_code) VALUES ($1, ''employer_contrib'', ''645100'')' USING t;
    PERFORM _as_user();
    r := _mk_pay_run(t, 'PR3');
    res := post_payroll_journal(r);
    SELECT sum(debit) INTO d6451 FROM journal_lines WHERE journal_id = (res->>'entry_id')::uuid AND account_code = '645100';
    PERFORM _rec('P03', 'charges patronales imputées au compte choisi par la société (645100)', d6451 = 1260, 'D645100=' || COALESCE(d6451::text, '∅'));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('P03', 'charges patronales imputées au compte choisi par la société (645100)', false, SQLERRM); END;
END $$;

-- P04 — le passage du lot à « payé » ne crée pas une seconde écriture
DO $$ DECLARE t uuid := _mk_tenant('P04'); r uuid; n int; BEGIN
  PERFORM _as_user();
  BEGIN
    r := _mk_pay_run(t, 'PR4');
    PERFORM post_payroll_journal(r);
    UPDATE pay_runs SET status = 'paid' WHERE id = r;
    SELECT count(*) INTO n FROM journal_entries WHERE tenant_id = t AND (journal_code = 'PAIE' OR reference LIKE 'PAYROLL-%');
    PERFORM _rec('P04', 'bouton puis passage à payé : une seule écriture de paie', n = 1, 'écritures de paie=' || n);
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('P04', 'bouton puis passage à payé : une seule écriture de paie', false, SQLERRM); END;
END $$;

-- P05 — un bulletin incohérent (net ≠ brut − retenues) est refusé, rien n'est écrit
DO $$ DECLARE t uuid := _mk_tenant('P05'); r uuid; ok boolean := false; msg text; n int; BEGIN
  PERFORM _as_user();
  BEGIN
    r := _mk_pay_run(t, 'PR5', 'approved', 1, 2500);
    BEGIN PERFORM post_payroll_journal(r); EXCEPTION WHEN OTHERS THEN ok := true; msg := SQLERRM; END;
    SELECT count(*) INTO n FROM journal_entries WHERE tenant_id = t;
    -- témoin : sans RPC, le test passerait sans rien prouver
    PERFORM _rec('P05', 'bulletin net 2 500 au lieu de 2 340 : refusé avec le bulletin en cause, aucune écriture',
      ok AND n = 0 AND msg LIKE '%PR5-BS1%', format('refus=%s écritures=%s | %s', ok, n, msg));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('P05', 'bulletin net 2 500 au lieu de 2 340 : refusé avec le bulletin en cause, aucune écriture', false, SQLERRM); END;
END $$;

-- P06 — un lot de paie en brouillon ne se comptabilise pas
DO $$ DECLARE t uuid := _mk_tenant('P06'); r uuid; ok boolean := false; msg text; BEGIN
  PERFORM _as_user();
  BEGIN
    r := _mk_pay_run(t, 'PR6', 'draft');
    BEGIN PERFORM post_payroll_journal(r); EXCEPTION WHEN OTHERS THEN ok := true; msg := SQLERRM; END;
    PERFORM _rec('P06', 'lot en brouillon refusé (message sur le statut)', ok AND msg ILIKE '%brouillon%', COALESCE(msg, 'accepté'));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('P06', 'lot en brouillon refusé (message sur le statut)', false, SQLERRM); END;
END $$;

-- P07 — passage direct à « payé » (sans le bouton) : même écriture, validée, au journal PAIE
DO $$ DECLARE t uuid := _mk_tenant('P07'); r uuid; v record; BEGIN
  PERFORM _as_user();
  BEGIN
    r := _mk_pay_run(t, 'PR7');
    UPDATE pay_runs SET status = 'paid' WHERE id = r;
    SELECT count(DISTINCT je.id) n, max(je.status) st, max(je.journal_code) jc,
           sum(jl.credit) FILTER (WHERE jl.account_code = '447000') c447, sum(jl.debit) d, sum(jl.credit) c
      INTO v FROM journal_entries je JOIN journal_lines jl ON jl.journal_id = je.id
     WHERE je.tenant_id = t AND je.reference = 'PAYROLL-PR7';
    PERFORM _rec('P07', 'lot passé à payé : une écriture PAIE validée, impôt retenu au 447, 4 260 = 4 260',
      v.n = 1 AND v.st = 'posted' AND v.jc = 'PAIE' AND v.c447 = 60 AND v.d = 4260 AND v.c = 4260,
      format('écritures=%s statut=%s journal=%s C447=%s D=%s C=%s', v.n, v.st, v.jc, v.c447, v.d, v.c));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('P07', 'lot passé à payé : une écriture PAIE validée, impôt retenu au 447, 4 260 = 4 260', false, SQLERRM); END;
END $$;

SELECT _audit_assert('181');
