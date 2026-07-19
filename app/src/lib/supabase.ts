import { createClient } from '@supabase/supabase-js'

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL || 'https://ndtaedcgwnaopopugiql.supabase.co'
const supabaseKey = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY || 'sb_publishable_6WZDE3wBMwc5ildtfy19Nw_pxdPnAZK'

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
