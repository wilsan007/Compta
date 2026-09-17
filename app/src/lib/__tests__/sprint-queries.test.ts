import { describe, it, expect, vi, beforeEach } from 'vitest'

// ============ Mock Infrastructure ============
function createMockChain(resolvedValue: { data: any; error: any } = { data: [], error: null }) {
  const chain: any = {
    select: vi.fn(() => chain),
    insert: vi.fn(() => chain),
    update: vi.fn(() => chain),
    delete: vi.fn(() => chain),
    eq: vi.fn(() => chain),
    neq: vi.fn(() => chain),
    order: vi.fn(() => chain),
    single: vi.fn(() => Promise.resolve(resolvedValue)),
    maybeSingle: vi.fn(() => Promise.resolve(resolvedValue)),
    limit: vi.fn(() => chain),
    // LOT7-03 : fetchAllRows pagine via .range() ; le mock doit renvoyer les mêmes
    // données que `then`, y compris après un setMockData qui réassigne `then`.
    range: vi.fn(() => new Promise((resolve) => chain.then(resolve))),
    in: vi.fn(() => chain),
    gte: vi.fn(() => chain),
    lte: vi.fn(() => chain),
    like: vi.fn(() => chain),
    ilike: vi.fn(() => chain),
    or: vi.fn(() => chain),
    not: vi.fn(() => chain),
    is: vi.fn(() => chain),
    count: vi.fn(() => chain),
    rpc: vi.fn(() => Promise.resolve(resolvedValue)),
    then: vi.fn((resolve: any) => Promise.resolve(resolvedValue).then(resolve)),
  }
  return chain
}

const mockChain = createMockChain()

vi.mock('@/lib/supabase', () => ({
  supabase: {
    from: vi.fn(() => mockChain),
    auth: {
      getSession: vi.fn(),
      signInWithPassword: vi.fn(),
      signOut: vi.fn(),
    },
    channel: vi.fn(),
    removeChannel: vi.fn(),
    rpc: vi.fn(() => Promise.resolve({ data: null, error: null })),
  },
  getCachedTenantId: vi.fn(() => 'test-tenant-id'),
  isTenantTable: vi.fn(() => true),
}))

import { supabase } from '@/lib/supabase'

function setMockData(data: any, error: any = null) {
  mockChain.single = vi.fn(() => Promise.resolve({ data, error }))
  mockChain.maybeSingle = vi.fn(() => Promise.resolve({ data, error }))
  mockChain.then = vi.fn((resolve: any) => Promise.resolve({ data, error }).then(resolve))
}

function resetMock() {
  mockChain.single = vi.fn(() => Promise.resolve({ data: null, error: null }))
  mockChain.maybeSingle = vi.fn(() => Promise.resolve({ data: null, error: null }))
  mockChain.then = vi.fn((resolve: any) => Promise.resolve({ data: [], error: null }).then(resolve))
  vi.clearAllMocks()
}

beforeEach(() => resetMock())

// ============ Sales Orders ============

describe('Sales Orders CRUD', () => {
  beforeEach(() => resetMock())

  it('getSalesOrders queries sales_orders', async () => {
    setMockData([{ id: '1', number: 'SO-001' }])
    const { getSalesOrders } = await import('@/lib/queries')
    const result = await getSalesOrders()
    expect((supabase as any).from).toHaveBeenCalledWith('sales_orders')
    expect(result).toHaveLength(1)
  })

  it('getSalesOrders filters by status', async () => {
    setMockData([])
    const { getSalesOrders } = await import('@/lib/queries')
    await getSalesOrders('pending')
    expect(mockChain.eq).toHaveBeenCalledWith('status', 'pending')
  })

  it('createSalesOrder inserts with tenant_id', async () => {
    setMockData({ id: '1', number: 'SO-001' })
    const { createSalesOrder } = await import('@/lib/queries')
    await createSalesOrder({ number: 'SO-001' } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ tenant_id: 'test-tenant-id' })
    )
  })

  it('deleteSalesOrder calls delete with id', async () => {
    setMockData(null, null)
    const { deleteSalesOrder } = await import('@/lib/queries')
    await deleteSalesOrder('so-1')
    expect(mockChain.delete).toHaveBeenCalled()
  })
})

// ============ Delivery Notes ============

describe('Delivery Notes CRUD', () => {
  beforeEach(() => resetMock())

  it('getDeliveryNotes queries delivery_notes', async () => {
    setMockData([{ id: '1', number: 'DN-001' }])
    const { getDeliveryNotes } = await import('@/lib/queries')
    const result = await getDeliveryNotes()
    expect((supabase as any).from).toHaveBeenCalledWith('delivery_notes')
    expect(result).toHaveLength(1)
  })

  it('createDeliveryNote inserts with tenant_id', async () => {
    setMockData({ id: '1', number: 'DN-001' })
    const { createDeliveryNote } = await import('@/lib/queries')
    await createDeliveryNote({ number: 'DN-001' } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ tenant_id: 'test-tenant-id' })
    )
  })

  it('deleteDeliveryNote calls delete', async () => {
    setMockData(null, null)
    const { deleteDeliveryNote } = await import('@/lib/queries')
    await deleteDeliveryNote('dn-1')
    expect(mockChain.delete).toHaveBeenCalled()
  })
})

// ============ Customer Payments ============

describe('Customer Payments', () => {
  beforeEach(() => resetMock())

  it('getCustomerPayments queries customer_payments', async () => {
    setMockData([{ id: '1', amount: 1000 }])
    const { getCustomerPayments } = await import('@/lib/queries')
    const result = await getCustomerPayments()
    expect((supabase as any).from).toHaveBeenCalledWith('customer_payments')
    expect(result).toHaveLength(1)
  })

  it('createCustomerPayment inserts with tenant_id', async () => {
    setMockData({ id: '1', amount: 1000 })
    const { createCustomerPayment } = await import('@/lib/queries')
    await createCustomerPayment({ amount: 1000 } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ tenant_id: 'test-tenant-id' })
    )
  })
})

// ============ Purchase Orders ============

describe('Purchase Orders CRUD', () => {
  beforeEach(() => resetMock())

  it('getPurchaseOrders queries purchase_orders', async () => {
    setMockData([{ id: '1', number: 'PO-001' }])
    const { getPurchaseOrders } = await import('@/lib/queries')
    const result = await getPurchaseOrders()
    expect((supabase as any).from).toHaveBeenCalledWith('purchase_orders')
    expect(result).toHaveLength(1)
  })

  it('createPurchaseOrder inserts with tenant_id', async () => {
    setMockData({ id: '1', number: 'PO-001' })
    const { createPurchaseOrder } = await import('@/lib/queries')
    await createPurchaseOrder({ number: 'PO-001' } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ tenant_id: 'test-tenant-id' })
    )
  })

  it('deletePurchaseOrder calls delete', async () => {
    setMockData(null, null)
    const { deletePurchaseOrder } = await import('@/lib/queries')
    await deletePurchaseOrder('po-1')
    expect(mockChain.delete).toHaveBeenCalled()
  })
})

// ============ Goods Receipts ============

describe('Goods Receipts CRUD', () => {
  beforeEach(() => resetMock())

  it('getGoodsReceipts queries goods_receipts', async () => {
    setMockData([{ id: '1', number: 'GR-001' }])
    const { getGoodsReceipts } = await import('@/lib/queries')
    const result = await getGoodsReceipts()
    expect((supabase as any).from).toHaveBeenCalledWith('goods_receipts')
    expect(result).toHaveLength(1)
  })

  it('createGoodsReceipt inserts with tenant_id', async () => {
    setMockData({ id: '1', number: 'GR-001' })
    const { createGoodsReceipt } = await import('@/lib/queries')
    await createGoodsReceipt({ number: 'GR-001' } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ tenant_id: 'test-tenant-id' })
    )
  })
})

// ============ Supplier Payments ============

describe('Supplier Payments', () => {
  beforeEach(() => resetMock())

  it('getSupplierPayments queries supplier_payments', async () => {
    setMockData([{ id: '1', amount: 500 }])
    const { getSupplierPayments } = await import('@/lib/queries')
    const result = await getSupplierPayments()
    expect((supabase as any).from).toHaveBeenCalledWith('supplier_payments')
    expect(result).toHaveLength(1)
  })

  it('createSupplierPayment inserts with tenant_id', async () => {
    setMockData({ id: '1', amount: 500 })
    const { createSupplierPayment } = await import('@/lib/queries')
    await createSupplierPayment({ amount: 500 } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ tenant_id: 'test-tenant-id' })
    )
  })
})

// ============ Warehouses ============

describe('Warehouses CRUD', () => {
  beforeEach(() => resetMock())

  it('getWarehouses queries warehouses ordered by name', async () => {
    setMockData([{ id: '1', name: 'Main WH' }])
    const { getWarehouses } = await import('@/lib/queries')
    const result = await getWarehouses()
    expect((supabase as any).from).toHaveBeenCalledWith('warehouses')
    expect(mockChain.order).toHaveBeenCalledWith('name')
    expect(result).toHaveLength(1)
  })

  it('createWarehouse inserts with tenant_id', async () => {
    setMockData({ id: '1', name: 'Main WH' })
    const { createWarehouse } = await import('@/lib/queries')
    await createWarehouse({ name: 'Main WH' } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ tenant_id: 'test-tenant-id' })
    )
  })

  it('deleteWarehouse calls delete', async () => {
    setMockData(null, null)
    const { deleteWarehouse } = await import('@/lib/queries')
    await deleteWarehouse('wh-1')
    expect(mockChain.delete).toHaveBeenCalled()
  })
})

// ============ Stock Quantities ============

describe('Stock Quantities', () => {
  beforeEach(() => resetMock())

  it('getStockQuantities queries stock_quantities', async () => {
    setMockData([{ id: '1', quantity: 100 }])
    const { getStockQuantities } = await import('@/lib/queries')
    const result = await getStockQuantities()
    expect((supabase as any).from).toHaveBeenCalledWith('stock_quantities')
    expect(result).toHaveLength(1)
  })

  it('getStockQuantities filters by warehouseId', async () => {
    setMockData([])
    const { getStockQuantities } = await import('@/lib/queries')
    await getStockQuantities('wh-1')
    expect(mockChain.eq).toHaveBeenCalledWith('warehouse_id', 'wh-1')
  })
})

// ============ Price Lists ============

describe('Price Lists CRUD', () => {
  beforeEach(() => resetMock())

  it('getPriceLists queries price_lists', async () => {
    setMockData([{ id: '1', name: 'Retail' }])
    const { getPriceLists } = await import('@/lib/queries')
    const result = await getPriceLists()
    expect((supabase as any).from).toHaveBeenCalledWith('price_lists')
    expect(result).toHaveLength(1)
  })

  it('createPriceList inserts with tenant_id', async () => {
    setMockData({ id: '1', name: 'Retail' })
    const { createPriceList } = await import('@/lib/queries')
    await createPriceList({ name: 'Retail' } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ tenant_id: 'test-tenant-id' })
    )
  })

  it('getPriceListLines queries by price_list_id', async () => {
    setMockData([{ id: '1', price_list_id: 'pl-1' }])
    const { getPriceListLines } = await import('@/lib/queries')
    const result = await getPriceListLines('pl-1')
    expect((supabase as any).from).toHaveBeenCalledWith('price_list_lines')
    expect(mockChain.eq).toHaveBeenCalledWith('price_list_id', 'pl-1')
    expect(result).toHaveLength(1)
  })
})

// ============ BOMs ============

describe('BOMs CRUD', () => {
  beforeEach(() => resetMock())

  it('getBOMs queries boms', async () => {
    setMockData([{ id: '1', code: 'BOM-001' }])
    const { getBOMs } = await import('@/lib/queries')
    const result = await getBOMs()
    expect((supabase as any).from).toHaveBeenCalledWith('boms')
    expect(result).toHaveLength(1)
  })

  it('createBOM inserts with tenant_id', async () => {
    setMockData({ id: '1', code: 'BOM-001' })
    const { createBOM } = await import('@/lib/queries')
    await createBOM({ code: 'BOM-001' } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ tenant_id: 'test-tenant-id' })
    )
  })

  it('getBOMLines queries by bom_id', async () => {
    setMockData([{ id: '1', bom_id: 'bom-1' }])
    const { getBOMLines } = await import('@/lib/queries')
    const result = await getBOMLines('bom-1')
    expect((supabase as any).from).toHaveBeenCalledWith('bom_lines')
    expect(mockChain.eq).toHaveBeenCalledWith('bom_id', 'bom-1')
    expect(result).toHaveLength(1)
  })
})

// ============ Manufacturing Orders ============

describe('Manufacturing Orders CRUD', () => {
  beforeEach(() => resetMock())

  it('getManufacturingOrders queries manufacturing_orders', async () => {
    setMockData([{ id: '1', number: 'MO-001' }])
    const { getManufacturingOrders } = await import('@/lib/queries')
    const result = await getManufacturingOrders()
    expect((supabase as any).from).toHaveBeenCalledWith('manufacturing_orders')
    expect(result).toHaveLength(1)
  })

  it('getManufacturingOrders filters by status', async () => {
    setMockData([])
    const { getManufacturingOrders } = await import('@/lib/queries')
    await getManufacturingOrders('in_progress')
    expect(mockChain.eq).toHaveBeenCalledWith('status', 'in_progress')
  })

  it('createManufacturingOrder inserts with tenant_id', async () => {
    setMockData({ id: '1', number: 'MO-001' })
    const { createManufacturingOrder } = await import('@/lib/queries')
    await createManufacturingOrder({ number: 'MO-001' } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ tenant_id: 'test-tenant-id' })
    )
  })

  it('deleteManufacturingOrder calls delete', async () => {
    setMockData(null, null)
    const { deleteManufacturingOrder } = await import('@/lib/queries')
    await deleteManufacturingOrder('mo-1')
    expect(mockChain.delete).toHaveBeenCalled()
  })
})

// ============ Pay Slips ============

describe('Pay Slips CRUD', () => {
  beforeEach(() => resetMock())

  it('getPaySlips queries pay_slips', async () => {
    setMockData([{ id: '1', number: 'BS-001' }])
    const { getPaySlips } = await import('@/lib/queries')
    const result = await getPaySlips()
    expect((supabase as any).from).toHaveBeenCalledWith('pay_slips')
    expect(result).toHaveLength(1)
  })

  it('getPaySlips filters by payRunId', async () => {
    setMockData([])
    const { getPaySlips } = await import('@/lib/queries')
    await getPaySlips('pr-1')
    expect(mockChain.eq).toHaveBeenCalledWith('pay_run_id', 'pr-1')
  })

  it('createPaySlip inserts with tenant_id', async () => {
    setMockData({ id: '1', number: 'BS-001' })
    const { createPaySlip } = await import('@/lib/queries')
    await createPaySlip({ number: 'BS-001' } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ tenant_id: 'test-tenant-id' })
    )
  })
})

// ============ Leave Requests ============

describe('Leave Requests CRUD', () => {
  beforeEach(() => resetMock())

  it('getLeaveRequests queries leave_requests', async () => {
    setMockData([{ id: '1', type: 'annual' }])
    const { getLeaveRequests } = await import('@/lib/queries')
    const result = await getLeaveRequests()
    expect((supabase as any).from).toHaveBeenCalledWith('leave_requests')
    expect(result).toHaveLength(1)
  })

  it('createLeaveRequest inserts with tenant_id', async () => {
    setMockData({ id: '1', type: 'annual' })
    const { createLeaveRequest } = await import('@/lib/queries')
    await createLeaveRequest({ type: 'annual', start_date: '2024-07-01' } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ tenant_id: 'test-tenant-id' })
    )
  })
})

// ============ Contracts ============

describe('Contracts', () => {
  beforeEach(() => resetMock())

  it('getContracts queries contracts', async () => {
    setMockData([{ id: '1', type: 'CDI' }])
    const { getContracts } = await import('@/lib/queries')
    const result = await getContracts()
    expect((supabase as any).from).toHaveBeenCalledWith('contracts')
    expect(result).toHaveLength(1)
  })
})

// ============ Collection Reminders ============

describe('Collection Reminders CRUD', () => {
  beforeEach(() => resetMock())

  it('getCollectionReminders queries collection_reminders', async () => {
    setMockData([{ id: '1', level: 1 }])
    const { getCollectionReminders } = await import('@/lib/queries')
    const result = await getCollectionReminders()
    expect((supabase as any).from).toHaveBeenCalledWith('collection_reminders')
    expect(result).toHaveLength(1)
  })

  it('getCollectionReminders filters by status', async () => {
    setMockData([])
    const { getCollectionReminders } = await import('@/lib/queries')
    await getCollectionReminders('sent')
    expect(mockChain.eq).toHaveBeenCalledWith('status', 'sent')
  })

  it('createCollectionReminder inserts with tenant_id', async () => {
    setMockData({ id: '1', level: 1 })
    const { createCollectionReminder } = await import('@/lib/queries')
    await createCollectionReminder({ level: 1 } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ tenant_id: 'test-tenant-id' })
    )
  })
})

// ============ Treasury Dashboard ============

describe('Treasury Dashboard', () => {
  beforeEach(() => resetMock())

  it('getTreasuryDashboard returns accounts and forecast', async () => {
    setMockData([{ id: '1', name: 'Main', balance: 10000 }])
    const { getTreasuryDashboard } = await import('@/lib/queries')
    const result = await getTreasuryDashboard()
    expect(result).toBeDefined()
    expect(result?.accounts).toBeDefined()
    expect(result?.forecastBuckets).toHaveLength(3)
    expect(result?.forecastBuckets[0].label).toBe('0-30j')
  })
})

// ============ Treasury Forecast ============

describe('Treasury Forecast', () => {
  beforeEach(() => resetMock())

  it('getTreasuryForecast returns timeline with events', async () => {
    setMockData([{ id: '1', balance: 5000, due_date: '2025-01-15', number: 'INV-001', total: 1000 }])
    const { getTreasuryForecast } = await import('@/lib/queries')
    const result = await getTreasuryForecast(90)
    expect(result).toBeDefined()
    expect(result?.currentBalance).toBe(5000)
    expect(result?.timeline).toBeDefined()
    expect(typeof result.totalIncoming).toBe('number')
  })
})

// ============ Collection Dashboard ============

describe('Collection Dashboard', () => {
  beforeEach(() => resetMock())

  it('getCollectionDashboard returns overdue invoices and totals', async () => {
    setMockData([{ id: '1', number: 'INV-001', total: 1000, due_date: '2024-01-01', status: 'overdue' }])
    const { getCollectionDashboard } = await import('@/lib/queries')
    const result = await getCollectionDashboard()
    expect(result).toBeDefined()
    expect(result?.overdueInvoices).toBeDefined()
    expect(typeof result.totalOverdue).toBe('number')
  })
})

// ============ Gescom Transfer ============

describe('Gescom Transfer', () => {
  beforeEach(() => resetMock())

  it('getGescomTransferData returns invoices and payments', async () => {
    setMockData([{ id: '1', number: 'INV-001', status: 'sent' }])
    const { getGescomTransferData } = await import('@/lib/queries')
    const result = await getGescomTransferData()
    expect(result).toBeDefined()
    expect(result?.invoices).toBeDefined()
    expect(typeof result.pendingCount).toBe('number')
  })

  it('getGescomTransferData filters by date range', async () => {
    setMockData([])
    const { getGescomTransferData } = await import('@/lib/queries')
    await getGescomTransferData('2024-01-01', '2024-12-31')
    expect(mockChain.gte).toHaveBeenCalledWith('date', '2024-01-01')
    expect(mockChain.lte).toHaveBeenCalledWith('date', '2024-12-31')
  })
})

// ============ Payroll Accounting Entries ============

describe('Payroll Accounting Entries', () => {
  beforeEach(() => resetMock())

  it('getPayrollAccountingEntries queries payroll_accounting_entries', async () => {
    setMockData([{ id: '1', number: 'PAE-001' }])
    const { getPayrollAccountingEntries } = await import('@/lib/queries')
    const result = await getPayrollAccountingEntries()
    expect((supabase as any).from).toHaveBeenCalledWith('payroll_accounting_entries')
    expect(result).toHaveLength(1)
  })

  it('createPayrollAccountingEntry inserts with tenant_id', async () => {
    setMockData({ id: '1', number: 'PAE-001' })
    const { createPayrollAccountingEntry } = await import('@/lib/queries')
    await createPayrollAccountingEntry({ number: 'PAE-001' } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ tenant_id: 'test-tenant-id' })
    )
  })
})

// ============ Tenant Management ============

describe('Tenant Management', () => {
  beforeEach(() => {
    resetMock()
    ;(supabase as any).auth.getSession = vi.fn(() => Promise.resolve({
      data: { session: { user: { id: 'user-1' } } }
    }))
  })

  it('getCurrentTenant returns tenant when session exists', async () => {
    setMockData([{ tenant_id: 'test-tenant-id', tenants: { id: 't1', name: 'Company A', enabled_modules: ['sales'] } }])
    const { getCurrentTenant } = await import('@/lib/queries')
    const result = await getCurrentTenant()
    expect(result).toBeDefined()
    expect(result?.name).toBe('Company A')
  })

  it('getCurrentTenant returns null when no session', async () => {
    ;(supabase as any).auth.getSession = vi.fn(() => Promise.resolve({
      data: { session: null }
    }))
    const { getCurrentTenant } = await import('@/lib/queries')
    const result = await getCurrentTenant()
    expect(result).toBeNull()
  })

  it('getTenantUsers queries tenant_users', async () => {
    setMockData([{ id: 'u1', email: 'user@test.com' }])
    const { getTenantUsers } = await import('@/lib/queries')
    const result = await getTenantUsers('test-tenant-id')
    expect((supabase as any).from).toHaveBeenCalledWith('tenant_users')
    expect(result).toHaveLength(1)
  })

  it('getTenantEnabledModules returns modules from tenant', async () => {
    setMockData([{ tenant_id: 'test-tenant-id', tenants: { id: 't1', enabled_modules: ['sales', 'accounting'] } }])
    const { getTenantEnabledModules } = await import('@/lib/queries')
    const result = await getTenantEnabledModules()
    expect(result).toBeDefined()
    expect(result).toContain('sales')
  })

  it('getTenantEnabledModules returns defaults when no tenant', async () => {
    ;(supabase as any).auth.getSession = vi.fn(() => Promise.resolve({
      data: { session: null }
    }))
    const { getTenantEnabledModules } = await import('@/lib/queries')
    const result = await getTenantEnabledModules()
    expect(result).toContain('accounting')
    expect(result).toContain('home')
  })
})

// ============ Product Variants ============

describe('Product Variants', () => {
  beforeEach(() => resetMock())

  it('getProductVariants queries product_variants', async () => {
    setMockData([{ id: '1', name: 'Red Widget' }])
    const { getProductVariants } = await import('@/lib/queries')
    const result = await getProductVariants()
    expect((supabase as any).from).toHaveBeenCalledWith('product_variants')
    expect(result).toHaveLength(1)
  })
})

// ============ Product Serial Numbers ============

describe('Product Serial Numbers', () => {
  beforeEach(() => resetMock())

  it('getProductSerialNumbers queries product_serial_numbers', async () => {
    setMockData([{ id: '1', serial_number: 'SN001' }])
    const { getProductSerialNumbers } = await import('@/lib/queries')
    const result = await getProductSerialNumbers()
    expect((supabase as any).from).toHaveBeenCalledWith('product_serial_numbers')
    expect(result).toHaveLength(1)
  })
})

// ============ Product Batches ============

describe('Product Batches', () => {
  beforeEach(() => resetMock())

  it('getProductBatches queries product_batches', async () => {
    setMockData([{ id: '1', batch_number: 'B001' }])
    const { getProductBatches } = await import('@/lib/queries')
    const result = await getProductBatches()
    expect((supabase as any).from).toHaveBeenCalledWith('product_batches')
    expect(result).toHaveLength(1)
  })
})

// ============ Warehouse Locations ============

describe('Warehouse Locations', () => {
  beforeEach(() => resetMock())

  it('getWarehouseLocations queries warehouse_locations', async () => {
    setMockData([{ id: '1', code: 'A-01' }])
    const { getWarehouseLocations } = await import('@/lib/queries')
    const result = await getWarehouseLocations()
    expect((supabase as any).from).toHaveBeenCalledWith('warehouse_locations')
    expect(result).toHaveLength(1)
  })
})

// ============ Quality Checks ============

describe('Quality Checks', () => {
  beforeEach(() => resetMock())

  it('getQualityChecks queries quality_checks', async () => {
    setMockData([{ id: '1', status: 'passed' }])
    const { getQualityChecks } = await import('@/lib/queries')
    const result = await getQualityChecks()
    expect((supabase as any).from).toHaveBeenCalledWith('quality_checks')
    expect(result).toHaveLength(1)
  })
})

// ============ Pick Lists ============

describe('Pick Lists', () => {
  beforeEach(() => resetMock())

  it('getPickLists queries pick_lists', async () => {
    setMockData([{ id: '1', status: 'pending' }])
    const { getPickLists } = await import('@/lib/queries')
    const result = await getPickLists()
    expect((supabase as any).from).toHaveBeenCalledWith('pick_lists')
    expect(result).toHaveLength(1)
  })
})

// ============ Product Documents ============

describe('Product Documents', () => {
  beforeEach(() => resetMock())

  it('getProductDocuments returns docs from multiple sources', async () => {
    setMockData([{ id: '1', number: 'INV-001', date: '2024-01-01' }])
    const { getProductDocuments } = await import('@/lib/queries')
    const result = await getProductDocuments('p1')
    expect(result).toBeDefined()
    expect(Array.isArray(result)).toBe(true)
  })
})

// ============ Product BOMs ============

describe('Product BOMs', () => {
  beforeEach(() => resetMock())

  it('getProductBOMs returns asFinished and asComponent arrays', async () => {
    setMockData([{ id: '1', product_id: 'p1' }])
    const { getProductBOMs } = await import('@/lib/queries')
    const result = await getProductBOMs('p1')
    expect(result).toBeDefined()
    expect(result?.asFinished).toBeDefined()
    expect(result?.asComponent).toBeDefined()
  })
})

// ============ Product Supplier Prices ============

describe('Product Supplier Prices', () => {
  beforeEach(() => resetMock())

  it('getProductSupplierPrices queries price_list_lines filtered by product_id', async () => {
    setMockData([{ id: '1', price: 10.5, price_lists: { type: 'purchase' } }])
    const { getProductSupplierPrices } = await import('@/lib/queries')
    const result = await getProductSupplierPrices('p1')
    expect((supabase as any).from).toHaveBeenCalledWith('price_list_lines')
    expect(mockChain.eq).toHaveBeenCalledWith('product_id', 'p1')
    expect(result).toHaveLength(1)
  })
})

// ============ Product Substitutes ============

describe('Product Substitutes', () => {
  beforeEach(() => resetMock())

  it('getProductSubstitutes queries product_substitutes', async () => {
    setMockData([{ id: '1' }])
    const { getProductSubstitutes } = await import('@/lib/queries')
    const result = await getProductSubstitutes('p1')
    expect((supabase as any).from).toHaveBeenCalledWith('product_substitutes')
    expect(result).toHaveLength(1)
  })
})

// ============ Product Equivalences ============

describe('Product Equivalences', () => {
  beforeEach(() => resetMock())

  it('getProductEquivalences queries product_equivalences', async () => {
    setMockData([{ id: '1' }])
    const { getProductEquivalences } = await import('@/lib/queries')
    const result = await getProductEquivalences('p1')
    expect((supabase as any).from).toHaveBeenCalledWith('product_equivalences')
    expect(result).toHaveLength(1)
  })
})

// ============ Recurring Invoice Templates ============

describe('Recurring Invoice Templates', () => {
  beforeEach(() => resetMock())

  it('getRecurringInvoiceTemplates queries recurring_invoice_templates', async () => {
    setMockData([{ id: '1', frequency: 'monthly' }])
    const { getRecurringInvoiceTemplates } = await import('@/lib/queries')
    const result = await getRecurringInvoiceTemplates()
    expect((supabase as any).from).toHaveBeenCalledWith('recurring_invoice_templates')
    expect(result).toHaveLength(1)
  })
})

// ============ Value Date Tracking ============

describe('Value Date Tracking', () => {
  beforeEach(() => resetMock())

  it('getValueDateTrackings queries value_date_tracking', async () => {
    setMockData([{ id: '1', value_date: '2024-01-15' }])
    const { getValueDateTrackings } = await import('@/lib/queries')
    const result = await getValueDateTrackings()
    expect((supabase as any).from).toHaveBeenCalledWith('value_date_tracking')
    expect(result).toHaveLength(1)
  })
})

// ============ Treasury Recurring ============

describe('Treasury Recurring', () => {
  beforeEach(() => resetMock())

  it('getTreasuryRecurring queries treasury_recurring', async () => {
    setMockData([{ id: '1', frequency: 'monthly' }])
    const { getTreasuryRecurring } = await import('@/lib/queries')
    const result = await getTreasuryRecurring()
    expect((supabase as any).from).toHaveBeenCalledWith('treasury_recurring')
    expect(result).toHaveLength(1)
  })
})

// ============ Consolidated Treasury ============

describe('Consolidated Treasury', () => {
  beforeEach(() => resetMock())

  it('getConsolidatedTreasury queries and returns consolidated data', async () => {
    setMockData([{ id: '1', balance: 10000 }])
    const { getConsolidatedTreasury } = await import('@/lib/queries')
    const result = await getConsolidatedTreasury()
    expect(result).toBeDefined()
  })
})

// ============ Payroll Templates ============

describe('Payroll Templates', () => {
  beforeEach(() => resetMock())

  it('getPayrollTemplates queries payroll_templates', async () => {
    setMockData([{ id: '1', name: 'Standard' }])
    const { getPayrollTemplates } = await import('@/lib/queries')
    const result = await getPayrollTemplates()
    expect((supabase as any).from).toHaveBeenCalledWith('payroll_templates')
    expect(result).toHaveLength(1)
  })
})

// ============ Pay Recalls ============

describe('Pay Recalls', () => {
  beforeEach(() => resetMock())

  it('getPayRecalls queries pay_recalls', async () => {
    setMockData([{ id: '1', amount: 200 }])
    const { getPayRecalls } = await import('@/lib/queries')
    const result = await getPayRecalls()
    expect((supabase as any).from).toHaveBeenCalledWith('pay_recalls')
    expect(result).toHaveLength(1)
  })
})

// ============ DPAE Records ============

describe('DPAE Records', () => {
  beforeEach(() => resetMock())

  it('getDpaeRecords queries dpae_records', async () => {
    setMockData([{ id: '1', status: 'submitted' }])
    const { getDpaeRecords } = await import('@/lib/queries')
    const result = await getDpaeRecords()
    expect((supabase as any).from).toHaveBeenCalledWith('dpae_records')
    expect(result).toHaveLength(1)
  })
})

// ============ Work Hardship ============

describe('Work Hardship', () => {
  beforeEach(() => resetMock())

  it('getWorkHardship queries work_hardship', async () => {
    setMockData([{ id: '1', level: 'high' }])
    const { getWorkHardship } = await import('@/lib/queries')
    const result = await getWorkHardship()
    expect((supabase as any).from).toHaveBeenCalledWith('work_hardship')
    expect(result).toHaveLength(1)
  })
})

// ============ Career History ============

describe('Career History', () => {
  beforeEach(() => resetMock())

  it('getCareerHistory queries career_history', async () => {
    setMockData([{ id: '1', position: 'Manager' }])
    const { getCareerHistory } = await import('@/lib/queries')
    const result = await getCareerHistory()
    expect((supabase as any).from).toHaveBeenCalledWith('career_history')
    expect(result).toHaveLength(1)
  })
})

// ============ CPF Accounts ============

describe('CPF Accounts', () => {
  beforeEach(() => resetMock())

  it('getCpfAccounts queries cpf_accounts', async () => {
    setMockData([{ id: '1', balance: 500 }])
    const { getCpfAccounts } = await import('@/lib/queries')
    const result = await getCpfAccounts()
    expect((supabase as any).from).toHaveBeenCalledWith('cpf_accounts')
    expect(result).toHaveLength(1)
  })
})

// ============ Payroll Archives ============

describe('Payroll Archives', () => {
  beforeEach(() => resetMock())

  it('getPayrollArchives queries payroll_archives', async () => {
    setMockData([{ id: '1', period: '2024-01' }])
    const { getPayrollArchives } = await import('@/lib/queries')
    const result = await getPayrollArchives()
    expect((supabase as any).from).toHaveBeenCalledWith('payroll_archives')
    expect(result).toHaveLength(1)
  })
})

// ============ Legal Watch ============

describe('Legal Watch', () => {
  beforeEach(() => resetMock())

  it('getLegalWatch queries legal_watch', async () => {
    setMockData([{ id: '1', topic: 'Tax' }])
    const { getLegalWatch } = await import('@/lib/queries')
    const result = await getLegalWatch()
    expect((supabase as any).from).toHaveBeenCalledWith('legal_watch')
    expect(result).toHaveLength(1)
  })
})

// ============ Employee Documents ============

describe('Employee Documents', () => {
  beforeEach(() => resetMock())

  it('getEmployeeDocuments queries employee_documents', async () => {
    setMockData([{ id: '1', name: 'contract.pdf' }])
    const { getEmployeeDocuments } = await import('@/lib/queries')
    const result = await getEmployeeDocuments('emp-1')
    expect((supabase as any).from).toHaveBeenCalledWith('employee_documents')
    expect(result).toHaveLength(1)
  })
})

// ============ Interviews ============

describe('Interviews', () => {
  beforeEach(() => resetMock())

  it('getInterviews queries interviews', async () => {
    setMockData([{ id: '1', type: 'annual' }])
    const { getInterviews } = await import('@/lib/queries')
    const result = await getInterviews()
    expect((supabase as any).from).toHaveBeenCalledWith('interviews')
    expect(result).toHaveLength(1)
  })
})

// ============ Asset Revaluations ============

describe('Asset Revaluations', () => {
  beforeEach(() => resetMock())

  it('getAssetRevaluations queries asset_revaluations', async () => {
    setMockData([{ id: '1', new_value: 5000 }])
    const { getAssetRevaluations } = await import('@/lib/queries')
    const result = await getAssetRevaluations()
    expect((supabase as any).from).toHaveBeenCalledWith('asset_revaluations')
    expect(result).toHaveLength(1)
  })
})

// ============ Asset Documents ============

describe('Asset Documents', () => {
  beforeEach(() => resetMock())

  it('getAssetDocuments queries asset_documents', async () => {
    setMockData([{ id: '1', name: 'invoice.pdf' }])
    const { getAssetDocuments } = await import('@/lib/queries')
    const result = await getAssetDocuments()
    expect((supabase as any).from).toHaveBeenCalledWith('asset_documents')
    expect(result).toHaveLength(1)
  })
})

// ============ Asset Splits ============

describe('Asset Splits', () => {
  beforeEach(() => resetMock())

  it('getAssetSplits queries asset_splits', async () => {
    setMockData([{ id: '1', ratio: 2 }])
    const { getAssetSplits } = await import('@/lib/queries')
    const result = await getAssetSplits()
    expect((supabase as any).from).toHaveBeenCalledWith('asset_splits')
    expect(result).toHaveLength(1)
  })
})

// ============ Stat Fields ============

describe('Stat Fields', () => {
  beforeEach(() => resetMock())

  it('getStatFields queries stat_fields', async () => {
    setMockData([{ id: '1', name: 'revenue' }])
    const { getStatFields } = await import('@/lib/queries')
    const result = await getStatFields()
    expect((supabase as any).from).toHaveBeenCalledWith('stat_fields')
    expect(result).toHaveLength(1)
  })
})

// ============ Reporting Plans ============

describe('Reporting Plans', () => {
  beforeEach(() => resetMock())

  it('getReportingPlans queries reporting_plans', async () => {
    setMockData([{ id: '1', name: 'Q1 Report' }])
    const { getReportingPlans } = await import('@/lib/queries')
    const result = await getReportingPlans()
    expect((supabase as any).from).toHaveBeenCalledWith('reporting_plans')
    expect(result).toHaveLength(1)
  })
})

// ============ Payment Templates Compta ============

describe('Payment Templates Compta', () => {
  beforeEach(() => resetMock())

  it('getPaymentTemplatesCompta queries payment_templates_compta', async () => {
    setMockData([{ id: '1', name: 'Virement' }])
    const { getPaymentTemplatesCompta } = await import('@/lib/queries')
    const result = await getPaymentTemplatesCompta()
    expect((supabase as any).from).toHaveBeenCalledWith('payment_templates_compta')
    expect(result).toHaveLength(1)
  })
})

// ============ Asset Depreciation Plans ============

describe('Asset Depreciation Plans', () => {
  beforeEach(() => resetMock())

  it('getAssetDepreciationPlans queries asset_depreciation_plans', async () => {
    setMockData([{ id: '1', year: 2024 }])
    const { getAssetDepreciationPlans } = await import('@/lib/queries')
    const result = await getAssetDepreciationPlans()
    expect((supabase as any).from).toHaveBeenCalledWith('asset_depreciation_plans')
    expect(result).toHaveLength(1)
  })
})

// ============ Asset Free Fields ============

describe('Asset Free Fields', () => {
  beforeEach(() => resetMock())

  it('getAssetFreeFields queries asset_free_fields', async () => {
    setMockData([{ id: '1', label: 'Location' }])
    const { getAssetFreeFields } = await import('@/lib/queries')
    const result = await getAssetFreeFields()
    expect((supabase as any).from).toHaveBeenCalledWith('asset_free_fields')
    expect(result).toHaveLength(1)
  })
})

// ============ Asset Batch Disposals ============

describe('Asset Batch Disposals', () => {
  beforeEach(() => resetMock())

  it('getAssetBatchDisposals queries asset_batch_disposals', async () => {
    setMockData([{ id: '1', disposal_date: '2024-06-01' }])
    const { getAssetBatchDisposals } = await import('@/lib/queries')
    const result = await getAssetBatchDisposals()
    expect((supabase as any).from).toHaveBeenCalledWith('asset_batch_disposals')
    expect(result).toHaveLength(1)
  })
})
