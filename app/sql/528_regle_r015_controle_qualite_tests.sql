-- ============================================================
-- 528_regle_r015_controle_qualite_tests.sql — partie B, lot Achats, R-015
--
--   T01  contrôle qualité PASSÉ → l'entrée en stock passe ;
--   T02  contrôle qualité EN ATTENTE → l'entrée en stock est REFUSÉE ;
--   T03  AUCUN contrôle → l'entrée passe (non-régression).
-- \ir ci/audit_helpers.sql.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '528', false);
DELETE FROM _audit_results WHERE file = '528';

-- p_qc : 'passed', 'pending' ou NULL (aucun contrôle).
CREATE OR REPLACE FUNCTION _b528(p_nom text, p_qc text, OUT t uuid, OUT gr uuid)
LANGUAGE plpgsql AS $$
DECLARE wh uuid; p uuid; po uuid;
BEGIN
  t := _mk_tenant(p_nom);
  INSERT INTO warehouses (tenant_id, code, name) VALUES (t, 'W-' || p_nom, 'Dépôt') RETURNING id INTO wh;
  INSERT INTO products (tenant_id, name, sku, type) VALUES (t, 'Art ' || p_nom, 'A-' || p_nom, 'stock') RETURNING id INTO p;
  INSERT INTO purchase_orders (tenant_id, number, order_date, status) VALUES (t, 'CMD-' || p_nom, '2026-03-01', 'draft') RETURNING id INTO po;
  INSERT INTO purchase_order_lines (tenant_id, purchase_order_id, product_id, description, quantity, unit_price)
    VALUES (t, po, p, 'Ligne ' || p_nom, 5, 10);
  INSERT INTO goods_receipts (tenant_id, number, purchase_order_id, warehouse_id, receipt_date, status)
    VALUES (t, 'BR-' || p_nom, po, wh, '2026-03-05', 'pending') RETURNING id INTO gr;
  INSERT INTO goods_receipt_lines (tenant_id, goods_receipt_id, product_id, description, quantity_received)
    VALUES (t, gr, p, 'Ligne ' || p_nom, 5);
  IF p_qc IS NOT NULL THEN
    INSERT INTO quality_checks (tenant_id, product_id, reference_type, reference_id, status)
      VALUES (t, p, 'goods_receipt', gr, p_qc);
  END IF;
END $$;

DO $$
DECLARE x record; st text;
BEGIN
  x := _b528('T01', 'passed');
  PERFORM _as_user();
  UPDATE goods_receipts SET status = 'received' WHERE id = x.gr;
  SELECT status INTO st FROM goods_receipts WHERE id = x.gr;
  PERFORM _rec('T01', 'un contrôle qualité PASSÉ laisse entrer le stock', st = 'received', format('statut=%s (received attendu)', st));
END $$;

DO $$
DECLARE x record; refuse boolean := false;
BEGIN
  x := _b528('T02', 'pending');
  PERFORM _as_user();
  BEGIN
    UPDATE goods_receipts SET status = 'received' WHERE id = x.gr;
  EXCEPTION WHEN check_violation THEN refuse := true;
  END;
  PERFORM _rec('T02', 'un contrôle qualité EN ATTENTE REFUSE l''entrée en stock',
    refuse, format('refus=%s (true attendu)', refuse));
END $$;

DO $$
DECLARE x record; st text;
BEGIN
  x := _b528('T03', NULL);
  PERFORM _as_user();
  UPDATE goods_receipts SET status = 'received' WHERE id = x.gr;
  SELECT status INTO st FROM goods_receipts WHERE id = x.gr;
  PERFORM _rec('T03', 'sans contrôle qualité, l''entrée passe (non-régression)', st = 'received', format('statut=%s (received attendu)', st));
END $$;

SELECT _audit_assert('528');