import { supabase, getCachedTenantId, isTenantTable } from '@/lib/supabase'
import type { Customer, Supplier, Product, Invoice, Quote, QuoteLine, CreditNote, CreditNoteLine, PurchaseCreditNote, PurchaseCreditNoteLine, PurchaseInvoice, BankAccount, BankTransaction, BankRule, BankConnection, PartnerBankAccount, PartnerContact, PartnerCategory, JournalEntry, JournalLine, ChartAccount, CompanySettings, Project, VatReturn, InvoiceLine, DashboardStats, FixedAsset, Employee, PayRun, Timesheet, StockMovement, Currency, Journal, FiscalYear, FiscalPeriod, EntryTemplate, ThirdPartyAccount, AnalyticSection, Budget, BudgetCommitment, BudgetControlResult, StandardLabel, PaymentOrder, AssetDepreciation, CollectionReminder, SalesOrder, SalesOrderLine, DeliveryNote, DeliveryNoteLine, CustomerPayment, PurchaseOrder, GoodsReceipt, SupplierPayment, Warehouse, StockQuantity, PriceList, PriceListLine, BOM, BOMLine, ManufacturingOrder, PaySlip, PayrollAccountingEntry, LeaveRequest, Contract, LegalDeclaration, AuditLog, Routing, RoutingOperation, WorkCenter, Machine, Tooling, OFLabel, OFLot, OFConsumption, STOrder, STShipment, STShipmentLine, STReceipt, STReceiptLine, MRPRun, MRPProposal, ProductionForecast, PlanningSlot, ProductEquivalence, Workflow, OFDocumentAccess, LegislationPack, TaxRate, RecurringEntry, RegularizationEntry, CurrencyRevaluation, AnalyticPlan, DistributionGrill, DistributionGrillLine, BankReconciliationRule, BankStatementImport, TvsDeclaration, FiscalBackup, ProductVariant, ProductSerialNumber, ProductBatch, WarehouseLocation, QualityCheck, PickList, SalesRepresentative, Prospect, ProductSubstitute, DeliverySchedule, RecurringInvoiceTemplate, DocumentTemplate, FutureAccountingMovement, TreasuryTransfer, CreditLine, Investment, ValueDateTracking, TreasuryRecurring, ConsolidatedTreasury, PayrollComponent, PayrollTemplate, SalaryAdvance, PayRecall, DsnDeclaration, DpaeRecord, WorkHardship, CareerHistory, CpfAccount, PayrollArchive, LegalWatch, EmployeeDocument, ExpenseReport, Interview, AssetDepreciationPlan, AssetFamily, AssetRevaluation, AssetDocument, AssetFreeField, AssetBatchDisposal, AssetSplit, AutoLabelRule, ExtourneLog, CarryForwardLog, LettrageDifference, AccountingControlRun, CashControlSession, FECAttestation, TierRIB, IFRSAdjustment, TaxPayment, CustomReportTemplate, DeferredPrintingJob, JournalAccessRight, VATOnCollection, BatchEntrySession, PaymentTerm, MarkingType, ReminderLevel, PaymentPromise, Dispute, JustificatifSolde, EtatRapprochement, RevisionCycle, ReportingPlan, StatField, DashboardWidget, FusionLog, CompactionLog, RGPDRequest, GridTemplate, PaymentTemplateCompta, AnalyticJournalCode, ReimputationLog, BankStatementTemplate, Bank, PayrollTaxGrid, PayrollTaxGridLine, CorporateTaxGrid, CorporateTaxGridLine, TaxGroup, TaxRepartitionLine, TaxCashBasisEntry, FiscalPosition, FiscalPositionMapping, AccountTag, AccountTagMapping, ExchangeRate, ExchangeGainLossEntry, CheckBook, Check, DocumentCharge, DocumentTransformation } from '@/types'
// ============ Tenant Helper ============
// RLS policies filter at the DB level, but we also filter at the app level
// for performance (smaller payloads) and defense-in-depth.
let _cachedTenantId: string | null = null

export async function getTenantId(): Promise<string | null> {
  // Check global cache first (set by auth.tsx on login)
  const global = getCachedTenantId()
  if (global) { _cachedTenantId = global; return global }
  // Check local cache
  if (_cachedTenantId) return _cachedTenantId
  // Fetch from DB
  const { data: { session } } = await supabase.auth.getSession()
  if (!session) return null
  // User may belong to multiple tenants — pick the one from localStorage or the first
  const { data } = await supabase
    .from('tenant_users')
    .select('tenant_id')
    .eq('auth_id', session.user.id)
    .eq('status', 'active')
  if (data && data.length > 0) {
    const stored = localStorage.getItem('active_tenant_id')
    const match = data.find(tu => tu.tenant_id === stored)
    const tid = match?.tenant_id || data[0].tenant_id
    _cachedTenantId = tid
    return tid
  }
  return null
}

export function clearTenantCache() {
  _cachedTenantId = null
}

// Helper: add tenant_id to an insert payload if the table is tenant-scoped
// SECURITY: Always force tenant_id to the authenticated user's tenant — never trust client-supplied tenant_id
export function ti<T extends Record<string, any>>(payload: T, table: string, tid: string | null): T {
  if (tid && isTenantTable(table)) return { ...payload, tenant_id: tid }
  return payload
}

// Helper: apply tenant filter to update/delete query builders
// Usage: tud(supabase.from('invoices').update(...), 'invoices', tid).eq('id', id)
export function tud<T extends { eq: (col: string, val: any) => T }>(q: T, table: string, tid: string | null): T {
  if (tid && isTenantTable(table)) return q.eq('tenant_id', tid)
  return q
}

