-- ============================================================
-- 514_regle_tresorerie_sepa_tests.sql — partie B, lot Trésorerie, R-048, R-049
--
-- Ce que les règles garantissent (doc/audit/plan6/B1-INVENTAIRE-62-REGLES-2026-10-05.md) :
--   T01  un ordre SEPA REJETÉ émet `sepa_payment_orders.rejected` ;
--   T02  un ordre SEPA TRAITÉ émet `sepa_payment_orders.processed` ;
--   T03  IDEMPOTENCE — un rejeu n'émet pas un second événement.
--
-- \ir ci/audit_helpers.sql.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '514', false);
DELETE FROM _audit_results WHERE file = '514';

-- Société isolée : un ordre SEPA.
CREATE OR REPLACE FUNCTION _b514(p_nom text, OUT t uuid, OUT s uuid)
LANGUAGE plpgsql AS $$
BEGIN
  t := _mk_tenant(p_nom);
  INSERT INTO sepa_payment_orders (tenant_id, number, execution_date, total_amount, status)
    VALUES (t, 'SEPA-' || p_nom, '2026-03-31', 1000, 'generated') RETURNING id INTO s;
END $$;

-- ── T01 : rejet ─────────────────────────────────────────────────
DO $$
DECLARE x record; ne int;
BEGIN
  x := _b514('T01');
  PERFORM _as_user();
  UPDATE sepa_payment_orders SET status = 'rejected' WHERE id = x.s;
  SELECT count(*) INTO ne FROM domain_events de
  WHERE de.tenant_id = x.t AND de.event_name = 'sepa_payment_orders.rejected' AND de.aggregate_id = x.s;
  PERFORM _rec('T01', 'un ordre SEPA rejeté émet sepa_payment_orders.rejected',
    ne = 1, format('événements=%s (1 attendu)', ne));
END $$;

-- ── T02 : traité ────────────────────────────────────────────────
DO $$
DECLARE x record; ne int; nt int;
BEGIN
  x := _b514('T02');
  PERFORM _as_user();
  UPDATE sepa_payment_orders SET status = 'transmitted' WHERE id = x.s;
  UPDATE sepa_payment_orders SET status = 'processed'   WHERE id = x.s;
  SELECT count(*) INTO ne FROM domain_events de
  WHERE de.tenant_id = x.t AND de.event_name = 'sepa_payment_orders.processed' AND de.aggregate_id = x.s;
  SELECT count(*) INTO nt FROM chain_traces ct
  WHERE ct.tenant_id = x.t AND ct.effet = 'treasury.sepa.processed' AND ct.amont_id = x.s AND ct.resultat = 'applique';
  PERFORM _rec('T02', 'un ordre SEPA traité émet sepa_payment_orders.processed + trace',
    ne = 1 AND nt = 1, format('événements=%s trace=%s (1 / 1 attendus)', ne, nt));
END $$;

-- ── T03 : idempotence ───────────────────────────────────────────
DO $$
DECLARE x record; ne int;
BEGIN
  x := _b514('T03');
  PERFORM _as_user();
  UPDATE sepa_payment_orders SET status = 'rejected'    WHERE id = x.s;
  UPDATE sepa_payment_orders SET status = 'generated'   WHERE id = x.s;
  UPDATE sepa_payment_orders SET status = 'rejected'    WHERE id = x.s;
  SELECT count(*) INTO ne FROM domain_events de
  WHERE de.tenant_id = x.t AND de.event_name = 'sepa_payment_orders.rejected' AND de.aggregate_id = x.s;
  PERFORM _rec('T03', 'un rejeu de « rejeté » n''émet pas un second événement',
    ne = 1, format('événements=%s (1 attendu)', ne));
END $$;

SELECT _audit_assert('514');