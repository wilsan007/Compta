// ============================================================================
// misc — fiscal.ts
// Extrait de l'ancien misc.ts le 2026-10-01 ; imports recalcules ;
// aucun code metier modifie.
// ============================================================================

import { supabase } from '@/lib/supabase'
import { getTenantId, tud } from '../core'
import { type PaymentTerm, type MarkingType, type ReminderLevel, type Dispute, type JustificatifSolde, type EtatRapprochement, type FiscalPosition, type FiscalPositionMapping, type AccountTag, type AccountTagMapping } from '@/types'

// ============ Fiscal Positions (#32, #56) ============

export async function getFiscalPositions(): Promise<FiscalPosition[]> {
  const tid = await getTenantId()
  let q = supabase.from('fiscal_positions').select('*').order('name', { ascending: true })
  if (tid) q = q.or(`tenant_id.is.null,tenant_id.eq.${tid}`)
  const { data, error } = await q
  if (error) throw error
  return data as FiscalPosition[]
}

export async function createFiscalPosition(fp: Omit<FiscalPosition, 'id' | 'created_at' | 'tenant_id'>): Promise<FiscalPosition> {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('fiscal_positions').insert({ ...fp, tenant_id: tid }).select().single()
  if (error) throw error
  return data as FiscalPosition
}

export async function updateFiscalPosition(id: string, updates: Partial<FiscalPosition>): Promise<FiscalPosition> {
  const tid = await getTenantId()
  let q = supabase.from('fiscal_positions').update(updates).eq('id', id)
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q.select().single()
  if (error) throw error
  return data as FiscalPosition
}

export async function deleteFiscalPosition(id: string): Promise<void> {
  const tid = await getTenantId()
  let q = supabase.from('fiscal_positions').delete().eq('id', id)
  if (tid) q = q.eq('tenant_id', tid)
  const { error } = await q
  if (error) throw error
}



// ============ Fiscal Position Mappings (#56) ============

export async function getFiscalPositionMappings(fiscalPositionId: string): Promise<FiscalPositionMapping[]> {
  const tid = await getTenantId()
  let q = supabase.from('fiscal_position_mappings').select('*').eq('fiscal_position_id', fiscalPositionId).order('created_at', { ascending: true })
  if (tid) q = q.or(`tenant_id.is.null,tenant_id.eq.${tid}`)
  const { data, error } = await q
  if (error) throw error
  return data as FiscalPositionMapping[]
}

export async function createFiscalPositionMapping(m: Omit<FiscalPositionMapping, 'id' | 'created_at' | 'tenant_id'>): Promise<FiscalPositionMapping> {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('fiscal_position_mappings').insert({ ...m, tenant_id: tid }).select().single()
  if (error) throw error
  return data as FiscalPositionMapping
}

export async function deleteFiscalPositionMapping(id: string): Promise<void> {
  const tid = await getTenantId()
  let q = supabase.from('fiscal_position_mappings').delete().eq('id', id)
  if (tid) q = q.eq('tenant_id', tid)
  const { error } = await q
  if (error) throw error
}



// ============ Account Tags (#22) ============

export async function getAccountTags(): Promise<AccountTag[]> {
  const tid = await getTenantId()
  let q = supabase.from('account_tags').select('*').order('name', { ascending: true })
  if (tid) q = q.or(`tenant_id.is.null,tenant_id.eq.${tid}`)
  const { data, error } = await q
  if (error) throw error
  return data as AccountTag[]
}

export async function createAccountTag(tag: Omit<AccountTag, 'id' | 'created_at' | 'tenant_id'>): Promise<AccountTag> {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('account_tags').insert({ ...tag, tenant_id: tid }).select().single()
  if (error) throw error
  return data as AccountTag
}

export async function deleteAccountTag(id: string): Promise<void> {
  const tid = await getTenantId()
  let q = supabase.from('account_tags').delete().eq('id', id)
  if (tid) q = q.eq('tenant_id', tid)
  const { error } = await q
  if (error) throw error
}

export async function updateAccountTag(id: string, updates: Partial<AccountTag>): Promise<AccountTag> {
  const tid = await getTenantId()
  let q = supabase.from('account_tags').update(updates).eq('id', id)
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q.select().single()
  if (error) throw error
  return data as AccountTag
}



// ============ Account Tag Mappings (#22) ============

export async function getAccountTagMappings(tagId?: string, entityType?: string, entityId?: string): Promise<AccountTagMapping[]> {
  const tid = await getTenantId()
  let q = supabase.from('account_tag_mappings').select('*').order('created_at', { ascending: false })
  if (tid) q = q.or(`tenant_id.is.null,tenant_id.eq.${tid}`)
  if (tagId) q = q.eq('tag_id', tagId)
  if (entityType) q = q.eq('entity_type', entityType)
  if (entityId) q = q.eq('entity_id', entityId)
  const { data, error } = await q
  if (error) throw error
  return data as AccountTagMapping[]
}

export async function createAccountTagMapping(m: Omit<AccountTagMapping, 'id' | 'created_at' | 'tenant_id'>): Promise<AccountTagMapping> {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('account_tag_mappings').insert({ ...m, tenant_id: tid }).select().single()
  if (error) throw error
  return data as AccountTagMapping
}

export async function deleteAccountTagMapping(id: string): Promise<void> {
  const tid = await getTenantId()
  let q = supabase.from('account_tag_mappings').delete().eq('id', id)
  if (tid) q = q.eq('tenant_id', tid)
  const { error } = await q
  if (error) throw error
}



// ============ Marking Types (Types de marquage) ============

export async function getMarkingTypes(): Promise<MarkingType[]> {
  const tid = await getTenantId()
  let q = supabase.from('marking_types').select('*').order('code', { ascending: true })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as MarkingType[]
}

export async function createMarkingType(mt: Omit<MarkingType, 'id' | 'tenant_id' | 'created_at' | 'updated_at'>): Promise<MarkingType> {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('marking_types').insert({ ...mt, tenant_id: tid }).select().single()
  if (error) throw error
  return data as MarkingType
}

export async function deleteMarkingType(id: string): Promise<void> {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('marking_types').delete(), 'marking_types', tid).eq('id', id)
  if (error) throw error
}



// ============ Phase 7B: Reminder Levels ============

export async function getReminderLevels(): Promise<ReminderLevel[]> {
  const tid = await getTenantId()
  let q = supabase.from('reminder_levels').select('*').order('level', { ascending: true })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as ReminderLevel[]
}

export async function createReminderLevel(rl: Omit<ReminderLevel, 'id' | 'created_at' | 'updated_at' | 'tenant_id'>): Promise<ReminderLevel> {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('reminder_levels').insert({ ...rl, tenant_id: tid }).select().single()
  if (error) throw error
  return data as ReminderLevel
}

export async function updateReminderLevel(id: string, updates: Partial<ReminderLevel>): Promise<ReminderLevel> {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('reminder_levels').update(updates), 'reminder_levels', tid).eq('id', id).select().single()
  if (error) throw error
  return data as ReminderLevel
}

export async function deleteReminderLevel(id: string): Promise<void> {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('reminder_levels').delete(), 'reminder_levels', tid).eq('id', id)
  if (error) throw error
}



// ============ Phase 7B: Disputes ============

export async function getDisputes(): Promise<Dispute[]> {
  const tid = await getTenantId()
  let q = supabase.from('disputes').select('*').order('opened_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as Dispute[]
}

export async function createDispute(d: Omit<Dispute, 'id' | 'created_at' | 'updated_at' | 'tenant_id'>): Promise<Dispute> {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('disputes').insert({ ...d, tenant_id: tid }).select().single()
  if (error) throw error
  return data as Dispute
}

export async function updateDispute(id: string, updates: Partial<Dispute>): Promise<Dispute> {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('disputes').update(updates), 'disputes', tid).eq('id', id).select().single()
  if (error) throw error
  return data as Dispute
}

export async function deleteDispute(id: string): Promise<void> {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('disputes').delete(), 'disputes', tid).eq('id', id)
  if (error) throw error
}



// ============ Phase 7B: Multi-Echeance Generation ============

export function generateMultiEcheances(
  date: string,
  paymentTerm: PaymentTerm
): { date: string; amount_pct: number; label: string }[] {
  const baseDate = new Date(date)
  const echeances: { date: string; amount_pct: number; label: string }[] = []

  if (paymentTerm.type === 'fixed' || paymentTerm.type === 'end_of_month') {
    const echeance = new Date(baseDate)
    echeance.setDate(echeance.getDate() + paymentTerm.days_1)
    if (paymentTerm.type === 'end_of_month') {
      echeance.setMonth(echeance.getMonth() + 1, 0)
    }
    echeances.push({
      date: echeance.toISOString().slice(0, 10),
      amount_pct: 100,
      label: `Échéance ${paymentTerm.code}`,
    })
  } else if (paymentTerm.type === 'split') {
    const pct1 = paymentTerm.pct_1 || 50
    const pct2 = paymentTerm.pct_2 || 50
    const echeance1 = new Date(baseDate)
    echeance1.setDate(echeance1.getDate() + paymentTerm.days_1)
    echeances.push({
      date: echeance1.toISOString().slice(0, 10),
      amount_pct: pct1,
      label: `Échéance 1 (${pct1}%)`,
    })
    if (paymentTerm.days_2) {
      const echeance2 = new Date(baseDate)
      echeance2.setDate(echeance2.getDate() + paymentTerm.days_2)
      echeances.push({
        date: echeance2.toISOString().slice(0, 10),
        amount_pct: pct2,
        label: `Échéance 2 (${pct2}%)`,
      })
    }
  }

  return echeances
}



// ============ Phase 7B: Justificatif de Solde ============

export async function generateJustificatifSolde(
  accountCode: string,
  thirdPartyCode: string | null,
  fiscalPeriodId: string | null
): Promise<JustificatifSolde> {
  const tid = await getTenantId()
  let q = supabase.from('journal_lines').select('debit, credit')
  if (tid) q = q.eq('tenant_id', tid)
  q = q.eq('account_code', accountCode)
  if (thirdPartyCode) q = q.eq('account_tiers', thirdPartyCode)
  if (fiscalPeriodId) {
    const { data: fp } = await supabase.from('fiscal_periods').select('start_date, end_date').eq('id', fiscalPeriodId).single()
    if (fp) {
      q = q.gte('line_date', fp.start_date).lte('line_date', fp.end_date)
    }
  }
  const { data: lines, error } = await q
  if (error) throw error

  const totalDebit = (lines || []).reduce((s: number, l: any) => s + (Number(l.debit) || 0), 0)
  const totalCredit = (lines || []).reduce((s: number, l: any) => s + (Number(l.credit) || 0), 0)
  const closingBalance = totalDebit - totalCredit

  const record = {
    account_code: accountCode,
    third_party_code: thirdPartyCode,
    fiscal_period_id: fiscalPeriodId,
    opening_balance: 0,
    total_debit: totalDebit,
    total_credit: totalCredit,
    closing_balance: closingBalance,
    generated_by: null,
  }

  const { data, error: insertError } = await supabase.from('justificatif_solde').insert({ ...record, tenant_id: tid }).select().single()
  if (insertError) throw insertError
  return data as JustificatifSolde
}

export async function getJustificatifsSolde(): Promise<JustificatifSolde[]> {
  const tid = await getTenantId()
  let q = supabase.from('justificatif_solde').select('*').order('generated_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as JustificatifSolde[]
}



// ============ Phase 7B: Etat Rapprochement ============

export async function generateEtatRapprochement(
  accountCode: string,
  bankAccountId: string | null,
  periodStart: string,
  periodEnd: string
): Promise<EtatRapprochement> {
  const tid = await getTenantId()
  let q = supabase.from('journal_lines').select('debit, credit')
  if (tid) q = q.eq('tenant_id', tid)
  q = q.eq('account_code', accountCode)
  q = q.gte('line_date', periodStart).lte('line_date', periodEnd)
  const { data: lines, error } = await q
  if (error) throw error

  const bookBalance = (lines || []).reduce((s: number, l: any) => s + (Number(l.debit) || 0) - (Number(l.credit) || 0), 0)

  let bankBalance = 0
  if (bankAccountId) {
    let bq = supabase.from('bank_transactions').select('amount')
    if (tid) bq = bq.eq('tenant_id', tid)
    bq = bq.eq('bank_account_id', bankAccountId)
    // LOT7-04 : `bank_transactions` porte `date`, pas `transaction_date` — 400/42703.
    bq = bq.gte('date', periodStart).lte('date', periodEnd)
    const { data: txns, error: txnError } = await bq
    if (txnError) throw txnError
    bankBalance = (txns || []).reduce((s: number, t: any) => s + (Number(t.amount) || 0), 0)
  }

  const record = {
    bank_account_id: bankAccountId,
    account_code: accountCode,
    period_start: periodStart,
    period_end: periodEnd,
    bank_balance: bankBalance,
    book_balance: bookBalance,
    difference: bankBalance - bookBalance,
    reconciled_items: 0,
    unreconciled_items: 0,
    generated_by: null,
  }

  const { data, error: insertError } = await supabase.from('etat_rapprochement').insert({ ...record, tenant_id: tid }).select().single()
  if (insertError) throw insertError
  return data as EtatRapprochement
}

export async function getEtatsRapprochement(): Promise<EtatRapprochement[]> {
  const tid = await getTenantId()
  let q = supabase.from('etat_rapprochement').select('*').order('generated_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as EtatRapprochement[]
}



// ============ Phase 7B: Mark line with marking code ============

export async function markLineWithCode(lineId: string, markingCode: string | null): Promise<void> {
  const tid = await getTenantId()
  const { error } = await tud(
    supabase.from('journal_lines').update({ marking_code: markingCode }),
    'journal_lines', tid
  ).eq('id', lineId)
  if (error) throw error
}
