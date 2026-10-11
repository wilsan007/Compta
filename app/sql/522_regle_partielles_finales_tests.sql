-- ============================================================
-- 522_regle_partielles_finales_tests.sql — partie B, R-020, R-029, R-032, R-043
--
--   T01  facture transformée → `invoices.transformed` (R-020) ;
--   T02  note de frais soumise → `expense_reports.submitted` (R-029) ;
--   T03  note de frais remboursée → `expense_reports.reimbursed` (R-032) ;
--   T04  OF annulé → `manufacturing_orders.cancelled` (R-043).
-- \ir ci/audit_helpers.sql.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '522', false);
DELETE FROM _audit_results WHERE file = '522';

CREATE OR REPLACE FUNCTION _b522(p_nom text, OUT t uuid, OUT inv uuid, OUT er uuid, OUT mo uuid)
LANGUAGE plpgsql AS $$
DECLARE c uuid; e uuid; p uuid;
BEGIN
  t := _mk_tenant(p_nom);
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client ' || p_nom) RETURNING id INTO c;
  INSERT INTO employees (tenant_id, name) VALUES (t, 'Salarié ' || p_nom) RETURNING id INTO e;
  INSERT INTO products (tenant_id, name, sku, type) VALUES (t, 'Art ' || p_nom, 'A-' || p_nom, 'service') RETURNING id INTO p;
  INSERT INTO invoices (tenant_id, customer_id, date, due_date, status, validation_status)
    VALUES (t, c, '2026-03-01', '2026-04-01', 'draft', 'draft') RETURNING id INTO inv;
  INSERT INTO invoice_lines (tenant_id, invoice_id, product_id, description, quantity, unit_price, vat_rate, line_order)
    VALUES (t, inv, p, 'Prestation ' || p_nom, 1, 100, 20, 0);
  INSERT INTO expense_reports (tenant_id, employee_id, number, period, total_amount, total_vat, status)
    VALUES (t, e, 'NF-' || p_nom, '2026-03', 100, 20, 'draft') RETURNING id INTO er;
  INSERT INTO manufacturing_orders (tenant_id, number, product_id, quantity, status)
    VALUES (t, 'OF-' || p_nom, p, 5, 'planned') RETURNING id INTO mo;
END $$;

DO $$
DECLARE x record; refuse boolean := false;
BEGIN
  x := _b522('T01');
  PERFORM _as_user();
  UPDATE invoices SET validation_status = 'validated' WHERE id = x.inv;
  BEGIN
    UPDATE invoices SET validation_status = 'transformed' WHERE id = x.inv;
  EXCEPTION WHEN check_violation THEN refuse := true;
  END;
  PERFORM _rec('T01', 'R-020 : sortir de « validated » est REFUSÉ (transformed inatteignable)',
    refuse, format('refus=%s (true attendu)', refuse));
END $$;

DO $$
DECLARE x record; ne int;
BEGIN
  x := _b522('T02');
  PERFORM _as_user();
  UPDATE expense_reports SET status = 'submitted' WHERE id = x.er;
  SELECT count(*) INTO ne FROM domain_events de
  WHERE de.tenant_id = x.t AND de.event_name = 'expense_reports.submitted' AND de.aggregate_id = x.er;
  PERFORM _rec('T02', 'une note de frais soumise émet expense_reports.submitted (R-029)',
    ne = 1, format('événements=%s (1 attendu)', ne));
END $$;

DO $$
DECLARE x record; ne int;
BEGIN
  x := _b522('T03');
  PERFORM _as_user();
  UPDATE expense_reports SET status = 'reimbursed' WHERE id = x.er;
  SELECT count(*) INTO ne FROM domain_events de
  WHERE de.tenant_id = x.t AND de.event_name = 'expense_reports.reimbursed' AND de.aggregate_id = x.er;
  PERFORM _rec('T03', 'une note de frais remboursée émet expense_reports.reimbursed (R-032)',
    ne = 1, format('événements=%s (1 attendu)', ne));
END $$;

DO $$
DECLARE x record; ne int;
BEGIN
  x := _b522('T04');
  PERFORM _as_user();
  UPDATE manufacturing_orders SET status = 'cancelled' WHERE id = x.mo;
  SELECT count(*) INTO ne FROM domain_events de
  WHERE de.tenant_id = x.t AND de.event_name = 'manufacturing_orders.cancelled' AND de.aggregate_id = x.mo;
  PERFORM _rec('T04', 'un OF annulé émet manufacturing_orders.cancelled (R-043)',
    ne = 1, format('événements=%s (1 attendu)', ne));
END $$;

SELECT _audit_assert('522');