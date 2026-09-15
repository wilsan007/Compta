-- ============================================================
-- 81_complete_workflow_triggers.sql
--
-- Câblage complet des workflows manquants:
--   1. Paiement client → statut facture + solde client
--   2. Paiement fournisseur → statut facture + solde fournisseur
--   3. Production → stock (consommation composants + production finis)
--   4. Réception → stock in automatique
--   5. Paie validée → écritures comptables
--   6. Triggers set_tenant_id sur 68 tables manquantes
--   7. Politiques RLS sur tables sans politique
--   8. Politiques RLS manquantes sur tables "lines"
-- ============================================================

-- ============================================================
-- 1. PAIEMENT CLIENT → STATUT FACTURE + SOLDE CLIENT
-- ============================================================

CREATE OR REPLACE FUNCTION update_invoice_on_customer_payment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_invoice RECORD;
  v_total_paid numeric;
  v_invoice_total numeric;
BEGIN
  -- Ne réagir qu'aux paiements enregistrés
  IF NEW.status NOT IN ('recorded', 'validated') THEN
    RETURN NEW;
  END IF;

  -- Récupérer la facture liée
  IF NEW.invoice_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT * INTO v_invoice FROM invoices WHERE id = NEW.invoice_id AND tenant_id = NEW.tenant_id;
  IF NOT FOUND THEN
    RETURN NEW;
  END IF;

  -- Calculer le total payé pour cette facture
  SELECT COALESCE(SUM(amount), 0) INTO v_total_paid
  FROM customer_payments
  WHERE invoice_id = NEW.invoice_id
    AND tenant_id = NEW.tenant_id
    AND status IN ('recorded', 'validated');

  v_invoice_total := COALESCE(v_invoice.total, 0);

  -- Mettre à jour la facture
  UPDATE invoices
    SET amount_paid = v_total_paid,
        amount_due = GREATEST(v_invoice_total - v_total_paid, 0),
        payment_state = CASE
          WHEN v_total_paid >= v_invoice_total AND v_invoice_total > 0 THEN 'paid'
          WHEN v_total_paid > 0 THEN 'partial'
          ELSE 'not_paid'
        END,
        status = CASE
          WHEN v_total_paid >= v_invoice_total AND v_invoice_total > 0 THEN 'paid'
          ELSE status
        END,
        updated_at = NOW()
  WHERE id = NEW.invoice_id AND tenant_id = NEW.tenant_id;

  -- Mettre à jour le solde client
  IF NEW.customer_id IS NOT NULL THEN
    UPDATE customers
      SET balance = GREATEST(COALESCE(balance, 0) - NEW.amount, 0),
          credit_used = GREATEST(COALESCE(credit_used, 0) - NEW.amount, 0),
          updated_at = NOW()
    WHERE id = NEW.customer_id AND tenant_id = NEW.tenant_id;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_customer_payment_update_invoice ON customer_payments;
CREATE TRIGGER trg_customer_payment_update_invoice
  AFTER INSERT OR UPDATE ON customer_payments
  FOR EACH ROW EXECUTE FUNCTION update_invoice_on_customer_payment();

-- ============================================================
-- 2. PAIEMENT FOURNISSEUR → STATUT FACTURE + SOLDE FOURNISSEUR
-- ============================================================

CREATE OR REPLACE FUNCTION update_invoice_on_supplier_payment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_invoice RECORD;
  v_total_paid numeric;
  v_invoice_total numeric;
BEGIN
  IF NEW.status NOT IN ('recorded', 'validated') THEN
    RETURN NEW;
  END IF;

  -- Chercher la facture d'achat liée via reference ou champ dédié
  -- supplier_payments n'a pas de invoice_id direct, on utilise reference
  IF NEW.reference IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT * INTO v_invoice
  FROM purchase_invoices
  WHERE number = NEW.reference
    AND tenant_id = NEW.tenant_id
  LIMIT 1;

  IF NOT FOUND THEN
    -- Pas de facture trouvée, juste mettre à jour le solde fournisseur
    IF NEW.supplier_id IS NOT NULL THEN
      UPDATE suppliers
        SET balance = COALESCE(balance, 0) + NEW.amount,
            updated_at = NOW()
      WHERE id = NEW.supplier_id AND tenant_id = NEW.tenant_id;
    END IF;
    RETURN NEW;
  END IF;

  -- Calculer le total payé
  SELECT COALESCE(SUM(amount), 0) INTO v_total_paid
  FROM supplier_payments
  WHERE reference = v_invoice.number
    AND tenant_id = NEW.tenant_id
    AND status IN ('recorded', 'validated');

  v_invoice_total := COALESCE(v_invoice.total, 0);

  -- Mettre à jour la facture d'achat
  UPDATE purchase_invoices
    SET amount_paid = v_total_paid,
        amount_due = GREATEST(v_invoice_total - v_total_paid, 0),
        payment_state = CASE
          WHEN v_total_paid >= v_invoice_total AND v_invoice_total > 0 THEN 'paid'
          WHEN v_total_paid > 0 THEN 'partial'
          ELSE 'not_paid'
        END,
        status = CASE
          WHEN v_total_paid >= v_invoice_total AND v_invoice_total > 0 THEN 'paid'
          ELSE status
        END,
        updated_at = NOW()
  WHERE id = v_invoice.id AND tenant_id = NEW.tenant_id;

  -- Mettre à jour le solde fournisseur
  IF NEW.supplier_id IS NOT NULL THEN
    UPDATE suppliers
      SET balance = GREATEST(COALESCE(balance, 0) - NEW.amount, 0),
          updated_at = NOW()
    WHERE id = NEW.supplier_id AND tenant_id = NEW.tenant_id;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_supplier_payment_update_invoice ON supplier_payments;
CREATE TRIGGER trg_supplier_payment_update_invoice
  AFTER INSERT OR UPDATE ON supplier_payments
  FOR EACH ROW EXECUTE FUNCTION update_invoice_on_supplier_payment();

-- ============================================================
-- 3. PRODUCTION → STOCK (consommation composants + production finis)
-- ============================================================

CREATE OR REPLACE FUNCTION create_stock_on_manufacturing_complete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_bom RECORD;
  v_component RECORD;
  v_piece_number text;
BEGIN
  -- Ne réagir qu'au passage à 'completed'
  IF NEW.status != 'completed' THEN
    RETURN NEW;
  END IF;

  -- Éviter la double exécution (si déjà completed avant)
  IF OLD.status = 'completed' THEN
    RETURN NEW;
  END IF;

  -- 1. Consommer les composants du BOM
  FOR v_component IN
    SELECT bl.product_id, bl.quantity * NEW.quantity AS total_qty
    FROM bom_lines bl
    JOIN boms b ON b.id = bl.bom_id
    WHERE bl.bom_id = NEW.bom_id
      AND bl.tenant_id = NEW.tenant_id
      AND b.tenant_id = NEW.tenant_id
  LOOP
    INSERT INTO stock_movements (
      tenant_id, product_id, movement_type, type, quantity,
      reference, reference_type, reference_id,
      date, movement_date, warehouse_id, notes
    ) VALUES (
      NEW.tenant_id, v_component.product_id, 'out', 'out', v_component.total_qty,
      'MO-' || NEW.number, 'manufacturing_order', NEW.id,
      NEW.end_date, NEW.end_date, NEW.warehouse_id,
      'Consommation automatique - OF ' || NEW.number
    );
  END LOOP;

  -- 2. Produire l'article fini
  v_piece_number := 'MO-' || NEW.number;

  INSERT INTO stock_movements (
    tenant_id, product_id, movement_type, type, quantity,
    reference, reference_type, reference_id,
    date, movement_date, warehouse_id, notes
  ) VALUES (
    NEW.tenant_id, NEW.product_id, 'in', 'in', NEW.quantity,
    'MO-' || NEW.number, 'manufacturing_order', NEW.id,
    NEW.end_date, NEW.end_date, NEW.warehouse_id,
    'Production automatique - OF ' || NEW.number
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_manufacturing_complete_stock ON manufacturing_orders;
CREATE TRIGGER trg_manufacturing_complete_stock
  AFTER UPDATE ON manufacturing_orders
  FOR EACH ROW EXECUTE FUNCTION create_stock_on_manufacturing_complete();

-- ============================================================
-- 4. RÉCEPTION → STOCK IN AUTOMATIQUE
-- ============================================================

CREATE OR REPLACE FUNCTION create_stock_on_goods_receipt()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_line RECORD;
BEGIN
  -- Ne réagir qu'au passage à 'received'
  IF NEW.status != 'received' THEN
    RETURN NEW;
  END IF;

  IF OLD.status = 'received' THEN
    RETURN NEW;
  END IF;

  -- Créer un mouvement de stock pour chaque ligne reçue
  FOR v_line IN
    SELECT * FROM goods_receipt_lines
    WHERE goods_receipt_id = NEW.id
      AND tenant_id = NEW.tenant_id
      AND quantity_received > 0
  LOOP
    INSERT INTO stock_movements (
      tenant_id, product_id, movement_type, type, quantity,
      reference, reference_type, reference_id,
      date, movement_date, notes
    ) VALUES (
      NEW.tenant_id, v_line.product_id, 'in', 'in', v_line.quantity_received,
      'BR-' || NEW.number, 'goods_receipt', NEW.id,
      NEW.receipt_date, NEW.receipt_date,
      'Réception automatique - BR ' || NEW.number
    );
  END LOOP;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_goods_receipt_stock ON goods_receipts;
CREATE TRIGGER trg_goods_receipt_stock
  AFTER UPDATE ON goods_receipts
  FOR EACH ROW EXECUTE FUNCTION create_stock_on_goods_receipt();

-- ============================================================
-- 5. PAIE VALIDÉE → ÉCRITURES COMPTABLES
-- ============================================================

CREATE OR REPLACE FUNCTION create_journal_on_payroll_validate()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_entry_id uuid;
  v_entry_number text;
  v_gross_total numeric;
  v_tax_total numeric;
  v_net_total numeric;
  v_employer_contributions numeric;
BEGIN
  -- Ne réagir qu'au passage à 'paid' (statut final de validation paie)
  IF NEW.status != 'paid' THEN
    RETURN NEW;
  END IF;

  IF OLD.status = 'paid' THEN
    RETURN NEW;
  END IF;

  v_gross_total := COALESCE(NEW.gross_total, 0);
  v_tax_total := COALESCE(NEW.tax_total, 0);
  v_net_total := COALESCE(NEW.net_total, 0);

  -- Récupérer les cotisations employeur depuis les fiches de paie
  SELECT COALESCE(SUM(employer_contributions), 0) INTO v_employer_contributions
  FROM pay_slips
  WHERE pay_run_id = NEW.id AND tenant_id = NEW.tenant_id;

  -- Générer un numéro d'écriture
  v_entry_number := 'OD-' || to_char(NOW(), 'YYYYMMDD') || '-' || NEW.number;

  -- Créer l'écriture comptable
  INSERT INTO journal_entries (
    tenant_id, number, date, description, reference,
    status, journal_code, total_debit, total_credit
  ) VALUES (
    NEW.tenant_id, v_entry_number, NEW.pay_date,
    'Écriture de paie - ' || NEW.number,
    'PAYROLL-' || NEW.number,
    'draft', 'OD',
    v_gross_total + v_employer_contributions,
    v_gross_total + v_employer_contributions
  ) RETURNING id INTO v_entry_id;

  -- Ligne 1: Débit - Charges de personnel (compte 641)
  INSERT INTO journal_lines (
    tenant_id, journal_id, account_code, account_general,
    debit, credit, description, line_order
  ) VALUES (
    NEW.tenant_id, v_entry_id, '641000', '641',
    v_gross_total, 0, 'Salaires bruts', 1
  );

  -- Ligne 2: Débit - Cotisations patronales (compte 645)
  IF v_employer_contributions > 0 THEN
    INSERT INTO journal_lines (
      tenant_id, journal_id, account_code, account_general,
      debit, credit, description, line_order
    ) VALUES (
      NEW.tenant_id, v_entry_id, '645000', '645',
      v_employer_contributions, 0, 'Cotisations patronales', 2
    );
  END IF;

  -- Ligne 3: Crédit - Cotisations sociales URSSAF (compte 431)
  IF v_tax_total > 0 THEN
    INSERT INTO journal_lines (
      tenant_id, journal_id, account_code, account_general,
      debit, credit, description, line_order
    ) VALUES (
      NEW.tenant_id, v_entry_id, '431000', '431',
      0, v_tax_total, 'Cotisations sociales', 3
    );
  END IF;

  -- Ligne 4: Crédit - Net à payer (compte 421)
  INSERT INTO journal_lines (
    tenant_id, journal_id, account_code, account_general,
    debit, credit, description, line_order
  ) VALUES (
    NEW.tenant_id, v_entry_id, '421000', '421',
    0, v_net_total, 'Net à payer', 4
  );

  -- Ligne 5: Crédit - Cotisations patronales (compte 431) si > 0
  IF v_employer_contributions > 0 THEN
    INSERT INTO journal_lines (
      tenant_id, journal_id, account_code, account_general,
      debit, credit, description, line_order
    ) VALUES (
      NEW.tenant_id, v_entry_id, '431000', '431',
      0, v_employer_contributions, 'Cotisations patronales à payer', 5
    );
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_payroll_create_journal ON pay_runs;
CREATE TRIGGER trg_payroll_create_journal
  AFTER UPDATE ON pay_runs
  FOR EACH ROW EXECUTE FUNCTION create_journal_on_payroll_validate();

-- ============================================================
-- 6. TRIGGERS set_tenant_id SUR 68 TABLES MANQUANTES
-- ============================================================

DO $$
DECLARE
  t text;
  tables text[] := ARRAY[
    'account_tag_mappings', 'account_tags', 'accounting_control_runs',
    'analytic_journal_codes', 'auto_label_rules', 'bank_statement_templates',
    'batch_entry_sessions', 'carry_forward_log', 'cash_control_sessions',
    'compaction_logs', 'corporate_tax_grids', 'custom_report_templates',
    'dashboard_widgets', 'deferred_printing_jobs', 'disputes',
    'etat_rapprochement', 'extourne_log', 'fec_attestations',
    'fiscal_position_mappings', 'fiscal_positions', 'fusion_logs',
    'grid_templates', 'ifrs_adjustments', 'journal_access_rights',
    'justificatif_solde', 'lettrage_differences', 'marking_types',
    'mirror_servers', 'mirror_verification_details', 'module_document_access_log',
    'module_document_shares', 'module_documents', 'notification_email_queue',
    'notification_preferences', 'payment_promises', 'payment_templates_compta',
    'payment_terms', 'payroll_tax_grids', 'project_activity_log',
    'project_docs', 'project_members', 'project_milestones',
    'project_notifications', 'project_stages', 'project_tags',
    'project_task_dependencies', 'project_task_tags', 'project_task_templates',
    'project_task_watchers', 'project_tasks', 'project_time_entries',
    'reimputation_logs', 'reminder_levels', 'reporting_plans',
    'revision_cycles', 'rgpd_requests', 'stat_fields',
    'task_action_attachments', 'task_actions', 'task_comments',
    'task_documents', 'tax_payments', 'tax_rates',
    'tenant_users', 'tier_ribs', 'vat_on_collections'
  ];
BEGIN
  FOREACH t IN ARRAY tables LOOP
    BEGIN
      EXECUTE format('DROP TRIGGER IF EXISTS set_tenant_id_%I ON %I', t, t);
      EXECUTE format(
        'CREATE TRIGGER set_tenant_id_%I BEFORE INSERT ON %I FOR EACH ROW EXECUTE FUNCTION set_tenant_id()',
        t, t
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Skipping trigger on %: %', t, SQLERRM;
    END;
  END LOOP;
END $$;

-- ============================================================
-- 7. POLITIQUES RLS SUR TABLES SANS POLITIQUE
-- ============================================================

-- module_documents
DROP POLICY IF EXISTS "tenant_select_module_documents" ON module_documents;
DROP POLICY IF EXISTS "tenant_insert_module_documents" ON module_documents;
DROP POLICY IF EXISTS "tenant_update_module_documents" ON module_documents;
DROP POLICY IF EXISTS "tenant_delete_module_documents" ON module_documents;

CREATE POLICY "tenant_select_module_documents" ON module_documents
  FOR SELECT USING (tenant_id = current_tenant_id());
CREATE POLICY "tenant_insert_module_documents" ON module_documents
  FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
CREATE POLICY "tenant_update_module_documents" ON module_documents
  FOR UPDATE USING (tenant_id = current_tenant_id()) WITH CHECK (tenant_id = current_tenant_id());
CREATE POLICY "tenant_delete_module_documents" ON module_documents
  FOR DELETE USING (tenant_id = current_tenant_id());

-- module_document_shares
DROP POLICY IF EXISTS "tenant_select_module_document_shares" ON module_document_shares;
DROP POLICY IF EXISTS "tenant_insert_module_document_shares" ON module_document_shares;
DROP POLICY IF EXISTS "tenant_update_module_document_shares" ON module_document_shares;
DROP POLICY IF EXISTS "tenant_delete_module_document_shares" ON module_document_shares;

CREATE POLICY "tenant_select_module_document_shares" ON module_document_shares
  FOR SELECT USING (tenant_id = current_tenant_id());
CREATE POLICY "tenant_insert_module_document_shares" ON module_document_shares
  FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
CREATE POLICY "tenant_update_module_document_shares" ON module_document_shares
  FOR UPDATE USING (tenant_id = current_tenant_id()) WITH CHECK (tenant_id = current_tenant_id());
CREATE POLICY "tenant_delete_module_document_shares" ON module_document_shares
  FOR DELETE USING (tenant_id = current_tenant_id());

-- module_document_access_log
DROP POLICY IF EXISTS "tenant_select_module_document_access_log" ON module_document_access_log;
DROP POLICY IF EXISTS "tenant_insert_module_document_access_log" ON module_document_access_log;
DROP POLICY IF EXISTS "tenant_update_module_document_access_log" ON module_document_access_log;
DROP POLICY IF EXISTS "tenant_delete_module_document_access_log" ON module_document_access_log;

CREATE POLICY "tenant_select_module_document_access_log" ON module_document_access_log
  FOR SELECT USING (tenant_id = current_tenant_id());
CREATE POLICY "tenant_insert_module_document_access_log" ON module_document_access_log
  FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
CREATE POLICY "tenant_update_module_document_access_log" ON module_document_access_log
  FOR UPDATE USING (tenant_id = current_tenant_id()) WITH CHECK (tenant_id = current_tenant_id());
CREATE POLICY "tenant_delete_module_document_access_log" ON module_document_access_log
  FOR DELETE USING (tenant_id = current_tenant_id());

-- ============================================================
-- 8. POLITIQUES RLS MANQUANTES SUR TABLES "LINES"
-- ============================================================

DO $$
DECLARE
  t text;
  tables text[] := ARRAY[
    'asset_split_components', 'credit_note_lines', 'delivery_note_lines',
    'expense_report_lines', 'goods_receipt_lines', 'purchase_credit_lines',
    'purchase_invoice_lines', 'purchase_order_lines', 'quote_lines',
    'sales_order_lines'
  ];
BEGIN
  FOREACH t IN ARRAY tables LOOP
    BEGIN
      -- SELECT
      EXECUTE format('DROP POLICY IF EXISTS "tenant_select_%I" ON %I', t, t);
      EXECUTE format(
        'CREATE POLICY "tenant_select_%I" ON %I FOR SELECT USING (tenant_id = current_tenant_id())',
        t, t
      );
      -- INSERT
      EXECUTE format('DROP POLICY IF EXISTS "tenant_insert_%I" ON %I', t, t);
      EXECUTE format(
        'CREATE POLICY "tenant_insert_%I" ON %I FOR INSERT WITH CHECK (tenant_id = current_tenant_id())',
        t, t
      );
      -- UPDATE
      EXECUTE format('DROP POLICY IF EXISTS "tenant_update_%I" ON %I', t, t);
      EXECUTE format(
        'CREATE POLICY "tenant_update_%I" ON %I FOR UPDATE USING (tenant_id = current_tenant_id()) WITH CHECK (tenant_id = current_tenant_id())',
        t, t
      );
      -- DELETE
      EXECUTE format('DROP POLICY IF EXISTS "tenant_delete_%I" ON %I', t, t);
      EXECUTE format(
        'CREATE POLICY "tenant_delete_%I" ON %I FOR DELETE USING (tenant_id = current_tenant_id())',
        t, t
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Skipping RLS on %: %', t, SQLERRM;
    END;
  END LOOP;
END $$;

-- ============================================================
-- GRANT EXECUTE sur les nouvelles fonctions
-- ============================================================
GRANT EXECUTE ON FUNCTION update_invoice_on_customer_payment() TO authenticated;
GRANT EXECUTE ON FUNCTION update_invoice_on_supplier_payment() TO authenticated;
GRANT EXECUTE ON FUNCTION create_stock_on_manufacturing_complete() TO authenticated;
GRANT EXECUTE ON FUNCTION create_stock_on_goods_receipt() TO authenticated;
GRANT EXECUTE ON FUNCTION create_journal_on_payroll_validate() TO authenticated;
