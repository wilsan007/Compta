-- ============================================================
-- 259_placebos_removed_or_wired_tests.sql — les écrans ne tamponnent plus un
--                                          succès (EF-03, EF-06, TVA-01)
--
-- MESURÉ AVANT la 259 (base neuve, 258 migrations) :
--   `submitEdiTva` (misc.ts) fabriquait `EDI-<Date.now()>` et écrivait
--   `edi_status = 'submitted'` ; `syncBankConnection` (banking.ts) tamponnait
--   `last_sync_at = now()` ; `EInvoicePage` n'écrivait rien du tout. Dans les
--   trois cas, **aucune transmission** n'avait eu lieu — et la base laissait
--   faire. Les trois scénarios ci-dessous sont rouges avant, verts après.
--
-- Les triggers refusent le CHANGEMENT de la colonne vue par un client : un
-- formulaire qui recopie la valeur existante continue de fonctionner.
-- ============================================================

\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '259', false);
DELETE FROM _audit_results WHERE file = '259';

-- Poser un JWT de client, puis reprendre le rôle du service (le cron, la
-- fonction Edge) : c'est la seule différence que la porte observe.
CREATE OR REPLACE FUNCTION _client259(p_role text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', gen_random_uuid()::text, 'role', p_role)::text, true);
  PERFORM set_config('role', p_role, true);
END $$;

-- ── T01 — TVA-01 : un écran ne peut pas se déclarer « déposée » ────────────
DO $$
DECLARE t uuid; v uuid; refus boolean := false; msg text; recopie boolean := false;
        service_ok boolean := false; statut text; ident text;
BEGIN
  t := _mk_tenant('PL259T01', false);
  INSERT INTO vat_returns (tenant_id, period_start, period_end, status, edi_status)
  VALUES (t, '2026-01-01', '2026-01-31', 'draft', 'not_submitted') RETURNING id INTO v;

  PERFORM _client259('authenticated');
  BEGIN
    UPDATE vat_returns SET edi_status = 'submitted', edi_tva_id = 'EDI-FABRIQUE' WHERE id = v;
  EXCEPTION WHEN insufficient_privilege THEN refus := true; msg := SQLERRM; END;

  -- Recopier la valeur existante (ce que fait un formulaire) reste permis.
  UPDATE vat_returns SET edi_status = edi_status, status = 'draft' WHERE id = v;
  recopie := true;

  -- Le service, lui, transmet réellement — et là seulement la trace s'écrit.
  PERFORM _client259('service_role');
  UPDATE vat_returns
     SET edi_status = 'submitted', edi_tva_id = 'EDI-REEL', edi_submitted_at = now()
   WHERE id = v;
  SELECT edi_status, edi_tva_id INTO statut, ident FROM vat_returns WHERE id = v;
  service_ok := (statut = 'submitted' AND ident = 'EDI-REEL');

  PERFORM _rec('T01',
    'EDI-TVA : un écran connecté ne peut pas écrire le statut de dépôt (refus nommé), le service le peut après transmission',
    refus AND recopie AND service_ok,
    format('refus = %s (%s), recopie permise = %s, dépôt du service = %s', refus, left(msg, 90), recopie, service_ok));
END $$;

-- ── T02 — EF-06 : un écran ne peut pas se déclarer « déposée à Chorus Pro » ──
DO $$
DECLARE t uuid; c uuid; inv uuid; refus boolean := false; service_ok boolean := false; statut text;
BEGIN
  t := _mk_tenant('PL259T02', false);
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client 259') RETURNING id INTO c;
  INSERT INTO invoices (tenant_id, number, customer_id, date, due_date, status)
  VALUES (t, 'F-259-2', c, CURRENT_DATE, CURRENT_DATE, 'sent') RETURNING id INTO inv;

  PERFORM _client259('authenticated');
  BEGIN
    UPDATE invoices
       SET e_invoice_status = 'submitted', e_invoice_platform = 'chorus_pro', e_invoice_id = 'FABRIQUE'
     WHERE id = inv;
  EXCEPTION WHEN insufficient_privilege THEN refus := true; END;

  PERFORM _client259('service_role');
  UPDATE invoices
     SET e_invoice_status = 'submitted', e_invoice_platform = 'chorus_pro',
         e_invoice_submitted_at = now(), e_invoice_id = 'CHORUS-REEL'
   WHERE id = inv;
  SELECT e_invoice_status INTO statut FROM invoices WHERE id = inv;
  service_ok := statut = 'submitted';

  PERFORM _rec('T02',
    'facture électronique : l''écran ne peut pas écrire la trace du dépôt, la fonction Edge le peut après le dépôt réel',
    refus AND service_ok,
    format('refus de l''écran = %s, dépôt du service = %s', refus, service_ok));
END $$;

-- ── T03 — EF-03 : un écran ne peut pas tamponner une synchronisation ───────
DO $$
DECLARE t uuid; v uuid; refus boolean := false; service_ok boolean := false;
        edition_ok boolean := false; quand timestamptz;
BEGIN
  t := _mk_tenant('PL259T03', false);
  INSERT INTO bank_connections (tenant_id, provider, status) VALUES (t, 'gocardless', 'pending')
  RETURNING id INTO v;

  PERFORM _client259('authenticated');
  BEGIN
    UPDATE bank_connections SET last_sync_at = now(), status = 'active', error_message = NULL WHERE id = v;
  EXCEPTION WHEN insufficient_privilege THEN refus := true; END;

  -- Les autres champs d'une connexion restent modifiables par l'écran.
  UPDATE bank_connections SET sync_frequency = 'hourly' WHERE id = v;
  edition_ok := true;

  PERFORM _client259('service_role');
  UPDATE bank_connections SET last_sync_at = now(), status = 'active' WHERE id = v;
  SELECT last_sync_at INTO quand FROM bank_connections WHERE id = v;
  service_ok := quand IS NOT NULL;

  PERFORM _rec('T03',
    'synchronisation bancaire : la date de synchronisation ne peut être tamponnée par un écran, seulement par la fonction après un appel réel',
    refus AND edition_ok AND service_ok,
    format('refus du tampon = %s, édition des autres champs = %s, tampon du service = %s', refus, edition_ok, service_ok));
END $$;

SELECT _audit_assert('259');
