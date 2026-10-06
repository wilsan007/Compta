-- ============================================================
-- 505_regle_achats_facture_surveillance_tests.sql — partie B, lot Achats, R-017 & R-018
--
-- Ce que les règles garantissent (doc/audit/plan6/B1-INVENTAIRE-62-REGLES-2026-10-05.md) :
--   T01  une facture fournisseur passée à `overdue` émet `purchase_invoices.overdue`
--        et laisse UNE trace `applique` ;
--   T02  une facture fournisseur REJETÉE émet `purchase_invoices.rejected` et une trace ;
--   T03  IDEMPOTENCE — repasser par `overdue` n'émet pas un second événement.
--
-- \ir ci/audit_helpers.sql : société posée en superutilisateur, puis rôle
-- `authenticated` (un utilisateur réel, sous RLS).
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '505', false);
DELETE FROM _audit_results WHERE file = '505';

-- Société isolée : un fournisseur et une facture fournisseur en brouillon (1200 TTC).
CREATE OR REPLACE FUNCTION _b505(p_nom text, OUT t uuid, OUT i uuid)
LANGUAGE plpgsql AS $$
DECLARE s uuid;
BEGIN
  t := _mk_tenant(p_nom);
  INSERT INTO suppliers (tenant_id, name) VALUES (t, 'Fournisseur ' || p_nom) RETURNING id INTO s;
  INSERT INTO purchase_invoices (tenant_id, number, supplier_id, supplier_name, date, due_date,
                                 status, subtotal, vat_total, total, amount_paid, amount_due, approval_status)
    VALUES (t, 'ACH-' || p_nom, s, 'Fournisseur ' || p_nom, '2026-03-01', '2026-03-31',
            'draft', 1000, 200, 1200, 0, 1200, 'pending')
    RETURNING id INTO i;
END $$;

-- ── T01 : facture fournisseur échue ─────────────────────────────
DO $$
DECLARE v record; ne int; nt int;
BEGIN
  v := _b505('T01');
  PERFORM _as_user();
  UPDATE purchase_invoices SET status = 'overdue' WHERE id = v.i;

  SELECT count(*) INTO ne FROM domain_events de
  WHERE de.tenant_id = v.t AND de.event_name = 'purchase_invoices.overdue' AND de.aggregate_id = v.i;
  PERFORM _rec('T01a', 'une facture fournisseur échue émet purchase_invoices.overdue',
    ne = 1, format('événements=%s (1 attendu)', ne));

  SELECT count(*) INTO nt FROM chain_traces ct
  WHERE ct.tenant_id = v.t AND ct.effet = 'purchase.invoice.overdue'
    AND ct.amont_id = v.i AND ct.resultat = 'applique';
  PERFORM _rec('T01b', 'le maillon d''échéance est tracé « applique »',
    nt = 1, format('traces=%s (1 attendue)', nt));
END $$;

-- ── T02 : facture fournisseur rejetée ───────────────────────────
DO $$
DECLARE v record; ne int; nt int;
BEGIN
  v := _b505('T02');
  PERFORM _as_user();
  UPDATE purchase_invoices SET approval_status = 'rejected' WHERE id = v.i;

  SELECT count(*) INTO ne FROM domain_events de
  WHERE de.tenant_id = v.t AND de.event_name = 'purchase_invoices.rejected' AND de.aggregate_id = v.i;
  PERFORM _rec('T02a', 'une facture fournisseur rejetée émet purchase_invoices.rejected',
    ne = 1, format('événements=%s (1 attendu)', ne));

  SELECT count(*) INTO nt FROM chain_traces ct
  WHERE ct.tenant_id = v.t AND ct.effet = 'purchase.invoice.rejected'
    AND ct.amont_id = v.i AND ct.resultat = 'applique';
  PERFORM _rec('T02b', 'le maillon de rejet est tracé « applique »',
    nt = 1, format('traces=%s (1 attendue)', nt));
END $$;

-- ── T03 : idempotence de l'échéance ─────────────────────────────
DO $$
DECLARE v record; ne int;
BEGIN
  v := _b505('T03');
  PERFORM _as_user();
  UPDATE purchase_invoices SET status = 'overdue' WHERE id = v.i;
  UPDATE purchase_invoices SET status = 'draft'   WHERE id = v.i;
  UPDATE purchase_invoices SET status = 'overdue' WHERE id = v.i;
  SELECT count(*) INTO ne FROM domain_events de
  WHERE de.tenant_id = v.t AND de.event_name = 'purchase_invoices.overdue' AND de.aggregate_id = v.i;
  PERFORM _rec('T03', 'un rejeu de l''état « échue » n''émet pas un second événement',
    ne = 1, format('événements=%s (1 attendu)', ne));
END $$;

SELECT _audit_assert('505');