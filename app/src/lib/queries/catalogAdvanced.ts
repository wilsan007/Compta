import { supabase } from '@/lib/supabase'
import { fetchAllRows, getTenantId, ti, tud } from './core'
import type { ProductGrid, ProductGridCombination, ProductPackaging, ProductLink, Promotion, WarehouseUser, StockAlert, Product } from '@/types'

// ============ Sprint D: Product Grids ============

export async function getProductGrids(productId: string) {
  const tid = await getTenantId()
  let q = supabase.from('product_grids').select('*').eq('product_id', productId).order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as ProductGrid[]
}

export async function createProductGrid(grid: Omit<ProductGrid, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('product_grids').insert(ti(grid, 'product_grids', tid)).select().single()
  if (error) throw error
  return data as ProductGrid
}

export async function deleteProductGrid(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('product_grids').delete(), 'product_grids', tid).eq('id', id)
  if (error) throw error
}

// ============ Sprint D: Product Grid Combinations ============

export async function getProductGridCombinations(productId: string) {
  const tid = await getTenantId()
  let q = supabase.from('product_grid_combinations').select('*').eq('product_id', productId).order('created_at', { ascending: false }).order('id')
  if (tid) q = q.eq('tenant_id', tid)
  // LOT7-03 : generateAllCombinations s'appuie sur cette liste pour ne pas recréer une
  // déclinaison existante. Tronquée à 1 000, elle produisait des doublons de SKU.
  return await fetchAllRows<ProductGridCombination>(q, { label: 'getProductGridCombinations' })
}

export async function createProductGridCombination(combo: Omit<ProductGridCombination, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('product_grid_combinations').insert(ti(combo, 'product_grid_combinations', tid)).select().single()
  if (error) throw error
  return data as ProductGridCombination
}

export async function generateAllCombinations(productId: string) {
  const tid = await getTenantId()
  const grids = await getProductGrids(productId)
  if (grids.length === 0) return []

  const axisValues: Record<string, string[]> = {}
  for (const g of grids) {
    if (g.active && g.values && g.values.length > 0) {
      axisValues[g.name] = g.values
    }
  }

  const keys = Object.keys(axisValues)
  if (keys.length === 0) return []

  function cartesian(arrays: string[][], index: number, current: string[]): string[][] {
    if (index === arrays.length) return [current]
    const result: string[][] = []
    for (const val of arrays[index]) {
      result.push(...cartesian(arrays, index + 1, [...current, val]))
    }
    return result
  }

  const combos = cartesian(keys.map(k => axisValues[k]), 0, [])
  const existing = await getProductGridCombinations(productId)
  const existingSet = new Set(existing.map(e => JSON.stringify(e.combination)))

  const newCombos: Omit<ProductGridCombination, 'id' | 'created_at'>[] = []
  for (const c of combos) {
    const combination: Record<string, string> = {}
    keys.forEach((k, i) => { combination[k] = c[i] })
    const key = JSON.stringify(combination)
    if (!existingSet.has(key)) {
      newCombos.push({
        tenant_id: tid,
        product_id: productId,
        combination,
        sku: null,
        barcode: null,
        price_override: null,
        stock_quantity: 0,
        active: true,
      })
    }
  }

  if (newCombos.length > 0) {
    const { data, error } = await supabase.from('product_grid_combinations').insert(newCombos.map(c => ti(c, 'product_grid_combinations', tid))).select()
    if (error) throw error
    return data as ProductGridCombination[]
  }
  return []
}

// ============ Sprint D: Product Packagings ============

export async function getProductPackagings(productId: string) {
  const tid = await getTenantId()
  let q = supabase.from('product_packagings').select('*').eq('product_id', productId).order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as ProductPackaging[]
}

export async function createProductPackaging(packaging: Omit<ProductPackaging, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('product_packagings').insert(ti(packaging, 'product_packagings', tid)).select().single()
  if (error) throw error
  return data as ProductPackaging
}

export async function deleteProductPackaging(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('product_packagings').delete(), 'product_packagings', tid).eq('id', id)
  if (error) throw error
}

// ============ Sprint D: Product Links ============

export async function getProductLinks(productId: string) {
  const tid = await getTenantId()
  let q = supabase.from('product_links').select('*, linked_product:products!linked_product_id(name, sku)').eq('product_id', productId).order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as (ProductLink & { linked_product: Pick<Product, 'name' | 'sku'> | null })[]
}

export async function createProductLink(link: Omit<ProductLink, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('product_links').insert(ti(link, 'product_links', tid)).select().single()
  if (error) throw error
  return data as ProductLink
}

export async function deleteProductLink(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('product_links').delete(), 'product_links', tid).eq('id', id)
  if (error) throw error
}

// ============ Sprint D: Promotions ============

export async function getPromotions(activeOnly?: boolean) {
  const tid = await getTenantId()
  let q = supabase.from('promotions').select('*').order('start_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (activeOnly) q = q.eq('active', true)
  const { data, error } = await q
  if (error) throw error
  return data as Promotion[]
}

export async function createPromotion(promo: Omit<Promotion, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('promotions').insert(ti(promo, 'promotions', tid)).select().single()
  if (error) throw error
  return data as Promotion
}

export async function updatePromotion(id: string, updates: Partial<Promotion>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('promotions').update(updates), 'promotions', tid).eq('id', id).select().single()
  if (error) throw error
  return data as Promotion
}

export async function deletePromotion(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('promotions').delete(), 'promotions', tid).eq('id', id)
  if (error) throw error
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

export async function applyPromotion(productId: string, customerId: string | null, quantity: number) {
  if (!UUID_RE.test(productId)) throw new Error('Invalid product ID format')
  const tid = await getTenantId()
  const now = new Date().toISOString().split('T')[0]
  let q = supabase.from('promotions').select('*').eq('active', true).lte('start_date', now).gte('end_date', now).or(`product_id.eq.${productId},product_id.is.null`)
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error

  const promos = (data || []).filter((p: any) => {
    if (Number(p.min_quantity || 1) > quantity) return false
    if (customerId && p.customer_id && p.customer_id !== customerId) return false
    return true
  })
  if (promos.length === 0) return null

  const promo = promos[0] as Promotion
  return {
    promotion: promo,
    discount: promo.promo_type === 'percentage' ? Number(promo.value || 0) : Number(promo.value || 0),
    type: promo.promo_type,
  }
}

// ============ Sprint E: Warehouse Users ============

export async function getWarehouseUsers(warehouseId: string) {
  const tid = await getTenantId()
  let q = supabase.from('warehouse_users').select('*').eq('warehouse_id', warehouseId).order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as WarehouseUser[]
}

export async function assignWarehouseUser(wu: Omit<WarehouseUser, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('warehouse_users').insert(ti(wu, 'warehouse_users', tid)).select().single()
  if (error) throw error
  return data as WarehouseUser
}

export async function removeWarehouseUser(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('warehouse_users').delete(), 'warehouse_users', tid).eq('id', id)
  if (error) throw error
}

// ============ Sprint E: Stock Alerts ============

export async function getStockAlerts(status?: 'active' | 'acknowledged' | 'resolved') {
  const tid = await getTenantId()
  let q = supabase.from('stock_alerts').select('*, product:products(name, sku), warehouse:warehouses(name)').order('triggered_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (status) q = q.eq('status', status)
  const { data, error } = await q
  if (error) throw error
  return data as (StockAlert & { product: Pick<Product, 'name' | 'sku'> | null, warehouse: { name: string } | null })[]
}

export async function acknowledgeStockAlert(id: string) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('stock_alerts').update({ status: 'acknowledged' }), 'stock_alerts', tid).eq('id', id).select().single()
  if (error) throw error
  return data as StockAlert
}

export async function resolveStockAlert(id: string) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('stock_alerts').update({ status: 'resolved', resolved_at: new Date().toISOString() }), 'stock_alerts', tid).eq('id', id).select().single()
  if (error) throw error
  return data as StockAlert
}

export async function checkStockThresholds() {
  const tid = await getTenantId()
  let qS = supabase.from('stock_quantities').select('product_id, warehouse_id, quantity, reserved_quantity')
  if (tid) qS = qS.eq('tenant_id', tid)
  const { data: stock, error } = await qS
  if (error) throw error

  // AUD-G07 (G18) : products n'a ni min_stock_level ni max_stock_level ; le seuil
  // bas est le stock de sécurité (à défaut, le point de commande). Aucun seuil haut
  // n'existe : l'alerte de surstock n'est pas calculable.
  let qP = supabase.from('products').select('id, name, sku, safety_stock, reorder_level')
  if (tid) qP = qP.eq('tenant_id', tid)
  const { data: products } = await qP

  const productMap = new Map((products || []).map((p: any) => [p.id, p]))
  const alertsCreated: StockAlert[] = []

  for (const s of stock || []) {
    const product = productMap.get(s.product_id)
    if (!product) continue
    const qty = Number(s.quantity || 0) - Number(s.reserved_quantity || 0)
    const minLevel = Number(product.safety_stock || product.reorder_level || 0)
    const maxLevel = 0

    let alertType: string | null = null
    if (qty <= 0) alertType = 'out_of_stock'
    else if (minLevel > 0 && qty <= minLevel) alertType = 'low_stock'
    else if (maxLevel > 0 && qty >= maxLevel) alertType = 'overstock'

    if (alertType) {
      const { data: existing, error: existError } = await supabase
        .from('stock_alerts')
        .select('id')
        .eq('product_id', s.product_id)
        .eq('status', 'active')
        .eq('alert_type', alertType)
      if (existError) throw existError
      if (existing && existing.length > 0) continue

      const { data: alert, error: alertError } = await supabase.from('stock_alerts').insert({
        tenant_id: tid,
        product_id: s.product_id,
        warehouse_id: s.warehouse_id,
        alert_type: alertType,
        threshold: alertType === 'overstock' ? maxLevel : minLevel,
        current_value: qty,
        status: 'active',
      }).select().single()
      if (alertError) throw alertError
      if (alert) alertsCreated.push(alert as StockAlert)
    }
  }

  return alertsCreated
}

export async function getStockForecastDetailed(productId: string) {
  const tid = await getTenantId()
  let qS = supabase.from('stock_quantities').select('quantity, reserved_quantity, incoming_quantity, warehouse_id').eq('product_id', productId).order('id')
  if (tid) qS = qS.eq('tenant_id', tid)
  // LOT7-03 : prévision de stock — somme sur tous les dépôts et toutes les commandes.
  const stock = await fetchAllRows<any>(qS, { label: 'getStockForecastDetailed/stock_quantities' })

  let qP = supabase.from('sales_order_lines').select('quantity, delivered_quantity, sales_orders(status)').eq('product_id', productId).order('id')
  if (tid) qP = qP.eq('tenant_id', tid)
  const pending = await fetchAllRows<any>(qP, { label: 'getStockForecastDetailed/sales_order_lines' })

  const byWarehouse: Record<string, { current: number; reserved: number; incoming: number; outgoing: number; forecast: number }> = {}
  let totalCurrent = 0
  let totalReserved = 0
  let totalIncoming = 0
  let totalOutgoing = 0

  for (const s of stock) {
    const wid = s.warehouse_id || 'default'
    const current = Number(s.quantity || 0)
    const reserved = Number(s.reserved_quantity || 0)
    const incoming = Number(s.incoming_quantity || 0)
    if (!byWarehouse[wid]) byWarehouse[wid] = { current: 0, reserved: 0, incoming: 0, outgoing: 0, forecast: 0 }
    byWarehouse[wid].current += current
    byWarehouse[wid].reserved += reserved
    byWarehouse[wid].incoming += incoming
    totalCurrent += current
    totalReserved += reserved
    totalIncoming += incoming
  }

  for (const p of pending) {
    if ((p as any).sales_orders?.status === 'confirmed') {
      const outgoing = Number((p as any).quantity || 0) - Number((p as any).delivered_quantity || 0)
      totalOutgoing += outgoing
    }
  }

  for (const w of Object.values(byWarehouse)) {
    w.outgoing = totalOutgoing
    w.forecast = w.current + w.incoming - w.outgoing
  }

  return {
    current: totalCurrent,
    reserved: totalReserved,
    incoming: totalIncoming,
    outgoing: totalOutgoing,
    forecast: totalCurrent + totalIncoming - totalOutgoing,
    byWarehouse,
  }
}
