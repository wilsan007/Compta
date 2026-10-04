// ============================================================================
// Comptabilite — reconciliation.ts
// Extrait de l'ancien src/lib/queries/accounting.ts (4238 l.) le 2026-10-01.
// Decoupage par domaine ; imports recalcules ; aucun code metier modifie.
// ============================================================================

import { supabase } from '@/lib/supabase'
import { getTenantId, tud } from '../core'
import { type BankReconciliationRule, type BankStatementImport, type BankStatementTemplate } from '@/types'

// ============ Bank Reconciliation Rules (AFB) ============
export async function getBankReconciliationRules() {
  const tid = await getTenantId()
  let q = supabase.from('bank_reconciliation_rules').select('*').order('priority', { ascending: true })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as BankReconciliationRule[]
}

export async function createBankReconciliationRule(rule: Omit<BankReconciliationRule, 'id' | 'tenant_id' | 'created_at' | 'updated_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase
    .from('bank_reconciliation_rules')
    .insert({ ...rule, tenant_id: tid })
    .select()
    .single()
  if (error) throw error
  return data as BankReconciliationRule
}

export async function deleteBankReconciliationRule(id: string) {
  const tid = await getTenantId()
  if (!tid) throw new Error('No tenant context')
  const { error } = await supabase
    .from('bank_reconciliation_rules')
    .delete()
    .eq('id', id)
    .eq('tenant_id', tid)
  if (error) throw error
}



// ============ Bank Statement Imports ============
export async function getBankStatementImports() {
  const tid = await getTenantId()
  let q = supabase.from('bank_statement_imports').select('*').order('imported_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as BankStatementImport[]
}

export async function createBankStatementImport(imp: Omit<BankStatementImport, 'id' | 'tenant_id' | 'imported_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase
    .from('bank_statement_imports')
    .insert({ ...imp, tenant_id: tid })
    .select()
    .single()
  if (error) throw error
  return data as BankStatementImport
}



// ============ Bank Statement Templates (AI-learned PDF parsing) ============

export async function getBankStatementTemplates(): Promise<BankStatementTemplate[]> {
  const tid = await getTenantId()
  let q = supabase.from('bank_statement_templates').select('*').eq('is_active', true).order('bank_name')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as BankStatementTemplate[]
}

export async function createBankStatementTemplate(tpl: Omit<BankStatementTemplate, 'id' | 'created_at' | 'updated_at' | 'tenant_id'>): Promise<BankStatementTemplate> {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('bank_statement_templates').insert({ ...tpl, tenant_id: tid }).select().single()
  if (error) throw error
  return data as BankStatementTemplate
}

export async function updateBankStatementTemplate(id: string, updates: Partial<BankStatementTemplate>): Promise<BankStatementTemplate> {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('bank_statement_templates').update(updates), 'bank_statement_templates', tid).eq('id', id).select().single()
  if (error) throw error
  return data as BankStatementTemplate
}

export async function deleteBankStatementTemplate(id: string): Promise<void> {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('bank_statement_templates').delete(), 'bank_statement_templates', tid).eq('id', id)
  if (error) throw error
}
