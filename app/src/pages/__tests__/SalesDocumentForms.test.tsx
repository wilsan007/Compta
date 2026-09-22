import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, waitFor, fireEvent, within } from '@testing-library/react'
import '@testing-library/jest-dom/vitest'
import { MemoryRouter } from 'react-router-dom'

// AUD-E02 : l'écran Factures ne créait que des factures vides (0 ligne, total 0).
// AUD-E04 : les écrans tiraient le numéro au hasard (Math.random) ; c'est le serveur
//           qui numérote désormais.
// Trouvé pendant V3 : Devis et Avoirs envoyaient leurs lignes sous `quote_lines` /
// `credit_note_lines`, clé que createQuote / createCreditNote ignorent — aucune
// ligne n'était enregistrée.

const createInvoice = vi.fn()
const updateInvoice = vi.fn()
const createCustomerPayment = vi.fn()
let invoiceList: unknown[] = []
const createQuote = vi.fn()
const createCreditNote = vi.fn()
const customers = [{ id: 'c1', name: 'Client Un' }]

vi.mock('@/lib/queries/sales', () => ({
  getInvoices: vi.fn(async () => invoiceList),
  getQuotes: vi.fn(async () => []),
  getCreditNotes: vi.fn(async () => []),
  // R-03 : les acomptes ouverts du client (aucun dans ces scénarios)
  getOpenAdvanceInvoices: vi.fn(async () => []),
  createInvoice: (...a: unknown[]) => createInvoice(...a),
  createQuote: (...a: unknown[]) => createQuote(...a),
  createCreditNote: (...a: unknown[]) => createCreditNote(...a),
  updateInvoice: (...a: unknown[]) => updateInvoice(...a), updateQuote: vi.fn(), deleteQuote: vi.fn(),
  updateCreditNote: vi.fn(), deleteCreditNote: vi.fn(), convertQuoteToInvoice: vi.fn(),
}))
vi.mock('@/lib/queries/partners', () => ({ getCustomers: vi.fn(async () => customers), createCustomerPayment: (...a: unknown[]) => createCustomerPayment(...a) }))
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
vi.mock('@/components/ui', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@/components/ui')>()
  return {
    ...actual,
    // la liste déroulante filtrable est remplacée par un <select> accessible
    Combobox: ({ label, value, onChange, options }: { label: string; value: string; onChange: (v: string) => void; options: { value: string; label: string }[] }) => (
      <select aria-label={label} value={value} onChange={(e) => onChange(e.target.value)}>
        <option value="">—</option>
        {options.map(o => <option key={o.value} value={o.value}>{o.label}</option>)}
      </select>
    ),
  }
})
vi.mock('react-i18next', async (importOriginal) => {
  const actual = await importOriginal<typeof import('react-i18next')>()
  return {
    ...actual,
    useTranslation: vi.fn(() => ({ t: (key: string) => key, i18n: { language: 'fr', changeLanguage: vi.fn() } })),
  }
})

const { InvoicesPage } = await import('../InvoicesPage')
const { QuotesPage } = await import('../QuotesPage')
const { CreditNotesPage } = await import('../CreditNotesPage')

function fillFirstLine(dialog: HTMLElement) {
  const inputs = within(dialog).getAllByRole('textbox')
  const description = inputs.find(i => (i as HTMLInputElement).placeholder === 'invoices.description')!
  fireEvent.change(description, { target: { value: 'Prestation' } })
  const numbers = within(dialog).getAllByRole('spinbutton')
  // quantité, prix unitaire, taux de TVA
  fireEvent.change(numbers[0], { target: { value: '2' } })
  fireEvent.change(numbers[1], { target: { value: '150' } })
}

function formOf(title: string) {
  return screen.getByRole('heading', { name: title }).closest('.card') as HTMLElement
}

describe('Formulaires de pièces de vente (AUD-E02, AUD-E04)', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    createInvoice.mockResolvedValue({ id: 'i1' })
    createQuote.mockResolvedValue({ id: 'q1' })
    createCreditNote.mockResolvedValue({ id: 'a1' })
    updateInvoice.mockResolvedValue({})
    createCustomerPayment.mockResolvedValue({})
    invoiceList = []
  })

  it('Nouvelle facture : envoie ses lignes et aucun numéro', async () => {
    render(<MemoryRouter><InvoicesPage /></MemoryRouter>)
    fireEvent.click(await screen.findByRole('button', { name: /invoices\.new/ }))
    const form = formOf('invoices.new')
    expect(within(form).queryByLabelText('invoices.number')).toBeNull()
    fireEvent.change(within(form).getByLabelText('invoices.customer'), { target: { value: 'c1' } })
    fillFirstLine(form)
    fireEvent.click(within(form).getByRole('button', { name: 'actions.create' }))

    await waitFor(() => expect(createInvoice).toHaveBeenCalledTimes(1))
    const payload = createInvoice.mock.calls[0][0]
    expect(payload.number).toBeUndefined()
    expect(payload.lines).toHaveLength(1)
    expect(payload.lines[0]).toMatchObject({ description: 'Prestation', quantity: 2, unit_price: 150, vat_rate: 20, total: 300, vat_amount: 60 })
    expect(payload.total).toBe(360)
  })

  it('Nouvelle facture : refusée sans ligne renseignée', async () => {
    render(<MemoryRouter><InvoicesPage /></MemoryRouter>)
    fireEvent.click(await screen.findByRole('button', { name: /invoices\.new/ }))
    const form = formOf('invoices.new')
    fireEvent.change(within(form).getByLabelText('invoices.customer'), { target: { value: 'c1' } })
    fireEvent.click(within(form).getByRole('button', { name: 'actions.create' }))
    await new Promise(r => setTimeout(r, 20))
    expect(createInvoice).not.toHaveBeenCalled()
  })

  it('Nouveau devis : les lignes partent sous `lines`, sans numéro saisi', async () => {
    render(<MemoryRouter><QuotesPage /></MemoryRouter>)
    fireEvent.click((await screen.findAllByRole('button', { name: /quotes\.new/ }))[0])
    const form = formOf('quotes.new')
    expect(within(form).queryByLabelText('quotes.number')).toBeNull()
    fireEvent.change(within(form).getByLabelText(/^quotes\.customer/), { target: { value: 'c1' } })
    fillFirstLine(form)
    fireEvent.submit(form.querySelector('form')!)

    await waitFor(() => expect(createQuote).toHaveBeenCalledTimes(1))
    const payload = createQuote.mock.calls[0][0]
    expect(payload.number).toBeUndefined()
    expect(payload.quote_lines).toBeUndefined()
    expect(payload.lines).toHaveLength(1)
    expect(payload.lines[0]).toMatchObject({ description: 'Prestation', quantity: 2, unit_price: 150 })
  })

  it('Nouvel avoir : les lignes partent sous `lines`, sans numéro saisi', async () => {
    render(<MemoryRouter><CreditNotesPage /></MemoryRouter>)
    fireEvent.click((await screen.findAllByRole('button', { name: /creditNotes\.new/ }))[0])
    const form = formOf('creditNotes.new')
    expect(within(form).queryByLabelText('creditNotes.number')).toBeNull()
    fireEvent.change(within(form).getByLabelText(/^creditNotes\.customer/), { target: { value: 'c1' } })
    fillFirstLine(form)
    fireEvent.submit(form.querySelector('form')!)

    await waitFor(() => expect(createCreditNote).toHaveBeenCalledTimes(1))
    const payload = createCreditNote.mock.calls[0][0]
    expect(payload.number).toBeUndefined()
    expect(payload.credit_note_lines).toBeUndefined()
    expect(payload.lines).toHaveLength(1)
    expect(payload.lines[0]).toMatchObject({ description: 'Prestation', quantity: 2, unit_price: 150 })
  })

  it('Liste des factures : « Envoyer » un brouillon le valide d’abord ; pas de paiement sur un brouillon', async () => {
    invoiceList = [{ id: 'd1', number: 'BROUILLON-FAC-1', customer_id: 'c1', customer_name: 'Client Un', date: '2026-03-01', due_date: '2026-03-31',
      status: 'draft', validation_status: 'draft', total: 120, amount_due: 120, amount_paid: 0, invoice_type: 'standard' }]
    render(<MemoryRouter><InvoicesPage /></MemoryRouter>)
    expect(await screen.findByText('Non comptabilisé')).toBeInTheDocument()
    expect(screen.queryByTitle('invoices.markAsPaid')).toBeNull()
    fireEvent.click(screen.getByTitle('actions.send'))
    await waitFor(() => expect(updateInvoice).toHaveBeenCalledTimes(2))
    expect(updateInvoice.mock.calls[0]).toEqual(['d1', { validation_status: 'validated' }])
    expect(updateInvoice.mock.calls[1]).toEqual(['d1', { status: 'sent' }])
  })

  it('Liste des factures : facture validée comptabilisée, paiement avec un numéro de règlement propre', async () => {
    invoiceList = [{ id: 'v1', number: 'FAC-2026-000001', customer_id: 'c1', customer_name: 'Client Un', date: '2026-03-01', due_date: '2026-03-31',
      status: 'sent', validation_status: 'validated', transferred_entry_id: 'je-1', total: 120, amount_due: 120, amount_paid: 0, invoice_type: 'standard' }]
    render(<MemoryRouter><InvoicesPage /></MemoryRouter>)
    expect(await screen.findByText('Comptabilisé')).toBeInTheDocument()
    fireEvent.click(screen.getByTitle('invoices.markAsPaid'))
    await waitFor(() => expect(createCustomerPayment).toHaveBeenCalledTimes(1))
    expect(createCustomerPayment.mock.calls[0][0]).toMatchObject({ number: 'REG-2026-000007', invoice_id: 'v1', amount: 120 })
  })
})
