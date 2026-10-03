import { describe, it, expect, vi, afterEach } from 'vitest'
import { render, screen, fireEvent, cleanup } from '@testing-library/react'
import { MemoryRouter, Routes, Route } from 'react-router-dom'

// pas d'auto-cleanup dans ce harnais : deux rendus successifs se cumulent et
// le second test ne trouve plus ce qu'il cherche
afterEach(cleanup)

// D3 (stk-010) : un ordre de fabrication **terminé** s'affichait à 0,00 € et
// son onglet « Consommations » restait vide (« Aucune consommation »).
//
// Deux causes, mesurées dans le code et dans les écritures de la base :
//   1. la clôture (migration 302, `update_manufacturing_order_costs`) écrit le
//      coût réel de l'OF dans ses **propres colonnes** — `cost_material`,
//      `cost_labor`, `cost_overhead`, `cost_total`, `unit_cost`, `cost_variance`
//      — et `getManufacturingOrder` les ramène déjà (`select('*')`) : l'écran ne
//      les lisait pas. Il ne montrait un coût qu'après un **recalcul manuel**
//      par `calculate_production_cost`, qui applique une autre définition
//      (10 % de frais généraux en dur, entrées de projet) — d'où un chiffre qui
//      peut contredire celui de la clôture ;
//   2. la clôture sort les composants en **`stock_movements`** avec
//      `reference_type = 'production'` et `reference_id = <OF>` — jamais dans
//      `of_consumptions`, que seul le formulaire manuel écrit. L'onglet lisait
//      cette seule table : vide par construction sur tout OF clôturé.

const mo = {
  id: 'of1', number: 'OF-2026-000001', status: 'completed', quantity: 10, qty_produced: 10,
  product_id: 'p1', warehouse_id: 'w1', bom_id: null, routing_id: null,
  cost_material: 440, cost_labor: 120, cost_overhead: 60, cost_total: 620,
  unit_cost: 62, cost_variance: -18, cost_standard: 458,
}

// les sorties de composants écrites par la clôture, sous la forme que le
// tableau attend
const mouvements = [
  { id: 'mv1', product_id: 'p2', products: { name: 'Composant A' }, quantity: 4, unit: 'pcs',
    consumption_date: '2026-03-10', is_deferred: false, notes: 'OF-2026-000001', origin: 'movement' },
]

const stock = vi.hoisted(() => ({
  getManufacturingOrder: vi.fn(async () => mo),
  getOFConsumptions: vi.fn(async () => mouvements),
  getProducts: vi.fn(async () => [{ id: 'p1', name: 'Produit fini' }]),
  getOFLabels: vi.fn(async () => []),
  getOFLots: vi.fn(async () => []),
  getSubManufacturingOrders: vi.fn(async () => []),
  generateOFLabels: vi.fn(), updateOFLabel: vi.fn(), deleteOFLabel: vi.fn(),
  createOFLot: vi.fn(), deleteOFLot: vi.fn(),
  createOFConsumption: vi.fn(), deleteOFConsumption: vi.fn(),
}))

// `calculateProductionCost` vit dans businessFunctions, pas dans stock
const business = vi.hoisted(() => ({
  calculateProductionCost: vi.fn(async () => ({ total_cost: 999 })),
}))

vi.mock('@/lib/queries/stock', () => stock)
vi.mock('@/lib/queries/businessFunctions', () => business)
vi.mock('@/lib/toast', () => ({ useToast: () => ({ toast: vi.fn() }) }))
vi.mock('react-i18next', async (importOriginal) => {
  const actual = await importOriginal<typeof import('react-i18next')>()
  return { ...actual, useTranslation: vi.fn(() => ({ t: (key: string) => key, i18n: { language: 'fr', changeLanguage: vi.fn() } })) }
})

const { ManufacturingOrderDetailPage } = await import('@/pages/ManufacturingOrderDetailPage')

// la page lit son id dans les paramètres de route : sans <Route>, elle reste
// indéfiniment en chargement et ne rend rien
function afficherOF() {
  return render(
    <MemoryRouter initialEntries={['/production/manufacturing/of1']}>
      <Routes>
        <Route path="/production/manufacturing/:id" element={<ManufacturingOrderDetailPage />} />
      </Routes>
    </MemoryRouter>,
  )
}

describe('D3 (stk-010) — un OF terminé affiche son coût réel et ses consommations', () => {
  it('le coût écrit par la clôture est affiché, sans recalcul', async () => {
    afficherOF()
    // 620,00 apparaît deux fois : dans l'en-tête et dans la ligne « Coût total »
    expect(await screen.findAllByText(/620[.,]00/)).toHaveLength(2)
    expect(screen.getByText(/62[.,]00/)).toBeInTheDocument()          // coût unitaire
    expect(screen.getByText(/440[.,]00/)).toBeInTheDocument()         // coût matières
    expect(screen.getByText(/120[.,]00/)).toBeInTheDocument()         // coût main-d'œuvre
    // aucun recalcul manuel n'a été déclenché pour afficher cela
    expect(business.calculateProductionCost).not.toHaveBeenCalled()
  })

  it('l’écart de coût (standard moins réel) est affiché', async () => {
    afficherOF()
    expect(await screen.findByText(/18[.,]00/)).toBeInTheDocument()
  })

  it('les sorties de composants de la clôture apparaissent dans l’onglet Consommations', async () => {
    afficherOF()
    fireEvent.click(await screen.findByRole('button', { name: /tabs\.consumptions/ }))
    expect(await screen.findByText('Composant A')).toBeInTheDocument()
    expect(screen.queryByText('manufacturing.detail.consumptions.noConsumptions')).toBeNull()
  })
})