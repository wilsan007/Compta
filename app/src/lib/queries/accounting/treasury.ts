// ============================================================================
// Comptabilite — treasury.ts
// Extrait de l'ancien src/lib/queries/accounting.ts (4238 l.) le 2026-10-01.
// Decoupage par domaine ; imports recalcules ; aucun code metier modifie.
// ============================================================================

import { supabase } from '@/lib/supabase'
import { type Row, type Joined } from '@/types/dbRow'
import { fetchAllRows, getTenantId, ti, tud } from '../core'
import { type PaymentOrder, type CollectionReminder, type CurrencyRevaluation, type FutureAccountingMovement, type TreasuryTransfer, type TreasuryRecurring, type ConsolidatedTreasury, type ExchangeRate, type ExchangeGainLossEntry, type CheckBook, type Check } from '@/types'
import { getKpis } from './pilotage'
// L19 : le prévisionnel a UN moteur — `cash_flow_forecast`. Avant, cette
// fonction en était une seconde implémentation en JavaScript, et les deux
// divergeaient de 4 000 € sur le même libellé (mesuré : la preuve 422).
import { cashFlowForecast } from '../businessFunctions'

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



// ============ Sprint 5: Collection Reminders ============
export async function getCollectionReminders(status?: string) {
  const tid = await getTenantId()
  // B9 (ven-015) : `collection_reminders` ne porte que son propre `number` —
  // ni nom de client, ni numéro de facture. Sans les jointures, l'écran
  // affichait « — » dans les deux colonnes : une relance ne disait ni à qui elle
  // s'adressait, ni quelle facture elle concernait.
  let query = supabase.from('collection_reminders').select('*, customers(name), invoices(number)').order('reminder_date', { ascending: false })
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
  const accounts = await fetchAllRows<Row<'bank_accounts'>>(accQ, { label: 'getTreasuryDashboard/bank_accounts' })

  // M5 (278) : la trésorerie est le solde des comptes 5x au grand livre
  const totalBalance = (await getKpis()).cash

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

  // 2.17 (470) : la dette fournisseur = approuvée, non annulée, reste dû > 0 —
  // et c'est le RESTE DÛ qui sortira, pas le total.
  let outQ = supabase
    .from('purchase_invoices')
    .select('amount_due, due_date')
    .eq('approval_status', 'approved')
    .neq('status', 'cancelled')
    .gt('amount_due', 0)
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
    if (days <= 30) forecastBuckets[0].outgoing += Number(inv.amount_due)
    else if (days <= 60) forecastBuckets[1].outgoing += Number(inv.amount_due)
    else forecastBuckets[2].outgoing += Number(inv.amount_due)
  }

  let ppQ = supabase.from('payment_orders').select('*').in('status', ['draft', 'approved']).order('id')
  if (tid) ppQ = ppQ.eq('tenant_id', tid)
  const pendingPayments = await fetchAllRows<Row<'payment_orders'>>(ppQ, { label: 'getTreasuryDashboard/payment_orders' })

  return {
    accounts,
    totalBalance,
    forecastBuckets,
    pendingPayments,
  }
}



// ============ Sprint 5: Treasury Forecast ============
//
// ⚠️ CETTE FONCTION ÉTAIT UNE SECONDE IMPLÉMENTATION DU PRÉVISIONNEL.
//
// Mesuré : elle recalculait en JavaScript ce que `cash_flow_forecast`
// calcule en SQL — et les deux ne disaient pas la même chose.
//
//   solde actuel   SQL : journal_lines, TOUTE la classe 5 (2 500 de banque
//                            + 1 500 de caisse = 4 000)
//                     JS : bank_accounts.calculated_balance ....... 0
//   entrées/sorties SQL : SUM(amount_due)  — l'ÉCHÉANCE
//                     JS : SUM(total)        — le TOTAL DE FACTURE
//
// Une facture partiellement réglée compte donc pour son total ici et pour
// son dû côté moteur : deux chiffres, un seul libellé, aucun avertissement.
// C'est le défaut « un seul moteur par grandeur » (W5), et c'est ce que la
// 420 areveulé en rendant enfin les bons clés côté SQL.
//
// LA RÈGLE, MAINTENANT : le MOTEUR est le SQL. Cette fonction n'assemble
// plus que la LIGNE DE TEMPS — une liste d'affichage, pas une grandeur. Tout
// chiffre affiché vient de `cash_flow_forecast`.
export async function getTreasuryForecast(days: number = 90) {
  const tid = await getTenantId()
  const today = new Date()
  const end = new Date(today)
  end.setDate(end.getDate() + days)

  // ── LE MOTEUR. Une seule source pour toutes les grandeurs.
  const previsionnel = await cashFlowForecast(days)

  let invQ = supabase
    .from('invoices')
    .select('number, total, amount_due, due_date, customer_id, status')
    .in('status', ['sent', 'overdue'])
    .gte('due_date', today.toISOString().split('T')[0])
    .lte('due_date', end.toISOString().split('T')[0])
    .order('due_date')
    .order('id')
  if (tid) invQ = invQ.eq('tenant_id', tid)
  // LOT7-03 : la courbe de trésorerie prévisionnelle doit intégrer toutes les échéances.
  const invoices = await fetchAllRows<any>(invQ, { label: 'getTreasuryForecast/invoices' })

  // 2.17 (470) : le même critère que le moteur — approuvée, non annulée, reste dû > 0.
  let purQ = supabase
    .from('purchase_invoices')
    .select('number, amount_due, due_date, supplier_id')
    .eq('approval_status', 'approved')
    .neq('status', 'cancelled')
    .gt('amount_due', 0)
    .gte('due_date', today.toISOString().split('T')[0])
    .lte('due_date', end.toISOString().split('T')[0])
    .order('due_date')
    .order('id')
  if (tid) purQ = purQ.eq('tenant_id', tid)
  const purchaseInvoices = await fetchAllRows<any>(purQ, { label: 'getTreasuryForecast/purchase_invoices' })

  // ⚠️ LE SOLDE NE SE LIT PLUS ICI. Il vient du moteur (classe 5), et
  // cette lecture-ci ne voyait que les comptes bancaires : une caisse de
  // 1 500 € n'y entrait pas, et l'écran affichait 0 € là où le moteur
  // disait 4 000 €. Mesuré, dans la preuve de la 422.
  const currentBalance = Number(previsionnel?.currentBalance ?? 0)

  const events: Array<{ date: string; type: 'in' | 'out'; amount: number; reference: string }> = []
  for (const inv of invoices) {
    // `amount_due` et non `total` : c'est l'ÉCHÉANCE que le moteur compte.
    // Une facture aux 3 000 € dont 2 000 € sont encaissés ne pèse que 1 000
    // dans la prévision — avec `total`, elle en pesait 3 000.
    events.push({ date: inv.due_date, type: 'in', amount: Number(inv.amount_due ?? inv.total ?? 0), reference: inv.number })
  }
  for (const inv of purchaseInvoices) {
    events.push({ date: inv.due_date, type: 'out', amount: Number(inv.amount_due), reference: inv.number })
  }

  events.sort((a, b) => a.date.localeCompare(b.date))

  let runningBalance = currentBalance
  const timeline = events.map((e) => {
    runningBalance += e.type === 'in' ? e.amount : -e.amount
    return { ...e, runningBalance }
  })

  // Les ENTRÉES et SORTIES viennent du moteur aussi : la somme de la ligne
  // de temps est un récapitulatif d'affichage, pas une deuxième grandeur.
  return {
    currentBalance,
    timeline,
    totalIncoming: Number(previsionnel?.totalIncoming ?? 0),
    totalOutgoing: Number(previsionnel?.totalOutgoing ?? 0),
    // et l'ENGAGEMENT DE PRODUCTION, que rien ne rendait visible jusqu'ici
    productionMaterialCommitment: Number(previsionnel?.production_material_commitment ?? 0),
    productionLaborCommitment: Number(previsionnel?.production_labor_commitment ?? 0),
    productionCommitment: Number(previsionnel?.production_commitment ?? 0),
    netForecast: Number(previsionnel?.net_forecast ?? 0),
    netWithProduction: Number(previsionnel?.net_with_production ?? 0),
  }
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



// ============ Currency Revaluation ============
export async function getCurrencyRevaluations() {
  const tid = await getTenantId()
  let q = supabase.from('currency_revaluations').select('*').order('period_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as CurrencyRevaluation[]
}

// M01-03 (309) : la réévaluation de clôture **se calcule** — soldes en devise des
// comptes de tiers au taux du jour, écart en 666/766, lignes dans
// `currency_revaluations` et écriture. Idempotente par période (une période déjà
// réévaluée est refusée, pas réécrite en silence).
export interface CurrencyRevaluationVerdict {
  period_date: string
  lines: number
  gain_loss: number
  without_rate: number
  entry_id: string | null
}

export async function revaluateCurrencyBalances(periodDate: string): Promise<CurrencyRevaluationVerdict> {
  const { data, error } = await supabase.rpc('revaluate_currency_balances', { p_period_date: periodDate })
  if (error) throw error
  return data as CurrencyRevaluationVerdict
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
