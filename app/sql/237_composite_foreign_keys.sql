-- ============================================================
-- 237_composite_foreign_keys.sql — ISO-02 : référencer chez le voisin
--
-- GÉNÉRÉ par scripts/generate-composite-fks.mjs — ne pas éditer à la main.
-- Relevé du 2026-09-24 : 408 clé(s) mono-colonne(s)
-- reliant deux tables cloisonnées, sur 219 table(s)
-- enfant, et 97 contrainte(s) d'unicité à poser avant que la clé
-- composite ne puisse exister (PostgreSQL exige que les colonnes référencées
-- portent une unicité).
--
-- LA FORME. La référence devient `(tenant_id, colonne)` : la société de l'enfant est
-- comparée à celle du parent, dans les DONNÉES. Un `UPDATE` de société ne peut plus
-- « emporter » la référence, et un `INSERT` inter-sociétés est refusé pour tout le
-- monde — `service_role` et déclencheurs `SECURITY DEFINER` compris, ce que la RLS ne
-- peut pas faire puisqu'elle ne les voit pas.
--
-- CE QUE LA MIGRATION NE FAIT PAS. Elle ne devine rien : si des lignes violent déjà la
-- clé, elle échoue et les nomme — jamais de `NOT VALID`, qui laisserait le défaut
-- derrière un nom de contrainte. Une ligne dont `tenant_id` est NULL (ligne système)
-- reste hors du contrôle : en `MATCH SIMPLE`, un NULL dispense de la vérification —
-- c'est voulu, ces lignes n'appartiennent à personne.
--
-- LES ACTIONS DE SUPPRESSION SONT RECOPIÉES, jamais réinventées, et avec leur
-- liste de colonnes : `ON DELETE SET NULL (colonne)` détache la seule colonne
-- concernée. Sans cette liste, une clé composite annulerait aussi `tenant_id` —
-- NOT NULL — et la suppression du parent échouerait au lieu de détacher.
-- ============================================================

-- ── 1. Les unicité des parents : (tenant_id, colonne référencée) ──────────

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'account_tags_tenant_id_id_key' AND conrelid = 'public.account_tags'::regclass) THEN
    ALTER TABLE public.account_tags ADD CONSTRAINT account_tags_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'fiscal_years_tenant_id_id_key' AND conrelid = 'public.fiscal_years'::regclass) THEN
    ALTER TABLE public.fiscal_years ADD CONSTRAINT fiscal_years_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'fiscal_periods_tenant_id_id_key' AND conrelid = 'public.fiscal_periods'::regclass) THEN
    ALTER TABLE public.fiscal_periods ADD CONSTRAINT fiscal_periods_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'journal_lines_tenant_id_id_key' AND conrelid = 'public.journal_lines'::regclass) THEN
    ALTER TABLE public.journal_lines ADD CONSTRAINT journal_lines_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'analytic_plans_tenant_id_id_key' AND conrelid = 'public.analytic_plans'::regclass) THEN
    ALTER TABLE public.analytic_plans ADD CONSTRAINT analytic_plans_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'analytic_sections_tenant_id_id_key' AND conrelid = 'public.analytic_sections'::regclass) THEN
    ALTER TABLE public.analytic_sections ADD CONSTRAINT analytic_sections_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'fixed_assets_tenant_id_id_key' AND conrelid = 'public.fixed_assets'::regclass) THEN
    ALTER TABLE public.fixed_assets ADD CONSTRAINT fixed_assets_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'asset_batch_disposals_tenant_id_id_key' AND conrelid = 'public.asset_batch_disposals'::regclass) THEN
    ALTER TABLE public.asset_batch_disposals ADD CONSTRAINT asset_batch_disposals_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'asset_families_tenant_id_id_key' AND conrelid = 'public.asset_families'::regclass) THEN
    ALTER TABLE public.asset_families ADD CONSTRAINT asset_families_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'asset_splits_tenant_id_id_key' AND conrelid = 'public.asset_splits'::regclass) THEN
    ALTER TABLE public.asset_splits ADD CONSTRAINT asset_splits_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'employees_tenant_id_id_key' AND conrelid = 'public.employees'::regclass) THEN
    ALTER TABLE public.employees ADD CONSTRAINT employees_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'users_tenant_id_id_key' AND conrelid = 'public.users'::regclass) THEN
    ALTER TABLE public.users ADD CONSTRAINT users_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'bank_accounts_tenant_id_id_key' AND conrelid = 'public.bank_accounts'::regclass) THEN
    ALTER TABLE public.bank_accounts ADD CONSTRAINT bank_accounts_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'invoices_tenant_id_id_key' AND conrelid = 'public.invoices'::regclass) THEN
    ALTER TABLE public.invoices ADD CONSTRAINT invoices_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'purchase_invoices_tenant_id_id_key' AND conrelid = 'public.purchase_invoices'::regclass) THEN
    ALTER TABLE public.purchase_invoices ADD CONSTRAINT purchase_invoices_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'journal_entries_tenant_id_id_key' AND conrelid = 'public.journal_entries'::regclass) THEN
    ALTER TABLE public.journal_entries ADD CONSTRAINT journal_entries_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'boms_tenant_id_id_key' AND conrelid = 'public.boms'::regclass) THEN
    ALTER TABLE public.boms ADD CONSTRAINT boms_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'products_tenant_id_id_key' AND conrelid = 'public.products'::regclass) THEN
    ALTER TABLE public.products ADD CONSTRAINT products_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'routings_tenant_id_id_key' AND conrelid = 'public.routings'::regclass) THEN
    ALTER TABLE public.routings ADD CONSTRAINT routings_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'suppliers_tenant_id_id_key' AND conrelid = 'public.suppliers'::regclass) THEN
    ALTER TABLE public.suppliers ADD CONSTRAINT suppliers_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'chart_accounts_tenant_id_id_key' AND conrelid = 'public.chart_accounts'::regclass) THEN
    ALTER TABLE public.chart_accounts ADD CONSTRAINT chart_accounts_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'check_books_tenant_id_id_key' AND conrelid = 'public.check_books'::regclass) THEN
    ALTER TABLE public.check_books ADD CONSTRAINT check_books_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'customers_tenant_id_id_key' AND conrelid = 'public.customers'::regclass) THEN
    ALTER TABLE public.customers ADD CONSTRAINT customers_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'disputes_tenant_id_id_key' AND conrelid = 'public.disputes'::regclass) THEN
    ALTER TABLE public.disputes ADD CONSTRAINT disputes_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'payment_promises_tenant_id_id_key' AND conrelid = 'public.payment_promises'::regclass) THEN
    ALTER TABLE public.payment_promises ADD CONSTRAINT payment_promises_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'reminder_levels_tenant_id_id_key' AND conrelid = 'public.reminder_levels'::regclass) THEN
    ALTER TABLE public.reminder_levels ADD CONSTRAINT reminder_levels_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'third_party_accounts_tenant_id_id_key' AND conrelid = 'public.third_party_accounts'::regclass) THEN
    ALTER TABLE public.third_party_accounts ADD CONSTRAINT third_party_accounts_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'collective_agreements_tenant_id_id_key' AND conrelid = 'public.collective_agreements'::regclass) THEN
    ALTER TABLE public.collective_agreements ADD CONSTRAINT collective_agreements_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'legislation_packs_tenant_id_code_key' AND conrelid = 'public.legislation_packs'::regclass) THEN
    ALTER TABLE public.legislation_packs ADD CONSTRAINT legislation_packs_tenant_id_code_key UNIQUE ("tenant_id", "code");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'credit_notes_tenant_id_id_key' AND conrelid = 'public.credit_notes'::regclass) THEN
    ALTER TABLE public.credit_notes ADD CONSTRAINT credit_notes_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'crm_opportunities_tenant_id_id_key' AND conrelid = 'public.crm_opportunities'::regclass) THEN
    ALTER TABLE public.crm_opportunities ADD CONSTRAINT crm_opportunities_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'crm_campaigns_tenant_id_id_key' AND conrelid = 'public.crm_campaigns'::regclass) THEN
    ALTER TABLE public.crm_campaigns ADD CONSTRAINT crm_campaigns_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'prospects_tenant_id_id_key' AND conrelid = 'public.prospects'::regclass) THEN
    ALTER TABLE public.prospects ADD CONSTRAINT prospects_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'sales_representatives_tenant_id_id_key' AND conrelid = 'public.sales_representatives'::regclass) THEN
    ALTER TABLE public.sales_representatives ADD CONSTRAINT sales_representatives_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'crm_territories_tenant_id_id_key' AND conrelid = 'public.crm_territories'::regclass) THEN
    ALTER TABLE public.crm_territories ADD CONSTRAINT crm_territories_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'price_lists_tenant_id_id_key' AND conrelid = 'public.price_lists'::regclass) THEN
    ALTER TABLE public.price_lists ADD CONSTRAINT price_lists_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'delivery_notes_tenant_id_id_key' AND conrelid = 'public.delivery_notes'::regclass) THEN
    ALTER TABLE public.delivery_notes ADD CONSTRAINT delivery_notes_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'sales_order_lines_tenant_id_id_key' AND conrelid = 'public.sales_order_lines'::regclass) THEN
    ALTER TABLE public.sales_order_lines ADD CONSTRAINT sales_order_lines_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'sales_orders_tenant_id_id_key' AND conrelid = 'public.sales_orders'::regclass) THEN
    ALTER TABLE public.sales_orders ADD CONSTRAINT sales_orders_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'distribution_grills_tenant_id_id_key' AND conrelid = 'public.distribution_grills'::regclass) THEN
    ALTER TABLE public.distribution_grills ADD CONSTRAINT distribution_grills_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'employee_documents_tenant_id_id_key' AND conrelid = 'public.employee_documents'::regclass) THEN
    ALTER TABLE public.employee_documents ADD CONSTRAINT employee_documents_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'pay_slips_tenant_id_id_key' AND conrelid = 'public.pay_slips'::regclass) THEN
    ALTER TABLE public.pay_slips ADD CONSTRAINT pay_slips_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'interview_campaigns_tenant_id_id_key' AND conrelid = 'public.interview_campaigns'::regclass) THEN
    ALTER TABLE public.interview_campaigns ADD CONSTRAINT interview_campaigns_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'collective_classifications_tenant_id_id_key' AND conrelid = 'public.collective_classifications'::regclass) THEN
    ALTER TABLE public.collective_classifications ADD CONSTRAINT collective_classifications_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'expense_categories_tenant_id_id_key' AND conrelid = 'public.expense_categories'::regclass) THEN
    ALTER TABLE public.expense_categories ADD CONSTRAINT expense_categories_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'expense_reports_tenant_id_id_key' AND conrelid = 'public.expense_reports'::regclass) THEN
    ALTER TABLE public.expense_reports ADD CONSTRAINT expense_reports_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'fiscal_positions_tenant_id_id_key' AND conrelid = 'public.fiscal_positions'::regclass) THEN
    ALTER TABLE public.fiscal_positions ADD CONSTRAINT fiscal_positions_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'tax_rates_tenant_id_id_key' AND conrelid = 'public.tax_rates'::regclass) THEN
    ALTER TABLE public.tax_rates ADD CONSTRAINT tax_rates_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'journals_tenant_id_id_key' AND conrelid = 'public.journals'::regclass) THEN
    ALTER TABLE public.journals ADD CONSTRAINT journals_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'goods_receipts_tenant_id_id_key' AND conrelid = 'public.goods_receipts'::regclass) THEN
    ALTER TABLE public.goods_receipts ADD CONSTRAINT goods_receipts_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'purchase_orders_tenant_id_id_key' AND conrelid = 'public.purchase_orders'::regclass) THEN
    ALTER TABLE public.purchase_orders ADD CONSTRAINT purchase_orders_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'work_stoppages_tenant_id_id_key' AND conrelid = 'public.work_stoppages'::regclass) THEN
    ALTER TABLE public.work_stoppages ADD CONSTRAINT work_stoppages_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'delivery_note_lines_tenant_id_id_key' AND conrelid = 'public.delivery_note_lines'::regclass) THEN
    ALTER TABLE public.delivery_note_lines ADD CONSTRAINT delivery_note_lines_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'quotes_tenant_id_id_key' AND conrelid = 'public.quotes'::regclass) THEN
    ALTER TABLE public.quotes ADD CONSTRAINT quotes_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'recurring_entries_tenant_id_id_key' AND conrelid = 'public.recurring_entries'::regclass) THEN
    ALTER TABLE public.recurring_entries ADD CONSTRAINT recurring_entries_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'landed_costs_tenant_id_id_key' AND conrelid = 'public.landed_costs'::regclass) THEN
    ALTER TABLE public.landed_costs ADD CONSTRAINT landed_costs_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'work_centers_tenant_id_id_key' AND conrelid = 'public.work_centers'::regclass) THEN
    ALTER TABLE public.work_centers ADD CONSTRAINT work_centers_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'maintenance_plans_tenant_id_id_key' AND conrelid = 'public.maintenance_plans'::regclass) THEN
    ALTER TABLE public.maintenance_plans ADD CONSTRAINT maintenance_plans_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'manufacturing_orders_tenant_id_id_key' AND conrelid = 'public.manufacturing_orders'::regclass) THEN
    ALTER TABLE public.manufacturing_orders ADD CONSTRAINT manufacturing_orders_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'warehouses_tenant_id_id_key' AND conrelid = 'public.warehouses'::regclass) THEN
    ALTER TABLE public.warehouses ADD CONSTRAINT warehouses_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'mirror_servers_tenant_id_id_key' AND conrelid = 'public.mirror_servers'::regclass) THEN
    ALTER TABLE public.mirror_servers ADD CONSTRAINT mirror_servers_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'module_documents_tenant_id_id_key' AND conrelid = 'public.module_documents'::regclass) THEN
    ALTER TABLE public.module_documents ADD CONSTRAINT module_documents_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'tenant_users_tenant_id_id_key' AND conrelid = 'public.tenant_users'::regclass) THEN
    ALTER TABLE public.tenant_users ADD CONSTRAINT tenant_users_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'mrp_runs_tenant_id_id_key' AND conrelid = 'public.mrp_runs'::regclass) THEN
    ALTER TABLE public.mrp_runs ADD CONSTRAINT mrp_runs_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'partner_categories_tenant_id_id_key' AND conrelid = 'public.partner_categories'::regclass) THEN
    ALTER TABLE public.partner_categories ADD CONSTRAINT partner_categories_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'pay_runs_tenant_id_id_key' AND conrelid = 'public.pay_runs'::regclass) THEN
    ALTER TABLE public.pay_runs ADD CONSTRAINT pay_runs_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'payroll_components_tenant_id_id_key' AND conrelid = 'public.payroll_components'::regclass) THEN
    ALTER TABLE public.payroll_components ADD CONSTRAINT payroll_components_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'warehouse_locations_tenant_id_id_key' AND conrelid = 'public.warehouse_locations'::regclass) THEN
    ALTER TABLE public.warehouse_locations ADD CONSTRAINT warehouse_locations_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'pick_lists_tenant_id_id_key' AND conrelid = 'public.pick_lists'::regclass) THEN
    ALTER TABLE public.pick_lists ADD CONSTRAINT pick_lists_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'machines_tenant_id_id_key' AND conrelid = 'public.machines'::regclass) THEN
    ALTER TABLE public.machines ADD CONSTRAINT machines_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'routing_operations_tenant_id_id_key' AND conrelid = 'public.routing_operations'::regclass) THEN
    ALTER TABLE public.routing_operations ADD CONSTRAINT routing_operations_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'pos_terminals_tenant_id_id_key' AND conrelid = 'public.pos_terminals'::regclass) THEN
    ALTER TABLE public.pos_terminals ADD CONSTRAINT pos_terminals_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'pos_tickets_tenant_id_id_key' AND conrelid = 'public.pos_tickets'::regclass) THEN
    ALTER TABLE public.pos_tickets ADD CONSTRAINT pos_tickets_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'pos_sessions_tenant_id_id_key' AND conrelid = 'public.pos_sessions'::regclass) THEN
    ALTER TABLE public.pos_sessions ADD CONSTRAINT pos_sessions_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'product_categories_tenant_id_id_key' AND conrelid = 'public.product_categories'::regclass) THEN
    ALTER TABLE public.product_categories ADD CONSTRAINT product_categories_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'uoms_tenant_id_id_key' AND conrelid = 'public.uoms'::regclass) THEN
    ALTER TABLE public.uoms ADD CONSTRAINT uoms_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'projects_tenant_id_id_key' AND conrelid = 'public.projects'::regclass) THEN
    ALTER TABLE public.projects ADD CONSTRAINT projects_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'project_tasks_tenant_id_id_key' AND conrelid = 'public.project_tasks'::regclass) THEN
    ALTER TABLE public.project_tasks ADD CONSTRAINT project_tasks_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'project_tags_tenant_id_id_key' AND conrelid = 'public.project_tags'::regclass) THEN
    ALTER TABLE public.project_tags ADD CONSTRAINT project_tags_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'project_milestones_tenant_id_id_key' AND conrelid = 'public.project_milestones'::regclass) THEN
    ALTER TABLE public.project_milestones ADD CONSTRAINT project_milestones_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'purchase_credit_notes_tenant_id_id_key' AND conrelid = 'public.purchase_credit_notes'::regclass) THEN
    ALTER TABLE public.purchase_credit_notes ADD CONSTRAINT purchase_credit_notes_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'purchase_order_lines_tenant_id_id_key' AND conrelid = 'public.purchase_order_lines'::regclass) THEN
    ALTER TABLE public.purchase_order_lines ADD CONSTRAINT purchase_order_lines_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'purchase_requests_tenant_id_id_key' AND conrelid = 'public.purchase_requests'::regclass) THEN
    ALTER TABLE public.purchase_requests ADD CONSTRAINT purchase_requests_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'quality_control_plans_tenant_id_id_key' AND conrelid = 'public.quality_control_plans'::regclass) THEN
    ALTER TABLE public.quality_control_plans ADD CONSTRAINT quality_control_plans_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'tenant_roles_tenant_id_id_key' AND conrelid = 'public.tenant_roles'::regclass) THEN
    ALTER TABLE public.tenant_roles ADD CONSTRAINT tenant_roles_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'toolings_tenant_id_id_key' AND conrelid = 'public.toolings'::regclass) THEN
    ALTER TABLE public.toolings ADD CONSTRAINT toolings_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'service_tickets_tenant_id_id_key' AND conrelid = 'public.service_tickets'::regclass) THEN
    ALTER TABLE public.service_tickets ADD CONSTRAINT service_tickets_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'customer_contacts_tenant_id_id_key' AND conrelid = 'public.customer_contacts'::regclass) THEN
    ALTER TABLE public.customer_contacts ADD CONSTRAINT customer_contacts_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'st_receipts_tenant_id_id_key' AND conrelid = 'public.st_receipts'::regclass) THEN
    ALTER TABLE public.st_receipts ADD CONSTRAINT st_receipts_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'st_orders_tenant_id_id_key' AND conrelid = 'public.st_orders'::regclass) THEN
    ALTER TABLE public.st_orders ADD CONSTRAINT st_orders_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'st_shipments_tenant_id_id_key' AND conrelid = 'public.st_shipments'::regclass) THEN
    ALTER TABLE public.st_shipments ADD CONSTRAINT st_shipments_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'stock_transfers_tenant_id_id_key' AND conrelid = 'public.stock_transfers'::regclass) THEN
    ALTER TABLE public.stock_transfers ADD CONSTRAINT stock_transfers_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'supplier_price_lists_tenant_id_id_key' AND conrelid = 'public.supplier_price_lists'::regclass) THEN
    ALTER TABLE public.supplier_price_lists ADD CONSTRAINT supplier_price_lists_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'task_actions_tenant_id_id_key' AND conrelid = 'public.task_actions'::regclass) THEN
    ALTER TABLE public.task_actions ADD CONSTRAINT task_actions_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'payment_terms_tenant_id_id_key' AND conrelid = 'public.payment_terms'::regclass) THEN
    ALTER TABLE public.payment_terms ADD CONSTRAINT payment_terms_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'uom_categories_tenant_id_id_key' AND conrelid = 'public.uom_categories'::regclass) THEN
    ALTER TABLE public.uom_categories ADD CONSTRAINT uom_categories_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'webhook_endpoints_tenant_id_id_key' AND conrelid = 'public.webhook_endpoints'::regclass) THEN
    ALTER TABLE public.webhook_endpoints ADD CONSTRAINT webhook_endpoints_tenant_id_id_key UNIQUE ("tenant_id", "id");
  END IF;
END $$;

-- ── 2. Les clés étrangères composites ────────────────────────────────────

-- account_tag_mappings
ALTER TABLE public.account_tag_mappings DROP CONSTRAINT IF EXISTS account_tag_mappings_tag_id_fkey;
ALTER TABLE public.account_tag_mappings ADD CONSTRAINT account_tag_mappings_tag_id_fkey
  FOREIGN KEY ("tenant_id", "tag_id")
  REFERENCES public.account_tags ("tenant_id", "id") ON DELETE CASCADE;
-- accounting_control_runs
ALTER TABLE public.accounting_control_runs DROP CONSTRAINT IF EXISTS acr_fiscal_year_id_fkey;
ALTER TABLE public.accounting_control_runs ADD CONSTRAINT acr_fiscal_year_id_fkey
  FOREIGN KEY ("tenant_id", "fiscal_year_id")
  REFERENCES public.fiscal_years ("tenant_id", "id") ON DELETE SET NULL ("fiscal_year_id");
ALTER TABLE public.accounting_control_runs DROP CONSTRAINT IF EXISTS acr_period_id_fkey;
ALTER TABLE public.accounting_control_runs ADD CONSTRAINT acr_period_id_fkey
  FOREIGN KEY ("tenant_id", "period_id")
  REFERENCES public.fiscal_periods ("tenant_id", "id") ON DELETE SET NULL ("period_id");
-- analytic_distribution_lines
ALTER TABLE public.analytic_distribution_lines DROP CONSTRAINT IF EXISTS analytic_distribution_lines_journal_line_id_fkey;
ALTER TABLE public.analytic_distribution_lines ADD CONSTRAINT analytic_distribution_lines_journal_line_id_fkey
  FOREIGN KEY ("tenant_id", "journal_line_id")
  REFERENCES public.journal_lines ("tenant_id", "id") ON DELETE CASCADE;
ALTER TABLE public.analytic_distribution_lines DROP CONSTRAINT IF EXISTS analytic_distribution_lines_plan_id_fkey;
ALTER TABLE public.analytic_distribution_lines ADD CONSTRAINT analytic_distribution_lines_plan_id_fkey
  FOREIGN KEY ("tenant_id", "plan_id")
  REFERENCES public.analytic_plans ("tenant_id", "id");
ALTER TABLE public.analytic_distribution_lines DROP CONSTRAINT IF EXISTS analytic_distribution_lines_section_id_fkey;
ALTER TABLE public.analytic_distribution_lines ADD CONSTRAINT analytic_distribution_lines_section_id_fkey
  FOREIGN KEY ("tenant_id", "section_id")
  REFERENCES public.analytic_sections ("tenant_id", "id");
-- analytic_sections
ALTER TABLE public.analytic_sections DROP CONSTRAINT IF EXISTS analytic_sections_parent_id_fkey;
ALTER TABLE public.analytic_sections ADD CONSTRAINT analytic_sections_parent_id_fkey
  FOREIGN KEY ("tenant_id", "parent_id")
  REFERENCES public.analytic_sections ("tenant_id", "id");
ALTER TABLE public.analytic_sections DROP CONSTRAINT IF EXISTS analytic_sections_plan_id_fkey;
ALTER TABLE public.analytic_sections ADD CONSTRAINT analytic_sections_plan_id_fkey
  FOREIGN KEY ("tenant_id", "plan_id")
  REFERENCES public.analytic_plans ("tenant_id", "id") ON DELETE SET NULL ("plan_id");
-- asset_batch_disposal_lines
ALTER TABLE public.asset_batch_disposal_lines DROP CONSTRAINT IF EXISTS asset_batch_disposal_lines_asset_id_fkey;
ALTER TABLE public.asset_batch_disposal_lines ADD CONSTRAINT asset_batch_disposal_lines_asset_id_fkey
  FOREIGN KEY ("tenant_id", "asset_id")
  REFERENCES public.fixed_assets ("tenant_id", "id") ON DELETE RESTRICT;
ALTER TABLE public.asset_batch_disposal_lines DROP CONSTRAINT IF EXISTS asset_batch_disposal_lines_batch_id_fkey;
ALTER TABLE public.asset_batch_disposal_lines ADD CONSTRAINT asset_batch_disposal_lines_batch_id_fkey
  FOREIGN KEY ("tenant_id", "batch_id")
  REFERENCES public.asset_batch_disposals ("tenant_id", "id") ON DELETE CASCADE;
-- asset_depreciation_plans
ALTER TABLE public.asset_depreciation_plans DROP CONSTRAINT IF EXISTS asset_depreciation_plans_asset_id_fkey;
ALTER TABLE public.asset_depreciation_plans ADD CONSTRAINT asset_depreciation_plans_asset_id_fkey
  FOREIGN KEY ("tenant_id", "asset_id")
  REFERENCES public.fixed_assets ("tenant_id", "id") ON DELETE CASCADE;
-- asset_depreciations
ALTER TABLE public.asset_depreciations DROP CONSTRAINT IF EXISTS asset_depreciations_asset_id_fkey;
ALTER TABLE public.asset_depreciations ADD CONSTRAINT asset_depreciations_asset_id_fkey
  FOREIGN KEY ("tenant_id", "asset_id")
  REFERENCES public.fixed_assets ("tenant_id", "id") ON DELETE CASCADE;
-- asset_documents
ALTER TABLE public.asset_documents DROP CONSTRAINT IF EXISTS asset_documents_asset_id_fkey;
ALTER TABLE public.asset_documents ADD CONSTRAINT asset_documents_asset_id_fkey
  FOREIGN KEY ("tenant_id", "asset_id")
  REFERENCES public.fixed_assets ("tenant_id", "id") ON DELETE CASCADE;
-- asset_families
ALTER TABLE public.asset_families DROP CONSTRAINT IF EXISTS asset_families_parent_id_fkey;
ALTER TABLE public.asset_families ADD CONSTRAINT asset_families_parent_id_fkey
  FOREIGN KEY ("tenant_id", "parent_id")
  REFERENCES public.asset_families ("tenant_id", "id") ON DELETE SET NULL ("parent_id");
-- asset_free_fields
ALTER TABLE public.asset_free_fields DROP CONSTRAINT IF EXISTS asset_free_fields_asset_id_fkey;
ALTER TABLE public.asset_free_fields ADD CONSTRAINT asset_free_fields_asset_id_fkey
  FOREIGN KEY ("tenant_id", "asset_id")
  REFERENCES public.fixed_assets ("tenant_id", "id") ON DELETE CASCADE;
-- asset_revaluations
ALTER TABLE public.asset_revaluations DROP CONSTRAINT IF EXISTS asset_revaluations_asset_id_fkey;
ALTER TABLE public.asset_revaluations ADD CONSTRAINT asset_revaluations_asset_id_fkey
  FOREIGN KEY ("tenant_id", "asset_id")
  REFERENCES public.fixed_assets ("tenant_id", "id") ON DELETE CASCADE;
-- asset_split_components
ALTER TABLE public.asset_split_components DROP CONSTRAINT IF EXISTS asset_split_components_new_asset_id_fkey;
ALTER TABLE public.asset_split_components ADD CONSTRAINT asset_split_components_new_asset_id_fkey
  FOREIGN KEY ("tenant_id", "new_asset_id")
  REFERENCES public.fixed_assets ("tenant_id", "id") ON DELETE CASCADE;
ALTER TABLE public.asset_split_components DROP CONSTRAINT IF EXISTS asset_split_components_split_id_fkey;
ALTER TABLE public.asset_split_components ADD CONSTRAINT asset_split_components_split_id_fkey
  FOREIGN KEY ("tenant_id", "split_id")
  REFERENCES public.asset_splits ("tenant_id", "id") ON DELETE CASCADE;
-- asset_splits
ALTER TABLE public.asset_splits DROP CONSTRAINT IF EXISTS asset_splits_original_asset_id_fkey;
ALTER TABLE public.asset_splits ADD CONSTRAINT asset_splits_original_asset_id_fkey
  FOREIGN KEY ("tenant_id", "original_asset_id")
  REFERENCES public.fixed_assets ("tenant_id", "id") ON DELETE RESTRICT;
-- at_rates
ALTER TABLE public.at_rates DROP CONSTRAINT IF EXISTS at_rates_employee_id_fkey;
ALTER TABLE public.at_rates ADD CONSTRAINT at_rates_employee_id_fkey
  FOREIGN KEY ("tenant_id", "employee_id")
  REFERENCES public.employees ("tenant_id", "id") ON DELETE CASCADE;
-- audit_log
ALTER TABLE public.audit_log DROP CONSTRAINT IF EXISTS audit_log_user_id_fkey;
ALTER TABLE public.audit_log ADD CONSTRAINT audit_log_user_id_fkey
  FOREIGN KEY ("tenant_id", "user_id")
  REFERENCES public.users ("tenant_id", "id") ON DELETE SET NULL ("user_id");
-- bank_connections
ALTER TABLE public.bank_connections DROP CONSTRAINT IF EXISTS bank_connections_bank_account_id_fkey;
ALTER TABLE public.bank_connections ADD CONSTRAINT bank_connections_bank_account_id_fkey
  FOREIGN KEY ("tenant_id", "bank_account_id")
  REFERENCES public.bank_accounts ("tenant_id", "id");
-- bank_statement_imports
ALTER TABLE public.bank_statement_imports DROP CONSTRAINT IF EXISTS bank_statement_imports_bank_account_id_fkey;
ALTER TABLE public.bank_statement_imports ADD CONSTRAINT bank_statement_imports_bank_account_id_fkey
  FOREIGN KEY ("tenant_id", "bank_account_id")
  REFERENCES public.bank_accounts ("tenant_id", "id") ON DELETE CASCADE;
-- bank_transactions
ALTER TABLE public.bank_transactions DROP CONSTRAINT IF EXISTS bank_transactions_account_id_fkey;
ALTER TABLE public.bank_transactions ADD CONSTRAINT bank_transactions_account_id_fkey
  FOREIGN KEY ("tenant_id", "account_id")
  REFERENCES public.bank_accounts ("tenant_id", "id") ON DELETE CASCADE;
ALTER TABLE public.bank_transactions DROP CONSTRAINT IF EXISTS bank_transactions_invoice_id_fkey;
ALTER TABLE public.bank_transactions ADD CONSTRAINT bank_transactions_invoice_id_fkey
  FOREIGN KEY ("tenant_id", "invoice_id")
  REFERENCES public.invoices ("tenant_id", "id") ON DELETE SET NULL ("invoice_id");
ALTER TABLE public.bank_transactions DROP CONSTRAINT IF EXISTS bank_transactions_purchase_invoice_id_fkey;
ALTER TABLE public.bank_transactions ADD CONSTRAINT bank_transactions_purchase_invoice_id_fkey
  FOREIGN KEY ("tenant_id", "purchase_invoice_id")
  REFERENCES public.purchase_invoices ("tenant_id", "id") ON DELETE SET NULL ("purchase_invoice_id");
ALTER TABLE public.bank_transactions DROP CONSTRAINT IF EXISTS bank_transactions_reconciled_entry_id_fkey;
ALTER TABLE public.bank_transactions ADD CONSTRAINT bank_transactions_reconciled_entry_id_fkey
  FOREIGN KEY ("tenant_id", "reconciled_entry_id")
  REFERENCES public.journal_entries ("tenant_id", "id") ON DELETE SET NULL ("reconciled_entry_id");
-- bom_lines
ALTER TABLE public.bom_lines DROP CONSTRAINT IF EXISTS bom_lines_bom_id_fkey;
ALTER TABLE public.bom_lines ADD CONSTRAINT bom_lines_bom_id_fkey
  FOREIGN KEY ("tenant_id", "bom_id")
  REFERENCES public.boms ("tenant_id", "id") ON DELETE CASCADE;
ALTER TABLE public.bom_lines DROP CONSTRAINT IF EXISTS bom_lines_product_id_fkey;
ALTER TABLE public.bom_lines ADD CONSTRAINT bom_lines_product_id_fkey
  FOREIGN KEY ("tenant_id", "product_id")
  REFERENCES public.products ("tenant_id", "id") ON DELETE CASCADE;
-- boms
ALTER TABLE public.boms DROP CONSTRAINT IF EXISTS boms_product_id_fkey;
ALTER TABLE public.boms ADD CONSTRAINT boms_product_id_fkey
  FOREIGN KEY ("tenant_id", "product_id")
  REFERENCES public.products ("tenant_id", "id") ON DELETE SET NULL ("product_id");
ALTER TABLE public.boms DROP CONSTRAINT IF EXISTS boms_routing_id_fkey;
ALTER TABLE public.boms ADD CONSTRAINT boms_routing_id_fkey
  FOREIGN KEY ("tenant_id", "routing_id")
  REFERENCES public.routings ("tenant_id", "id") ON DELETE SET NULL ("routing_id");
-- budget_commitments
ALTER TABLE public.budget_commitments DROP CONSTRAINT IF EXISTS budget_commitments_fiscal_year_id_fkey;
ALTER TABLE public.budget_commitments ADD CONSTRAINT budget_commitments_fiscal_year_id_fkey
  FOREIGN KEY ("tenant_id", "fiscal_year_id")
  REFERENCES public.fiscal_years ("tenant_id", "id") ON DELETE CASCADE;
ALTER TABLE public.budget_commitments DROP CONSTRAINT IF EXISTS budget_commitments_supplier_id_fkey;
ALTER TABLE public.budget_commitments ADD CONSTRAINT budget_commitments_supplier_id_fkey
  FOREIGN KEY ("tenant_id", "supplier_id")
  REFERENCES public.suppliers ("tenant_id", "id") ON DELETE SET NULL ("supplier_id");
-- budgets
ALTER TABLE public.budgets DROP CONSTRAINT IF EXISTS budgets_analytic_section_id_fkey;
ALTER TABLE public.budgets ADD CONSTRAINT budgets_analytic_section_id_fkey
  FOREIGN KEY ("tenant_id", "analytic_section_id")
  REFERENCES public.analytic_sections ("tenant_id", "id") ON DELETE SET NULL ("analytic_section_id");
ALTER TABLE public.budgets DROP CONSTRAINT IF EXISTS budgets_fiscal_year_id_fkey;
ALTER TABLE public.budgets ADD CONSTRAINT budgets_fiscal_year_id_fkey
  FOREIGN KEY ("tenant_id", "fiscal_year_id")
  REFERENCES public.fiscal_years ("tenant_id", "id") ON DELETE CASCADE;
-- career_history
ALTER TABLE public.career_history DROP CONSTRAINT IF EXISTS career_history_employee_id_fkey;
ALTER TABLE public.career_history ADD CONSTRAINT career_history_employee_id_fkey
  FOREIGN KEY ("tenant_id", "employee_id")
  REFERENCES public.employees ("tenant_id", "id") ON DELETE CASCADE;
-- carry_forward_log
ALTER TABLE public.carry_forward_log DROP CONSTRAINT IF EXISTS cfl_journal_entry_id_fkey;
ALTER TABLE public.carry_forward_log ADD CONSTRAINT cfl_journal_entry_id_fkey
  FOREIGN KEY ("tenant_id", "journal_entry_id")
  REFERENCES public.journal_entries ("tenant_id", "id") ON DELETE SET NULL ("journal_entry_id");
ALTER TABLE public.carry_forward_log DROP CONSTRAINT IF EXISTS cfl_source_fy_fkey;
ALTER TABLE public.carry_forward_log ADD CONSTRAINT cfl_source_fy_fkey
  FOREIGN KEY ("tenant_id", "source_fiscal_year_id")
  REFERENCES public.fiscal_years ("tenant_id", "id") ON DELETE SET NULL ("source_fiscal_year_id");
ALTER TABLE public.carry_forward_log DROP CONSTRAINT IF EXISTS cfl_target_fy_fkey;
ALTER TABLE public.carry_forward_log ADD CONSTRAINT cfl_target_fy_fkey
  FOREIGN KEY ("tenant_id", "target_fiscal_year_id")
  REFERENCES public.fiscal_years ("tenant_id", "id") ON DELETE SET NULL ("target_fiscal_year_id");
-- chart_accounts
ALTER TABLE public.chart_accounts DROP CONSTRAINT IF EXISTS chart_accounts_parent_id_fkey;
ALTER TABLE public.chart_accounts ADD CONSTRAINT chart_accounts_parent_id_fkey
  FOREIGN KEY ("tenant_id", "parent_id")
  REFERENCES public.chart_accounts ("tenant_id", "id");
-- check_books
ALTER TABLE public.check_books DROP CONSTRAINT IF EXISTS check_books_bank_account_id_fkey;
ALTER TABLE public.check_books ADD CONSTRAINT check_books_bank_account_id_fkey
  FOREIGN KEY ("tenant_id", "bank_account_id")
  REFERENCES public.bank_accounts ("tenant_id", "id");
-- checks
ALTER TABLE public.checks DROP CONSTRAINT IF EXISTS checks_check_book_id_fkey;
ALTER TABLE public.checks ADD CONSTRAINT checks_check_book_id_fkey
  FOREIGN KEY ("tenant_id", "check_book_id")
  REFERENCES public.check_books ("tenant_id", "id") ON DELETE CASCADE;
ALTER TABLE public.checks DROP CONSTRAINT IF EXISTS checks_journal_entry_id_fkey;
ALTER TABLE public.checks ADD CONSTRAINT checks_journal_entry_id_fkey
  FOREIGN KEY ("tenant_id", "journal_entry_id")
  REFERENCES public.journal_entries ("tenant_id", "id") ON DELETE SET NULL ("journal_entry_id");
-- collection_reminders
ALTER TABLE public.collection_reminders DROP CONSTRAINT IF EXISTS collection_reminders_customer_id_fkey;
ALTER TABLE public.collection_reminders ADD CONSTRAINT collection_reminders_customer_id_fkey
  FOREIGN KEY ("tenant_id", "customer_id")
  REFERENCES public.customers ("tenant_id", "id") ON DELETE SET NULL ("customer_id");
ALTER TABLE public.collection_reminders DROP CONSTRAINT IF EXISTS collection_reminders_dispute_id_fkey;
ALTER TABLE public.collection_reminders ADD CONSTRAINT collection_reminders_dispute_id_fkey
  FOREIGN KEY ("tenant_id", "dispute_id")
  REFERENCES public.disputes ("tenant_id", "id") ON DELETE SET NULL ("dispute_id");
ALTER TABLE public.collection_reminders DROP CONSTRAINT IF EXISTS collection_reminders_invoice_id_fkey;
ALTER TABLE public.collection_reminders ADD CONSTRAINT collection_reminders_invoice_id_fkey
  FOREIGN KEY ("tenant_id", "invoice_id")
  REFERENCES public.invoices ("tenant_id", "id") ON DELETE SET NULL ("invoice_id");
ALTER TABLE public.collection_reminders DROP CONSTRAINT IF EXISTS collection_reminders_promise_id_fkey;
ALTER TABLE public.collection_reminders ADD CONSTRAINT collection_reminders_promise_id_fkey
  FOREIGN KEY ("tenant_id", "promise_id")
  REFERENCES public.payment_promises ("tenant_id", "id") ON DELETE SET NULL ("promise_id");
ALTER TABLE public.collection_reminders DROP CONSTRAINT IF EXISTS collection_reminders_reminder_level_id_fkey;
ALTER TABLE public.collection_reminders ADD CONSTRAINT collection_reminders_reminder_level_id_fkey
  FOREIGN KEY ("tenant_id", "reminder_level_id")
  REFERENCES public.reminder_levels ("tenant_id", "id") ON DELETE SET NULL ("reminder_level_id");
ALTER TABLE public.collection_reminders DROP CONSTRAINT IF EXISTS collection_reminders_third_party_id_fkey;
ALTER TABLE public.collection_reminders ADD CONSTRAINT collection_reminders_third_party_id_fkey
  FOREIGN KEY ("tenant_id", "third_party_id")
  REFERENCES public.third_party_accounts ("tenant_id", "id") ON DELETE SET NULL ("third_party_id");
-- collective_classifications
ALTER TABLE public.collective_classifications DROP CONSTRAINT IF EXISTS collective_classifications_agreement_id_fkey;
ALTER TABLE public.collective_classifications ADD CONSTRAINT collective_classifications_agreement_id_fkey
  FOREIGN KEY ("tenant_id", "agreement_id")
  REFERENCES public.collective_agreements ("tenant_id", "id") ON DELETE CASCADE;
-- compaction_logs
ALTER TABLE public.compaction_logs DROP CONSTRAINT IF EXISTS cl_fiscal_year_id_fkey;
ALTER TABLE public.compaction_logs ADD CONSTRAINT cl_fiscal_year_id_fkey
  FOREIGN KEY ("tenant_id", "fiscal_year_id")
  REFERENCES public.fiscal_years ("tenant_id", "id") ON DELETE SET NULL ("fiscal_year_id");
-- company_settings
ALTER TABLE public.company_settings DROP CONSTRAINT IF EXISTS company_settings_legislation_pack_code_fkey;
ALTER TABLE public.company_settings ADD CONSTRAINT company_settings_legislation_pack_code_fkey
  FOREIGN KEY ("tenant_id", "legislation_pack_code")
  REFERENCES public.legislation_packs ("tenant_id", "code");
-- contracts
ALTER TABLE public.contracts DROP CONSTRAINT IF EXISTS contracts_employee_id_fkey;
ALTER TABLE public.contracts ADD CONSTRAINT contracts_employee_id_fkey
  FOREIGN KEY ("tenant_id", "employee_id")
  REFERENCES public.employees ("tenant_id", "id") ON DELETE CASCADE;
-- cpf_accounts
ALTER TABLE public.cpf_accounts DROP CONSTRAINT IF EXISTS cpf_accounts_employee_id_fkey;
ALTER TABLE public.cpf_accounts ADD CONSTRAINT cpf_accounts_employee_id_fkey
  FOREIGN KEY ("tenant_id", "employee_id")
  REFERENCES public.employees ("tenant_id", "id") ON DELETE CASCADE;
-- cpf_transactions
ALTER TABLE public.cpf_transactions DROP CONSTRAINT IF EXISTS cpf_transactions_employee_id_fkey;
ALTER TABLE public.cpf_transactions ADD CONSTRAINT cpf_transactions_employee_id_fkey
  FOREIGN KEY ("tenant_id", "employee_id")
  REFERENCES public.employees ("tenant_id", "id") ON DELETE CASCADE;
-- credit_lines
ALTER TABLE public.credit_lines DROP CONSTRAINT IF EXISTS credit_lines_bank_account_id_fkey;
ALTER TABLE public.credit_lines ADD CONSTRAINT credit_lines_bank_account_id_fkey
  FOREIGN KEY ("tenant_id", "bank_account_id")
  REFERENCES public.bank_accounts ("tenant_id", "id") ON DELETE SET NULL ("bank_account_id");
-- credit_note_lines
ALTER TABLE public.credit_note_lines DROP CONSTRAINT IF EXISTS credit_note_lines_credit_note_id_fkey;
ALTER TABLE public.credit_note_lines ADD CONSTRAINT credit_note_lines_credit_note_id_fkey
  FOREIGN KEY ("tenant_id", "credit_note_id")
  REFERENCES public.credit_notes ("tenant_id", "id") ON DELETE CASCADE;
ALTER TABLE public.credit_note_lines DROP CONSTRAINT IF EXISTS credit_note_lines_product_id_fkey;
ALTER TABLE public.credit_note_lines ADD CONSTRAINT credit_note_lines_product_id_fkey
  FOREIGN KEY ("tenant_id", "product_id")
  REFERENCES public.products ("tenant_id", "id") ON DELETE SET NULL ("product_id");
-- credit_notes
ALTER TABLE public.credit_notes DROP CONSTRAINT IF EXISTS credit_notes_customer_id_fkey;
ALTER TABLE public.credit_notes ADD CONSTRAINT credit_notes_customer_id_fkey
  FOREIGN KEY ("tenant_id", "customer_id")
  REFERENCES public.customers ("tenant_id", "id") ON DELETE SET NULL ("customer_id");
ALTER TABLE public.credit_notes DROP CONSTRAINT IF EXISTS credit_notes_invoice_id_fkey;
ALTER TABLE public.credit_notes ADD CONSTRAINT credit_notes_invoice_id_fkey
  FOREIGN KEY ("tenant_id", "invoice_id")
  REFERENCES public.invoices ("tenant_id", "id") ON DELETE SET NULL ("invoice_id");
ALTER TABLE public.credit_notes DROP CONSTRAINT IF EXISTS credit_notes_source_invoice_id_fkey;
ALTER TABLE public.credit_notes ADD CONSTRAINT credit_notes_source_invoice_id_fkey
  FOREIGN KEY ("tenant_id", "source_invoice_id")
  REFERENCES public.invoices ("tenant_id", "id") ON DELETE SET NULL ("source_invoice_id");
ALTER TABLE public.credit_notes DROP CONSTRAINT IF EXISTS credit_notes_transferred_entry_id_fkey;
ALTER TABLE public.credit_notes ADD CONSTRAINT credit_notes_transferred_entry_id_fkey
  FOREIGN KEY ("tenant_id", "transferred_entry_id")
  REFERENCES public.journal_entries ("tenant_id", "id");
-- crm_activities
ALTER TABLE public.crm_activities DROP CONSTRAINT IF EXISTS crm_activities_customer_id_fkey;
ALTER TABLE public.crm_activities ADD CONSTRAINT crm_activities_customer_id_fkey
  FOREIGN KEY ("tenant_id", "customer_id")
  REFERENCES public.customers ("tenant_id", "id") ON DELETE SET NULL ("customer_id");
ALTER TABLE public.crm_activities DROP CONSTRAINT IF EXISTS crm_activities_opportunity_id_fkey;
ALTER TABLE public.crm_activities ADD CONSTRAINT crm_activities_opportunity_id_fkey
  FOREIGN KEY ("tenant_id", "opportunity_id")
  REFERENCES public.crm_opportunities ("tenant_id", "id") ON DELETE CASCADE;
-- crm_campaign_recipients
ALTER TABLE public.crm_campaign_recipients DROP CONSTRAINT IF EXISTS crm_campaign_recipients_campaign_id_fkey;
ALTER TABLE public.crm_campaign_recipients ADD CONSTRAINT crm_campaign_recipients_campaign_id_fkey
  FOREIGN KEY ("tenant_id", "campaign_id")
  REFERENCES public.crm_campaigns ("tenant_id", "id") ON DELETE CASCADE;
ALTER TABLE public.crm_campaign_recipients DROP CONSTRAINT IF EXISTS crm_campaign_recipients_customer_id_fkey;
ALTER TABLE public.crm_campaign_recipients ADD CONSTRAINT crm_campaign_recipients_customer_id_fkey
  FOREIGN KEY ("tenant_id", "customer_id")
  REFERENCES public.customers ("tenant_id", "id") ON DELETE SET NULL ("customer_id");
ALTER TABLE public.crm_campaign_recipients DROP CONSTRAINT IF EXISTS crm_campaign_recipients_prospect_id_fkey;
ALTER TABLE public.crm_campaign_recipients ADD CONSTRAINT crm_campaign_recipients_prospect_id_fkey
  FOREIGN KEY ("tenant_id", "prospect_id")
  REFERENCES public.prospects ("tenant_id", "id") ON DELETE SET NULL ("prospect_id");
-- crm_forecasts
ALTER TABLE public.crm_forecasts DROP CONSTRAINT IF EXISTS crm_forecasts_sales_rep_id_fkey;
ALTER TABLE public.crm_forecasts ADD CONSTRAINT crm_forecasts_sales_rep_id_fkey
  FOREIGN KEY ("tenant_id", "sales_rep_id")
  REFERENCES public.sales_representatives ("tenant_id", "id") ON DELETE SET NULL ("sales_rep_id");
-- crm_opportunities
ALTER TABLE public.crm_opportunities DROP CONSTRAINT IF EXISTS crm_opportunities_customer_id_fkey;
ALTER TABLE public.crm_opportunities ADD CONSTRAINT crm_opportunities_customer_id_fkey
  FOREIGN KEY ("tenant_id", "customer_id")
  REFERENCES public.customers ("tenant_id", "id") ON DELETE SET NULL ("customer_id");
ALTER TABLE public.crm_opportunities DROP CONSTRAINT IF EXISTS crm_opportunities_prospect_id_fkey;
ALTER TABLE public.crm_opportunities ADD CONSTRAINT crm_opportunities_prospect_id_fkey
  FOREIGN KEY ("tenant_id", "prospect_id")
  REFERENCES public.prospects ("tenant_id", "id") ON DELETE SET NULL ("prospect_id");
ALTER TABLE public.crm_opportunities DROP CONSTRAINT IF EXISTS crm_opportunities_sales_rep_id_fkey;
ALTER TABLE public.crm_opportunities ADD CONSTRAINT crm_opportunities_sales_rep_id_fkey
  FOREIGN KEY ("tenant_id", "sales_rep_id")
  REFERENCES public.sales_representatives ("tenant_id", "id") ON DELETE SET NULL ("sales_rep_id");
-- crm_territories
ALTER TABLE public.crm_territories DROP CONSTRAINT IF EXISTS crm_territories_parent_id_fkey;
ALTER TABLE public.crm_territories ADD CONSTRAINT crm_territories_parent_id_fkey
  FOREIGN KEY ("tenant_id", "parent_id")
  REFERENCES public.crm_territories ("tenant_id", "id") ON DELETE SET NULL ("parent_id");
ALTER TABLE public.crm_territories DROP CONSTRAINT IF EXISTS crm_territories_sales_rep_id_fkey;
ALTER TABLE public.crm_territories ADD CONSTRAINT crm_territories_sales_rep_id_fkey
  FOREIGN KEY ("tenant_id", "sales_rep_id")
  REFERENCES public.sales_representatives ("tenant_id", "id") ON DELETE SET NULL ("sales_rep_id");
-- currency_revaluations
ALTER TABLE public.currency_revaluations DROP CONSTRAINT IF EXISTS cr_entry_id_fkey;
ALTER TABLE public.currency_revaluations ADD CONSTRAINT cr_entry_id_fkey
  FOREIGN KEY ("tenant_id", "entry_id")
  REFERENCES public.journal_entries ("tenant_id", "id") ON DELETE SET NULL ("entry_id");
ALTER TABLE public.currency_revaluations DROP CONSTRAINT IF EXISTS cr_fiscal_year_id_fkey;
ALTER TABLE public.currency_revaluations ADD CONSTRAINT cr_fiscal_year_id_fkey
  FOREIGN KEY ("tenant_id", "fiscal_year_id")
  REFERENCES public.fiscal_years ("tenant_id", "id") ON DELETE SET NULL ("fiscal_year_id");
-- customer_contacts
ALTER TABLE public.customer_contacts DROP CONSTRAINT IF EXISTS customer_contacts_customer_id_fkey;
ALTER TABLE public.customer_contacts ADD CONSTRAINT customer_contacts_customer_id_fkey
  FOREIGN KEY ("tenant_id", "customer_id")
  REFERENCES public.customers ("tenant_id", "id") ON DELETE CASCADE;
-- customer_payments
ALTER TABLE public.customer_payments DROP CONSTRAINT IF EXISTS customer_payments_bank_account_id_fkey;
ALTER TABLE public.customer_payments ADD CONSTRAINT customer_payments_bank_account_id_fkey
  FOREIGN KEY ("tenant_id", "bank_account_id")
  REFERENCES public.bank_accounts ("tenant_id", "id") ON DELETE SET NULL ("bank_account_id");
ALTER TABLE public.customer_payments DROP CONSTRAINT IF EXISTS customer_payments_customer_id_fkey;
ALTER TABLE public.customer_payments ADD CONSTRAINT customer_payments_customer_id_fkey
  FOREIGN KEY ("tenant_id", "customer_id")
  REFERENCES public.customers ("tenant_id", "id") ON DELETE SET NULL ("customer_id");
ALTER TABLE public.customer_payments DROP CONSTRAINT IF EXISTS customer_payments_invoice_id_fkey;
ALTER TABLE public.customer_payments ADD CONSTRAINT customer_payments_invoice_id_fkey
  FOREIGN KEY ("tenant_id", "invoice_id")
  REFERENCES public.invoices ("tenant_id", "id") ON DELETE SET NULL ("invoice_id");
ALTER TABLE public.customer_payments DROP CONSTRAINT IF EXISTS customer_payments_transferred_entry_id_fkey;
ALTER TABLE public.customer_payments ADD CONSTRAINT customer_payments_transferred_entry_id_fkey
  FOREIGN KEY ("tenant_id", "transferred_entry_id")
  REFERENCES public.journal_entries ("tenant_id", "id");
-- customers
ALTER TABLE public.customers DROP CONSTRAINT IF EXISTS customers_bank_account_id_fkey;
ALTER TABLE public.customers ADD CONSTRAINT customers_bank_account_id_fkey
  FOREIGN KEY ("tenant_id", "bank_account_id")
  REFERENCES public.bank_accounts ("tenant_id", "id") ON DELETE SET NULL ("bank_account_id");
ALTER TABLE public.customers DROP CONSTRAINT IF EXISTS customers_parent_id_fkey;
ALTER TABLE public.customers ADD CONSTRAINT customers_parent_id_fkey
  FOREIGN KEY ("tenant_id", "parent_id")
  REFERENCES public.customers ("tenant_id", "id") ON DELETE SET NULL ("parent_id");
ALTER TABLE public.customers DROP CONSTRAINT IF EXISTS customers_price_list_id_fkey;
ALTER TABLE public.customers ADD CONSTRAINT customers_price_list_id_fkey
  FOREIGN KEY ("tenant_id", "price_list_id")
  REFERENCES public.price_lists ("tenant_id", "id") ON DELETE SET NULL ("price_list_id");
ALTER TABLE public.customers DROP CONSTRAINT IF EXISTS customers_sales_rep_id_fkey;
ALTER TABLE public.customers ADD CONSTRAINT customers_sales_rep_id_fkey
  FOREIGN KEY ("tenant_id", "sales_rep_id")
  REFERENCES public.sales_representatives ("tenant_id", "id") ON DELETE SET NULL ("sales_rep_id");
-- delivery_note_lines
ALTER TABLE public.delivery_note_lines DROP CONSTRAINT IF EXISTS delivery_note_lines_delivery_note_id_fkey;
ALTER TABLE public.delivery_note_lines ADD CONSTRAINT delivery_note_lines_delivery_note_id_fkey
  FOREIGN KEY ("tenant_id", "delivery_note_id")
  REFERENCES public.delivery_notes ("tenant_id", "id") ON DELETE CASCADE;
ALTER TABLE public.delivery_note_lines DROP CONSTRAINT IF EXISTS delivery_note_lines_product_id_fkey;
ALTER TABLE public.delivery_note_lines ADD CONSTRAINT delivery_note_lines_product_id_fkey
  FOREIGN KEY ("tenant_id", "product_id")
  REFERENCES public.products ("tenant_id", "id") ON DELETE SET NULL ("product_id");
ALTER TABLE public.delivery_note_lines DROP CONSTRAINT IF EXISTS dnl_sales_order_line_id_fkey;
ALTER TABLE public.delivery_note_lines ADD CONSTRAINT dnl_sales_order_line_id_fkey
  FOREIGN KEY ("tenant_id", "sales_order_line_id")
  REFERENCES public.sales_order_lines ("tenant_id", "id") ON DELETE SET NULL ("sales_order_line_id");
-- delivery_notes
ALTER TABLE public.delivery_notes DROP CONSTRAINT IF EXISTS delivery_notes_customer_id_fkey;
ALTER TABLE public.delivery_notes ADD CONSTRAINT delivery_notes_customer_id_fkey
  FOREIGN KEY ("tenant_id", "customer_id")
  REFERENCES public.customers ("tenant_id", "id") ON DELETE SET NULL ("customer_id");
ALTER TABLE public.delivery_notes DROP CONSTRAINT IF EXISTS delivery_notes_sales_order_id_fkey;
ALTER TABLE public.delivery_notes ADD CONSTRAINT delivery_notes_sales_order_id_fkey
  FOREIGN KEY ("tenant_id", "sales_order_id")
  REFERENCES public.sales_orders ("tenant_id", "id") ON DELETE SET NULL ("sales_order_id");
-- delivery_schedules
ALTER TABLE public.delivery_schedules DROP CONSTRAINT IF EXISTS delivery_schedules_customer_id_fkey;
ALTER TABLE public.delivery_schedules ADD CONSTRAINT delivery_schedules_customer_id_fkey
  FOREIGN KEY ("tenant_id", "customer_id")
  REFERENCES public.customers ("tenant_id", "id") ON DELETE SET NULL ("customer_id");
ALTER TABLE public.delivery_schedules DROP CONSTRAINT IF EXISTS delivery_schedules_product_id_fkey;
ALTER TABLE public.delivery_schedules ADD CONSTRAINT delivery_schedules_product_id_fkey
  FOREIGN KEY ("tenant_id", "product_id")
  REFERENCES public.products ("tenant_id", "id") ON DELETE CASCADE;
-- distribution_grill_lines
ALTER TABLE public.distribution_grill_lines DROP CONSTRAINT IF EXISTS distribution_grill_lines_grill_id_fkey;
ALTER TABLE public.distribution_grill_lines ADD CONSTRAINT distribution_grill_lines_grill_id_fkey
  FOREIGN KEY ("tenant_id", "grill_id")
  REFERENCES public.distribution_grills ("tenant_id", "id") ON DELETE CASCADE;
-- document_charges
ALTER TABLE public.document_charges DROP CONSTRAINT IF EXISTS document_charges_supplier_id_fkey;
ALTER TABLE public.document_charges ADD CONSTRAINT document_charges_supplier_id_fkey
  FOREIGN KEY ("tenant_id", "supplier_id")
  REFERENCES public.suppliers ("tenant_id", "id") ON DELETE SET NULL ("supplier_id");
-- document_distribution_logs
ALTER TABLE public.document_distribution_logs DROP CONSTRAINT IF EXISTS document_distribution_logs_employee_document_id_fkey;
ALTER TABLE public.document_distribution_logs ADD CONSTRAINT document_distribution_logs_employee_document_id_fkey
  FOREIGN KEY ("tenant_id", "employee_document_id")
  REFERENCES public.employee_documents ("tenant_id", "id") ON DELETE CASCADE;
ALTER TABLE public.document_distribution_logs DROP CONSTRAINT IF EXISTS document_distribution_logs_employee_id_fkey;
ALTER TABLE public.document_distribution_logs ADD CONSTRAINT document_distribution_logs_employee_id_fkey
  FOREIGN KEY ("tenant_id", "employee_id")
  REFERENCES public.employees ("tenant_id", "id") ON DELETE CASCADE;
-- document_number_sequences
ALTER TABLE public.document_number_sequences DROP CONSTRAINT IF EXISTS document_number_sequences_fiscal_year_id_fkey;
ALTER TABLE public.document_number_sequences ADD CONSTRAINT document_number_sequences_fiscal_year_id_fkey
  FOREIGN KEY ("tenant_id", "fiscal_year_id")
  REFERENCES public.fiscal_years ("tenant_id", "id") ON DELETE CASCADE;
-- dpae_records
ALTER TABLE public.dpae_records DROP CONSTRAINT IF EXISTS dpae_records_employee_id_fkey;
ALTER TABLE public.dpae_records ADD CONSTRAINT dpae_records_employee_id_fkey
  FOREIGN KEY ("tenant_id", "employee_id")
  REFERENCES public.employees ("tenant_id", "id") ON DELETE CASCADE;
-- employee_activity_logs
ALTER TABLE public.employee_activity_logs DROP CONSTRAINT IF EXISTS employee_activity_logs_employee_id_fkey;
ALTER TABLE public.employee_activity_logs ADD CONSTRAINT employee_activity_logs_employee_id_fkey
  FOREIGN KEY ("tenant_id", "employee_id")
  REFERENCES public.employees ("tenant_id", "id") ON DELETE CASCADE;
-- employee_documents
ALTER TABLE public.employee_documents DROP CONSTRAINT IF EXISTS employee_documents_employee_id_fkey;
ALTER TABLE public.employee_documents ADD CONSTRAINT employee_documents_employee_id_fkey
  FOREIGN KEY ("tenant_id", "employee_id")
  REFERENCES public.employees ("tenant_id", "id") ON DELETE CASCADE;
-- employee_exit_processes
ALTER TABLE public.employee_exit_processes DROP CONSTRAINT IF EXISTS eep_exit_payslip_id_fkey;
ALTER TABLE public.employee_exit_processes ADD CONSTRAINT eep_exit_payslip_id_fkey
  FOREIGN KEY ("tenant_id", "exit_payslip_id")
  REFERENCES public.pay_slips ("tenant_id", "id") ON DELETE SET NULL ("exit_payslip_id");
ALTER TABLE public.employee_exit_processes DROP CONSTRAINT IF EXISTS employee_exit_processes_employee_id_fkey;
ALTER TABLE public.employee_exit_processes ADD CONSTRAINT employee_exit_processes_employee_id_fkey
  FOREIGN KEY ("tenant_id", "employee_id")
  REFERENCES public.employees ("tenant_id", "id") ON DELETE CASCADE;
-- employee_objectives
ALTER TABLE public.employee_objectives DROP CONSTRAINT IF EXISTS employee_objectives_campaign_id_fkey;
ALTER TABLE public.employee_objectives ADD CONSTRAINT employee_objectives_campaign_id_fkey
  FOREIGN KEY ("tenant_id", "campaign_id")
  REFERENCES public.interview_campaigns ("tenant_id", "id") ON DELETE SET NULL ("campaign_id");
ALTER TABLE public.employee_objectives DROP CONSTRAINT IF EXISTS employee_objectives_employee_id_fkey;
ALTER TABLE public.employee_objectives ADD CONSTRAINT employee_objectives_employee_id_fkey
  FOREIGN KEY ("tenant_id", "employee_id")
  REFERENCES public.employees ("tenant_id", "id") ON DELETE CASCADE;
-- employees
ALTER TABLE public.employees DROP CONSTRAINT IF EXISTS employees_classification_id_fkey;
ALTER TABLE public.employees ADD CONSTRAINT employees_classification_id_fkey
  FOREIGN KEY ("tenant_id", "classification_id")
  REFERENCES public.collective_classifications ("tenant_id", "id");
ALTER TABLE public.employees DROP CONSTRAINT IF EXISTS employees_collective_agreement_id_fkey;
ALTER TABLE public.employees ADD CONSTRAINT employees_collective_agreement_id_fkey
  FOREIGN KEY ("tenant_id", "collective_agreement_id")
  REFERENCES public.collective_agreements ("tenant_id", "id");
-- etat_rapprochement
ALTER TABLE public.etat_rapprochement DROP CONSTRAINT IF EXISTS er_bank_account_id_fkey;
ALTER TABLE public.etat_rapprochement ADD CONSTRAINT er_bank_account_id_fkey
  FOREIGN KEY ("tenant_id", "bank_account_id")
  REFERENCES public.bank_accounts ("tenant_id", "id") ON DELETE SET NULL ("bank_account_id");
-- exchange_gain_loss_entries
ALTER TABLE public.exchange_gain_loss_entries DROP CONSTRAINT IF EXISTS exgl_invoice_id_fkey;
ALTER TABLE public.exchange_gain_loss_entries ADD CONSTRAINT exgl_invoice_id_fkey
  FOREIGN KEY ("tenant_id", "invoice_id")
  REFERENCES public.invoices ("tenant_id", "id") ON DELETE SET NULL ("invoice_id");
ALTER TABLE public.exchange_gain_loss_entries DROP CONSTRAINT IF EXISTS exgl_journal_entry_id_fkey;
ALTER TABLE public.exchange_gain_loss_entries ADD CONSTRAINT exgl_journal_entry_id_fkey
  FOREIGN KEY ("tenant_id", "journal_entry_id")
  REFERENCES public.journal_entries ("tenant_id", "id") ON DELETE SET NULL ("journal_entry_id");
-- expense_report_lines
ALTER TABLE public.expense_report_lines DROP CONSTRAINT IF EXISTS expense_report_lines_category_id_fkey;
ALTER TABLE public.expense_report_lines ADD CONSTRAINT expense_report_lines_category_id_fkey
  FOREIGN KEY ("tenant_id", "category_id")
  REFERENCES public.expense_categories ("tenant_id", "id") ON DELETE SET NULL ("category_id");
ALTER TABLE public.expense_report_lines DROP CONSTRAINT IF EXISTS expense_report_lines_expense_report_id_fkey;
ALTER TABLE public.expense_report_lines ADD CONSTRAINT expense_report_lines_expense_report_id_fkey
  FOREIGN KEY ("tenant_id", "expense_report_id")
  REFERENCES public.expense_reports ("tenant_id", "id") ON DELETE CASCADE;
-- expense_reports
ALTER TABLE public.expense_reports DROP CONSTRAINT IF EXISTS er_manager_id_fkey;
ALTER TABLE public.expense_reports ADD CONSTRAINT er_manager_id_fkey
  FOREIGN KEY ("tenant_id", "manager_id")
  REFERENCES public.employees ("tenant_id", "id") ON DELETE SET NULL ("manager_id");
ALTER TABLE public.expense_reports DROP CONSTRAINT IF EXISTS expense_reports_employee_id_fkey;
ALTER TABLE public.expense_reports ADD CONSTRAINT expense_reports_employee_id_fkey
  FOREIGN KEY ("tenant_id", "employee_id")
  REFERENCES public.employees ("tenant_id", "id") ON DELETE CASCADE;
-- extourne_log
ALTER TABLE public.extourne_log DROP CONSTRAINT IF EXISTS el_extourne_entry_id_fkey;
ALTER TABLE public.extourne_log ADD CONSTRAINT el_extourne_entry_id_fkey
  FOREIGN KEY ("tenant_id", "extourne_entry_id")
  REFERENCES public.journal_entries ("tenant_id", "id") ON DELETE SET NULL ("extourne_entry_id");
ALTER TABLE public.extourne_log DROP CONSTRAINT IF EXISTS el_original_entry_id_fkey;
ALTER TABLE public.extourne_log ADD CONSTRAINT el_original_entry_id_fkey
  FOREIGN KEY ("tenant_id", "original_entry_id")
  REFERENCES public.journal_entries ("tenant_id", "id") ON DELETE SET NULL ("original_entry_id");
-- fec_attestations
ALTER TABLE public.fec_attestations DROP CONSTRAINT IF EXISTS fec_attest_fiscal_year_id_fkey;
ALTER TABLE public.fec_attestations ADD CONSTRAINT fec_attest_fiscal_year_id_fkey
  FOREIGN KEY ("tenant_id", "fiscal_year_id")
  REFERENCES public.fiscal_years ("tenant_id", "id") ON DELETE SET NULL ("fiscal_year_id");
-- fiscal_backups
ALTER TABLE public.fiscal_backups DROP CONSTRAINT IF EXISTS fiscal_backups_fiscal_year_id_fkey;
ALTER TABLE public.fiscal_backups ADD CONSTRAINT fiscal_backups_fiscal_year_id_fkey
  FOREIGN KEY ("tenant_id", "fiscal_year_id")
  REFERENCES public.fiscal_years ("tenant_id", "id") ON DELETE SET NULL ("fiscal_year_id");
-- fiscal_periods
ALTER TABLE public.fiscal_periods DROP CONSTRAINT IF EXISTS fiscal_periods_fiscal_year_id_fkey;
ALTER TABLE public.fiscal_periods ADD CONSTRAINT fiscal_periods_fiscal_year_id_fkey
  FOREIGN KEY ("tenant_id", "fiscal_year_id")
  REFERENCES public.fiscal_years ("tenant_id", "id") ON DELETE CASCADE;
-- fiscal_position_mappings
ALTER TABLE public.fiscal_position_mappings DROP CONSTRAINT IF EXISTS fiscal_position_mappings_fiscal_position_id_fkey;
ALTER TABLE public.fiscal_position_mappings ADD CONSTRAINT fiscal_position_mappings_fiscal_position_id_fkey
  FOREIGN KEY ("tenant_id", "fiscal_position_id")
  REFERENCES public.fiscal_positions ("tenant_id", "id") ON DELETE CASCADE;
ALTER TABLE public.fiscal_position_mappings DROP CONSTRAINT IF EXISTS fiscal_position_mappings_source_tax_id_fkey;
ALTER TABLE public.fiscal_position_mappings ADD CONSTRAINT fiscal_position_mappings_source_tax_id_fkey
  FOREIGN KEY ("tenant_id", "source_tax_id")
  REFERENCES public.tax_rates ("tenant_id", "id");
ALTER TABLE public.fiscal_position_mappings DROP CONSTRAINT IF EXISTS fiscal_position_mappings_target_tax_id_fkey;
ALTER TABLE public.fiscal_position_mappings ADD CONSTRAINT fiscal_position_mappings_target_tax_id_fkey
  FOREIGN KEY ("tenant_id", "target_tax_id")
  REFERENCES public.tax_rates ("tenant_id", "id");
-- fiscal_years
ALTER TABLE public.fiscal_years DROP CONSTRAINT IF EXISTS fiscal_years_closed_by_fkey;
ALTER TABLE public.fiscal_years ADD CONSTRAINT fiscal_years_closed_by_fkey
  FOREIGN KEY ("tenant_id", "closed_by")
  REFERENCES public.users ("tenant_id", "id");
ALTER TABLE public.fiscal_years DROP CONSTRAINT IF EXISTS fiscal_years_result_allocation_entry_id_fkey;
ALTER TABLE public.fiscal_years ADD CONSTRAINT fiscal_years_result_allocation_entry_id_fkey
  FOREIGN KEY ("tenant_id", "result_allocation_entry_id")
  REFERENCES public.journal_entries ("tenant_id", "id") ON DELETE RESTRICT;
-- fixed_asset_components
ALTER TABLE public.fixed_asset_components DROP CONSTRAINT IF EXISTS fixed_asset_components_fixed_asset_id_fkey;
ALTER TABLE public.fixed_asset_components ADD CONSTRAINT fixed_asset_components_fixed_asset_id_fkey
  FOREIGN KEY ("tenant_id", "fixed_asset_id")
  REFERENCES public.fixed_assets ("tenant_id", "id") ON DELETE CASCADE;
-- fixed_assets
ALTER TABLE public.fixed_assets DROP CONSTRAINT IF EXISTS fa_journal_id_fkey;
ALTER TABLE public.fixed_assets ADD CONSTRAINT fa_journal_id_fkey
  FOREIGN KEY ("tenant_id", "journal_id")
  REFERENCES public.journals ("tenant_id", "id") ON DELETE SET NULL ("journal_id");
ALTER TABLE public.fixed_assets DROP CONSTRAINT IF EXISTS fixed_assets_family_id_fkey;
ALTER TABLE public.fixed_assets ADD CONSTRAINT fixed_assets_family_id_fkey
  FOREIGN KEY ("tenant_id", "family_id")
  REFERENCES public.asset_families ("tenant_id", "id") ON DELETE SET NULL ("family_id");
ALTER TABLE public.fixed_assets DROP CONSTRAINT IF EXISTS fixed_assets_parent_asset_id_fkey;
ALTER TABLE public.fixed_assets ADD CONSTRAINT fixed_assets_parent_asset_id_fkey
  FOREIGN KEY ("tenant_id", "parent_asset_id")
  REFERENCES public.fixed_assets ("tenant_id", "id") ON DELETE SET NULL ("parent_asset_id");
-- future_accounting_movements
ALTER TABLE public.future_accounting_movements DROP CONSTRAINT IF EXISTS fam_incorporated_entry_id_fkey;
ALTER TABLE public.future_accounting_movements ADD CONSTRAINT fam_incorporated_entry_id_fkey
  FOREIGN KEY ("tenant_id", "incorporated_entry_id")
  REFERENCES public.journal_entries ("tenant_id", "id") ON DELETE SET NULL ("incorporated_entry_id");
-- goods_receipt_lines
ALTER TABLE public.goods_receipt_lines DROP CONSTRAINT IF EXISTS goods_receipt_lines_goods_receipt_id_fkey;
ALTER TABLE public.goods_receipt_lines ADD CONSTRAINT goods_receipt_lines_goods_receipt_id_fkey
  FOREIGN KEY ("tenant_id", "goods_receipt_id")
  REFERENCES public.goods_receipts ("tenant_id", "id") ON DELETE CASCADE;
ALTER TABLE public.goods_receipt_lines DROP CONSTRAINT IF EXISTS goods_receipt_lines_product_id_fkey;
ALTER TABLE public.goods_receipt_lines ADD CONSTRAINT goods_receipt_lines_product_id_fkey
  FOREIGN KEY ("tenant_id", "product_id")
  REFERENCES public.products ("tenant_id", "id") ON DELETE SET NULL ("product_id");
-- goods_receipts
ALTER TABLE public.goods_receipts DROP CONSTRAINT IF EXISTS goods_receipts_purchase_order_id_fkey;
ALTER TABLE public.goods_receipts ADD CONSTRAINT goods_receipts_purchase_order_id_fkey
  FOREIGN KEY ("tenant_id", "purchase_order_id")
  REFERENCES public.purchase_orders ("tenant_id", "id") ON DELETE SET NULL ("purchase_order_id");
ALTER TABLE public.goods_receipts DROP CONSTRAINT IF EXISTS goods_receipts_supplier_id_fkey;
ALTER TABLE public.goods_receipts ADD CONSTRAINT goods_receipts_supplier_id_fkey
  FOREIGN KEY ("tenant_id", "supplier_id")
  REFERENCES public.suppliers ("tenant_id", "id") ON DELETE SET NULL ("supplier_id");
-- honorarium_records
ALTER TABLE public.honorarium_records DROP CONSTRAINT IF EXISTS honorarium_records_employee_id_fkey;
ALTER TABLE public.honorarium_records ADD CONSTRAINT honorarium_records_employee_id_fkey
  FOREIGN KEY ("tenant_id", "employee_id")
  REFERENCES public.employees ("tenant_id", "id") ON DELETE SET NULL ("employee_id");
ALTER TABLE public.honorarium_records DROP CONSTRAINT IF EXISTS hr_accounting_entry_id_fkey;
ALTER TABLE public.honorarium_records ADD CONSTRAINT hr_accounting_entry_id_fkey
  FOREIGN KEY ("tenant_id", "accounting_entry_id")
  REFERENCES public.journal_entries ("tenant_id", "id") ON DELETE SET NULL ("accounting_entry_id");
-- ifrs_adjustments
ALTER TABLE public.ifrs_adjustments DROP CONSTRAINT IF EXISTS ifrs_fiscal_year_id_fkey;
ALTER TABLE public.ifrs_adjustments ADD CONSTRAINT ifrs_fiscal_year_id_fkey
  FOREIGN KEY ("tenant_id", "fiscal_year_id")
  REFERENCES public.fiscal_years ("tenant_id", "id") ON DELETE SET NULL ("fiscal_year_id");
ALTER TABLE public.ifrs_adjustments DROP CONSTRAINT IF EXISTS ifrs_journal_entry_id_fkey;
ALTER TABLE public.ifrs_adjustments ADD CONSTRAINT ifrs_journal_entry_id_fkey
  FOREIGN KEY ("tenant_id", "journal_entry_id")
  REFERENCES public.journal_entries ("tenant_id", "id") ON DELETE SET NULL ("journal_entry_id");
-- ijss_history
ALTER TABLE public.ijss_history DROP CONSTRAINT IF EXISTS ijss_history_employee_id_fkey;
ALTER TABLE public.ijss_history ADD CONSTRAINT ijss_history_employee_id_fkey
  FOREIGN KEY ("tenant_id", "employee_id")
  REFERENCES public.employees ("tenant_id", "id") ON DELETE CASCADE;
ALTER TABLE public.ijss_history DROP CONSTRAINT IF EXISTS ijss_history_work_stoppage_id_fkey;
ALTER TABLE public.ijss_history ADD CONSTRAINT ijss_history_work_stoppage_id_fkey
  FOREIGN KEY ("tenant_id", "work_stoppage_id")
  REFERENCES public.work_stoppages ("tenant_id", "id") ON DELETE CASCADE;
ALTER TABLE public.ijss_history DROP CONSTRAINT IF EXISTS ijss_payslip_id_fkey;
ALTER TABLE public.ijss_history ADD CONSTRAINT ijss_payslip_id_fkey
  FOREIGN KEY ("tenant_id", "payslip_id")
  REFERENCES public.pay_slips ("tenant_id", "id") ON DELETE SET NULL ("payslip_id");
-- interviews
ALTER TABLE public.interviews DROP CONSTRAINT IF EXISTS interviews_campaign_id_fkey;
ALTER TABLE public.interviews ADD CONSTRAINT interviews_campaign_id_fkey
  FOREIGN KEY ("tenant_id", "campaign_id")
  REFERENCES public.interview_campaigns ("tenant_id", "id") ON DELETE SET NULL ("campaign_id");
ALTER TABLE public.interviews DROP CONSTRAINT IF EXISTS interviews_employee_id_fkey;
ALTER TABLE public.interviews ADD CONSTRAINT interviews_employee_id_fkey
  FOREIGN KEY ("tenant_id", "employee_id")
  REFERENCES public.employees ("tenant_id", "id") ON DELETE CASCADE;
-- invoice_lines
ALTER TABLE public.invoice_lines DROP CONSTRAINT IF EXISTS invoice_lines_delivery_note_line_id_fkey;
ALTER TABLE public.invoice_lines ADD CONSTRAINT invoice_lines_delivery_note_line_id_fkey
  FOREIGN KEY ("tenant_id", "delivery_note_line_id")
  REFERENCES public.delivery_note_lines ("tenant_id", "id") ON DELETE SET NULL ("delivery_note_line_id");
ALTER TABLE public.invoice_lines DROP CONSTRAINT IF EXISTS invoice_lines_invoice_id_fkey;
ALTER TABLE public.invoice_lines ADD CONSTRAINT invoice_lines_invoice_id_fkey
  FOREIGN KEY ("tenant_id", "invoice_id")
  REFERENCES public.invoices ("tenant_id", "id") ON DELETE CASCADE;
ALTER TABLE public.invoice_lines DROP CONSTRAINT IF EXISTS invoice_lines_product_id_fkey;
ALTER TABLE public.invoice_lines ADD CONSTRAINT invoice_lines_product_id_fkey
  FOREIGN KEY ("tenant_id", "product_id")
  REFERENCES public.products ("tenant_id", "id") ON DELETE SET NULL ("product_id");
ALTER TABLE public.invoice_lines DROP CONSTRAINT IF EXISTS invoice_lines_sales_order_line_id_fkey;
ALTER TABLE public.invoice_lines ADD CONSTRAINT invoice_lines_sales_order_line_id_fkey
  FOREIGN KEY ("tenant_id", "sales_order_line_id")
  REFERENCES public.sales_order_lines ("tenant_id", "id") ON DELETE SET NULL ("sales_order_line_id");
-- invoices
ALTER TABLE public.invoices DROP CONSTRAINT IF EXISTS invoices_customer_id_fkey;
ALTER TABLE public.invoices ADD CONSTRAINT invoices_customer_id_fkey
  FOREIGN KEY ("tenant_id", "customer_id")
  REFERENCES public.customers ("tenant_id", "id") ON DELETE SET NULL ("customer_id");
ALTER TABLE public.invoices DROP CONSTRAINT IF EXISTS invoices_delivery_note_id_fkey;
ALTER TABLE public.invoices ADD CONSTRAINT invoices_delivery_note_id_fkey
  FOREIGN KEY ("tenant_id", "delivery_note_id")
  REFERENCES public.delivery_notes ("tenant_id", "id") ON DELETE SET NULL ("delivery_note_id");
ALTER TABLE public.invoices DROP CONSTRAINT IF EXISTS invoices_fiscal_position_id_fkey;
ALTER TABLE public.invoices ADD CONSTRAINT invoices_fiscal_position_id_fkey
  FOREIGN KEY ("tenant_id", "fiscal_position_id")
  REFERENCES public.fiscal_positions ("tenant_id", "id");
ALTER TABLE public.invoices DROP CONSTRAINT IF EXISTS invoices_parent_invoice_id_fkey;
ALTER TABLE public.invoices ADD CONSTRAINT invoices_parent_invoice_id_fkey
  FOREIGN KEY ("tenant_id", "parent_invoice_id")
  REFERENCES public.invoices ("tenant_id", "id") ON DELETE SET NULL ("parent_invoice_id");
ALTER TABLE public.invoices DROP CONSTRAINT IF EXISTS invoices_quote_id_fkey;
ALTER TABLE public.invoices ADD CONSTRAINT invoices_quote_id_fkey
  FOREIGN KEY ("tenant_id", "quote_id")
  REFERENCES public.quotes ("tenant_id", "id") ON DELETE SET NULL ("quote_id");
ALTER TABLE public.invoices DROP CONSTRAINT IF EXISTS invoices_sales_order_id_fkey;
ALTER TABLE public.invoices ADD CONSTRAINT invoices_sales_order_id_fkey
  FOREIGN KEY ("tenant_id", "sales_order_id")
  REFERENCES public.sales_orders ("tenant_id", "id") ON DELETE SET NULL ("sales_order_id");
ALTER TABLE public.invoices DROP CONSTRAINT IF EXISTS invoices_transferred_entry_id_fkey;
ALTER TABLE public.invoices ADD CONSTRAINT invoices_transferred_entry_id_fkey
  FOREIGN KEY ("tenant_id", "transferred_entry_id")
  REFERENCES public.journal_entries ("tenant_id", "id");
-- journal_entries
ALTER TABLE public.journal_entries DROP CONSTRAINT IF EXISTS journal_entries_entry_template_id_fkey;
ALTER TABLE public.journal_entries ADD CONSTRAINT journal_entries_entry_template_id_fkey
  FOREIGN KEY ("tenant_id", "entry_template_id")
  REFERENCES public.recurring_entries ("tenant_id", "id") ON DELETE SET NULL ("entry_template_id");
ALTER TABLE public.journal_entries DROP CONSTRAINT IF EXISTS journal_entries_fiscal_period_id_fkey;
ALTER TABLE public.journal_entries ADD CONSTRAINT journal_entries_fiscal_period_id_fkey
  FOREIGN KEY ("tenant_id", "fiscal_period_id")
  REFERENCES public.fiscal_periods ("tenant_id", "id") ON DELETE SET NULL ("fiscal_period_id");
ALTER TABLE public.journal_entries DROP CONSTRAINT IF EXISTS journal_entries_fiscal_year_id_fkey;
ALTER TABLE public.journal_entries ADD CONSTRAINT journal_entries_fiscal_year_id_fkey
  FOREIGN KEY ("tenant_id", "fiscal_year_id")
  REFERENCES public.fiscal_years ("tenant_id", "id") ON DELETE RESTRICT;
-- journal_lines
ALTER TABLE public.journal_lines DROP CONSTRAINT IF EXISTS journal_lines_analytic_section_id_fkey;
ALTER TABLE public.journal_lines ADD CONSTRAINT journal_lines_analytic_section_id_fkey
  FOREIGN KEY ("tenant_id", "analytic_section_id")
  REFERENCES public.analytic_sections ("tenant_id", "id") ON DELETE SET NULL ("analytic_section_id");
ALTER TABLE public.journal_lines DROP CONSTRAINT IF EXISTS journal_lines_journal_id_fkey;
ALTER TABLE public.journal_lines ADD CONSTRAINT journal_lines_journal_id_fkey
  FOREIGN KEY ("tenant_id", "journal_id")
  REFERENCES public.journal_entries ("tenant_id", "id") ON DELETE CASCADE;
ALTER TABLE public.journal_lines DROP CONSTRAINT IF EXISTS journal_lines_product_id_fkey;
ALTER TABLE public.journal_lines ADD CONSTRAINT journal_lines_product_id_fkey
  FOREIGN KEY ("tenant_id", "product_id")
  REFERENCES public.products ("tenant_id", "id") ON DELETE SET NULL ("product_id");
-- journal_posting_sequences
ALTER TABLE public.journal_posting_sequences DROP CONSTRAINT IF EXISTS journal_posting_sequences_fiscal_year_id_fkey;
ALTER TABLE public.journal_posting_sequences ADD CONSTRAINT journal_posting_sequences_fiscal_year_id_fkey
  FOREIGN KEY ("tenant_id", "fiscal_year_id")
  REFERENCES public.fiscal_years ("tenant_id", "id") ON DELETE CASCADE;
-- journals
ALTER TABLE public.journals DROP CONSTRAINT IF EXISTS journals_bank_account_id_fkey;
ALTER TABLE public.journals ADD CONSTRAINT journals_bank_account_id_fkey
  FOREIGN KEY ("tenant_id", "bank_account_id")
  REFERENCES public.bank_accounts ("tenant_id", "id") ON DELETE SET NULL ("bank_account_id");
-- justificatif_solde
ALTER TABLE public.justificatif_solde DROP CONSTRAINT IF EXISTS js_fiscal_period_id_fkey;
ALTER TABLE public.justificatif_solde ADD CONSTRAINT js_fiscal_period_id_fkey
  FOREIGN KEY ("tenant_id", "fiscal_period_id")
  REFERENCES public.fiscal_periods ("tenant_id", "id") ON DELETE SET NULL ("fiscal_period_id");
-- landed_cost_lines
ALTER TABLE public.landed_cost_lines DROP CONSTRAINT IF EXISTS landed_cost_lines_landed_cost_id_fkey;
ALTER TABLE public.landed_cost_lines ADD CONSTRAINT landed_cost_lines_landed_cost_id_fkey
  FOREIGN KEY ("tenant_id", "landed_cost_id")
  REFERENCES public.landed_costs ("tenant_id", "id") ON DELETE CASCADE;
-- leave_balances
ALTER TABLE public.leave_balances DROP CONSTRAINT IF EXISTS leave_balances_employee_id_fkey;
ALTER TABLE public.leave_balances ADD CONSTRAINT leave_balances_employee_id_fkey
  FOREIGN KEY ("tenant_id", "employee_id")
  REFERENCES public.employees ("tenant_id", "id") ON DELETE CASCADE;
-- leave_provisions
ALTER TABLE public.leave_provisions DROP CONSTRAINT IF EXISTS leave_provisions_employee_id_fkey;
ALTER TABLE public.leave_provisions ADD CONSTRAINT leave_provisions_employee_id_fkey
  FOREIGN KEY ("tenant_id", "employee_id")
  REFERENCES public.employees ("tenant_id", "id") ON DELETE CASCADE;
ALTER TABLE public.leave_provisions DROP CONSTRAINT IF EXISTS lp_accounting_entry_id_fkey;
ALTER TABLE public.leave_provisions ADD CONSTRAINT lp_accounting_entry_id_fkey
  FOREIGN KEY ("tenant_id", "accounting_entry_id")
  REFERENCES public.journal_entries ("tenant_id", "id") ON DELETE SET NULL ("accounting_entry_id");
-- leave_requests
ALTER TABLE public.leave_requests DROP CONSTRAINT IF EXISTS leave_requests_approved_by_fkey;
ALTER TABLE public.leave_requests ADD CONSTRAINT leave_requests_approved_by_fkey
  FOREIGN KEY ("tenant_id", "approved_by")
  REFERENCES public.employees ("tenant_id", "id") ON DELETE SET NULL ("approved_by");
ALTER TABLE public.leave_requests DROP CONSTRAINT IF EXISTS leave_requests_employee_id_fkey;
ALTER TABLE public.leave_requests ADD CONSTRAINT leave_requests_employee_id_fkey
  FOREIGN KEY ("tenant_id", "employee_id")
  REFERENCES public.employees ("tenant_id", "id") ON DELETE CASCADE;
-- lettrage_differences
ALTER TABLE public.lettrage_differences DROP CONSTRAINT IF EXISTS ld_generated_entry_id_fkey;
ALTER TABLE public.lettrage_differences ADD CONSTRAINT ld_generated_entry_id_fkey
  FOREIGN KEY ("tenant_id", "generated_entry_id")
  REFERENCES public.journal_entries ("tenant_id", "id") ON DELETE SET NULL ("generated_entry_id");
-- machines
ALTER TABLE public.machines DROP CONSTRAINT IF EXISTS machines_work_center_id_fkey;
ALTER TABLE public.machines ADD CONSTRAINT machines_work_center_id_fkey
  FOREIGN KEY ("tenant_id", "work_center_id")
  REFERENCES public.work_centers ("tenant_id", "id") ON DELETE SET NULL ("work_center_id");
-- maintenance_records
ALTER TABLE public.maintenance_records DROP CONSTRAINT IF EXISTS maintenance_records_plan_id_fkey;
ALTER TABLE public.maintenance_records ADD CONSTRAINT maintenance_records_plan_id_fkey
  FOREIGN KEY ("tenant_id", "plan_id")
  REFERENCES public.maintenance_plans ("tenant_id", "id") ON DELETE SET NULL ("plan_id");
-- manufacturing_orders
ALTER TABLE public.manufacturing_orders DROP CONSTRAINT IF EXISTS manufacturing_orders_bom_id_fkey;
ALTER TABLE public.manufacturing_orders ADD CONSTRAINT manufacturing_orders_bom_id_fkey
  FOREIGN KEY ("tenant_id", "bom_id")
  REFERENCES public.boms ("tenant_id", "id") ON DELETE SET NULL ("bom_id");
ALTER TABLE public.manufacturing_orders DROP CONSTRAINT IF EXISTS manufacturing_orders_parent_mo_id_fkey;
ALTER TABLE public.manufacturing_orders ADD CONSTRAINT manufacturing_orders_parent_mo_id_fkey
  FOREIGN KEY ("tenant_id", "parent_mo_id")
  REFERENCES public.manufacturing_orders ("tenant_id", "id") ON DELETE SET NULL ("parent_mo_id");
ALTER TABLE public.manufacturing_orders DROP CONSTRAINT IF EXISTS manufacturing_orders_product_id_fkey;
ALTER TABLE public.manufacturing_orders ADD CONSTRAINT manufacturing_orders_product_id_fkey
  FOREIGN KEY ("tenant_id", "product_id")
  REFERENCES public.products ("tenant_id", "id") ON DELETE SET NULL ("product_id");
ALTER TABLE public.manufacturing_orders DROP CONSTRAINT IF EXISTS manufacturing_orders_routing_id_fkey;
ALTER TABLE public.manufacturing_orders ADD CONSTRAINT manufacturing_orders_routing_id_fkey
  FOREIGN KEY ("tenant_id", "routing_id")
  REFERENCES public.routings ("tenant_id", "id") ON DELETE SET NULL ("routing_id");
ALTER TABLE public.manufacturing_orders DROP CONSTRAINT IF EXISTS manufacturing_orders_warehouse_id_fkey;
ALTER TABLE public.manufacturing_orders ADD CONSTRAINT manufacturing_orders_warehouse_id_fkey
  FOREIGN KEY ("tenant_id", "warehouse_id")
  REFERENCES public.warehouses ("tenant_id", "id") ON DELETE SET NULL ("warehouse_id");
-- medical_exams
ALTER TABLE public.medical_exams DROP CONSTRAINT IF EXISTS medical_exams_employee_id_fkey;
ALTER TABLE public.medical_exams ADD CONSTRAINT medical_exams_employee_id_fkey
  FOREIGN KEY ("tenant_id", "employee_id")
  REFERENCES public.employees ("tenant_id", "id") ON DELETE CASCADE;
-- mirror_verification_details
ALTER TABLE public.mirror_verification_details DROP CONSTRAINT IF EXISTS mirror_verification_details_mirror_server_id_fkey;
ALTER TABLE public.mirror_verification_details ADD CONSTRAINT mirror_verification_details_mirror_server_id_fkey
  FOREIGN KEY ("tenant_id", "mirror_server_id")
  REFERENCES public.mirror_servers ("tenant_id", "id") ON DELETE CASCADE;
-- mo_consumptions
ALTER TABLE public.mo_consumptions DROP CONSTRAINT IF EXISTS mo_consumptions_manufacturing_order_id_fkey;
ALTER TABLE public.mo_consumptions ADD CONSTRAINT mo_consumptions_manufacturing_order_id_fkey
  FOREIGN KEY ("tenant_id", "manufacturing_order_id")
  REFERENCES public.manufacturing_orders ("tenant_id", "id") ON DELETE CASCADE;
-- mo_operations
ALTER TABLE public.mo_operations DROP CONSTRAINT IF EXISTS mo_operations_manufacturing_order_id_fkey;
ALTER TABLE public.mo_operations ADD CONSTRAINT mo_operations_manufacturing_order_id_fkey
  FOREIGN KEY ("tenant_id", "manufacturing_order_id")
  REFERENCES public.manufacturing_orders ("tenant_id", "id") ON DELETE CASCADE;
-- module_document_access_log
ALTER TABLE public.module_document_access_log DROP CONSTRAINT IF EXISTS module_document_access_log_document_id_fkey;
ALTER TABLE public.module_document_access_log ADD CONSTRAINT module_document_access_log_document_id_fkey
  FOREIGN KEY ("tenant_id", "document_id")
  REFERENCES public.module_documents ("tenant_id", "id") ON DELETE CASCADE;
ALTER TABLE public.module_document_access_log DROP CONSTRAINT IF EXISTS module_document_access_log_user_id_fkey;
ALTER TABLE public.module_document_access_log ADD CONSTRAINT module_document_access_log_user_id_fkey
  FOREIGN KEY ("tenant_id", "user_id")
  REFERENCES public.tenant_users ("tenant_id", "id");
-- module_document_shares
ALTER TABLE public.module_document_shares DROP CONSTRAINT IF EXISTS module_document_shares_created_by_fkey;
ALTER TABLE public.module_document_shares ADD CONSTRAINT module_document_shares_created_by_fkey
  FOREIGN KEY ("tenant_id", "created_by")
  REFERENCES public.tenant_users ("tenant_id", "id");
ALTER TABLE public.module_document_shares DROP CONSTRAINT IF EXISTS module_document_shares_document_id_fkey;
ALTER TABLE public.module_document_shares ADD CONSTRAINT module_document_shares_document_id_fkey
  FOREIGN KEY ("tenant_id", "document_id")
  REFERENCES public.module_documents ("tenant_id", "id") ON DELETE CASCADE;
-- module_documents
ALTER TABLE public.module_documents DROP CONSTRAINT IF EXISTS module_documents_approved_by_fkey;
ALTER TABLE public.module_documents ADD CONSTRAINT module_documents_approved_by_fkey
  FOREIGN KEY ("tenant_id", "approved_by")
  REFERENCES public.tenant_users ("tenant_id", "id");
ALTER TABLE public.module_documents DROP CONSTRAINT IF EXISTS module_documents_uploaded_by_fkey;
ALTER TABLE public.module_documents ADD CONSTRAINT module_documents_uploaded_by_fkey
  FOREIGN KEY ("tenant_id", "uploaded_by")
  REFERENCES public.tenant_users ("tenant_id", "id");
-- mrp_pending_docs
ALTER TABLE public.mrp_pending_docs DROP CONSTRAINT IF EXISTS mrp_pending_docs_product_id_fkey;
ALTER TABLE public.mrp_pending_docs ADD CONSTRAINT mrp_pending_docs_product_id_fkey
  FOREIGN KEY ("tenant_id", "product_id")
  REFERENCES public.products ("tenant_id", "id") ON DELETE SET NULL ("product_id");
-- mrp_proposals
ALTER TABLE public.mrp_proposals DROP CONSTRAINT IF EXISTS mrp_proposals_bom_id_fkey;
ALTER TABLE public.mrp_proposals ADD CONSTRAINT mrp_proposals_bom_id_fkey
  FOREIGN KEY ("tenant_id", "bom_id")
  REFERENCES public.boms ("tenant_id", "id") ON DELETE SET NULL ("bom_id");
ALTER TABLE public.mrp_proposals DROP CONSTRAINT IF EXISTS mrp_proposals_mrp_run_id_fkey;
ALTER TABLE public.mrp_proposals ADD CONSTRAINT mrp_proposals_mrp_run_id_fkey
  FOREIGN KEY ("tenant_id", "mrp_run_id")
  REFERENCES public.mrp_runs ("tenant_id", "id") ON DELETE CASCADE;
ALTER TABLE public.mrp_proposals DROP CONSTRAINT IF EXISTS mrp_proposals_product_id_fkey;
ALTER TABLE public.mrp_proposals ADD CONSTRAINT mrp_proposals_product_id_fkey
  FOREIGN KEY ("tenant_id", "product_id")
  REFERENCES public.products ("tenant_id", "id") ON DELETE CASCADE;
ALTER TABLE public.mrp_proposals DROP CONSTRAINT IF EXISTS mrp_proposals_supplier_id_fkey;
ALTER TABLE public.mrp_proposals ADD CONSTRAINT mrp_proposals_supplier_id_fkey
  FOREIGN KEY ("tenant_id", "supplier_id")
  REFERENCES public.suppliers ("tenant_id", "id") ON DELETE SET NULL ("supplier_id");
-- notification_preferences
ALTER TABLE public.notification_preferences DROP CONSTRAINT IF EXISTS notification_preferences_employee_id_fkey;
ALTER TABLE public.notification_preferences ADD CONSTRAINT notification_preferences_employee_id_fkey
  FOREIGN KEY ("tenant_id", "employee_id")
  REFERENCES public.employees ("tenant_id", "id") ON DELETE CASCADE;
-- of_consumptions
ALTER TABLE public.of_consumptions DROP CONSTRAINT IF EXISTS of_consumptions_manufacturing_order_id_fkey;
ALTER TABLE public.of_consumptions ADD CONSTRAINT of_consumptions_manufacturing_order_id_fkey
  FOREIGN KEY ("tenant_id", "manufacturing_order_id")
  REFERENCES public.manufacturing_orders ("tenant_id", "id") ON DELETE CASCADE;
ALTER TABLE public.of_consumptions DROP CONSTRAINT IF EXISTS of_consumptions_product_id_fkey;
ALTER TABLE public.of_consumptions ADD CONSTRAINT of_consumptions_product_id_fkey
  FOREIGN KEY ("tenant_id", "product_id")
  REFERENCES public.products ("tenant_id", "id") ON DELETE CASCADE;
-- of_document_access
ALTER TABLE public.of_document_access DROP CONSTRAINT IF EXISTS of_document_access_user_id_fkey;
ALTER TABLE public.of_document_access ADD CONSTRAINT of_document_access_user_id_fkey
  FOREIGN KEY ("tenant_id", "user_id")
  REFERENCES public.users ("tenant_id", "id") ON DELETE CASCADE;
-- of_labels
ALTER TABLE public.of_labels DROP CONSTRAINT IF EXISTS of_labels_manufacturing_order_id_fkey;
ALTER TABLE public.of_labels ADD CONSTRAINT of_labels_manufacturing_order_id_fkey
  FOREIGN KEY ("tenant_id", "manufacturing_order_id")
  REFERENCES public.manufacturing_orders ("tenant_id", "id") ON DELETE CASCADE;
ALTER TABLE public.of_labels DROP CONSTRAINT IF EXISTS of_labels_product_id_fkey;
ALTER TABLE public.of_labels ADD CONSTRAINT of_labels_product_id_fkey
  FOREIGN KEY ("tenant_id", "product_id")
  REFERENCES public.products ("tenant_id", "id") ON DELETE SET NULL ("product_id");
-- of_lots
ALTER TABLE public.of_lots DROP CONSTRAINT IF EXISTS of_lots_manufacturing_order_id_fkey;
ALTER TABLE public.of_lots ADD CONSTRAINT of_lots_manufacturing_order_id_fkey
  FOREIGN KEY ("tenant_id", "manufacturing_order_id")
  REFERENCES public.manufacturing_orders ("tenant_id", "id") ON DELETE CASCADE;
ALTER TABLE public.of_lots DROP CONSTRAINT IF EXISTS of_lots_product_id_fkey;
ALTER TABLE public.of_lots ADD CONSTRAINT of_lots_product_id_fkey
  FOREIGN KEY ("tenant_id", "product_id")
  REFERENCES public.products ("tenant_id", "id") ON DELETE SET NULL ("product_id");
-- online_payments
ALTER TABLE public.online_payments DROP CONSTRAINT IF EXISTS online_payments_customer_id_fkey;
ALTER TABLE public.online_payments ADD CONSTRAINT online_payments_customer_id_fkey
  FOREIGN KEY ("tenant_id", "customer_id")
  REFERENCES public.customers ("tenant_id", "id") ON DELETE SET NULL ("customer_id");
ALTER TABLE public.online_payments DROP CONSTRAINT IF EXISTS online_payments_invoice_id_fkey;
ALTER TABLE public.online_payments ADD CONSTRAINT online_payments_invoice_id_fkey
  FOREIGN KEY ("tenant_id", "invoice_id")
  REFERENCES public.invoices ("tenant_id", "id") ON DELETE SET NULL ("invoice_id");
-- partner_categories
ALTER TABLE public.partner_categories DROP CONSTRAINT IF EXISTS pc_parent_id_fkey;
ALTER TABLE public.partner_categories ADD CONSTRAINT pc_parent_id_fkey
  FOREIGN KEY ("tenant_id", "parent_id")
  REFERENCES public.partner_categories ("tenant_id", "id") ON DELETE SET NULL ("parent_id");
-- partner_category_mappings
ALTER TABLE public.partner_category_mappings DROP CONSTRAINT IF EXISTS partner_category_mappings_category_id_fkey;
ALTER TABLE public.partner_category_mappings ADD CONSTRAINT partner_category_mappings_category_id_fkey
  FOREIGN KEY ("tenant_id", "category_id")
  REFERENCES public.partner_categories ("tenant_id", "id") ON DELETE CASCADE;
-- pas_rates
ALTER TABLE public.pas_rates DROP CONSTRAINT IF EXISTS pas_rates_employee_id_fkey;
ALTER TABLE public.pas_rates ADD CONSTRAINT pas_rates_employee_id_fkey
  FOREIGN KEY ("tenant_id", "employee_id")
  REFERENCES public.employees ("tenant_id", "id") ON DELETE CASCADE;
-- pay_recalls
ALTER TABLE public.pay_recalls DROP CONSTRAINT IF EXISTS pay_recalls_employee_id_fkey;
ALTER TABLE public.pay_recalls ADD CONSTRAINT pay_recalls_employee_id_fkey
  FOREIGN KEY ("tenant_id", "employee_id")
  REFERENCES public.employees ("tenant_id", "id") ON DELETE CASCADE;
ALTER TABLE public.pay_recalls DROP CONSTRAINT IF EXISTS pay_recalls_processed_pay_run_id_fkey;
ALTER TABLE public.pay_recalls ADD CONSTRAINT pay_recalls_processed_pay_run_id_fkey
  FOREIGN KEY ("tenant_id", "processed_pay_run_id")
  REFERENCES public.pay_runs ("tenant_id", "id") ON DELETE SET NULL ("processed_pay_run_id");
-- pay_slip_clarified
ALTER TABLE public.pay_slip_clarified DROP CONSTRAINT IF EXISTS pay_slip_clarified_pay_slip_id_fkey;
ALTER TABLE public.pay_slip_clarified ADD CONSTRAINT pay_slip_clarified_pay_slip_id_fkey
  FOREIGN KEY ("tenant_id", "pay_slip_id")
  REFERENCES public.pay_slips ("tenant_id", "id") ON DELETE CASCADE;
-- pay_slips
ALTER TABLE public.pay_slips DROP CONSTRAINT IF EXISTS pay_slips_employee_id_fkey;
ALTER TABLE public.pay_slips ADD CONSTRAINT pay_slips_employee_id_fkey
  FOREIGN KEY ("tenant_id", "employee_id")
  REFERENCES public.employees ("tenant_id", "id") ON DELETE CASCADE;
ALTER TABLE public.pay_slips DROP CONSTRAINT IF EXISTS pay_slips_pay_run_id_fkey;
ALTER TABLE public.pay_slips ADD CONSTRAINT pay_slips_pay_run_id_fkey
  FOREIGN KEY ("tenant_id", "pay_run_id")
  REFERENCES public.pay_runs ("tenant_id", "id") ON DELETE CASCADE;
-- payment_orders
ALTER TABLE public.payment_orders DROP CONSTRAINT IF EXISTS payment_orders_bank_account_id_fkey;
ALTER TABLE public.payment_orders ADD CONSTRAINT payment_orders_bank_account_id_fkey
  FOREIGN KEY ("tenant_id", "bank_account_id")
  REFERENCES public.bank_accounts ("tenant_id", "id") ON DELETE SET NULL ("bank_account_id");
ALTER TABLE public.payment_orders DROP CONSTRAINT IF EXISTS payment_orders_third_party_id_fkey;
ALTER TABLE public.payment_orders ADD CONSTRAINT payment_orders_third_party_id_fkey
  FOREIGN KEY ("tenant_id", "third_party_id")
  REFERENCES public.third_party_accounts ("tenant_id", "id") ON DELETE SET NULL ("third_party_id");
-- payroll_accounting_entries
ALTER TABLE public.payroll_accounting_entries DROP CONSTRAINT IF EXISTS payroll_accounting_entries_journal_entry_id_fkey;
ALTER TABLE public.payroll_accounting_entries ADD CONSTRAINT payroll_accounting_entries_journal_entry_id_fkey
  FOREIGN KEY ("tenant_id", "journal_entry_id")
  REFERENCES public.journal_entries ("tenant_id", "id") ON DELETE SET NULL ("journal_entry_id");
ALTER TABLE public.payroll_accounting_entries DROP CONSTRAINT IF EXISTS payroll_accounting_entries_pay_run_id_fkey;
ALTER TABLE public.payroll_accounting_entries ADD CONSTRAINT payroll_accounting_entries_pay_run_id_fkey
  FOREIGN KEY ("tenant_id", "pay_run_id")
  REFERENCES public.pay_runs ("tenant_id", "id") ON DELETE SET NULL ("pay_run_id");
-- payroll_archives
ALTER TABLE public.payroll_archives DROP CONSTRAINT IF EXISTS payroll_archives_employee_id_fkey;
ALTER TABLE public.payroll_archives ADD CONSTRAINT payroll_archives_employee_id_fkey
  FOREIGN KEY ("tenant_id", "employee_id")
  REFERENCES public.employees ("tenant_id", "id") ON DELETE SET NULL ("employee_id");
-- payroll_component_rates
ALTER TABLE public.payroll_component_rates DROP CONSTRAINT IF EXISTS payroll_component_rates_component_id_fkey;
ALTER TABLE public.payroll_component_rates ADD CONSTRAINT payroll_component_rates_component_id_fkey
  FOREIGN KEY ("tenant_id", "component_id")
  REFERENCES public.payroll_components ("tenant_id", "id") ON DELETE CASCADE;
-- payroll_variable_elements
ALTER TABLE public.payroll_variable_elements DROP CONSTRAINT IF EXISTS payroll_variable_elements_employee_id_fkey;
ALTER TABLE public.payroll_variable_elements ADD CONSTRAINT payroll_variable_elements_employee_id_fkey
  FOREIGN KEY ("tenant_id", "employee_id")
  REFERENCES public.employees ("tenant_id", "id") ON DELETE CASCADE;
ALTER TABLE public.payroll_variable_elements DROP CONSTRAINT IF EXISTS pve_pay_run_id_fkey;
ALTER TABLE public.payroll_variable_elements ADD CONSTRAINT pve_pay_run_id_fkey
  FOREIGN KEY ("tenant_id", "pay_run_id")
  REFERENCES public.pay_runs ("tenant_id", "id") ON DELETE SET NULL ("pay_run_id");
-- pick_list_lines
ALTER TABLE public.pick_list_lines DROP CONSTRAINT IF EXISTS pick_list_lines_location_id_fkey;
ALTER TABLE public.pick_list_lines ADD CONSTRAINT pick_list_lines_location_id_fkey
  FOREIGN KEY ("tenant_id", "location_id")
  REFERENCES public.warehouse_locations ("tenant_id", "id") ON DELETE SET NULL ("location_id");
ALTER TABLE public.pick_list_lines DROP CONSTRAINT IF EXISTS pick_list_lines_pick_list_id_fkey;
ALTER TABLE public.pick_list_lines ADD CONSTRAINT pick_list_lines_pick_list_id_fkey
  FOREIGN KEY ("tenant_id", "pick_list_id")
  REFERENCES public.pick_lists ("tenant_id", "id") ON DELETE CASCADE;
ALTER TABLE public.pick_list_lines DROP CONSTRAINT IF EXISTS pick_list_lines_product_id_fkey;
ALTER TABLE public.pick_list_lines ADD CONSTRAINT pick_list_lines_product_id_fkey
  FOREIGN KEY ("tenant_id", "product_id")
  REFERENCES public.products ("tenant_id", "id") ON DELETE CASCADE;
-- pick_lists
ALTER TABLE public.pick_lists DROP CONSTRAINT IF EXISTS pick_lists_warehouse_id_fkey;
ALTER TABLE public.pick_lists ADD CONSTRAINT pick_lists_warehouse_id_fkey
  FOREIGN KEY ("tenant_id", "warehouse_id")
  REFERENCES public.warehouses ("tenant_id", "id") ON DELETE SET NULL ("warehouse_id");
-- planning_slots
ALTER TABLE public.planning_slots DROP CONSTRAINT IF EXISTS planning_slots_machine_id_fkey;
ALTER TABLE public.planning_slots ADD CONSTRAINT planning_slots_machine_id_fkey
  FOREIGN KEY ("tenant_id", "machine_id")
  REFERENCES public.machines ("tenant_id", "id") ON DELETE SET NULL ("machine_id");
ALTER TABLE public.planning_slots DROP CONSTRAINT IF EXISTS planning_slots_manufacturing_order_id_fkey;
ALTER TABLE public.planning_slots ADD CONSTRAINT planning_slots_manufacturing_order_id_fkey
  FOREIGN KEY ("tenant_id", "manufacturing_order_id")
  REFERENCES public.manufacturing_orders ("tenant_id", "id") ON DELETE CASCADE;
ALTER TABLE public.planning_slots DROP CONSTRAINT IF EXISTS planning_slots_routing_operation_id_fkey;
ALTER TABLE public.planning_slots ADD CONSTRAINT planning_slots_routing_operation_id_fkey
  FOREIGN KEY ("tenant_id", "routing_operation_id")
  REFERENCES public.routing_operations ("tenant_id", "id") ON DELETE SET NULL ("routing_operation_id");
ALTER TABLE public.planning_slots DROP CONSTRAINT IF EXISTS planning_slots_work_center_id_fkey;
ALTER TABLE public.planning_slots ADD CONSTRAINT planning_slots_work_center_id_fkey
  FOREIGN KEY ("tenant_id", "work_center_id")
  REFERENCES public.work_centers ("tenant_id", "id") ON DELETE SET NULL ("work_center_id");
-- pos_sessions
ALTER TABLE public.pos_sessions DROP CONSTRAINT IF EXISTS pos_sessions_terminal_id_fkey;
ALTER TABLE public.pos_sessions ADD CONSTRAINT pos_sessions_terminal_id_fkey
  FOREIGN KEY ("tenant_id", "terminal_id")
  REFERENCES public.pos_terminals ("tenant_id", "id") ON DELETE CASCADE;
-- pos_terminals
ALTER TABLE public.pos_terminals DROP CONSTRAINT IF EXISTS pos_terminals_warehouse_id_fkey;
ALTER TABLE public.pos_terminals ADD CONSTRAINT pos_terminals_warehouse_id_fkey
  FOREIGN KEY ("tenant_id", "warehouse_id")
  REFERENCES public.warehouses ("tenant_id", "id") ON DELETE SET NULL ("warehouse_id");
-- pos_ticket_lines
ALTER TABLE public.pos_ticket_lines DROP CONSTRAINT IF EXISTS pos_ticket_lines_product_id_fkey;
ALTER TABLE public.pos_ticket_lines ADD CONSTRAINT pos_ticket_lines_product_id_fkey
  FOREIGN KEY ("tenant_id", "product_id")
  REFERENCES public.products ("tenant_id", "id") ON DELETE SET NULL ("product_id");
ALTER TABLE public.pos_ticket_lines DROP CONSTRAINT IF EXISTS pos_ticket_lines_ticket_id_fkey;
ALTER TABLE public.pos_ticket_lines ADD CONSTRAINT pos_ticket_lines_ticket_id_fkey
  FOREIGN KEY ("tenant_id", "ticket_id")
  REFERENCES public.pos_tickets ("tenant_id", "id") ON DELETE CASCADE;
-- pos_tickets
ALTER TABLE public.pos_tickets DROP CONSTRAINT IF EXISTS pos_tickets_customer_id_fkey;
ALTER TABLE public.pos_tickets ADD CONSTRAINT pos_tickets_customer_id_fkey
  FOREIGN KEY ("tenant_id", "customer_id")
  REFERENCES public.customers ("tenant_id", "id") ON DELETE SET NULL ("customer_id");
ALTER TABLE public.pos_tickets DROP CONSTRAINT IF EXISTS pos_tickets_session_id_fkey;
ALTER TABLE public.pos_tickets ADD CONSTRAINT pos_tickets_session_id_fkey
  FOREIGN KEY ("tenant_id", "session_id")
  REFERENCES public.pos_sessions ("tenant_id", "id") ON DELETE CASCADE;
ALTER TABLE public.pos_tickets DROP CONSTRAINT IF EXISTS pos_tickets_terminal_id_fkey;
ALTER TABLE public.pos_tickets ADD CONSTRAINT pos_tickets_terminal_id_fkey
  FOREIGN KEY ("tenant_id", "terminal_id")
  REFERENCES public.pos_terminals ("tenant_id", "id") ON DELETE CASCADE;
-- price_list_customers
ALTER TABLE public.price_list_customers DROP CONSTRAINT IF EXISTS price_list_customers_customer_id_fkey;
ALTER TABLE public.price_list_customers ADD CONSTRAINT price_list_customers_customer_id_fkey
  FOREIGN KEY ("tenant_id", "customer_id")
  REFERENCES public.customers ("tenant_id", "id") ON DELETE CASCADE;
ALTER TABLE public.price_list_customers DROP CONSTRAINT IF EXISTS price_list_customers_price_list_id_fkey;
ALTER TABLE public.price_list_customers ADD CONSTRAINT price_list_customers_price_list_id_fkey
  FOREIGN KEY ("tenant_id", "price_list_id")
  REFERENCES public.price_lists ("tenant_id", "id") ON DELETE CASCADE;
-- price_list_lines
ALTER TABLE public.price_list_lines DROP CONSTRAINT IF EXISTS price_list_lines_price_list_id_fkey;
ALTER TABLE public.price_list_lines ADD CONSTRAINT price_list_lines_price_list_id_fkey
  FOREIGN KEY ("tenant_id", "price_list_id")
  REFERENCES public.price_lists ("tenant_id", "id") ON DELETE CASCADE;
ALTER TABLE public.price_list_lines DROP CONSTRAINT IF EXISTS price_list_lines_product_id_fkey;
ALTER TABLE public.price_list_lines ADD CONSTRAINT price_list_lines_product_id_fkey
  FOREIGN KEY ("tenant_id", "product_id")
  REFERENCES public.products ("tenant_id", "id") ON DELETE CASCADE;
-- product_batches
ALTER TABLE public.product_batches DROP CONSTRAINT IF EXISTS product_batches_product_id_fkey;
ALTER TABLE public.product_batches ADD CONSTRAINT product_batches_product_id_fkey
  FOREIGN KEY ("tenant_id", "product_id")
  REFERENCES public.products ("tenant_id", "id") ON DELETE CASCADE;
-- product_categories
ALTER TABLE public.product_categories DROP CONSTRAINT IF EXISTS product_categories_parent_id_fkey;
ALTER TABLE public.product_categories ADD CONSTRAINT product_categories_parent_id_fkey
  FOREIGN KEY ("tenant_id", "parent_id")
  REFERENCES public.product_categories ("tenant_id", "id");
-- product_equivalences
ALTER TABLE public.product_equivalences DROP CONSTRAINT IF EXISTS product_equivalences_equivalent_product_id_fkey;
ALTER TABLE public.product_equivalences ADD CONSTRAINT product_equivalences_equivalent_product_id_fkey
  FOREIGN KEY ("tenant_id", "equivalent_product_id")
  REFERENCES public.products ("tenant_id", "id") ON DELETE CASCADE;
ALTER TABLE public.product_equivalences DROP CONSTRAINT IF EXISTS product_equivalences_product_id_fkey;
ALTER TABLE public.product_equivalences ADD CONSTRAINT product_equivalences_product_id_fkey
  FOREIGN KEY ("tenant_id", "product_id")
  REFERENCES public.products ("tenant_id", "id") ON DELETE CASCADE;
-- product_grid_combinations
ALTER TABLE public.product_grid_combinations DROP CONSTRAINT IF EXISTS product_grid_combinations_product_id_fkey;
ALTER TABLE public.product_grid_combinations ADD CONSTRAINT product_grid_combinations_product_id_fkey
  FOREIGN KEY ("tenant_id", "product_id")
  REFERENCES public.products ("tenant_id", "id") ON DELETE CASCADE;
-- product_grids
ALTER TABLE public.product_grids DROP CONSTRAINT IF EXISTS product_grids_product_id_fkey;
ALTER TABLE public.product_grids ADD CONSTRAINT product_grids_product_id_fkey
  FOREIGN KEY ("tenant_id", "product_id")
  REFERENCES public.products ("tenant_id", "id") ON DELETE CASCADE;
-- product_links
ALTER TABLE public.product_links DROP CONSTRAINT IF EXISTS product_links_linked_product_id_fkey;
ALTER TABLE public.product_links ADD CONSTRAINT product_links_linked_product_id_fkey
  FOREIGN KEY ("tenant_id", "linked_product_id")
  REFERENCES public.products ("tenant_id", "id") ON DELETE CASCADE;
ALTER TABLE public.product_links DROP CONSTRAINT IF EXISTS product_links_product_id_fkey;
ALTER TABLE public.product_links ADD CONSTRAINT product_links_product_id_fkey
  FOREIGN KEY ("tenant_id", "product_id")
  REFERENCES public.products ("tenant_id", "id") ON DELETE CASCADE;
-- product_packagings
ALTER TABLE public.product_packagings DROP CONSTRAINT IF EXISTS product_packagings_product_id_fkey;
ALTER TABLE public.product_packagings ADD CONSTRAINT product_packagings_product_id_fkey
  FOREIGN KEY ("tenant_id", "product_id")
  REFERENCES public.products ("tenant_id", "id") ON DELETE CASCADE;
-- product_serial_numbers
ALTER TABLE public.product_serial_numbers DROP CONSTRAINT IF EXISTS product_serial_numbers_product_id_fkey;
ALTER TABLE public.product_serial_numbers ADD CONSTRAINT product_serial_numbers_product_id_fkey
  FOREIGN KEY ("tenant_id", "product_id")
  REFERENCES public.products ("tenant_id", "id") ON DELETE CASCADE;
-- product_substitutes
ALTER TABLE public.product_substitutes DROP CONSTRAINT IF EXISTS product_substitutes_product_id_fkey;
ALTER TABLE public.product_substitutes ADD CONSTRAINT product_substitutes_product_id_fkey
  FOREIGN KEY ("tenant_id", "product_id")
  REFERENCES public.products ("tenant_id", "id") ON DELETE CASCADE;
ALTER TABLE public.product_substitutes DROP CONSTRAINT IF EXISTS product_substitutes_substitute_id_fkey;
ALTER TABLE public.product_substitutes ADD CONSTRAINT product_substitutes_substitute_id_fkey
  FOREIGN KEY ("tenant_id", "substitute_id")
  REFERENCES public.products ("tenant_id", "id") ON DELETE CASCADE;
-- product_variants
ALTER TABLE public.product_variants DROP CONSTRAINT IF EXISTS product_variants_product_id_fkey;
ALTER TABLE public.product_variants ADD CONSTRAINT product_variants_product_id_fkey
  FOREIGN KEY ("tenant_id", "product_id")
  REFERENCES public.products ("tenant_id", "id") ON DELETE CASCADE;
-- production_forecasts
ALTER TABLE public.production_forecasts DROP CONSTRAINT IF EXISTS production_forecasts_product_id_fkey;
ALTER TABLE public.production_forecasts ADD CONSTRAINT production_forecasts_product_id_fkey
  FOREIGN KEY ("tenant_id", "product_id")
  REFERENCES public.products ("tenant_id", "id") ON DELETE SET NULL ("product_id");
-- products
ALTER TABLE public.products DROP CONSTRAINT IF EXISTS products_category_fk;
ALTER TABLE public.products ADD CONSTRAINT products_category_fk
  FOREIGN KEY ("tenant_id", "category_id")
  REFERENCES public.product_categories ("tenant_id", "id") ON DELETE SET NULL ("category_id");
ALTER TABLE public.products DROP CONSTRAINT IF EXISTS products_purchase_uom_id_fkey;
ALTER TABLE public.products ADD CONSTRAINT products_purchase_uom_id_fkey
  FOREIGN KEY ("tenant_id", "purchase_uom_id")
  REFERENCES public.uoms ("tenant_id", "id");
ALTER TABLE public.products DROP CONSTRAINT IF EXISTS products_sale_uom_id_fkey;
ALTER TABLE public.products ADD CONSTRAINT products_sale_uom_id_fkey
  FOREIGN KEY ("tenant_id", "sale_uom_id")
  REFERENCES public.uoms ("tenant_id", "id");
ALTER TABLE public.products DROP CONSTRAINT IF EXISTS products_uom_id_fkey;
ALTER TABLE public.products ADD CONSTRAINT products_uom_id_fkey
  FOREIGN KEY ("tenant_id", "uom_id")
  REFERENCES public.uoms ("tenant_id", "id");
-- project_activity_log
ALTER TABLE public.project_activity_log DROP CONSTRAINT IF EXISTS project_activity_log_project_id_fkey;
ALTER TABLE public.project_activity_log ADD CONSTRAINT project_activity_log_project_id_fkey
  FOREIGN KEY ("tenant_id", "project_id")
  REFERENCES public.projects ("tenant_id", "id") ON DELETE SET NULL ("project_id");
ALTER TABLE public.project_activity_log DROP CONSTRAINT IF EXISTS project_activity_log_task_id_fkey;
ALTER TABLE public.project_activity_log ADD CONSTRAINT project_activity_log_task_id_fkey
  FOREIGN KEY ("tenant_id", "task_id")
  REFERENCES public.project_tasks ("tenant_id", "id") ON DELETE CASCADE;
-- project_docs
ALTER TABLE public.project_docs DROP CONSTRAINT IF EXISTS project_docs_project_id_fkey;
ALTER TABLE public.project_docs ADD CONSTRAINT project_docs_project_id_fkey
  FOREIGN KEY ("tenant_id", "project_id")
  REFERENCES public.projects ("tenant_id", "id") ON DELETE CASCADE;
-- project_members
ALTER TABLE public.project_members DROP CONSTRAINT IF EXISTS project_members_employee_id_fkey;
ALTER TABLE public.project_members ADD CONSTRAINT project_members_employee_id_fkey
  FOREIGN KEY ("tenant_id", "employee_id")
  REFERENCES public.employees ("tenant_id", "id") ON DELETE CASCADE;
ALTER TABLE public.project_members DROP CONSTRAINT IF EXISTS project_members_project_id_fkey;
ALTER TABLE public.project_members ADD CONSTRAINT project_members_project_id_fkey
  FOREIGN KEY ("tenant_id", "project_id")
  REFERENCES public.projects ("tenant_id", "id") ON DELETE CASCADE;
-- project_milestones
ALTER TABLE public.project_milestones DROP CONSTRAINT IF EXISTS project_milestones_project_id_fkey;
ALTER TABLE public.project_milestones ADD CONSTRAINT project_milestones_project_id_fkey
  FOREIGN KEY ("tenant_id", "project_id")
  REFERENCES public.projects ("tenant_id", "id") ON DELETE CASCADE;
-- project_notifications
ALTER TABLE public.project_notifications DROP CONSTRAINT IF EXISTS project_notifications_project_id_fkey;
ALTER TABLE public.project_notifications ADD CONSTRAINT project_notifications_project_id_fkey
  FOREIGN KEY ("tenant_id", "project_id")
  REFERENCES public.projects ("tenant_id", "id") ON DELETE SET NULL ("project_id");
ALTER TABLE public.project_notifications DROP CONSTRAINT IF EXISTS project_notifications_recipient_id_fkey;
ALTER TABLE public.project_notifications ADD CONSTRAINT project_notifications_recipient_id_fkey
  FOREIGN KEY ("tenant_id", "recipient_id")
  REFERENCES public.employees ("tenant_id", "id") ON DELETE CASCADE;
ALTER TABLE public.project_notifications DROP CONSTRAINT IF EXISTS project_notifications_task_id_fkey;
ALTER TABLE public.project_notifications ADD CONSTRAINT project_notifications_task_id_fkey
  FOREIGN KEY ("tenant_id", "task_id")
  REFERENCES public.project_tasks ("tenant_id", "id") ON DELETE CASCADE;
-- project_task_dependencies
ALTER TABLE public.project_task_dependencies DROP CONSTRAINT IF EXISTS project_task_dependencies_depends_on_task_id_fkey;
ALTER TABLE public.project_task_dependencies ADD CONSTRAINT project_task_dependencies_depends_on_task_id_fkey
  FOREIGN KEY ("tenant_id", "depends_on_task_id")
  REFERENCES public.project_tasks ("tenant_id", "id") ON DELETE CASCADE;
ALTER TABLE public.project_task_dependencies DROP CONSTRAINT IF EXISTS project_task_dependencies_task_id_fkey;
ALTER TABLE public.project_task_dependencies ADD CONSTRAINT project_task_dependencies_task_id_fkey
  FOREIGN KEY ("tenant_id", "task_id")
  REFERENCES public.project_tasks ("tenant_id", "id") ON DELETE CASCADE;
-- project_task_tags
ALTER TABLE public.project_task_tags DROP CONSTRAINT IF EXISTS project_task_tags_tag_id_fkey;
ALTER TABLE public.project_task_tags ADD CONSTRAINT project_task_tags_tag_id_fkey
  FOREIGN KEY ("tenant_id", "tag_id")
  REFERENCES public.project_tags ("tenant_id", "id") ON DELETE CASCADE;
ALTER TABLE public.project_task_tags DROP CONSTRAINT IF EXISTS project_task_tags_task_id_fkey;
ALTER TABLE public.project_task_tags ADD CONSTRAINT project_task_tags_task_id_fkey
  FOREIGN KEY ("tenant_id", "task_id")
  REFERENCES public.project_tasks ("tenant_id", "id") ON DELETE CASCADE;
-- project_task_watchers
ALTER TABLE public.project_task_watchers DROP CONSTRAINT IF EXISTS project_task_watchers_employee_id_fkey;
ALTER TABLE public.project_task_watchers ADD CONSTRAINT project_task_watchers_employee_id_fkey
  FOREIGN KEY ("tenant_id", "employee_id")
  REFERENCES public.employees ("tenant_id", "id") ON DELETE CASCADE;
ALTER TABLE public.project_task_watchers DROP CONSTRAINT IF EXISTS project_task_watchers_task_id_fkey;
ALTER TABLE public.project_task_watchers ADD CONSTRAINT project_task_watchers_task_id_fkey
  FOREIGN KEY ("tenant_id", "task_id")
  REFERENCES public.project_tasks ("tenant_id", "id") ON DELETE CASCADE;
-- project_tasks
ALTER TABLE public.project_tasks DROP CONSTRAINT IF EXISTS project_tasks_assignee_id_fkey;
ALTER TABLE public.project_tasks ADD CONSTRAINT project_tasks_assignee_id_fkey
  FOREIGN KEY ("tenant_id", "assignee_id")
  REFERENCES public.employees ("tenant_id", "id") ON DELETE SET NULL ("assignee_id");
ALTER TABLE public.project_tasks DROP CONSTRAINT IF EXISTS project_tasks_milestone_id_fkey;
ALTER TABLE public.project_tasks ADD CONSTRAINT project_tasks_milestone_id_fkey
  FOREIGN KEY ("tenant_id", "milestone_id")
  REFERENCES public.project_milestones ("tenant_id", "id") ON DELETE SET NULL ("milestone_id");
ALTER TABLE public.project_tasks DROP CONSTRAINT IF EXISTS project_tasks_parent_id_fkey;
ALTER TABLE public.project_tasks ADD CONSTRAINT project_tasks_parent_id_fkey
  FOREIGN KEY ("tenant_id", "parent_id")
  REFERENCES public.project_tasks ("tenant_id", "id") ON DELETE CASCADE;
ALTER TABLE public.project_tasks DROP CONSTRAINT IF EXISTS project_tasks_project_id_fkey;
ALTER TABLE public.project_tasks ADD CONSTRAINT project_tasks_project_id_fkey
  FOREIGN KEY ("tenant_id", "project_id")
  REFERENCES public.projects ("tenant_id", "id") ON DELETE SET NULL ("project_id");
-- project_time_entries
ALTER TABLE public.project_time_entries DROP CONSTRAINT IF EXISTS project_time_entries_employee_id_fkey;
ALTER TABLE public.project_time_entries ADD CONSTRAINT project_time_entries_employee_id_fkey
  FOREIGN KEY ("tenant_id", "employee_id")
  REFERENCES public.employees ("tenant_id", "id") ON DELETE SET NULL ("employee_id");
ALTER TABLE public.project_time_entries DROP CONSTRAINT IF EXISTS project_time_entries_project_id_fkey;
ALTER TABLE public.project_time_entries ADD CONSTRAINT project_time_entries_project_id_fkey
  FOREIGN KEY ("tenant_id", "project_id")
  REFERENCES public.projects ("tenant_id", "id") ON DELETE SET NULL ("project_id");
ALTER TABLE public.project_time_entries DROP CONSTRAINT IF EXISTS project_time_entries_task_id_fkey;
ALTER TABLE public.project_time_entries ADD CONSTRAINT project_time_entries_task_id_fkey
  FOREIGN KEY ("tenant_id", "task_id")
  REFERENCES public.project_tasks ("tenant_id", "id") ON DELETE CASCADE;
-- projects
ALTER TABLE public.projects DROP CONSTRAINT IF EXISTS proj_manager_id_fkey;
ALTER TABLE public.projects ADD CONSTRAINT proj_manager_id_fkey
  FOREIGN KEY ("tenant_id", "manager_id")
  REFERENCES public.employees ("tenant_id", "id") ON DELETE SET NULL ("manager_id");
ALTER TABLE public.projects DROP CONSTRAINT IF EXISTS projects_customer_id_fkey;
ALTER TABLE public.projects ADD CONSTRAINT projects_customer_id_fkey
  FOREIGN KEY ("tenant_id", "customer_id")
  REFERENCES public.customers ("tenant_id", "id") ON DELETE SET NULL ("customer_id");
-- promotions
ALTER TABLE public.promotions DROP CONSTRAINT IF EXISTS promotions_customer_id_fkey;
ALTER TABLE public.promotions ADD CONSTRAINT promotions_customer_id_fkey
  FOREIGN KEY ("tenant_id", "customer_id")
  REFERENCES public.customers ("tenant_id", "id") ON DELETE CASCADE;
ALTER TABLE public.promotions DROP CONSTRAINT IF EXISTS promotions_free_product_id_fkey;
ALTER TABLE public.promotions ADD CONSTRAINT promotions_free_product_id_fkey
  FOREIGN KEY ("tenant_id", "free_product_id")
  REFERENCES public.products ("tenant_id", "id") ON DELETE SET NULL ("free_product_id");
ALTER TABLE public.promotions DROP CONSTRAINT IF EXISTS promotions_product_id_fkey;
ALTER TABLE public.promotions ADD CONSTRAINT promotions_product_id_fkey
  FOREIGN KEY ("tenant_id", "product_id")
  REFERENCES public.products ("tenant_id", "id") ON DELETE CASCADE;
-- prospects
ALTER TABLE public.prospects DROP CONSTRAINT IF EXISTS prospects_assigned_rep_id_fkey;
ALTER TABLE public.prospects ADD CONSTRAINT prospects_assigned_rep_id_fkey
  FOREIGN KEY ("tenant_id", "assigned_rep_id")
  REFERENCES public.sales_representatives ("tenant_id", "id") ON DELETE SET NULL ("assigned_rep_id");
ALTER TABLE public.prospects DROP CONSTRAINT IF EXISTS prospects_converted_customer_id_fkey;
ALTER TABLE public.prospects ADD CONSTRAINT prospects_converted_customer_id_fkey
  FOREIGN KEY ("tenant_id", "converted_customer_id")
  REFERENCES public.customers ("tenant_id", "id") ON DELETE SET NULL ("converted_customer_id");
-- purchase_credit_lines
ALTER TABLE public.purchase_credit_lines DROP CONSTRAINT IF EXISTS purchase_credit_lines_product_id_fkey;
ALTER TABLE public.purchase_credit_lines ADD CONSTRAINT purchase_credit_lines_product_id_fkey
  FOREIGN KEY ("tenant_id", "product_id")
  REFERENCES public.products ("tenant_id", "id") ON DELETE SET NULL ("product_id");
ALTER TABLE public.purchase_credit_lines DROP CONSTRAINT IF EXISTS purchase_credit_lines_purchase_credit_id_fkey;
ALTER TABLE public.purchase_credit_lines ADD CONSTRAINT purchase_credit_lines_purchase_credit_id_fkey
  FOREIGN KEY ("tenant_id", "purchase_credit_id")
  REFERENCES public.purchase_credit_notes ("tenant_id", "id") ON DELETE CASCADE;
-- purchase_credit_notes
ALTER TABLE public.purchase_credit_notes DROP CONSTRAINT IF EXISTS purchase_credit_notes_purchase_invoice_id_fkey;
ALTER TABLE public.purchase_credit_notes ADD CONSTRAINT purchase_credit_notes_purchase_invoice_id_fkey
  FOREIGN KEY ("tenant_id", "purchase_invoice_id")
  REFERENCES public.purchase_invoices ("tenant_id", "id") ON DELETE SET NULL ("purchase_invoice_id");
ALTER TABLE public.purchase_credit_notes DROP CONSTRAINT IF EXISTS purchase_credit_notes_supplier_id_fkey;
ALTER TABLE public.purchase_credit_notes ADD CONSTRAINT purchase_credit_notes_supplier_id_fkey
  FOREIGN KEY ("tenant_id", "supplier_id")
  REFERENCES public.suppliers ("tenant_id", "id") ON DELETE SET NULL ("supplier_id");
ALTER TABLE public.purchase_credit_notes DROP CONSTRAINT IF EXISTS purchase_credit_notes_transferred_entry_id_fkey;
ALTER TABLE public.purchase_credit_notes ADD CONSTRAINT purchase_credit_notes_transferred_entry_id_fkey
  FOREIGN KEY ("tenant_id", "transferred_entry_id")
  REFERENCES public.journal_entries ("tenant_id", "id");
-- purchase_invoice_lines
ALTER TABLE public.purchase_invoice_lines DROP CONSTRAINT IF EXISTS purchase_invoice_lines_product_id_fkey;
ALTER TABLE public.purchase_invoice_lines ADD CONSTRAINT purchase_invoice_lines_product_id_fkey
  FOREIGN KEY ("tenant_id", "product_id")
  REFERENCES public.products ("tenant_id", "id") ON DELETE SET NULL ("product_id");
ALTER TABLE public.purchase_invoice_lines DROP CONSTRAINT IF EXISTS purchase_invoice_lines_purchase_invoice_id_fkey;
ALTER TABLE public.purchase_invoice_lines ADD CONSTRAINT purchase_invoice_lines_purchase_invoice_id_fkey
  FOREIGN KEY ("tenant_id", "purchase_invoice_id")
  REFERENCES public.purchase_invoices ("tenant_id", "id") ON DELETE CASCADE;
ALTER TABLE public.purchase_invoice_lines DROP CONSTRAINT IF EXISTS purchase_invoice_lines_purchase_order_line_id_fkey;
ALTER TABLE public.purchase_invoice_lines ADD CONSTRAINT purchase_invoice_lines_purchase_order_line_id_fkey
  FOREIGN KEY ("tenant_id", "purchase_order_line_id")
  REFERENCES public.purchase_order_lines ("tenant_id", "id") ON DELETE SET NULL ("purchase_order_line_id");
-- purchase_invoices
ALTER TABLE public.purchase_invoices DROP CONSTRAINT IF EXISTS purchase_invoices_fiscal_position_id_fkey;
ALTER TABLE public.purchase_invoices ADD CONSTRAINT purchase_invoices_fiscal_position_id_fkey
  FOREIGN KEY ("tenant_id", "fiscal_position_id")
  REFERENCES public.fiscal_positions ("tenant_id", "id");
ALTER TABLE public.purchase_invoices DROP CONSTRAINT IF EXISTS purchase_invoices_goods_receipt_id_fkey;
ALTER TABLE public.purchase_invoices ADD CONSTRAINT purchase_invoices_goods_receipt_id_fkey
  FOREIGN KEY ("tenant_id", "goods_receipt_id")
  REFERENCES public.goods_receipts ("tenant_id", "id") ON DELETE SET NULL ("goods_receipt_id");
ALTER TABLE public.purchase_invoices DROP CONSTRAINT IF EXISTS purchase_invoices_purchase_order_id_fkey;
ALTER TABLE public.purchase_invoices ADD CONSTRAINT purchase_invoices_purchase_order_id_fkey
  FOREIGN KEY ("tenant_id", "purchase_order_id")
  REFERENCES public.purchase_orders ("tenant_id", "id") ON DELETE SET NULL ("purchase_order_id");
ALTER TABLE public.purchase_invoices DROP CONSTRAINT IF EXISTS purchase_invoices_supplier_id_fkey;
ALTER TABLE public.purchase_invoices ADD CONSTRAINT purchase_invoices_supplier_id_fkey
  FOREIGN KEY ("tenant_id", "supplier_id")
  REFERENCES public.suppliers ("tenant_id", "id") ON DELETE SET NULL ("supplier_id");
ALTER TABLE public.purchase_invoices DROP CONSTRAINT IF EXISTS purchase_invoices_transferred_entry_id_fkey;
ALTER TABLE public.purchase_invoices ADD CONSTRAINT purchase_invoices_transferred_entry_id_fkey
  FOREIGN KEY ("tenant_id", "transferred_entry_id")
  REFERENCES public.journal_entries ("tenant_id", "id");
-- purchase_order_lines
ALTER TABLE public.purchase_order_lines DROP CONSTRAINT IF EXISTS purchase_order_lines_product_id_fkey;
ALTER TABLE public.purchase_order_lines ADD CONSTRAINT purchase_order_lines_product_id_fkey
  FOREIGN KEY ("tenant_id", "product_id")
  REFERENCES public.products ("tenant_id", "id") ON DELETE SET NULL ("product_id");
ALTER TABLE public.purchase_order_lines DROP CONSTRAINT IF EXISTS purchase_order_lines_purchase_order_id_fkey;
ALTER TABLE public.purchase_order_lines ADD CONSTRAINT purchase_order_lines_purchase_order_id_fkey
  FOREIGN KEY ("tenant_id", "purchase_order_id")
  REFERENCES public.purchase_orders ("tenant_id", "id") ON DELETE CASCADE;
-- purchase_orders
ALTER TABLE public.purchase_orders DROP CONSTRAINT IF EXISTS purchase_orders_supplier_id_fkey;
ALTER TABLE public.purchase_orders ADD CONSTRAINT purchase_orders_supplier_id_fkey
  FOREIGN KEY ("tenant_id", "supplier_id")
  REFERENCES public.suppliers ("tenant_id", "id") ON DELETE SET NULL ("supplier_id");
-- purchase_request_lines
ALTER TABLE public.purchase_request_lines DROP CONSTRAINT IF EXISTS purchase_request_lines_preferred_supplier_id_fkey;
ALTER TABLE public.purchase_request_lines ADD CONSTRAINT purchase_request_lines_preferred_supplier_id_fkey
  FOREIGN KEY ("tenant_id", "preferred_supplier_id")
  REFERENCES public.suppliers ("tenant_id", "id") ON DELETE SET NULL ("preferred_supplier_id");
ALTER TABLE public.purchase_request_lines DROP CONSTRAINT IF EXISTS purchase_request_lines_product_id_fkey;
ALTER TABLE public.purchase_request_lines ADD CONSTRAINT purchase_request_lines_product_id_fkey
  FOREIGN KEY ("tenant_id", "product_id")
  REFERENCES public.products ("tenant_id", "id") ON DELETE SET NULL ("product_id");
ALTER TABLE public.purchase_request_lines DROP CONSTRAINT IF EXISTS purchase_request_lines_purchase_request_id_fkey;
ALTER TABLE public.purchase_request_lines ADD CONSTRAINT purchase_request_lines_purchase_request_id_fkey
  FOREIGN KEY ("tenant_id", "purchase_request_id")
  REFERENCES public.purchase_requests ("tenant_id", "id") ON DELETE CASCADE;
-- quality_checks
ALTER TABLE public.quality_checks DROP CONSTRAINT IF EXISTS quality_checks_product_id_fkey;
ALTER TABLE public.quality_checks ADD CONSTRAINT quality_checks_product_id_fkey
  FOREIGN KEY ("tenant_id", "product_id")
  REFERENCES public.products ("tenant_id", "id") ON DELETE CASCADE;
-- quality_control_points
ALTER TABLE public.quality_control_points DROP CONSTRAINT IF EXISTS quality_control_points_plan_id_fkey;
ALTER TABLE public.quality_control_points ADD CONSTRAINT quality_control_points_plan_id_fkey
  FOREIGN KEY ("tenant_id", "plan_id")
  REFERENCES public.quality_control_plans ("tenant_id", "id") ON DELETE CASCADE;
-- quote_lines
ALTER TABLE public.quote_lines DROP CONSTRAINT IF EXISTS quote_lines_product_id_fkey;
ALTER TABLE public.quote_lines ADD CONSTRAINT quote_lines_product_id_fkey
  FOREIGN KEY ("tenant_id", "product_id")
  REFERENCES public.products ("tenant_id", "id") ON DELETE SET NULL ("product_id");
ALTER TABLE public.quote_lines DROP CONSTRAINT IF EXISTS quote_lines_quote_id_fkey;
ALTER TABLE public.quote_lines ADD CONSTRAINT quote_lines_quote_id_fkey
  FOREIGN KEY ("tenant_id", "quote_id")
  REFERENCES public.quotes ("tenant_id", "id") ON DELETE CASCADE;
-- quotes
ALTER TABLE public.quotes DROP CONSTRAINT IF EXISTS quotes_customer_id_fkey;
ALTER TABLE public.quotes ADD CONSTRAINT quotes_customer_id_fkey
  FOREIGN KEY ("tenant_id", "customer_id")
  REFERENCES public.customers ("tenant_id", "id") ON DELETE SET NULL ("customer_id");
ALTER TABLE public.quotes DROP CONSTRAINT IF EXISTS quotes_transformed_to_order_id_fkey;
ALTER TABLE public.quotes ADD CONSTRAINT quotes_transformed_to_order_id_fkey
  FOREIGN KEY ("tenant_id", "transformed_to_order_id")
  REFERENCES public.sales_orders ("tenant_id", "id") ON DELETE SET NULL ("transformed_to_order_id");
-- recurring_invoice_templates
ALTER TABLE public.recurring_invoice_templates DROP CONSTRAINT IF EXISTS recurring_invoice_templates_customer_id_fkey;
ALTER TABLE public.recurring_invoice_templates ADD CONSTRAINT recurring_invoice_templates_customer_id_fkey
  FOREIGN KEY ("tenant_id", "customer_id")
  REFERENCES public.customers ("tenant_id", "id") ON DELETE SET NULL ("customer_id");
-- regularization_entries
ALTER TABLE public.regularization_entries DROP CONSTRAINT IF EXISTS reg_created_entry_id_fkey;
ALTER TABLE public.regularization_entries ADD CONSTRAINT reg_created_entry_id_fkey
  FOREIGN KEY ("tenant_id", "created_entry_id")
  REFERENCES public.journal_entries ("tenant_id", "id") ON DELETE SET NULL ("created_entry_id");
ALTER TABLE public.regularization_entries DROP CONSTRAINT IF EXISTS reg_fiscal_year_id_fkey;
ALTER TABLE public.regularization_entries ADD CONSTRAINT reg_fiscal_year_id_fkey
  FOREIGN KEY ("tenant_id", "fiscal_year_id")
  REFERENCES public.fiscal_years ("tenant_id", "id") ON DELETE SET NULL ("fiscal_year_id");
-- reimputation_logs
ALTER TABLE public.reimputation_logs DROP CONSTRAINT IF EXISTS reimputation_logs_original_entry_id_fkey;
ALTER TABLE public.reimputation_logs ADD CONSTRAINT reimputation_logs_original_entry_id_fkey
  FOREIGN KEY ("tenant_id", "original_entry_id")
  REFERENCES public.journal_entries ("tenant_id", "id");
ALTER TABLE public.reimputation_logs DROP CONSTRAINT IF EXISTS reimputation_logs_original_line_id_fkey;
ALTER TABLE public.reimputation_logs ADD CONSTRAINT reimputation_logs_original_line_id_fkey
  FOREIGN KEY ("tenant_id", "original_line_id")
  REFERENCES public.journal_lines ("tenant_id", "id");
ALTER TABLE public.reimputation_logs DROP CONSTRAINT IF EXISTS rl_reimputed_entry_id_fkey;
ALTER TABLE public.reimputation_logs ADD CONSTRAINT rl_reimputed_entry_id_fkey
  FOREIGN KEY ("tenant_id", "reimputed_entry_id")
  REFERENCES public.journal_entries ("tenant_id", "id") ON DELETE SET NULL ("reimputed_entry_id");
-- rh_requests
ALTER TABLE public.rh_requests DROP CONSTRAINT IF EXISTS rh_requests_employee_id_fkey;
ALTER TABLE public.rh_requests ADD CONSTRAINT rh_requests_employee_id_fkey
  FOREIGN KEY ("tenant_id", "employee_id")
  REFERENCES public.employees ("tenant_id", "id") ON DELETE CASCADE;
-- role_permissions
ALTER TABLE public.role_permissions DROP CONSTRAINT IF EXISTS role_permissions_role_id_fkey;
ALTER TABLE public.role_permissions ADD CONSTRAINT role_permissions_role_id_fkey
  FOREIGN KEY ("tenant_id", "role_id")
  REFERENCES public.tenant_roles ("tenant_id", "id") ON DELETE CASCADE;
-- routing_operations
ALTER TABLE public.routing_operations DROP CONSTRAINT IF EXISTS routing_operations_machine_id_fkey;
ALTER TABLE public.routing_operations ADD CONSTRAINT routing_operations_machine_id_fkey
  FOREIGN KEY ("tenant_id", "machine_id")
  REFERENCES public.machines ("tenant_id", "id") ON DELETE SET NULL ("machine_id");
ALTER TABLE public.routing_operations DROP CONSTRAINT IF EXISTS routing_operations_routing_id_fkey;
ALTER TABLE public.routing_operations ADD CONSTRAINT routing_operations_routing_id_fkey
  FOREIGN KEY ("tenant_id", "routing_id")
  REFERENCES public.routings ("tenant_id", "id") ON DELETE CASCADE;
ALTER TABLE public.routing_operations DROP CONSTRAINT IF EXISTS routing_operations_supplier_id_fkey;
ALTER TABLE public.routing_operations ADD CONSTRAINT routing_operations_supplier_id_fkey
  FOREIGN KEY ("tenant_id", "supplier_id")
  REFERENCES public.suppliers ("tenant_id", "id") ON DELETE SET NULL ("supplier_id");
ALTER TABLE public.routing_operations DROP CONSTRAINT IF EXISTS routing_operations_tooling_id_fkey;
ALTER TABLE public.routing_operations ADD CONSTRAINT routing_operations_tooling_id_fkey
  FOREIGN KEY ("tenant_id", "tooling_id")
  REFERENCES public.toolings ("tenant_id", "id") ON DELETE SET NULL ("tooling_id");
ALTER TABLE public.routing_operations DROP CONSTRAINT IF EXISTS routing_operations_work_center_id_fkey;
ALTER TABLE public.routing_operations ADD CONSTRAINT routing_operations_work_center_id_fkey
  FOREIGN KEY ("tenant_id", "work_center_id")
  REFERENCES public.work_centers ("tenant_id", "id") ON DELETE SET NULL ("work_center_id");
-- routings
ALTER TABLE public.routings DROP CONSTRAINT IF EXISTS routings_product_id_fkey;
ALTER TABLE public.routings ADD CONSTRAINT routings_product_id_fkey
  FOREIGN KEY ("tenant_id", "product_id")
  REFERENCES public.products ("tenant_id", "id") ON DELETE SET NULL ("product_id");
-- salary_advances
ALTER TABLE public.salary_advances DROP CONSTRAINT IF EXISTS salary_advances_employee_id_fkey;
ALTER TABLE public.salary_advances ADD CONSTRAINT salary_advances_employee_id_fkey
  FOREIGN KEY ("tenant_id", "employee_id")
  REFERENCES public.employees ("tenant_id", "id") ON DELETE CASCADE;
-- sales_order_lines
ALTER TABLE public.sales_order_lines DROP CONSTRAINT IF EXISTS sales_order_lines_product_id_fkey;
ALTER TABLE public.sales_order_lines ADD CONSTRAINT sales_order_lines_product_id_fkey
  FOREIGN KEY ("tenant_id", "product_id")
  REFERENCES public.products ("tenant_id", "id") ON DELETE SET NULL ("product_id");
ALTER TABLE public.sales_order_lines DROP CONSTRAINT IF EXISTS sales_order_lines_sales_order_id_fkey;
ALTER TABLE public.sales_order_lines ADD CONSTRAINT sales_order_lines_sales_order_id_fkey
  FOREIGN KEY ("tenant_id", "sales_order_id")
  REFERENCES public.sales_orders ("tenant_id", "id") ON DELETE CASCADE;
-- sales_orders
ALTER TABLE public.sales_orders DROP CONSTRAINT IF EXISTS sales_orders_customer_id_fkey;
ALTER TABLE public.sales_orders ADD CONSTRAINT sales_orders_customer_id_fkey
  FOREIGN KEY ("tenant_id", "customer_id")
  REFERENCES public.customers ("tenant_id", "id") ON DELETE SET NULL ("customer_id");
ALTER TABLE public.sales_orders DROP CONSTRAINT IF EXISTS sales_orders_quote_id_fkey;
ALTER TABLE public.sales_orders ADD CONSTRAINT sales_orders_quote_id_fkey
  FOREIGN KEY ("tenant_id", "quote_id")
  REFERENCES public.quotes ("tenant_id", "id") ON DELETE SET NULL ("quote_id");
-- sepa_payment_orders
ALTER TABLE public.sepa_payment_orders DROP CONSTRAINT IF EXISTS spo_pay_run_id_fkey;
ALTER TABLE public.sepa_payment_orders ADD CONSTRAINT spo_pay_run_id_fkey
  FOREIGN KEY ("tenant_id", "pay_run_id")
  REFERENCES public.pay_runs ("tenant_id", "id") ON DELETE SET NULL ("pay_run_id");
-- service_contracts
ALTER TABLE public.service_contracts DROP CONSTRAINT IF EXISTS service_contracts_customer_id_fkey;
ALTER TABLE public.service_contracts ADD CONSTRAINT service_contracts_customer_id_fkey
  FOREIGN KEY ("tenant_id", "customer_id")
  REFERENCES public.customers ("tenant_id", "id") ON DELETE CASCADE;
-- service_ticket_messages
ALTER TABLE public.service_ticket_messages DROP CONSTRAINT IF EXISTS service_ticket_messages_ticket_id_fkey;
ALTER TABLE public.service_ticket_messages ADD CONSTRAINT service_ticket_messages_ticket_id_fkey
  FOREIGN KEY ("tenant_id", "ticket_id")
  REFERENCES public.service_tickets ("tenant_id", "id") ON DELETE CASCADE;
-- service_tickets
ALTER TABLE public.service_tickets DROP CONSTRAINT IF EXISTS service_tickets_contact_id_fkey;
ALTER TABLE public.service_tickets ADD CONSTRAINT service_tickets_contact_id_fkey
  FOREIGN KEY ("tenant_id", "contact_id")
  REFERENCES public.customer_contacts ("tenant_id", "id") ON DELETE SET NULL ("contact_id");
ALTER TABLE public.service_tickets DROP CONSTRAINT IF EXISTS service_tickets_customer_id_fkey;
ALTER TABLE public.service_tickets ADD CONSTRAINT service_tickets_customer_id_fkey
  FOREIGN KEY ("tenant_id", "customer_id")
  REFERENCES public.customers ("tenant_id", "id") ON DELETE CASCADE;
-- sick_leaves
ALTER TABLE public.sick_leaves DROP CONSTRAINT IF EXISTS sick_leaves_employee_id_fkey;
ALTER TABLE public.sick_leaves ADD CONSTRAINT sick_leaves_employee_id_fkey
  FOREIGN KEY ("tenant_id", "employee_id")
  REFERENCES public.employees ("tenant_id", "id") ON DELETE CASCADE;
-- st_orders
ALTER TABLE public.st_orders DROP CONSTRAINT IF EXISTS st_orders_manufacturing_order_id_fkey;
ALTER TABLE public.st_orders ADD CONSTRAINT st_orders_manufacturing_order_id_fkey
  FOREIGN KEY ("tenant_id", "manufacturing_order_id")
  REFERENCES public.manufacturing_orders ("tenant_id", "id") ON DELETE SET NULL ("manufacturing_order_id");
ALTER TABLE public.st_orders DROP CONSTRAINT IF EXISTS st_orders_product_id_fkey;
ALTER TABLE public.st_orders ADD CONSTRAINT st_orders_product_id_fkey
  FOREIGN KEY ("tenant_id", "product_id")
  REFERENCES public.products ("tenant_id", "id") ON DELETE SET NULL ("product_id");
ALTER TABLE public.st_orders DROP CONSTRAINT IF EXISTS st_orders_routing_operation_id_fkey;
ALTER TABLE public.st_orders ADD CONSTRAINT st_orders_routing_operation_id_fkey
  FOREIGN KEY ("tenant_id", "routing_operation_id")
  REFERENCES public.routing_operations ("tenant_id", "id") ON DELETE SET NULL ("routing_operation_id");
ALTER TABLE public.st_orders DROP CONSTRAINT IF EXISTS st_orders_supplier_id_fkey;
ALTER TABLE public.st_orders ADD CONSTRAINT st_orders_supplier_id_fkey
  FOREIGN KEY ("tenant_id", "supplier_id")
  REFERENCES public.suppliers ("tenant_id", "id") ON DELETE RESTRICT;
-- st_receipt_lines
ALTER TABLE public.st_receipt_lines DROP CONSTRAINT IF EXISTS st_receipt_lines_product_id_fkey;
ALTER TABLE public.st_receipt_lines ADD CONSTRAINT st_receipt_lines_product_id_fkey
  FOREIGN KEY ("tenant_id", "product_id")
  REFERENCES public.products ("tenant_id", "id") ON DELETE CASCADE;
ALTER TABLE public.st_receipt_lines DROP CONSTRAINT IF EXISTS st_receipt_lines_st_receipt_id_fkey;
ALTER TABLE public.st_receipt_lines ADD CONSTRAINT st_receipt_lines_st_receipt_id_fkey
  FOREIGN KEY ("tenant_id", "st_receipt_id")
  REFERENCES public.st_receipts ("tenant_id", "id") ON DELETE CASCADE;
-- st_receipts
ALTER TABLE public.st_receipts DROP CONSTRAINT IF EXISTS st_receipts_st_order_id_fkey;
ALTER TABLE public.st_receipts ADD CONSTRAINT st_receipts_st_order_id_fkey
  FOREIGN KEY ("tenant_id", "st_order_id")
  REFERENCES public.st_orders ("tenant_id", "id") ON DELETE CASCADE;
ALTER TABLE public.st_receipts DROP CONSTRAINT IF EXISTS st_receipts_warehouse_id_fkey;
ALTER TABLE public.st_receipts ADD CONSTRAINT st_receipts_warehouse_id_fkey
  FOREIGN KEY ("tenant_id", "warehouse_id")
  REFERENCES public.warehouses ("tenant_id", "id") ON DELETE SET NULL ("warehouse_id");
-- st_shipment_lines
ALTER TABLE public.st_shipment_lines DROP CONSTRAINT IF EXISTS st_shipment_lines_product_id_fkey;
ALTER TABLE public.st_shipment_lines ADD CONSTRAINT st_shipment_lines_product_id_fkey
  FOREIGN KEY ("tenant_id", "product_id")
  REFERENCES public.products ("tenant_id", "id") ON DELETE CASCADE;
ALTER TABLE public.st_shipment_lines DROP CONSTRAINT IF EXISTS st_shipment_lines_st_shipment_id_fkey;
ALTER TABLE public.st_shipment_lines ADD CONSTRAINT st_shipment_lines_st_shipment_id_fkey
  FOREIGN KEY ("tenant_id", "st_shipment_id")
  REFERENCES public.st_shipments ("tenant_id", "id") ON DELETE CASCADE;
-- st_shipments
ALTER TABLE public.st_shipments DROP CONSTRAINT IF EXISTS st_shipments_st_order_id_fkey;
ALTER TABLE public.st_shipments ADD CONSTRAINT st_shipments_st_order_id_fkey
  FOREIGN KEY ("tenant_id", "st_order_id")
  REFERENCES public.st_orders ("tenant_id", "id") ON DELETE CASCADE;
ALTER TABLE public.st_shipments DROP CONSTRAINT IF EXISTS st_shipments_warehouse_id_fkey;
ALTER TABLE public.st_shipments ADD CONSTRAINT st_shipments_warehouse_id_fkey
  FOREIGN KEY ("tenant_id", "warehouse_id")
  REFERENCES public.warehouses ("tenant_id", "id") ON DELETE SET NULL ("warehouse_id");
-- stock_alerts
ALTER TABLE public.stock_alerts DROP CONSTRAINT IF EXISTS stock_alerts_product_id_fkey;
ALTER TABLE public.stock_alerts ADD CONSTRAINT stock_alerts_product_id_fkey
  FOREIGN KEY ("tenant_id", "product_id")
  REFERENCES public.products ("tenant_id", "id") ON DELETE CASCADE;
ALTER TABLE public.stock_alerts DROP CONSTRAINT IF EXISTS stock_alerts_warehouse_id_fkey;
ALTER TABLE public.stock_alerts ADD CONSTRAINT stock_alerts_warehouse_id_fkey
  FOREIGN KEY ("tenant_id", "warehouse_id")
  REFERENCES public.warehouses ("tenant_id", "id") ON DELETE SET NULL ("warehouse_id");
-- stock_movements
ALTER TABLE public.stock_movements DROP CONSTRAINT IF EXISTS sm_warehouse_id_fkey;
ALTER TABLE public.stock_movements ADD CONSTRAINT sm_warehouse_id_fkey
  FOREIGN KEY ("tenant_id", "warehouse_id")
  REFERENCES public.warehouses ("tenant_id", "id") ON DELETE SET NULL ("warehouse_id");
ALTER TABLE public.stock_movements DROP CONSTRAINT IF EXISTS stock_movements_product_id_fkey;
ALTER TABLE public.stock_movements ADD CONSTRAINT stock_movements_product_id_fkey
  FOREIGN KEY ("tenant_id", "product_id")
  REFERENCES public.products ("tenant_id", "id") ON DELETE CASCADE;
-- stock_quantities
ALTER TABLE public.stock_quantities DROP CONSTRAINT IF EXISTS stock_quantities_location_id_fkey;
ALTER TABLE public.stock_quantities ADD CONSTRAINT stock_quantities_location_id_fkey
  FOREIGN KEY ("tenant_id", "location_id")
  REFERENCES public.warehouse_locations ("tenant_id", "id") ON DELETE SET NULL ("location_id");
ALTER TABLE public.stock_quantities DROP CONSTRAINT IF EXISTS stock_quantities_product_id_fkey;
ALTER TABLE public.stock_quantities ADD CONSTRAINT stock_quantities_product_id_fkey
  FOREIGN KEY ("tenant_id", "product_id")
  REFERENCES public.products ("tenant_id", "id") ON DELETE CASCADE;
ALTER TABLE public.stock_quantities DROP CONSTRAINT IF EXISTS stock_quantities_warehouse_id_fkey;
ALTER TABLE public.stock_quantities ADD CONSTRAINT stock_quantities_warehouse_id_fkey
  FOREIGN KEY ("tenant_id", "warehouse_id")
  REFERENCES public.warehouses ("tenant_id", "id") ON DELETE CASCADE;
-- stock_transfer_lines
ALTER TABLE public.stock_transfer_lines DROP CONSTRAINT IF EXISTS stock_transfer_lines_transfer_id_fkey;
ALTER TABLE public.stock_transfer_lines ADD CONSTRAINT stock_transfer_lines_transfer_id_fkey
  FOREIGN KEY ("tenant_id", "transfer_id")
  REFERENCES public.stock_transfers ("tenant_id", "id") ON DELETE CASCADE;
-- supplier_contacts
ALTER TABLE public.supplier_contacts DROP CONSTRAINT IF EXISTS supplier_contacts_supplier_id_fkey;
ALTER TABLE public.supplier_contacts ADD CONSTRAINT supplier_contacts_supplier_id_fkey
  FOREIGN KEY ("tenant_id", "supplier_id")
  REFERENCES public.suppliers ("tenant_id", "id") ON DELETE CASCADE;
-- supplier_delivery_schedules
ALTER TABLE public.supplier_delivery_schedules DROP CONSTRAINT IF EXISTS supplier_delivery_schedules_product_id_fkey;
ALTER TABLE public.supplier_delivery_schedules ADD CONSTRAINT supplier_delivery_schedules_product_id_fkey
  FOREIGN KEY ("tenant_id", "product_id")
  REFERENCES public.products ("tenant_id", "id") ON DELETE CASCADE;
ALTER TABLE public.supplier_delivery_schedules DROP CONSTRAINT IF EXISTS supplier_delivery_schedules_supplier_id_fkey;
ALTER TABLE public.supplier_delivery_schedules ADD CONSTRAINT supplier_delivery_schedules_supplier_id_fkey
  FOREIGN KEY ("tenant_id", "supplier_id")
  REFERENCES public.suppliers ("tenant_id", "id") ON DELETE CASCADE;
ALTER TABLE public.supplier_delivery_schedules DROP CONSTRAINT IF EXISTS supplier_delivery_schedules_warehouse_id_fkey;
ALTER TABLE public.supplier_delivery_schedules ADD CONSTRAINT supplier_delivery_schedules_warehouse_id_fkey
  FOREIGN KEY ("tenant_id", "warehouse_id")
  REFERENCES public.warehouses ("tenant_id", "id") ON DELETE SET NULL ("warehouse_id");
-- supplier_payments
ALTER TABLE public.supplier_payments DROP CONSTRAINT IF EXISTS supplier_payments_bank_account_id_fkey;
ALTER TABLE public.supplier_payments ADD CONSTRAINT supplier_payments_bank_account_id_fkey
  FOREIGN KEY ("tenant_id", "bank_account_id")
  REFERENCES public.bank_accounts ("tenant_id", "id") ON DELETE SET NULL ("bank_account_id");
ALTER TABLE public.supplier_payments DROP CONSTRAINT IF EXISTS supplier_payments_purchase_invoice_id_fkey;
ALTER TABLE public.supplier_payments ADD CONSTRAINT supplier_payments_purchase_invoice_id_fkey
  FOREIGN KEY ("tenant_id", "purchase_invoice_id")
  REFERENCES public.purchase_invoices ("tenant_id", "id") ON DELETE SET NULL ("purchase_invoice_id");
ALTER TABLE public.supplier_payments DROP CONSTRAINT IF EXISTS supplier_payments_supplier_id_fkey;
ALTER TABLE public.supplier_payments ADD CONSTRAINT supplier_payments_supplier_id_fkey
  FOREIGN KEY ("tenant_id", "supplier_id")
  REFERENCES public.suppliers ("tenant_id", "id") ON DELETE SET NULL ("supplier_id");
ALTER TABLE public.supplier_payments DROP CONSTRAINT IF EXISTS supplier_payments_transferred_entry_id_fkey;
ALTER TABLE public.supplier_payments ADD CONSTRAINT supplier_payments_transferred_entry_id_fkey
  FOREIGN KEY ("tenant_id", "transferred_entry_id")
  REFERENCES public.journal_entries ("tenant_id", "id");
-- supplier_price_list_lines
ALTER TABLE public.supplier_price_list_lines DROP CONSTRAINT IF EXISTS supplier_price_list_lines_price_list_id_fkey;
ALTER TABLE public.supplier_price_list_lines ADD CONSTRAINT supplier_price_list_lines_price_list_id_fkey
  FOREIGN KEY ("tenant_id", "price_list_id")
  REFERENCES public.supplier_price_lists ("tenant_id", "id") ON DELETE CASCADE;
ALTER TABLE public.supplier_price_list_lines DROP CONSTRAINT IF EXISTS supplier_price_list_lines_product_id_fkey;
ALTER TABLE public.supplier_price_list_lines ADD CONSTRAINT supplier_price_list_lines_product_id_fkey
  FOREIGN KEY ("tenant_id", "product_id")
  REFERENCES public.products ("tenant_id", "id") ON DELETE CASCADE;
-- supplier_price_lists
ALTER TABLE public.supplier_price_lists DROP CONSTRAINT IF EXISTS supplier_price_lists_supplier_id_fkey;
ALTER TABLE public.supplier_price_lists ADD CONSTRAINT supplier_price_lists_supplier_id_fkey
  FOREIGN KEY ("tenant_id", "supplier_id")
  REFERENCES public.suppliers ("tenant_id", "id") ON DELETE CASCADE;
-- suppliers
ALTER TABLE public.suppliers DROP CONSTRAINT IF EXISTS suppliers_bank_account_id_fkey;
ALTER TABLE public.suppliers ADD CONSTRAINT suppliers_bank_account_id_fkey
  FOREIGN KEY ("tenant_id", "bank_account_id")
  REFERENCES public.bank_accounts ("tenant_id", "id") ON DELETE SET NULL ("bank_account_id");
ALTER TABLE public.suppliers DROP CONSTRAINT IF EXISTS suppliers_parent_id_fkey;
ALTER TABLE public.suppliers ADD CONSTRAINT suppliers_parent_id_fkey
  FOREIGN KEY ("tenant_id", "parent_id")
  REFERENCES public.suppliers ("tenant_id", "id") ON DELETE SET NULL ("parent_id");
ALTER TABLE public.suppliers DROP CONSTRAINT IF EXISTS suppliers_price_list_id_fkey;
ALTER TABLE public.suppliers ADD CONSTRAINT suppliers_price_list_id_fkey
  FOREIGN KEY ("tenant_id", "price_list_id")
  REFERENCES public.price_lists ("tenant_id", "id") ON DELETE SET NULL ("price_list_id");
ALTER TABLE public.suppliers DROP CONSTRAINT IF EXISTS suppliers_sales_rep_id_fkey;
ALTER TABLE public.suppliers ADD CONSTRAINT suppliers_sales_rep_id_fkey
  FOREIGN KEY ("tenant_id", "sales_rep_id")
  REFERENCES public.sales_representatives ("tenant_id", "id") ON DELETE SET NULL ("sales_rep_id");
-- task_action_attachments
ALTER TABLE public.task_action_attachments DROP CONSTRAINT IF EXISTS task_action_attachments_task_action_id_fkey;
ALTER TABLE public.task_action_attachments ADD CONSTRAINT task_action_attachments_task_action_id_fkey
  FOREIGN KEY ("tenant_id", "task_action_id")
  REFERENCES public.task_actions ("tenant_id", "id") ON DELETE CASCADE;
ALTER TABLE public.task_action_attachments DROP CONSTRAINT IF EXISTS task_action_attachments_task_id_fkey;
ALTER TABLE public.task_action_attachments ADD CONSTRAINT task_action_attachments_task_id_fkey
  FOREIGN KEY ("tenant_id", "task_id")
  REFERENCES public.project_tasks ("tenant_id", "id") ON DELETE CASCADE;
-- task_actions
ALTER TABLE public.task_actions DROP CONSTRAINT IF EXISTS task_actions_task_id_fkey;
ALTER TABLE public.task_actions ADD CONSTRAINT task_actions_task_id_fkey
  FOREIGN KEY ("tenant_id", "task_id")
  REFERENCES public.project_tasks ("tenant_id", "id") ON DELETE CASCADE;
-- task_comments
ALTER TABLE public.task_comments DROP CONSTRAINT IF EXISTS task_comments_task_id_fkey;
ALTER TABLE public.task_comments ADD CONSTRAINT task_comments_task_id_fkey
  FOREIGN KEY ("tenant_id", "task_id")
  REFERENCES public.project_tasks ("tenant_id", "id") ON DELETE CASCADE;
-- task_documents
ALTER TABLE public.task_documents DROP CONSTRAINT IF EXISTS task_documents_project_id_fkey;
ALTER TABLE public.task_documents ADD CONSTRAINT task_documents_project_id_fkey
  FOREIGN KEY ("tenant_id", "project_id")
  REFERENCES public.projects ("tenant_id", "id") ON DELETE SET NULL ("project_id");
ALTER TABLE public.task_documents DROP CONSTRAINT IF EXISTS task_documents_task_id_fkey;
ALTER TABLE public.task_documents ADD CONSTRAINT task_documents_task_id_fkey
  FOREIGN KEY ("tenant_id", "task_id")
  REFERENCES public.project_tasks ("tenant_id", "id") ON DELETE CASCADE;
-- tax_cash_basis_entries
ALTER TABLE public.tax_cash_basis_entries DROP CONSTRAINT IF EXISTS tax_cash_basis_entries_tax_id_fkey;
ALTER TABLE public.tax_cash_basis_entries ADD CONSTRAINT tax_cash_basis_entries_tax_id_fkey
  FOREIGN KEY ("tenant_id", "tax_id")
  REFERENCES public.tax_rates ("tenant_id", "id");
ALTER TABLE public.tax_cash_basis_entries DROP CONSTRAINT IF EXISTS tcb_journal_entry_id_fkey;
ALTER TABLE public.tax_cash_basis_entries ADD CONSTRAINT tcb_journal_entry_id_fkey
  FOREIGN KEY ("tenant_id", "journal_entry_id")
  REFERENCES public.journal_entries ("tenant_id", "id") ON DELETE SET NULL ("journal_entry_id");
-- tax_payments
ALTER TABLE public.tax_payments DROP CONSTRAINT IF EXISTS tax_payments_bank_account_id_fkey;
ALTER TABLE public.tax_payments ADD CONSTRAINT tax_payments_bank_account_id_fkey
  FOREIGN KEY ("tenant_id", "bank_account_id")
  REFERENCES public.bank_accounts ("tenant_id", "id") ON DELETE SET NULL ("bank_account_id");
ALTER TABLE public.tax_payments DROP CONSTRAINT IF EXISTS tax_payments_journal_entry_id_fkey;
ALTER TABLE public.tax_payments ADD CONSTRAINT tax_payments_journal_entry_id_fkey
  FOREIGN KEY ("tenant_id", "journal_entry_id")
  REFERENCES public.journal_entries ("tenant_id", "id") ON DELETE SET NULL ("journal_entry_id");
-- tax_rates
ALTER TABLE public.tax_rates DROP CONSTRAINT IF EXISTS tax_rates_pack_code_fkey;
ALTER TABLE public.tax_rates ADD CONSTRAINT tax_rates_pack_code_fkey
  FOREIGN KEY ("tenant_id", "pack_code")
  REFERENCES public.legislation_packs ("tenant_id", "code") ON DELETE CASCADE;
ALTER TABLE public.tax_rates DROP CONSTRAINT IF EXISTS tax_rates_parent_tax_id_fkey;
ALTER TABLE public.tax_rates ADD CONSTRAINT tax_rates_parent_tax_id_fkey
  FOREIGN KEY ("tenant_id", "parent_tax_id")
  REFERENCES public.tax_rates ("tenant_id", "id");
-- tax_repartition_lines
ALTER TABLE public.tax_repartition_lines DROP CONSTRAINT IF EXISTS tax_repartition_lines_tax_id_fkey;
ALTER TABLE public.tax_repartition_lines ADD CONSTRAINT tax_repartition_lines_tax_id_fkey
  FOREIGN KEY ("tenant_id", "tax_id")
  REFERENCES public.tax_rates ("tenant_id", "id") ON DELETE CASCADE;
-- tenant_users
ALTER TABLE public.tenant_users DROP CONSTRAINT IF EXISTS tenant_users_custom_role_id_fkey;
ALTER TABLE public.tenant_users ADD CONSTRAINT tenant_users_custom_role_id_fkey
  FOREIGN KEY ("tenant_id", "custom_role_id")
  REFERENCES public.tenant_roles ("tenant_id", "id");
ALTER TABLE public.tenant_users DROP CONSTRAINT IF EXISTS tenant_users_invited_by_fkey;
ALTER TABLE public.tenant_users ADD CONSTRAINT tenant_users_invited_by_fkey
  FOREIGN KEY ("tenant_id", "invited_by")
  REFERENCES public.tenant_users ("tenant_id", "id");
-- third_party_accounts
ALTER TABLE public.third_party_accounts DROP CONSTRAINT IF EXISTS fk_tpa_payment_term;
ALTER TABLE public.third_party_accounts ADD CONSTRAINT fk_tpa_payment_term
  FOREIGN KEY ("tenant_id", "payment_term_id")
  REFERENCES public.payment_terms ("tenant_id", "id") ON DELETE SET NULL ("payment_term_id");
ALTER TABLE public.third_party_accounts DROP CONSTRAINT IF EXISTS third_party_accounts_customer_id_fkey;
ALTER TABLE public.third_party_accounts ADD CONSTRAINT third_party_accounts_customer_id_fkey
  FOREIGN KEY ("tenant_id", "customer_id")
  REFERENCES public.customers ("tenant_id", "id") ON DELETE SET NULL ("customer_id");
ALTER TABLE public.third_party_accounts DROP CONSTRAINT IF EXISTS third_party_accounts_employee_id_fkey;
ALTER TABLE public.third_party_accounts ADD CONSTRAINT third_party_accounts_employee_id_fkey
  FOREIGN KEY ("tenant_id", "employee_id")
  REFERENCES public.users ("tenant_id", "id") ON DELETE SET NULL ("employee_id");
ALTER TABLE public.third_party_accounts DROP CONSTRAINT IF EXISTS third_party_accounts_supplier_id_fkey;
ALTER TABLE public.third_party_accounts ADD CONSTRAINT third_party_accounts_supplier_id_fkey
  FOREIGN KEY ("tenant_id", "supplier_id")
  REFERENCES public.suppliers ("tenant_id", "id") ON DELETE SET NULL ("supplier_id");
ALTER TABLE public.third_party_accounts DROP CONSTRAINT IF EXISTS tpa_default_bank_account_id_fkey;
ALTER TABLE public.third_party_accounts ADD CONSTRAINT tpa_default_bank_account_id_fkey
  FOREIGN KEY ("tenant_id", "default_bank_account_id")
  REFERENCES public.bank_accounts ("tenant_id", "id") ON DELETE SET NULL ("default_bank_account_id");
-- three_way_matches
ALTER TABLE public.three_way_matches DROP CONSTRAINT IF EXISTS three_way_matches_goods_receipt_id_fkey;
ALTER TABLE public.three_way_matches ADD CONSTRAINT three_way_matches_goods_receipt_id_fkey
  FOREIGN KEY ("tenant_id", "goods_receipt_id")
  REFERENCES public.goods_receipts ("tenant_id", "id") ON DELETE SET NULL ("goods_receipt_id");
ALTER TABLE public.three_way_matches DROP CONSTRAINT IF EXISTS three_way_matches_purchase_invoice_id_fkey;
ALTER TABLE public.three_way_matches ADD CONSTRAINT three_way_matches_purchase_invoice_id_fkey
  FOREIGN KEY ("tenant_id", "purchase_invoice_id")
  REFERENCES public.purchase_invoices ("tenant_id", "id") ON DELETE CASCADE;
ALTER TABLE public.three_way_matches DROP CONSTRAINT IF EXISTS three_way_matches_purchase_order_id_fkey;
ALTER TABLE public.three_way_matches ADD CONSTRAINT three_way_matches_purchase_order_id_fkey
  FOREIGN KEY ("tenant_id", "purchase_order_id")
  REFERENCES public.purchase_orders ("tenant_id", "id") ON DELETE SET NULL ("purchase_order_id");
-- tier_ribs
ALTER TABLE public.tier_ribs DROP CONSTRAINT IF EXISTS tier_ribs_third_party_account_id_fkey;
ALTER TABLE public.tier_ribs ADD CONSTRAINT tier_ribs_third_party_account_id_fkey
  FOREIGN KEY ("tenant_id", "third_party_account_id")
  REFERENCES public.third_party_accounts ("tenant_id", "id") ON DELETE CASCADE;
-- timesheets
ALTER TABLE public.timesheets DROP CONSTRAINT IF EXISTS timesheets_employee_id_fkey;
ALTER TABLE public.timesheets ADD CONSTRAINT timesheets_employee_id_fkey
  FOREIGN KEY ("tenant_id", "employee_id")
  REFERENCES public.employees ("tenant_id", "id") ON DELETE CASCADE;
ALTER TABLE public.timesheets DROP CONSTRAINT IF EXISTS timesheets_project_id_fkey;
ALTER TABLE public.timesheets ADD CONSTRAINT timesheets_project_id_fkey
  FOREIGN KEY ("tenant_id", "project_id")
  REFERENCES public.projects ("tenant_id", "id") ON DELETE SET NULL ("project_id");
-- toolings
ALTER TABLE public.toolings DROP CONSTRAINT IF EXISTS toolings_machine_id_fkey;
ALTER TABLE public.toolings ADD CONSTRAINT toolings_machine_id_fkey
  FOREIGN KEY ("tenant_id", "machine_id")
  REFERENCES public.machines ("tenant_id", "id") ON DELETE SET NULL ("machine_id");
-- treasury_recurring
ALTER TABLE public.treasury_recurring DROP CONSTRAINT IF EXISTS treasury_recurring_bank_account_id_fkey;
ALTER TABLE public.treasury_recurring ADD CONSTRAINT treasury_recurring_bank_account_id_fkey
  FOREIGN KEY ("tenant_id", "bank_account_id")
  REFERENCES public.bank_accounts ("tenant_id", "id") ON DELETE SET NULL ("bank_account_id");
-- treasury_transfers
ALTER TABLE public.treasury_transfers DROP CONSTRAINT IF EXISTS treasury_transfers_from_account_id_fkey;
ALTER TABLE public.treasury_transfers ADD CONSTRAINT treasury_transfers_from_account_id_fkey
  FOREIGN KEY ("tenant_id", "from_account_id")
  REFERENCES public.bank_accounts ("tenant_id", "id") ON DELETE RESTRICT;
ALTER TABLE public.treasury_transfers DROP CONSTRAINT IF EXISTS treasury_transfers_to_account_id_fkey;
ALTER TABLE public.treasury_transfers ADD CONSTRAINT treasury_transfers_to_account_id_fkey
  FOREIGN KEY ("tenant_id", "to_account_id")
  REFERENCES public.bank_accounts ("tenant_id", "id") ON DELETE RESTRICT;
ALTER TABLE public.treasury_transfers DROP CONSTRAINT IF EXISTS tt_journal_entry_id_fkey;
ALTER TABLE public.treasury_transfers ADD CONSTRAINT tt_journal_entry_id_fkey
  FOREIGN KEY ("tenant_id", "journal_entry_id")
  REFERENCES public.journal_entries ("tenant_id", "id") ON DELETE SET NULL ("journal_entry_id");
-- uoms
ALTER TABLE public.uoms DROP CONSTRAINT IF EXISTS uoms_category_id_fkey;
ALTER TABLE public.uoms ADD CONSTRAINT uoms_category_id_fkey
  FOREIGN KEY ("tenant_id", "category_id")
  REFERENCES public.uom_categories ("tenant_id", "id") ON DELETE CASCADE;
-- value_date_tracking
ALTER TABLE public.value_date_tracking DROP CONSTRAINT IF EXISTS value_date_tracking_bank_account_id_fkey;
ALTER TABLE public.value_date_tracking ADD CONSTRAINT value_date_tracking_bank_account_id_fkey
  FOREIGN KEY ("tenant_id", "bank_account_id")
  REFERENCES public.bank_accounts ("tenant_id", "id") ON DELETE CASCADE;
-- vat_on_collections
ALTER TABLE public.vat_on_collections DROP CONSTRAINT IF EXISTS voc_fiscal_year_id_fkey;
ALTER TABLE public.vat_on_collections ADD CONSTRAINT voc_fiscal_year_id_fkey
  FOREIGN KEY ("tenant_id", "fiscal_year_id")
  REFERENCES public.fiscal_years ("tenant_id", "id") ON DELETE SET NULL ("fiscal_year_id");
ALTER TABLE public.vat_on_collections DROP CONSTRAINT IF EXISTS voc_journal_entry_id_fkey;
ALTER TABLE public.vat_on_collections ADD CONSTRAINT voc_journal_entry_id_fkey
  FOREIGN KEY ("tenant_id", "journal_entry_id")
  REFERENCES public.journal_entries ("tenant_id", "id") ON DELETE SET NULL ("journal_entry_id");
-- warehouse_locations
ALTER TABLE public.warehouse_locations DROP CONSTRAINT IF EXISTS warehouse_locations_parent_id_fkey;
ALTER TABLE public.warehouse_locations ADD CONSTRAINT warehouse_locations_parent_id_fkey
  FOREIGN KEY ("tenant_id", "parent_id")
  REFERENCES public.warehouse_locations ("tenant_id", "id");
ALTER TABLE public.warehouse_locations DROP CONSTRAINT IF EXISTS warehouse_locations_warehouse_id_fkey;
ALTER TABLE public.warehouse_locations ADD CONSTRAINT warehouse_locations_warehouse_id_fkey
  FOREIGN KEY ("tenant_id", "warehouse_id")
  REFERENCES public.warehouses ("tenant_id", "id") ON DELETE CASCADE;
-- warehouse_users
ALTER TABLE public.warehouse_users DROP CONSTRAINT IF EXISTS warehouse_users_warehouse_id_fkey;
ALTER TABLE public.warehouse_users ADD CONSTRAINT warehouse_users_warehouse_id_fkey
  FOREIGN KEY ("tenant_id", "warehouse_id")
  REFERENCES public.warehouses ("tenant_id", "id") ON DELETE CASCADE;
-- webhook_delivery_queue
ALTER TABLE public.webhook_delivery_queue DROP CONSTRAINT IF EXISTS webhook_delivery_queue_endpoint_id_fkey;
ALTER TABLE public.webhook_delivery_queue ADD CONSTRAINT webhook_delivery_queue_endpoint_id_fkey
  FOREIGN KEY ("tenant_id", "endpoint_id")
  REFERENCES public.webhook_endpoints ("tenant_id", "id") ON DELETE CASCADE;
-- work_hardship
ALTER TABLE public.work_hardship DROP CONSTRAINT IF EXISTS work_hardship_employee_id_fkey;
ALTER TABLE public.work_hardship ADD CONSTRAINT work_hardship_employee_id_fkey
  FOREIGN KEY ("tenant_id", "employee_id")
  REFERENCES public.employees ("tenant_id", "id") ON DELETE CASCADE;
-- work_hardship_records
ALTER TABLE public.work_hardship_records DROP CONSTRAINT IF EXISTS work_hardship_records_employee_id_fkey;
ALTER TABLE public.work_hardship_records ADD CONSTRAINT work_hardship_records_employee_id_fkey
  FOREIGN KEY ("tenant_id", "employee_id")
  REFERENCES public.employees ("tenant_id", "id") ON DELETE CASCADE;
-- work_stoppages
ALTER TABLE public.work_stoppages DROP CONSTRAINT IF EXISTS work_stoppages_employee_id_fkey;
ALTER TABLE public.work_stoppages ADD CONSTRAINT work_stoppages_employee_id_fkey
  FOREIGN KEY ("tenant_id", "employee_id")
  REFERENCES public.employees ("tenant_id", "id") ON DELETE CASCADE;

-- ── 3. La preuve, dans la migration elle-même ────────────────────────────
-- Le contrôle permanent (`ci/check_composite_fks.sql`) relit ce relevé à chaque
-- exécution ; la migration, elle, refuse de passer s'il reste une clé. La mesure
-- emploie EXACTEMENT le filtre du générateur, schéma du parent compris :
-- `auth.users` n'est pas cloisonné — un même compte appartient légitimement à
-- plusieurs sociétés, une clé composite y serait fausse.

DO $$
DECLARE v_reste text; v_n int;
BEGIN
  SELECT count(*), string_agg(cc.relname || '.' || a.attname || ' → ' || cp.relname, ', ' ORDER BY cc.relname)
    INTO v_n, v_reste
  FROM pg_constraint f
  JOIN pg_class cc     ON cc.oid = f.conrelid
  JOIN pg_namespace nc ON nc.oid = cc.relnamespace AND nc.nspname = 'public'
  JOIN pg_class cp     ON cp.oid = f.confrelid
  JOIN pg_namespace np ON np.oid = cp.relnamespace AND np.nspname = 'public'
  JOIN pg_attribute a  ON a.attrelid = f.conrelid AND a.attnum = f.conkey[1]
  WHERE f.contype = 'f' AND array_length(f.conkey, 1) = 1 AND a.attname <> 'tenant_id'
    AND EXISTS (SELECT 1 FROM information_schema.columns x
                WHERE x.table_schema = 'public' AND x.table_name = cc.relname AND x.column_name = 'tenant_id')
    AND EXISTS (SELECT 1 FROM information_schema.columns y
                WHERE y.table_schema = 'public' AND y.table_name = cp.relname AND y.column_name = 'tenant_id');
  IF v_n > 0 THEN
    RAISE EXCEPTION '[ISO-02] % clé(s) étrangère(s) mono-colonne(s) relient encore deux tables cloisonnées : %', v_n, v_reste;
  END IF;
  RAISE NOTICE '[ISO-02] aucune clé étrangère mono-colonne entre deux tables cloisonnées.';
END $$;

