// ============================================================================
// Comptabilite — journal.ts
// Extrait de l'ancien src/lib/queries/accounting.ts (4238 l.) le 2026-10-01.
// Decoupage par domaine ; imports recalcules ; aucun code metier modifie.
// ============================================================================

import { supabase } from '@/lib/supabase'
import { fetchAllRows, getTenantId, tud } from '../core'
import { type JournalEntry, type JournalLine } from '@/types'

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
export async function getCurrentFiscalYearId(): Promise<string | null> {
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
