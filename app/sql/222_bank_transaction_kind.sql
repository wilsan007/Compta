-- ============================================================
-- 222_bank_transaction_kind.sql — R-07 : un sens unique, une seule fois compté
--
-- Constat, mesuré dans le code : `bank_transactions` porte DEUX natures de lignes
-- sans le dire — le reflet des règlements saisis (`source = customer_payment` /
-- `supplier_payment`) et les lignes de relevé (`import`, `manual`, …). Le concept
-- n'existait qu'en creux, dans `is_statement_line(source)` (196), et chacun
-- pouvait le redéfinir. Conséquences :
--   * `update_bank_balance_on_transaction` (90) ajoutait TOUTE ligne au
--     `calculated_balance`, quelle que soit sa nature : une opération enregistrée
--     comme règlement PUIS importée du relevé était comptée deux fois ;
--   * le trigger était `AFTER INSERT` seulement : supprimer ou déplacer une ligne
--     laissait le solde faux pour toujours ;
--   * la source par défaut (« manual ») ne disait pas si l'on parlait d'une
--     saisie comptable ou d'une ligne de relevé.
--
-- Correctif :
--   1. `kind` ∈ {book, statement}, non nul, défaut `statement` — tout ce qui n'est
--      pas un reflet de règlement est une ligne de relevé, ce que faisait déjà
--      `is_statement_line` ; reprise des lignes existantes par leur source ;
--   2. le solde `calculated_balance` est celui des **mouvements de trésorerie
--      saisis** (`kind = 'book'`) : une seule ligne par règlement, donc plus de
--      double comptage quand le relevé contient la même opération. Le solde
--      COMPTABLE du 512x reste lu du journal par l'état de rapprochement (196) —
--      deux notions distinctes, jamais confondues ;
--   3. le solde est RECALCULÉ (et non incrémenté) à chaque insertion, mise à jour
--      ou suppression, sur le compte concerné — et sur l'ancien compte si la ligne
--      change de compte : un incrément ne se rattrape pas, un recalcul si ;
--   4. les deux portes d'entrée écrivent leur nature explicitement : les reflets
--      de règlement (`create_bank_tx_on_*_payment`, 90) en `book`, l'import du
--      relevé et la saisie manuelle en `statement` ;
--   5. `statement_line_ledger_match` et `auto_reconcile_by_score` (196) testent
--      `NEW.kind` au lieu de deviner la nature depuis la source.
--
-- Preuve : sql/222_bank_transaction_kind_tests.sql (G12a à G12e), vu rouge avant.
-- ============================================================

-- ------------------------------------------------------------
-- 1. La nature de la ligne, explicite et contrainte
-- ------------------------------------------------------------
ALTER TABLE bank_transactions ADD COLUMN IF NOT EXISTS kind text;

-- Reprise par la source : c'est la seule information dont on dispose pour les
-- lignes existantes, et c'est exactement la règle que `is_statement_line` codait.
UPDATE bank_transactions
   SET kind = CASE WHEN source IN ('customer_payment', 'supplier_payment') THEN 'book' ELSE 'statement' END
 WHERE kind IS NULL;

ALTER TABLE bank_transactions ALTER COLUMN kind SET DEFAULT 'statement';
ALTER TABLE bank_transactions ALTER COLUMN kind SET NOT NULL;

DO $$ BEGIN
  ALTER TABLE bank_transactions ADD CONSTRAINT bank_transactions_kind_check
    CHECK (kind IN ('book', 'statement'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

COMMENT ON COLUMN bank_transactions.kind IS
  'Nature de la ligne : "book" = mouvement de trésorerie saisi (reflet d''un '
  'règlement), "statement" = ligne du relevé bancaire. Seul "book" alimente '
  'calculated_balance : une opération saisie puis importée du relevé est comptée '
  'une fois (R-07, 222).';

COMMENT ON COLUMN bank_accounts.calculated_balance IS
  'Solde des mouvements de trésorerie SAISIS (bank_transactions.kind = ''book''), '
  'recalculé à chaque changement. Ce n''est pas le solde comptable du 512x, que '
  'lit l''état de rapprochement depuis le journal (R-07, 222).';

-- ------------------------------------------------------------
-- 2. La nature d'une ligne, lisible sans deviner
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION is_statement_row(p_kind text)
RETURNS boolean
LANGUAGE sql IMMUTABLE
AS $$ SELECT COALESCE(p_kind, 'statement') = 'statement' $$;

COMMENT ON FUNCTION is_statement_row(text) IS
  'Vrai pour une ligne de relevé (kind = statement). Remplace is_statement_line, '
  'qui déduisait la nature de la source (R-07, 222).';

-- L'ancienne fonction déduisait la nature de la source : la colonne `kind` la
-- remplace partout, on ne la garde pas de peur que deux définitions coexistent.
DROP FUNCTION IF EXISTS is_statement_line(text);

-- ------------------------------------------------------------
-- 3. Les deux portes d'entrée écrivent leur nature
--    (les reflets de règlement sont des mouvements saisis, pas des lignes de relevé)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION create_bank_tx_on_customer_payment()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.bank_account_id IS NOT NULL THEN
    INSERT INTO bank_transactions (tenant_id, account_id, date, description, reference, type, amount,
                                   reconciled, matched, invoice_id, source, kind)
    VALUES (NEW.tenant_id, NEW.bank_account_id, NEW.payment_date, 'Encaissement ' || NEW.number,
            NEW.reference, 'credit', NEW.amount, false, false, NEW.invoice_id, 'customer_payment', 'book');
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS create_bank_tx_on_customer_payment ON customer_payments;
CREATE TRIGGER create_bank_tx_on_customer_payment AFTER INSERT ON customer_payments FOR EACH ROW EXECUTE FUNCTION create_bank_tx_on_customer_payment();

CREATE OR REPLACE FUNCTION create_bank_tx_on_supplier_payment()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.bank_account_id IS NOT NULL THEN
    INSERT INTO bank_transactions (tenant_id, account_id, date, description, reference, type, amount,
                                   reconciled, matched, purchase_invoice_id, source, kind)
    VALUES (NEW.tenant_id, NEW.bank_account_id, NEW.payment_date, 'Décaissement ' || NEW.number,
            NEW.reference, 'debit', NEW.amount, false, false, NEW.purchase_invoice_id, 'supplier_payment', 'book');
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS create_bank_tx_on_supplier_payment ON supplier_payments;
CREATE TRIGGER create_bank_tx_on_supplier_payment AFTER INSERT ON supplier_payments FOR EACH ROW EXECUTE FUNCTION create_bank_tx_on_supplier_payment();

-- ------------------------------------------------------------
-- 4. Le solde suit les mouvements SAISIS, et il est RECALCULÉ
--
-- `bank_accounts` est sous FORCE ROW LEVEL SECURITY chez l'hébergeur : la
-- fonction s'exécute donc dans le contexte de la requête (comme la 218 l'a
-- montré pour les migrations). Dans un appel d'application, les politiques
-- laissent passer la société courante ; la reprise ci-dessous pose le contexte.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION refresh_bank_account_balance(p_account uuid)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  UPDATE bank_accounts ba
     SET calculated_balance = COALESCE((
           SELECT sum(CASE WHEN bt.type = 'credit' THEN bt.amount ELSE -bt.amount END)
           FROM bank_transactions bt
           WHERE bt.tenant_id = ba.tenant_id
             AND COALESCE(bt.bank_account_id, bt.account_id) = ba.id
             AND bt.kind = 'book'
         ), 0),
         updated_at = now()
   WHERE ba.id = p_account
$$;
REVOKE ALL ON FUNCTION refresh_bank_account_balance(uuid) FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION refresh_bank_account_balance(uuid) IS
  'Recalcule calculated_balance d''un compte : somme des mouvements de trésorerie '
  'saisis (kind = book). Un recalcul, jamais un incrément — c''est ce qui permet de '
  'rattraper une suppression (R-07, 222).';

CREATE OR REPLACE FUNCTION update_bank_balance_on_transaction()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  v_new_acc uuid;
  v_old_acc uuid;
BEGIN
  IF TG_OP <> 'INSERT' THEN
    v_old_acc := COALESCE(OLD.bank_account_id, OLD.account_id);
  END IF;
  IF TG_OP <> 'DELETE' THEN
    v_new_acc := COALESCE(NEW.bank_account_id, NEW.account_id);
  END IF;

  IF v_new_acc IS NOT NULL THEN
    PERFORM refresh_bank_account_balance(v_new_acc);
  END IF;
  -- Une ligne qui change de compte laisse un solde faux derrière elle
  IF v_old_acc IS NOT NULL AND v_old_acc IS DISTINCT FROM v_new_acc THEN
    PERFORM refresh_bank_account_balance(v_old_acc);
  END IF;

  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$;

DROP TRIGGER IF EXISTS update_bank_balance ON bank_transactions;
CREATE TRIGGER update_bank_balance
  AFTER INSERT OR UPDATE OR DELETE ON bank_transactions
  FOR EACH ROW EXECUTE FUNCTION update_bank_balance_on_transaction();

-- ------------------------------------------------------------
-- 5. Reprise des soldes existants (le solde était faux dès qu'une opération
--    saisie avait aussi été importée, ou qu'une ligne avait été supprimée).
--    Contexte de société posé société par société — sous FORCE RLS, une
--    migration sans contexte ne verrait aucune ligne (leçon de la 218).
-- ------------------------------------------------------------
DO $$
DECLARE r record; n int := 0;
BEGIN
  FOR r IN SELECT id, tenant_id FROM bank_accounts ORDER BY tenant_id, id LOOP
    PERFORM set_config('app.active_tenant_id', r.tenant_id::text, true);
    PERFORM refresh_bank_account_balance(r.id);
    n := n + 1;
  END LOOP;
  PERFORM set_config('app.active_tenant_id', '', true);
  RAISE NOTICE '222 : % solde(s) de compte bancaire recalculé(s)', n;
END $$;

-- ------------------------------------------------------------
-- 6. Le pointage et le rapprochement par score testent la NATURE, plus la source
--    (196 testait `is_statement_line(NEW.source)` : la même règle, mais déduite)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION statement_line_ledger_match()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_acc text; v_line record; v_already uuid;
BEGIN
  IF NOT is_statement_row(NEW.kind) OR COALESCE(NEW.amount, 0) = 0 THEN RETURN NULL; END IF;
  SELECT reconciled_entry_id INTO v_already FROM bank_transactions WHERE id = NEW.id;
  IF v_already IS NOT NULL THEN RETURN NULL; END IF;

  SELECT account_code INTO v_acc FROM bank_accounts
  WHERE id = COALESCE(NEW.bank_account_id, NEW.account_id) AND tenant_id = NEW.tenant_id;
  IF v_acc IS NULL THEN RETURN NULL; END IF;

  SELECT jl.id, jl.journal_id INTO v_line
  FROM journal_lines jl
  JOIN journal_entries je ON je.id = jl.journal_id
  WHERE jl.tenant_id = NEW.tenant_id AND jl.account_code = v_acc AND je.status = 'posted'
    AND NOT COALESCE(jl.reconciled, false)
    AND CASE WHEN NEW.type = 'credit' THEN jl.debit ELSE jl.credit END = NEW.amount
    AND je.date BETWEEN NEW.date - 15 AND NEW.date + 5
  ORDER BY abs(je.date - NEW.date), je.date, jl.id
  LIMIT 1
  FOR UPDATE OF jl SKIP LOCKED;
  IF NOT FOUND THEN RETURN NULL; END IF;

  UPDATE journal_lines SET reconciled = true WHERE id = v_line.id;
  UPDATE bank_transactions
     SET matched = true, reconciled = true, reconciled_entry_id = v_line.journal_id,
         reconciled_at = now(), matched_account_code = v_acc, match_type = 'ledger_auto'
   WHERE id = NEW.id;
  RETURN NULL;
END $$;

CREATE OR REPLACE FUNCTION public.auto_reconcile_by_score()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_invoice record;
  v_best_score int := 0;
  v_best record;
BEGIN
  IF NEW.matched = true OR NOT is_statement_row(NEW.kind) OR NEW.type IS DISTINCT FROM 'credit'
     OR COALESCE(NEW.amount, 0) <= 0 THEN
    RETURN NEW;
  END IF;

  FOR v_invoice IN
    SELECT i.id, i.customer_id, i.amount_due,
      (CASE WHEN ABS(i.amount_due - NEW.amount) < 0.01              THEN 50 ELSE 0 END
     + CASE WHEN NEW.description ILIKE '%' || i.number || '%'       THEN 40 ELSE 0 END
     + CASE WHEN NULLIF(NEW.reference, '') IS NOT NULL
            AND NEW.reference = i.number                            THEN 40 ELSE 0 END
     + CASE WHEN c.name IS NOT NULL AND NEW.description ILIKE '%' || c.name || '%' THEN 20 ELSE 0 END
     + CASE WHEN i.due_date BETWEEN NEW.date - 30 AND NEW.date + 30 THEN 10 ELSE 0 END
      ) AS score
    FROM invoices i
    LEFT JOIN customers c ON c.id = i.customer_id AND c.tenant_id = i.tenant_id
    WHERE i.tenant_id = NEW.tenant_id AND i.validation_status = 'validated'
      AND i.payment_state IN ('not_paid', 'partial') AND i.amount_due > 0
    ORDER BY 4 DESC, i.due_date, i.id
    LIMIT 5
  LOOP
    IF v_invoice.score >= 70 AND v_invoice.score > v_best_score THEN
      v_best_score := v_invoice.score;
      v_best := v_invoice;
    ELSIF v_invoice.score >= 40 AND v_invoice.score < 70 THEN
      INSERT INTO bank_reconciliation_suggestions (tenant_id, bank_transaction_id, invoice_id, customer_id,
        score, match_type, matched_amount, status)
      VALUES (NEW.tenant_id, NEW.id, v_invoice.id, v_invoice.customer_id, v_invoice.score, 'suggestion',
        v_invoice.amount_due, 'pending');
    END IF;
  END LOOP;

  IF v_best_score > 0 THEN
    INSERT INTO customer_payments (tenant_id, number, customer_id, invoice_id, payment_date, amount, method,
                                   bank_account_id, reference, status)
    VALUES (NEW.tenant_id, 'REG-REL-' || upper(left(replace(NEW.id::text, '-', ''), 10)), v_best.customer_id,
            v_best.id, NEW.date, NEW.amount, 'transfer', COALESCE(NEW.bank_account_id, NEW.account_id),
            NEW.reference, 'recorded');
    UPDATE bank_transactions SET matched = true, invoice_id = v_best.id, matched_invoice_id = v_best.id
    WHERE id = NEW.id;
    INSERT INTO bank_reconciliation_suggestions (tenant_id, bank_transaction_id, invoice_id, customer_id,
      score, match_type, matched_amount, status)
    VALUES (NEW.tenant_id, NEW.id, v_best.id, v_best.customer_id, v_best_score, 'auto', NEW.amount, 'accepted');
  END IF;
  RETURN NEW;
END $$;

-- ------------------------------------------------------------
-- 7. L'état de rapprochement testait la nature par la source : il la lit
--    maintenant dans la colonne. (R-09 réécrira ce que l'état MONTRE ; ici seule
--    la façon de reconnaître une ligne de relevé change.)
-- ------------------------------------------------------------
DROP FUNCTION IF EXISTS get_bank_reconciliation_state(uuid, date);
CREATE FUNCTION get_bank_reconciliation_state(p_bank_account_id uuid, p_date date)
RETURNS TABLE (
  bank_account_id uuid,
  account_code text,
  statement_balance numeric,
  accounting_balance numeric,
  unmatched_debits numeric,
  unmatched_credits numeric,
  ledger_unmatched_debits numeric,
  ledger_unmatched_credits numeric,
  is_balanced boolean,
  unmatched_transactions json
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_acc text;
  v_stmt numeric; v_book numeric;
  v_ud numeric; v_uc numeric; v_ld numeric; v_lc numeric;
BEGIN
  SELECT ba.account_code INTO v_acc FROM bank_accounts ba WHERE ba.id = p_bank_account_id AND ba.tenant_id = v_tid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Compte bancaire introuvable' USING ERRCODE = 'no_data_found';
  END IF;

  SELECT COALESCE(sum(CASE WHEN bt.type = 'credit' THEN bt.amount ELSE -bt.amount END), 0),
         COALESCE(sum(bt.amount) FILTER (WHERE bt.type = 'debit' AND bt.reconciled_entry_id IS NULL), 0),
         COALESCE(sum(bt.amount) FILTER (WHERE bt.type = 'credit' AND bt.reconciled_entry_id IS NULL), 0)
    INTO v_stmt, v_ud, v_uc
  FROM bank_transactions bt
  WHERE bt.tenant_id = v_tid AND COALESCE(bt.bank_account_id, bt.account_id) = p_bank_account_id
    AND bt.date <= p_date AND bt.kind = 'statement';

  SELECT COALESCE(sum(jl.debit - jl.credit), 0),
         COALESCE(sum(jl.debit) FILTER (WHERE NOT COALESCE(jl.reconciled, false)), 0),
         COALESCE(sum(jl.credit) FILTER (WHERE NOT COALESCE(jl.reconciled, false)), 0)
    INTO v_book, v_ld, v_lc
  FROM journal_lines jl
  JOIN journal_entries je ON je.id = jl.journal_id
  WHERE jl.tenant_id = v_tid AND jl.account_code = v_acc AND je.status = 'posted' AND je.date <= p_date;

  RETURN QUERY SELECT
    p_bank_account_id, v_acc, v_stmt, v_book, v_ud, v_uc, v_ld, v_lc,
    (v_stmt - v_uc + v_ud) = (v_book - v_ld + v_lc),
    (SELECT COALESCE(json_agg(row_to_json(x) ORDER BY x.date DESC), '[]'::json) FROM (
       SELECT bt.id, bt.date, bt.description AS label,
              CASE WHEN bt.type = 'credit' THEN bt.amount ELSE -bt.amount END AS amount, bt.reference
       FROM bank_transactions bt
       WHERE bt.tenant_id = v_tid AND COALESCE(bt.bank_account_id, bt.account_id) = p_bank_account_id
         AND bt.date <= p_date AND bt.kind = 'statement' AND bt.reconciled_entry_id IS NULL
    ) x);
END $$;
REVOKE ALL ON FUNCTION get_bank_reconciliation_state(uuid, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_bank_reconciliation_state(uuid, date) TO authenticated;