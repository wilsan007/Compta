import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, waitFor, fireEvent } from '@testing-library/react'
import '@testing-library/jest-dom/vitest'

// R-01 : la dotation aux amortissements se comptabilise depuis l'écran
// « Immobilisations » (fiche « Comptes liés »), dans l'exercice ouvert.

const getFixedAssets = vi.fn()
const getFiscalYears = vi.fn()
const getAssetDepreciations = vi.fn()
const generateDepreciationEntry = vi.fn()

vi.mock('@/lib/queries/accounting', () => ({
  getFixedAssets: (...a: unknown[]) => getFixedAssets(...a),
  getFiscalYears: (...a: unknown[]) => getFiscalYears(...a),
  getAssetDepreciations: (...a: unknown[]) => getAssetDepreciations(...a),
  generateDepreciationEntry: (...a: unknown[]) => generateDepreciationEntry(...a),
  createFixedAsset: vi.fn(),
  updateFixedAsset: vi.fn(),
  deleteFixedAsset: vi.fn(),
  disposeFixedAsset: vi.fn(),
}))
vi.mock('@/lib/queries/businessFunctions', () => ({ calculateDepreciation: vi.fn() }))
vi.mock('@/lib/queries/misc', () => ({ calculateAllDepreciation: vi.fn() }))
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

const { FixedAssetsPage } = await import('../FixedAssetsPage')

const ASSET = {
  id: 'fa-1', name: 'Camion', code: 'IMMO-001', category: 'materiel',
  purchase_date: '2025-01-01', purchase_value: 12000, current_value: 12000,
  depreciation_method: 'straight_line', useful_life_years: 5, residual_value: 0,
  status: 'active', created_at: '', updated_at: '',
  account_asset_code: '215400', account_depreciation_code: '281000',
  account_expense_depreciation_code: '681200', journal_id: null, currency_code: 'EUR',
}
const YEAR_OPEN = { id: 'fy-2026', code: '2026', start_date: '2026-01-01', end_date: '2026-12-31', status: 'open', closed_at: null, closed_by: null, created_at: '' }

describe('FixedAssetsPage — dotation aux amortissements (R-01)', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    getFixedAssets.mockResolvedValue([ASSET])
    getFiscalYears.mockResolvedValue([YEAR_OPEN])
    getAssetDepreciations.mockResolvedValue([])
    generateDepreciationEntry.mockResolvedValue('je-1')
  })

  it('comptabilise la dotation dans l\'exercice ouvert', async () => {
    render(<FixedAssetsPage />)
    fireEvent.click(await screen.findByTitle('assetAccounts.title'))
    const button = await screen.findByRole('button', { name: /assetAccounts\.generateDepreciationEntry/ })
    expect(button).toBeEnabled()
    fireEvent.click(button)
    await waitFor(() => expect(generateDepreciationEntry).toHaveBeenCalledWith('fa-1', 'fy-2026'))
  })

  it('désactive le bouton sans exercice ouvert', async () => {
    getFiscalYears.mockResolvedValue([{ ...YEAR_OPEN, status: 'closed' }])
    render(<FixedAssetsPage />)
    fireEvent.click(await screen.findByTitle('assetAccounts.title'))
    const button = await screen.findByRole('button', { name: /assetAccounts\.generateDepreciationEntry/ })
    expect(button).toBeDisabled()
  })
})