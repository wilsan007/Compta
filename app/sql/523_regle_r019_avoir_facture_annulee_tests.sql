-- ============================================================
-- 523_regle_r019_avoir_facture_annulee_tests.sql — partie B, lot Ventes, R-019
--
--   T01  annuler une facture CRÉE un avoir lié + ANNULE les relances ouvertes ;
--   T02  IDEMPOTENCE — une seconde annulation ne crée pas un second avoir.
-- \ir ci/audit_helpers.sql.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '523', false);
DELETE FROM _audit_results WHERE file = '523';

CREATE OR REPLACE FUNCTION _b523(p_nom text, OUT t uuid, OUT inv uuid, OUT rem uuid)
LANGUAGE plpgsql AS $$
DECLARE c uuid; p uuid;
BEGIN
  t := _mk_tenant(p_nom);
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client ' || p_nom) RETURNING id INTO c;
  INSERT INTO products (tenant_id, name, sku, type) VALUES (t, 'Art ' || p_nom, 'A-' || p_nom, 'service') RETURNING id INTO p;
  INSERT INTO invoices (tenant_id, customer_id, date, due_date, status, validation_status)
    VALUES (t, c, '2026-03-01', '2026-04-01', 'draft', 'draft') RETURNING id INTO inv;
  INSERT INTO invoice_lines (tenant_id, invoice_id, product_id, description, quantity, unit_price, vat_rate, line_order)
    VALUES (t, inv, p, 'Prestation ' || p_nom, 1, 100, 20, 0);
  INSERT INTO collection_reminders (tenant_id, number, customer_id, invoice_id, reminder_level, reminder_date, amount, status)
    VALUES (t, 'REL-' || p_nom, c, inv, 1, '2026-03-15', 120, 'sent') RETURNING id INTO rem;
END $$;

DO $$
DECLARE x record; n_cn int; n_lig int; nl int; ne int; st text;
BEGIN
  x := _b523('T01');
  PERFORM _as_user();
  UPDATE invoices SET status = 'cancelled' WHERE id = x.inv;

  SELECT count(*), min(status) INTO n_cn, st FROM credit_notes cn
  WHERE cn.tenant_id = x.t AND cn.invoice_id = x.inv;
  PERFORM _rec('T01a', 'annuler une facture crée UN avoir en brouillon',
    n_cn = 1 AND st = 'draft', format('avoirs=%s statut=%s (1 / draft attendus)', n_cn, st));

  SELECT count(*) INTO n_lig FROM credit_note_lines cl
  JOIN credit_notes cn ON cn.id = cl.credit_note_id AND cn.tenant_id = cl.tenant_id
  WHERE cn.tenant_id = x.t AND cn.invoice_id = x.inv;
  PERFORM _rec('T01b', 'l''avoir reprend les lignes de la facture (1)', n_lig = 1, format('lignes=%s (1 attendue)', n_lig));

  SELECT count(*) INTO nl FROM document_links dl
  WHERE dl.tenant_id = x.t AND dl.amont_type = 'invoices' AND dl.amont_id = x.inv
    AND dl.aval_type = 'credit_notes' AND dl.effet = 'sale.credit_note.from_invoice' AND dl.link_type = 'reversed_by';
  PERFORM _rec('T01c', 'l''avoir est LIÉ à la facture (reversed_by)', nl = 1, format('liens=%s (1 attendu)', nl));

  PERFORM _rec('T01d', 'les relances ouvertes de la facture sont ANNULÉES',
    (SELECT status = 'cancelled' FROM collection_reminders WHERE id = x.rem),
    (SELECT format('relance=%s', status) FROM collection_reminders WHERE id = x.rem));

  SELECT count(*) INTO ne FROM domain_events de
  WHERE de.tenant_id = x.t AND de.event_name = 'credit_notes.created_from_invoice' AND de.aggregate_id = x.inv;
  PERFORM _rec('T01e', 'un événement credit_notes.created_from_invoice est émis', ne = 1, format('événements=%s (1 attendu)', ne));
END $$;

DO $$
DECLARE x record; n_cn int;
BEGIN
  x := _b523('T02');
  PERFORM _as_user();
  UPDATE invoices SET status = 'cancelled' WHERE id = x.inv;
  UPDATE invoices SET status = 'draft'     WHERE id = x.inv;
  UPDATE invoices SET status = 'cancelled' WHERE id = x.inv;
  SELECT count(*) INTO n_cn FROM credit_notes cn WHERE cn.tenant_id = x.t AND cn.invoice_id = x.inv;
  PERFORM _rec('T02', 'une seconde annulation ne crée pas un second avoir',
    n_cn = 1, format('avoirs=%s (1 attendu)', n_cn));
END $$;

SELECT _audit_assert('523');