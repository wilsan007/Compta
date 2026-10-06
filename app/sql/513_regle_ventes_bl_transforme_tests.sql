-- ============================================================
-- 513_regle_ventes_bl_transforme_tests.sql — partie B, lot Ventes, règle R-009
--
-- Ce que la règle garantit (doc/audit/plan6/B1-INVENTAIRE-62-REGLES-2026-10-05.md) :
--   T01  un BL transformé est LIÉ à sa facture (1 lien `invoiced_by`) + 1 événement ;
--   T02  un BL transformé SANS facture ne pose aucun lien (trace « sans_effet »).
--
-- \ir ci/audit_helpers.sql.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '513', false);
DELETE FROM _audit_results WHERE file = '513';

-- Société isolée : un client, un BL « livré » (validation_status brouillon) et, si
-- demandé, la facture née de ce BL.
CREATE OR REPLACE FUNCTION _b513(p_nom text, p_avec_facture boolean DEFAULT true, OUT t uuid, OUT dn uuid)
LANGUAGE plpgsql AS $$
DECLARE c uuid;
BEGIN
  t := _mk_tenant(p_nom);
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client ' || p_nom) RETURNING id INTO c;
  INSERT INTO delivery_notes (tenant_id, number, customer_id, delivery_date, status, validation_status)
    VALUES (t, 'BL-' || p_nom, c, '2026-03-05', 'delivered', 'draft') RETURNING id INTO dn;
  IF p_avec_facture THEN
    INSERT INTO invoices (tenant_id, customer_id, date, due_date, status, delivery_note_id)
      VALUES (t, c, '2026-03-05', '2026-04-05', 'draft', dn);
  END IF;
END $$;

-- ── T01 : lien au document transformé ───────────────────────────
DO $$
DECLARE x record; nl int; ne int;
BEGIN
  x := _b513('T01');
  PERFORM _as_user();
  UPDATE delivery_notes SET validation_status = 'transformed' WHERE id = x.dn;

  SELECT count(*) INTO nl FROM document_links dl
  WHERE dl.tenant_id = x.t AND dl.amont_type = 'delivery_notes' AND dl.amont_id = x.dn
    AND dl.aval_type = 'invoices' AND dl.effet = 'sale.delivery.transformed' AND dl.link_type = 'invoiced_by';
  PERFORM _rec('T01a', 'un BL transformé est lié à sa facture (1 lien invoiced_by)',
    nl = 1, format('liens=%s (1 attendu)', nl));

  SELECT count(*) INTO ne FROM domain_events de
  WHERE de.tenant_id = x.t AND de.event_name = 'delivery_notes.transformed' AND de.aggregate_id = x.dn;
  PERFORM _rec('T01b', 'un événement delivery_notes.transformed est émis', ne = 1, format('événements=%s (1 attendu)', ne));
END $$;

-- ── T02 : BL transformé sans facture ────────────────────────────
DO $$
DECLARE x record; nl int; n_trace int;
BEGIN
  x := _b513('T02', false);
  PERFORM _as_user();
  UPDATE delivery_notes SET validation_status = 'transformed' WHERE id = x.dn;
  SELECT count(*) INTO nl FROM document_links dl
  WHERE dl.tenant_id = x.t AND dl.amont_type = 'delivery_notes' AND dl.amont_id = x.dn
    AND dl.effet = 'sale.delivery.transformed';
  SELECT count(*) INTO n_trace FROM chain_traces ct
  WHERE ct.tenant_id = x.t AND ct.effet = 'sale.delivery.transformed' AND ct.amont_id = x.dn AND ct.resultat = 'sans_effet';
  PERFORM _rec('T02', 'un BL transformé sans facture ne pose aucun lien (trace « sans_effet »)',
    nl = 0 AND n_trace = 1, format('liens=%s trace sans_effet=%s (0 / 1 attendus)', nl, n_trace));
END $$;

SELECT _audit_assert('513');