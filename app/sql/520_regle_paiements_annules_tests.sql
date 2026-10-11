-- ============================================================
-- 520_regle_paiements_annules_tests.sql — partie B, lot Trésorerie, R-023, R-024
--
--   T01  règlement CLIENT annulé → `customer_payments.cancelled` (R-023) ;
--   T02  règlement FOURNISSEUR annulé → `supplier_payments.cancelled` (R-024).
-- \ir ci/audit_helpers.sql.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '520', false);
DELETE FROM _audit_results WHERE file = '520';

CREATE OR REPLACE FUNCTION _b520(p_nom text, OUT t uuid, OUT cp uuid, OUT sp uuid)
LANGUAGE plpgsql AS $$
DECLARE c uuid; s uuid;
BEGIN
  t := _mk_tenant(p_nom);
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client ' || p_nom) RETURNING id INTO c;
  INSERT INTO suppliers (tenant_id, name) VALUES (t, 'Fourn ' || p_nom) RETURNING id INTO s;
  INSERT INTO customer_payments (tenant_id, number, customer_id, amount, status)
    VALUES (t, 'RC-' || p_nom, c, 300, 'recorded') RETURNING id INTO cp;
  INSERT INTO supplier_payments (tenant_id, number, supplier_id, amount, status)
    VALUES (t, 'RF-' || p_nom, s, 200, 'recorded') RETURNING id INTO sp;
END $$;

DO $$
DECLARE x record; ne int; nt int;
BEGIN
  x := _b520('T01');
  PERFORM _as_user();
  UPDATE customer_payments SET status = 'cancelled' WHERE id = x.cp;
  SELECT count(*) INTO ne FROM domain_events de
  WHERE de.tenant_id = x.t AND de.event_name = 'customer_payments.cancelled' AND de.aggregate_id = x.cp;
  SELECT count(*) INTO nt FROM chain_traces ct
  WHERE ct.tenant_id = x.t AND ct.effet = 'sale.payment.cancelled' AND ct.amont_id = x.cp AND ct.resultat = 'applique';
  PERFORM _rec('T01', 'un règlement client annulé émet customer_payments.cancelled + trace (R-023)',
    ne = 1 AND nt = 1, format('événements=%s trace=%s (1 / 1 attendus)', ne, nt));
END $$;

DO $$
DECLARE x record; ne int;
BEGIN
  x := _b520('T02');
  PERFORM _as_user();
  UPDATE supplier_payments SET status = 'cancelled' WHERE id = x.sp;
  SELECT count(*) INTO ne FROM domain_events de
  WHERE de.tenant_id = x.t AND de.event_name = 'supplier_payments.cancelled' AND de.aggregate_id = x.sp;
  PERFORM _rec('T02', 'un règlement fournisseur annulé émet supplier_payments.cancelled (R-024)',
    ne = 1, format('événements=%s (1 attendu)', ne));
END $$;

SELECT _audit_assert('520');