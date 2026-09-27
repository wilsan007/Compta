-- ============================================================
-- 258_payment_reminders_idempotent_tests.sql — la relance part une fois
--                                              (EF-01, EF-02)
--
-- MESURÉ AVANT la 258 (base neuve, 257 migrations) :
--   T01 ❌ deux prises du même niveau rendent deux relances — le client était
--          relancé tous les jours, indéfiniment ;
--   T02 ❌ une relance en échec ne peut pas être reprise : elle bloquerait le
--          client pour toujours ;
--   T03 ❌ le niveau 4 (« procédure de recouvrement ») n'existait pas en base :
--          `reminder_level_check` s'arrêtait à 3 ;
--   T04 ❌ un doublon direct n'était refusé par rien ;
--   T05 ❌ un écran connecté pouvait appeler la prise et la clôture.
-- ============================================================

\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '258', false);
DELETE FROM _audit_results WHERE file = '258';

-- Une facture en retard, dans sa société, par le chemin normal.
CREATE OR REPLACE FUNCTION _rel258(p_nom text)
RETURNS TABLE (t uuid, c uuid, inv uuid) LANGUAGE plpgsql AS $$
DECLARE v_t uuid; v_c uuid; v_inv uuid;
BEGIN
  v_t := _mk_tenant(p_nom, false);
  INSERT INTO customers (tenant_id, name) VALUES (v_t, 'Client ' || p_nom) RETURNING id INTO v_c;
  INSERT INTO invoices (tenant_id, number, customer_id, date, due_date, status, total, amount_due, payment_state)
  VALUES (v_t, 'F-' || p_nom, v_c, CURRENT_DATE - 45, CURRENT_DATE - 45, 'sent', 1200, 1200, 'not_paid')
  RETURNING id INTO v_inv;
  t := v_t; c := v_c; inv := v_inv; RETURN NEXT;
END $$;

-- ── T01 — EF-02 : deux prises du même niveau → une seule relance ──────────
DO $$
DECLARE f record; v1 uuid; v2 uuid; v3 uuid; n int;
BEGIN
  SELECT * INTO f FROM _rel258('REL258T01');
  v1 := claim_collection_reminder(f.t, f.inv, f.c, 1, 1200, 5, 'REL-T01-1');
  v2 := claim_collection_reminder(f.t, f.inv, f.c, 1, 1200, 6, 'REL-T01-2');
  -- Un niveau DIFFERENT reste possible : la 2e relance n'est pas la 1re.
  v3 := claim_collection_reminder(f.t, f.inv, f.c, 2, 1200, 20, 'REL-T01-3');
  SELECT count(*) INTO n FROM collection_reminders WHERE tenant_id = f.t AND invoice_id = f.inv;

  PERFORM _rec('T01',
    'deux prises du même niveau : la seconde ne crée rien (le client n''est pas relancé deux fois), un autre niveau reste possible',
    v1 IS NOT NULL AND v2 IS NULL AND v3 IS NOT NULL AND n = 2,
    format('prise 1 = %s, prise 2 = %s (NULL attendu), niveau 2 = %s, relances = %s',
           v1 IS NOT NULL, v2, v3 IS NOT NULL, n));
END $$;

-- ── T02 — EF-02 : un échec se reprend, un envoi prouvé ne se rejoue pas ──
DO $$
DECLARE f record; v1 uuid; v_reprise uuid; v_apres_succes uuid; statut text;
BEGIN
  SELECT * INTO f FROM _rel258('REL258T02');
  v1 := claim_collection_reminder(f.t, f.inv, f.c, 1, 1200, 5, 'REL-T02-1');
  PERFORM finalize_collection_reminder(f.t, v1, false, 'SMTP 550');

  -- L'échec ne prive pas le client de sa relance : elle peut être reprise.
  v_reprise := claim_collection_reminder(f.t, f.inv, f.c, 1, 1200, 6, 'REL-T02-2');
  SELECT status INTO statut FROM collection_reminders WHERE id = v1;

  PERFORM finalize_collection_reminder(f.t, v1, true, NULL);
  -- Un envoi prouvé ne se rejoue plus.
  v_apres_succes := claim_collection_reminder(f.t, f.inv, f.c, 1, 1200, 7, 'REL-T02-3');

  PERFORM _rec('T02',
    'une relance en échec se reprend (statut failed → pending), une relance envoyée ne se rejoue pas',
    v_reprise IS NOT NULL AND statut = 'pending' AND v_apres_succes IS NULL,
    format('prise = %s, statut après reprise = %s, nouvelle prise après envoi = %s',
           v_reprise IS NOT NULL, statut, v_apres_succes));
END $$;

-- ── T03 — le niveau 4 existe, avec son horodatage réel ────────────────────
DO $$
DECLARE f record; v uuid; statut text; quand timestamptz; drapeau boolean; v_err text;
BEGIN
  SELECT * INTO f FROM _rel258('REL258T03');
  v := claim_collection_reminder(f.t, f.inv, f.c, 4, 1200, 65, 'REL-T03-1');
  PERFORM finalize_collection_reminder(f.t, v, true, NULL);
  SELECT status, sent_at, email_sent INTO statut, quand, drapeau
    FROM collection_reminders WHERE id = v;

  -- La clôture depuis un état qui n'est plus `pending` est refusée, nommément.
  BEGIN
    PERFORM finalize_collection_reminder(f.t, v, true, NULL);
  EXCEPTION WHEN no_data_found THEN v_err := SQLERRM; END;

  PERFORM _rec('T03',
    'le niveau 4 (« procédure de recouvrement ») se relance, se dit envoyé avec son heure, et ne se clôt pas deux fois',
    statut = 'sent' AND quand IS NOT NULL AND drapeau AND v_err IS NOT NULL,
    format('statut = %s, heure = %s, email_sent = %s, double clôture refusée = %s',
           statut, quand IS NOT NULL, drapeau, v_err IS NOT NULL));
END $$;

-- ── T04 — l'unicité rend le doublon impossible, l'annulation le libère ────
DO $$
DECLARE f record; v uuid; v2 uuid; refuse boolean := false; reprise boolean := false;
BEGIN
  SELECT * INTO f FROM _rel258('REL258T04');
  v := claim_collection_reminder(f.t, f.inv, f.c, 3, 1200, 40, 'REL-T04-1');
  PERFORM finalize_collection_reminder(f.t, v, true, NULL);

  -- Écrire un doublon à la main (ce que faisait le cron jour après jour) : refusé.
  BEGIN
    INSERT INTO collection_reminders (tenant_id, number, invoice_id, customer_id, reminder_level, amount, status)
    VALUES (f.t, 'REL-T04-2', f.inv, f.c, 3, 1200, 'sent');
  EXCEPTION WHEN unique_violation THEN refuse := true; END;

  -- Une relance annulée ne compte pas : le même niveau peut repartir.
  UPDATE collection_reminders SET status = 'cancelled' WHERE id = v;
  v2 := claim_collection_reminder(f.t, f.inv, f.c, 3, 1200, 41, 'REL-T04-3');
  reprise := v2 IS NOT NULL;

  PERFORM _rec('T04',
    'un doublon de relance est refusé par l''unicité, et une relance annulée libère le niveau',
    refuse AND reprise,
    format('doublon refusé = %s, reprise après annulation = %s', refuse, reprise));
END $$;

-- ── T05 — les droits : un écran ne prend ni ne clôt une relance ───────────
DO $$
DECLARE f record; v uuid; t2 uuid; refus_prise boolean := false; refus_cloture boolean := false;
BEGIN
  SELECT * INTO f FROM _rel258('REL258T05');
  v := claim_collection_reminder(f.t, f.inv, f.c, 1, 1200, 5, 'REL-T05-1');

  PERFORM _as_user();
  BEGIN
    PERFORM claim_collection_reminder(f.t, f.inv, f.c, 2, 1200, 20, 'REL-T05-2');
  EXCEPTION WHEN insufficient_privilege THEN refus_prise := true; END;
  PERFORM set_config('role', 'postgres', true);

  t2 := _mk_tenant('REL258T05B', false);
  BEGIN
    PERFORM finalize_collection_reminder(t2, v, true, NULL);
  EXCEPTION WHEN no_data_found THEN refus_cloture := true; END;

  PERFORM _rec('T05',
    'la prise et la clôture sont réservées au service : un écran connecté est refusé, et la clôture est bornée à la société',
    refus_prise AND refus_cloture,
    format('prise refusée à authenticated = %s, clôture hors société refusée = %s', refus_prise, refus_cloture));
END $$;

SELECT _audit_assert('258');
