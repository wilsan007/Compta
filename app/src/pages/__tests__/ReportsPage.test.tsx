import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, waitFor, fireEvent } from '@testing-library/react'
import '@testing-library/jest-dom/vitest'
import { MemoryRouter } from 'react-router-dom'

// AUD-D07 : l'écran des états financiers affichait des chiffres écrits en dur
// (85 600 de revenus, 78 400 de dépenses) quelle que soit la comptabilité.

// recharts mesure son conteneur : jsdom ne fournit pas ResizeObserver
globalThis.ResizeObserver ??= class {
  observe() {}
  unobserve() {}
  disconnect() {}
} as unknown as typeof ResizeObserver

const getFiscalYears = vi.fn()
const getIncomeStatement = vi.fn()
const getIncomeStatementMonthly = vi.fn()
const navigate = vi.fn()

vi.mock('@/lib/queries/accounting', () => ({
  getFiscalYears: (...a: unknown[]) => getFiscalYears(...a),
  getIncomeStatement: (...a: unknown[]) => getIncomeStatement(...a),
  getIncomeStatementMonthly: (...a: unknown[]) => getIncomeStatementMonthly(...a),
}))

vi.mock('@/lib/queries/businessFunctions', () => ({ generateAccountingAnnex: vi.fn() }))
vi.mock('@/lib/toast', () => ({ useToast: vi.fn(() => ({ toast: vi.fn() })) }))

vi.mock('@/hooks/useLocale', () => ({
  useLocale: vi.fn(() => ({
    locale: 'fr-FR',
    formatCurrency: (n: number) => `EUR ${n.toFixed(2)}`,
  })),
}))

vi.mock('react-i18next', async (importOriginal) => {
  const actual = await importOriginal<typeof import('react-i18next')>()
  return {
    ...actual,
    useTranslation: vi.fn(() => ({ t: (key: string) => key, i18n: { language: 'fr', changeLanguage: vi.fn() } })),
  }
})

vi.mock('react-router-dom', async () => {
  const actual = await vi.importActual('react-router-dom')
  return { ...actual, useNavigate: () => navigate }
})

const { ReportsPage } = await import('../ReportsPage')

function renderPage() {
  return render(<MemoryRouter><ReportsPage /></MemoryRouter>)
}

describe('ReportsPage — compte de résultat (AUD-D07)', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    getFiscalYears.mockResolvedValue([
      { id: 'fy-2025', code: '2025', status: 'closed' },
      { id: 'fy-2026', code: '2026', status: 'open' },
    ])
    getIncomeStatement.mockResolvedValue([
      { account_code: '601000', account_name: 'Achats', account_type: 'expense', debit: 600, credit: 0, amount: 600 },
      { account_code: '706000', account_name: 'Prestations', account_type: 'income', debit: 0, credit: 1000, amount: 1000 },
    ])
    getIncomeStatementMonthly.mockResolvedValue([
      { month: '2026-01-01', revenue: 0, expense: 600, result: -600 },
      { month: '2026-02-01', revenue: 1000, expense: 0, result: 1000 },
    ])
  })

  it('affiche les totaux de la comptabilité de l’exercice ouvert, pas des chiffres de démonstration', async () => {
    renderPage()
    await waitFor(() => expect(getIncomeStatement).toHaveBeenCalledWith('fy-2026'))
    expect(getIncomeStatementMonthly).toHaveBeenCalledWith('fy-2026')

    expect(await screen.findAllByText('EUR 1000.00')).not.toHaveLength(0)
    expect(screen.getAllByText('EUR 600.00')).not.toHaveLength(0)
    expect(screen.getAllByText('EUR 400.00')).not.toHaveLength(0) // résultat net
    expect(screen.queryByText('EUR 85600.00')).toBeNull()
    expect(screen.queryByText('EUR 7200.00')).toBeNull()
    expect(screen.getByText('706000 Prestations')).toBeInTheDocument()
    expect(screen.getByText('601000 Achats')).toBeInTheDocument()
  })

  it('recharge le compte de résultat quand on change d’exercice', async () => {
    const { container } = renderPage()
    await waitFor(() => expect(getIncomeStatement).toHaveBeenCalledWith('fy-2026'))
    getIncomeStatement.mockResolvedValueOnce([])
    getIncomeStatementMonthly.mockResolvedValueOnce([])
    const select = container.querySelector('select') as HTMLSelectElement
    fireEvent.change(select, { target: { value: 'fy-2025' } })
    await waitFor(() => expect(getIncomeStatement).toHaveBeenCalledWith('fy-2025'))
    expect(await screen.findByText('financialReports.noData')).toBeInTheDocument()
    expect(screen.getAllByText('EUR 0.00')).toHaveLength(3)
  })

  it('les raccourcis vers les autres états sont de vrais liens', async () => {
    renderPage()
    fireEvent.click(await screen.findByText('financialReports.balanceSheet'))
    expect(navigate).toHaveBeenCalledWith('/reports/balance-sheet')
  })
})
