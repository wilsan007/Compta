-- ============================================================
-- 506_regle_relances_suivi_tests.sql — partie B, lot Relances, R-059, R-060, R-061
--
-- Ce que les règles garantissent (doc/audit/plan6/B1-INVENTAIRE-62-REGLES-2026-10-05.md) :
--   T01  une relance passée à `sent` reçoit son HORODATAGE (`sent_at`) — défaut EF-02 ;
--   T02  une relance PAYÉE émet `collection_reminders.paid` ;
--   T03  une relance ANNULÉE émet `collection_reminders.cancelled` ;
--   T04  IDEMPOTENCE — repasser par `paid` n'émet pas un second événement.
--
-- \ir ci/audit_helpers.sql : société posée en superutilisateur, puis rôle
-- `authenticated` (un utilisateur réel, sous RLS).
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '506', false);
DELETE FROM _audit_results WHERE file = '506';

-- Société isolée : un client et une relance en attente (montant 500).
CREATE OR REPLACE FUNCTION _b506(p_nom text, OUT t uuid, OUT r uuid)
LANGUAGE plpgsql AS $$
DECLARE c uuid;
BEGIN
  t := _mk_tenant(p_nom);
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client ' || p_nom) RETURNING id INTO c;
  INSERT INTO collection_reminders (tenant_id, number, customer_id, reminder_level, reminder_date, amount, status)
    VALUES (t, 'REL-' || p_nom, c, 1, '2026-03-15', 500, 'pending') RETURNING id INTO r;
END $$;

-- ── T01 : horodatage de la relance ──────────────────────────────
DO $$
DECLARE v record; v_sent timestamptz;
BEGIN
  v := _b506('T01');
  PERFORM _as_user();
  UPDATE collection_reminders SET status = 'sent' WHERE id = v.r;
  SELECT sent_at INTO v_sent FROM collection_reminders WHERE id = v.r;
  PERFORM _rec('T01', 'une relance passée à « sent » reçoit son horodatage (sent_at)',
    v_sent IS NOT NULL, format('sent_at=%s (non nul attendu)', v_sent));
END $$;

-- ── T02 : relance payée ─────────────────────────────────────────
DO $$
DECLARE v record; ne int;
BEGIN
  v := _b506('T02');
  PERFORM _as_user();
  UPDATE collection_reminders SET status = 'paid' WHERE id = v.r;
  SELECT count(*) INTO ne FROM domain_events de
  WHERE de.tenant_id = v.t AND de.event_name = 'collection_reminders.paid' AND de.aggregate_id = v.r;
  PERFORM _rec('T02', 'une relance payée émet collection_reminders.paid',
    ne = 1, format('événements=%s (1 attendu)', ne));
END $$;

-- ── T03 : relance annulée ───────────────────────────────────────
DO $$
DECLARE v record; ne int;
BEGIN
  v := _b506('T03');
  PERFORM _as_user();
  UPDATE collection_reminders SET status = 'cancelled' WHERE id = v.r;
  SELECT count(*) INTO ne FROM domain_events de
  WHERE de.tenant_id = v.t AND de.event_name = 'collection_reminders.cancelled' AND de.aggregate_id = v.r;
  PERFORM _rec('T03', 'une relance annulée émet collection_reminders.cancelled',
    ne = 1, format('événements=%s (1 attendu)', ne));
END $$;

-- ── T04 : idempotence ───────────────────────────────────────────
DO $$
DECLARE v record; ne int;
BEGIN
  v := _b506('T04');
  PERFORM _as_user();
  UPDATE collection_reminders SET status = 'paid'    WHERE id = v.r;
  UPDATE collection_reminders SET status = 'pending' WHERE id = v.r;
  UPDATE collection_reminders SET status = 'paid'    WHERE id = v.r;
  SELECT count(*) INTO ne FROM domain_events de
  WHERE de.tenant_id = v.t AND de.event_name = 'collection_reminders.paid' AND de.aggregate_id = v.r;
  PERFORM _rec('T04', 'un rejeu de l''état « payée » n''émet pas un second événement',
    ne = 1, format('événements=%s (1 attendu)', ne));
END $$;

SELECT _audit_assert('506');