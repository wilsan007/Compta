import { supabase } from '@/lib/supabase'
import { getTenantId, ti, tud, clearTenantCache } from './core'
import type { Customer, Supplier, Product, Invoice, Quote, QuoteLine, CreditNote, CreditNoteLine, PurchaseCreditNote, PurchaseCreditNoteLine, PurchaseInvoice, BankAccount, BankTransaction, BankRule, BankConnection, PartnerBankAccount, PartnerContact, PartnerCategory, JournalEntry, JournalLine, ChartAccount, CompanySettings, Project, VatReturn, InvoiceLine, DashboardStats, FixedAsset, Employee, PayRun, Timesheet, StockMovement, Currency, Journal, FiscalYear, FiscalPeriod, EntryTemplate, ThirdPartyAccount, AnalyticSection, Budget, BudgetCommitment, BudgetControlResult, StandardLabel, PaymentOrder, AssetDepreciation, CollectionReminder, SalesOrder, SalesOrderLine, DeliveryNote, DeliveryNoteLine, CustomerPayment, PurchaseOrder, GoodsReceipt, SupplierPayment, Warehouse, StockQuantity, PriceList, PriceListLine, BOM, BOMLine, ManufacturingOrder, PaySlip, PayrollAccountingEntry, LeaveRequest, Contract, LegalDeclaration, AuditLog, Routing, RoutingOperation, WorkCenter, Machine, Tooling, OFLabel, OFLot, OFConsumption, STOrder, STShipment, STShipmentLine, STReceipt, STReceiptLine, MRPRun, MRPProposal, ProductionForecast, PlanningSlot, ProductEquivalence, Workflow, OFDocumentAccess, LegislationPack, TaxRate, RecurringEntry, RegularizationEntry, CurrencyRevaluation, AnalyticPlan, DistributionGrill, DistributionGrillLine, BankReconciliationRule, BankStatementImport, TvsDeclaration, FiscalBackup, ProductVariant, ProductSerialNumber, ProductBatch, WarehouseLocation, QualityCheck, PickList, SalesRepresentative, Prospect, ProductSubstitute, DeliverySchedule, RecurringInvoiceTemplate, DocumentTemplate, FutureAccountingMovement, TreasuryTransfer, CreditLine, Investment, ValueDateTracking, TreasuryRecurring, ConsolidatedTreasury, PayrollComponent, PayrollTemplate, SalaryAdvance, PayRecall, DsnDeclaration, DpaeRecord, WorkHardship, CareerHistory, CpfAccount, PayrollArchive, LegalWatch, EmployeeDocument, ExpenseReport, Interview, AssetDepreciationPlan, AssetFamily, AssetRevaluation, AssetDocument, AssetFreeField, AssetBatchDisposal, AssetSplit, AutoLabelRule, ExtourneLog, CarryForwardLog, LettrageDifference, AccountingControlRun, CashControlSession, FECAttestation, TierRIB, IFRSAdjustment, TaxPayment, CustomReportTemplate, DeferredPrintingJob, JournalAccessRight, VATOnCollection, BatchEntrySession, PaymentTerm, MarkingType, ReminderLevel, PaymentPromise, Dispute, JustificatifSolde, EtatRapprochement, RevisionCycle, ReportingPlan, StatField, DashboardWidget, FusionLog, CompactionLog, RGPDRequest, GridTemplate, PaymentTemplateCompta, AnalyticJournalCode, ReimputationLog, BankStatementTemplate, Bank, PayrollTaxGrid, PayrollTaxGridLine, CorporateTaxGrid, CorporateTaxGridLine, TaxGroup, TaxRepartitionLine, TaxCashBasisEntry, FiscalPosition, FiscalPositionMapping, AccountTag, AccountTagMapping, ExchangeRate, ExchangeGainLossEntry, CheckBook, Check, DocumentCharge, DocumentTransformation } from '@/types'

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

export async function createInvoice(invoice: Omit<Invoice, 'id' | 'created_at' | 'updated_at'> & { lines: Omit<InvoiceLine, 'id' | 'created_at'>[] }) {
  const tid = await getTenantId()
  const { lines, ...invoiceData } = invoice
  const { data: inv, error: invError } = await supabase.from('invoices').insert(ti(invoiceData, 'invoices', tid)).select().single()
  if (invError) throw invError
  
  if (lines && lines.length > 0) {
    const { error: linesError } = await supabase
      .from('invoice_lines')
      .insert(lines.map((l, i) => ti({ ...l, invoice_id: inv.id, line_order: i }, 'invoice_lines', tid)))
    if (linesError) throw linesError
  }
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
  const tid = await getTenantId()
  let qQ = supabase
    .from('quotes')
    .select('*, quote_lines(*)')
    .eq('id', quoteId)
  if (tid) qQ = qQ.eq('tenant_id', tid)
  const { data: quote, error: qErr } = await qQ.single()
  if (qErr) throw qErr

  const invNumber = 'FAC-' + new Date().getFullYear() + '-' + String(Math.floor(Math.random() * 999)).padStart(3, '0')
  const { data: inv, error: invErr } = await supabase.from('invoices').insert(ti({
    number: invNumber,
    customer_id: quote.customer_id,
    customer_name: quote.customer_name,
    date: new Date().toISOString().split('T')[0],
    due_date: new Date(Date.now() + 30 * 86400000).toISOString().split('T')[0],
    status: 'draft',
    subtotal: quote.subtotal,
    vat_total: quote.vat_total,
    total: quote.total,
    amount_paid: 0,
    amount_due: quote.total,
    notes: 'Converti depuis devis ' + quote.number,
  }, 'invoices', tid)).select().single()
  if (invErr) throw invErr

  if (quote.quote_lines && quote.quote_lines.length > 0) {
    const { error: lErr } = await supabase
      .from('invoice_lines')
      .insert(quote.quote_lines.map((l: any, i: number) => ti({
        invoice_id: inv.id,
        product_id: l.product_id,
        description: l.description,
        quantity: l.quantity,
        unit_price: l.unit_price,
        vat_rate: l.vat_rate,
        total: l.total,
        vat_total: l.vat_total,
        line_order: i,
      }, 'invoice_lines', tid)))
    if (lErr) throw lErr
  }

  await tud(supabase.from('quotes').update({ status: 'accepted' }), 'quotes', tid).eq('id', quoteId)
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

export async function createPurchaseInvoice(invoice: Omit<PurchaseInvoice, 'id' | 'created_at' | 'updated_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('purchase_invoices').insert(ti(invoice, 'purchase_invoices', tid)).select().single()
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

export async function createPurchaseCreditNote(pcn: Omit<PurchaseCreditNote, 'id' | 'created_at'> & { lines: Omit<PurchaseCreditNoteLine, 'id' | 'created_at'>[] }) {
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

