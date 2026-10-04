// ============================================================================
// Comptabilite — budgets.ts
// Extrait de l'ancien src/lib/queries/accounting.ts (4238 l.) le 2026-10-01.
// Decoupage par domaine ; imports recalcules ; aucun code metier modifie.
// ============================================================================

import { supabase } from '@/lib/supabase'
import { fetchAllRows, getTenantId, ti, tud } from '../core'
import { type Budget, type BudgetCommitment, type BudgetControlResult } from '@/types'

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



// ============ Sprint 8: Budget Tracking ============
export async function getBudgetTracking(fiscalYearId?: string) {
  const tid = await getTenantId()
  // AUD-G08 (G20) : budgets.account_code est un code libre, sans clé étrangère vers
  // chart_accounts — le libellé du compte est chargé à part.
  // BUD-01 : l'exercice du budget porte ses bornes — le réalisé s'y borne.
  let q = supabase.from('budgets').select('*, fiscal_years(code, start_date, end_date)').order('name').order('id')
  if (tid) q = q.eq('tenant_id', tid)
  if (fiscalYearId) q = q.eq('fiscal_year_id', fiscalYearId)
  const budgets = await fetchAllRows<any>(q, { label: 'getBudgetTracking/budgets' })
  const codes = [...new Set(budgets.map((b: any) => b.account_code).filter(Boolean))]
  const byCode = new Map<string, any>()
  if (codes.length > 0) {
    let aq = supabase.from('chart_accounts').select('code, name').in('code', codes).order('code')
    if (tid) aq = aq.eq('tenant_id', tid)
    const accounts = await fetchAllRows<{ code: string; name: string }>(aq, { label: 'getBudgetTracking/chart_accounts' })
    for (const a of accounts) byCode.set(a.code, a)
  }

  // BUD-01/02 : **une** requête de lignes par exercice distinct (et non par
  // budget — c'est BUD-04), bornée aux dates de l'exercice, aux écritures
  // **validées** et hors à-nouveaux / clôture (AN, CL) — sans quoi le réalisé
  // cumule depuis l'origine et les écritures de solde l'annulent après clôture.
  const parExercice = new Map<string, { debut: string; fin: string; codes: string[] }>()
  for (const b of budgets) {
    const fy = b.fiscal_years
    if (!fy?.start_date || !fy?.end_date || !b.account_code) continue
    const cle = `${fy.start_date}|${fy.end_date}`
    if (!parExercice.has(cle)) parExercice.set(cle, { debut: fy.start_date, fin: fy.end_date, codes: [] })
    parExercice.get(cle)!.codes.push(b.account_code)
  }

  const realised = new Map<string, number>()
  for (const grp of parExercice.values()) {
    let jlQ = supabase
      .from('journal_lines')
      .select('debit, credit, account_general, journal_entries!inner(date, status, journal_code)')
      .in('account_general', grp.codes)
      .gte('journal_entries.date', grp.debut)
      .lte('journal_entries.date', grp.fin)
      .eq('journal_entries.status', 'posted')
      .not('journal_entries.journal_code', 'in', '(AN,CL)')
      .order('id')
    if (tid) jlQ = jlQ.eq('tenant_id', tid)
    const lignes = await fetchAllRows<any>(jlQ, { label: 'getBudgetTracking/journal_lines' })
    for (const l of lignes) {
      const k = l.account_general || l.account_code
      realised.set(k, (realised.get(k) ?? 0) + (Number(l.debit) || 0) - (Number(l.credit) || 0))
    }
  }

  // Engagements : une seule requête pour tous les comptes (BUD-04).
  const engages = new Map<string, number>()
  if (codes.length > 0) {
    let cQ = supabase
      .from('budget_commitments')
      .select('amount, account_code')
      .eq('status', 'active')
      .in('account_code', codes)
    if (tid) cQ = cQ.eq('tenant_id', tid)
    if (fiscalYearId) cQ = cQ.eq('fiscal_year_id', fiscalYearId)
    const engagements = await fetchAllRows<any>(cQ.order('id'), { label: 'getBudgetTracking/budget_commitments' })
    for (const c of engagements) engages.set(c.account_code, (engages.get(c.account_code) ?? 0) + (Number(c.amount) || 0))
  }

  const results: any[] = []
  for (const b of budgets) {
    const budgetTotal = ['period_1','period_2','period_3','period_4','period_5','period_6','period_7','period_8','period_9','period_10','period_11','period_12']
      .reduce((s, k) => s + Number((b as any)[k] || 0), 0)

    const realized = realised.get(b.account_code) ?? 0
    const committed = engages.get(b.account_code) ?? 0
    const available = budgetTotal - realized - committed

    results.push({
      ...b,
      chart_accounts: byCode.get(b.account_code) ?? null,
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
