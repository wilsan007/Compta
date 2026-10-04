import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, waitFor, fireEvent } from '@testing-library/react'
import '@testing-library/jest-dom/vitest'

// L19 — l'ENGAGEMENT DE PRODUCTION doit être VISIBLE, sinon la 420 n'a rien
// fermé. La fonction rend l'engagement (420, mesuré) mais l'écran ne le
// montrait pas : le module production ↔ trésorerie restait donc invisible
// pour la seule personne qui décide — l'utilisateur.
//
// Deux défauts distincts, dont un que personne n'avait vu :
//   1. les cartes n'affichaient ni la matière, ni les salaires, ni le
//      total, ni le net « quand on tient compte de la production » ;
//   2. le bouton « Lancer le prévisionnel » annonçait `net_flow` et
//      `projected_balance` — DEUX CLÉS QUE LA FONCTION NE REND PAS.
//      Le repli `?? result` tombait donc sur l'objet entier, `typeof net`
//      n'était jamais 'number', et le toast affichait 0 €. Un bouton qui
//      annonce toujours 0 est plus pire qu'un bouton mort : il confirme.

const cashFlowForecast = vi.fn()
const getTreasuryForecast = vi.fn()
const toast = vi.fn()

vi.mock('@/lib/queries/accounting', () => ({
  getTreasuryForecast: (...a: unknown[]) => getTreasuryForecast(...a),
}))
vi.mock('@/lib/queries/businessFunctions', () => ({
  cashFlowForecast: (...a: unknown[]) => cashFlowForecast(...a),
}))
vi.mock('@/lib/toast', () => ({ useToast: () => ({ toast }) }))
vi.mock('@/lib/confirm', () => ({ confirmSync: vi.fn(() => true) }))
vi.mock('react-i18next', async (importOriginal) => {
  const actual = await importOriginal<typeof import('react-i18next')>()
  return {
    ...actual,
    useTranslation: vi.fn(() => ({
      t: (key: string, params?: Record<string, unknown>) =>
        params ? `${key}|${JSON.stringify(params)}` : key,
      i18n: { language: 'fr', changeLanguage: vi.fn() },
    })),
  }
})

const { TreasuryForecastPage } = await import('../TreasuryForecastPage')

// La réponse RÉELLE de `cash_flow_forecast` — les onze clés de la 420.
const RENDU_REEL = {
  days: 90,
  expected_inflows: 12000, expected_outflows: 8000, net_forecast: 4000,
  currentBalance: 50000, totalIncoming: 12000, totalOutgoing: 8000,
  production_material_commitment: 3200, production_labor_commitment: 1800,
  production_commitment: 5000, net_with_production: -1000,
}

// Les montants sont rendus par `Intl.NumberFormat` en EUR — on calcule la
// chaîne ATTENDUE avec le même formateur, plutôt que d'écrire « 3200 » et
// de dépendre d'un séparateur de milliers qu'on aurait deviné.
// `Intl` insère des espaces insécables (U+202F) : comparer les chaînes
// brutes ferait dépendre le test d'un caractère qu'on ne voit pas. On
// normalise les espaces, et on compare le contenu, pas la ponctuation.
const EUR = (n: number) =>
  new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR', minimumFractionDigits: 2 })
    .format(n)
    .replace(/[\s  ]/g, ' ')

function montantAffiche(n: number) {
  const attendu = EUR(n)
  return (contenu: string | null) => (contenu ?? '').replace(/[\s  ]/g, ' ') === attendu
}

// Ce que l'écran reçoit APRÈS le correctif : le MOTEUR a parlé. Les
// quatre anciennes clés gardent leurs noms, et l'engagement s'y ajoute.
const RENDU_ECRAN = {
  currentBalance: 50000,
  totalIncoming: 12000,
  totalOutgoing: 8000,
  productionMaterialCommitment: 3200,
  productionLaborCommitment: 1800,
  productionCommitment: 5000,
  netForecast: 4000,
  netWithProduction: -1000,
  timeline: [
    { date: '2026-11-01', reference: 'FA-2026-01', type: 'in', amount: 12000, runningBalance: 62000 },
  ],
}

describe("TreasuryForecastPage — l'engagement de production est VISIBLE (L19)", () => {
  beforeEach(() => {
    vi.clearAllMocks()
    getTreasuryForecast.mockResolvedValue({ ...RENDU_ECRAN })
    cashFlowForecast.mockResolvedValue({ ...RENDU_REEL })
  })

  it('T01 — affiche l\'engagement MATIÈRE, les SALAIRES et leur total', async () => {
    render(<TreasuryForecastPage />)
    await waitFor(() => expect(screen.getByText('forecast.currentBalance')).toBeInTheDocument())
    // 3 200 € de matière à acheter, 1 800 € de salaires d'atelier, 5 000 € au total
    expect(screen.getByText('forecast.materialToBuy')).toBeInTheDocument()
    expect(screen.getByText('forecast.workshopLabor')).toBeInTheDocument()
    expect(screen.getByText('forecast.commitmentTotal')).toBeInTheDocument()
    expect(screen.getByText(montantAffiche(3200))).toBeInTheDocument()
    expect(screen.getByText(montantAffiche(1800))).toBeInTheDocument()
    expect(screen.getByText(montantAffiche(5000))).toBeInTheDocument()
  })

  it('T02 — affiche le net QUAND ON TIENT COMPTE de la production, distinct du net historique', async () => {
    render(<TreasuryForecastPage />)
    await waitFor(() => expect(screen.getByText('forecast.currentBalance')).toBeInTheDocument())
    // net_forecast = 4 000 €, net_with_production = -1 000 € : deux chiffres
    // DIFFÉRENTS, et les deux lisibles. C'est tout l'objet de
    // `net_with_production` : ne rien changer à ce que les écrans montrent
    // aujourd'hui, et donner à qui le veut le net qui tient l'atelier.
    expect(screen.getByText('forecast.netWithProduction')).toBeInTheDocument()
    expect(screen.getByText(montantAffiche(4000))).toBeInTheDocument()
    expect(screen.getByText(montantAffiche(-1000))).toBeInTheDocument()
  })

  it('T03 — le bouton annonce le VRAI résultat, pas 0 (il lisait deux clés inexistantes)', async () => {
    render(<TreasuryForecastPage />)
    await waitFor(() => expect(screen.getByText('forecast.currentBalance')).toBeInTheDocument())
    fireEvent.click(screen.getByRole('button', { name: /forecast.runForecast/i }))
    await waitFor(() => expect(toast).toHaveBeenCalled())
    const args = toast.mock.calls[0] as unknown[]
    expect(args[2]).toContain('forecast.cashFlowResult')
    // 4000 = net_forecast. Le toast ne doit plus dire 0 : c'est ce qu'il
    // annonçait, en lisant deux clés que la fonction ne rend pas.
    expect(args[2]).toContain('amount":4000')
  })
})