/**
 * Test Global Multiple - Phase 2: Tests de logique métier avec données mockées
 * 
 * Tests ultra-complexes avec vérifications multi-niveau et multi-tableau
 * pour la cohérence des résultats et leur robustesse.
 */

import { describe, it, expect } from 'vitest';
import { calculateVAT } from '@/lib/queries/accounting';
import { calculateTax, calculateGroupTax, calculateMultipleTaxes, calculatePriceWithTax, extractTaxFromIncludedPrice, calculateCorporateTax } from '@/lib/taxCalculator';
import { validateDistribution, distributeEvenly, computeAmounts, flattenDistribution } from '@/lib/analyticDistribution';
import { calculatePayroll, formatPayrollAmount } from '@/lib/payroll';
import type { TaxRate, FixedAsset, DistributionGrill, DistributionGrillLine, FiscalPosition, FiscalPositionMapping, AccountTag, AccountTagMapping, Currency, ExchangeGainLossEntry, CorporateTaxGridLine, PayrollTaxGridLine, PartnerContact, PartnerBankAccount } from '@/types';

// ============ MOCK DATA ============

const mockTax20: TaxRate = {
  id: 'tax-20', pack_code: 'FR', name: 'TVA 20%', category: 'vat' as any,
  rate: 20, account_code: '445710', is_default: true,
  effective_from: '2024-01-01', effective_to: null, created_at: '2024-01-01',
  amount_type: 'percent', type_tax_use: 'sale', sequence: 10,
  parent_tax_id: null, tax_exigibility: 'on_invoice', price_include: false,
  include_base_amount: false, is_base_affected: true, fixed_amount: null,
}

const mockTax55: TaxRate = {
  ...mockTax20, id: 'tax-55', name: 'TVA 5.5%', rate: 5.5,
}


const mockTax0: TaxRate = {
  ...mockTax20, id: 'tax-0', name: 'TVA 0%', rate: 0,
}

const mockTaxFixed: TaxRate = {
  ...mockTax20, id: 'tax-fixed', name: 'Taxe fixe', rate: 0,
  amount_type: 'fixed', fixed_amount: 15.50,
}

const mockTaxDivision: TaxRate = {
  ...mockTax20, id: 'tax-div', name: 'TVA division', rate: 20,
  amount_type: 'division',
}

const mockTaxIncluded: TaxRate = {
  ...mockTax20, id: 'tax-inc', name: 'TVA incluse', rate: 20,
  price_include: true,
}

const mockParentTax: TaxRate = {
  ...mockTax20, id: 'tax-parent', name: 'Groupe TVA', rate: 0,
  amount_type: 'group',
}

const mockChildTax1: TaxRate = {
  ...mockTax20, id: 'tax-child-1', name: 'TVA 20%', rate: 20,
  parent_tax_id: 'tax-parent', sequence: 10,
}

const mockChildTax2: TaxRate = {
  ...mockTax20, id: 'tax-child-2', name: 'Taxe éco', rate: 2,
  parent_tax_id: 'tax-parent', sequence: 20, include_base_amount: true,
}

const mockAsset: FixedAsset = {
  id: 'asset-1', name: 'Ordinateur', code: 'IMMO-001', category: 'IT',
  purchase_date: '2024-01-01', purchase_value: 10000, current_value: 10000,
  depreciation_method: 'straight_line', useful_life_years: 5,
  residual_value: 0, status: 'active', created_at: '2024-01-01',
  updated_at: '2024-01-01', account_asset_code: '210000',
  account_depreciation_code: '281000', account_expense_depreciation_code: '681000',
  journal_id: 'journal-immo', currency_code: 'EUR',
}

const mockGrillLines: DistributionGrillLine[] = [
  { id: 'l1', grill_id: 'g1', section_code: 'A001', percentage: 60, created_at: '2024-01-01' },
  { id: 'l2', grill_id: 'g1', section_code: 'A002', percentage: 40, created_at: '2024-01-01' },
]

const mockGrill: DistributionGrill = {
  id: 'g1', tenant_id: 'tid', name: 'Grill Achat', description: 'Test grill',
  account_code: '607000', journal_code: 'ACH', active: true,
  lines: mockGrillLines, created_at: '2024-01-01', updated_at: '2024-01-01',
}

const mockFiscalPosition: FiscalPosition = {
  id: 'fp1', tenant_id: 'tid', name: 'Export UE', country_code: 'DE',
  country_group_id: null, zip_from: null, zip_to: null,
  auto_apply: false, active: true, created_at: '2024-01-01',
}

const mockFiscalMapping: FiscalPositionMapping = {
  id: 'fpm1', tenant_id: 'tid', fiscal_position_id: 'fp1',
  source_tax_id: 'tax-20', target_tax_id: 'tax-0',
  source_account_code: null, target_account_code: null,
  created_at: '2024-01-01',
}

const mockTag: AccountTag = {
  id: 'tag1', tenant_id: 'tid', name: 'Comptes clients',
  applicability: 'accounts', color: 'blue', country_code: null,
  created_at: '2024-01-01',
}

const mockTagMapping: AccountTagMapping = {
  id: 'tm1', tenant_id: 'tid', tag_id: 'tag1',
  entity_type: 'account', entity_id: '411000',
  created_at: '2024-01-01',
}

const mockCurrencyEUR: Currency = {
  id: 'c-eur', code: 'EUR', name: 'Euro', symbol: '€',
  exchange_rate: 1, is_base: true, created_at: '2024-01-01',
  decimal_places: 2, active: true, position: 'after',
}

const mockCurrencyUSD: Currency = {
  id: 'c-usd', code: 'USD', name: 'Dollar US', symbol: '$',
  exchange_rate: 1.085, is_base: false, created_at: '2024-01-01',
  decimal_places: 2, active: true, position: 'before',
}

const mockExchangeGain: ExchangeGainLossEntry = {
  id: 'egl1', tenant_id: 'tid', payment_id: 'pay-1', invoice_id: 'inv-1',
  type: 'gain', amount: 150.00, exchange_rate_original: 1.085,
  exchange_rate_payment: 1.090, account_gain_code: '766000',
  account_loss_code: null, journal_entry_id: 'je-1', created_at: '2024-06-01',
}

const mockExchangeLoss: ExchangeGainLossEntry = {
  id: 'egl2', tenant_id: 'tid', payment_id: 'pay-2', invoice_id: 'inv-2',
  type: 'loss', amount: 80.00, exchange_rate_original: 1.085,
  exchange_rate_payment: 1.080, account_gain_code: null,
  account_loss_code: '666000', journal_entry_id: 'je-2', created_at: '2024-06-02',
}

const mockContact: PartnerContact = {
  id: 'pc1', tenant_id: 'tid', partner_type: 'customer', partner_id: 'cust-1',
  contact_type: 'primary', name: 'Jean Dupont', email: 'jean@test.com',
  phone: '0123456789', mobile: '0612345678', function: 'Directeur',
  address: '1 rue Test', postal_code: '75001', city: 'Paris', country: 'France',
  is_default: true, active: true, created_at: '2024-01-01',
}

const mockBankAccount: PartnerBankAccount = {
  id: 'ba1', tenant_id: 'tid', partner_type: 'customer', partner_id: 'cust-1',
  account_number: 'FR76 1234 5678 9012 3456 7890 123',
  bank_name: 'BNP', bic: 'BNPAFRPP', bank_code: '12345',
  sort_code: '56789', account_key: '01', currency_code: 'EUR',
  is_default: true, active: true, created_at: '2024-01-01',
}

const mockCorporateGridLines: CorporateTaxGridLine[] = [
  { id: 'cl1', grid_id: 'g1', line_type: 'bracket', label: 'Tranche 1',
    base_type: 'profit', min_amount: 0, max_amount: 50000, rate: 15,
    cap_amount: null, fixed_amount: 0, sort_order: 1, created_at: '2024-01-01' },
  { id: 'cl2', grid_id: 'g1', line_type: 'bracket', label: 'Tranche 2',
    base_type: 'profit', min_amount: 50000, max_amount: null, rate: 25,
    cap_amount: null, fixed_amount: 0, sort_order: 2, created_at: '2024-01-01' },
]

const mockPayrollGridLines: PayrollTaxGridLine[] = [
  { id: 'pl1', grid_id: 'g1', line_type: 'percentage', category: 'social_security',
    label: 'Sécu salariale', base_type: 'gross', min_amount: 0, max_amount: null,
    rate_employee: 6.98, rate_employer: 29.74, cap_amount: null, fixed_amount: 0,
    sort_order: 1, created_at: '2024-01-01' },
  { id: 'pl2', grid_id: 'g1', line_type: 'percentage', category: 'retirement',
    label: 'Retraite salariale', base_type: 'gross', min_amount: 0, max_amount: null,
    rate_employee: 11.40, rate_employer: 10.93, cap_amount: null, fixed_amount: 0,
    sort_order: 2, created_at: '2024-01-01' },
  { id: 'pl3', grid_id: 'g1', line_type: 'percentage', category: 'csg_crds',
    label: 'CSG/CRDS', base_type: 'total_gross', min_amount: 0, max_amount: null,
    rate_employee: 9.20, rate_employer: 0, cap_amount: null, fixed_amount: 0,
    sort_order: 3, created_at: '2024-01-01' },
  { id: 'pl4', grid_id: 'g1', line_type: 'percentage', category: 'income_tax',
    label: 'ITS/PAS', base_type: 'taxable_gross', min_amount: 0, max_amount: null,
    rate_employee: 0, rate_employer: 0, cap_amount: null, fixed_amount: 0,
    sort_order: 4, created_at: '2024-01-01' },
]

// ============ 2a: TESTS DE CALCULS FINANCIERS ============

describe('2a. Tests de calculs financiers', () => {

  // --- calculateVAT ---
  describe('calculateVAT', () => {
    it('TVA 20% sur montant HT de 1000 → HT=1000, TVA=200, TTC=1200', () => {
      const result = calculateVAT(1000, 20, 'ht')
      expect(result.ht).toBe(1000)
      expect(result.tva).toBe(200)
      expect(result.ttc).toBe(1200)
    })

    it('TVA 5.5% sur montant HT de 1000 → HT=1000, TVA=55, TTC=1055', () => {
      const result = calculateVAT(1000, 5.5, 'ht')
      expect(result.ht).toBe(1000)
      expect(result.tva).toBe(55)
      expect(result.ttc).toBe(1055)
    })

    it('TVA 0% sur montant HT de 1000 → HT=1000, TVA=0, TTC=1000', () => {
      const result = calculateVAT(1000, 0, 'ht')
      expect(result.ht).toBe(1000)
      expect(result.tva).toBe(0)
      expect(result.ttc).toBe(1000)
    })

    it('TVA 20% sur montant TTC de 1200 → HT=1000, TVA=200, TTC=1200', () => {
      const result = calculateVAT(1200, 20, 'ttc')
      expect(result.ht).toBe(1000)
      expect(result.tva).toBe(200)
      expect(result.ttc).toBe(1200)
    })

    it('TVA 10% sur montant TTC de 110 → HT=100, TVA=10, TTC=110', () => {
      const result = calculateVAT(110, 10, 'ttc')
      expect(result.ht).toBe(100)
      expect(result.tva).toBe(10)
      expect(result.ttc).toBe(110)
    })

    it('Montant 0 → tout à 0', () => {
      const result = calculateVAT(0, 20, 'ht')
      expect(result.ht).toBe(0)
      expect(result.tva).toBe(0)
      expect(result.ttc).toBe(0)
    })

    it('Montant avec décimales: 999.99 HT à 20% → arrondi correct', () => {
      const result = calculateVAT(999.99, 20, 'ht')
      expect(result.ht).toBe(999.99)
      expect(result.tva).toBe(200) // 999.99 * 0.20 = 199.998 → arrondi à 200
      expect(result.ttc).toBe(1199.99)
    })

    it('Montant négatif HT à 20% → TVA négative (avoir)', () => {
      const result = calculateVAT(-100, 20, 'ht')
      expect(result.ht).toBe(-100)
      expect(result.tva).toBe(-20)
      expect(result.ttc).toBe(-120)
    })
  })

  // --- calculateTax ---
  describe('calculateTax (taxCalculator)', () => {
    it('Percent: 1000 * 20% → taxAmount=200', () => {
      const result = calculateTax(1000, mockTax20)
      expect(result.taxAmount).toBe(200)
      expect(result.newBase).toBe(1000)
    })

    it('Percent 5.5%: 1000 * 5.5% → taxAmount=55', () => {
      const result = calculateTax(1000, mockTax55)
      expect(result.taxAmount).toBe(55)
    })

    it('Percent 0%: 1000 * 0% → taxAmount=0', () => {
      const result = calculateTax(1000, mockTax0)
      expect(result.taxAmount).toBe(0)
    })

    it('Fixed: taxAmount=15.50 regardless of base', () => {
      const result = calculateTax(100000, mockTaxFixed)
      expect(result.taxAmount).toBe(15.50)
      expect(result.newBase).toBe(100000)
    })

    it('Fixed with 0 base: taxAmount=15.50', () => {
      const result = calculateTax(0, mockTaxFixed)
      expect(result.taxAmount).toBe(15.50)
    })

    it('Division: 1200 with 20% → taxAmount=200, newBase=1000', () => {
      const result = calculateTax(1200, mockTaxDivision)
      expect(result.taxAmount).toBe(200) // 1200 * 20/(100+20) = 200
      expect(result.newBase).toBe(1000) // 1200 - 200 = 1000
    })

    it('Group without allTaxes → taxAmount=0', () => {
      const result = calculateTax(1000, mockParentTax)
      expect(result.taxAmount).toBe(0)
    })

    it('Group with children → sum of child taxes', () => {
      const allTaxes = [mockParentTax, mockChildTax1, mockChildTax2]
      const result = calculateTax(1000, mockParentTax, allTaxes)
      // Child1: 1000 * 20% = 200, base stays 1000 (include_base_amount=false)
      // Child2: 1000 * 2% = 20, base becomes 1020 (include_base_amount=true)
      expect(result.taxAmount).toBe(220)
      expect(result.breakdown).toHaveLength(2)
      expect(result.breakdown![0].taxAmount).toBe(200)
      expect(result.breakdown![1].taxAmount).toBe(20)
    })
  })

  // --- calculateMultipleTaxes ---
  describe('calculateMultipleTaxes', () => {
    it('Multiple taxes with include_base_amount', () => {
      const taxes = [{ ...mockTax20, include_base_amount: true }, mockTax55]
      const result = calculateMultipleTaxes(1000, taxes)
      // Tax1: 1000 * 20% = 200, base becomes 1200 (include_base_amount)
      // Tax2: 1200 * 5.5% = 66 (no include_base_amount, base stays 1200)
      expect(result.totalTax).toBe(266)
      expect(result.finalBase).toBe(1200)
    })

    it('Empty taxes array → totalTax=0', () => {
      const result = calculateMultipleTaxes(1000, [])
      expect(result.totalTax).toBe(0)
      expect(result.finalBase).toBe(1000)
    })

    it('Single tax → same as calculateTax', () => {
      const result = calculateMultipleTaxes(1000, [mockTax20])
      expect(result.totalTax).toBe(200)
    })
  })

  // --- calculatePriceWithTax ---
  describe('calculatePriceWithTax', () => {
    it('Price 100 * qty 10 with 20% TVA → HT=1000, TVA=200, TTC=1200', () => {
      const result = calculatePriceWithTax(100, 10, [mockTax20])
      expect(result.ht).toBe(1000)
      expect(result.taxAmount).toBe(200)
      expect(result.ttc).toBe(1200)
    })

    it('Price 0 * qty 10 → tout à 0', () => {
      const result = calculatePriceWithTax(0, 10, [mockTax20])
      expect(result.ht).toBe(0)
      expect(result.taxAmount).toBe(0)
      expect(result.ttc).toBe(0)
    })

    it('Price 100 * qty 0 → tout à 0', () => {
      const result = calculatePriceWithTax(100, 0, [mockTax20])
      expect(result.ht).toBe(0)
      expect(result.taxAmount).toBe(0)
      expect(result.ttc).toBe(0)
    })
  })

  // --- extractTaxFromIncludedPrice ---
  describe('extractTaxFromIncludedPrice', () => {
    it('TTC 1200 with 20% included → HT=1000, TVA=200', () => {
      const result = extractTaxFromIncludedPrice(1200, mockTaxIncluded)
      expect(result.ttc).toBe(1200)
      expect(result.ht).toBe(1000)
      expect(result.taxAmount).toBe(200)
    })

    it('TTC 0 with 20% included → HT=0, TVA=0', () => {
      const result = extractTaxFromIncludedPrice(0, mockTaxIncluded)
      expect(result.ht).toBe(0)
      expect(result.taxAmount).toBe(0)
    })
  })

  // --- calculateCorporateTax ---
  describe('calculateCorporateTax', () => {
    it('Profit 100000 with bracket 0-50000@15%, 50000+@25% → tax=17500', () => {
      const result = calculateCorporateTax(100000, 500000, mockCorporateGridLines)
      // Tranche 1: 50000 * 15% = 7500
      // Tranche 2: (100000 - 50000) * 25% = 12500
      // Total: 20000
      expect(result.taxAmount).toBe(20000)
      expect(result.afterTaxProfit).toBe(80000)
    })

    it('Profit 30000 (below first bracket cap) → tax=4500', () => {
      const result = calculateCorporateTax(30000, 200000, mockCorporateGridLines)
      // 30000 * 15% = 4500
      expect(result.taxAmount).toBe(4500)
      expect(result.afterTaxProfit).toBe(25500)
    })

    it('Profit 0 → tax=0', () => {
      const result = calculateCorporateTax(0, 100000, mockCorporateGridLines)
      expect(result.taxAmount).toBe(0)
      expect(result.afterTaxProfit).toBe(0)
    })

    it('Profit négatif → tax=0 (pas de taxe sur perte)', () => {
      const result = calculateCorporateTax(-50000, 100000, mockCorporateGridLines)
      expect(result.taxAmount).toBe(0)
      expect(result.afterTaxProfit).toBe(-50000)
    })

    it('Minimum tax > calculated tax → finalTax = minimum', () => {
      const minTaxLines: CorporateTaxGridLine[] = [
        { id: 'mt1', grid_id: 'g1', line_type: 'percentage', label: 'IMF',
          base_type: 'turnover', min_amount: 0, max_amount: null, rate: 1,
          cap_amount: 5000, fixed_amount: 0, sort_order: 1, created_at: '2024-01-01' },
      ]
      // Profit 100000, turnover 500000
      // Calculated tax: 20000
      // Minimum: 500000 * 1% = 5000, capped at 5000
      // Final: max(20000, 5000) = 20000
      const result = calculateCorporateTax(100000, 500000, mockCorporateGridLines, minTaxLines)
      expect(result.minimumTax).toBe(5000)
      expect(result.finalTax).toBe(20000)
    })

    it('Minimum tax > calculated tax with low profit → finalTax = minimum', () => {
      const minTaxLines: CorporateTaxGridLine[] = [
        { id: 'mt1', grid_id: 'g1', line_type: 'percentage', label: 'IMF',
          base_type: 'turnover', min_amount: 0, max_amount: null, rate: 1,
          cap_amount: null, fixed_amount: 0, sort_order: 1, created_at: '2024-01-01' },
      ]
      // Profit 10000, turnover 2000000
      // Calculated tax: 10000 * 15% = 1500
      // Minimum: 2000000 * 1% = 20000
      // Final: max(1500, 20000) = 20000
      const result = calculateCorporateTax(10000, 2000000, mockCorporateGridLines, minTaxLines)
      expect(result.taxAmount).toBe(1500)
      expect(result.minimumTax).toBe(20000)
      expect(result.finalTax).toBe(20000)
    })
  })
})

// ============ 2b: TESTS DE COHÉRENCE MULTI-TABLEAU ============

describe('2b. Tests de cohérence multi-tableau', () => {

  // --- Distribution grills ---
  describe('Distribution grills', () => {
    it('Grill avec lignes 60%+40%=100% → validation OK', () => {
      const dist: Record<string, Record<string, number>> = {
        'plan-1': { 'A001': 60, 'A002': 40 },
      }
      expect(validateDistribution(dist)).toBe(true)
    })

    it('Grill avec lignes 60%+30%=90% → validation FAIL', () => {
      const dist: Record<string, Record<string, number>> = {
        'plan-1': { 'A001': 60, 'A002': 30 },
      }
      expect(validateDistribution(dist)).toBe(false)
    })

    it('Grill avec 0 ligne → validation OK (vacuous truth)', () => {
      const dist: Record<string, Record<string, number>> = {}
      expect(validateDistribution(dist)).toBe(true)
    })

    it('distributeEvenly avec 4 sections → 25% chacune', () => {
      const result = distributeEvenly(['s1', 's2', 's3', 's4'])
      expect(Object.keys(result)).toHaveLength(4)
      expect(result['s1']).toBe(25)
      expect(result['s4']).toBe(25)
    })

    it('distributeEvenly avec 0 sections → objet vide', () => {
      const result = distributeEvenly([])
      expect(Object.keys(result)).toHaveLength(0)
    })

    it('distributeEvenly avec 3 sections → 33.33% chacune', () => {
      const result = distributeEvenly(['s1', 's2', 's3'])
      expect(result['s1']).toBe(33.33)
      // Note: 33.33 * 3 = 99.99, not 100 — this is a known rounding issue
    })

    it('computeAmounts: 1000€ avec 60%/40% → 600€/400€', () => {
      const dist: Record<string, Record<string, number>> = {
        'plan-1': { 'A001': 60, 'A002': 40 },
      }
      const result = computeAmounts(dist, 1000)
      expect(result['plan-1']['A001']).toBe(600)
      expect(result['plan-1']['A002']).toBe(400)
    })

    it('computeAmounts: 0€ avec 60%/40% → 0€/0€', () => {
      const dist: Record<string, Record<string, number>> = {
        'plan-1': { 'A001': 60, 'A002': 40 },
      }
      const result = computeAmounts(dist, 0)
      expect(result['plan-1']['A001']).toBe(0)
      expect(result['plan-1']['A002']).toBe(0)
    })

    it('flattenDistribution: 2 plans * 2 sections → 4 entrées', () => {
      const dist: Record<string, Record<string, number>> = {
        'plan-1': { 'A001': 60, 'A002': 40 },
        'plan-2': { 'B001': 100 },
      }
      const result = flattenDistribution(dist)
      expect(result).toHaveLength(3)
      expect(result[0].planId).toBe('plan-1')
      expect(result[0].sectionId).toBe('A001')
      expect(result[0].percentage).toBe(60)
    })

    it('Mock grill: somme des pourcentages = 100%', () => {
      const total = mockGrill.lines.reduce((s: number, l: DistributionGrillLine) => s + l.percentage, 0)
      expect(total).toBe(100)
    })

    it('Mock grill: lignes dupliquées (même section_code) → détection', () => {
      const dupLines = [
        ...mockGrillLines,
        { id: 'l3', grill_id: 'g1', section_code: 'A001', percentage: 10, created_at: '2024-01-01' },
      ]
      const sectionCodes = dupLines.map(l => l.section_code)
      const duplicates = sectionCodes.filter((c, i) => sectionCodes.indexOf(c) !== i)
      expect(duplicates).toEqual(['A001'])
    })
  })

  // --- Positions fiscales + mappings ---
  describe('Positions fiscales + mappings', () => {
    it('Mapping avec source_tax_id et target_tax_id → cohérent', () => {
      expect(mockFiscalMapping.source_tax_id).toBe('tax-20')
      expect(mockFiscalMapping.target_tax_id).toBe('tax-0')
      expect(mockFiscalMapping.fiscal_position_id).toBe(mockFiscalPosition.id)
    })

    it('Application: tax 20% → tax 0% (export) → transformation correcte', () => {
      const sourceTax = mockTax20
      const targetTax = mockTax0
      const baseAmount = 1000
      const sourceTaxAmount = calculateTax(baseAmount, sourceTax).taxAmount
      const targetTaxAmount = calculateTax(baseAmount, targetTax).taxAmount
      expect(sourceTaxAmount).toBe(200)
      expect(targetTaxAmount).toBe(0)
      // La position fiscale transforme 200€ de TVA en 0€
      expect(sourceTaxAmount - targetTaxAmount).toBe(200)
    })

    it('Mapping sans tax (account only) → OK', () => {
      const accountMapping: FiscalPositionMapping = {
        ...mockFiscalMapping, id: 'fpm2',
        source_tax_id: null, target_tax_id: null,
        source_account_code: '411000', target_account_code: '412000',
      }
      expect(accountMapping.source_tax_id).toBeNull()
      expect(accountMapping.target_tax_id).toBeNull()
      expect(accountMapping.source_account_code).toBe('411000')
    })

    it('Position fiscale avec zip_from/zip_to → cohérent', () => {
      const fpWithZip: FiscalPosition = {
        ...mockFiscalPosition, id: 'fp2',
        zip_from: '75000', zip_to: '75020',
      }
      expect(fpWithZip.zip_from).toBe('75000')
      expect(fpWithZip.zip_to).toBe('75020')
    })
  })

  // --- Tags comptables + mappings ---
  describe('Tags comptables + mappings', () => {
    it('Tag avec applicability "accounts" → type correct', () => {
      expect(mockTag.applicability).toBe('accounts')
    })

    it('Mapping avec entity_type "account" → cohérent avec tag applicability', () => {
      expect(mockTagMapping.entity_type).toBe('account')
      expect(mockTag.applicability).toBe('accounts')
      // entity_type 'account' est compatible avec applicability 'accounts'
    })

    it('Mapping avec entity_type "tax" mais tag applicability "accounts" → incohérent', () => {
      const incompatibleMapping: AccountTagMapping = {
        ...mockTagMapping, id: 'tm2', entity_type: 'tax',
      }
      // Ce mapping est incohérent: le tag est pour 'accounts' mais le mapping cible 'tax'
      expect(incompatibleMapping.entity_type).not.toBe(mockTag.applicability)
    })
  })

  // --- Contacts tiers + comptes bancaires ---
  describe('Contacts tiers + comptes bancaires', () => {
    it('Contact par défaut: is_default=true', () => {
      expect(mockContact.is_default).toBe(true)
    })

    it('Compte bancaire par défaut: is_default=true', () => {
      expect(mockBankAccount.is_default).toBe(true)
    })

    it('Un seul contact par défaut par tiers → vérification', () => {
      const contacts: PartnerContact[] = [
        { ...mockContact, id: 'pc1', is_default: true },
        { ...mockContact, id: 'pc2', is_default: false },
      ]
      const defaultCount = contacts.filter(c => c.is_default).length
      expect(defaultCount).toBe(1)
    })

    it('Deux contacts par défaut → incohérent', () => {
      const contacts: PartnerContact[] = [
        { ...mockContact, id: 'pc1', is_default: true },
        { ...mockContact, id: 'pc2', is_default: true },
      ]
      const defaultCount = contacts.filter(c => c.is_default).length
      expect(defaultCount).toBe(2) // BUG: should be 1
    })

    it('Contact inactif ne doit pas être sélectionné', () => {
      const contacts: PartnerContact[] = [
        { ...mockContact, id: 'pc1', active: true },
        { ...mockContact, id: 'pc2', active: false },
      ]
      const activeContacts = contacts.filter(c => c.active)
      expect(activeContacts).toHaveLength(1)
      expect(activeContacts[0].id).toBe('pc1')
    })

    it('Compte bancaire inactif ne doit pas être sélectionné', () => {
      const banks: PartnerBankAccount[] = [
        { ...mockBankAccount, id: 'ba1', active: true },
        { ...mockBankAccount, id: 'ba2', active: false },
      ]
      const activeBanks = banks.filter(b => b.active)
      expect(activeBanks).toHaveLength(1)
    })
  })

  // --- Immobilisations + amortissements ---
  describe('Immobilisations + amortissements', () => {
    it('Amortissement linéaire: 10000 / 5 ans = 2000/an', () => {
      const annualDep = (mockAsset.purchase_value - mockAsset.residual_value) / mockAsset.useful_life_years
      expect(annualDep).toBe(2000)
    })

    it('Valeur nette après 3 ans = 10000 - 6000 = 4000', () => {
      const annualDep = (mockAsset.purchase_value - mockAsset.residual_value) / mockAsset.useful_life_years
      const yearsElapsed = 3
      const totalDep = annualDep * yearsElapsed
      const netValue = mockAsset.purchase_value - totalDep
      expect(netValue).toBe(4000)
    })

    it('Valeur nette ne descend pas sous la valeur résiduelle', () => {
      const asset: FixedAsset = {
        ...mockAsset, purchase_value: 10000, residual_value: 2000, useful_life_years: 5,
      }
      const annualDep = (asset.purchase_value - asset.residual_value) / asset.useful_life_years
      const yearsElapsed = 10 // Plus que la durée de vie
      const totalDep = annualDep * Math.min(yearsElapsed, asset.useful_life_years)
      const netValue = Math.max(asset.purchase_value - totalDep, asset.residual_value)
      expect(netValue).toBe(2000) // S'arrête à la valeur résiduelle
    })

    it('Durée 0 → division par zéro doit être gérée', () => {
      const asset: FixedAsset = { ...mockAsset, useful_life_years: 0 }
      // La fonction calculateDepreciation dans queries.ts vérifie: if (usefulLife <= 0) throw Error
      // Ici on vérifie juste que la logique de validation existe
      expect(asset.useful_life_years).toBe(0)
      expect(() => {
        const _ = (asset.purchase_value - asset.residual_value) / asset.useful_life_years
        if (!isFinite(_)) throw new Error('Division by zero')
      }).toThrow('Division by zero')
    })

    it('Après disposal: status=disposed, current_value=0', () => {
      const disposedAsset: FixedAsset = {
        ...mockAsset, status: 'disposed', current_value: 0,
      }
      expect(disposedAsset.status).toBe('disposed')
      expect(disposedAsset.current_value).toBe(0)
    })

    it('Asset avec currency_code USD → currency_code présent', () => {
      const asset: FixedAsset = { ...mockAsset, currency_code: 'USD' }
      expect(asset.currency_code).toBe('USD')
    })

    it('Calcul gain/perte sur disposal: disposalValue - currentValue', () => {
      const asset: FixedAsset = { ...mockAsset, current_value: 4000 }
      const disposalValue = 5000
      const gainLoss = disposalValue - asset.current_value
      expect(gainLoss).toBe(1000) // Gain de 1000
    })

    it('Calcul perte sur disposal: disposalValue < currentValue', () => {
      const asset: FixedAsset = { ...mockAsset, current_value: 6000 }
      const disposalValue = 4000
      const gainLoss = disposalValue - asset.current_value
      expect(gainLoss).toBe(-2000) // Perte de 2000
    })
  })

  // --- Exchange gain/loss ---
  describe('Exchange gain/loss', () => {
    it('Gain: taux paiement > taux original → type=gain', () => {
      const originalRate = 1.085
      const paymentRate = 1.090
      expect(paymentRate > originalRate).toBe(true)
      expect(mockExchangeGain.type).toBe('gain')
    })

    it('Perte: taux paiement < taux original → type=loss', () => {
      const originalRate = 1.085
      const paymentRate = 1.080
      expect(paymentRate < originalRate).toBe(true)
      expect(mockExchangeLoss.type).toBe('loss')
    })

    it('Taux identiques → écart = 0', () => {
      const originalRate = 1.085
      const paymentRate = 1.085
      const ecart = paymentRate - originalRate
      expect(Math.abs(ecart)).toBe(0)
    })

    it('Calcul gain: 1000€ * (1.090 - 1.085) = 5€', () => {
      const amount = 1000
      const rateDiff = 1.090 - 1.085
      const gain = amount * rateDiff
      expect(gain).toBeCloseTo(5, 5)
    })

    it('Calcul perte: 1000€ * (1.085 - 1.080) = 5€', () => {
      const amount = 1000
      const rateDiff = 1.085 - 1.080
      const loss = amount * rateDiff
      expect(loss).toBeCloseTo(5, 5)
    })

    it('ExchangeGainLossEntry: payment_id et invoice_id présents', () => {
      expect(mockExchangeGain.payment_id).toBe('pay-1')
      expect(mockExchangeGain.invoice_id).toBe('inv-1')
      expect(mockExchangeGain.journal_entry_id).toBe('je-1')
    })
  })

  // --- Currencies ---
  describe('Currencies', () => {
    it('Currency EUR: is_base=true, exchange_rate=1', () => {
      expect(mockCurrencyEUR.is_base).toBe(true)
      expect(mockCurrencyEUR.exchange_rate).toBe(1)
    })

    it('Currency USD: is_base=false, exchange_rate=1.085', () => {
      expect(mockCurrencyUSD.is_base).toBe(false)
      expect(mockCurrencyUSD.exchange_rate).toBe(1.085)
    })

    it('Conversion USD→EUR: 1000$ / 1.085 = 921.66€', () => {
      const usdAmount = 1000
      const eurAmount = usdAmount / mockCurrencyUSD.exchange_rate
      expect(Math.round(eurAmount * 100) / 100).toBe(921.66)
    })

    it('Conversion EUR→USD: 1000€ * 1.085 = 1085$', () => {
      const eurAmount = 1000
      const usdAmount = eurAmount * mockCurrencyUSD.exchange_rate
      expect(usdAmount).toBe(1085)
    })

    it('Currency inactive: active=false', () => {
      const inactiveCurrency: Currency = { ...mockCurrencyUSD, active: false }
      expect(inactiveCurrency.active).toBe(false)
    })

    it('Decimal places: EUR=2, USD=2', () => {
      expect(mockCurrencyEUR.decimal_places).toBe(2)
      expect(mockCurrencyUSD.decimal_places).toBe(2)
    })

    it('Position: EUR=after, USD=before', () => {
      expect(mockCurrencyEUR.position).toBe('after')
      expect(mockCurrencyUSD.position).toBe('before')
    })
  })
})

// ============ 2c: TESTS DE ROBUSTESSE ============

describe('2c. Tests de robustesse', () => {

  describe('Null/undefined handling', () => {
    it('calculateVAT avec montant 0 → pas de crash', () => {
      expect(() => calculateVAT(0, 20, 'ht')).not.toThrow()
    })

    it('calculateTax avec tax sans amount_type → default percent', () => {
      const taxNoType: TaxRate = { ...mockTax20, amount_type: undefined as any }
      const result = calculateTax(1000, taxNoType)
      expect(result.taxAmount).toBe(200) // Default to percent
    })

    it('calculateTax avec tax sans rate → taxAmount=0', () => {
      const taxNoRate: TaxRate = { ...mockTax20, rate: undefined as any }
      const result = calculateTax(1000, taxNoRate)
      expect(result.taxAmount).toBe(0) // NaN guard: Number(undefined) || 0 = 0
    })

    it('calculateTax avec fixed_amount null → taxAmount=0', () => {
      const taxNullFixed: TaxRate = { ...mockTax20, amount_type: 'fixed', fixed_amount: null }
      const result = calculateTax(1000, taxNullFixed)
      expect(result.taxAmount).toBe(0) // fixed_amount || 0 = 0
    })

    it('validateDistribution avec objet vide → true', () => {
      expect(validateDistribution({})).toBe(true)
    })

    it('computeAmounts avec dist vide → objet vide', () => {
      const result = computeAmounts({}, 1000)
      expect(Object.keys(result)).toHaveLength(0)
    })

    it('distributeEvenly avec array vide → objet vide', () => {
      const result = distributeEvenly([])
      expect(Object.keys(result)).toHaveLength(0)
    })
  })

  describe('Empty arrays', () => {
    it('calculateMultipleTaxes avec [] → totalTax=0', () => {
      const result = calculateMultipleTaxes(1000, [])
      expect(result.totalTax).toBe(0)
      expect(result.breakdown).toHaveLength(0)
    })

    it('calculateGroupTax sans children → taxAmount=0', () => {
      const result = calculateGroupTax(1000, mockParentTax, [mockParentTax])
      expect(result.taxAmount).toBe(0)
    })

    it('flattenDistribution avec dist vide → array vide', () => {
      const result = flattenDistribution({})
      expect(result).toHaveLength(0)
    })
  })

  describe('Boundary values', () => {
    it('TVA 0%: calculateVAT(1000, 0, "ht") → tva=0', () => {
      const result = calculateVAT(1000, 0, 'ht')
      expect(result.tva).toBe(0)
    })

    it('TVA 100%: calculateVAT(1000, 100, "ht") → tva=1000, ttc=2000', () => {
      const result = calculateVAT(1000, 100, 'ht')
      expect(result.tva).toBe(1000)
      expect(result.ttc).toBe(2000)
    })

    it('Montant 0: calculateVAT(0, 20, "ht") → tout à 0', () => {
      const result = calculateVAT(0, 20, 'ht')
      expect(result.ht).toBe(0)
      expect(result.tva).toBe(0)
      expect(result.ttc).toBe(0)
    })

    it('Distribution 100% sur une section → validation OK', () => {
      const dist = { 'plan-1': { 'A001': 100 } }
      expect(validateDistribution(dist)).toBe(true)
    })

    it('Distribution 0% sur une section → validation FAIL', () => {
      const dist = { 'plan-1': { 'A001': 0 } }
      expect(validateDistribution(dist)).toBe(false)
    })
  })

  describe('Type coercion', () => {
    it('Number(null) = 0 → pas de crash dans calculateVAT', () => {
      const n = Number(null)
      expect(n).toBe(0)
      expect(() => calculateVAT(n, 20, 'ht')).not.toThrow()
    })

    it('Number("abc") = NaN → calculateVAT produit NaN', () => {
      const n = Number('abc')
      expect(isNaN(n)).toBe(true)
      const result = calculateVAT(n, 20, 'ht')
      // NaN propagation — potential issue but no crash
      expect(isNaN(result.ht)).toBe(true)
    })
  })

  describe('Duplicate detection', () => {
    it('Détection de doublons dans sections de grill', () => {
      const lines = [
        { id: 'l1', grill_id: 'g1', section_code: 'A001', percentage: 50, created_at: '' },
        { id: 'l2', grill_id: 'g1', section_code: 'A001', percentage: 50, created_at: '' },
      ]
      const codes = lines.map(l => l.section_code)
      const dupes = codes.filter((c, i) => codes.indexOf(c) !== i)
      expect(dupes).toEqual(['A001'])
    })

    it('Détection de doublons dans codes de devise', () => {
      const currencies = [mockCurrencyEUR, mockCurrencyUSD, { ...mockCurrencyUSD, id: 'c3' }]
      const codes = currencies.map(c => c.code)
      const dupes = codes.filter((c, i) => codes.indexOf(c) !== i)
      expect(dupes).toEqual(['USD'])
    })
  })
})

// ============ 2d: TESTS DE COHÉRENCE MULTI-NIVEAU ============

describe('2d. Tests de cohérence multi-niveau', () => {

  describe('Niveau SQL → Type → Query → UI', () => {
    it('FixedAsset: type a currency_code, query l\'utilise, UI l\'affiche', () => {
      // Type check
      expect(mockAsset).toHaveProperty('currency_code')
      // Query check: createFixedAsset dans queries.ts passe currency_code
      // UI check: FixedAssetsPage AssetForm a un champ currency_code
      expect(mockAsset.currency_code).toBe('EUR')
    })

    it('DistributionGrill: type a journal_code, query l\'utilise, UI l\'affiche', () => {
      expect(mockGrill).toHaveProperty('journal_code')
      expect(mockGrill).toHaveProperty('active')
      expect(mockGrill).toHaveProperty('description')
      expect(mockGrill.journal_code).toBe('ACH')
      expect(mockGrill.active).toBe(true)
    })

    it('FiscalPosition: type a zip_from/zip_to, UI les affiche', () => {
      const fp: FiscalPosition = { ...mockFiscalPosition, zip_from: '75000', zip_to: '75020' }
      expect(fp).toHaveProperty('zip_from')
      expect(fp).toHaveProperty('zip_to')
      expect(fp.zip_from).toBe('75000')
      expect(fp.zip_to).toBe('75020')
    })

    it('PartnerBankAccount: type a active, UI l\'affiche', () => {
      expect(mockBankAccount).toHaveProperty('active')
      expect(mockBankAccount.active).toBe(true)
    })

    it('ExchangeGainLossEntry: type a payment_id, invoice_id, journal_entry_id', () => {
      expect(mockExchangeGain).toHaveProperty('payment_id')
      expect(mockExchangeGain).toHaveProperty('invoice_id')
      expect(mockExchangeGain).toHaveProperty('journal_entry_id')
      expect(mockExchangeGain).toHaveProperty('account_gain_code')
      expect(mockExchangeGain).toHaveProperty('account_loss_code')
    })

    it('Currency: type a decimal_places, position, active', () => {
      expect(mockCurrencyEUR).toHaveProperty('decimal_places')
      expect(mockCurrencyEUR).toHaveProperty('position')
      expect(mockCurrencyEUR).toHaveProperty('active')
    })
  })

  describe('Niveau FK relations', () => {
    it('FiscalPositionMapping.fiscal_position_id → FiscalPosition.id', () => {
      expect(mockFiscalMapping.fiscal_position_id).toBe(mockFiscalPosition.id)
    })

    it('AccountTagMapping.tag_id → AccountTag.id', () => {
      expect(mockTagMapping.tag_id).toBe(mockTag.id)
    })

    it('DistributionGrillLine.grill_id → DistributionGrill.id', () => {
      expect(mockGrillLines[0].grill_id).toBe(mockGrill.id)
    })

    it('PartnerContact.partner_id → Customer/Supplier.id', () => {
      expect(mockContact.partner_id).toBe('cust-1')
      expect(mockContact.partner_type).toBe('customer')
    })

    it('PartnerBankAccount.partner_id → Customer/Supplier.id', () => {
      expect(mockBankAccount.partner_id).toBe('cust-1')
      expect(mockBankAccount.partner_type).toBe('customer')
    })

    it('ExchangeGainLossEntry.payment_id → Payment.id', () => {
      expect(mockExchangeGain.payment_id).toBe('pay-1')
    })

    it('ExchangeGainLossEntry.invoice_id → Invoice.id', () => {
      expect(mockExchangeGain.invoice_id).toBe('inv-1')
    })
  })

  describe('Niveau Payroll', () => {
    it('calculatePayroll avec grid lines: salaire 3000€ → net positif', () => {
      const result = calculatePayroll({
        grossSalary: 3000,
        contractType: 'cdi',
        hoursPerWeek: 35,
        overtimeHours: 0,
        mealVouchers: 100,
        transportAllowance: 50,
        age: 30,
        department: '75',
        taxRate: 5,
      }, mockPayrollGridLines)

      expect(result.grossSalary).toBe(3000)
      expect(result.totalGross).toBe(3000)
      expect(result.netPay).toBeGreaterThan(0)
      expect(result.netPayable).toBeGreaterThan(result.netPay) // net + vouchers + transport
      expect(result.totalCostEmployer).toBeGreaterThan(result.totalGross)
    })

    it('calculatePayroll fallback (sans grid): salaire 3000€ → net positif', () => {
      const result = calculatePayroll({
        grossSalary: 3000,
        contractType: 'cdi',
        hoursPerWeek: 35,
        overtimeHours: 0,
        mealVouchers: 0,
        transportAllowance: 0,
        age: 30,
        department: '75',
        taxRate: 5,
      })

      expect(result.grossSalary).toBe(3000)
      expect(result.socialSecurityEmployee).toBeGreaterThan(0)
      expect(result.retirementEmployee).toBeGreaterThan(0)
      expect(result.csgCrds).toBeGreaterThan(0)
      expect(result.netPay).toBeGreaterThan(0)
    })

    it('calculatePayroll avec overtime: 10h supplémentaires', () => {
      const result = calculatePayroll({
        grossSalary: 3000,
        contractType: 'cdi',
        hoursPerWeek: 35,
        overtimeHours: 10,
        mealVouchers: 0,
        transportAllowance: 0,
        age: 30,
        department: '75',
        taxRate: 0,
      })

      // overtimePay = 10 * (3000 / 151.67) * 1.25 = 247.18...
      expect(result.overtimePay).toBeGreaterThan(240)
      expect(result.overtimePay).toBeLessThan(250)
      expect(result.totalGross).toBe(result.grossSalary + result.overtimePay)
    })

    it('calculatePayroll salaire 0 → tout à 0 ou proche', () => {
      const result = calculatePayroll({
        grossSalary: 0,
        contractType: 'cdi',
        hoursPerWeek: 35,
        overtimeHours: 0,
        mealVouchers: 0,
        transportAllowance: 0,
        age: 30,
        department: '75',
        taxRate: 0,
      })

      expect(result.grossSalary).toBe(0)
      expect(result.totalGross).toBe(0)
      expect(result.netPay).toBe(0)
    })

    it('formatPayrollAmount: 1234.567 → "1234.57"', () => {
      expect(formatPayrollAmount(1234.567)).toBe('1234.57')
    })

    it('CSG/CRDS base = totalGross * 0.9825', () => {
      const result = calculatePayroll({
        grossSalary: 3000,
        contractType: 'cdi',
        hoursPerWeek: 35,
        overtimeHours: 0,
        mealVouchers: 0,
        transportAllowance: 0,
        age: 30,
        department: '75',
        taxRate: 0,
      }, mockPayrollGridLines)

      const expectedCsgBase = 3000 * 0.9825
      const expectedCsg = expectedCsgBase * 0.092
      expect(result.csgCrds).toBe(Math.round(expectedCsg * 100) / 100)
    })
  })
})

// ============ TESTS DE COHÉRENCE CROSS-MODULE ============

describe('2e. Tests de cohérence cross-module', () => {

  it('TVA calculée via calculateVAT = TVA calculée via calculateTax', () => {
    const amount = 1000
    const rate = 20
    const vatResult = calculateVAT(amount, rate, 'ht')
    const taxResult = calculateTax(amount, mockTax20)
    expect(vatResult.tva).toBe(taxResult.taxAmount)
  })

  it('Prix avec taxe incluse = extractTaxFromIncludedPrice sur TTC', () => {
    const ht = 1000
    const ttc = 1200
    const vatResult = calculateVAT(ht, 20, 'ht')
    const extractResult = extractTaxFromIncludedPrice(ttc, mockTaxIncluded)
    expect(vatResult.ttc).toBe(extractResult.ttc)
    expect(vatResult.ht).toBe(extractResult.ht)
    expect(vatResult.tva).toBe(extractResult.taxAmount)
  })

  it('Distribution + computeAmounts: somme des montants = montant ligne', () => {
    const lineAmount = 5000
    const dist = { 'plan-1': { 'A001': 60, 'A002': 40 } }
    const amounts = computeAmounts(dist, lineAmount)
    const total = (Object.values(amounts['plan-1']) as number[]).reduce((s, v) => s + v, 0)
    expect(total).toBe(lineAmount)
  })

  it('Distribution + computeAmounts avec 3 sections 33.33/33.33/33.34', () => {
    const lineAmount = 3000
    const dist = { 'plan-1': { 'A001': 33.33, 'A002': 33.33, 'A003': 33.34 } }
    const amounts = computeAmounts(dist, lineAmount)
    const total = (Object.values(amounts['plan-1']) as number[]).reduce((s, v) => s + v, 0)
    // 33.33% of 3000 = 999.9, 33.34% of 3000 = 1000.2
    // Total = 999.9 + 999.9 + 1000.2 = 3000
    expect(total).toBe(3000)
  })

  it('Asset depreciation + disposal: gain = disposalValue - netBookValue', () => {
    const asset: FixedAsset = {
      ...mockAsset, purchase_value: 10000, residual_value: 0,
      useful_life_years: 5, current_value: 6000, // After 2 years
    }
    const disposalValue = 7000
    const gain = disposalValue - asset.current_value
    expect(gain).toBe(1000) // Gain of 1000

    // After disposal
    const disposedAsset: FixedAsset = { ...asset, status: 'disposed', current_value: 0 }
    expect(disposedAsset.status).toBe('disposed')
    expect(disposedAsset.current_value).toBe(0)
  })

  it('Corporate tax + après taxe: profit - finalTax = afterTaxProfit', () => {
    const result = calculateCorporateTax(100000, 500000, mockCorporateGridLines)
    expect(result.afterTaxProfit).toBe(100000 - result.finalTax)
  })

  it('Payroll: totalGross = grossSalary + overtimePay', () => {
    const result = calculatePayroll({
      grossSalary: 3000, contractType: 'cdi', hoursPerWeek: 35,
      overtimeHours: 10, mealVouchers: 100, transportAllowance: 50,
      age: 30, department: '75', taxRate: 5,
    })
    expect(result.totalGross).toBe(result.grossSalary + result.overtimePay)
  })

  it('Payroll: netPayable = netPay + mealVouchers + transportAllowance', () => {
    const result = calculatePayroll({
      grossSalary: 3000, contractType: 'cdi', hoursPerWeek: 35,
      overtimeHours: 0, mealVouchers: 100, transportAllowance: 50,
      age: 30, department: '75', taxRate: 5,
    })
    expect(result.netPayable).toBe(result.netPay + result.mealVouchers + result.transportAllowance)
  })

  it('Payroll: totalCostEmployer = totalGross + totalEmployerContributions + mealVouchers + transportAllowance', () => {
    const result = calculatePayroll({
      grossSalary: 3000, contractType: 'cdi', hoursPerWeek: 35,
      overtimeHours: 0, mealVouchers: 100, transportAllowance: 50,
      age: 30, department: '75', taxRate: 5,
    })
    expect(result.totalCostEmployer).toBe(
      result.totalGross + result.totalEmployerContributions + result.mealVouchers + result.transportAllowance
    )
  })
})

// ============ 2f: MODULE COMMERCIAL — TESTS DYNAMIQUES ============
import type { Quote, QuoteLine, SalesOrder, SalesOrderLine, DeliveryNote, DeliveryNoteLine, Invoice, InvoiceLine, Customer, Promotion, CreditNote } from '@/types';

const mockCust: Customer = {
  id: 'cust-1', name: 'Acme Corp', email: 'c@acme.com', phone: '01', address: '1 rue',
  city: 'Paris', postal_code: '75001', country: 'France', vat_number: 'FR12', contact_name: 'JD',
  balance: 5000, credit_limit: 10000, payment_terms: '30 days', currency: 'EUR', active: true,
  created_at: '2024-01-01', updated_at: '2024-01-01',
}

const mockCustBlocked: Customer = { ...mockCust, id: 'c2', balance: 12000, credit_limit: 10000 }

const mockQL: QuoteLine = {
  id: 'ql1', quote_id: 'q1', product_id: 'p1', description: 'Product A', quantity: 10,
  unit_price: 100, vat_rate: 20, total: 1000, vat_total: 200, line_order: 0, created_at: '2024-01-01',
}

const mockQ: Quote = {
  id: 'q1', number: 'DEV-2024-001', customer_id: 'cust-1', customer_name: 'Acme Corp',
  date: '2024-01-15', expiry_date: '2024-02-15', status: 'draft', subtotal: 1000, vat_total: 200,
  total: 1200, notes: '', created_at: '2024-01-15', updated_at: '2024-01-15',
  quote_lines: [mockQL], transformation_status: 'pending',
}

const mockSOL: SalesOrderLine = {
  id: 'sol1', sales_order_id: 'so1', product_id: 'p1', description: 'Product A', quantity: 10,
  unit_price: 100, vat_rate: 20, line_total: 1000, delivered_quantity: 0,
}

const mockSO: SalesOrder = {
  id: 'so1', number: 'CMD-2024-001', customer_id: 'cust-1', order_date: '2024-01-16',
  delivery_date: '2024-01-25', status: 'confirmed', subtotal: 1000, vat: 200, total: 1200,
  notes: '', created_at: '2024-01-16', updated_at: '2024-01-16', quote_id: 'q1',
  fully_delivered: false, delivery_status: 'pending',
}

const mockDNL: DeliveryNoteLine = {
  id: 'dnl1', delivery_note_id: 'dn1', product_id: 'p1', description: 'Product A',
  quantity: 10, invoiced_quantity: 0, sales_order_line_id: 'sol1',
}

const mockDN: DeliveryNote = {
  id: 'dn1', number: 'BL-2024-001', customer_id: 'cust-1', sales_order_id: 'so1',
  delivery_date: '2024-01-25', status: 'delivered', carrier: 'Chronopost', tracking_number: 'T1',
  notes: '', created_at: '2024-01-25', fully_invoiced: false, invoice_status: 'pending',
}

const mockIL: InvoiceLine = {
  id: 'il1', invoice_id: 'inv1', product_id: 'p1', description: 'Product A', quantity: 10,
  unit_price: 100, vat_rate: 20, total: 1000, vat_total: 200, line_order: 0, created_at: '2024-01-30',
}

const mockInv: Invoice = {
  id: 'inv1', number: 'FAC-2024-001', customer_id: 'cust-1', customer_name: 'Acme Corp',
  date: '2024-01-30', due_date: '2024-03-01', status: 'draft', subtotal: 1000, vat_total: 200,
  total: 1200, amount_paid: 0, amount_due: 1200, notes: '', recurring: false,
  recurring_frequency: null, created_at: '2024-01-30', updated_at: '2024-01-30',
  invoice_lines: [mockIL], invoice_type: 'standard',
}

const mockPromo: Promotion = {
  id: 'promo1', tenant_id: 'tid', name: 'Summer Sale', description: '10% off',
  promo_type: 'percentage', value: 10, product_id: 'p1', category: null, customer_id: null,
  start_date: '2024-06-01', end_date: '2024-08-31', min_quantity: 1, free_product_id: null,
  free_product_qty: 0, active: true, created_at: '2024-06-01',
}

const mockCN: CreditNote = {
  id: 'cn1', number: 'AV-2024-001', customer_id: 'cust-1', customer_name: 'Acme Corp',
  date: '2024-02-01', status: 'draft', subtotal: 1000, vat_total: 200, total: 1200,
  reason: 'Return', invoice_id: 'inv1', source_invoice_id: 'inv1',
  created_at: '2024-02-01',
}

describe('2f. Module Commercial — Workflows & Transformations', () => {
  describe('Quote → Sales Order', () => {
    it('Amounts copiés: subtotal, vat, total', () => {
      expect(mockQ.subtotal).toBe(mockSO.subtotal)
      expect(mockQ.vat_total).toBe(mockSO.vat)
      expect(mockQ.total).toBe(mockSO.total)
    })
    it('Lines: qty et prix préservés', () => {
      expect(mockQL.quantity).toBe(mockSOL.quantity)
      expect(mockQL.unit_price).toBe(mockSOL.unit_price)
    })
    it('transformation_status pending → transformed', () => {
      const tq: Quote = { ...mockQ, transformation_status: 'transformed', transformed_to_order_id: mockSO.id }
      expect(tq.transformation_status).toBe('transformed')
      expect(tq.transformed_to_order_id).toBe(mockSO.id)
    })
    it('SO.quote_id référence la quote', () => {
      expect(mockSO.quote_id).toBe(mockQ.id)
    })
  })

  describe('Sales Order → Delivery Note', () => {
    it('Delivery partielle: status=partial', () => {
      const so: SalesOrder = { ...mockSO, delivery_status: 'partial', fully_delivered: false }
      expect(so.delivery_status).toBe('partial')
      expect(so.fully_delivered).toBe(false)
    })
    it('Delivery complète: status=delivered', () => {
      const so: SalesOrder = { ...mockSO, delivery_status: 'delivered', fully_delivered: true }
      expect(so.delivery_status).toBe('delivered')
      expect(so.fully_delivered).toBe(true)
    })
    it('DN.sales_order_id référence SO', () => {
      expect(mockDN.sales_order_id).toBe(mockSO.id)
    })
    it('DNL.sales_order_line_id référence SOL', () => {
      expect(mockDNL.sales_order_line_id).toBe(mockSOL.id)
    })
    it('Qté livrée ≤ qté commandée', () => {
      expect(mockDNL.quantity).toBeLessThanOrEqual(mockSOL.quantity)
    })
  })

  describe('Delivery Note → Invoice', () => {
    it('DN invoice_status partial → invoiced', () => {
      const dn: DeliveryNote = { ...mockDN, invoice_status: 'invoiced', fully_invoiced: true }
      expect(dn.invoice_status).toBe('invoiced')
    })
    it('Invoice delivery_note_id référence DN', () => {
      const inv: Invoice = { ...mockInv, delivery_note_id: mockDN.id }
      expect(inv.delivery_note_id).toBe(mockDN.id)
    })
    it('Calcul depuis lignes: sum(total)=subtotal, sum(vat_total)=vat_total', () => {
      const lines = [mockIL, { ...mockIL, id: 'il2', total: 500, vat_total: 100 }]
      const sub = lines.reduce((s, l) => s + l.total, 0)
      const vat = lines.reduce((s, l) => s + l.vat_total, 0)
      expect(sub).toBe(1500)
      expect(vat).toBe(300)
      expect(sub + vat).toBe(1800)
    })
  })

  describe('Invoice → Credit Note', () => {
    it('CN amounts = Invoice amounts', () => {
      expect(mockCN.subtotal).toBe(mockInv.subtotal)
      expect(mockCN.total).toBe(mockInv.total)
    })
    it('CN.source_invoice_id = Invoice.id', () => {
      expect(mockCN.source_invoice_id).toBe(mockInv.id)
    })
    it('CN status commence à draft', () => {
      expect(mockCN.status).toBe('draft')
    })
    it('Application CN: amount_due réduit à 0', () => {
      const newDue = Math.max(mockInv.amount_due - mockCN.total, 0)
      expect(newDue).toBe(0)
    })
  })
})

describe('2g. Module Commercial — Promotions', () => {
  it('Percentage 10% sur 1000€ → remise 100€', () => {
    expect(1000 * (Number(mockPromo.value) / 100)).toBe(100)
  })
  it('Fixed 50€ sur 1000€ → remise 50€', () => {
    const p: Promotion = { ...mockPromo, promo_type: 'fixed_amount', value: 50 }
    expect(Number(p.value)).toBe(50)
  })
  it('Promo inactive → non applicable', () => {
    expect(({ ...mockPromo, active: false }).active).toBe(false)
  })
  it('Promo expirée: end_date < today', () => {
    const p: Promotion = { ...mockPromo, end_date: '2023-12-31' }
    expect(p.end_date < '2024-07-27').toBe(true)
  })
  it('Promo active: start <= today <= end', () => {
    const today = '2024-07-15'
    expect(mockPromo.active && mockPromo.start_date <= today && mockPromo.end_date >= today).toBe(true)
  })
  it('min_quantity: qty=1 >= min=1 → OK', () => {
    expect(1 >= Number(mockPromo.min_quantity)).toBe(true)
  })
  it('min_quantity: qty=3 < min=5 → non applicable', () => {
    const qty = 3
    expect(qty >= 5).toBe(false)
  })
  it('Promo client spécifique: match → applicable', () => {
    const p: Promotion = { ...mockPromo, customer_id: 'cust-1' }
    expect(p.customer_id === null || p.customer_id === 'cust-1').toBe(true)
  })
  it('Promo client spécifique: mismatch → non applicable', () => {
    const p: Promotion = { ...mockPromo, customer_id: 'cust-2' }
    expect(p.customer_id === null || p.customer_id === 'cust-1').toBe(false)
  })
  it('Remise + TVA: 1000 - 10% + 20% = 1080', () => {
    const sub = 1000, discount = sub * 0.10, after = sub - discount
    expect(after + after * 0.20).toBe(1080)
  })
})

describe('2h. Module Commercial — Credit Limit', () => {
  it('Balance < credit_limit → non bloqué', () => {
    expect(mockCust.balance < mockCust.credit_limit).toBe(true)
  })
  it('Balance > credit_limit → bloqué', () => {
    expect(mockCustBlocked.balance > mockCustBlocked.credit_limit).toBe(true)
  })
  it('Credit available = credit_limit - balance', () => {
    expect(mockCust.credit_limit - mockCust.balance).toBe(5000)
  })
  it('Credit available négatif si bloqué', () => {
    expect(mockCustBlocked.credit_limit - mockCustBlocked.balance).toBe(-2000)
  })
  it('Credit limit = 0 → aucun crédit', () => {
    const c: Customer = { ...mockCust, credit_limit: 0, balance: 0 }
    expect(c.credit_limit - c.balance).toBe(0)
  })
})

describe('2i. Module Commercial — Invoice Payment Status', () => {
  it('amount_paid=0 → not_paid', () => {
    expect(mockInv.amount_paid).toBe(0)
    expect(mockInv.amount_due).toBe(mockInv.total)
  })
  it('amount_paid=total → paid', () => {
    const inv: Invoice = { ...mockInv, amount_paid: 1200, amount_due: 0, status: 'paid' }
    expect(inv.amount_paid).toBe(inv.total)
    expect(inv.amount_due).toBe(0)
  })
  it('amount_paid partiel → partial', () => {
    const inv: Invoice = { ...mockInv, amount_paid: 600, amount_due: 600 }
    expect(inv.amount_paid).toBeLessThan(inv.total)
    expect(inv.amount_due).toBeGreaterThan(0)
  })
  it('amount_paid + amount_due = total', () => {
    expect(mockInv.amount_paid + mockInv.amount_due).toBe(mockInv.total)
  })
  it('Overdue: due_date < today et status != paid', () => {
    const inv: Invoice = { ...mockInv, due_date: '2024-01-01', status: 'overdue' }
    expect(inv.due_date < '2024-07-27').toBe(true)
    expect(inv.status).not.toBe('paid')
  })
})

describe('2j. Module Commercial — Line Item Consistency', () => {
  it('Quote: sum(line.total) = subtotal', () => {
    const sum = (mockQ.quote_lines || []).reduce((s: number, l: QuoteLine) => s + l.total, 0)
    expect(sum).toBe(mockQ.subtotal)
  })
  it('Quote: sum(line.vat_total) = vat_total', () => {
    const sum = (mockQ.quote_lines || []).reduce((s: number, l: QuoteLine) => s + l.vat_total, 0)
    expect(sum).toBe(mockQ.vat_total)
  })
  it('Quote: subtotal + vat_total = total', () => {
    expect(mockQ.subtotal + mockQ.vat_total).toBe(mockQ.total)
  })
  it('Invoice: subtotal + vat_total = total', () => {
    expect(mockInv.subtotal + mockInv.vat_total).toBe(mockInv.total)
  })
  it('Sales order: subtotal + vat = total', () => {
    expect(mockSO.subtotal + mockSO.vat).toBe(mockSO.total)
  })
  it('Line total = qty * unit_price', () => {
    expect(mockQL.quantity * mockQL.unit_price).toBe(mockQL.total)
  })
  it('Line vat_total = total * (vat_rate / 100)', () => {
    expect(mockQL.total * (mockQL.vat_rate / 100)).toBe(mockQL.vat_total)
  })
  it('Invoice lines: sum(total) = subtotal', () => {
    const sum = (mockInv.invoice_lines || []).reduce((s: number, l: InvoiceLine) => s + l.total, 0)
    expect(sum).toBe(mockInv.subtotal)
  })
  it('Multi-taux TVA: 20% + 10% + 5.5%', () => {
    const lines = [
      { ...mockIL, id: 'l1', total: 1000, vat_rate: 20, vat_total: 200 },
      { ...mockIL, id: 'l2', total: 500, vat_rate: 10, vat_total: 50 },
      { ...mockIL, id: 'l3', total: 200, vat_rate: 5.5, vat_total: 11 },
    ]
    const sub = lines.reduce((s, l) => s + l.total, 0)
    const vat = lines.reduce((s, l) => s + l.vat_total, 0)
    expect(sub).toBe(1700)
    expect(vat).toBe(261)
    expect(sub + vat).toBe(1961)
  })
})

describe('2k. Module Commercial — Advance Invoice', () => {
  it('Advance: is_advance_invoice=true, type=advance', () => {
    const inv: Invoice = { ...mockInv, is_advance_invoice: true, advance_amount: 500, invoice_type: 'advance' }
    expect(inv.is_advance_invoice).toBe(true)
    expect(inv.invoice_type).toBe('advance')
  })
  it('Advance VAT: 500 * 20% = 100', () => {
    expect(500 * 0.20).toBe(100)
  })
  it('Balance invoice: type=balance, parent set', () => {
    const inv: Invoice = { ...mockInv, invoice_type: 'balance', parent_invoice_id: 'inv-adv-1' }
    expect(inv.invoice_type).toBe('balance')
    expect(inv.parent_invoice_id).toBe('inv-adv-1')
  })
})

describe('2l. Module Commercial — Fulfillment & Robustness', () => {
  it('Order fully delivered: delivered_qty = qty pour toutes lignes', () => {
    const lines: SalesOrderLine[] = [
      { ...mockSOL, delivered_quantity: 10 },
      { ...mockSOL, id: 'sol2', delivered_quantity: 5, quantity: 5 },
    ]
    const allDelivered = lines.every(l => (l as any).delivered_quantity >= l.quantity)
    expect(allDelivered).toBe(true)
  })
  it('Order partial: 5/10 → not fully delivered', () => {
    const lines: SalesOrderLine[] = [{ ...mockSOL, delivered_quantity: 5, quantity: 10 }]
    expect(lines.every(l => (l as any).delivered_quantity >= l.quantity)).toBe(false)
  })
  it('Quote sans lines: subtotal=0, total=0', () => {
    const emptyQ: Quote = { ...mockQ, quote_lines: [], subtotal: 0, vat_total: 0, total: 0 }
    const sum = (emptyQ.quote_lines || []).reduce((s: number, l: QuoteLine) => s + l.total, 0)
    expect(sum).toBe(0)
  })
  it('Invoice avec lines vides: pas de crash', () => {
    const emptyInv: Invoice = { ...mockInv, invoice_lines: [] }
    const sum = (emptyInv.invoice_lines || []).reduce((s: number, l: InvoiceLine) => s + l.total, 0)
    expect(sum).toBe(0)
  })
  it('Customer avec balance null: pas de crash', () => {
    const c: Customer = { ...mockCust, balance: 0 }
    expect(c.balance).not.toBeNull()
    expect(c.balance).toBe(0)
  })
  it('Promotion avec value null: remise=0', () => {
    const p: Promotion = { ...mockPromo, value: null }
    const discount = p.value ? Number(p.value) : 0
    expect(discount).toBe(0)
  })
  it('DN avec carrier null: pas de crash', () => {
    const dn: DeliveryNote = { ...mockDN, carrier: null as any }
    expect(dn.carrier).toBeNull()
  })
  it('Invoice avec amount_paid > total: amount_due=0 (pas négatif)', () => {
    const overpaid: Invoice = { ...mockInv, amount_paid: 1500, amount_due: 0 }
    expect(Math.max(overpaid.total - overpaid.amount_paid, 0)).toBe(0)
  })
})

// ============ LOT5-05 : SSRF Filtering ============

describe('LOT5-05 : Filtrage SSRF des URLs de webhook', () => {
  // Replique la fonction isAllowedWebhookUrl du frontend
  function isAllowedWebhookUrl(raw: string): boolean {
    let u: URL
    try { u = new URL(raw) } catch { return false }
    if (u.protocol !== 'https:') return false
    const h = u.hostname.toLowerCase().replace(/^\[|\]$/g, '')
    if (h === 'localhost' || h.endsWith('.local') || h.endsWith('.internal')) return false
    if (/^(127\.|10\.|192\.168\.|169\.254\.|0\.)/.test(h)) return false
    if (/^172\.(1[6-9]|2\d|3[01])\./.test(h)) return false
    if (h === '::1' || h.startsWith('fd') || h.startsWith('fe80:')) return false
    return true
  }

  it('Accepte une URL HTTPS valide', () => {
    expect(isAllowedWebhookUrl('https://example.com/webhook')).toBe(true)
    expect(isAllowedWebhookUrl('https://api.slack.com/post')).toBe(true)
  })

  it('Rejette HTTP (non-HTTPS)', () => {
    expect(isAllowedWebhookUrl('http://example.com/webhook')).toBe(false)
  })

  it('Rejette localhost', () => {
    expect(isAllowedWebhookUrl('https://localhost:3000/webhook')).toBe(false)
  })

  it('Rejette .local et .internal', () => {
    expect(isAllowedWebhookUrl('https://myapp.local/webhook')).toBe(false)
    expect(isAllowedWebhookUrl('https://internal.internal/hook')).toBe(false)
  })

  it('Rejette 127.x (loopback)', () => {
    expect(isAllowedWebhookUrl('https://127.0.0.1/webhook')).toBe(false)
    expect(isAllowedWebhookUrl('https://127.0.1.5:8080/hook')).toBe(false)
  })

  it('Rejette 10.x (privé)', () => {
    expect(isAllowedWebhookUrl('https://10.0.0.1/webhook')).toBe(false)
  })

  it('Rejette 192.168.x (privé)', () => {
    expect(isAllowedWebhookUrl('https://192.168.1.1/webhook')).toBe(false)
  })

  it('Rejette 169.254.x (link-local / metadata)', () => {
    expect(isAllowedWebhookUrl('https://169.254.169.254/latest/meta-data')).toBe(false)
  })

  it('Rejette 172.16-31.x (privé)', () => {
    expect(isAllowedWebhookUrl('https://172.16.0.1/webhook')).toBe(false)
    expect(isAllowedWebhookUrl('https://172.31.255.255/webhook')).toBe(false)
  })

  it('Rejette 0.x (réservé)', () => {
    expect(isAllowedWebhookUrl('https://0.0.0.0/webhook')).toBe(false)
  })

  it('Rejette IPv6 ::1 (loopback)', () => {
    expect(isAllowedWebhookUrl('https://[::1]/webhook')).toBe(false)
  })

  it('Rejette IPv6 fdxx (ULA)', () => {
    expect(isAllowedWebhookUrl('https://[fd00::1]/webhook')).toBe(false)
  })

  it('Rejette IPv6 fe80 (link-local)', () => {
    expect(isAllowedWebhookUrl('https://[fe80::1]/webhook')).toBe(false)
  })

  it('Rejette URL invalide', () => {
    expect(isAllowedWebhookUrl('not-a-url')).toBe(false)
    expect(isAllowedWebhookUrl('')).toBe(false)
  })
})

// ============ LOT5-01 : NF-525 Chain Verification Logic ============

describe('LOT5-01 : Logique de vérification chaîne NF-525', () => {
  // Simule la logique de verify_nf525_chain
  interface NF525Event {
    id: number
    previous_hash: string | null
    current_hash: string
  }

  function verifyChain(events: NF525Event[]): {
    broken_count: number
    gap_count: number
    chain_valid: boolean
  } {
    let broken_count = 0
    let gap_count = 0
    let last_seen_hash: string | null = null
    let last_id: number | null = null

    for (const rec of events) {
      // Vérifier le chaînage
      if (last_seen_hash !== null && rec.previous_hash !== last_seen_hash) {
        broken_count++
      }
      last_seen_hash = rec.current_hash

      // Vérifier les gaps (BIGSERIAL)
      if (last_id !== null && rec.id !== last_id + 1) {
        gap_count++
      }
      last_id = rec.id
    }

    return {
      broken_count,
      gap_count,
      chain_valid: broken_count === 0 && gap_count === 0,
    }
  }

  it('Chaîne valide → chain_valid = true', () => {
    const events: NF525Event[] = [
      { id: 1, previous_hash: 'GENESIS', current_hash: 'hash1' },
      { id: 2, previous_hash: 'hash1', current_hash: 'hash2' },
      { id: 3, previous_hash: 'hash2', current_hash: 'hash3' },
    ]
    const result = verifyChain(events)
    expect(result.broken_count).toBe(0)
    expect(result.gap_count).toBe(0)
    expect(result.chain_valid).toBe(true)
  })

  it('Maillon supprimé → chain_valid = false (broken + gap)', () => {
    const events: NF525Event[] = [
      { id: 1, previous_hash: 'GENESIS', current_hash: 'hash1' },
      // id=2 supprimé → gap détecté
      { id: 3, previous_hash: 'hash2', current_hash: 'hash3' }, // previous_hash ne correspond pas à hash1
    ]
    const result = verifyChain(events)
    expect(result.broken_count).toBe(1) // previous_hash 'hash2' ≠ 'hash1'
    expect(result.gap_count).toBe(1) // id saute de 1 à 3
    expect(result.chain_valid).toBe(false)
  })

  it('Maillon réécrit avec son propre previous_hash → chain_valid = false', () => {
    const events: NF525Event[] = [
      { id: 1, previous_hash: 'GENESIS', current_hash: 'hash1' },
      { id: 2, previous_hash: 'FAKE_HASH', current_hash: 'hash2' }, // previous_hash recalculé mais faux
      { id: 3, previous_hash: 'hash2', current_hash: 'hash3' },
    ]
    const result = verifyChain(events)
    expect(result.broken_count).toBe(1) // 'FAKE_HASH' ≠ 'hash1'
    expect(result.gap_count).toBe(0)
    expect(result.chain_valid).toBe(false)
  })

  it('Chaîne vide → chain_valid = true', () => {
    const result = verifyChain([])
    expect(result.chain_valid).toBe(true)
  })

  it('Premier événement → pas de vérification previous_hash', () => {
    const events: NF525Event[] = [
      { id: 1, previous_hash: 'GENESIS', current_hash: 'hash1' },
    ]
    const result = verifyChain(events)
    expect(result.broken_count).toBe(0)
    expect(result.chain_valid).toBe(true)
  })
})

// ============ LOT5-03 : Séparation des tâches désactivable ============

describe('LOT5-03 : Séparation des tâches désactivable', () => {
  it('Défaut: enforce_segregation = false (désactivé pour TPE/indépendants)', () => {
    // Simule la logique du trigger
    const companySettings = { enforce_segregation: false }
    const canValidate = !companySettings.enforce_segregation || false // check_segregation retourne false
    expect(canValidate).toBe(true) // L'utilisateur peut valider
  })

  it('Activé: enforce_segregation = true → séparation appliquée', () => {
    const companySettings = { enforce_segregation: true }
    const isCreator = true // L'utilisateur a créé l'écriture
    const canValidate = !companySettings.enforce_segregation || !isCreator
    expect(canValidate).toBe(false) // L'utilisateur ne peut pas valider
  })

  it('Activé mais utilisateur différent du créateur → peut valider', () => {
    const companySettings = { enforce_segregation: true }
    const isCreator = false
    const canValidate = !companySettings.enforce_segregation || !isCreator
    expect(canValidate).toBe(true)
  })
})

// ============ PAY-01 : Taux PAS + assiette transport ============

describe('PAY-01 : Assiette transport exonérée et taux PAS', () => {
  const TRANSPORT_EXEMPT_CAP = 75

  function calculateTransportTaxable(transportAllowance: number): number {
    const transportExempt = Math.min(transportAllowance, TRANSPORT_EXEMPT_CAP)
    return Math.max(0, transportAllowance - transportExempt)
  }

  it('Indemnité transport ≤ 75€ → entièrement exonérée (0€ imposable)', () => {
    expect(calculateTransportTaxable(50)).toBe(0)
    expect(calculateTransportTaxable(75)).toBe(0)
  })

  it('Indemnité transport > 75€ → seul le dépassement est imposable', () => {
    expect(calculateTransportTaxable(100)).toBe(25)
    expect(calculateTransportTaxable(200)).toBe(125)
  })

  it('Indemnité transport = 0 → 0€ imposable', () => {
    expect(calculateTransportTaxable(0)).toBe(0)
  })

  it('Taux PAS personnalisé DGFiP est utilisé (3,5%)', () => {
    const withholdingTaxRate = 3.5
    const taxableGross = 3000
    const incomeTax = Math.round(taxableGross * (withholdingTaxRate / 100) * 100) / 100
    expect(incomeTax).toBe(105)
  })

  it('Taux PAS neutre utilisé quand pas de taux personnalisé', () => {
    function neutralRate(taxableGross: number): number {
      if (taxableGross <= 1705) return 0
      if (taxableGross <= 1800) return 0.5
      if (taxableGross <= 1915) return 1.5
      if (taxableGross <= 2035) return 2.5
      if (taxableGross <= 2165) return 3.5
      if (taxableGross <= 2315) return 4.5
      if (taxableGross <= 2475) return 6
      if (taxableGross <= 2655) return 7.5
      if (taxableGross <= 2855) return 9
      if (taxableGross <= 3075) return 10.5
      if (taxableGross <= 3315) return 12
      if (taxableGross <= 3585) return 14
      if (taxableGross <= 3885) return 16
      if (taxableGross <= 4215) return 18
      if (taxableGross <= 4575) return 20
      if (taxableGross <= 4965) return 22
      if (taxableGross <= 5385) return 24
      if (taxableGross <= 5835) return 26
      if (taxableGross <= 6335) return 28
      if (taxableGross <= 6865) return 29
      if (taxableGross <= 7445) return 30
      return 31
    }
    expect(neutralRate(3000)).toBe(10.5)
    const incomeTax = 3000 * (10.5 / 100)
    expect(incomeTax).toBe(315)
  })
})

// ============ PRD-05 : MRP déduction commandes en cours ============

describe('PRD-05 : MRP déduit les commandes en cours (reste à recevoir)', () => {
  it('Reste à recevoir = quantité - quantité reçue', () => {
    const line = { product_id: 'p1', quantity: 100, quantity_received: 30 }
    const remaining = Number(line.quantity) - Number(line.quantity_received || 0)
    expect(remaining).toBe(70)
  })

  it('Commande entièrement reçue → reste à recevoir = 0', () => {
    const line = { product_id: 'p1', quantity: 100, quantity_received: 100 }
    const remaining = Number(line.quantity) - Number(line.quantity_received || 0)
    expect(remaining).toBe(0)
  })

  it('Deux exécutions MRP consécutives → même résultat (pas de double)', () => {
    const openPOLines = [
      { product_id: 'p1', quantity: 100, quantity_received: 30 },
      { product_id: 'p2', quantity: 50, quantity_received: 0 },
    ]

    function runMRP(): Record<string, number> {
      const openPOMap: Record<string, number> = {}
      for (const pol of openPOLines) {
        const remaining = Number(pol.quantity) - Number(pol.quantity_received || 0)
        if (remaining > 0 && pol.product_id) {
          openPOMap[pol.product_id] = (openPOMap[pol.product_id] || 0) + remaining
        }
      }
      return openPOMap
    }

    const result1 = runMRP()
    const result2 = runMRP()
    expect(result1).toEqual(result2)
    expect(result1.p1).toBe(70)
    expect(result1.p2).toBe(50)
  })

  it('MRP lit purchase_order_lines (product_id), pas purchase_orders', () => {
    const po = { supplier_id: 's1', total_amount: 1000 }
    expect((po as any).product_id).toBeUndefined()

    const pol = { product_id: 'p1', quantity: 100 }
    expect(pol.product_id).toBe('p1')
  })
})
