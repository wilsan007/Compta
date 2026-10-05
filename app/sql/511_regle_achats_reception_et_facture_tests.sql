-- ============================================================
-- 511_regle_achats_reception_et_facture_tests.sql — partie B, lot Achats, R-013, R-015, R-016
--
-- Ce que les règles garantissent (doc/audit/plan6/B1-INVENTAIRE-62-REGLES-2026-10-05.md) :
--   T01  une réception passée à `partial` émet `goods_receipts.partial` (reliquat 4) ;
--   T02  une réception passée à `pending` émet `goods_receipts.pending` ;
--   T03  une facture fournisseur annulée émet `purchase_invoices.cancelled`.
--
-- \ir ci/audit_helpers.sql.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '511', false);
DELETE FROM _audit_results WHERE file = '511';

-- Société isolée : commande (10), réception en attente (6 reçus), facture brouillon.
CREATE OR REPLACE FUNCTION _b511(p_nom text, OUT t uuid, OUT gr uuid, OUT pi uuid)
LANGUAGE plpgsql AS $$
DECLARE s uuid; p uuid; po uuid;
BEGIN
  t := _mk_tenant(p_nom);
  INSERT INTO suppliers (tenant_id, name) VALUES (t, 'Fourn ' || p_nom) RETURNING id INTO s;
  INSERT INTO products (tenant_id, name, sku, type) VALUES (t, 'Art ' || p_nom, 'A-' || p_nom, 'stock') RETURNING id INTO p;
  INSERT INTO purchase_orders (tenant_id, number, supplier_id, order_date, status)
    VALUES (t, 'CMD-' || p_nom, s, '2026-03-01', 'draft') RETURNING id INTO po;
  INSERT INTO purchase_order_lines (tenant_id, purchase_order_id, product_id, description, quantity, unit_price)
    VALUES (t, po, p, 'Ligne ' || p_nom, 10, 100);
  INSERT INTO goods_receipts (tenant_id, number, purchase_order_id, receipt_date, status)
    VALUES (t, 'BR-' || p_nom, po, '2026-03-05', 'pending') RETURNING id INTO gr;
  INSERT INTO goods_receipt_lines (tenant_id, goods_receipt_id, product_id, description, quantity_received)
    VALUES (t, gr, p, 'Ligne ' || p_nom, 6);
  INSERT INTO purchase_invoices (tenant_id, number, supplier_id, supplier_name, date, due_date,
                                 status, subtotal, vat_total, total, amount_paid, amount_due, approval_status)
    VALUES (t, 'ACH-' || p_nom, s, 'Fourn ' || p_nom, '2026-03-05', '2026-04-05',
            'draft', 1000, 200, 1200, 0, 1200, 'pending') RETURNING id INTO pi;
END $$;

-- ── T01 : réception partielle ───────────────────────────────────
DO $$
DECLARE x record; ne int; rel numeric;
BEGIN
  x := _b511('T01');
  PERFORM _as_user();
  UPDATE goods_receipts SET status = 'partial' WHERE id = x.gr;
  SELECT count(*), max((de.payload->>'reliquat')::numeric) INTO ne, rel FROM domain_events de
  WHERE de.tenant_id = x.t AND de.event_name = 'goods_receipts.partial' AND de.aggregate_id = x.gr;
  PERFORM _rec('T01', 'une réception partielle émet goods_receipts.partial (reliquat 4)',
    ne = 1 AND rel = 4, format('événements=%s reliquat=%s (1 / 4 attendus)', ne, rel));
END $$;

-- ── T02 : réception en attente ──────────────────────────────────
DO $$
DECLARE x record; ne int;
BEGIN
  x := _b511('T02');
  PERFORM _as_user();
  UPDATE goods_receipts SET status = 'received' WHERE id = x.gr;
  UPDATE goods_receipts SET status = 'pending'  WHERE id = x.gr;
  SELECT count(*) INTO ne FROM domain_events de
  WHERE de.tenant_id = x.t AND de.event_name = 'goods_receipts.pending' AND de.aggregate_id = x.gr;
  PERFORM _rec('T02', 'une réception en attente émet goods_receipts.pending',
    ne = 1, format('événements=%s (1 attendu)', ne));
END $$;

-- ── T03 : facture fournisseur annulée ───────────────────────────
DO $$
DECLARE x record; ne int;
BEGIN
  x := _b511('T03');
  PERFORM _as_user();
  UPDATE purchase_invoices SET status = 'cancelled' WHERE id = x.pi;
  SELECT count(*) INTO ne FROM domain_events de
  WHERE de.tenant_id = x.t AND de.event_name = 'purchase_invoices.cancelled' AND de.aggregate_id = x.pi;
  PERFORM _rec('T03', 'une facture fournisseur annulée émet purchase_invoices.cancelled',
    ne = 1, format('événements=%s (1 attendu)', ne));
END $$;

SELECT _audit_assert('511');