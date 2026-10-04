-- ============================================================
-- 90_missing_workflow_triggers.sql
--
-- Triggers de workflow manquants non couverts par les
-- migrations 81-89. Complète les chaînes RH/Paie, Banque,
-- CRM, Stock, et Conformité.
--
-- 22 triggers inspirés des leaders SaaS :
--   PayFit, Silae, Gusto, Rippling, Workday (RH/Paie)
--   Odoo, ERPNext (Stock/CRM)
--   Pennylane, Xero (Banque/Compta)
-- ============================================================

-- ============================================================
-- A. RH / PAIE (6 triggers)
-- ============================================================

-- A1. Avances sur salaire → payroll_variable_elements
CREATE OR REPLACE FUNCTION integrate_salary_advances_on_payrun()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_adv RECORD; v_period text;
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status AND NEW.status = 'processing' THEN
    v_period := to_char(NEW.period_start, 'YYYY-MM');
    FOR v_adv IN SELECT * FROM salary_advances
      WHERE tenant_id = NEW.tenant_id AND status = 'pending'
        AND deduction_month IS NOT NULL
        AND to_char(deduction_month, 'YYYY-MM') = v_period
    LOOP
      INSERT INTO payroll_variable_elements (tenant_id, employee_id, pay_run_id, period, element_type, description, amount, source, source_id, integrated)
      VALUES (NEW.tenant_id, v_adv.employee_id, NEW.id, v_period, 'advance_deduction', 'Acompte du ' || v_adv.advance_date, v_adv.amount, 'salary_advance', v_adv.id, false);
      UPDATE salary_advances SET status = 'processed' WHERE id = v_adv.id;
    END LOOP;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS integrate_salary_advances ON pay_runs;
CREATE TRIGGER integrate_salary_advances AFTER UPDATE ON pay_runs FOR EACH ROW EXECUTE FUNCTION integrate_salary_advances_on_payrun();

-- A2. Rappels de paie → payroll_variable_elements
CREATE OR REPLACE FUNCTION integrate_pay_recalls_on_payrun()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_recall RECORD; v_period text;
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status AND NEW.status = 'processing' THEN
    v_period := to_char(NEW.period_start, 'YYYY-MM');
    FOR v_recall IN SELECT * FROM pay_recalls
      WHERE tenant_id = NEW.tenant_id AND status = 'pending'
        AND reference_period = v_period
    LOOP
      INSERT INTO payroll_variable_elements (tenant_id, employee_id, pay_run_id, period, element_type, description, amount, source, source_id, integrated)
      VALUES (NEW.tenant_id, v_recall.employee_id, NEW.id, v_period, 'pay_recall', 'Rappel ' || v_recall.reference_period, v_recall.recall_amount, 'pay_recall', v_recall.id, false);
      UPDATE pay_recalls SET status = 'processed', processed_pay_run_id = NEW.id WHERE id = v_recall.id;
    END LOOP;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS integrate_pay_recalls ON pay_runs;
CREATE TRIGGER integrate_pay_recalls AFTER UPDATE ON pay_runs FOR EACH ROW EXECUTE FUNCTION integrate_pay_recalls_on_payrun();

-- A3. Notes de frais approuvées → payroll_variable_elements
CREATE OR REPLACE FUNCTION integrate_expense_report_on_approval()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_period text; v_pay_run_id uuid;
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status AND NEW.status = 'approved' THEN
    v_period := to_char(COALESCE(NEW.submitted_at, now()), 'YYYY-MM');
    SELECT id INTO v_pay_run_id FROM pay_runs
      WHERE tenant_id = NEW.tenant_id AND to_char(period_start, 'YYYY-MM') = v_period
        AND status IN ('draft', 'processing') ORDER BY created_at DESC LIMIT 1;
    INSERT INTO payroll_variable_elements (tenant_id, employee_id, pay_run_id, period, element_type, description, amount, source, source_id, integrated)
    VALUES (NEW.tenant_id, NEW.employee_id, v_pay_run_id, v_period, 'expense_reimbursement', 'Frais ' || NEW.number, NEW.total_amount, 'expense_report', NEW.id, false);
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS integrate_expense_report ON expense_reports;
CREATE TRIGGER integrate_expense_report AFTER UPDATE ON expense_reports FOR EACH ROW EXECUTE FUNCTION integrate_expense_report_on_approval();

-- A4. Congés sans solde approuvés → payroll_variable_elements
CREATE OR REPLACE FUNCTION deduct_unpaid_leave_on_approval()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_rule RECORD; v_period text; v_pay_run_id uuid; v_daily_rate numeric; v_deduction numeric; v_emp RECORD;
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status AND NEW.status = 'approved' THEN
    SELECT * INTO v_rule FROM leave_rules
      WHERE tenant_id = NEW.tenant_id AND leave_type = NEW.leave_type
        AND affects_pay = true AND active = true LIMIT 1;
    IF NOT FOUND THEN RETURN NEW; END IF;
    v_period := to_char(NEW.start_date, 'YYYY-MM');
    SELECT * INTO v_emp FROM employees WHERE id = NEW.employee_id AND tenant_id = NEW.tenant_id;
    IF v_emp.salary IS NOT NULL AND v_emp.salary > 0 THEN
      v_daily_rate := v_emp.salary / 30;
      v_deduction := v_daily_rate * NEW.days * (COALESCE(v_rule.deduction_rate, 100) / 100);
    ELSE v_deduction := 0; END IF;
    SELECT id INTO v_pay_run_id FROM pay_runs
      WHERE tenant_id = NEW.tenant_id AND to_char(period_start, 'YYYY-MM') = v_period
        AND status IN ('draft', 'processing') ORDER BY created_at DESC LIMIT 1;
    INSERT INTO payroll_variable_elements (tenant_id, employee_id, pay_run_id, period, element_type, description, quantity, unit_price, amount, source, source_id, integrated)
    VALUES (NEW.tenant_id, NEW.employee_id, v_pay_run_id, v_period, 'unpaid_leave_deduction', 'Congé sans solde ' || NEW.leave_type, NEW.days, v_daily_rate, v_deduction, 'leave_request', NEW.id, false);
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS deduct_unpaid_leave ON leave_requests;
CREATE TRIGGER deduct_unpaid_leave AFTER UPDATE ON leave_requests FOR EACH ROW EXECUTE FUNCTION deduct_unpaid_leave_on_approval();

-- A5. Transactions CPF → cpf_accounts
CREATE OR REPLACE FUNCTION sync_cpf_on_transaction()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_hours_delta numeric; v_amount_delta numeric;
BEGIN
  IF NEW.transaction_type IN ('acquisition', 'credit', 'abondement') THEN
    v_hours_delta := NEW.hours; v_amount_delta := NEW.amount;
  ELSIF NEW.transaction_type IN ('usage', 'debit', 'withdrawal') THEN
    v_hours_delta := -NEW.hours; v_amount_delta := -NEW.amount;
  ELSE v_hours_delta := NEW.hours; v_amount_delta := NEW.amount; END IF;
  INSERT INTO cpf_accounts (tenant_id, employee_id, balance_hours, balance_amount, history, last_sync_date, created_at, updated_at)
  VALUES (NEW.tenant_id, NEW.employee_id, v_hours_delta, v_amount_delta, jsonb_build_array(jsonb_build_object('transaction_id', NEW.id, 'type', NEW.transaction_type, 'hours', NEW.hours, 'amount', NEW.amount, 'date', NEW.created_at)), now(), now(), now())
  ON CONFLICT (tenant_id, employee_id) DO UPDATE SET
    balance_hours = cpf_accounts.balance_hours + v_hours_delta,
    balance_amount = cpf_accounts.balance_amount + v_amount_delta,
    history = cpf_accounts.history || jsonb_build_array(jsonb_build_object('transaction_id', NEW.id, 'type', NEW.transaction_type, 'hours', NEW.hours, 'amount', NEW.amount, 'date', NEW.created_at)),
    last_sync_date = now(), updated_at = now();
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS sync_cpf ON cpf_transactions;
CREATE TRIGGER sync_cpf AFTER INSERT ON cpf_transactions FOR EACH ROW EXECUTE FUNCTION sync_cpf_on_transaction();

-- A6. Clôture pay_run → DSN
CREATE OR REPLACE FUNCTION generate_dsn_on_payrun_close()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_period text; v_existing uuid;
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status AND NEW.status = 'closed' THEN
    v_period := to_char(NEW.period_start, 'YYYY-MM');
    SELECT id INTO v_existing FROM dsn_declarations
      WHERE tenant_id = NEW.tenant_id AND period = v_period AND type = 'mensuelle' LIMIT 1;
    IF v_existing IS NULL THEN
      INSERT INTO dsn_declarations (tenant_id, period, type, status, generated_at)
      VALUES (NEW.tenant_id, v_period, 'mensuelle', 'draft', now());
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS generate_dsn ON pay_runs;
CREATE TRIGGER generate_dsn AFTER UPDATE ON pay_runs FOR EACH ROW EXECUTE FUNCTION generate_dsn_on_payrun_close();


-- ============================================================
-- B. ÉCRITURES COMPTABLES (4 triggers)
-- ============================================================

-- B1. Facture validée → écriture vente (411/707/4457)
CREATE OR REPLACE FUNCTION create_journal_on_invoice_validate()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_entry_id uuid; v_number text; v_existing uuid;
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status AND NEW.status IN ('validated', 'posted') THEN
    SELECT id INTO v_existing FROM journal_entries
      WHERE tenant_id = NEW.tenant_id AND invoice_ref = NEW.number AND journal_code = 'VT' LIMIT 1;
    IF v_existing IS NOT NULL THEN RETURN NEW; END IF;
    v_number := 'JE-INV-' || NEW.number;
    INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description, invoice_ref, piece_number)
    VALUES (NEW.tenant_id, v_number, NEW.date, 'VT', 'posted', 'Facture vente ' || NEW.number, NEW.number, v_number)
    RETURNING id INTO v_entry_id;
    INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, debit, credit, description, line_order) VALUES
      (NEW.tenant_id, v_entry_id, '411000', '411000', NEW.total, 0, 'Client ' || NEW.number, 0),
      (NEW.tenant_id, v_entry_id, '707000', '707000', 0, NEW.subtotal, 'Ventes ' || NEW.number, 1),
      (NEW.tenant_id, v_entry_id, '4457000', '4457000', 0, NEW.vat_total, 'TVA collectée ' || NEW.number, 2);
    UPDATE invoices SET transferred_entry_id = v_entry_id WHERE id = NEW.id AND tenant_id = NEW.tenant_id;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS create_journal_invoice ON invoices;
CREATE TRIGGER create_journal_invoice AFTER UPDATE ON invoices FOR EACH ROW EXECUTE FUNCTION create_journal_on_invoice_validate();

-- B2. Facture d'achat validée → écriture achat (607/4456/401)
CREATE OR REPLACE FUNCTION create_journal_on_purchase_invoice_validate()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_entry_id uuid; v_number text; v_existing uuid;
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status AND NEW.status IN ('validated', 'posted', 'approved') THEN
    SELECT id INTO v_existing FROM journal_entries
      WHERE tenant_id = NEW.tenant_id AND invoice_ref = NEW.number AND journal_code = 'AC' LIMIT 1;
    IF v_existing IS NOT NULL THEN RETURN NEW; END IF;
    v_number := 'JE-PI-' || NEW.number;
    INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description, invoice_ref, piece_number)
    VALUES (NEW.tenant_id, v_number, NEW.date, 'AC', 'posted', 'Facture achat ' || NEW.number, NEW.number, v_number)
    RETURNING id INTO v_entry_id;
    INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, debit, credit, description, line_order) VALUES
      (NEW.tenant_id, v_entry_id, '607000', '607000', NEW.subtotal, 0, 'Achats ' || NEW.number, 0),
      (NEW.tenant_id, v_entry_id, '4456000', '4456000', NEW.vat_total, 0, 'TVA déductible ' || NEW.number, 1),
      (NEW.tenant_id, v_entry_id, '401000', '401000', 0, NEW.total, 'Fournisseur ' || NEW.number, 2);
    UPDATE purchase_invoices SET transferred_entry_id = v_entry_id WHERE id = NEW.id AND tenant_id = NEW.tenant_id;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS create_journal_purchase_invoice ON purchase_invoices;
CREATE TRIGGER create_journal_purchase_invoice AFTER UPDATE ON purchase_invoices FOR EACH ROW EXECUTE FUNCTION create_journal_on_purchase_invoice_validate();

-- B3. Paiement client → écriture encaissement (512/411)
CREATE OR REPLACE FUNCTION create_journal_on_customer_payment()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_entry_id uuid; v_number text;
BEGIN
  v_number := 'JE-CP-' || NEW.number;
  INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description, piece_number)
  VALUES (NEW.tenant_id, v_number, NEW.payment_date, 'BQ', 'posted', 'Encaissement ' || NEW.number, v_number)
  RETURNING id INTO v_entry_id;
  INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, debit, credit, description, line_order) VALUES
    (NEW.tenant_id, v_entry_id, '512000', '512000', NEW.amount, 0, 'Banque ' || NEW.number, 0),
    (NEW.tenant_id, v_entry_id, '411000', '411000', 0, NEW.amount, 'Client ' || NEW.number, 1);
  UPDATE customer_payments SET transferred_entry_id = v_entry_id WHERE id = NEW.id AND tenant_id = NEW.tenant_id;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS create_journal_customer_payment ON customer_payments;
CREATE TRIGGER create_journal_customer_payment AFTER INSERT ON customer_payments FOR EACH ROW EXECUTE FUNCTION create_journal_on_customer_payment();

-- B4. Paiement fournisseur → écriture décaissement (401/512)
CREATE OR REPLACE FUNCTION create_journal_on_supplier_payment()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_entry_id uuid; v_number text;
BEGIN
  v_number := 'JE-SP-' || NEW.number;
  INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description, piece_number)
  VALUES (NEW.tenant_id, v_number, NEW.payment_date, 'BQ', 'posted', 'Décaissement ' || NEW.number, v_number)
  RETURNING id INTO v_entry_id;
  INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, debit, credit, description, line_order) VALUES
    (NEW.tenant_id, v_entry_id, '401000', '401000', NEW.amount, 0, 'Fournisseur ' || NEW.number, 0),
    (NEW.tenant_id, v_entry_id, '512000', '512000', 0, NEW.amount, 'Banque ' || NEW.number, 1);
  UPDATE supplier_payments SET transferred_entry_id = v_entry_id WHERE id = NEW.id AND tenant_id = NEW.tenant_id;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS create_journal_supplier_payment ON supplier_payments;
CREATE TRIGGER create_journal_supplier_payment AFTER INSERT ON supplier_payments FOR EACH ROW EXECUTE FUNCTION create_journal_on_supplier_payment();


-- ============================================================
-- C. STOCK / PRODUCTION (3 triggers)
-- ============================================================

-- C1. Statut PO après réception
CREATE OR REPLACE FUNCTION update_po_status_on_receipt()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_po RECORD; v_total_ordered numeric; v_total_received numeric;
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status AND NEW.status = 'received' THEN
    IF NEW.purchase_order_id IS NOT NULL THEN
      SELECT COALESCE(SUM(quantity), 0), COALESCE(SUM(quantity_received), 0) INTO v_total_ordered, v_total_received
      FROM purchase_order_lines WHERE purchase_order_id = NEW.purchase_order_id AND tenant_id = NEW.tenant_id;
      IF v_total_received >= v_total_ordered AND v_total_ordered > 0 THEN
        UPDATE purchase_orders SET status = 'received', updated_at = now() WHERE id = NEW.purchase_order_id AND tenant_id = NEW.tenant_id;
      ELSIF v_total_received > 0 THEN
        UPDATE purchase_orders SET status = 'partial', updated_at = now() WHERE id = NEW.purchase_order_id AND tenant_id = NEW.tenant_id;
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS update_po_status ON goods_receipts;
CREATE TRIGGER update_po_status AFTER UPDATE ON goods_receipts FOR EACH ROW EXECUTE FUNCTION update_po_status_on_receipt();

-- C2. Livraison → stock out
CREATE OR REPLACE FUNCTION create_stock_out_on_delivery()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_line RECORD;
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status AND NEW.status IN ('shipped', 'delivered') THEN
    FOR v_line IN SELECT * FROM delivery_note_lines WHERE delivery_note_id = NEW.id AND tenant_id = NEW.tenant_id AND quantity > 0 LOOP
      INSERT INTO stock_movements (tenant_id, product_id, movement_type, type, quantity, reference, reference_type, reference_id, date, movement_date, notes)
      VALUES (NEW.tenant_id, v_line.product_id, 'out', 'out', v_line.quantity, 'BL-' || NEW.number, 'delivery_note', NEW.id, NEW.delivery_date, NEW.delivery_date, v_line.description);
    END LOOP;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS create_stock_out_on_delivery ON delivery_notes;
CREATE TRIGGER create_stock_out_on_delivery AFTER UPDATE ON delivery_notes FOR EACH ROW EXECUTE FUNCTION create_stock_out_on_delivery();

-- C3. Contrôle qualité réussi → stock in
CREATE OR REPLACE FUNCTION create_stock_in_on_quality_pass()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_gr_line RECORD;
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status AND NEW.status = 'passed' THEN
    IF NEW.reference_type = 'goods_receipt' AND NEW.reference_id IS NOT NULL THEN
      FOR v_gr_line IN SELECT * FROM goods_receipt_lines WHERE goods_receipt_id = NEW.reference_id AND tenant_id = NEW.tenant_id AND product_id = NEW.product_id AND quantity_received > 0 LOOP
        INSERT INTO stock_movements (tenant_id, product_id, movement_type, type, quantity, reference, reference_type, reference_id, date, movement_date, notes)
        VALUES (NEW.tenant_id, NEW.product_id, 'in', 'in', v_gr_line.quantity_received, 'QC-' || COALESCE(NEW.checked_by, 'auto'), 'quality_check', NEW.id, CURRENT_DATE, CURRENT_DATE, 'Stock après QC');
      END LOOP;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS create_stock_on_quality ON quality_checks;
CREATE TRIGGER create_stock_on_quality AFTER UPDATE ON quality_checks FOR EACH ROW EXECUTE FUNCTION create_stock_in_on_quality_pass();


-- ============================================================
-- D. BANQUE / TRÉSORERIE (4 triggers)
-- ============================================================

-- D1. Paiement client → transaction bancaire
CREATE OR REPLACE FUNCTION create_bank_tx_on_customer_payment()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.bank_account_id IS NOT NULL THEN
    INSERT INTO bank_transactions (tenant_id, account_id, date, description, reference, type, amount, reconciled, matched, invoice_id, source)
    VALUES (NEW.tenant_id, NEW.bank_account_id, NEW.payment_date, 'Encaissement ' || NEW.number, NEW.reference, 'credit', NEW.amount, false, false, NEW.invoice_id, 'customer_payment');
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS create_bank_tx_on_customer_payment ON customer_payments;
CREATE TRIGGER create_bank_tx_on_customer_payment AFTER INSERT ON customer_payments FOR EACH ROW EXECUTE FUNCTION create_bank_tx_on_customer_payment();

-- D2. Paiement fournisseur → transaction bancaire
CREATE OR REPLACE FUNCTION create_bank_tx_on_supplier_payment()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.bank_account_id IS NOT NULL THEN
    INSERT INTO bank_transactions (tenant_id, account_id, date, description, reference, type, amount, reconciled, matched, purchase_invoice_id, source)
    VALUES (NEW.tenant_id, NEW.bank_account_id, NEW.payment_date, 'Décaissement ' || NEW.number, NEW.reference, 'debit', NEW.amount, false, false, NEW.purchase_invoice_id, 'supplier_payment');
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS create_bank_tx_on_supplier_payment ON supplier_payments;
CREATE TRIGGER create_bank_tx_on_supplier_payment AFTER INSERT ON supplier_payments FOR EACH ROW EXECUTE FUNCTION create_bank_tx_on_supplier_payment();

-- D3. Transaction bancaire → solde compte
CREATE OR REPLACE FUNCTION update_bank_balance_on_transaction()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_delta numeric;
BEGIN
  v_delta := CASE WHEN NEW.type = 'credit' THEN NEW.amount WHEN NEW.type = 'debit' THEN -NEW.amount ELSE 0 END;
  IF NEW.account_id IS NOT NULL AND v_delta != 0 THEN
    UPDATE bank_accounts SET calculated_balance = COALESCE(calculated_balance, 0) + v_delta, updated_at = now()
    WHERE id = NEW.account_id AND tenant_id = NEW.tenant_id;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS update_bank_balance ON bank_transactions;
CREATE TRIGGER update_bank_balance AFTER INSERT ON bank_transactions FOR EACH ROW EXECUTE FUNCTION update_bank_balance_on_transaction();

-- D4. Rapprochement bancaire automatique par montant
CREATE OR REPLACE FUNCTION auto_reconcile_bank_transaction()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_invoice RECORD;
BEGIN
  IF NEW.reconciled = true OR NEW.matched = true THEN RETURN NEW; END IF;
  IF NEW.type = 'credit' AND NEW.amount > 0 THEN
    SELECT * INTO v_invoice FROM invoices
      WHERE tenant_id = NEW.tenant_id AND status IN ('validated', 'posted', 'sent')
        AND payment_state IN ('not_paid', 'partial') AND ABS(total - NEW.amount) < 0.01
      ORDER BY CASE WHEN due_date BETWEEN NEW.date - 30 AND NEW.date + 30 THEN 0 ELSE 1 END, due_date LIMIT 1;
    IF FOUND THEN
      UPDATE bank_transactions SET matched = true, invoice_id = v_invoice.id WHERE id = NEW.id AND tenant_id = NEW.tenant_id;
    END IF;
  ELSIF NEW.type = 'debit' AND NEW.amount > 0 THEN
    SELECT * INTO v_invoice FROM purchase_invoices
      WHERE tenant_id = NEW.tenant_id AND status IN ('validated', 'posted', 'approved')
        AND payment_state IN ('not_paid', 'partial') AND ABS(total - NEW.amount) < 0.01
      ORDER BY CASE WHEN due_date BETWEEN NEW.date - 30 AND NEW.date + 30 THEN 0 ELSE 1 END, due_date LIMIT 1;
    IF FOUND THEN
      UPDATE bank_transactions SET matched = true, purchase_invoice_id = v_invoice.id WHERE id = NEW.id AND tenant_id = NEW.tenant_id;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS auto_reconcile_bank_tx ON bank_transactions;
CREATE TRIGGER auto_reconcile_bank_tx AFTER INSERT ON bank_transactions FOR EACH ROW EXECUTE FUNCTION auto_reconcile_bank_transaction();


-- ============================================================
-- E. CRM / PROJETS (3 triggers)
-- ============================================================

-- E1. Opportunité gagnée → devis
CREATE OR REPLACE FUNCTION create_quote_on_opportunity_won()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_quote_number text; v_customer_name text;
BEGIN
  IF NEW.stage IS DISTINCT FROM OLD.stage AND NEW.stage = 'won' THEN
    SELECT name INTO v_customer_name FROM customers WHERE id = NEW.customer_id AND tenant_id = NEW.tenant_id;
    v_quote_number := 'DEV-' || to_char(now(), 'YYYY') || '-' || upper(substr(NEW.number, 1, 6));
    INSERT INTO quotes (tenant_id, number, customer_id, customer_name, date, expiry_date, status, subtotal, vat_total, total, notes)
    VALUES (NEW.tenant_id, v_quote_number, NEW.customer_id, v_customer_name, CURRENT_DATE, CURRENT_DATE + 30, 'draft',
      COALESCE(NEW.actual_amount, NEW.expected_amount, 0), 0, COALESCE(NEW.actual_amount, NEW.expected_amount, 0),
      'Devis auto depuis opportunité ' || NEW.title);
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS create_quote_on_opportunity ON crm_opportunities;
CREATE TRIGGER create_quote_on_opportunity AFTER UPDATE ON crm_opportunities FOR EACH ROW EXECUTE FUNCTION create_quote_on_opportunity_won();

-- E2. Timesheet approuvé → payroll_variable_elements
CREATE OR REPLACE FUNCTION sync_timesheet_to_payroll()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_period text; v_pay_run_id uuid; v_emp RECORD; v_overtime_hours numeric;
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status AND NEW.status = 'approved' THEN
    IF NEW.employee_id IS NULL THEN RETURN NEW; END IF;
    v_period := to_char(NEW.date, 'YYYY-MM');
    SELECT id INTO v_pay_run_id FROM pay_runs
      WHERE tenant_id = NEW.tenant_id AND to_char(period_start, 'YYYY-MM') = v_period
        AND status IN ('draft', 'processing') ORDER BY created_at DESC LIMIT 1;
    SELECT * INTO v_emp FROM employees WHERE id = NEW.employee_id AND tenant_id = NEW.tenant_id;
    v_overtime_hours := CASE WHEN v_emp.salary IS NOT NULL AND NEW.hours > 7 THEN GREATEST(NEW.hours - 7, 0) ELSE 0 END;
    INSERT INTO payroll_variable_elements (tenant_id, employee_id, pay_run_id, period, element_type, description, quantity, unit_price, amount, source, source_id, integrated)
    VALUES (NEW.tenant_id, NEW.employee_id, v_pay_run_id, v_period, 'timesheet_hours', 'Heures ' || to_char(NEW.date, 'DD/MM'), NEW.hours, 0, 0, 'timesheet', NEW.id, false);
    IF v_overtime_hours > 0 THEN
      INSERT INTO payroll_variable_elements (tenant_id, employee_id, pay_run_id, period, element_type, description, quantity, unit_price, amount, source, source_id, integrated)
      VALUES (NEW.tenant_id, NEW.employee_id, v_pay_run_id, v_period, 'overtime', 'Heures supp ' || to_char(NEW.date, 'DD/MM'), v_overtime_hours, 0, 0, 'timesheet', NEW.id, false);
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS sync_timesheet_to_payroll ON timesheets;
CREATE TRIGGER sync_timesheet_to_payroll AFTER UPDATE ON timesheets FOR EACH ROW EXECUTE FUNCTION sync_timesheet_to_payroll();

-- E3. Commande de vente confirmée → alerte stock
CREATE OR REPLACE FUNCTION check_stock_on_sales_order_confirm()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_line RECORD; v_product RECORD; v_shortage numeric;
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status AND NEW.status = 'confirmed' THEN
    FOR v_line IN SELECT * FROM sales_order_lines WHERE sales_order_id = NEW.id AND tenant_id = NEW.tenant_id LOOP
      SELECT stock_quantity, name INTO v_product FROM products WHERE id = v_line.product_id AND tenant_id = NEW.tenant_id;
      IF FOUND THEN
        v_shortage := v_line.quantity - COALESCE(v_product.stock_quantity, 0);
        IF v_shortage > 0 THEN
          INSERT INTO stock_alerts (tenant_id, product_id, alert_type, threshold, current_value, status, triggered_at)
          VALUES (NEW.tenant_id, v_line.product_id, 'shortage', v_line.quantity, v_product.stock_quantity, 'active', now());
        END IF;
      END IF;
    END LOOP;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS check_stock_on_sales_order ON sales_orders;
CREATE TRIGGER check_stock_on_sales_order AFTER UPDATE ON sales_orders FOR EACH ROW EXECUTE FUNCTION check_stock_on_sales_order_confirm();


-- ============================================================
-- F. CONFORMITÉ (2 triggers)
-- ============================================================

-- F1. Report automatique des congés en fin d'année
CREATE OR REPLACE FUNCTION auto_carry_over_leave_balances()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_rule RECORD; v_remaining numeric; v_carry_over numeric; v_next_year integer; v_existing_id uuid;
BEGIN
  v_next_year := EXTRACT(year FROM CURRENT_DATE) + 1;
  v_remaining := COALESCE(NEW.acquired, 0) + COALESCE(NEW.carry_over, 0) - COALESCE(NEW.taken, 0);
  IF v_remaining > 0 THEN
    SELECT * INTO v_rule FROM leave_rules WHERE tenant_id = NEW.tenant_id AND leave_type = NEW.leave_type AND active = true LIMIT 1;
    IF FOUND THEN
      v_carry_over := LEAST(v_remaining, COALESCE(v_rule.max_carry_over, 0));
      SELECT id INTO v_existing_id FROM leave_balances WHERE employee_id = NEW.employee_id AND leave_type = NEW.leave_type AND year = v_next_year AND tenant_id = NEW.tenant_id LIMIT 1;
      IF v_existing_id IS NOT NULL THEN
        UPDATE leave_balances SET carry_over = v_carry_over, remaining = acquired + v_carry_over - taken - pending, updated_at = now() WHERE id = v_existing_id;
      ELSE
        INSERT INTO leave_balances (tenant_id, employee_id, leave_type, year, acquired, taken, pending, remaining, carry_over)
        VALUES (NEW.tenant_id, NEW.employee_id, NEW.leave_type, v_next_year, 0, 0, 0, v_carry_over, v_carry_over);
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS auto_carry_over_leave ON leave_balances;
CREATE TRIGGER auto_carry_over_leave AFTER UPDATE ON leave_balances FOR EACH ROW WHEN (EXTRACT(month FROM CURRENT_DATE) = 12) EXECUTE FUNCTION auto_carry_over_leave_balances();

-- F2. Révocation automatique des auditeurs expirés
CREATE OR REPLACE FUNCTION trigger_revoke_expired_auditors()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
  PERFORM auto_revoke_expired_auditors();
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS revoke_expired_auditors ON tenant_users;
CREATE TRIGGER revoke_expired_auditors AFTER INSERT OR UPDATE ON tenant_users FOR EACH STATEMENT EXECUTE FUNCTION trigger_revoke_expired_auditors();


-- ============================================================
-- GRANT EXECUTE
-- ============================================================
GRANT EXECUTE ON FUNCTION integrate_salary_advances_on_payrun() TO authenticated;
GRANT EXECUTE ON FUNCTION integrate_pay_recalls_on_payrun() TO authenticated;
GRANT EXECUTE ON FUNCTION integrate_expense_report_on_approval() TO authenticated;
GRANT EXECUTE ON FUNCTION deduct_unpaid_leave_on_approval() TO authenticated;
GRANT EXECUTE ON FUNCTION sync_cpf_on_transaction() TO authenticated;
GRANT EXECUTE ON FUNCTION generate_dsn_on_payrun_close() TO authenticated;
GRANT EXECUTE ON FUNCTION create_journal_on_invoice_validate() TO authenticated;
GRANT EXECUTE ON FUNCTION create_journal_on_purchase_invoice_validate() TO authenticated;
GRANT EXECUTE ON FUNCTION create_journal_on_customer_payment() TO authenticated;
GRANT EXECUTE ON FUNCTION create_journal_on_supplier_payment() TO authenticated;
GRANT EXECUTE ON FUNCTION update_po_status_on_receipt() TO authenticated;
GRANT EXECUTE ON FUNCTION create_stock_out_on_delivery() TO authenticated;
GRANT EXECUTE ON FUNCTION create_stock_in_on_quality_pass() TO authenticated;
GRANT EXECUTE ON FUNCTION create_bank_tx_on_customer_payment() TO authenticated;
GRANT EXECUTE ON FUNCTION create_bank_tx_on_supplier_payment() TO authenticated;
GRANT EXECUTE ON FUNCTION update_bank_balance_on_transaction() TO authenticated;
GRANT EXECUTE ON FUNCTION auto_reconcile_bank_transaction() TO authenticated;
GRANT EXECUTE ON FUNCTION create_quote_on_opportunity_won() TO authenticated;
GRANT EXECUTE ON FUNCTION sync_timesheet_to_payroll() TO authenticated;
GRANT EXECUTE ON FUNCTION check_stock_on_sales_order_confirm() TO authenticated;
GRANT EXECUTE ON FUNCTION auto_carry_over_leave_balances() TO authenticated;
GRANT EXECUTE ON FUNCTION trigger_revoke_expired_auditors() TO authenticated;
