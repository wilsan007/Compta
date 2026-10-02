// ============================================================================
// Comptabilite — etats.ts
// Extrait de l'ancien src/lib/queries/accounting.ts (4238 l.) le 2026-10-01.
// Decoupage par domaine ; imports recalcules ; aucun code metier modifie.
// ============================================================================

import { supabase } from '@/lib/supabase'
import { type Row } from '@/types/dbRow'
import { fetchAllRows, getTenantId } from '../core'
import { buildFECRows, sirenFrom, type FECExport, type FECReferences } from '@/lib/fecValidator'
import { type JournalEntry, type FiscalYear } from '@/types'
import { getCompanySettings } from './settings'
import { getCurrentFiscalYearId } from './journal'

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
  const tiers = await fetchAllRows<Row<'third_party_accounts'>>(tpQ, { label: 'getAgedBalance/third_party_accounts' })

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

// --- FEC complet (M1, A47 A-1) : lignes à 18 colonnes, libellés résolus ---
// CompteLib vient du plan comptable, JournalLib du journal, CompAuxLib du compte
// de tiers (à défaut, du client ou du fournisseur dont c'est le compte auxiliaire).
export async function getFECExport(fiscalYearId: string): Promise<FECExport> {
  const tid = await getTenantId()
  const entries = await getFECData(fiscalYearId)
  const scoped = <T,>(q: T) => (tid ? (q as any).eq('tenant_id', tid) : q)
  const [accounts, journals, tpa, customers, suppliers, settings] = await Promise.all([
    fetchAllRows<{ code: string; name: string }>(scoped(supabase.from('chart_accounts').select('code, name').order('id')), { label: 'getFECExport/chart_accounts' }),
    fetchAllRows<{ code: string; name: string }>(scoped(supabase.from('journals').select('code, name').order('id')), { label: 'getFECExport/journals' }),
    fetchAllRows<{ code: string; name: string }>(scoped(supabase.from('third_party_accounts').select('code, name').order('id')), { label: 'getFECExport/third_party_accounts' }),
    fetchAllRows<{ account_tiers: string | null; name: string }>(scoped(supabase.from('customers').select('account_tiers, name').not('account_tiers', 'is', null).order('id')), { label: 'getFECExport/customers' }),
    fetchAllRows<{ account_tiers: string | null; name: string }>(scoped(supabase.from('suppliers').select('account_tiers, name').not('account_tiers', 'is', null).order('id')), { label: 'getFECExport/suppliers' }),
    getCompanySettings(),
  ])
  const tiers: Record<string, string> = {}
  for (const p of [...customers, ...suppliers]) if (p.account_tiers) tiers[p.account_tiers] = p.name
  for (const a of tpa) tiers[a.code] = a.name
  const refs: FECReferences = {
    accounts: Object.fromEntries(accounts.map((a) => [a.code, a.name])),
    journals: Object.fromEntries(journals.map((j) => [j.code, j.name])),
    tiers,
    functionalCurrency: (settings as any)?.currency || 'EUR',
  }
  return {
    rows: buildFECRows(entries, refs),
    siren: sirenFrom((settings as any)?.siret),
    entryCount: entries.length,
  }
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

// --- Analytic Balance: journal_lines by analytic_section_id, bornée à une période ---
// ANA-03 (304) : la balance porte sur **la période demandée**, plus sur tout
// l'historique. Le filtre s'appuie sur la date de l'écriture (`journal_entries`
// en jointure interne), comme les autres états comptables.
export async function getAnalyticBalance(dateFrom: string, dateTo: string) {
  const tid = await getTenantId()
  let abQ2 = supabase
    .from('journal_lines')
    .select('analytic_section_id, analytic_amount, debit, credit, account_code, account_general, journal_entries!inner(date)')
    .not('analytic_section_id', 'is', null)
    .gte('journal_entries.date', dateFrom)
    .lte('journal_entries.date', dateTo)
    .order('id')
  if (tid) abQ2 = abQ2.eq('tenant_id', tid)
  // LOT7-03 : balance analytique = agrégat par section, borné à la période.
  const lines = await fetchAllRows<any>(abQ2, { label: 'getAnalyticBalance/journal_lines' })

  let asQ = supabase.from('analytic_sections').select('*').order('id')
  if (tid) asQ = asQ.eq('tenant_id', tid)
  const sections = await fetchAllRows<Row<'analytic_sections'>>(asQ, { label: 'getAnalyticBalance/analytic_sections' })

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
