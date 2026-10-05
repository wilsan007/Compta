/**
 * 370 — un montant FIXE ne vaut que DANS SA TRANCHE
 *
 * LE DÉFAUT TENU ICI. Le barème ITS de Djibouti (migration 370, 392 lignes de
 * 5 000 DJF) est une grille EN TABLE : « si le salaire imposable tombe dans
 * [min_amount, max_amount], l'impôt est CE montant ». Le moteur lisait
 * `line.fixed_amount` sans tester la tranche — `bracket` et `percentage` la
 * testaient, `fixed_amount` non (`payroll.ts`, `taxCalculator.ts`).
 *
 * MESURÉ AVANT : sur une grille de trois tranches (3 650 / 4 400 / 5 150 DJF),
 * tout salaire imposait 3 650 + 4 400 + 5 150 = 13 200 DJF — et un salaire SOUS
 * la première tranche imposait la même chose. Sur le barème réel à 392 lignes,
 * l'ITS était la somme des 392 montants.
 *
 * Ces tests sont donc écritS pour être ROUGES avant le correctif, et verts après.
 * Ils ne testent pas le moteur avec une grille française (`percentage`) : ce
 * chemin était déjà juste. Ils testent la forme « en table », qui n'existait
 * nulle part dans `main` avant la 370.
 */
import { describe, it, expect, vi } from 'vitest'

vi.mock('@/lib/supabase', () => ({
  supabase: { rpc: vi.fn(), from: vi.fn() },
  getCachedTenantId: vi.fn(() => 'test-tenant-id'),
  isTenantTable: vi.fn(() => true),
}))

import { calculatePayroll } from '@/lib/payroll'
import { calculateCorporateTax } from '@/lib/taxCalculator'
import type { PayrollTaxGridLine } from '@/types'

/** Une tranche du barème : « dans cette assiette, l'impôt vaut ce montant ». */
function tranche(min: number, max: number | null, montant: number, ordre: number): PayrollTaxGridLine {
  return {
    grid_id: 'g1',
    line_type: 'fixed_amount',
    category: 'its',
    label: `Tranche ${min} - ${max ?? 'et au-delà'} DJF`,
    base_type: 'taxable_gross',
    min_amount: min,
    max_amount: max,
    rate_employee: 0,
    rate_employer: 0,
    cap_amount: null,
    fixed_amount: montant,
    sort_order: ordre,
  } as unknown as PayrollTaxGridLine
}

/** Les trois premières tranches réelles du barème ITS de Djibouti. */
const TROIS_TRANCHES: PayrollTaxGridLine[] = [
  tranche(50000, 54999, 3650, 1),
  tranche(55000, 59999, 4400, 2),
  tranche(60000, 64999, 5150, 3),
]

/** `taxRate: 0` neutralise le repli « net imposable × taux » : seul le barème parle. */
function its(grossSalary: number, grille: PayrollTaxGridLine[]): number {
  return calculatePayroll(
    {
      grossSalary,
      contractType: 'cdi',
      hoursPerWeek: 35,
      overtimeHours: 0,
      mealVouchers: 0,
      transportAllowance: 0,
      age: 40,
      department: 'Direction',
      taxRate: 0,
    },
    grille
  ).incomeTax
}

describe('370 — un montant fixe ne vaut que dans sa tranche', () => {
  it('un salaire qui tombe dans UNE tranche n’impose que CETTE tranche', () => {
    // 56 000 DJF → la deuxième tranche. Avant : 3 650 + 4 400 + 5 150 = 13 200.
    expect(its(56000, TROIS_TRANCHES)).toBe(4400)
  })

  it('un salaire SOUS la première tranche n’impose RIEN', () => {
    // Le barème est exonéré sous 50 000 DJF. Avant : 13 200.
    expect(its(49000, TROIS_TRANCHES)).toBe(0)
  })

  it('les deux bornes de la tranche sont incluses', () => {
    expect(its(55000, TROIS_TRANCHES)).toBe(4400) // borne basse
    expect(its(59999, TROIS_TRANCHES)).toBe(4400) // juste sous la borne haute
    expect(its(60000, TROIS_TRANCHES)).toBe(5150) // borne haute de la suivante
  })

  it('la dernière tranche est bornée par le haut (la tranche suivante prend le relais)', () => {
    expect(its(64999, TROIS_TRANCHES)).toBe(5150)
  })

  it('au-delà du barème : le plancher extrapolé PLUS le marginal, et non leur somme blindée', () => {
    // Les deux dernières lignes de la 370 (sort_order 392 et 393) se recouvrent
    // DÉLIBÉRÉMENT : l'une pose un plancher, l'autre un taux marginal sur l'excédent.
    // Elles n'ont de sens qu'ENSEMBLE — et ne s'appliquent qu'au-dessus de 2 005 000.
    const extrapolated: PayrollTaxGridLine[] = [
      { ...tranche(2000000, 2004999, 597650, 391), line_type: 'fixed_amount' } as PayrollTaxGridLine,
      tranche(2005000, null, 597650, 392),
      { ...tranche(2005000, null, 0, 393), line_type: 'bracket', rate_employee: 45 } as PayrollTaxGridLine,
    ]
    // 597 650 + 45 % × (3 000 000 − 2 005 000) = 1 045 400
    expect(its(3000000, extrapolated)).toBe(1045400)
    // Juste sous le seuil : ni le plancher ni le marginal.
    expect(its(2004999, extrapolated)).toBe(597650)
  })

  it('le moteur d’IS (taxCalculator) obéit à la même règle', () => {
    const is = (min: number, max: number | null, montant: number, ordre: number) => ({
      grid_id: 'g1',
      line_type: 'fixed_amount',
      category: 'corporate_income_tax',
      label: `Tranche ${min}`,
      base_type: 'profit',
      min_amount: min,
      max_amount: max,
      rate: 0,
      fixed_amount: montant,
      sort_order: ordre,
    })
    const grille = [is(50000, 54999, 3650, 1), is(55000, 59999, 4400, 2), is(60000, 64999, 5150, 3)]

    expect(calculateCorporateTax(56000, 0, grille as never).taxAmount).toBe(4400)
    expect(calculateCorporateTax(49000, 0, grille as never).taxAmount).toBe(0)
  })
})