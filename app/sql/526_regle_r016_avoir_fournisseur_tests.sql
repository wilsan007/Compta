-- ============================================================
-- 526_regle_r016_avoir_fournisseur_tests.sql — partie B, lot Achats, R-016
--
--   T01  annuler une facture fournisseur CRÉE un avoir fournisseur lié (reversed_by) ;
--   T02  IDEMPOTENCE — une seconde annulation ne crée pas un second avoir.
-- \ir ci/audit_helpers.sql.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '526', false);
DELETE FROM _audit_results WHERE file = '526';

CREATE OR REPLACE FUNCTION _b526(p_nom text, OUT t uuid, OUT pi uuid)
LANGUAGE plpgsql AS $$
DECLARE s uuid;
BEGIN
  t := _mk_tenant(p_nom);
  INSERT INTO suppliers (tenant_id, name) VALUES (t, 'Fourn ' || p_nom) RETURNING id INTO s;
  INSERT INTO purchase_invoices (tenant_id, number, supplier_id, supplier_name, date, due_date,
                                 status, subtotal, vat_total, total, amount_paid, amount_due, approval_status)
    VALUES (t, 'ACH-' || p_nom, s, 'Fourn ' || p_nom, '2026-03-01', '2026-03-31',
            'draft', 1000, 200, 1200, 0, 1200, 'pending') RETURNING id INTO pi;
END $$;

DO $$
DECLARE x record; n int; st text; nl int; ne int;
BEGIN
  x := _b526('T01');
  PERFORM _as_user();
  UPDATE purchase_invoices SET status = 'cancelled' WHERE id = x.pi;

  SELECT count(*), min(status) INTO n, st FROM purchase_credit_notes pcn
  WHERE pcn.tenant_id = x.t AND pcn.purchase_invoice_id = x.pi;
  PERFORM _rec('T01a', 'annuler une facture fournisseur crée UN avoir fournisseur (brouillon)',
    n = 1 AND st = 'draft', format('avoirs=%s statut=%s (1 / draft attendus)', n, st));

  SELECT count(*) INTO nl FROM document_links dl
  WHERE dl.tenant_id = x.t AND dl.amont_type = 'purchase_invoices' AND dl.amont_id = x.pi
    AND dl.aval_type = 'purchase_credit_notes' AND dl.effet = 'purchase.credit_note.from_invoice'
    AND dl.link_type = 'reversed_by';
  PERFORM _rec('T01b', 'l''avoir fournisseur est LIÉ à la facture (reversed_by)', nl = 1, format('liens=%s (1 attendu)', nl));

  SELECT count(*) INTO ne FROM domain_events de
  WHERE de.tenant_id = x.t AND de.event_name = 'purchase_credit_notes.created_from_invoice' AND de.aggregate_id = x.pi;
  PERFORM _rec('T01c', 'un événement purchase_credit_notes.created_from_invoice est émis', ne = 1, format('événements=%s (1 attendu)', ne));
END $$;

DO $$
DECLARE x record; n int;
BEGIN
  x := _b526('T02');
  PERFORM _as_user();
  UPDATE purchase_invoices SET status = 'cancelled' WHERE id = x.pi;
  UPDATE purchase_invoices SET status = 'draft'     WHERE id = x.pi;
  UPDATE purchase_invoices SET status = 'cancelled' WHERE id = x.pi;
  SELECT count(*) INTO n FROM purchase_credit_notes pcn WHERE pcn.tenant_id = x.t AND pcn.purchase_invoice_id = x.pi;
  PERFORM _rec('T02', 'une seconde annulation ne crée pas un second avoir',
    n = 1, format('avoirs=%s (1 attendu)', n));
END $$;

SELECT _audit_assert('526');