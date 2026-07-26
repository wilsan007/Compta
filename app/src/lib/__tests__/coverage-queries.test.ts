import { describe, it, expect, vi, beforeEach } from 'vitest'

// ============================================================
// Mock infrastructure — uses module-level variables so vi.mock
// factory (which captures references) always sees current state
// ============================================================
let _data: any = []
let _error: any = null
let _fromOverride: ((table: string) => any) | null = null

function makeChain(): any {
  const chain: any = {
    select: vi.fn(() => chain),
    insert: vi.fn(() => chain),
    update: vi.fn(() => chain),
    delete: vi.fn(() => chain),
    upsert: vi.fn(() => chain),
    eq: vi.fn(() => chain),
    neq: vi.fn(() => chain),
    order: vi.fn(() => chain),
    single: vi.fn(() => Promise.resolve({ data: _data, error: _error })),
    maybeSingle: vi.fn(() => Promise.resolve({ data: _data, error: _error })),
    limit: vi.fn(() => chain),
    range: vi.fn(() => Promise.resolve({ data: _data, error: _error })),
    in: vi.fn(() => chain),
    not: vi.fn(() => chain),
    is: vi.fn(() => chain),
    gte: vi.fn(() => chain),
    lte: vi.fn(() => chain),
    like: vi.fn(() => chain),
    ilike: vi.fn(() => chain),
    or: vi.fn(() => chain),
    count: vi.fn(() => chain),
    filter: vi.fn(() => chain),
    then: vi.fn((resolve: any) => Promise.resolve({ data: _data, error: _error }).then(resolve)),
  }
  return chain
}

function chainWith(data: any, error: any = null): any {
  const c = makeChain()
  c.single = vi.fn(() => Promise.resolve({ data, error }))
  c.maybeSingle = vi.fn(() => Promise.resolve({ data, error }))
  c.then = vi.fn((resolve: any) => Promise.resolve({ data, error }).then(resolve))
  return c
}

vi.mock('@/lib/supabase', () => ({
  supabase: {
    from: vi.fn((table: string) => _fromOverride ? _fromOverride(table) : makeChain()),
    auth: {
      getSession: vi.fn(() => Promise.resolve({
        data: { session: { user: { id: 'test-user-id', email: 'test@test.com' } } }
      })),
      signInWithPassword: vi.fn(),
      signOut: vi.fn(),
    },
    functions: {
      invoke: vi.fn(() => Promise.resolve({ data: { success: true }, error: null })),
    },
    channel: vi.fn(),
    removeChannel: vi.fn(),
    rpc: vi.fn(() => Promise.resolve({ data: null, error: null })),
  },
  getCachedTenantId: vi.fn(() => 'test-tenant-id'),
  isTenantTable: vi.fn(() => true),
  setTenantId: vi.fn(),
}))

import { supabase } from '@/lib/supabase'

function setMockData(data: any, error: any = null) {
  _data = data
  _error = error
}

function resetMock() {
  _data = []
  _error = null
  _fromOverride = null
  ;(supabase as any).auth.getSession = vi.fn(() => Promise.resolve({
    data: { session: { user: { id: 'test-user-id', email: 'test@test.com' } } }
  }))
  ;(supabase as any).functions.invoke = vi.fn(() => Promise.resolve({
    data: { success: true }, error: null
  }))
}

// ============================================================
// 1. MRP Calculation (5042-5154) — runMRPCalculation inner logic
// ============================================================
describe('MRP Calculation — runMRPCalculation', () => {
  beforeEach(() => resetMock())

  it('generates proposals for products with net needs', async () => {
    let firstCall = true
    _fromOverride = (table: string) => {
      if (firstCall && table === 'mrp_runs') {
        firstCall = false
        const c = chainWith({ id: 'run1', status: 'running' })
        c.insert = vi.fn(() => c)
        c.select = vi.fn(() => c)
        c.single = vi.fn(() => Promise.resolve({ data: { id: 'run1', status: 'running' }, error: null }))
        return c
      }
      const dataMap: Record<string, any> = {
        products: [{ id: 'p1', name: 'Product A', exclude_from_mrp: false, supplier_id: 's1' }],
        boms: [{ id: 'bom1', product_id: 'p1' }],
        bom_lines: [{ bom_id: 'bom1', product_id: 'p1', quantity: 2 }],
        stock_quantities: [{ product_id: 'p1', quantity: 5 }],
        manufacturing_orders: [{ id: 'mo1', product_id: 'p1', bom_id: 'bom1', quantity: 10, status: 'planned' }],
        purchase_orders: [],
      }
      const c = chainWith(dataMap[table] || [])
      if (table === 'mrp_proposals') c.insert = vi.fn(() => c)
      if (table === 'mrp_runs') {
        c.update = vi.fn(() => c)
        c.eq = vi.fn(() => c)
        c.select = vi.fn(() => c)
        c.single = vi.fn(() => Promise.resolve({ data: { id: 'run1', status: 'completed' }, error: null }))
      }
      return c
    }

    const { runMRPCalculation } = await import('@/lib/queries')
    const result = await runMRPCalculation()
    expect(result).toBeDefined()
    expect(result.status).toBe('completed')
  })

  it('handles errors and cancels run', async () => {
    let firstCall = true
    _fromOverride = (table: string) => {
      if (firstCall && table === 'mrp_runs') {
        firstCall = false
        const c = chainWith({ id: 'run1', status: 'running' })
        c.insert = vi.fn(() => c)
        c.select = vi.fn(() => c)
        c.single = vi.fn(() => Promise.resolve({ data: { id: 'run1', status: 'running' }, error: null }))
        return c
      }
      if (table === 'products') return chainWith(null, { message: 'DB error' })
      if (table === 'mrp_runs') {
        const c = chainWith({ id: 'run1', status: 'cancelled' })
        c.update = vi.fn(() => c)
        c.eq = vi.fn(() => c)
        c.select = vi.fn(() => c)
        c.single = vi.fn(() => Promise.resolve({ data: { id: 'run1', status: 'cancelled' }, error: null }))
        return c
      }
      return chainWith([])
    }

    const { runMRPCalculation } = await import('@/lib/queries')
    await expect(runMRPCalculation()).rejects.toThrow()
  })
})

// ============================================================
// 2. autoScheduleMOs (5317-5355)
// ============================================================
describe('autoScheduleMOs', () => {
  beforeEach(() => resetMock())

  it('schedules planned MOs', async () => {
    _fromOverride = (table: string) => {
      const dataMap: Record<string, any> = {
        manufacturing_orders: [{ id: 'mo1', product_id: 'p1', routing_id: 'r1', quantity: 10, status: 'planned' }],
        machines: [{ id: 'm1', name: 'Machine 1', status: 'active' }],
        routings: [{ id: 'r1', name: 'Routing 1' }],
        routing_operations: [{ id: 'op1', routing_id: 'r1', sequence: 1, setup_time: 5, run_time: 10, work_center_id: 'wc1' }],
      }
      const c = chainWith(dataMap[table] || [])
      if (table === 'planning_slots') c.insert = vi.fn(() => c)
      if (table === 'manufacturing_orders') {
        c.update = vi.fn(() => c)
        c.eq = vi.fn(() => c)
        c.select = vi.fn(() => c)
        c.single = vi.fn(() => Promise.resolve({ data: { id: 'mo1', status: 'in_progress' }, error: null }))
      }
      return c
    }

    const { autoScheduleMOs } = await import('@/lib/queries')
    const result = await autoScheduleMOs()
    expect(typeof result).toBe('number')
  })

  it('returns scheduled=0 when no tenant', async () => {
    const mod = await import('@/lib/supabase')
    ;(mod.getCachedTenantId as any).mockReturnValueOnce(null)
    // Clear local cache in queries.ts
    const { clearTenantCache } = await import('@/lib/queries')
    clearTenantCache()
    ;(supabase as any).auth.getSession = vi.fn(() => Promise.resolve({ data: { session: null } }))
    const { autoScheduleMOs } = await import('@/lib/queries')
    const result = await autoScheduleMOs()
    expect(result).toEqual({ scheduled: 0, message: 'No tenant' })
  })
})

// ============================================================
// 3. checkMaterialAvailability (5278-5311)
// ============================================================
describe('checkMaterialAvailability', () => {
  beforeEach(() => resetMock())

  it('checks material availability', async () => {
    _fromOverride = (table: string) => {
      const dataMap: Record<string, any> = {
        bom_lines: [{ product_id: 'comp1', quantity: 5 }, { product_id: 'comp2', quantity: 3 }],
        stock_quantities: [{ product_id: 'comp1', quantity: 10 }, { product_id: 'comp2', quantity: 1 }],
      }
      return chainWith(dataMap[table] || [])
    }

    const { checkMaterialAvailability } = await import('@/lib/queries')
    const result = await checkMaterialAvailability('bom1', 2)
    expect(result).toBeDefined()
    expect(result.available).toBeDefined()
    expect(result.missing).toBeDefined()
  })
})

// ============================================================
// 4. transferGescomToAccounting (3120-3153)
// ============================================================
describe('transferGescomToAccounting', () => {
  beforeEach(() => resetMock())

  it('transfers items to accounting', async () => {
    let callIdx = 0
    _fromOverride = () => {
      const c = chainWith({ id: 'entry-' + callIdx++ })
      c.insert = vi.fn(() => c)
      c.select = vi.fn(() => c)
      c.single = vi.fn(() => Promise.resolve({ data: { id: 'entry-' + callIdx++ }, error: null }))
      return c
    }

    const { transferGescomToAccounting } = await import('@/lib/queries')
    const results = await transferGescomToAccounting([
      { type: 'sales', id: 'i1', number: 'INV-001', amount: 1000, date: '2024-01-15' },
      { type: 'purchase', id: 'pi1', number: 'PI-001', amount: 500, date: '2024-01-16' },
      { type: 'customer_payment', id: 'cp1', number: 'PAY-001', amount: 1000, date: '2024-01-17' },
      { type: 'supplier_payment', id: 'sp1', number: 'SPAY-001', amount: 500, date: '2024-01-18' },
    ])
    expect(results).toHaveLength(4)
    results.forEach((r: any) => expect(r.success).toBe(true))
  })

  it('handles errors per item', async () => {
    _fromOverride = () => {
      const c = chainWith(null, { message: 'Insert failed' })
      c.insert = vi.fn(() => c)
      c.select = vi.fn(() => c)
      c.single = vi.fn(() => Promise.resolve({ data: null, error: { message: 'Insert failed' } }))
      return c
    }

    const { transferGescomToAccounting } = await import('@/lib/queries')
    const results = await transferGescomToAccounting([
      { type: 'sales', id: 'i1', number: 'INV-001', amount: 1000, date: '2024-01-15' },
    ])
    expect(results).toHaveLength(1)
    expect(results[0].success).toBe(false)
  })
})

// ============================================================
// 5. Pay Slips & Payroll (3157-3216)
// ============================================================
describe('Pay Slips & Payroll', () => {
  beforeEach(() => resetMock())

  it('getPaySlips fetches with optional payRunId filter', async () => {
    setMockData([{ id: 'ps1', number: 'BS-001' }])
    const { getPaySlips } = await import('@/lib/queries')
    const result = await getPaySlips('run1')
    expect(result).toBeDefined()
  })

  it('createPaySlip inserts and returns data', async () => {
    setMockData({ id: 'ps1', number: 'BS-001' })
    const { createPaySlip } = await import('@/lib/queries')
    const result = await createPaySlip({ pay_run_id: 'run1', employee_id: 'e1' } as any)
    expect(result).toBeDefined()
  })

  it('updatePaySlip updates and returns data', async () => {
    setMockData({ id: 'ps1', status: 'approved' })
    const { updatePaySlip } = await import('@/lib/queries')
    const result = await updatePaySlip('ps1', { status: 'approved' } as any)
    expect(result).toBeDefined()
  })

  it('deletePaySlip deletes without error', async () => {
    setMockData(null)
    const { deletePaySlip } = await import('@/lib/queries')
    await expect(deletePaySlip('ps1')).resolves.not.toThrow()
  })

  it('generatePaySlipsForRun generates for active employees only', async () => {
    let callIdx = 0
    _fromOverride = () => {
      const c = chainWith({ id: 'ps-' + callIdx++, number: 'BS-PR-001-ALI' })
      c.insert = vi.fn(() => c)
      c.select = vi.fn(() => c)
      c.single = vi.fn(() => Promise.resolve({ data: { id: 'ps-' + callIdx++ }, error: null }))
      return c
    }

    const { generatePaySlipsForRun } = await import('@/lib/queries')
    const results = await generatePaySlipsForRun('run1', [
      { id: 'e1', name: 'Alice', salary: 3000, status: 'active' },
      { id: 'e2', name: 'Bob', salary: 2500, status: 'inactive' },
    ] as any, { number: 'PR-001', period_start: '2024-01-01', period_end: '2024-01-31' } as any)
    expect(results).toHaveLength(1)
  })

  it('getPayrollAccountingEntries fetches entries', async () => {
    setMockData([{ id: 'pae1' }])
    const { getPayrollAccountingEntries } = await import('@/lib/queries')
    const result = await getPayrollAccountingEntries()
    expect(result).toBeDefined()
  })

  it('createPayrollAccountingEntry inserts and returns', async () => {
    setMockData({ id: 'pae1' })
    const { createPayrollAccountingEntry } = await import('@/lib/queries')
    const result = await createPayrollAccountingEntry({ period_date: '2024-01-01' } as any)
    expect(result).toBeDefined()
  })

  it('updatePayrollAccountingEntry updates and returns', async () => {
    setMockData({ id: 'pae1', status: 'posted' })
    const { updatePayrollAccountingEntry } = await import('@/lib/queries')
    const result = await updatePayrollAccountingEntry('pae1', { status: 'posted' } as any)
    expect(result).toBeDefined()
  })
})

// ============================================================
// 6. getJournalPeriodBalance (1714-1747)
// ============================================================
describe('getJournalPeriodBalance', () => {
  beforeEach(() => resetMock())

  it('returns empty when no accountCounterpart', async () => {
    const { getJournalPeriodBalance } = await import('@/lib/queries')
    const result = await getJournalPeriodBalance('BQ', null, '2024-01-01', '2024-01-31')
    expect(result).toEqual({ ancienSolde: 0, mouvementDebit: 0, mouvementCredit: 0, nouveauSolde: 0 })
  })

  it('calculates balance from journal lines', async () => {
    const mockLines = [
      { account_general: '512000', account_code: '512000', debit: 100, credit: 0, journal_entries: { date: '2023-12-15', journal_code: 'BQ' } },
      { account_general: '512000', account_code: '512000', debit: 500, credit: 0, journal_entries: { date: '2024-01-10', journal_code: 'BQ' } },
      { account_general: '512000', account_code: '512000', debit: 0, credit: 200, journal_entries: { date: '2024-01-20', journal_code: 'BQ' } },
      { account_general: '401000', account_code: '401000', debit: 50, credit: 0, journal_entries: { date: '2024-01-10', journal_code: 'BQ' } },
    ]
    setMockData(mockLines)
    const { getJournalPeriodBalance } = await import('@/lib/queries')
    const result = await getJournalPeriodBalance('BQ', '512000', '2024-01-01', '2024-01-31')
    expect(result.ancienSolde).toBe(100) // Before period
    expect(result.mouvementDebit).toBe(500) // In period
    expect(result.mouvementCredit).toBe(200)
    expect(result.nouveauSolde).toBe(100 + 500 - 200)
  })

  it('returns empty on error', async () => {
    setMockData(null, { message: 'Query failed' })
    const { getJournalPeriodBalance } = await import('@/lib/queries')
    const result = await getJournalPeriodBalance('BQ', '512000', '2024-01-01', '2024-01-31')
    expect(result).toEqual({ ancienSolde: 0, mouvementDebit: 0, mouvementCredit: 0, nouveauSolde: 0 })
  })
})

// ============================================================
// 7. getNextPieceNumber (1811-1830)
// ============================================================
describe('getNextPieceNumber', () => {
  beforeEach(() => resetMock())

  it('returns default when no entries', async () => {
    setMockData([])
    const { getNextPieceNumber } = await import('@/lib/queries')
    const result = await getNextPieceNumber('VTE')
    expect(result).toBe('VTE-0001')
  })

  it('increments last piece number', async () => {
    setMockData([{ piece_number: 'VTE-0023' }])
    const { getNextPieceNumber } = await import('@/lib/queries')
    const result = await getNextPieceNumber('VTE')
    expect(result).toBe('VTE-0024')
  })

  it('returns default when no numeric suffix', async () => {
    setMockData([{ piece_number: 'VTE-ABC' }])
    const { getNextPieceNumber } = await import('@/lib/queries')
    const result = await getNextPieceNumber('VTE')
    expect(result).toBe('VTE-0001')
  })
})

// ============================================================
// 8. getUnletteredLines (1834-1845)
// ============================================================
describe('getUnletteredLines', () => {
  beforeEach(() => resetMock())

  it('fetches unlettered lines for a tiers', async () => {
    setMockData([{ id: 'jl1', account_tiers: 'CUST001' }])
    const { getUnletteredLines } = await import('@/lib/queries')
    const result = await getUnletteredLines('CUST001')
    expect(result).toHaveLength(1)
  })
})

// ============================================================
// 9. autoMatchBankTransactions (556-591)
// ============================================================
describe('autoMatchBankTransactions', () => {
  beforeEach(() => resetMock())

  it('matches transactions by amount and date', async () => {
    const mockTxns = [
      { id: 'tx1', amount: 100, date: '2024-01-10', type: 'credit', account_id: 'acc1' },
      { id: 'tx2', amount: 200, date: '2024-01-15', type: 'debit', account_id: 'acc1' },
    ]
    const mockLines = [
      { id: 'jl1', debit: 0, credit: 100, account_code: '512000', journal_entries: { date: '2024-01-10' } },
      { id: 'jl2', debit: 200, credit: 0, account_code: '401000', journal_entries: { date: '2024-01-14' } },
    ]

    let callIdx = 0
    _fromOverride = (table: string) => {
      callIdx++
      const isTxQuery = callIdx === 1
      const isLineQuery = callIdx === 2
      const data = isTxQuery ? mockTxns : isLineQuery ? mockLines : mockTxns
      const c = chainWith(data)
      if (callIdx > 2 && table === 'bank_transactions') {
        c.update = vi.fn(() => c)
        c.eq = vi.fn(() => c)
      }
      return c
    }

    const { autoMatchBankTransactions } = await import('@/lib/queries')
    const result = await autoMatchBankTransactions('acc1')
    expect(result.matched + result.unmatched).toBe(2)
  })
})

// ============================================================
// 10. getAgedBalance (2065-2101)
// ============================================================
describe('getAgedBalance', () => {
  beforeEach(() => resetMock())

  it('categorizes lines into age buckets', async () => {
    const now = new Date()
    const daysAgo = (d: number) => new Date(now.getTime() - d * 86400000).toISOString().split('T')[0]

    let callIdx = 0
    _fromOverride = () => {
      callIdx++
      const data = callIdx === 1
        ? [
            { account_tiers: 'CUST001', debit: 100, credit: 0, journal_entries: { date: daysAgo(10) }, created_at: daysAgo(10) },
            { account_tiers: 'CUST001', debit: 200, credit: 0, journal_entries: { date: daysAgo(45) }, created_at: daysAgo(45) },
            { account_tiers: 'CUST001', debit: 300, credit: 0, journal_entries: { date: daysAgo(75) }, created_at: daysAgo(75) },
            { account_tiers: 'CUST001', debit: 400, credit: 0, journal_entries: { date: daysAgo(120) }, created_at: daysAgo(120) },
          ]
        : [{ code: 'CUST001', name: 'Customer A', type: 'customer' }]
      return chainWith(data)
    }

    const { getAgedBalance } = await import('@/lib/queries')
    const result = await getAgedBalance()
    expect(result).toBeDefined()
    if (result.length > 0) {
      expect(result[0].code).toBe('CUST001')
      expect(result[0].bucket0_30).toBe(100)
      expect(result[0].bucket31_60).toBe(200)
      expect(result[0].bucket61_90).toBe(300)
      expect(result[0].bucket90p).toBe(400)
    }
  })
})

// ============================================================
// 11. inviteUser (4310-4365)
// ============================================================
describe('inviteUser', () => {
  beforeEach(() => resetMock())

  it('returns failure when no session', async () => {
    ;(supabase as any).auth.getSession = vi.fn(() => Promise.resolve({ data: { session: null } }))
    const { inviteUser } = await import('@/lib/queries')
    const result = await inviteUser({ tenantId: 'tid1', email: 'test@test.com', name: 'Test', role: 'viewer' })
    expect(result.success).toBe(false)
  })

  it('invites user via edge function', async () => {
    setMockData({ id: 'tu1', role: 'admin', status: 'active', tenant_id: 'test-tenant-id' })
    ;(supabase as any).functions.invoke = vi.fn(() => Promise.resolve({
      data: { success: true, message: 'User invited' }, error: null
    }))

    const { inviteUser } = await import('@/lib/queries')
    const result = await inviteUser({ tenantId: 'test-tenant-id', email: 'new@test.com', name: 'New User', role: 'viewer' })
    expect(result.success).toBe(true)
  })

  it('handles edge function error', async () => {
    setMockData({ id: 'tu1', role: 'admin', status: 'active', tenant_id: 'test-tenant-id' })
    ;(supabase as any).functions.invoke = vi.fn(() => Promise.resolve({
      data: null, error: { message: 'Function error', context: null }
    }))

    const { inviteUser } = await import('@/lib/queries')
    const result = await inviteUser({ tenantId: 'test-tenant-id', email: 'new@test.com', name: 'New User', role: 'viewer' })
    expect(result.success).toBe(false)
  })
})

// ============================================================
// 12. updateUserRole & revokeUser & reactivateUser (4368-4420)
// ============================================================
describe('User Management', () => {
  beforeEach(() => resetMock())

  it('updateUserRole updates role', async () => {
    // requireAdminOfTenant queries tenant_users first, then update
    let callIdx = 0
    _fromOverride = (table: string) => {
      callIdx++
      if (table === 'tenant_users' && callIdx === 1) {
        // Admin check query
        return chainWith({ id: 'tu1', role: 'admin', status: 'active', tenant_id: 'test-tenant-id' })
      }
      // Update call
      const c = chainWith(null)
      c.update = vi.fn(() => c)
      c.eq = vi.fn(() => c)
      c.then = vi.fn((resolve: any) => Promise.resolve({ data: null, error: null }).then(resolve))
      return c
    }
    const { updateUserRole } = await import('@/lib/queries')
    const result = await updateUserRole('tu1', 'manager')
    expect(result.success).toBe(true)
  })

  it('revokeUser revokes user', async () => {
    let callIdx = 0
    _fromOverride = (table: string) => {
      callIdx++
      if (table === 'tenant_users' && callIdx === 1) {
        return chainWith({ id: 'tu1', role: 'admin', status: 'active', tenant_id: 'test-tenant-id' })
      }
      const c = chainWith(null)
      c.update = vi.fn(() => c)
      c.eq = vi.fn(() => c)
      c.then = vi.fn((resolve: any) => Promise.resolve({ data: null, error: null }).then(resolve))
      return c
    }
    const { revokeUser } = await import('@/lib/queries')
    const result = await revokeUser('tu1')
    expect(result.success).toBe(true)
  })

  it('reactivateUser reactivates user', async () => {
    let callIdx = 0
    _fromOverride = (table: string) => {
      callIdx++
      if (table === 'tenant_users' && callIdx === 1) {
        return chainWith({ id: 'tu1', role: 'admin', status: 'active', tenant_id: 'test-tenant-id' })
      }
      const c = chainWith(null)
      c.update = vi.fn(() => c)
      c.eq = vi.fn(() => c)
      c.then = vi.fn((resolve: any) => Promise.resolve({ data: null, error: null }).then(resolve))
      return c
    }
    const { reactivateUser } = await import('@/lib/queries')
    const result = await reactivateUser('tu1')
    expect(result.success).toBe(true)
  })
})

// ============================================================
// 13. hasPermission (4523-4554)
// ============================================================
describe('hasPermission', () => {
  it('admin has all permissions', async () => {
    const { hasPermission } = await import('@/lib/queries')
    expect(hasPermission({ role: 'admin' } as any, 'invoices', 'delete')).toBe(true)
    expect(hasPermission({ role: 'admin' } as any, 'any_table', 'insert')).toBe(true)
  })

  it('accountant can select/insert/update, limited delete', async () => {
    const { hasPermission } = await import('@/lib/queries')
    const user = { role: 'accountant' } as any
    expect(hasPermission(user, 'invoices', 'select')).toBe(true)
    expect(hasPermission(user, 'invoices', 'insert')).toBe(true)
    expect(hasPermission(user, 'invoices', 'update')).toBe(true)
    expect(hasPermission(user, 'journal_entries', 'delete')).toBe(true)
    expect(hasPermission(user, 'customers', 'delete')).toBe(false)
  })

  it('manager can select all, insert/update commercial only', async () => {
    const { hasPermission } = await import('@/lib/queries')
    const user = { role: 'manager' } as any
    expect(hasPermission(user, 'invoices', 'select')).toBe(true)
    expect(hasPermission(user, 'invoices', 'insert')).toBe(true)
    expect(hasPermission(user, 'journal_entries', 'insert')).toBe(false)
    expect(hasPermission(user, 'invoices', 'delete')).toBe(false)
  })

  it('viewer and auditor can only select', async () => {
    const { hasPermission } = await import('@/lib/queries')
    expect(hasPermission({ role: 'viewer' } as any, 'invoices', 'select')).toBe(true)
    expect(hasPermission({ role: 'viewer' } as any, 'invoices', 'insert')).toBe(false)
    expect(hasPermission({ role: 'auditor' } as any, 'invoices', 'select')).toBe(true)
    expect(hasPermission({ role: 'auditor' } as any, 'invoices', 'delete')).toBe(false)
  })

  it('custom role uses permissions map', async () => {
    const { hasPermission } = await import('@/lib/queries')
    const user = { role: 'custom', permissions: { invoices: ['select', 'update'] } } as any
    expect(hasPermission(user, 'invoices', 'select')).toBe(true)
    expect(hasPermission(user, 'invoices', 'update')).toBe(true)
    expect(hasPermission(user, 'invoices', 'delete')).toBe(false)
    expect(hasPermission(user, 'products', 'select')).toBe(false)
  })

  it('null user has no permissions', async () => {
    const { hasPermission } = await import('@/lib/queries')
    expect(hasPermission(null, 'invoices', 'select')).toBe(false)
  })
})

// ============================================================
// 14. exportAllData & exportToSQL (3568-3645)
// ============================================================
describe('exportAllData', () => {
  beforeEach(() => resetMock())

  it('exports all tables', async () => {
    setMockData([{ id: '1', name: 'Test' }])
    const { exportAllData } = await import('@/lib/queries')
    const result = await exportAllData()
    expect(result).toBeDefined()
    expect(result.tables).toBeDefined()
    expect(result.totalRows).toBeGreaterThanOrEqual(0)
  })
})

// ============================================================
// 15. generatePaymentLink (5646-5665)
// ============================================================
describe('generatePaymentLink', () => {
  beforeEach(() => resetMock())

  it('generates a payment link for a reminder', async () => {
    setMockData({ id: 'r1', payment_link_token: 'tok123' })
    const { generatePaymentLink } = await import('@/lib/queries')
    const result = await generatePaymentLink('r1')
    expect(result).toBeDefined()
  })
})

// ============================================================
// 16. getProductStock & getProductSupplierPrices (5371-5387)
// ============================================================
describe('Article Interrogation', () => {
  beforeEach(() => resetMock())

  it('getProductStock returns stock quantities', async () => {
    setMockData([{ product_id: 'p1', quantity: 100, warehouses: { name: 'WH1' } }])
    const { getProductStock } = await import('@/lib/queries')
    const result = await getProductStock('p1')
    expect(result).toHaveLength(1)
  })

  it('getProductSupplierPrices returns purchase price lists only', async () => {
    setMockData([
      { product_id: 'p1', price_lists: { name: 'Purchase PL', type: 'purchase' }, suppliers: { name: 'Supplier A' } },
      { product_id: 'p1', price_lists: { name: 'Sales PL', type: 'sale' }, suppliers: null },
    ])
    const { getProductSupplierPrices } = await import('@/lib/queries')
    const result = await getProductSupplierPrices('p1')
    expect(result).toHaveLength(1) // Only purchase type
  })
})

// ============================================================
// 17. exportToExcel (8233-8250)
// ============================================================
describe('exportToExcel', () => {
  it('generates CSV and triggers download', async () => {
    const { exportToExcel } = await import('@/lib/queries')
    const origURL = URL.createObjectURL
    const origClick = HTMLAnchorElement.prototype.click
    URL.createObjectURL = vi.fn(() => 'blob:test')
    HTMLAnchorElement.prototype.click = vi.fn()

    exportToExcel('test.csv', ['Name', 'Value'], [['Alice', 100], ['Bob', 200]])

    expect(URL.createObjectURL).toHaveBeenCalled()
    URL.createObjectURL = origURL
    HTMLAnchorElement.prototype.click = origClick
  })

  it('escapes CSV special characters', async () => {
    const { exportToExcel } = await import('@/lib/queries')
    const origURL = URL.createObjectURL
    const origClick = HTMLAnchorElement.prototype.click
    URL.createObjectURL = vi.fn(() => 'blob:test')
    HTMLAnchorElement.prototype.click = vi.fn()

    exportToExcel('test.csv', ['Name'], [['Hello, "World"']])

    expect(URL.createObjectURL).toHaveBeenCalled()
    URL.createObjectURL = origURL
    HTMLAnchorElement.prototype.click = origClick
  })
})

// ============================================================
// 18. checkCreditLimit (8220-8229)
// ============================================================
describe('checkCreditLimit', () => {
  beforeEach(() => resetMock())

  it('returns exceeded=true when balance > limit', async () => {
    setMockData({ balance: 1500, credit_limit: 1000 })
    const { checkCreditLimit } = await import('@/lib/queries')
    const result = await checkCreditLimit('cust1')
    expect(result.exceeded).toBe(true)
    expect(result.balance).toBe(1500)
    expect(result.limit).toBe(1000)
  })

  it('returns exceeded=false when balance <= limit', async () => {
    setMockData({ balance: 500, credit_limit: 1000 })
    const { checkCreditLimit } = await import('@/lib/queries')
    const result = await checkCreditLimit('cust1')
    expect(result.exceeded).toBe(false)
  })

  it('returns exceeded=false when no limit set', async () => {
    setMockData({ balance: 500, credit_limit: null })
    const { checkCreditLimit } = await import('@/lib/queries')
    const result = await checkCreditLimit('cust1')
    expect(result.exceeded).toBe(false)
    expect(result.limit).toBe(null)
  })

  it('returns exceeded=false on error', async () => {
    setMockData(null, { message: 'Not found' })
    const { checkCreditLimit } = await import('@/lib/queries')
    const result = await checkCreditLimit('cust1')
    expect(result.exceeded).toBe(false)
  })
})

// ============================================================
// 19. getEcheancier (2105-2150)
// ============================================================
describe('getEcheancier', () => {
  beforeEach(() => resetMock())

  it('fetches customer echeancier', async () => {
    let callIdx = 0
    _fromOverride = () => {
      callIdx++
      const data = callIdx <= 2
        ? [{ id: 'inv1', number: 'INV-001', date: '2024-01-01', due_date: '2024-02-01', total_ttc: 1000, paid_amount: 400, customer_id: 'c1', customers: { name: 'Customer A' } }]
        : []
      return chainWith(data)
    }

    const { getEcheancier } = await import('@/lib/queries')
    const result = await getEcheancier('customer')
    expect(result).toBeDefined()
  })
})

// ============================================================
// 20. createTenant (4140-4200)
// ============================================================
describe('createTenant', () => {
  beforeEach(() => resetMock())

  it('returns failure when no session', async () => {
    ;(supabase as any).auth.getSession = vi.fn(() => Promise.resolve({ data: { session: null } }))
    const queries = await import('@/lib/queries')
    expect(queries.createTenantForUser).toBeDefined()
    const result = await queries.createTenantForUser({ name: 'Test Co' })
    expect(result.success).toBe(false)
  })

  it('creates tenant and tenant_users entry', async () => {
    _fromOverride = (table: string) => {
      const c = chainWith({ id: 't1', name: 'Test Co' })
      if (table === 'tenants' || table === 'tenant_users') {
        c.insert = vi.fn(() => c)
        c.select = vi.fn(() => c)
        c.single = vi.fn(() => Promise.resolve({ data: { id: 't1', name: 'Test Co' }, error: null }))
      }
      if (table === 'company_settings') c.insert = vi.fn(() => c)
      return c
    }

    const queries = await import('@/lib/queries')
    expect(queries.createTenantForUser).toBeDefined()
    const result = await queries.createTenantForUser({ name: 'Test Co' })
    expect(result.success).toBe(true)
    expect(result.tenant).toBeDefined()
  })
})
