import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, waitFor, fireEvent } from '@testing-library/react'
import '@testing-library/jest-dom/vitest'
import { MemoryRouter } from 'react-router-dom'

// Migration 201 : seuls les pays dotés d'un plan comptable (publié ou provisoire)
// sont proposés à l'inscription ; les autres sont visibles « Bientôt disponible ».

const getAvailableSignupCountries = vi.fn()

vi.mock('react-i18next', () => ({ useTranslation: () => ({ t: (k: string) => k }) }))
vi.mock('@/lib/auth', () => ({ useAuth: () => ({ user: null, reloadUser: vi.fn() }) }))
vi.mock('@/lib/queries/misc', () => ({ createTenantForUser: vi.fn() }))
vi.mock('@/lib/queries/accounting', () => ({
  getLegislationPacks: vi.fn(async () => [
    { code: 'FR', country_code: 'FR', country_name: 'France', currency: 'EUR', accounting_standard: 'PCG', fiscal_year_start: '01-01' },
    { code: 'DJ', country_code: 'DJ', country_name: 'Djibouti', currency: 'DJF', accounting_standard: 'PCG', fiscal_year_start: '01-01' },
    { code: 'MA', country_code: 'MA', country_name: 'Maroc', currency: 'MAD', accounting_standard: 'CGNC', fiscal_year_start: '01-01' },
  ]),
  getApplicableVatRates: vi.fn(async () => []),
}))
vi.mock('@/lib/queries/chartPacks', () => ({ getAvailableSignupCountries: () => getAvailableSignupCountries() }))

import { OnboardingPage } from '@/pages/OnboardingPage'

const AVAILABLE = [
  { country_code: 'DJ', country_name: 'Djibouti', pack_code: 'FR', provisional: true, currency: 'DJF' },
  { country_code: 'FR', country_name: 'France', pack_code: 'FR', provisional: false, currency: 'EUR' },
]

function renderPage() {
  render(<MemoryRouter><OnboardingPage /></MemoryRouter>)
}

// Ouvre la liste des pays (bouton qui affiche le pays courant) et renvoie l'option demandée
// Le bouton d'ouverture est le premier bouton libellé « France » (pays par défaut)
async function openCountryOption(label: string) {
  fireEvent.click((await screen.findAllByRole('button', { name: /^France$/ }))[0])
  return screen.getAllByRole('button').find((b) => b.textContent?.startsWith(label)) as HTMLButtonElement
}

describe('Inscription — pays disponibles (201)', () => {
  beforeEach(() => getAvailableSignupCountries.mockReset())

  it('propose France et Djibouti, affiche les autres pays désactivés « Bientôt disponible »', async () => {
    getAvailableSignupCountries.mockResolvedValue(AVAILABLE)
    renderPage()
    await waitFor(() => expect(getAvailableSignupCountries).toHaveBeenCalled())
    const maroc = await openCountryOption('Maroc')
    expect(maroc).toBeDisabled()
    expect(maroc).toHaveTextContent('onboarding.countryComingSoon')
    const djibouti = screen.getAllByRole('button').find((b) => b.textContent === 'Djibouti')
    expect(djibouti).toBeEnabled()
  })

  it('un pays désactivé ne peut pas être choisi', async () => {
    getAvailableSignupCountries.mockResolvedValue(AVAILABLE)
    renderPage()
    await waitFor(() => expect(getAvailableSignupCountries).toHaveBeenCalled())
    fireEvent.click(await openCountryOption('Maroc'))
    // le choix n'a pas changé : le bouton d'ouverture affiche toujours France
    expect(screen.getAllByRole('button', { name: /^France$/ })[0]).toBeInTheDocument()
    expect(screen.getAllByRole('button').filter((b) => b.textContent === 'Maroc')).toHaveLength(0)
  })

  it('Djibouti affiche la mention du plan provisoire', async () => {
    getAvailableSignupCountries.mockResolvedValue(AVAILABLE)
    renderPage()
    await waitFor(() => expect(getAvailableSignupCountries).toHaveBeenCalled())
    expect(screen.queryByText('onboarding.chartProvisional')).not.toBeInTheDocument()
    await openCountryOption('Maroc')
    fireEvent.click(screen.getAllByRole('button').find((b) => b.textContent === 'Djibouti')!)
    expect(await screen.findByText('onboarding.chartProvisional')).toBeInTheDocument()
  })

  it('serveur sans la migration 201 : aucun pays bloqué côté écran (le serveur reste juge)', async () => {
    getAvailableSignupCountries.mockResolvedValue(null)
    renderPage()
    await waitFor(() => expect(getAvailableSignupCountries).toHaveBeenCalled())
    const maroc = await openCountryOption('Maroc')
    expect(maroc).toBeEnabled()
  })
})
