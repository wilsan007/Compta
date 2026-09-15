-- ============================================================
-- 128_performance.sql
-- PRF-04 : Trigger d'équilibre en FOR EACH STATEMENT
-- ============================================================

-- Remplacer le trigger FOR EACH ROW par FOR EACH STATEMENT
-- pour éviter le coût quadratique sur les imports massifs

-- 1. Supprimer l'ancien trigger FOR EACH ROW
DROP TRIGGER IF EXISTS check_journal_entry_balance ON journal_lines;

-- 2. Fonction d'équilibre en FOR EACH STATEMENT
CREATE OR REPLACE FUNCTION check_journal_entry_balance_stmt()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_je_id uuid;
  v_total_debit numeric;
  v_total_credit numeric;
  v_affected_je_ids uuid[];
BEGIN
  -- Collecter les IDs d'écritures affectées depuis la table de transition
  SELECT ARRAY_agg(DISTINCT journal_id) INTO v_affected_je_ids
  FROM (
    SELECT journal_id FROM new_table
    UNION
    SELECT journal_id FROM old_table
  ) AS combined;

  -- Vérifier l'équilibre pour chaque écriture affectée
  FOREACH v_je_id IN ARRAY v_affected_je_ids
  LOOP
    SELECT COALESCE(SUM(debit), 0), COALESCE(SUM(credit), 0)
    INTO v_total_debit, v_total_credit
    FROM journal_lines
    WHERE journal_id = v_je_id;

    IF ABS(v_total_debit - v_total_credit) > 0.01 THEN
      RAISE EXCEPTION 'Écriture % non équilibrée : débit % ≠ crédit %',
        v_je_id, v_total_debit, v_total_credit;
    END IF;

    -- Mettre à jour les totaux sur l'écriture
    UPDATE journal_entries
    SET total_debit = v_total_debit, total_credit = v_total_credit, updated_at = now()
    WHERE id = v_je_id;
  END LOOP;

  RETURN NULL;
END;
$$;

-- 3. Créer les triggers FOR EACH STATEMENT (un par événement car les tables de transition ne supportent pas plusieurs événements)
CREATE TRIGGER check_journal_entry_balance_ins
  AFTER INSERT ON journal_lines
  REFERENCING NEW TABLE AS new_table
  FOR EACH STATEMENT EXECUTE FUNCTION check_journal_entry_balance_stmt();

CREATE TRIGGER check_journal_entry_balance_upd
  AFTER UPDATE ON journal_lines
  REFERENCING NEW TABLE AS new_table OLD TABLE AS old_table
  FOR EACH STATEMENT EXECUTE FUNCTION check_journal_entry_balance_stmt();

CREATE TRIGGER check_journal_entry_balance_del
  AFTER DELETE ON journal_lines
  REFERENCING OLD TABLE AS old_table
  FOR EACH STATEMENT EXECUTE FUNCTION check_journal_entry_balance_stmt();

-- ============================================================
-- PRF-01 : Index de couverture pour les requêtes fréquentes
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_journal_lines_je_id
  ON journal_lines (journal_id) INCLUDE (account_code, debit, credit);

CREATE INDEX IF NOT EXISTS idx_stock_movements_product_date
  ON stock_movements (tenant_id, product_id, movement_date DESC)
  INCLUDE (quantity, movement_type);

CREATE INDEX IF NOT EXISTS idx_invoices_customer_status
  ON invoices (tenant_id, customer_id, status, date DESC);

CREATE INDEX IF NOT EXISTS idx_journal_entries_date
  ON journal_entries (tenant_id, date DESC, status)
  INCLUDE (journal_code, number);

CREATE INDEX IF NOT EXISTS idx_stock_quantities_product
  ON stock_quantities (tenant_id, product_id)
  INCLUDE (quantity, unit_cost);

CREATE INDEX IF NOT EXISTS idx_customers_name
  ON customers (tenant_id, name);

CREATE INDEX IF NOT EXISTS idx_products_sku
  ON products (tenant_id, sku)
  WHERE sku IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_employees_name
  ON employees (tenant_id, name);

CREATE INDEX IF NOT EXISTS idx_project_tasks_project
  ON project_tasks (tenant_id, project_id, status)
  INCLUDE (title, due_date, assignee_id);

CREATE INDEX IF NOT EXISTS idx_pay_slips_period
  ON pay_slips (tenant_id, period_start, employee_id);

-- ============================================================
-- PRF-02 : Index pour la pagination (DAT-01)
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_journal_lines_account
  ON journal_lines (tenant_id, account_code, journal_id);

CREATE INDEX IF NOT EXISTS idx_bank_transactions_date
  ON bank_transactions (tenant_id, date DESC);

CREATE INDEX IF NOT EXISTS idx_purchase_orders_status
  ON purchase_orders (tenant_id, status, order_date DESC);
