-- ============================================================
-- 196_bank_reconciliation.sql — lot G du plan correctif (vague V3)
--
-- AUD-G04 — prouvé par G04 de sql/192_purchases_treasury_tests.sql.
-- get_bank_reconciliation_state était faux à trois endroits :
--   - le « compte comptable » lu était bank_accounts.account_number (le numéro
--     du compte bancaire) : le solde comptable valait toujours 0 ;
--   - le solde du relevé additionnait des montants tous positifs, débits compris ;
--   - les « débits non rapprochés » cherchaient des montants négatifs, qui n'existent pas.
-- Et aucune ligne de relevé n'était pointée contre une écriture de banque : le
-- rapprochement automatique existant associe une ligne à une FACTURE (par montant).
--
-- Correctif :
--   - une ligne de relevé (toute ligne qui n'est pas le reflet d'un règlement saisi)
--     est pointée à l'insertion contre une ligne non pointée du compte de
--     trésorerie du compte bancaire (190), de même montant et de même sens,
--     datée de 15 jours avant à 5 jours après ;
--   - l'état de rapprochement compare le relevé et le compte 512x, et donne les
--     écarts des deux côtés.
-- ============================================================

-- Lignes de bank_transactions qui reflètent un règlement saisi (côté comptable) :
-- elles ne font pas partie du relevé
CREATE OR REPLACE FUNCTION is_statement_line(p_source text)
RETURNS boolean
LANGUAGE sql IMMUTABLE
AS $$ SELECT COALESCE(p_source, 'manual') NOT IN ('customer_payment', 'supplier_payment') $$;

CREATE OR REPLACE FUNCTION statement_line_ledger_match()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_acc text; v_line record; v_already uuid;
BEGIN
  IF NOT is_statement_line(NEW.source) OR COALESCE(NEW.amount, 0) = 0 THEN RETURN NULL; END IF;
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

-- Nommé tg_* : après les rapprochements existants (règles, factures, score)
DROP TRIGGER IF EXISTS tg_statement_ledger_match ON bank_transactions;
CREATE TRIGGER tg_statement_ledger_match
  AFTER INSERT ON bank_transactions
  FOR EACH ROW EXECUTE FUNCTION statement_line_ledger_match();

DROP FUNCTION IF EXISTS get_bank_reconciliation_state(uuid, date);
CREATE FUNCTION get_bank_reconciliation_state(p_bank_account_id uuid, p_date date)
RETURNS TABLE (
  bank_account_id uuid,
  account_code text,
  statement_balance numeric,          -- solde du relevé (crédits − débits)
  accounting_balance numeric,         -- solde du compte de trésorerie
  unmatched_debits numeric,           -- relevé : débits non pointés (frais, prélèvements…)
  unmatched_credits numeric,          -- relevé : crédits non pointés
  ledger_unmatched_debits numeric,    -- comptabilité : encaissements absents du relevé
  ledger_unmatched_credits numeric,   -- comptabilité : décaissements absents du relevé
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
    AND bt.date <= p_date AND is_statement_line(bt.source);

  SELECT COALESCE(sum(jl.debit - jl.credit), 0),
         COALESCE(sum(jl.debit) FILTER (WHERE NOT COALESCE(jl.reconciled, false)), 0),
         COALESCE(sum(jl.credit) FILTER (WHERE NOT COALESCE(jl.reconciled, false)), 0)
    INTO v_book, v_ld, v_lc
  FROM journal_lines jl
  JOIN journal_entries je ON je.id = jl.journal_id
  WHERE jl.tenant_id = v_tid AND jl.account_code = v_acc AND je.status = 'posted' AND je.date <= p_date;

  RETURN QUERY SELECT
    p_bank_account_id, v_acc, v_stmt, v_book, v_ud, v_uc, v_ld, v_lc,
    -- relevé hors écarts = comptabilité hors écarts
    (v_stmt - v_uc + v_ud) = (v_book - v_ld + v_lc),
    (SELECT COALESCE(json_agg(row_to_json(x) ORDER BY x.date DESC), '[]'::json) FROM (
       SELECT bt.id, bt.date, bt.description AS label,
              CASE WHEN bt.type = 'credit' THEN bt.amount ELSE -bt.amount END AS amount, bt.reference
       FROM bank_transactions bt
       WHERE bt.tenant_id = v_tid AND COALESCE(bt.bank_account_id, bt.account_id) = p_bank_account_id
         AND bt.date <= p_date AND is_statement_line(bt.source) AND bt.reconciled_entry_id IS NULL
    ) x);
END $$;
REVOKE ALL ON FUNCTION get_bank_reconciliation_state(uuid, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_bank_reconciliation_state(uuid, date) TO authenticated;

-- ------------------------------------------------------------
-- Rapprochement par score (prouvé par G11) : une ligne de relevé reconnue comme le
-- paiement d'une facture augmentait amount_paid sans règlement ni écriture (et
-- s'appliquait aussi aux lignes reflétant un règlement déjà saisi). Désormais, sur
-- une ligne de RELEVÉ au crédit, une correspondance sûre (score ≥ 70) enregistre
-- un vrai règlement client : écriture 512/411, reste dû, lettrage et pointage
-- suivent les chemins de la 190 et de ce fichier.
-- ------------------------------------------------------------
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
  IF NEW.matched = true OR NOT is_statement_line(NEW.source) OR NEW.type IS DISTINCT FROM 'credit'
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
