import { supabase } from '@/lib/supabase'
import type { Joined } from '@/types/dbRow'
import { fetchAllRows, getTenantId } from './core'

// Hors de `stock.ts`, qui ne porte aucun appel RPC (W10 : le stock n'y est
// jamais remis à jour par le front — un seul moteur, le déclencheur).
// ============ D-B (280) : mouvements fantômes à valider ============
export interface StockMovementPhantom {
  id: string; movement_id: string; product_id: string | null; warehouse_id: string | null
  type: string; quantity: number; unit_cost: number | null; movement_date: string | null; reference: string | null
  detected_at: string; decision: 'pending' | 'replayed' | 'ignored'
}

export async function getStockMovementPhantoms() {
  const tid = await getTenantId()
  let q = supabase.from('stock_movement_phantoms').select('*, products(name, sku)').eq('decision', 'pending').order('movement_date').order('id')
  if (tid) q = q.eq('tenant_id', tid)
  return await fetchAllRows<StockMovementPhantom & { products: Joined<'products', 'name' | 'sku'> }>(q, { label: 'getStockMovementPhantoms' })
}

export async function resolveStockMovementPhantom(id: string, decision: 'replayed' | 'ignored') {
  const { data, error } = await supabase.rpc('resolve_stock_movement_phantom', { p_phantom_id: id, p_decision: decision })
  if (error) throw error
  return data
}
