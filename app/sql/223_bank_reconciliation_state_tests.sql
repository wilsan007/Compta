-- ============================================================
-- 223_bank_reconciliation_state_tests.sql — R-09 : l'écran d'état de rapprochement
--
-- Avant la 223 :
--   * `get_bank_reconciliation_state` n'exposait PAS les écarts du compte 512x
--     (`ledger_unmatched_transactions`, `ledger_unmatched_count`), ni les pointages
--     effectués, ni `is_reconciled`, ni la comparaison au solde de clôture du relevé
--     (`statement_closing_balance`, `closing_date`, `closing_difference`,
--     `closing_matches`) : l'écran n'avait rien à montrer d'utile ;
--   * le pointage de l'écran (drapeaux `reconciled`/`matched` du seul côté relevé)
--     ne changeait RIEN à l'état : les deux écarts restaient ;
--   * `reconcile_bank_statement_line`, `unreconcile_bank_statement_line` et
--     `post_bank_statement_line` n'existaient pas.
--
-- Scénarios :
-- R09a — les écarts des DEUX côtés sont exposés (relevé et compte 512x)
-- R09b — le drapeau d'un seul côté ne pointe rien ; la RPC pointe les deux côtés
-- R09c — le pointage refuse ce qui n'est pas une paire juste (montant, sens, statut, déjà pointé)
-- R09d — le dépointage rouvre les deux côtés
-- R09e — « Comptabiliser » un débit : D 627000 / C 512x, pointé, idempotent
-- R09f — « Comptabiliser » un crédit : D 512x / C 768000
-- R09g — le solde de clôture du relevé est comparé aux lignes importées
-- R09h — `is_balanced` (intégrité) n'est pas `is_reconciled` (l'état)
-- R09i — un lecteur ne pointe ni ne comptabilise (la lecture, elle, reste ouverte)
-- R09j — le pointage manuel ne franchit pas la société (isolation)
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '223', false);
DELETE FROM _audit_results WHERE file = '223';

-- Société + compte bancaire 512000
CREATE OR REPLACE FUNCTION _banque223(p_name text, OUT t uuid, OUT b uuid, OUT acc text)
LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'RESET ROLE';
  t := _mk_tenant(p_name);
  PERFORM _as_user();
  INSERT INTO bank_accounts (tenant_id, name, type, account_code, currency, balance)
  VALUES (t, 'Compte ' || p_name, 'chequing', '512000', 'EUR', 0) RETURNING id INTO b;
  acc := '512000';
END $$;

-- Écriture validée : [{"a":compte,"d":débit,"c":crédit}]
CREATE OR REPLACE FUNCTION _ecriture223(p_t uuid, p_num text, p_date date, p_lines jsonb)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE e uuid;
BEGIN
  INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description)
  VALUES (p_t, p_num, p_date, 'OD', 'draft', p_num) RETURNING id INTO e;
  INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_name, debit, credit, description)
  SELECT p_t, e, x->>'a', x->>'a', COALESCE((x->>'d')::numeric, 0), COALESCE((x->>'c')::numeric, 0), p_num
  FROM jsonb_array_elements(p_lines) x;
  UPDATE journal_entries SET status = 'posted' WHERE id = e;
  RETURN e;
END $$;

-- Ligne de relevé telle que l'import l'enregistre
CREATE OR REPLACE FUNCTION _releve223(p_t uuid, p_b uuid, p_date date, p_label text, p_type text, p_amount numeric)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE tx uuid;
BEGIN
  INSERT INTO bank_transactions (tenant_id, account_id, bank_account_id, date, description, type, amount, source)
  VALUES (p_t, p_b, p_b, p_date, p_label, p_type, p_amount, 'import') RETURNING id INTO tx;
  RETURN tx;
END $$;

-- Message du refus (ou '(aucun refus)' si l'appel passe)
CREATE OR REPLACE FUNCTION _err223(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE p_sql;
  RETURN '(aucun refus)';
EXCEPTION WHEN OTHERS THEN RETURN SQLERRM;
END $$;

-- Un utilisateur du rôle demandé, avec le contexte PostgREST comme _mk_tenant
CREATE OR REPLACE FUNCTION _as_role223(p_t uuid, p_role text, p_label text DEFAULT 'Utilisateur')
RETURNS void LANGUAGE plpgsql AS $$
DECLARE a uuid := uuid_generate_v4();
BEGIN
  EXECUTE 'RESET ROLE';
  INSERT INTO auth.users (id, email) VALUES (a, p_role || '-' || a || '@audit.test');
  INSERT INTO tenant_users (tenant_id, auth_id, email, name, role, status, created_at)
  VALUES (p_t, a, p_role || '-' || a || '@audit.test', p_label, p_role, 'active', now());
  PERFORM set_config('request.jwt.claim.sub', a::text, false);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', a, 'role', 'authenticated', 'email', p_role || '@audit.test')::text, false);
  PERFORM set_config('app.active_tenant_id', p_t::text, false);
  PERFORM _as_user();
END $$;

-- R09a — les écarts des DEUX côtés sont exposés
DO $$
DECLARE t uuid; b uuid; acc text; st record;
BEGIN
  BEGIN
    SELECT * INTO t, b, acc FROM _banque223('R223a');
    PERFORM _as_user();
    -- un chèque émis (écriture validée) qui n'est pas encore au relevé
    PERFORM _ecriture223(t, 'CHQ-223A', '2026-03-10',
      '[{"a":"401000","d":25},{"a":"512000","c":25}]'::jsonb);
    -- des frais bancaires au relevé, sans écriture
    PERFORM _releve223(t, b, '2026-03-12', 'FRAIS TENUE DE COMPTE', 'debit', 3);
    SELECT * INTO st FROM get_bank_reconciliation_state(b, '2026-03-31');
    PERFORM _rec('R09a', 'l''état donne les écarts des DEUX côtés : 1 ligne de relevé (3) et 1 écriture du compte (25)',
      st.unmatched_count = 1 AND st.ledger_unmatched_count = 1
        AND json_array_length(st.ledger_unmatched_transactions) = 1
        AND (st.ledger_unmatched_transactions->0->>'entry_number') = 'CHQ-223A'
        AND st.unmatched_debits = 3 AND st.ledger_unmatched_credits = 25,
      format('relevé=%s / compte=%s ; écarts relevé=%s (D%s), écritures=%s (C%s)',
             st.statement_balance, st.accounting_balance, st.unmatched_count, st.unmatched_debits,
             st.ledger_unmatched_count, st.ledger_unmatched_credits));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('R09a', 'l''état donne les écarts des DEUX côtés : 1 ligne de relevé (3) et 1 écriture du compte (25)', false, SQLERRM);
  END;
END $$;

-- R09b — le drapeau d'un seul côté ne pointe rien ; la RPC pointe les DEUX côtés
-- (c'est exactement ce que faisait l'écran : updateBankTransaction({reconciled, matched}))
DO $$
DECLARE t uuid; b uuid; acc text; e uuid; jl uuid; tx uuid; st1 record; st2 record; res jsonb;
BEGIN
  BEGIN
    SELECT * INTO t, b, acc FROM _banque223('R223b');
    PERFORM _as_user();
    -- des frais déjà comptabilisés : D 627000 40 / C 512000 40
    e := _ecriture223(t, 'FRAIS-223B', '2026-01-05',
      '[{"a":"627000","d":40},{"a":"512000","c":40}]'::jsonb);
    SELECT id INTO jl FROM journal_lines WHERE journal_id = e AND account_code = acc;
    -- le relevé, 60 jours plus tard : aucune fenêtre de pointage automatique
    tx := _releve223(t, b, '2026-03-06', 'FRAIS BANCAIRES', 'debit', 40);
    -- ce que faisait l'écran : les drapeaux du seul côté relevé
    UPDATE bank_transactions SET reconciled = true, matched = true WHERE id = tx;
    SELECT * INTO st1 FROM get_bank_reconciliation_state(b, '2026-03-31');
    -- le pointage de la 223
    res := reconcile_bank_statement_line(tx, jl);
    SELECT * INTO st2 FROM get_bank_reconciliation_state(b, '2026-03-31');
    PERFORM _rec('R09b', 'le drapeau d''un seul côté laisse les 2 écarts ; la RPC pointe les deux côtés et l''état est réconcilié',
      st1.unmatched_count = 1 AND st1.ledger_unmatched_count = 1 AND NOT st1.is_reconciled
        AND st2.is_reconciled AND st2.unmatched_count = 0 AND st2.ledger_unmatched_count = 0
        AND st2.is_balanced AND (res->>'account_code') = '512000',
      format('drapeau seul : relevé=%s / compta=%s (réconcilié=%s) ; après RPC : %s / %s (réconcilié=%s, équilibré=%s)',
             st1.unmatched_count, st1.ledger_unmatched_count, st1.is_reconciled,
             st2.unmatched_count, st2.ledger_unmatched_count, st2.is_reconciled, st2.is_balanced));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('R09b', 'le drapeau d''un seul côté laisse les 2 écarts ; la RPC pointe les deux côtés et l''état est réconcilié', false, SQLERRM);
  END;
END $$;

-- R09c — le pointage refuse ce qui n'est pas une paire juste
DO $$
DECLARE t uuid; b uuid; acc text; e uuid; jl uuid; tx uuid; draft uuid; jld uuid;
        e_a uuid; jl_a uuid; tx_a uuid; tx_b uuid;
        m_sens text; m_statut text; m_releve text; m_ecriture text; res jsonb;
BEGIN
  BEGIN
    SELECT * INTO t, b, acc FROM _banque223('R223c');
    PERFORM _as_user();
    -- une écriture de 40 au DÉBIT du compte (encaissement), à distance du relevé :
-- le relevé est un débit de 40 (sortie) — montant identique, sens contraire
    e := _ecriture223(t, 'FRAIS-223C', '2026-01-05', '[{"a":"512000","d":40},{"a":"411000","c":40}]'::jsonb);
    SELECT id INTO jl FROM journal_lines WHERE journal_id = e AND account_code = acc;
    tx := _releve223(t, b, '2026-03-06', 'FRAIS 40', 'debit', 40);
    -- le relevé est un DÉBIT de 40, l'écriture un CRÉDIT de 40 : montant/sens différents
    m_sens := _err223(format('SELECT reconcile_bank_statement_line(%L::uuid, %L::uuid)', tx, jl));

    -- une écriture en brouillard ne se pointe pas
    INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description)
    VALUES (t, 'BROUILLON-223C', '2026-01-06', 'OD', 'draft', 'Brouillon') RETURNING id INTO draft;
    INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_name, debit, credit, description)
    VALUES (t, draft, '627000', '627000', 40, 0, 'Brouillon');
    INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_name, debit, credit, description)
    VALUES (t, draft, acc, acc, 0, 40, 'Brouillon') RETURNING id INTO jld;
    m_statut := _err223(format('SELECT reconcile_bank_statement_line(%L::uuid, %L::uuid)', tx, jld));

    -- une paire juste, pointée : le relevé ne se pointe pas deux fois,
    -- et l'écriture non plus
    e_a := _ecriture223(t, 'VIREMENT-223C', '2026-01-07', '[{"a":"411000","d":41},{"a":"512000","c":41}]'::jsonb);
    SELECT id INTO jl_a FROM journal_lines WHERE journal_id = e_a AND account_code = acc;
    tx_a := _releve223(t, b, '2026-03-07', 'VIREMENT 41', 'debit', 41);
    res := reconcile_bank_statement_line(tx_a, jl_a);
    m_releve := _err223(format('SELECT reconcile_bank_statement_line(%L::uuid, %L::uuid)', tx_a, jl_a));
    tx_b := _releve223(t, b, '2026-03-08', 'VIREMENT 42', 'debit', 42);
    m_ecriture := _err223(format('SELECT reconcile_bank_statement_line(%L::uuid, %L::uuid)', tx_b, jl_a));

    PERFORM _rec('R09c', 'le pointage refuse montant/sens différents, une écriture en brouillon, un relevé déjà pointé et une écriture déjà pointée',
      m_sens LIKE '%Montant ou sens différents%'
        AND m_statut LIKE '%non validée%'
        AND m_releve LIKE '%relevé déjà pointée%'
        AND m_ecriture LIKE '%écriture%déjà pointée%'
        AND (res->>'entry_number') = 'VIREMENT-223C',
      format('sens=[%s] brouillon=[%s] relevé=[%s] écriture=[%s]', m_sens, m_statut, m_releve, m_ecriture));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('R09c', 'le pointage refuse montant/sens différents, une écriture en brouillon, un relevé déjà pointé et une écriture déjà pointée', false, SQLERRM);
  END;
END $$;

-- R09d — le dépointage rouvre les deux côtés
DO $$
DECLARE t uuid; b uuid; acc text; e uuid; jl uuid; tx uuid; st record; res jsonb; v_rec uuid;
BEGIN
  BEGIN
    SELECT * INTO t, b, acc FROM _banque223('R223d');
    PERFORM _as_user();
    e := _ecriture223(t, 'VIREMENT-223D', '2026-01-07', '[{"a":"411000","d":41},{"a":"512000","c":41}]'::jsonb);
    SELECT id INTO jl FROM journal_lines WHERE journal_id = e AND account_code = acc;
    tx := _releve223(t, b, '2026-03-07', 'VIREMENT 41', 'debit', 41);
    PERFORM reconcile_bank_statement_line(tx, jl);
    res := unreconcile_bank_statement_line(tx);
    SELECT reconciled_entry_id INTO v_rec FROM bank_transactions WHERE id = tx;
    SELECT * INTO st FROM get_bank_reconciliation_state(b, '2026-03-31');
    PERFORM _rec('R09d', 'le dépointage rend la ligne de relevé ET l''écriture aux écarts',
      st.unmatched_count = 1 AND st.ledger_unmatched_count = 1 AND NOT st.is_reconciled
        AND v_rec IS NULL AND (res->>'ledger_lines_reopened')::int = 1
        AND json_array_length(st.reconciled_transactions) = 0,
      format('écarts relevé=%s / compta=%s ; écriture pointée=%s ; lignes rouvertes=%s',
             st.unmatched_count, st.ledger_unmatched_count, COALESCE(v_rec::text, '∅'),
             res->>'ledger_lines_reopened'));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('R09d', 'le dépointage rend la ligne de relevé ET l''écriture aux écarts', false, SQLERRM);
  END;
END $$;

-- R09e — « Comptabiliser » un débit : D 627000 / C 512x, validée, pointée, idempotente
DO $$
DECLARE t uuid; b uuid; acc text; tx uuid; res jsonb; st record; v_je uuid;
        v_num text; v_journal text; v_status text;
        v_debit numeric; v_credit numeric; v_counter text; m_double text; v_count int;
BEGIN
  BEGIN
    SELECT * INTO t, b, acc FROM _banque223('R223e');
    PERFORM _as_user();
    tx := _releve223(t, b, '2026-03-12', 'FRAIS TENUE DE COMPTE', 'debit', 3);
    res := post_bank_statement_line(tx);
    v_je := (res->>'journal_entry_id')::uuid;
    SELECT je.number, je.journal_code, je.status INTO v_num, v_journal, v_status
      FROM journal_entries je WHERE je.id = v_je;
    SELECT COALESCE(sum(jl.debit) FILTER (WHERE jl.account_code = '627000'), 0),
           COALESCE(sum(jl.credit) FILTER (WHERE jl.account_code = acc), 0)
      INTO v_debit, v_credit
      FROM journal_lines jl WHERE jl.journal_id = v_je;
    SELECT jl.account_code INTO v_counter FROM journal_lines jl
     WHERE jl.journal_id = v_je AND jl.account_code <> acc LIMIT 1;
    m_double := _err223(format('SELECT post_bank_statement_line(%L::uuid)', tx));
    SELECT count(*) INTO v_count FROM journal_entries WHERE tenant_id = t AND reference LIKE 'COMPTA-BQ-%';
    SELECT * INTO st FROM get_bank_reconciliation_state(b, '2026-03-31');
    PERFORM _rec('R09e', 'comptabiliser un frais crée D 627000 3 / C 512000 3 (validée), pointe la ligne et l''état se réconcilie',
      (res->>'counterpart_account') = '627000' AND v_status = 'posted' AND v_journal = 'BQ'
        AND v_debit = 3 AND v_credit = 3 AND v_counter = '627000'
        AND st.unmatched_count = 0 AND st.ledger_unmatched_count = 0 AND st.is_reconciled
        AND st.statement_balance = -3 AND st.accounting_balance = -3 AND st.difference = 0
        AND m_double LIKE '%déjà pointée%' AND v_count = 1,
      format('compte=%s écriture=%s/%s D627000=%s C512=%s ; relevé=%s compte=%s écarts %s/%s ; 2e appel=[%s] ; écritures COMPTA-BQ=%s',
             res->>'counterpart_account', v_journal, v_status, v_debit, v_credit,
             st.statement_balance, st.accounting_balance, st.unmatched_count, st.ledger_unmatched_count,
             m_double, v_count));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('R09e', 'comptabiliser un frais crée D 627000 3 / C 512000 3 (validée), pointe la ligne et l''état se réconcilie', false, SQLERRM);
  END;
END $$;

-- R09f — « Comptabiliser » un crédit : D 512x / C 768000
DO $$
DECLARE t uuid; b uuid; acc text; tx uuid; res jsonb; st record; v_je uuid;
        v_debit numeric; v_credit numeric; v_counter text;
BEGIN
  BEGIN
    SELECT * INTO t, b, acc FROM _banque223('R223f');
    PERFORM _as_user();
    tx := _releve223(t, b, '2026-03-14', 'INTERETS CREDITEURS', 'credit', 12);
    res := post_bank_statement_line(tx);
    v_je := (res->>'journal_entry_id')::uuid;
    SELECT COALESCE(sum(jl.debit) FILTER (WHERE jl.account_code = acc), 0),
           COALESCE(sum(jl.credit) FILTER (WHERE jl.account_code = '768000'), 0)
      INTO v_debit, v_credit
      FROM journal_lines jl WHERE jl.journal_id = v_je;
    SELECT jl.account_code INTO v_counter FROM journal_lines jl
     WHERE jl.journal_id = v_je AND jl.account_code <> acc LIMIT 1;
    SELECT * INTO st FROM get_bank_reconciliation_state(b, '2026-03-31');
    PERFORM _rec('R09f', 'comptabiliser un crédit crée D 512000 12 / C 768000 12 et l''état se réconcilie',
      (res->>'counterpart_account') = '768000' AND (res->>'direction') = 'in'
        AND v_debit = 12 AND v_credit = 12 AND v_counter = '768000'
        AND st.unmatched_count = 0 AND st.ledger_unmatched_count = 0 AND st.is_reconciled
        AND st.statement_balance = 12 AND st.accounting_balance = 12,
      format('compte=%s sens=%s D512=%s C768000=%s ; relevé=%s compte=%s écarts %s/%s',
             res->>'counterpart_account', res->>'direction', v_debit, v_credit,
             st.statement_balance, st.accounting_balance, st.unmatched_count, st.ledger_unmatched_count));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('R09f', 'comptabiliser un crédit crée D 512000 12 / C 768000 12 et l''état se réconcilie', false, SQLERRM);
  END;
END $$;

-- R09g — le solde de clôture du relevé est comparé aux lignes importées
DO $$
DECLARE t uuid; b uuid; acc text; st1 record; st2 record;
BEGIN
  BEGIN
    SELECT * INTO t, b, acc FROM _banque223('R223g');
    PERFORM _as_user();
    PERFORM _releve223(t, b, '2026-03-06', 'VIR 120', 'credit', 120);
    PERFORM _releve223(t, b, '2026-03-07', 'VIR 50', 'debit', 50);
    -- le relevé annonce 67 de clôture au 31/03, ses lignes en totalisent 70
    UPDATE bank_accounts SET statement_balance = 67, statement_balance_date = '2026-03-31' WHERE id = b;
    SELECT * INTO st1 FROM get_bank_reconciliation_state(b, '2026-03-31');
    UPDATE bank_accounts SET statement_balance = 70 WHERE id = b;
    SELECT * INTO st2 FROM get_bank_reconciliation_state(b, '2026-03-31');
    PERFORM _rec('R09g', 'le solde de clôture du relevé est comparé : 67 annoncés contre 70 importés (écart −3), puis 70 (juste)',
      st1.statement_closing_balance = 67 AND st1.closing_date = '2026-03-31'
        AND st1.closing_difference = -3 AND st1.closing_matches = false AND st1.statement_balance = 70
        AND st2.closing_matches AND st2.closing_difference = 0,
      format('annoncé=%s au %s ; lignes importées=%s ; écart=%s ; juste=%s → puis juste=%s',
             st1.statement_closing_balance, st1.closing_date, st1.statement_balance,
             st1.closing_difference, st1.closing_matches, st2.closing_matches));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('R09g', 'le solde de clôture du relevé est comparé : 67 annoncés contre 70 importés (écart −3), puis 70 (juste)', false, SQLERRM);
  END;
END $$;

-- R09h — `is_balanced` est un contrôle d'INTÉGRITÉ : il est vrai alors qu'un écart
-- subsiste. C'est exactement pourquoi l'écran ne doit pas s'y fier : il montre
-- `is_reconciled` et la liste des écarts.
DO $$
DECLARE t uuid; b uuid; acc text; e uuid; jl uuid; tx uuid; st record;
BEGIN
  BEGIN
    SELECT * INTO t, b, acc FROM _banque223('R223h');
    PERFORM _as_user();
    e := _ecriture223(t, 'ENC-223H', '2026-01-05', '[{"a":"512000","d":120},{"a":"411000","c":120}]'::jsonb);
    SELECT id INTO jl FROM journal_lines WHERE journal_id = e AND account_code = acc;
    tx := _releve223(t, b, '2026-03-06', 'VIR 120', 'credit', 120);
    PERFORM reconcile_bank_statement_line(tx, jl);
    PERFORM _releve223(t, b, '2026-03-12', 'FRAIS 3', 'debit', 3);
    SELECT * INTO st FROM get_bank_reconciliation_state(b, '2026-03-31');
    PERFORM _rec('R09h', 'is_balanced vaut true alors qu''il reste un écart de 3 : l''état est is_reconciled = false',
      st.is_balanced AND NOT st.is_reconciled AND st.unmatched_count = 1 AND st.unmatched_debits = 3
        AND st.difference = -3 AND st.explained_difference = -3,
      format('équilibré=%s réconcilié=%s ; écarts relevé=%s (%s) ; écart de solde=%s expliqué par les écarts=%s',
             st.is_balanced, st.is_reconciled, st.unmatched_count, st.unmatched_debits,
             st.difference, st.explained_difference));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('R09h', 'is_balanced vaut true alors qu''il reste un écart de 3 : l''état est is_reconciled = false', false, SQLERRM);
  END;
END $$;

-- R09h2 — mais l'intégrité reste vérifiée : une paire incohérente (relevé pointé
-- sur une écriture dont la ligne du compte n'est pas pointée) la fait échouer.
DO $$
DECLARE t uuid; b uuid; acc text; e uuid; tx uuid; st record;
BEGIN
  BEGIN
    SELECT * INTO t, b, acc FROM _banque223('R223h2');
    PERFORM _as_user();
    e := _ecriture223(t, 'INCT-223H2', '2026-01-05', '[{"a":"512000","d":30},{"a":"411000","c":30}]'::jsonb);
    tx := _releve223(t, b, '2026-03-20', 'VIR 30', 'debit', 30);
    -- pointage écrit à la main d'un seul côté (reprise de données) : le relevé
    -- se dit pointé, l'écriture du compte ne l'est pas
    UPDATE bank_transactions SET reconciled = true, matched = true, reconciled_entry_id = e WHERE id = tx;
    SELECT * INTO st FROM get_bank_reconciliation_state(b, '2026-03-31');
    PERFORM _rec('R09h2', 'une paire incohérente est signalée : is_balanced passe à false',
      NOT st.is_balanced AND NOT st.is_reconciled,
      format('équilibré=%s ; écart de solde=%s expliqué par les écarts=%s (écriture du compte non pointée=%s)',
             st.is_balanced, st.difference, st.explained_difference, st.ledger_unmatched_count));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('R09h2', 'une paire incohérente est signalée : is_balanced passe à false', false, SQLERRM);
  END;
END $$;

-- R09i — un lecteur lit l'état, mais ne pointe ni ne comptabilise
DO $$
DECLARE t uuid; b uuid; acc text; e uuid; jl uuid; tx uuid; st record; m_pt text; m_cp text;
BEGIN
  BEGIN
    SELECT * INTO t, b, acc FROM _banque223('R223i');
    PERFORM _as_user();
    e := _ecriture223(t, 'FRAIS-223I', '2026-01-05', '[{"a":"627000","d":3},{"a":"512000","c":3}]'::jsonb);
    SELECT id INTO jl FROM journal_lines WHERE journal_id = e AND account_code = acc;
    tx := _releve223(t, b, '2026-03-12', 'FRAIS 3', 'debit', 3);
    -- rôle « viewer »
    PERFORM _as_role223(t, 'viewer', 'Lecteur');
    SELECT * INTO st FROM get_bank_reconciliation_state(b, '2026-03-31');
    m_pt := _err223(format('SELECT reconcile_bank_statement_line(%L::uuid, %L::uuid)', tx, jl));
    m_cp := _err223(format('SELECT post_bank_statement_line(%L::uuid)', tx));
    PERFORM _rec('R09i', 'un lecteur lit l''état (2 écarts) mais ne pointe ni ne comptabilise : Permission refusée',
      m_pt LIKE '%Permission refusée%' AND m_cp LIKE '%Permission refusée%'
        AND st.unmatched_count = 1 AND st.ledger_unmatched_count = 1,
      format('pointage=[%s] comptabilisation=[%s] ; lecture : écarts %s/%s',
             m_pt, m_cp, st.unmatched_count, st.ledger_unmatched_count));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('R09i', 'un lecteur lit l''état (2 écarts) mais ne pointe ni ne comptabilise : Permission refusée', false, SQLERRM);
  END;
END $$;

-- R09j — le pointage ne franchit pas la société
DO $$
DECLARE ta uuid; ba uuid; acca text; ea uuid; jla uuid; txa uuid;
        tb uuid; bb uuid; accb text; m text;
BEGIN
  BEGIN
    SELECT * INTO ta, ba, acca FROM _banque223('R223j1');
    PERFORM _as_user();
    ea := _ecriture223(ta, 'FRAIS-223J', '2026-01-05', '[{"a":"627000","d":3},{"a":"512000","c":3}]'::jsonb);
    SELECT id INTO jla FROM journal_lines WHERE journal_id = ea AND account_code = acca;
    txa := _releve223(ta, ba, '2026-03-12', 'FRAIS 3', 'debit', 3);
    -- une autre société : ces identifiants ne lui appartiennent pas
    SELECT * INTO tb, bb, accb FROM _banque223('R223j2');
    PERFORM _as_user();
    m := _err223(format('SELECT reconcile_bank_statement_line(%L::uuid, %L::uuid)', txa, jla));
    PERFORM _rec('R09j', 'le pointage ne franchit pas la société : la ligne d''une autre société est introuvable',
      m LIKE '%Ligne de relevé introuvable%', format('refus=[%s]', m));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('R09j', 'le pointage ne franchit pas la société : la ligne d''une autre société est introuvable', false, SQLERRM);
  END;
END $$;

DROP FUNCTION _banque223(text);
DROP FUNCTION _ecriture223(uuid, text, date, jsonb);
DROP FUNCTION _releve223(uuid, uuid, date, text, text, numeric);
DROP FUNCTION _err223(text);
DROP FUNCTION _as_role223(uuid, text, text);

SELECT _audit_assert('223');