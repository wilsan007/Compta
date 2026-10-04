// ============================================================================
// Comptabilite — vat.ts
// Extrait de l'ancien src/lib/queries/accounting.ts (4238 l.) le 2026-10-01.
// Decoupage par domaine ; imports recalcules ; aucun code metier modifie.
// ============================================================================

import { supabase } from '@/lib/supabase'
import { getTenantId, ti, tud } from '../core'
import { type VatReturn, type TaxRate, type TvsDeclaration, type PayrollTaxGrid, type PayrollTaxGridLine, type CorporateTaxGrid, type CorporateTaxGridLine, type TaxGroup, type TaxRepartitionLine, type TaxCashBasisEntry } from '@/types'

// ============ VAT Returns ============
export async function getVatReturns() {
  const tid = await getTenantId()
  let q = supabase.from('vat_returns').select('*').order('period_start', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as VatReturn[]
}

export async function createVatReturn(vat: Omit<VatReturn, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('vat_returns').insert(ti(vat, 'vat_returns', tid)).select().single()
  if (error) throw error
  return data as VatReturn
}



// ============ VAT Returns (full CRUD) ============
export async function updateVatReturn(id: string, updates: Partial<VatReturn>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('vat_returns').update(updates), 'vat_returns', tid).eq('id', id).select().single()
  if (error) throw error
  return data as VatReturn
}

export async function deleteVatReturn(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('vat_returns').delete(), 'vat_returns', tid).eq('id', id)
  if (error) throw error
}



// ============ TVS (Taxe Véhicules de Société) ============
export async function getTvsDeclarations() {
  const tid = await getTenantId()
  let q = supabase.from('tvs_declarations').select('*').order('fiscal_year', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as TvsDeclaration[]
}

export async function createTvsDeclaration(decl: Omit<TvsDeclaration, 'id' | 'tenant_id' | 'created_at' | 'updated_at' | 'filed_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase
    .from('tvs_declarations')
    .insert({ ...decl, tenant_id: tid })
    .select()
    .single()
  if (error) throw error
  return data as TvsDeclaration
}

export async function deleteTvsDeclaration(id: string) {
  const tid = await getTenantId()
  if (!tid) throw new Error('No tenant context')
  const { error } = await supabase
    .from('tvs_declarations')
    .delete()
    .eq('id', id)
    .eq('tenant_id', tid)
  if (error) throw error
}



// ============ Tax Rates (enriched CRUD) ============

export async function getTaxRates(): Promise<TaxRate[]> {
  const tid = await getTenantId()
  let q = supabase.from('tax_rates').select('*').order('rate', { ascending: false })
  if (tid) q = q.or(`tenant_id.is.null,tenant_id.eq.${tid}`)
  const { data, error } = await q
  if (error) throw error
  return data as TaxRate[]
}

export async function createTaxRate(tr: Omit<TaxRate, 'id' | 'created_at' | 'tenant_id'>): Promise<TaxRate> {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('tax_rates').insert({ ...tr, tenant_id: tid }).select().single()
  if (error) throw error
  return data as TaxRate
}

export async function updateTaxRate(id: string, updates: Partial<TaxRate>): Promise<TaxRate> {
  const { data, error } = await supabase.from('tax_rates').update(updates).eq('id', id).select().single()
  if (error) throw error
  return data as TaxRate
}

export async function deleteTaxRate(id: string): Promise<void> {
  const { error } = await supabase.from('tax_rates').delete().eq('id', id)
  if (error) throw error
}



// ============ Tax Groups (#11) ============

export async function getTaxGroups(): Promise<TaxGroup[]> {
  const tid = await getTenantId()
  let q = supabase.from('tax_groups').select('*').order('name', { ascending: true })
  if (tid) q = q.or(`tenant_id.is.null,tenant_id.eq.${tid}`)
  const { data, error } = await q
  if (error) throw error
  return data as TaxGroup[]
}

export async function createTaxGroup(tg: Omit<TaxGroup, 'id' | 'created_at' | 'tenant_id'>): Promise<TaxGroup> {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('tax_groups').insert({ ...tg, tenant_id: tid }).select().single()
  if (error) throw error
  return data as TaxGroup
}

export async function deleteTaxGroup(id: string): Promise<void> {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('tax_groups').delete(), 'tax_groups', tid).eq('id', id)
  if (error) throw error
}



// ============ Tax Repartition Lines (#18) ============

export async function getTaxRepartitionLines(taxId: string): Promise<TaxRepartitionLine[]> {
  const tid = await getTenantId()
  let q = supabase.from('tax_repartition_lines').select('*').eq('tax_id', taxId).order('repartition_type', { ascending: true })
  if (tid) q = q.or(`tenant_id.is.null,tenant_id.eq.${tid}`)
  const { data, error } = await q
  if (error) throw error
  return data as TaxRepartitionLine[]
}

export async function createTaxRepartitionLine(line: Omit<TaxRepartitionLine, 'id' | 'created_at' | 'tenant_id'>): Promise<TaxRepartitionLine> {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('tax_repartition_lines').insert({ ...line, tenant_id: tid }).select().single()
  if (error) throw error
  return data as TaxRepartitionLine
}

export async function deleteTaxRepartitionLine(id: string): Promise<void> {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('tax_repartition_lines').delete(), 'tax_repartition_lines', tid).eq('id', id)
  if (error) throw error
}



// ============ Tax Cash Basis Entries (#20) ============

export async function getTaxCashBasisEntries(): Promise<TaxCashBasisEntry[]> {
  const tid = await getTenantId()
  let q = supabase.from('tax_cash_basis_entries').select('*').order('created_at', { ascending: false })
  if (tid) q = q.or(`tenant_id.is.null,tenant_id.eq.${tid}`)
  const { data, error } = await q
  if (error) throw error
  return data as TaxCashBasisEntry[]
}

export async function createTaxCashBasisEntry(entry: Omit<TaxCashBasisEntry, 'id' | 'created_at' | 'tenant_id'>): Promise<TaxCashBasisEntry> {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('tax_cash_basis_entries').insert({ ...entry, tenant_id: tid }).select().single()
  if (error) throw error
  return data as TaxCashBasisEntry
}

export async function updateTaxCashBasisEntry(id: string, updates: Partial<TaxCashBasisEntry>): Promise<void> {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('tax_cash_basis_entries').update(updates), 'tax_cash_basis_entries', tid).eq('id', id)
  if (error) throw error
}



// ============ Tax Grids (Payroll & Corporate) ============

// --- Payroll Tax Grids ---
export async function getPayrollTaxGrids(countryCode?: string) {
  const tid = await getTenantId()
  let q = supabase
    .from('payroll_tax_grids')
    .select('*')
    .order('created_at', { ascending: false })
  if (tid) q = q.or(`tenant_id.eq.${tid},tenant_id.is.null`)
  if (countryCode) q = q.eq('country_code', countryCode)
  const { data, error } = await q
  if (error) throw error
  return data as PayrollTaxGrid[]
}

export async function getPayrollTaxGridLines(gridId: string) {
  const tid = await getTenantId()
  const { data: grid } = await supabase
    .from('payroll_tax_grids')
    .select('id, tenant_id')
    .eq('id', gridId)
    .or(`tenant_id.eq.${tid},tenant_id.is.null`)
    .maybeSingle()
  if (!grid) throw new Error('Grille introuvable ou accès non autorisé')
  const { data, error } = await supabase
    .from('payroll_tax_grid_lines')
    .select('*')
    .eq('grid_id', gridId)
    .order('sort_order', { ascending: true })
  if (error) throw error
  return data as PayrollTaxGridLine[]
}

export async function createPayrollTaxGrid(grid: Omit<PayrollTaxGrid, 'id' | 'tenant_id' | 'created_at' | 'updated_at'>) {
  const tid = await getTenantId()
  const payload = { ...grid, tenant_id: tid }
  const { data, error } = await supabase
    .from('payroll_tax_grids')
    .insert(payload)
    .select()
    .single()
  if (error) throw error
  return data as PayrollTaxGrid
}

export async function updatePayrollTaxGrid(id: string, updates: Partial<PayrollTaxGrid>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase
    .from('payroll_tax_grids')
    .update({ ...updates, updated_at: new Date().toISOString() }), 'payroll_tax_grids', tid)
    .eq('id', id)
    .select()
    .single()
  if (error) throw error
  return data as PayrollTaxGrid
}

export async function deletePayrollTaxGrid(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase
    .from('payroll_tax_grids')
    .delete(), 'payroll_tax_grids', tid)
    .eq('id', id)
  if (error) throw error
}

export async function createPayrollTaxGridLines(lines: Omit<PayrollTaxGridLine, 'id' | 'created_at'>[]) {
  const tid = await getTenantId()
  const { data, error } = await supabase
    .from('payroll_tax_grid_lines')
    .insert(lines.map(l => ti(l, 'payroll_tax_grid_lines', tid)))
    .select()
  if (error) throw error
  return data as PayrollTaxGridLine[]
}

export async function deletePayrollTaxGridLines(gridId: string) {
  const tid = await getTenantId()
  let gridQ = supabase
    .from('payroll_tax_grids')
    .select('id')
    .eq('id', gridId)
  if (tid) gridQ = gridQ.eq('tenant_id', tid)
  const { data: grid, error: gridErr } = await gridQ.maybeSingle()
  if (gridErr) throw gridErr
  // maybeSingle() rend null sans erreur quand la grille est celle d'une autre société :
  // sans ce test, le contrôle d'appartenance passe et la suppression part quand même.
  if (!grid) throw new Error('Grille de paie introuvable')
  const { error } = await tud(supabase
    .from('payroll_tax_grid_lines')
    .delete(), 'payroll_tax_grid_lines', tid)
    .eq('grid_id', gridId)
  if (error) throw error
}

// --- Corporate Tax Grids ---
export async function getCorporateTaxGrids(countryCode?: string) {
  const tid = await getTenantId()
  let q = supabase
    .from('corporate_tax_grids')
    .select('*')
    .order('created_at', { ascending: false })
  if (tid) q = q.or(`tenant_id.eq.${tid},tenant_id.is.null`)
  if (countryCode) q = q.eq('country_code', countryCode)
  const { data, error } = await q
  if (error) throw error
  return data as CorporateTaxGrid[]
}

export async function getCorporateTaxGridLines(gridId: string) {
  const tid = await getTenantId()
  const { data: grid } = await supabase
    .from('corporate_tax_grids')
    .select('id, tenant_id')
    .eq('id', gridId)
    .or(`tenant_id.eq.${tid},tenant_id.is.null`)
    .maybeSingle()
  if (!grid) throw new Error('Grille introuvable ou accès non autorisé')
  const { data, error } = await supabase
    .from('corporate_tax_grid_lines')
    .select('*')
    .eq('grid_id', gridId)
    .order('sort_order', { ascending: true })
  if (error) throw error
  return data as CorporateTaxGridLine[]
}

export async function createCorporateTaxGrid(grid: Omit<CorporateTaxGrid, 'id' | 'tenant_id' | 'created_at' | 'updated_at'>) {
  const tid = await getTenantId()
  const payload = { ...grid, tenant_id: tid }
  const { data, error } = await supabase
    .from('corporate_tax_grids')
    .insert(payload)
    .select()
    .single()
  if (error) throw error
  return data as CorporateTaxGrid
}

export async function updateCorporateTaxGrid(id: string, updates: Partial<CorporateTaxGrid>) {
  const tid = await getTenantId()
  const { data, error } = await supabase
    .from('corporate_tax_grids')
    .update({ ...updates, updated_at: new Date().toISOString() })
    .eq('id', id)
    .eq('tenant_id', tid ?? '')
    .select()
    .single()
  if (error) throw error
  return data as CorporateTaxGrid
}

export async function deleteCorporateTaxGrid(id: string) {
  const tid = await getTenantId()
  const { error } = await supabase
    .from('corporate_tax_grids')
    .delete()
    .eq('id', id)
    .eq('tenant_id', tid ?? '')
  if (error) throw error
}

export async function createCorporateTaxGridLines(lines: Omit<CorporateTaxGridLine, 'id' | 'created_at'>[]) {
  const tid = await getTenantId()
  const { data, error } = await supabase
    .from('corporate_tax_grid_lines')
    .insert(lines.map(l => ti(l, 'corporate_tax_grid_lines', tid)))
    .select()
  if (error) throw error
  return data as CorporateTaxGridLine[]
}

export async function deleteCorporateTaxGridLines(gridId: string) {
  const tid = await getTenantId()
  const { data: grid, error: gridErr } = await supabase
    .from('corporate_tax_grids')
    .select('id')
    .eq('id', gridId)
    .eq('tenant_id', tid ?? '')
    .maybeSingle()
  if (gridErr) throw gridErr
  // Même piège qu'en paie : sans ce test, une grille d'une autre société passe le contrôle.
  if (!grid) throw new Error('Grille d\'impôt société introuvable')
  const { error } = await tud(supabase
    .from('corporate_tax_grid_lines')
    .delete(), 'corporate_tax_grid_lines', tid)
    .eq('grid_id', gridId)
  if (error) throw error
}

// --- Helper: get active payroll tax grid for a country ---
export async function getActivePayrollTaxGrid(countryCode: string, gridType?: string) {
  const tid = await getTenantId()
  let q = supabase
    .from('payroll_tax_grids')
    .select('*')
    .eq('country_code', countryCode)
    .eq('status', 'active')
    .order('is_default', { ascending: false })
    .limit(1)
  if (gridType) q = q.eq('grid_type', gridType)
  if (tid) q = q.or(`tenant_id.eq.${tid},tenant_id.is.null`)
  const { data, error } = await q
  if (error) throw error
  return data?.[0] as PayrollTaxGrid | undefined
}

// --- Helper: get active corporate tax grid for a country ---
export async function getActiveCorporateTaxGrid(countryCode: string, taxType?: string) {
  const tid = await getTenantId()
  let q = supabase
    .from('corporate_tax_grids')
    .select('*')
    .eq('country_code', countryCode)
    .eq('status', 'active')
    .order('is_default', { ascending: false })
    .limit(1)
  if (taxType) q = q.eq('tax_type', taxType)
  if (tid) q = q.or(`tenant_id.eq.${tid},tenant_id.is.null`)
  const { data, error } = await q
  if (error) throw error
  return data?.[0] as CorporateTaxGrid | undefined
}
