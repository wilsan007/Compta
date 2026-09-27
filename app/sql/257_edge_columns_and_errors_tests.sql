-- ============================================================
-- 257_edge_columns_and_errors_tests.sql — les colonnes fantômes (W6)
--
-- MESURÉ AVANT la 257, sur base neuve (231 migrations) : **20 écritures
-- impossibles** (scanner W0.2), et les huit scénarios ci-dessous rouges pour la
-- bonne raison — la colonne n'existe pas. Après : chaque colonne existe, et
-- chacune porte la garantie qu'elle annonce (unicité, clé composite, énumération).
--
-- Les cas « le code écrit une colonne réelle après alignement » (http_status →
-- response_code, provider_requisition_id → provider_connection_id) sont des
-- colonnes **existantes** : ils sont vérifiés par le scanner, pas ici.
-- ============================================================

\ir ci/audit_helpers.sql
\ir ci/ledger_fixture.sql
SELECT set_config('audit.file', '257', false);
DELETE FROM _audit_results WHERE file = '257';

CREATE OR REPLACE FUNCTION _a_col(p_table text, p_col text)
RETURNS boolean LANGUAGE sql AS $$
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns c
    WHERE c.table_schema = 'public' AND c.table_name = p_table AND c.column_name = p_col)
$$;

-- Poser le contexte d'une société sans changer de rôle (on mesure en `postgres`,
-- comme la 237 : une clé de données doit refuser même hors contexte applicatif).
CREATE OR REPLACE FUNCTION _ctx257(p_t uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_u uuid;
BEGIN
  SELECT auth_id INTO v_u FROM tenant_users
   WHERE tenant_id = p_t AND status = 'active' ORDER BY created_at LIMIT 1;
  PERFORM set_config('request.jwt.claim.sub', v_u::text, false);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_u, 'role', 'postgres')::text, false);
  PERFORM set_config('app.active_tenant_id', p_t::text, false);
END $$;

-- ── T01 — leave_requests.manager_comment : le refus mobile peut écrire son motif ──
DO $$
DECLARE t uuid; e uuid; lr uuid; v_motif text; v_ok boolean;
BEGIN
  t := _mk_tenant('EF257T01', false);
  PERFORM _as_user();
  BEGIN
    INSERT INTO employees (tenant_id, name, email, status, salary)
    VALUES (t, 'Dupont Jean', 'ef257t01@audit.test', 'active', 3000) RETURNING id INTO e;
    INSERT INTO leave_requests (tenant_id, employee_id, leave_type, start_date, end_date, days, status)
    VALUES (t, e, 'annual', CURRENT_DATE, CURRENT_DATE, 1, 'pending') RETURNING id INTO lr;

    UPDATE leave_requests
       SET status = 'rejected', manager_comment = 'Effectif insuffisant cette semaine'
     WHERE id = lr AND tenant_id = t;

    SELECT manager_comment INTO v_motif FROM leave_requests WHERE id = lr;
    v_ok := (v_motif = 'Effectif insuffisant cette semaine');
    PERFORM _rec('T01',
      'refus d''un congé depuis le mobile : le motif est écrit et relu',
      v_ok, format('manager_comment relu = %L', v_motif));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T01', 'refus d''un congé depuis le mobile : le motif est écrit et relu', false, SQLERRM);
  END;
END $$;

-- ── T02 — bank_transactions.matched_line_id : clé composite, pas de fuite ──
DO $$
DECLARE t1 uuid; t2 uuid; a uuid; tx uuid; ligne1 uuid; ligne2 uuid; e1 uuid; e2 uuid;
        refuse boolean := false; accepte boolean := false;
BEGIN
  -- Exercice 2026 : `_entry` valide l'écriture, et le 26/09/2026 doit être couvert.
  -- Les deux sociétés sont montées hors contexte applicatif (rôle `postgres`) :
  -- c'est une CLÉ, pas une politique RLS — elle doit refuser même hors contexte.
  t1 := _mk_tenant('EF257T02A', false);
  PERFORM _ledger_fixture(t1);
  t2 := _mk_tenant('EF257T02B', false);
  PERFORM _ledger_fixture(t2);
  BEGIN
    PERFORM _ctx257(t1);
    e1 := _entry(t1, 'EC-257-1', CURRENT_DATE, '[{"a":"512000","d":100},{"a":"706000","c":100}]');
    PERFORM _ctx257(t2);
    e2 := _entry(t2, 'EC-257-2', CURRENT_DATE, '[{"a":"512000","d":100},{"a":"706000","c":100}]');
    PERFORM _ctx257(t1);
    -- `_entry` rend l'ÉCRITURE ; la clé pointe la LIGNE : on la relit.
    SELECT id INTO ligne1 FROM journal_lines WHERE journal_id = e1 AND tenant_id = t1 ORDER BY id LIMIT 1;
    SELECT id INTO ligne2 FROM journal_lines WHERE journal_id = e2 AND tenant_id = t2 ORDER BY id LIMIT 1;
    INSERT INTO bank_accounts (tenant_id, name, type) VALUES (t1, 'Compte ' || t1, 'chequing') RETURNING id INTO a;
    INSERT INTO bank_transactions (tenant_id, account_id, date, description, type, amount, source)
    VALUES (t1, a, CURRENT_DATE, 'VIR CLIENT', 'credit', 100, 'import') RETURNING id INTO tx;

    -- 1. pointer l'écriture de la société voisine est refusé
    BEGIN
      UPDATE bank_transactions SET matched_line_id = ligne2, matched = true WHERE id = tx;
    EXCEPTION WHEN foreign_key_violation THEN refuse := true; END;

    -- 2. pointer sa propre écriture est accepté
    UPDATE bank_transactions SET matched_line_id = ligne1, matched = true WHERE id = tx;
    SELECT matched_line_id = ligne1 INTO accepte FROM bank_transactions WHERE id = tx;

    PERFORM _rec('T02',
      'matched_line_id : l''écriture d''une autre société est refusée, la sienne est acceptée (clé composite)',
      refuse AND accepte,
      format('fuite refusée = %s, pointage accepté = %s', refuse, accepte));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T02', 'matched_line_id : l''écriture d''une autre société est refusée, la sienne est acceptée (clé composite)', false, SQLERRM);
  END;
END $$;

-- ── T03 — provider_transaction_id : rejouer une synchronisation ne double pas ──
DO $$
DECLARE t uuid; a1 uuid; a2 uuid; refuse boolean := false; autre_compte boolean := false;
BEGIN
  t := _mk_tenant('EF257T03', false);
  PERFORM _as_user();
  BEGIN
    INSERT INTO bank_accounts (tenant_id, name, type) VALUES (t, 'Compte A', 'chequing') RETURNING id INTO a1;
    INSERT INTO bank_accounts (tenant_id, name, type) VALUES (t, 'Compte B', 'chequing') RETURNING id INTO a2;

    INSERT INTO bank_transactions (tenant_id, account_id, date, description, type, amount, source, provider_transaction_id)
    VALUES (t, a1, CURRENT_DATE, 'VIR 1', 'credit', 10, 'gocardless', 'GC-1');

    -- même identifiant, même compte → refusé
    BEGIN
      INSERT INTO bank_transactions (tenant_id, account_id, date, description, type, amount, source, provider_transaction_id)
      VALUES (t, a1, CURRENT_DATE, 'VIR 1 bis', 'credit', 10, 'gocardless', 'GC-1');
    EXCEPTION WHEN unique_violation THEN refuse := true; END;

    -- même identifiant, autre compte → accepté (deux comptes, deux relevés)
    INSERT INTO bank_transactions (tenant_id, account_id, date, description, type, amount, source, provider_transaction_id)
    VALUES (t, a2, CURRENT_DATE, 'VIR 1', 'credit', 10, 'gocardless', 'GC-1');
    autre_compte := true;

    PERFORM _rec('T03',
      'provider_transaction_id : le même identifiant sur le même compte est refusé, sur un autre compte il passe',
      refuse AND autre_compte,
      format('doublon refusé = %s, autre compte accepté = %s', refuse, autre_compte));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T03', 'provider_transaction_id : le même identifiant sur le même compte est refusé, sur un autre compte il passe', false, SQLERRM);
  END;
END $$;

-- ── T04 — collection_reminders : la relance dit quand, combien, et si elle est partie ──
DO $$
DECLARE t uuid; c uuid; inv uuid; v_id uuid;
        l4 boolean := true; l5 boolean := false; envoi boolean := true; mensonge boolean := false;
BEGIN
  t := _mk_tenant('EF257T04', false);
  PERFORM _as_user();
  BEGIN
    INSERT INTO customers (tenant_id, name) VALUES (t, 'Client 257') RETURNING id INTO c;
    INSERT INTO invoices (tenant_id, number, customer_id, date, due_date, status, total, amount_due)
    VALUES (t, 'F-257-1', c, CURRENT_DATE, CURRENT_DATE, 'sent', 100, 100) RETURNING id INTO inv;

    -- niveau 4 (« procédure de recouvrement ») : la table le refusait jusqu'ici
    BEGIN
      INSERT INTO collection_reminders (tenant_id, number, invoice_id, customer_id, reminder_level,
        amount, status, days_overdue, sent_at, email_sent)
      VALUES (t, 'REL-257-4', inv, c, 4, 100, 'pending', 65, NULL, false) RETURNING id INTO v_id;
    EXCEPTION WHEN OTHERS THEN l4 := false; END;

    BEGIN
      INSERT INTO collection_reminders (tenant_id, number, invoice_id, customer_id, reminder_level, amount, status)
      VALUES (t, 'REL-257-5', inv, c, 5, 100, 'sent');
    EXCEPTION WHEN check_violation THEN l5 := true; END;

    -- « envoyée » = une heure réelle et le drapeau
    BEGIN
      UPDATE collection_reminders SET status = 'sent', sent_at = now(), email_sent = true WHERE id = v_id;
    EXCEPTION WHEN OTHERS THEN envoi := false; END;

    -- « envoyée » sans heure : refusé (invariant de la 257)
    BEGIN
      UPDATE collection_reminders SET email_sent = true, sent_at = NULL WHERE id = v_id;
    EXCEPTION WHEN check_violation THEN mensonge := true; END;

    PERFORM _rec('T04',
      'collection_reminders : niveau 4 accepté, niveau 5 refusé, « envoyée » exige une heure réelle',
      l4 AND l5 AND envoi AND mensonge,
      format('niveau 4 = %s, niveau 5 refusé = %s, envoi horodaté = %s, envoi sans heure refusé = %s',
             l4, l5, envoi, mensonge));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T04', 'collection_reminders : niveau 4 accepté, niveau 5 refusé, « envoyée » exige une heure réelle', false, SQLERRM);
  END;
END $$;

-- ── T05 — notification_email_queue.metadata : le contexte voyage avec la notification ──
DO $$
DECLARE t uuid; v_ctx jsonb; ok boolean;
BEGIN
  t := _mk_tenant('EF257T05', false);
  PERFORM _as_user();
  BEGIN
    INSERT INTO notification_email_queue (tenant_id, recipient_email, notification_type, subject, status, metadata)
    VALUES (t, 'client@audit.test', 'payment_failed', 'Échec de paiement', 'pending',
            jsonb_build_object('invoice_number', 'F-257-1', 'stripe_payment_intent_id', 'pi_123', 'error', 'card_declined'));
    SELECT metadata INTO v_ctx FROM notification_email_queue WHERE tenant_id = t LIMIT 1;
    ok := (v_ctx ->> 'invoice_number' = 'F-257-1' AND v_ctx ->> 'error' = 'card_declined');
    PERFORM _rec('T05', 'notification_email_queue.metadata : le numéro de facture et l''erreur Stripe sont conservés',
      ok, format('metadata relu = %s', v_ctx));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T05', 'notification_email_queue.metadata : le numéro de facture et l''erreur Stripe sont conservés', false, SQLERRM);
  END;
END $$;

-- ── T06 — electronic_signatures : la demande de signature est enregistrable ──
DO $$
DECLARE t uuid; v_id uuid; sans_document boolean := false; doublon boolean := false;
        v_status text; v_signers jsonb;
BEGIN
  t := _mk_tenant('EF257T06', false);
  PERFORM _as_user();
  BEGIN
    INSERT INTO electronic_signatures (tenant_id, document_type, document_id, signer_name, signer_email,
      provider, provider_signature_id, status, signers, initiated_at)
    VALUES (t, 'invoice', gen_random_uuid(), 'Dupont Jean', 'j@audit.test',
      'yousign', 'YSN-1', 'pending', '[{"first_name":"Jean","last_name":"Dupont","email":"j@audit.test"}]'::jsonb, now())
    RETURNING id INTO v_id;

    SELECT status, signers INTO v_status, v_signers FROM electronic_signatures WHERE id = v_id;

    -- `document_type` est NOT NULL : c'est CE QUI manquait au code de la fonction
    -- (il ne l'écrivait pas) — la colonne ajoutée ne suffisait pas.
    BEGIN
      INSERT INTO electronic_signatures (tenant_id, document_id, signer_name)
      VALUES (t, gen_random_uuid(), 'Sans type');
    EXCEPTION WHEN not_null_violation THEN sans_document := true; END;

    -- même procédure prestataire enregistrée deux fois → refusé
    BEGIN
      INSERT INTO electronic_signatures (tenant_id, document_type, document_id, signer_name, provider, provider_signature_id, status)
      VALUES (t, 'invoice', gen_random_uuid(), 'Dupont Jean', 'yousign', 'YSN-1', 'pending');
    EXCEPTION WHEN unique_violation THEN doublon := true; END;

    PERFORM _rec('T06',
      'electronic_signatures : la demande Yousign s''enregistre (statut, signataires), sans type elle est refusée, la même procédure ne s''enregistre pas deux fois',
      v_status = 'pending' AND jsonb_array_length(v_signers) = 1 AND sans_document AND doublon,
      format('statut = %s, signataires = %s, sans document_type refusé = %s, doublon refusé = %s',
             v_status, jsonb_array_length(v_signers), sans_document, doublon));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T06', 'electronic_signatures : la demande Yousign s''enregistre (statut, signataires), sans type elle est refusée, la même procédure ne s''enregistre pas deux fois', false, SQLERRM);
  END;
END $$;

-- ── T07 — invoices.e_invoice_* : le dépôt laisse une trace, et le double envoi se voit ──
DO $$
DECLARE t uuid; c uuid; inv uuid; doublon boolean := false; v record;
BEGIN
  t := _mk_tenant('EF257T07', false);
  -- Le contexte est posé, mais SANS passer sous le rôle d'un client : la 259
  -- refuse précisément, à un client, l'écriture de `e_invoice_status`. Ici on
  -- mesure la colonne et sa garantie, pas la porte (c'est le T02 de la 259).
  PERFORM _ctx257(t);
  BEGIN
    INSERT INTO customers (tenant_id, name) VALUES (t, 'Client 257-7') RETURNING id INTO c;
    INSERT INTO invoices (tenant_id, number, customer_id, date, due_date, status)
    VALUES (t, 'F-257-7', c, CURRENT_DATE, CURRENT_DATE, 'sent') RETURNING id INTO inv;

    UPDATE invoices
       SET e_invoice_status = 'submitted', e_invoice_platform = 'chorus_pro',
           e_invoice_submitted_at = now(), e_invoice_id = 'CHORUS-1'
     WHERE id = inv;

    SELECT e_invoice_status, e_invoice_platform, e_invoice_submitted_at, e_invoice_id INTO v
      FROM invoices WHERE id = inv;

    -- Le même identifiant de dépôt pour la même plateforme ne peut pas être
    -- porté par deux factures : le second envoi est une erreur, pas un doublon.
    BEGIN
      INSERT INTO invoices (tenant_id, number, customer_id, date, due_date, status,
        e_invoice_status, e_invoice_platform, e_invoice_id)
      VALUES (t, 'F-257-8', c, CURRENT_DATE, CURRENT_DATE, 'sent',
        'submitted', 'chorus_pro', 'CHORUS-1');
    EXCEPTION WHEN unique_violation THEN doublon := true; END;

    PERFORM _rec('T07',
      'invoices.e_invoice_* : le dépôt est tracé (statut, plateforme, heure, identifiant) et ne peut pas l''être deux fois pour le même identifiant',
      v.e_invoice_status = 'submitted' AND v.e_invoice_submitted_at IS NOT NULL
        AND v.e_invoice_id = 'CHORUS-1' AND doublon,
      format('statut = %s, déposé à = %s, id = %s, doublon refusé = %s',
             v.e_invoice_status, v.e_invoice_submitted_at, v.e_invoice_id, doublon));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('T07', 'invoices.e_invoice_* : le dépôt est tracé (statut, plateforme, heure, identifiant) et ne peut pas l''être deux fois pour le même identifiant', false, SQLERRM);
  END;
END $$;

-- ── T08 — après alignement, les colonnes écrites par les fonctions existent ──
DO $$
DECLARE ok boolean;
BEGIN
  ok := _a_col('webhook_delivery_logs', 'response_code')        -- http_status → response_code
    AND _a_col('webhook_delivery_queue', 'next_attempt_at')     -- next_retry_at → next_attempt_at
    AND _a_col('bank_connections', 'provider_connection_id')    -- provider_requisition_id → provider_connection_id
    AND _a_col('bank_connections', 'metadata')                  -- link_url / user_id → metadata
    AND _a_col('invoices', 'e_invoice_id')
    AND _a_col('electronic_signatures', 'provider_signature_id')
    AND _a_col('collection_reminders', 'days_overdue')
    AND _a_col('notification_email_queue', 'metadata')
    AND _a_col('leave_requests', 'manager_comment')
    AND _a_col('bank_transactions', 'matched_line_id');

  PERFORM _rec('T08',
    'toutes les colonnes que les fonctions Edge et les écrans écrivent après alignement existent en base',
    ok, 'les 10 colonnes sont présentes');
END $$;

SELECT _audit_assert('257');
