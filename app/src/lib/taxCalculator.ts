import type { TaxRate, CorporateTaxGridLine } from '@/types'
import { getTaxRates } from './queries'

export type AmountType = 'percent' | 'fixed' | 'group' | 'division'

export interface TaxCalculationResult {
  taxAmount: number
  newBase: number
  breakdown?: { taxId: string; taxName: string; taxAmount: number }[]
}

export function calculateTax(
  baseAmount: number,
  tax: TaxRate,
  allTaxes?: TaxRate[]
): TaxCalculationResult {
  const amountType = (tax.amount_type || 'percent') as AmountType

  switch (amountType) {
    case 'percent': {
      const taxAmount = baseAmount * (tax.rate / 100)
      return {
        taxAmount: round2(taxAmount),
        newBase: baseAmount,
      }
    }

    case 'fixed': {
      const taxAmount = tax.fixed_amount || 0
      return {
        taxAmount: round2(taxAmount),
        newBase: baseAmount,
      }
    }

    case 'division': {
      const taxAmount = baseAmount * (tax.rate / (100 + tax.rate))
      const newBase = baseAmount - taxAmount
      return {
        taxAmount: round2(taxAmount),
        newBase: round2(newBase),
      }
    }

    case 'group': {
      if (!allTaxes) return { taxAmount: 0, newBase: baseAmount }
      return calculateGroupTax(baseAmount, tax, allTaxes)
    }

    default:
      return { taxAmount: 0, newBase: baseAmount }
  }
}

export function calculateGroupTax(
  baseAmount: number,
  parentTax: TaxRate,
  allTaxes: TaxRate[]
): TaxCalculationResult {
  const children = allTaxes
    .filter((t) => t.parent_tax_id === parentTax.id)
    .sort((a, b) => (a.sequence || 10) - (b.sequence || 10))

  if (children.length === 0) return { taxAmount: 0, newBase: baseAmount }

  let currentBase = baseAmount
  let totalTax = 0
  const breakdown: { taxId: string; taxName: string; taxAmount: number }[] = []

  for (const child of children) {
    const result = calculateTax(currentBase, child, allTaxes)
    totalTax += result.taxAmount
    breakdown.push({ taxId: child.id, taxName: child.name, taxAmount: result.taxAmount })

    if (child.include_base_amount && child.is_base_affected !== false) {
      currentBase = currentBase + result.taxAmount
    }
  }

  return {
    taxAmount: round2(totalTax),
    newBase: round2(currentBase),
    breakdown,
  }
}

export function calculateMultipleTaxes(
  baseAmount: number,
  taxes: TaxRate[],
  allTaxes?: TaxRate[]
): { totalTax: number; finalBase: number; breakdown: TaxCalculationResult[] } {
  let currentBase = baseAmount
  let totalTax = 0
  const breakdown: TaxCalculationResult[] = []

  const sorted = [...taxes].sort((a, b) => (a.sequence || 10) - (b.sequence || 10))

  for (const tax of sorted) {
    const result = calculateTax(currentBase, tax, allTaxes)
    totalTax += result.taxAmount
    breakdown.push(result)

    if (tax.include_base_amount) {
      currentBase = currentBase + result.taxAmount
    }
  }

  return {
    totalTax: round2(totalTax),
    finalBase: round2(currentBase),
    breakdown,
  }
}

export function calculatePriceWithTax(
  unitPrice: number,
  quantity: number,
  taxes: TaxRate[],
  allTaxes?: TaxRate[]
): { ht: number; taxAmount: number; ttc: number } {
  const baseHT = unitPrice * quantity
  const { totalTax } = calculateMultipleTaxes(baseHT, taxes, allTaxes)
  return {
    ht: round2(baseHT),
    taxAmount: round2(totalTax),
    ttc: round2(baseHT + totalTax),
  }
}

export function extractTaxFromIncludedPrice(
  ttcAmount: number,
  tax: TaxRate,
  allTaxes?: TaxRate[]
): { ht: number; taxAmount: number; ttc: number } {
  if (tax.price_include) {
    if ((tax.amount_type || 'percent') === 'division') {
      const taxAmount = ttcAmount * (tax.rate / (100 + tax.rate))
      return {
        ttc: round2(ttcAmount),
        ht: round2(ttcAmount - taxAmount),
        taxAmount: round2(taxAmount),
      }
    }
    const ht = ttcAmount / (1 + tax.rate / 100)
    return {
      ttc: round2(ttcAmount),
      ht: round2(ht),
      taxAmount: round2(ttcAmount - ht),
    }
  }
  const result = calculateTax(ttcAmount, tax, allTaxes)
  return {
    ht: round2(ttcAmount),
    taxAmount: result.taxAmount,
    ttc: round2(ttcAmount + result.taxAmount),
  }
}

function round2(n: number): number {
  return Math.round(n * 100) / 100
}

export async function getTaxChildren(parentTaxId: string): Promise<TaxRate[]> {
  const all = await getTaxRates()
  return all.filter((t) => t.parent_tax_id === parentTaxId)
}

// ============ Corporate Tax Engine ============

export interface CorporateTaxResult {
  taxableBase: number
  taxAmount: number
  minimumTax: number
  finalTax: number
  afterTaxProfit: number
  breakdown: { label: string; amount: number; rate: number }[]
}

export function calculateCorporateTax(
  profit: number,
  turnover: number,
  gridLines: CorporateTaxGridLine[],
  minimumTaxLines?: CorporateTaxGridLine[]
): CorporateTaxResult {
  const breakdown: { label: string; amount: number; rate: number }[] = []
  let taxAmount = 0

  for (const line of gridLines) {
    const base = line.base_type === 'turnover' ? turnover : profit
    let lineTax = 0

    if (line.line_type === 'bracket') {
      const min = Number(line.min_amount || 0)
      const max = line.max_amount != null ? Number(line.max_amount) : Infinity
      if (base > min) {
        const taxableInBracket = Math.min(base, max) - min
        lineTax = taxableInBracket * (Number(line.rate || 0) / 100)
      }
    } else if (line.line_type === 'flat') {
      lineTax = base * (Number(line.rate || 0) / 100)
    } else if (line.line_type === 'percentage') {
      lineTax = base * (Number(line.rate || 0) / 100)
      const cap = line.cap_amount != null ? Number(line.cap_amount) : null
      if (cap != null && lineTax > cap) lineTax = cap
    } else if (line.line_type === 'fixed_amount') {
      lineTax = Number(line.fixed_amount || 0)
    }

    taxAmount += lineTax
    breakdown.push({ label: line.label, amount: round2(lineTax), rate: Number(line.rate || 0) })
  }

  // Calculate minimum tax (IMF) if lines provided
  let minimumTax = 0
  if (minimumTaxLines && minimumTaxLines.length > 0) {
    for (const line of minimumTaxLines) {
      const base = line.base_type === 'turnover' ? turnover : profit
      let lineMinTax = 0
      if (line.line_type === 'percentage') {
        lineMinTax = base * (Number(line.rate || 0) / 100)
        const cap = line.cap_amount != null ? Number(line.cap_amount) : null
        if (cap != null && lineMinTax > cap) lineMinTax = cap
        const floor = Number(line.fixed_amount || 0)
        if (floor > 0 && lineMinTax < floor) lineMinTax = floor
      } else if (line.line_type === 'fixed_amount') {
        lineMinTax = Number(line.fixed_amount || 0)
      }
      minimumTax += lineMinTax
    }
  }

  const finalTax = Math.max(taxAmount, minimumTax)
  const afterTaxProfit = profit - finalTax

  return {
    taxableBase: round2(profit),
    taxAmount: round2(taxAmount),
    minimumTax: round2(minimumTax),
    finalTax: round2(finalTax),
    afterTaxProfit: round2(afterTaxProfit),
    breakdown,
  }
}
