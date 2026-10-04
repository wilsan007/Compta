// ============================================================================
// misc — treasuryExt.ts
// Extrait de l'ancien misc.ts le 2026-10-01 ; imports recalcules ;
// aucun code metier modifie.
// ============================================================================

import { supabase } from '@/lib/supabase'
import { type Joined } from '@/types/dbRow'
import { getTenantId, ti, tud } from '../core'
import { type CreditLine, type Investment, type ValueDateTracking } from '@/types'

// ============ Phase 3: Credit Lines ============
export async function getCreditLines() {
  const tid = await getTenantId()
  let q = supabase.from('credit_lines').select('*, bank_accounts(name)').order('name')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as (CreditLine & { bank_accounts: Joined<'bank_accounts', 'name'> })[]
}
export async function createCreditLine(c: Omit<CreditLine, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('credit_lines').insert(ti(c, 'credit_lines', tid)).select().single()
  if (error) throw error
  return data as CreditLine
}
export async function updateCreditLine(id: string, updates: Partial<CreditLine>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('credit_lines').update(updates), 'credit_lines', tid).eq('id', id).select().single()
  if (error) throw error
  return data as CreditLine
}
export async function deleteCreditLine(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('credit_lines').delete(), 'credit_lines', tid).eq('id', id)
  if (error) throw error
}



// ============ Phase 3: Investments ============
export async function getInvestments() {
  const tid = await getTenantId()
  let q = supabase.from('investments').select('*').order('name')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as Investment[]
}
export async function createInvestment(i: Omit<Investment, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('investments').insert(ti(i, 'investments', tid)).select().single()
  if (error) throw error
  return data as Investment
}
export async function updateInvestment(id: string, updates: Partial<Investment>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('investments').update(updates), 'investments', tid).eq('id', id).select().single()
  if (error) throw error
  return data as Investment
}
export async function deleteInvestment(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('investments').delete(), 'investments', tid).eq('id', id)
  if (error) throw error
}



// ============ Phase 3: Value Date Tracking ============
export async function getValueDateTrackings() {
  const tid = await getTenantId()
  let q = supabase.from('value_date_tracking').select('*, bank_accounts(name)').order('value_date')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as (ValueDateTracking & { bank_accounts: Joined<'bank_accounts', 'name'> })[]
}
export async function createValueDateTracking(v: Omit<ValueDateTracking, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('value_date_tracking').insert(ti(v, 'value_date_tracking', tid)).select().single()
  if (error) throw error
  return data as ValueDateTracking
}
