/**
 * ven-016 (lot B10) — « Contrôle du crédit client » : boucle infinie de requêtes.
 *
 * Avant : `loadData()` était appelé DANS LE CORPS du composant. Chaque rendu
 * relançait la lecture, `setCustomers` provoquait un nouveau rendu, et la boucle
 * n'avait aucune condition d'arrêt : 5 734 GET /rest/v1/customers en 5 s,
 * 14 301 en 10 s (recette /qa du 29/09/2026), puis `net::ERR_INSUFFICIENT_RESOURCES`.
 *
 * Après : une seule lecture au montage, quel que soit le nombre de rendus.
 *
 * Le même motif cachait `OnboardingDashboardPage` (jamais relevé à la recette :
 * l'écran dépend de l'état d'onboarding) — même budget pour lui.
 *
 * Budget : au-delà de `PLAFOND` appels, la source simulée cesse de résoudre, pour
 * qu'un rouge s'arrête net au lieu de tourner pendant tout le `testTimeout`.
 */
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render } from '@testing-library/react'
import '@testing-library/jest-dom/vitest'
import { MemoryRouter } from 'react-router-dom'

const { fromSpy, toastSpy, onboardingSpy, completeSpy, BUDGET, resetBudget } = vi.hoisted(() => {
  const BUDGET = 1
  const PLAFOND = 50
  const etat = { appels: 0, gele: false }
  const jamais = () => new Promise<never>(() => {})

  // Chaîne PostgREST simulée : elle reste chaînable APRÈS `order()` (contrat du
  // vrai constructeur Supabase, et `getCustomerBalances` fait `.order().eq()`).
  const chain: any = {
    select: () => chain,
    eq: () => chain,
    order: () => chain,
    maybeSingle: () => (etat.gele ? jamais() : Promise.resolve({ data: null, error: null })),
    then: (resolve: any) => (etat.gele ? jamais() : Promise.resolve({ data: [], error: null }).then(resolve)),
  }

  const fromSpy = vi.fn((_table: string) => {
    etat.appels += 1
    if (etat.appels > PLAFOND) etat.gele = true
    return chain
  })

  const onb = { appels: 0 }
  const onboardingSpy = vi.fn(() => {
    onb.appels += 1
    return onb.appels > PLAFOND ? jamais() : Promise.resolve({ step_identity: true })
  })
  const completeSpy = vi.fn(async () => false)

  return {
    fromSpy,
    toastSpy: vi.fn(),
    onboardingSpy,
    completeSpy,
    BUDGET,
    resetBudget: () => { etat.appels = 0; etat.gele = false; onb.appels = 0 },
  }
})

vi.mock('@/lib/supabase', () => ({
  supabase: {
    from: fromSpy,
    auth: {
      getSession: vi.fn(async () => ({ data: { session: null } })),
      signInWithPassword: vi.fn(),
      signOut: vi.fn(),
    },
    channel: vi.fn(),
    removeChannel: vi.fn(),
  },
  getCachedTenantId: vi.fn(() => 'tenant-qa'),
  isTenantTable: vi.fn(() => true),
}))

// `toast` et `t` restent STABLES d'un rendu à l'autre : un objet ou une fonction
// recréés referaient `loadData` (useCallback [toast, tCommon]) et reproduiraient
// la boucle même après correctif — le test deviendrait un faux rouge.
vi.mock('@/lib/toast', () => ({ useToast: () => ({ toast: toastSpy }) }))

vi.mock('@/lib/queries/admin', () => ({
  getOnboardingState: onboardingSpy,
  isOnboardingComplete: completeSpy,
  updateOnboardingStep: vi.fn(async () => undefined),
}))

vi.mock('react-i18next', async (importOriginal) => {
  const actual = await importOriginal<typeof import('react-i18next')>()
  const t = (key: string) => key
  const i18n = { language: 'fr', changeLanguage: vi.fn(), on: vi.fn(), off: vi.fn() }
  return { ...actual, useTranslation: () => ({ t, i18n }) }
})

const FENETRE_MS = 50
const attendre = () => new Promise((resolve) => setTimeout(resolve, FENETRE_MS))
const lecturesClients = () => fromSpy.mock.calls.filter(([table]) => table === 'customers').length

beforeEach(() => {
  resetBudget()
  fromSpy.mockClear()
  toastSpy.mockClear()
  onboardingSpy.mockClear()
  completeSpy.mockClear()
})

describe('Contrôle du crédit (ven-016)', () => {
  it('ne lit la liste des clients qu’une fois, même après plusieurs rendus', async () => {
    const { CreditControlPage } = await import('@/pages/CreditControlPage')
    const { rerender } = render(
      <MemoryRouter>
        <CreditControlPage />
      </MemoryRouter>,
    )

    await attendre()
    expect(lecturesClients()).toBe(BUDGET)

    rerender(
      <MemoryRouter>
        <CreditControlPage />
      </MemoryRouter>,
    )
    rerender(
      <MemoryRouter>
        <CreditControlPage />
      </MemoryRouter>,
    )
    await attendre()
    expect(lecturesClients()).toBe(BUDGET)
  })
})

describe('Assistant de paramétrage (même cause racine)', () => {
  it('ne lit l’état d’onboarding qu’une fois, même après plusieurs rendus', async () => {
    const { OnboardingDashboardPage } = await import('@/pages/OnboardingDashboardPage')
    const { rerender } = render(
      <MemoryRouter>
        <OnboardingDashboardPage />
      </MemoryRouter>,
    )

    await attendre()
    expect(onboardingSpy).toHaveBeenCalledTimes(BUDGET)

    rerender(
      <MemoryRouter>
        <OnboardingDashboardPage />
      </MemoryRouter>,
    )
    rerender(
      <MemoryRouter>
        <OnboardingDashboardPage />
      </MemoryRouter>,
    )
    await attendre()
    expect(onboardingSpy).toHaveBeenCalledTimes(BUDGET)
  })
})
