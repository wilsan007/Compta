import { supabase } from '@/lib/supabase';
import type { Joined } from '@/types/dbRow'
import { fetchAllRows, getTenantId, ti, tud } from './core';
import type { ManufacturingOrder, QualityCheck, PickList } from '@/types';

// ============ Sprint 6: Manufacturing Orders ============
export async function getManufacturingOrders(status?: string) {
  const tid = await getTenantId()
  let q = supabase.from('manufacturing_orders').select('*, boms(name, code), products(name, sku), warehouses(name), routings(name, code)').order('created_at', { ascending: false }).order('id')
  if (tid) q = q.eq('tenant_id', tid)
  if (status) q = q.eq('status', status)
  // LOT7-03 : autoScheduleMOs ordonnance à partir de cette liste — elle doit être complète.
  return await fetchAllRows<ManufacturingOrder>(q, { label: 'getManufacturingOrders' })
}

export async function createManufacturingOrder(mo: Omit<ManufacturingOrder, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('manufacturing_orders').insert(ti(mo, 'manufacturing_orders', tid)).select().single()
  if (error) throw error
  return data as ManufacturingOrder
}

export async function updateManufacturingOrder(id: string, updates: Partial<ManufacturingOrder>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('manufacturing_orders').update(updates), 'manufacturing_orders', tid).eq('id', id).select().single()
  if (error) throw error
  return data as ManufacturingOrder
}

export async function deleteManufacturingOrder(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('manufacturing_orders').delete(), 'manufacturing_orders', tid).eq('id', id)
  if (error) throw error
}


// ============ Phase 2: Quality Checks ============
export async function getQualityChecks() {
  const tid = await getTenantId()
  let q = supabase.from('quality_checks').select('*, products(name, sku)').order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as (QualityCheck & { products: Joined<'products', 'name' | 'sku'> })[]
}
export async function createQualityCheck(qc: Omit<QualityCheck, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('quality_checks').insert(ti(qc, 'quality_checks', tid)).select().single()
  if (error) throw error
  return data as QualityCheck
}
export async function updateQualityCheck(id: string, updates: Partial<QualityCheck>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('quality_checks').update(updates), 'quality_checks', tid).eq('id', id).select().single()
  if (error) throw error
  return data as QualityCheck
}


// ============ Phase 2: Pick Lists ============
export async function getPickLists() {
  const tid = await getTenantId()
  let q = supabase.from('pick_lists').select('*, warehouses(name)').order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as (PickList & { warehouses: Joined<'warehouses', 'name'> })[]
}
export async function createPickList(p: Omit<PickList, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('pick_lists').insert(ti(p, 'pick_lists', tid)).select().single()
  if (error) throw error
  return data as PickList
}
export async function updatePickList(id: string, updates: Partial<PickList>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('pick_lists').update(updates), 'pick_lists', tid).eq('id', id).select().single()
  if (error) throw error
  return data as PickList
}

// ============ PRD-09 : Sous-traitance ============

export async function getStockAtSubcontractors() {
  const { data, error } = await supabase.rpc('get_stock_at_subcontractors')
  if (error) throw error
  return data as any[]
}

// ============ IMP-01 : Reprise de données ============

export async function importOpeningBalance(balanceData: any[]) {
  const { data, error } = await supabase.rpc('import_opening_balance', {
    p_balance_data: balanceData,
  })
  if (error) throw error
  return data as any[]
}

export async function logDataImport(
  importType: string,
  fileName: string,
  totalRows: number,
  importedRows: number,
  rejectedRows: number,
  status: string,
  errorDetails?: any
) {
  const tid = await getTenantId()
  const { data, error } = await supabase
    .from('data_import_logs')
    .insert(ti({
      import_type: importType,
      file_name: fileName,
      total_rows: totalRows,
      imported_rows: importedRows,
      rejected_rows: rejectedRows,
      status,
      error_details: errorDetails,
      started_at: new Date().toISOString(),
      completed_at: status === 'completed' || status === 'partial' ? new Date().toISOString() : null,
    }, 'data_import_logs', tid))
    .select()
    .single()
  if (error) throw error
  return data
}

