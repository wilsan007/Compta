import { createClient } from '@supabase/supabase-js'

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL
const supabaseKey = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY

if (!supabaseUrl || !supabaseKey) {
  throw new Error('VITE_SUPABASE_URL and VITE_SUPABASE_PUBLISHABLE_KEY must be set in environment variables')
}

export const supabase = createClient(supabaseUrl, supabaseKey, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
  },
})

export type SupabaseClient = typeof supabase

// ============ Tenant table registry ============
const TENANT_TABLES = new Set([
  'company_settings', 'chart_accounts', 'customers', 'suppliers', 'products',
  'invoices', 'invoice_lines', 'quotes', 'quote_lines',
  'credit_notes', 'credit_note_lines',
  'purchase_invoices', 'purchase_invoice_lines',
  'purchase_orders', 'purchase_order_lines',
  'purchase_credit_notes', 'purchase_credit_lines',
  'bank_accounts', 'bank_transactions', 'bank_rules',
  'journal_entries', 'journal_lines',
  'vat_returns', 'projects', 'journals',
  'fiscal_years', 'fiscal_periods',
  'entry_templates', 'third_party_accounts', 'analytic_sections',
  'budgets', 'budget_commitments', 'standard_labels',
  'fixed_assets', 'asset_depreciations',
  'employees', 'pay_runs', 'pay_slips', 'timesheets', 'leave_requests',
  'payroll_accounting_entries',
  'currencies', 'audit_log',
  'warehouses', 'stock_quantities', 'stock_movements',
  'boms', 'bom_lines', 'manufacturing_orders',
  'price_lists', 'price_list_lines',
  'sales_orders', 'sales_order_lines',
  'delivery_notes', 'delivery_note_lines',
  'goods_receipts', 'goods_receipt_lines',
  'collection_reminders', 'contracts',
  'customer_payments', 'supplier_payments',
  'payment_orders', 'legal_declarations',
  'routings', 'routing_operations', 'work_centers', 'machines', 'toolings',
  'of_labels', 'of_lots', 'of_consumptions',
  'st_orders', 'st_shipments', 'st_shipment_lines', 'st_receipts', 'st_receipt_lines',
  'mrp_runs', 'mrp_proposals', 'mrp_pending_docs',
  'production_forecasts',
  'planning_slots',
  'product_equivalences', 'workflows', 'of_document_access',
  // Phase 2: GesCom
  'product_attributes', 'product_variants', 'product_serial_numbers', 'product_batches',
  'warehouse_locations', 'quality_checks', 'pick_lists', 'pick_list_lines',
  'sales_representatives', 'prospects', 'product_substitutes',
  'delivery_schedules', 'recurring_invoice_templates', 'document_templates',
  // Phase 3: Treasury
  'future_accounting_movements', 'treasury_transfers', 'credit_lines', 'investments',
  'value_date_tracking', 'treasury_recurring', 'consolidated_treasury',
  // Phase 4: Payroll & HR
  'payroll_components', 'payroll_component_rates', 'payroll_templates',
  'salary_advances', 'pay_recalls', 'dsn_declarations', 'dpae_records',
  'work_hardship', 'career_history', 'cpf_accounts', 'payroll_archives',
  'legal_watch', 'employee_documents', 'expense_reports', 'expense_report_lines',
  'interviews',
  // Phase 5: Fixed Assets
  'asset_depreciation_plans', 'asset_families', 'asset_revaluations',
  'asset_documents', 'asset_free_fields', 'asset_batch_disposals', 'asset_batch_disposal_lines',
  'asset_splits', 'asset_split_components',
  // Phase 6: Additional tenant-scoped tables
  'recurring_entries', 'regularization_entries', 'currency_revaluations',
  'analytic_plans', 'distribution_grills', 'distribution_grill_lines',
  'bank_reconciliation_rules', 'bank_statement_imports',
  'tvs_declarations', 'fiscal_backups',
])

const EXEMPT_TABLES = new Set([
  'tenants', 'tenant_users', 'users',
  'mirror_servers', 'mirror_verification_details',
])

let _tenantId: string | null | undefined = undefined

export async function setTenantId(id: string | null) {
  _tenantId = id
}

export function getCachedTenantId(): string | null {
  return _tenantId === undefined ? null : _tenantId
}

export function isTenantTable(table: string): boolean {
  return TENANT_TABLES.has(table) && !EXEMPT_TABLES.has(table)
}
