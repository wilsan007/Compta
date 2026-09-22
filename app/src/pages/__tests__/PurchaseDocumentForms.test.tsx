import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, waitFor, fireEvent, within } from '@testing-library/react'
import '@testing-library/jest-dom/vitest'
import { MemoryRouter } from 'react-router-dom'

// AUD-G01/G02 (V3) : l'écran « Nouvelle facture fournisseur » envoyait status 'received',
// refusé par la contrainte de la table — la création échouait toujours ; il ne saisissait
// qu'un total TTC sans TVA ni ligne, et tirait le numéro au hasard. L'écran des avoirs
// fournisseur envoyait ses lignes sous `purchase_credit_lines` (ignorée) et n'avait
// aucune action de validation.

const createPurchaseInvoice = vi.fn()
const createPurchaseCreditNote = vi.fn()
const updatePurchaseCreditNote = vi.fn()
const suppliers = [{ id: 's1', name: 'Fournisseur Un' }]
let creditNotes: unknown[] = []
let purchaseInvoices: unknown[] = []
const createSupplierPayment = vi.fn()
const updatePurchaseInvoice = vi.fn()

vi.mock('@/lib/queries/sales', () => ({
  getPurchaseInvoices: vi.fn(async () => purchaseInvoices),
  getPurchaseCreditNotes: vi.fn(async () => creditNotes),
  createPurchaseInvoice: (...a: unknown[]) => createPurchaseInvoice(...a),
  createPurchaseCreditNote: (...a: unknown[]) => createPurchaseCreditNote(...a),
  updatePurchaseCreditNote: (...a: unknown[]) => updatePurchaseCreditNote(...a),
  updatePurchaseInvoice: (...a: unknown[]) => updatePurchaseInvoice(...a), deletePurchaseCreditNote: vi.fn(),
}))
vi.mock('@/lib/queries/partners', () => ({ getSuppliers: vi.fn(async () => suppliers), createSupplierPayment: (...a: unknown[]) => createSupplierPayment(...a) }))
vi.mock('@/lib/queries/core', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@/lib/queries/core')>()
  return { ...actual, nextDocumentNumber: vi.fn(async (p: string) => `${p}-2026-000003`) }
})
vi.mock('@/lib/queries/accounting', () => ({
  getChartAccounts: vi.fn(async () => []), getFiscalYears: vi.fn(async () => []),
  checkBudgetAvailability: vi.fn(), createBudgetCommitment: vi.fn(),
}))
vi.mock('@/lib/queries/businessFunctions', () => ({ performThreeWayMatch: vi.fn() }))
vi.mock('@/lib/legislation', () => ({ useLegislation: () => ({ defaultVatRate: 20 }) }))
vi.mock('@/hooks/usePermission', () => ({ usePermission: () => ({ canCreate: true, canDelete: true, canEdit: true }) }))
vi.mock('@/components/cross-module/useModuleAwareAccess', () => ({ useModuleAwareAccess: () => ({ getAccessStrategy: () => 'none' }) }))
vi.mock('@/components/cross-module/QuickSupplierAccess', () => ({ QuickSupplierAccess: () => null }))
vi.mock('@/lib/toast', () => ({ useToast: vi.fn(() => ({ toast: vi.fn() })) }))
vi.mock('@/components/ui', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@/components/ui')>()
  return {
    ...actual,
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

const { PurchaseInvoicesPage } = await import('../PurchaseInvoicesPage')
const { PurchaseCreditNotesPage } = await import('../PurchaseCreditNotesPage')

function formOf(title: string) {
  return screen.getByRole('heading', { name: title }).closest('.card') as HTMLElement
}

function fillFirstLine(form: HTMLElement) {
  const description = within(form).getAllByRole('textbox').find(i => (i as HTMLInputElement).placeholder === 'invoices.description')
    ?? within(form).getAllByRole('textbox').find(i => (i as HTMLInputElement).placeholder === 'creditNotes.description')!
  fireEvent.change(description, { target: { value: 'Fournitures' } })
  const numbers = within(form).getAllByRole('spinbutton')
  fireEvent.change(numbers[0], { target: { value: '2' } })
  fireEvent.change(numbers[1], { target: { value: '150' } })
}

describe('Formulaires de pièces d’achat (AUD-G01, AUD-G02)', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    creditNotes = []
    purchaseInvoices = []
    createSupplierPayment.mockResolvedValue({})
    createPurchaseInvoice.mockResolvedValue({ id: 'p1' })
    createPurchaseCreditNote.mockResolvedValue({ id: 'a1' })
    updatePurchaseCreditNote.mockResolvedValue({ id: 'a1' })
  })

  it('Nouvelle facture fournisseur : brouillon avec lignes, référence du fournisseur, sans numéro interne', async () => {
    render(<MemoryRouter><PurchaseInvoicesPage /></MemoryRouter>)
    fireEvent.click((await screen.findAllByRole('button', { name: /purchaseInvoices\.(new|recordPurchase)/ }))[0])
    const form = formOf('purchaseInvoices.new')
    fireEvent.change(within(form).getByLabelText('purchaseInvoices.supplier'), { target: { value: 's1' } })
    fireEvent.change(within(form).getByLabelText(/^purchaseInvoices\.supplierReference/), { target: { value: 'FA-778' } })
    fillFirstLine(form)
    fireEvent.submit(form.querySelector('form')!)

    await waitFor(() => expect(createPurchaseInvoice).toHaveBeenCalledTimes(1))
    const payload = createPurchaseInvoice.mock.calls[0][0]
    expect(payload.number).toBeUndefined()
    expect(payload.status).toBe('draft')
    expect(payload.supplier_reference).toBe('FA-778')
    expect(payload.lines).toHaveLength(1)
    expect(payload.lines[0]).toMatchObject({ quantity: 2, unit_price: 150, vat_rate: 20, total: 300, vat_amount: 60 })
    expect(payload.total).toBe(360)
  })

  it('Nouvel avoir fournisseur : lignes sous `lines`, sans numéro interne', async () => {
    render(<MemoryRouter><PurchaseCreditNotesPage /></MemoryRouter>)
    fireEvent.click((await screen.findAllByRole('button', { name: /creditNotes\.new/ }))[0])
    const form = formOf('creditNotes.new')
    fireEvent.change(within(form).getByLabelText(/^creditNotes\.supplier(?!Reference)/), { target: { value: 's1' } })
    fillFirstLine(form)
    fireEvent.submit(form.querySelector('form')!)

    await waitFor(() => expect(createPurchaseCreditNote).toHaveBeenCalledTimes(1))
    const payload = createPurchaseCreditNote.mock.calls[0][0]
    expect(payload.number).toBeUndefined()
    expect(payload.purchase_credit_lines).toBeUndefined()
    expect(payload.lines).toHaveLength(1)
  })

  it('Avoir fournisseur en brouillon : validable depuis la liste', async () => {
    creditNotes = [{ id: 'a1', number: 'BROUILLON-AVF-1', date: '2026-03-10', supplier_name: 'Fournisseur Un', total: 120, status: 'draft' }]
    render(<MemoryRouter><PurchaseCreditNotesPage /></MemoryRouter>)
    fireEvent.click(await screen.findByRole('button', { name: 'actions.validate' }))
    await waitFor(() => expect(updatePurchaseCreditNote).toHaveBeenCalledWith('a1', { status: 'validated' }))
  })

  it('« Marquer payée » enregistre un décaissement (jamais le payé directement), et seulement sur une facture approuvée', async () => {
    purchaseInvoices = [
      { id: 'p-ok', number: 'ACH-2026-000001', supplier_id: 's1', supplier_name: 'Fournisseur Un', supplier_reference: 'FA-1', date: '2026-03-01', due_date: '2026-03-31',
        status: 'draft', approval_status: 'approved', transferred_entry_id: 'je-1', total: 120, amount_due: 120, amount_paid: 0 },
      { id: 'p-att', number: 'BROUILLON-ACH-2', supplier_id: 's1', supplier_name: 'Fournisseur Un', date: '2026-03-02', due_date: '2026-03-31',
        status: 'draft', approval_status: 'pending', total: 60, amount_due: 60, amount_paid: 0 },
    ]
    render(<MemoryRouter><PurchaseInvoicesPage /></MemoryRouter>)
    expect(await screen.findByText('Comptabilisé')).toBeInTheDocument()
    const buttons = screen.getAllByTitle('purchaseInvoices.markPaid')
    expect(buttons).toHaveLength(1)
    fireEvent.click(buttons[0])
    // R-08 : le décaissement se saisit dans la fenêtre (date, montant, mode, compte)
    const dialog = await screen.findByRole('dialog')
    fireEvent.click(within(dialog).getByRole('button', { name: 'payments.record' }))
    await waitFor(() => expect(createSupplierPayment).toHaveBeenCalledTimes(1))
    expect(createSupplierPayment.mock.calls[0][0]).toMatchObject({ number: 'DEC-2026-000003', purchase_invoice_id: 'p-ok', amount: 120, status: 'recorded' })
    expect(updatePurchaseInvoice).not.toHaveBeenCalled()
  })
})
