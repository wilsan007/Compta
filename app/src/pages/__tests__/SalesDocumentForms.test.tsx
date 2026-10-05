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
const updateInvoiceDraft = vi.fn()
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
  updateInvoiceDraft: (...a: unknown[]) => updateInvoiceDraft(...a),
  updateCreditNote: vi.fn(), deleteCreditNote: vi.fn(), convertQuoteToInvoice: vi.fn(),
}))
// R-08 : la fenêtre de règlement propose les comptes bancaires de la société
vi.mock('@/lib/queries/banking', () => ({
  getBankAccounts: vi.fn(async () => [
    { id: 'bq1', name: 'Compte courant', bank_name: 'BCI' },
    { id: 'bq2', name: 'Compte devises', bank_name: 'BCI' },
  ]),
}))
vi.mock('@/lib/queries/partners', () => ({ getCustomers: vi.fn(async () => customers), createCustomerPayment: (...a: unknown[]) => createCustomerPayment(...a) }))
vi.mock('@/lib/queries/core', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@/lib/queries/core')>()
  return { ...actual, nextDocumentNumber: vi.fn(async (p: string) => `${p}-2026-000007`) }
})
vi.mock('@/lib/queries/misc', () => ({ transformInvoiceToCreditNote: vi.fn(), createAdvanceInvoice: vi.fn(), transformQuoteToSalesOrder: vi.fn(), getFiscalPositions: vi.fn(async () => []) }))
vi.mock('@/lib/queries/stock', () => ({ getProducts: vi.fn(async () => []), getProductStock: vi.fn(async () => 0) }))
vi.mock('@/lib/queries/accounting', () => ({ getCompanySettings: vi.fn(async () => null), getAnalyticSections: vi.fn(async () => []) }))
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
    updateInvoiceDraft.mockResolvedValue({ id: 'd1' })
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

  // 2.13 (G1) : un brouillon se modifie depuis la liste, par le formulaire de création.
  it('Liste des factures : « Modifier » un brouillon rouvre ses lignes et le remplace d’un geste', async () => {
    invoiceList = [{ id: 'd1', number: 'BROUILLON-FAC-1', customer_id: 'c1', customer_name: 'Client Un', date: '2026-03-01', due_date: '2026-03-31',
      status: 'draft', validation_status: 'draft', total: 120, amount_due: 120, amount_paid: 0, invoice_type: 'standard',
      invoice_lines: [{ id: 'l1', description: 'Ancienne ligne', quantity: 1, unit_price: 100, vat_rate: 20, line_order: 0, analytic_section_id: 's1' }] }]
    render(<MemoryRouter><InvoicesPage /></MemoryRouter>)
    fireEvent.click(await screen.findByTitle('invoices.editDraft'))
    const form = formOf('invoices.editDraftTitle')
    const description = within(form).getByLabelText('invoices.description') as HTMLInputElement
    expect(description.value).toBe('Ancienne ligne')
    fireEvent.change(within(form).getByLabelText('invoices.quantity'), { target: { value: '3' } })
    fireEvent.click(within(form).getByRole('button', { name: 'actions.save' }))

    await waitFor(() => expect(updateInvoiceDraft).toHaveBeenCalledTimes(1))
    expect(createInvoice).not.toHaveBeenCalled()
    const [id, header, lines] = updateInvoiceDraft.mock.calls[0]
    expect(id).toBe('d1')
    expect(header).toEqual({ customer_id: 'c1', customer_name: 'Client Un', date: '2026-03-01', due_date: '2026-03-31' })
    expect(lines).toHaveLength(1)
    // la section de la ligne survit à la modification, même quand la société n'affiche pas la colonne
    expect(lines[0]).toMatchObject({ description: 'Ancienne ligne', quantity: 3, unit_price: 100, total: 300, vat_amount: 60, analytic_section_id: 's1' })
  })

  it('Liste des factures : ni une facture validée ni un brouillon né d’un temps passé ne proposent « Modifier »', async () => {
    invoiceList = [
      { id: 'v1', number: 'FAC-2026-000001', customer_id: 'c1', customer_name: 'Client Un', date: '2026-03-01', due_date: '2026-03-31',
        status: 'sent', validation_status: 'validated', total: 120, amount_due: 120, amount_paid: 0, invoice_type: 'standard', invoice_lines: [] },
      { id: 'd2', number: 'BROUILLON-FAC-2', customer_id: 'c1', customer_name: 'Client Un', date: '2026-03-01', due_date: '2026-03-31',
        status: 'draft', validation_status: 'draft', total: 240, amount_due: 240, amount_paid: 0, invoice_type: 'standard',
        invoice_lines: [{ id: 'l2', description: 'Temps passé', quantity: 3, unit_price: 80, vat_rate: 20, line_order: 0, time_entry_id: 't1' }] },
    ]
    render(<MemoryRouter><InvoicesPage /></MemoryRouter>)
    await screen.findByText('FAC-2026-000001')
    expect(screen.queryByTitle('invoices.editDraft')).toBeNull()
  })

  it('Liste des factures : facture validée comptabilisée, paiement avec un numéro de règlement propre', async () => {
    invoiceList = [{ id: 'v1', number: 'FAC-2026-000001', customer_id: 'c1', customer_name: 'Client Un', date: '2026-03-01', due_date: '2026-03-31',
      status: 'sent', validation_status: 'validated', transferred_entry_id: 'je-1', total: 120, amount_due: 120, amount_paid: 0, invoice_type: 'standard' }]
    render(<MemoryRouter><InvoicesPage /></MemoryRouter>)
    expect(await screen.findByText('Comptabilisé')).toBeInTheDocument()
    fireEvent.click(screen.getByTitle('invoices.markAsPaid'))
    // R-08 : le règlement se saisit dans la fenêtre — et ce qui y est SAISI doit
    // arriver jusqu'au règlement, sinon tout repartirait en 512000/BQ comme avant
    const dialog = await screen.findByRole('dialog')
    await waitFor(() => expect(within(dialog).getByText('Compte devises — BCI')).toBeInTheDocument())
    fireEvent.change(within(dialog).getByLabelText(/payments\.date/), { target: { value: '2026-04-15' } })
    fireEvent.change(within(dialog).getByLabelText(/payments\.amount/), { target: { value: '80' } })
    fireEvent.change(within(dialog).getByLabelText(/payments\.method/), { target: { value: 'check' } })
    fireEvent.change(within(dialog).getByLabelText(/payments\.bankAccount/), { target: { value: 'bq2' } })
    fireEvent.change(within(dialog).getByLabelText(/payments\.reference/), { target: { value: 'CHQ-77' } })
    fireEvent.click(within(dialog).getByRole('button', { name: 'payments.record' }))
    await waitFor(() => expect(createCustomerPayment).toHaveBeenCalledTimes(1))
    expect(createCustomerPayment.mock.calls[0][0]).toMatchObject({
      number: 'REG-2026-000007', invoice_id: 'v1',
      amount: 80, payment_date: '2026-04-15', method: 'check', bank_account_id: 'bq2', reference: 'CHQ-77',
    })
  })

  // B6 (ven-006, restitution) : la fenêtre « Voir » n'affichait que l'en-tête —
  // aucune ligne, aucun HT ni TVA par taux. La facture est pourtant chargée
  // avec ses lignes (`getInvoices` sélectionne `invoice_lines(*)`).
  it('Liste des factures : « Voir » affiche les lignes, le HT et la TVA par taux', async () => {
    invoiceList = [{
      id: 'v2', number: 'FAC-2026-000002', customer_id: 'c1', customer_name: 'Client Deux',
      date: '2026-03-01', due_date: '2026-03-31', status: 'sent', validation_status: 'validated',
      subtotal: 340, vat_total: 59, total: 399, amount_due: 399, amount_paid: 0, invoice_type: 'standard',
      invoice_lines: [
        { id: 'l1', invoice_id: 'v2', product_id: null, description: 'Prestation', quantity: 1, unit_price: 250, vat_rate: 20, total: 250, vat_total: 50, line_order: 1 },
        { id: 'l2', invoice_id: 'v2', product_id: null, description: 'Marchandise', quantity: 2, unit_price: 45, vat_rate: 10, total: 90, vat_total: 9, line_order: 2 },
      ],
    }]
    render(<MemoryRouter><InvoicesPage /></MemoryRouter>)
    expect(await screen.findByText('FAC-2026-000002')).toBeInTheDocument()
    fireEvent.click(screen.getByTitle('actions.view'))
    const dialog = await screen.findByRole('dialog')
    // les lignes elles-mêmes, avec leur description
    expect(within(dialog).getByText('Prestation')).toBeInTheDocument()
    expect(within(dialog).getByText('Marchandise')).toBeInTheDocument()
    // le HT et la TVA par taux : 20 % (base 250,00, TVA 50,00) et 10 % (base 90,00, TVA 9,00)
    expect(within(dialog).getByText('20 %')).toBeInTheDocument()
    expect(within(dialog).getByText('10 %')).toBeInTheDocument()
    expect(within(dialog).getAllByText(/^250[.,]00/)).toHaveLength(3) // prix unitaire, total de ligne HT et base 20 %
    expect(within(dialog).getAllByText(/^90[.,]00/)).toHaveLength(2)   // total de ligne HT + base 10 %
    expect(within(dialog).getAllByText(/^50[.,]00/)).toHaveLength(1)  // TVA 20 %
    expect(within(dialog).getAllByText(/^9[.,]00/)).toHaveLength(1)    // TVA 10 %
    expect(within(dialog).getAllByText(/^340[.,]00/)).toHaveLength(1)  // total HT
    expect(within(dialog).getAllByText(/^399[.,]00/)).toHaveLength(2)  // total TTC + reste dû (échue en entier)
  })
})
