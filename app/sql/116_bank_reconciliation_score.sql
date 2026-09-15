-- ============================================================
-- 116_bank_reconciliation_score.sql
-- BNQ-02 : Rapprochement bancaire par score multi-critères
-- ============================================================

-- Ensure bank_transactions has required columns for scoring and rules
ALTER TABLE bank_transactions ADD COLUMN IF NOT EXISTS label text;
ALTER TABLE bank_transactions ADD COLUMN IF NOT EXISTS matched_invoice_id uuid;
ALTER TABLE bank_transactions ADD COLUMN IF NOT EXISTS matched_account_code text;
ALTER TABLE bank_transactions ADD COLUMN IF NOT EXISTS match_type text;
ALTER TABLE bank_transactions ADD COLUMN IF NOT EXISTS bank_account_id uuid;


-- ============================================================
-- Table des suggestions de rapprochement
-- ============================================================
CREATE TABLE IF NOT EXISTS bank_reconciliation_suggestions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  bank_transaction_id uuid NOT NULL,
  invoice_id uuid,
  customer_id uuid,
  supplier_id uuid,
  score int NOT NULL DEFAULT 0,
  match_type text NOT NULL DEFAULT 'suggestion'
    CHECK (match_type IN ('auto', 'suggestion', 'manual')),
  matched_amount numeric DEFAULT 0,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'accepted', 'rejected')),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE bank_reconciliation_suggestions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS bank_recon_suggestions_tenant ON bank_reconciliation_suggestions;
CREATE POLICY bank_recon_suggestions_tenant ON bank_reconciliation_suggestions
  FOR ALL USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

CREATE INDEX IF NOT EXISTS idx_bank_recon_suggestions_tx
  ON bank_reconciliation_suggestions (tenant_id, bank_transaction_id);
CREATE INDEX IF NOT EXISTS idx_bank_recon_suggestions_score
  ON bank_reconciliation_suggestions (tenant_id, score DESC);

-- ============================================================
-- BNQ-02 : Rapprochement par score multi-critères
-- Remplace auto_reconcile_bank_transaction par un classement
-- ============================================================
CREATE OR REPLACE FUNCTION auto_reconcile_by_score()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_invoice record;
  v_score int;
  v_best_score int := 0;
  v_best_invoice_id uuid;
  v_best_customer_id uuid;
  v_best_amount numeric;
  v_tx_label text;
BEGIN
  -- Ne rapprocher que les mouvements non déjà rapprochés
  IF NEW.matched = true THEN RETURN NEW; END IF;

  v_tx_label := NEW.description;

  -- Chercher la meilleure facture par score multi-critères
  FOR v_invoice IN
    SELECT i.*,
      (CASE WHEN ABS(i.amount_due - NEW.amount) < 0.01              THEN 50 ELSE 0 END
     + CASE WHEN v_tx_label ILIKE '%' || i.number || '%'            THEN 40 ELSE 0 END
     + CASE WHEN NEW.reference = i.payment_reference
            AND i.payment_reference IS NOT NULL
            AND i.payment_reference != ''                           THEN 40 ELSE 0 END
     + CASE WHEN v_tx_label ILIKE '%' || c.name || '%'              THEN 20 ELSE 0 END
     + CASE WHEN i.due_date BETWEEN NEW.date - 30 AND NEW.date + 30 THEN 10 ELSE 0 END
      ) AS score
    FROM invoices i
    LEFT JOIN customers c ON c.id = i.customer_id AND c.tenant_id = i.tenant_id
    WHERE i.tenant_id = NEW.tenant_id
      AND i.payment_state IN ('not_paid', 'partial')
      AND ABS(i.amount_due) > 0
    ORDER BY score DESC
    LIMIT 5
  LOOP
    v_score := v_invoice.score;

    -- Au-dessus du seuil : rapprochement automatique
    IF v_score >= 70 AND v_score > v_best_score THEN
      v_best_score := v_score;
      v_best_invoice_id := v_invoice.id;
      v_best_customer_id := v_invoice.customer_id;
      v_best_amount := v_invoice.amount_due;
    END IF;

    -- Entre 40 et 70 : créer une suggestion
    IF v_score >= 40 AND v_score < 70 THEN
      INSERT INTO bank_reconciliation_suggestions (
        tenant_id, bank_transaction_id, invoice_id, customer_id,
        score, match_type, matched_amount, status
      ) VALUES (
        NEW.tenant_id, NEW.id, v_invoice.id, v_invoice.customer_id,
        v_score, 'suggestion', v_invoice.amount_due, 'pending'
      );
    END IF;
  END LOOP;

  -- Si une facture a un score >= 70, rapprocher automatiquement
  IF v_best_invoice_id IS NOT NULL THEN
    -- Mettre à jour la transaction dans la table
    UPDATE bank_transactions
    SET matched = true,
        invoice_id = v_best_invoice_id,
        matched_invoice_id = v_best_invoice_id
    WHERE id = NEW.id;

    -- Mettre à jour la facture
    UPDATE invoices
    SET payment_state = CASE
      WHEN amount_due <= ABS(NEW.amount) THEN 'paid'
      ELSE 'partial'
    END,
    amount_paid = COALESCE(amount_paid, 0) + ABS(NEW.amount),
    updated_at = now()
    WHERE id = v_best_invoice_id AND tenant_id = NEW.tenant_id;

    -- Créer l'écriture de règlement
    INSERT INTO bank_reconciliation_suggestions (
      tenant_id, bank_transaction_id, invoice_id, customer_id,
      score, match_type, matched_amount, status
    ) VALUES (
      NEW.tenant_id, NEW.id, v_best_invoice_id, v_best_customer_id,
      v_best_score, 'auto', v_best_amount, 'accepted'
    );
  END IF;

  RETURN NEW;
END;
$$;

-- Remplacer l'ancien trigger par le nouveau
DROP TRIGGER IF EXISTS auto_reconcile_bank_transaction ON bank_transactions;
DROP TRIGGER IF EXISTS auto_reconcile_by_score_trigger ON bank_transactions;

CREATE TRIGGER auto_reconcile_by_score_trigger
  AFTER INSERT ON bank_transactions
  FOR EACH ROW
  EXECUTE FUNCTION auto_reconcile_by_score();

-- ============================================================
-- BNQ-02 : Exploiter bank_reconciliation_rules
-- Rapprochement par règle de libellé (ex: "VIR SEPA URSSAF" → compte 431)
-- ============================================================
CREATE OR REPLACE FUNCTION apply_bank_reconciliation_rules()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_rule record;
BEGIN
  IF NEW.matched = true THEN RETURN NEW; END IF;

  FOR v_rule IN
    SELECT *
    FROM bank_reconciliation_rules
    WHERE tenant_id = NEW.tenant_id
      AND active = true
    ORDER BY priority DESC
  LOOP
    -- Vérifier si le libellé correspond au pattern
    IF NEW.description ILIKE v_rule.label_pattern THEN
      -- Appliquer la règle : assigner le compte et marquer comme rapproché
      NEW.matched_account_code := v_rule.account_code;
      NEW.matched := true;
      NEW.match_type := 'rule';

      -- Créer l'écriture comptable correspondante
      -- (la création complète se fait via le trigger de rapprochement)
      EXIT;
    END IF;
  END LOOP;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS apply_bank_recon_rules_trigger ON bank_transactions;
CREATE TRIGGER apply_bank_recon_rules_trigger
  BEFORE INSERT ON bank_transactions
  FOR EACH ROW
  EXECUTE FUNCTION apply_bank_reconciliation_rules();

-- ============================================================
-- BNQ-03 : État de rapprochement bancaire
-- Vue calculant l'égalité solde bancaire ± écritures en rapprochement = solde comptable
-- ============================================================
CREATE OR REPLACE FUNCTION get_bank_reconciliation_state(
  p_bank_account_id uuid,
  p_date date DEFAULT CURRENT_DATE
)
RETURNS TABLE(
  bank_account_id uuid,
  account_number text,
  statement_balance numeric,
  accounting_balance numeric,
  unmatched_debits numeric,
  unmatched_credits numeric,
  is_balanced boolean,
  unmatched_transactions json
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_stmt_balance numeric;
  v_acct_balance numeric;
  v_unmatched_debits numeric;
  v_unmatched_credits numeric;
  v_account_number text;
BEGIN
  -- Solde du relevé (dernière transaction rapprochée)
  SELECT COALESCE(SUM(amount), 0), account_number
  INTO v_stmt_balance, v_account_number
  FROM bank_transactions
  WHERE tenant_id = v_tid AND bank_account_id = p_bank_account_id
    AND date <= p_date
  GROUP BY account_number;

  -- Solde comptable (écritures du compte de banque)
  SELECT COALESCE(SUM(jl.debit - jl.credit), 0)
  INTO v_acct_balance
  FROM journal_lines jl
  JOIN journal_entries je ON je.id = jl.journal_id AND je.tenant_id = jl.tenant_id
  WHERE jl.tenant_id = v_tid
    AND jl.account_code = v_account_number
    AND je.date <= p_date
    AND je.status = 'posted';

  -- Écritures en rapprochement (chèques émis non débités, remises non créditées)
  SELECT
    COALESCE(SUM(CASE WHEN amount < 0 THEN ABS(amount) ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN amount > 0 THEN amount ELSE 0 END), 0)
  INTO v_unmatched_debits, v_unmatched_credits
  FROM bank_transactions
  WHERE tenant_id = v_tid AND (bank_account_id = p_bank_account_id OR account_id = p_bank_account_id)
    AND date <= p_date AND matched = false;

  RETURN QUERY
  SELECT
    p_bank_account_id,
    v_account_number,
    v_stmt_balance,
    v_acct_balance,
    v_unmatched_debits,
    v_unmatched_credits,
    -- Égalité : solde bancaire ± écritures en rapprochement = solde comptable
    ABS(v_stmt_balance - v_unmatched_debits + v_unmatched_credits - v_acct_balance) < 0.01,
    (
      SELECT COALESCE(json_agg(row_to_json(t)), '[]'::json)
      FROM (
        SELECT id, date, description AS label, amount, reference, matched
        FROM bank_transactions
        WHERE tenant_id = v_tid AND (bank_account_id = p_bank_account_id OR account_id = p_bank_account_id)
          AND date <= p_date AND matched = false
        ORDER BY date DESC
      ) t
    );
END;
$$;
