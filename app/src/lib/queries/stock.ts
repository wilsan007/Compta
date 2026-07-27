import { supabase } from '@/lib/supabase'
import { getTenantId, ti, tud, clearTenantCache } from './core'
import type { Customer, Supplier, Product, Invoice, Quote, QuoteLine, CreditNote, CreditNoteLine, PurchaseCreditNote, PurchaseCreditNoteLine, PurchaseInvoice, BankAccount, BankTransaction, BankRule, BankConnection, PartnerBankAccount, PartnerContact, PartnerCategory, JournalEntry, JournalLine, ChartAccount, CompanySettings, Project, VatReturn, InvoiceLine, DashboardStats, FixedAsset, Employee, PayRun, Timesheet, StockMovement, Currency, Journal, FiscalYear, FiscalPeriod, EntryTemplate, ThirdPartyAccount, AnalyticSection, Budget, BudgetCommitment, BudgetControlResult, StandardLabel, PaymentOrder, AssetDepreciation, CollectionReminder, SalesOrder, SalesOrderLine, DeliveryNote, DeliveryNoteLine, CustomerPayment, PurchaseOrder, GoodsReceipt, SupplierPayment, Warehouse, StockQuantity, PriceList, PriceListLine, BOM, BOMLine, ManufacturingOrder, PaySlip, PayrollAccountingEntry, LeaveRequest, Contract, LegalDeclaration, AuditLog, Routing, RoutingOperation, WorkCenter, Machine, Tooling, OFLabel, OFLot, OFConsumption, STOrder, STShipment, STShipmentLine, STReceipt, STReceiptLine, MRPRun, MRPProposal, ProductionForecast, PlanningSlot, ProductEquivalence, Workflow, OFDocumentAccess, LegislationPack, TaxRate, RecurringEntry, RegularizationEntry, CurrencyRevaluation, AnalyticPlan, DistributionGrill, DistributionGrillLine, BankReconciliationRule, BankStatementImport, TvsDeclaration, FiscalBackup, ProductVariant, ProductSerialNumber, ProductBatch, WarehouseLocation, QualityCheck, PickList, SalesRepresentative, Prospect, ProductSubstitute, DeliverySchedule, RecurringInvoiceTemplate, DocumentTemplate, FutureAccountingMovement, TreasuryTransfer, CreditLine, Investment, ValueDateTracking, TreasuryRecurring, ConsolidatedTreasury, PayrollComponent, PayrollTemplate, SalaryAdvance, PayRecall, DsnDeclaration, DpaeRecord, WorkHardship, CareerHistory, CpfAccount, PayrollArchive, LegalWatch, EmployeeDocument, ExpenseReport, Interview, AssetDepreciationPlan, AssetFamily, AssetRevaluation, AssetDocument, AssetFreeField, AssetBatchDisposal, AssetSplit, AutoLabelRule, ExtourneLog, CarryForwardLog, LettrageDifference, AccountingControlRun, CashControlSession, FECAttestation, TierRIB, IFRSAdjustment, TaxPayment, CustomReportTemplate, DeferredPrintingJob, JournalAccessRight, VATOnCollection, BatchEntrySession, PaymentTerm, MarkingType, ReminderLevel, PaymentPromise, Dispute, JustificatifSolde, EtatRapprochement, RevisionCycle, ReportingPlan, StatField, DashboardWidget, FusionLog, CompactionLog, RGPDRequest, GridTemplate, PaymentTemplateCompta, AnalyticJournalCode, ReimputationLog, BankStatementTemplate, Bank, PayrollTaxGrid, PayrollTaxGridLine, CorporateTaxGrid, CorporateTaxGridLine, TaxGroup, TaxRepartitionLine, TaxCashBasisEntry, FiscalPosition, FiscalPositionMapping, AccountTag, AccountTagMapping, ExchangeRate, ExchangeGainLossEntry, CheckBook, Check, DocumentCharge, DocumentTransformation } from '@/types'

// ============ Products ============
export async function getProducts() {
  const tid = await getTenantId()
  let q = supabase.from('products').select('*').order('name', { ascending: true })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as Product[]
}

export async function createProduct(product: Omit<Product, 'id' | 'created_at' | 'updated_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('products').insert({ ...product, tenant_id: tid }).select().single()
  if (error) throw error
  return data as Product
}

export async function updateProduct(id: string, updates: Partial<Product>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('products').update(updates), 'products', tid).eq('id', id).select().single()
  if (error) throw error
  return data as Product
}

export async function deleteProduct(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('products').delete(), 'products', tid).eq('id', id)
  if (error) throw error
}


// ============ Stock Movements ============
export async function getStockMovements(productId?: string, warehouseId?: string) {
  const tid = await getTenantId()
  let query = supabase.from('stock_movements').select('*, products(name, sku), warehouses(name)').order('movement_date', { ascending: false }).limit(100)
  if (tid) query = query.eq('tenant_id', tid)
  if (productId) query = query.eq('product_id', productId)
  if (warehouseId) query = query.eq('warehouse_id', warehouseId)
  const { data, error } = await query
  if (error) throw error
  return data as any[]
}

export async function createStockMovement(sm: Omit<StockMovement, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('stock_movements').insert(ti(sm, 'stock_movements', tid)).select().single()
  if (error) throw error
  if (sm.movement_type === 'in') {
    await supabase.rpc('increment_stock', { p_id: sm.product_id, qty: sm.quantity })
  } else if (sm.movement_type === 'out') {
    await supabase.rpc('decrement_stock', { p_id: sm.product_id, qty: sm.quantity })
  } else {
    await tud(supabase.from('products').update({ stock_quantity: sm.quantity }), 'products', tid).eq('id', sm.product_id)
  }
  return data as StockMovement
}


// ============ Sprint 6: Warehouses ============
export async function getWarehouses() {
  const tid = await getTenantId()
  let q = supabase.from('warehouses').select('*').order('name')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as Warehouse[]
}

export async function createWarehouse(w: Omit<Warehouse, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('warehouses').insert(ti(w, 'warehouses', tid)).select().single()
  if (error) throw error
  return data as Warehouse
}

export async function updateWarehouse(id: string, updates: Partial<Warehouse>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('warehouses').update(updates), 'warehouses', tid).eq('id', id).select().single()
  if (error) throw error
  return data as Warehouse
}

export async function deleteWarehouse(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('warehouses').delete(), 'warehouses', tid).eq('id', id)
  if (error) throw error
}


// ============ Sprint 6: Stock Quantities ============
export async function getStockQuantities(warehouseId?: string) {
  const tid = await getTenantId()
  let q = supabase.from('stock_quantities').select('*, products(name, sku), warehouses(name)').order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (warehouseId) q = q.eq('warehouse_id', warehouseId)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}

export async function updateStockQuantity(id: string, updates: Partial<StockQuantity>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('stock_quantities').update({ ...updates, updated_at: new Date().toISOString() }), 'stock_quantities', tid).eq('id', id).select().single()
  if (error) throw error
  return data as StockQuantity
}


// ============ Sprint 6: Price Lists ============
export async function getPriceLists() {
  const tid = await getTenantId()
  let q = supabase.from('price_lists').select('*').order('name')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as PriceList[]
}

export async function createPriceList(pl: Omit<PriceList, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('price_lists').insert(ti(pl, 'price_lists', tid)).select().single()
  if (error) throw error
  return data as PriceList
}

export async function updatePriceList(id: string, updates: Partial<PriceList>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('price_lists').update(updates), 'price_lists', tid).eq('id', id).select().single()
  if (error) throw error
  return data as PriceList
}

export async function deletePriceList(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('price_lists').delete(), 'price_lists', tid).eq('id', id)
  if (error) throw error
}

export async function getPriceListLines(priceListId: string) {
  const tid = await getTenantId()
  let q = supabase.from('price_list_lines').select('*, products(name, sku)').eq('price_list_id', priceListId).order('min_quantity')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}

export async function createPriceListLine(pll: Omit<PriceListLine, 'id'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('price_list_lines').insert(ti(pll, 'price_list_lines', tid)).select().single()
  if (error) throw error
  return data as PriceListLine
}

export async function deletePriceListLine(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('price_list_lines').delete(), 'price_list_lines', tid).eq('id', id)
  if (error) throw error
}


// ============ Sprint 6: BOMs ============
export async function getBOMs() {
  const tid = await getTenantId()
  let q = supabase.from('boms').select('*').order('code')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as BOM[]
}

export async function createBOM(b: Omit<BOM, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('boms').insert(ti(b, 'boms', tid)).select().single()
  if (error) throw error
  return data as BOM
}

export async function deleteBOM(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('boms').delete(), 'boms', tid).eq('id', id)
  if (error) throw error
}

export async function getBOMLines(bomId: string) {
  const tid = await getTenantId()
  let q = supabase.from('bom_lines').select('*, products(name, sku)').eq('bom_id', bomId).order('position')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}

export async function createBOMLine(bl: Omit<BOMLine, 'id'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('bom_lines').insert(ti(bl, 'bom_lines', tid)).select().single()
  if (error) throw error
  return data as BOMLine
}

export async function deleteBOMLine(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('bom_lines').delete(), 'bom_lines', tid).eq('id', id)
  if (error) throw error
}


// ============ Production Module: Routings ============
export async function getRoutings() {
  const tid = await getTenantId()
  let q = supabase.from('routings').select('*, products(name, sku)').order('code')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}

export async function createRouting(r: Omit<Routing, 'id' | 'created_at' | 'updated_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('routings').insert(ti(r, 'routings', tid)).select().single()
  if (error) throw error
  return data as Routing
}

export async function updateRouting(id: string, updates: Partial<Routing>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('routings').update(updates), 'routings', tid).eq('id', id).select().single()
  if (error) throw error
  return data as Routing
}

export async function deleteRouting(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('routings').delete(), 'routings', tid).eq('id', id)
  if (error) throw error
}

export async function getRoutingOperations(routingId: string) {
  const tid = await getTenantId()
  let q = supabase.from('routing_operations').select('*, work_centers(name), machines(name), toolings(name), suppliers(name)').eq('routing_id', routingId).order('sequence')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}

export async function createRoutingOperation(op: Omit<RoutingOperation, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('routing_operations').insert(ti(op, 'routing_operations', tid)).select().single()
  if (error) throw error
  return data as RoutingOperation
}

export async function updateRoutingOperation(id: string, updates: Partial<RoutingOperation>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('routing_operations').update(updates), 'routing_operations', tid).eq('id', id).select().single()
  if (error) throw error
  return data as RoutingOperation
}

export async function deleteRoutingOperation(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('routing_operations').delete(), 'routing_operations', tid).eq('id', id)
  if (error) throw error
}

export async function renumberRoutingOperation(id: string, newSequence: number) {
  return updateRoutingOperation(id, { sequence: newSequence })
}

export async function renumberAllOperations(routingId: string) {
  const ops = await getRoutingOperations(routingId)
  for (let i = 0; i < ops.length; i++) {
    await updateRoutingOperation(ops[i].id, { sequence: (i + 1) * 10 })
  }
}


// ============ Production Module: Work Centers ============
export async function getWorkCenters() {
  const tid = await getTenantId()
  let q = supabase.from('work_centers').select('*').order('code')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as WorkCenter[]
}

export async function createWorkCenter(wc: Omit<WorkCenter, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('work_centers').insert(ti(wc, 'work_centers', tid)).select().single()
  if (error) throw error
  return data as WorkCenter
}

export async function deleteWorkCenter(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('work_centers').delete(), 'work_centers', tid).eq('id', id)
  if (error) throw error
}


// ============ Production Module: Machines ============
export async function getMachines() {
  const tid = await getTenantId()
  let q = supabase.from('machines').select('*, work_centers(name)').order('code')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}

export async function createMachine(m: Omit<Machine, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('machines').insert(ti(m, 'machines', tid)).select().single()
  if (error) throw error
  return data as Machine
}

export async function updateMachine(id: string, updates: Partial<Machine>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('machines').update(updates), 'machines', tid).eq('id', id).select().single()
  if (error) throw error
  return data as Machine
}

export async function deleteMachine(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('machines').delete(), 'machines', tid).eq('id', id)
  if (error) throw error
}


// ============ Production Module: Toolings ============
export async function getToolings() {
  const tid = await getTenantId()
  let q = supabase.from('toolings').select('*, machines(name)').order('code')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}

export async function createTooling(t: Omit<Tooling, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('toolings').insert(ti(t, 'toolings', tid)).select().single()
  if (error) throw error
  return data as Tooling
}

export async function updateTooling(id: string, updates: Partial<Tooling>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('toolings').update(updates), 'toolings', tid).eq('id', id).select().single()
  if (error) throw error
  return data as Tooling
}

export async function deleteTooling(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('toolings').delete(), 'toolings', tid).eq('id', id)
  if (error) throw error
}


// ============ Production Module: OF Labels ============
export async function getOFLabels(moId: string) {
  const tid = await getTenantId()
  let q = supabase.from('of_labels').select('*, products(name, sku)').eq('manufacturing_order_id', moId).order('label_number')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}

export async function createOFLabel(label: Omit<OFLabel, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('of_labels').insert(ti(label, 'of_labels', tid)).select().single()
  if (error) throw error
  return data as OFLabel
}

export async function updateOFLabel(id: string, updates: Partial<OFLabel>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('of_labels').update(updates), 'of_labels', tid).eq('id', id).select().single()
  if (error) throw error
  return data as OFLabel
}

export async function deleteOFLabel(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('of_labels').delete(), 'of_labels', tid).eq('id', id)
  if (error) throw error
}

export async function generateOFLabels(moId: string, count: number, plannedQtyPerLabel: number, productId: string | null) {
  const existing = await getOFLabels(moId)
  const startNum = existing.length + 1
  for (let i = 0; i < count; i++) {
    await createOFLabel({
      manufacturing_order_id: moId,
      label_number: `LBL-${String(startNum + i).padStart(3, '0')}`,
      product_id: productId,
      planned_quantity: plannedQtyPerLabel,
      actual_quantity: 0,
      is_complete: false,
      is_declared: false,
    })
  }
}


// ============ Production Module: OF Lots ============
export async function getOFLots(moId: string) {
  const tid = await getTenantId()
  let q = supabase.from('of_lots').select('*, products(name, sku)').eq('manufacturing_order_id', moId).order('lot_number')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}

export async function createOFLot(lot: Omit<OFLot, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('of_lots').insert(ti(lot, 'of_lots', tid)).select().single()
  if (error) throw error
  return data as OFLot
}

export async function deleteOFLot(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('of_lots').delete(), 'of_lots', tid).eq('id', id)
  if (error) throw error
}


// ============ Production Module: OF Consumptions ============
export async function getOFConsumptions(moId: string) {
  const tid = await getTenantId()
  let q = supabase.from('of_consumptions').select('*, products(name, sku)').eq('manufacturing_order_id', moId).order('consumption_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}

export async function createOFConsumption(cons: Omit<OFConsumption, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('of_consumptions').insert(ti(cons, 'of_consumptions', tid)).select().single()
  if (error) throw error
  return data as OFConsumption
}

export async function deleteOFConsumption(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('of_consumptions').delete(), 'of_consumptions', tid).eq('id', id)
  if (error) throw error
}


// ============ Production Module: Manufacturing Order Detail ============
export async function getManufacturingOrder(id: string) {
  const tid = await getTenantId()
  let q = supabase.from('manufacturing_orders').select('*, boms(name, code), products(name, sku), warehouses(name), routings(name, code)').eq('id', id)
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q.single()
  if (error) throw error
  return data as any
}

export async function getSubManufacturingOrders(parentId: string) {
  const tid = await getTenantId()
  let q = supabase.from('manufacturing_orders').select('*').eq('parent_mo_id', parentId).order('number')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as ManufacturingOrder[]
}


// ============ Production Module: Subcontracting Orders ============
export async function getSTOrders() {
  const tid = await getTenantId()
  let q = supabase.from('st_orders').select('*, suppliers(name), products(name, sku), manufacturing_orders(number)').order('order_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}

export async function createSTOrder(order: Omit<STOrder, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('st_orders').insert(ti(order, 'st_orders', tid)).select().single()
  if (error) throw error
  return data as STOrder
}

export async function updateSTOrder(id: string, updates: Partial<STOrder>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('st_orders').update(updates), 'st_orders', tid).eq('id', id).select().single()
  if (error) throw error
  return data as STOrder
}

export async function deleteSTOrder(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('st_orders').delete(), 'st_orders', tid).eq('id', id)
  if (error) throw error
}


// ============ Production Module: Subcontracting Shipments ============
export async function getSTShipments() {
  const tid = await getTenantId()
  let q = supabase.from('st_shipments').select('*, st_orders(number, suppliers(name)), warehouses(name)').order('shipment_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}

export async function createSTShipment(ship: Omit<STShipment, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('st_shipments').insert(ti(ship, 'st_shipments', tid)).select().single()
  if (error) throw error
  return data as STShipment
}

export async function deleteSTShipment(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('st_shipments').delete(), 'st_shipments', tid).eq('id', id)
  if (error) throw error
}

export async function getSTShipmentLines(shipId: string) {
  const tid = await getTenantId()
  let q = supabase.from('st_shipment_lines').select('*, products(name, sku)').eq('st_shipment_id', shipId)
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}

export async function createSTShipmentLine(line: Omit<STShipmentLine, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('st_shipment_lines').insert(ti(line, 'st_shipment_lines', tid)).select().single()
  if (error) throw error
  return data as STShipmentLine
}

export async function deleteSTShipmentLine(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('st_shipment_lines').delete(), 'st_shipment_lines', tid).eq('id', id)
  if (error) throw error
}


// ============ Production Module: Subcontracting Receipts ============
export async function getSTReceipts() {
  const tid = await getTenantId()
  let q = supabase.from('st_receipts').select('*, st_orders(number, suppliers(name)), warehouses(name)').order('receipt_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}

export async function createSTReceipt(receipt: Omit<STReceipt, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('st_receipts').insert(ti(receipt, 'st_receipts', tid)).select().single()
  if (error) throw error
  return data as STReceipt
}

export async function deleteSTReceipt(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('st_receipts').delete(), 'st_receipts', tid).eq('id', id)
  if (error) throw error
}

export async function getSTReceiptLines(receiptId: string) {
  const tid = await getTenantId()
  let q = supabase.from('st_receipt_lines').select('*, products(name, sku)').eq('st_receipt_id', receiptId)
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}

export async function createSTReceiptLine(line: Omit<STReceiptLine, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('st_receipt_lines').insert(ti(line, 'st_receipt_lines', tid)).select().single()
  if (error) throw error
  return data as STReceiptLine
}

export async function deleteSTReceiptLine(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('st_receipt_lines').delete(), 'st_receipt_lines', tid).eq('id', id)
  if (error) throw error
}


// ============ Production Module: Subcontracting Supervisor ============
export async function getSTSupervisorData() {
  const tid = await getTenantId()
  let oq = supabase.from('st_orders').select('*, suppliers(name), products(name, sku), st_shipments(number, shipment_date, status), st_receipts(number, receipt_date, status, quantity_received)').order('order_date', { ascending: false })
  if (tid) oq = oq.eq('tenant_id', tid)
  const { data, error } = await oq
  if (error) throw error
  return data as any[]
}


// ============ Production Module: MRP Runs ============
export async function getMRPRuns() {
  const tid = await getTenantId()
  let q = supabase.from('mrp_runs').select('*').order('run_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as MRPRun[]
}

export async function createMRPRun(run: Omit<MRPRun, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('mrp_runs').insert(ti(run, 'mrp_runs', tid)).select().single()
  if (error) throw error
  return data as MRPRun
}

export async function deleteMRPRun(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('mrp_runs').delete(), 'mrp_runs', tid).eq('id', id)
  if (error) throw error
}


// ============ Production Module: MRP Proposals ============
export async function getMRPProposals(runId: string) {
  const tid = await getTenantId()
  let q = supabase.from('mrp_proposals').select('*, products(name, sku, exclude_from_mrp), boms(code, name), suppliers(name)').eq('mrp_run_id', runId).order('net_need', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}

export async function updateMRPProposal(id: string, updates: Partial<MRPProposal>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('mrp_proposals').update(updates), 'mrp_proposals', tid).eq('id', id).select().single()
  if (error) throw error
  return data as MRPProposal
}

export async function deleteMRPProposal(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('mrp_proposals').delete(), 'mrp_proposals', tid).eq('id', id)
  if (error) throw error
}


// ============ Production Module: MRP Pending Docs ============
export async function getMRPPendingDocs() {
  const tid = await getTenantId()
  let q = supabase.from('mrp_pending_docs').select('*, products(name, sku)').order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}

export async function deleteMRPPendingDoc(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('mrp_pending_docs').delete(), 'mrp_pending_docs', tid).eq('id', id)
  if (error) throw error
}


// ============ Production Module: MRP Calculation Algorithm ============
export async function runMRPCalculation(): Promise<MRPRun> {
  const tid = await getTenantId()
  const runNumber = `MRP-${new Date().getFullYear()}-${String(Date.now()).slice(-6)}`

  const run = await createMRPRun({
    run_number: runNumber,
    run_date: new Date().toISOString(),
    status: 'running',
    parameters: { generated_at: new Date().toISOString() },
    summary: null,
  })

  try {
    const [products, boms, bomLines, stockQtys, openMOs, openPOs] = await Promise.all([
      getProducts(),
      getBOMs(),
      supabase.from('bom_lines').select('*').eq('tenant_id', tid).then(r => r.data || []),
      supabase.from('stock_quantities').select('*').eq('tenant_id', tid).then(r => r.data || []),
      supabase.from('manufacturing_orders').select('*').eq('tenant_id', tid).in('status', ['planned', 'in_progress']).then(r => r.data || []),
      supabase.from('purchase_orders').select('*').eq('tenant_id', tid).in('status', ['draft', 'sent']).then(r => r.data || []),
    ])

    // Build stock map: product_id -> total quantity
    const stockMap: Record<string, number> = {}
    for (const sq of stockQtys as any[]) {
      stockMap[sq.product_id] = (stockMap[sq.product_id] || 0) + Number(sq.quantity || 0)
    }

    // Build open MO map: product_id -> total quantity (from MO product_id or BOM product_id)
    const openMOMap: Record<string, number> = {}
    for (const mo of openMOs as any[]) {
      if (mo.product_id) openMOMap[mo.product_id] = (openMOMap[mo.product_id] || 0) + Number(mo.quantity || 0)
      if (mo.bom_id) {
        const bom = (boms as any[]).find((b) => b.id === mo.bom_id)
        if (bom?.product_id) openMOMap[bom.product_id] = (openMOMap[bom.product_id] || 0) + Number(mo.quantity || 0)
      }
    }

    // Build open PO map: product_id -> total quantity
    const openPOMap: Record<string, number> = {}
    for (const po of openPOs as any[]) {
      if (po.product_id) openPOMap[po.product_id] = (openPOMap[po.product_id] || 0) + Number(po.quantity || 0)
    }

    // Build BOM line map: product_id -> [{component_id, quantity}]
    const bomLineMap: Record<string, any[]> = {}
    for (const bl of bomLines as any[]) {
      if (!bomLineMap[bl.bom_id]) bomLineMap[bl.bom_id] = []
      bomLineMap[bl.bom_id].push({ product_id: bl.product_id, quantity: Number(bl.quantity) })
    }

    // Build BOM map: product_id -> bom
    const bomByProduct: Record<string, any> = {}
    for (const bom of boms as any[]) {
      if (bom.product_id) bomByProduct[bom.product_id] = bom
    }

    // Calculate gross needs: sum of all MO quantities * BOM line quantities
    const grossNeeds: Record<string, number> = {}
    for (const mo of openMOs as any[]) {
      if (mo.bom_id && bomLineMap[mo.bom_id]) {
        for (const line of bomLineMap[mo.bom_id]) {
          grossNeeds[line.product_id] = (grossNeeds[line.product_id] || 0) + line.quantity * Number(mo.quantity || 0)
        }
      }
      if (mo.product_id) {
        grossNeeds[mo.product_id] = (grossNeeds[mo.product_id] || 0) + Number(mo.quantity || 0)
      }
    }

    // Generate proposals
    const proposals: Omit<MRPProposal, 'id' | 'created_at'>[] = []
    for (const product of products as any[]) {
      if (product.exclude_from_mrp) continue

      const grossNeed = grossNeeds[product.id] || 0
      if (grossNeed <= 0) continue

      const stock = stockMap[product.id] || 0
      const openOrders = (openMOMap[product.id] || 0) + (openPOMap[product.id] || 0)
      const netNeed = Math.max(0, grossNeed - stock - openOrders)

      if (netNeed <= 0) continue

      const hasBOM = bomByProduct[product.id]
      const proposalType = hasBOM ? 'manufacture' : 'purchase'
      const suggestedQty = Math.ceil(netNeed)

      proposals.push({
        mrp_run_id: run.id,
        product_id: product.id,
        proposal_type: proposalType as any,
        gross_need: grossNeed,
        stock_available: stock,
        open_orders: openOrders,
        net_need: netNeed,
        suggested_quantity: suggestedQty,
        suggested_date: new Date(Date.now() + 7 * 86400000).toISOString().split('T')[0],
        bom_id: hasBOM?.id || null,
        supplier_id: product.supplier_id || null,
        status: 'pending',
        notes: null,
      })
    }

    // Insert proposals
    for (const p of proposals) {
      await supabase.from('mrp_proposals').insert(ti(p, 'mrp_proposals', tid))
    }

    // Update run with summary
    const summary = {
      total_products: products.length,
      products_with_needs: proposals.length,
      total_net_need: proposals.reduce((sum, p) => sum + p.net_need, 0),
      manufacture_count: proposals.filter((p) => p.proposal_type === 'manufacture').length,
      purchase_count: proposals.filter((p) => p.proposal_type === 'purchase').length,
    }
    await updateMRPRun(run.id, { status: 'completed', summary })

    return { ...run, status: 'completed', summary }
  } catch (err) {
    await updateMRPRun(run.id, { status: 'cancelled' })
    throw err
  }
}

async function updateMRPRun(id: string, updates: Partial<MRPRun>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('mrp_runs').update(updates as any), 'mrp_runs', tid).eq('id', id).select().single()
  if (error) throw error
  return data as MRPRun
}


// ============ Production Module: Production Forecasts ============
export async function getProductionForecasts() {
  const tid = await getTenantId()
  let q = supabase.from('production_forecasts').select('*, products(name, sku)').order('start_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}

export async function createProductionForecast(f: Omit<ProductionForecast, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('production_forecasts').insert(ti(f, 'production_forecasts', tid)).select().single()
  if (error) throw error
  return data as ProductionForecast
}

export async function deleteProductionForecast(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('production_forecasts').delete(), 'production_forecasts', tid).eq('id', id)
  if (error) throw error
}

export async function importForecastsFromInvoices(period: string, startDate: string, endDate: string) {
  const tid = await getTenantId()
  let q = supabase.from('invoices').select('*, invoice_lines(product_id, quantity)').eq('status', 'paid').gte('issue_date', startDate).lte('issue_date', endDate)
  if (tid) q = q.eq('tenant_id', tid)
  const { data: invoices, error } = await q
  if (error) throw error

  const productQtyMap: Record<string, number> = {}
  for (const inv of invoices || []) {
    for (const line of (inv as any).invoice_lines || []) {
      if (line.product_id) {
        productQtyMap[line.product_id] = (productQtyMap[line.product_id] || 0) + Number(line.quantity || 0)
      }
    }
  }

  const products = await getProducts()
  let count = 0
  for (const product of products as any[]) {
    if (product.exclude_from_mrp) continue
    const qty = productQtyMap[product.id] || 0
    if (qty <= 0) continue

    const num = `PREV-${period}-${String(count + 1).padStart(3, '0')}`
    await supabase.from('production_forecasts').insert(ti({
      forecast_number: num, period, start_date: startDate, end_date: endDate,
      product_id: product.id, forecasted_quantity: qty, actual_quantity: 0,
      reliability_rate: 0, source: 'invoice_import', notes: null,
    }, 'production_forecasts', tid))
    count++
  }
  return count
}

export async function calculateForecastReliability(forecastId: string) {
  const tid = await getTenantId()
  let q = supabase.from('production_forecasts').select('*').eq('id', forecastId)
  if (tid) q = q.eq('tenant_id', tid)
  const { data: forecast } = await q.single()
  if (!forecast) throw new Error('Forecast not found')

  const forecasted = Number((forecast as any).forecasted_quantity || 0)
  const actual = Number((forecast as any).actual_quantity || 0)
  const reliability = forecasted > 0 ? Math.min(100, Math.round((actual / forecasted) * 100 * 100) / 100) : 0

  const { data, error } = await tud(supabase.from('production_forecasts').update({ reliability_rate: reliability }), 'production_forecasts', tid).eq('id', forecastId).select().single()
  if (error) throw error
  return data as ProductionForecast
}


// ============ Production Module: Planning ============
export async function getPlanningSlots() {
  const tid = await getTenantId()
  let q = supabase.from('planning_slots').select('*, manufacturing_orders(number, quantity, status, boms(name)), routing_operations(name, sequence), machines(name, code), work_centers(name)').order('planned_start', { ascending: true })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}

export async function createPlanningSlot(slot: Omit<PlanningSlot, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('planning_slots').insert(ti(slot, 'planning_slots', tid)).select().single()
  if (error) throw error
  return data as PlanningSlot
}

export async function updatePlanningSlot(id: string, updates: Partial<PlanningSlot>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('planning_slots').update(updates), 'planning_slots', tid).eq('id', id).select().single()
  if (error) throw error
  return data as PlanningSlot
}

export async function deletePlanningSlot(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('planning_slots').delete(), 'planning_slots', tid).eq('id', id)
  if (error) throw error
}

export async function checkMaterialAvailability(slotId: string) {
  const tid = await getTenantId()
  let q = supabase.from('planning_slots').select('*, manufacturing_orders(bom_id, quantity)').eq('id', slotId)
  if (tid) q = q.eq('tenant_id', tid)
  const { data: slot } = await q.single()
  if (!slot) throw new Error('Slot not found')

  const mo = (slot as any).manufacturing_orders
  if (!mo?.bom_id) {
    await updatePlanningSlot(slotId, { material_available: true, material_check_date: new Date().toISOString() })
    return { available: true, missing: [] }
  }

  const bomLines = await getBOMLines(mo.bom_id)
  let stockQ = supabase.from('stock_quantities').select('product_id, quantity')
  if (tid) stockQ = stockQ.eq('tenant_id', tid)
  const stockQtys = await stockQ.then(r => r.data || [])
  const stockMap: Record<string, number> = {}
  for (const sq of stockQtys as any[]) {
    stockMap[sq.product_id] = (stockMap[sq.product_id] || 0) + Number(sq.quantity || 0)
  }

  const missing: { product_id: string; needed: number; available: number }[] = []
  for (const line of bomLines) {
    const needed = Number(line.quantity) * Number(mo.quantity || 0)
    const available = stockMap[line.product_id] || 0
    if (available < needed) {
      missing.push({ product_id: line.product_id, needed, available })
    }
  }

  const available = missing.length === 0
  await updatePlanningSlot(slotId, { material_available: available, material_check_date: new Date().toISOString() })
  return { available, missing }
}

export async function autoScheduleMOs() {
  const tid = await getTenantId()
  if (!tid) return { scheduled: 0, message: 'No tenant' }
  const [mos, machines, routings, routingOps] = await Promise.all([
    getManufacturingOrders('planned'),
    supabase.from('machines').select('*').eq('status', 'active').eq('tenant_id', tid).then(r => r.data || []),
    supabase.from('routings').select('*').eq('tenant_id', tid).then(r => r.data || []),
    supabase.from('routing_operations').select('*').eq('tenant_id', tid).order('sequence', { ascending: true }).then(r => r.data || []),
  ])

  let scheduled = 0
  const now = new Date()
  let currentTime = new Date(now)

  for (const mo of mos as any[]) {
    const routing = (routings as any[]).find((r) => r.id === mo.routing_id)
    if (!routing) continue

    const ops = (routingOps as any[]).filter((op) => op.routing_id === routing.id)
    if (ops.length === 0) continue

    const availableMachines = machines as any[]
    if (availableMachines.length === 0) continue

    let slotStart = new Date(currentTime)
    for (let i = 0; i < ops.length; i++) {
      const op = ops[i]
      const machine = availableMachines[i % availableMachines.length]
      const setupTime = Number(op.setup_time || 0)
      const runTime = Number(op.run_time || 0) * Number(mo.quantity || 1)
      const slotEnd = new Date(slotStart.getTime() + (setupTime + runTime) * 60000)

      await supabase.from('planning_slots').insert(ti({
        manufacturing_order_id: mo.id,
        routing_operation_id: op.id,
        machine_id: machine.id,
        work_center_id: op.work_center_id || null,
        planned_start: slotStart.toISOString(),
        planned_end: slotEnd.toISOString(),
        setup_time: setupTime,
        run_time: runTime,
        status: 'scheduled',
        material_available: true,
        material_check_date: null,
      }, 'planning_slots', tid))

      slotStart = new Date(slotEnd)
    }

    await updateManufacturingOrder(mo.id, { status: 'in_progress' } as any)
    currentTime = new Date(slotStart)
    scheduled++
  }

  return scheduled
}


// ============ Production Module: Article Interrogation ============
export async function getProductStock(productId: string) {
  const tid = await getTenantId()
  let q = supabase.from('stock_quantities').select('*, warehouses(name)').eq('product_id', productId)
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}

export async function getProductSupplierPrices(productId: string) {
  const tid = await getTenantId()
  let q = supabase.from('price_list_lines').select('*, price_lists(name, type), suppliers(name)').eq('product_id', productId)
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return (data as any[]).filter((line) => line.price_lists?.type === 'purchase')
}

export async function getProductDocuments(productId: string) {
  const tid = await getTenantId()
  if (!tid) return []
  const [invoices, purchaseOrders, manufacturingOrders, salesOrders] = await Promise.all([
    supabase.from('invoice_lines').select('*, invoices(number, issue_date, status)').eq('product_id', productId).eq('tenant_id', tid).then(r => r.data || []),
    supabase.from('purchase_order_lines').select('*, purchase_orders(number, order_date, status)').eq('product_id', productId).eq('tenant_id', tid).then(r => r.data || []),
    supabase.from('manufacturing_orders').select('number, planned_date, status, quantity').eq('product_id', productId).eq('tenant_id', tid).then(r => r.data || []),
    supabase.from('sales_order_lines').select('*, sales_orders(number, order_date, status)').eq('product_id', productId).eq('tenant_id', tid).then(r => r.data || []),
  ])

  const docs: any[] = []
  for (const line of invoices as any[]) {
    if (line.invoices) docs.push({ type: 'Facture', number: line.invoices.number, date: line.invoices.issue_date, quantity: line.quantity, status: line.invoices.status })
  }
  for (const line of purchaseOrders as any[]) {
    if (line.purchase_orders) docs.push({ type: 'Commande achat', number: line.purchase_orders.number, date: line.purchase_orders.order_date, quantity: line.quantity, status: line.purchase_orders.status })
  }
  for (const mo of manufacturingOrders as any[]) {
    docs.push({ type: 'OF', number: mo.number, date: mo.planned_date, quantity: mo.quantity, status: mo.status })
  }
  for (const line of salesOrders as any[]) {
    if (line.sales_orders) docs.push({ type: 'Commande vente', number: line.sales_orders.number, date: line.sales_orders.order_date, quantity: line.quantity, status: line.sales_orders.status })
  }
  return docs.sort((a, b) => new Date(b.date || 0).getTime() - new Date(a.date || 0).getTime())
}

export async function getProductBOMs(productId: string) {
  const tid = await getTenantId()
  if (!tid) return { asFinished: [], asComponent: [] }
  const [asFinished, asComponent] = await Promise.all([
    supabase.from('boms').select('*').eq('product_id', productId).eq('tenant_id', tid).then(r => r.data || []),
    supabase.from('bom_lines').select('*, boms(code, name)').eq('product_id', productId).eq('tenant_id', tid).then(r => r.data || []),
  ])
  return { asFinished: asFinished as any[], asComponent: asComponent as any[] }
}


// ============ Production Module: Complémentaires ============
export async function getProductEquivalences(productId?: string) {
  const tid = await getTenantId()
  let q = supabase.from('product_equivalences').select('*, products!product_equivalences_product_id_fkey(name, sku), products!product_equivalences_equivalent_product_id_fkey(name, sku)')
  if (tid) q = q.eq('tenant_id', tid)
  if (productId) q = q.eq('product_id', productId)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}

export async function createProductEquivalence(eq: Omit<ProductEquivalence, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('product_equivalences').insert(ti(eq, 'product_equivalences', tid)).select().single()
  if (error) throw error
  return data as ProductEquivalence
}

export async function deleteProductEquivalence(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('product_equivalences').delete(), 'product_equivalences', tid).eq('id', id)
  if (error) throw error
}

export async function getWorkflows() {
  const tid = await getTenantId()
  let q = supabase.from('workflows').select('*').order('name')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as Workflow[]
}

export async function createWorkflow(wf: Omit<Workflow, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('workflows').insert(ti(wf, 'workflows', tid)).select().single()
  if (error) throw error
  return data as Workflow
}

export async function updateWorkflow(id: string, updates: Partial<Workflow>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('workflows').update(updates), 'workflows', tid).eq('id', id).select().single()
  if (error) throw error
  return data as Workflow
}

export async function deleteWorkflow(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('workflows').delete(), 'workflows', tid).eq('id', id)
  if (error) throw error
}

export async function getOFDocumentAccess() {
  const tid = await getTenantId()
  let q = supabase.from('of_document_access').select('*, users(email, full_name)').order('document_type')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}

export async function createOFDocumentAccess(acc: Omit<OFDocumentAccess, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('of_document_access').insert(ti(acc, 'of_document_access', tid)).select().single()
  if (error) throw error
  return data as OFDocumentAccess
}

export async function updateOFDocumentAccess(id: string, updates: Partial<OFDocumentAccess>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('of_document_access').update(updates), 'of_document_access', tid).eq('id', id).select().single()
  if (error) throw error
  return data as OFDocumentAccess
}

export async function deleteOFDocumentAccess(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('of_document_access').delete(), 'of_document_access', tid).eq('id', id)
  if (error) throw error
}

export async function checkOFDocumentAccess(userId: string, documentType: string) {
  const tid = await getTenantId()
  let q = supabase.from('of_document_access').select('*').eq('user_id', userId).eq('document_type', documentType)
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q.maybeSingle()
  if (error) throw error
  if (!data) return { can_view: true, can_print: true, can_export: true }
  return { can_view: (data as any).can_view, can_print: (data as any).can_print, can_export: (data as any).can_export }
}


// ============ Phase 2: GesCom — Product Variants ============
export async function getProductVariants(productId?: string) {
  const tid = await getTenantId()
  let q = supabase.from('product_variants').select('*, products(name, sku)').order('sku')
  if (tid) q = q.eq('tenant_id', tid)
  if (productId) q = q.eq('product_id', productId)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}
export async function createProductVariant(v: Omit<ProductVariant, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('product_variants').insert(ti(v, 'product_variants', tid)).select().single()
  if (error) throw error
  return data as ProductVariant
}
export async function updateProductVariant(id: string, updates: Partial<ProductVariant>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('product_variants').update(updates), 'product_variants', tid).eq('id', id).select().single()
  if (error) throw error
  return data as ProductVariant
}
export async function deleteProductVariant(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('product_variants').delete(), 'product_variants', tid).eq('id', id)
  if (error) throw error
}


// ============ Phase 2: Product Serial Numbers ============
export async function getProductSerialNumbers(productId?: string) {
  const tid = await getTenantId()
  let q = supabase.from('product_serial_numbers').select('*, products(name, sku)').order('serial_number')
  if (tid) q = q.eq('tenant_id', tid)
  if (productId) q = q.eq('product_id', productId)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}
export async function createProductSerialNumber(s: Omit<ProductSerialNumber, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('product_serial_numbers').insert(ti(s, 'product_serial_numbers', tid)).select().single()
  if (error) throw error
  return data as ProductSerialNumber
}
export async function deleteProductSerialNumber(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('product_serial_numbers').delete(), 'product_serial_numbers', tid).eq('id', id)
  if (error) throw error
}


// ============ Phase 2: Product Batches ============
export async function getProductBatches(productId?: string) {
  const tid = await getTenantId()
  let q = supabase.from('product_batches').select('*, products(name, sku)').order('batch_number')
  if (tid) q = q.eq('tenant_id', tid)
  if (productId) q = q.eq('product_id', productId)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}
export async function createProductBatch(b: Omit<ProductBatch, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('product_batches').insert(ti(b, 'product_batches', tid)).select().single()
  if (error) throw error
  return data as ProductBatch
}
export async function deleteProductBatch(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('product_batches').delete(), 'product_batches', tid).eq('id', id)
  if (error) throw error
}


// ============ Phase 2: Warehouse Locations ============
export async function getWarehouseLocations(warehouseId?: string) {
  const tid = await getTenantId()
  let q = supabase.from('warehouse_locations').select('*, warehouses(name)').order('code')
  if (tid) q = q.eq('tenant_id', tid)
  if (warehouseId) q = q.eq('warehouse_id', warehouseId)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}
export async function createWarehouseLocation(l: Omit<WarehouseLocation, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('warehouse_locations').insert(ti(l, 'warehouse_locations', tid)).select().single()
  if (error) throw error
  return data as WarehouseLocation
}
export async function deleteWarehouseLocation(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('warehouse_locations').delete(), 'warehouse_locations', tid).eq('id', id)
  if (error) throw error
}


// ============ Phase 2: Product Substitutes ============
export async function getProductSubstitutes(productId?: string) {
  const tid = await getTenantId()
  let q = supabase.from('product_substitutes').select('*, products!product_substitutes_product_id_fkey(name, sku), products!product_substitutes_substitute_id_fkey(name as sub_name, sku as sub_sku)')
  if (tid) q = q.eq('tenant_id', tid)
  if (productId) q = q.eq('product_id', productId)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}
export async function createProductSubstitute(s: Omit<ProductSubstitute, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('product_substitutes').insert(ti(s, 'product_substitutes', tid)).select().single()
  if (error) throw error
  return data as ProductSubstitute
}
export async function deleteProductSubstitute(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('product_substitutes').delete(), 'product_substitutes', tid).eq('id', id)
  if (error) throw error
}

