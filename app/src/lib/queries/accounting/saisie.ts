// ============================================================================
// Comptabilite — saisie.ts
// Extrait de l'ancien src/lib/queries/accounting.ts (4238 l.) le 2026-10-01.
// Decoupage par domaine ; imports recalcules ; aucun code metier modifie.
// ============================================================================

import { supabase } from '@/lib/supabase'
import { type Joined } from '@/types/dbRow'
import { fetchAllRows, getTenantId, tud } from '../core'
import { type JournalEntry, type JournalLine, type FiscalPeriod } from '@/types'
import { getCompanySettings } from './settings'

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
  /** « Enregistrer et valider » : l'écriture est validée dans la même transaction */
  validate?: boolean
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
    vat_code?: string | null
    vat_amount?: number
    echeance_date?: string | null
    lettrage_code?: string | null
    quantity?: number | null
    /** code de la section analytique choisie à l'écran */
    analytic_section?: string | null
  }>
}) {
  const { lines, validate, ...entryData } = entry
  // X2/C4 (273) : un seul chemin atomique — `post_journal_entry` écrit l'en-tête
  // et les lignes dans la même transaction (avant : en-tête PUIS lignes, et une
  // colonne `analytic_section` inexistante qui faisait échouer la saisie).
  // La section analytique choisie à l'écran est un CODE : la base attend l'id.
  const codes = [...new Set(lines.map((l) => l.analytic_section).filter(Boolean))] as string[]
  const sectionIds = new Map<string, string>()
  if (codes.length) {
    const tid = await getTenantId()
    let sq = supabase.from('analytic_sections').select('id, code').in('code', codes)
    if (tid) sq = sq.eq('tenant_id', tid)
    const { data: secs, error: secErr } = await sq
    if (secErr) throw secErr
    for (const sec of secs || []) sectionIds.set(sec.code, sec.id)
  }
  const { data, error } = await supabase.rpc('post_journal_entry', {
    p_entry: { ...entryData, status: validate ? 'posted' : 'draft' },
    p_lines: lines.map(({ analytic_section, ...l }) => ({
      ...l,
      analytic_section_id: analytic_section ? sectionIds.get(analytic_section) ?? null : null,
    })),
  })
  if (error) throw error
  const res = data as any
  if (res && res.success === false) throw new Error(res.error || 'Échec de la création de l\'écriture')
  return { ...entryData, id: res?.entry_id, number: res?.number } as unknown as JournalEntry
}

// --- Validation des écritures saisies (X2/C4, décision D-A) ---
// Une écriture saisie naît brouillon ; « Valider » la fait passer par le noyau
// (équilibre, période ouverte, droit, séparation des tâches, numéro définitif).
// La base rend un verdict PAR écriture : un refus n'empêche pas les autres.
export type JournalValidationVerdict = { id: string; number?: string; ok: boolean; posting_number?: string; error?: string }

export async function validateJournalEntries(ids: string[]): Promise<JournalValidationVerdict[]> {
  if (!ids.length) return []
  const { data, error } = await supabase.rpc('validate_journal_entries', { p_ids: ids })
  if (error) throw error
  return (data || []) as JournalValidationVerdict[]
}

// SAGE-01/02/03 (308) : l'import d'écritures (FEC, balance) est un **acte unique**
// côté base — contrôle d'équilibre global, comptes créés au besoin, écritures
// **validées** par le noyau et soldes de comptes **cumulés**. Une erreur annule
// tout : la comptabilité ne peut pas rester à moitié importée.
export interface FecImportVerdict {
  entries: number
  lines: number
  accounts_created: number
  total_debit: number
  total_credit: number
}

export async function importFecEntries(entries: unknown[]): Promise<FecImportVerdict> {
  const { data, error } = await supabase.rpc('import_fec_entries', { p_entries: entries })
  if (error) throw error
  return data as FecImportVerdict
}

// « Enregistrer et valider » n'est offert que sans séparation des tâches :
// avec elle, l'auteur d'une écriture ne peut pas la valider (232).
export async function isSegregationEnforced(): Promise<boolean> {
  const settings = await getCompanySettings()
  return Boolean((settings as any)?.enforce_segregation)
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
