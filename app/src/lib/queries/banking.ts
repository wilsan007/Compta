import { supabase } from '@/lib/supabase';
import { fetchAllRows, getTenantId, ti, tud } from './core';
import type { BankAccount, BankTransaction, BankRule, BankConnection, Bank } from '@/types';
import { parseBankStatement, detectBankStatementFormat, type BankStatementFormat } from '@/lib/bankParsers';

// ============ Bank Accounts ============
export async function getBankAccounts() {
  const tid = await getTenantId()
  let baQ = supabase.from('bank_accounts').select('*').order('name', { ascending: true }).order('id')
  if (tid) baQ = baQ.eq('tenant_id', tid)
  // LOT7-03 : la déduplication ci-dessous suppose de voir TOUS les comptes ; une liste
  // tronquée à 1 000 lignes laisserait passer des doublons.
  const accounts = await fetchAllRows<BankAccount>(baQ, { label: 'getBankAccounts' })
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

export async function autoMatchBankTransactions(accountId?: string): Promise<{ matched: number; unmatched: number }> {
  const tid = await getTenantId()
  let txQ = supabase.from('bank_transactions').select('*').eq('reconciled', false)
  if (tid) txQ = txQ.eq('tenant_id', tid)
  if (accountId) txQ = txQ.eq('account_id', accountId)
  const { data: txns, error: txErr } = await txQ
  if (txErr) throw txErr

  let jlQ = supabase.from('journal_lines').select('id, debit, credit, account_code, account_general, journal_entries!inner(date, journal_code, number, description)')
  if (tid) jlQ = jlQ.eq('tenant_id', tid)
  const { data: lines, error: jlErr } = await jlQ
  if (jlErr) throw jlErr

  let matched = 0
  let unmatched = 0

  for (const tx of txns || []) {
    const txAmount = Number(tx.amount)
    const txDate = tx.date
    const isCredit = tx.type === 'credit'

    const match = (lines || []).find((l: any) => {
      const lineAmount = isCredit ? Number(l.credit) : Number(l.debit)
      if (lineAmount !== txAmount) return false
      const entryDate = l.journal_entries?.date
      if (!entryDate) return false
      const diff = Math.abs(new Date(entryDate).getTime() - new Date(txDate).getTime())
      return diff <= 7 * 24 * 60 * 60 * 1000
    })

    if (match) {
      const { error: updErr } = await tud(supabase.from('bank_transactions').update({ reconciled: true, matched: true, matched_line_id: match.id }), 'bank_transactions', tid).eq('id', tx.id)
      if (updErr) throw updErr
      matched++
    } else {
      unmatched++
    }
  }

  return { matched, unmatched }
}


// ============ État de rapprochement (R-09) ============
// L'écran « État de rapprochement » lit `get_bank_reconciliation_state` (196, réécrite
// par la 223) : soldes du relevé et du compte 512x, écarts des DEUX côtés, pointages
// effectués, comparaison au solde de clôture du relevé importé. Les mutations passent
// par les RPC gardées : un drapeau posé d'un seul côté n'est pas un pointage.

export interface BankStatementEcart {
  id: string
  date: string
  label: string | null
  reference?: string | null
  type: 'debit' | 'credit'
  raw_amount: number
  amount: number
}

export interface BankLedgerEcart {
  id: string
  date: string
  entry_number: string | null
  entry_label?: string | null
  label: string | null
  debit: number
  credit: number
  amount: number
}

export interface BankReconciledPair {
  id: string
  date: string
  label: string | null
  type: 'debit' | 'credit'
  raw_amount: number
  amount: number
  reconciled_entry_id: string
  entry_number: string | null
  entry_date: string | null
  match_type: string | null
  matched_account_code: string | null
}

export interface BankReconciliationState {
  bank_account_id: string
  account_code: string | null
  statement_balance: number
  accounting_balance: number
  unmatched_debits: number
  unmatched_credits: number
  ledger_unmatched_debits: number
  ledger_unmatched_credits: number
  /** Intégrité des paires pointées — vrai par construction quand le pointage est cohérent */
  is_balanced: boolean
  unmatched_transactions: BankStatementEcart[]
  ledger_unmatched_transactions: BankLedgerEcart[]
  reconciled_transactions: BankReconciledPair[]
  difference: number
  explained_difference: number
  /** Plus aucun écart des deux côtés : la réponse à « est-ce rapproché ? » */
  is_reconciled: boolean
  unmatched_count: number
  ledger_unmatched_count: number
  reconciled_count: number
  statement_closing_balance: number | null
  closing_date: string | null
  closing_difference: number | null
  closing_matches: boolean | null
}

export async function getBankReconciliationState(bankAccountId: string, date: string) {
  const { data, error } = await supabase.rpc('get_bank_reconciliation_state', {
    p_bank_account_id: bankAccountId,
    p_date: date,
  })
  if (error) throw error
  const row = Array.isArray(data) ? data[0] : data
  return (row || null) as unknown as BankReconciliationState | null
}

/** Pointe une ligne de relevé contre une écriture du compte — les DEUX côtés */
export async function reconcileBankStatementLine(transactionId: string, journalLineId: string) {
  const { data, error } = await supabase.rpc('reconcile_bank_statement_line', {
    p_transaction_id: transactionId,
    p_journal_line_id: journalLineId,
  })
  if (error) throw error
  return data
}

/** Défait un pointage — les DEUX côtés reviennent dans les écarts */
export async function unreconcileBankStatementLine(transactionId: string) {
  const { data, error } = await supabase.rpc('unreconcile_bank_statement_line', {
    p_transaction_id: transactionId,
  })
  if (error) throw error
  return data
}

/** « Comptabiliser » une ligne de relevé non pointée (frais bancaires, agios…) */
export async function postBankStatementLine(transactionId: string, accountCode?: string | null, label?: string | null) {
  const { data, error } = await supabase.rpc('post_bank_statement_line', {
    p_transaction_id: transactionId,
    p_account_code: accountCode || null,
    p_label: label || null,
  })
  if (error) throw error
  return data
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


// ============ Delete Bank Account ============
export async function deleteBankAccount(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('bank_accounts').delete(), 'bank_accounts', tid).eq('id', id)
  if (error) throw error
}


// ============ Banks Registry (global, filtered by country) ============

export async function getBanks(countryCode?: string): Promise<Bank[]> {
  let q = supabase.from('banks').select('*').eq('is_active', true).order('name')
  if (countryCode) q = q.eq('country', countryCode)
  const { data, error } = await q
  if (error) throw error
  return data as Bank[]
}

export async function getCompanyCountry(): Promise<string | null> {
  const tid = await getTenantId()
  if (!tid) return null
  let q = supabase.from('company_settings').select('country, country_code').limit(1)
  q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) { console.error('getCompanyCountry:', error); return null }
  if (!data || data.length === 0) return null
  const cs = data[0] as any
  const raw = cs.country_code || cs.country || null
  if (!raw) return null
  // Convert ISO alpha-2 to alpha-3 (legislation_packs uses 2-letter codes)
  const alpha2ToAlpha3: Record<string, string> = {
    FR: 'FRA', GB: 'GBR', US: 'USA', MA: 'MAR', DZ: 'DZA', TN: 'TUN',
    SN: 'SEN', CI: 'CIV', CM: 'CMR', DE: 'DEU', ES: 'ESP', IT: 'ITA',
    DJ: 'DJI', ET: 'ETH', SA: 'SAU', AE: 'ARE', EG: 'EGY', NG: 'NGA',
    KE: 'KEN', ZA: 'ZAF', BE: 'BEL', NL: 'NLD', PT: 'PRT', CH: 'CHE',
    CA: 'CAN', AU: 'AUS', JP: 'JPN', CN: 'CHN', IN: 'IND', BR: 'BRA',
    MX: 'MEX', RU: 'RUS', TR: 'TUR', SE: 'SWE', NO: 'NOR', DK: 'DNK',
    FI: 'FIN', PL: 'POL', GR: 'GRC', IE: 'IRL', AT: 'AUT', CZ: 'CZE',
    HU: 'HUN', RO: 'ROU', BG: 'BGR', HR: 'HRV', SK: 'SVK', SI: 'SVN',
    LT: 'LTU', LV: 'LVA', EE: 'EST', LU: 'LUX', MT: 'MLT', CY: 'CYP',
    IS: 'ISL', QA: 'QAT', KW: 'KWT', BH: 'BHR', OM: 'OMN', JO: 'JOR',
    LB: 'LBN', IQ: 'IRQ', IR: 'IRN', SD: 'SDN', LY: 'LBY', MR: 'MRT',
    ML: 'MLI', BF: 'BFA', BJ: 'BEN', TG: 'TGO', NE: 'NER', GN: 'GIN',
    GQ: 'GNQ', GA: 'GAB', CG: 'COG', CD: 'COD', AO: 'AGO', MZ: 'MOZ',
    TZ: 'TZA', UG: 'UGA', RW: 'RWA', BI: 'BDI', SO: 'SOM', ER: 'ERI',
    MG: 'MDG', MU: 'MUS', SC: 'SYC', KM: 'COM', CV: 'CPV', GW: 'GNB',
    SL: 'SLE', LR: 'LBR', GH: 'GHA', NA: 'NAM', BW: 'BWA', ZM: 'ZMB',
    ZW: 'ZWE', LS: 'LSO', SZ: 'SWZ', MW: 'MWI',
  }
  const upper = raw.toUpperCase()
  // Already 3 letters
  if (upper.length === 3) return upper
  // Convert 2-letter to 3-letter
  if (upper.length === 2 && alpha2ToAlpha3[upper]) return alpha2ToAlpha3[upper]
  return upper
}


// ============ Bank Connections (#69) ============
export async function getBankConnections() {
  const tid = await getTenantId()
  let q = supabase.from('bank_connections').select('*').order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as BankConnection[]
}

export async function createBankConnection(conn: Omit<BankConnection, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('bank_connections').insert({ ...conn, tenant_id: tid }).select().single()
  if (error) throw error
  return data as BankConnection
}

export async function updateBankConnection(id: string, updates: Partial<BankConnection>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('bank_connections').update(updates), 'bank_connections', tid).eq('id', id).select().single()
  if (error) throw error
  return data as BankConnection
}

export async function deleteBankConnection(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('bank_connections').delete(), 'bank_connections', tid).eq('id', id)
  if (error) throw error
}

export async function syncBankConnection(connectionId: string): Promise<{ synced: number; error: string | null }> {
  const tid = await getTenantId()
  const { error: connErr } = await supabase.from('bank_connections').select('*').eq('id', connectionId).single()
  if (connErr) throw connErr
  const now = new Date().toISOString()
  const { error: updErr } = await tud(
    supabase.from('bank_connections').update({ last_sync_at: now, status: 'active', error_message: null }),
    'bank_connections', tid
  ).eq('id', connectionId)
  if (updErr) throw updErr
  return { synced: 0, error: null }
}



// ============ Import de relevé (AUD-G03) ============
export interface BankStatementImportSummary {
  format: BankStatementFormat
  parsed: number
  imported: number
  duplicates: number
  warnings: string[]
  /** R-10 : solde de clôture repris sur le compte — null si le relevé n'en portait pas, ou pas de date pour le porter */
  closingBalance?: number | null
  closingBalanceDate?: string | null
}

/**
 * Lit un relevé normé (CAMT.053, MT940, CFONB 120, OFX 1.x/2.x), écarte les opérations
 * déjà importées sur ce compte (même date, montant signé et référence), enregistre les
 * autres comme lignes de relevé (source « import ») et reprend le solde de clôture du
 * relevé sur le compte. Le serveur les pointe contre les écritures du compte de
 * trésorerie (migration 196).
 */
// ============================================================
// R-10 : le relevé refusé quand sa devise n'est pas celle du compte
//
// Un relevé en USD importé sur un compte en EUR écrit des montants qui n'ont pas
// la même unité que le solde du compte : ni le pointage automatique (montant égal)
// ni l'état de rapprochement (soldes comparés) ne veulent plus rien dire — et rien
// dans l'écran ne le signalait (LOC1-49). Le refus est explicite et porte un code,
// pour que l'écran puisse le traduire plutôt que d'afficher un message brut.
// ============================================================
export class BankStatementCurrencyError extends Error {
  readonly code = 'bank_statement_currency_mismatch'
  readonly statementCurrency: string
  readonly accountCurrency: string
  constructor(statementCurrency: string, accountCurrency: string) {
    super(`Devise du relevé (${statementCurrency}) différente de celle du compte (${accountCurrency})`)
    this.name = 'BankStatementCurrencyError'
    this.statementCurrency = statementCurrency
    this.accountCurrency = accountCurrency
  }
}

const normalizeCurrency = (value: unknown) => (typeof value === 'string' ? value.trim().toUpperCase() : '')

export async function importBankStatement(bankAccountId: string, filename: string, content: string, format?: BankStatementFormat): Promise<BankStatementImportSummary> {
  const tid = await getTenantId()
  const detected = format && format !== 'unknown' ? format : detectBankStatementFormat(content)
  const result = parseBankStatement(content, detected)
  const signed = (t: { type: string; amount: number }) => (t.type === 'debit' ? -Math.abs(t.amount) : Math.abs(t.amount))

  // Compte visé : sa devise fait foi (c'est celle de la comptabilité) et son
  // solde de clôture sera repris du relevé.
  const { data: account, error: accountError } = await supabase.from('bank_accounts')
    .select('id, currency, calculated_balance').eq('id', bankAccountId).maybeSingle()
  if (accountError) throw accountError

  const accountCurrency = normalizeCurrency(account?.currency)
  const statementCurrency = normalizeCurrency(result.currency)
  // Seule une devise RÉELLEMENT LUE dans le fichier peut fonder un refus : les lecteurs
  // retombent sur « EUR » quand le relevé n'en porte pas, et refuser sur ce repli ferait
  // échouer un relevé muet sur un compte en DJF.
  if (result.currencyFromFile && statementCurrency && accountCurrency && statementCurrency !== accountCurrency) {
    throw new BankStatementCurrencyError(statementCurrency, accountCurrency)
  }

  let q = supabase.from('bank_transactions').select('date, amount, type, reference')
    .eq('source', 'import').or(`bank_account_id.eq.${bankAccountId},account_id.eq.${bankAccountId}`).order('id')
  if (tid) q = q.eq('tenant_id', tid)
  const existing = await fetchAllRows<{ date: string; amount: number; type: string; reference: string | null }>(q, { label: 'importBankStatement/bank_transactions' })
  const known = new Set(existing.map(e => `${e.date}|${signed(e).toFixed(2)}|${e.reference || ''}`))

  const fresh = result.transactions.filter(t => {
    const key = `${t.date}|${signed(t).toFixed(2)}|${t.reference || ''}`
    if (known.has(key)) return false
    known.add(key) // une même opération répétée dans le fichier n'est importée qu'une fois
    return true
  })

  if (fresh.length > 0) {
    const { error } = await supabase.from('bank_transactions').insert(fresh.map(t => ti({
      account_id: bankAccountId,
      bank_account_id: bankAccountId,
      date: t.date,
      description: t.description,
      reference: t.reference || null,
      type: signed(t) < 0 ? 'debit' : 'credit',
      amount: Math.abs(t.amount),
      source: 'import',
      // R-07 : une ligne de relevé, par opposition au reflet d'un règlement saisi
      kind: 'statement',
      reconciled: false,
      matched: false,
    }, 'bank_transactions', tid)))
    if (error) throw error
  }

  // R-10 : le solde de CLÔTURE du relevé est la donnée qui manquait pour comparer le
  // compte à sa banque (LOC1-49) — `updateStatementBalance` (misc.ts) existait sans
  // appelant. Il n'est repris que si le lecteur en a trouvé un ET qu'il sait le dater :
  // sans date, l'état de rapprochement (223) ne comparerait rien.
  let closingBalance: number | null = null
  let closingBalanceDate: string | null = null
  if (result.closingBalance != null && result.periodEnd) {
    closingBalance = result.closingBalance
    closingBalanceDate = result.periodEnd
    const { error: balanceError } = await tud(supabase.from('bank_accounts').update({
      statement_balance: closingBalance,
      statement_balance_date: closingBalanceDate,
      reconciliation_diff: closingBalance - Number(account?.calculated_balance ?? 0),
    }), 'bank_accounts', tid).eq('id', bankAccountId)
    if (balanceError) throw balanceError
  }

  const failed = result.transactions.length === 0
  const { error: logError } = await supabase.from('bank_statement_imports').insert({
    tenant_id: tid,
    bank_account_id: bankAccountId,
    filename,
    format: detected,
    file_size: content.length,
    status: failed ? 'failed' : 'completed',
    imported_count: fresh.length,
    error_message: result.warnings.length > 0 ? result.warnings.join(' | ') : null,
  })
  if (logError) throw logError

  return { format: detected, parsed: result.transactions.length, imported: fresh.length, duplicates: result.transactions.length - fresh.length, warnings: result.warnings, closingBalance, closingBalanceDate }
}
