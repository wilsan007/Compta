import { supabase } from '@/lib/supabase'
import { getTenantId, ti, tud, clearTenantCache } from './core'
import type { Customer, Supplier, Product, Invoice, Quote, QuoteLine, CreditNote, CreditNoteLine, PurchaseCreditNote, PurchaseCreditNoteLine, PurchaseInvoice, BankAccount, BankTransaction, BankRule, BankConnection, PartnerBankAccount, PartnerContact, PartnerCategory, JournalEntry, JournalLine, ChartAccount, CompanySettings, Project, VatReturn, InvoiceLine, DashboardStats, FixedAsset, Employee, PayRun, Timesheet, StockMovement, Currency, Journal, FiscalYear, FiscalPeriod, EntryTemplate, ThirdPartyAccount, AnalyticSection, Budget, BudgetCommitment, BudgetControlResult, StandardLabel, PaymentOrder, AssetDepreciation, CollectionReminder, SalesOrder, SalesOrderLine, DeliveryNote, DeliveryNoteLine, CustomerPayment, PurchaseOrder, GoodsReceipt, SupplierPayment, Warehouse, StockQuantity, PriceList, PriceListLine, BOM, BOMLine, ManufacturingOrder, PaySlip, PayrollAccountingEntry, LeaveRequest, Contract, LegalDeclaration, AuditLog, Routing, RoutingOperation, WorkCenter, Machine, Tooling, OFLabel, OFLot, OFConsumption, STOrder, STShipment, STShipmentLine, STReceipt, STReceiptLine, MRPRun, MRPProposal, ProductionForecast, PlanningSlot, ProductEquivalence, Workflow, OFDocumentAccess, LegislationPack, TaxRate, RecurringEntry, RegularizationEntry, CurrencyRevaluation, AnalyticPlan, DistributionGrill, DistributionGrillLine, BankReconciliationRule, BankStatementImport, TvsDeclaration, FiscalBackup, ProductVariant, ProductSerialNumber, ProductBatch, WarehouseLocation, QualityCheck, PickList, SalesRepresentative, Prospect, ProductSubstitute, DeliverySchedule, RecurringInvoiceTemplate, DocumentTemplate, FutureAccountingMovement, TreasuryTransfer, CreditLine, Investment, ValueDateTracking, TreasuryRecurring, ConsolidatedTreasury, PayrollComponent, PayrollTemplate, SalaryAdvance, PayRecall, DsnDeclaration, DpaeRecord, WorkHardship, CareerHistory, CpfAccount, PayrollArchive, LegalWatch, EmployeeDocument, ExpenseReport, Interview, AssetDepreciationPlan, AssetFamily, AssetRevaluation, AssetDocument, AssetFreeField, AssetBatchDisposal, AssetSplit, AutoLabelRule, ExtourneLog, CarryForwardLog, LettrageDifference, AccountingControlRun, CashControlSession, FECAttestation, TierRIB, IFRSAdjustment, TaxPayment, CustomReportTemplate, DeferredPrintingJob, JournalAccessRight, VATOnCollection, BatchEntrySession, PaymentTerm, MarkingType, ReminderLevel, PaymentPromise, Dispute, JustificatifSolde, EtatRapprochement, RevisionCycle, ReportingPlan, StatField, DashboardWidget, FusionLog, CompactionLog, RGPDRequest, GridTemplate, PaymentTemplateCompta, AnalyticJournalCode, ReimputationLog, BankStatementTemplate, Bank, PayrollTaxGrid, PayrollTaxGridLine, CorporateTaxGrid, CorporateTaxGridLine, TaxGroup, TaxRepartitionLine, TaxCashBasisEntry, FiscalPosition, FiscalPositionMapping, AccountTag, AccountTagMapping, ExchangeRate, ExchangeGainLossEntry, CheckBook, Check, DocumentCharge, DocumentTransformation } from '@/types'

// ============ Sprint 6: Manufacturing Orders ============
export async function getManufacturingOrders(status?: string) {
  const tid = await getTenantId()
  let q = supabase.from('manufacturing_orders').select('*, boms(name, code), products(name, sku), warehouses(name), routings(name, code)').order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (status) q = q.eq('status', status)
  const { data, error } = await q
  if (error) throw error
  return data as ManufacturingOrder[]
}

export async function createManufacturingOrder(mo: Omit<ManufacturingOrder, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('manufacturing_orders').insert(ti(mo, 'manufacturing_orders', tid)).select().single()
  if (error) throw error
  return data as ManufacturingOrder
}

export async function updateManufacturingOrder(id: string, updates: Partial<ManufacturingOrder>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('manufacturing_orders').update(updates), 'manufacturing_orders', tid).eq('id', id).select().single()
  if (error) throw error
  return data as ManufacturingOrder
}

export async function deleteManufacturingOrder(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('manufacturing_orders').delete(), 'manufacturing_orders', tid).eq('id', id)
  if (error) throw error
}


// ============ Phase 2: Quality Checks ============
export async function getQualityChecks() {
  const tid = await getTenantId()
  let q = supabase.from('quality_checks').select('*, products(name, sku)').order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}
export async function createQualityCheck(qc: Omit<QualityCheck, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('quality_checks').insert(ti(qc, 'quality_checks', tid)).select().single()
  if (error) throw error
  return data as QualityCheck
}
export async function updateQualityCheck(id: string, updates: Partial<QualityCheck>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('quality_checks').update(updates), 'quality_checks', tid).eq('id', id).select().single()
  if (error) throw error
  return data as QualityCheck
}


// ============ Phase 2: Pick Lists ============
export async function getPickLists() {
  const tid = await getTenantId()
  let q = supabase.from('pick_lists').select('*, warehouses(name)').order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}
export async function createPickList(p: Omit<PickList, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('pick_lists').insert(ti(p, 'pick_lists', tid)).select().single()
  if (error) throw error
  return data as PickList
}
export async function updatePickList(id: string, updates: Partial<PickList>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('pick_lists').update(updates), 'pick_lists', tid).eq('id', id).select().single()
  if (error) throw error
  return data as PickList
}

