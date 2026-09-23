-- ============================================================
-- 222_bank_transaction_kind_tests.sql — R-07 : une nature explicite, un solde juste
--
-- Avant la 222, `bank_transactions` mêlait deux natures sans le dire :
--   - le reflet d'un règlement saisi (source customer_payment / supplier_payment) ;
--   - une ligne de relevé (import, manual…).
-- Le solde `calculated_balance` additionnait LES DEUX : une opération enregistrée
-- comme règlement PUIS importée du relevé était comptée deux fois. Et le trigger
-- n'était posé que sur INSERT : une suppression laissait le solde faux à vie.
--
-- G12a — le reflet d'un règlement est un mouvement saisi (kind = book)
-- G12b — la même opération importée du relevé NE double PAS le solde
-- G12c — supprimer un mouvement saisi corrige le solde (recalcul, pas incrément)
-- G12d — une ligne de relevé non pointée reste pointable à l'insertion (196)
-- G12e — le solde ne suit pas les lignes de relevé, même créditrices
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '222', false);
DELETE FROM _audit_results WHERE file = '222';

-- Société avec un compte bancaire et un client
CREATE OR REPLACE FUNCTION _banque222(p_name text, OUT t uuid, OUT acc uuid, OUT cli uuid)
LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'RESET ROLE';
  t := _mk_tenant(p_name);
  PERFORM _as_user();
  INSERT INTO bank_accounts (tenant_id, name, type, account_code, currency, balance)
  VALUES (t, 'Compte ' || p_name, 'chequing', '512000', 'EUR', 0) RETURNING id INTO acc;
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client ' || p_name) RETURNING id INTO cli;
END $$;

CREATE OR REPLACE FUNCTION _solde222(p_acc uuid)
RETURNS numeric LANGUAGE sql AS $$
  SELECT COALESCE(calculated_balance, 0) FROM bank_accounts WHERE id = p_acc
$$;

-- G12a — un règlement saisi pose un mouvement « book » et le solde le suit une fois
DO $$
DECLARE t uuid; acc uuid; cli uuid; k text; s numeric;
BEGIN
  BEGIN
    SELECT * INTO t, acc, cli FROM _banque222('B222a');
    INSERT INTO customer_payments (tenant_id, number, customer_id, payment_date, amount, method, bank_account_id, status)
    VALUES (t, 'REG-222A', cli, '2026-03-05', 120, 'transfer', acc, 'recorded');
    SELECT kind INTO k FROM bank_transactions WHERE tenant_id = t AND COALESCE(bank_account_id, account_id) = acc;
    s := _solde222(acc);
    PERFORM _rec('G12a', 'un encaissement saisi est un mouvement de trésorerie (kind = book) et le solde vaut 120',
      k = 'book' AND s = 120, format('kind=%s solde=%s', k, s));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('G12a', 'un encaissement saisi est un mouvement de trésorerie (kind = book) et le solde vaut 120', false, SQLERRM); END;
END $$;

-- G12b — LA même opération apparaît dans le relevé : le solde ne bouge pas.
-- L'insertion du relevé ne nomme pas `kind` : c'est le défaut qui s'applique,
-- comme le fait l'import réel — ainsi le rouge d'avant montre le solde doublé
-- (240) et non « colonne absente ».
DO $$
DECLARE t uuid; acc uuid; cli uuid; s numeric; n int;
BEGIN
  BEGIN
    SELECT * INTO t, acc, cli FROM _banque222('B222b');
    INSERT INTO customer_payments (tenant_id, number, customer_id, payment_date, amount, method, bank_account_id, status)
    VALUES (t, 'REG-222B', cli, '2026-03-05', 120, 'transfer', acc, 'recorded');
    PERFORM _as_user();
    -- import du relevé : la même opération, telle que le lecteur l'enregistre
    INSERT INTO bank_transactions (tenant_id, account_id, bank_account_id, date, description, type, amount, source)
    VALUES (t, acc, acc, '2026-03-06', 'VIR CLIENT B222', 'credit', 120, 'import');
    SELECT _solde222(acc) INTO s;
    SELECT count(*) INTO n FROM bank_transactions WHERE tenant_id = t AND COALESCE(bank_account_id, account_id) = acc;
    PERFORM _rec('G12b', 'la même opération saisie PUIS importée ne compte qu''une fois : solde 120 (et non 240)',
      s = 120 AND n = 2,
      format('solde=%s (240 avant la 222), lignes=%s', s, n));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('G12b', 'la même opération saisie PUIS importée ne compte qu''une fois : solde 120 (et non 240)', false, SQLERRM); END;
END $$;

-- G12c — supprimer un mouvement saisi corrige le solde. La suppression vise la
-- source du règlement, pas `kind`, pour que le rouge montre le solde figé (80).
DO $$
DECLARE t uuid; acc uuid; cli uuid; s numeric;
BEGIN
  BEGIN
    SELECT * INTO t, acc, cli FROM _banque222('B222c');
    INSERT INTO customer_payments (tenant_id, number, customer_id, payment_date, amount, method, bank_account_id, status)
    VALUES (t, 'REG-222C', cli, '2026-03-05', 80, 'transfer', acc, 'recorded');
    DELETE FROM bank_transactions WHERE tenant_id = t AND source = 'customer_payment';
    SELECT _solde222(acc) INTO s;
    PERFORM _rec('G12c', 'mouvement saisi supprimé : le solde revient à 0 (recalculé, jamais incrémenté)',
      s = 0, format('solde=%s (restait 80 avant la 222)', s));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('G12c', 'mouvement saisi supprimé : le solde revient à 0 (recalculé, jamais incrémenté)', false, SQLERRM); END;
END $$;

-- G12d — une ligne de relevé reste pointée contre une écriture du compte (196)
DO $$
DECLARE t uuid; acc uuid; cli uuid; e uuid; pt boolean;
BEGIN
  BEGIN
    EXECUTE 'RESET ROLE';   -- _banque222() laisse le rôle authenticated : les helpers exigent le propriétaire
    SELECT * INTO t, acc, cli FROM _banque222('B222d');
    EXECUTE 'RESET ROLE';
    PERFORM ensure_standard_journals(t);
    PERFORM _as_user();
    e := _entry(t, 'OD-222D', '2026-03-05', '[{"a":"512000","d":250},{"a":"707000","c":250}]'::jsonb);
    INSERT INTO bank_transactions (tenant_id, account_id, bank_account_id, date, description, type, amount, source)
    VALUES (t, acc, acc, '2026-03-06', 'Virement reçu', 'credit', 250, 'import');
    SELECT reconciled_entry_id IS NOT NULL INTO pt FROM bank_transactions
     WHERE tenant_id = t AND source = 'import' ORDER BY created_at DESC LIMIT 1;
    PERFORM _rec('G12d', 'ligne de relevé pointée contre l''écriture du compte (pointage de la 196 préservé)',
      pt, format('pointée=%s, écriture=%s', pt, COALESCE(e::text, '∅')));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('G12d', 'ligne de relevé pointée contre l''écriture du compte (pointage de la 196 préservé)', false, SQLERRM); END;
END $$;

-- G12e — une ligne de relevé créditrice ne gonfle pas le solde des mouvements saisis
DO $$
DECLARE t uuid; acc uuid; cli uuid; s numeric;
BEGIN
  BEGIN
    SELECT * INTO t, acc, cli FROM _banque222('B222e');
    PERFORM _as_user();
    INSERT INTO bank_transactions (tenant_id, account_id, bank_account_id, date, description, type, amount, source)
    VALUES (t, acc, acc, '2026-03-06', 'Virement relevé seul', 'credit', 500, 'import');
    SELECT _solde222(acc) INTO s;
    PERFORM _rec('G12e', 'une ligne de relevé ne fait pas le solde des mouvements saisis (0)',
      s = 0, format('solde=%s (500 avant la 222)', s));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('G12e', 'une ligne de relevé ne fait pas le solde des mouvements saisis (0)', false, SQLERRM); END;
END $$;

DROP FUNCTION _banque222(text);
DROP FUNCTION _solde222(uuid);

SELECT _audit_assert('222');