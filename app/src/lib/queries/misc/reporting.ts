// ============================================================================
// misc — reporting.ts
// Extrait de l'ancien misc.ts le 2026-10-01 ; imports recalcules ;
// aucun code metier modifie.
// ============================================================================

import { supabase, isTenantTable } from '@/lib/supabase'
import { getTenantId, ti, tud } from '../core'
import { createStockMovement } from '../stock'
import { type BankAccount, type JournalEntry, type Journal } from '@/types'

// ============ Journals Report ============
export async function getJournalsReport(startDate?: string, endDate?: string) {
  const tid = await getTenantId()
  let query = supabase
    .from('journal_entries')
    .select('*, journal_lines(*)')
    .order('date', { ascending: false })
  if (tid) query = query.eq('tenant_id', tid)
  if (startDate) query = query.gte('date', startDate)
  if (endDate) query = query.lte('date', endDate)
  const { data, error } = await query
  if (error) throw error
  return data as JournalEntry[]
}



// ============ Interconnections ============

// Generate journal entries from a pay run
// AUD-F02 : l'écriture de paie est construite par le serveur depuis les rubriques
// des bulletins (journal PAIE, idempotente, comptes par rubrique — AUD-F03)
export async function generatePayrollJournal(payRunId: string) {
  const { data, error } = await supabase.rpc('post_payroll_journal', { p_pay_run_id: payRunId })
  if (error) throw error
  return data as { success: boolean; entry_id: string; already_posted: boolean }
}

// R-04 : paiement de la paie (nets, organismes, impôt retenu, acomptes)
export async function payPayrollRun(
  payRunId: string,
  bankAccountId: string | null,
  date: string,
  scope: 'net' | 'social' | 'tax' | 'advances' | 'all' = 'all',
) {
  const { data, error } = await supabase.rpc('post_payroll_payment', {
    p_pay_run_id: payRunId,
    p_bank_account_id: bankAccountId,
    p_date: date,
    p_scope: scope,
  })
  if (error) throw error
  return data as {
    success: boolean
    entries: { scope: string; entry_id: string; amount: number }[]
    already_paid: { scope: string; entry_id: string }[]
    remaining: { scope: string; amount: number }[]
  }
}

// W5 (IMMO-01, IMMO-02, IMMO-05) : le calcul d'amortissement du front est
// SUPPRIMÉ. Il produisait un plan différent du moteur SQL (`floor(jours/365,25)`),
// partait de `Date.now()` — donc écrasait la valeur d'un exercice clos — et son
// lot avalait les échecs (`console.error`) en rendant une liste partielle comme
// un succès. Le seul moteur est `generate_depreciation_entry` (base) ; le lot
// est `generate_depreciation_entries` (base), appelé depuis
// `@/lib/queries/accounting`.

// Create stock movement linked to an invoice
export async function createInvoiceStockMovement(productId: string, type: 'in' | 'out', quantity: number, reference: string, invoiceId?: string) {
  const sm = await createStockMovement({
    product_id: productId,
    type,
    quantity,
    reference,
    date: new Date().toISOString().split('T')[0],
  } as any)

  if (invoiceId) {
    const tid = await getTenantId()
    const { error } = await tud(supabase
      .from('stock_movements')
      .update({ reference: `${reference} (Facture: ${invoiceId.slice(0, 8)})` }), 'stock_movements', tid)
      .eq('id', sm.id)
    if (error) console.error('Failed to link stock movement to invoice:', error)
  }

  return sm
}

// Impute un avoir fournisseur sur une facture : la validation de l'avoir passe
// l'écriture et recalcule le reste dû de la facture côté serveur (192) — le payé
// ne se modifie jamais directement
export async function applyPurchaseCreditToInvoice(creditNoteId: string, invoiceId: string) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase
    .from('purchase_credit_notes')
    .update({ purchase_invoice_id: invoiceId, status: 'validated' }), 'purchase_credit_notes', tid)
    .eq('id', creditNoteId)
    .select('id, status')
    .single()
  if (error) throw error
  let invQ = supabase.from('purchase_invoices').select('id, amount_due, status').eq('id', invoiceId)
  if (tid) invQ = invQ.eq('tenant_id', tid)
  const { data: invoice, error: invError } = await invQ.single()
  if (invError) throw invError
  return { invoice, creditNote: data }
}



// ============ Journals (codes journaux) ============
export async function getJournals() {
  const tid = await getTenantId()
  let q = supabase.from('journals').select('*').order('code', { ascending: true })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as Journal[]
}

export async function createJournal(journal: Omit<Journal, 'id' | 'created_at' | 'updated_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('journals').insert(ti(journal, 'journals', tid)).select().single()
  if (error) throw error
  return data as Journal
}

export async function updateJournal(id: string, updates: Partial<Journal>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('journals').update(updates), 'journals', tid).eq('id', id).select().single()
  if (error) throw error
  return data as Journal
}

export async function deleteJournal(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('journals').delete(), 'journals', tid).eq('id', id)
  if (error) throw error
}



// ============ Full Data Export ============
export const EXPORT_TABLES = [
  'company_settings', 'users', 'chart_accounts', 'customers', 'suppliers',
  'products', 'invoices', 'invoice_lines', 'quotes', 'quote_lines',
  'credit_notes', 'credit_note_lines', 'purchase_invoices', 'purchase_invoice_lines',
  'bank_accounts', 'bank_transactions', 'bank_rules',
  'journal_entries', 'journal_lines', 'journals', 'vat_returns',
  'fiscal_years', 'fiscal_periods', 'entry_templates', 'third_party_accounts',
  'analytic_sections', 'budgets', 'budget_commitments', 'standard_labels',
  'projects', 'fixed_assets', 'asset_depreciations',
  'employees', 'pay_runs', 'timesheets', 'pay_slips', 'payroll_accounting_entries',
  'leave_requests', 'contracts', 'legal_declarations',
  'stock_movements', 'stock_quantities', 'warehouses',
  'currencies', 'payment_orders', 'collection_reminders',
  'sales_orders', 'sales_order_lines', 'delivery_notes', 'delivery_note_lines',
  'customer_payments', 'purchase_orders', 'purchase_order_lines',
  'goods_receipts', 'goods_receipt_lines', 'supplier_payments',
  'purchase_credit_notes', 'purchase_credit_lines',
  'price_lists', 'price_list_lines',
  'boms', 'bom_lines', 'manufacturing_orders',
  'audit_log',
]

export interface ExportResult {
  tableName: string
  rowCount: number
  columns: string[]
  rows: Record<string, any>[]
}

export async function exportAllData(): Promise<{ tables: ExportResult[]; exportedAt: string; totalRows: number }> {
  const tid = await getTenantId()
  const tables: ExportResult[] = []
  let totalRows = 0

  for (const table of EXPORT_TABLES) {
    try {
      let q = supabase.from(table).select('*')
      if (tid && isTenantTable(table)) q = q.eq('tenant_id', tid)
      const { data, error } = await q
      if (error) {
        console.warn(`Export: skipping table ${table}:`, error.message)
        tables.push({ tableName: table, rowCount: 0, columns: [], rows: [] })
        continue
      }
      const rows = data || []
      const columns = rows.length > 0 ? Object.keys(rows[0]) : []
      tables.push({ tableName: table, rowCount: rows.length, columns, rows })
      totalRows += rows.length
    } catch (err) {
      console.warn(`Export: error on table ${table}:`, err)
      tables.push({ tableName: table, rowCount: 0, columns: [], rows: [] })
    }
  }

  return { tables, exportedAt: new Date().toISOString(), totalRows }
}

function escapeSqlValue(val: any): string {
  if (val === null || val === undefined) return 'NULL'
  if (typeof val === 'number') return String(val)
  if (typeof val === 'boolean') return val ? 'TRUE' : 'FALSE'
  if (typeof val === 'object') return `'${JSON.stringify(val).replace(/\\/g, '\\\\').replace(/'/g, "''").replaceAll('\0', '')}'`
  const str = String(val).replace(/\\/g, '\\\\').replace(/'/g, "''").replaceAll('\0', '')
  return `'${str}'`
}

function quoteIdentifier(name: string): string {
  return '"' + String(name).replace(/"/g, '""').replaceAll('\0', '') + '"'
}

export function generateSqlDump(tables: ExportResult[], exportedAt: string): string {
  const lines: string[] = []
  lines.push(`-- ============================================`)
  lines.push(`-- EXPORT COMPLET DES DONNEES`)
  lines.push(`-- Date: ${exportedAt}`)
  lines.push(`-- Source: Supabase (compta app)`)
  lines.push(`-- Total: ${tables.reduce((s, t) => s + t.rowCount, 0)} lignes`)
  lines.push(`-- ============================================`)
  lines.push('')
  lines.push('-- Metadonnees de sync')
  lines.push(`CREATE TABLE IF NOT EXISTS sync_metadata (`)
  lines.push(`  table_name text,`)
  lines.push(`  last_sync_at timestamptz,`)
  lines.push(`  row_count integer,`)
  lines.push(`  source text`)
  lines.push(`);`)
  lines.push('')

  for (const table of tables) {
    const quotedTable = quoteIdentifier(table.tableName)
    lines.push(`-- Table: ${table.tableName} (${table.rowCount} lignes)`)
    lines.push(`INSERT INTO sync_metadata (table_name, last_sync_at, row_count, source) VALUES ('${table.tableName.replace(/'/g, "''")}', '${exportedAt}', ${table.rowCount}, 'supabase');`)
    lines.push('')

    if (table.rowCount === 0) {
      lines.push(`-- ${table.tableName}: aucune donnee`)
      lines.push('')
      continue
    }

    const cols = table.columns.map(c => quoteIdentifier(c)).join(', ')
    for (const row of table.rows) {
      const values = table.columns.map(c => escapeSqlValue(row[c])).join(', ')
      lines.push(`INSERT INTO ${quotedTable} (${cols}) VALUES (${values});`)
    }
    lines.push('')
  }

  lines.push('-- ============================================')
  lines.push("-- FIN DE L'EXPORT")
  lines.push('-- ============================================')
  return lines.join('\n')
}

export function generateCsvForTable(table: ExportResult): string {
  if (table.rowCount === 0) return ''
  const headers = table.columns.join(';')
  const rows = table.rows.map(row =>
    table.columns.map(c => {
      const val = row[c]
      if (val === null || val === undefined) return ''
      if (typeof val === 'object') return `"${JSON.stringify(val).replace(/"/g, '""')}"`
      let str = String(val)
      // SECURITY: Prevent CSV formula injection
      if (/^[=+\-@]/.test(str)) str = '\t' + str
      str = str.replace(/"/g, '""')
      return str.includes(';') || str.includes('\n') || str.includes('\t') ? `"${str}"` : str
    }).join(';')
  )
  return [headers, ...rows].join('\n')
}



// ============ #26 — Export to Excel (CSV) ============
export function exportToExcel(filename: string, headers: string[], rows: (string | number)[][]) {
  const escapeCsv = (val: string | number) => {
    const s = String(val ?? '')
    if (s.includes(',') || s.includes('"') || s.includes('\n')) {
      return `"${s.replace(/"/g, '""')}"`
    }
    return s
  }
  const csv = [headers.map(escapeCsv).join(','), ...rows.map(r => r.map(escapeCsv).join(','))].join('\n')
  const blob = new Blob(['\ufeff' + csv], { type: 'text/csv;charset=utf-8;' })
  const url = URL.createObjectURL(blob)
  const link = document.createElement('a')
  link.href = url
  link.download = `${filename}.csv`
  document.body.appendChild(link)
  link.click()
  document.body.removeChild(link)
  URL.revokeObjectURL(url)
}



// ============ Statement Balance Update (#70) ============
export async function updateStatementBalance(accountId: string, statementBalance: number, statementDate: string) {
  const tid = await getTenantId()
  const { data: account, error: accErr } = await supabase.from('bank_accounts').select('calculated_balance').eq('id', accountId).single()
  if (accErr) throw accErr
  const calculated = Number(account?.calculated_balance || 0)
  const diff = statementBalance - calculated
  const { data, error } = await tud(
    supabase.from('bank_accounts').update({
      statement_balance: statementBalance,
      statement_balance_date: statementDate,
      reconciliation_diff: diff,
    }),
    'bank_accounts', tid
  ).eq('id', accountId).select().single()
  if (error) throw error
  return data as BankAccount
}
