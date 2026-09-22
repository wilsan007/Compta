import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, waitFor, fireEvent } from '@testing-library/react'
import '@testing-library/jest-dom/vitest'

// R-04 : le versement de la paie se déclenche depuis la liste des campagnes
// (net par salarié, organismes, impôt, acomptes) ; le serveur décide du reste.

const getPayRuns = vi.fn()
const getEmployees = vi.fn()
const generatePayrollJournal = vi.fn()
const payPayrollRun = vi.fn()

vi.mock('@/lib/queries/payroll', () => ({
  getPayRuns: (...a: unknown[]) => getPayRuns(...a),
  getEmployees: (...a: unknown[]) => getEmployees(...a),
  createPayRun: vi.fn(),
  updatePayRun: vi.fn(),
  deletePayRun: vi.fn(),
}))
vi.mock('@/lib/queries/misc', () => ({
  generatePayrollJournal: (...a: unknown[]) => generatePayrollJournal(...a),
  payPayrollRun: (...a: unknown[]) => payPayrollRun(...a),
}))
vi.mock('@/lib/toast', () => ({ useToast: vi.fn(() => ({ toast: vi.fn() })) }))
vi.mock('@/lib/confirm', () => ({ confirmSync: vi.fn(() => true) }))
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

const { PayRunsPage } = await import('../PayRunsPage')

const RUN = {
  id: 'pr-1', number: 'PAY-2026-03', period_start: '2026-03-01', period_end: '2026-03-31',
  pay_date: '2026-03-31', status: 'approved', gross_total: 6000, tax_total: 1320,
  net_total: 4680, employee_count: 2, created_at: '',
}

describe('PayRunsPage — versement de la paie (R-04)', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    getPayRuns.mockResolvedValue([RUN])
    getEmployees.mockResolvedValue([])
    payPayrollRun.mockResolvedValue({ success: true, entries: [{ scope: 'net', entry_id: 'e1' }], already_paid: [], remaining: [] })
  })

  it('verse la paie du lot approuvé via la RPC serveur', async () => {
    render(<PayRunsPage />)
    fireEvent.click(await screen.findByRole('button', { name: 'payRuns.pay' }))
    await waitFor(() => expect(payPayrollRun).toHaveBeenCalledWith('pr-1', null, expect.any(String), 'all'))
  })

  it('ne propose pas de versement pour un lot déjà payé', async () => {
    getPayRuns.mockResolvedValue([{ ...RUN, status: 'paid' }])
    render(<PayRunsPage />)
    await screen.findByText('PAY-2026-03')
    expect(screen.queryByRole('button', { name: 'payRuns.pay' })).not.toBeInTheDocument()
  })
})