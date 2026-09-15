import { supabase } from '@/lib/supabase';
import { getTenantId, ti, tud } from './core';
import type { BankAccount, BankTransaction, BankRule, BankConnection, Bank } from '@/types';

// ============ Bank Accounts ============
export async function getBankAccounts() {
  const tid = await getTenantId()
  let baQ = supabase.from('bank_accounts').select('*').order('name', { ascending: true })
  if (tid) baQ = baQ.eq('tenant_id', tid)
  const { data, error } = await baQ
  if (error) throw error

  const accounts = (data || []) as BankAccount[]
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

