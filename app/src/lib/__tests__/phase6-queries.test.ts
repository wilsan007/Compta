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
  vi.clearAllMocks()
}

// ============ Tests ============

describe('Phase 6 — Auto Label Rules', () => {
  beforeEach(() => resetMock())

  it('getAutoLabelRules calls correct table with tenant filter', async () => {
    setMockData([{ id: '1', name: 'Rule 1', label_pattern: 'Facture {{num}}', priority: 100, active: true }])
    const { getAutoLabelRules } = await import('@/lib/queries')
    const result = await getAutoLabelRules()
    expect((supabase as any).from).toHaveBeenCalledWith('auto_label_rules')
    expect(mockChain.order).toHaveBeenCalledWith('priority', { ascending: true })
    expect(mockChain.eq).toHaveBeenCalledWith('tenant_id', 'test-tenant-id')
    expect(result).toHaveLength(1)
  })

  it('createAutoLabelRule inserts with tenant_id', async () => {
    setMockData({ id: '1', name: 'New Rule', label_pattern: 'Test', priority: 50, active: true })
    const { createAutoLabelRule } = await import('@/lib/queries')
    const result = await createAutoLabelRule({
      name: 'New Rule', description: '', journal_code: 'VT', account_code: '411000',
      account_prefix: '', label_pattern: 'Test', priority: 50, active: true,
    } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ name: 'New Rule', tenant_id: 'test-tenant-id' })
    )
    expect(result).toBeDefined()
  })

  it('deleteAutoLabelRule calls delete with id and tenant filter', async () => {
    setMockData(null, null)
    const { deleteAutoLabelRule } = await import('@/lib/queries')
    await deleteAutoLabelRule('rule-id-123')
    expect((supabase as any).from).toHaveBeenCalledWith('auto_label_rules')
    expect(mockChain.delete).toHaveBeenCalled()
    expect(mockChain.eq).toHaveBeenCalledWith('id', 'rule-id-123')
  })
})

describe('Phase 6 — Extourne Log', () => {
  beforeEach(() => resetMock())

  it('getExtourneLogs queries extourne_log table ordered by date desc', async () => {
    setMockData([{ id: '1', extourne_date: '2024-01-01', reason: 'Error correction' }])
    const { getExtourneLogs } = await import('@/lib/queries')
    const result = await getExtourneLogs()
    expect((supabase as any).from).toHaveBeenCalledWith('extourne_log')
    expect(mockChain.order).toHaveBeenCalledWith('extourne_date', { ascending: false })
    expect(result).toHaveLength(1)
  })

  it('generateExtourne is exported and callable', async () => {
    const { generateExtourne } = await import('@/lib/queries')
    expect(typeof generateExtourne).toBe('function')
  })
})

describe('Phase 6 — Carry Forward Log', () => {
  beforeEach(() => resetMock())

  it('getCarryForwardLogs queries carry_forward_log table', async () => {
    setMockData([{ id: '1', carry_forward_date: '2024-01-01', total_debit: 1000, total_credit: 1000 }])
    const { getCarryForwardLogs } = await import('@/lib/queries')
    const result = await getCarryForwardLogs()
    expect((supabase as any).from).toHaveBeenCalledWith('carry_forward_log')
    expect(mockChain.order).toHaveBeenCalledWith('carry_forward_date', { ascending: false })
    expect(result).toHaveLength(1)
  })
})

describe('Phase 6 — Lettrage Differences', () => {
  beforeEach(() => resetMock())

  it('getLettrageDifferences queries lettrage_differences table', async () => {
    setMockData([{ id: '1', third_party_code: 'C001', difference: 5.00 }])
    const { getLettrageDifferences } = await import('@/lib/queries')
    const result = await getLettrageDifferences()
    expect((supabase as any).from).toHaveBeenCalledWith('lettrage_differences')
    expect(result).toHaveLength(1)
  })

  it('deleteLettrageDifference calls delete with id and tenant filter', async () => {
    setMockData(null, null)
    const { deleteLettrageDifference } = await import('@/lib/queries')
    await deleteLettrageDifference('diff-id-123')
    expect(mockChain.delete).toHaveBeenCalled()
    expect(mockChain.eq).toHaveBeenCalledWith('id', 'diff-id-123')
  })
})

describe('Phase 6 — Accounting Control Runs', () => {
  beforeEach(() => resetMock())

  it('getAccountingControlRuns queries accounting_control_runs table', async () => {
    setMockData([{ id: '1', control_type: 'full', errors_found: 0, warnings_found: 2 }])
    const { getAccountingControlRuns } = await import('@/lib/queries')
    const result = await getAccountingControlRuns()
    expect((supabase as any).from).toHaveBeenCalledWith('accounting_control_runs')
    expect(result).toHaveLength(1)
  })

  it('runAccountingControl is exported and callable', async () => {
    const { runAccountingControl } = await import('@/lib/queries')
    expect(typeof runAccountingControl).toBe('function')
  })
})

describe('Phase 6 — Cash Control Sessions', () => {
  beforeEach(() => resetMock())

  it('getCashControlSessions queries cash_control_sessions table', async () => {
    setMockData([{ id: '1', session_number: 'CC001', theoretical_balance: 100, counted_balance: 95, difference: -5 }])
    const { getCashControlSessions } = await import('@/lib/queries')
    const result = await getCashControlSessions()
    expect((supabase as any).from).toHaveBeenCalledWith('cash_control_sessions')
    expect(result).toHaveLength(1)
  })

  it('createCashControlSession inserts with tenant_id', async () => {
    setMockData({ id: '1', session_number: 'CC001', theoretical_balance: 100, counted_balance: 100, difference: 0 })
    const { createCashControlSession } = await import('@/lib/queries')
    const result = await createCashControlSession({
      session_number: 'CC001', journal_code: 'CQ', session_date: '2024-01-01',
      theoretical_balance: 100, counted_balance: 100, difference: 0, status: 'open',
      counted_by: null, validated_by: null, validated_at: null, notes: null, details: [],
    } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ session_number: 'CC001', tenant_id: 'test-tenant-id' })
    )
    expect(result).toBeDefined()
  })

  it('deleteCashControlSession calls delete with id', async () => {
    setMockData(null, null)
    const { deleteCashControlSession } = await import('@/lib/queries')
    await deleteCashControlSession('session-id-123')
    expect(mockChain.delete).toHaveBeenCalled()
    expect(mockChain.eq).toHaveBeenCalledWith('id', 'session-id-123')
  })
})

describe('Phase 6 — FEC Attestations', () => {
  beforeEach(() => resetMock())

  it('getFECAttestations queries fec_attestations table', async () => {
    setMockData([{ id: '1', attestation_number: 'FEC001', entry_count: 500 }])
    const { getFECAttestations } = await import('@/lib/queries')
    const result = await getFECAttestations()
    expect((supabase as any).from).toHaveBeenCalledWith('fec_attestations')
    expect(result).toHaveLength(1)
  })

  it('createFECAttestation inserts with tenant_id', async () => {
    setMockData({ id: '1', attestation_number: 'FEC001', entry_count: 500 })
    const { createFECAttestation } = await import('@/lib/queries')
    await createFECAttestation({
      fiscal_year_id: 'fy-1', attestation_number: 'FEC001', attestation_date: '2024-01-01',
      fec_type: 'definitive', entry_count: 500, total_debit: 10000, total_credit: 10000,
      file_name: null, file_content: null, status: 'generated', generated_by: 'user-1',
    } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ attestation_number: 'FEC001', tenant_id: 'test-tenant-id' })
    )
  })

  it('deleteFECAttestation calls delete with id', async () => {
    setMockData(null, null)
    const { deleteFECAttestation } = await import('@/lib/queries')
    await deleteFECAttestation('fec-id-123')
    expect(mockChain.delete).toHaveBeenCalled()
  })
})

describe('Phase 6 — Tier RIBs', () => {
  beforeEach(() => resetMock())

  it('getTierRIBs queries tier_ribs table ordered by is_default desc', async () => {
    setMockData([{ id: '1', iban: 'FR76...', is_default: true }])
    const { getTierRIBs } = await import('@/lib/queries')
    const result = await getTierRIBs()
    expect((supabase as any).from).toHaveBeenCalledWith('tier_ribs')
    expect(mockChain.order).toHaveBeenCalledWith('is_default', { ascending: false })
    expect(result).toHaveLength(1)
  })

  it('getTierRIBs filters by thirdPartyAccountId when provided', async () => {
    setMockData([])
    const { getTierRIBs } = await import('@/lib/queries')
    await getTierRIBs('tp-123')
    expect(mockChain.eq).toHaveBeenCalledWith('third_party_account_id', 'tp-123')
  })

  it('createTierRIB inserts with tenant_id', async () => {
    setMockData({ id: '1', iban: 'FR76...', is_default: true })
    const { createTierRIB } = await import('@/lib/queries')
    await createTierRIB({
      third_party_account_id: 'tp-1', rib_label: 'Main RIB', iban: 'FR76...',
      bic: 'BNPAFRPP', bank_name: 'BNP', bank_code: '30002', branch_code: '00001',
      account_number: '12345678901', key: '12', is_default: true, active: true,
    } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ iban: 'FR76...', tenant_id: 'test-tenant-id' })
    )
  })

  it('deleteTierRIB calls delete with id', async () => {
    setMockData(null, null)
    const { deleteTierRIB } = await import('@/lib/queries')
    await deleteTierRIB('rib-id-123')
    expect(mockChain.delete).toHaveBeenCalled()
  })
})

describe('Phase 6 — IFRS Adjustments', () => {
  beforeEach(() => resetMock())

  it('getIFRSAdjustments queries ifrs_adjustments table', async () => {
    setMockData([{ id: '1', adjustment_type: 'provision', amount: 5000 }])
    const { getIFRSAdjustments } = await import('@/lib/queries')
    const result = await getIFRSAdjustments()
    expect((supabase as any).from).toHaveBeenCalledWith('ifrs_adjustments')
    expect(mockChain.order).toHaveBeenCalledWith('adjustment_date', { ascending: false })
    expect(result).toHaveLength(1)
  })

  it('createIFRSAdjustment inserts with tenant_id', async () => {
    setMockData({ id: '1', adjustment_type: 'provision', amount: 5000 })
    const { createIFRSAdjustment } = await import('@/lib/queries')
    await createIFRSAdjustment({
      fiscal_year_id: null, adjustment_type: 'provision', account_code: '391000',
      counter_account_code: '445800', description: 'Provision for bad debts',
      amount: 5000, adjustment_date: '2024-01-01', ifrs_standard: 'IAS 39',
      journal_entry_id: null, status: 'draft',
    } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ adjustment_type: 'provision', tenant_id: 'test-tenant-id' })
    )
  })

  it('deleteIFRSAdjustment calls delete with id', async () => {
    setMockData(null, null)
    const { deleteIFRSAdjustment } = await import('@/lib/queries')
    await deleteIFRSAdjustment('ifrs-id-123')
    expect(mockChain.delete).toHaveBeenCalled()
  })
})

describe('Phase 6 — Tax Payments', () => {
  beforeEach(() => resetMock())

  it('getTaxPayments queries tax_payments table', async () => {
    setMockData([{ id: '1', payment_number: 'TP001', tax_type: 'TVA', amount: 1500 }])
    const { getTaxPayments } = await import('@/lib/queries')
    const result = await getTaxPayments()
    expect((supabase as any).from).toHaveBeenCalledWith('tax_payments')
    expect(mockChain.order).toHaveBeenCalledWith('payment_date', { ascending: false })
    expect(result).toHaveLength(1)
  })

  it('createTaxPayment inserts with tenant_id', async () => {
    setMockData({ id: '1', payment_number: 'TP001' })
    const { createTaxPayment } = await import('@/lib/queries')
    await createTaxPayment({
      payment_number: 'TP001', tax_type: 'TVA', period_label: '2024-Q1',
      period_start: '2024-01-01', period_end: '2024-03-31', amount: 1500,
      payment_date: '2024-04-15', payment_method: 'telepayment',
      bank_account_id: null, status: 'draft', confirmation_number: null, journal_entry_id: null,
    } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ payment_number: 'TP001', tenant_id: 'test-tenant-id' })
    )
  })

  it('deleteTaxPayment calls delete with id', async () => {
    setMockData(null, null)
    const { deleteTaxPayment } = await import('@/lib/queries')
    await deleteTaxPayment('tax-id-123')
    expect(mockChain.delete).toHaveBeenCalled()
  })
})

describe('Phase 6 — Custom Report Templates', () => {
  beforeEach(() => resetMock())

  it('getCustomReportTemplates queries custom_report_templates table', async () => {
    setMockData([{ id: '1', name: 'Custom Balance', report_type: 'trial_balance' }])
    const { getCustomReportTemplates } = await import('@/lib/queries')
    const result = await getCustomReportTemplates()
    expect((supabase as any).from).toHaveBeenCalledWith('custom_report_templates')
    expect(mockChain.order).toHaveBeenCalledWith('name', { ascending: true })
    expect(result).toHaveLength(1)
  })

  it('createCustomReportTemplate inserts with tenant_id', async () => {
    setMockData({ id: '1', name: 'Custom Balance' })
    const { createCustomReportTemplate } = await import('@/lib/queries')
    await createCustomReportTemplate({
      name: 'Custom Balance', description: 'Custom trial balance',
      report_type: 'trial_balance', category: 'accounting', columns: [], filters: {},
      group_by: null, sort_by: null, sort_order: 'asc', page_orientation: 'portrait',
      page_size: 'A4', header_text: null, footer_text: null,
      show_logo: true, show_date: true, show_page_numbers: true, active: true,
    } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ name: 'Custom Balance', tenant_id: 'test-tenant-id' })
    )
  })
})

describe('Phase 6 — Deferred Printing Jobs', () => {
  beforeEach(() => resetMock())

  it('getDeferredPrintingJobs queries deferred_printing_jobs table', async () => {
    setMockData([{ id: '1', job_name: 'Monthly Report', status: 'pending' }])
    const { getDeferredPrintingJobs } = await import('@/lib/queries')
    const result = await getDeferredPrintingJobs()
    expect((supabase as any).from).toHaveBeenCalledWith('deferred_printing_jobs')
    expect(mockChain.order).toHaveBeenCalledWith('scheduled_date', { ascending: false })
    expect(result).toHaveLength(1)
  })

  it('createDeferredPrintingJob inserts with tenant_id', async () => {
    setMockData({ id: '1', job_name: 'Monthly Report' })
    const { createDeferredPrintingJob } = await import('@/lib/queries')
    await createDeferredPrintingJob({
      job_name: 'Monthly Report', report_type: 'trial_balance',
      scheduled_date: '2024-12-31', output_format: 'pdf',
      status: 'pending', parameters: {}, generated_file_path: null,
    } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ job_name: 'Monthly Report', tenant_id: 'test-tenant-id' })
    )
  })
})

describe('Phase 6 — Journal Access Rights', () => {
  beforeEach(() => resetMock())

  it('getJournalAccessRights queries journal_access_rights with tenant_users join', async () => {
    setMockData([{ id: '1', user_id: 'u1', journal_code: 'VT', can_view: true }])
    const { getJournalAccessRights } = await import('@/lib/queries')
    const result = await getJournalAccessRights()
    expect((supabase as any).from).toHaveBeenCalledWith('journal_access_rights')
    expect(mockChain.order).toHaveBeenCalledWith('journal_code', { ascending: true })
    expect(result).toHaveLength(1)
  })

  it('createJournalAccessRight inserts with tenant_id', async () => {
    setMockData({ id: '1', user_id: 'u1', journal_code: 'VT' })
    const { createJournalAccessRight } = await import('@/lib/queries')
    await createJournalAccessRight({
      user_id: 'u1', journal_code: 'VT', can_view: true, can_create: false,
      can_edit: false, can_delete: false, can_close: false,
    } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ user_id: 'u1', tenant_id: 'test-tenant-id' })
    )
  })

  it('deleteJournalAccessRight calls delete with id', async () => {
    setMockData(null, null)
    const { deleteJournalAccessRight } = await import('@/lib/queries')
    await deleteJournalAccessRight('right-id-123')
    expect(mockChain.delete).toHaveBeenCalled()
  })
})

describe('Phase 6 — VAT on Collections', () => {
  beforeEach(() => resetMock())

  it('getVATOnCollections queries vat_on_collections table', async () => {
    setMockData([{ id: '1', period_label: '2024-01', vat_base: 10000, vat_amount: 2000 }])
    const { getVATOnCollections } = await import('@/lib/queries')
    const result = await getVATOnCollections()
    expect((supabase as any).from).toHaveBeenCalledWith('vat_on_collections')
    expect(mockChain.order).toHaveBeenCalledWith('period_start', { ascending: false })
    expect(result).toHaveLength(1)
  })

  it('createVATOnCollection inserts with tenant_id', async () => {
    setMockData({ id: '1', period_label: '2024-01' })
    const { createVATOnCollection } = await import('@/lib/queries')
    await createVATOnCollection({
      period_label: '2024-01', period_start: '2024-01-01', period_end: '2024-01-31',
      vat_base: 10000, vat_rate: 20, vat_amount: 2000, collected_amount: 5000,
      uncollected_amount: 5000, vat_collected: 1000, vat_uncollected: 1000,
      status: 'draft',
    } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ period_label: '2024-01', tenant_id: 'test-tenant-id' })
    )
  })

  it('deleteVATOnCollection calls delete with id', async () => {
    setMockData(null, null)
    const { deleteVATOnCollection } = await import('@/lib/queries')
    await deleteVATOnCollection('vat-id-123')
    expect(mockChain.delete).toHaveBeenCalled()
  })
})

describe('Phase 6 — Batch Entry Sessions', () => {
  beforeEach(() => resetMock())

  it('getBatchEntrySessions queries batch_entry_sessions table', async () => {
    setMockData([{ id: '1', session_name: 'Batch Jan', entry_count: 50 }])
    const { getBatchEntrySessions } = await import('@/lib/queries')
    const result = await getBatchEntrySessions()
    expect((supabase as any).from).toHaveBeenCalledWith('batch_entry_sessions')
    expect(mockChain.order).toHaveBeenCalledWith('session_date', { ascending: false })
    expect(result).toHaveLength(1)
  })

  it('createBatchEntrySession inserts with tenant_id', async () => {
    setMockData({ id: '1', session_name: 'Batch Jan' })
    const { createBatchEntrySession } = await import('@/lib/queries')
    await createBatchEntrySession({
      session_name: 'Batch Jan', journal_code: 'VT', session_date: '2024-01-01',
      entry_count: 0, total_debit: 0, total_credit: 0, status: 'draft',
    } as any)
    expect(mockChain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ session_name: 'Batch Jan', tenant_id: 'test-tenant-id' })
    )
  })

  it('deleteBatchEntrySession calls delete with id', async () => {
    setMockData(null, null)
    const { deleteBatchEntrySession } = await import('@/lib/queries')
    await deleteBatchEntrySession('session-id-123')
    expect(mockChain.delete).toHaveBeenCalled()
  })
})

// ============ Cross-cutting: Tenant isolation ============
describe('Phase 6 — Tenant Isolation (all queries use tenant_id)', () => {
  beforeEach(() => resetMock())

  it('All GET functions filter by tenant_id', async () => {
    const { getAutoLabelRules, getExtourneLogs, getCarryForwardLogs, getLettrageDifferences,
            getAccountingControlRuns, getCashControlSessions, getFECAttestations, getTierRIBs,
            getIFRSAdjustments, getTaxPayments, getCustomReportTemplates, getDeferredPrintingJobs,
            getJournalAccessRights, getVATOnCollections, getBatchEntrySessions } = await import('@/lib/queries')

    setMockData([])
    await Promise.all([
      getAutoLabelRules(), getExtourneLogs(), getCarryForwardLogs(), getLettrageDifferences(),
      getAccountingControlRuns(), getCashControlSessions(), getFECAttestations(), getTierRIBs(),
      getIFRSAdjustments(), getTaxPayments(), getCustomReportTemplates(), getDeferredPrintingJobs(),
      getJournalAccessRights(), getVATOnCollections(), getBatchEntrySessions(),
    ])

    const eqCalls = mockChain.eq.mock.calls.filter((c: any[]) => c[0] === 'tenant_id')
    expect(eqCalls.length).toBeGreaterThanOrEqual(15)
  })
})
