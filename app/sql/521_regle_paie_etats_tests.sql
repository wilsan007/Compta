-- ============================================================
-- 521_regle_paie_etats_tests.sql — partie B, lot Paie/RH, R-025, R-026, R-028
--
--   T01  lot de paie APPROUVÉ → `pay_runs.approved` (R-025) ;
--   T02  bulletin APPROUVÉ → `pay_slips.approved` (R-026) ;
--   T03  bulletin PAYÉ → `pay_slips.paid` (R-028).
-- \ir ci/audit_helpers.sql.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '521', false);
DELETE FROM _audit_results WHERE file = '521';

CREATE OR REPLACE FUNCTION _b521(p_nom text, OUT t uuid, OUT run uuid, OUT slip uuid)
LANGUAGE plpgsql AS $$
DECLARE e uuid;
BEGIN
  t := _mk_tenant(p_nom);
  INSERT INTO employees (tenant_id, name) VALUES (t, 'Salarié ' || p_nom) RETURNING id INTO e;
  INSERT INTO pay_runs (tenant_id, number, period_start, period_end, pay_date, status)
    VALUES (t, 'PR-' || p_nom, '2026-03-01', '2026-03-31', '2026-03-31', 'draft') RETURNING id INTO run;
  INSERT INTO pay_slips (tenant_id, number, employee_id, pay_run_id, period_start, period_end, status)
    VALUES (t, 'BS-' || p_nom, e, run, '2026-03-01', '2026-03-31', 'draft') RETURNING id INTO slip;
END $$;

DO $$
DECLARE x record; ne int;
BEGIN
  x := _b521('T01');
  PERFORM _as_user();
  UPDATE pay_runs SET status = 'approved' WHERE id = x.run;
  SELECT count(*) INTO ne FROM domain_events de
  WHERE de.tenant_id = x.t AND de.event_name = 'pay_runs.approved' AND de.aggregate_id = x.run;
  PERFORM _rec('T01', 'un lot de paie approuvé émet pay_runs.approved (R-025)',
    ne = 1, format('événements=%s (1 attendu)', ne));
END $$;

DO $$
DECLARE x record; ne int;
BEGIN
  x := _b521('T02');
  PERFORM _as_user();
  UPDATE pay_slips SET status = 'approved' WHERE id = x.slip;
  SELECT count(*) INTO ne FROM domain_events de
  WHERE de.tenant_id = x.t AND de.event_name = 'pay_slips.approved' AND de.aggregate_id = x.slip;
  PERFORM _rec('T02', 'un bulletin approuvé émet pay_slips.approved (R-026)',
    ne = 1, format('événements=%s (1 attendu)', ne));
END $$;

DO $$
DECLARE x record; ne int; nt int;
BEGIN
  x := _b521('T03');
  PERFORM _as_user();
  UPDATE pay_slips SET status = 'approved' WHERE id = x.slip;
  UPDATE pay_slips SET status = 'paid'     WHERE id = x.slip;
  SELECT count(*) INTO ne FROM domain_events de
  WHERE de.tenant_id = x.t AND de.event_name = 'pay_slips.paid' AND de.aggregate_id = x.slip;
  SELECT count(*) INTO nt FROM chain_traces ct
  WHERE ct.tenant_id = x.t AND ct.effet = 'payroll.slip.paid' AND ct.amont_id = x.slip AND ct.resultat = 'applique';
  PERFORM _rec('T03', 'un bulletin payé émet pay_slips.paid + trace (R-028)',
    ne = 1 AND nt = 1, format('événements=%s trace=%s (1 / 1 attendus)', ne, nt));
END $$;

SELECT _audit_assert('521');