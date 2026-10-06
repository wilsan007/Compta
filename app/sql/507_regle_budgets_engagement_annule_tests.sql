-- ============================================================
-- 507_regle_budgets_engagement_annule_tests.sql — partie B, lot Budgets, règle R-058
--
-- Ce que la règle garantit (doc/audit/plan6/B1-INVENTAIRE-62-REGLES-2026-10-05.md) :
--   T01  un engagement annulé émet `budget_commitments.cancelled` et laisse UNE trace ;
--   T02  IDEMPOTENCE — repasser par `cancelled` n'émet pas un second événement.
--
-- \ir ci/audit_helpers.sql : société posée en superutilisateur, puis rôle
-- `authenticated` (un utilisateur réel, sous RLS).
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '507', false);
DELETE FROM _audit_results WHERE file = '507';

-- Société isolée : un engagement actif de 1000 sur le compte 607000.
CREATE OR REPLACE FUNCTION _b507(p_nom text, OUT t uuid, OUT b uuid)
LANGUAGE plpgsql AS $$
BEGIN
  t := _mk_tenant(p_nom);
  INSERT INTO budget_commitments (tenant_id, description, account_code, amount, commitment_date, status)
    VALUES (t, 'Engagement ' || p_nom, '607000', 1000, '2026-03-01', 'active') RETURNING id INTO b;
END $$;

-- ── T01 : engagement annulé → événement + trace ─────────────────
DO $$
DECLARE v record; ne int; nt int;
BEGIN
  v := _b507('T01');
  PERFORM _as_user();
  UPDATE budget_commitments SET status = 'cancelled' WHERE id = v.b;

  SELECT count(*) INTO ne FROM domain_events de
  WHERE de.tenant_id = v.t AND de.event_name = 'budget_commitments.cancelled' AND de.aggregate_id = v.b;
  PERFORM _rec('T01a', 'un engagement annulé émet budget_commitments.cancelled',
    ne = 1, format('événements=%s (1 attendu)', ne));

  SELECT count(*) INTO nt FROM chain_traces ct
  WHERE ct.tenant_id = v.t AND ct.effet = 'budget.commitment.cancelled'
    AND ct.amont_id = v.b AND ct.resultat = 'applique';
  PERFORM _rec('T01b', 'la libération de l''engagement est tracée « applique »',
    nt = 1, format('traces=%s (1 attendue)', nt));
END $$;

-- ── T02 : idempotence ───────────────────────────────────────────
DO $$
DECLARE v record; ne int;
BEGIN
  v := _b507('T02');
  PERFORM _as_user();
  UPDATE budget_commitments SET status = 'cancelled' WHERE id = v.b;
  UPDATE budget_commitments SET status = 'active'    WHERE id = v.b;
  UPDATE budget_commitments SET status = 'cancelled' WHERE id = v.b;
  SELECT count(*) INTO ne FROM domain_events de
  WHERE de.tenant_id = v.t AND de.event_name = 'budget_commitments.cancelled' AND de.aggregate_id = v.b;
  PERFORM _rec('T02', 'un rejeu de l''état « annulé » n''émet pas un second événement',
    ne = 1, format('événements=%s (1 attendu)', ne));
END $$;

SELECT _audit_assert('507');