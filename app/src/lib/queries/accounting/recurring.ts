// ============================================================================
// Comptabilite — recurring.ts
// Extrait de l'ancien src/lib/queries/accounting.ts (4238 l.) le 2026-10-01.
// Decoupage par domaine ; imports recalcules ; aucun code metier modifie.
// ============================================================================

import { supabase } from '@/lib/supabase'
import { type Joined } from '@/types/dbRow'
import { getTenantId, ti, tud } from '../core'
import { type Invoice, type RecurringEntry, type RegularizationEntry, type RecurringInvoiceTemplate } from '@/types'

// ============ Recurring Invoices ============
export async function getRecurringInvoices() {
  const tid = await getTenantId()
  let q = supabase
    .from('invoices')
    .select('*, invoice_lines(*)')
    .eq('recurring', true)
    .order('date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as Invoice[]
}

export async function toggleRecurringInvoice(id: string, recurring: boolean, frequency?: string) {
  const tid = await getTenantId()
  const updates: Partial<Invoice> = { recurring }
  if (frequency) updates.recurring_frequency = frequency
  const { data, error } = await tud(supabase.from('invoices').update(updates), 'invoices', tid).eq('id', id).select().single()
  if (error) throw error
  return data as Invoice
}



// ============ Recurring Entries (Écritures d'abonnement) ============
export async function getRecurringEntries() {
  const tid = await getTenantId()
  let q = supabase.from('recurring_entries').select('*').order('next_generation_date', { ascending: true })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as RecurringEntry[]
}

export async function createRecurringEntry(entry: Omit<RecurringEntry, 'id' | 'tenant_id' | 'created_at' | 'updated_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase
    .from('recurring_entries')
    .insert({ ...entry, tenant_id: tid })
    .select()
    .single()
  if (error) throw error
  return data as RecurringEntry
}

export async function updateRecurringEntry(id: string, updates: Partial<RecurringEntry>) {
  const tid = await getTenantId()
  const { data, error } = await supabase
    .from('recurring_entries')
    .update({ ...updates, updated_at: new Date().toISOString() })
    .eq('id', id)
    .eq('tenant_id', tid ?? '')
    .select()
    .single()
  if (error) throw error
  return data as RecurringEntry
}

export async function deleteRecurringEntry(id: string) {
  const tid = await getTenantId()
  const { error } = await supabase
    .from('recurring_entries')
    .delete()
    .eq('id', id)
    .eq('tenant_id', tid ?? '')
  if (error) throw error
}

export async function generateRecurringEntry(id: string) {
  const tid = await getTenantId()
  const { data, error } = await supabase
    .rpc('generate_recurring_entry', { p_entry_id: id, p_tenant_id: tid })
  if (error) throw error
  return data
}



// ============ Regularization Entries (CCA/PCA/PRC/CRC) ============
export async function getRegularizationEntries(type?: string) {
  const tid = await getTenantId()
  let q = supabase.from('regularization_entries').select('*').order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (type) q = q.eq('type', type)
  const { data, error } = await q
  if (error) throw error
  return data as RegularizationEntry[]
}

export async function createRegularizationEntry(entry: Omit<RegularizationEntry, 'id' | 'tenant_id' | 'created_at' | 'updated_at' | 'used_amount' | 'remaining_amount' | 'created_entry_id' | 'extourne_entry_id'>) {
  const tid = await getTenantId()
  const payload = { ...entry, tenant_id: tid, used_amount: 0, remaining_amount: entry.amount }
  const { data, error } = await supabase
    .from('regularization_entries')
    .insert(payload)
    .select()
    .single()
  if (error) throw error
  return data as RegularizationEntry
}

export async function updateRegularizationEntry(id: string, updates: Partial<RegularizationEntry>) {
  const tid = await getTenantId()
  const { data, error } = await supabase
    .from('regularization_entries')
    .update({ ...updates, updated_at: new Date().toISOString() })
    .eq('id', id)
    .eq('tenant_id', tid ?? '')
    .select()
    .single()
  if (error) throw error
  return data as RegularizationEntry
}

export async function deleteRegularizationEntry(id: string) {
  const tid = await getTenantId()
  const { error } = await supabase
    .from('regularization_entries')
    .delete()
    .eq('id', id)
    .eq('tenant_id', tid ?? '')
  if (error) throw error
}



// ============ Phase 2: Recurring Invoice Templates ============
export async function getRecurringInvoiceTemplates() {
  const tid = await getTenantId()
  let q = supabase.from('recurring_invoice_templates').select('*, customers(name)').order('name')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as (RecurringInvoiceTemplate & { customers: Joined<'customers', 'name'> })[]
}
export async function createRecurringInvoiceTemplate(t: Omit<RecurringInvoiceTemplate, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('recurring_invoice_templates').insert(ti(t, 'recurring_invoice_templates', tid)).select().single()
  if (error) throw error
  return data as RecurringInvoiceTemplate
}
export async function deleteRecurringInvoiceTemplate(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('recurring_invoice_templates').delete(), 'recurring_invoice_templates', tid).eq('id', id)
  if (error) throw error
}
