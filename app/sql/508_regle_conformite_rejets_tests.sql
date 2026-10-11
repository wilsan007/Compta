-- ============================================================
-- 508_regle_conformite_rejets_tests.sql — partie B, lot Conformité, R-054, R-055, R-056
--
-- Ce que les règles garantissent (doc/audit/plan6/B1-INVENTAIRE-62-REGLES-2026-10-05.md) :
--   T01  un rejet EDI de déclaration de TVA émet `vat_returns.edi_rejected` + trace ;
--   T02  une DSN rejetée émet `dsn_declarations.rejected` + trace ;
--   T03  une déclaration sociale rejetée émet `social_declarations.rejected` + trace ;
--   T04  IDEMPOTENCE — un rejeu de DSN rejetée n'émet pas un second événement.
--
-- \ir ci/audit_helpers.sql : société posée en superutilisateur, puis rôle
-- `authenticated` (un utilisateur réel, sous RLS).
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '508', false);
DELETE FROM _audit_results WHERE file = '508';

-- Société isolée : une déclaration de TVA, une DSN, une déclaration sociale.
CREATE OR REPLACE FUNCTION _b508(p_nom text, OUT t uuid, OUT v uuid, OUT d uuid, OUT s uuid)
LANGUAGE plpgsql AS $$
BEGIN
  t := _mk_tenant(p_nom);
  INSERT INTO vat_returns (tenant_id, period_start, period_end, status, edi_status)
    VALUES (t, '2026-01-01', '2026-03-31', 'draft', 'submitted') RETURNING id INTO v;
  INSERT INTO dsn_declarations (tenant_id, period, type, status)
    VALUES (t, '2026-03', 'mensuelle', 'generated') RETURNING id INTO d;
  INSERT INTO social_declarations (tenant_id, number, declaration_type, period, status)
    VALUES (t, 'DS-' || p_nom, 'urssaf', '2026-03', 'generated') RETURNING id INTO s;
END $$;

-- ── T01 : rejet EDI de TVA ──────────────────────────────────────
-- `edi_status` s'écrit par le SERVEUR : la garde `trg_refuse_client_edi_stamp` refuse
-- un JWT utilisateur (« la télédéclaration EDI-TVA n'a pas eu lieu »). C'est le
-- comportement VOULU. Le test écarte donc cette garde le temps de simuler la trame
-- serveur, puis la remet — et vérifie que NOTRE maillon émet bien l'événement.
DO $$
DECLARE x record; ne int;
BEGIN
  x := _b508('T01');
  ALTER TABLE vat_returns DISABLE TRIGGER trg_refuse_client_edi_stamp;
  UPDATE vat_returns SET edi_status = 'rejected' WHERE id = x.v;
  ALTER TABLE vat_returns ENABLE TRIGGER trg_refuse_client_edi_stamp;
  PERFORM _as_user();

  SELECT count(*) INTO ne FROM domain_events de
  WHERE de.tenant_id = x.t AND de.event_name = 'vat_returns.edi_rejected' AND de.aggregate_id = x.v;
  PERFORM _rec('T01', 'un rejet EDI de TVA émet vat_returns.edi_rejected',
    ne = 1, format('événements=%s (1 attendu)', ne));
END $$;

-- ── T02 : DSN rejetée ───────────────────────────────────────────
DO $$
DECLARE x record; ne int; nt int;
BEGIN
  x := _b508('T02');
  PERFORM _as_user();
  UPDATE dsn_declarations SET status = 'rejected' WHERE id = x.d;
  SELECT count(*) INTO ne FROM domain_events de
  WHERE de.tenant_id = x.t AND de.event_name = 'dsn_declarations.rejected' AND de.aggregate_id = x.d;
  SELECT count(*) INTO nt FROM chain_traces ct
  WHERE ct.tenant_id = x.t AND ct.effet = 'payroll.dsn.rejected' AND ct.amont_id = x.d AND ct.resultat = 'applique';
  PERFORM _rec('T02', 'une DSN rejetée émet dsn_declarations.rejected et laisse une trace',
    ne = 1 AND nt = 1, format('événements=%s trace=%s (1 / 1 attendus)', ne, nt));
END $$;

-- ── T03 : déclaration sociale rejetée ───────────────────────────
DO $$
DECLARE x record; ne int;
BEGIN
  x := _b508('T03');
  PERFORM _as_user();
  UPDATE social_declarations SET status = 'rejected' WHERE id = x.s;
  SELECT count(*) INTO ne FROM domain_events de
  WHERE de.tenant_id = x.t AND de.event_name = 'social_declarations.rejected' AND de.aggregate_id = x.s;
  PERFORM _rec('T03', 'une déclaration sociale rejetée émet social_declarations.rejected',
    ne = 1, format('événements=%s (1 attendu)', ne));
END $$;

-- ── T04 : idempotence (DSN) ─────────────────────────────────────
DO $$
DECLARE x record; ne int;
BEGIN
  x := _b508('T04');
  PERFORM _as_user();
  UPDATE dsn_declarations SET status = 'rejected'   WHERE id = x.d;
  UPDATE dsn_declarations SET status = 'generated'  WHERE id = x.d;
  UPDATE dsn_declarations SET status = 'rejected'   WHERE id = x.d;
  SELECT count(*) INTO ne FROM domain_events de
  WHERE de.tenant_id = x.t AND de.event_name = 'dsn_declarations.rejected' AND de.aggregate_id = x.d;
  PERFORM _rec('T04', 'un rejeu de « DSN rejetée » n''émet pas un second événement',
    ne = 1, format('événements=%s (1 attendu)', ne));
END $$;

SELECT _audit_assert('508');