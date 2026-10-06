-- ============================================================
-- 515_regle_tresorerie_virement_tests.sql — partie B, lot Trésorerie, R-050, R-051
--
-- Ce que les règles garantissent (doc/audit/plan6/B1-INVENTAIRE-62-REGLES-2026-10-05.md) :
--   T01  un virement EXÉCUTÉ émet `treasury_transfers.executed` ;
--   T02  un virement ANNULÉ émet `treasury_transfers.cancelled` ;
--   T03  IDEMPOTENCE — un rejeu n'émet pas un second événement.
--
-- \ir ci/audit_helpers.sql.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '515', false);
DELETE FROM _audit_results WHERE file = '515';

-- Société isolée : deux comptes bancaires, un virement brouillon de 500.
CREATE OR REPLACE FUNCTION _b515(p_nom text, OUT t uuid, OUT tt uuid)
LANGUAGE plpgsql AS $$
DECLARE a1 uuid; a2 uuid;
BEGIN
  t := _mk_tenant(p_nom);
  INSERT INTO bank_accounts (tenant_id, name, type, account_code, journal_code)
    VALUES (t, 'Banque 1 ' || p_nom, 'chequing', '512100', 'BQ') RETURNING id INTO a1;
  INSERT INTO bank_accounts (tenant_id, name, type, account_code, journal_code)
    VALUES (t, 'Banque 2 ' || p_nom, 'chequing', '512200', 'BQ') RETURNING id INTO a2;
  INSERT INTO treasury_transfers (tenant_id, number, from_account_id, to_account_id, amount, transfer_date, status)
    VALUES (t, 'VIR-' || p_nom, a1, a2, 500, '2026-03-20', 'draft') RETURNING id INTO tt;
END $$;

-- ── T01 : virement exécuté ──────────────────────────────────────
DO $$
DECLARE x record; ne int; nt int;
BEGIN
  x := _b515('T01');
  PERFORM _as_user();
  UPDATE treasury_transfers SET status = 'executed' WHERE id = x.tt;
  SELECT count(*) INTO ne FROM domain_events de
  WHERE de.tenant_id = x.t AND de.event_name = 'treasury_transfers.executed' AND de.aggregate_id = x.tt;
  SELECT count(*) INTO nt FROM chain_traces ct
  WHERE ct.tenant_id = x.t AND ct.effet = 'treasury.transfer.executed' AND ct.amont_id = x.tt AND ct.resultat = 'applique';
  PERFORM _rec('T01', 'un virement exécuté émet treasury_transfers.executed + trace',
    ne = 1 AND nt = 1, format('événements=%s trace=%s (1 / 1 attendus)', ne, nt));
END $$;

-- ── T02 : virement annulé ───────────────────────────────────────
DO $$
DECLARE x record; ne int;
BEGIN
  x := _b515('T02');
  PERFORM _as_user();
  UPDATE treasury_transfers SET status = 'cancelled' WHERE id = x.tt;
  SELECT count(*) INTO ne FROM domain_events de
  WHERE de.tenant_id = x.t AND de.event_name = 'treasury_transfers.cancelled' AND de.aggregate_id = x.tt;
  PERFORM _rec('T02', 'un virement annulé émet treasury_transfers.cancelled',
    ne = 1, format('événements=%s (1 attendu)', ne));
END $$;

-- ── T03 : idempotence ───────────────────────────────────────────
DO $$
DECLARE x record; ne int;
BEGIN
  x := _b515('T03');
  PERFORM _as_user();
  UPDATE treasury_transfers SET status = 'executed' WHERE id = x.tt;
  UPDATE treasury_transfers SET status = 'draft'    WHERE id = x.tt;
  UPDATE treasury_transfers SET status = 'executed' WHERE id = x.tt;
  SELECT count(*) INTO ne FROM domain_events de
  WHERE de.tenant_id = x.t AND de.event_name = 'treasury_transfers.executed' AND de.aggregate_id = x.tt;
  PERFORM _rec('T03', 'un rejeu de « exécuté » n''émet pas un second événement',
    ne = 1, format('événements=%s (1 attendu)', ne));
END $$;

SELECT _audit_assert('515');