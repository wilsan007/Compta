-- ============================================================
-- 516_regle_conformite_tva_retour_tests.sql — partie B, lot Conformité, R-052, R-053
--
--   T01  une déclaration de TVA SOUMISE émet `vat_returns.submitted` ;
--   T02  une déclaration de TVA PAYÉE émet `vat_returns.paid` ;
--   T03  IDEMPOTENCE — un rejeu n'émet pas un second événement.
-- \ir ci/audit_helpers.sql.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '516', false);
DELETE FROM _audit_results WHERE file = '516';

CREATE OR REPLACE FUNCTION _b516(p_nom text, OUT t uuid, OUT v uuid)
LANGUAGE plpgsql AS $$
BEGIN
  t := _mk_tenant(p_nom);
  INSERT INTO vat_returns (tenant_id, period_start, period_end, status)
    VALUES (t, '2026-01-01', '2026-03-31', 'draft') RETURNING id INTO v;
END $$;

DO $$
DECLARE x record; ne int;
BEGIN
  x := _b516('T01');
  PERFORM _as_user();
  UPDATE vat_returns SET status = 'submitted' WHERE id = x.v;
  SELECT count(*) INTO ne FROM domain_events de
  WHERE de.tenant_id = x.t AND de.event_name = 'vat_returns.submitted' AND de.aggregate_id = x.v;
  PERFORM _rec('T01', 'une déclaration de TVA soumise émet vat_returns.submitted',
    ne = 1, format('événements=%s (1 attendu)', ne));
END $$;

DO $$
DECLARE x record; ne int; nt int;
BEGIN
  x := _b516('T02');
  PERFORM _as_user();
  UPDATE vat_returns SET status = 'paid' WHERE id = x.v;
  SELECT count(*) INTO ne FROM domain_events de
  WHERE de.tenant_id = x.t AND de.event_name = 'vat_returns.paid' AND de.aggregate_id = x.v;
  SELECT count(*) INTO nt FROM chain_traces ct
  WHERE ct.tenant_id = x.t AND ct.effet = 'tax.vat_return.paid' AND ct.amont_id = x.v AND ct.resultat = 'applique';
  PERFORM _rec('T02', 'une déclaration de TVA payée émet vat_returns.paid + trace',
    ne = 1 AND nt = 1, format('événements=%s trace=%s (1 / 1 attendus)', ne, nt));
END $$;

DO $$
DECLARE x record; ne int;
BEGIN
  x := _b516('T03');
  PERFORM _as_user();
  UPDATE vat_returns SET status = 'submitted' WHERE id = x.v;
  UPDATE vat_returns SET status = 'draft'     WHERE id = x.v;
  UPDATE vat_returns SET status = 'submitted' WHERE id = x.v;
  SELECT count(*) INTO ne FROM domain_events de
  WHERE de.tenant_id = x.t AND de.event_name = 'vat_returns.submitted' AND de.aggregate_id = x.v;
  PERFORM _rec('T03', 'un rejeu de « soumise » n''émet pas un second événement',
    ne = 1, format('événements=%s (1 attendu)', ne));
END $$;

SELECT _audit_assert('516');