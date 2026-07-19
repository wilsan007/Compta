import { supabase, getCachedTenantId, isTenantTable } from '@/lib/supabase'
import type { Customer, Supplier, Product, Invoice, Quote, QuoteLine, CreditNote, CreditNoteLine, PurchaseCreditNote, PurchaseCreditNoteLine, PurchaseInvoice, BankAccount, BankTransaction, BankRule, JournalEntry, JournalLine, ChartAccount, User, CompanySettings, Project, VatReturn, InvoiceLine, DashboardStats, FixedAsset, Employee, PayRun, Timesheet, StockMovement, Currency, Journal, FiscalYear, FiscalPeriod, EntryTemplate, ThirdPartyAccount, AnalyticSection, Budget, BudgetCommitment, BudgetControlResult, StandardLabel, PaymentOrder, AssetDepreciation, CollectionReminder, SalesOrder, DeliveryNote, CustomerPayment, PurchaseOrder, GoodsReceipt, SupplierPayment, Warehouse, StockQuantity, PriceList, PriceListLine, BOM, BOMLine, ManufacturingOrder, PaySlip, PayrollAccountingEntry, LeaveRequest, Contract, LegalDeclaration, AuditLog } from '@/types'

// ============ Tenant Helper ============
// RLS policies filter at the DB level, but we also filter at the app level
// for performance (smaller payloads) and defense-in-depth.
let _cachedTenantId: string | null = null

export async function getTenantId(): Promise<string | null> {
  // Check global cache first (set by auth.tsx on login)
  const global = getCachedTenantId()
  if (global) { _cachedTenantId = global; return global }
  // Check local cache
  if (_cachedTenantId) return _cachedTenantId
  // Fetch from DB
  const { data: { session } } = await supabase.auth.getSession()
  if (!session) return null
  const { data } = await supabase
    .from('tenant_users')
    .select('tenant_id')
    .eq('auth_id', session.user.id)
    .eq('status', 'active')
    .single()
  if (data?.tenant_id) {
    _cachedTenantId = data.tenant_id
    return data.tenant_id
  }
  return null
}

export function clearTenantCache() {
  _cachedTenantId = null
}

// Helper: add tenant_id to an insert payload if the table is tenant-scoped
function ti<T extends Record<string, any>>(payload: T, table: string, tid: string | null): T {
  if (tid && isTenantTable(table) && !('tenant_id' in payload)) return { ...payload, tenant_id: tid }
  return payload
}

// Helper: apply tenant filter to update/delete query builders
// Usage: tud(supabase.from('invoices').update(...), 'invoices', tid).eq('id', id)
function tud<T extends { eq: (col: string, val: any) => T }>(q: T, table: string, tid: string | null): T {
  if (tid && isTenantTable(table)) return q.eq('tenant_id', tid)
  return q
}

// ============ Company Settings ============
export async function getCompanySettings() {
  const tid = await getTenantId()
  let q = supabase.from('company_settings').select('*').limit(1)
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q.single()
  if (error) throw error
  return data as CompanySettings
}

export async function updateCompanySettings(id: string, updates: Partial<CompanySettings>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('company_settings').update(updates), 'company_settings', tid).eq('id', id).select().single()
  if (error) throw error
  return data as CompanySettings
}

// ============ Users ============
export async function getUsers() {
  const { data, error } = await supabase.from('users').select('*').order('created_at', { ascending: false })
  if (error) throw error
  return data as User[]
}

// ============ Chart of Accounts ============
export async function getChartAccounts() {
  const tid = await getTenantId()
  let q = supabase.from('chart_accounts').select('*').order('code', { ascending: true })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as ChartAccount[]
}

export async function createChartAccount(account: Omit<ChartAccount, 'id'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('chart_accounts').insert({ ...account, tenant_id: tid }).select().single()
  if (error) throw error
  return data as ChartAccount
}

export async function updateChartAccount(id: string, updates: Partial<ChartAccount>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('chart_accounts').update(updates), 'chart_accounts', tid).eq('id', id).select().single()
  if (error) throw error
  return data as ChartAccount
}

export async function deleteChartAccount(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('chart_accounts').delete(), 'chart_accounts', tid).eq('id', id)
  if (error) throw error
}

// ============ Customers ============
export async function getCustomers() {
  const tid = await getTenantId()
  let q = supabase.from('customers').select('*').order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as Customer[]
}

export async function createCustomer(customer: Omit<Customer, 'id' | 'created_at' | 'updated_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('customers').insert({ ...customer, tenant_id: tid }).select().single()
  if (error) throw error
  return data as Customer
}

export async function updateCustomer(id: string, updates: Partial<Customer>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('customers').update(updates), 'customers', tid).eq('id', id).select().single()
  if (error) throw error
  return data as Customer
}

export async function deleteCustomer(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('customers').delete(), 'customers', tid).eq('id', id)
  if (error) throw error
}

// ============ Suppliers ============
export async function getSuppliers() {
  const tid = await getTenantId()
  let q = supabase.from('suppliers').select('*').order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as Supplier[]
}

export async function createSupplier(supplier: Omit<Supplier, 'id' | 'created_at' | 'updated_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('suppliers').insert({ ...supplier, tenant_id: tid }).select().single()
  if (error) throw error
  return data as Supplier
}

export async function updateSupplier(id: string, updates: Partial<Supplier>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('suppliers').update(updates), 'suppliers', tid).eq('id', id).select().single()
  if (error) throw error
  return data as Supplier
}

export async function deleteSupplier(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('suppliers').delete(), 'suppliers', tid).eq('id', id)
  if (error) throw error
}

// ============ Products ============
export async function getProducts() {
  const tid = await getTenantId()
  let q = supabase.from('products').select('*').order('name', { ascending: true })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as Product[]
}

export async function createProduct(product: Omit<Product, 'id' | 'created_at' | 'updated_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('products').insert({ ...product, tenant_id: tid }).select().single()
  if (error) throw error
  return data as Product
}

export async function updateProduct(id: string, updates: Partial<Product>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('products').update(updates), 'products', tid).eq('id', id).select().single()
  if (error) throw error
  return data as Product
}

export async function deleteProduct(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('products').delete(), 'products', tid).eq('id', id)
  if (error) throw error
}

// ============ Invoices ============
export async function getInvoices() {
  const tid = await getTenantId()
  let q = supabase
    .from('invoices')
    .select('*, invoice_lines(*)')
    .order('date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as Invoice[]
}

export async function createInvoice(invoice: Omit<Invoice, 'id' | 'created_at' | 'updated_at'> & { lines: Omit<InvoiceLine, 'id' | 'created_at'>[] }) {
  const tid = await getTenantId()
  const { lines, ...invoiceData } = invoice
  const { data: inv, error: invError } = await supabase.from('invoices').insert(ti(invoiceData, 'invoices', tid)).select().single()
  if (invError) throw invError
  
  if (lines && lines.length > 0) {
    const { error: linesError } = await supabase
      .from('invoice_lines')
      .insert(lines.map((l, i) => ti({ ...l, invoice_id: inv.id, line_order: i }, 'invoice_lines', tid)))
    if (linesError) throw linesError
  }
  return inv as Invoice
}

export async function updateInvoice(id: string, updates: Partial<Invoice>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('invoices').update(updates), 'invoices', tid).eq('id', id).select().single()
  if (error) throw error
  return data as Invoice
}

export async function deleteInvoice(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('invoices').delete(), 'invoices', tid).eq('id', id)
  if (error) throw error
}

// ============ Quotes ============
export async function getQuotes() {
  const tid = await getTenantId()
  let q = supabase
    .from('quotes')
    .select('*, quote_lines(*)')
    .order('date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as Quote[]
}

export async function createQuote(quote: Omit<Quote, 'id' | 'created_at' | 'updated_at'> & { lines: Omit<QuoteLine, 'id' | 'created_at'>[] }) {
  const tid = await getTenantId()
  const { lines, ...quoteData } = quote
  const { data: qt, error: qtError } = await supabase.from('quotes').insert(ti(quoteData, 'quotes', tid)).select().single()
  if (qtError) throw qtError
  
  if (lines && lines.length > 0) {
    const { error: linesError } = await supabase
      .from('quote_lines')
      .insert(lines.map((l, i) => ti({ ...l, quote_id: qt.id, line_order: i }, 'quote_lines', tid)))
    if (linesError) throw linesError
  }
  return qt as Quote
}

// ============ Quotes ============
export async function updateQuote(id: string, updates: Partial<Quote>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('quotes').update(updates), 'quotes', tid).eq('id', id).select().single()
  if (error) throw error
  return data as Quote
}

export async function deleteQuote(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('quotes').delete(), 'quotes', tid).eq('id', id)
  if (error) throw error
}

export async function convertQuoteToInvoice(quoteId: string) {
  const tid = await getTenantId()
  let qQ = supabase
    .from('quotes')
    .select('*, quote_lines(*)')
    .eq('id', quoteId)
  if (tid) qQ = qQ.eq('tenant_id', tid)
  const { data: quote, error: qErr } = await qQ.single()
  if (qErr) throw qErr

  const invNumber = 'FAC-' + new Date().getFullYear() + '-' + String(Math.floor(Math.random() * 999)).padStart(3, '0')
  const { data: inv, error: invErr } = await supabase.from('invoices').insert(ti({
    number: invNumber,
    customer_id: quote.customer_id,
    customer_name: quote.customer_name,
    date: new Date().toISOString().split('T')[0],
    due_date: new Date(Date.now() + 30 * 86400000).toISOString().split('T')[0],
    status: 'draft',
    subtotal: quote.subtotal,
    vat_total: quote.vat_total,
    total: quote.total,
    amount_paid: 0,
    amount_due: quote.total,
    notes: 'Converti depuis devis ' + quote.number,
  }, 'invoices', tid)).select().single()
  if (invErr) throw invErr

  if (quote.quote_lines && quote.quote_lines.length > 0) {
    const { error: lErr } = await supabase
      .from('invoice_lines')
      .insert(quote.quote_lines.map((l: any, i: number) => ti({
        invoice_id: inv.id,
        product_id: l.product_id,
        description: l.description,
        quantity: l.quantity,
        unit_price: l.unit_price,
        vat_rate: l.vat_rate,
        total: l.total,
        vat_total: l.vat_total,
        line_order: i,
      }, 'invoice_lines', tid)))
    if (lErr) throw lErr
  }

  await tud(supabase.from('quotes').update({ status: 'accepted' }), 'quotes', tid).eq('id', quoteId)
  return inv as Invoice
}

// ============ Credit Notes ============
export async function getCreditNotes() {
  const tid = await getTenantId()
  let q = supabase
    .from('credit_notes')
    .select('*, credit_note_lines(*)')
    .order('date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as CreditNote[]
}

export async function createCreditNote(cn: Omit<CreditNote, 'id' | 'created_at'> & { lines: Omit<CreditNoteLine, 'id' | 'created_at'>[] }) {
  const tid = await getTenantId()
  const { lines, ...cnData } = cn
  const { data, error } = await supabase.from('credit_notes').insert(ti(cnData, 'credit_notes', tid)).select().single()
  if (error) throw error
  if (lines && lines.length > 0) {
    const { error: lErr } = await supabase
      .from('credit_note_lines')
      .insert(lines.map((l, i) => ti({ ...l, credit_note_id: data.id, line_order: i }, 'credit_note_lines', tid)))
    if (lErr) throw lErr
  }
  return data as CreditNote
}

export async function updateCreditNote(id: string, updates: Partial<CreditNote>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('credit_notes').update(updates), 'credit_notes', tid).eq('id', id).select().single()
  if (error) throw error
  return data as CreditNote
}

export async function deleteCreditNote(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('credit_notes').delete(), 'credit_notes', tid).eq('id', id)
  if (error) throw error
}

// ============ Recurring Invoices ============
export async function getRecurringInvoices() {
  const tid = await getTenantId()
  let q = supabase
    .from('invoices')
    .select('*, invoice_lines(*)')
    .eq('recurring', true)
    .order('date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as Invoice[]
}

export async function toggleRecurringInvoice(id: string, recurring: boolean, frequency?: string) {
  const tid = await getTenantId()
  const updates: Partial<Invoice> = { recurring }
  if (frequency) updates.recurring_frequency = frequency
  const { data, error } = await tud(supabase.from('invoices').update(updates), 'invoices', tid).eq('id', id).select().single()
  if (error) throw error
  return data as Invoice
}

// ============ Purchase Invoices ============
export async function getPurchaseInvoices() {
  const tid = await getTenantId()
  let q = supabase
    .from('purchase_invoices')
    .select('*, purchase_invoice_lines(*)')
    .order('date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as PurchaseInvoice[]
}

export async function createPurchaseInvoice(invoice: Omit<PurchaseInvoice, 'id' | 'created_at' | 'updated_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('purchase_invoices').insert(ti(invoice, 'purchase_invoices', tid)).select().single()
  if (error) throw error
  return data as PurchaseInvoice
}

export async function updatePurchaseInvoice(id: string, updates: Partial<PurchaseInvoice>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('purchase_invoices').update(updates), 'purchase_invoices', tid).eq('id', id).select().single()
  if (error) throw error
  return data as PurchaseInvoice
}

// ============ Bank Accounts ============
export async function getBankAccounts() {
  const tid = await getTenantId()
  let baQ = supabase.from('bank_accounts').select('*').order('name', { ascending: true })
  if (tid) baQ = baQ.eq('tenant_id', tid)
  const { data, error } = await baQ
  if (error) throw error

  const accounts = (data || []) as BankAccount[]
  const uniqueAccounts = new Map<string, BankAccount>()

  for (const account of accounts) {
    const identity = [
      account.name,
      account.type,
      account.account_number || '',
      account.bank_name || '',
    ].map((value) => String(value).trim().toLowerCase()).join('|')

    if (!uniqueAccounts.has(identity)) uniqueAccounts.set(identity, account)
  }

  return Array.from(uniqueAccounts.values())
}

export async function createBankAccount(account: Omit<BankAccount, 'id' | 'created_at' | 'updated_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('bank_accounts').insert({ ...account, tenant_id: tid }).select().single()
  if (error) throw error
  return data as BankAccount
}

export async function updateBankAccount(id: string, updates: Partial<BankAccount>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('bank_accounts').update(updates), 'bank_accounts', tid).eq('id', id).select().single()
  if (error) throw error
  return data as BankAccount
}

// ============ Bank Transactions ============
export async function getBankTransactions(accountId?: string) {
  const tid = await getTenantId()
  let query = supabase.from('bank_transactions').select('*').order('date', { ascending: false })
  if (tid) query = query.eq('tenant_id', tid)
  if (accountId) query = query.eq('account_id', accountId)
  const { data, error } = await query
  if (error) throw error
  return data as BankTransaction[]
}

export async function createBankTransaction(txn: Omit<BankTransaction, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('bank_transactions').insert(ti(txn, 'bank_transactions', tid)).select().single()
  if (error) throw error
  return data as BankTransaction
}

export async function updateBankTransaction(id: string, updates: Partial<BankTransaction>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('bank_transactions').update(updates), 'bank_transactions', tid).eq('id', id).select().single()
  if (error) throw error
  return data as BankTransaction
}

// ============ Bank Rules ============
export async function getBankRules() {
  const tid = await getTenantId()
  let q = supabase.from('bank_rules').select('*').order('priority', { ascending: true })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as BankRule[]
}

export async function createBankRule(rule: Omit<BankRule, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('bank_rules').insert(ti(rule, 'bank_rules', tid)).select().single()
  if (error) throw error
  return data as BankRule
}

// ============ Journal Entries ============
export async function getJournalEntries() {
  const tid = await getTenantId()
  let q = supabase
    .from('journal_entries')
    .select('*, journal_lines(*)')
    .order('date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as JournalEntry[]
}

export async function createJournalEntry(entry: Omit<JournalEntry, 'id' | 'created_at' | 'updated_at'> & { lines: Omit<JournalLine, 'id' | 'created_at'>[] }) {
  const tid = await getTenantId()
  const { lines, ...entryData } = entry
  const { data: je, error: jeError } = await supabase.from('journal_entries').insert(ti(entryData, 'journal_entries', tid)).select().single()
  if (jeError) throw jeError
  
  if (lines && lines.length > 0) {
    const { error: linesError } = await supabase
      .from('journal_lines')
      .insert(lines.map((l, i) => ti({ ...l, journal_id: je.id, line_order: i }, 'journal_lines', tid)))
    if (linesError) throw linesError
  }
  return je as JournalEntry
}

export async function updateJournalEntry(id: string, updates: Partial<JournalEntry>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('journal_entries').update(updates), 'journal_entries', tid).eq('id', id).select().single()
  if (error) throw error
  return data as JournalEntry
}

export async function deleteJournalEntry(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('journal_entries').delete(), 'journal_entries', tid).eq('id', id)
  if (error) throw error
}

export async function getJournalEntry(id: string) {
  const tid = await getTenantId()
  let q = supabase
    .from('journal_entries')
    .select('*, journal_lines(*)')
    .eq('id', id)
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q.single()
  if (error) throw error
  return data as JournalEntry
}

// ============ General Ledger (mouvements par compte) ============
export async function getGeneralLedger(accountCode?: string) {
  const tid = await getTenantId()
  let query = supabase
    .from('journal_lines')
    .select(`
      id,
      account_code,
      account_name,
      debit,
      credit,
      description,
      line_order,
      created_at,
      journal_id,
      journal_entries!inner(number, date, description, reference, status)
    `)
    .order('created_at', { ascending: false })
  if (tid) query = query.eq('tenant_id', tid)
  if (accountCode) query = query.eq('account_code', accountCode)
  const { data, error } = await query
  if (error) throw error
  return data as any[]
}

// ============ Trial Balance (soldes par compte) ============
export async function getTrialBalance() {
  const tid = await getTenantId()
  let tbQ = supabase
    .from('journal_lines')
    .select('account_code, account_name, debit, credit')
  if (tid) tbQ = tbQ.eq('tenant_id', tid)
  const { data, error } = await tbQ
  if (error) throw error

  const map = new Map<string, { account_code: string; account_name: string; total_debit: number; total_credit: number }>()
  for (const line of data || []) {
    const key = line.account_code
    if (!map.has(key)) {
      map.set(key, { account_code: line.account_code, account_name: line.account_name, total_debit: 0, total_credit: 0 })
    }
    const entry = map.get(key)!
    entry.total_debit += Number(line.debit) || 0
    entry.total_credit += Number(line.credit) || 0
  }

  return Array.from(map.values()).sort((a, b) => a.account_code.localeCompare(b.account_code))
}

// ============ VAT Returns ============
export async function getVatReturns() {
  const tid = await getTenantId()
  let q = supabase.from('vat_returns').select('*').order('period_start', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as VatReturn[]
}

export async function createVatReturn(vat: Omit<VatReturn, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('vat_returns').insert(ti(vat, 'vat_returns', tid)).select().single()
  if (error) throw error
  return data as VatReturn
}

// ============ Projects ============
export async function getProjects() {
  const tid = await getTenantId()
  let q = supabase.from('projects').select('*').order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as Project[]
}

// ============ Dashboard Aggregates ============
export async function getDashboardStats(): Promise<DashboardStats> {
  const tid = await getTenantId()
  const [invoices, purchaseInvoices, bankAccounts, customers, suppliers] = await Promise.all([
    tid ? supabase.from('invoices').select('total, amount_due, status').eq('tenant_id', tid) : supabase.from('invoices').select('total, amount_due, status'),
    tid ? supabase.from('purchase_invoices').select('total, amount_due, status').eq('tenant_id', tid) : supabase.from('purchase_invoices').select('total, amount_due, status'),
    tid ? supabase.from('bank_accounts').select('balance').eq('tenant_id', tid) : supabase.from('bank_accounts').select('balance'),
    tid ? supabase.from('customers').select('balance').eq('tenant_id', tid) : supabase.from('customers').select('balance'),
    tid ? supabase.from('suppliers').select('balance').eq('tenant_id', tid) : supabase.from('suppliers').select('balance'),
  ])

  const totalRevenue = (invoices.data || []).filter((i: any) => i.status === 'paid').reduce((sum: number, i: any) => sum + Number(i.total), 0)
  const outstandingInvoice = (invoices.data || []).filter((i: any) => i.status === 'sent' || i.status === 'overdue' || i.status === 'viewed').reduce((sum: number, i: any) => sum + Number(i.amount_due), 0)
  const outstandingBills = (purchaseInvoices.data || []).filter((i: any) => i.status !== 'paid' && i.status !== 'cancelled' && i.status !== 'draft').reduce((sum: number, i: any) => sum + Number(i.amount_due), 0)
  const bankBalance = (bankAccounts.data || []).reduce((sum: number, a: any) => sum + Number(a.balance), 0)
  const totalDebtors = (customers.data || []).reduce((sum: number, c: any) => sum + Number(c.balance), 0)
  const totalCreditors = (suppliers.data || []).reduce((sum: number, s: any) => sum + Number(s.balance), 0)

  return {
    totalRevenue,
    outstandingInvoice,
    outstandingBills,
    bankBalance,
    totalDebtors,
    totalCreditors,
    invoiceCount: invoices.data?.length || 0,
    billCount: purchaseInvoices.data?.length || 0,
  }
}

export async function getDashboardChartData(): Promise<{
  monthly: Array<{ month: string; revenus: number; depenses: number }>
  cashFlow: Array<{ name: string; value: number; color: string }>
  overdueCount: number
  overdueTotal: number
}> {
  const tid = await getTenantId()
  const now = new Date()
  const yearStart = new Date(now.getFullYear(), 0, 1)
  const months = ['Jan', 'Fév', 'Mar', 'Avr', 'Mai', 'Juin', 'Juil', 'Août', 'Sep', 'Oct', 'Nov', 'Déc']

  let invQ = supabase
    .from('invoices')
    .select('date, total, status')
    .gte('date', yearStart.toISOString().split('T')[0])
    .in('status', ['paid', 'sent', 'viewed', 'overdue'])
  if (tid) invQ = invQ.eq('tenant_id', tid)
  const { data: invoices } = await invQ

  let purQ = supabase
    .from('purchase_invoices')
    .select('date, total, status')
    .gte('date', yearStart.toISOString().split('T')[0])
    .in('status', ['paid', 'received', 'overdue', 'sent'])
  if (tid) purQ = purQ.eq('tenant_id', tid)
  const { data: purchaseInvoices } = await purQ

  const monthly = months.map((m) => ({
    month: m,
    revenus: 0,
    depenses: 0,
  }))

  for (const inv of invoices || []) {
    const m = new Date(inv.date).getMonth()
    if (m >= 0 && m < 12) monthly[m].revenus += Number(inv.total)
  }
  for (const pur of purchaseInvoices || []) {
    const m = new Date(pur.date).getMonth()
    if (m >= 0 && m < 12) monthly[m].depenses += Number(pur.total)
  }

  const currentMonth = now.getMonth()
  const monthlyTrimmed = monthly.slice(0, currentMonth + 1)

  const totalRevenus = monthlyTrimmed.reduce((s, m) => s + m.revenus, 0)
  const totalDepenses = monthlyTrimmed.reduce((s, m) => s + m.depenses, 0)
  const soldeNet = totalRevenus - totalDepenses

  const cashFlow = [
    { name: 'Encaissements', value: totalRevenus, color: '#00875a' },
    { name: 'Décaissements', value: totalDepenses, color: '#de350b' },
    { name: 'Solde net', value: soldeNet, color: '#0066cc' },
  ]

  let overQ = supabase
    .from('invoices')
    .select('total, amount_due')
    .eq('status', 'overdue')
  if (tid) overQ = overQ.eq('tenant_id', tid)
  const { data: overdue } = await overQ

  const overdueCount = overdue?.length || 0
  const overdueTotal = (overdue || []).reduce((s, i) => s + Number(i.amount_due || i.total), 0)

  return { monthly: monthlyTrimmed, cashFlow, overdueCount, overdueTotal }
}

export async function getRecentActivity(): Promise<Array<{
  id: string
  type: 'invoice' | 'payment' | 'customer' | 'supplier' | 'bank'
  icon: string
  title: string
  description: string
  time: string
  color: string
}>> {
  const tid = await getTenantId()
  const activities: Array<{
    id: string
    type: 'invoice' | 'payment' | 'customer' | 'supplier' | 'bank'
    icon: string
    title: string
    description: string
    time: string
    color: string
  }> = []

  let invQ = supabase
    .from('invoices')
    .select('id, number, customer_name, total, date, status')
    .order('created_at', { ascending: false })
    .limit(5)
  if (tid) invQ = invQ.eq('tenant_id', tid)
  const { data: recentInvoices } = await invQ

  for (const inv of recentInvoices || []) {
    const statusLabel = inv.status === 'overdue' ? 'en retard' : inv.status === 'paid' ? 'payée' : 'créée'
    activities.push({
      id: `inv-${inv.id}`,
      type: 'invoice',
      icon: inv.status === 'overdue' ? 'AlertCircle' : 'FileText',
      title: `Facture ${inv.number} ${statusLabel}`,
      description: `${inv.customer_name || 'Client'} - ${Number(inv.total).toLocaleString('fr-FR')} €`,
      time: inv.date,
      color: inv.status === 'overdue' ? 'text-[var(--color-danger)]' : inv.status === 'paid' ? 'text-[var(--color-success)]' : 'text-[var(--color-primary)]',
    })
  }

  let purQ = supabase
    .from('purchase_invoices')
    .select('id, number, supplier_name, total, date')
    .order('created_at', { ascending: false })
    .limit(3)
  if (tid) purQ = purQ.eq('tenant_id', tid)
  const { data: recentPurchases } = await purQ

  for (const pur of recentPurchases || []) {
    activities.push({
      id: `pur-${pur.id}`,
      type: 'supplier',
      icon: 'Package',
      title: `Facture fournisseur ${pur.number} reçue`,
      description: `${pur.supplier_name || 'Fournisseur'} - ${Number(pur.total).toLocaleString('fr-FR')} €`,
      time: pur.date,
      color: 'text-[var(--color-warning)]',
    })
  }

  let bnkQ = supabase
    .from('bank_transactions')
    .select('id, description, amount, type, date')
    .order('date', { ascending: false })
    .limit(3)
  if (tid) bnkQ = bnkQ.eq('tenant_id', tid)
  const { data: recentBank } = await bnkQ

  for (const bnk of recentBank || []) {
    activities.push({
      id: `bnk-${bnk.id}`,
      type: 'bank',
      icon: 'Banknote',
      title: bnk.type === 'credit' ? 'Encaissement bancaire' : 'Décaissement bancaire',
      description: `${bnk.description} - ${Number(bnk.amount).toLocaleString('fr-FR')} €`,
      time: bnk.date,
      color: bnk.type === 'credit' ? 'text-[var(--color-success)]' : 'text-[var(--color-danger)]',
    })
  }

  activities.sort((a, b) => new Date(b.time).getTime() - new Date(a.time).getTime())
  return activities.slice(0, 8)
}

// ============ Purchase Credit Notes ============
export async function getPurchaseCreditNotes() {
  const tid = await getTenantId()
  let q = supabase
    .from('purchase_credit_notes')
    .select('*, purchase_credit_lines(*)')
    .order('date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as PurchaseCreditNote[]
}

export async function createPurchaseCreditNote(pcn: Omit<PurchaseCreditNote, 'id' | 'created_at'> & { lines: Omit<PurchaseCreditNoteLine, 'id' | 'created_at'>[] }) {
  const tid = await getTenantId()
  const { lines, ...pcnData } = pcn
  const { data, error } = await supabase.from('purchase_credit_notes').insert(ti(pcnData, 'purchase_credit_notes', tid)).select().single()
  if (error) throw error
  if (lines && lines.length > 0) {
    const { error: lErr } = await supabase
      .from('purchase_credit_lines')
      .insert(lines.map((l, i) => ti({ ...l, purchase_credit_id: data.id, line_order: i }, 'purchase_credit_lines', tid)))
    if (lErr) throw lErr
  }
  return data as PurchaseCreditNote
}

export async function deletePurchaseCreditNote(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('purchase_credit_notes').delete(), 'purchase_credit_notes', tid).eq('id', id)
  if (error) throw error
}

// ============ Bank Rules (CRUD) ============
export async function updateBankRule(id: string, updates: Partial<BankRule>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('bank_rules').update(updates), 'bank_rules', tid).eq('id', id).select().single()
  if (error) throw error
  return data as BankRule
}

export async function deleteBankRule(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('bank_rules').delete(), 'bank_rules', tid).eq('id', id)
  if (error) throw error
}

export async function deleteBankTransaction(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('bank_transactions').delete(), 'bank_transactions', tid).eq('id', id)
  if (error) throw error
}

// ============ Balance Sheet ============
export async function getBalanceSheet() {
  const tid = await getTenantId()
  let bsQ = supabase
    .from('journal_lines')
    .select('account_code, account_name, debit, credit')
  if (tid) bsQ = bsQ.eq('tenant_id', tid)
  const { data, error } = await bsQ
  if (error) throw error

  let caQ = supabase
    .from('chart_accounts')
    .select('code, name, type')
  if (tid) caQ = caQ.eq('tenant_id', tid)
  const { data: accounts } = await caQ

  const accountMap = new Map((accounts || []).map((a: any) => [a.code, a.type]))

  const map = new Map<string, { code: string; name: string; type: string; debit: number; credit: number }>()
  for (const line of data || []) {
    const key = line.account_code
    if (!map.has(key)) {
      map.set(key, { code: line.account_code, name: line.account_name, type: accountMap.get(line.account_code) || 'unknown', debit: 0, credit: 0 })
    }
    const entry = map.get(key)!
    entry.debit += Number(line.debit) || 0
    entry.credit += Number(line.credit) || 0
  }

  const assets = Array.from(map.values()).filter(a => a.type === 'asset')
  const liabilities = Array.from(map.values()).filter(a => a.type === 'liability')
  const equity = Array.from(map.values()).filter(a => a.type === 'equity')

  return { assets, liabilities, equity }
}

// ============ Cash Flow ============
export async function getCashFlow() {
  const tid = await getTenantId()
  let cfQ = supabase
    .from('bank_transactions')
    .select('date, type, amount, description')
    .order('date', { ascending: true })
  if (tid) cfQ = cfQ.eq('tenant_id', tid)
  const { data: bankTxns, error } = await cfQ
  if (error) throw error

  const inflow = (bankTxns || []).filter((t: any) => t.type === 'credit').reduce((s: number, t: any) => s + Number(t.amount), 0)
  const outflow = (bankTxns || []).filter((t: any) => t.type === 'debit').reduce((s: number, t: any) => s + Number(t.amount), 0)

  const byMonth = new Map<string, { inflow: number; outflow: number }>()
  for (const t of bankTxns || []) {
    const month = (t as any).date?.substring(0, 7) || 'unknown'
    if (!byMonth.has(month)) byMonth.set(month, { inflow: 0, outflow: 0 })
    const entry = byMonth.get(month)!
    if ((t as any).type === 'credit') entry.inflow += Number((t as any).amount)
    else entry.outflow += Number((t as any).amount)
  }

  return { inflow, outflow, net: inflow - outflow, byMonth: Array.from(byMonth.entries()).map(([month, v]) => ({ month, ...v })) }
}

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

// ============ VAT Returns (full CRUD) ============
export async function updateVatReturn(id: string, updates: Partial<VatReturn>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('vat_returns').update(updates), 'vat_returns', tid).eq('id', id).select().single()
  if (error) throw error
  return data as VatReturn
}

export async function deleteVatReturn(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('vat_returns').delete(), 'vat_returns', tid).eq('id', id)
  if (error) throw error
}

// ============ Projects (full CRUD) ============
export async function createProject(project: Omit<Project, 'id' | 'created_at' | 'updated_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('projects').insert({ ...project, tenant_id: tid }).select().single()
  if (error) throw error
  return data as Project
}

export async function updateProject(id: string, updates: Partial<Project>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('projects').update(updates), 'projects', tid).eq('id', id).select().single()
  if (error) throw error
  return data as Project
}

export async function deleteProject(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('projects').delete(), 'projects', tid).eq('id', id)
  if (error) throw error
}

// ============ Fixed Assets ============
export async function getFixedAssets() {
  const tid = await getTenantId()
  let q = supabase.from('fixed_assets').select('*').order('purchase_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as FixedAsset[]
}

export async function createFixedAsset(asset: Omit<FixedAsset, 'id' | 'created_at' | 'updated_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('fixed_assets').insert(ti(asset, 'fixed_assets', tid)).select().single()
  if (error) throw error
  return data as FixedAsset
}

export async function updateFixedAsset(id: string, updates: Partial<FixedAsset>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('fixed_assets').update(updates), 'fixed_assets', tid).eq('id', id).select().single()
  if (error) throw error
  return data as FixedAsset
}

export async function deleteFixedAsset(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('fixed_assets').delete(), 'fixed_assets', tid).eq('id', id)
  if (error) throw error
}

// ============ Employees ============
export async function getEmployees() {
  const tid = await getTenantId()
  let q = supabase.from('employees').select('*').order('name', { ascending: true })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as Employee[]
}

export async function createEmployee(emp: Omit<Employee, 'id' | 'created_at' | 'updated_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('employees').insert(ti(emp, 'employees', tid)).select().single()
  if (error) throw error
  return data as Employee
}

export async function updateEmployee(id: string, updates: Partial<Employee>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('employees').update(updates), 'employees', tid).eq('id', id).select().single()
  if (error) throw error
  return data as Employee
}

export async function deleteEmployee(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('employees').delete(), 'employees', tid).eq('id', id)
  if (error) throw error
}

// ============ Pay Runs ============
export async function getPayRuns() {
  const tid = await getTenantId()
  let q = supabase.from('pay_runs').select('*').order('pay_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as PayRun[]
}

export async function createPayRun(pr: Omit<PayRun, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('pay_runs').insert(ti(pr, 'pay_runs', tid)).select().single()
  if (error) throw error
  return data as PayRun
}

export async function updatePayRun(id: string, updates: Partial<PayRun>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('pay_runs').update(updates), 'pay_runs', tid).eq('id', id).select().single()
  if (error) throw error
  return data as PayRun
}

export async function deletePayRun(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('pay_runs').delete(), 'pay_runs', tid).eq('id', id)
  if (error) throw error
}

// ============ Timesheets ============
export async function getTimesheets() {
  const tid = await getTenantId()
  let q = supabase.from('timesheets').select('*, employees(name)').order('date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}

export async function createTimesheet(ts: Omit<Timesheet, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('timesheets').insert(ti(ts, 'timesheets', tid)).select().single()
  if (error) throw error
  return data as Timesheet
}

export async function updateTimesheet(id: string, updates: Partial<Timesheet>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('timesheets').update(updates), 'timesheets', tid).eq('id', id).select().single()
  if (error) throw error
  return data as Timesheet
}

export async function deleteTimesheet(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('timesheets').delete(), 'timesheets', tid).eq('id', id)
  if (error) throw error
}

// ============ Stock Movements ============
export async function getStockMovements(productId?: string, warehouseId?: string) {
  const tid = await getTenantId()
  let query = supabase.from('stock_movements').select('*, products(name, sku), warehouses(name)').order('movement_date', { ascending: false }).limit(100)
  if (tid) query = query.eq('tenant_id', tid)
  if (productId) query = query.eq('product_id', productId)
  if (warehouseId) query = query.eq('warehouse_id', warehouseId)
  const { data, error } = await query
  if (error) throw error
  return data as any[]
}

export async function createStockMovement(sm: Omit<StockMovement, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('stock_movements').insert(ti(sm, 'stock_movements', tid)).select().single()
  if (error) throw error
  if (sm.movement_type === 'in') {
    await supabase.rpc('increment_stock', { p_id: sm.product_id, qty: sm.quantity })
  } else if (sm.movement_type === 'out') {
    await supabase.rpc('decrement_stock', { p_id: sm.product_id, qty: sm.quantity })
  } else {
    await tud(supabase.from('products').update({ stock_quantity: sm.quantity }), 'products', tid).eq('id', sm.product_id)
  }
  return data as StockMovement
}

// ============ Currencies ============
export async function getCurrencies() {
  const tid = await getTenantId()
  let q = supabase.from('currencies').select('*').order('code', { ascending: true })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as Currency[]
}

export async function createCurrency(c: Omit<Currency, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('currencies').insert(ti(c, 'currencies', tid)).select().single()
  if (error) throw error
  return data as Currency
}

export async function updateCurrency(id: string, updates: Partial<Currency>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('currencies').update(updates), 'currencies', tid).eq('id', id).select().single()
  if (error) throw error
  return data as Currency
}

export async function deleteCurrency(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('currencies').delete(), 'currencies', tid).eq('id', id)
  if (error) throw error
}

// ============ Delete Purchase Invoice ============
export async function deletePurchaseInvoice(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('purchase_invoices').delete(), 'purchase_invoices', tid).eq('id', id)
  if (error) throw error
}

// ============ Delete Bank Account ============
export async function deleteBankAccount(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('bank_accounts').delete(), 'bank_accounts', tid).eq('id', id)
  if (error) throw error
}

// ============ Interconnections ============

// Generate journal entries from a pay run
export async function generatePayrollJournal(payRunId: string) {
  const tid = await getTenantId()
  let prQ = supabase.from('pay_runs').select('*').eq('id', payRunId)
  if (tid) prQ = prQ.eq('tenant_id', tid)
  const { data: payRun, error: prError } = await prQ.single()
  if (prError) throw prError

  const jeNumber = 'JE-PAY-' + payRun.number
  let jeChkQ = supabase.from('journal_entries').select('id').eq('number', jeNumber)
  if (tid) jeChkQ = jeChkQ.eq('tenant_id', tid)
  const { data: existing } = await jeChkQ.maybeSingle()
  if (existing) throw new Error('Écriture de journal déjà générée pour ce bulletin')

  const lines = [
    { account_code: '641000', account_name: 'Rémunérations du personnel', description: 'Salaires bruts ' + payRun.number, debit: Number(payRun.gross_total), credit: 0, line_order: 0 },
    { account_code: '645000', account_name: 'Charges sociales', description: 'Charges sociales ' + payRun.number, debit: Number(payRun.tax_total), credit: 0, line_order: 1 },
    { account_code: '421000', account_name: 'Personnel - Rémunérations dues', description: 'Net à payer ' + payRun.number, debit: 0, credit: Number(payRun.net_total), line_order: 2 },
    { account_code: '431000', account_name: 'Sécurité sociale - Charges', description: 'Charges sociales à payer ' + payRun.number, debit: 0, credit: Number(payRun.tax_total), line_order: 3 },
  ]

  return createJournalEntry({
    number: jeNumber,
    date: payRun.pay_date,
    description: 'Écriture de paie ' + payRun.number,
    journal_type: 'purchase',
    status: 'posted',
    total_debit: Number(payRun.gross_total) + Number(payRun.tax_total),
    total_credit: Number(payRun.net_total) + Number(payRun.tax_total),
    lines,
  } as any)
}

// Calculate and update depreciation for a fixed asset
export async function calculateDepreciation(assetId: string) {
  const tid = await getTenantId()
  let faQ = supabase.from('fixed_assets').select('*').eq('id', assetId)
  if (tid) faQ = faQ.eq('tenant_id', tid)
  const { data: asset, error } = await faQ.single()
  if (error) throw error

  const purchaseValue = Number(asset.purchase_value)
  const residualValue = Number(asset.residual_value)
  const usefulLife = Number(asset.useful_life_years)
  if (usefulLife <= 0) throw new Error('Durée de vie invalide')

  const annualDepreciation = (purchaseValue - residualValue) / usefulLife
  const yearsElapsed = Math.min(
    usefulLife,
    Math.floor((Date.now() - new Date(asset.purchase_date).getTime()) / (365.25 * 86400000))
  )
  const totalDepreciation = annualDepreciation * yearsElapsed
  const currentValue = Math.max(purchaseValue - totalDepreciation, residualValue)

  const status = currentValue <= residualValue ? 'fully_depreciated' : asset.status

  const { data, error: updateError } = await tud(supabase
    .from('fixed_assets')
    .update({ current_value: currentValue, status }), 'fixed_assets', tid)
    .eq('id', assetId)
    .select()
    .single()
  if (updateError) throw updateError
  return data as FixedAsset
}

// Calculate depreciation for all active assets
export async function calculateAllDepreciation() {
  const tid = await getTenantId()
  let q = supabase
    .from('fixed_assets')
    .select('*')
    .eq('status', 'active')
  if (tid) q = q.eq('tenant_id', tid)
  const { data: assets, error } = await q
  if (error) throw error

  const results: FixedAsset[] = []
  for (const asset of assets || []) {
    try {
      const updated = await calculateDepreciation(asset.id)
      results.push(updated)
    } catch (err) {
      console.error('Depreciation failed for asset', asset.id, err)
    }
  }
  return results
}

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

// Apply purchase credit note to purchase invoice (update amounts)
export async function applyPurchaseCreditToInvoice(creditNoteId: string, invoiceId: string) {
  const tid = await getTenantId()
  let cnQ = supabase.from('purchase_credit_notes').select('*').eq('id', creditNoteId)
  if (tid) cnQ = cnQ.eq('tenant_id', tid)
  const { data: cn, error: cnError } = await cnQ.single()
  if (cnError) throw cnError

  let invQ = supabase.from('purchase_invoices').select('*').eq('id', invoiceId)
  if (tid) invQ = invQ.eq('tenant_id', tid)
  const { data: inv, error: invError } = await invQ.single()
  if (invError) throw invError

  const creditAmount = Number(cn.total)
  const newAmountPaid = Number(inv.amount_paid) + creditAmount
  const newAmountDue = Math.max(Number(inv.amount_due) - creditAmount, 0)
  const newStatus = newAmountDue <= 0 ? 'paid' : inv.status

  const { error: invUpdateError } = await tud(supabase
    .from('purchase_invoices')
    .update({ amount_paid: newAmountPaid, amount_due: newAmountDue, status: newStatus }), 'purchase_invoices', tid)
    .eq('id', invoiceId)
  if (invUpdateError) throw invUpdateError

  const { error: cnUpdateError } = await tud(supabase
    .from('purchase_credit_notes')
    .update({ status: 'applied', purchase_invoice_id: invoiceId }), 'purchase_credit_notes', tid)
    .eq('id', creditNoteId)
  if (cnUpdateError) throw cnUpdateError

  return { invoice: { id: invoiceId, amount_due: newAmountDue, status: newStatus }, creditNote: { id: creditNoteId, status: 'applied' } }
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

// ============ Fiscal Years ============
export async function getFiscalYears() {
  const tid = await getTenantId()
  let q = supabase.from('fiscal_years').select('*').order('start_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as FiscalYear[]
}

export async function createFiscalYear(fy: Omit<FiscalYear, 'id' | 'created_at' | 'closed_at' | 'closed_by'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('fiscal_years').insert(ti(fy, 'fiscal_years', tid)).select().single()
  if (error) throw error
  return data as FiscalYear
}

export async function updateFiscalYear(id: string, updates: Partial<FiscalYear>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('fiscal_years').update(updates), 'fiscal_years', tid).eq('id', id).select().single()
  if (error) throw error
  return data as FiscalYear
}

export async function deleteFiscalYear(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('fiscal_years').delete(), 'fiscal_years', tid).eq('id', id)
  if (error) throw error
}

// ============ Fiscal Periods ============
export async function getFiscalPeriods(fiscalYearId?: string) {
  const tid = await getTenantId()
  let query = supabase.from('fiscal_periods').select('*').order('period_number', { ascending: true })
  if (tid) query = query.eq('tenant_id', tid)
  if (fiscalYearId) query = query.eq('fiscal_year_id', fiscalYearId)
  const { data, error } = await query
  if (error) throw error
  return data as FiscalPeriod[]
}

export async function createFiscalPeriodsForYear(fiscalYearId: string, startDate: string, endDate: string) {
  const tid = await getTenantId()
  const start = new Date(startDate)
  const end = new Date(endDate)
  const months: Omit<FiscalPeriod, 'id' | 'created_at'>[] = []
  const monthNames = ['Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin', 'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre']

  for (let m = 0; m < 12; m++) {
    const periodStart = new Date(start.getFullYear(), m, 1)
    const periodEnd = new Date(start.getFullYear(), m + 1, 0)
    if (periodStart > end) break
    months.push({
      fiscal_year_id: fiscalYearId,
      period_number: m + 1,
      period_label: `${monthNames[m]} ${start.getFullYear()}`,
      start_date: periodStart.toISOString().split('T')[0],
      end_date: periodEnd.toISOString().split('T')[0],
      status: 'open',
    })
  }

  const { data, error } = await supabase.from('fiscal_periods').insert(months.map(m => ti(m, 'fiscal_periods', tid))).select()
  if (error) throw error
  return data as FiscalPeriod[]
}

export async function updateFiscalPeriod(id: string, updates: Partial<FiscalPeriod>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('fiscal_periods').update(updates), 'fiscal_periods', tid).eq('id', id).select().single()
  if (error) throw error
  return data as FiscalPeriod
}

// ============ Entry Templates ============
export async function getEntryTemplates() {
  const tid = await getTenantId()
  let q = supabase.from('entry_templates').select('*').order('name', { ascending: true })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as EntryTemplate[]
}

export async function createEntryTemplate(et: Omit<EntryTemplate, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('entry_templates').insert(ti(et, 'entry_templates', tid)).select().single()
  if (error) throw error
  return data as EntryTemplate
}

export async function updateEntryTemplate(id: string, updates: Partial<EntryTemplate>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('entry_templates').update(updates), 'entry_templates', tid).eq('id', id).select().single()
  if (error) throw error
  return data as EntryTemplate
}

export async function deleteEntryTemplate(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('entry_templates').delete(), 'entry_templates', tid).eq('id', id)
  if (error) throw error
}

// ============ Third Party Accounts ============
export async function getThirdPartyAccounts(type?: string) {
  const tid = await getTenantId()
  let query = supabase.from('third_party_accounts').select('*').order('code', { ascending: true })
  if (tid) query = query.eq('tenant_id', tid)
  if (type) query = query.eq('type', type)
  const { data, error } = await query
  if (error) throw error
  return data as ThirdPartyAccount[]
}

export async function createThirdPartyAccount(tpa: Omit<ThirdPartyAccount, 'id' | 'created_at' | 'updated_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('third_party_accounts').insert(ti(tpa, 'third_party_accounts', tid)).select().single()
  if (error) throw error
  return data as ThirdPartyAccount
}

export async function updateThirdPartyAccount(id: string, updates: Partial<ThirdPartyAccount>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('third_party_accounts').update(updates), 'third_party_accounts', tid).eq('id', id).select().single()
  if (error) throw error
  return data as ThirdPartyAccount
}

export async function deleteThirdPartyAccount(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('third_party_accounts').delete(), 'third_party_accounts', tid).eq('id', id)
  if (error) throw error
}

// ============ Analytic Sections ============
export async function getAnalyticSections() {
  const tid = await getTenantId()
  let q = supabase.from('analytic_sections').select('*').order('code', { ascending: true })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as AnalyticSection[]
}

export async function createAnalyticSection(as: Omit<AnalyticSection, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('analytic_sections').insert(ti(as, 'analytic_sections', tid)).select().single()
  if (error) throw error
  return data as AnalyticSection
}

export async function updateAnalyticSection(id: string, updates: Partial<AnalyticSection>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('analytic_sections').update(updates), 'analytic_sections', tid).eq('id', id).select().single()
  if (error) throw error
  return data as AnalyticSection
}

export async function deleteAnalyticSection(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('analytic_sections').delete(), 'analytic_sections', tid).eq('id', id)
  if (error) throw error
}

// ============ Budgets ============
export async function getBudgets() {
  const tid = await getTenantId()
  let q = supabase.from('budgets').select('*').order('name', { ascending: true })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as Budget[]
}

export async function createBudget(b: Omit<Budget, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('budgets').insert(ti(b, 'budgets', tid)).select().single()
  if (error) throw error
  return data as Budget
}

export async function updateBudget(id: string, updates: Partial<Budget>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('budgets').update(updates), 'budgets', tid).eq('id', id).select().single()
  if (error) throw error
  return data as Budget
}

export async function deleteBudget(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('budgets').delete(), 'budgets', tid).eq('id', id)
  if (error) throw error
}

// ============ Standard Labels ============
export async function getStandardLabels() {
  const tid = await getTenantId()
  let q = supabase.from('standard_labels').select('*').order('label', { ascending: true })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as StandardLabel[]
}

export async function createStandardLabel(sl: Omit<StandardLabel, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('standard_labels').insert(ti(sl, 'standard_labels', tid)).select().single()
  if (error) throw error
  return data as StandardLabel
}

export async function deleteStandardLabel(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('standard_labels').delete(), 'standard_labels', tid).eq('id', id)
  if (error) throw error
}

// ============ Sprint 2: Saisie, Lettrage, Search, Closure ============

// --- Saisie: get entries by journal + period ---
export async function getEntriesByJournalPeriod(journalCode: string, fiscalPeriodId: string) {
  const tid = await getTenantId()
  let q = supabase
    .from('journal_entries')
    .select('*, journal_lines(*)')
    .eq('journal_code', journalCode)
    .eq('fiscal_period_id', fiscalPeriodId)
    .order('date', { ascending: true })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as JournalEntry[]
}

// --- Saisie: get all entries for a set of periods (for the Journal × Période grid) ---
export async function getEntriesForPeriods(periodIds: string[]) {
  if (!periodIds.length) return []
  const tid = await getTenantId()
  let q = supabase
    .from('journal_entries')
    .select('*, journal_lines(*)')
    .in('fiscal_period_id', periodIds)
    .order('date', { ascending: true })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) {
    console.warn('getEntriesForPeriods failed:', error.message)
    return []
  }
  return data as JournalEntry[]
}

// --- Saisie: compute journal balance (Ancien solde / Mouvements / Nouveau solde) ---
// Used for bank/cash journals where the counterpart account carries the running balance.
export async function getJournalPeriodBalance(
  journalCode: string,
  accountCounterpart: string | null,
  periodStart: string,
  periodEnd: string,
) {
  const empty = { ancienSolde: 0, mouvementDebit: 0, mouvementCredit: 0, nouveauSolde: 0 }
  if (!accountCounterpart) return empty
  const tid = await getTenantId()
  let jpbQ = supabase
    .from('journal_lines')
    .select('debit, credit, account_general, account_code, journal_entries!inner(journal_code, date)')
    .eq('journal_entries.journal_code', journalCode)
  if (tid) jpbQ = jpbQ.eq('tenant_id', tid)
  const { data, error } = await jpbQ
  if (error) {
    console.warn('getJournalPeriodBalance failed:', error.message)
    return empty
  }
  let ancien = 0, mvtD = 0, mvtC = 0
  for (const l of (data as any[]) || []) {
    const acct = l.account_general || l.account_code
    if (acct !== accountCounterpart) continue
    const d: string = l.journal_entries?.date
    const deb = Number(l.debit) || 0
    const cred = Number(l.credit) || 0
    if (d < periodStart) {
      ancien += deb - cred
    } else if (d >= periodStart && d <= periodEnd) {
      mvtD += deb
      mvtC += cred
    }
  }
  return { ancienSolde: ancien, mouvementDebit: mvtD, mouvementCredit: mvtC, nouveauSolde: ancien + mvtD - mvtC }
}

// --- Saisie: create entry with lines (Sage 100 format) ---
export async function createSaisieEntry(entry: {
  number: string
  date: string
  description: string
  journal_code: string
  fiscal_period_id: string
  piece_number?: string | null
  invoice_ref?: string | null
  entry_template_id?: string | null
  status: 'draft'
  status_detail?: 'open' | 'printed' | 'closed'
  total_debit: number
  total_credit: number
  lines: Array<{
    account_code: string
    account_name: string
    account_general?: string | null
    account_tiers?: string | null
    debit: number
    credit: number
    description: string
    piece_number?: string | null
    reference?: string | null
    line_order: number
    line_date?: string | null
  }>
}) {
  const tid = await getTenantId()
  const { lines, ...entryData } = entry
  const { data: je, error: jeError } = await supabase
    .from('journal_entries')
    .insert(ti({
      ...entryData,
      status_detail: entryData.status_detail || 'open',
    }, 'journal_entries', tid))
    .select()
    .single()
  if (jeError) throw jeError

  const linesData = lines.map((l) => ti({ ...l, journal_id: je.id }, 'journal_lines', tid))
  const { error: linesError } = await supabase.from('journal_lines').insert(linesData)
  if (linesError) throw linesError

  return je as JournalEntry
}

// --- Saisie: update entry status_detail (printed/closed) ---
export async function updateEntryStatusDetail(id: string, statusDetail: 'open' | 'printed' | 'closed') {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase
    .from('journal_entries')
    .update({ status_detail: statusDetail, updated_at: new Date().toISOString() }), 'journal_entries', tid)
    .eq('id', id)
    .select()
    .single()
  if (error) throw error
  return data as JournalEntry
}

// --- Saisie: get next piece number for a journal ---
export async function getNextPieceNumber(journalCode: string) {
  const tid = await getTenantId()
  let q = supabase
    .from('journal_entries')
    .select('piece_number')
    .eq('journal_code', journalCode)
    .not('piece_number', 'is', null)
    .order('piece_number', { ascending: false })
    .limit(1)
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  if (!data || data.length === 0) return `${journalCode}-0001`
  const last = data[0].piece_number
  const match = last?.match(/(\d+)$/)
  if (match) {
    const next = String(Number(match[1]) + 1).padStart(match[1].length, '0')
    return `${journalCode}-${next}`
  }
  return `${journalCode}-0001`
}

// --- Lettrage: get unlettered lines for a third party ---
export async function getUnletteredLines(accountTiers: string) {
  const tid = await getTenantId()
  let q = supabase
    .from('journal_lines')
    .select('*, journal_entries!inner(number, date, journal_code, description)')
    .eq('account_tiers', accountTiers)
    .or('lettrage_code.is.null,lettrage_code.eq.')
    .order('created_at', { ascending: true })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}

// --- Lettrage: get lettered lines for a third party ---
export async function getLetteredLines(accountTiers: string) {
  const tid = await getTenantId()
  let q = supabase
    .from('journal_lines')
    .select('*, journal_entries!inner(number, date, journal_code, description)')
    .eq('account_tiers', accountTiers)
    .not('lettrage_code', 'is', null)
    .neq('lettrage_code', '')
    .order('lettrage_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}

// --- Lettrage: apply lettrage code to multiple lines ---
export async function applyLettrage(lineIds: string[], code: string) {
  const tid = await getTenantId()
  const today = new Date().toISOString().slice(0, 10)
  const { error } = await tud(supabase
    .from('journal_lines')
    .update({ lettrage_code: code, lettrage_date: today }), 'journal_lines', tid)
    .in('id', lineIds)
  if (error) throw error
}

// --- Lettrage: remove lettrage (delettrer) ---
export async function removeLettrage(lineIds: string[]) {
  const tid = await getTenantId()
  const { error } = await tud(supabase
    .from('journal_lines')
    .update({ lettrage_code: null, lettrage_date: null }), 'journal_lines', tid)
    .in('id', lineIds)
  if (error) throw error
}

// --- Lettrage: get next lettrage code ---
export async function getNextLettrageCode() {
  const tid = await getTenantId()
  let q = supabase
    .from('journal_lines')
    .select('lettrage_code')
    .not('lettrage_code', 'is', null)
    .neq('lettrage_code', '')
    .order('lettrage_code', { ascending: false })
    .limit(1)
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  if (!data || data.length === 0) return 'A001'
  const last = data[0].lettrage_code
  const match = last?.match(/^([A-Z])(\d+)$/)
  if (match) {
    const letter = match[1]
    const num = Number(match[2]) + 1
    return `${letter}${String(num).padStart(3, '0')}`
  }
  return 'A001'
}

// --- Search: multi-criteria search on journal entries + lines ---
export async function searchEntries(criteria: {
  journalCode?: string
  dateFrom?: string
  dateTo?: string
  accountCode?: string
  accountTiers?: string
  amountMin?: number
  amountMax?: number
  description?: string
  pieceNumber?: string
}) {
  const tid = await getTenantId()
  let query = supabase
    .from('journal_entries')
    .select('*, journal_lines(*)')
    .order('date', { ascending: false })
  if (tid) query = query.eq('tenant_id', tid)

  if (criteria.journalCode) query = query.eq('journal_code', criteria.journalCode)
  if (criteria.dateFrom) query = query.gte('date', criteria.dateFrom)
  if (criteria.dateTo) query = query.lte('date', criteria.dateTo)
  if (criteria.pieceNumber) query = query.ilike('piece_number', `%${criteria.pieceNumber}%`)
  if (criteria.description) query = query.ilike('description', `%${criteria.description}%`)

  const { data, error } = await query.limit(200)
  if (error) throw error

  let results = data as JournalEntry[]

  // Filter by line-level criteria in JS (Supabase can't filter on nested array easily)
  if (criteria.accountCode || criteria.accountTiers || criteria.amountMin !== undefined || criteria.amountMax !== undefined) {
    results = results.filter((e) =>
      e.journal_lines?.some((l) => {
        if (criteria.accountCode && l.account_code !== criteria.accountCode && l.account_general !== criteria.accountCode) return false
        if (criteria.accountTiers && l.account_tiers !== criteria.accountTiers) return false
        if (criteria.amountMin !== undefined && (Number(l.debit) < criteria.amountMin && Number(l.credit) < criteria.amountMin)) return false
        if (criteria.amountMax !== undefined && (Number(l.debit) > criteria.amountMax && Number(l.credit) > criteria.amountMax)) return false
        return true
      })
    )
  }

  return results
}

// --- Closure: get journal × period status matrix ---
export async function getJournalPeriodStatus(fiscalYearId: string) {
  const tid = await getTenantId()
  let jQ = supabase.from('journals').select('*').eq('status', 'active').order('code', { ascending: true })
  if (tid) jQ = jQ.eq('tenant_id', tid)
  const { data: journals, error: jError } = await jQ
  if (jError) throw jError

  let pQ = supabase.from('fiscal_periods').select('*').eq('fiscal_year_id', fiscalYearId).order('period_number', { ascending: true })
  if (tid) pQ = pQ.eq('tenant_id', tid)
  const { data: periods, error: pError } = await pQ
  if (pError) throw pError

  let eQ = supabase.from('journal_entries').select('id, journal_code, fiscal_period_id, status_detail, total_debit, total_credit').in('fiscal_period_id', periods.map((p) => p.id))
  if (tid) eQ = eQ.eq('tenant_id', tid)
  const { data: entries, error: eError } = await eQ
  if (eError) throw eError

  return { journals: journals || [], periods: periods || [], entries: entries || [] }
}

// --- Closure: close a period for a journal (set all entries to closed) ---
export async function closeJournalPeriod(journalCode: string, fiscalPeriodId: string) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase
    .from('journal_entries')
    .update({ status_detail: 'closed', updated_at: new Date().toISOString() }), 'journal_entries', tid)
    .eq('journal_code', journalCode)
    .eq('fiscal_period_id', fiscalPeriodId)
    .neq('status_detail', 'closed')
    .select('id')
  if (error) throw error
  return data
}

// --- Closure: reopen a period for a journal ---
export async function reopenJournalPeriod(journalCode: string, fiscalPeriodId: string) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase
    .from('journal_entries')
    .update({ status_detail: 'open', updated_at: new Date().toISOString() }), 'journal_entries', tid)
    .eq('journal_code', journalCode)
    .eq('fiscal_period_id', fiscalPeriodId)
    .eq('status_detail', 'closed')
    .select('id')
  if (error) throw error
  return data
}

// --- Closure: close a fiscal period ---
export async function closeFiscalPeriod(periodId: string) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase
    .from('fiscal_periods')
    .update({ status: 'closed' }), 'fiscal_periods', tid)
    .eq('id', periodId)
    .select()
    .single()
  if (error) throw error
  return data as FiscalPeriod
}

// --- Closure: reopen a fiscal period ---
export async function reopenFiscalPeriod(periodId: string) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase
    .from('fiscal_periods')
    .update({ status: 'open' }), 'fiscal_periods', tid)
    .eq('id', periodId)
    .select()
    .single()
  if (error) throw error
  return data as FiscalPeriod
}

// ============ Sprint 3: États & Clôture ============

// --- Brouillard: entries not printed (status_detail = 'open' or null) ---
export async function getBrouillard() {
  const tid = await getTenantId()
  let q = supabase
    .from('journal_entries')
    .select('*, journal_lines(*)')
    .or('status_detail.eq.open,status_detail.is.null')
    .order('date', { ascending: true })
    .order('number', { ascending: true })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as JournalEntry[]
}

// --- Aged Balance: unlettered lines by third party with aging ---
export async function getAgedBalance(typeFilter?: string, refDate?: string) {
  const tid = await getTenantId()
  let abQ = supabase
    .from('journal_lines')
    .select('*, journal_entries!inner(date, journal_code, number, piece_number)')
    .not('account_tiers', 'is', null)
    .neq('account_tiers', '')
    .or('lettrage_code.is.null,lettrage_code.eq.')
  if (tid) abQ = abQ.eq('tenant_id', tid)
  const { data: lines, error } = await abQ
  if (error) throw error

  let tpQ = supabase.from('third_party_accounts').select('*')
  if (tid) tpQ = tpQ.eq('tenant_id', tid)
  const { data: tiers, error: tError } = await tpQ
  if (tError) throw tError

  const tiersMap = new Map((tiers || []).map((t) => [t.code, t]))
  const referenceDate = refDate ? new Date(refDate) : new Date()

  const byTiers: Record<string, {
    code: string; name: string; type: string; total: number
    bucket0_30: number; bucket31_60: number; bucket61_90: number; bucket90p: number
  }> = {}

  for (const line of lines || []) {
    const code = line.account_tiers
    if (!code) continue
    const tp = tiersMap.get(code)
    if (typeFilter && tp?.type !== typeFilter) continue

    if (!byTiers[code]) {
      byTiers[code] = {
        code, name: tp?.name || code, type: tp?.type || 'other',
        total: 0, bucket0_30: 0, bucket31_60: 0, bucket61_90: 0, bucket90p: 0,
      }
    }

    const amount = Number(line.debit) - Number(line.credit)
    if (Math.abs(amount) < 0.01) continue
    byTiers[code].total += amount

    const entryDate = new Date(line.journal_entries?.date || line.created_at)
    const daysDiff = Math.floor((referenceDate.getTime() - entryDate.getTime()) / (1000 * 60 * 60 * 24))

    if (daysDiff <= 30) byTiers[code].bucket0_30 += amount
    else if (daysDiff <= 60) byTiers[code].bucket31_60 += amount
    else if (daysDiff <= 90) byTiers[code].bucket61_90 += amount
    else byTiers[code].bucket90p += amount
  }

  return Object.values(byTiers).filter((b) => Math.abs(b.total) > 0.01).sort((a, b) => b.total - a.total)
}

// --- Echeancier: upcoming payments from invoices + purchase invoices ---
export async function getEcheancier(typeFilter?: string) {
  const results: Array<{
    type: 'customer' | 'supplier'; number: string; date: string; due_date: string
    amount: number; paid: number; remaining: number; third_party_name: string; days_overdue: number
  }> = []

  const tid = await getTenantId()
  if (!typeFilter || typeFilter === 'customer') {
    let ecQ = supabase
      .from('invoices')
      .select('id, number, issue_date, due_date, total, customer_name, status')
      .neq('status', 'paid')
      .neq('status', 'cancelled')
      .order('due_date', { ascending: true })
    if (tid) ecQ = ecQ.eq('tenant_id', tid)
    const { data: invoices, error } = await ecQ
    if (!error && invoices) {
      for (const inv of invoices) {
        const remaining = Number(inv.total) || 0
        if (remaining <= 0) continue
        const due = new Date(inv.due_date)
        const daysOverdue = Math.floor((Date.now() - due.getTime()) / (1000 * 60 * 60 * 24))
        results.push({
          type: 'customer', number: inv.number, date: inv.issue_date, due_date: inv.due_date,
          amount: Number(inv.total) || 0, paid: 0, remaining,
          third_party_name: inv.customer_name || '—', days_overdue: daysOverdue > 0 ? daysOverdue : 0,
        })
      }
    }
  }

  if (!typeFilter || typeFilter === 'supplier') {
    let esQ = supabase
      .from('purchase_invoices')
      .select('id, invoice_number, invoice_date, due_date, total, supplier_name, status')
      .neq('status', 'paid')
      .neq('status', 'cancelled')
      .order('due_date', { ascending: true })
    if (tid) esQ = esQ.eq('tenant_id', tid)
    const { data: pinvoices, error } = await esQ
    if (!error && pinvoices) {
      for (const inv of pinvoices) {
        const remaining = Number(inv.total) || 0
        if (remaining <= 0) continue
        const due = new Date(inv.due_date)
        const daysOverdue = Math.floor((Date.now() - due.getTime()) / (1000 * 60 * 60 * 24))
        results.push({
          type: 'supplier', number: inv.invoice_number, date: inv.invoice_date, due_date: inv.due_date,
          amount: Number(inv.total) || 0, paid: 0, remaining,
          third_party_name: inv.supplier_name || '—', days_overdue: daysOverdue > 0 ? daysOverdue : 0,
        })
      }
    }
  }

  return results.sort((a, b) => new Date(a.due_date).getTime() - new Date(b.due_date).getTime())
}

// --- Grand Livre Tiers: journal_lines by account_tiers ---
export async function getGrandLivreTiers(accountTiers: string, dateFrom?: string, dateTo?: string) {
  const tid = await getTenantId()
  let query = supabase
    .from('journal_lines')
    .select('*, journal_entries!inner(number, date, journal_code, description, piece_number)')
    .eq('account_tiers', accountTiers)
    .order('created_at', { ascending: true })
  if (tid) query = query.eq('tenant_id', tid)

  if (dateFrom) query = query.gte('journal_entries.date', dateFrom)
  if (dateTo) query = query.lte('journal_entries.date', dateTo)

  const { data, error } = await query
  if (error) throw error
  return data as any[]
}

// --- FEC Export: all entries + lines for a fiscal year ---
export async function getFECData(fiscalYearId: string) {
  const tid = await getTenantId()
  let fpQ = supabase.from('fiscal_periods').select('id').eq('fiscal_year_id', fiscalYearId)
  if (tid) fpQ = fpQ.eq('tenant_id', tid)
  const { data: periods, error: pError } = await fpQ
  if (pError) throw pError

  const periodIds = (periods || []).map((p) => p.id)
  if (periodIds.length === 0) return []

  let feQ = supabase.from('journal_entries').select('*, journal_lines(*)').in('fiscal_period_id', periodIds).order('date', { ascending: true })
  if (tid) feQ = feQ.eq('tenant_id', tid)
  const { data: entries, error } = await feQ
  if (error) throw error

  return entries as JournalEntry[]
}

// --- SIG: balances for class 6/7 accounts ---
export async function getSIGData(fiscalYearId?: string) {
  const tid = await getTenantId()
  let query = supabase
    .from('journal_lines')
    .select('account_code, account_general, debit, credit, journal_entries!inner(fiscal_period_id)')
  if (tid) query = query.eq('tenant_id', tid)

  if (fiscalYearId) {
    const { data: periods } = await supabase
      .from('fiscal_periods')
      .select('id')
      .eq('fiscal_year_id', fiscalYearId)
    if (periods && periods.length > 0) {
      query = query.in('journal_entries.fiscal_period_id', periods.map((p) => p.id))
    }
  }

  const { data, error } = await query
  if (error) throw error

  const accountBalances: Record<string, { debit: number; credit: number }> = {}

  for (const line of data || []) {
    const code = line.account_general || line.account_code || ''
    if (!code.match(/^[67]/)) continue
    if (!accountBalances[code]) accountBalances[code] = { debit: 0, credit: 0 }
    accountBalances[code].debit += Number(line.debit) || 0
    accountBalances[code].credit += Number(line.credit) || 0
  }

  let caQ2 = supabase.from('chart_accounts').select('code, name').or('code.like.6%,code.like.7%')
  if (tid) caQ2 = caQ2.eq('tenant_id', tid)
  const { data: accounts } = await caQ2

  const accountMap = new Map((accounts || []).map((a) => [a.code, a.name]))

  return Object.entries(accountBalances).map(([code, bal]) => ({
    code, name: accountMap.get(code) || '—',
    debit: bal.debit, credit: bal.credit, solde: bal.debit - bal.credit,
  })).sort((a, b) => a.code.localeCompare(b.code))
}

// --- Analytic Balance: journal_lines by analytic_section_id ---
export async function getAnalyticBalance() {
  const tid = await getTenantId()
  let abQ2 = supabase
    .from('journal_lines')
    .select('analytic_section_id, analytic_amount, debit, credit, account_code, account_general')
    .not('analytic_section_id', 'is', null)
  if (tid) abQ2 = abQ2.eq('tenant_id', tid)
  const { data: lines, error } = await abQ2
  if (error) throw error

  let asQ = supabase.from('analytic_sections').select('*')
  if (tid) asQ = asQ.eq('tenant_id', tid)
  const { data: sections, error: sError } = await asQ
  if (sError) throw sError

  const sectionMap = new Map((sections || []).map((s) => [s.id, s]))

  const bySection: Record<string, {
    sectionId: string; sectionCode: string; sectionName: string
    totalDebit: number; totalCredit: number; totalAnalytic: number
  }> = {}

  for (const line of lines || []) {
    const sid = line.analytic_section_id
    if (!sid) continue
    if (!bySection[sid]) {
      const sec = sectionMap.get(sid)
      bySection[sid] = {
        sectionId: sid, sectionCode: sec?.code || '—', sectionName: sec?.name || '—',
        totalDebit: 0, totalCredit: 0, totalAnalytic: 0,
      }
    }
    bySection[sid].totalDebit += Number(line.debit) || 0
    bySection[sid].totalCredit += Number(line.credit) || 0
    bySection[sid].totalAnalytic += Number(line.analytic_amount) || 0
  }

  return Object.values(bySection).sort((a, b) => a.sectionCode.localeCompare(b.sectionCode))
}

// --- Fiscal Year Closure: close year + generate opening entries ---
export async function closeFiscalYear(fiscalYearId: string, newFiscalYearId: string) {
  const tid = await getTenantId()
  let fyQ = supabase.from('fiscal_years').select('*').eq('id', fiscalYearId)
  if (tid) fyQ = fyQ.eq('tenant_id', tid)
  const { data: year, error: yError } = await fyQ.single()
  if (yError) throw yError

  let fpQ2 = supabase.from('fiscal_periods').select('id').eq('fiscal_year_id', fiscalYearId)
  if (tid) fpQ2 = fpQ2.eq('tenant_id', tid)
  const { data: periods } = await fpQ2
  if (!periods) return

  const periodIds = periods.map((p) => p.id)

  let jlQ3 = supabase
    .from('journal_lines')
    .select('account_code, account_general, debit, credit')
    .in('journal_entries.fiscal_period_id', periodIds)
  if (tid) jlQ3 = jlQ3.eq('tenant_id', tid)
  const { data: lines, error: lError } = await jlQ3
  if (lError) throw lError

  const accountBalances: Record<string, number> = {}
  for (const line of lines || []) {
    const code = line.account_general || line.account_code || ''
    if (!code) continue
    if (!accountBalances[code]) accountBalances[code] = 0
    accountBalances[code] += Number(line.debit) - Number(line.credit)
  }

  let npQ = supabase.from('fiscal_periods').select('id').eq('fiscal_year_id', newFiscalYearId).order('period_number', { ascending: true }).limit(1)
  if (tid) npQ = npQ.eq('tenant_id', tid)
  const { data: newPeriods } = await npQ

  const newPeriodId = newPeriods?.[0]?.id
  if (!newPeriodId) throw new Error('Nouvel exercice sans période')

  const openingLines: Array<any> = []
  let order = 0
  for (const [code, balance] of Object.entries(accountBalances)) {
    if (Math.abs(balance) < 0.01) continue
    if (code.match(/^[67]/)) continue
    const { data: acc } = await supabase
      .from('chart_accounts')
      .select('name')
      .eq('code', code)
      .single()
    openingLines.push({
      account_code: code,
      account_name: acc?.name || code,
      account_general: code,
      debit: balance > 0 ? balance : 0,
      credit: balance < 0 ? Math.abs(balance) : 0,
      description: `Report à nouveau — ${code}`,
      line_order: order++,
      line_date: new Date().toISOString().slice(0, 10),
    })
  }

  if (openingLines.length > 0) {
    const totalD = openingLines.reduce((s, l) => s + l.debit, 0)
    const totalC = openingLines.reduce((s, l) => s + l.credit, 0)
    await createSaisieEntry({
      number: `OUV-${year.code}`,
      date: new Date().toISOString().slice(0, 10),
      description: `Report à nouveau — ${year.code}`,
      journal_code: 'OD',
      fiscal_period_id: newPeriodId,
      status: 'draft',
      status_detail: 'open',
      total_debit: totalD,
      total_credit: totalC,
      lines: openingLines,
    })
  }

  const { error: closeError } = await tud(supabase
    .from('fiscal_years')
    .update({ status: 'closed', closed_at: new Date().toISOString() }), 'fiscal_years', tid)
    .eq('id', fiscalYearId)
  if (closeError) throw closeError

  return { openingLinesCount: openingLines.length }
}

// --- VAT auto-calc from journal lines (accounts 4456x / 4457x) ---
export async function calcVatFromEntries(dateFrom: string, dateTo: string) {
  const tid = await getTenantId()
  let q = supabase
    .from('journal_lines')
    .select('account_code, account_general, debit, credit, journal_entries!inner(date)')
    .gte('journal_entries.date', dateFrom)
    .lte('journal_entries.date', dateTo)
  if (tid) q = q.eq('tenant_id', tid)
  const { data: lines, error } = await q
  if (error) throw error

  let outputVat = 0
  let inputVat = 0
  let totalSales = 0
  let totalPurchases = 0

  for (const line of lines || []) {
    const code = line.account_general || line.account_code || ''
    const debit = Number(line.debit) || 0
    const credit = Number(line.credit) || 0

    if (code.startsWith('4457')) outputVat += credit - debit
    if (code.startsWith('4456')) inputVat += debit - credit
    if (code.startsWith('70')) totalSales += credit - debit
    if (code.startsWith('60')) totalPurchases += debit - credit
  }

  return {
    outputVat: Math.max(0, outputVat),
    inputVat: Math.max(0, inputVat),
    netVat: outputVat - inputVat,
    totalSales: Math.max(0, totalSales),
    totalPurchases: Math.max(0, totalPurchases),
  }
}

// --- General Ledger with filters (journal, period, date range) ---
export async function getGeneralLedgerFiltered(accountCode: string, filters?: {
  journalCode?: string
  dateFrom?: string
  dateTo?: string
}) {
  const tid = await getTenantId()
  let query = supabase
    .from('journal_lines')
    .select('*, journal_entries!inner(number, date, journal_code, description, reference, piece_number)')
    .or(`account_code.eq.${accountCode},account_general.eq.${accountCode}`)
    .order('created_at', { ascending: true })
  if (tid) query = query.eq('tenant_id', tid)

  if (filters?.journalCode) query = query.eq('journal_entries.journal_code', filters.journalCode)
  if (filters?.dateFrom) query = query.gte('journal_entries.date', filters.dateFrom)
  if (filters?.dateTo) query = query.lte('journal_entries.date', filters.dateTo)

  const { data, error } = await query
  if (error) throw error
  return data as any[]
}

// --- Trial Balance with period filter ---
export async function getTrialBalanceFiltered(filters?: {
  dateFrom?: string
  dateTo?: string
  journalCode?: string
}) {
  const tid = await getTenantId()
  let query = supabase
    .from('journal_lines')
    .select('account_code, account_general, debit, credit, journal_entries!inner(date, journal_code)')
  if (tid) query = query.eq('tenant_id', tid)

  if (filters?.dateFrom) query = query.gte('journal_entries.date', filters.dateFrom)
  if (filters?.dateTo) query = query.lte('journal_entries.date', filters.dateTo)
  if (filters?.journalCode) query = query.eq('journal_entries.journal_code', filters.journalCode)

  const { data, error } = await query
  if (error) throw error

  const balances: Record<string, { account_code: string; total_debit: number; total_credit: number }> = {}

  for (const line of data || []) {
    const code = line.account_general || line.account_code || ''
    if (!code) continue
    if (!balances[code]) balances[code] = { account_code: code, total_debit: 0, total_credit: 0 }
    balances[code].total_debit += Number(line.debit) || 0
    balances[code].total_credit += Number(line.credit) || 0
  }

  return Object.values(balances).sort((a, b) => a.account_code.localeCompare(b.account_code))
}

// ============ Sprint 5: Payment Orders ============
export async function getPaymentOrders(status?: string) {
  const tid = await getTenantId()
  let query = supabase.from('payment_orders').select('*').order('payment_date', { ascending: false })
  if (tid) query = query.eq('tenant_id', tid)
  if (status) query = query.eq('status', status)
  const { data, error } = await query
  if (error) throw error
  return data as PaymentOrder[]
}

export async function createPaymentOrder(po: Omit<PaymentOrder, 'id' | 'created_at' | 'updated_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('payment_orders').insert(ti(po, 'payment_orders', tid)).select().single()
  if (error) throw error
  return data as PaymentOrder
}

export async function updatePaymentOrder(id: string, updates: Partial<PaymentOrder>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('payment_orders').update({ ...updates, updated_at: new Date().toISOString() }), 'payment_orders', tid).eq('id', id).select().single()
  if (error) throw error
  return data as PaymentOrder
}

export async function deletePaymentOrder(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('payment_orders').delete(), 'payment_orders', tid).eq('id', id)
  if (error) throw error
}

// ============ Sprint 5: Asset Depreciations ============
export async function getAssetDepreciations(assetId?: string) {
  const tid = await getTenantId()
  let query = supabase.from('asset_depreciations').select('*').order('created_at', { ascending: false })
  if (tid) query = query.eq('tenant_id', tid)
  if (assetId) query = query.eq('asset_id', assetId)
  const { data, error } = await query
  if (error) throw error
  return data as AssetDepreciation[]
}

export async function createAssetDepreciation(ad: Omit<AssetDepreciation, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('asset_depreciations').insert(ti(ad, 'asset_depreciations', tid)).select().single()
  if (error) throw error
  return data as AssetDepreciation
}

export async function deleteAssetDepreciation(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('asset_depreciations').delete(), 'asset_depreciations', tid).eq('id', id)
  if (error) throw error
}

export async function disposeFixedAsset(assetId: string, disposalValue: number, disposalDate: string) {
  const tid = await getTenantId()
  let faQ = supabase.from('fixed_assets').select('*').eq('id', assetId)
  if (tid) faQ = faQ.eq('tenant_id', tid)
  const { data: asset, error: assetErr } = await faQ.single()
  if (assetErr) throw assetErr

  const { error: updateErr } = await tud(supabase
    .from('fixed_assets')
    .update({ status: 'disposed', current_value: 0, updated_at: new Date().toISOString() }), 'fixed_assets', tid)
    .eq('id', assetId)
  if (updateErr) throw updateErr

  const { error: depErr } = await supabase.from('asset_depreciations').insert(ti({
    asset_id: assetId,
    depreciation_type: 'disposal',
    period: new Date(disposalDate).getMonth() + 1,
    amount: Number(asset.current_value) - disposalValue,
    cumulative_amount: Number(asset.purchase_value) - disposalValue,
    net_book_value: 0,
  }, 'asset_depreciations', tid))
  if (depErr) throw depErr

  return { asset, disposalValue }
}

// ============ Sprint 5: Collection Reminders ============
export async function getCollectionReminders(status?: string) {
  const tid = await getTenantId()
  let query = supabase.from('collection_reminders').select('*').order('reminder_date', { ascending: false })
  if (tid) query = query.eq('tenant_id', tid)
  if (status) query = query.eq('status', status)
  const { data, error } = await query
  if (error) throw error
  return data as CollectionReminder[]
}

export async function createCollectionReminder(cr: Omit<CollectionReminder, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('collection_reminders').insert(ti(cr, 'collection_reminders', tid)).select().single()
  if (error) throw error
  return data as CollectionReminder
}

export async function updateCollectionReminder(id: string, updates: Partial<CollectionReminder>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('collection_reminders').update(updates), 'collection_reminders', tid).eq('id', id).select().single()
  if (error) throw error
  return data as CollectionReminder
}

export async function deleteCollectionReminder(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('collection_reminders').delete(), 'collection_reminders', tid).eq('id', id)
  if (error) throw error
}

// ============ Sprint 5: Treasury Dashboard ============
export async function getTreasuryDashboard() {
  const tid = await getTenantId()
  let accQ = supabase.from('bank_accounts').select('*').order('name')
  if (tid) accQ = accQ.eq('tenant_id', tid)
  const { data: accounts, error: accErr } = await accQ
  if (accErr) throw accErr

  const totalBalance = (accounts || []).reduce((s, a) => s + Number(a.balance), 0)

  const today = new Date()
  const in30 = new Date(today)
  in30.setDate(in30.getDate() + 30)
  const in60 = new Date(today)
  in60.setDate(in60.getDate() + 60)
  const in90 = new Date(today)
  in90.setDate(in90.getDate() + 90)

  let inQ = supabase
    .from('invoices')
    .select('total, due_date, status')
    .in('status', ['sent', 'overdue'])
    .gte('due_date', today.toISOString().split('T')[0])
    .lte('due_date', in90.toISOString().split('T')[0])
  if (tid) inQ = inQ.eq('tenant_id', tid)
  const { data: incoming } = await inQ

  let outQ = supabase
    .from('purchase_invoices')
    .select('total, due_date, status')
    .in('status', ['received', 'overdue'])
    .gte('due_date', today.toISOString().split('T')[0])
    .lte('due_date', in90.toISOString().split('T')[0])
  if (tid) outQ = outQ.eq('tenant_id', tid)
  const { data: outgoing } = await outQ

  const forecastBuckets = [
    { label: '0-30j', incoming: 0, outgoing: 0 },
    { label: '31-60j', incoming: 0, outgoing: 0 },
    { label: '61-90j', incoming: 0, outgoing: 0 },
  ]

  for (const inv of incoming || []) {
    const due = new Date(inv.due_date)
    const days = Math.floor((due.getTime() - today.getTime()) / 86400000)
    if (days <= 30) forecastBuckets[0].incoming += Number(inv.total)
    else if (days <= 60) forecastBuckets[1].incoming += Number(inv.total)
    else forecastBuckets[2].incoming += Number(inv.total)
  }

  for (const inv of outgoing || []) {
    const due = new Date(inv.due_date)
    const days = Math.floor((due.getTime() - today.getTime()) / 86400000)
    if (days <= 30) forecastBuckets[0].outgoing += Number(inv.total)
    else if (days <= 60) forecastBuckets[1].outgoing += Number(inv.total)
    else forecastBuckets[2].outgoing += Number(inv.total)
  }

  let ppQ = supabase.from('payment_orders').select('*').in('status', ['draft', 'approved'])
  if (tid) ppQ = ppQ.eq('tenant_id', tid)
  const { data: pendingPayments } = await ppQ

  return {
    accounts: accounts || [],
    totalBalance,
    forecastBuckets,
    pendingPayments: pendingPayments || [],
  }
}

// ============ Sprint 5: Treasury Forecast ============
export async function getTreasuryForecast(days: number = 90) {
  const tid = await getTenantId()
  const today = new Date()
  const end = new Date(today)
  end.setDate(end.getDate() + days)

  let invQ = supabase
    .from('invoices')
    .select('number, total, due_date, customer_id, status')
    .in('status', ['sent', 'overdue'])
    .gte('due_date', today.toISOString().split('T')[0])
    .lte('due_date', end.toISOString().split('T')[0])
    .order('due_date')
  if (tid) invQ = invQ.eq('tenant_id', tid)
  const { data: invoices } = await invQ

  let purQ = supabase
    .from('purchase_invoices')
    .select('number, total, due_date, supplier_id, status')
    .in('status', ['received', 'overdue'])
    .gte('due_date', today.toISOString().split('T')[0])
    .lte('due_date', end.toISOString().split('T')[0])
    .order('due_date')
  if (tid) purQ = purQ.eq('tenant_id', tid)
  const { data: purchaseInvoices } = await purQ

  let baQ = supabase.from('bank_accounts').select('balance')
  if (tid) baQ = baQ.eq('tenant_id', tid)
  const { data: bankAccounts } = await baQ
  const currentBalance = (bankAccounts || []).reduce((s, a) => s + Number(a.balance), 0)

  const events: Array<{ date: string; type: 'in' | 'out'; amount: number; reference: string }> = []
  for (const inv of invoices || []) {
    events.push({ date: inv.due_date, type: 'in', amount: Number(inv.total), reference: inv.number })
  }
  for (const inv of purchaseInvoices || []) {
    events.push({ date: inv.due_date, type: 'out', amount: Number(inv.total), reference: inv.number })
  }

  events.sort((a, b) => a.date.localeCompare(b.date))

  let runningBalance = currentBalance
  const timeline = events.map((e) => {
    runningBalance += e.type === 'in' ? e.amount : -e.amount
    return { ...e, runningBalance }
  })

  return { currentBalance, timeline, totalIncoming: events.filter((e) => e.type === 'in').reduce((s, e) => s + e.amount, 0), totalOutgoing: events.filter((e) => e.type === 'out').reduce((s, e) => s + e.amount, 0) }
}

// ============ Sprint 5: Collection Dashboard ============
export async function getCollectionDashboard() {
  const tid = await getTenantId()
  let oiQ = supabase
    .from('invoices')
    .select('id, number, customer_id, total, due_date, status, customers(name)')
    .in('status', ['sent', 'overdue'])
    .order('due_date', { ascending: true })
  if (tid) oiQ = oiQ.eq('tenant_id', tid)
  const { data: overdueInvoices, error } = await oiQ
  if (error) throw error

  const today = new Date()
  const enriched = (overdueInvoices || []).map((inv: any) => {
    const due = new Date(inv.due_date)
    const daysOverdue = Math.max(0, Math.floor((today.getTime() - due.getTime()) / 86400000))
    return { ...inv, daysOverdue, customer_name: inv.customers?.name || '—' }
  })

  const totalOverdue = enriched.filter((i) => i.daysOverdue > 0).reduce((s, i) => s + Number(i.total), 0)
  const totalDue = enriched.reduce((s, i) => s + Number(i.total), 0)

  let crQ = supabase
    .from('collection_reminders')
    .select('*')
    .order('reminder_date', { ascending: false })
    .limit(20)
  if (tid) crQ = crQ.eq('tenant_id', tid)
  const { data: reminders } = await crQ

  return {
    overdueInvoices: enriched,
    totalOverdue,
    totalDue,
    reminders: reminders || [],
  }
}

// ============ Sprint 6: Sales Orders ============
export async function getSalesOrders(status?: string) {
  const tid = await getTenantId()
  let q = supabase.from('sales_orders').select('*').order('order_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (status) q = q.eq('status', status)
  const { data, error } = await q
  if (error) throw error
  return data as SalesOrder[]
}

export async function createSalesOrder(so: Omit<SalesOrder, 'id' | 'created_at' | 'updated_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('sales_orders').insert(ti(so, 'sales_orders', tid)).select().single()
  if (error) throw error
  return data as SalesOrder
}

export async function updateSalesOrder(id: string, updates: Partial<SalesOrder>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('sales_orders').update({ ...updates, updated_at: new Date().toISOString() }), 'sales_orders', tid).eq('id', id).select().single()
  if (error) throw error
  return data as SalesOrder
}

export async function deleteSalesOrder(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('sales_orders').delete(), 'sales_orders', tid).eq('id', id)
  if (error) throw error
}

// ============ Sprint 6: Delivery Notes ============
export async function getDeliveryNotes(status?: string) {
  const tid = await getTenantId()
  let q = supabase.from('delivery_notes').select('*').order('delivery_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (status) q = q.eq('status', status)
  const { data, error } = await q
  if (error) throw error
  return data as DeliveryNote[]
}

export async function createDeliveryNote(dn: Omit<DeliveryNote, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('delivery_notes').insert(ti(dn, 'delivery_notes', tid)).select().single()
  if (error) throw error
  return data as DeliveryNote
}

export async function updateDeliveryNote(id: string, updates: Partial<DeliveryNote>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('delivery_notes').update(updates), 'delivery_notes', tid).eq('id', id).select().single()
  if (error) throw error
  return data as DeliveryNote
}

export async function deleteDeliveryNote(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('delivery_notes').delete(), 'delivery_notes', tid).eq('id', id)
  if (error) throw error
}

// ============ Sprint 6: Customer Payments ============
export async function getCustomerPayments(status?: string) {
  const tid = await getTenantId()
  let q = supabase.from('customer_payments').select('*').order('payment_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (status) q = q.eq('status', status)
  const { data, error } = await q
  if (error) throw error
  return data as CustomerPayment[]
}

export async function createCustomerPayment(cp: Omit<CustomerPayment, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('customer_payments').insert(ti(cp, 'customer_payments', tid)).select().single()
  if (error) throw error
  return data as CustomerPayment
}

export async function deleteCustomerPayment(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('customer_payments').delete(), 'customer_payments', tid).eq('id', id)
  if (error) throw error
}

// ============ Sprint 6: Purchase Orders ============
export async function getPurchaseOrders(status?: string) {
  const tid = await getTenantId()
  let q = supabase.from('purchase_orders').select('*').order('order_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (status) q = q.eq('status', status)
  const { data, error } = await q
  if (error) throw error
  return data as PurchaseOrder[]
}

export async function createPurchaseOrder(po: Omit<PurchaseOrder, 'id' | 'created_at' | 'updated_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('purchase_orders').insert(ti(po, 'purchase_orders', tid)).select().single()
  if (error) throw error
  return data as PurchaseOrder
}

export async function updatePurchaseOrder(id: string, updates: Partial<PurchaseOrder>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('purchase_orders').update({ ...updates, updated_at: new Date().toISOString() }), 'purchase_orders', tid).eq('id', id).select().single()
  if (error) throw error
  return data as PurchaseOrder
}

export async function deletePurchaseOrder(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('purchase_orders').delete(), 'purchase_orders', tid).eq('id', id)
  if (error) throw error
}

// ============ Sprint 6: Goods Receipts ============
export async function getGoodsReceipts(status?: string) {
  const tid = await getTenantId()
  let q = supabase.from('goods_receipts').select('*').order('receipt_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (status) q = q.eq('status', status)
  const { data, error } = await q
  if (error) throw error
  return data as GoodsReceipt[]
}

export async function createGoodsReceipt(gr: Omit<GoodsReceipt, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('goods_receipts').insert(ti(gr, 'goods_receipts', tid)).select().single()
  if (error) throw error
  return data as GoodsReceipt
}

export async function updateGoodsReceipt(id: string, updates: Partial<GoodsReceipt>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('goods_receipts').update(updates), 'goods_receipts', tid).eq('id', id).select().single()
  if (error) throw error
  return data as GoodsReceipt
}

export async function deleteGoodsReceipt(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('goods_receipts').delete(), 'goods_receipts', tid).eq('id', id)
  if (error) throw error
}

// ============ Sprint 6: Supplier Payments ============
export async function getSupplierPayments(status?: string) {
  const tid = await getTenantId()
  let q = supabase.from('supplier_payments').select('*').order('payment_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (status) q = q.eq('status', status)
  const { data, error } = await q
  if (error) throw error
  return data as SupplierPayment[]
}

export async function createSupplierPayment(sp: Omit<SupplierPayment, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('supplier_payments').insert(ti(sp, 'supplier_payments', tid)).select().single()
  if (error) throw error
  return data as SupplierPayment
}

export async function deleteSupplierPayment(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('supplier_payments').delete(), 'supplier_payments', tid).eq('id', id)
  if (error) throw error
}

// ============ Sprint 6: Warehouses ============
export async function getWarehouses() {
  const tid = await getTenantId()
  let q = supabase.from('warehouses').select('*').order('name')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as Warehouse[]
}

export async function createWarehouse(w: Omit<Warehouse, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('warehouses').insert(ti(w, 'warehouses', tid)).select().single()
  if (error) throw error
  return data as Warehouse
}

export async function updateWarehouse(id: string, updates: Partial<Warehouse>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('warehouses').update(updates), 'warehouses', tid).eq('id', id).select().single()
  if (error) throw error
  return data as Warehouse
}

export async function deleteWarehouse(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('warehouses').delete(), 'warehouses', tid).eq('id', id)
  if (error) throw error
}

// ============ Sprint 6: Stock Quantities ============
export async function getStockQuantities(warehouseId?: string) {
  const tid = await getTenantId()
  let q = supabase.from('stock_quantities').select('*, products(name, sku), warehouses(name)').order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (warehouseId) q = q.eq('warehouse_id', warehouseId)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}

export async function updateStockQuantity(id: string, updates: Partial<StockQuantity>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('stock_quantities').update({ ...updates, updated_at: new Date().toISOString() }), 'stock_quantities', tid).eq('id', id).select().single()
  if (error) throw error
  return data as StockQuantity
}

// ============ Sprint 6: Price Lists ============
export async function getPriceLists() {
  const tid = await getTenantId()
  let q = supabase.from('price_lists').select('*').order('name')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as PriceList[]
}

export async function createPriceList(pl: Omit<PriceList, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('price_lists').insert(ti(pl, 'price_lists', tid)).select().single()
  if (error) throw error
  return data as PriceList
}

export async function updatePriceList(id: string, updates: Partial<PriceList>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('price_lists').update(updates), 'price_lists', tid).eq('id', id).select().single()
  if (error) throw error
  return data as PriceList
}

export async function deletePriceList(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('price_lists').delete(), 'price_lists', tid).eq('id', id)
  if (error) throw error
}

export async function getPriceListLines(priceListId: string) {
  const tid = await getTenantId()
  let q = supabase.from('price_list_lines').select('*, products(name, sku)').eq('price_list_id', priceListId).order('min_quantity')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}

export async function createPriceListLine(pll: Omit<PriceListLine, 'id'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('price_list_lines').insert(ti(pll, 'price_list_lines', tid)).select().single()
  if (error) throw error
  return data as PriceListLine
}

export async function deletePriceListLine(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('price_list_lines').delete(), 'price_list_lines', tid).eq('id', id)
  if (error) throw error
}

// ============ Sprint 6: BOMs ============
export async function getBOMs() {
  const tid = await getTenantId()
  let q = supabase.from('boms').select('*').order('code')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as BOM[]
}

export async function createBOM(b: Omit<BOM, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('boms').insert(ti(b, 'boms', tid)).select().single()
  if (error) throw error
  return data as BOM
}

export async function deleteBOM(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('boms').delete(), 'boms', tid).eq('id', id)
  if (error) throw error
}

export async function getBOMLines(bomId: string) {
  const tid = await getTenantId()
  let q = supabase.from('bom_lines').select('*, products(name, sku)').eq('bom_id', bomId).order('position')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}

export async function createBOMLine(bl: Omit<BOMLine, 'id'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('bom_lines').insert(ti(bl, 'bom_lines', tid)).select().single()
  if (error) throw error
  return data as BOMLine
}

export async function deleteBOMLine(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('bom_lines').delete(), 'bom_lines', tid).eq('id', id)
  if (error) throw error
}

// ============ Sprint 6: Manufacturing Orders ============
export async function getManufacturingOrders(status?: string) {
  const tid = await getTenantId()
  let q = supabase.from('manufacturing_orders').select('*').order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (status) q = q.eq('status', status)
  const { data, error } = await q
  if (error) throw error
  return data as ManufacturingOrder[]
}

export async function createManufacturingOrder(mo: Omit<ManufacturingOrder, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('manufacturing_orders').insert(ti(mo, 'manufacturing_orders', tid)).select().single()
  if (error) throw error
  return data as ManufacturingOrder
}

export async function updateManufacturingOrder(id: string, updates: Partial<ManufacturingOrder>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('manufacturing_orders').update(updates), 'manufacturing_orders', tid).eq('id', id).select().single()
  if (error) throw error
  return data as ManufacturingOrder
}

export async function deleteManufacturingOrder(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('manufacturing_orders').delete(), 'manufacturing_orders', tid).eq('id', id)
  if (error) throw error
}

// ============ Sprint 6: Gescom Transfer (Compta) ============
export async function getGescomTransferData(dateFrom?: string, dateTo?: string) {
  const tid = await getTenantId()
  let invQ = supabase.from('invoices').select('id, number, date, total, status, customer_id').in('status', ['sent', 'paid']).order('date', { ascending: false })
  if (tid) invQ = invQ.eq('tenant_id', tid)
  if (dateFrom) invQ = invQ.gte('date', dateFrom)
  if (dateTo) invQ = invQ.lte('date', dateTo)
  const { data: invoices } = await invQ

  let purQ = supabase.from('purchase_invoices').select('id, number, date, total, status, supplier_id').in('status', ['received', 'paid']).order('date', { ascending: false })
  if (tid) purQ = purQ.eq('tenant_id', tid)
  if (dateFrom) purQ = purQ.gte('date', dateFrom)
  if (dateTo) purQ = purQ.lte('date', dateTo)
  const { data: purchaseInvoices } = await purQ

  let cpQ = supabase.from('customer_payments').select('*').eq('status', 'recorded').order('payment_date', { ascending: false })
  if (tid) cpQ = cpQ.eq('tenant_id', tid)
  const { data: customerPayments } = await cpQ

  let spQ = supabase.from('supplier_payments').select('*').eq('status', 'recorded').order('payment_date', { ascending: false })
  if (tid) spQ = spQ.eq('tenant_id', tid)
  const { data: supplierPayments } = await spQ

  let jeQ = supabase.from('journal_entries').select('invoice_ref').not('invoice_ref', 'is', null)
  if (tid) jeQ = jeQ.eq('tenant_id', tid)
  const { data: existingEntries } = await jeQ
  const alreadyTransferred = new Set((existingEntries || []).map((e: any) => e.invoice_ref))

  return {
    invoices: (invoices || []).map((i: any) => ({ ...i, transferred: alreadyTransferred.has(i.number) })),
    purchaseInvoices: (purchaseInvoices || []).map((p: any) => ({ ...p, transferred: alreadyTransferred.has(p.number) })),
    customerPayments: customerPayments || [],
    supplierPayments: supplierPayments || [],
    pendingCount: (invoices || []).filter((i: any) => !alreadyTransferred.has(i.number)).length + (purchaseInvoices || []).filter((p: any) => !alreadyTransferred.has(p.number)).length,
  }
}

export async function transferGescomToAccounting(items: Array<{ type: 'sales' | 'purchase' | 'customer_payment' | 'supplier_payment'; id: string; number: string; amount: number; date: string }>) {
  const tid = await getTenantId()
  const results: Array<{ success: boolean; number: string; error?: string }> = []
  for (const item of items) {
    try {
      let journalCode = 'VTE'
      let accountDebit = '411000'
      let accountCredit = '707000'
      if (item.type === 'purchase') { journalCode = 'ACH'; accountDebit = '607000'; accountCredit = '401000' }
      else if (item.type === 'customer_payment') { journalCode = 'BQ'; accountDebit = '512000'; accountCredit = '411000' }
      else if (item.type === 'supplier_payment') { journalCode = 'BQ'; accountDebit = '401000'; accountCredit = '512000' }

      const entryNumber = `${journalCode}-${item.number}`
      const { data: entry, error: entryErr } = await supabase.from('journal_entries').insert(ti({
        number: entryNumber,
        date: item.date,
        journal_code: journalCode,
        status: 'draft',
        invoice_ref: item.number,
      }, 'journal_entries', tid)).select().single()
      if (entryErr) throw entryErr

      const { error: lineErr } = await supabase.from('journal_lines').insert([
        ti({ journal_id: entry.id, account_code: accountDebit, account_general: accountDebit, debit: item.amount, credit: 0, description: item.number }, 'journal_lines', tid),
        ti({ journal_id: entry.id, account_code: accountCredit, account_general: accountCredit, debit: 0, credit: item.amount, description: item.number }, 'journal_lines', tid),
      ])
      if (lineErr) throw lineErr

      results.push({ success: true, number: item.number })
    } catch (err: any) {
      results.push({ success: false, number: item.number, error: err.message })
    }
  }
  return results
}

// ============ Sprint 7: Pay Slips ============
export async function getPaySlips(payRunId?: string) {
  const tid = await getTenantId()
  let q = supabase.from('pay_slips').select('*, employees(name, position, department)').order('period_start', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (payRunId) q = q.eq('pay_run_id', payRunId)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}

export async function createPaySlip(ps: Omit<PaySlip, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('pay_slips').insert(ti(ps, 'pay_slips', tid)).select().single()
  if (error) throw error
  return data as PaySlip
}

export async function updatePaySlip(id: string, updates: Partial<PaySlip>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('pay_slips').update(updates), 'pay_slips', tid).eq('id', id).select().single()
  if (error) throw error
  return data as PaySlip
}

export async function deletePaySlip(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('pay_slips').delete(), 'pay_slips', tid).eq('id', id)
  if (error) throw error
}

export async function generatePaySlipsForRun(payRunId: string, employees: Employee[], payRun: PayRun) {
  const tid = await getTenantId()
  const results: PaySlip[] = []
  for (const emp of employees) {
    if (emp.status === 'inactive') continue
    const grossSalary = Number(emp.salary)
    const overtimePay = 0
    const bonus = 0
    const totalGross = grossSalary + overtimePay + bonus
    const socialSecurity = totalGross * 0.22
    const incomeTax = totalGross * 0.10
    const otherDeductions = 0
    const totalDeductions = socialSecurity + incomeTax + otherDeductions
    const netSalary = totalGross - totalDeductions
    const employerContributions = totalGross * 0.42

    const number = `BS-${payRun.number}-${emp.name.substring(0, 3).toUpperCase()}`
    const { data, error } = await supabase.from('pay_slips').insert(ti({
      number, pay_run_id: payRunId, employee_id: emp.id,
      period_start: payRun.period_start, period_end: payRun.period_end,
      gross_salary: grossSalary, overtime_pay: overtimePay, bonus,
      total_gross: totalGross, social_security_employee: socialSecurity,
      income_tax: incomeTax, other_deductions: otherDeductions,
      total_deductions: totalDeductions, net_salary: netSalary,
      employer_contributions: employerContributions, status: 'draft',
    }, 'pay_slips', tid)).select().single()
    if (error) throw error
    results.push(data as PaySlip)
  }
  return results
}

// ============ Sprint 7: Payroll Accounting Entries ============
export async function getPayrollAccountingEntries() {
  const tid = await getTenantId()
  let q = supabase.from('payroll_accounting_entries').select('*, pay_runs(number)').order('period_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}

export async function createPayrollAccountingEntry(pae: Omit<PayrollAccountingEntry, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('payroll_accounting_entries').insert(ti(pae, 'payroll_accounting_entries', tid)).select().single()
  if (error) throw error
  return data as PayrollAccountingEntry
}

export async function updatePayrollAccountingEntry(id: string, updates: Partial<PayrollAccountingEntry>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('payroll_accounting_entries').update(updates), 'payroll_accounting_entries', tid).eq('id', id).select().single()
  if (error) throw error
  return data as PayrollAccountingEntry
}

export async function deletePayrollAccountingEntry(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('payroll_accounting_entries').delete(), 'payroll_accounting_entries', tid).eq('id', id)
  if (error) throw error
}

export async function transferPayrollToAccounting(entryId: string, entry: PayrollAccountingEntry) {
  const tid = await getTenantId()
  const entryNumber = `OD-PAIE-${entry.number}`
  const { data: je, error: jeErr } = await supabase.from('journal_entries').insert(ti({
    number: entryNumber, date: entry.period_date, journal_code: 'OD',
    status: 'draft', description: `OD de paie ${entry.number}`,
  }, 'journal_entries', tid)).select().single()
  if (jeErr) throw jeErr

  const lines = [
    ti({ journal_id: je.id, account_code: '641000', account_general: '641000', debit: entry.gross_total, credit: 0, description: 'Rémunérations brutes' }, 'journal_lines', tid),
    ti({ journal_id: je.id, account_code: '645000', account_general: '645000', debit: entry.employer_contributions_total, credit: 0, description: 'Charges patronales' }, 'journal_lines', tid),
    ti({ journal_id: je.id, account_code: '431000', account_general: '431000', debit: 0, credit: entry.employee_deductions_total, description: 'Charges salariales' }, 'journal_lines', tid),
    ti({ journal_id: je.id, account_code: '421000', account_general: '421000', debit: 0, credit: entry.net_total, description: 'Net à payer' }, 'journal_lines', tid),
  ]
  const { error: lineErr } = await supabase.from('journal_lines').insert(lines)
  if (lineErr) throw lineErr

  await updatePayrollAccountingEntry(entryId, { status: 'transferred', journal_entry_id: je.id })
  return je
}

// ============ Sprint 7: Leave Requests ============
export async function getLeaveRequests(status?: string) {
  const tid = await getTenantId()
  let q = supabase.from('leave_requests').select('*, employees(name, department)').order('start_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (status) q = q.eq('status', status)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}

export async function createLeaveRequest(lr: Omit<LeaveRequest, 'id' | 'created_at' | 'approved_by' | 'approved_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('leave_requests').insert(ti(lr, 'leave_requests', tid)).select().single()
  if (error) throw error
  return data as LeaveRequest
}

export async function updateLeaveRequest(id: string, updates: Partial<LeaveRequest>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('leave_requests').update(updates), 'leave_requests', tid).eq('id', id).select().single()
  if (error) throw error
  return data as LeaveRequest
}

export async function deleteLeaveRequest(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('leave_requests').delete(), 'leave_requests', tid).eq('id', id)
  if (error) throw error
}

// ============ Sprint 7: Contracts ============
export async function getContracts() {
  const tid = await getTenantId()
  let q = supabase.from('contracts').select('*, employees(name, position, department)').order('start_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}

export async function createContract(c: Omit<Contract, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('contracts').insert(ti(c, 'contracts', tid)).select().single()
  if (error) throw error
  return data as Contract
}

export async function updateContract(id: string, updates: Partial<Contract>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('contracts').update(updates), 'contracts', tid).eq('id', id).select().single()
  if (error) throw error
  return data as Contract
}

export async function deleteContract(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('contracts').delete(), 'contracts', tid).eq('id', id)
  if (error) throw error
}

// ============ Sprint 7: Legal Declarations ============
export async function getLegalDeclarations(status?: string) {
  const tid = await getTenantId()
  let q = supabase.from('legal_declarations').select('*').order('due_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (status) q = q.eq('status', status)
  const { data, error } = await q
  if (error) throw error
  return data as LegalDeclaration[]
}

export async function createLegalDeclaration(ld: Omit<LegalDeclaration, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('legal_declarations').insert(ti(ld, 'legal_declarations', tid)).select().single()
  if (error) throw error
  return data as LegalDeclaration
}

export async function updateLegalDeclaration(id: string, updates: Partial<LegalDeclaration>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('legal_declarations').update(updates), 'legal_declarations', tid).eq('id', id).select().single()
  if (error) throw error
  return data as LegalDeclaration
}

export async function deleteLegalDeclaration(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('legal_declarations').delete(), 'legal_declarations', tid).eq('id', id)
  if (error) throw error
}

// ============ Sprint 8: Audit Log ============
export async function getAuditLog(entityType?: string, action?: string) {
  const tid = await getTenantId()
  let q = supabase.from('audit_log').select('*').order('created_at', { ascending: false }).limit(200)
  if (tid) q = q.eq('tenant_id', tid)
  if (entityType) q = q.eq('entity_type', entityType)
  if (action) q = q.eq('action', action)
  const { data, error } = await q
  if (error) {
    console.warn('audit_log query failed:', error.message)
    return []
  }
  return data as any[]
}

export async function createAuditLog(entry: Omit<AuditLog, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('audit_log').insert(ti(entry, 'audit_log', tid)).select().single()
  if (error) throw error
  return data as AuditLog
}

// ============ Sprint 8: Budget Tracking ============
export async function getBudgetTracking(fiscalYearId?: string) {
  const tid = await getTenantId()
  let q = supabase.from('budgets').select('*, chart_accounts(code, name), fiscal_years(code)').order('name')
  if (tid) q = q.eq('tenant_id', tid)
  if (fiscalYearId) q = q.eq('fiscal_year_id', fiscalYearId)
  const { data: budgets, error } = await q
  if (error) throw error

  const results: any[] = []
  for (const b of budgets || []) {
    let jlQ = supabase
      .from('journal_lines')
      .select('debit, credit')
      .eq('account_general', b.account_code)
    if (tid) jlQ = jlQ.eq('tenant_id', tid)
    const { data: lines } = await jlQ
    const realized = (lines || []).reduce((s, l) => s + Number(l.debit) - Number(l.credit), 0)

    const budgetTotal = ['period_1','period_2','period_3','period_4','period_5','period_6','period_7','period_8','period_9','period_10','period_11','period_12']
      .reduce((s, k) => s + Number((b as any)[k] || 0), 0)

    let committed = 0
    let commitQ = supabase
      .from('budget_commitments')
      .select('amount')
      .eq('account_code', b.account_code)
      .eq('status', 'active')
    if (tid) commitQ = commitQ.eq('tenant_id', tid)
    if (b.fiscal_year_id) commitQ = commitQ.eq('fiscal_year_id', b.fiscal_year_id)
    const { data: commitments } = await commitQ
    committed = (commitments || []).reduce((s, c) => s + Number(c.amount), 0)

    const available = budgetTotal - realized - committed

    results.push({
      ...b,
      total: budgetTotal,
      realized,
      committed,
      available,
      variance: budgetTotal - realized,
      variance_pct: budgetTotal > 0 ? ((budgetTotal - realized) / budgetTotal) * 100 : 0,
    })
  }
  return results
}

// ============ Budget Commitments ============
export async function getBudgetCommitments(fiscalYearId?: string) {
  const tid = await getTenantId()
  let q = supabase.from('budget_commitments').select('*').order('commitment_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (fiscalYearId) q = q.eq('fiscal_year_id', fiscalYearId)
  const { data, error } = await q
  if (error) throw error
  return data as BudgetCommitment[]
}

export async function createBudgetCommitment(c: Omit<BudgetCommitment, 'id' | 'created_at' | 'updated_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('budget_commitments').insert(ti(c, 'budget_commitments', tid)).select().single()
  if (error) throw error
  return data as BudgetCommitment
}

export async function updateBudgetCommitment(id: string, updates: Partial<BudgetCommitment>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('budget_commitments').update(updates), 'budget_commitments', tid).eq('id', id).select().single()
  if (error) throw error
  return data as BudgetCommitment
}

export async function deleteBudgetCommitment(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('budget_commitments').delete(), 'budget_commitments', tid).eq('id', id)
  if (error) throw error
}

export async function checkBudgetAvailability(accountCode: string, amount: number, fiscalYearId?: string): Promise<BudgetControlResult> {
  const tid = await getTenantId()
  let bq = supabase.from('budgets').select('*').eq('account_code', accountCode)
  if (tid) bq = bq.eq('tenant_id', tid)
  if (fiscalYearId) bq = bq.eq('fiscal_year_id', fiscalYearId)
  const { data: budgets } = await bq

  const budgetTotal = (budgets || []).reduce((s, b) =>
    s + ['period_1','period_2','period_3','period_4','period_5','period_6','period_7','period_8','period_9','period_10','period_11','period_12']
      .reduce((acc, k) => acc + Number((b as any)[k] || 0), 0), 0)

  let jlQ2 = supabase
    .from('journal_lines')
    .select('debit, credit')
    .eq('account_general', accountCode)
  if (tid) jlQ2 = jlQ2.eq('tenant_id', tid)
  const { data: lines } = await jlQ2
  const realized = (lines || []).reduce((s, l) => s + Number(l.debit) - Number(l.credit), 0)

  let commitQ2 = supabase
    .from('budget_commitments')
    .select('amount')
    .eq('account_code', accountCode)
    .eq('status', 'active')
  if (tid) commitQ2 = commitQ2.eq('tenant_id', tid)
  if (fiscalYearId) commitQ2 = commitQ2.eq('fiscal_year_id', fiscalYearId)
  const { data: commitments } = await commitQ2
  const committed = (commitments || []).reduce((s, c) => s + Number(c.amount), 0)

  const available = budgetTotal - realized - committed
  const would_exceed = amount > available
  const overshoot_amount = would_exceed ? amount - available : 0

  return {
    account_code: accountCode,
    budget_total: budgetTotal,
    realized,
    committed,
    available,
    would_exceed,
    overshoot_amount,
  }
}

// ============ Sprint 8: Financial Dashboard ============
export async function getFinancialDashboard() {
  const tid = await getTenantId()
  const [invoices, purchaseInvoices, bankAccounts, journalEntries] = await Promise.all([
    tid ? supabase.from('invoices').select('total, status, date').eq('status', 'paid').eq('tenant_id', tid) : supabase.from('invoices').select('total, status, date').eq('status', 'paid'),
    tid ? supabase.from('purchase_invoices').select('total, status, date').eq('status', 'paid').eq('tenant_id', tid) : supabase.from('purchase_invoices').select('total, status, date').eq('status', 'paid'),
    tid ? supabase.from('bank_accounts').select('balance, type').eq('tenant_id', tid) : supabase.from('bank_accounts').select('balance, type'),
    tid ? supabase.from('journal_entries').select('number, date, status').eq('tenant_id', tid) : supabase.from('journal_entries').select('number, date, status'),
  ])

  const revenue = (invoices.data || []).reduce((s, i) => s + Number(i.total), 0)
  const expenses = (purchaseInvoices.data || []).reduce((s, i) => s + Number(i.total), 0)
  const cashPosition = (bankAccounts.data || []).reduce((s, a) => s + Number(a.balance), 0)
  const margin = revenue - expenses
  const marginPct = revenue > 0 ? (margin / revenue) * 100 : 0

  return {
    revenue,
    expenses,
    margin,
    marginPct,
    cashPosition,
    pendingEntries: (journalEntries.data || []).filter((e) => e.status === 'draft').length,
    totalEntries: (journalEntries.data || []).length,
    invoiceCount: (invoices.data || []).length,
    supplierInvoiceCount: (purchaseInvoices.data || []).length,
  }
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
  if (typeof val === 'object') return `'${JSON.stringify(val).replace(/'/g, "''")}'`
  const str = String(val).replace(/'/g, "''")
  return `'${str}'`
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
    lines.push(`-- Table: ${table.tableName} (${table.rowCount} lignes)`)
    lines.push(`INSERT INTO sync_metadata (table_name, last_sync_at, row_count, source) VALUES ('${table.tableName}', '${exportedAt}', ${table.rowCount}, 'supabase');`)
    lines.push('')

    if (table.rowCount === 0) {
      lines.push(`-- ${table.tableName}: aucune donnee`)
      lines.push('')
      continue
    }

    const cols = table.columns.join(', ')
    for (const row of table.rows) {
      const values = table.columns.map(c => escapeSqlValue(row[c])).join(', ')
      lines.push(`INSERT INTO ${table.tableName} (${cols}) VALUES (${values});`)
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
      const str = String(val).replace(/"/g, '""')
      return str.includes(';') || str.includes('\n') ? `"${str}"` : str
    }).join(';')
  )
  return [headers, ...rows].join('\n')
}

// ============ Mirror Server Management ============
export interface MirrorServer {
  id: string
  tenant_id: string
  machine_id: string
  machine_name: string
  os: string | null
  ip_address: string | null
  mirror_dir: string | null
  registered_at: string
  last_heartbeat: string
  status: 'active' | 'inactive' | 'revoked'
  config: Record<string, any> | null
}

export async function registerMirrorServer(data: {
  tenant_id: string
  machine_id: string
  machine_name: string
  os?: string
  ip_address?: string
  mirror_dir?: string
  config?: Record<string, any>
}): Promise<{ success: boolean; error?: string; server?: MirrorServer }> {
  const { data: existing, error: checkError } = await supabase
    .from('mirror_servers')
    .select('*')
    .eq('tenant_id', data.tenant_id)
    .eq('status', 'active')
    .maybeSingle()

  if (checkError) {
    return { success: false, error: checkError.message }
  }

  if (existing && existing.machine_id !== data.machine_id) {
    return {
      success: false,
      error: `Un serveur miroir est déjà enregistré pour ce tenant sur la machine "${existing.machine_name}". Un seul serveur miroir par tenant est autorisé. Révoquez-le d'abord pour enregistrer un nouveau.`,
    }
  }

  if (existing && existing.machine_id === data.machine_id) {
    const { data: updated, error: updateError } = await supabase
      .from('mirror_servers')
      .update({
        machine_name: data.machine_name,
        os: data.os || null,
        ip_address: data.ip_address || null,
        mirror_dir: data.mirror_dir || null,
        last_heartbeat: new Date().toISOString(),
        status: 'active',
        config: data.config || null,
      })
      .eq('id', existing.id)
      .select()
      .single()
    if (updateError) return { success: false, error: updateError.message }
    return { success: true, server: updated as MirrorServer }
  }

  const { data: created, error: insertError } = await supabase
    .from('mirror_servers')
    .insert({
      tenant_id: data.tenant_id,
      machine_id: data.machine_id,
      machine_name: data.machine_name,
      os: data.os || null,
      ip_address: data.ip_address || null,
      mirror_dir: data.mirror_dir || null,
      status: 'active',
      config: data.config || null,
    })
    .select()
    .single()

  if (insertError) {
    if (insertError.code === '23505') {
      return { success: false, error: 'Un serveur miroir est déjà enregistré pour ce tenant.' }
    }
    return { success: false, error: insertError.message }
  }

  return { success: true, server: created as MirrorServer }
}

export async function getMirrorServer(tenantId: string): Promise<MirrorServer | null> {
  const { data, error } = await supabase
    .from('mirror_servers')
    .select('*')
    .eq('tenant_id', tenantId)
    .maybeSingle()
  if (error) {
    console.error('Error getting mirror server:', error)
    return null
  }
  return data as MirrorServer | null
}

export async function updateMirrorHeartbeat(machineId: string): Promise<void> {
  await supabase
    .from('mirror_servers')
    .update({ last_heartbeat: new Date().toISOString() })
    .eq('machine_id', machineId)
}

export async function revokeMirrorServer(tenantId: string): Promise<{ error?: string }> {
  const { error } = await supabase
    .from('mirror_servers')
    .update({ status: 'revoked' })
    .eq('tenant_id', tenantId)
  if (error) return { error: error.message }
  return {}
}

// ============ Mirror Server Installation Flow ============

export async function preRegisterMirrorServer(data: {
  tenant_id: string
  install_platform: 'mac' | 'windows' | 'linux'
}): Promise<{ success: boolean; error?: string; install_token?: string }> {
  const { data: existing } = await supabase
    .from('mirror_servers')
    .select('*')
    .eq('tenant_id', data.tenant_id)
    .in('status', ['active'])
    .maybeSingle()

  if (existing && existing.install_status === 'verified') {
    return { success: false, error: 'Un serveur miroir vérifié est déjà installé pour ce tenant.' }
  }

  const installToken = crypto.randomUUID()

  if (existing) {
    const { error } = await supabase
      .from('mirror_servers')
      .update({
        install_status: 'pending',
        install_token: installToken,
        install_platform: data.install_platform,
      })
      .eq('id', existing.id)
    if (error) return { success: false, error: error.message }
  } else {
    const { error } = await supabase
      .from('mirror_servers')
      .insert({
        tenant_id: data.tenant_id,
        machine_id: 'pending-' + installToken,
        machine_name: 'En attente d\'installation',
        status: 'active',
        install_status: 'pending',
        install_token: installToken,
        install_platform: data.install_platform,
      })
    if (error) return { success: false, error: error.message }
  }

  return { success: true, install_token: installToken }
}

export async function getMirrorServerStatus(tenantId: string): Promise<{
  exists: boolean
  install_status?: string
  install_platform?: string
  machine_name?: string
  verified_at?: string
  verification_data?: Record<string, any>
  last_heartbeat?: string
}> {
  const { data, error } = await supabase
    .from('mirror_servers')
    .select('*')
    .eq('tenant_id', tenantId)
    .maybeSingle()

  if (error || !data) return { exists: false }

  return {
    exists: true,
    install_status: data.install_status,
    install_platform: data.install_platform,
    machine_name: data.machine_name,
    verified_at: data.verified_at,
    verification_data: data.verification_data,
    last_heartbeat: data.last_heartbeat,
  }
}

export async function getMirrorVerificationDetails(serverId: string): Promise<any[]> {
  const { data, error } = await supabase
    .from('mirror_verification_details')
    .select('*')
    .eq('mirror_server_id', serverId)
    .order('table_name')
  if (error) return []
  return data || []
}

export function generateMacInstaller(config: {
  supabaseUrl: string
  supabaseKey: string
  tenantId: string
  installToken: string
  daemonCode: string
}): string {
  return `#!/bin/bash
# Installateur du serveur miroir Compta - macOS
# Généré automatiquement depuis la plateforme

set -e

INSTALL_DIR="$HOME/compta-mirror"
TENANT_ID="${config.tenantId}"
SUPABASE_URL="${config.supabaseUrl}"
SUPABASE_KEY="${config.supabaseKey}"
INSTALL_TOKEN="${config.installToken}"

echo "======================================================"
echo "  INSTALLATION SERVEUR MIROIR COMPTA - macOS          "
echo "======================================================"
echo ""

# Vérifier Node.js
if ! command -v node &> /dev/null; then
  echo "ERREUR: Node.js n'est pas installé."
  echo "Installez-le depuis: https://nodejs.org (version 18+)"
  exit 1
fi
NODE_PATH=$(which node)
echo "Node.js: $NODE_PATH ($(node --version))"

# Créer le dossier
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"
echo "Dossier: $INSTALL_DIR"

# Écrire la configuration
cat > config.json << EOF
{
  "supabaseUrl": "$SUPABASE_URL",
  "supabaseKey": "$SUPABASE_KEY",
  "mirrorDir": "./mirror-data",
  "pollIntervalMs": 300000,
  "syncOnStart": true,
  "tenantId": "$TENANT_ID",
  "installToken": "$INSTALL_TOKEN"
}
EOF

# Écrire package.json
cat > package.json << EOF
{
  "name": "compta-mirror-daemon",
  "version": "1.0.0",
  "type": "module",
  "dependencies": { "@supabase/supabase-js": "^2.45.0" }
}
EOF

echo "Installation des dépendances..."
npm install --production 2>&1 | tail -3

# Écrire le daemon
cat > daemon.mjs << 'DAEMON_EOF'
${config.daemonCode}
DAEMON_EOF

# Enregistrer + première sync + vérification
echo ""
echo "=== Enregistrement et synchronisation ==="
node daemon.mjs --register --force --once --verbose

if [ $? -ne 0 ]; then
  echo "ERREUR: L'installation a échoué."
  exit 1
fi

# Configurer launchd
PLIST_LABEL="com.compta.mirror-daemon"
PLIST_PATH="$HOME/Library/LaunchAgents/\${PLIST_LABEL}.plist"
mkdir -p "$(dirname "$PLIST_PATH")"

cat > "$PLIST_PATH" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>\${PLIST_LABEL}</string>
  <key>ProgramArguments</key><array>
    <string>\${NODE_PATH}</string>
    <string>\${INSTALL_DIR}/daemon.mjs</string>
  </array>
  <key>WorkingDirectory</key><string>\${INSTALL_DIR}</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>\${INSTALL_DIR}/daemon.log</string>
  <key>StandardErrorPath</key><string>\${INSTALL_DIR}/daemon-error.log</string>
</dict>
</plist>
EOF

launchctl unload "$PLIST_PATH" 2>/dev/null || true
launchctl load "$PLIST_PATH"

echo ""
echo "======================================================"
echo "  INSTALLATION TERMINÉE ET VÉRIFIÉE                   "
echo "  Le daemon est actif. Données dans:                  "
echo "  $INSTALL_DIR/mirror-data/                           "
echo "  Démarrage automatique au boot.                      "
echo "======================================================"
`
}

export function generateWindowsInstaller(config: {
  supabaseUrl: string
  supabaseKey: string
  tenantId: string
  installToken: string
  daemonCode: string
}): string {
  return `# Installateur du serveur miroir Compta - Windows (PowerShell)
# Genere automatiquement depuis la plateforme
# Usage: Right-click > Run with PowerShell

$ErrorActionPreference = "Stop"

$INSTALL_DIR = "$env:USERPROFILE\\compta-mirror"
$TENANT_ID = "${config.tenantId}"
$SUPABASE_URL = "${config.supabaseUrl}"
$SUPABASE_KEY = "${config.supabaseKey}"
$INSTALL_TOKEN = "${config.installToken}"

Write-Host "======================================================="
Write-Host "  INSTALLATION SERVEUR MIROIR COMPTA - Windows        "
Write-Host "======================================================="
Write-Host ""

# Verifier Node.js
$nodePath = (Get-Command node -ErrorAction SilentlyContinue).Source
if (-not $nodePath) {
    Write-Host "ERREUR: Node.js n'est pas installe." -ForegroundColor Red
    Write-Host "Installez-le depuis: https://nodejs.org (version 18+)"
    exit 1
}
Write-Host "Node.js: $nodePath ($(node --version))"

# Creer le dossier
New-Item -ItemType Directory -Force -Path $INSTALL_DIR | Out-Null
Set-Location $INSTALL_DIR
Write-Host "Dossier: $INSTALL_DIR"

# Ecrire la configuration
$conf = @{
    supabaseUrl = $SUPABASE_URL
    supabaseKey = $SUPABASE_KEY
    mirrorDir = "./mirror-data"
    pollIntervalMs = 300000
    syncOnStart = $true
    tenantId = $TENANT_ID
    installToken = $INSTALL_TOKEN
} | ConvertTo-Json
$conf | Out-File -FilePath "config.json" -Encoding utf8

# Ecrire package.json
$pkg = @{
    name = "compta-mirror-daemon"
    version = "1.0.0"
    type = "module"
    dependencies = @{ "@supabase/supabase-js" = "^2.45.0" }
} | ConvertTo-Json
$pkg | Out-File -FilePath "package.json" -Encoding utf8

Write-Host "Installation des dependances..."
npm install --production 2>&1 | Select-Object -Last 3

# Ecrire le daemon
$daemonCode = @'
${config.daemonCode}
'@
$daemonCode | Out-File -FilePath "daemon.mjs" -Encoding utf8

# Enregistrer + premiere sync + verification
Write-Host ""
Write-Host "=== Enregistrement et synchronisation ==="
node daemon.mjs --register --force --once --verbose

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERREUR: L'installation a echoue." -ForegroundColor Red
    exit 1
}

# Creer la tache planifiee Windows
$action = New-ScheduledTaskAction -Execute $nodePath -Argument "daemon.mjs" -WorkingDirectory $INSTALL_DIR
$trigger = New-ScheduledTaskTrigger -AtStartup
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName "ComptaMirrorDaemon" -Action $action -Trigger $trigger -Settings $settings -Force

Write-Host ""
Write-Host "======================================================="
Write-Host "  INSTALLATION TERMINEE ET VERIFIEE                   "
Write-Host "  Tache planifiee: ComptaMirrorDaemon                  "
Write-Host "  Donnees dans: $INSTALL_DIR\\mirror-data\\           "
Write-Host "======================================================="
`
}

// ============ Multi-Tenant Management ============

export interface Tenant {
  id: string
  name: string
  legal_name: string | null
  siren: string | null
  siret: string | null
  vat_number: string | null
  address: string | null
  city: string | null
  postal_code: string | null
  country: string
  currency: string
  phone: string | null
  email: string | null
  logo_url: string | null
  status: string
  plan: string
  trial_ends_at: string | null
  created_at: string
}

export interface TenantUser {
  id: string
  tenant_id: string
  auth_id: string | null
  email: string
  name: string
  role: 'admin' | 'accountant' | 'manager' | 'viewer' | 'custom'
  permissions: Record<string, string[]>
  status: 'pending' | 'active' | 'revoked'
  invited_by: string | null
  invited_at: string
  accepted_at: string | null
  last_login: string | null
  created_at: string
}

export async function createTenant(data: {
  name: string
  legal_name?: string
  siren?: string
  vat_number?: string
  address?: string
  city?: string
  postal_code?: string
  country?: string
  currency?: string
  email?: string
  phone?: string
}): Promise<{ success: boolean; error?: string; tenant?: Tenant }> {
  const { data: tenant, error } = await supabase
    .from('tenants')
    .insert({
      name: data.name,
      legal_name: data.legal_name || data.name,
      siren: data.siren || null,
      vat_number: data.vat_number || null,
      address: data.address || null,
      city: data.city || null,
      postal_code: data.postal_code || null,
      country: data.country || 'France',
      currency: data.currency || 'EUR',
      email: data.email || null,
      phone: data.phone || null,
      status: 'active',
      plan: 'trial',
      trial_ends_at: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString(),
    })
    .select()
    .single()

  if (error) return { success: false, error: error.message }
  return { success: true, tenant: tenant as Tenant }
}

export async function createTenantForUser(data: {
  name: string
  legal_name?: string
  siren?: string
  vat_number?: string
  address?: string
  city?: string
  postal_code?: string
  country?: string
  currency?: string
  email?: string
  phone?: string
}): Promise<{ success: boolean; error?: string; tenant?: Tenant }> {
  const { data: { session } } = await supabase.auth.getSession()
  if (!session) return { success: false, error: 'Non connecté' }

  const authId = session.user.id
  const userEmail = session.user.email || data.email || ''

  const { data: tenant, error: tenantErr } = await supabase
    .from('tenants')
    .insert({
      name: data.name,
      legal_name: data.legal_name || data.name,
      siren: data.siren || null,
      vat_number: data.vat_number || null,
      address: data.address || null,
      city: data.city || null,
      postal_code: data.postal_code || null,
      country: data.country || 'France',
      currency: data.currency || 'EUR',
      email: data.email || userEmail,
      phone: data.phone || null,
      status: 'active',
      plan: 'trial',
      trial_ends_at: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString(),
    })
    .select()
    .single()

  if (tenantErr) return { success: false, error: tenantErr.message }

  const { error: tuErr } = await supabase
    .from('tenant_users')
    .insert({
      tenant_id: tenant.id,
      auth_id: authId,
      email: userEmail,
      name: data.name,
      role: 'admin',
      permissions: {},
      status: 'active',
      accepted_at: new Date().toISOString(),
    })

  if (tuErr) {
    await supabase.from('tenants').delete().eq('id', tenant.id)
    return { success: false, error: tuErr.message }
  }

  return { success: true, tenant: tenant as Tenant }
}

export async function getCurrentTenant(): Promise<Tenant | null> {
  const { data: { session } } = await supabase.auth.getSession()
  if (!session) return null

  const { data, error } = await supabase
    .from('tenant_users')
    .select('tenant_id, tenants(*)')
    .eq('auth_id', session.user.id)
    .eq('status', 'active')
    .single()

  if (error || !data) return null
  return (data as any).tenants as Tenant
}

export async function getCurrentTenantUser(): Promise<TenantUser | null> {
  const { data: { session } } = await supabase.auth.getSession()
  if (!session) return null

  const { data, error } = await supabase
    .from('tenant_users')
    .select('*')
    .eq('auth_id', session.user.id)
    .eq('status', 'active')
    .single()

  if (error || !data) return null
  return data as TenantUser
}

export async function getTenantUsers(tenantId: string): Promise<TenantUser[]> {
  const { data, error } = await supabase
    .from('tenant_users')
    .select('*')
    .eq('tenant_id', tenantId)
    .order('created_at', { ascending: false })

  if (error) throw error
  return (data || []) as TenantUser[]
}

export async function inviteUser(data: {
  tenantId: string
  email: string
  name: string
  role: TenantUser['role']
  permissions?: Record<string, string[]>
  invitedBy?: string
}): Promise<{ success: boolean; error?: string }> {
  const { error: dbError } = await supabase
    .from('tenant_users')
    .insert({
      tenant_id: data.tenantId,
      email: data.email,
      name: data.name,
      role: data.role,
      permissions: data.permissions || {},
      status: 'pending',
      invited_by: data.invitedBy || null,
    })

  if (dbError) {
    if (dbError.code === '23505') {
      return { success: false, error: 'Cet email est déjà invité dans cette entreprise.' }
    }
    return { success: false, error: dbError.message }
  }

  const redirectTo = `${window.location.origin}/accept-invitation`
  const { error: inviteError } = await supabase.auth.signInWithOtp({
    email: data.email,
    options: {
      emailRedirectTo: redirectTo,
      data: {
        tenant_id: data.tenantId,
        name: data.name,
        role: data.role,
      },
    },
  })

  if (inviteError) {
    return { success: false, error: `Utilisateur cree mais email non envoye: ${inviteError.message}` }
  }

  return { success: true }
}

export async function updateUserRole(
  tenantUserId: string,
  role: TenantUser['role'],
  permissions?: Record<string, string[]>
): Promise<{ success: boolean; error?: string }> {
  const update: Record<string, any> = { role }
  if (permissions !== undefined) update.permissions = permissions

  const { error } = await supabase
    .from('tenant_users')
    .update(update)
    .eq('id', tenantUserId)

  if (error) return { success: false, error: error.message }
  return { success: true }
}

export async function revokeUser(tenantUserId: string): Promise<{ success: boolean; error?: string }> {
  const { error } = await supabase
    .from('tenant_users')
    .update({ status: 'revoked' })
    .eq('id', tenantUserId)

  if (error) return { success: false, error: error.message }
  return { success: true }
}

export async function reactivateUser(tenantUserId: string): Promise<{ success: boolean; error?: string }> {
  const { error } = await supabase
    .from('tenant_users')
    .update({ status: 'active' })
    .eq('id', tenantUserId)

  if (error) return { success: false, error: error.message }
  return { success: true }
}

export async function reinviteUser(tenantUserId: string, email: string): Promise<{ success: boolean; error?: string }> {
  const { error: updateError } = await supabase
    .from('tenant_users')
    .update({ status: 'pending' })
    .eq('id', tenantUserId)

  if (updateError) return { success: false, error: updateError.message }

  const redirectTo = `${window.location.origin}/accept-invitation`
  const { error: inviteError } = await supabase.auth.signInWithOtp({
    email,
    options: { emailRedirectTo: redirectTo },
  })

  if (inviteError) return { success: false, error: inviteError.message }
  return { success: true }
}

export function hasPermission(
  user: TenantUser | null,
  table: string,
  action: 'select' | 'insert' | 'update' | 'delete'
): boolean {
  if (!user) return false
  if (user.role === 'admin') return true
  if (user.role === 'accountant') {
    if (action === 'select' || action === 'insert' || action === 'update') return true
    if (action === 'delete' && ['journal_entries', 'journal_lines', 'invoice_lines', 'quote_lines', 'credit_note_lines'].includes(table)) return true
    return false
  }
  if (user.role === 'manager') {
    if (action === 'select') return true
    if (action === 'insert' || action === 'update') {
      const commercialTables = ['invoices', 'invoice_lines', 'quotes', 'quote_lines', 'credit_notes', 'credit_note_lines', 'customers', 'products', 'delivery_notes', 'delivery_note_lines', 'sales_orders', 'sales_order_lines', 'purchase_orders', 'purchase_order_lines']
      return commercialTables.includes(table)
    }
    return false
  }
  if (user.role === 'viewer') return action === 'select'
  if (user.role === 'custom') {
    const perms = user.permissions[table]
    if (!perms) return false
    return perms.includes(action)
  }
  return false
}

export const ROLE_LABELS: Record<TenantUser['role'], string> = {
  admin: 'Administrateur',
  accountant: 'Comptable',
  manager: 'Manager',
  viewer: 'Lecture seule',
  custom: 'Personnalise',
}

export const ROLE_DESCRIPTIONS: Record<TenantUser['role'], string> = {
  admin: 'Acces complet a toutes les fonctions et donnees',
  accountant: 'Comptabilite, journaux, declarations - pas de suppression (sauf journaux)',
  manager: 'Ventes, achats, clients, produits - pas de comptabilite ni parametres',
  viewer: 'Consultation uniquement, aucune modification',
  custom: 'Permissions granulaires definies par l administrateur',
}

export const PERMISSION_TABLES = [
  { name: 'invoices', label: 'Factures ventes' },
  { name: 'quotes', label: 'Devis' },
  { name: 'customers', label: 'Clients' },
  { name: 'suppliers', label: 'Fournisseurs' },
  { name: 'products', label: 'Produits' },
  { name: 'purchase_invoices', label: 'Factures achats' },
  { name: 'purchase_orders', label: 'Commandes achats' },
  { name: 'journal_entries', label: 'Ecritures comptables' },
  { name: 'bank_transactions', label: 'Transactions bancaires' },
  { name: 'chart_accounts', label: 'Plan comptable' },
  { name: 'budgets', label: 'Budgets' },
  { name: 'fiscal_years', label: 'Exercices' },
  { name: 'vat_returns', label: 'Declarations TVA' },
  { name: 'employees', label: 'Employes' },
  { name: 'pay_runs', label: 'Paies' },
  { name: 'company_settings', label: 'Parametres entreprise' },
  { name: 'projects', label: 'Projets' },
  { name: 'warehouses', label: 'Entrepots' },
  { name: 'stock_movements', label: 'Mouvements stock' },
  { name: 'audit_log', label: 'Journal d audit' },
] as const

export const PERMISSION_ACTIONS = [
  { value: 'select', label: 'Voir' },
  { value: 'insert', label: 'Creer' },
  { value: 'update', label: 'Modifier' },
  { value: 'delete', label: 'Supprimer' },
] as const
