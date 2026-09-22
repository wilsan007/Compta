import { supabase } from '@/lib/supabase'
import type { Joined } from '@/types/dbRow'
import { fetchAllRows, getTenantId, ti, tud } from './core'
import { getJournals } from './misc'
import { getPaymentTermById } from './payroll'
import type { Invoice, JournalEntry, JournalLine, ChartAccount, CompanySettings, Project, VatReturn, DashboardStats, FixedAsset, Currency, Journal, FiscalYear, FiscalPeriod, EntryTemplate, ThirdPartyAccount, AnalyticSection, Budget, BudgetCommitment, BudgetControlResult, StandardLabel, PaymentOrder, AssetDepreciation, CollectionReminder, AuditLog, LegislationPack, TaxRate, RecurringEntry, RegularizationEntry, CurrencyRevaluation, AnalyticPlan, DistributionGrill, DistributionGrillLine, BankReconciliationRule, BankStatementImport, TvsDeclaration, FiscalBackup, RecurringInvoiceTemplate, FutureAccountingMovement, TreasuryTransfer, TreasuryRecurring, ConsolidatedTreasury, AssetDepreciationPlan, AutoLabelRule, ExtourneLog, CarryForwardLog, LettrageDifference, AccountingControlRun, CashControlSession, FECAttestation, TierRIB, IFRSAdjustment, TaxPayment, CustomReportTemplate, DeferredPrintingJob, JournalAccessRight, VATOnCollection, BatchEntrySession, DashboardWidget, AnalyticJournalCode, BankStatementTemplate, PayrollTaxGrid, PayrollTaxGridLine, CorporateTaxGrid, CorporateTaxGridLine, TaxGroup, TaxRepartitionLine, TaxCashBasisEntry, ExchangeRate, ExchangeGainLossEntry, CheckBook, Check } from '@/types'

// ============ Company Settings ============
export async function getCompanySettings(): Promise<CompanySettings | null> {
  const tid = await getTenantId()
  let q = supabase.from('company_settings').select('*').limit(1)
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q.maybeSingle()
  if (error) throw error
  if (!data && tid) {
    // No company_settings row for this tenant — auto-create a default one
    const { data: created, error: createErr } = await supabase
      .from('company_settings')
      .insert({ tenant_id: tid, name: 'Mon Entreprise', country: 'France', currency: 'EUR', fiscal_year_start: '01-01' })
      .select('*')
      .single()
    if (createErr) throw createErr
    return created as CompanySettings
  }
  return data as CompanySettings | null
}

export async function updateCompanySettings(id: string, updates: Partial<CompanySettings>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('company_settings').update(updates), 'company_settings', tid).eq('id', id).select().single()
  if (error) throw error
  return data as CompanySettings
}


// ============ Legislation Packs (global reference, NOT tenant-scoped) ============
export async function getLegislationPacks() {
  const { data, error } = await supabase
    .from('legislation_packs')
    .select('*')
    .eq('active', true)
    .order('country_name', { ascending: true })
  if (error) throw error
  return data as LegislationPack[]
}

export async function getLegislationPack(code: string) {
  const { data, error } = await supabase.from('legislation_packs').select('*').eq('code', code).single()
  if (error) throw error
  return data as LegislationPack
}

// Resolve the pack that applies to the current tenant (from company_settings),
// falling back to the default pack when the tenant has none configured.
export async function getActiveLegislationPack() {
  try {
    const settings = await getCompanySettings()
    if (settings?.legislation_pack_code) {
      return await getLegislationPack(settings.legislation_pack_code)
    }
  } catch (e) {
    // no settings yet — fall through to default
    console.error('getActiveLegislationPack: settings lookup failed:', e)
  }
  const { data, error } = await supabase
    .from('legislation_packs')
    .select('*')
    .eq('is_default', true)
    .limit(1)
    .maybeSingle()
  if (error) throw error
  return (data as LegislationPack) || null
}

// VAT rates in force for a pack at a given date (versioned by effective_from/to).
export async function getApplicableVatRates(packCode: string, atDate: string = new Date().toISOString().slice(0, 10)) {
  if (!/^[A-Za-z0-9_-]{1,20}$/.test(packCode)) throw new Error('Invalid pack code format')
  if (!/^\d{4}-\d{2}-\d{2}$/.test(atDate)) throw new Error('Invalid date format')
  const { data, error } = await supabase
    .from('tax_rates')
    .select('*')
    .eq('pack_code', packCode)
    .lte('effective_from', atDate)
    .or(`effective_to.is.null,effective_to.gte.${atDate}`)
    .order('rate', { ascending: false })
  if (error) throw error
  return data as TaxRate[]
}


// ============ Users ============
// Deprecated: use getTenantUsers(tenantId) instead. Kept for backward compat but now tenant-scoped.
export async function getUsers() {
  const tid = await getTenantId()
  if (!tid) return []
  const { data, error } = await supabase.from('tenant_users').select('*').eq('tenant_id', tid).order('created_at', { ascending: false })
  if (error) throw error
  return data as any[]
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

// SOC-04 : Résout l'exercice courant pour les RPC d'agrégation
// Exercice qui couvre la date du jour ; à défaut, le plus récent déjà commencé, puis le plus récent.
async function getCurrentFiscalYearId(): Promise<string | null> {
  const tid = await getTenantId()
  let q = supabase.from('fiscal_years').select('id, start_date, end_date').order('start_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data } = await q
  const years = (data || []) as Array<{ id: string; start_date: string; end_date: string }>
  const today = new Date().toISOString().slice(0, 10)
  const current = years.find((y) => y.start_date <= today && today <= y.end_date)
    ?? years.find((y) => y.start_date <= today)
    ?? years[0]
  return current ? current.id : null
}

export async function createJournalEntry(entry: Omit<JournalEntry, 'id' | 'created_at' | 'updated_at'> & { lines: Omit<JournalLine, 'id' | 'created_at'>[] }) {
  const { lines, ...entryData } = entry
  // SOC-01/ACC-01 : RPC atomique — entête + lignes dans une seule transaction serveur,
  // numérotation atomique et contrôle d'équilibre par trigger.
  const { data, error } = await supabase.rpc('post_journal_entry', {
    p_entry: entryData,
    p_lines: (lines || []).map((l, i) => ({ ...l, line_order: (l as any).line_order ?? i })),
  })
  if (error) throw error
  const res = data as any
  if (res && res.success === false) throw new Error(res.error || 'Échec de la création de l\'écriture')
  return { ...entryData, id: res?.entry_id, number: res?.number } as unknown as JournalEntry
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
export async function getGeneralLedger(accountCode?: string, opts?: { dateFrom?: string; dateTo?: string; journalCode?: string; limit?: number; offset?: number }) {
  // SOC-04 : Agrégation et pagination côté serveur (évite la truncation silencieuse)
  const fiscalYearId = await getCurrentFiscalYearId()
  const { data, error } = await supabase.rpc('get_general_ledger', {
    p_fiscal_year_id: fiscalYearId,
    p_account_code: accountCode ?? null,
    p_date_from: opts?.dateFrom ?? null,
    p_date_to: opts?.dateTo ?? null,
    p_journal_code: opts?.journalCode ?? null,
    p_limit: opts?.limit ?? 1000,
    p_offset: opts?.offset ?? 0,
  })
  if (error) throw error
  return (data || []) as any[]
}

// --- Analytic ledger lines: lignes imputées analytiquement (bornées, hors périmètre du RPC get_general_ledger) ---
export async function getAnalyticLedgerLines(sectionId?: string, limit = 200) {
  const tid = await getTenantId()
  let q = supabase
    .from('journal_lines')
    .select('id, account_code, description, debit, credit, analytic_section_id, analytic_amount, journal_entries!inner(date)')
    .not('analytic_section_id', 'is', null)
    .order('created_at', { ascending: false })
    .limit(limit)
  if (tid) q = q.eq('tenant_id', tid)
  if (sectionId) q = q.eq('analytic_section_id', sectionId)
  const { data, error } = await q
  if (error) throw error
  return (data || []).map((l: any) => ({
    id: l.id,
    date: l.journal_entries?.date,
    account_code: l.account_code,
    description: l.description,
    debit: l.debit,
    credit: l.credit,
    analytic_section_id: l.analytic_section_id,
    analytic_amount: l.analytic_amount,
  }))
}


// ============ Trial Balance (soldes par compte) ============
export async function getTrialBalance(opts?: { dateFrom?: string; dateTo?: string; journalCode?: string }) {
  // SOC-04 : Agrégation côté serveur (évite la truncation silencieuse et l'effondrement navigateur)
  const fiscalYearId = await getCurrentFiscalYearId()
  const { data, error } = await supabase.rpc('get_trial_balance', {
    p_fiscal_year_id: fiscalYearId,
    p_date_from: opts?.dateFrom ?? null,
    p_date_to: opts?.dateTo ?? null,
    p_journal_code: opts?.journalCode ?? null,
  })
  if (error) throw error
  return (data || []).map((row: any) => ({
    account_code: row.account_code,
    account_name: row.account_name,
    opening_debit: Number(row.opening_debit) || 0,
    opening_credit: Number(row.opening_credit) || 0,
    total_debit: Number(row.period_debit) || 0,
    total_credit: Number(row.period_credit) || 0,
    closing_debit: Number(row.closing_debit) || 0,
    closing_credit: Number(row.closing_credit) || 0,
  })).sort((a: any, b: any) => a.account_code.localeCompare(b.account_code))
}


// ============ Income statement ============
// AUD-D07 : compte de résultat calculé par le serveur sur les écritures validées
// de l'exercice (classes 6 et 7). Remplace les chiffres écrits en dur de ReportsPage.
export interface IncomeStatementRow {
  account_code: string
  account_name: string
  account_type: 'income' | 'expense'
  debit: number
  credit: number
  /** Montant en valeur positive : produit net pour la classe 7, charge nette pour la classe 6 */
  amount: number
}

export async function getIncomeStatement(fiscalYearId: string, opts?: { dateFrom?: string; dateTo?: string }): Promise<IncomeStatementRow[]> {
  const { data, error } = await supabase.rpc('get_income_statement', {
    p_fiscal_year_id: fiscalYearId,
    p_date_from: opts?.dateFrom ?? null,
    p_date_to: opts?.dateTo ?? null,
  })
  if (error) throw error
  return ((data || []) as any[]).map((row) => {
    const debit = Number(row.debit) || 0
    const credit = Number(row.credit) || 0
    const type: 'income' | 'expense' = row.account_type === 'income' ? 'income' : 'expense'
    return {
      account_code: row.account_code,
      account_name: row.account_name,
      account_type: type,
      debit,
      credit,
      amount: type === 'income' ? credit - debit : debit - credit,
    }
  })
}

export interface IncomeStatementMonth {
  month: string
  revenue: number
  expense: number
  result: number
}

export async function getIncomeStatementMonthly(fiscalYearId: string): Promise<IncomeStatementMonth[]> {
  const { data, error } = await supabase.rpc('get_income_statement_monthly', { p_fiscal_year_id: fiscalYearId })
  if (error) throw error
  return ((data || []) as any[]).map((row) => ({
    month: String(row.month),
    revenue: Number(row.revenue) || 0,
    expense: Number(row.expense) || 0,
    result: Number(row.result) || 0,
  }))
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
  if (!tid) return { totalRevenue: 0, outstandingInvoice: 0, outstandingBills: 0, bankBalance: 0, totalDebtors: 0, totalCreditors: 0, invoiceCount: 0, billCount: 0 }
  // LOT7-03 : ces 5 requêtes agrègent des tables entières. Sans pagination, le chiffre
  // d'affaires et les encours s'arrêtaient à 1 000 lignes (max_rows) — un tableau de bord
  // faux, sans message d'erreur.
  const [invoices, purchaseInvoices, bankAccounts, customers, suppliers] = await Promise.all([
    fetchAllRows<any>(supabase.from('invoices').select('total, amount_due, status').eq('tenant_id', tid).order('id'), { label: 'getDashboardStats/invoices' }),
    fetchAllRows<any>(supabase.from('purchase_invoices').select('total, amount_due, status').eq('tenant_id', tid).order('id'), { label: 'getDashboardStats/purchase_invoices' }),
    fetchAllRows<any>(supabase.from('bank_accounts').select('balance').eq('tenant_id', tid).order('id'), { label: 'getDashboardStats/bank_accounts' }),
    fetchAllRows<any>(supabase.from('customers').select('balance').eq('tenant_id', tid).order('id'), { label: 'getDashboardStats/customers' }),
    fetchAllRows<any>(supabase.from('suppliers').select('balance').eq('tenant_id', tid).order('id'), { label: 'getDashboardStats/suppliers' }),
  ])

  // AUD-D09 : chiffre d'affaires = ventes HT comptabilisées de l'exercice en cours (comptes 70),
  // et non plus le TTC des seules factures payées.
  let totalRevenue = 0
  const fyId = await getCurrentFiscalYearId()
  if (fyId) {
    const { data: is, error: isErr } = await supabase.rpc('get_income_statement', {
      p_fiscal_year_id: fyId, p_date_from: null, p_date_to: null,
    })
    if (isErr) throw isErr
    totalRevenue = ((is || []) as any[])
      .filter((r) => String(r.account_code).startsWith('70'))
      .reduce((sum, r) => sum + (Number(r.credit) || 0) - (Number(r.debit) || 0), 0)
  }
  const outstandingInvoice = invoices.filter((i: any) => i.status === 'sent' || i.status === 'overdue' || i.status === 'viewed').reduce((sum: number, i: any) => sum + Number(i.amount_due), 0)
  const outstandingBills = purchaseInvoices.filter((i: any) => i.status !== 'paid' && i.status !== 'cancelled' && i.status !== 'draft').reduce((sum: number, i: any) => sum + Number(i.amount_due), 0)
  const bankBalance = bankAccounts.reduce((sum: number, a: any) => sum + Number(a.balance), 0)
  const totalDebtors = customers.reduce((sum: number, c: any) => sum + Number(c.balance), 0)
  const totalCreditors = suppliers.reduce((sum: number, s: any) => sum + Number(s.balance), 0)

  return {
    totalRevenue,
    outstandingInvoice,
    outstandingBills,
    bankBalance,
    totalDebtors,
    totalCreditors,
    invoiceCount: invoices.length,
    billCount: purchaseInvoices.length,
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
      description: `${inv.customer_name || 'Client'} - ${Number(inv.total).toLocaleString('fr-FR')}`,
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
      description: `${pur.supplier_name || 'Fournisseur'} - ${Number(pur.total).toLocaleString('fr-FR')}`,
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
      description: `${bnk.description} - ${Number(bnk.amount).toLocaleString('fr-FR')}`,
      time: bnk.date,
      color: bnk.type === 'credit' ? 'text-[var(--color-success)]' : 'text-[var(--color-danger)]',
    })
  }

  activities.sort((a, b) => new Date(b.time).getTime() - new Date(a.time).getTime())
  return activities.slice(0, 8)
}


// ============ Balance Sheet ============
export async function getBalanceSheet(opts?: { dateTo?: string; fiscalYearId?: string }) {
  // SOC-04 : Agrégation côté serveur — le RPC renvoie déjà account_type.
  // AUD-D08 : aucun compte n'est écarté (hors plan → « unclassified ») et une ligne
  // RESULTAT porte le résultat tant que l'exercice n'est pas clôturé.
  const fiscalYearId = opts?.fiscalYearId || await getCurrentFiscalYearId()
  const { data, error } = await supabase.rpc('get_balance_sheet', {
    p_fiscal_year_id: fiscalYearId,
    p_date_to: opts?.dateTo ?? null,
  })
  if (error) throw error

  const all = (data || []).map((row: any) => ({
    code: row.account_code,
    name: row.account_name,
    type: row.account_type || 'unclassified',
    debit: Number(row.debit) || 0,
    credit: Number(row.credit) || 0,
    balance: Number(row.balance) || 0,
  }))
  const placed = new Set(['asset', 'liability', 'equity'])

  return {
    assets: all.filter((a: any) => a.type === 'asset'),
    liabilities: all.filter((a: any) => a.type === 'liability'),
    equity: all.filter((a: any) => a.type === 'equity'),
    unclassified: all.filter((a: any) => !placed.has(a.type)),
    // Σ des soldes de toutes les lignes : nul quand actif = passif + capitaux + résultat
    gap: Math.round(all.reduce((s: number, a: any) => s + a.balance, 0) * 100) / 100,
  }
}


// ============ Cash Flow ============
export async function getCashFlow() {
  const tid = await getTenantId()
  let cfQ = supabase
    .from('bank_transactions')
    .select('date, type, amount, description')
    .order('date', { ascending: true })
    .order('id')
  if (tid) cfQ = cfQ.eq('tenant_id', tid)
  // LOT7-03 : agrégat de trésorerie sur toutes les opérations bancaires — pagination obligatoire.
  const bankTxns = await fetchAllRows<any>(cfQ, { label: 'getCashFlow/bank_transactions' })

  const inflow = bankTxns.filter((t: any) => t.type === 'credit').reduce((s: number, t: any) => s + Number(t.amount), 0)
  const outflow = bankTxns.filter((t: any) => t.type === 'debit').reduce((s: number, t: any) => s + Number(t.amount), 0)

  const byMonth = new Map<string, { inflow: number; outflow: number }>()
  for (const t of bankTxns) {
    const month = (t as any).date?.substring(0, 7) || 'unknown'
    if (!byMonth.has(month)) byMonth.set(month, { inflow: 0, outflow: 0 })
    const entry = byMonth.get(month)!
    if ((t as any).type === 'credit') entry.inflow += Number((t as any).amount)
    else entry.outflow += Number((t as any).amount)
  }

  return { inflow, outflow, net: inflow - outflow, byMonth: Array.from(byMonth.entries()).map(([month, v]) => ({ month, ...v })) }
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

/**
 * Dotation aux amortissements d'un exercice (R-01) : écriture D 681x / C 28x
 * validée, historique `asset_depreciations` et valeur nette mis à jour.
 * Renvoie l'identifiant de l'écriture, ou `null` s'il n'y a rien à amortir.
 */
export async function generateDepreciationEntry(assetId: string, fiscalYearId: string) {
  const { data, error } = await supabase.rpc('generate_depreciation_entry', {
    p_fixed_asset_id: assetId,
    p_fiscal_year_id: fiscalYearId,
  })
  if (error) throw error
  return data as string | null
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
    // LOT7-03 : les lignes postérieures à la période sont ignorées par la boucle — autant
    // ne pas les rapatrier. Le reste (antérieur) sert au calcul de l'ancien solde.
    .lte('journal_entries.date', periodEnd)
    .order('id')
  if (tid) jpbQ = jpbQ.eq('tenant_id', tid)
  let data: any[]
  try {
    data = await fetchAllRows<any>(jpbQ, { label: 'getJournalPeriodBalance/journal_lines' })
  } catch (error) {
    console.warn('getJournalPeriodBalance failed:', (error as { message?: string })?.message)
    return empty
  }
  let ancien = 0, mvtD = 0, mvtC = 0
  for (const l of data) {
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

// --- Saisie: create entry with lines ---
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
  currency_code?: string
  functional_currency?: string
  exchange_rate?: number
  exchange_rate_date?: string | null
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
  // ACC-01 : Numérotation atomique côté serveur (évite les doublons en concurrence)
  const { data, error } = await supabase.rpc('get_next_piece_number', { p_journal_code: journalCode })
  if (error) throw error
  return (data as string) || `${journalCode}-0001`
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
  return data as (JournalLine & { journal_entries: Joined<'journal_entries', 'number' | 'date' | 'journal_code' | 'description'> })[]
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
  return data as (JournalLine & { journal_entries: Joined<'journal_entries', 'number' | 'date' | 'journal_code' | 'description'> })[]
}

// --- Lettrage: apply lettrage code to multiple lines ---
// LOT4-08/09 : RPC serveur — contrôle d'équilibre débit/crédit et numérotation atomique
export async function applyLettrage(lineIds: string[], code: string) {
  const { data, error } = await supabase.rpc('apply_lettrage', { p_line_ids: lineIds, p_code: code })
  if (error) throw error
  const res = data as any
  if (res && res.success === false) throw new Error(res.error || 'Échec du lettrage')
  return res
}

// --- Lettrage: remove lettrage (delettrer) ---
export async function removeLettrage(lineIds: string[]) {
  const { data, error } = await supabase.rpc('remove_lettrage', { p_line_ids: lineIds })
  if (error) throw error
  const res = data as any
  if (res && res.success === false) throw new Error(res.error || 'Échec du délettrage')
  return res
}

// --- Lettrage: get next lettrage code ---
export async function getNextLettrageCode() {
  const { data, error } = await supabase.rpc('next_lettrage_code')
  if (error) throw error
  return (data as string) || 'A001'
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
  page?: number
  pageSize?: number
}) {
  const tid = await getTenantId()
  // ACC-02/DAT-01 : Pagination bornée côté serveur (.range + count exact)
  const page = criteria.page ?? 0
  const pageSize = Math.min(criteria.pageSize ?? 100, 500)
  let query = supabase
    .from('journal_entries')
    .select('*, journal_lines(*)', { count: 'exact' })
    .order('date', { ascending: false })
  if (tid) query = query.eq('tenant_id', tid)

  if (criteria.journalCode) query = query.eq('journal_code', criteria.journalCode)
  if (criteria.dateFrom) query = query.gte('date', criteria.dateFrom)
  if (criteria.dateTo) query = query.lte('date', criteria.dateTo)
  if (criteria.pieceNumber) query = query.ilike('piece_number', `%${criteria.pieceNumber.replace(/[%_]/g, '\\$&')}%`)
  if (criteria.description) query = query.ilike('description', `%${criteria.description.replace(/[%_]/g, '\\$&')}%`)

  const { data, error, count } = await query.range(page * pageSize, page * pageSize + pageSize - 1)
  if (error) throw error

  let results = (data || []) as JournalEntry[]

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

  return { data: results, count: count ?? results.length, page, pageSize }
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
    .order('id')
  if (tid) abQ = abQ.eq('tenant_id', tid)
  // LOT7-03 : la balance âgée doit voir TOUTES les lignes non lettrées, sinon les encours
  // les plus anciens disparaissent silencieusement au-delà de 1 000 lignes.
  const lines = await fetchAllRows<any>(abQ, { label: 'getAgedBalance/journal_lines' })

  let tpQ = supabase.from('third_party_accounts').select('*').order('id')
  if (tid) tpQ = tpQ.eq('tenant_id', tid)
  const tiers = await fetchAllRows<any>(tpQ, { label: 'getAgedBalance/third_party_accounts' })

  const tiersMap = new Map(tiers.map((t) => [t.code, t]))
  const referenceDate = refDate ? new Date(refDate) : new Date()

  const byTiers: Record<string, {
    code: string; name: string; type: string; total: number
    bucket0_30: number; bucket31_60: number; bucket61_90: number; bucket90p: number
  }> = {}

  for (const line of lines) {
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
      // LOT7-04 : `issue_date` n'existe pas sur `invoices` (colonne `date`) — PostgREST
      // renvoyait 400/42703 et l'échéancier client était vide. Vérifié sur PostgREST 16.3.
      .select('id, number, date, due_date, total, customer_name, status')
      .neq('status', 'paid')
      .neq('status', 'cancelled')
      .order('due_date', { ascending: true })
      .order('id')
    if (tid) ecQ = ecQ.eq('tenant_id', tid)
    // LOT7-03 : l'échéancier doit lister TOUTES les factures ouvertes.
    const invoices = await fetchAllRows<any>(ecQ, { label: 'getEcheancier/invoices' })
    for (const inv of invoices) {
      const remaining = Number(inv.total) || 0
      if (remaining <= 0) continue
      const due = new Date(inv.due_date)
      const daysOverdue = Math.floor((Date.now() - due.getTime()) / (1000 * 60 * 60 * 24))
      results.push({
        type: 'customer', number: inv.number, date: inv.date, due_date: inv.due_date,
        amount: Number(inv.total) || 0, paid: 0, remaining,
        third_party_name: inv.customer_name || '—', days_overdue: daysOverdue > 0 ? daysOverdue : 0,
      })
    }
  }

  if (!typeFilter || typeFilter === 'supplier') {
    let esQ = supabase
      .from('purchase_invoices')
      // LOT7-04 : `purchase_invoices` porte `number` et `date`, pas `invoice_number` /
      // `invoice_date` — même défaut, l'échéancier fournisseur était vide lui aussi.
      .select('id, number, date, due_date, total, supplier_name, status')
      .neq('status', 'paid')
      .neq('status', 'cancelled')
      .order('due_date', { ascending: true })
      .order('id')
    if (tid) esQ = esQ.eq('tenant_id', tid)
    const pinvoices = await fetchAllRows<any>(esQ, { label: 'getEcheancier/purchase_invoices' })
    for (const inv of pinvoices) {
      const remaining = Number(inv.total) || 0
      if (remaining <= 0) continue
      const due = new Date(inv.due_date)
      const daysOverdue = Math.floor((Date.now() - due.getTime()) / (1000 * 60 * 60 * 24))
      results.push({
        type: 'supplier', number: inv.number, date: inv.date, due_date: inv.due_date,
        amount: Number(inv.total) || 0, paid: 0, remaining,
        third_party_name: inv.supplier_name || '—', days_overdue: daysOverdue > 0 ? daysOverdue : 0,
      })
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
    .order('id')
  if (tid) query = query.eq('tenant_id', tid)

  if (dateFrom) query = query.gte('journal_entries.date', dateFrom)
  if (dateTo) query = query.lte('journal_entries.date', dateTo)

  // LOT7-03 : grand livre auxiliaire — un compte tiers actif dépasse vite 1 000 lignes.
  return await fetchAllRows<any>(query, { label: 'getGrandLivreTiers/journal_lines' })
}

// --- FEC Export: all entries + lines for a fiscal year ---
// LOT7-03 : l'export FEC doit être EXHAUSTIF (art. A47 A-1 du LPF). PostgREST rabote à
// max_rows = 1000 sans erreur : sans pagination, un exercice de plus de 1 000 écritures
// produisait un fichier légal silencieusement amputé. `.order('id')` complète le tri sur
// `date` pour le rendre total — sinon la pagination saute ou double des écritures.
export async function getFECData(fiscalYearId: string) {
  const tid = await getTenantId()
  // AUD-C08/C11 : écritures validées de l'exercice (fiscal_year_id est renseigné par le
  // serveur, avec ou sans découpage en périodes), dans l'ordre de leur numéro définitif.
  let feQ = supabase.from('journal_entries').select('*, journal_lines(*)')
    .eq('fiscal_year_id', fiscalYearId)
    .eq('status', 'posted')
    .order('date', { ascending: true })
    .order('journal_code', { ascending: true })
    .order('posting_seq', { ascending: true })
    .order('id')
  if (tid) feQ = feQ.eq('tenant_id', tid)
  const entries = await fetchAllRows<JournalEntry>(feQ, { label: 'getFECData/journal_entries' })

  return entries
}

// --- SIG: balances for class 6/7 accounts ---
// AUD-D09 : agrégation serveur par les dates de l'exercice, écritures validées seulement,
// hors écritures de clôture (journal CL). L'ancien filtre sur fiscal_period_id rendait
// un SIG vide dès qu'il existait des périodes, et tout l'historique (brouillards compris) sinon.
export async function getSIGData(fiscalYearId?: string) {
  const fyId = fiscalYearId || await getCurrentFiscalYearId()
  if (!fyId) return []
  const { data, error } = await supabase.rpc('get_income_statement', {
    p_fiscal_year_id: fyId,
    p_date_from: null,
    p_date_to: null,
  })
  if (error) throw error
  return ((data || []) as any[]).map((row) => ({
    code: row.account_code as string,
    name: (row.account_name as string) || '—',
    debit: Number(row.debit) || 0,
    credit: Number(row.credit) || 0,
    solde: Number(row.balance) || 0,
  }))
}

// --- Analytic Balance: journal_lines by analytic_section_id ---
export async function getAnalyticBalance() {
  const tid = await getTenantId()
  let abQ2 = supabase
    .from('journal_lines')
    .select('analytic_section_id, analytic_amount, debit, credit, account_code, account_general')
    .not('analytic_section_id', 'is', null)
    .order('id')
  if (tid) abQ2 = abQ2.eq('tenant_id', tid)
  // LOT7-03 : balance analytique = agrégat par section sur tout l'historique.
  const lines = await fetchAllRows<any>(abQ2, { label: 'getAnalyticBalance/journal_lines' })

  let asQ = supabase.from('analytic_sections').select('*').order('id')
  if (tid) asQ = asQ.eq('tenant_id', tid)
  const sections = await fetchAllRows<any>(asQ, { label: 'getAnalyticBalance/analytic_sections' })

  const sectionMap = new Map(sections.map((s) => [s.id, s]))

  const bySection: Record<string, {
    sectionId: string; sectionCode: string; sectionName: string
    totalDebit: number; totalCredit: number; totalAnalytic: number
  }> = {}

  for (const line of lines) {
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
// ACC-05 : RPC atomique — détermination du résultat, écriture de clôture, report à nouveau
// (classes 6/7 exclues des à-nouveaux), hash d'intégrité et journalisation.
export async function closeFiscalYear(fiscalYearId: string, newFiscalYearId?: string, carryForward = true) {
  const { data, error } = await supabase.rpc('close_fiscal_year', {
    p_fiscal_year_id: fiscalYearId,
    p_next_fiscal_year_id: newFiscalYearId ?? null,
    p_carry_forward: carryForward,
  })
  if (error) throw error
  const res = data as any
  if (res && res.success === false) throw new Error(res.error || 'Échec de la clôture')
  return res as {
    success: boolean
    fiscal_year_id: string
    result: number
    result_account?: string
    carry_forward_entry_id?: string
    close_entry_id?: string
    hash?: string
    log_id?: string
  }
}

// --- Affectation du résultat (décision n° 3 : obligatoire avant la clôture suivante) ---
export type ResultAllocationLine = { account: string; amount: number }

/** Exercices clos dont le résultat attend son affectation (la clôture suivante est bloquée). */
export function pendingResultAllocations(years: FiscalYear[]): FiscalYear[] {
  return years
    .filter((y) => y.status !== 'open' && y.closing_result != null && Number(y.closing_result) !== 0 && !y.result_allocated_at)
    .sort((a, b) => a.start_date.localeCompare(b.start_date))
}

export async function allocateResult(fiscalYearId: string, lines: ResultAllocationLine[], date?: string | null) {
  const { data, error } = await supabase.rpc('allocate_result', {
    p_fiscal_year_id: fiscalYearId,
    p_allocation: lines.map((l) => ({ account: l.account, amount: Math.round(l.amount * 100) / 100 })),
    p_date: date || null,
    p_description: null,
  })
  if (error) throw error
  const res = data as any
  if (res && res.success === false) throw new Error(res.error || 'Échec de l\'affectation du résultat')
  return res as { success: true; entry_id: string; fiscal_year_id: string; result: number; date: string }
}

// --- VAT auto-calc from journal lines (accounts 4456x / 4457x) ---
export async function calcVatFromEntries(dateFrom: string, dateTo: string) {
  // ACC-02 : TVA multi-taux agrégée côté serveur par code de TVA (base HT + montant)
  const fiscalYearId = await getCurrentFiscalYearId()
  const { data: rows, error } = await supabase.rpc('get_vat_summary_by_code', {
    p_fiscal_year_id: fiscalYearId,
    p_date_from: dateFrom,
    p_date_to: dateTo,
  })
  if (error) throw error

  let outputVat = 0
  let inputVat = 0
  let totalSales = 0
  let totalPurchases = 0
  const byCode: Array<{ vat_code: string; direction: string; ca3_box: string; rate: number; base_ht: number; vat_amount: number }> = []

  for (const row of (rows || []) as any[]) {
    const baseHt = Number(row.base_ht) || 0
    const vatAmount = Number(row.vat_amount) || 0
    byCode.push({ vat_code: row.vat_code, direction: row.direction, ca3_box: row.ca3_box, rate: Number(row.rate) || 0, base_ht: baseHt, vat_amount: vatAmount })
    if (row.direction === 'collected') { outputVat += vatAmount; totalSales += baseHt }
    else if (row.direction === 'deductible') { inputVat += vatAmount; totalPurchases += baseHt }
  }

  return {
    outputVat: Math.max(0, outputVat),
    inputVat: Math.max(0, inputVat),
    netVat: outputVat - inputVat,
    totalSales: Math.max(0, totalSales),
    totalPurchases: Math.max(0, totalPurchases),
    byCode, // ACC-02 : détail par code/taux de TVA pour la CA3
  }
}

// --- General Ledger with filters (journal, period, date range) ---
export async function getGeneralLedgerFiltered(accountCode: string, filters?: {
  journalCode?: string
  dateFrom?: string
  dateTo?: string
  ifrsMode?: boolean
}) {
  if (!/^[0-9A-Za-z._ -]{1,20}$/.test(accountCode)) throw new Error('Invalid account code format')
  const tid = await getTenantId()
  let query = supabase
    .from('journal_lines')
    .select('*, journal_entries!inner(number, date, journal_code, description, reference, piece_number, ifrs_mode)')
    .or(`account_code.eq.${accountCode},account_general.eq.${accountCode}`)
    .order('created_at', { ascending: true })
    .order('id')
  if (tid) query = query.eq('tenant_id', tid)

  if (filters?.journalCode) query = query.eq('journal_entries.journal_code', filters.journalCode)
  if (filters?.dateFrom) query = query.gte('journal_entries.date', filters.dateFrom)
  if (filters?.dateTo) query = query.lte('journal_entries.date', filters.dateTo)
  if (filters?.ifrsMode !== undefined) query = query.eq('journal_entries.ifrs_mode', filters.ifrsMode)

  // LOT7-03 : le `.limit(100000)` d'origine ne servait à rien — PostgREST rabote toujours
  // à max_rows = 1000. Le grand livre s'arrêtait donc à 1 000 lignes sans le dire.
  return await fetchAllRows<any>(query, { label: 'getGeneralLedgerFiltered/journal_lines' })
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
    .order('id')
  if (tid) query = query.eq('tenant_id', tid)

  if (filters?.dateFrom) query = query.gte('journal_entries.date', filters.dateFrom)
  if (filters?.dateTo) query = query.lte('journal_entries.date', filters.dateTo)
  if (filters?.journalCode) query = query.eq('journal_entries.journal_code', filters.journalCode)

  // LOT7-03 : idem, `.limit(100000)` inopérant. Une balance tronquée est une balance FAUSSE
  // (elle ne s'équilibre plus), et rien ne le signalait.
  const data = await fetchAllRows<any>(query, { label: 'getTrialBalanceFiltered/journal_lines' })

  const balances: Record<string, { account_code: string; total_debit: number; total_credit: number }> = {}

  for (const line of data) {
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
  let accQ = supabase.from('bank_accounts').select('*').order('name').order('id')
  if (tid) accQ = accQ.eq('tenant_id', tid)
  // LOT7-03 : le solde de trésorerie somme tous les comptes bancaires.
  const accounts = await fetchAllRows<any>(accQ, { label: 'getTreasuryDashboard/bank_accounts' })

  const totalBalance = accounts.reduce((s, a) => s + Number(a.balance), 0)

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
    .order('id')
  if (tid) inQ = inQ.eq('tenant_id', tid)
  const incoming = await fetchAllRows<any>(inQ, { label: 'getTreasuryDashboard/invoices' })

  let outQ = supabase
    .from('purchase_invoices')
    .select('total, due_date, status')
    .in('status', ['received', 'overdue'])
    .gte('due_date', today.toISOString().split('T')[0])
    .lte('due_date', in90.toISOString().split('T')[0])
    .order('id')
  if (tid) outQ = outQ.eq('tenant_id', tid)
  const outgoing = await fetchAllRows<any>(outQ, { label: 'getTreasuryDashboard/purchase_invoices' })

  const forecastBuckets = [
    { label: '0-30j', incoming: 0, outgoing: 0 },
    { label: '31-60j', incoming: 0, outgoing: 0 },
    { label: '61-90j', incoming: 0, outgoing: 0 },
  ]

  for (const inv of incoming) {
    const due = new Date(inv.due_date)
    const days = Math.floor((due.getTime() - today.getTime()) / 86400000)
    if (days <= 30) forecastBuckets[0].incoming += Number(inv.total)
    else if (days <= 60) forecastBuckets[1].incoming += Number(inv.total)
    else forecastBuckets[2].incoming += Number(inv.total)
  }

  for (const inv of outgoing) {
    const due = new Date(inv.due_date)
    const days = Math.floor((due.getTime() - today.getTime()) / 86400000)
    if (days <= 30) forecastBuckets[0].outgoing += Number(inv.total)
    else if (days <= 60) forecastBuckets[1].outgoing += Number(inv.total)
    else forecastBuckets[2].outgoing += Number(inv.total)
  }

  let ppQ = supabase.from('payment_orders').select('*').in('status', ['draft', 'approved']).order('id')
  if (tid) ppQ = ppQ.eq('tenant_id', tid)
  const pendingPayments = await fetchAllRows<any>(ppQ, { label: 'getTreasuryDashboard/payment_orders' })

  return {
    accounts,
    totalBalance,
    forecastBuckets,
    pendingPayments,
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
    .order('id')
  if (tid) invQ = invQ.eq('tenant_id', tid)
  // LOT7-03 : la courbe de trésorerie prévisionnelle doit intégrer toutes les échéances.
  const invoices = await fetchAllRows<any>(invQ, { label: 'getTreasuryForecast/invoices' })

  let purQ = supabase
    .from('purchase_invoices')
    .select('number, total, due_date, supplier_id, status')
    .in('status', ['received', 'overdue'])
    .gte('due_date', today.toISOString().split('T')[0])
    .lte('due_date', end.toISOString().split('T')[0])
    .order('due_date')
    .order('id')
  if (tid) purQ = purQ.eq('tenant_id', tid)
  const purchaseInvoices = await fetchAllRows<any>(purQ, { label: 'getTreasuryForecast/purchase_invoices' })

  let baQ = supabase.from('bank_accounts').select('balance').order('id')
  if (tid) baQ = baQ.eq('tenant_id', tid)
  const bankAccounts = await fetchAllRows<any>(baQ, { label: 'getTreasuryForecast/bank_accounts' })
  const currentBalance = bankAccounts.reduce((s, a) => s + Number(a.balance), 0)

  const events: Array<{ date: string; type: 'in' | 'out'; amount: number; reference: string }> = []
  for (const inv of invoices) {
    events.push({ date: inv.due_date, type: 'in', amount: Number(inv.total), reference: inv.number })
  }
  for (const inv of purchaseInvoices) {
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
      let journalCode = 'VT'
      let accountDebit = '411000'
      let accountCredit = '707000'
      if (item.type === 'purchase') { journalCode = 'AC'; accountDebit = '607000'; accountCredit = '401000' }
      else if (item.type === 'customer_payment') { journalCode = 'BQ'; accountDebit = '512000'; accountCredit = '411000' }
      else if (item.type === 'supplier_payment') { journalCode = 'BQ'; accountDebit = '401000'; accountCredit = '512000' }

      // ACC-01.7 : Idempotence — ne pas retransférer un document déjà comptabilisé
      const sourceTable = item.type === 'sales' ? 'invoices'
        : item.type === 'purchase' ? 'purchase_invoices'
        : item.type === 'customer_payment' ? 'customer_payments'
        : 'supplier_payments'
      let srcQ = supabase.from(sourceTable).select('transferred_entry_id').eq('id', item.id)
      if (tid) srcQ = srcQ.eq('tenant_id', tid)
      const { data: source } = await srcQ.single()
      if (source?.transferred_entry_id) {
        results.push({ success: true, number: item.number, error: 'Déjà transféré' })
        continue
      }

      // SOC-01/ACC-01 : RPC atomique — entête et lignes dans une seule transaction
      const entryNumber = `${journalCode}-${item.number}`
      const { data: rpcRes, error: rpcErr } = await supabase.rpc('post_journal_entry', {
        p_entry: { number: entryNumber, date: item.date, journal_code: journalCode, status: 'draft', invoice_ref: item.number },
        p_lines: [
          { account_code: accountDebit, account_general: accountDebit, debit: item.amount, credit: 0, description: item.number, line_order: 0 },
          { account_code: accountCredit, account_general: accountCredit, debit: 0, credit: item.amount, description: item.number, line_order: 1 },
        ],
      })
      if (rpcErr) throw rpcErr
      const res = rpcRes as any
      if (res?.success === false) throw new Error(res.error || 'Échec du transfert')

      // Marquer la source comme transférée (idempotence)
      await tud(supabase.from(sourceTable).update({ transferred_entry_id: res?.entry_id }), sourceTable, tid).eq('id', item.id)

      results.push({ success: true, number: item.number })
    } catch (err: any) {
      results.push({ success: false, number: item.number, error: err.message })
    }
  }
  return results
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
  return data as AuditLog[]
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
  // AUD-G08 (G20) : budgets.account_code est un code libre, sans clé étrangère vers
  // chart_accounts — le libellé du compte est chargé à part.
  let q = supabase.from('budgets').select('*, fiscal_years(code)').order('name').order('id')
  if (tid) q = q.eq('tenant_id', tid)
  if (fiscalYearId) q = q.eq('fiscal_year_id', fiscalYearId)
  // LOT7-03 : suivi budgétaire — le réalisé est une somme sur toutes les lignes du compte.
  const budgets = await fetchAllRows<any>(q, { label: 'getBudgetTracking/budgets' })
  const codes = [...new Set(budgets.map((b: any) => b.account_code).filter(Boolean))]
  if (codes.length > 0) {
    let aq = supabase.from('chart_accounts').select('code, name').in('code', codes).order('code')
    if (tid) aq = aq.eq('tenant_id', tid)
    const accounts = await fetchAllRows<{ code: string; name: string }>(aq, { label: 'getBudgetTracking/chart_accounts' })
    const byCode = new Map(accounts.map(a => [a.code, a]))
    for (const b of budgets) b.chart_accounts = byCode.get(b.account_code) ?? null
  }

  const results: any[] = []
  for (const b of budgets) {
    let jlQ = supabase
      .from('journal_lines')
      .select('debit, credit')
      .eq('account_general', b.account_code)
      .order('id')
    if (tid) jlQ = jlQ.eq('tenant_id', tid)
    const lines = await fetchAllRows<any>(jlQ, { label: 'getBudgetTracking/journal_lines' })
    const realized = lines.reduce((s, l) => s + Number(l.debit) - Number(l.credit), 0)

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
    const commitments = await fetchAllRows<any>(commitQ.order('id'), { label: 'getBudgetTracking/budget_commitments' })
    committed = commitments.reduce((s, c) => s + Number(c.amount), 0)

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
  // LOT7-03 : contrôle d'engagement budgétaire. Un réalisé tronqué à 1 000 lignes laisse
  // passer des dépassements de budget sans alerte.
  const budgets = await fetchAllRows<any>(bq.order('id'), { label: 'checkBudgetAvailability/budgets' })

  const budgetTotal = budgets.reduce((s, b) =>
    s + ['period_1','period_2','period_3','period_4','period_5','period_6','period_7','period_8','period_9','period_10','period_11','period_12']
      .reduce((acc, k) => acc + Number((b as any)[k] || 0), 0), 0)

  let jlQ2 = supabase
    .from('journal_lines')
    .select('debit, credit')
    .eq('account_general', accountCode)
    .order('id')
  if (tid) jlQ2 = jlQ2.eq('tenant_id', tid)
  const lines = await fetchAllRows<any>(jlQ2, { label: 'checkBudgetAvailability/journal_lines' })
  const realized = lines.reduce((s, l) => s + Number(l.debit) - Number(l.credit), 0)

  let commitQ2 = supabase
    .from('budget_commitments')
    .select('amount')
    .eq('account_code', accountCode)
    .eq('status', 'active')
  if (tid) commitQ2 = commitQ2.eq('tenant_id', tid)
  if (fiscalYearId) commitQ2 = commitQ2.eq('fiscal_year_id', fiscalYearId)
  const commitments = await fetchAllRows<any>(commitQ2.order('id'), { label: 'checkBudgetAvailability/budget_commitments' })
  const committed = commitments.reduce((s, c) => s + Number(c.amount), 0)

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
  if (!tid) return { revenue: 0, expenses: 0, margin: 0, marginPct: 0, cashPosition: 0, pendingEntries: 0, totalEntries: 0, invoiceCount: 0, supplierInvoiceCount: 0 }
  // LOT7-03 : CA, charges et nombre d'écritures étaient plafonnés à 1 000 lignes chacun.
  const [invoices, purchaseInvoices, bankAccounts, journalEntries] = await Promise.all([
    fetchAllRows<any>(supabase.from('invoices').select('total, status, date').eq('status', 'paid').eq('tenant_id', tid).order('id'), { label: 'getFinancialDashboard/invoices' }),
    fetchAllRows<any>(supabase.from('purchase_invoices').select('total, status, date').eq('status', 'paid').eq('tenant_id', tid).order('id'), { label: 'getFinancialDashboard/purchase_invoices' }),
    fetchAllRows<any>(supabase.from('bank_accounts').select('balance, type').eq('tenant_id', tid).order('id'), { label: 'getFinancialDashboard/bank_accounts' }),
    fetchAllRows<any>(supabase.from('journal_entries').select('number, date, status').eq('tenant_id', tid).order('id'), { label: 'getFinancialDashboard/journal_entries' }),
  ])

  const revenue = invoices.reduce((s, i) => s + Number(i.total), 0)
  const expenses = purchaseInvoices.reduce((s, i) => s + Number(i.total), 0)
  const cashPosition = bankAccounts.reduce((s, a) => s + Number(a.balance), 0)
  const margin = revenue - expenses
  const marginPct = revenue > 0 ? (margin / revenue) * 100 : 0

  return {
    revenue,
    expenses,
    margin,
    marginPct,
    cashPosition,
    pendingEntries: journalEntries.filter((e) => e.status === 'draft').length,
    totalEntries: journalEntries.length,
    invoiceCount: invoices.length,
    supplierInvoiceCount: purchaseInvoices.length,
  }
}


// ============ Recurring Entries (Écritures d'abonnement) ============
export async function getRecurringEntries() {
  const tid = await getTenantId()
  let q = supabase.from('recurring_entries').select('*').order('next_generation_date', { ascending: true })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as RecurringEntry[]
}

export async function createRecurringEntry(entry: Omit<RecurringEntry, 'id' | 'tenant_id' | 'created_at' | 'updated_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase
    .from('recurring_entries')
    .insert({ ...entry, tenant_id: tid })
    .select()
    .single()
  if (error) throw error
  return data as RecurringEntry
}

export async function updateRecurringEntry(id: string, updates: Partial<RecurringEntry>) {
  const tid = await getTenantId()
  const { data, error } = await supabase
    .from('recurring_entries')
    .update({ ...updates, updated_at: new Date().toISOString() })
    .eq('id', id)
    .eq('tenant_id', tid ?? '')
    .select()
    .single()
  if (error) throw error
  return data as RecurringEntry
}

export async function deleteRecurringEntry(id: string) {
  const tid = await getTenantId()
  const { error } = await supabase
    .from('recurring_entries')
    .delete()
    .eq('id', id)
    .eq('tenant_id', tid ?? '')
  if (error) throw error
}

export async function generateRecurringEntry(id: string) {
  const tid = await getTenantId()
  const { data, error } = await supabase
    .rpc('generate_recurring_entry', { p_entry_id: id, p_tenant_id: tid })
  if (error) throw error
  return data
}


// ============ Regularization Entries (CCA/PCA/PRC/CRC) ============
export async function getRegularizationEntries(type?: string) {
  const tid = await getTenantId()
  let q = supabase.from('regularization_entries').select('*').order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (type) q = q.eq('type', type)
  const { data, error } = await q
  if (error) throw error
  return data as RegularizationEntry[]
}

export async function createRegularizationEntry(entry: Omit<RegularizationEntry, 'id' | 'tenant_id' | 'created_at' | 'updated_at' | 'used_amount' | 'remaining_amount' | 'created_entry_id' | 'extourne_entry_id'>) {
  const tid = await getTenantId()
  const payload = { ...entry, tenant_id: tid, used_amount: 0, remaining_amount: entry.amount }
  const { data, error } = await supabase
    .from('regularization_entries')
    .insert(payload)
    .select()
    .single()
  if (error) throw error
  return data as RegularizationEntry
}

export async function updateRegularizationEntry(id: string, updates: Partial<RegularizationEntry>) {
  const tid = await getTenantId()
  const { data, error } = await supabase
    .from('regularization_entries')
    .update({ ...updates, updated_at: new Date().toISOString() })
    .eq('id', id)
    .eq('tenant_id', tid ?? '')
    .select()
    .single()
  if (error) throw error
  return data as RegularizationEntry
}

export async function deleteRegularizationEntry(id: string) {
  const tid = await getTenantId()
  const { error } = await supabase
    .from('regularization_entries')
    .delete()
    .eq('id', id)
    .eq('tenant_id', tid ?? '')
  if (error) throw error
}


// ============ Currency Revaluation ============
export async function getCurrencyRevaluations() {
  const tid = await getTenantId()
  let q = supabase.from('currency_revaluations').select('*').order('period_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as CurrencyRevaluation[]
}

export async function createCurrencyRevaluation(entry: Omit<CurrencyRevaluation, 'id' | 'tenant_id' | 'created_at' | 'updated_at' | 'entry_id'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase
    .from('currency_revaluations')
    .insert({ ...entry, tenant_id: tid })
    .select()
    .single()
  if (error) throw error
  return data as CurrencyRevaluation
}

export async function updateCurrencyRevaluation(id: string, updates: Partial<CurrencyRevaluation>): Promise<CurrencyRevaluation> {
  const tid = await getTenantId()
  const { data, error } = await supabase
    .from('currency_revaluations')
    .update({ ...updates, updated_at: new Date().toISOString() })
    .eq('id', id)
    .eq('tenant_id', tid ?? '')
    .select()
    .single()
  if (error) throw error
  return data as CurrencyRevaluation
}

export async function deleteCurrencyRevaluation(id: string) {
  const tid = await getTenantId()
  const { error } = await supabase
    .from('currency_revaluations')
    .delete()
    .eq('id', id)
    .eq('tenant_id', tid ?? '')
  if (error) throw error
}


// ============ Analytic Plans ============
export async function getAnalyticPlans() {
  const tid = await getTenantId()
  let q = supabase.from('analytic_plans').select('*').order('code', { ascending: true })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as AnalyticPlan[]
}

export async function createAnalyticPlan(plan: Omit<AnalyticPlan, 'id' | 'tenant_id' | 'created_at' | 'updated_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase
    .from('analytic_plans')
    .insert({ ...plan, tenant_id: tid })
    .select()
    .single()
  if (error) throw error
  return data as AnalyticPlan
}

export async function updateAnalyticPlan(id: string, updates: Partial<AnalyticPlan>): Promise<AnalyticPlan> {
  const tid = await getTenantId()
  const { data, error } = await supabase
    .from('analytic_plans')
    .update({ ...updates, updated_at: new Date().toISOString() })
    .eq('id', id)
    .eq('tenant_id', tid ?? '')
    .select()
    .single()
  if (error) throw error
  return data as AnalyticPlan
}

export async function deleteAnalyticPlan(id: string) {
  const tid = await getTenantId()
  const { error } = await supabase
    .from('analytic_plans')
    .delete()
    .eq('id', id)
    .eq('tenant_id', tid ?? '')
  if (error) throw error
}


// ============ Distribution Grills ============
export async function getDistributionGrills() {
  const tid = await getTenantId()
  let q = supabase.from('distribution_grills').select('*, lines:distribution_grill_lines(*)').order('name', { ascending: true })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as any[] as DistributionGrill[]
}

export async function createDistributionGrill(grill: Omit<DistributionGrill, 'id' | 'tenant_id' | 'created_at' | 'updated_at' | 'lines'> & { lines: Omit<DistributionGrillLine, 'id' | 'grill_id' | 'created_at'>[] }) {
  const tid = await getTenantId()
  const { lines, ...grillData } = grill
  const { data, error } = await supabase
    .from('distribution_grills')
    .insert({ ...grillData, tenant_id: tid })
    .select()
    .single()
  if (error) throw error
  const grillId = (data as any).id
  if (lines && lines.length > 0) {
    const { error: lineError } = await supabase
      .from('distribution_grill_lines')
      .insert(lines.map(l => ({ ...l, grill_id: grillId })))
    if (lineError) throw lineError
  }
  return data
}

export async function deleteDistributionGrill(id: string) {
  const tid = await getTenantId()
  const { error } = await supabase
    .from('distribution_grills')
    .delete()
    .eq('id', id)
    .eq('tenant_id', tid ?? '')
  if (error) throw error
}


// ============ Bank Reconciliation Rules (AFB) ============
export async function getBankReconciliationRules() {
  const tid = await getTenantId()
  let q = supabase.from('bank_reconciliation_rules').select('*').order('priority', { ascending: true })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as BankReconciliationRule[]
}

export async function createBankReconciliationRule(rule: Omit<BankReconciliationRule, 'id' | 'tenant_id' | 'created_at' | 'updated_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase
    .from('bank_reconciliation_rules')
    .insert({ ...rule, tenant_id: tid })
    .select()
    .single()
  if (error) throw error
  return data as BankReconciliationRule
}

export async function deleteBankReconciliationRule(id: string) {
  const tid = await getTenantId()
  if (!tid) throw new Error('No tenant context')
  const { error } = await supabase
    .from('bank_reconciliation_rules')
    .delete()
    .eq('id', id)
    .eq('tenant_id', tid)
  if (error) throw error
}


// ============ Bank Statement Imports ============
export async function getBankStatementImports() {
  const tid = await getTenantId()
  let q = supabase.from('bank_statement_imports').select('*').order('imported_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as BankStatementImport[]
}

export async function createBankStatementImport(imp: Omit<BankStatementImport, 'id' | 'tenant_id' | 'imported_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase
    .from('bank_statement_imports')
    .insert({ ...imp, tenant_id: tid })
    .select()
    .single()
  if (error) throw error
  return data as BankStatementImport
}


// ============ TVS (Taxe Véhicules de Société) ============
export async function getTvsDeclarations() {
  const tid = await getTenantId()
  let q = supabase.from('tvs_declarations').select('*').order('fiscal_year', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as TvsDeclaration[]
}

export async function createTvsDeclaration(decl: Omit<TvsDeclaration, 'id' | 'tenant_id' | 'created_at' | 'updated_at' | 'filed_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase
    .from('tvs_declarations')
    .insert({ ...decl, tenant_id: tid })
    .select()
    .single()
  if (error) throw error
  return data as TvsDeclaration
}

export async function deleteTvsDeclaration(id: string) {
  const tid = await getTenantId()
  if (!tid) throw new Error('No tenant context')
  const { error } = await supabase
    .from('tvs_declarations')
    .delete()
    .eq('id', id)
    .eq('tenant_id', tid)
  if (error) throw error
}


// ============ Fiscal Backups ============
export async function getFiscalBackups() {
  const tid = await getTenantId()
  let q = supabase.from('fiscal_backups').select('*').order('created_at', { ascending: false }).order('id')
  if (tid) q = q.eq('tenant_id', tid)
  // LOT7-03 : piste d'audit fiscale — la liste des sauvegardes doit être complète.
  return await fetchAllRows<FiscalBackup>(q, { label: 'getFiscalBackups' })
}

export async function createFiscalBackup(backup: Omit<FiscalBackup, 'id' | 'tenant_id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase
    .from('fiscal_backups')
    .insert({ ...backup, tenant_id: tid })
    .select()
    .single()
  if (error) throw error
  return data as FiscalBackup
}

export async function deleteFiscalBackup(id: string) {
  const tid = await getTenantId()
  if (!tid) throw new Error('No tenant context')
  const { error } = await supabase
    .from('fiscal_backups')
    .delete()
    .eq('id', id)
    .eq('tenant_id', tid)
  if (error) throw error
}


// ============ Phase 2: Recurring Invoice Templates ============
export async function getRecurringInvoiceTemplates() {
  const tid = await getTenantId()
  let q = supabase.from('recurring_invoice_templates').select('*, customers(name)').order('name')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as (RecurringInvoiceTemplate & { customers: Joined<'customers', 'name'> })[]
}
export async function createRecurringInvoiceTemplate(t: Omit<RecurringInvoiceTemplate, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('recurring_invoice_templates').insert(ti(t, 'recurring_invoice_templates', tid)).select().single()
  if (error) throw error
  return data as RecurringInvoiceTemplate
}
export async function deleteRecurringInvoiceTemplate(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('recurring_invoice_templates').delete(), 'recurring_invoice_templates', tid).eq('id', id)
  if (error) throw error
}


// ============ Phase 3: Treasury — MCF ============
export async function getFutureAccountingMovements() {
  const tid = await getTenantId()
  let q = supabase.from('future_accounting_movements').select('*').order('expected_date')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as FutureAccountingMovement[]
}
export async function createFutureAccountingMovement(m: Omit<FutureAccountingMovement, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('future_accounting_movements').insert(ti(m, 'future_accounting_movements', tid)).select().single()
  if (error) throw error
  return data as FutureAccountingMovement
}
export async function updateFutureAccountingMovement(id: string, updates: Partial<FutureAccountingMovement>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('future_accounting_movements').update(updates), 'future_accounting_movements', tid).eq('id', id).select().single()
  if (error) throw error
  return data as FutureAccountingMovement
}
export async function deleteFutureAccountingMovement(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('future_accounting_movements').delete(), 'future_accounting_movements', tid).eq('id', id)
  if (error) throw error
}


// ============ Phase 3: Treasury Transfers ============
export async function getTreasuryTransfers() {
  const tid = await getTenantId()
  let q = supabase.from('treasury_transfers').select('*, ba1:bank_accounts!treasury_transfers_from_account_id_fkey(name), ba2:bank_accounts!treasury_transfers_to_account_id_fkey(name)').order('transfer_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as (TreasuryTransfer & { ba1: Joined<'bank_accounts', 'name'>; ba2: Joined<'bank_accounts', 'name'> })[]
}
export async function createTreasuryTransfer(t: Omit<TreasuryTransfer, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('treasury_transfers').insert(ti(t, 'treasury_transfers', tid)).select().single()
  if (error) throw error
  return data as TreasuryTransfer
}
export async function updateTreasuryTransfer(id: string, updates: Partial<TreasuryTransfer>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('treasury_transfers').update(updates), 'treasury_transfers', tid).eq('id', id).select().single()
  if (error) throw error
  return data as TreasuryTransfer
}
export async function deleteTreasuryTransfer(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('treasury_transfers').delete(), 'treasury_transfers', tid).eq('id', id)
  if (error) throw error
}


// ============ Phase 3: Treasury Recurring ============
export async function getTreasuryRecurring() {
  const tid = await getTenantId()
  let q = supabase.from('treasury_recurring').select('*, bank_accounts(name)').order('next_date')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as (TreasuryRecurring & { bank_accounts: Joined<'bank_accounts', 'name'> })[]
}
export async function createTreasuryRecurring(t: Omit<TreasuryRecurring, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('treasury_recurring').insert(ti(t, 'treasury_recurring', tid)).select().single()
  if (error) throw error
  return data as TreasuryRecurring
}
export async function deleteTreasuryRecurring(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('treasury_recurring').delete(), 'treasury_recurring', tid).eq('id', id)
  if (error) throw error
}


// ============ Phase 3: Consolidated Treasury ============
export async function getConsolidatedTreasury() {
  const tid = await getTenantId()
  let q = supabase.from('consolidated_treasury').select('*').order('consolidation_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as ConsolidatedTreasury[]
}


// ============ Phase 5: Asset Depreciation Plans ============
export async function getAssetDepreciationPlans(assetId?: string) {
  const tid = await getTenantId()
  let q = supabase.from('asset_depreciation_plans').select('*, fixed_assets(name)')
  if (tid) q = q.eq('tenant_id', tid)
  if (assetId) q = q.eq('asset_id', assetId)
  const { data, error } = await q
  if (error) throw error
  return data as (AssetDepreciationPlan & { fixed_assets: Joined<'fixed_assets', 'name'> })[]
}
export async function createAssetDepreciationPlan(p: Omit<AssetDepreciationPlan, 'id' | 'created_at' | 'updated_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('asset_depreciation_plans').insert(ti(p, 'asset_depreciation_plans', tid)).select().single()
  if (error) throw error
  return data as AssetDepreciationPlan
}
export async function updateAssetDepreciationPlan(id: string, updates: Partial<AssetDepreciationPlan>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('asset_depreciation_plans').update(updates), 'asset_depreciation_plans', tid).eq('id', id).select().single()
  if (error) throw error
  return data as AssetDepreciationPlan
}


// ============ Phase 6: Accounting Features ============

// --- Auto Label Rules ---
export async function getAutoLabelRules() {
  const tid = await getTenantId()
  let q = supabase.from('auto_label_rules').select('*').order('priority', { ascending: true })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as AutoLabelRule[]
}
export async function createAutoLabelRule(r: Omit<AutoLabelRule, 'id' | 'tenant_id' | 'created_at' | 'updated_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('auto_label_rules').insert({ ...r, tenant_id: tid }).select().single()
  if (error) throw error
  return data as AutoLabelRule
}
export async function updateAutoLabelRule(id: string, updates: Partial<AutoLabelRule>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('auto_label_rules').update(updates), 'auto_label_rules', tid).eq('id', id).select().single()
  if (error) throw error
  return data as AutoLabelRule
}
export async function deleteAutoLabelRule(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('auto_label_rules').delete(), 'auto_label_rules', tid).eq('id', id)
  if (error) throw error
}

// --- Extourne Log ---
export async function getExtourneLogs() {
  const tid = await getTenantId()
  let q = supabase.from('extourne_log').select('*').order('extourne_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as ExtourneLog[]
}
export async function createExtourneLog(e: Omit<ExtourneLog, 'id' | 'tenant_id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('extourne_log').insert({ ...e, tenant_id: tid }).select().single()
  if (error) throw error
  return data as ExtourneLog
}

// --- Carry Forward Log ---
export async function getCarryForwardLogs() {
  const tid = await getTenantId()
  let q = supabase.from('carry_forward_log').select('*').order('carry_forward_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as CarryForwardLog[]
}
export async function createCarryForwardLog(c: Omit<CarryForwardLog, 'id' | 'tenant_id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('carry_forward_log').insert({ ...c, tenant_id: tid }).select().single()
  if (error) throw error
  return data as CarryForwardLog
}

// --- Lettrage Differences ---
export async function getLettrageDifferences() {
  const tid = await getTenantId()
  let q = supabase.from('lettrage_differences').select('*').order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as LettrageDifference[]
}
export async function createLettrageDifference(d: Omit<LettrageDifference, 'id' | 'tenant_id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('lettrage_differences').insert({ ...d, tenant_id: tid }).select().single()
  if (error) throw error
  return data as LettrageDifference
}
export async function updateLettrageDifference(id: string, updates: Partial<LettrageDifference>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('lettrage_differences').update(updates), 'lettrage_differences', tid).eq('id', id).select().single()
  if (error) throw error
  return data as LettrageDifference
}
export async function deleteLettrageDifference(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('lettrage_differences').delete(), 'lettrage_differences', tid).eq('id', id)
  if (error) throw error
}

// --- Accounting Control Runs ---
export async function getAccountingControlRuns() {
  const tid = await getTenantId()
  let q = supabase.from('accounting_control_runs').select('*').order('run_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as AccountingControlRun[]
}
export async function createAccountingControlRun(c: Omit<AccountingControlRun, 'id' | 'tenant_id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('accounting_control_runs').insert({ ...c, tenant_id: tid }).select().single()
  if (error) throw error
  return data as AccountingControlRun
}

// --- Cash Control Sessions ---
export async function getCashControlSessions() {
  const tid = await getTenantId()
  let q = supabase.from('cash_control_sessions').select('*').order('session_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as CashControlSession[]
}
export async function createCashControlSession(c: Omit<CashControlSession, 'id' | 'tenant_id' | 'created_at' | 'updated_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('cash_control_sessions').insert({ ...c, tenant_id: tid }).select().single()
  if (error) throw error
  return data as CashControlSession
}
export async function updateCashControlSession(id: string, updates: Partial<CashControlSession>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('cash_control_sessions').update(updates), 'cash_control_sessions', tid).eq('id', id).select().single()
  if (error) throw error
  return data as CashControlSession
}
export async function deleteCashControlSession(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('cash_control_sessions').delete(), 'cash_control_sessions', tid).eq('id', id)
  if (error) throw error
}

// --- FEC Attestations ---
export async function getFECAttestations() {
  const tid = await getTenantId()
  let q = supabase.from('fec_attestations').select('*').order('attestation_date', { ascending: false }).order('id')
  if (tid) q = q.eq('tenant_id', tid)
  // LOT7-03 : pièce justificative de l'export FEC — la liste doit être complète.
  return await fetchAllRows<FECAttestation>(q, { label: 'getFECAttestations' })
}
export async function createFECAttestation(a: Omit<FECAttestation, 'id' | 'tenant_id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('fec_attestations').insert({ ...a, tenant_id: tid }).select().single()
  if (error) throw error
  return data as FECAttestation
}
export async function deleteFECAttestation(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('fec_attestations').delete(), 'fec_attestations', tid).eq('id', id)
  if (error) throw error
}

// --- Tier RIBs ---
export async function getTierRIBs(thirdPartyAccountId?: string) {
  const tid = await getTenantId()
  let q = supabase.from('tier_ribs').select('*').order('is_default', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (thirdPartyAccountId) q = q.eq('third_party_account_id', thirdPartyAccountId)
  const { data, error } = await q
  if (error) throw error
  return data as TierRIB[]
}
export async function createTierRIB(r: Omit<TierRIB, 'id' | 'tenant_id' | 'created_at' | 'updated_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('tier_ribs').insert({ ...r, tenant_id: tid }).select().single()
  if (error) throw error
  return data as TierRIB
}
export async function updateTierRIB(id: string, updates: Partial<TierRIB>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('tier_ribs').update(updates), 'tier_ribs', tid).eq('id', id).select().single()
  if (error) throw error
  return data as TierRIB
}
export async function deleteTierRIB(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('tier_ribs').delete(), 'tier_ribs', tid).eq('id', id)
  if (error) throw error
}

// --- IFRS Adjustments ---
export async function getIFRSAdjustments() {
  const tid = await getTenantId()
  let q = supabase.from('ifrs_adjustments').select('*').order('adjustment_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as IFRSAdjustment[]
}
export async function createIFRSAdjustment(a: Omit<IFRSAdjustment, 'id' | 'tenant_id' | 'created_at' | 'updated_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('ifrs_adjustments').insert({ ...a, tenant_id: tid }).select().single()
  if (error) throw error
  return data as IFRSAdjustment
}
export async function updateIFRSAdjustment(id: string, updates: Partial<IFRSAdjustment>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('ifrs_adjustments').update(updates), 'ifrs_adjustments', tid).eq('id', id).select().single()
  if (error) throw error
  return data as IFRSAdjustment
}
export async function deleteIFRSAdjustment(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('ifrs_adjustments').delete(), 'ifrs_adjustments', tid).eq('id', id)
  if (error) throw error
}

// --- Tax Payments ---
export async function getTaxPayments() {
  const tid = await getTenantId()
  let q = supabase.from('tax_payments').select('*').order('payment_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as TaxPayment[]
}
export async function createTaxPayment(p: Omit<TaxPayment, 'id' | 'tenant_id' | 'created_at' | 'updated_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('tax_payments').insert({ ...p, tenant_id: tid }).select().single()
  if (error) throw error
  return data as TaxPayment
}
export async function updateTaxPayment(id: string, updates: Partial<TaxPayment>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('tax_payments').update(updates), 'tax_payments', tid).eq('id', id).select().single()
  if (error) throw error
  return data as TaxPayment
}
export async function deleteTaxPayment(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('tax_payments').delete(), 'tax_payments', tid).eq('id', id)
  if (error) throw error
}

// --- Custom Report Templates ---
export async function getCustomReportTemplates() {
  const tid = await getTenantId()
  let q = supabase.from('custom_report_templates').select('*').order('name', { ascending: true })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as CustomReportTemplate[]
}
export async function createCustomReportTemplate(t: Omit<CustomReportTemplate, 'id' | 'tenant_id' | 'created_at' | 'updated_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('custom_report_templates').insert({ ...t, tenant_id: tid }).select().single()
  if (error) throw error
  return data as CustomReportTemplate
}
export async function updateCustomReportTemplate(id: string, updates: Partial<CustomReportTemplate>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('custom_report_templates').update(updates), 'custom_report_templates', tid).eq('id', id).select().single()
  if (error) throw error
  return data as CustomReportTemplate
}
export async function deleteCustomReportTemplate(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('custom_report_templates').delete(), 'custom_report_templates', tid).eq('id', id)
  if (error) throw error
}

// --- Deferred Printing Jobs ---
export async function getDeferredPrintingJobs() {
  const tid = await getTenantId()
  let q = supabase.from('deferred_printing_jobs').select('*').order('scheduled_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as DeferredPrintingJob[]
}
export async function createDeferredPrintingJob(j: Omit<DeferredPrintingJob, 'id' | 'tenant_id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('deferred_printing_jobs').insert({ ...j, tenant_id: tid }).select().single()
  if (error) throw error
  return data as DeferredPrintingJob
}
export async function updateDeferredPrintingJob(id: string, updates: Partial<DeferredPrintingJob>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('deferred_printing_jobs').update(updates), 'deferred_printing_jobs', tid).eq('id', id).select().single()
  if (error) throw error
  return data as DeferredPrintingJob
}
export async function deleteDeferredPrintingJob(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('deferred_printing_jobs').delete(), 'deferred_printing_jobs', tid).eq('id', id)
  if (error) throw error
}

// --- Journal Access Rights ---
export async function getJournalAccessRights() {
  const tid = await getTenantId()
  // AUD-G08 (G21) : user_id n'a pas de clé étrangère vers tenant_users — les
  // courriels sont chargés à part (user_id = identifiant d'authentification ou de membre)
  let q = supabase.from('journal_access_rights').select('*').order('journal_code', { ascending: true })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  let uq = supabase.from('tenant_users').select('id, auth_id, email').order('id')
  if (tid) uq = uq.eq('tenant_id', tid)
  const { data: users, error: uErr } = await uq
  if (uErr) throw uErr
  const emailOf = new Map<string, string>()
  for (const u of users || []) {
    if (u.auth_id) emailOf.set(u.auth_id, u.email)
    emailOf.set(u.id, u.email)
  }
  return (data || []).map(r => ({ ...r, tenant_users: emailOf.has(r.user_id) ? { email: emailOf.get(r.user_id)! } : null })) as
    (JournalAccessRight & { tenant_users: Joined<'tenant_users', 'email'> })[]
}
export async function createJournalAccessRight(r: Omit<JournalAccessRight, 'id' | 'tenant_id' | 'created_at' | 'updated_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('journal_access_rights').insert({ ...r, tenant_id: tid }).select().single()
  if (error) throw error
  return data as JournalAccessRight
}
export async function updateJournalAccessRight(id: string, updates: Partial<JournalAccessRight>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('journal_access_rights').update(updates), 'journal_access_rights', tid).eq('id', id).select().single()
  if (error) throw error
  return data as JournalAccessRight
}
export async function deleteJournalAccessRight(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('journal_access_rights').delete(), 'journal_access_rights', tid).eq('id', id)
  if (error) throw error
}

// --- VAT on Collections ---
export async function getVATOnCollections() {
  const tid = await getTenantId()
  let q = supabase.from('vat_on_collections').select('*').order('period_start', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as VATOnCollection[]
}
export async function createVATOnCollection(v: Omit<VATOnCollection, 'id' | 'tenant_id' | 'created_at' | 'updated_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('vat_on_collections').insert({ ...v, tenant_id: tid }).select().single()
  if (error) throw error
  return data as VATOnCollection
}
export async function updateVATOnCollection(id: string, updates: Partial<VATOnCollection>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('vat_on_collections').update(updates), 'vat_on_collections', tid).eq('id', id).select().single()
  if (error) throw error
  return data as VATOnCollection
}
export async function deleteVATOnCollection(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('vat_on_collections').delete(), 'vat_on_collections', tid).eq('id', id)
  if (error) throw error
}

// --- Batch Entry Sessions ---
export async function getBatchEntrySessions() {
  const tid = await getTenantId()
  let q = supabase.from('batch_entry_sessions').select('*').order('session_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as BatchEntrySession[]
}
export async function createBatchEntrySession(b: Omit<BatchEntrySession, 'id' | 'tenant_id' | 'created_at' | 'updated_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('batch_entry_sessions').insert({ ...b, tenant_id: tid }).select().single()
  if (error) throw error
  return data as BatchEntrySession
}
export async function updateBatchEntrySession(id: string, updates: Partial<BatchEntrySession>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('batch_entry_sessions').update(updates), 'batch_entry_sessions', tid).eq('id', id).select().single()
  if (error) throw error
  return data as BatchEntrySession
}
export async function deleteBatchEntrySession(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('batch_entry_sessions').delete(), 'batch_entry_sessions', tid).eq('id', id)
  if (error) throw error
}

// --- Extourne: create reversal entry from original ---
export async function generateExtourne(originalEntryId: string, reason: string) {
  const tid = await getTenantId()
  let q = supabase.from('journal_entries').select('*, journal_lines(*)').eq('id', originalEntryId)
  if (tid) q = q.eq('tenant_id', tid)
  const { data: original, error: e1 } = await q.single()
  if (e1) throw e1

  // LOT4-10 : numérotation séquentielle continue (RPC 146), plus d'horodatage
  const { data: extourneNumber, error: eNum } = await supabase.rpc('get_next_document_number', { p_prefix: 'EXT' })
  if (eNum) throw eNum
  const { data: newEntry, error: e2 } = await supabase.from('journal_entries').insert({
    tenant_id: tid,
    number: extourneNumber,
    date: new Date().toISOString().slice(0, 10),
    description: `Extourne: ${original.description}`,
    reference: original.reference || '',
    // AUD-C02 : une écriture naît en brouillard ; elle est validée après ses lignes
    status: 'draft',
    journal_code: original.journal_code,
    piece_number: `EXT-${original.piece_number || original.number}`,
  }).select().single()
  if (e2) throw e2

  const reversedLines = (original.journal_lines || []).map((l: any) => ({
    tenant_id: tid,
    journal_id: newEntry.id,
    account_code: l.account_code,
    account_general: l.account_general,
    account_tiers: l.account_tiers,
    account_name: l.account_name,
    debit: l.credit,
    credit: l.debit,
    description: `Extourne: ${l.description || ''}`,
    line_order: l.line_order,
    piece_number: `EXT-${l.piece_number || ''}`,
  }))
  if (reversedLines.length) {
    const { error: e3 } = await supabase.from('journal_lines').insert(reversedLines)
    if (e3) throw e3
  }
  const { error: ePost } = await supabase.from('journal_entries').update({ status: 'posted' }).eq('id', newEntry.id)
  if (ePost) throw ePost

  await createExtourneLog({
    original_entry_id: originalEntryId,
    extourne_entry_id: newEntry.id,
    extourne_date: new Date().toISOString().slice(0, 10),
    reason,
    journal_code: original.journal_code || null,
    total_debit: original.total_credit,
    total_credit: original.total_debit,
    status: 'completed',
  })

  return newEntry
}

// --- Carry Forward: generate reports à-nouveaux ---
export async function generateCarryForward(sourceFiscalYearId: string, targetFiscalYearId: string) {
  const tid = await getTenantId()

  // Un seul report par exercice source (close_fiscal_year en génère déjà un)
  let logQ = supabase.from('carry_forward_log').select('id').eq('source_fiscal_year_id', sourceFiscalYearId).eq('status', 'completed').limit(1)
  if (tid) logQ = logQ.eq('tenant_id', tid)
  const { data: existingLogs, error: eLog } = await logQ
  if (eLog) throw eLog
  if (existingLogs && existingLogs.length > 0) throw new Error('Les à-nouveaux de cet exercice ont déjà été générés')

  const fecData = await getFECData(sourceFiscalYearId)
  // Solde par compte général + compte tiers (les tiers sont reportés ligne à ligne)
  const balanceMap = new Map<string, { account: string; tiers: string | null; debit: number; credit: number }>()
  let result = 0 // produits (classe 7) − charges (classe 6)
  for (const entry of fecData) {
    if (entry.status !== 'posted') continue
    for (const line of entry.journal_lines || []) {
      const account = line.account_general || line.account_code
      if (!account) continue
      const debit = Number(line.debit) || 0
      const credit = Number(line.credit) || 0
      // LOT4-01 : les classes 6 et 7 sont soldées dans le résultat, jamais reportées
      if (account.startsWith('6') || account.startsWith('7')) {
        result += credit - debit
        continue
      }
      const tiers = line.account_tiers || null
      const key = `${account}|${tiers ?? ''}`
      const existing = balanceMap.get(key) || { account, tiers, debit: 0, credit: 0 }
      existing.debit += debit
      existing.credit += credit
      balanceMap.set(key, existing)
    }
  }
  const resultAccount = result >= 0 ? '120000' : '129000'
  if (Math.abs(result) >= 0.01) {
    const key = `${resultAccount}|`
    const existing = balanceMap.get(key) || { account: resultAccount, tiers: null, debit: 0, credit: 0 }
    if (result > 0) existing.credit += result
    else existing.debit += -result
    balanceMap.set(key, existing)
  }

  const anLines: any[] = []
  let totalDebit = 0, totalCredit = 0
  for (const { account, tiers, debit, credit } of balanceMap.values()) {
    const solde = debit - credit
    if (Math.abs(solde) < 0.01) continue
    const base = { tenant_id: tid, account_code: account, account_general: account, account_tiers: tiers, description: 'Report à-nouveau', line_order: anLines.length + 1 }
    if (solde > 0) {
      anLines.push({ ...base, debit: solde, credit: 0 })
      totalDebit += solde
    } else {
      anLines.push({ ...base, debit: 0, credit: -solde })
      totalCredit += -solde
    }
  }
  if (anLines.length === 0) return null

  // LOT4-10 : numérotation séquentielle continue (RPC 146)
  const { data: anNumber, error: eNum } = await supabase.rpc('get_next_document_number', { p_prefix: 'AN' })
  if (eNum) throw eNum

  // Les à-nouveaux sont datés du premier jour de l'exercice cible (et non du jour de saisie)
  let tfyQ = supabase.from('fiscal_years').select('start_date').eq('id', targetFiscalYearId)
  if (tid) tfyQ = tfyQ.eq('tenant_id', tid)
  const { data: targetFy, error: eFy } = await tfyQ.single()
  if (eFy) throw eFy

  // AUD-C02 : brouillard, lignes, puis validation
  const { data: newEntry, error } = await supabase.from('journal_entries').insert({
    tenant_id: tid,
    number: anNumber,
    date: (targetFy as any).start_date,
    description: 'Reports à-nouveaux',
    reference: 'AN',
    status: 'draft',
    journal_code: 'AN',
    piece_number: 'AN-OUV',
  }).select().single()
  if (error) throw error

  const linesWithEntry = anLines.map(l => ({ ...l, journal_id: newEntry.id }))
  const { error: e2 } = await supabase.from('journal_lines').insert(linesWithEntry)
  if (e2) throw e2
  const { error: ePost } = await supabase.from('journal_entries').update({ status: 'posted' }).eq('id', newEntry.id)
  if (ePost) throw ePost

  await createCarryForwardLog({
    source_fiscal_year_id: sourceFiscalYearId,
    target_fiscal_year_id: targetFiscalYearId,
    carry_forward_date: new Date().toISOString().slice(0, 10),
    total_debit: totalDebit,
    total_credit: totalCredit,
    entry_count: anLines.length,
    status: 'completed',
    journal_entry_id: newEntry.id,
  })

  return newEntry
}

// --- Accounting Control Run: detect anomalies ---
export async function runAccountingControl(controlType: string, fiscalYearId?: string) {
  const tid = await getTenantId()
  const errors: any[] = []
  const warnings: any[] = []
  let totalChecks = 0

  let jeQ = supabase.from('journal_entries').select('*, journal_lines(*)').order('id')
  if (tid) jeQ = jeQ.eq('tenant_id', tid)
  // LOT7-03 : contrôle de cohérence comptable. Tronqué à 1 000 écritures, il déclarait
  // « aucune anomalie » alors que les écritures suivantes n'avaient jamais été examinées.
  const entries = await fetchAllRows<any>(jeQ, { label: 'runAccountingControl/journal_entries' })

  for (const entry of entries) {
    totalChecks++
    const totalD = (entry.journal_lines || []).reduce((s: number, l: any) => s + Number(l.debit || 0), 0)
    const totalC = (entry.journal_lines || []).reduce((s: number, l: any) => s + Number(l.credit || 0), 0)
    if (Math.abs(totalD - totalC) > 0.01) {
      errors.push({ type: 'unbalanced', entry_number: entry.number, debit: totalD, credit: totalC, difference: totalD - totalC })
    }
    if (!entry.journal_lines || entry.journal_lines.length < 2) {
      warnings.push({ type: 'single_line', entry_number: entry.number })
    }
    for (const line of entry.journal_lines || []) {
      if (!line.account_code && !line.account_general) {
        errors.push({ type: 'missing_account', entry_number: entry.number, line_id: line.id })
      }
    }
  }

  // Check for duplicates
  totalChecks++
  const numberMap = new Map<string, number>()
  for (const e of entries || []) {
    const key = `${e.journal_code}-${e.piece_number || e.number}`
    numberMap.set(key, (numberMap.get(key) || 0) + 1)
  }
  for (const [key, count] of numberMap) {
    if (count > 1) {
      errors.push({ type: 'duplicate_piece', key, count })
    }
  }

  // Check tiers non lettrés
  totalChecks++
  let lq = supabase.from('journal_lines').select('id, account_tiers, lettrage_code, debit, credit').not('account_tiers', 'is', null).is('lettrage_code', null)
  if (tid) lq = lq.eq('tenant_id', tid)
  const { data: unlettered } = await lq
  if (unlettered && unlettered.length > 0) {
    warnings.push({ type: 'unlettered_tiers', count: unlettered.length })
  }

  const result = {
    control_type: controlType,
    fiscal_year_id: fiscalYearId || null,
    period_id: null,
    run_date: new Date().toISOString(),
    status: 'completed',
    total_checks: totalChecks,
    errors_found: errors.length,
    warnings_found: warnings.length,
    details: [...errors, ...warnings],
  }
  return await createAccountingControlRun(result)
}


// ============ Phase 7A: Critical Features ============

// --- Calculate VAT from HT or TTC amount ---
export function calculateVAT(amount: number, vatRate: number, mode: 'ht' | 'ttc' = 'ht'): { ht: number; tva: number; ttc: number } {
  if (mode === 'ht') {
    const ht = amount
    const tva = ht * (vatRate / 100)
    const ttc = ht + tva
    return { ht: Math.round(ht * 100) / 100, tva: Math.round(tva * 100) / 100, ttc: Math.round(ttc * 100) / 100 }
  } else {
    const ttc = amount
    const ht = ttc / (1 + vatRate / 100)
    const tva = ttc - ht
    return { ht: Math.round(ht * 100) / 100, tva: Math.round(tva * 100) / 100, ttc: Math.round(ttc * 100) / 100 }
  }
}

// --- Apply auto label rules to generate a label ---
export async function applyAutoLabelRules(
  journalCode: string,
  accountCode: string,
  accountTiers: string | null,
  pieceNumber: string,
  date: string
): Promise<string | null> {
  const rules = await getAutoLabelRules()
  for (const rule of rules) {
    if (!rule.active) continue
    if (rule.journal_code && rule.journal_code !== journalCode) continue
    if (rule.account_code && rule.account_code !== accountCode) continue
    if (rule.account_prefix && !accountCode.startsWith(rule.account_prefix)) continue
    let label = rule.label_pattern
    label = label.replace(/\{\{numero\}\}/g, pieceNumber || '')
    label = label.replace(/\{\{tiers\}\}/g, accountTiers || '')
    label = label.replace(/\{\{date\}\}/g, date || '')
    label = label.replace(/\{\{compte\}\}/g, accountCode || '')
    return label
  }
  return null
}

// --- Calculate echeance date based on payment term ---
export async function calculateEcheance(date: string, paymentTermId: string | null): Promise<string | null> {
  if (!paymentTermId) return null
  const term = await getPaymentTermById(paymentTermId)
  if (!term) return null

  const baseDate = new Date(date)
  if (term.type === 'fixed') {
    const echeance = new Date(baseDate)
    echeance.setDate(echeance.getDate() + term.days_1)
    return echeance.toISOString().slice(0, 10)
  } else if (term.type === 'end_of_month') {
    const echeance = new Date(baseDate)
    echeance.setDate(echeance.getDate() + term.days_1)
    // Set to end of month
    echeance.setMonth(echeance.getMonth() + 1, 0)
    return echeance.toISOString().slice(0, 10)
  } else if (term.type === 'split') {
    // Return first echeance only (caller handles multi-echeance)
    const echeance = new Date(baseDate)
    echeance.setDate(echeance.getDate() + term.days_1)
    return echeance.toISOString().slice(0, 10)
  }
  return null
}

// --- Get authorized journals for a user ---
export async function getAuthorizedJournals(userId?: string): Promise<Journal[]> {
  const tid = await getTenantId()
  if (!userId) {
    // No user filtering — return all journals
    return getJournals()
  }
  // Check journal_access_rights for this user
  let rightsQ = supabase
    .from('journal_access_rights')
    .select('journal_code, can_view, can_create')
    .eq('user_id', userId)
  if (tid) rightsQ = rightsQ.eq('tenant_id', tid)
  const { data: rights, error } = await rightsQ
  if (error || !rights || rights.length === 0) {
    // No rights defined — return all journals (open access by default)
    return getJournals()
  }
  const allowedCodes = rights.filter((r: any) => r.can_view !== false).map((r: any) => r.journal_code)
  const allJournals = await getJournals()
  return allJournals.filter((j) => allowedCodes.includes(j.code))
}


// ============ Tax Rates (enriched CRUD) ============

export async function getTaxRates(): Promise<TaxRate[]> {
  const tid = await getTenantId()
  let q = supabase.from('tax_rates').select('*').order('rate', { ascending: false })
  if (tid) q = q.or(`tenant_id.is.null,tenant_id.eq.${tid}`)
  const { data, error } = await q
  if (error) throw error
  return data as TaxRate[]
}

export async function createTaxRate(tr: Omit<TaxRate, 'id' | 'created_at' | 'tenant_id'>): Promise<TaxRate> {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('tax_rates').insert({ ...tr, tenant_id: tid }).select().single()
  if (error) throw error
  return data as TaxRate
}

export async function updateTaxRate(id: string, updates: Partial<TaxRate>): Promise<TaxRate> {
  const { data, error } = await supabase.from('tax_rates').update(updates).eq('id', id).select().single()
  if (error) throw error
  return data as TaxRate
}

export async function deleteTaxRate(id: string): Promise<void> {
  const { error } = await supabase.from('tax_rates').delete().eq('id', id)
  if (error) throw error
}


// ============ Tax Groups (#11) ============

export async function getTaxGroups(): Promise<TaxGroup[]> {
  const tid = await getTenantId()
  let q = supabase.from('tax_groups').select('*').order('name', { ascending: true })
  if (tid) q = q.or(`tenant_id.is.null,tenant_id.eq.${tid}`)
  const { data, error } = await q
  if (error) throw error
  return data as TaxGroup[]
}

export async function createTaxGroup(tg: Omit<TaxGroup, 'id' | 'created_at' | 'tenant_id'>): Promise<TaxGroup> {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('tax_groups').insert({ ...tg, tenant_id: tid }).select().single()
  if (error) throw error
  return data as TaxGroup
}

export async function deleteTaxGroup(id: string): Promise<void> {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('tax_groups').delete(), 'tax_groups', tid).eq('id', id)
  if (error) throw error
}


// ============ Tax Repartition Lines (#18) ============

export async function getTaxRepartitionLines(taxId: string): Promise<TaxRepartitionLine[]> {
  const tid = await getTenantId()
  let q = supabase.from('tax_repartition_lines').select('*').eq('tax_id', taxId).order('repartition_type', { ascending: true })
  if (tid) q = q.or(`tenant_id.is.null,tenant_id.eq.${tid}`)
  const { data, error } = await q
  if (error) throw error
  return data as TaxRepartitionLine[]
}

export async function createTaxRepartitionLine(line: Omit<TaxRepartitionLine, 'id' | 'created_at' | 'tenant_id'>): Promise<TaxRepartitionLine> {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('tax_repartition_lines').insert({ ...line, tenant_id: tid }).select().single()
  if (error) throw error
  return data as TaxRepartitionLine
}

export async function deleteTaxRepartitionLine(id: string): Promise<void> {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('tax_repartition_lines').delete(), 'tax_repartition_lines', tid).eq('id', id)
  if (error) throw error
}


// ============ Tax Cash Basis Entries (#20) ============

export async function getTaxCashBasisEntries(): Promise<TaxCashBasisEntry[]> {
  const tid = await getTenantId()
  let q = supabase.from('tax_cash_basis_entries').select('*').order('created_at', { ascending: false })
  if (tid) q = q.or(`tenant_id.is.null,tenant_id.eq.${tid}`)
  const { data, error } = await q
  if (error) throw error
  return data as TaxCashBasisEntry[]
}

export async function createTaxCashBasisEntry(entry: Omit<TaxCashBasisEntry, 'id' | 'created_at' | 'tenant_id'>): Promise<TaxCashBasisEntry> {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('tax_cash_basis_entries').insert({ ...entry, tenant_id: tid }).select().single()
  if (error) throw error
  return data as TaxCashBasisEntry
}

export async function updateTaxCashBasisEntry(id: string, updates: Partial<TaxCashBasisEntry>): Promise<void> {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('tax_cash_basis_entries').update(updates), 'tax_cash_basis_entries', tid).eq('id', id)
  if (error) throw error
}


// ============ Phase 7C: Dashboard Widgets ============

export async function getDashboardWidgets(userId: string): Promise<DashboardWidget[]> {
  const tid = await getTenantId()
  let q = supabase.from('dashboard_widgets').select('*').eq('user_id', userId).order('position', { ascending: true })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as DashboardWidget[]
}

export async function createDashboardWidget(dw: Omit<DashboardWidget, 'id' | 'created_at' | 'updated_at' | 'tenant_id'>): Promise<DashboardWidget> {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('dashboard_widgets').insert({ ...dw, tenant_id: tid }).select().single()
  if (error) throw error
  return data as DashboardWidget
}

export async function updateDashboardWidget(id: string, updates: Partial<DashboardWidget>): Promise<DashboardWidget> {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('dashboard_widgets').update(updates), 'dashboard_widgets', tid).eq('id', id).select().single()
  if (error) throw error
  return data as DashboardWidget
}

export async function deleteDashboardWidget(id: string): Promise<void> {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('dashboard_widgets').delete(), 'dashboard_widgets', tid).eq('id', id)
  if (error) throw error
}


// ============ Phase 7D: Analytic Journal Codes (Codes journaux analytiques) ============

export async function getAnalyticJournalCodes(): Promise<AnalyticJournalCode[]> {
  const tid = await getTenantId()
  let q = supabase.from('analytic_journal_codes').select('*').order('code')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as AnalyticJournalCode[]
}

export async function createAnalyticJournalCode(ajc: Omit<AnalyticJournalCode, 'id' | 'created_at' | 'updated_at' | 'tenant_id'>): Promise<AnalyticJournalCode> {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('analytic_journal_codes').insert({ ...ajc, tenant_id: tid }).select().single()
  if (error) throw error
  return data as AnalyticJournalCode
}

export async function updateAnalyticJournalCode(id: string, updates: Partial<AnalyticJournalCode>): Promise<AnalyticJournalCode> {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('analytic_journal_codes').update(updates), 'analytic_journal_codes', tid).eq('id', id).select().single()
  if (error) throw error
  return data as AnalyticJournalCode
}

export async function deleteAnalyticJournalCode(id: string): Promise<void> {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('analytic_journal_codes').delete(), 'analytic_journal_codes', tid).eq('id', id)
  if (error) throw error
}


// ============ Bank Statement Templates (AI-learned PDF parsing) ============

export async function getBankStatementTemplates(): Promise<BankStatementTemplate[]> {
  const tid = await getTenantId()
  let q = supabase.from('bank_statement_templates').select('*').eq('is_active', true).order('bank_name')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as BankStatementTemplate[]
}

export async function createBankStatementTemplate(tpl: Omit<BankStatementTemplate, 'id' | 'created_at' | 'updated_at' | 'tenant_id'>): Promise<BankStatementTemplate> {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('bank_statement_templates').insert({ ...tpl, tenant_id: tid }).select().single()
  if (error) throw error
  return data as BankStatementTemplate
}

export async function updateBankStatementTemplate(id: string, updates: Partial<BankStatementTemplate>): Promise<BankStatementTemplate> {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('bank_statement_templates').update(updates), 'bank_statement_templates', tid).eq('id', id).select().single()
  if (error) throw error
  return data as BankStatementTemplate
}

export async function deleteBankStatementTemplate(id: string): Promise<void> {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('bank_statement_templates').delete(), 'bank_statement_templates', tid).eq('id', id)
  if (error) throw error
}


// ============ #22 — Analytic journals filter ============
export async function getAnalyticJournals() {
  const tid = await getTenantId()
  let q = supabase.from('journals').select('*').eq('is_analytic', true).order('code', { ascending: true })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as Journal[]
}

export async function getNonAnalyticJournals() {
  const tid = await getTenantId()
  let q = supabase.from('journals').select('*').or('is_analytic.is.null,is_analytic.eq.false').order('code', { ascending: true })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as Journal[]
}


// ============ #28 — Third party default bank account ============
export async function getThirdPartyWithBank(tpaId: string) {
  const tid = await getTenantId()
  let q = supabase.from('third_party_accounts').select('*, bank_accounts!default_bank_account_id(*)').eq('id', tpaId)
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q.single()
  if (error) throw error
  return data
}


// ============ Tax Grids (Payroll & Corporate) ============

// --- Payroll Tax Grids ---
export async function getPayrollTaxGrids(countryCode?: string) {
  const tid = await getTenantId()
  let q = supabase
    .from('payroll_tax_grids')
    .select('*')
    .order('created_at', { ascending: false })
  if (tid) q = q.or(`tenant_id.eq.${tid},tenant_id.is.null`)
  if (countryCode) q = q.eq('country_code', countryCode)
  const { data, error } = await q
  if (error) throw error
  return data as PayrollTaxGrid[]
}

export async function getPayrollTaxGridLines(gridId: string) {
  const tid = await getTenantId()
  const { data: grid } = await supabase
    .from('payroll_tax_grids')
    .select('id, tenant_id')
    .eq('id', gridId)
    .or(`tenant_id.eq.${tid},tenant_id.is.null`)
    .maybeSingle()
  if (!grid) throw new Error('Grille introuvable ou accès non autorisé')
  const { data, error } = await supabase
    .from('payroll_tax_grid_lines')
    .select('*')
    .eq('grid_id', gridId)
    .order('sort_order', { ascending: true })
  if (error) throw error
  return data as PayrollTaxGridLine[]
}

export async function createPayrollTaxGrid(grid: Omit<PayrollTaxGrid, 'id' | 'tenant_id' | 'created_at' | 'updated_at'>) {
  const tid = await getTenantId()
  const payload = { ...grid, tenant_id: tid }
  const { data, error } = await supabase
    .from('payroll_tax_grids')
    .insert(payload)
    .select()
    .single()
  if (error) throw error
  return data as PayrollTaxGrid
}

export async function updatePayrollTaxGrid(id: string, updates: Partial<PayrollTaxGrid>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase
    .from('payroll_tax_grids')
    .update({ ...updates, updated_at: new Date().toISOString() }), 'payroll_tax_grids', tid)
    .eq('id', id)
    .select()
    .single()
  if (error) throw error
  return data as PayrollTaxGrid
}

export async function deletePayrollTaxGrid(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase
    .from('payroll_tax_grids')
    .delete(), 'payroll_tax_grids', tid)
    .eq('id', id)
  if (error) throw error
}

export async function createPayrollTaxGridLines(lines: Omit<PayrollTaxGridLine, 'id' | 'created_at'>[]) {
  const { data, error } = await supabase
    .from('payroll_tax_grid_lines')
    .insert(lines)
    .select()
  if (error) throw error
  return data as PayrollTaxGridLine[]
}

export async function deletePayrollTaxGridLines(gridId: string) {
  const tid = await getTenantId()
  let gridQ = supabase
    .from('payroll_tax_grids')
    .select('id')
    .eq('id', gridId)
  if (tid) gridQ = gridQ.eq('tenant_id', tid)
  const { error: gridErr } = await gridQ.maybeSingle()
  if (gridErr) throw gridErr
  const { error } = await supabase
    .from('payroll_tax_grid_lines')
    .delete()
    .eq('grid_id', gridId)
  if (error) throw error
}

// --- Corporate Tax Grids ---
export async function getCorporateTaxGrids(countryCode?: string) {
  const tid = await getTenantId()
  let q = supabase
    .from('corporate_tax_grids')
    .select('*')
    .order('created_at', { ascending: false })
  if (tid) q = q.or(`tenant_id.eq.${tid},tenant_id.is.null`)
  if (countryCode) q = q.eq('country_code', countryCode)
  const { data, error } = await q
  if (error) throw error
  return data as CorporateTaxGrid[]
}

export async function getCorporateTaxGridLines(gridId: string) {
  const tid = await getTenantId()
  const { data: grid } = await supabase
    .from('corporate_tax_grids')
    .select('id, tenant_id')
    .eq('id', gridId)
    .or(`tenant_id.eq.${tid},tenant_id.is.null`)
    .maybeSingle()
  if (!grid) throw new Error('Grille introuvable ou accès non autorisé')
  const { data, error } = await supabase
    .from('corporate_tax_grid_lines')
    .select('*')
    .eq('grid_id', gridId)
    .order('sort_order', { ascending: true })
  if (error) throw error
  return data as CorporateTaxGridLine[]
}

export async function createCorporateTaxGrid(grid: Omit<CorporateTaxGrid, 'id' | 'tenant_id' | 'created_at' | 'updated_at'>) {
  const tid = await getTenantId()
  const payload = { ...grid, tenant_id: tid }
  const { data, error } = await supabase
    .from('corporate_tax_grids')
    .insert(payload)
    .select()
    .single()
  if (error) throw error
  return data as CorporateTaxGrid
}

export async function updateCorporateTaxGrid(id: string, updates: Partial<CorporateTaxGrid>) {
  const tid = await getTenantId()
  const { data, error } = await supabase
    .from('corporate_tax_grids')
    .update({ ...updates, updated_at: new Date().toISOString() })
    .eq('id', id)
    .eq('tenant_id', tid ?? '')
    .select()
    .single()
  if (error) throw error
  return data as CorporateTaxGrid
}

export async function deleteCorporateTaxGrid(id: string) {
  const tid = await getTenantId()
  const { error } = await supabase
    .from('corporate_tax_grids')
    .delete()
    .eq('id', id)
    .eq('tenant_id', tid ?? '')
  if (error) throw error
}

export async function createCorporateTaxGridLines(lines: Omit<CorporateTaxGridLine, 'id' | 'created_at'>[]) {
  const { data, error } = await supabase
    .from('corporate_tax_grid_lines')
    .insert(lines)
    .select()
  if (error) throw error
  return data as CorporateTaxGridLine[]
}

export async function deleteCorporateTaxGridLines(gridId: string) {
  const tid = await getTenantId()
  const { error: gridErr } = await supabase
    .from('corporate_tax_grids')
    .select('id')
    .eq('id', gridId)
    .eq('tenant_id', tid ?? '')
    .maybeSingle()
  if (gridErr) throw gridErr
  const { error } = await supabase
    .from('corporate_tax_grid_lines')
    .delete()
    .eq('grid_id', gridId)
  if (error) throw error
}

// --- Helper: get active payroll tax grid for a country ---
export async function getActivePayrollTaxGrid(countryCode: string, gridType?: string) {
  const tid = await getTenantId()
  let q = supabase
    .from('payroll_tax_grids')
    .select('*')
    .eq('country_code', countryCode)
    .eq('status', 'active')
    .order('is_default', { ascending: false })
    .limit(1)
  if (gridType) q = q.eq('grid_type', gridType)
  if (tid) q = q.or(`tenant_id.eq.${tid},tenant_id.is.null`)
  const { data, error } = await q
  if (error) throw error
  return data?.[0] as PayrollTaxGrid | undefined
}

// --- Helper: get active corporate tax grid for a country ---
export async function getActiveCorporateTaxGrid(countryCode: string, taxType?: string) {
  const tid = await getTenantId()
  let q = supabase
    .from('corporate_tax_grids')
    .select('*')
    .eq('country_code', countryCode)
    .eq('status', 'active')
    .order('is_default', { ascending: false })
    .limit(1)
  if (taxType) q = q.eq('tax_type', taxType)
  if (tid) q = q.or(`tenant_id.eq.${tid},tenant_id.is.null`)
  const { data, error } = await q
  if (error) throw error
  return data?.[0] as CorporateTaxGrid | undefined
}


// ============ Sprint 8: Check Books (#82) ============
export async function getCheckBooks() {
  const tid = await getTenantId()
  let q = supabase.from('check_books').select('*').order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as CheckBook[]
}

export async function createCheckBook(book: Omit<CheckBook, 'id' | 'tenant_id' | 'created_at' | 'issued_count'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase
    .from('check_books')
    .insert({ ...book, tenant_id: tid, issued_count: 0 })
    .select()
    .single()
  if (error) throw error
  return data as CheckBook
}

export async function updateCheckBook(id: string, updates: Partial<CheckBook>) {
  const tid = await getTenantId()
  const { data, error } = await supabase
    .from('check_books')
    .update(updates)
    .eq('id', id)
    .eq('tenant_id', tid ?? '')
    .select()
    .single()
  if (error) throw error
  return data as CheckBook
}

export async function deleteCheckBook(id: string) {
  const tid = await getTenantId()
  const { error } = await supabase
    .from('check_books')
    .delete()
    .eq('id', id)
    .eq('tenant_id', tid ?? '')
  if (error) throw error
}


// ============ Sprint 8: Checks (#82) ============
export async function getChecks() {
  const tid = await getTenantId()
  let q = supabase.from('checks').select('*').order('issue_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as Check[]
}

export async function createCheck(check: Omit<Check, 'id' | 'tenant_id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase
    .from('checks')
    .insert({ ...check, tenant_id: tid })
    .select()
    .single()
  if (error) throw error
  return data as Check
}

export async function updateCheck(id: string, updates: Partial<Check>) {
  const tid = await getTenantId()
  const { data, error } = await supabase
    .from('checks')
    .update(updates)
    .eq('id', id)
    .eq('tenant_id', tid ?? '')
    .select()
    .single()
  if (error) throw error
  return data as Check
}

export async function deleteCheck(id: string) {
  const tid = await getTenantId()
  const { error } = await supabase
    .from('checks')
    .delete()
    .eq('id', id)
    .eq('tenant_id', tid ?? '')
  if (error) throw error
}


// ============ Sprint 8: Exchange Gain/Loss (#9) ============
export async function getExchangeGainLossEntries() {
  const tid = await getTenantId()
  let q = supabase.from('exchange_gain_loss_entries').select('*').order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as ExchangeGainLossEntry[]
}

export async function createExchangeGainLossEntry(entry: Omit<ExchangeGainLossEntry, 'id' | 'tenant_id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase
    .from('exchange_gain_loss_entries')
    .insert({ ...entry, tenant_id: tid })
    .select()
    .single()
  if (error) throw error
  return data as ExchangeGainLossEntry
}


// ============ Sprint 8: Exchange Rates (#89) ============
export async function getExchangeRates(baseCurrency?: string, quoteCurrency?: string) {
  const tid = await getTenantId()
  let q = supabase.from('exchange_rates').select('*').order('rate_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (baseCurrency) q = q.eq('base_currency', baseCurrency)
  if (quoteCurrency) q = q.eq('quote_currency', quoteCurrency)
  const { data, error } = await q
  if (error) throw error
  return data as ExchangeRate[]
}

export async function getLatestRate(baseCurrency: string, quoteCurrency: string): Promise<ExchangeRate | null> {
  const tid = await getTenantId()
  let q = supabase
    .from('exchange_rates')
    .select('*')
    .eq('base_currency', baseCurrency)
    .eq('quote_currency', quoteCurrency)
    .order('rate_date', { ascending: false })
    .limit(1)
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return (data && data.length > 0) ? data[0] as ExchangeRate : null
}

export async function createExchangeRate(rate: Omit<ExchangeRate, 'id' | 'tenant_id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase
    .from('exchange_rates')
    .insert({ ...rate, tenant_id: tid })
    .select()
    .single()
  if (error) throw error
  return data as ExchangeRate
}

