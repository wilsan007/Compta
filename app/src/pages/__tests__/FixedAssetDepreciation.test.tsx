import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, waitFor, fireEvent } from '@testing-library/react'
import '@testing-library/jest-dom/vitest'

// R-01 / W5 : la dotation aux amortissements se comptabilise depuis l'écran
// « Immobilisations » — dans l'exercice ouvert, par le moteur SQL. Le lot rend
// un verdict par immobilisation et l'écran AFFICHE les échecs (IMMO-02, IMMO-05).

const getFixedAssets = vi.fn()
const getFiscalYears = vi.fn()
const getAssetDepreciations = vi.fn()
const generateDepreciationEntry = vi.fn()
const generateDepreciationEntries = vi.fn()
const toast = vi.fn()

vi.mock('@/lib/queries/accounting', () => ({
  getFixedAssets: (...a: unknown[]) => getFixedAssets(...a),
  getFiscalYears: (...a: unknown[]) => getFiscalYears(...a),
  getAssetDepreciations: (...a: unknown[]) => getAssetDepreciations(...a),
  generateDepreciationEntry: (...a: unknown[]) => generateDepreciationEntry(...a),
  generateDepreciationEntries: (...a: unknown[]) => generateDepreciationEntries(...a),
  createFixedAsset: vi.fn(),
  updateFixedAsset: vi.fn(),
  deleteFixedAsset: vi.fn(),
  disposeFixedAsset: vi.fn(),
}))
vi.mock('@/lib/toast', () => ({ useToast: () => ({ toast }) }))
vi.mock('@/lib/confirm', () => ({ confirmDialog: vi.fn(() => Promise.resolve(true)) }))
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

describe('FixedAssetsPage — dotation aux amortissements (R-01, W5)', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    getFixedAssets.mockResolvedValue([ASSET])
    getFiscalYears.mockResolvedValue([YEAR_OPEN])
    getAssetDepreciations.mockResolvedValue([])
    generateDepreciationEntry.mockResolvedValue('je-1')
    generateDepreciationEntries.mockResolvedValue({
      exercice: '2026', total: 1, comptabilisees: 1, sans_objet: 0, echecs: [], entrees: { 'fa-1': 'je-1' },
    })
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

  it('le lot comptabilise TOUTES les immobilisations de l\'exercice ouvert', async () => {
    render(<FixedAssetsPage />)
    const [batch] = await screen.findAllByRole('button', { name: /fixedAssets\.calculateDepreciation/ })
    fireEvent.click(batch)
    await waitFor(() => expect(generateDepreciationEntries).toHaveBeenCalledWith('fy-2026'))
    expect(toast).toHaveBeenCalledWith('success', 'fixedAssets.recalcComplete', expect.anything())
  })

  it('affiche les échecs du lot — ils ne sont plus comptés comme des succès (IMMO-05)', async () => {
    generateDepreciationEntries.mockResolvedValue({
      exercice: '2026', total: 2, comptabilisees: 1, sans_objet: 0,
      echecs: [{ asset_id: 'fa-2', asset: 'Serveur', message: 'Compte 289999 absent du plan comptable de la société' }],
      entrees: { 'fa-1': 'je-1' },
    })
    render(<FixedAssetsPage />)
    const [batch] = await screen.findAllByRole('button', { name: /fixedAssets\.calculateDepreciation/ })
    fireEvent.click(batch)
    await waitFor(() => expect(toast).toHaveBeenCalledWith(
      'error',
      'fixedAssets.depreciationFailures',
      expect.stringContaining('289999'),
    ))
  })

  it('sans exercice ouvert, le bouton du lot est désactivé (IMMO-03)', async () => {
    getFiscalYears.mockResolvedValue([])
    render(<FixedAssetsPage />)
    const [batch] = await screen.findAllByRole('button', { name: /fixedAssets\.calculateDepreciation/ })
    expect(batch).toBeDisabled()
  })
})
