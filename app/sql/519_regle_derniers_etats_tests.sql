-- ============================================================
-- 519_regle_derniers_etats_tests.sql — partie B, R-019, R-044, R-045, R-047
--
--   T01  facture client ANNULÉE → `invoices.cancelled` (R-019) ;
--   T02  OF planifié → `manufacturing_orders.planned` (R-045) ;
--   T03  OF en cours → `manufacturing_orders.in_progress` (R-044) ;
--   T04  transfert de stock → `stock_movements.transfer` (R-047).
-- \ir ci/audit_helpers.sql.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '519', false);
DELETE FROM _audit_results WHERE file = '519';

CREATE OR REPLACE FUNCTION _b519(p_nom text, OUT t uuid, OUT inv uuid, OUT mo uuid, OUT p uuid, OUT wh uuid)
LANGUAGE plpgsql AS $$
DECLARE c uuid;
BEGIN
  t := _mk_tenant(p_nom);
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client ' || p_nom) RETURNING id INTO c;
  INSERT INTO products (tenant_id, name, sku, type) VALUES (t, 'Art ' || p_nom, 'A-' || p_nom, 'stock') RETURNING id INTO p;
  INSERT INTO warehouses (tenant_id, code, name) VALUES (t, 'W-' || p_nom, 'Dépôt') RETURNING id INTO wh;
  INSERT INTO invoices (tenant_id, customer_id, date, due_date, status)
    VALUES (t, c, '2026-03-01', '2026-04-01', 'draft') RETURNING id INTO inv;
  INSERT INTO manufacturing_orders (tenant_id, number, product_id, quantity, status)
    VALUES (t, 'OF-' || p_nom, p, 5, 'in_progress') RETURNING id INTO mo;
END $$;

DO $$
DECLARE x record; ne int; nt int;
BEGIN
  x := _b519('T01');
  PERFORM _as_user();
  UPDATE invoices SET status = 'cancelled' WHERE id = x.inv;
  SELECT count(*) INTO ne FROM domain_events de
  WHERE de.tenant_id = x.t AND de.event_name = 'invoices.cancelled' AND de.aggregate_id = x.inv;
  SELECT count(*) INTO nt FROM chain_traces ct
  WHERE ct.tenant_id = x.t AND ct.effet = 'sale.invoice.cancelled' AND ct.amont_id = x.inv AND ct.resultat = 'applique';
  PERFORM _rec('T01', 'une facture client annulée émet invoices.cancelled + trace (R-019)',
    ne = 1 AND nt = 1, format('événements=%s trace=%s (1 / 1 attendus)', ne, nt));
END $$;

DO $$
DECLARE x record; ne int;
BEGIN
  x := _b519('T02');
  PERFORM _as_user();
  UPDATE manufacturing_orders SET status = 'planned' WHERE id = x.mo;
  SELECT count(*) INTO ne FROM domain_events de
  WHERE de.tenant_id = x.t AND de.event_name = 'manufacturing_orders.planned' AND de.aggregate_id = x.mo;
  PERFORM _rec('T02', 'un OF planifié émet manufacturing_orders.planned (R-045)',
    ne = 1, format('événements=%s (1 attendu)', ne));
END $$;

DO $$
DECLARE x record; ne int;
BEGIN
  x := _b519('T03');
  PERFORM _as_user();
  UPDATE manufacturing_orders SET status = 'planned'     WHERE id = x.mo;
  UPDATE manufacturing_orders SET status = 'in_progress' WHERE id = x.mo;
  SELECT count(*) INTO ne FROM domain_events de
  WHERE de.tenant_id = x.t AND de.event_name = 'manufacturing_orders.in_progress' AND de.aggregate_id = x.mo;
  PERFORM _rec('T03', 'un OF en cours émet manufacturing_orders.in_progress (R-044)',
    ne = 1, format('événements=%s (1 attendu)', ne));
END $$;

DO $$
DECLARE x record; m uuid; ne int;
BEGIN
  x := _b519('T04');
  PERFORM _as_user();
  INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, movement_type, type, quantity, reference, movement_date, date)
    VALUES (x.t, x.p, x.wh, 'transfer', 'transfer', 3, 'TRF-T04', CURRENT_DATE, CURRENT_DATE) RETURNING id INTO m;
  SELECT count(*) INTO ne FROM domain_events de
  WHERE de.tenant_id = x.t AND de.event_name = 'stock_movements.transfer' AND de.aggregate_id = m;
  PERFORM _rec('T04', 'un mouvement de transfert émet stock_movements.transfer (R-047)',
    ne = 1, format('événements=%s (1 attendu)', ne));
END $$;

SELECT _audit_assert('519');