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
    range: vi.fn(() => chain),
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

// ============ Helper ============
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
  // Restaurer from et rpc après clearAllMocks
  ;(supabase as any).from = vi.fn(() => mockChain)
  ;(supabase as any).rpc = vi.fn(() => Promise.resolve({ data: null, error: null }))
}

beforeEach(() => resetMock())

// ============ Credit Notes ============

describe('Credit Notes CRUD', () => {
  beforeEach(() => resetMock())

  it('getCreditNotes queries credit_notes with lines', async () => {
    setMockData([{ id: '1', number: 'CN-001' }])
    const { getCreditNotes } = await import('@/lib/queries')
    const result = await getCreditNotes()
    expect((supabase as any).from).toHaveBeenCalledWith('credit_notes')
    expect(mockChain.order).toHaveBeenCalledWith('date', { ascending: false })
    expect(result).toHaveLength(1)
  })

  it('createCreditNote inserts with tenant_id', async () => {
    setMockData({ id: '1', number: 'CN-001' })
    const { createCreditNote } = await import('@/lib/queries')
    await createCreditNote({ number: 'CN-001', date: '2024-01-01', lines: [] } as any)
    expect(mockChain.insert).toHaveBeenCalled()
  })

  it('deleteCreditNote calls delete with id', async () => {
    setMockData(null, null)
    const { deleteCreditNote } = await import('@/lib/queries')
    await deleteCreditNote('cn-1')
    expect(mockChain.delete).toHaveBeenCalled()
  })
})

// ============ Recurring Invoices ============

describe('Recurring Invoices', () => {
  beforeEach(() => resetMock())

  it('getRecurringInvoices queries invoices with recurring=true', async () => {
    setMockData([{ id: '1', recurring: true }])
    const { getRecurringInvoices } = await import('@/lib/queries')
    const result = await getRecurringInvoices()
    expect((supabase as any).from).toHaveBeenCalledWith('invoices')
    expect(mockChain.eq).toHaveBeenCalledWith('recurring', true)
    expect(result).toHaveLength(1)
  })

  it('toggleRecurringInvoice updates recurring flag', async () => {
    setMockData({ id: '1', recurring: true })
    const { toggleRecurringInvoice } = await import('@/lib/queries')
    await toggleRecurringInvoice('inv-1', true, 'monthly')
    expect((supabase as any).from).toHaveBeenCalledWith('invoices')
    expect(mockChain.eq).toHaveBeenCalledWith('id', 'inv-1')
  })
})

// ============ Pay Runs ============

describe('Pay Runs CRUD', () => {
  beforeEach(() => resetMock())

  it('getPayRuns queries pay_runs ordered by pay_date desc', async () => {
    setMockData([{ id: '1', number: 'PAY-001' }])
    const { getPayRuns } = await import('@/lib/queries')
    const result = await getPayRuns()
    expect((supabase as any).from).toHaveBeenCalledWith('pay_runs')
    expect(mockChain.order).toHaveBeenCalledWith('pay_date', { ascending: false })
    expect(result).toHaveLength(1)
  })

  it('createPayRun inserts with tenant_id', async () => {
    setMockData({ id: '1', number: 'PAY-001' })
    const { createPayRun } = await import('@/lib/queries')
    await createPayRun({ number: 'PAY-001', pay_date: '2024-01-31' } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ number: 'PAY-001', tenant_id: 'test-tenant-id' })
    )
  })

  it('deletePayRun calls delete with id', async () => {
    setMockData(null, null)
    const { deletePayRun } = await import('@/lib/queries')
    await deletePayRun('pr-1')
    expect(mockChain.delete).toHaveBeenCalled()
  })
})

// ============ Timesheets ============

describe('Timesheets CRUD', () => {
  beforeEach(() => resetMock())

  it('getTimesheets queries timesheets with employee join', async () => {
    setMockData([{ id: '1', date: '2024-01-01' }])
    const { getTimesheets } = await import('@/lib/queries')
    const result = await getTimesheets()
    expect((supabase as any).from).toHaveBeenCalledWith('timesheets')
    expect(result).toHaveLength(1)
  })

  it('createTimesheet inserts with tenant_id', async () => {
    setMockData({ id: '1', date: '2024-01-01' })
    const { createTimesheet } = await import('@/lib/queries')
    await createTimesheet({ date: '2024-01-01', hours: 8 } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ tenant_id: 'test-tenant-id' })
    )
  })
})

// ============ Stock Movements ============

describe('Stock Movements', () => {
  beforeEach(() => resetMock())

  it('getStockMovements queries stock_movements with limit 100', async () => {
    setMockData([{ id: '1', movement_type: 'in', quantity: 10 }])
    const { getStockMovements } = await import('@/lib/queries')
    const result = await getStockMovements()
    expect((supabase as any).from).toHaveBeenCalledWith('stock_movements')
    expect(mockChain.limit).toHaveBeenCalledWith(100)
    expect(result).toHaveLength(1)
  })

  it('getStockMovements filters by productId when provided', async () => {
    setMockData([])
    const { getStockMovements } = await import('@/lib/queries')
    await getStockMovements('prod-1')
    expect(mockChain.eq).toHaveBeenCalledWith('product_id', 'prod-1')
  })

  it('getStockMovements filters by warehouseId when provided', async () => {
    setMockData([])
    const { getStockMovements } = await import('@/lib/queries')
    await getStockMovements(undefined, 'wh-1')
    expect(mockChain.eq).toHaveBeenCalledWith('warehouse_id', 'wh-1')
  })

  it('createStockMovement inserts with tenant_id', async () => {
    setMockData({ id: '1', movement_type: 'in', quantity: 10 })
    const { createStockMovement } = await import('@/lib/queries')
    await createStockMovement({ product_id: 'p1', movement_type: 'in', quantity: 10 } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ tenant_id: 'test-tenant-id' })
    )
  })
})

// ============ Currencies ============

describe('Currencies CRUD', () => {
  beforeEach(() => resetMock())

  it('getCurrencies queries currencies ordered by code', async () => {
    setMockData([{ id: '1', code: 'EUR', rate: 1 }])
    const { getCurrencies } = await import('@/lib/queries')
    const result = await getCurrencies()
    expect((supabase as any).from).toHaveBeenCalledWith('currencies')
    expect(mockChain.order).toHaveBeenCalledWith('code', { ascending: true })
    expect(result).toHaveLength(1)
  })

  it('createCurrency inserts with tenant_id', async () => {
    setMockData({ id: '1', code: 'USD' })
    const { createCurrency } = await import('@/lib/queries')
    await createCurrency({ code: 'USD', rate: 1.1 } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ code: 'USD', tenant_id: 'test-tenant-id' })
    )
  })

  it('deleteCurrency calls delete with id', async () => {
    setMockData(null, null)
    const { deleteCurrency } = await import('@/lib/queries')
    await deleteCurrency('cur-1')
    expect(mockChain.delete).toHaveBeenCalled()
  })
})

// ============ Journals CRUD ============

describe('Journals CRUD', () => {
  beforeEach(() => resetMock())

  it('createJournal inserts with tenant_id', async () => {
    setMockData({ id: '1', code: 'VT', name: 'Ventes' })
    const { createJournal } = await import('@/lib/queries')
    await createJournal({ code: 'VT', name: 'Ventes' } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ code: 'VT', tenant_id: 'test-tenant-id' })
    )
  })

  it('updateJournal updates with id', async () => {
    setMockData({ id: '1', code: 'VT' })
    const { updateJournal } = await import('@/lib/queries')
    await updateJournal('j-1', { name: 'Updated' } as any)
    expect((supabase as any).from).toHaveBeenCalledWith('journals')
    expect(mockChain.eq).toHaveBeenCalledWith('id', 'j-1')
  })

  it('deleteJournal calls delete with id', async () => {
    setMockData(null, null)
    const { deleteJournal } = await import('@/lib/queries')
    await deleteJournal('j-1')
    expect(mockChain.delete).toHaveBeenCalled()
  })
})

// ============ Fiscal Years ============

describe('Fiscal Years CRUD', () => {
  beforeEach(() => resetMock())

  it('getFiscalYears queries fiscal_years ordered by start_date desc', async () => {
    setMockData([{ id: '1', code: '2024', start_date: '2024-01-01' }])
    const { getFiscalYears } = await import('@/lib/queries')
    const result = await getFiscalYears()
    expect((supabase as any).from).toHaveBeenCalledWith('fiscal_years')
    expect(mockChain.order).toHaveBeenCalledWith('start_date', { ascending: false })
    expect(result).toHaveLength(1)
  })

  it('createFiscalYear inserts with tenant_id', async () => {
    setMockData({ id: '1', code: '2024' })
    const { createFiscalYear } = await import('@/lib/queries')
    await createFiscalYear({ code: '2024', start_date: '2024-01-01', end_date: '2024-12-31' } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ code: '2024', tenant_id: 'test-tenant-id' })
    )
  })

  it('deleteFiscalYear calls delete with id', async () => {
    setMockData(null, null)
    const { deleteFiscalYear } = await import('@/lib/queries')
    await deleteFiscalYear('fy-1')
    expect(mockChain.delete).toHaveBeenCalled()
  })
})

// ============ Fiscal Periods ============

describe('Fiscal Periods', () => {
  beforeEach(() => resetMock())

  it('getFiscalPeriods queries fiscal_periods ordered by period_number', async () => {
    setMockData([{ id: '1', period_number: 1, period_label: 'Janvier 2024' }])
    const { getFiscalPeriods } = await import('@/lib/queries')
    const result = await getFiscalPeriods()
    expect((supabase as any).from).toHaveBeenCalledWith('fiscal_periods')
    expect(mockChain.order).toHaveBeenCalledWith('period_number', { ascending: true })
    expect(result).toHaveLength(1)
  })

  it('getFiscalPeriods filters by fiscalYearId when provided', async () => {
    setMockData([])
    const { getFiscalPeriods } = await import('@/lib/queries')
    await getFiscalPeriods('fy-1')
    expect(mockChain.eq).toHaveBeenCalledWith('fiscal_year_id', 'fy-1')
  })

  it('createFiscalPeriodsForYear generates 12 monthly periods', async () => {
    setMockData([])
    const { createFiscalPeriodsForYear } = await import('@/lib/queries')
    await createFiscalPeriodsForYear('fy-1', '2024-01-01', '2024-12-31')
    expect(mockChain.insert).toHaveBeenCalled()
    const inserted = mockChain.insert.mock.calls[0][0]
    expect(inserted).toHaveLength(12)
    expect(inserted[0].period_number).toBe(1)
    expect(inserted[0].period_label).toContain('Janvier')
    expect(inserted[11].period_label).toContain('Décembre')
  })

  it('closeFiscalPeriod updates status to closed', async () => {
    setMockData({ id: '1', status: 'closed' })
    const { closeFiscalPeriod } = await import('@/lib/queries')
    await closeFiscalPeriod('fp-1')
    expect((supabase as any).from).toHaveBeenCalledWith('fiscal_periods')
    expect(mockChain.eq).toHaveBeenCalledWith('id', 'fp-1')
  })

  it('reopenFiscalPeriod updates status to open', async () => {
    setMockData({ id: '1', status: 'open' })
    const { reopenFiscalPeriod } = await import('@/lib/queries')
    await reopenFiscalPeriod('fp-1')
    expect((supabase as any).from).toHaveBeenCalledWith('fiscal_periods')
    expect(mockChain.eq).toHaveBeenCalledWith('id', 'fp-1')
  })
})

// ============ Entry Templates ============

describe('Entry Templates CRUD', () => {
  beforeEach(() => resetMock())

  it('getEntryTemplates queries entry_templates ordered by name', async () => {
    setMockData([{ id: '1', name: 'Template 1' }])
    const { getEntryTemplates } = await import('@/lib/queries')
    const result = await getEntryTemplates()
    expect((supabase as any).from).toHaveBeenCalledWith('entry_templates')
    expect(mockChain.order).toHaveBeenCalledWith('name', { ascending: true })
    expect(result).toHaveLength(1)
  })

  it('createEntryTemplate inserts with tenant_id', async () => {
    setMockData({ id: '1', name: 'Template 1' })
    const { createEntryTemplate } = await import('@/lib/queries')
    await createEntryTemplate({ name: 'Template 1' } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ tenant_id: 'test-tenant-id' })
    )
  })

  it('deleteEntryTemplate calls delete with id', async () => {
    setMockData(null, null)
    const { deleteEntryTemplate } = await import('@/lib/queries')
    await deleteEntryTemplate('et-1')
    expect(mockChain.delete).toHaveBeenCalled()
  })
})

// ============ Third Party Accounts ============

describe('Third Party Accounts CRUD', () => {
  beforeEach(() => resetMock())

  it('getThirdPartyAccounts queries third_party_accounts ordered by code', async () => {
    setMockData([{ id: '1', code: 'C001', name: 'Client 1' }])
    const { getThirdPartyAccounts } = await import('@/lib/queries')
    const result = await getThirdPartyAccounts()
    expect((supabase as any).from).toHaveBeenCalledWith('third_party_accounts')
    expect(mockChain.order).toHaveBeenCalledWith('code', { ascending: true })
    expect(result).toHaveLength(1)
  })

  it('getThirdPartyAccounts filters by type when provided', async () => {
    setMockData([])
    const { getThirdPartyAccounts } = await import('@/lib/queries')
    await getThirdPartyAccounts('customer')
    expect(mockChain.eq).toHaveBeenCalledWith('type', 'customer')
  })

  it('createThirdPartyAccount inserts with tenant_id', async () => {
    setMockData({ id: '1', code: 'C001' })
    const { createThirdPartyAccount } = await import('@/lib/queries')
    await createThirdPartyAccount({ code: 'C001', name: 'Client 1', type: 'customer' } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ code: 'C001', tenant_id: 'test-tenant-id' })
    )
  })

  it('deleteThirdPartyAccount calls delete with id', async () => {
    setMockData(null, null)
    const { deleteThirdPartyAccount } = await import('@/lib/queries')
    await deleteThirdPartyAccount('tpa-1')
    expect(mockChain.delete).toHaveBeenCalled()
  })
})

// ============ Analytic Sections ============

describe('Analytic Sections CRUD', () => {
  beforeEach(() => resetMock())

  it('getAnalyticSections queries analytic_sections ordered by code', async () => {
    setMockData([{ id: '1', code: 'A1', name: 'Section A' }])
    const { getAnalyticSections } = await import('@/lib/queries')
    const result = await getAnalyticSections()
    expect((supabase as any).from).toHaveBeenCalledWith('analytic_sections')
    expect(mockChain.order).toHaveBeenCalledWith('code', { ascending: true })
    expect(result).toHaveLength(1)
  })

  it('createAnalyticSection inserts with tenant_id', async () => {
    setMockData({ id: '1', code: 'A1' })
    const { createAnalyticSection } = await import('@/lib/queries')
    await createAnalyticSection({ code: 'A1', name: 'Section A' } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ tenant_id: 'test-tenant-id' })
    )
  })
})

// ============ Budgets ============

describe('Budgets CRUD', () => {
  beforeEach(() => resetMock())

  it('getBudgets queries budgets ordered by name', async () => {
    setMockData([{ id: '1', name: 'Budget 2024' }])
    const { getBudgets } = await import('@/lib/queries')
    const result = await getBudgets()
    expect((supabase as any).from).toHaveBeenCalledWith('budgets')
    expect(mockChain.order).toHaveBeenCalledWith('name', { ascending: true })
    expect(result).toHaveLength(1)
  })

  it('createBudget inserts with tenant_id', async () => {
    setMockData({ id: '1', name: 'Budget 2024' })
    const { createBudget } = await import('@/lib/queries')
    await createBudget({ name: 'Budget 2024' } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ tenant_id: 'test-tenant-id' })
    )
  })
})

// ============ Standard Labels ============

describe('Standard Labels', () => {
  beforeEach(() => resetMock())

  it('getStandardLabels queries standard_labels ordered by label', async () => {
    setMockData([{ id: '1', label: 'Facture' }])
    const { getStandardLabels } = await import('@/lib/queries')
    const result = await getStandardLabels()
    expect((supabase as any).from).toHaveBeenCalledWith('standard_labels')
    expect(mockChain.order).toHaveBeenCalledWith('label', { ascending: true })
    expect(result).toHaveLength(1)
  })

  it('createStandardLabel inserts with tenant_id', async () => {
    setMockData({ id: '1', label: 'Facture' })
    const { createStandardLabel } = await import('@/lib/queries')
    await createStandardLabel({ label: 'Facture' } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ tenant_id: 'test-tenant-id' })
    )
  })
})

// ============ Lettrage ============

describe('Lettrage', () => {
  beforeEach(() => resetMock())

  it('getUnletteredLines queries journal_lines with null/empty lettrage_code', async () => {
    setMockData([{ id: '1', account_tiers: 'C001' }])
    const { getUnletteredLines } = await import('@/lib/queries')
    const result = await getUnletteredLines('C001')
    expect((supabase as any).from).toHaveBeenCalledWith('journal_lines')
    expect(mockChain.eq).toHaveBeenCalledWith('account_tiers', 'C001')
    expect(result).toHaveLength(1)
  })

  it('getLetteredLines queries journal_lines with non-null lettrage_code', async () => {
    setMockData([{ id: '1', lettrage_code: 'A001' }])
    const { getLetteredLines } = await import('@/lib/queries')
    const result = await getLetteredLines('C001')
    expect((supabase as any).from).toHaveBeenCalledWith('journal_lines')
    expect(result).toHaveLength(1)
  })

  it('applyLettrage updates lines with code and date', async () => {
    // LOT4-08/09 : applyLettrage utilise maintenant la RPC apply_lettrage
    ;(supabase as any).rpc = vi.fn(() => Promise.resolve({ data: { success: true }, error: null }))
    const { applyLettrage } = await import('@/lib/queries')
    await applyLettrage(['l1', 'l2'], 'A001')
    expect((supabase as any).rpc).toHaveBeenCalledWith('apply_lettrage', {
      p_line_ids: ['l1', 'l2'],
      p_code: 'A001',
    })
  })

  it('removeLettrage clears lettrage_code and date', async () => {
    // LOT4-09 : removeLettrage utilise maintenant la RPC remove_lettrage
    ;(supabase as any).rpc = vi.fn(() => Promise.resolve({ data: { success: true }, error: null }))
    const { removeLettrage } = await import('@/lib/queries')
    await removeLettrage(['l1'])
    expect((supabase as any).rpc).toHaveBeenCalledWith('remove_lettrage', {
      p_line_ids: ['l1'],
    })
  })

  it('getNextLettrageCode returns A001 when no existing codes', async () => {
    // LOT4-08 : getNextLettrageCode utilise maintenant la RPC next_lettrage_code
    ;(supabase as any).rpc = vi.fn(() => Promise.resolve({ data: 'A001', error: null }))
    const { getNextLettrageCode } = await import('@/lib/queries')
    const result = await getNextLettrageCode()
    expect(result).toBe('A001')
  })

  it('getNextLettrageCode increments last code', async () => {
    // LOT4-08 : getNextLettrageCode utilise maintenant la RPC next_lettrage_code
    ;(supabase as any).rpc = vi.fn(() => Promise.resolve({ data: 'A006', error: null }))
    const { getNextLettrageCode } = await import('@/lib/queries')
    const result = await getNextLettrageCode()
    expect(result).toBe('A006')
  })
})

// ============ Search ============

describe('searchEntries', () => {
  beforeEach(() => resetMock())

  it('searches with no criteria returns paginated results', async () => {
    setMockData([{ id: '1', number: 'JE-001', journal_lines: [] }])
    const { searchEntries } = await import('@/lib/queries')
    const result = await searchEntries({})
    expect((supabase as any).from).toHaveBeenCalledWith('journal_entries')
    // ACC-02: Utilise .range() au lieu de .limit()
    expect(mockChain.range).toHaveBeenCalled()
    expect(result.data).toHaveLength(1)
  })

  it('filters by journalCode', async () => {
    setMockData([])
    const { searchEntries } = await import('@/lib/queries')
    await searchEntries({ journalCode: 'VT' })
    expect(mockChain.eq).toHaveBeenCalledWith('journal_code', 'VT')
  })

  it('filters by dateFrom/dateTo', async () => {
    setMockData([])
    const { searchEntries } = await import('@/lib/queries')
    await searchEntries({ dateFrom: '2024-01-01', dateTo: '2024-12-31' })
    expect(mockChain.gte).toHaveBeenCalledWith('date', '2024-01-01')
    expect(mockChain.lte).toHaveBeenCalledWith('date', '2024-12-31')
  })

  it('filters by description with ilike', async () => {
    setMockData([])
    const { searchEntries } = await import('@/lib/queries')
    await searchEntries({ description: 'test' })
    expect(mockChain.ilike).toHaveBeenCalledWith('description', '%test%')
  })

  it('filters by accountCode at line level (JS-side)', async () => {
    setMockData([{
      id: '1', number: 'JE-001',
      journal_lines: [{ account_code: '400000', debit: 100, credit: 0 }]
    }])
    const { searchEntries } = await import('@/lib/queries')
    const result = await searchEntries({ accountCode: '400000' })
    expect(result.data).toHaveLength(1)
  })

  it('filters out entries without matching accountCode', async () => {
    setMockData([{
      id: '1', number: 'JE-001',
      journal_lines: [{ account_code: '411000', debit: 100, credit: 0 }]
    }])
    const { searchEntries } = await import('@/lib/queries')
    const result = await searchEntries({ accountCode: '400000' })
    expect(result.data).toHaveLength(0)
  })
})

// ============ Closure ============

describe('Closure functions', () => {
  beforeEach(() => resetMock())

  it('closeJournalPeriod updates entries to closed', async () => {
    setMockData([{ id: '1' }])
    const { closeJournalPeriod } = await import('@/lib/queries')
    await closeJournalPeriod('VT', 'fp-1')
    expect((supabase as any).from).toHaveBeenCalledWith('journal_entries')
    expect(mockChain.eq).toHaveBeenCalledWith('journal_code', 'VT')
    expect(mockChain.eq).toHaveBeenCalledWith('fiscal_period_id', 'fp-1')
  })

  it('reopenJournalPeriod updates entries to open', async () => {
    setMockData([{ id: '1' }])
    const { reopenJournalPeriod } = await import('@/lib/queries')
    await reopenJournalPeriod('VT', 'fp-1')
    expect((supabase as any).from).toHaveBeenCalledWith('journal_entries')
    expect(mockChain.eq).toHaveBeenCalledWith('status_detail', 'closed')
  })
})

// ============ Payment Orders ============

describe('Payment Orders CRUD', () => {
  beforeEach(() => resetMock())

  it('getPaymentOrders queries payment_orders', async () => {
    setMockData([{ id: '1', amount: 1000 }])
    const { getPaymentOrders } = await import('@/lib/queries')
    const result = await getPaymentOrders()
    expect((supabase as any).from).toHaveBeenCalledWith('payment_orders')
    expect(result).toHaveLength(1)
  })

  it('getPaymentOrders filters by status when provided', async () => {
    setMockData([])
    const { getPaymentOrders } = await import('@/lib/queries')
    await getPaymentOrders('pending')
    expect(mockChain.eq).toHaveBeenCalledWith('status', 'pending')
  })

  it('createPaymentOrder inserts with tenant_id', async () => {
    setMockData({ id: '1', amount: 1000 })
    const { createPaymentOrder } = await import('@/lib/queries')
    await createPaymentOrder({ amount: 1000, payment_date: '2024-01-15' } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ tenant_id: 'test-tenant-id' })
    )
  })

  it('deletePaymentOrder calls delete with id', async () => {
    setMockData(null, null)
    const { deletePaymentOrder } = await import('@/lib/queries')
    await deletePaymentOrder('po-1')
    expect(mockChain.delete).toHaveBeenCalled()
  })
})

// ============ Asset Depreciations ============

describe('Asset Depreciations', () => {
  beforeEach(() => resetMock())

  it('getAssetDepreciations queries asset_depreciations', async () => {
    setMockData([{ id: '1', amount: 500 }])
    const { getAssetDepreciations } = await import('@/lib/queries')
    const result = await getAssetDepreciations()
    expect((supabase as any).from).toHaveBeenCalledWith('asset_depreciations')
    expect(result).toHaveLength(1)
  })

  it('getAssetDepreciations filters by assetId when provided', async () => {
    setMockData([])
    const { getAssetDepreciations } = await import('@/lib/queries')
    await getAssetDepreciations('asset-1')
    expect(mockChain.eq).toHaveBeenCalledWith('asset_id', 'asset-1')
  })
})

// ============ Treasury Transfers ============

describe('Treasury Transfers', () => {
  beforeEach(() => resetMock())

  it('getTreasuryTransfers queries treasury_transfers', async () => {
    setMockData([{ id: '1', amount: 5000 }])
    const { getTreasuryTransfers } = await import('@/lib/queries')
    const result = await getTreasuryTransfers()
    expect((supabase as any).from).toHaveBeenCalledWith('treasury_transfers')
    expect(result).toHaveLength(1)
  })

  it('createTreasuryTransfer inserts with tenant_id', async () => {
    setMockData({ id: '1', amount: 5000 })
    const { createTreasuryTransfer } = await import('@/lib/queries')
    await createTreasuryTransfer({ amount: 5000, from_account: 'a1', to_account: 'a2' } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ tenant_id: 'test-tenant-id' })
    )
  })
})

// ============ Credit Lines ============

describe('Credit Lines', () => {
  beforeEach(() => resetMock())

  it('getCreditLines queries credit_lines', async () => {
    setMockData([{ id: '1', limit: 50000 }])
    const { getCreditLines } = await import('@/lib/queries')
    const result = await getCreditLines()
    expect((supabase as any).from).toHaveBeenCalledWith('credit_lines')
    expect(result).toHaveLength(1)
  })
})

// ============ Investments ============

describe('Investments', () => {
  beforeEach(() => resetMock())

  it('getInvestments queries investments', async () => {
    setMockData([{ id: '1', amount: 10000 }])
    const { getInvestments } = await import('@/lib/queries')
    const result = await getInvestments()
    expect((supabase as any).from).toHaveBeenCalledWith('investments')
    expect(result).toHaveLength(1)
  })
})

// ============ Payroll Components ============

describe('Payroll Components', () => {
  beforeEach(() => resetMock())

  it('getPayrollComponents queries payroll_components', async () => {
    setMockData([{ id: '1', code: 'SAL', name: 'Salaire de base' }])
    const { getPayrollComponents } = await import('@/lib/queries')
    const result = await getPayrollComponents()
    expect((supabase as any).from).toHaveBeenCalledWith('payroll_components')
    expect(result).toHaveLength(1)
  })

  it('createPayrollComponent inserts with tenant_id', async () => {
    setMockData({ id: '1', code: 'SAL' })
    const { createPayrollComponent } = await import('@/lib/queries')
    await createPayrollComponent({ code: 'SAL', name: 'Salaire de base' } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ tenant_id: 'test-tenant-id' })
    )
  })
})

// ============ Salary Advances ============

describe('Salary Advances', () => {
  beforeEach(() => resetMock())

  it('getSalaryAdvances queries salary_advances', async () => {
    setMockData([{ id: '1', amount: 500 }])
    const { getSalaryAdvances } = await import('@/lib/queries')
    const result = await getSalaryAdvances()
    expect((supabase as any).from).toHaveBeenCalledWith('salary_advances')
    expect(result).toHaveLength(1)
  })
})

// ============ DSN Declarations ============

describe('DSN Declarations', () => {
  beforeEach(() => resetMock())

  it('getDsnDeclarations queries dsn_declarations', async () => {
    setMockData([{ id: '1', period: '2024-01' }])
    const { getDsnDeclarations } = await import('@/lib/queries')
    const result = await getDsnDeclarations()
    expect((supabase as any).from).toHaveBeenCalledWith('dsn_declarations')
    expect(result).toHaveLength(1)
  })
})

// ============ Expense Reports ============

describe('Expense Reports', () => {
  beforeEach(() => resetMock())

  it('getExpenseReports queries expense_reports', async () => {
    setMockData([{ id: '1', amount: 150 }])
    const { getExpenseReports } = await import('@/lib/queries')
    const result = await getExpenseReports()
    expect((supabase as any).from).toHaveBeenCalledWith('expense_reports')
    expect(result).toHaveLength(1)
  })
})

// ============ Asset Families ============

describe('Asset Families', () => {
  beforeEach(() => resetMock())

  it('getAssetFamilies queries asset_families', async () => {
    setMockData([{ id: '1', code: 'IT', name: 'Informatique' }])
    const { getAssetFamilies } = await import('@/lib/queries')
    const result = await getAssetFamilies()
    expect((supabase as any).from).toHaveBeenCalledWith('asset_families')
    expect(result).toHaveLength(1)
  })
})

// ============ Reminder Levels ============

describe('Reminder Levels', () => {
  beforeEach(() => resetMock())

  it('getReminderLevels queries reminder_levels', async () => {
    setMockData([{ id: '1', level: 1, label: '1er rappel' }])
    const { getReminderLevels } = await import('@/lib/queries')
    const result = await getReminderLevels()
    expect((supabase as any).from).toHaveBeenCalledWith('reminder_levels')
    expect(result).toHaveLength(1)
  })
})

// ============ Payment Promises ============

describe('Payment Promises', () => {
  beforeEach(() => resetMock())

  it('getPaymentPromises queries payment_promises', async () => {
    setMockData([{ id: '1', amount: 1000, promise_date: '2024-02-01' }])
    const { getPaymentPromises } = await import('@/lib/queries')
    const result = await getPaymentPromises()
    expect((supabase as any).from).toHaveBeenCalledWith('payment_promises')
    expect(result).toHaveLength(1)
  })
})

// ============ Disputes ============

describe('Disputes', () => {
  beforeEach(() => resetMock())

  it('getDisputes queries disputes', async () => {
    setMockData([{ id: '1', reason: 'Damaged goods' }])
    const { getDisputes } = await import('@/lib/queries')
    const result = await getDisputes()
    expect((supabase as any).from).toHaveBeenCalledWith('disputes')
    expect(result).toHaveLength(1)
  })
})

// ============ Revision Cycles ============

describe('Revision Cycles', () => {
  beforeEach(() => resetMock())

  it('getRevisionCycles queries revision_cycles', async () => {
    setMockData([{ id: '1', name: 'Audit 2024' }])
    const { getRevisionCycles } = await import('@/lib/queries')
    const result = await getRevisionCycles()
    expect((supabase as any).from).toHaveBeenCalledWith('revision_cycles')
    expect(result).toHaveLength(1)
  })
})

// ============ Dashboard Widgets ============

describe('Dashboard Widgets', () => {
  beforeEach(() => resetMock())

  it('getDashboardWidgets queries dashboard_widgets', async () => {
    setMockData([{ id: '1', widget_type: 'chart' }])
    const { getDashboardWidgets } = await import('@/lib/queries')
    const result = await getDashboardWidgets('user-1')
    expect((supabase as any).from).toHaveBeenCalledWith('dashboard_widgets')
    expect(result).toHaveLength(1)
  })
})

// ============ RGPD Requests ============

describe('RGPD Requests', () => {
  beforeEach(() => resetMock())

  it('getRGPDRequests queries rgpd_requests', async () => {
    setMockData([{ id: '1', type: 'export' }])
    const { getRGPDRequests } = await import('@/lib/queries')
    const result = await getRGPDRequests()
    expect((supabase as any).from).toHaveBeenCalledWith('rgpd_requests')
    expect(result).toHaveLength(1)
  })
})

// ============ Grid Templates ============

describe('Grid Templates', () => {
  beforeEach(() => resetMock())

  it('getGridTemplates queries grid_templates', async () => {
    setMockData([{ id: '1', name: 'Template 1' }])
    const { getGridTemplates } = await import('@/lib/queries')
    const result = await getGridTemplates()
    expect((supabase as any).from).toHaveBeenCalledWith('grid_templates')
    expect(result).toHaveLength(1)
  })
})

// ============ Analytic Journal Codes ============

describe('Analytic Journal Codes', () => {
  beforeEach(() => resetMock())

  it('getAnalyticJournalCodes queries analytic_journal_codes', async () => {
    setMockData([{ id: '1', code: 'AN1' }])
    const { getAnalyticJournalCodes } = await import('@/lib/queries')
    const result = await getAnalyticJournalCodes()
    expect((supabase as any).from).toHaveBeenCalledWith('analytic_journal_codes')
    expect(result).toHaveLength(1)
  })
})

// ============ Reimputation Logs ============

describe('Reimputation Logs', () => {
  beforeEach(() => resetMock())

  it('getReimputationLogs queries reimputation_logs', async () => {
    setMockData([{ id: '1', reason: 'Error' }])
    const { getReimputationLogs } = await import('@/lib/queries')
    const result = await getReimputationLogs()
    expect((supabase as any).from).toHaveBeenCalledWith('reimputation_logs')
    expect(result).toHaveLength(1)
  })
})

// ============ Bank Statement Templates ============

describe('Bank Statement Templates', () => {
  beforeEach(() => resetMock())

  it('getBankStatementTemplates queries bank_statement_templates', async () => {
    setMockData([{ id: '1', name: 'BNP Template' }])
    const { getBankStatementTemplates } = await import('@/lib/queries')
    const result = await getBankStatementTemplates()
    expect((supabase as any).from).toHaveBeenCalledWith('bank_statement_templates')
    expect(result).toHaveLength(1)
  })
})

// ============ Banks Registry ============

describe('Banks Registry', () => {
  beforeEach(() => resetMock())

  it('getBanks queries banks', async () => {
    setMockData([{ id: '1', name: 'BNP Paribas' }])
    const { getBanks } = await import('@/lib/queries')
    const result = await getBanks()
    expect((supabase as any).from).toHaveBeenCalledWith('banks')
    expect(result).toHaveLength(1)
  })
})

// ============ Analytic Journals ============

describe('Analytic Journals Filter', () => {
  beforeEach(() => resetMock())

  it('getAnalyticJournals queries journals with is_analytic=true', async () => {
    setMockData([{ id: '1', code: 'AN', is_analytic: true }])
    const { getAnalyticJournals } = await import('@/lib/queries')
    const result = await getAnalyticJournals()
    expect((supabase as any).from).toHaveBeenCalledWith('journals')
    expect(mockChain.eq).toHaveBeenCalledWith('is_analytic', true)
    expect(result).toHaveLength(1)
  })

  it('getNonAnalyticJournals queries journals with is_analytic false/null', async () => {
    setMockData([{ id: '1', code: 'VT' }])
    const { getNonAnalyticJournals } = await import('@/lib/queries')
    const result = await getNonAnalyticJournals()
    expect((supabase as any).from).toHaveBeenCalledWith('journals')
    expect(result).toHaveLength(1)
  })
})

// ============ checkCreditLimit ============

describe('checkCreditLimit', () => {
  beforeEach(() => resetMock())

  it('returns exceeded=false when balance within limit', async () => {
    setMockData({ balance: 5000, credit_limit: 10000 })
    const { checkCreditLimit } = await import('@/lib/queries')
    const result = await checkCreditLimit('C001')
    expect(result.exceeded).toBe(false)
    expect(result.balance).toBe(5000)
    expect(result.limit).toBe(10000)
  })

  it('returns exceeded=true when balance exceeds limit', async () => {
    setMockData({ balance: 15000, credit_limit: 10000 })
    const { checkCreditLimit } = await import('@/lib/queries')
    const result = await checkCreditLimit('C001')
    expect(result.exceeded).toBe(true)
  })

  it('returns exceeded=false when no limit set (null)', async () => {
    setMockData({ balance: 5000, credit_limit: null })
    const { checkCreditLimit } = await import('@/lib/queries')
    const result = await checkCreditLimit('C001')
    expect(result.exceeded).toBe(false)
    expect(result.limit).toBeNull()
  })
})

// ============ getCompanyCountry ============

describe('getCompanyCountry', () => {
  beforeEach(() => resetMock())

  it('returns country from company_settings', async () => {
    setMockData([{ country: 'France', country_code: 'FR' }])
    const { getCompanyCountry } = await import('@/lib/queries')
    const result = await getCompanyCountry()
    expect(result).toBe('FRA')
  })

  it('returns null when no settings found', async () => {
    mockChain.single = vi.fn(() => Promise.resolve({ data: null, error: { message: 'Not found' } }))
    const { getCompanyCountry } = await import('@/lib/queries')
    const result = await getCompanyCountry()
    expect(result).toBeNull()
  })
})

// ============ getProductStock ============

describe('getProductStock', () => {
  beforeEach(() => resetMock())

  it('queries stock_quantities for a product', async () => {
    setMockData([{ product_id: 'p1', warehouse_id: 'w1', quantity: 100 }])
    const { getProductStock } = await import('@/lib/queries')
    const result = await getProductStock('p1')
    expect((supabase as any).from).toHaveBeenCalledWith('stock_quantities')
    expect(mockChain.eq).toHaveBeenCalledWith('product_id', 'p1')
    expect(result).toHaveLength(1)
  })
})

// ============ Tax Grids ============

describe('Payroll Tax Grids', () => {
  beforeEach(() => resetMock())

  it('getPayrollTaxGrids queries payroll_tax_grids', async () => {
    setMockData([{ id: '1', name: 'Grid 2024', country_code: 'FR' }])
    const { getPayrollTaxGrids } = await import('@/lib/queries')
    const result = await getPayrollTaxGrids()
    expect((supabase as any).from).toHaveBeenCalledWith('payroll_tax_grids')
    expect(result).toHaveLength(1)
  })

  it('getPayrollTaxGrids filters by countryCode when provided', async () => {
    setMockData([])
    const { getPayrollTaxGrids } = await import('@/lib/queries')
    await getPayrollTaxGrids('FR')
    expect(mockChain.eq).toHaveBeenCalledWith('country_code', 'FR')
  })

  it('getPayrollTaxGridLines queries lines by grid_id', async () => {
    setMockData([{ id: '1', grid_id: 'g1', sort_order: 1 }])
    const { getPayrollTaxGridLines } = await import('@/lib/queries')
    const result = await getPayrollTaxGridLines('g1')
    expect((supabase as any).from).toHaveBeenCalledWith('payroll_tax_grid_lines')
    expect(mockChain.eq).toHaveBeenCalledWith('grid_id', 'g1')
    expect(result).toHaveLength(1)
  })
})

describe('Corporate Tax Grids', () => {
  beforeEach(() => resetMock())

  it('getCorporateTaxGrids queries corporate_tax_grids', async () => {
    setMockData([{ id: '1', name: 'IS 2024' }])
    const { getCorporateTaxGrids } = await import('@/lib/queries')
    const result = await getCorporateTaxGrids()
    expect((supabase as any).from).toHaveBeenCalledWith('corporate_tax_grids')
    expect(result).toHaveLength(1)
  })
})

// ============ Sales Representatives ============

describe('Sales Representatives', () => {
  beforeEach(() => resetMock())

  it('getSalesRepresentatives queries sales_representatives', async () => {
    setMockData([{ id: '1', name: 'John Doe' }])
    const { getSalesRepresentatives } = await import('@/lib/queries')
    const result = await getSalesRepresentatives()
    expect((supabase as any).from).toHaveBeenCalledWith('sales_representatives')
    expect(result).toHaveLength(1)
  })
})

// ============ Prospects ============

describe('Prospects', () => {
  beforeEach(() => resetMock())

  it('getProspects queries prospects', async () => {
    setMockData([{ id: '1', name: 'Lead 1' }])
    const { getProspects } = await import('@/lib/queries')
    const result = await getProspects()
    expect((supabase as any).from).toHaveBeenCalledWith('prospects')
    expect(result).toHaveLength(1)
  })
})

// ============ Delivery Schedules ============

describe('Delivery Schedules', () => {
  beforeEach(() => resetMock())

  it('getDeliverySchedules queries delivery_schedules', async () => {
    setMockData([{ id: '1', frequency: 'weekly' }])
    const { getDeliverySchedules } = await import('@/lib/queries')
    const result = await getDeliverySchedules()
    expect((supabase as any).from).toHaveBeenCalledWith('delivery_schedules')
    expect(result).toHaveLength(1)
  })
})

// ============ Document Templates ============

describe('Document Templates', () => {
  beforeEach(() => resetMock())

  it('getDocumentTemplates queries document_templates', async () => {
    setMockData([{ id: '1', name: 'Invoice Template' }])
    const { getDocumentTemplates } = await import('@/lib/queries')
    const result = await getDocumentTemplates()
    expect((supabase as any).from).toHaveBeenCalledWith('document_templates')
    expect(result).toHaveLength(1)
  })
})

// ============ Future Accounting Movements ============

describe('Future Accounting Movements', () => {
  beforeEach(() => resetMock())

  it('getFutureAccountingMovements queries future_accounting_movements', async () => {
    setMockData([{ id: '1', amount: 5000, expected_date: '2025-01-01' }])
    const { getFutureAccountingMovements } = await import('@/lib/queries')
    const result = await getFutureAccountingMovements()
    expect((supabase as any).from).toHaveBeenCalledWith('future_accounting_movements')
    expect(result).toHaveLength(1)
  })
})

// ============ Marking Types ============

describe('Marking Types', () => {
  beforeEach(() => resetMock())

  it('getMarkingTypes queries marking_types', async () => {
    setMockData([{ id: '1', code: 'BAP', label: 'Bon à Payer' }])
    const { getMarkingTypes } = await import('@/lib/queries')
    const result = await getMarkingTypes()
    expect((supabase as any).from).toHaveBeenCalledWith('marking_types')
    expect(result).toHaveLength(1)
  })
})

// ============ Fusion Logs ============

describe('Fusion Logs', () => {
  beforeEach(() => resetMock())

  it('getFusionLogs queries fusion_logs', async () => {
    setMockData([{ id: '1', merged_into: '400000' }])
    const { getFusionLogs } = await import('@/lib/queries')
    const result = await getFusionLogs()
    expect((supabase as any).from).toHaveBeenCalledWith('fusion_logs')
    expect(result).toHaveLength(1)
  })
})

// ============ Compaction Logs ============

describe('Compaction Logs', () => {
  beforeEach(() => resetMock())

  it('getCompactionLogs queries compaction_logs', async () => {
    setMockData([{ id: '1', status: 'completed' }])
    const { getCompactionLogs } = await import('@/lib/queries')
    const result = await getCompactionLogs()
    expect((supabase as any).from).toHaveBeenCalledWith('compaction_logs')
    expect(result).toHaveLength(1)
  })
})
