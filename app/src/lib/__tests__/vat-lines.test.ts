import { describe, it, expect } from 'vitest'
import { buildVatLines, type VatCode } from '@/lib/vatLines'

const FR20: VatCode = {
  vat_code: 'FR20', label: 'TVA 20 %', rate: 20, reverse_charge: false,
  collected_account: '445711', deductible_account: '445661', ca3_base_box: 'A1', ca3_tax_box: '08',
}
const AUTOLIQ: VatCode = {
  vat_code: 'AUTOLIQ', label: 'Autoliquidation (art. 283 CGI)', rate: 20, reverse_charge: true,
  collected_account: '445790', deductible_account: '445668', ca3_base_box: 'A2', ca3_tax_box: '08',
}
const EXO: VatCode = {
  vat_code: 'EXO', label: 'Exonéré', rate: 0, reverse_charge: false,
  collected_account: '445710', deductible_account: null, ca3_base_box: 'E2', ca3_tax_box: null,
}

describe('buildVatLines — saisie manuelle (198)', () => {
  it('achat à 20 % : TVA au compte déductible du paramétrage, contrepartie TTC', () => {
    expect(buildVatLines(FR20, 100, true)).toEqual({
      ht: 100, tva: 20, counterpart: 120,
      lines: [{ account: '445661', description: 'TVA 20 %', debit: 20, credit: 0 }],
    })
  })

  it('vente à 20 % : TVA au compte collecté', () => {
    expect(buildVatLines(FR20, 1000, false)?.lines).toEqual([
      { account: '445711', description: 'TVA 20 %', debit: 0, credit: 200 },
    ])
  })

  it('achat autoliquidé : TVA déductible ET due, fournisseur au HT', () => {
    const r = buildVatLines(AUTOLIQ, 300, true)
    expect(r?.counterpart).toBe(300)
    expect(r?.lines).toEqual([
      { account: '445668', description: 'TVA déductible — Autoliquidation (art. 283 CGI)', debit: 60, credit: 0 },
      { account: '445790', description: 'TVA due — Autoliquidation (art. 283 CGI)', debit: 0, credit: 60 },
    ])
  })

  it('code sans taux ou sans compte pour ce sens : rien à calculer', () => {
    expect(buildVatLines(EXO, 100, false)).toBeNull()
    expect(buildVatLines({ ...FR20, deductible_account: null }, 100, true)).toBeNull()
    expect(buildVatLines(FR20, 0, true)).toBeNull()
  })
})
