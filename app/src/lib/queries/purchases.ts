import { supabase } from '@/lib/supabase';
import { getTenantId, tud } from './core';
import type { PurchaseOrder, PurchaseOrderLine } from '@/types';

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

export type OrderLineInput = { product_id: string | null; description: string; quantity: number; unit_price: number; vat_rate: number }

/**
 * C9 (280) : une commande fournisseur naît AVEC ses lignes, en un seul appel
 * atomique ; ses totaux sont calculés par la base (somme des lignes), jamais
 * saisis. Une commande sans ligne est refusée.
 */
export async function createPurchaseOrder(
  po: Pick<PurchaseOrder, 'number' | 'supplier_id' | 'order_date' | 'expected_date' | 'notes'>,
  lines: OrderLineInput[],
) {
  const { data, error } = await supabase.rpc('create_purchase_order', { p_order: po, p_lines: lines })
  if (error) throw error
  return data as unknown as PurchaseOrder
}

export async function getPurchaseOrderLines(orderId: string) {
  const tid = await getTenantId()
  let q = supabase.from('purchase_order_lines').select('*').eq('purchase_order_id', orderId).order('line_order').order('id')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as PurchaseOrderLine[]
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

