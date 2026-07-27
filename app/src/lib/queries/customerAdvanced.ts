import { supabase } from '@/lib/supabase'
import { getTenantId, ti, tud } from './core'
import type { CustomerContact, SupplierContact, Customer, Invoice, Quote, SalesOrder, DeliveryNote, CustomerPayment, CollectionReminder } from '@/types'

// ============ Sprint B: Customer Contacts ============
export async function getCustomerContacts(customerId: string) {
  const tid = await getTenantId()
  let q = supabase.from('customer_contacts').select('*').eq('customer_id', customerId).order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as CustomerContact[]
}

export async function createCustomerContact(contact: Omit<CustomerContact, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('customer_contacts').insert(ti(contact, 'customer_contacts', tid)).select().single()
  if (error) throw error
  return data as CustomerContact
}

export async function updateCustomerContact(id: string, updates: Partial<CustomerContact>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('customer_contacts').update(updates), 'customer_contacts', tid).eq('id', id).select().single()
  if (error) throw error
  return data as CustomerContact
}

export async function deleteCustomerContact(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('customer_contacts').delete(), 'customer_contacts', tid).eq('id', id)
  if (error) throw error
}

// ============ Sprint B: Supplier Contacts ============
export async function getSupplierContacts(supplierId: string) {
  const tid = await getTenantId()
  let q = supabase.from('supplier_contacts').select('*').eq('supplier_id', supplierId).order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as SupplierContact[]
}

export async function createSupplierContact(contact: Omit<SupplierContact, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('supplier_contacts').insert(ti(contact, 'supplier_contacts', tid)).select().single()
  if (error) throw error
  return data as SupplierContact
}

export async function updateSupplierContact(id: string, updates: Partial<SupplierContact>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('supplier_contacts').update(updates), 'supplier_contacts', tid).eq('id', id).select().single()
  if (error) throw error
  return data as SupplierContact
}

export async function deleteSupplierContact(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('supplier_contacts').delete(), 'supplier_contacts', tid).eq('id', id)
  if (error) throw error
}

// ============ Sprint B: Customer 360° ============
export async function getCustomer360(customerId: string) {
  const tid = await getTenantId()

  const [customer, contacts, invoices, quotes, orders, deliveryNotes, payments, reminders] = await Promise.all([
    tid ? supabase.from('customers').select('*').eq('id', customerId).eq('tenant_id', tid).maybeSingle() : supabase.from('customers').select('*').eq('id', customerId).maybeSingle(),
    tid ? supabase.from('customer_contacts').select('*').eq('customer_id', customerId).eq('tenant_id', tid).order('created_at', { ascending: false }) : supabase.from('customer_contacts').select('*').eq('customer_id', customerId).order('created_at', { ascending: false }),
    tid ? supabase.from('invoices').select('*').eq('customer_id', customerId).eq('tenant_id', tid).order('date', { ascending: false }) : supabase.from('invoices').select('*').eq('customer_id', customerId).order('date', { ascending: false }),
    tid ? supabase.from('quotes').select('*').eq('customer_id', customerId).eq('tenant_id', tid).order('date', { ascending: false }) : supabase.from('quotes').select('*').eq('customer_id', customerId).order('date', { ascending: false }),
    tid ? supabase.from('sales_orders').select('*').eq('customer_id', customerId).eq('tenant_id', tid).order('date', { ascending: false }) : supabase.from('sales_orders').select('*').eq('customer_id', customerId).order('date', { ascending: false }),
    tid ? supabase.from('delivery_notes').select('*').eq('customer_id', customerId).eq('tenant_id', tid).order('date', { ascending: false }) : supabase.from('delivery_notes').select('*').eq('customer_id', customerId).order('date', { ascending: false }),
    tid ? supabase.from('customer_payments').select('*').eq('customer_id', customerId).eq('tenant_id', tid).order('payment_date', { ascending: false }) : supabase.from('customer_payments').select('*').eq('customer_id', customerId).order('payment_date', { ascending: false }),
    tid ? supabase.from('collection_reminders').select('*').eq('customer_id', customerId).eq('tenant_id', tid).order('created_at', { ascending: false }) : supabase.from('collection_reminders').select('*').eq('customer_id', customerId).order('created_at', { ascending: false }),
  ])

  if (customer.error) throw customer.error

  const customerData = customer.data as Customer | null
  const creditLimit = Number(customerData?.credit_limit || 0)
  const creditUsed = Number(customerData?.credit_used || customerData?.balance || 0)
  const creditAvailable = creditLimit - creditUsed
  const creditBlocked = customerData?.credit_blocked || false

  const totalRevenue = (invoices.data || []).reduce((sum, inv) => sum + Number((inv as any).total || 0), 0)
  const paidInvoices = (invoices.data || []).filter((inv: any) => inv.status === 'paid')
  const avgPaymentDelay = paidInvoices.length > 0
    ? paidInvoices.reduce((sum, inv) => {
        const created = new Date(inv.date).getTime()
        const paid = new Date(inv.due_date || inv.date).getTime()
        return sum + Math.max(0, (paid - created) / (1000 * 60 * 60 * 24))
      }, 0) / paidInvoices.length
    : 0

  const productCounts: Record<string, number> = {}
  ;(invoices.data || []).forEach((inv: any) => {
    if (inv.invoice_lines) {
      inv.invoice_lines.forEach((line: any) => {
        const desc = line.description || 'Unknown'
        productCounts[desc] = (productCounts[desc] || 0) + Number(line.quantity || 0)
      })
    }
  })
  const topProducts = Object.entries(productCounts)
    .sort(([, a], [, b]) => b - a)
    .slice(0, 5)
    .map(([name, qty]) => ({ name, quantity: qty }))

  return {
    infos: customerData,
    contacts: (contacts.data || []) as CustomerContact[],
    invoices: (invoices.data || []) as Invoice[],
    quotes: (quotes.data || []) as Quote[],
    orders: (orders.data || []) as SalesOrder[],
    deliveryNotes: (deliveryNotes.data || []) as DeliveryNote[],
    payments: (payments.data || []) as CustomerPayment[],
    reminders: (reminders.data || []) as CollectionReminder[],
    credit: {
      limit: creditLimit,
      used: creditUsed,
      available: creditAvailable,
      blocked: creditBlocked,
    },
    stats: {
      annualRevenue: totalRevenue,
      invoicesCount: (invoices.data || []).length,
      avgPaymentDelay: Math.round(avgPaymentDelay),
      topProducts,
    },
  }
}

// ============ Sprint B: Check Customer Credit ============
export async function checkCustomerCredit(customerId: string) {
  const tid = await getTenantId()
  let q = supabase.from('customers').select('credit_limit, credit_used, credit_blocked, balance').eq('id', customerId)
  if (tid) q = q.eq('tenant_id', tid)
  const { data: credData, error: credError } = await q.maybeSingle()
  if (credError) throw credError
  if (!credData) return { limit: 0, used: 0, available: 0, blocked: false }
  const limit = Number(credData.credit_limit || 0)
  const used = Number(credData.credit_used || credData.balance || 0)
  return {
    limit,
    used,
    available: limit - used,
    blocked: credData.credit_blocked || false,
  }
}
