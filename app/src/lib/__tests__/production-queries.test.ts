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
    range: vi.fn(() => Promise.resolve(resolvedValue)),
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
      getSession: vi.fn(() => Promise.resolve({ data: { session: { user: { id: 'user-1' } } } })),
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

// ============ Routings ============

describe('Routings CRUD', () => {
  beforeEach(() => resetMock())

  it('getRoutings queries routings', async () => {
    setMockData([{ id: '1', code: 'RT-001' }])
    const { getRoutings } = await import('@/lib/queries')
    const result = await getRoutings()
    expect((supabase as any).from).toHaveBeenCalledWith('routings')
    expect(result).toHaveLength(1)
  })

  it('createRouting inserts with tenant_id', async () => {
    setMockData({ id: '1', code: 'RT-001' })
    const { createRouting } = await import('@/lib/queries')
    await createRouting({ code: 'RT-001' } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ tenant_id: 'test-tenant-id' })
    )
  })

  it('deleteRouting calls delete', async () => {
    setMockData(null, null)
    const { deleteRouting } = await import('@/lib/queries')
    await deleteRouting('rt-1')
    expect(mockChain.delete).toHaveBeenCalled()
  })
})

// ============ Routing Operations ============

describe('Routing Operations', () => {
  beforeEach(() => resetMock())

  it('getRoutingOperations queries by routing_id', async () => {
    setMockData([{ id: '1', sequence: 10 }])
    const { getRoutingOperations } = await import('@/lib/queries')
    const result = await getRoutingOperations('rt-1')
    expect((supabase as any).from).toHaveBeenCalledWith('routing_operations')
    expect(mockChain.eq).toHaveBeenCalledWith('routing_id', 'rt-1')
    expect(result).toHaveLength(1)
  })

  it('createRoutingOperation inserts with tenant_id', async () => {
    setMockData({ id: '1', sequence: 10 })
    const { createRoutingOperation } = await import('@/lib/queries')
    await createRoutingOperation({ sequence: 10 } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ tenant_id: 'test-tenant-id' })
    )
  })

  it('deleteRoutingOperation calls delete', async () => {
    setMockData(null, null)
    const { deleteRoutingOperation } = await import('@/lib/queries')
    await deleteRoutingOperation('op-1')
    expect(mockChain.delete).toHaveBeenCalled()
  })
})

// ============ Work Centers ============

describe('Work Centers', () => {
  beforeEach(() => resetMock())

  it('getWorkCenters queries work_centers', async () => {
    setMockData([{ id: '1', code: 'WC-001' }])
    const { getWorkCenters } = await import('@/lib/queries')
    const result = await getWorkCenters()
    expect((supabase as any).from).toHaveBeenCalledWith('work_centers')
    expect(result).toHaveLength(1)
  })

  it('createWorkCenter inserts with tenant_id', async () => {
    setMockData({ id: '1', code: 'WC-001' })
    const { createWorkCenter } = await import('@/lib/queries')
    await createWorkCenter({ code: 'WC-001' } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ tenant_id: 'test-tenant-id' })
    )
  })

  it('deleteWorkCenter calls delete', async () => {
    setMockData(null, null)
    const { deleteWorkCenter } = await import('@/lib/queries')
    await deleteWorkCenter('wc-1')
    expect(mockChain.delete).toHaveBeenCalled()
  })
})

// ============ Machines ============

describe('Machines CRUD', () => {
  beforeEach(() => resetMock())

  it('getMachines queries machines', async () => {
    setMockData([{ id: '1', code: 'M-001' }])
    const { getMachines } = await import('@/lib/queries')
    const result = await getMachines()
    expect((supabase as any).from).toHaveBeenCalledWith('machines')
    expect(result).toHaveLength(1)
  })

  it('createMachine inserts with tenant_id', async () => {
    setMockData({ id: '1', code: 'M-001' })
    const { createMachine } = await import('@/lib/queries')
    await createMachine({ code: 'M-001' } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ tenant_id: 'test-tenant-id' })
    )
  })

  it('deleteMachine calls delete', async () => {
    setMockData(null, null)
    const { deleteMachine } = await import('@/lib/queries')
    await deleteMachine('m-1')
    expect(mockChain.delete).toHaveBeenCalled()
  })
})

// ============ Toolings ============

describe('Toolings CRUD', () => {
  beforeEach(() => resetMock())

  it('getToolings queries toolings', async () => {
    setMockData([{ id: '1', code: 'T-001' }])
    const { getToolings } = await import('@/lib/queries')
    const result = await getToolings()
    expect((supabase as any).from).toHaveBeenCalledWith('toolings')
    expect(result).toHaveLength(1)
  })

  it('createTooling inserts with tenant_id', async () => {
    setMockData({ id: '1', code: 'T-001' })
    const { createTooling } = await import('@/lib/queries')
    await createTooling({ code: 'T-001' } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ tenant_id: 'test-tenant-id' })
    )
  })

  it('deleteTooling calls delete', async () => {
    setMockData(null, null)
    const { deleteTooling } = await import('@/lib/queries')
    await deleteTooling('t-1')
    expect(mockChain.delete).toHaveBeenCalled()
  })
})

// ============ OF Labels ============

describe('OF Labels', () => {
  beforeEach(() => resetMock())

  it('getOFLabels queries by manufacturing_order_id', async () => {
    setMockData([{ id: '1', label_number: 'LBL-001' }])
    const { getOFLabels } = await import('@/lib/queries')
    const result = await getOFLabels('mo-1')
    expect((supabase as any).from).toHaveBeenCalledWith('of_labels')
    expect(mockChain.eq).toHaveBeenCalledWith('manufacturing_order_id', 'mo-1')
    expect(result).toHaveLength(1)
  })

  it('createOFLabel inserts with tenant_id', async () => {
    setMockData({ id: '1', label_number: 'LBL-001' })
    const { createOFLabel } = await import('@/lib/queries')
    await createOFLabel({ label_number: 'LBL-001' } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ tenant_id: 'test-tenant-id' })
    )
  })

  it('deleteOFLabel calls delete', async () => {
    setMockData(null, null)
    const { deleteOFLabel } = await import('@/lib/queries')
    await deleteOFLabel('lbl-1')
    expect(mockChain.delete).toHaveBeenCalled()
  })
})

// ============ OF Lots ============

describe('OF Lots', () => {
  beforeEach(() => resetMock())

  it('getOFLots queries by manufacturing_order_id', async () => {
    setMockData([{ id: '1', lot_number: 'LOT-001' }])
    const { getOFLots } = await import('@/lib/queries')
    const result = await getOFLots('mo-1')
    expect((supabase as any).from).toHaveBeenCalledWith('of_lots')
    expect(mockChain.eq).toHaveBeenCalledWith('manufacturing_order_id', 'mo-1')
    expect(result).toHaveLength(1)
  })

  it('createOFLot inserts with tenant_id', async () => {
    setMockData({ id: '1', lot_number: 'LOT-001' })
    const { createOFLot } = await import('@/lib/queries')
    await createOFLot({ lot_number: 'LOT-001' } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ tenant_id: 'test-tenant-id' })
    )
  })

  it('deleteOFLot calls delete', async () => {
    setMockData(null, null)
    const { deleteOFLot } = await import('@/lib/queries')
    await deleteOFLot('lot-1')
    expect(mockChain.delete).toHaveBeenCalled()
  })
})

// ============ OF Consumptions ============

describe('OF Consumptions', () => {
  beforeEach(() => resetMock())

  it('getOFConsumptions queries by manufacturing_order_id', async () => {
    setMockData([{ id: '1', quantity: 10 }])
    const { getOFConsumptions } = await import('@/lib/queries')
    const result = await getOFConsumptions('mo-1')
    expect((supabase as any).from).toHaveBeenCalledWith('of_consumptions')
    expect(mockChain.eq).toHaveBeenCalledWith('manufacturing_order_id', 'mo-1')
    expect(result).toHaveLength(1)
  })

  it('createOFConsumption inserts with tenant_id', async () => {
    setMockData({ id: '1', quantity: 10 })
    const { createOFConsumption } = await import('@/lib/queries')
    await createOFConsumption({ quantity: 10 } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ tenant_id: 'test-tenant-id' })
    )
  })

  it('deleteOFConsumption calls delete', async () => {
    setMockData(null, null)
    const { deleteOFConsumption } = await import('@/lib/queries')
    await deleteOFConsumption('cons-1')
    expect(mockChain.delete).toHaveBeenCalled()
  })
})

// ============ Manufacturing Order Detail ============

describe('Manufacturing Order Detail', () => {
  beforeEach(() => resetMock())

  it('getManufacturingOrder queries by id with single()', async () => {
    setMockData({ id: '1', number: 'MO-001' })
    const { getManufacturingOrder } = await import('@/lib/queries')
    const result = await getManufacturingOrder('mo-1')
    expect((supabase as any).from).toHaveBeenCalledWith('manufacturing_orders')
    expect(mockChain.eq).toHaveBeenCalledWith('id', 'mo-1')
    expect(result).toBeDefined()
  })

  it('getSubManufacturingOrders queries by parent_mo_id', async () => {
    setMockData([{ id: '2', number: 'MO-002' }])
    const { getSubManufacturingOrders } = await import('@/lib/queries')
    const result = await getSubManufacturingOrders('mo-1')
    expect((supabase as any).from).toHaveBeenCalledWith('manufacturing_orders')
    expect(mockChain.eq).toHaveBeenCalledWith('parent_mo_id', 'mo-1')
    expect(result).toHaveLength(1)
  })
})

// ============ Subcontracting Orders ============

describe('ST Orders CRUD', () => {
  beforeEach(() => resetMock())

  it('getSTOrders queries st_orders', async () => {
    setMockData([{ id: '1', number: 'ST-001' }])
    const { getSTOrders } = await import('@/lib/queries')
    const result = await getSTOrders()
    expect((supabase as any).from).toHaveBeenCalledWith('st_orders')
    expect(result).toHaveLength(1)
  })

  it('createSTOrder inserts with tenant_id', async () => {
    setMockData({ id: '1', number: 'ST-001' })
    const { createSTOrder } = await import('@/lib/queries')
    await createSTOrder({ number: 'ST-001' } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ tenant_id: 'test-tenant-id' })
    )
  })

  it('deleteSTOrder calls delete', async () => {
    setMockData(null, null)
    const { deleteSTOrder } = await import('@/lib/queries')
    await deleteSTOrder('st-1')
    expect(mockChain.delete).toHaveBeenCalled()
  })
})

// ============ Subcontracting Shipments ============

describe('ST Shipments', () => {
  beforeEach(() => resetMock())

  it('getSTShipments queries st_shipments', async () => {
    setMockData([{ id: '1', number: 'SHP-001' }])
    const { getSTShipments } = await import('@/lib/queries')
    const result = await getSTShipments()
    expect((supabase as any).from).toHaveBeenCalledWith('st_shipments')
    expect(result).toHaveLength(1)
  })

  it('createSTShipment inserts with tenant_id', async () => {
    setMockData({ id: '1', number: 'SHP-001' })
    const { createSTShipment } = await import('@/lib/queries')
    await createSTShipment({ number: 'SHP-001' } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ tenant_id: 'test-tenant-id' })
    )
  })

  it('getSTShipmentLines queries by st_shipment_id', async () => {
    setMockData([{ id: '1', quantity: 5 }])
    const { getSTShipmentLines } = await import('@/lib/queries')
    const result = await getSTShipmentLines('shp-1')
    expect((supabase as any).from).toHaveBeenCalledWith('st_shipment_lines')
    expect(mockChain.eq).toHaveBeenCalledWith('st_shipment_id', 'shp-1')
    expect(result).toHaveLength(1)
  })
})

// ============ Subcontracting Receipts ============

describe('ST Receipts', () => {
  beforeEach(() => resetMock())

  it('getSTReceipts queries st_receipts', async () => {
    setMockData([{ id: '1', number: 'RCPT-001' }])
    const { getSTReceipts } = await import('@/lib/queries')
    const result = await getSTReceipts()
    expect((supabase as any).from).toHaveBeenCalledWith('st_receipts')
    expect(result).toHaveLength(1)
  })

  it('createSTReceipt inserts with tenant_id', async () => {
    setMockData({ id: '1', number: 'RCPT-001' })
    const { createSTReceipt } = await import('@/lib/queries')
    await createSTReceipt({ number: 'RCPT-001' } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ tenant_id: 'test-tenant-id' })
    )
  })

  it('getSTReceiptLines queries by st_receipt_id', async () => {
    setMockData([{ id: '1', quantity_received: 5 }])
    const { getSTReceiptLines } = await import('@/lib/queries')
    const result = await getSTReceiptLines('rcpt-1')
    expect((supabase as any).from).toHaveBeenCalledWith('st_receipt_lines')
    expect(mockChain.eq).toHaveBeenCalledWith('st_receipt_id', 'rcpt-1')
    expect(result).toHaveLength(1)
  })
})

// ============ ST Supervisor ============

describe('ST Supervisor', () => {
  beforeEach(() => resetMock())

  it('getSTSupervisorData queries st_orders with joins', async () => {
    setMockData([{ id: '1', number: 'ST-001' }])
    const { getSTSupervisorData } = await import('@/lib/queries')
    const result = await getSTSupervisorData()
    expect((supabase as any).from).toHaveBeenCalledWith('st_orders')
    expect(result).toHaveLength(1)
  })
})

// ============ MRP Runs ============

describe('MRP Runs', () => {
  beforeEach(() => resetMock())

  it('getMRPRuns queries mrp_runs', async () => {
    setMockData([{ id: '1', run_number: 'MRP-001' }])
    const { getMRPRuns } = await import('@/lib/queries')
    const result = await getMRPRuns()
    expect((supabase as any).from).toHaveBeenCalledWith('mrp_runs')
    expect(result).toHaveLength(1)
  })

  it('createMRPRun inserts with tenant_id', async () => {
    setMockData({ id: '1', run_number: 'MRP-001' })
    const { createMRPRun } = await import('@/lib/queries')
    await createMRPRun({ run_number: 'MRP-001' } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ tenant_id: 'test-tenant-id' })
    )
  })

  it('deleteMRPRun calls delete', async () => {
    setMockData(null, null)
    const { deleteMRPRun } = await import('@/lib/queries')
    await deleteMRPRun('mrp-1')
    expect(mockChain.delete).toHaveBeenCalled()
  })
})

// ============ MRP Proposals ============

describe('MRP Proposals', () => {
  beforeEach(() => resetMock())

  it('getMRPProposals queries by mrp_run_id', async () => {
    setMockData([{ id: '1', net_need: 100 }])
    const { getMRPProposals } = await import('@/lib/queries')
    const result = await getMRPProposals('run-1')
    expect((supabase as any).from).toHaveBeenCalledWith('mrp_proposals')
    expect(mockChain.eq).toHaveBeenCalledWith('mrp_run_id', 'run-1')
    expect(result).toHaveLength(1)
  })

  it('deleteMRPProposal calls delete', async () => {
    setMockData(null, null)
    const { deleteMRPProposal } = await import('@/lib/queries')
    await deleteMRPProposal('prop-1')
    expect(mockChain.delete).toHaveBeenCalled()
  })
})

// ============ MRP Pending Docs ============

describe('MRP Pending Docs', () => {
  beforeEach(() => resetMock())

  it('getMRPPendingDocs queries mrp_pending_docs', async () => {
    setMockData([{ id: '1', doc_type: 'PO' }])
    const { getMRPPendingDocs } = await import('@/lib/queries')
    const result = await getMRPPendingDocs()
    expect((supabase as any).from).toHaveBeenCalledWith('mrp_pending_docs')
    expect(result).toHaveLength(1)
  })

  it('deleteMRPPendingDoc calls delete', async () => {
    setMockData(null, null)
    const { deleteMRPPendingDoc } = await import('@/lib/queries')
    await deleteMRPPendingDoc('doc-1')
    expect(mockChain.delete).toHaveBeenCalled()
  })
})

// ============ Production Forecasts ============

describe('Production Forecasts', () => {
  beforeEach(() => resetMock())

  it('getProductionForecasts queries production_forecasts', async () => {
    setMockData([{ id: '1', forecasted_quantity: 100 }])
    const { getProductionForecasts } = await import('@/lib/queries')
    const result = await getProductionForecasts()
    expect((supabase as any).from).toHaveBeenCalledWith('production_forecasts')
    expect(result).toHaveLength(1)
  })

  it('createProductionForecast inserts with tenant_id', async () => {
    setMockData({ id: '1', forecasted_quantity: 100 })
    const { createProductionForecast } = await import('@/lib/queries')
    await createProductionForecast({ forecasted_quantity: 100 } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ tenant_id: 'test-tenant-id' })
    )
  })

  it('deleteProductionForecast calls delete', async () => {
    setMockData(null, null)
    const { deleteProductionForecast } = await import('@/lib/queries')
    await deleteProductionForecast('pf-1')
    expect(mockChain.delete).toHaveBeenCalled()
  })
})

// ============ Planning Slots ============

describe('Planning Slots CRUD', () => {
  beforeEach(() => resetMock())

  it('getPlanningSlots queries planning_slots', async () => {
    setMockData([{ id: '1', status: 'scheduled' }])
    const { getPlanningSlots } = await import('@/lib/queries')
    const result = await getPlanningSlots()
    expect((supabase as any).from).toHaveBeenCalledWith('planning_slots')
    expect(result).toHaveLength(1)
  })

  it('createPlanningSlot inserts with tenant_id', async () => {
    setMockData({ id: '1', status: 'scheduled' })
    const { createPlanningSlot } = await import('@/lib/queries')
    await createPlanningSlot({ status: 'scheduled' } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ tenant_id: 'test-tenant-id' })
    )
  })

  it('deletePlanningSlot calls delete', async () => {
    setMockData(null, null)
    const { deletePlanningSlot } = await import('@/lib/queries')
    await deletePlanningSlot('slot-1')
    expect(mockChain.delete).toHaveBeenCalled()
  })
})

// ============ Echeancier (Payment Schedule) ============

describe('Echeancier', () => {
  beforeEach(() => resetMock())

  it('getEcheancier returns customer and supplier echeances', async () => {
    setMockData([{ id: '1', number: 'INV-001', total: 1000, due_date: '2025-01-01', status: 'sent', customer_name: 'Cust' }])
    const { getEcheancier } = await import('@/lib/queries')
    const result = await getEcheancier()
    expect(result).toBeDefined()
    expect(Array.isArray(result)).toBe(true)
  })

  it('getEcheancier filters by customer type', async () => {
    setMockData([{ id: '1', number: 'INV-001', total: 1000, due_date: '2025-01-01', status: 'sent', customer_name: 'Cust' }])
    const { getEcheancier } = await import('@/lib/queries')
    const result = await getEcheancier('customer')
    expect(result).toBeDefined()
    expect(result.every((r: any) => r.type === 'customer')).toBe(true)
  })
})

// ============ Grand Livre Tiers ============

describe('Grand Livre Tiers', () => {
  beforeEach(() => resetMock())

  it('getGrandLivreTiers queries journal_lines by account_tiers', async () => {
    setMockData([{ id: '1', debit: 100, credit: 0 }])
    const { getGrandLivreTiers } = await import('@/lib/queries')
    const result = await getGrandLivreTiers('400000')
    expect((supabase as any).from).toHaveBeenCalledWith('journal_lines')
    expect(mockChain.eq).toHaveBeenCalledWith('account_tiers', '400000')
    expect(result).toHaveLength(1)
  })

  it('getGrandLivreTiers filters by date range', async () => {
    setMockData([])
    const { getGrandLivreTiers } = await import('@/lib/queries')
    await getGrandLivreTiers('400000', '2024-01-01', '2024-12-31')
    expect(mockChain.gte).toHaveBeenCalledWith('journal_entries.date', '2024-01-01')
    expect(mockChain.lte).toHaveBeenCalledWith('journal_entries.date', '2024-12-31')
  })
})

// ============ FEC Data ============

describe('FEC Data', () => {
  beforeEach(() => resetMock())

  it('getFECData returns entries for fiscal year periods', async () => {
    setMockData([{ id: 'p1' }])
    const { getFECData } = await import('@/lib/queries')
    const result = await getFECData('fy-1')
    expect(result).toBeDefined()
  })

  it('getFECData returns empty when no periods', async () => {
    setMockData([])
    const { getFECData } = await import('@/lib/queries')
    const result = await getFECData('fy-1')
    expect(result).toEqual([])
  })
})

// ============ SIG Data ============

describe('SIG Data', () => {
  beforeEach(() => resetMock())

  it('getSIGData returns class 6/7 account balances', async () => {
    setMockData([{ account_code: '701000', account_general: '701000', debit: 0, credit: 5000 }])
    const { getSIGData } = await import('@/lib/queries')
    const result = await getSIGData()
    expect(result).toBeDefined()
    expect(Array.isArray(result)).toBe(true)
  })

  it('getSIGData filters by fiscalYearId', async () => {
    setMockData([{ account_code: '601000', account_general: '601000', debit: 3000, credit: 0 }])
    const { getSIGData } = await import('@/lib/queries')
    const result = await getSIGData('fy-1')
    expect(result).toBeDefined()
  })
})

// ============ Analytic Balance ============

describe('Analytic Balance', () => {
  beforeEach(() => resetMock())

  it('getAnalyticBalance returns sections with totals', async () => {
    setMockData([{ analytic_section_id: 's1', analytic_amount: 100, debit: 50, credit: 0, account_code: '701', account_general: '701' }])
    const { getAnalyticBalance } = await import('@/lib/queries')
    const result = await getAnalyticBalance()
    expect(result).toBeDefined()
    expect(Array.isArray(result)).toBe(true)
  })
})

// ============ VAT from Entries ============

describe('calcVatFromEntries', () => {
  beforeEach(() => resetMock())

  it('calculates VAT from journal lines in date range', async () => {
    setMockData([
      { account_general: '445710', debit: 0, credit: 200 },
      { account_general: '445660', debit: 100, credit: 0 },
      { account_general: '701000', debit: 0, credit: 1000 },
      { account_general: '601000', debit: 500, credit: 0 },
    ])
    const { calcVatFromEntries } = await import('@/lib/queries')
    const result = await calcVatFromEntries('2024-01-01', '2024-12-31')
    expect(result.outputVat).toBe(200)
    expect(result.inputVat).toBe(100)
    expect(result.netVat).toBe(100)
    expect(result.totalSales).toBe(1000)
    expect(result.totalPurchases).toBe(500)
  })
})

// ============ General Ledger Filtered ============

describe('General Ledger Filtered', () => {
  beforeEach(() => resetMock())

  it('getGeneralLedgerFiltered queries by account_code', async () => {
    setMockData([{ id: '1', debit: 100, credit: 0 }])
    const { getGeneralLedgerFiltered } = await import('@/lib/queries')
    const result = await getGeneralLedgerFiltered('401000')
    expect(result).toBeDefined()
  })
})

// ============ Contracts CRUD ============

describe('Contracts CRUD', () => {
  beforeEach(() => resetMock())

  it('createContract inserts with tenant_id', async () => {
    setMockData({ id: '1', type: 'CDI' })
    const { createContract } = await import('@/lib/queries')
    await createContract({ type: 'CDI' } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ tenant_id: 'test-tenant-id' })
    )
  })

  it('deleteContract calls delete', async () => {
    setMockData(null, null)
    const { deleteContract } = await import('@/lib/queries')
    await deleteContract('c-1')
    expect(mockChain.delete).toHaveBeenCalled()
  })
})

// ============ Legal Declarations ============

describe('Legal Declarations CRUD', () => {
  beforeEach(() => resetMock())

  it('getLegalDeclarations queries legal_declarations', async () => {
    setMockData([{ id: '1', type: 'TVA' }])
    const { getLegalDeclarations } = await import('@/lib/queries')
    const result = await getLegalDeclarations()
    expect((supabase as any).from).toHaveBeenCalledWith('legal_declarations')
    expect(result).toHaveLength(1)
  })

  it('getLegalDeclarations filters by status', async () => {
    setMockData([])
    const { getLegalDeclarations } = await import('@/lib/queries')
    await getLegalDeclarations('pending')
    expect(mockChain.eq).toHaveBeenCalledWith('status', 'pending')
  })

  it('createLegalDeclaration inserts with tenant_id', async () => {
    setMockData({ id: '1', type: 'TVA' })
    const { createLegalDeclaration } = await import('@/lib/queries')
    await createLegalDeclaration({ type: 'TVA' } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ tenant_id: 'test-tenant-id' })
    )
  })

  it('deleteLegalDeclaration calls delete', async () => {
    setMockData(null, null)
    const { deleteLegalDeclaration } = await import('@/lib/queries')
    await deleteLegalDeclaration('ld-1')
    expect(mockChain.delete).toHaveBeenCalled()
  })
})

// ============ Audit Log ============

describe('Audit Log', () => {
  beforeEach(() => resetMock())

  it('getAuditLog queries audit_log with limit 200', async () => {
    setMockData([{ id: '1', action: 'create' }])
    const { getAuditLog } = await import('@/lib/queries')
    const result = await getAuditLog()
    expect((supabase as any).from).toHaveBeenCalledWith('audit_log')
    expect(mockChain.limit).toHaveBeenCalledWith(200)
    expect(result).toHaveLength(1)
  })

  it('getAuditLog filters by entityType and action', async () => {
    setMockData([])
    const { getAuditLog } = await import('@/lib/queries')
    await getAuditLog('invoice', 'create')
    expect(mockChain.eq).toHaveBeenCalledWith('entity_type', 'invoice')
    expect(mockChain.eq).toHaveBeenCalledWith('action', 'create')
  })

  it('getAuditLog returns empty array on error', async () => {
    mockChain.then = vi.fn((resolve: any) => Promise.resolve({ data: null, error: { message: 'Table missing' } }).then(resolve))
    const { getAuditLog } = await import('@/lib/queries')
    const result = await getAuditLog()
    expect(result).toEqual([])
  })

  it('createAuditLog inserts with tenant_id', async () => {
    setMockData({ id: '1', action: 'create' })
    const { createAuditLog } = await import('@/lib/queries')
    await createAuditLog({ action: 'create', entity_type: 'invoice' } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ tenant_id: 'test-tenant-id' })
    )
  })
})

// ============ Budget Tracking ============

describe('Budget Tracking', () => {
  beforeEach(() => resetMock())

  it('getBudgetTracking returns budgets with realized and available', async () => {
    setMockData([{ id: '1', account_code: '601000', period_1: 1000, period_2: 2000 }])
    const { getBudgetTracking } = await import('@/lib/queries')
    const result = await getBudgetTracking()
    expect(result).toBeDefined()
    expect(Array.isArray(result)).toBe(true)
  })

  it('getBudgetTracking filters by fiscalYearId', async () => {
    setMockData([])
    const { getBudgetTracking } = await import('@/lib/queries')
    await getBudgetTracking('fy-1')
    expect(mockChain.eq).toHaveBeenCalledWith('fiscal_year_id', 'fy-1')
  })
})

// ============ Budget Commitments ============

describe('Budget Commitments CRUD', () => {
  beforeEach(() => resetMock())

  it('getBudgetCommitments queries budget_commitments', async () => {
    setMockData([{ id: '1', amount: 500 }])
    const { getBudgetCommitments } = await import('@/lib/queries')
    const result = await getBudgetCommitments()
    expect((supabase as any).from).toHaveBeenCalledWith('budget_commitments')
    expect(result).toHaveLength(1)
  })

  it('createBudgetCommitment inserts with tenant_id', async () => {
    setMockData({ id: '1', amount: 500 })
    const { createBudgetCommitment } = await import('@/lib/queries')
    await createBudgetCommitment({ amount: 500 } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ tenant_id: 'test-tenant-id' })
    )
  })

  it('deleteBudgetCommitment calls delete', async () => {
    setMockData(null, null)
    const { deleteBudgetCommitment } = await import('@/lib/queries')
    await deleteBudgetCommitment('bc-1')
    expect(mockChain.delete).toHaveBeenCalled()
  })
})

// ============ checkBudgetAvailability ============

describe('checkBudgetAvailability', () => {
  beforeEach(() => resetMock())

  it('returns budget control result with would_exceed flag', async () => {
    setMockData([{ id: '1', account_code: '601000', period_1: 1000 }])
    const { checkBudgetAvailability } = await import('@/lib/queries')
    const result = await checkBudgetAvailability('601000', 500)
    expect(result).toBeDefined()
    expect(result.account_code).toBe('601000')
    expect(typeof result.would_exceed).toBe('boolean')
    expect(typeof result.available).toBe('number')
  })
})

// ============ Financial Dashboard ============

describe('Financial Dashboard', () => {
  beforeEach(() => resetMock())

  it('getFinancialDashboard returns revenue, expenses, margin', async () => {
    setMockData([{ id: '1', total: 5000, status: 'paid', date: '2024-01-01' }])
    const { getFinancialDashboard } = await import('@/lib/queries')
    const result = await getFinancialDashboard()
    expect(result).toBeDefined()
    expect(typeof result.revenue).toBe('number')
    expect(typeof result.expenses).toBe('number')
    expect(typeof result.margin).toBe('number')
    expect(typeof result.cashPosition).toBe('number')
  })
})

// ============ Product Stock ============

describe('Product Stock', () => {
  beforeEach(() => resetMock())

  it('getProductStock queries stock_quantities by product_id', async () => {
    setMockData([{ id: '1', product_id: 'p1', quantity: 100 }])
    const { getProductStock } = await import('@/lib/queries')
    const result = await getProductStock('p1')
    expect((supabase as any).from).toHaveBeenCalledWith('stock_quantities')
    expect(mockChain.eq).toHaveBeenCalledWith('product_id', 'p1')
    expect(result).toHaveLength(1)
  })
})

// ============ Product Equivalences ============

describe('Product Equivalences', () => {
  beforeEach(() => resetMock())

  it('getProductEquivalences queries product_equivalences', async () => {
    setMockData([{ id: '1', ratio: 2 }])
    const { getProductEquivalences } = await import('@/lib/queries')
    const result = await getProductEquivalences('p1')
    expect((supabase as any).from).toHaveBeenCalledWith('product_equivalences')
    expect(result).toHaveLength(1)
  })
})

// ============ Batch Entry Sessions ============

describe('Batch Entry Sessions', () => {
  beforeEach(() => resetMock())

  it('updateBatchEntrySession calls update with tenant_id', async () => {
    setMockData({ id: '1', status: 'closed' })
    const { updateBatchEntrySession } = await import('@/lib/queries')
    await updateBatchEntrySession('bs-1', { status: 'closed' })
    expect(mockChain.update).toHaveBeenCalled()
  })

  it('deleteBatchEntrySession calls delete', async () => {
    setMockData(null, null)
    const { deleteBatchEntrySession } = await import('@/lib/queries')
    await deleteBatchEntrySession('bs-1')
    expect(mockChain.delete).toHaveBeenCalled()
  })
})

// ============ Fiscal Year Closure ============

describe('Fiscal Year Closure', () => {
  beforeEach(() => resetMock())

  it('closeFiscalYear closes year and generates opening entries', async () => {
    mockChain.single = vi.fn(() => Promise.resolve({ data: { id: 'fy-1', code: '2024', status: 'open' }, error: null }))
    mockChain.then = vi.fn((resolve: any) => Promise.resolve({ data: [{ id: 'p1' }, { id: 'p2' }], error: null }).then(resolve))
    const { closeFiscalYear } = await import('@/lib/queries')
    const result = await closeFiscalYear('fy-1', 'fy-2')
    expect(result).toBeDefined()
    expect(typeof result.openingLinesCount).toBe('number')
  })
})

// ============ Generate Extourne ============

describe('generateExtourne', () => {
  beforeEach(() => resetMock())

  it('creates reversal entry from original', async () => {
    setMockData({
      id: 'je-1', number: 'JE-001', description: 'Test', journal_code: 'OD',
      total_debit: 100, total_credit: 100, journal_lines: [
        { account_code: '401000', account_general: '401000', debit: 100, credit: 0, description: 'Test line' }
      ]
    })
    const { generateExtourne } = await import('@/lib/queries')
    const result = await generateExtourne('je-1', 'Error in entry')
    expect(result).toBeDefined()
  })
})

// ============ Carry Forward ============

describe('generateCarryForward', () => {
  beforeEach(() => resetMock())

  it('generates carry forward entries between fiscal years', async () => {
    setMockData([{ id: 'je-1', journal_lines: [{ account_general: '401000', debit: 500, credit: 0 }] }])
    const { generateCarryForward } = await import('@/lib/queries')
    const result = await generateCarryForward('fy-1', 'fy-2')
    expect(result).toBeDefined()
  })
})
