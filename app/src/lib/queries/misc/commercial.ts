// ============================================================================
// misc — commercial.ts
// Extrait de l'ancien misc.ts le 2026-10-01 ; imports recalcules ;
// aucun code metier modifie.
// ============================================================================

import { supabase } from '@/lib/supabase'
import { type Joined } from '@/types/dbRow'
import { fetchAllRows, getTenantId, nextDocumentNumber, ti, tud } from '../core'
import { type Customer, type Invoice, type CreditNote, type SalesOrder, type SalesOrderLine, type DeliveryNote, type DeliveryNoteLine, type GoodsReceipt, type GoodsReceiptLine, type SalesRepresentative, type Prospect, type DeliverySchedule, type DocumentTemplate, type DocumentCharge, type DocumentTransformation } from '@/types'

// ============ Sprint 6: Goods Receipts ============
export async function getGoodsReceipts(status?: string) {
  const tid = await getTenantId()
  let q = supabase.from('goods_receipts').select('*').order('receipt_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (status) q = q.eq('status', status)
  const { data, error } = await q
  if (error) throw error
  return data as GoodsReceipt[]
}

/**
 * C9 (280) : une réception naît DE sa commande confirmée — une ligne par ligne
 * de commande, au reste à recevoir. Passer la réception à « reçue » fait ensuite
 * entrer la marchandise (chaîne 241/251 : mouvement, couche, écriture ST).
 */
export async function createGoodsReceiptFromOrder(orderId: string, opts: { number: string; receipt_date: string; warehouse_id: string | null }) {
  const { data, error } = await supabase.rpc('create_goods_receipt_from_order', {
    p_order_id: orderId, p_number: opts.number, p_receipt_date: opts.receipt_date, p_warehouse_id: opts.warehouse_id,
  })
  if (error) throw error
  return data as unknown as GoodsReceipt
}

export async function getGoodsReceiptLines(receiptId: string) {
  const tid = await getTenantId()
  let q = supabase.from('goods_receipt_lines').select('*').eq('goods_receipt_id', receiptId).order('id')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as GoodsReceiptLine[]
}

export async function updateGoodsReceipt(id: string, updates: Partial<GoodsReceipt>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('goods_receipts').update(updates), 'goods_receipts', tid).eq('id', id).select().single()
  if (error) throw error
  return data as GoodsReceipt
}

export async function deleteGoodsReceipt(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('goods_receipts').delete(), 'goods_receipts', tid).eq('id', id)
  if (error) throw error
}



// ============ Phase 2: Sales Representatives ============
export async function getSalesRepresentatives() {
  const tid = await getTenantId()
  let q = supabase.from('sales_representatives').select('*').order('name')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as SalesRepresentative[]
}
export async function createSalesRepresentative(r: Omit<SalesRepresentative, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('sales_representatives').insert(ti(r, 'sales_representatives', tid)).select().single()
  if (error) throw error
  return data as SalesRepresentative
}
export async function updateSalesRepresentative(id: string, updates: Partial<SalesRepresentative>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('sales_representatives').update(updates), 'sales_representatives', tid).eq('id', id).select().single()
  if (error) throw error
  return data as SalesRepresentative
}
export async function deleteSalesRepresentative(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('sales_representatives').delete(), 'sales_representatives', tid).eq('id', id)
  if (error) throw error
}



// ============ Phase 2: Prospects ============
export async function getProspects() {
  const tid = await getTenantId()
  let q = supabase.from('prospects').select('*, sales_representatives(name)').order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as (Prospect & { sales_representatives: Joined<'sales_representatives', 'name'> })[]
}
export async function createProspect(p: Omit<Prospect, 'id' | 'created_at' | 'updated_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('prospects').insert(ti(p, 'prospects', tid)).select().single()
  if (error) throw error
  return data as Prospect
}
export async function updateProspect(id: string, updates: Partial<Prospect>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('prospects').update(updates), 'prospects', tid).eq('id', id).select().single()
  if (error) throw error
  return data as Prospect
}
export async function deleteProspect(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('prospects').delete(), 'prospects', tid).eq('id', id)
  if (error) throw error
}
export async function convertProspectToCustomer(id: string, customerData: Partial<Customer>) {
  const tid = await getTenantId()
  const { data: cust, error: custErr } = await supabase.from('customers').insert(ti(customerData as any, 'customers', tid)).select().single()
  if (custErr) throw custErr
  await tud(supabase.from('prospects').update({ status: 'converted', converted_customer_id: cust.id }), 'prospects', tid).eq('id', id)
  return cust as Customer
}



// ============ Phase 2: Delivery Schedules ============
export async function getDeliverySchedules() {
  const tid = await getTenantId()
  let q = supabase.from('delivery_schedules').select('*, customers(name), products(name, sku)').order('start_date')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as (DeliverySchedule & { customers: Joined<'customers', 'name'>; products: Joined<'products', 'name' | 'sku'> })[]
}
export async function createDeliverySchedule(d: Omit<DeliverySchedule, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('delivery_schedules').insert(ti(d, 'delivery_schedules', tid)).select().single()
  if (error) throw error
  return data as DeliverySchedule
}
export async function deleteDeliverySchedule(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('delivery_schedules').delete(), 'delivery_schedules', tid).eq('id', id)
  if (error) throw error
}



// ============ Phase 2: Document Templates ============
export async function getDocumentTemplates() {
  const tid = await getTenantId()
  let q = supabase.from('document_templates').select('*').order('name')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as DocumentTemplate[]
}
export async function createDocumentTemplate(t: Omit<DocumentTemplate, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('document_templates').insert(ti(t, 'document_templates', tid)).select().single()
  if (error) throw error
  return data as DocumentTemplate
}
export async function updateDocumentTemplate(id: string, updates: Partial<DocumentTemplate>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('document_templates').update(updates), 'document_templates', tid).eq('id', id).select().single()
  if (error) throw error
  return data as DocumentTemplate
}
export async function deleteDocumentTemplate(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('document_templates').delete(), 'document_templates', tid).eq('id', id)
  if (error) throw error
}



// ============ Sprint A: Commercial Transformations ============

// --- Document Charges ---
export async function getDocumentCharges(documentType: string, documentId: string) {
  const tid = await getTenantId()
  let q = supabase.from('document_charges').select('*').eq('document_type', documentType).eq('document_id', documentId).order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as DocumentCharge[]
}

export async function addDocumentCharge(charge: Omit<DocumentCharge, 'id' | 'tenant_id' | 'created_at'>) {
  const tid = await getTenantId()
  const vatAmount = Number(charge.amount) * (Number(charge.vat_rate) / 100)
  const totalAmount = Number(charge.amount) + vatAmount
  const { data, error } = await supabase
    .from('document_charges')
    .insert({ ...charge, vat_amount: vatAmount, total_amount: totalAmount, tenant_id: tid })
    .select()
    .single()
  if (error) throw error
  return data as DocumentCharge
}

export async function deleteDocumentCharge(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('document_charges').delete(), 'document_charges', tid).eq('id', id)
  if (error) throw error
}

// --- Document Transformations ---
export async function getDocumentTransformations(sourceType?: string, sourceId?: string) {
  const tid = await getTenantId()
  let q = supabase.from('document_transformations').select('*').order('transformed_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (sourceType) q = q.eq('source_type', sourceType)
  if (sourceId) q = q.eq('source_id', sourceId)
  const { data, error } = await q
  if (error) throw error
  return data as DocumentTransformation[]
}

async function recordTransformation(sourceType: string, sourceId: string, targetType: string, targetId: string, transformationType: 'full' | 'partial', notes?: string) {
  const tid = await getTenantId()
  const { error } = await supabase
    .from('document_transformations')
    .insert({ tenant_id: tid, source_type: sourceType, source_id: sourceId, target_type: targetType, target_id: targetId, transformation_type: transformationType, notes: notes || null })
  if (error) throw error
}

// --- Transform Quote to Sales Order ---
export async function transformQuoteToSalesOrder(quoteId: string) {
  const tid = await getTenantId()
  const { data: quote, error: qErr } = await supabase.from('quotes').select('*, quote_lines(*)').eq('id', quoteId).single()
  if (qErr) throw qErr

  const orderNumber = await nextDocumentNumber('CMD')
  // B6 (ven-006) : la commande garde la date du devis ; la date du jour faisait
  // d'un devis du 10/09 une commande du 29/09.
  const orderDate = (quote.date as string) || new Date().toISOString().split('T')[0]
  const { data: order, error: oErr } = await supabase
    .from('sales_orders')
    .insert({ tenant_id: tid, number: orderNumber, customer_id: quote.customer_id, order_date: orderDate, delivery_date: null, status: 'confirmed', subtotal: Number(quote.subtotal), vat: Number(quote.vat_total), total: Number(quote.total), notes: quote.notes, quote_id: quoteId })
    .select()
    .single()
  if (oErr) throw oErr

  for (const line of quote.quote_lines || []) {
    const { error: lErr } = await supabase
      .from('sales_order_lines')
      .insert({ tenant_id: tid, sales_order_id: order.id, product_id: line.product_id, description: line.description, quantity: Number(line.quantity), unit_price: Number(line.unit_price), vat_rate: Number(line.vat_rate), line_total: Number(line.total), delivered_quantity: 0 })
    if (lErr) throw lErr
  }

  await tud(supabase.from('quotes').update({ transformed_to_order_id: order.id, transformation_status: 'transformed' }), 'quotes', tid).eq('id', quoteId)
  await recordTransformation('quote', quoteId, 'sales_order', order.id, 'full')
  return order as SalesOrder
}

// --- Transform Sales Order to Delivery Note ---
export async function transformSalesOrderToDeliveryNote(
  orderId: string,
  lines: { sales_order_line_id: string; quantity: number }[],
  header?: { delivery_date?: string; carrier?: string | null; tracking_number?: string | null; notes?: string | null },
) {
  const tid = await getTenantId()
  const { data: order, error: oErr } = await supabase.from('sales_orders').select('*, sales_order_lines(*)').eq('id', orderId).single()
  if (oErr) throw oErr

  const dnNumber = await nextDocumentNumber('BL')
  const { data: dn, error: dErr } = await supabase
    .from('delivery_notes')
    .insert({ tenant_id: tid, number: dnNumber, customer_id: order.customer_id, sales_order_id: orderId, delivery_date: header?.delivery_date || new Date().toISOString().split('T')[0], status: 'pending', carrier: header?.carrier ?? null, tracking_number: header?.tracking_number ?? null, notes: header?.notes ?? null })
    .select()
    .single()
  if (dErr) throw dErr

  let allDelivered = true
  for (const sel of lines) {
    const ol = (order.sales_order_lines || []).find((l: any) => l.id === sel.sales_order_line_id)
    if (!ol) continue
    const { error: lErr } = await supabase
      .from('delivery_note_lines')
      .insert({ tenant_id: tid, delivery_note_id: dn.id, product_id: ol.product_id, description: ol.description, quantity: sel.quantity, invoiced_quantity: 0, sales_order_line_id: sel.sales_order_line_id })
    if (lErr) throw lErr

    const newDelivered = Number(ol.delivered_quantity || 0) + sel.quantity
    await tud(supabase.from('sales_order_lines').update({ delivered_quantity: newDelivered }), 'sales_order_lines', tid).eq('id', sel.sales_order_line_id)
    if (newDelivered < Number(ol.quantity)) allDelivered = false
  }

  // B1 (ven-005) : la commande ne se déclare plus livrée ici. Créer le bon n'est
  // pas expédier la marchandise : `delivery_status` et `fully_delivered` sont
  // posés par la base, à la sortie réelle du dépôt (migration 314), pour les
  // livraisons partielles comme complètes. L'écran seul les affiche.
  await recordTransformation('sales_order', orderId, 'delivery_note', dn.id, allDelivered ? 'full' : 'partial')
  return dn as DeliveryNote
}

// --- Transform Delivery Note to Invoice ---
export async function transformDeliveryNoteToInvoice(dnId: string, lines: { delivery_note_line_id: string; quantity: number }[]) {
  const tid = await getTenantId()
  const { data: dn, error: dErr } = await supabase.from('delivery_notes').select('*, delivery_note_lines(*)').eq('id', dnId).single()
  if (dErr) throw dErr

  // AUD-E04 : numéro provisoire posé par le serveur, définitif à la validation
  let subtotal = 0
  let vatTotal = 0

  // B6 (ven-006) : la facture née d'un BL porte le nom du client (la liste
  // affichait « — » et la recherche par nom ne la trouvait pas) et la date du
  // bon ; l'échéance suit les conditions de paiement du client (30 j par défaut).
  const { data: cust } = await supabase.from('customers').select('name, payment_terms').eq('id', dn.customer_id).maybeSingle()
  const invoiceDate = (dn.delivery_date as string) || new Date().toISOString().split('T')[0]
  const termsDays = (() => {
    const m = /(\d+)/.exec(cust?.payment_terms || '')
    const days = m ? Number(m[1]) : 30
    return Number.isFinite(days) && days >= 0 ? days : 30
  })()
  const due = new Date(`${invoiceDate}T00:00:00Z`)
  due.setUTCDate(due.getUTCDate() + termsDays)

  const { data: inv, error: iErr } = await supabase
    .from('invoices')
    .insert({ tenant_id: tid, customer_id: dn.customer_id, customer_name: cust?.name ?? null, date: invoiceDate, due_date: due.toISOString().split('T')[0], status: 'draft', subtotal: 0, vat_total: 0, total: 0, amount_paid: 0, amount_due: 0, notes: '', recurring: false, recurring_frequency: null, delivery_note_id: dnId, invoice_type: 'standard' })
    .select()
    .single()
  if (iErr) throw iErr

  let allInvoiced = true
  for (const sel of lines) {
    const dl = (dn.delivery_note_lines || []).find((l: any) => l.id === sel.delivery_note_line_id)
    if (!dl) continue
    const olData = dl.sales_order_line_id ? (await supabase.from('sales_order_lines').select('*').eq('id', dl.sales_order_line_id).single()).data : null
    const unitPrice = olData ? Number(olData.unit_price) : 0
    const vatRate = olData ? Number(olData.vat_rate) : 0
    const lineTotal = sel.quantity * unitPrice
    const lineVat = lineTotal * (vatRate / 100)
    subtotal += lineTotal
    vatTotal += lineVat

    const { error: lErr } = await supabase
      .from('invoice_lines')
      .insert({ tenant_id: tid, invoice_id: inv.id, product_id: dl.product_id, description: dl.description, quantity: sel.quantity, unit_price: unitPrice, vat_rate: vatRate, total: lineTotal, vat_total: lineVat, line_order: 0, delivery_note_line_id: sel.delivery_note_line_id, sales_order_line_id: dl.sales_order_line_id || null })
    if (lErr) throw lErr

    const newInvoiced = Number(dl.invoiced_quantity || 0) + sel.quantity
    await tud(supabase.from('delivery_note_lines').update({ invoiced_quantity: newInvoiced }), 'delivery_note_lines', tid).eq('id', sel.delivery_note_line_id)
    if (newInvoiced < Number(dl.quantity)) allInvoiced = false
  }

  await tud(supabase.from('invoices').update({ subtotal, vat_total: vatTotal, total: subtotal + vatTotal, amount_due: subtotal + vatTotal }), 'invoices', tid).eq('id', inv.id)
  await tud(supabase.from('delivery_notes').update({ invoice_status: allInvoiced ? 'invoiced' : 'partial', fully_invoiced: allInvoiced }), 'delivery_notes', tid).eq('id', dnId)
  await recordTransformation('delivery_note', dnId, 'invoice', inv.id, allInvoiced ? 'full' : 'partial')
  return inv as Invoice
}

// --- Transform Invoice to Credit Note ---
export async function transformInvoiceToCreditNote(invoiceId: string, reason: string) {
  const tid = await getTenantId()
  const { data: inv, error: iErr } = await supabase.from('invoices').select('*, invoice_lines(*)').eq('id', invoiceId).single()
  if (iErr) throw iErr

  // AUD-E04 : numéro provisoire posé par le serveur, définitif à la validation
  const { data: cn, error: cErr } = await supabase
    .from('credit_notes')
    .insert({ tenant_id: tid, customer_id: inv.customer_id, customer_name: inv.customer_name, date: new Date().toISOString().split('T')[0], status: 'draft', subtotal: Number(inv.subtotal), vat_total: Number(inv.vat_total), total: Number(inv.total), reason, invoice_id: invoiceId, source_invoice_id: invoiceId })
    .select()
    .single()
  if (cErr) throw cErr

  for (const line of inv.invoice_lines || []) {
    const { error: lErr } = await supabase
      .from('credit_note_lines')
      .insert({ tenant_id: tid, credit_note_id: cn.id, product_id: line.product_id, vat_code: line.vat_code, description: line.description, quantity: Number(line.quantity), unit_price: Number(line.unit_price), vat_rate: Number(line.vat_rate), total: Number(line.total), vat_total: Number(line.vat_total) })
    if (lErr) throw lErr
  }

  await recordTransformation('invoice', invoiceId, 'credit_note', cn.id, 'full')
  return cn as CreditNote
}

// --- Create Advance Invoice ---
export async function createAdvanceInvoice(customerId: string, amount: number, vatRate: number) {
  const tid = await getTenantId()
  const { data: cust, error: cErr } = await supabase.from('customers').select('name').eq('id', customerId).single()
  if (cErr) throw cErr

  const vatAmount = amount * (vatRate / 100)
  const total = amount + vatAmount
  // AUD-E04 : numéro provisoire posé par le serveur, définitif à la validation

  const { data: inv, error: iErr } = await supabase
    .from('invoices')
    .insert({ tenant_id: tid, customer_id: customerId, customer_name: cust?.name || null, date: new Date().toISOString().split('T')[0], due_date: new Date(Date.now() + 30 * 86400000).toISOString().split('T')[0], status: 'draft', subtotal: amount, vat_total: vatAmount, total, amount_paid: 0, amount_due: total, notes: '', recurring: false, recurring_frequency: null, is_advance_invoice: true, advance_amount: amount, invoice_type: 'advance' })
    .select()
    .single()
  if (iErr) throw iErr

  const { error: lErr } = await supabase
    .from('invoice_lines')
    .insert({ tenant_id: tid, invoice_id: inv.id, product_id: null, description: 'Acompte', quantity: 1, unit_price: amount, vat_rate: vatRate, total: amount, vat_total: vatAmount, line_order: 0 })
  if (lErr) throw lErr

  return inv as Invoice
}

// --- Stock helpers ---
export async function checkStockAvailability(productId: string, requiredQty: number) {
  const tid = await getTenantId()
  let q = supabase.from('stock_quantities').select('quantity').eq('product_id', productId).order('id')
  if (tid) q = q.eq('tenant_id', tid)
  // LOT7-03 : disponibilité = somme sur tous les dépôts et tous les lots.
  const data = await fetchAllRows<any>(q, { label: 'checkStockAvailability/stock_quantities' })
  const available = data.reduce((sum, s) => sum + Number(s.quantity || 0), 0)
  return { available, required: requiredQty, sufficient: available >= requiredQty }
}

export async function getStockForecast(productId: string) {
  const tid = await getTenantId()
  let qS = supabase.from('stock_quantities').select('quantity').eq('product_id', productId).order('id')
  if (tid) qS = qS.eq('tenant_id', tid)
  // LOT7-03 : prévision de stock — somme sur tous les dépôts et toutes les commandes.
  const stock = await fetchAllRows<any>(qS, { label: 'getStockForecast/stock_quantities' })
  const current = stock.reduce((sum: number, s: any) => sum + Number(s.quantity || 0), 0)

  let qP = supabase.from('sales_order_lines').select('quantity, delivered_quantity, sales_orders(status)').eq('product_id', productId).order('id')
  if (tid) qP = qP.eq('tenant_id', tid)
  const pending = await fetchAllRows<any>(qP, { label: 'getStockForecast/sales_order_lines' })
  const pendingQty = pending.filter((p: any) => p.sales_orders?.status === 'confirmed').reduce((sum: number, p: any) => sum + (Number(p.quantity) - Number(p.delivered_quantity || 0)), 0)

  return { current, pending: pendingQty, forecast: current - pendingQty }
}

// --- Get sales order lines ---
export async function getSalesOrderLines(orderId: string) {
  const tid = await getTenantId()
  let q = supabase.from('sales_order_lines').select('*').eq('sales_order_id', orderId).order('line_total', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as SalesOrderLine[]
}

// --- Get delivery note lines ---
export async function getDeliveryNoteLines(dnId: string) {
  const tid = await getTenantId()
  let q = supabase.from('delivery_note_lines').select('*').eq('delivery_note_id', dnId)
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as DeliveryNoteLine[]
}
