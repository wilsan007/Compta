import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { render, screen, fireEvent, waitFor } from '@testing-library/react'
import '@testing-library/jest-dom/vitest'
import { MemoryRouter } from 'react-router-dom'

// R-11 : un brouillon peut être téléchargé, mais le document doit dire ce qu'il
// est. Avant, le téléchargement d'un brouillon produisait un .txt nommé d'après
// son numéro provisoire (BROUILLON-FAC-…) sans aucune mention — rien n'empêchait
// de le présenter comme une facture.

let invoiceList: unknown[] = []
vi.mock('@/lib/queries/sales', () => ({
  getInvoices: vi.fn(async () => invoiceList),
  getQuotes: vi.fn(async () => []),
  getCreditNotes: vi.fn(async () => []),
  getOpenAdvanceInvoices: vi.fn(async () => []),
  createInvoice: vi.fn(), createQuote: vi.fn(), createCreditNote: vi.fn(),
  updateInvoice: vi.fn(), updateQuote: vi.fn(), deleteQuote: vi.fn(),
  updateCreditNote: vi.fn(), deleteCreditNote: vi.fn(), convertQuoteToInvoice: vi.fn(),
}))
vi.mock('@/lib/queries/partners', () => ({
  getCustomers: vi.fn(async () => [{ id: 'c1', name: 'Client Un' }]),
  createCustomerPayment: vi.fn(),
}))
vi.mock('@/lib/queries/core', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@/lib/queries/core')>()
  return { ...actual, nextDocumentNumber: vi.fn(async (p: string) => `${p}-2026-000007`) }
})
vi.mock('@/lib/queries/misc', () => ({ transformInvoiceToCreditNote: vi.fn(), createAdvanceInvoice: vi.fn(), transformQuoteToSalesOrder: vi.fn() }))
vi.mock('@/lib/queries/stock', () => ({ getProducts: vi.fn(async () => []), getProductStock: vi.fn(async () => 0) }))
vi.mock('@/lib/queries/accounting', () => ({ getCompanySettings: vi.fn(async () => null) }))
vi.mock('@/lib/legislation', () => ({ useLegislation: () => ({ defaultVatRate: 20 }) }))
vi.mock('@/hooks/usePermission', () => ({ usePermission: () => ({ canCreate: true, canDelete: true, canEdit: true }) }))
vi.mock('@/components/cross-module/useModuleAwareAccess', () => ({ useModuleAwareAccess: () => ({ getAccessStrategy: () => 'none' }) }))
vi.mock('@/components/cross-module/QuickCustomerAccess', () => ({ QuickCustomerAccess: () => null }))
vi.mock('@/lib/toast', () => ({ useToast: vi.fn(() => ({ toast: vi.fn() })) }))
vi.mock('react-i18next', async (importOriginal) => {
  const actual = await importOriginal<typeof import('react-i18next')>()
  return { ...actual, useTranslation: vi.fn(() => ({ t: (key: string) => key, i18n: { language: 'fr', changeLanguage: vi.fn() } })) }
})

const { InvoicesPage } = await import('../InvoicesPage')

let blobs: Blob[] = []
let downloaded = ''
const origCreate = URL.createObjectURL
let clickSpy: ReturnType<typeof vi.spyOn>

describe('R-11 — téléchargement d’un document provisoire', () => {
  beforeEach(() => {
    invoiceList = []
    blobs = []
    downloaded = ''
    URL.createObjectURL = vi.fn((b: Blob) => { blobs.push(b); return 'blob:test' }) as unknown as typeof URL.createObjectURL
    // jsdom ne suit pas le clic : on lit le nom du fichier au moment du clic
    clickSpy = vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(function (this: HTMLAnchorElement) {
      downloaded = this.download
    })
  })

  afterEach(() => {
    URL.createObjectURL = origCreate
    clickSpy.mockRestore()
  })

  it('un brouillon se télécharge avec la mention PRO FORMA et un nom qui l’annonce', async () => {
    invoiceList = [{ id: 'd1', number: 'BROUILLON-FAC-1', customer_id: 'c1', customer_name: 'Client Un',
      date: '2026-03-01', due_date: '2026-03-31', status: 'draft', validation_status: 'draft',
      total: 120, amount_due: 120, amount_paid: 0, invoice_type: 'standard' }]
    render(<MemoryRouter><InvoicesPage /></MemoryRouter>)
    fireEvent.click(await screen.findByTitle('actions.download'))
    await waitFor(() => expect(blobs).toHaveLength(1))
    const texte = await blobs[0].text()
    expect(texte).toContain('invoices.proFormaNotice')
    expect(downloaded).toMatch(/^PRO-FORMA-/)
  })

  it('une facture validée ne porte pas la mention et garde son nom (non-régression)', async () => {
    invoiceList = [{ id: 'v1', number: 'FAC-2026-000001', customer_id: 'c1', customer_name: 'Client Un',
      date: '2026-03-01', due_date: '2026-03-31', status: 'sent', validation_status: 'validated',
      transferred_entry_id: 'je-1', total: 120, amount_due: 120, amount_paid: 0, invoice_type: 'standard' }]
    render(<MemoryRouter><InvoicesPage /></MemoryRouter>)
    fireEvent.click(await screen.findByTitle('actions.download'))
    await waitFor(() => expect(blobs).toHaveLength(1))
    const texte = await blobs[0].text()
    expect(texte).not.toContain('invoices.proFormaNotice')
    expect(downloaded).toBe('FAC-2026-000001.txt')
  })
})