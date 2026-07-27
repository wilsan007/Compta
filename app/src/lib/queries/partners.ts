import { supabase } from '@/lib/supabase'
import { getTenantId, ti, tud, clearTenantCache } from './core'
import type { Customer, Supplier, Product, Invoice, Quote, QuoteLine, CreditNote, CreditNoteLine, PurchaseCreditNote, PurchaseCreditNoteLine, PurchaseInvoice, BankAccount, BankTransaction, BankRule, BankConnection, PartnerBankAccount, PartnerContact, PartnerCategory, JournalEntry, JournalLine, ChartAccount, CompanySettings, Project, VatReturn, InvoiceLine, DashboardStats, FixedAsset, Employee, PayRun, Timesheet, StockMovement, Currency, Journal, FiscalYear, FiscalPeriod, EntryTemplate, ThirdPartyAccount, AnalyticSection, Budget, BudgetCommitment, BudgetControlResult, StandardLabel, PaymentOrder, AssetDepreciation, CollectionReminder, SalesOrder, SalesOrderLine, DeliveryNote, DeliveryNoteLine, CustomerPayment, PurchaseOrder, GoodsReceipt, SupplierPayment, Warehouse, StockQuantity, PriceList, PriceListLine, BOM, BOMLine, ManufacturingOrder, PaySlip, PayrollAccountingEntry, LeaveRequest, Contract, LegalDeclaration, AuditLog, Routing, RoutingOperation, WorkCenter, Machine, Tooling, OFLabel, OFLot, OFConsumption, STOrder, STShipment, STShipmentLine, STReceipt, STReceiptLine, MRPRun, MRPProposal, ProductionForecast, PlanningSlot, ProductEquivalence, Workflow, OFDocumentAccess, LegislationPack, TaxRate, RecurringEntry, RegularizationEntry, CurrencyRevaluation, AnalyticPlan, DistributionGrill, DistributionGrillLine, BankReconciliationRule, BankStatementImport, TvsDeclaration, FiscalBackup, ProductVariant, ProductSerialNumber, ProductBatch, WarehouseLocation, QualityCheck, PickList, SalesRepresentative, Prospect, ProductSubstitute, DeliverySchedule, RecurringInvoiceTemplate, DocumentTemplate, FutureAccountingMovement, TreasuryTransfer, CreditLine, Investment, ValueDateTracking, TreasuryRecurring, ConsolidatedTreasury, PayrollComponent, PayrollTemplate, SalaryAdvance, PayRecall, DsnDeclaration, DpaeRecord, WorkHardship, CareerHistory, CpfAccount, PayrollArchive, LegalWatch, EmployeeDocument, ExpenseReport, Interview, AssetDepreciationPlan, AssetFamily, AssetRevaluation, AssetDocument, AssetFreeField, AssetBatchDisposal, AssetSplit, AutoLabelRule, ExtourneLog, CarryForwardLog, LettrageDifference, AccountingControlRun, CashControlSession, FECAttestation, TierRIB, IFRSAdjustment, TaxPayment, CustomReportTemplate, DeferredPrintingJob, JournalAccessRight, VATOnCollection, BatchEntrySession, PaymentTerm, MarkingType, ReminderLevel, PaymentPromise, Dispute, JustificatifSolde, EtatRapprochement, RevisionCycle, ReportingPlan, StatField, DashboardWidget, FusionLog, CompactionLog, RGPDRequest, GridTemplate, PaymentTemplateCompta, AnalyticJournalCode, ReimputationLog, BankStatementTemplate, Bank, PayrollTaxGrid, PayrollTaxGridLine, CorporateTaxGrid, CorporateTaxGridLine, TaxGroup, TaxRepartitionLine, TaxCashBasisEntry, FiscalPosition, FiscalPositionMapping, AccountTag, AccountTagMapping, ExchangeRate, ExchangeGainLossEntry, CheckBook, Check, DocumentCharge, DocumentTransformation } from '@/types'

// ============ Customers ============
export async function getCustomers() {
  const tid = await getTenantId()
  let q = supabase.from('customers').select('*').order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as Customer[]
}

export async function createCustomer(customer: Omit<Customer, 'id' | 'created_at' | 'updated_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('customers').insert({ ...customer, tenant_id: tid }).select().single()
  if (error) throw error
  return data as Customer
}

export async function updateCustomer(id: string, updates: Partial<Customer>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('customers').update(updates), 'customers', tid).eq('id', id).select().single()
  if (error) throw error
  return data as Customer
}

export async function deleteCustomer(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('customers').delete(), 'customers', tid).eq('id', id)
  if (error) throw error
}


// ============ Suppliers ============
export async function getSuppliers() {
  const tid = await getTenantId()
  let q = supabase.from('suppliers').select('*').order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as Supplier[]
}

export async function createSupplier(supplier: Omit<Supplier, 'id' | 'created_at' | 'updated_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('suppliers').insert({ ...supplier, tenant_id: tid }).select().single()
  if (error) throw error
  return data as Supplier
}

export async function updateSupplier(id: string, updates: Partial<Supplier>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('suppliers').update(updates), 'suppliers', tid).eq('id', id).select().single()
  if (error) throw error
  return data as Supplier
}

export async function deleteSupplier(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('suppliers').delete(), 'suppliers', tid).eq('id', id)
  if (error) throw error
}


// ============ Sprint 6: Partner Contacts (#62) ============
export async function getPartnerContacts(partnerType: string, partnerId: string) {
  const tid = await getTenantId()
  let q = supabase.from('partner_contacts').select('*').eq('partner_type', partnerType).eq('partner_id', partnerId).order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as PartnerContact[]
}

export async function createPartnerContact(contact: Omit<PartnerContact, 'id' | 'created_at' | 'tenant_id'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('partner_contacts').insert(ti(contact, 'partner_contacts', tid)).select().single()
  if (error) throw error
  return data as PartnerContact
}

export async function updatePartnerContact(id: string, updates: Partial<PartnerContact>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('partner_contacts').update(updates), 'partner_contacts', tid).eq('id', id).select().single()
  if (error) throw error
  return data as PartnerContact
}

export async function deletePartnerContact(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('partner_contacts').delete(), 'partner_contacts', tid).eq('id', id)
  if (error) throw error
}


// ============ Sprint 6: Partner Categories (#64) ============
export async function getPartnerCategories() {
  const tid = await getTenantId()
  let q = supabase.from('partner_categories').select('*').order('name', { ascending: true })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as PartnerCategory[]
}

export async function createPartnerCategory(cat: Omit<PartnerCategory, 'id' | 'created_at' | 'tenant_id'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('partner_categories').insert(ti(cat, 'partner_categories', tid)).select().single()
  if (error) throw error
  return data as PartnerCategory
}

export async function updatePartnerCategory(id: string, updates: Partial<PartnerCategory>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('partner_categories').update(updates), 'partner_categories', tid).eq('id', id).select().single()
  if (error) throw error
  return data as PartnerCategory
}

export async function deletePartnerCategory(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('partner_categories').delete(), 'partner_categories', tid).eq('id', id)
  if (error) throw error
}


// ============ Sprint 6: Partner Bank Accounts (#80) ============
export async function getPartnerBankAccounts(partnerType: string, partnerId: string) {
  const tid = await getTenantId()
  let q = supabase.from('partner_bank_accounts').select('*').eq('partner_type', partnerType).eq('partner_id', partnerId).order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as PartnerBankAccount[]
}

export async function createPartnerBankAccount(bank: Omit<PartnerBankAccount, 'id' | 'created_at' | 'tenant_id'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('partner_bank_accounts').insert(ti(bank, 'partner_bank_accounts', tid)).select().single()
  if (error) throw error
  return data as PartnerBankAccount
}

export async function updatePartnerBankAccount(id: string, updates: Partial<PartnerBankAccount>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('partner_bank_accounts').update(updates), 'partner_bank_accounts', tid).eq('id', id).select().single()
  if (error) throw error
  return data as PartnerBankAccount
}

export async function deletePartnerBankAccount(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('partner_bank_accounts').delete(), 'partner_bank_accounts', tid).eq('id', id)
  if (error) throw error
}


// ============ Sprint 6: Customer Payments ============
export async function getCustomerPayments(status?: string) {
  const tid = await getTenantId()
  let q = supabase.from('customer_payments').select('*').order('payment_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (status) q = q.eq('status', status)
  const { data, error } = await q
  if (error) throw error
  return data as CustomerPayment[]
}

export async function createCustomerPayment(cp: Omit<CustomerPayment, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('customer_payments').insert(ti(cp, 'customer_payments', tid)).select().single()
  if (error) throw error
  return data as CustomerPayment
}

export async function deleteCustomerPayment(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('customer_payments').delete(), 'customer_payments', tid).eq('id', id)
  if (error) throw error
}


// ============ Sprint 6: Supplier Payments ============
export async function getSupplierPayments(status?: string) {
  const tid = await getTenantId()
  let q = supabase.from('supplier_payments').select('*').order('payment_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (status) q = q.eq('status', status)
  const { data, error } = await q
  if (error) throw error
  return data as SupplierPayment[]
}

export async function createSupplierPayment(sp: Omit<SupplierPayment, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('supplier_payments').insert(ti(sp, 'supplier_payments', tid)).select().single()
  if (error) throw error
  return data as SupplierPayment
}

export async function deleteSupplierPayment(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('supplier_payments').delete(), 'supplier_payments', tid).eq('id', id)
  if (error) throw error
}

