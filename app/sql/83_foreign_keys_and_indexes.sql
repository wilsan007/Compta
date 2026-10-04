-- ============================================================
-- 83_foreign_keys_and_indexes.sql
--
-- Ajout des clés étrangères manquantes (134 identifiées) et
-- des index composites critiques pour les performances.
--
-- Les FK sont ajoutées avec ON DELETE SET NULL pour éviter
-- les blocages lors de suppressions de références.
-- ============================================================

-- ============================================================
-- SECTION 1 — Clés étrangères critiques (intégrité référentielle)
-- ============================================================

-- invoices → delivery_notes, sales_orders, quotes, invoices (self-ref)
DO $$ BEGIN ALTER TABLE invoices ADD CONSTRAINT invoices_delivery_note_id_fkey FOREIGN KEY (delivery_note_id) REFERENCES delivery_notes(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP invoices.delivery_note_id: %', SQLERRM; END $$;
DO $$ BEGIN ALTER TABLE invoices ADD CONSTRAINT invoices_sales_order_id_fkey FOREIGN KEY (sales_order_id) REFERENCES sales_orders(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP invoices.sales_order_id: %', SQLERRM; END $$;
DO $$ BEGIN ALTER TABLE invoices ADD CONSTRAINT invoices_quote_id_fkey FOREIGN KEY (quote_id) REFERENCES quotes(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP invoices.quote_id: %', SQLERRM; END $$;
DO $$ BEGIN ALTER TABLE invoices ADD CONSTRAINT invoices_parent_invoice_id_fkey FOREIGN KEY (parent_invoice_id) REFERENCES invoices(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP invoices.parent_invoice_id: %', SQLERRM; END $$;

-- invoice_lines → delivery_note_lines, sales_order_lines
DO $$ BEGIN ALTER TABLE invoice_lines ADD CONSTRAINT invoice_lines_delivery_note_line_id_fkey FOREIGN KEY (delivery_note_line_id) REFERENCES delivery_note_lines(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP invoice_lines.delivery_note_line_id: %', SQLERRM; END $$;
DO $$ BEGIN ALTER TABLE invoice_lines ADD CONSTRAINT invoice_lines_sales_order_line_id_fkey FOREIGN KEY (sales_order_line_id) REFERENCES sales_order_lines(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP invoice_lines.sales_order_line_id: %', SQLERRM; END $$;

-- journal_lines → products, analytic_sections
DO $$ BEGIN ALTER TABLE journal_lines ADD CONSTRAINT journal_lines_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP journal_lines.product_id: %', SQLERRM; END $$;
DO $$ BEGIN ALTER TABLE journal_lines ADD CONSTRAINT journal_lines_analytic_section_id_fkey FOREIGN KEY (analytic_section_id) REFERENCES analytic_sections(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP journal_lines.analytic_section_id: %', SQLERRM; END $$;

-- customers → customers (self), sales_representatives, bank_accounts, price_lists
DO $$ BEGIN ALTER TABLE customers ADD CONSTRAINT customers_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES customers(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP customers.parent_id: %', SQLERRM; END $$;
DO $$ BEGIN ALTER TABLE customers ADD CONSTRAINT customers_sales_rep_id_fkey FOREIGN KEY (sales_rep_id) REFERENCES sales_representatives(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP customers.sales_rep_id: %', SQLERRM; END $$;
DO $$ BEGIN ALTER TABLE customers ADD CONSTRAINT customers_bank_account_id_fkey FOREIGN KEY (bank_account_id) REFERENCES bank_accounts(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP customers.bank_account_id: %', SQLERRM; END $$;
DO $$ BEGIN ALTER TABLE customers ADD CONSTRAINT customers_price_list_id_fkey FOREIGN KEY (price_list_id) REFERENCES price_lists(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP customers.price_list_id: %', SQLERRM; END $$;

-- suppliers → suppliers (self), sales_representatives, bank_accounts, price_lists
DO $$ BEGIN ALTER TABLE suppliers ADD CONSTRAINT suppliers_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES suppliers(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP suppliers.parent_id: %', SQLERRM; END $$;
DO $$ BEGIN ALTER TABLE suppliers ADD CONSTRAINT suppliers_sales_rep_id_fkey FOREIGN KEY (sales_rep_id) REFERENCES sales_representatives(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP suppliers.sales_rep_id: %', SQLERRM; END $$;
DO $$ BEGIN ALTER TABLE suppliers ADD CONSTRAINT suppliers_bank_account_id_fkey FOREIGN KEY (bank_account_id) REFERENCES bank_accounts(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP suppliers.bank_account_id: %', SQLERRM; END $$;
DO $$ BEGIN ALTER TABLE suppliers ADD CONSTRAINT suppliers_price_list_id_fkey FOREIGN KEY (price_list_id) REFERENCES price_lists(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP suppliers.price_list_id: %', SQLERRM; END $$;

-- bank_transactions → journal_entries
DO $$ BEGIN ALTER TABLE bank_transactions ADD CONSTRAINT bank_transactions_reconciled_entry_id_fkey FOREIGN KEY (reconciled_entry_id) REFERENCES journal_entries(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP bank_transactions.reconciled_entry_id: %', SQLERRM; END $$;

-- quotes → sales_orders
DO $$ BEGIN ALTER TABLE quotes ADD CONSTRAINT quotes_transformed_to_order_id_fkey FOREIGN KEY (transformed_to_order_id) REFERENCES sales_orders(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP quotes.transformed_to_order_id: %', SQLERRM; END $$;

-- sales_orders → quotes
DO $$ BEGIN ALTER TABLE sales_orders ADD CONSTRAINT sales_orders_quote_id_fkey FOREIGN KEY (quote_id) REFERENCES quotes(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP sales_orders.quote_id: %', SQLERRM; END $$;

-- tier_ribs → third_party_accounts
DO $$ BEGIN ALTER TABLE tier_ribs ADD CONSTRAINT tier_ribs_third_party_account_id_fkey FOREIGN KEY (third_party_account_id) REFERENCES third_party_accounts(id) ON DELETE CASCADE; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP tier_ribs.third_party_account_id: %', SQLERRM; END $$;

-- credit_notes → invoices (source_invoice_id)
DO $$ BEGIN ALTER TABLE credit_notes ADD CONSTRAINT credit_notes_source_invoice_id_fkey FOREIGN KEY (source_invoice_id) REFERENCES invoices(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP credit_notes.source_invoice_id: %', SQLERRM; END $$;

-- journal_entries → fiscal_periods, recurring_entries
DO $$ BEGIN ALTER TABLE journal_entries ADD CONSTRAINT journal_entries_fiscal_period_id_fkey FOREIGN KEY (fiscal_period_id) REFERENCES fiscal_periods(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP journal_entries.fiscal_period_id: %', SQLERRM; END $$;
DO $$ BEGIN ALTER TABLE journal_entries ADD CONSTRAINT journal_entries_entry_template_id_fkey FOREIGN KEY (entry_template_id) REFERENCES recurring_entries(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP journal_entries.entry_template_id: %', SQLERRM; END $$;

-- checks → journal_entries, customer_payments/supplier_payments
DO $$ BEGIN ALTER TABLE checks ADD CONSTRAINT checks_journal_entry_id_fkey FOREIGN KEY (journal_entry_id) REFERENCES journal_entries(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP checks.journal_entry_id: %', SQLERRM; END $$;

-- exchange_gain_loss_entries → journal_entries, invoices, customer_payments
DO $$ BEGIN ALTER TABLE exchange_gain_loss_entries ADD CONSTRAINT exgl_journal_entry_id_fkey FOREIGN KEY (journal_entry_id) REFERENCES journal_entries(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP exgl.journal_entry_id: %', SQLERRM; END $$;
DO $$ BEGIN ALTER TABLE exchange_gain_loss_entries ADD CONSTRAINT exgl_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES invoices(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP exgl.invoice_id: %', SQLERRM; END $$;

-- tax_cash_basis_entries → journal_entries
DO $$ BEGIN ALTER TABLE tax_cash_basis_entries ADD CONSTRAINT tcb_journal_entry_id_fkey FOREIGN KEY (journal_entry_id) REFERENCES journal_entries(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP tcb.journal_entry_id: %', SQLERRM; END $$;

-- tax_payments → journal_entries, bank_accounts
DO $$ BEGIN ALTER TABLE tax_payments ADD CONSTRAINT tax_payments_journal_entry_id_fkey FOREIGN KEY (journal_entry_id) REFERENCES journal_entries(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP tax_payments.journal_entry_id: %', SQLERRM; END $$;
DO $$ BEGIN ALTER TABLE tax_payments ADD CONSTRAINT tax_payments_bank_account_id_fkey FOREIGN KEY (bank_account_id) REFERENCES bank_accounts(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP tax_payments.bank_account_id: %', SQLERRM; END $$;

-- accounting_control_runs → fiscal_years, fiscal_periods
DO $$ BEGIN ALTER TABLE accounting_control_runs ADD CONSTRAINT acr_fiscal_year_id_fkey FOREIGN KEY (fiscal_year_id) REFERENCES fiscal_years(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP acr.fiscal_year_id: %', SQLERRM; END $$;
DO $$ BEGIN ALTER TABLE accounting_control_runs ADD CONSTRAINT acr_period_id_fkey FOREIGN KEY (period_id) REFERENCES fiscal_periods(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP acr.period_id: %', SQLERRM; END $$;

-- fec_attestations → fiscal_years
DO $$ BEGIN ALTER TABLE fec_attestations ADD CONSTRAINT fec_attest_fiscal_year_id_fkey FOREIGN KEY (fiscal_year_id) REFERENCES fiscal_years(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP fec_attestations.fiscal_year_id: %', SQLERRM; END $$;

-- fiscal_backups → fiscal_years
DO $$ BEGIN ALTER TABLE fiscal_backups ADD CONSTRAINT fiscal_backups_fiscal_year_id_fkey FOREIGN KEY (fiscal_year_id) REFERENCES fiscal_years(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP fiscal_backups.fiscal_year_id: %', SQLERRM; END $$;

-- partner_bank_accounts → customers/suppliers (partner_id polymorphic - skip if ambiguous)
-- partner_contacts → customers/suppliers (partner_id polymorphic - skip if ambiguous)

-- pay_recalls → pay_runs
DO $$ BEGIN ALTER TABLE pay_recalls ADD CONSTRAINT pay_recalls_processed_pay_run_id_fkey FOREIGN KEY (processed_pay_run_id) REFERENCES pay_runs(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP pay_recalls.processed_pay_run_id: %', SQLERRM; END $$;

-- payroll_variable_elements → pay_runs
DO $$ BEGIN ALTER TABLE payroll_variable_elements ADD CONSTRAINT pve_pay_run_id_fkey FOREIGN KEY (pay_run_id) REFERENCES pay_runs(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP pve.pay_run_id: %', SQLERRM; END $$;

-- sepa_payment_orders → pay_runs
DO $$ BEGIN ALTER TABLE sepa_payment_orders ADD CONSTRAINT spo_pay_run_id_fkey FOREIGN KEY (pay_run_id) REFERENCES pay_runs(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP spo.pay_run_id: %', SQLERRM; END $$;

-- ijss_history → pay_slips
DO $$ BEGIN ALTER TABLE ijss_history ADD CONSTRAINT ijss_payslip_id_fkey FOREIGN KEY (payslip_id) REFERENCES pay_slips(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP ijss.payslip_id: %', SQLERRM; END $$;

-- employee_exit_processes → pay_slips
DO $$ BEGIN ALTER TABLE employee_exit_processes ADD CONSTRAINT eep_exit_payslip_id_fkey FOREIGN KEY (exit_payslip_id) REFERENCES pay_slips(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP eep.exit_payslip_id: %', SQLERRM; END $$;

-- fixed_assets → journals, partners
DO $$ BEGIN ALTER TABLE fixed_assets ADD CONSTRAINT fa_journal_id_fkey FOREIGN KEY (journal_id) REFERENCES journals(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP fa.journal_id: %', SQLERRM; END $$;

-- recurring_entries → journals
DO $$ BEGIN ALTER TABLE recurring_entries ADD CONSTRAINT re_journal_id_fkey FOREIGN KEY (journal_id) REFERENCES journals(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP re.journal_id: %', SQLERRM; END $$;

-- regularization_entries → journal_entries, journals, fiscal_years
DO $$ BEGIN ALTER TABLE regularization_entries ADD CONSTRAINT reg_journal_id_fkey FOREIGN KEY (journal_id) REFERENCES journals(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP reg.journal_id: %', SQLERRM; END $$;
DO $$ BEGIN ALTER TABLE regularization_entries ADD CONSTRAINT reg_fiscal_year_id_fkey FOREIGN KEY (fiscal_year_id) REFERENCES fiscal_years(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP reg.fiscal_year_id: %', SQLERRM; END $$;
DO $$ BEGIN ALTER TABLE regularization_entries ADD CONSTRAINT reg_created_entry_id_fkey FOREIGN KEY (created_entry_id) REFERENCES journal_entries(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP reg.created_entry_id: %', SQLERRM; END $$;

-- ifrs_adjustments → journal_entries, fiscal_years
DO $$ BEGIN ALTER TABLE ifrs_adjustments ADD CONSTRAINT ifrs_journal_entry_id_fkey FOREIGN KEY (journal_entry_id) REFERENCES journal_entries(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP ifrs.journal_entry_id: %', SQLERRM; END $$;
DO $$ BEGIN ALTER TABLE ifrs_adjustments ADD CONSTRAINT ifrs_fiscal_year_id_fkey FOREIGN KEY (fiscal_year_id) REFERENCES fiscal_years(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP ifrs.fiscal_year_id: %', SQLERRM; END $$;

-- vat_on_collections → journal_entries, fiscal_years
DO $$ BEGIN ALTER TABLE vat_on_collections ADD CONSTRAINT voc_journal_entry_id_fkey FOREIGN KEY (journal_entry_id) REFERENCES journal_entries(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP voc.journal_entry_id: %', SQLERRM; END $$;
DO $$ BEGIN ALTER TABLE vat_on_collections ADD CONSTRAINT voc_fiscal_year_id_fkey FOREIGN KEY (fiscal_year_id) REFERENCES fiscal_years(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP voc.fiscal_year_id: %', SQLERRM; END $$;

-- carry_forward_log → journal_entries, fiscal_years
DO $$ BEGIN ALTER TABLE carry_forward_log ADD CONSTRAINT cfl_journal_entry_id_fkey FOREIGN KEY (journal_entry_id) REFERENCES journal_entries(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP cfl.journal_entry_id: %', SQLERRM; END $$;
DO $$ BEGIN ALTER TABLE carry_forward_log ADD CONSTRAINT cfl_source_fy_fkey FOREIGN KEY (source_fiscal_year_id) REFERENCES fiscal_years(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP cfl.source_fiscal_year_id: %', SQLERRM; END $$;
DO $$ BEGIN ALTER TABLE carry_forward_log ADD CONSTRAINT cfl_target_fy_fkey FOREIGN KEY (target_fiscal_year_id) REFERENCES fiscal_years(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP cfl.target_fiscal_year_id: %', SQLERRM; END $$;

-- compaction_logs → fiscal_years
DO $$ BEGIN ALTER TABLE compaction_logs ADD CONSTRAINT cl_fiscal_year_id_fkey FOREIGN KEY (fiscal_year_id) REFERENCES fiscal_years(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP cl.fiscal_year_id: %', SQLERRM; END $$;

-- currency_revaluations → journal_entries, fiscal_years
DO $$ BEGIN ALTER TABLE currency_revaluations ADD CONSTRAINT cr_entry_id_fkey FOREIGN KEY (entry_id) REFERENCES journal_entries(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP cr.entry_id: %', SQLERRM; END $$;
DO $$ BEGIN ALTER TABLE currency_revaluations ADD CONSTRAINT cr_fiscal_year_id_fkey FOREIGN KEY (fiscal_year_id) REFERENCES fiscal_years(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP cr.fiscal_year_id: %', SQLERRM; END $$;

-- leave_provisions → journal_entries
DO $$ BEGIN ALTER TABLE leave_provisions ADD CONSTRAINT lp_accounting_entry_id_fkey FOREIGN KEY (accounting_entry_id) REFERENCES journal_entries(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP lp.accounting_entry_id: %', SQLERRM; END $$;

-- honorarium_records → journal_entries
DO $$ BEGIN ALTER TABLE honorarium_records ADD CONSTRAINT hr_accounting_entry_id_fkey FOREIGN KEY (accounting_entry_id) REFERENCES journal_entries(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP hr.accounting_entry_id: %', SQLERRM; END $$;

-- treasury_transfers → journal_entries
DO $$ BEGIN ALTER TABLE treasury_transfers ADD CONSTRAINT tt_journal_entry_id_fkey FOREIGN KEY (journal_entry_id) REFERENCES journal_entries(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP tt.journal_entry_id: %', SQLERRM; END $$;

-- future_accounting_movements → journal_entries
DO $$ BEGIN ALTER TABLE future_accounting_movements ADD CONSTRAINT fam_incorporated_entry_id_fkey FOREIGN KEY (incorporated_entry_id) REFERENCES journal_entries(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP fam.incorporated_entry_id: %', SQLERRM; END $$;

-- extourne_log → journal_entries
DO $$ BEGIN ALTER TABLE extourne_log ADD CONSTRAINT el_original_entry_id_fkey FOREIGN KEY (original_entry_id) REFERENCES journal_entries(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP el.original_entry_id: %', SQLERRM; END $$;
DO $$ BEGIN ALTER TABLE extourne_log ADD CONSTRAINT el_extourne_entry_id_fkey FOREIGN KEY (extourne_entry_id) REFERENCES journal_entries(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP el.extourne_entry_id: %', SQLERRM; END $$;

-- reimputation_logs → journal_entries, journal_lines
DO $$ BEGIN ALTER TABLE reimputation_logs ADD CONSTRAINT rl_reimputed_entry_id_fkey FOREIGN KEY (reimputed_entry_id) REFERENCES journal_entries(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP rl.reimputed_entry_id: %', SQLERRM; END $$;

-- lettrage_differences → journal_entries
DO $$ BEGIN ALTER TABLE lettrage_differences ADD CONSTRAINT ld_generated_entry_id_fkey FOREIGN KEY (generated_entry_id) REFERENCES journal_entries(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP ld.generated_entry_id: %', SQLERRM; END $$;

-- delivery_note_lines → sales_order_lines
DO $$ BEGIN ALTER TABLE delivery_note_lines ADD CONSTRAINT dnl_sales_order_line_id_fkey FOREIGN KEY (sales_order_line_id) REFERENCES sales_order_lines(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP dnl.sales_order_line_id: %', SQLERRM; END $$;

-- stock_movements → warehouses
DO $$ BEGIN ALTER TABLE stock_movements ADD CONSTRAINT sm_warehouse_id_fkey FOREIGN KEY (warehouse_id) REFERENCES warehouses(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP sm.warehouse_id: %', SQLERRM; END $$;

-- expense_reports → employees (manager_id)
DO $$ BEGIN ALTER TABLE expense_reports ADD CONSTRAINT er_manager_id_fkey FOREIGN KEY (manager_id) REFERENCES employees(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP er.manager_id: %', SQLERRM; END $$;

-- projects → employees (manager_id)
DO $$ BEGIN ALTER TABLE projects ADD CONSTRAINT proj_manager_id_fkey FOREIGN KEY (manager_id) REFERENCES employees(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP proj.manager_id: %', SQLERRM; END $$;

-- third_party_accounts → bank_accounts (default_bank_account_id)
DO $$ BEGIN ALTER TABLE third_party_accounts ADD CONSTRAINT tpa_default_bank_account_id_fkey FOREIGN KEY (default_bank_account_id) REFERENCES bank_accounts(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP tpa.default_bank_account_id: %', SQLERRM; END $$;

-- etat_rapprochement → bank_accounts
DO $$ BEGIN ALTER TABLE etat_rapprochement ADD CONSTRAINT er_bank_account_id_fkey FOREIGN KEY (bank_account_id) REFERENCES bank_accounts(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP er.bank_account_id: %', SQLERRM; END $$;

-- justificatif_solde → fiscal_periods
DO $$ BEGIN ALTER TABLE justificatif_solde ADD CONSTRAINT js_fiscal_period_id_fkey FOREIGN KEY (fiscal_period_id) REFERENCES fiscal_periods(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP js.fiscal_period_id: %', SQLERRM; END $$;

-- partner_categories self-reference
DO $$ BEGIN ALTER TABLE partner_categories ADD CONSTRAINT pc_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES partner_categories(id) ON DELETE SET NULL; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'SKIP pc.parent_id: %', SQLERRM; END $$;


-- ============================================================
-- SECTION 2 — Index composites pour requêtes fréquentes
-- ============================================================
-- Ces index accélèrent les filtres par tenant + statut + date
-- qui sont les patterns de requête les plus fréquents.

-- Factures
CREATE INDEX IF NOT EXISTS idx_invoices_tenant_status_date ON invoices(tenant_id, status, date);
CREATE INDEX IF NOT EXISTS idx_invoices_tenant_customer_status ON invoices(tenant_id, customer_id, status);
CREATE INDEX IF NOT EXISTS idx_invoices_tenant_date ON invoices(tenant_id, date DESC);
CREATE INDEX IF NOT EXISTS idx_invoices_tenant_payment_state ON invoices(tenant_id, payment_state);

-- Factures d'achat
CREATE INDEX IF NOT EXISTS idx_purchase_invoices_tenant_status_date ON purchase_invoices(tenant_id, status, date);
CREATE INDEX IF NOT EXISTS idx_purchase_invoices_tenant_supplier ON purchase_invoices(tenant_id, supplier_id, status);
CREATE INDEX IF NOT EXISTS idx_purchase_invoices_tenant_date ON purchase_invoices(tenant_id, date DESC);

-- Devis
CREATE INDEX IF NOT EXISTS idx_quotes_tenant_status_date ON quotes(tenant_id, status, date);
CREATE INDEX IF NOT EXISTS idx_quotes_tenant_customer ON quotes(tenant_id, customer_id);

-- Commandes de vente
CREATE INDEX IF NOT EXISTS idx_sales_orders_tenant_status ON sales_orders(tenant_id, status, order_date);
CREATE INDEX IF NOT EXISTS idx_sales_orders_tenant_customer ON sales_orders(tenant_id, customer_id);

-- Commandes d'achat
CREATE INDEX IF NOT EXISTS idx_purchase_orders_tenant_status ON purchase_orders(tenant_id, status, order_date);
CREATE INDEX IF NOT EXISTS idx_purchase_orders_tenant_supplier ON purchase_orders(tenant_id, supplier_id);

-- Écritures comptables
CREATE INDEX IF NOT EXISTS idx_journal_entries_tenant_status_date ON journal_entries(tenant_id, status, date);
CREATE INDEX IF NOT EXISTS idx_journal_entries_tenant_journal_code ON journal_entries(tenant_id, journal_code, date);
CREATE INDEX IF NOT EXISTS idx_journal_entries_tenant_date ON journal_entries(tenant_id, date DESC);

-- Lignes d'écritures
CREATE INDEX IF NOT EXISTS idx_journal_lines_tenant_journal_id ON journal_lines(tenant_id, journal_id);
CREATE INDEX IF NOT EXISTS idx_journal_lines_tenant_account_code ON journal_lines(tenant_id, account_code);

-- Paiements clients
CREATE INDEX IF NOT EXISTS idx_customer_payments_tenant_date ON customer_payments(tenant_id, payment_date DESC);
CREATE INDEX IF NOT EXISTS idx_customer_payments_tenant_invoice ON customer_payments(tenant_id, invoice_id);

-- Paiements fournisseurs
CREATE INDEX IF NOT EXISTS idx_supplier_payments_tenant_date ON supplier_payments(tenant_id, payment_date DESC);
CREATE INDEX IF NOT EXISTS idx_supplier_payments_tenant_invoice ON supplier_payments(tenant_id, purchase_invoice_id);

-- Transactions bancaires
CREATE INDEX IF NOT EXISTS idx_bank_transactions_tenant_date ON bank_transactions(tenant_id, date DESC);
CREATE INDEX IF NOT EXISTS idx_bank_transactions_tenant_account ON bank_transactions(tenant_id, account_id, date DESC);
CREATE INDEX IF NOT EXISTS idx_bank_transactions_tenant_reconciled ON bank_transactions(tenant_id, reconciled) WHERE reconciled = false;

-- Mouvements de stock
CREATE INDEX IF NOT EXISTS idx_stock_movements_tenant_product ON stock_movements(tenant_id, product_id);
CREATE INDEX IF NOT EXISTS idx_stock_movements_tenant_date ON stock_movements(tenant_id, movement_date DESC);
CREATE INDEX IF NOT EXISTS idx_stock_movements_tenant_type ON stock_movements(tenant_id, movement_type);

-- Employés
CREATE INDEX IF NOT EXISTS idx_employees_tenant_active ON employees(tenant_id) WHERE status = 'active';
CREATE INDEX IF NOT EXISTS idx_employees_tenant_department ON employees(tenant_id, department);

-- Bulletins de paie
CREATE INDEX IF NOT EXISTS idx_pay_slips_tenant_period ON pay_slips(tenant_id, period_start);
CREATE INDEX IF NOT EXISTS idx_pay_slips_tenant_employee ON pay_slips(tenant_id, employee_id);

-- Pay runs
CREATE INDEX IF NOT EXISTS idx_pay_runs_tenant_status ON pay_runs(tenant_id, status);
CREATE INDEX IF NOT EXISTS idx_pay_runs_tenant_period ON pay_runs(tenant_id, period_start);

-- Notes de frais
CREATE INDEX IF NOT EXISTS idx_expense_reports_tenant_status ON expense_reports(tenant_id, status);
CREATE INDEX IF NOT EXISTS idx_expense_reports_tenant_employee ON expense_reports(tenant_id, employee_id);

-- Congés
CREATE INDEX IF NOT EXISTS idx_leave_requests_tenant_status ON leave_requests(tenant_id, status);
CREATE INDEX IF NOT EXISTS idx_leave_requests_tenant_employee ON leave_requests(tenant_id, employee_id);

-- Timesheets
CREATE INDEX IF NOT EXISTS idx_timesheets_tenant_status ON timesheets(tenant_id, status);
CREATE INDEX IF NOT EXISTS idx_timesheets_tenant_employee_date ON timesheets(tenant_id, employee_id, date);

-- Opportunités CRM
CREATE INDEX IF NOT EXISTS idx_crm_opportunities_tenant_stage ON crm_opportunities(tenant_id, stage);
CREATE INDEX IF NOT EXISTS idx_crm_opportunities_tenant_customer ON crm_opportunities(tenant_id, customer_id);

-- Projets
CREATE INDEX IF NOT EXISTS idx_projects_tenant_status ON projects(tenant_id, status);
CREATE INDEX IF NOT EXISTS idx_projects_tenant_manager ON projects(tenant_id, manager_id);

-- Tâches de projet
CREATE INDEX IF NOT EXISTS idx_project_tasks_tenant_project ON project_tasks(tenant_id, project_id);
CREATE INDEX IF NOT EXISTS idx_project_tasks_tenant_status ON project_tasks(tenant_id, status);

-- Produits
CREATE INDEX IF NOT EXISTS idx_products_tenant_active ON products(tenant_id) WHERE active = true;
CREATE INDEX IF NOT EXISTS idx_products_tenant_category ON products(tenant_id, category);

-- Clients
CREATE INDEX IF NOT EXISTS idx_customers_tenant_active ON customers(tenant_id) WHERE active = true;
CREATE INDEX IF NOT EXISTS idx_customers_tenant_name ON customers(tenant_id, name);

-- Fournisseurs
CREATE INDEX IF NOT EXISTS idx_suppliers_tenant_active ON suppliers(tenant_id) WHERE active = true;
CREATE INDEX IF NOT EXISTS idx_suppliers_tenant_name ON suppliers(tenant_id, name);

-- Réceptions
CREATE INDEX IF NOT EXISTS idx_goods_receipts_tenant_status ON goods_receipts(tenant_id, status);
CREATE INDEX IF NOT EXISTS idx_goods_receipts_tenant_po ON goods_receipts(tenant_id, purchase_order_id);

-- Ordres de fabrication
CREATE INDEX IF NOT EXISTS idx_manufacturing_orders_tenant_status ON manufacturing_orders(tenant_id, status);
CREATE INDEX IF NOT EXISTS idx_manufacturing_orders_tenant_product ON manufacturing_orders(tenant_id, product_id);

-- Livraisons
CREATE INDEX IF NOT EXISTS idx_delivery_notes_tenant_status ON delivery_notes(tenant_id, status);
CREATE INDEX IF NOT EXISTS idx_delivery_notes_tenant_customer ON delivery_notes(tenant_id, customer_id);

-- Contrôles qualité
CREATE INDEX IF NOT EXISTS idx_quality_checks_tenant_status ON quality_checks(tenant_id, status);

-- DSN
CREATE INDEX IF NOT EXISTS idx_dsn_declarations_tenant_period ON dsn_declarations(tenant_id, period);
CREATE INDEX IF NOT EXISTS idx_dsn_declarations_tenant_status ON dsn_declarations(tenant_id, status);

-- Avances sur salaire
CREATE INDEX IF NOT EXISTS idx_salary_advances_tenant_status ON salary_advances(tenant_id, status);
CREATE INDEX IF NOT EXISTS idx_salary_advances_tenant_employee ON salary_advances(tenant_id, employee_id);

-- Rappels de paie
CREATE INDEX IF NOT EXISTS idx_pay_recalls_tenant_status ON pay_recalls(tenant_id, status);

-- Éléments variables de paie
CREATE INDEX IF NOT EXISTS idx_payroll_variable_elements_tenant_period ON payroll_variable_elements(tenant_id, period);
CREATE INDEX IF NOT EXISTS idx_payroll_variable_elements_tenant_employee ON payroll_variable_elements(tenant_id, employee_id);
CREATE INDEX IF NOT EXISTS idx_payroll_variable_elements_tenant_payrun ON payroll_variable_elements(tenant_id, pay_run_id);

-- Notifications
CREATE INDEX IF NOT EXISTS idx_notification_email_queue_tenant_status ON notification_email_queue(tenant_id, status);

-- Documents
CREATE INDEX IF NOT EXISTS idx_module_documents_tenant_entity ON module_documents(tenant_id, entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_module_documents_tenant_type ON module_documents(tenant_id, document_type);

-- Audit log
CREATE INDEX IF NOT EXISTS idx_audit_log_tenant_entity ON audit_log(tenant_id, entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_tenant_created ON audit_log(tenant_id, created_at DESC);


-- ============================================================
-- SECTION 3 — Index sur clés étrangères non indexées
-- ============================================================
-- Ces index accélèrent les JOIN et les suppressions en cascade.

CREATE INDEX IF NOT EXISTS idx_invoices_delivery_note_id ON invoices(delivery_note_id) WHERE delivery_note_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_invoices_sales_order_id ON invoices(sales_order_id) WHERE sales_order_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_invoices_quote_id ON invoices(quote_id) WHERE quote_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_invoices_parent_invoice_id ON invoices(parent_invoice_id) WHERE parent_invoice_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_invoice_lines_delivery_note_line_id ON invoice_lines(delivery_note_line_id) WHERE delivery_note_line_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_invoice_lines_sales_order_line_id ON invoice_lines(sales_order_line_id) WHERE sales_order_line_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_journal_lines_product_id ON journal_lines(product_id) WHERE product_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_journal_lines_third_party_id ON journal_lines(third_party_id) WHERE third_party_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_journal_lines_analytic_section_id ON journal_lines(analytic_section_id) WHERE analytic_section_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_customers_parent_id ON customers(parent_id) WHERE parent_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_customers_sales_rep_id ON customers(sales_rep_id) WHERE sales_rep_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_customers_bank_account_id ON customers(bank_account_id) WHERE bank_account_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_customers_price_list_id ON customers(price_list_id) WHERE price_list_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_suppliers_parent_id ON suppliers(parent_id) WHERE parent_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_suppliers_sales_rep_id ON suppliers(sales_rep_id) WHERE sales_rep_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_suppliers_bank_account_id ON suppliers(bank_account_id) WHERE bank_account_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_suppliers_price_list_id ON suppliers(price_list_id) WHERE price_list_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_bank_transactions_reconciled_entry_id ON bank_transactions(reconciled_entry_id) WHERE reconciled_entry_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_bank_transactions_invoice_id ON bank_transactions(invoice_id) WHERE invoice_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_bank_transactions_purchase_invoice_id ON bank_transactions(purchase_invoice_id) WHERE purchase_invoice_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_credit_notes_source_invoice_id ON credit_notes(source_invoice_id) WHERE source_invoice_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_quotes_transformed_to_order_id ON quotes(transformed_to_order_id) WHERE transformed_to_order_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_sales_orders_quote_id ON sales_orders(quote_id) WHERE quote_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_stock_movements_warehouse_id ON stock_movements(warehouse_id) WHERE warehouse_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_tier_ribs_third_party_account_id ON tier_ribs(third_party_account_id);

-- ============================================================
-- RÉCAPITULATIF
-- ============================================================
-- Section 1 : ~60 FK ajoutées sur les tables critiques
-- Section 2 : ~60 index composites pour les requêtes fréquentes
-- Section 3 : ~25 index sur FK non indexées
-- Total : ~145 objets créés
-- ============================================================
