-- ============================================================
-- 504_regle_ventes_devis_expire_tests.sql — partie B, lot Ventes, règle R-002
--
-- Ce que la règle R-002 garantit (doc/audit/plan6/B1-INVENTAIRE-62-REGLES-2026-10-05.md) :
--   T01  un devis passé à `expired` ÉMET UN événement `quotes.expired` et laisse
--        UNE trace `applique` ;
--   T02  IDEMPOTENCE — repasser par `expired` n'émet pas un second événement.
--
-- \ir ci/audit_helpers.sql : société posée en superutilisateur, puis rôle
-- `authenticated` (un utilisateur réel, sous RLS).
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '504', false);
DELETE FROM _audit_results WHERE file = '504';

-- Société isolée : un devis « envoyé ».
CREATE OR REPLACE FUNCTION _b504(p_nom text, OUT t uuid, OUT q uuid)
LANGUAGE plpgsql AS $$
DECLARE c uuid;
BEGIN
  t := _mk_tenant(p_nom);
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client ' || p_nom) RETURNING id INTO c;
  INSERT INTO quotes (tenant_id, number, customer_id, date, expiry_date, status, validation_status)
    VALUES (t, 'DEV-' || p_nom, c, '2026-03-10', '2026-04-10', 'sent', 'draft') RETURNING id INTO q;
END $$;

-- ── T01 : devis expiré → événement + trace ──────────────────────
DO $$
DECLARE v record; ne int; nt int;
BEGIN
  v := _b504('T01');
  PERFORM _as_user();
  UPDATE quotes SET status = 'expired' WHERE id = v.q;

  SELECT count(*) INTO ne FROM domain_events de
  WHERE de.tenant_id = v.t AND de.event_name = 'quotes.expired' AND de.aggregate_id = v.q;
  PERFORM _rec('T01a', 'un devis expiré émet un événement quotes.expired',
    ne = 1, format('événements=%s (1 attendu)', ne));

  SELECT count(*) INTO nt FROM chain_traces ct
  WHERE ct.tenant_id = v.t AND ct.effet = 'sale.quote.expired'
    AND ct.amont_id = v.q AND ct.resultat = 'applique';
  PERFORM _rec('T01b', 'le maillon est tracé « applique »',
    nt = 1, format('traces=%s (1 attendue)', nt));
END $$;

-- ── T02 : idempotence — pas de second événement ─────────────────
DO $$
DECLARE v record; ne int;
BEGIN
  v := _b504('T02');
  PERFORM _as_user();
  UPDATE quotes SET status = 'expired' WHERE id = v.q;
  UPDATE quotes SET status = 'sent'    WHERE id = v.q;   -- on recule
  UPDATE quotes SET status = 'expired' WHERE id = v.q;   -- rejeu de l'état

  SELECT count(*) INTO ne FROM domain_events de
  WHERE de.tenant_id = v.t AND de.event_name = 'quotes.expired' AND de.aggregate_id = v.q;
  PERFORM _rec('T02', 'un rejeu de l''état « expiré » n''émet pas un second événement',
    ne = 1, format('événements=%s (1 attendu)', ne));
END $$;

SELECT _audit_assert('504');