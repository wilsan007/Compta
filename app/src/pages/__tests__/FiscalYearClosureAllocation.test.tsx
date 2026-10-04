import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, waitFor, fireEvent } from '@testing-library/react'
import '@testing-library/jest-dom/vitest'

// Décision n° 3 : l'affectation du résultat est obligatoire avant de clôturer
// l'exercice suivant. L'écran de clôture propose l'affectation et bloque la clôture.

const getFiscalYears = vi.fn()
const closeFiscalYear = vi.fn()
const allocateResult = vi.fn()

vi.mock('@/lib/queries/accounting', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@/lib/queries/accounting')>()
  return {
    pendingResultAllocations: actual.pendingResultAllocations,
    getFiscalYears: (...a: unknown[]) => getFiscalYears(...a),
    closeFiscalYear: (...a: unknown[]) => closeFiscalYear(...a),
    allocateResult: (...a: unknown[]) => allocateResult(...a),
  }
})
vi.mock('@/lib/toast', () => ({ useToast: vi.fn(() => ({ toast: vi.fn() })) }))
vi.mock('@/lib/confirm', () => ({ confirmSync: vi.fn(() => true) }))
vi.mock('react-i18next', async (importOriginal) => {
  const actual = await importOriginal<typeof import('react-i18next')>()
  return {
    ...actual,
    useTranslation: vi.fn(() => ({
      t: (key: string, opts?: Record<string, unknown>) => (opts?.codes ? `${key}:${opts.codes}` : key),
      i18n: { language: 'fr', changeLanguage: vi.fn() },
    })),
  }
})

const { FiscalYearClosurePage } = await import('../FiscalYearClosurePage')

const Y2025 = { id: 'fy-2025', code: '2025', start_date: '2025-01-01', end_date: '2025-12-31', status: 'closed', closed_at: null, closed_by: null, created_at: '', closing_result: 400, result_allocated_at: null }
const Y2026 = { id: 'fy-2026', code: '2026', start_date: '2026-01-01', end_date: '2026-12-31', status: 'open', closed_at: null, closed_by: null, created_at: '', closing_result: null, result_allocated_at: null }
const Y2027 = { id: 'fy-2027', code: '2027', start_date: '2027-01-01', end_date: '2027-12-31', status: 'open', closed_at: null, closed_by: null, created_at: '', closing_result: null, result_allocated_at: null }

describe('FiscalYearClosurePage — affectation du résultat obligatoire', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    allocateResult.mockResolvedValue({ success: true })
  })

  it('bloque la clôture de 2026 tant que le résultat 2025 n\'est pas affecté', async () => {
    getFiscalYears.mockResolvedValue([Y2027, Y2026, Y2025])
    render(<FiscalYearClosurePage />)
    expect(await screen.findByTestId('result-allocation')).toBeInTheDocument()
    expect(screen.getByRole('alert')).toHaveTextContent('fiscalYearClosure.allocation.blocking:2025')
    fireEvent.change(screen.getByLabelText('fiscalYearClosure.targetYear'), { target: { value: 'fy-2027' } })
    expect(screen.getByRole('button', { name: /fiscalYearClosure\.close$/ })).toBeDisabled()
  })

  it('envoie une répartition égale au résultat, datée du premier jour de l\'exercice suivant', async () => {
    getFiscalYears.mockResolvedValue([Y2026, Y2025])
    render(<FiscalYearClosurePage />)
    await screen.findByTestId('result-allocation')
    // Proposition initiale : tout en report à nouveau ; on en met 20 en réserve légale
    fireEvent.change(screen.getByLabelText('fiscalYearClosure.allocation.amount'), { target: { value: '380' } })
    expect(screen.getByRole('button', { name: 'fiscalYearClosure.allocation.submit' })).toBeDisabled()
    fireEvent.click(screen.getByRole('button', { name: /fiscalYearClosure\.allocation\.addLine/ }))
    const accounts = screen.getAllByLabelText('fiscalYearClosure.allocation.account')
    fireEvent.change(accounts[1], { target: { value: '106100' } })
    fireEvent.click(screen.getByRole('button', { name: 'fiscalYearClosure.allocation.submit' }))
    await waitFor(() => expect(allocateResult).toHaveBeenCalledWith('fy-2025', [
      { account: '110000', amount: 380 },
      { account: '106100', amount: 20 },
    ], '2026-01-01'))
  })

  it('n\'affiche rien quand le résultat est déjà affecté', async () => {
    getFiscalYears.mockResolvedValue([Y2026, { ...Y2025, result_allocated_at: '2026-02-01T00:00:00Z' }])
    render(<FiscalYearClosurePage />)
    await screen.findByText('fiscalYearClosure.availableYears')
    expect(screen.queryByTestId('result-allocation')).not.toBeInTheDocument()
    expect(screen.queryByRole('alert')).not.toBeInTheDocument()
  })
})
