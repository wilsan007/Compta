// ============================================================================
// Comptabilite — accounts.ts
// Extrait de l'ancien src/lib/queries/accounting.ts (4238 l.) le 2026-10-01.
// Decoupage par domaine ; imports recalcules ; aucun code metier modifie.
// ============================================================================

import { supabase } from '@/lib/supabase'
import { getTenantId, ti, tud } from '../core'
import { type ChartAccount, type Currency, type Journal, type FiscalYear, type FiscalPeriod, type EntryTemplate, type ThirdPartyAccount, type AnalyticSection, type StandardLabel, type AnalyticPlan, type DistributionGrill, type DistributionGrillLine, type AnalyticJournalCode } from '@/types'

// ============ Chart of Accounts ============
export async function getChartAccounts() {
  const tid = await getTenantId()
  let q = supabase.from('chart_accounts').select('*').order('code', { ascending: true })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as ChartAccount[]
}

// X2/C14 (W05) : un compte créé à la volée prend sa nature de sa classe (PCG) —
// `chart_accounts.type` n'admet que asset / liability / equity / income / expense.
export function chartAccountTypeFromCode(code: string): ChartAccount['type'] {
  const c = code.trim()
  switch (c.charAt(0)) {
    case '1': return 'equity'
    case '2': case '3': case '5': return 'asset'
    case '4': return c.startsWith('41') ? 'asset' : 'liability'
    case '6': return 'expense'
    case '7': return 'income'
    default: return 'asset'
  }
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
      .insert(lines.map(l => ti({ ...l, grill_id: grillId }, 'distribution_grill_lines', tid)))
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
  // La clé est COMPOSITE depuis la 237 (ISO-02) : `(tenant_id, default_bank_account_id)
  // → bank_accounts(tenant_id, id)`. Un hint qui ne nomme qu'une partie des colonnes de la
  // clé ne résout plus la relation : seul le NOM DE LA CONTRAINTE le fait (mesuré sur
  // PostgREST v16.3, contrôle LOT7-04 — `db:embeds`).
  let q = supabase.from('third_party_accounts').select('*, bank_accounts!tpa_default_bank_account_id_fkey(*)').eq('id', tpaId)
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q.single()
  if (error) throw error
  return data
}
