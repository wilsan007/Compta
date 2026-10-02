import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, waitFor, fireEvent, within } from '@testing-library/react'
import '@testing-library/jest-dom/vitest'
import { MemoryRouter } from 'react-router-dom'

// A4 — ven-001 / ach-002 : la fiche client et la fiche fournisseur ne
// permettaient de saisir ni SIRET, ni code postal, ni ville, ni pays, ni
// conditions de paiement ; « Société parente (ID) » et « Commercial assigné (ID) »
// demandaient un UUID tapé. Le pays, surtout, n'était pas une donnée : la colonne
// portait le défaut figé 'France' (migration 318), et rien ne distinguait un
// client français d'un client belge — ce dont B3 (autoliquidation, mention,
// Factur-X `AE`) a besoin.

const createCustomer = vi.fn()
const updateCustomer = vi.fn()
const createSupplier = vi.fn()
const verifySiret = vi.fn()
const toast = vi.fn()
// A6 : l'export CSV est capturé, pas exécuté (il télécharge un fichier)
const exportToCSV = vi.fn()

const clients = [
  { id: 'c1', name: 'Client Un', country: 'FR', contact_name: 'Dupont', phone: '0102030405', created_at: '2026-02-11T09:00:00Z' },
  { id: 'c2', name: 'MClient Deux', country: 'FR', contact_name: 'Martin', phone: '0605060607', created_at: '2026-03-12T09:00:00Z' },
]
const fournisseurs = [{ id: 'f1', name: 'Fournisseur Un', country: 'FR' }]
const paymentTerms = [{ id: 'pt1', code: '30J', name: '30 jours', type: 'fixed', days_1: 30, pct_1: 100, active: true }]
const reps = [{ id: 'r1', name: 'Commercial Un' }]

vi.mock('@/lib/queries/partners', () => ({
  getCustomers: vi.fn(async () => clients),
  getSuppliers: vi.fn(async () => fournisseurs),
  deleteCustomer: vi.fn(), deleteSupplier: vi.fn(),
  createCustomer: (...a: unknown[]) => createCustomer(...a),
  updateCustomer: (...a: unknown[]) => updateCustomer(...a),
  createSupplier: (...a: unknown[]) => createSupplier(...a),
  updateSupplier: vi.fn(),
}))
vi.mock('@/lib/queries/accounting', () => ({
  getCustomerBalances: vi.fn(async () => []),
  getSupplierBalances: vi.fn(async () => []),
  // Société française : c'est le repli proposé quand le champ pays est laissé vide.
  getCompanySettings: vi.fn(async () => ({ id: 'cs1', name: 'Ma Société', country: 'France', country_code: 'FR' })),
}))
vi.mock('@/lib/queries/payroll', () => ({ getPaymentTerms: vi.fn(async () => paymentTerms) }))
vi.mock('@/lib/queries/misc', () => ({ getSalesRepresentatives: vi.fn(async () => reps), getFiscalPositions: vi.fn(async () => []) }))
vi.mock('@/lib/queries/verifications', () => ({
  verifySiret: (...a: unknown[]) => verifySiret(...a),
  validateVatVies: vi.fn(),
  verifyIban: vi.fn(),
  requestSignature: vi.fn(),
}))
vi.mock('@/lib/toast', () => ({ useToast: () => ({ toast }) }))
// A6 : on veut lire ce que l'export écrit, pas télécharger un fichier
vi.mock('@/components/ui', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@/components/ui')>()
  return { ...actual, exportToCSV }
})
vi.mock('@/hooks/usePermission', () => ({ usePermission: () => ({ canCreate: true, canDelete: true, canEdit: true }) }))
vi.mock('@/pages/PartnerContactsModal', () => ({ PartnerContactsModal: () => null }))
vi.mock('react-i18next', async (importOriginal) => {
  const actual = await importOriginal<typeof import('react-i18next')>()
  return {
    ...actual,
    useTranslation: vi.fn(() => ({ t: (key: string) => key, i18n: { language: 'fr', changeLanguage: vi.fn() } })),
  }
})

const { CustomersPage } = await import('../CustomersPage')
const { SuppliersPage } = await import('../SuppliersPage')

// SIRET valides (clé de Luhn) et invalides.
const SIRET_VALIDE = '73282932000074'
const SIRET_FAUX = '12345678901234'

async function ouvrirFormulaireClient() {
  render(<MemoryRouter><CustomersPage /></MemoryRouter>)
  fireEvent.click(await screen.findByRole('button', { name: 'customers.new' }))
  // le nom porte l'astérisque de champ requis : on le cherche par motif
  return await screen.findByLabelText(/customers\.name/)
}

async function ouvrirFormulaireFournisseur() {
  render(<MemoryRouter><SuppliersPage /></MemoryRouter>)
  fireEvent.click(await screen.findByRole('button', { name: 'suppliers.new' }))
  return await screen.findByLabelText(/suppliers\.nameLabel/)
}


describe('A4 (318) — la fiche client porte l’identité du tiers', () => {
  it('un SIRET dont la clé de Luhn est fausse est refusé, et rien n’est écrit', async () => {
    const nom = await ouvrirFormulaireClient()
    fireEvent.change(nom, { target: { value: 'Client Belge' } })
    fireEvent.change(screen.getByLabelText('customers.siret'), { target: { value: SIRET_FAUX } })
    fireEvent.submit(nom.closest('form')!)

    await waitFor(() => expect(toast).toHaveBeenCalledWith('warning', expect.any(String), 'customers.siretInvalid'))
    expect(createCustomer).not.toHaveBeenCalled()
  })

  it('un SIRET valide est enregistré, avec le pays en code ISO et les conditions de paiement', async () => {
    const nom = await ouvrirFormulaireClient()
    fireEvent.change(nom, { target: { value: 'Client Belge' } })
    fireEvent.change(screen.getByLabelText('customers.siret'), { target: { value: SIRET_VALIDE } })
    fireEvent.change(screen.getByLabelText('customers.zipCode'), { target: { value: '1000' } })
    fireEvent.change(screen.getByLabelText('customers.city'), { target: { value: 'Bruxelles' } })
    await waitFor(() => expect(screen.getByLabelText('customers.paymentTerms')).toBeInTheDocument())
    fireEvent.change(screen.getByLabelText('customers.country'), { target: { value: 'BE' } })
    fireEvent.change(screen.getByLabelText('customers.paymentTerms'), { target: { value: 'pt1' } })
    fireEvent.submit(nom.closest('form')!)

    await waitFor(() => expect(createCustomer).toHaveBeenCalled())
    expect(createCustomer).toHaveBeenCalledWith(expect.objectContaining({
      name: 'Client Belge',
      siret: SIRET_VALIDE,
      city: 'Bruxelles',
      postal_code: '1000',
      country: 'BE',              // un code, jamais « Belgique »
      payment_term_id: 'pt1',
      // le texte reste tenu : l’échéance d’une facture née d’un BL le lit
      payment_terms: '30 jours',
    }))
  })

  it('le pays laissé vide reprend celui de la société, pas « France » par défaut de colonne', async () => {
    const nom = await ouvrirFormulaireClient()
    await waitFor(() => expect(screen.getByLabelText('customers.country')).toHaveValue('FR'))
    fireEvent.change(nom, { target: { value: 'Client Sans Pays Saisi' } })
    fireEvent.submit(nom.closest('form')!)
    await waitFor(() => expect(createCustomer).toHaveBeenCalledWith(expect.objectContaining({ country: 'FR' })))
  })

  it('un SIRET vide est accepté : un tiers sans SIRET reste saisissable', async () => {
    const nom = await ouvrirFormulaireClient()
    fireEvent.change(nom, { target: { value: 'Client Particulier' } })
    fireEvent.submit(nom.closest('form')!)
    await waitFor(() => expect(createCustomer).toHaveBeenCalledWith(expect.objectContaining({ siret: null })))
  })

  it('« Vérifier » appelle la fonction Edge et n’annonce que ce qu’elle a vérifié', async () => {
    verifySiret.mockResolvedValue({ valid: true, api_source: 'local_validation', company_name: 'CLIENT BELGE' })
    await ouvrirFormulaireClient()
    fireEvent.change(screen.getByLabelText('customers.siret'), { target: { value: SIRET_VALIDE } })
    fireEvent.click(screen.getByRole('button', { name: 'customers.checkSiret' }))
    await waitFor(() => expect(verifySiret).toHaveBeenCalledWith(SIRET_VALIDE))
    // pas de clé d'API : la fonction ne l'a pas vérifié à l'INSEE, l'écran ne le dit pas
    await screen.findByText(/customers\.siretFormatOnly/)
    expect(screen.queryByText(/customers\.siretAtSource/)).toBeNull()
  })

  it('« Société parente » et « Commercial » sont des listes, pas un UUID tapé', async () => {
    await ouvrirFormulaireClient()
    await waitFor(() => expect(screen.getByLabelText('customers.salesRepId')).toBeInTheDocument())
    const parentes = within(screen.getByLabelText('customers.parentId')).getAllByRole('option')
    expect(parentes.map((o) => o.textContent)).toEqual(['customers.parentIdUnset', 'Client Un', 'MClient Deux'])
    const commerciaux = within(screen.getByLabelText('customers.salesRepId')).getAllByRole('option')
    expect(commerciaux.map((o) => o.textContent)).toEqual(['customers.salesRepIdUnset', 'Commercial Un'])
  })
})

// A6 (ven-002) : la colonne « Total » de la liste des clients affichait une
// **date de création**, et l'export CSV répétait le mensonge (les cinq autres
// en-têtes y sont, eux, correctement alignés sur leurs valeurs). Un en-tête
// doit dire ce que la case contient ; on n'invente pas un « total facturé » dont
// la définition (factures validées seules ? nets d'avoirs ?) n'est écrite nulle
// part.
describe('A6 (ven-002) — les en-têtes de la liste des clients disent ce qu’ils montrent', () => {
  it('la colonne de date s’appelle « Créé le », pas « Total »', async () => {
    render(<MemoryRouter><CustomersPage /></MemoryRouter>)
    await screen.findByText('Client Un')
    expect(screen.getByText('customers.createdAt')).toBeInTheDocument()
    expect(screen.queryByText('table.total')).toBeNull()
  })

  it('l’export CSV met le téléphone sous « Téléphone » et la date sous « Créé le »', async () => {
    render(<MemoryRouter><CustomersPage /></MemoryRouter>)
    await screen.findByText('Client Un')
    fireEvent.click(screen.getByRole('button', { name: 'actions.export' }))

    expect(exportToCSV).toHaveBeenCalledTimes(1)
    const [, headers, rows] = exportToCSV.mock.calls[0] as [string, string[], (string | number)[][]]
    expect(headers).toEqual([
      'customers.name', 'customers.contactName', 'customers.email',
      'customers.phone', 'customers.outstandingBalance', 'customers.createdAt',
    ])
    // la ligne dit bien le téléphone sous l'en-tête Téléphone (4e colonne)
    expect(rows[0][3]).toBe('0102030405')
    // … et une date de création sous « Créé le » (6e colonne), pas un montant
    // (formatée par `formatDate` : 11/02/2026)
    expect(String(rows[0][5])).toBe('11/02/2026')
  })
})

describe('A4 (318) — la fiche fournisseur aussi (ach-002)', () => {
  it('un SIRET faux est refusé, et un SIRET valide est enregistré avec le pays', async () => {
    const nom = await ouvrirFormulaireFournisseur()
    fireEvent.change(nom, { target: { value: 'Fournisseur Belge' } })
    fireEvent.change(screen.getByLabelText('suppliers.siret'), { target: { value: SIRET_FAUX } })
    fireEvent.submit(nom.closest('form')!)
    await waitFor(() => expect(toast).toHaveBeenCalledWith('warning', expect.any(String), 'suppliers.siretInvalid'))
    expect(createSupplier).not.toHaveBeenCalled()

    fireEvent.change(screen.getByLabelText('suppliers.siret'), { target: { value: SIRET_VALIDE } })
    fireEvent.change(screen.getByLabelText('suppliers.country'), { target: { value: 'BE' } })
    fireEvent.submit(nom.closest('form')!)
    await waitFor(() => expect(createSupplier).toHaveBeenCalledWith(expect.objectContaining({
      siret: SIRET_VALIDE, country: 'BE',
    })))
  })
})

beforeEach(() => {
  createCustomer.mockReset(); updateCustomer.mockReset(); createSupplier.mockReset()
  verifySiret.mockReset(); toast.mockReset()
})
