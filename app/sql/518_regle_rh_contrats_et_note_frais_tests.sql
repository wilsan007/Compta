-- ============================================================
-- 518_regle_rh_contrats_et_note_frais_tests.sql — partie B, lot Paie/RH
--
--   T01  note de frais REJETÉE → `expense_reports.rejected` (R-031) ;
--   T02  contrat CRÉÉ → `contracts.created` avec son type (R-039, accroche) ;
--   T03  contrat RUPTURÉ (terminated) → `contracts.terminated` (R-037) ;
--   T04  contrat SUSPENDU → `contracts.suspended` (R-038).
-- \ir ci/audit_helpers.sql.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '518', false);
DELETE FROM _audit_results WHERE file = '518';

CREATE OR REPLACE FUNCTION _b518(p_nom text, OUT t uuid, OUT e uuid, OUT er uuid, OUT ct uuid)
LANGUAGE plpgsql AS $$
BEGIN
  t := _mk_tenant(p_nom);
  INSERT INTO employees (tenant_id, name) VALUES (t, 'Salarié ' || p_nom) RETURNING id INTO e;
  INSERT INTO expense_reports (tenant_id, employee_id, number, period, total_amount, total_vat, status)
    VALUES (t, e, 'NF-' || p_nom, '2026-03', 120, 20, 'submitted') RETURNING id INTO er;
  INSERT INTO contracts (tenant_id, number, employee_id, contract_type, start_date, status)
    VALUES (t, 'CT-' || p_nom, e, 'cdi', '2026-01-01', 'active') RETURNING id INTO ct;
END $$;

DO $$
DECLARE x record; ne int;
BEGIN
  x := _b518('T01');
  PERFORM _as_user();
  UPDATE expense_reports SET status = 'rejected' WHERE id = x.er;
  SELECT count(*) INTO ne FROM domain_events de
  WHERE de.tenant_id = x.t AND de.event_name = 'expense_reports.rejected' AND de.aggregate_id = x.er;
  PERFORM _rec('T01', 'une note de frais rejetée émet expense_reports.rejected (R-031)',
    ne = 1, format('événements=%s (1 attendu)', ne));
END $$;

DO $$
DECLARE tt uuid; ne int; typ text;
BEGIN
  tt := _mk_tenant('T02');
  PERFORM _as_user();
  INSERT INTO employees (tenant_id, name) VALUES (tt, 'Salarié T02');
  INSERT INTO contracts (tenant_id, number, employee_id, contract_type, start_date, status)
    SELECT tt, 'CT-T02', id, 'cdd', '2026-02-01', 'active' FROM employees WHERE tenant_id = tt LIMIT 1;
  SELECT count(*), max(de.payload->>'contract_type') INTO ne, typ FROM domain_events de
  WHERE de.tenant_id = tt AND de.event_name = 'contracts.created';
  PERFORM _rec('T02', 'un contrat créé émet contracts.created avec son type (R-039)',
    ne = 1 AND typ = 'cdd', format('événements=%s type=%s (1 / cdd attendus)', ne, typ));
END $$;

DO $$
DECLARE x record; ne int;
BEGIN
  x := _b518('T03');
  PERFORM _as_user();
  UPDATE contracts SET status = 'terminated' WHERE id = x.ct;
  SELECT count(*) INTO ne FROM domain_events de
  WHERE de.tenant_id = x.t AND de.event_name = 'contracts.terminated' AND de.aggregate_id = x.ct;
  PERFORM _rec('T03', 'un contrat rompu émet contracts.terminated (R-037)',
    ne = 1, format('événements=%s (1 attendu)', ne));
END $$;

DO $$
DECLARE x record; ne int;
BEGIN
  x := _b518('T04');
  PERFORM _as_user();
  UPDATE contracts SET status = 'suspended' WHERE id = x.ct;
  SELECT count(*) INTO ne FROM domain_events de
  WHERE de.tenant_id = x.t AND de.event_name = 'contracts.suspended' AND de.aggregate_id = x.ct;
  PERFORM _rec('T04', 'un contrat suspendu émet contracts.suspended (R-038)',
    ne = 1, format('événements=%s (1 attendu)', ne));
END $$;

SELECT _audit_assert('518');