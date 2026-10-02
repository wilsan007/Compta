// ============================================================================
// Comptabilite — features6.ts
// Extrait de l'ancien src/lib/queries/accounting.ts (4238 l.) le 2026-10-01.
// Decoupage par domaine ; imports recalcules ; aucun code metier modifie.
// ============================================================================

import { supabase } from '@/lib/supabase'
import { type Joined } from '@/types/dbRow'
import { fetchAllRows, getTenantId, tud } from '../core'
import { getJournals } from '../misc'
import { getPaymentTermById } from '../payroll'
import { type Journal, type AutoLabelRule, type ExtourneLog, type CarryForwardLog, type LettrageDifference, type AccountingControlRun, type CashControlSession, type FECAttestation, type TierRIB, type IFRSAdjustment, type TaxPayment, type CustomReportTemplate, type DeferredPrintingJob, type JournalAccessRight, type VATOnCollection, type BatchEntrySession } from '@/types'
import { getFECData } from './etats'

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
  const { error: ePost } = await tud(supabase.from('journal_entries').update({ status: 'posted' }), 'journal_entries', tid).eq('id', newEntry.id)
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
  const { error: ePost } = await tud(supabase.from('journal_entries').update({ status: 'posted' }), 'journal_entries', tid).eq('id', newEntry.id)
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
