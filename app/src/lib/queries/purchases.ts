import { supabase } from '@/lib/supabase';
import { getTenantId, ti, tud } from './core';
import type { PurchaseOrder } from '@/types';

// ============ Sprint 6: Purchase Orders ============
export async function getPurchaseOrders(status?: string) {
  const tid = await getTenantId()
  let q = supabase.from('purchase_orders').select('*').order('order_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (status) q = q.eq('status', status)
  const { data, error } = await q
  if (error) throw error
  return data as PurchaseOrder[]
}

export async function createPurchaseOrder(po: Omit<PurchaseOrder, 'id' | 'created_at' | 'updated_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('purchase_orders').insert(ti(po, 'purchase_orders', tid)).select().single()
  if (error) throw error
  return data as PurchaseOrder
}

export async function updatePurchaseOrder(id: string, updates: Partial<PurchaseOrder>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('purchase_orders').update({ ...updates, updated_at: new Date().toISOString() }), 'purchase_orders', tid).eq('id', id).select().single()
  if (error) throw error
  return data as PurchaseOrder
}

export async function deletePurchaseOrder(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('purchase_orders').delete(), 'purchase_orders', tid).eq('id', id)
  if (error) throw error
}

