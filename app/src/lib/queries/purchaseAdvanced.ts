import { supabase } from '@/lib/supabase'
import { getTenantId, nextDocumentNumber, ti, tud } from './core'
import type { PurchaseRequest, PurchaseRequestLine, SupplierPriceList, SupplierPriceListLine, SupplierDeliverySchedule } from '@/types'

// ============ Sprint C: Purchase Requests ============
export async function getPurchaseRequests(status?: string) {
  const tid = await getTenantId()
  let q = supabase.from('purchase_requests').select('*, purchase_request_lines(*)').order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (status) q = q.eq('status', status)
  const { data, error } = await q
  if (error) throw error
  return data as PurchaseRequest[]
}

export async function createPurchaseRequest(pr: Omit<PurchaseRequest, 'id' | 'created_at' | 'purchase_request_lines'> & { purchase_request_lines?: PurchaseRequestLine[] }) {
  const tid = await getTenantId()
  const { purchase_request_lines: lines, ...header } = pr
  const { data, error } = await supabase.from('purchase_requests').insert(ti(header, 'purchase_requests', tid)).select().single()
  if (error) throw error
  const created = data as PurchaseRequest
  if (lines && lines.length > 0) {
    const lineData = lines.map(l => ti({ ...l, purchase_request_id: created.id }, 'purchase_request_lines', tid))
    const { error: lineError } = await supabase.from('purchase_request_lines').insert(lineData)
    if (lineError) throw lineError
  }
  return created
}

export async function updatePurchaseRequestStatus(id: string, status: string, approvedBy?: string) {
  const tid = await getTenantId()
  const updates: Record<string, any> = { status }
  if (status === 'approved' && approvedBy) {
    updates.approved_by = approvedBy
    updates.approved_at = new Date().toISOString()
  }
  const { data, error } = await tud(supabase.from('purchase_requests').update(updates), 'purchase_requests', tid).eq('id', id).select().single()
  if (error) throw error
  return data as PurchaseRequest
}

export async function deletePurchaseRequest(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('purchase_requests').delete(), 'purchase_requests', tid).eq('id', id)
  if (error) throw error
}

export async function convertPurchaseRequestToOrder(prId: string, supplierId: string) {
  const tid = await getTenantId()
  const { data: pr, error: prError } = await supabase.from('purchase_requests').select('*, purchase_request_lines(*)').eq('id', prId).single()
  if (prError) throw prError

  const orderNumber = await nextDocumentNumber('PO')
  const { data: order, error: orderError } = await supabase.from('purchase_orders').insert(ti({
    number: orderNumber,
    supplier_id: supplierId,
    status: 'draft',
    date: new Date().toISOString().split('T')[0],
  }, 'purchase_orders', tid)).select().single()
  if (orderError) throw orderError

  if (pr.purchase_request_lines && pr.purchase_request_lines.length > 0) {
    const orderLines = pr.purchase_request_lines.map((line: any) => ti({
      purchase_order_id: order.id,
      product_id: line.product_id,
      description: line.description,
      quantity: line.quantity,
      unit_price: line.estimated_price || 0,
      vat_rate: 0,
    }, 'purchase_order_lines', tid))
    const { error: lineError } = await supabase.from('purchase_order_lines').insert(orderLines)
    if (lineError) throw lineError
  }

  await updatePurchaseRequestStatus(prId, 'converted')
  return order
}

// ============ Sprint C: Supplier Price Lists ============
export async function getSupplierPriceLists(supplierId?: string) {
  const tid = await getTenantId()
  let q = supabase.from('supplier_price_lists').select('*, supplier_price_list_lines(*)').order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (supplierId) q = q.eq('supplier_id', supplierId)
  const { data, error } = await q
  if (error) throw error
  return data as SupplierPriceList[]
}

export async function createSupplierPriceList(list: Omit<SupplierPriceList, 'id' | 'created_at' | 'supplier_price_list_lines'> & { supplier_price_list_lines?: SupplierPriceListLine[] }) {
  const tid = await getTenantId()
  const { supplier_price_list_lines, ...header } = list
  const { data, error } = await supabase.from('supplier_price_lists').insert(ti(header, 'supplier_price_lists', tid)).select().single()
  if (error) throw error
  const created = data as SupplierPriceList
  if (supplier_price_list_lines && supplier_price_list_lines.length > 0) {
    const lineData = supplier_price_list_lines.map(l => ti({ ...l, price_list_id: created.id }, 'supplier_price_list_lines', tid))
    const { error: lineError } = await supabase.from('supplier_price_list_lines').insert(lineData)
    if (lineError) throw lineError
  }
  return created
}

export async function updateSupplierPriceList(id: string, updates: Partial<SupplierPriceList>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('supplier_price_lists').update(updates), 'supplier_price_lists', tid).eq('id', id).select().single()
  if (error) throw error
  return data as SupplierPriceList
}

export async function deleteSupplierPriceList(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('supplier_price_lists').delete(), 'supplier_price_lists', tid).eq('id', id)
  if (error) throw error
}

export async function getBestSupplierPrice(productId: string, qty: number) {
  const tid = await getTenantId()
  let q = supabase
    .from('supplier_price_list_lines')
    .select(`
      *,
      supplier_price_lists!inner(supplier_id, name, discount_percent, valid_from, valid_to, active)
    `)
    .eq('product_id', productId)
    .lte('min_quantity', qty)
  if (tid) q = q.eq('tenant_id', tid) as any
  const { data, error } = await q
  if (error) throw error
  if (!data || data.length === 0) return null

  const priced = data.map((line: any) => {
    const pl = line.supplier_price_lists
    const discount = (Number(line.discount_percent || 0) + Number(pl?.discount_percent || 0)) / 100
    const effectivePrice = Number(line.unit_price) * (1 - discount)
    return {
      supplier_id: pl?.supplier_id,
      price_list_name: pl?.name,
      unit_price: Number(line.unit_price),
      effective_price: effectivePrice,
      discount_percent: discount * 100,
      lead_time_days: line.lead_time_days,
    }
  })

  return priced.sort((a, b) => a.effective_price - b.effective_price)[0]
}

// ============ Sprint C: Supplier Delivery Schedules ============
export async function getSupplierDeliverySchedules(supplierId?: string) {
  const tid = await getTenantId()
  let q = supabase.from('supplier_delivery_schedules').select('*').order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (supplierId) q = q.eq('supplier_id', supplierId)
  const { data, error } = await q
  if (error) throw error
  return data as SupplierDeliverySchedule[]
}

export async function createSupplierDeliverySchedule(schedule: Omit<SupplierDeliverySchedule, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('supplier_delivery_schedules').insert(ti(schedule, 'supplier_delivery_schedules', tid)).select().single()
  if (error) throw error
  return data as SupplierDeliverySchedule
}

export async function updateSupplierDeliverySchedule(id: string, updates: Partial<SupplierDeliverySchedule>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('supplier_delivery_schedules').update(updates), 'supplier_delivery_schedules', tid).eq('id', id).select().single()
  if (error) throw error
  return data as SupplierDeliverySchedule
}

export async function deleteSupplierDeliverySchedule(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('supplier_delivery_schedules').delete(), 'supplier_delivery_schedules', tid).eq('id', id)
  if (error) throw error
}

export async function generatePurchaseFromSchedule(date: string) {
  const tid = await getTenantId()
  const dayOfWeek = new Date(date).getDay()
  const dayMap = ['sunday_qty', 'monday_qty', 'tuesday_qty', 'wednesday_qty', 'thursday_qty', 'friday_qty', 'saturday_qty']
  const qtyField = dayMap[dayOfWeek]

  let q = supabase.from('supplier_delivery_schedules').select('*').eq('active', true).lte('start_date', date)
  if (tid) q = q.eq('tenant_id', tid)
  const { data: schedules, error } = await q
  if (error) throw error
  if (!schedules || schedules.length === 0) return []

  const bySupplier: Record<string, any[]> = {}
  for (const s of schedules) {
    const qty = Number((s as any)[qtyField] || 0)
    if (qty <= 0) continue
    if (!bySupplier[s.supplier_id]) bySupplier[s.supplier_id] = []
    bySupplier[s.supplier_id].push({ product_id: s.product_id, quantity: qty, warehouse_id: s.warehouse_id })
  }

  const createdOrders: any[] = []
  for (const [supplierId, items] of Object.entries(bySupplier)) {
    const orderNumber = await nextDocumentNumber('PO')
    const { data: order, error: orderError } = await supabase.from('purchase_orders').insert(ti({
      number: orderNumber,
      supplier_id: supplierId,
      status: 'draft',
      date,
    }, 'purchase_orders', tid)).select().single()
    if (orderError) throw orderError

    const orderLines = items.map(item => ti({
      purchase_order_id: order.id,
      product_id: item.product_id,
      description: 'Generated from delivery schedule',
      quantity: item.quantity,
      unit_price: 0,
      vat_rate: 0,
    }, 'purchase_order_lines', tid))
    const { error: lineError } = await supabase.from('purchase_order_lines').insert(orderLines)
    if (lineError) throw lineError
    createdOrders.push(order)
  }

  return createdOrders
}
