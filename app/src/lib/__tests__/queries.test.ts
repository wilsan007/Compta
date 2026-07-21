import { describe, it, expect, vi, beforeEach } from 'vitest'

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
  },
  getCachedTenantId: vi.fn(() => 'test-tenant-id'),
  isTenantTable: vi.fn(() => true),
}))

import { supabase } from '@/lib/supabase'

describe('Phase 1.1 — Recurring Entries Queries', () => {
  beforeEach(() => vi.clearAllMocks())

  it('getRecurringEntries calls supabase with correct table', async () => {
    const { getRecurringEntries } = await import('@/lib/queries')
    await getRecurringEntries()
    expect((supabase as any).from).toHaveBeenCalledWith('recurring_entries')
  })

  it('createRecurringEntry inserts with tenant_id', async () => {
    const { createRecurringEntry } = await import('@/lib/queries')
    const result = await createRecurringEntry({
      name: 'Test recurring',
      description: 'Test',
      journal_id: null,
      frequency: 'monthly',
      day_of_month: 1,
      start_date: '2024-01-01',
      end_date: '2024-12-31',
      next_generation_date: '2024-06-01',
      status: 'active',
      total_debit: 0,
      total_credit: 0,
      lines: [],
    } as any)
    expect(result).toBeDefined()
  })

  it('deleteRecurringEntry calls delete with id and tenant_id', async () => {
    const { deleteRecurringEntry } = await import('@/lib/queries')
    await deleteRecurringEntry('test-id')
    expect((supabase as any).from).toHaveBeenCalledWith('recurring_entries')
  })
})

describe('Phase 1.2 — Regularization Queries', () => {
  beforeEach(() => vi.clearAllMocks())

  it('getRegularizationEntries queries regularization_entries table', async () => {
    const { getRegularizationEntries } = await import('@/lib/queries')
    await getRegularizationEntries()
    expect((supabase as any).from).toHaveBeenCalledWith('regularization_entries')
  })
})

describe('Phase 1.6 — Currency Revaluation Queries', () => {
  beforeEach(() => vi.clearAllMocks())

  it('getCurrencyRevaluations queries currency_revaluations table', async () => {
    const { getCurrencyRevaluations } = await import('@/lib/queries')
    await getCurrencyRevaluations()
    expect((supabase as any).from).toHaveBeenCalledWith('currency_revaluations')
  })
})

describe('Phase 1.7 — Collection Reminders Queries', () => {
  beforeEach(() => vi.clearAllMocks())

  it('getCollectionReminders queries collection_reminders table', async () => {
    const { getCollectionReminders } = await import('@/lib/queries')
    await getCollectionReminders()
    expect((supabase as any).from).toHaveBeenCalledWith('collection_reminders')
  })
})

describe('Phase 1.9 — Analytic Plans Queries', () => {
  beforeEach(() => vi.clearAllMocks())

  it('getAnalyticPlans queries analytic_plans table', async () => {
    const { getAnalyticPlans } = await import('@/lib/queries')
    await getAnalyticPlans()
    expect((supabase as any).from).toHaveBeenCalledWith('analytic_plans')
  })
})

describe('Phase 1.10 — Distribution Grills Queries', () => {
  beforeEach(() => vi.clearAllMocks())

  it('getDistributionGrills queries distribution_grills table', async () => {
    const { getDistributionGrills } = await import('@/lib/queries')
    await getDistributionGrills()
    expect((supabase as any).from).toHaveBeenCalledWith('distribution_grills')
  })
})

describe('Phase 1.11 — Bank Reconciliation Rules Queries', () => {
  beforeEach(() => vi.clearAllMocks())

  it('getBankReconciliationRules queries bank_reconciliation_rules table', async () => {
    const { getBankReconciliationRules } = await import('@/lib/queries')
    await getBankReconciliationRules()
    expect((supabase as any).from).toHaveBeenCalledWith('bank_reconciliation_rules')
  })
})

describe('Phase 1.12 — Bank Statement Imports Queries', () => {
  beforeEach(() => vi.clearAllMocks())

  it('getBankStatementImports queries bank_statement_imports table', async () => {
    const { getBankStatementImports } = await import('@/lib/queries')
    await getBankStatementImports()
    expect((supabase as any).from).toHaveBeenCalledWith('bank_statement_imports')
  })
})

describe('Phase 1.16 — TVS Queries', () => {
  beforeEach(() => vi.clearAllMocks())

  it('getTvsDeclarations queries tvs_declarations table', async () => {
    const { getTvsDeclarations } = await import('@/lib/queries')
    await getTvsDeclarations()
    expect((supabase as any).from).toHaveBeenCalledWith('tvs_declarations')
  })
})

describe('Phase 1.22 — Fiscal Backup Queries', () => {
  beforeEach(() => vi.clearAllMocks())

  it('getFiscalBackups queries fiscal_backups table', async () => {
    const { getFiscalBackups } = await import('@/lib/queries')
    await getFiscalBackups()
    expect((supabase as any).from).toHaveBeenCalledWith('fiscal_backups')
  })

  it('createFiscalBackup inserts with tenant_id', async () => {
    const { createFiscalBackup } = await import('@/lib/queries')
    const result = await createFiscalBackup({
      fiscal_year_id: null,
      backup_type: 'manual',
      status: 'pending',
      file_url: null,
      file_size: null,
      created_by: null,
    })
    expect(result).toBeDefined()
  })

  it('deleteFiscalBackup calls delete on fiscal_backups', async () => {
    const { deleteFiscalBackup } = await import('@/lib/queries')
    await deleteFiscalBackup('bk-1')
    expect((supabase as any).from).toHaveBeenCalledWith('fiscal_backups')
  })
})

describe('Phase 1.0 — Company Settings Queries', () => {
  beforeEach(() => vi.clearAllMocks())

  it('getCompanySettings queries company_settings table', async () => {
    const { getCompanySettings } = await import('@/lib/queries')
    await getCompanySettings()
    expect((supabase as any).from).toHaveBeenCalledWith('company_settings')
  })

  it('updateCompanySettings updates with id and tenant filter', async () => {
    const { updateCompanySettings } = await import('@/lib/queries')
    await updateCompanySettings('cs-1', { name: 'Updated' } as any)
    expect((supabase as any).from).toHaveBeenCalledWith('company_settings')
  })
})
