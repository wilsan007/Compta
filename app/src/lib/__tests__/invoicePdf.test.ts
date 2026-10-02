// ============================================================
// invoicePdf.test.ts — B8 (ven-010)
//
// La recette du 29/09/2026 a mesuré que « Télécharger » produisait un blob
// `text/plain` de 156 octets (« Factures FAC-… / Client: null / … ») : ni
// lignes, ni HT, ni TVA, ni vendeur, ni mentions. Le document est désormais un
// vrai PDF, construit ici, sans service externe.
//
// Ce fichier fige : l'en-tête `%PDF-`, une table xref refermable, le texte
// (client, SIREN/TVA du vendeur, lignes, HT par taux, TVA, TTC, mentions) et
// l'échappement des parenthèses d'une désignation.
// ============================================================
import { describe, it, expect } from 'vitest'
import { buildInvoicePdf, invoicePdfLines, type InvoicePdfLabels } from '@/lib/invoicePdf'
import type { Invoice, Customer } from '@/types'

const labels: InvoicePdfLabels = {
  title: 'Facture',
  proForma: '',
  seller: 'Vendeur',
  customer: 'Client',
  date: 'Date',
  dueDate: 'Échéance',
  description: 'Désignation',
  quantity: 'Qté',
  unitPrice: 'P.U. HT',
  vatRate: 'TVA',
  lineTotal: 'Total HT',
  subtotal: 'Total HT',
  vatTotal: 'TVA',
  total: 'Total TTC',
  balance: 'Reste dû',
  mentions: ['Pénalités de retard : trois fois le taux légal.', 'Indemnité forfaitaire : 40 EUR.'],
}

const invoice = {
  id: 'inv-1',
  number: 'FAC-2026-000001',
  customer_id: 'c-1',
  customer_name: 'Dubois Industrie SAS',
  date: '2026-09-14',
  due_date: '2026-10-14',
  validation_status: 'validated',
  subtotal: 280,
  vat_total: 51.65,
  total: 331.65,
  amount_due: 331.65,
  invoice_lines: [
    { id: 'l1', invoice_id: 'inv-1', product_id: 'p1', description: 'Livre 5,5', quantity: 3, unit_price: 10, vat_rate: 5.5, total: 30, vat_total: 1.65, line_order: 0, created_at: '' },
    { id: 'l2', invoice_id: 'inv-1', product_id: 'p2', description: 'Service conseil 250', quantity: 1, unit_price: 250, vat_rate: 20, total: 250, vat_total: 50, line_order: 1, created_at: '' },
  ],
} as unknown as Invoice

const customer = { id: 'c-1', name: 'Dubois Industrie SAS', vat_number: 'FR44732829320' } as Customer
const company = { name: 'QA Recette SARL', siret: '12345678900012', vat_number: 'FR12345678900', address: '1 rue de la Paix', postal_code: '75001', city: 'Paris' }

describe('facture PDF — le document porte ses mentions (B8)', () => {
  it('le texte porte le vendeur (SIRET, TVA), le client, les lignes et les totaux', () => {
    const text = invoicePdfLines(invoice, customer, company, labels).join('\n')

    expect(text).toContain('FAC-2026-000001')
    expect(text).toContain('QA Recette SARL')
    expect(text).toContain('SIRET 12345678900012')
    expect(text).toContain('FR12345678900')
    expect(text).toContain('Dubois Industrie SAS')
    expect(text).toContain('Livre 5,5')
    expect(text).toContain('Service conseil 250')
    expect(text).toContain('Total TTC')
    expect(text).toContain('Reste dû')
  })

  it('le HT est ventilé par taux, et les mentions légales sont présentes', () => {
    const text = invoicePdfLines(invoice, customer, company, labels).join('\n')

    expect(text).toContain('Total HT 5,50 %')
    expect(text).toContain('Total HT 20,00 %')
    expect(text).toContain('Pénalités de retard')
    expect(text).toContain('Indemnité forfaitaire')
  })

  it('un brouillon porte la mention PRO FORMA', () => {
    const text = invoicePdfLines(invoice, customer, company, { ...labels, proForma: 'PRO FORMA — document de travail' }).join('\n')
    expect(text.startsWith('PRO FORMA')).toBe(true)
  })

  it('le fichier est un PDF refermable (en-tête, xref, trailer, EOF)', () => {
    const bytes = buildInvoicePdf(invoice, customer, company, labels)
    const text = new TextDecoder('latin1').decode(bytes)

    expect(text.startsWith('%PDF-1.4')).toBe(true)
    expect(text).toContain('1 0 obj')
    expect(text).toContain('/BaseFont /Helvetica')
    expect(text).toContain('xref')
    expect(text).toContain('trailer')
    expect(text.trimEnd().endsWith('%%EOF')).toBe(true)
    // startxref pointe sur un décalage réel
    const startxref = Number(/startxref\s+(\d+)/.exec(text)?.[1])
    expect(Number.isFinite(startxref)).toBe(true)
    expect(text.slice(startxref, startxref + 4)).toBe('xref')
  })

  it('les parenthèses et les barres obliques d’une désignation sont échappées', () => {
    const withParens = {
      ...invoice,
      invoice_lines: [{ id: 'l1', invoice_id: 'inv-1', product_id: null, description: 'Article (A\\B)', quantity: 1, unit_price: 10, vat_rate: 20, total: 10, vat_total: 2, line_order: 0, created_at: '' }],
    } as unknown as Invoice
    const bytes = buildInvoicePdf(withParens, customer, company, labels)
    const text = new TextDecoder('latin1').decode(bytes)

    expect(text).toContain('Article \\(A\\\\B\\)')
  })
})
