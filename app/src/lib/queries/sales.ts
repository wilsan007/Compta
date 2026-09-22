import { supabase } from '@/lib/supabase';
import { getTenantId, ti, tud } from './core';
import type { Invoice, Quote, QuoteLine, CreditNote, CreditNoteLine, PurchaseCreditNote, PurchaseCreditNoteLine, PurchaseInvoice, PurchaseInvoiceLine, InvoiceLine, SalesOrder, DeliveryNote } from '@/types';

// ============ VTE-01 : Résolution de prix par grille tarifaire ============

export interface ResolvedPrice {
  unitPrice: number
  discount: number
  priceListId: string | null
  priceListName: string | null
  source: string
}

export async function resolvePrice(
  productId: string,
  customerId: string,
  quantity: number = 1,
  date: Date = new Date()
): Promise<ResolvedPrice | null> {
  const { data, error } = await supabase.rpc('resolve_price', {
    p_product_id: productId,
    p_customer_id: customerId,
    p_quantity: quantity,
    p_date: date.toISOString().split('T')[0],
  })

  if (error || !data || (data as any[]).length === 0) return null

  const row = (data as any[])[0]
  return {
    unitPrice: Number(row.unit_price),
    discount: Number(row.discount_percent || 0),
    priceListId: row.price_list_id,
    priceListName: row.price_list_name,
    source: row.source,
  }
}

// ============ VTE-02 : Contrôle d'encours client ============

export interface CustomerCreditState {
  creditLimit: number
  creditUsed: number
  outstandingInvoices: number
  outstandingOrders: number
  isBlocked: boolean
  policy: 'blocking' | 'warning' | 'information'
}

export async function getCustomerCreditState(customerId: string): Promise<CustomerCreditState | null> {
  const tid = await getTenantId()
  const { data: customer, error: custError } = await supabase
    .from('customers')
    .select('credit_limit, credit_used, credit_policy')
    .eq('id', customerId)
    .maybeSingle()
  if (custError) { console.error('getCustomerCreditState:', custError); return null }

  if (!customer) return null

  const { data: invoices, error: invError } = await supabase
    .from('invoices')
    .select('amount_due')
    .eq('customer_id', customerId)
    .eq('tenant_id', tid)
    .in('payment_state', ['not_paid', 'partial'])
  if (invError) { console.error('getCustomerCreditState:', invError); return null }

  const { data: orders, error: ordError } = await supabase
    .from('sales_orders')
    .select('total')
    .eq('customer_id', customerId)
    .eq('tenant_id', tid)
    .eq('status', 'confirmed')
  if (ordError) { console.error('getCustomerCreditState:', ordError); return null }

  const outstandingInvoices = (invoices || []).reduce((sum: number, inv: any) => sum + Number(inv.amount_due || 0), 0)
  const outstandingOrders = (orders || []).reduce((sum: number, ord: any) => sum + Number(ord.total || 0), 0)
  const creditLimit = Number(customer.credit_limit || 0)
  const creditUsed = outstandingInvoices + outstandingOrders

  return {
    creditLimit,
    creditUsed,
    outstandingInvoices,
    outstandingOrders,
    isBlocked: creditLimit > 0 && creditUsed > creditLimit,
    policy: customer.credit_policy || 'blocking',
  }
}

// ============ Invoices ============
export async function getInvoices() {
  const tid = await getTenantId()
  let q = supabase
    .from('invoices')
    .select('*, invoice_lines(*)')
    .order('date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as Invoice[]
}

// AUD-E03/E04 : le serveur recalcule lignes et totaux ; la facture naît en brouillon
// avec un numéro provisoire, remplacé par FAC-<exercice>-n à la validation.
export async function createInvoice(invoice: Omit<Invoice, 'id' | 'created_at' | 'updated_at' | 'number'> & { number?: string; lines: Omit<InvoiceLine, 'id' | 'created_at' | 'invoice_id'>[] }) {
  const tid = await getTenantId()
  const { lines, ...invoiceData } = invoice
  // LOT4-11 : Utiliser la RPC atomique create_invoice_atomic
  const { data: result, error: rpcError } = await supabase.rpc('create_invoice_atomic', {
    p_invoice: { ...invoiceData, tenant_id: tid },
    p_lines: (lines || []).map((l, i) => ({ ...l, line_order: i })),
  })
  if (rpcError) throw rpcError
  if (result && result.success === false) throw new Error(result.error || 'Erreur création facture')
  // Recharger la facture créée
  const { data: inv, error: invError } = await supabase.from('invoices').select('*').eq('id', result.invoice_id).single()
  if (invError) throw invError
  return inv as Invoice
}

export async function updateInvoice(id: string, updates: Partial<Invoice>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('invoices').update(updates), 'invoices', tid).eq('id', id).select().single()
  if (error) throw error
  return data as Invoice
}

export async function deleteInvoice(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('invoices').delete(), 'invoices', tid).eq('id', id)
  if (error) throw error
}


// ============ Quotes ============
export async function getQuotes() {
  const tid = await getTenantId()
  let q = supabase
    .from('quotes')
    .select('*, quote_lines(*)')
    .order('date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as Quote[]
}

export async function createQuote(quote: Omit<Quote, 'id' | 'created_at' | 'updated_at'> & { lines: Omit<QuoteLine, 'id' | 'created_at'>[] }) {
  const tid = await getTenantId()
  const { lines, ...quoteData } = quote
  const { data: qt, error: qtError } = await supabase.from('quotes').insert(ti(quoteData, 'quotes', tid)).select().single()
  if (qtError) throw qtError
  
  if (lines && lines.length > 0) {
    const { error: linesError } = await supabase
      .from('quote_lines')
      .insert(lines.map((l, i) => ti({ ...l, quote_id: qt.id, line_order: i }, 'quote_lines', tid)))
    if (linesError) throw linesError
  }
  return qt as Quote
}


// ============ Quotes ============
export async function updateQuote(id: string, updates: Partial<Quote>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('quotes').update(updates), 'quotes', tid).eq('id', id).select().single()
  if (error) throw error
  return data as Quote
}

export async function deleteQuote(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('quotes').delete(), 'quotes', tid).eq('id', id)
  if (error) throw error
}

export async function convertQuoteToInvoice(quoteId: string) {
  // AUD-E05 : conversion atomique côté serveur (lignes, TVA et totaux recalculés) ;
  // la facture naît en brouillon, son numéro est attribué à la validation (AUD-E04)
  const { data, error } = await supabase.rpc('convert_quote_to_invoice', { p_quote_id: quoteId })
  if (error) throw error
  const { data: inv, error: invError } = await supabase.from('invoices').select('*').eq('id', (data as any).invoice_id).single()
  if (invError) throw invError
  return inv as Invoice
}


// ============ Credit Notes ============
export async function getCreditNotes() {
  const tid = await getTenantId()
  let q = supabase
    .from('credit_notes')
    .select('*, credit_note_lines(*)')
    .order('date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as CreditNote[]
}

export async function createCreditNote(cn: Omit<CreditNote, 'id' | 'created_at'> & { lines: Omit<CreditNoteLine, 'id' | 'created_at'>[] }) {
  const tid = await getTenantId()
  const { lines, ...cnData } = cn
  const { data, error } = await supabase.from('credit_notes').insert(ti(cnData, 'credit_notes', tid)).select().single()
  if (error) throw error
  if (lines && lines.length > 0) {
    const { error: lErr } = await supabase
      .from('credit_note_lines')
      .insert(lines.map((l, i) => ti({ ...l, credit_note_id: data.id, line_order: i }, 'credit_note_lines', tid)))
    if (lErr) throw lErr
  }
  return data as CreditNote
}

export async function updateCreditNote(id: string, updates: Partial<CreditNote>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('credit_notes').update(updates), 'credit_notes', tid).eq('id', id).select().single()
  if (error) throw error
  return data as CreditNote
}

export async function deleteCreditNote(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('credit_notes').delete(), 'credit_notes', tid).eq('id', id)
  if (error) throw error
}


// ============ Purchase Invoices ============
export async function getPurchaseInvoices() {
  const tid = await getTenantId()
  let q = supabase
    .from('purchase_invoices')
    .select('*, purchase_invoice_lines(*)')
    .order('date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as PurchaseInvoice[]
}

// AUD-G02 : numéro interne attribué par le serveur à l'approbation ; en-tête et
// lignes créés ensemble (RPC atomique), montants recalculés par le serveur
export async function createPurchaseInvoice(invoice: Omit<PurchaseInvoice, 'id' | 'created_at' | 'updated_at' | 'number'> & { number?: string; lines?: Omit<PurchaseInvoiceLine, 'id' | 'created_at' | 'purchase_invoice_id'>[] }) {
  const tid = await getTenantId()
  const { lines, ...header } = invoice
  if (lines && lines.length > 0) {
    const { data: result, error: rpcError } = await supabase.rpc('create_purchase_invoice_atomic', {
      p_invoice: { ...header, tenant_id: tid },
      p_lines: lines.map((l, i) => ({ ...l, line_order: i })),
    })
    if (rpcError) throw rpcError
    if (result && result.success === false) throw new Error(result.error || 'Erreur création facture fournisseur')
    const { data, error } = await supabase.from('purchase_invoices').select('*').eq('id', result.purchase_invoice_id).single()
    if (error) throw error
    return data as PurchaseInvoice
  }
  const { data, error } = await supabase.from('purchase_invoices').insert(ti(header, 'purchase_invoices', tid)).select().single()
  if (error) throw error
  return data as PurchaseInvoice
}

export async function updatePurchaseInvoice(id: string, updates: Partial<PurchaseInvoice>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('purchase_invoices').update(updates), 'purchase_invoices', tid).eq('id', id).select().single()
  if (error) throw error
  return data as PurchaseInvoice
}

export async function updatePurchaseInvoiceApproval(id: string, status: 'approved' | 'rejected') {
  const tid = await getTenantId()
  const updates: Record<string, any> = {
    approval_status: status,
    approved_at: status === 'approved' ? new Date().toISOString() : null,
  }
  const { data, error } = await tud(supabase.from('purchase_invoices').update(updates), 'purchase_invoices', tid).eq('id', id).select().single()
  if (error) throw error
  return data
}


// ============ Purchase Credit Notes ============
export async function getPurchaseCreditNotes() {
  const tid = await getTenantId()
  let q = supabase
    .from('purchase_credit_notes')
    .select('*, purchase_credit_lines(*)')
    .order('date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as PurchaseCreditNote[]
}

export async function updatePurchaseCreditNote(id: string, updates: Partial<PurchaseCreditNote>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('purchase_credit_notes').update(updates), 'purchase_credit_notes', tid).eq('id', id).select().single()
  if (error) throw error
  return data as PurchaseCreditNote
}

export async function createPurchaseCreditNote(pcn: Omit<PurchaseCreditNote, 'id' | 'created_at' | 'number'> & { number?: string; lines: Omit<PurchaseCreditNoteLine, 'id' | 'created_at'>[] }) {
  const tid = await getTenantId()
  const { lines, ...pcnData } = pcn
  const { data, error } = await supabase.from('purchase_credit_notes').insert(ti(pcnData, 'purchase_credit_notes', tid)).select().single()
  if (error) throw error
  if (lines && lines.length > 0) {
    const { error: lErr } = await supabase
      .from('purchase_credit_lines')
      .insert(lines.map((l, i) => ti({ ...l, purchase_credit_id: data.id, line_order: i }, 'purchase_credit_lines', tid)))
    if (lErr) throw lErr
  }
  return data as PurchaseCreditNote
}

export async function deletePurchaseCreditNote(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('purchase_credit_notes').delete(), 'purchase_credit_notes', tid).eq('id', id)
  if (error) throw error
}


// ============ Delete Purchase Invoice ============
export async function deletePurchaseInvoice(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('purchase_invoices').delete(), 'purchase_invoices', tid).eq('id', id)
  if (error) throw error
}


// ============ Sprint 6: Sales Orders ============
export async function getSalesOrders(status?: string) {
  const tid = await getTenantId()
  let q = supabase.from('sales_orders').select('*').order('order_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (status) q = q.eq('status', status)
  const { data, error } = await q
  if (error) throw error
  return data as SalesOrder[]
}

export async function createSalesOrder(so: Omit<SalesOrder, 'id' | 'created_at' | 'updated_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('sales_orders').insert(ti(so, 'sales_orders', tid)).select().single()
  if (error) throw error
  return data as SalesOrder
}

export async function updateSalesOrder(id: string, updates: Partial<SalesOrder>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('sales_orders').update({ ...updates, updated_at: new Date().toISOString() }), 'sales_orders', tid).eq('id', id).select().single()
  if (error) throw error
  return data as SalesOrder
}

export async function deleteSalesOrder(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('sales_orders').delete(), 'sales_orders', tid).eq('id', id)
  if (error) throw error
}


// ============ Sprint 6: Delivery Notes ============
export async function getDeliveryNotes(status?: string) {
  const tid = await getTenantId()
  let q = supabase.from('delivery_notes').select('*').order('delivery_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (status) q = q.eq('status', status)
  const { data, error } = await q
  if (error) throw error
  return data as DeliveryNote[]
}

export async function createDeliveryNote(dn: Omit<DeliveryNote, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('delivery_notes').insert(ti(dn, 'delivery_notes', tid)).select().single()
  if (error) throw error
  return data as DeliveryNote
}

export async function updateDeliveryNote(id: string, updates: Partial<DeliveryNote>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('delivery_notes').update(updates), 'delivery_notes', tid).eq('id', id).select().single()
  if (error) throw error
  return data as DeliveryNote
}

export async function deleteDeliveryNote(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('delivery_notes').delete(), 'delivery_notes', tid).eq('id', id)
  if (error) throw error
}

