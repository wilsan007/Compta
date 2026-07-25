import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, waitFor, fireEvent } from '@testing-library/react'
import '@testing-library/jest-dom/vitest'
import { MemoryRouter } from 'react-router-dom'

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
    auth: { getSession: vi.fn(), signInWithPassword: vi.fn(), signOut: vi.fn() },
    channel: vi.fn(), removeChannel: vi.fn(),
  },
  getCachedTenantId: vi.fn(() => 'test-tenant-id'),
  isTenantTable: vi.fn(() => true),
}))

vi.mock('@/lib/toast', () => ({
  useToast: vi.fn(() => ({ toast: vi.fn() })),
}))

vi.mock('@/hooks/useLocale', () => ({
  useLocale: vi.fn(() => ({
    locale: 'fr',
    formatDate: (d: string) => new Date(d).toLocaleDateString('fr-FR'),
    formatCurrency: (n: number) => new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(n),
  })),
}))

vi.mock('react-i18next', async (importOriginal) => {
  const actual = await importOriginal<typeof import('react-i18next')>()
  return {
    ...actual,
    useTranslation: vi.fn(() => ({
      t: (key: string) => key,
      i18n: { language: 'fr', changeLanguage: vi.fn() },
    })),
  }
})

vi.mock('react-router-dom', async () => {
  const actual = await vi.importActual('react-router-dom')
  return { ...actual, useNavigate: () => vi.fn(), useLocation: () => ({ pathname: '/accounting' }) }
})

// ============ Helper ============
function renderWithRouter(component: React.ReactElement) {
  return render(<MemoryRouter>{component}</MemoryRouter>)
}

function setMockData(data: any, error: any = null) {
  mockChain.single = vi.fn(() => Promise.resolve({ data, error }))
  mockChain.then = vi.fn((resolve: any) => Promise.resolve({ data, error }).then(resolve))
}

function resetMock() {
  mockChain.single = vi.fn(() => Promise.resolve({ data: null, error: null }))
  mockChain.then = vi.fn((resolve: any) => Promise.resolve({ data: [], error: null }).then(resolve))
  vi.clearAllMocks()
}

beforeEach(() => resetMock())

// ============ Tests ============

describe('BatchEntryPage', () => {
  it('renders page title and breadcrumb', async () => {
    setMockData([])
    const { BatchEntryPage } = await import('@/pages/Phase6Pages')
    renderWithRouter(<BatchEntryPage />)
    await waitFor(() => {
      expect(screen.getAllByText('batchEntry.title').length).toBeGreaterThanOrEqual(1)
      expect(screen.getByText('batchEntry.subtitle')).toBeInTheDocument()
    })
  })

  it('shows empty state when no sessions', async () => {
    setMockData([])
    const { BatchEntryPage } = await import('@/pages/Phase6Pages')
    renderWithRouter(<BatchEntryPage />)
    await waitFor(() => {
      expect(screen.getByText('batchEntry.empty')).toBeInTheDocument()
    })
  })

  it('shows form when "new" button is clicked', async () => {
    setMockData([])
    const { BatchEntryPage } = await import('@/pages/Phase6Pages')
    renderWithRouter(<BatchEntryPage />)
    await waitFor(() => expect(screen.getByText('batchEntry.new')).toBeInTheDocument())
    fireEvent.click(screen.getByText('batchEntry.new'))
    expect(screen.getByText('batchEntry.sessionName')).toBeInTheDocument()
  })
})

describe('AutoLabelRulesPage', () => {
  it('renders page title', async () => {
    setMockData([])
    const { AutoLabelRulesPage } = await import('@/pages/Phase6Pages')
    renderWithRouter(<AutoLabelRulesPage />)
    await waitFor(() => {
      expect(screen.getAllByText('autoLabel.title').length).toBeGreaterThanOrEqual(1)
    })
  })

  it('shows empty state when no rules', async () => {
    setMockData([])
    const { AutoLabelRulesPage } = await import('@/pages/Phase6Pages')
    renderWithRouter(<AutoLabelRulesPage />)
    await waitFor(() => {
      expect(screen.getByText('autoLabel.empty')).toBeInTheDocument()
    })
  })
})

describe('ExtournePage', () => {
  it('renders page title', async () => {
    setMockData([])
    const { ExtournePage } = await import('@/pages/Phase6Pages')
    renderWithRouter(<ExtournePage />)
    await waitFor(() => {
      expect(screen.getAllByText('extourne.title').length).toBeGreaterThanOrEqual(1)
    })
  })

  it('shows empty state when no logs', async () => {
    setMockData([])
    const { ExtournePage } = await import('@/pages/Phase6Pages')
    renderWithRouter(<ExtournePage />)
    await waitFor(() => {
      expect(screen.getByText('extourne.empty')).toBeInTheDocument()
    })
  })
})

describe('CarryForwardPage', () => {
  it('renders page title', async () => {
    setMockData([])
    const { CarryForwardPage } = await import('@/pages/Phase6Pages')
    renderWithRouter(<CarryForwardPage />)
    await waitFor(() => {
      expect(screen.getAllByText('carryForward.title').length).toBeGreaterThanOrEqual(1)
    })
  })
})

describe('LettrageDifferencesPage', () => {
  it('renders page title', async () => {
    setMockData([])
    const { LettrageDifferencesPage } = await import('@/pages/Phase6Pages')
    renderWithRouter(<LettrageDifferencesPage />)
    await waitFor(() => {
      expect(screen.getAllByText('lettrageDiff.title').length).toBeGreaterThanOrEqual(1)
    })
  })
})

describe('AccountingControlsPage', () => {
  it('renders page title and run button', async () => {
    setMockData([])
    const { AccountingControlsPage } = await import('@/pages/Phase6Pages')
    renderWithRouter(<AccountingControlsPage />)
    await waitFor(() => {
      expect(screen.getAllByText('controls.title').length).toBeGreaterThanOrEqual(1)
      expect(screen.getByText('controls.run')).toBeInTheDocument()
    })
  })
})

describe('CashControlPage', () => {
  it('renders page title', async () => {
    setMockData([])
    const { CashControlPage } = await import('@/pages/Phase6Pages')
    renderWithRouter(<CashControlPage />)
    await waitFor(() => {
      expect(screen.getAllByText('cashControl.title').length).toBeGreaterThanOrEqual(1)
    })
  })
})

describe('FECAttestationPage', () => {
  it('renders page title', async () => {
    setMockData([])
    const { FECAttestationPage } = await import('@/pages/Phase6Pages')
    renderWithRouter(<FECAttestationPage />)
    await waitFor(() => {
      expect(screen.getAllByText('fecAttest.title').length).toBeGreaterThanOrEqual(1)
    })
  })
})

describe('TierRIBsPage', () => {
  it('renders page title', async () => {
    setMockData([])
    const { TierRIBsPage } = await import('@/pages/Phase6Pages')
    renderWithRouter(<TierRIBsPage />)
    await waitFor(() => {
      expect(screen.getAllByText('tierRIB.title').length).toBeGreaterThanOrEqual(1)
    })
  })
})

describe('IFRSAdjustmentsPage', () => {
  it('renders page title', async () => {
    setMockData([])
    const { IFRSAdjustmentsPage } = await import('@/pages/Phase6Pages')
    renderWithRouter(<IFRSAdjustmentsPage />)
    await waitFor(() => {
      expect(screen.getAllByText('ifrsAdjustments.title').length).toBeGreaterThanOrEqual(1)
    })
  })
})

describe('TaxPaymentsPage', () => {
  it('renders page title', async () => {
    setMockData([])
    const { TaxPaymentsPage } = await import('@/pages/Phase6Pages')
    renderWithRouter(<TaxPaymentsPage />)
    await waitFor(() => {
      expect(screen.getAllByText('taxPayment.title').length).toBeGreaterThanOrEqual(1)
    })
  })
})

describe('CustomReportTemplatesPage', () => {
  it('renders page title', async () => {
    setMockData([])
    const { CustomReportTemplatesPage } = await import('@/pages/Phase6Pages')
    renderWithRouter(<CustomReportTemplatesPage />)
    await waitFor(() => {
      expect(screen.getAllByText('customReport.title').length).toBeGreaterThanOrEqual(1)
    })
  })
})

describe('DeferredPrintingPage', () => {
  it('renders page title', async () => {
    setMockData([])
    const { DeferredPrintingPage } = await import('@/pages/Phase6Pages')
    renderWithRouter(<DeferredPrintingPage />)
    await waitFor(() => {
      expect(screen.getAllByText('deferredPrint.title').length).toBeGreaterThanOrEqual(1)
    })
  })
})

describe('JournalAccessRightsPage', () => {
  it('renders page title', async () => {
    setMockData([])
    const { JournalAccessRightsPage } = await import('@/pages/Phase6Pages')
    renderWithRouter(<JournalAccessRightsPage />)
    await waitFor(() => {
      expect(screen.getAllByText('journalAccessRights.title').length).toBeGreaterThanOrEqual(1)
    })
  })
})

describe('VATOnCollectionsPage', () => {
  it('renders page title', async () => {
    setMockData([])
    const { VATOnCollectionsPage } = await import('@/pages/Phase6Pages')
    renderWithRouter(<VATOnCollectionsPage />)
    await waitFor(() => {
      expect(screen.getAllByText('vatCollection.title').length).toBeGreaterThanOrEqual(1)
    })
  })
})
