-- ============================================================
-- 220_payroll_permission_tests.sql — R-17 : les RPC de paie gardent le rôle
--
-- Avant la 220, `post_payroll_journal` et `post_payroll_payment` ne vérifiaient
-- que la société : un lecteur pouvait déclencher l'écriture de paie et son
-- versement par un appel direct (le contrôle de la 154 ne se déclenche qu'au
-- moment d'écrire, et son message ne dit rien du droit métier).
--
-- P01 — administrateur : payroll.post et payroll.pay, écriture générée
-- P02 — comptable : les deux aussi (socle du métier) et écriture générée
-- P03 — lecteur : refus explicite sur les deux RPC
-- P04 — administrateur révoqué : aucun droit, refus
-- P05 — le corps renommé n'est plus exécutable par l'application : la garde
--       n'est pas contournable en appelant l'ancien nom directement
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '220', false);
DELETE FROM _audit_results WHERE file = '220';

CREATE OR REPLACE FUNCTION _role220(p_tenant uuid, p_email text, p_role text, p_status text DEFAULT 'active')
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE a uuid := uuid_generate_v4();
BEGIN
  INSERT INTO auth.users (id, email) VALUES (a, p_email);
  INSERT INTO tenant_users (tenant_id, auth_id, email, name, role, status)
  VALUES (p_tenant, a, p_email, p_email, p_role, p_status);
  RETURN a;
END $$;

-- Lot de paie approuvé, cohérent, prêt à être comptabilisé
CREATE OR REPLACE FUNCTION _lot220(p_t uuid, p_number text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE r uuid; e uuid;
BEGIN
  INSERT INTO pay_runs (tenant_id, number, period_start, period_end, pay_date, status,
                        gross_total, tax_total, net_total, employee_count)
  VALUES (p_t, p_number, '2026-03-01', '2026-03-31', '2026-03-31', 'draft', 3000, 60, 2340, 1)
  RETURNING id INTO r;
  INSERT INTO employees (tenant_id, name, email, status, employee_number)
  VALUES (p_t, 'Salarié 220', lower(p_number) || '@perm.test', 'active', p_number || '-S1')
  RETURNING id INTO e;
  INSERT INTO pay_slips (tenant_id, number, pay_run_id, employee_id, period_start, period_end,
                         gross_salary, total_gross, social_security_employee, income_tax,
                         other_deductions, total_deductions, net_salary, employer_contributions,
                         status, calc_inputs)
  VALUES (p_t, p_number || '-BS1', r, e, '2026-03-01', '2026-03-31',
          3000, 3000, 400, 60, 200, 660, 2340, 1260, 'draft',
          jsonb_build_object('csgDeductible', 120, 'csgNonDeductible', 60, 'crds', 20,
                             'advanceDeduction', 0, 'otherDeductions', 0));
  UPDATE pay_runs SET status = 'approved' WHERE id = r;
  RETURN r;
END $$;

DO $$
DECLARE t uuid; u_admin uuid; u_compta uuid; u_lecteur uuid; u_revoque uuid;
        la uuid; lb uuid; res jsonb; faux boolean; msg text;
BEGIN
  EXECUTE 'RESET ROLE';
  t := _mk_tenant('R17');
  PERFORM ensure_standard_journals(t);   -- le journal PAIE est requis par l'écriture de paie
  u_admin   := _role220(t, 'admin-r17@perm.test',   'admin');
  u_compta  := _role220(t, 'compta-r17@perm.test',  'accountant');
  u_lecteur := _role220(t, 'lecteur-r17@perm.test', 'viewer');
  u_revoque := _role220(t, 'revoque-r17@perm.test', 'admin', 'revoked');

  -- P01 — administrateur
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', u_admin::text, true);
    PERFORM _as_user();
    faux := has_permission('payroll.post') AND has_permission('payroll.pay');
    la := _lot220(t, 'PR-P01');
    res := post_payroll_journal(la);
    PERFORM _rec('P01', 'administrateur : payroll.post et payroll.pay, et l''écriture de paie est générée',
      faux AND res->>'success' = 'true' AND (res->>'entry_id') IS NOT NULL,
      format('droits=%s, écriture=%s', faux, COALESCE(res->>'entry_id', '∅')));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('P01', 'administrateur : payroll.post et payroll.pay, et l''écriture de paie est générée', false, SQLERRM); END;

  -- P02 — comptable : c'est son métier (socle ajouté par la 220)
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', u_compta::text, true);
    faux := has_permission('payroll.post') AND has_permission('payroll.pay');
    lb := _lot220(t, 'PR-P02');
    res := post_payroll_journal(lb);
    PERFORM _rec('P02', 'comptable : payroll.post et payroll.pay (socle), écriture générée',
      faux AND res->>'success' = 'true',
      format('droits=%s, écriture=%s', faux, COALESCE(res->>'entry_id', '∅')));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('P02', 'comptable : payroll.post et payroll.pay (socle), écriture générée', false, SQLERRM); END;

  -- P03 — lecteur : refus explicite sur les deux portes
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', u_lecteur::text, true);
    faux := has_permission('payroll.post') OR has_permission('payroll.pay');
    msg := '';
    BEGIN PERFORM post_payroll_journal(la); EXCEPTION WHEN OTHERS THEN msg := msg || ' journal:' || SQLERRM; END;
    BEGIN PERFORM post_payroll_payment(la); EXCEPTION WHEN OTHERS THEN msg := msg || ' paiement:' || SQLERRM; END;
    PERFORM _rec('P03', 'lecteur : refus explicite sur les deux RPC (aucun droit de paie)',
      NOT faux AND msg LIKE '%payroll.post%' AND msg LIKE '%payroll.pay%',
      trim(msg));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('P03', 'lecteur : refus explicite sur les deux RPC (aucun droit de paie)', false, SQLERRM); END;

  -- P04 — administrateur révoqué
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', u_revoque::text, true);
    faux := has_permission('payroll.post');
    msg := '';
    BEGIN PERFORM post_payroll_journal(la); EXCEPTION WHEN OTHERS THEN msg := SQLERRM; END;
    PERFORM _rec('P04', 'administrateur révoqué : aucun droit, et la RPC refuse',
      NOT faux AND msg LIKE '%payroll.post%', format('droit=%s, refus=%s', faux, msg));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('P04', 'administrateur révoqué : aucun droit, et la RPC refuse', false, SQLERRM); END;

  -- P05 — le corps renommé n'est plus exposé : la garde n'est pas contournable
  BEGIN
    PERFORM _rec('P05', 'le corps renommé (payroll_payment_inner) n''est plus exécutable par l''application',
      NOT has_function_privilege('authenticated', 'public.payroll_payment_inner(uuid, uuid, date, text)', 'EXECUTE')
        AND NOT has_function_privilege('anon', 'public.payroll_payment_inner(uuid, uuid, date, text)', 'EXECUTE')
        AND has_function_privilege('authenticated', 'public.post_payroll_payment(uuid, uuid, date, text)', 'EXECUTE'),
      'inner révoqué, porte gardée conservée');
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('P05', 'le corps renommé (payroll_payment_inner) n''est plus exécutable par l''application', false, SQLERRM); END;

  PERFORM set_config('request.jwt.claim.sub', '', false);
END $$;

DROP FUNCTION _role220(uuid, text, text, text);
DROP FUNCTION _lot220(uuid, text);

SELECT _audit_assert('220');