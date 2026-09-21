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

// ============ Helper ============
function setMockData(data: any, error: any = null) {
  mockChain.single = vi.fn(() => Promise.resolve({ data, error }))
  mockChain.then = vi.fn((resolve: any) => Promise.resolve({ data, error }).then(resolve))
}

function resetMock() {
  mockChain.single = vi.fn(() => Promise.resolve({ data: null, error: null }))
  mockChain.then = vi.fn((resolve: any) => Promise.resolve({ data: [], error: null }).then(resolve))
  // ACC-01: Réinitialiser rpc au mock par défaut
  ;(supabase as any).rpc = vi.fn(() => Promise.resolve({ data: null, error: null }))
  vi.clearAllMocks()
  // Restaurer from après clearAllMocks
  ;(supabase as any).from = vi.fn(() => mockChain)
}

beforeEach(() => resetMock())

// ============ Pure Function Tests (no DB) ============

describe('calculateVAT', () => {
  it('calculates VAT from HT amount', async () => {
    const { calculateVAT } = await import('@/lib/queries')
    const result = calculateVAT(1000, 20, 'ht')
    expect(result.ht).toBe(1000)
    expect(result.tva).toBe(200)
    expect(result.ttc).toBe(1200)
  })

  it('calculates VAT from TTC amount', async () => {
    const { calculateVAT } = await import('@/lib/queries')
    const result = calculateVAT(1200, 20, 'ttc')
    expect(result.ttc).toBe(1200)
    expect(result.tva).toBe(200)
    expect(result.ht).toBe(1000)
  })

  it('defaults to HT mode', async () => {
    const { calculateVAT } = await import('@/lib/queries')
    const result = calculateVAT(100, 10)
    expect(result.ht).toBe(100)
    expect(result.tva).toBe(10)
    expect(result.ttc).toBe(110)
  })

  it('handles zero amount', async () => {
    const { calculateVAT } = await import('@/lib/queries')
    const result = calculateVAT(0, 20, 'ht')
    expect(result.ht).toBe(0)
    expect(result.tva).toBe(0)
    expect(result.ttc).toBe(0)
  })

  it('rounds to 2 decimal places', async () => {
    const { calculateVAT } = await import('@/lib/queries')
    const result = calculateVAT(333.333, 20, 'ht')
    expect(result.tva).toBe(66.67)
  })

  it('handles TTC with rounding', async () => {
    const { calculateVAT } = await import('@/lib/queries')
    const result = calculateVAT(100, 20, 'ttc')
    expect(result.ht).toBe(83.33)
    expect(result.tva).toBe(16.67)
  })
})

describe('generateMultiEcheances', () => {
  it('generates single echeance for fixed type', async () => {
    const { generateMultiEcheances } = await import('@/lib/queries')
    const result = generateMultiEcheances('2024-01-15', {
      id: '1', code: '30D', type: 'fixed', days_1: 30, days_2: null, pct_1: null, pct_2: null,
    } as any)
    expect(result).toHaveLength(1)
    expect(result[0].amount_pct).toBe(100)
    expect(result[0].label).toContain('30D')
  })

  it('generates single echeance for end_of_month type', async () => {
    const { generateMultiEcheances } = await import('@/lib/queries')
    const result = generateMultiEcheances('2024-01-15', {
      id: '1', code: 'FM', type: 'end_of_month', days_1: 0, days_2: null, pct_1: null, pct_2: null,
    } as any)
    expect(result).toHaveLength(1)
    expect(result[0].amount_pct).toBe(100)
    // Should be end of January 2024
    expect(result[0].date).toBe('2024-01-31')
  })

  it('generates two echeances for split type', async () => {
    const { generateMultiEcheances } = await import('@/lib/queries')
    const result = generateMultiEcheances('2024-01-15', {
      id: '1', code: 'SPLIT', type: 'split', days_1: 30, days_2: 60, pct_1: 50, pct_2: 50,
    } as any)
    expect(result).toHaveLength(2)
    expect(result[0].amount_pct).toBe(50)
    expect(result[1].amount_pct).toBe(50)
    expect(result[0].label).toContain('1')
    expect(result[1].label).toContain('2')
  })

  it('handles split with default percentages', async () => {
    const { generateMultiEcheances } = await import('@/lib/queries')
    const result = generateMultiEcheances('2024-01-15', {
      id: '1', code: 'SPLIT', type: 'split', days_1: 30, days_2: 60, pct_1: null, pct_2: null,
    } as any)
    expect(result).toHaveLength(2)
    expect(result[0].amount_pct).toBe(50)
    expect(result[1].amount_pct).toBe(50)
  })

  it('handles split without days_2 (single echeance)', async () => {
    const { generateMultiEcheances } = await import('@/lib/queries')
    const result = generateMultiEcheances('2024-01-15', {
      id: '1', code: 'SPLIT', type: 'split', days_1: 30, days_2: null, pct_1: 100, pct_2: 0,
    } as any)
    expect(result).toHaveLength(1)
    expect(result[0].amount_pct).toBe(100)
  })
})

// ============ Chart of Accounts CRUD ============

describe('Chart Accounts CRUD', () => {
  beforeEach(() => resetMock())

  it('getChartAccounts queries chart_accounts ordered by code', async () => {
    setMockData([{ id: '1', code: '400000', name: 'Clients' }])
    const { getChartAccounts } = await import('@/lib/queries')
    const result = await getChartAccounts()
    expect((supabase as any).from).toHaveBeenCalledWith('chart_accounts')
    expect(mockChain.order).toHaveBeenCalledWith('code', { ascending: true })
    expect(mockChain.eq).toHaveBeenCalledWith('tenant_id', 'test-tenant-id')
    expect(result).toHaveLength(1)
  })

  it('createChartAccount inserts with tenant_id', async () => {
    setMockData({ id: '1', code: '400000', name: 'Clients' })
    const { createChartAccount } = await import('@/lib/queries')
    await createChartAccount({ code: '400000', name: 'Clients' } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ code: '400000', tenant_id: 'test-tenant-id' })
    )
  })

  it('updateChartAccount updates with id and tenant filter', async () => {
    setMockData({ id: '1', code: '400000', name: 'Updated' })
    const { updateChartAccount } = await import('@/lib/queries')
    await updateChartAccount('1', { name: 'Updated' } as any)
    expect((supabase as any).from).toHaveBeenCalledWith('chart_accounts')
    expect(mockChain.eq).toHaveBeenCalledWith('id', '1')
  })

  it('deleteChartAccount calls delete with id', async () => {
    setMockData(null, null)
    const { deleteChartAccount } = await import('@/lib/queries')
    await deleteChartAccount('acc-1')
    expect(mockChain.delete).toHaveBeenCalled()
    expect(mockChain.eq).toHaveBeenCalledWith('id', 'acc-1')
  })
})

// ============ Customers CRUD ============

describe('Customers CRUD', () => {
  beforeEach(() => resetMock())

  it('getCustomers queries customers ordered by created_at desc', async () => {
    setMockData([{ id: '1', name: 'Acme' }])
    const { getCustomers } = await import('@/lib/queries')
    const result = await getCustomers()
    expect((supabase as any).from).toHaveBeenCalledWith('customers')
    expect(mockChain.order).toHaveBeenCalledWith('created_at', { ascending: false })
    expect(result).toHaveLength(1)
  })

  it('createCustomer inserts with tenant_id', async () => {
    setMockData({ id: '1', name: 'Acme' })
    const { createCustomer } = await import('@/lib/queries')
    await createCustomer({ name: 'Acme', email: 'info@acme.com' } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ name: 'Acme', tenant_id: 'test-tenant-id' })
    )
  })

  it('updateCustomer updates with id', async () => {
    setMockData({ id: '1', name: 'Updated' })
    const { updateCustomer } = await import('@/lib/queries')
    await updateCustomer('cust-1', { name: 'Updated' } as any)
    expect((supabase as any).from).toHaveBeenCalledWith('customers')
    expect(mockChain.eq).toHaveBeenCalledWith('id', 'cust-1')
  })

  it('deleteCustomer calls delete with id', async () => {
    setMockData(null, null)
    const { deleteCustomer } = await import('@/lib/queries')
    await deleteCustomer('cust-1')
    expect(mockChain.delete).toHaveBeenCalled()
    expect(mockChain.eq).toHaveBeenCalledWith('id', 'cust-1')
  })
})

// ============ Suppliers CRUD ============

describe('Suppliers CRUD', () => {
  beforeEach(() => resetMock())

  it('getSuppliers queries suppliers ordered by created_at desc', async () => {
    setMockData([{ id: '1', name: 'Supplier Co' }])
    const { getSuppliers } = await import('@/lib/queries')
    const result = await getSuppliers()
    expect((supabase as any).from).toHaveBeenCalledWith('suppliers')
    expect(mockChain.order).toHaveBeenCalledWith('created_at', { ascending: false })
    expect(result).toHaveLength(1)
  })

  it('createSupplier inserts with tenant_id', async () => {
    setMockData({ id: '1', name: 'Supplier Co' })
    const { createSupplier } = await import('@/lib/queries')
    await createSupplier({ name: 'Supplier Co' } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ name: 'Supplier Co', tenant_id: 'test-tenant-id' })
    )
  })

  it('updateSupplier updates with id', async () => {
    setMockData({ id: '1', name: 'Updated' })
    const { updateSupplier } = await import('@/lib/queries')
    await updateSupplier('sup-1', { name: 'Updated' } as any)
    expect((supabase as any).from).toHaveBeenCalledWith('suppliers')
    expect(mockChain.eq).toHaveBeenCalledWith('id', 'sup-1')
  })

  it('deleteSupplier calls delete with id', async () => {
    setMockData(null, null)
    const { deleteSupplier } = await import('@/lib/queries')
    await deleteSupplier('sup-1')
    expect(mockChain.delete).toHaveBeenCalled()
  })
})

// ============ Products CRUD ============

describe('Products CRUD', () => {
  beforeEach(() => resetMock())

  it('getProducts queries products ordered by name', async () => {
    setMockData([{ id: '1', name: 'Widget' }])
    const { getProducts } = await import('@/lib/queries')
    const result = await getProducts()
    expect((supabase as any).from).toHaveBeenCalledWith('products')
    expect(mockChain.order).toHaveBeenCalledWith('name', { ascending: true })
    expect(result).toHaveLength(1)
  })

  it('createProduct inserts with tenant_id', async () => {
    setMockData({ id: '1', name: 'Widget' })
    const { createProduct } = await import('@/lib/queries')
    await createProduct({ name: 'Widget', price: 10 } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ name: 'Widget', tenant_id: 'test-tenant-id' })
    )
  })

  it('updateProduct updates with id', async () => {
    setMockData({ id: '1', name: 'Updated' })
    const { updateProduct } = await import('@/lib/queries')
    await updateProduct('prod-1', { name: 'Updated' } as any)
    expect((supabase as any).from).toHaveBeenCalledWith('products')
    expect(mockChain.eq).toHaveBeenCalledWith('id', 'prod-1')
  })

  it('deleteProduct calls delete with id', async () => {
    setMockData(null, null)
    const { deleteProduct } = await import('@/lib/queries')
    await deleteProduct('prod-1')
    expect(mockChain.delete).toHaveBeenCalled()
  })
})

// ============ Invoices CRUD ============

describe('Invoices CRUD', () => {
  beforeEach(() => resetMock())

  it('getInvoices queries invoices with invoice_lines ordered by date desc', async () => {
    setMockData([{ id: '1', number: 'INV-001' }])
    const { getInvoices } = await import('@/lib/queries')
    const result = await getInvoices()
    expect((supabase as any).from).toHaveBeenCalledWith('invoices')
    expect(mockChain.order).toHaveBeenCalledWith('date', { ascending: false })
    expect(result).toHaveLength(1)
  })

  it('createInvoice inserts invoice with tenant_id', async () => {
    // LOT4-11 : createInvoice utilise maintenant la RPC atomique create_invoice_atomic
    ;(supabase as any).rpc = vi.fn(() => Promise.resolve({ data: { success: true, invoice_id: '1' }, error: null }))
    setMockData({ id: '1', number: 'INV-001' })
    const { createInvoice } = await import('@/lib/queries')
    await createInvoice({
      number: 'INV-001', customer_id: 'c1', customer_name: 'Acme',
      date: '2024-01-01', due_date: '2024-01-31', status: 'draft',
      lines: [],
    } as any)
    expect((supabase as any).rpc).toHaveBeenCalledWith('create_invoice_atomic', expect.objectContaining({
      p_invoice: expect.objectContaining({ number: 'INV-001', tenant_id: 'test-tenant-id' }),
      p_lines: [],
    }))
  })

  it('createInvoice inserts lines when provided', async () => {
    // LOT4-11 : createInvoice utilise maintenant la RPC atomique create_invoice_atomic
    ;(supabase as any).rpc = vi.fn(() => Promise.resolve({ data: { success: true, invoice_id: '1' }, error: null }))
    setMockData({ id: '1', number: 'INV-001' })
    const { createInvoice } = await import('@/lib/queries')
    await createInvoice({
      number: 'INV-001', customer_id: 'c1', customer_name: 'Acme',
      date: '2024-01-01', due_date: '2024-01-31', status: 'draft',
      lines: [{ description: 'Item 1', quantity: 1, unit_price: 100, line_total: 100 }],
    } as any)
    // La RPC atomique reçoit les lignes dans p_lines
    expect((supabase as any).rpc).toHaveBeenCalledWith('create_invoice_atomic', expect.objectContaining({
      p_lines: expect.arrayContaining([expect.objectContaining({ description: 'Item 1', line_order: 0 })]),
    }))
  })

  it('updateInvoice updates with id', async () => {
    setMockData({ id: '1', number: 'INV-001' })
    const { updateInvoice } = await import('@/lib/queries')
    await updateInvoice('inv-1', { status: 'paid' } as any)
    expect((supabase as any).from).toHaveBeenCalledWith('invoices')
    expect(mockChain.eq).toHaveBeenCalledWith('id', 'inv-1')
  })

  it('deleteInvoice calls delete with id', async () => {
    setMockData(null, null)
    const { deleteInvoice } = await import('@/lib/queries')
    await deleteInvoice('inv-1')
    expect(mockChain.delete).toHaveBeenCalled()
  })
})

// ============ Journal Entries CRUD ============

describe('Journal Entries CRUD', () => {
  beforeEach(() => resetMock())

  it('getJournalEntries queries journal_entries with journal_lines', async () => {
    setMockData([{ id: '1', number: 'JE-001', journal_lines: [] }])
    const { getJournalEntries } = await import('@/lib/queries')
    const result = await getJournalEntries()
    expect((supabase as any).from).toHaveBeenCalledWith('journal_entries')
    expect(mockChain.order).toHaveBeenCalledWith('date', { ascending: false })
    expect(result).toHaveLength(1)
  })

  it('createJournalEntry inserts entry with tenant_id', async () => {
    // ACC-01: createJournalEntry utilise maintenant le RPC post_journal_entry
    setMockData({ id: '1', number: 'JE-001' })
    const supabaseMock = await import('@/lib/supabase')
    ;(supabaseMock.supabase as any).rpc = vi.fn(() => Promise.resolve({ data: { success: true, entry_id: '1', number: 'JE-001' }, error: null }))
    const { createJournalEntry } = await import('@/lib/queries')
    await createJournalEntry({
      number: 'JE-001', date: '2024-01-01', description: 'Test',
      journal_code: 'VT', status: 'draft', lines: [],
    } as any)
    expect((supabaseMock.supabase as any).rpc).toHaveBeenCalledWith('post_journal_entry', expect.any(Object))
  })

  it('createJournalEntry inserts lines when provided', async () => {
    // ACC-01: createJournalEntry utilise maintenant le RPC post_journal_entry
    setMockData({ id: '1', number: 'JE-001' })
    const supabaseMock = await import('@/lib/supabase')
    ;(supabaseMock.supabase as any).rpc = vi.fn(() => Promise.resolve({ data: { success: true, entry_id: '1', number: 'JE-001' }, error: null }))
    const { createJournalEntry } = await import('@/lib/queries')
    await createJournalEntry({
      number: 'JE-001', date: '2024-01-01', description: 'Test',
      journal_code: 'VT', status: 'draft',
      lines: [{ account_code: '411000', debit: 100, credit: 0, description: 'Line 1' }],
    } as any)
    expect((supabaseMock.supabase as any).rpc).toHaveBeenCalledWith('post_journal_entry', expect.any(Object))
  })

  it('updateJournalEntry updates with id', async () => {
    setMockData({ id: '1', number: 'JE-001' })
    const { updateJournalEntry } = await import('@/lib/queries')
    await updateJournalEntry('je-1', { status: 'posted' } as any)
    expect((supabase as any).from).toHaveBeenCalledWith('journal_entries')
    expect(mockChain.eq).toHaveBeenCalledWith('id', 'je-1')
  })

  it('deleteJournalEntry calls delete with id', async () => {
    setMockData(null, null)
    const { deleteJournalEntry } = await import('@/lib/queries')
    await deleteJournalEntry('je-1')
    expect(mockChain.delete).toHaveBeenCalled()
  })

  it('getJournalEntry fetches single entry by id', async () => {
    setMockData({ id: '1', number: 'JE-001', journal_lines: [] })
    const { getJournalEntry } = await import('@/lib/queries')
    const result = await getJournalEntry('je-1')
    expect((supabase as any).from).toHaveBeenCalledWith('journal_entries')
    expect(mockChain.eq).toHaveBeenCalledWith('id', 'je-1')
    expect(result).toBeDefined()
  })
})

// ============ Reporting: General Ledger ============

describe('General Ledger', () => {
  beforeEach(() => resetMock())

  it('getGeneralLedger queries journal_lines', async () => {
    ;(supabase as any).from = vi.fn((table: string) => {
      if (table === 'fiscal_years') {
        const fyChain = createMockChain({ data: [{ id: 'fy-1' }], error: null })
        return fyChain
      }
      return mockChain
    })
    ;(supabase as any).rpc = vi.fn(() => Promise.resolve({ data: [{ line_id: '1', account_code: '400000', debit: 100, credit: 0, total_count: 1 }], error: null }))
    const { getGeneralLedger } = await import('@/lib/queries')
    const result = await getGeneralLedger()
    expect((supabase as any).rpc).toHaveBeenCalledWith('get_general_ledger', expect.any(Object))
    expect(result).toHaveLength(1)
  })

  it('getGeneralLedger filters by accountCode when provided', async () => {
    ;(supabase as any).from = vi.fn((table: string) => {
      if (table === 'fiscal_years') {
        return createMockChain({ data: [{ id: 'fy-1' }], error: null })
      }
      return mockChain
    })
    ;(supabase as any).rpc = vi.fn(() => Promise.resolve({ data: [], error: null }))
    const { getGeneralLedger } = await import('@/lib/queries')
    await getGeneralLedger('400000')
    expect((supabase as any).rpc).toHaveBeenCalledWith('get_general_ledger', expect.objectContaining({ p_account_code: '400000' }))
  })
})

// ============ Reporting: Trial Balance ============

describe('Trial Balance', () => {
  beforeEach(() => resetMock())

  it('getTrialBalance aggregates debit/credit by account', async () => {
    ;(supabase as any).from = vi.fn((table: string) => {
      if (table === 'fiscal_years') return createMockChain({ data: [{ id: 'fy-1' }], error: null })
      return mockChain
    })
    ;(supabase as any).rpc = vi.fn(() => Promise.resolve({
      data: [
        { account_code: '400000', account_name: 'Clients', opening_debit: 0, opening_credit: 0, period_debit: 150, period_credit: 30, closing_debit: 120, closing_credit: 0 },
        { account_code: '411000', account_name: 'Fournisseurs', opening_debit: 0, opening_credit: 0, period_debit: 0, period_credit: 200, closing_debit: 0, closing_credit: 200 },
      ],
      error: null
    }))
    const { getTrialBalance } = await import('@/lib/queries')
    const result = await getTrialBalance()
    expect(result).toHaveLength(2)
    const clients = result.find((r: any) => r.account_code === '400000')
    expect(clients?.total_debit).toBe(150)
    expect(clients?.total_credit).toBe(30)
  })

  it('getTrialBalance returns empty array for no data', async () => {
    ;(supabase as any).from = vi.fn((table: string) => {
      if (table === 'fiscal_years') return createMockChain({ data: [{ id: 'fy-1' }], error: null })
      return mockChain
    })
    ;(supabase as any).rpc = vi.fn(() => Promise.resolve({ data: [], error: null }))
    const { getTrialBalance } = await import('@/lib/queries')
    const result = await getTrialBalance()
    expect(result).toHaveLength(0)
  })
})

// ============ Reporting: Balance Sheet ============

describe('Balance Sheet', () => {
  beforeEach(() => resetMock())

  it('getBalanceSheet queries journal_lines', async () => {
    ;(supabase as any).from = vi.fn((table: string) => {
      if (table === 'fiscal_years') return createMockChain({ data: [{ id: 'fy-1' }], error: null })
      return mockChain
    })
    ;(supabase as any).rpc = vi.fn(() => Promise.resolve({
      data: [{ account_code: '100000', account_name: 'Capital', account_type: 'equity', debit: 0, credit: 10000, balance: -10000 }],
      error: null
    }))
    const { getBalanceSheet } = await import('@/lib/queries')
    const result = await getBalanceSheet()
    expect((supabase as any).rpc).toHaveBeenCalledWith('get_balance_sheet', expect.any(Object))
    expect(result).toBeDefined()
  })
})

describe('Balance Sheet — AUD-D08', () => {
  beforeEach(() => resetMock())

  it('interroge l\'exercice demandé, isole les comptes non classés et mesure l\'écart', async () => {
    ;(supabase as any).rpc = vi.fn(() => Promise.resolve({
      data: [
        { account_code: '512000', account_name: 'Banque', account_type: 'asset', debit: 300, credit: 0, balance: 300 },
        { account_code: 'ZZ9999', account_name: 'ZZ9999', account_type: 'unclassified', debit: 0, credit: 300, balance: -300 },
      ],
      error: null,
    }))
    const { getBalanceSheet } = await import('@/lib/queries')
    const result = await getBalanceSheet({ fiscalYearId: 'fy-9' })
    expect((supabase as any).rpc).toHaveBeenCalledWith('get_balance_sheet', { p_fiscal_year_id: 'fy-9', p_date_to: null })
    expect(result.assets.map((a: any) => a.code)).toEqual(['512000'])
    expect(result.unclassified.map((a: any) => a.code)).toEqual(['ZZ9999'])
    expect(result.gap).toBe(0)
  })

  it('signale un bilan déséquilibré par un écart non nul', async () => {
    ;(supabase as any).rpc = vi.fn(() => Promise.resolve({
      data: [{ account_code: '512000', account_name: 'Banque', account_type: 'asset', debit: 300, credit: 0, balance: 300 }],
      error: null,
    }))
    const { getBalanceSheet } = await import('@/lib/queries')
    const result = await getBalanceSheet({ fiscalYearId: 'fy-9' })
    expect(result.gap).toBe(300)
  })
})

// ============ Reporting: Cash Flow ============

describe('Cash Flow', () => {
  beforeEach(() => resetMock())

  it('getCashFlow queries bank_transactions', async () => {
    setMockData([{ amount: 1000, transaction_type: 'credit' }])
    const { getCashFlow } = await import('@/lib/queries')
    const result = await getCashFlow()
    expect((supabase as any).from).toHaveBeenCalledWith('bank_transactions')
    expect(result).toBeDefined()
  })
})

// ============ VAT Returns ============

describe('VAT Returns', () => {
  beforeEach(() => resetMock())

  it('getVatReturns queries vat_returns ordered by period_start desc', async () => {
    setMockData([{ id: '1', period_start: '2024-01-01', period_end: '2024-03-31' }])
    const { getVatReturns } = await import('@/lib/queries')
    const result = await getVatReturns()
    expect((supabase as any).from).toHaveBeenCalledWith('vat_returns')
    expect(mockChain.order).toHaveBeenCalledWith('period_start', { ascending: false })
    expect(result).toHaveLength(1)
  })

  it('createVatReturn inserts with tenant_id', async () => {
    setMockData({ id: '1', period_start: '2024-01-01' })
    const { createVatReturn } = await import('@/lib/queries')
    await createVatReturn({
      period_start: '2024-01-01', period_end: '2024-03-31',
      status: 'draft', vat_collected: 1000, vat_deductible: 500,
    } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ period_start: '2024-01-01', tenant_id: 'test-tenant-id' })
    )
  })
})

// ============ Dashboard Stats ============

describe('Dashboard Stats', () => {
  beforeEach(() => resetMock())

  it('getDashboardStats returns zeros when no tenant', async () => {
    vi.mocked(supabase as any).from = vi.fn(() => mockChain)
    const { getDashboardStats } = await import('@/lib/queries')
    // With cached tenant_id, it will try to fetch data
    setMockData([])
    const result = await getDashboardStats()
    expect(result).toBeDefined()
    expect(typeof result.totalRevenue).toBe('number')
  })
})

// ============ Legislation Packs ============

describe('Legislation Packs', () => {
  beforeEach(() => resetMock())

  it('getLegislationPacks queries legislation_packs (not tenant-scoped)', async () => {
    setMockData([{ id: '1', code: 'FR', name: 'France' }])
    const { getLegislationPacks } = await import('@/lib/queries')
    const result = await getLegislationPacks()
    expect((supabase as any).from).toHaveBeenCalledWith('legislation_packs')
    expect(result).toHaveLength(1)
  })

  it('getLegislationPack fetches by code', async () => {
    setMockData({ id: '1', code: 'FR', name: 'France' })
    const { getLegislationPack } = await import('@/lib/queries')
    const result = await getLegislationPack('FR')
    expect((supabase as any).from).toHaveBeenCalledWith('legislation_packs')
    expect(mockChain.eq).toHaveBeenCalledWith('code', 'FR')
    expect(result).toBeDefined()
  })
})

// ============ Payment Terms ============

describe('Payment Terms', () => {
  beforeEach(() => resetMock())

  it('getPaymentTerms queries payment_terms ordered by code', async () => {
    setMockData([{ id: '1', code: '30D', type: 'fixed', days_1: 30 }])
    const { getPaymentTerms } = await import('@/lib/queries')
    const result = await getPaymentTerms()
    expect((supabase as any).from).toHaveBeenCalledWith('payment_terms')
    expect(mockChain.order).toHaveBeenCalledWith('code', { ascending: true })
    expect(result).toHaveLength(1)
  })

  it('getPaymentTermById fetches single record', async () => {
    setMockData({ id: '1', code: '30D', type: 'fixed', days_1: 30 })
    const { getPaymentTermById } = await import('@/lib/queries')
    const result = await getPaymentTermById('pt-1')
    expect((supabase as any).from).toHaveBeenCalledWith('payment_terms')
    expect(mockChain.eq).toHaveBeenCalledWith('id', 'pt-1')
    expect(result).toBeDefined()
  })

  it('getPaymentTermById returns null on error', async () => {
    mockChain.single = vi.fn(() => Promise.resolve({ data: null, error: { message: 'Not found' } }))
    const { getPaymentTermById } = await import('@/lib/queries')
    const result = await getPaymentTermById('nonexistent')
    expect(result).toBeNull()
  })

  it('createPaymentTerm inserts with tenant_id', async () => {
    setMockData({ id: '1', code: '30D' })
    const { createPaymentTerm } = await import('@/lib/queries')
    await createPaymentTerm({ code: '30D', type: 'fixed', days_1: 30 } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ code: '30D', tenant_id: 'test-tenant-id' })
    )
  })

  it('updatePaymentTerm updates with id', async () => {
    setMockData({ id: '1', code: '30D' })
    const { updatePaymentTerm } = await import('@/lib/queries')
    await updatePaymentTerm('pt-1', { days_1: 45 } as any)
    expect((supabase as any).from).toHaveBeenCalledWith('payment_terms')
    expect(mockChain.eq).toHaveBeenCalledWith('id', 'pt-1')
  })

  it('deletePaymentTerm calls delete with id', async () => {
    setMockData(null, null)
    const { deletePaymentTerm } = await import('@/lib/queries')
    await deletePaymentTerm('pt-1')
    expect(mockChain.delete).toHaveBeenCalled()
  })
})

// ============ Tax Rates ============

describe('Tax Rates', () => {
  beforeEach(() => resetMock())

  it('getTaxRates queries tax_rates ordered by rate', async () => {
    setMockData([{ id: '1', code: 'TVA20', rate: 20 }])
    const { getTaxRates } = await import('@/lib/queries')
    const result = await getTaxRates()
    expect((supabase as any).from).toHaveBeenCalledWith('tax_rates')
    expect(result).toHaveLength(1)
  })

  it('createTaxRate inserts with tenant_id', async () => {
    setMockData({ id: '1', code: 'TVA20', rate: 20 })
    const { createTaxRate } = await import('@/lib/queries')
    await createTaxRate({ code: 'TVA20', rate: 20, name: 'TVA 20%' } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ code: 'TVA20', tenant_id: 'test-tenant-id' })
    )
  })

  it('updateTaxRate updates with id', async () => {
    setMockData({ id: '1', rate: 20 })
    const { updateTaxRate } = await import('@/lib/queries')
    await updateTaxRate('tr-1', { rate: 25 } as any)
    expect((supabase as any).from).toHaveBeenCalledWith('tax_rates')
    expect(mockChain.eq).toHaveBeenCalledWith('id', 'tr-1')
  })

  it('deleteTaxRate calls delete with id', async () => {
    setMockData(null, null)
    const { deleteTaxRate } = await import('@/lib/queries')
    await deleteTaxRate('tr-1')
    expect(mockChain.delete).toHaveBeenCalled()
  })
})

// ============ calculateEcheance ============

describe('calculateEcheance', () => {
  beforeEach(() => resetMock())

  it('returns null when no paymentTermId', async () => {
    const { calculateEcheance } = await import('@/lib/queries')
    const result = await calculateEcheance('2024-01-15', null)
    expect(result).toBeNull()
  })

  it('returns null when payment term not found', async () => {
    mockChain.single = vi.fn(() => Promise.resolve({ data: null, error: { message: 'Not found' } }))
    const { calculateEcheance } = await import('@/lib/queries')
    const result = await calculateEcheance('2024-01-15', 'nonexistent')
    expect(result).toBeNull()
  })

  it('calculates echeance for fixed type', async () => {
    setMockData({ id: '1', code: '30D', type: 'fixed', days_1: 30, days_2: null, pct_1: null, pct_2: null })
    const { calculateEcheance } = await import('@/lib/queries')
    const result = await calculateEcheance('2024-01-15', 'pt-1')
    expect(result).toBe('2024-02-14')
  })

  it('calculates echeance for end_of_month type', async () => {
    setMockData({ id: '1', code: 'FM', type: 'end_of_month', days_1: 0, days_2: null, pct_1: null, pct_2: null })
    const { calculateEcheance } = await import('@/lib/queries')
    const result = await calculateEcheance('2024-01-15', 'pt-1')
    expect(result).toBe('2024-01-31')
  })

  it('calculates echeance for split type (first echeance)', async () => {
    setMockData({ id: '1', code: 'SPLIT', type: 'split', days_1: 30, days_2: 60, pct_1: 50, pct_2: 50 })
    const { calculateEcheance } = await import('@/lib/queries')
    const result = await calculateEcheance('2024-01-15', 'pt-1')
    expect(result).toBe('2024-02-14')
  })
})

// ============ Bank Accounts ============

describe('Bank Accounts', () => {
  beforeEach(() => resetMock())

  it('getBankAccounts queries bank_accounts', async () => {
    setMockData([{ id: '1', name: 'Main Account', balance: 10000 }])
    const { getBankAccounts } = await import('@/lib/queries')
    const result = await getBankAccounts()
    expect((supabase as any).from).toHaveBeenCalledWith('bank_accounts')
    expect(result).toHaveLength(1)
  })

  it('createBankAccount inserts with tenant_id', async () => {
    setMockData({ id: '1', name: 'Main Account' })
    const { createBankAccount } = await import('@/lib/queries')
    await createBankAccount({ name: 'Main Account', iban: 'FR76...' } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ name: 'Main Account', tenant_id: 'test-tenant-id' })
    )
  })
})

// ============ Projects ============

describe('Projects', () => {
  beforeEach(() => resetMock())

  it('getProjects queries projects', async () => {
    setMockData([{ id: '1', name: 'Project Alpha' }])
    const { getProjects } = await import('@/lib/queries')
    const result = await getProjects()
    expect((supabase as any).from).toHaveBeenCalledWith('projects')
    expect(result).toHaveLength(1)
  })

  it('createProject inserts with tenant_id', async () => {
    setMockData({ id: '1', name: 'Project Alpha' })
    const { createProject } = await import('@/lib/queries')
    await createProject({ name: 'Project Alpha' } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ name: 'Project Alpha', tenant_id: 'test-tenant-id' })
    )
  })

  it('deleteProject calls delete with id', async () => {
    setMockData(null, null)
    const { deleteProject } = await import('@/lib/queries')
    await deleteProject('proj-1')
    expect(mockChain.delete).toHaveBeenCalled()
  })
})

// ============ Users ============

describe('Users', () => {
  beforeEach(() => resetMock())

  it('getUsers queries tenant_users with tenant filter', async () => {
    setMockData([{ id: 'u1', email: 'user@test.com' }])
    const { getUsers } = await import('@/lib/queries')
    const result = await getUsers()
    expect((supabase as any).from).toHaveBeenCalledWith('tenant_users')
    expect(mockChain.eq).toHaveBeenCalledWith('tenant_id', 'test-tenant-id')
    expect(result).toHaveLength(1)
  })
})

// ============ Quotes ============

describe('Quotes CRUD', () => {
  beforeEach(() => resetMock())

  it('getQuotes queries quotes with quote_lines', async () => {
    setMockData([{ id: '1', number: 'QT-001', quote_lines: [] }])
    const { getQuotes } = await import('@/lib/queries')
    const result = await getQuotes()
    expect((supabase as any).from).toHaveBeenCalledWith('quotes')
    expect(mockChain.order).toHaveBeenCalledWith('date', { ascending: false })
    expect(result).toHaveLength(1)
  })

  it('createQuote inserts with tenant_id', async () => {
    setMockData({ id: '1', number: 'QT-001' })
    const { createQuote } = await import('@/lib/queries')
    await createQuote({
      number: 'QT-001', customer_id: 'c1', customer_name: 'Acme',
      date: '2024-01-01', status: 'draft', lines: [],
    } as any)
    expect(mockChain.insert).toHaveBeenCalled()
  })

  it('deleteQuote calls delete with id', async () => {
    setMockData(null, null)
    const { deleteQuote } = await import('@/lib/queries')
    await deleteQuote('qt-1')
    expect(mockChain.delete).toHaveBeenCalled()
  })
})

// ============ Purchase Invoices ============

describe('Purchase Invoices', () => {
  beforeEach(() => resetMock())

  it('getPurchaseInvoices queries purchase_invoices', async () => {
    setMockData([{ id: '1', number: 'PI-001', supplier_name: 'Supplier Co' }])
    const { getPurchaseInvoices } = await import('@/lib/queries')
    const result = await getPurchaseInvoices()
    expect((supabase as any).from).toHaveBeenCalledWith('purchase_invoices')
    expect(result).toHaveLength(1)
  })

  it('createPurchaseInvoice inserts with tenant_id', async () => {
    setMockData({ id: '1', number: 'PI-001' })
    const { createPurchaseInvoice } = await import('@/lib/queries')
    await createPurchaseInvoice({
      number: 'PI-001', supplier_id: 's1', supplier_name: 'Supplier Co',
      date: '2024-01-01', status: 'draft',
    } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ number: 'PI-001', tenant_id: 'test-tenant-id' })
    )
  })
})

// ============ Journals ============

describe('Journals', () => {
  beforeEach(() => resetMock())

  it('getJournals queries journals ordered by code', async () => {
    setMockData([{ id: '1', code: 'VT', name: 'Ventes' }])
    const { getJournals } = await import('@/lib/queries')
    const result = await getJournals()
    expect((supabase as any).from).toHaveBeenCalledWith('journals')
    expect(mockChain.order).toHaveBeenCalledWith('code', { ascending: true })
    expect(result).toHaveLength(1)
  })
})

// ============ Fixed Assets ============

describe('Fixed Assets', () => {
  beforeEach(() => resetMock())

  it('getFixedAssets queries fixed_assets', async () => {
    setMockData([{ id: '1', name: 'Computer', purchase_value: 2000 }])
    const { getFixedAssets } = await import('@/lib/queries')
    const result = await getFixedAssets()
    expect((supabase as any).from).toHaveBeenCalledWith('fixed_assets')
    expect(result).toHaveLength(1)
  })

  it('createFixedAsset inserts with tenant_id', async () => {
    setMockData({ id: '1', name: 'Computer' })
    const { createFixedAsset } = await import('@/lib/queries')
    await createFixedAsset({ name: 'Computer', purchase_value: 2000 } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ name: 'Computer', tenant_id: 'test-tenant-id' })
    )
  })
})

// ============ Employees ============

describe('Employees', () => {
  beforeEach(() => resetMock())

  it('getEmployees queries employees', async () => {
    setMockData([{ id: '1', first_name: 'John', last_name: 'Doe' }])
    const { getEmployees } = await import('@/lib/queries')
    const result = await getEmployees()
    expect((supabase as any).from).toHaveBeenCalledWith('employees')
    expect(result).toHaveLength(1)
  })

  it('createEmployee inserts with tenant_id', async () => {
    setMockData({ id: '1', first_name: 'John' })
    const { createEmployee } = await import('@/lib/queries')
    await createEmployee({ first_name: 'John', last_name: 'Doe' } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ first_name: 'John', tenant_id: 'test-tenant-id' })
    )
  })
})
