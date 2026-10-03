import { describe, it, expect } from 'vitest'
import { generateFacturX, generateUBL, isDraftDocument, exemptionCategory, exemptionReason, lineExemptionReason } from '@/lib/facturX'
import type { Invoice, Customer, CompanySettings } from '@/types'

// R-11 : un brouillon est un document provisoire. Il peut être téléchargé, mais
// il ne doit pas pouvoir devenir une facture électronique (Factur-X / UBL) :
// l'écran masquait le bouton, la génération elle-même ne refusait rien — un
// appel direct produisait un XML au numéro BROUILLON-FAC-…, présentable comme
// une facture.

function facture(over: Partial<Invoice>): Invoice {
  return {
    id: 'i1',
    number: 'FAC-2026-000001',
    customer_id: 'c1',
    customer_name: 'Client Un',
    date: '2026-03-01',
    due_date: '2026-03-31',
    status: 'sent',
    validation_status: 'validated',
    subtotal: 100,
    vat_total: 20,
    total: 120,
    amount_due: 120,
    amount_paid: 0,
    currency_code: 'EUR',
    invoice_lines: [],
    ...over,
  } as unknown as Invoice
}

const client = { id: 'c1', name: 'Client Un', country: 'FR' } as unknown as Customer
const societe = { name: 'Ma Société', country: 'FR', currency: 'EUR' } as unknown as CompanySettings

// B3 (ven-009) : la catégorie EN 16931 d'une opération non taxée en France ne se
// lit pas sur le seul taux (0), mais sur le code TVA **et** la nature de la
// ligne : une livraison intracommunautaire de biens est `K` (art. 262 ter I),
// une prestation autoliquidée par le preneur est `AE` (art. 283-2).
describe('B3 — catégorie et motif d’une opération non taxée en France', () => {
  it('le code décide de la catégorie, et la nature de la ligne tranche UE', () => {
    expect(exemptionCategory('UE', false)).toBe('AE')   // prestation intracom.
    expect(exemptionCategory('UE', true)).toBe('K')     // livraison de biens
    expect(exemptionCategory('EXO', false)).toBe('G')   // export
    expect(exemptionCategory('FR0', false)).toBe('Z')   // taux zéro national
    expect(exemptionCategory(null, false)).toBe('Z')
  })

  it('chaque catégorie porte son motif légal', () => {
    expect(exemptionReason('AE')).toContain('283-2')
    expect(exemptionReason('K')).toContain('262 ter')
    expect(exemptionReason('G')).toContain('262 I')
    expect(exemptionReason('Z')).toBe('')
  })

  it('lineExemptionReason lit le type d’article de la ligne', () => {
    expect(lineExemptionReason({ vat_code: 'UE', product_id: 'p1' }, { p1: 'stock' })).toContain('262 ter')
    expect(lineExemptionReason({ vat_code: 'UE', product_id: 'p1' }, { p1: 'service' })).toContain('283-2')
    expect(lineExemptionReason({ vat_code: 'FR20', product_id: 'p1' }, { p1: 'stock' })).toBe('')
  })
})

describe('R-11 — Factur-X et UBL refusent un document provisoire', () => {
  it('un brouillon est reconnu comme document provisoire', () => {
    expect(isDraftDocument(facture({ validation_status: 'draft', number: 'BROUILLON-FAC-1' }))).toBe(true)
    expect(isDraftDocument(facture({ validation_status: 'validated' }))).toBe(false)
    // validation_status absent (donnée ancienne) : provisoire par prudence
    expect(isDraftDocument(facture({ validation_status: null }))).toBe(true)
  })

  it('generateFacturX refuse un brouillon au lieu de produire un XML présentable', () => {
    const brouillon = facture({ validation_status: 'draft', number: 'BROUILLON-FAC-1' })
    expect(() => generateFacturX(brouillon, client, societe)).toThrow(/provisoire/i)
  })

  it('generateUBL refuse un brouillon pour la même raison', () => {
    const brouillon = facture({ validation_status: 'draft', number: 'BROUILLON-FAC-1' })
    expect(() => generateUBL(brouillon, client, societe)).toThrow(/provisoire/i)
  })

  it('une facture validée produit toujours son XML (non-régression)', () => {
    const xml = generateFacturX(facture({}), client, societe)
    expect(xml).toContain('FAC-2026-000001')
    expect(xml.length).toBeGreaterThan(100)
  })

  it('une prestation au code UE porte la catégorie AE et son motif (ven-009)', () => {
    const ligne = { id: 'l1', invoice_id: 'i1', product_id: 'p1', description: 'Prestation', quantity: 1, unit_price: 250, vat_rate: 0, vat_total: 0, vat_code: 'UE', total: 250 }
    const xml = generateFacturX(facture({ invoice_lines: [ligne] as never }), client, societe, { productTypes: { p1: 'service' } })
    expect(xml).toContain('<ram:CategoryCode>AE</ram:CategoryCode>')
    expect(xml).toContain('283-2')
  })

  it('une livraison de bien au code UE porte la catégorie K (262 ter I)', () => {
    const ligne = { id: 'l1', invoice_id: 'i1', product_id: 'p2', description: 'Marchandise', quantity: 1, unit_price: 100, vat_rate: 0, vat_total: 0, vat_code: 'UE', total: 100 }
    const xml = generateFacturX(facture({ invoice_lines: [ligne] as never }), client, societe, { productTypes: { p2: 'stock' } })
    expect(xml).toContain('<ram:CategoryCode>K</ram:CategoryCode>')
    expect(xml).toContain('262 ter')
  })
})