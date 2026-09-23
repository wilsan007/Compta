import { describe, it, expect } from 'vitest'
import { generateFacturX, generateUBL, isDraftDocument } from '@/lib/facturX'
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
})