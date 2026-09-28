-- ============================================================
-- 277_bank_balance_from_ledger_tests.sql — vague X6 / M3 (décision D-F)
--
-- MESURÉ AVANT (chemin de l'écran) : un compte créé avec 1 000 de solde initial
-- n'avait AUCUNE écriture (S02b) ; `balance` affichée restait à 1 000 après
-- 1 357,10 d'encaissements (S06e).
--
--   T01 solde initial 1 000 → à-nouveau validé AN : 512x D 1 000 / 890000 C 1 000,
--       daté du début de l'exercice ; solde comptable = 1 000
--   T02 solde initial négatif (−200) → 512x C 200 / 890000 D 200
--   T03 un second à-nouveau sur le même compte dans l'exercice est refusé
--   T04 un encaissement validé au 512x met le solde comptable à jour ; l'écart
--       au relevé = relevé − comptable
--   T05 solde initial nul → aucune écriture
--
-- T01–T04 sont ROUGES avant la 277.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '277', false);
DELETE FROM _audit_results WHERE file = '277';

DO $$
DECLARE t uuid; b uuid; b2 uuid; code text; code2 text; e record; cb numeric; n int; err text;
BEGIN
  t := _mk_tenant('X6M3');
  PERFORM _as_user();
  INSERT INTO bank_accounts (tenant_id, name, bank_name, type, balance, currency) VALUES (t, 'Banque ouverture', 'BNP', 'chequing', 1000, 'EUR')
  RETURNING id, account_code INTO b, code;
  EXECUTE 'RESET ROLE';
  SELECT je.status, je.date, (SELECT string_agg(coalesce(account_general, account_code) || ':' || debit || '/' || credit, ' ' ORDER BY line_order)
                              FROM journal_lines WHERE journal_id = je.id) AS l
    INTO e FROM journal_entries je WHERE je.tenant_id = t AND je.journal_code = 'AN' LIMIT 1;
  SELECT calculated_balance INTO cb FROM bank_accounts WHERE id = b;
  PERFORM _rec('T01', 'solde initial 1 000 : à-nouveau validé 512x/890000 au début de l''exercice, solde comptable 1 000',
    e.status = 'posted' AND e.date = '2026-01-01' AND e.l = code || ':1000.00/0.00 890000:0.00/1000.00' AND cb = 1000,
    format('écriture=%s %s [%s] solde=%s', e.status, e.date, e.l, cb));

  PERFORM _as_user();
  INSERT INTO bank_accounts (tenant_id, name, bank_name, type, balance, currency) VALUES (t, 'Banque découverte', 'SG', 'chequing', -200, 'EUR')
  RETURNING id, account_code INTO b2, code2;
  EXECUTE 'RESET ROLE';
  SELECT (SELECT string_agg(coalesce(account_general, account_code) || ':' || debit || '/' || credit, ' ' ORDER BY line_order)
          FROM journal_lines jl JOIN journal_entries je ON je.id = jl.journal_id
          WHERE je.tenant_id = t AND je.journal_code = 'AN' AND je.reference = 'BANK-OPEN-' || b2) INTO err;
  SELECT calculated_balance INTO cb FROM bank_accounts WHERE id = b2;
  PERFORM _rec('T02', 'solde initial −200 : 512x crédit 200 / 890000 débit 200',
    err = code2 || ':0.00/200.00 890000:200.00/0.00' AND cb = -200, format('[%s] solde=%s', err, cb));

  err := NULL;
  PERFORM _as_user();
  BEGIN
    INSERT INTO bank_accounts (tenant_id, name, bank_name, type, balance, currency, account_code, journal_code)
    VALUES (t, 'Même compte', 'BNP', 'chequing', 50, 'EUR', code, 'BQ9');
    err := 'ACCEPTÉ';
  EXCEPTION WHEN OTHERS THEN err := SQLERRM;
  END;
  EXECUTE 'RESET ROLE';
  PERFORM _rec('T03', 'un second à-nouveau sur le même compte dans l''exercice est refusé', err ~ 'déjà un à-nouveau', err);

  PERFORM _entry(t, 'ENC-1', '2026-09-20', format('[{"a":"%s","d":357.10},{"a":"411000","c":357.10}]', code)::jsonb, true, 'OD');
  UPDATE bank_accounts SET statement_balance = 1400, statement_balance_date = '2026-09-30' WHERE id = b;
  PERFORM refresh_bank_account_balance(b);
  SELECT calculated_balance, reconciliation_diff INTO e FROM bank_accounts WHERE id = b;
  PERFORM _rec('T04', 'un encaissement validé met le solde comptable à jour ; écart = relevé − comptable',
    e.calculated_balance = 1357.10 AND e.reconciliation_diff = 42.90, format('comptable=%s écart=%s', e.calculated_balance, e.reconciliation_diff));

  PERFORM _as_user();
  INSERT INTO bank_accounts (tenant_id, name, bank_name, type, balance, currency) VALUES (t, 'Banque vide', 'LCL', 'chequing', 0, 'EUR') RETURNING id INTO b;
  EXECUTE 'RESET ROLE';
  SELECT count(*) INTO n FROM journal_entries WHERE tenant_id = t AND reference = 'BANK-OPEN-' || b;
  PERFORM _rec('T05', 'solde initial nul : aucune écriture', n = 0, format('%s écriture(s)', n));
END $$;

SELECT _audit_assert('277');
