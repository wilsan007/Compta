import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, waitFor, fireEvent, within } from '@testing-library/react'
import '@testing-library/jest-dom/vitest'
import { MemoryRouter } from 'react-router-dom'

// R-09 : l'écran « État de rapprochement ». Avant la 223, la fonction
// `get_bank_reconciliation_state` n'était appelée par AUCUN écran ; le pointage se
// faisait sur un seul côté (les drapeaux de la ligne de relevé), donc l'état ne voyait
// rien. Ici, on vérifie que l'écran lit l'état, montre les écarts des DEUX côtés et
// passe par les RPC qui pointent les deux côtés.

const getBankAccounts = vi.fn()
const getBankReconciliationState = vi.fn()
const reconcileBankStatementLine = vi.fn()
const unreconcileBankStatementLine = vi.fn()
const postBankStatementLine = vi.fn()
const getChartAccounts = vi.fn()
const updateStatementBalance = vi.fn()

vi.mock('@/lib/queries/banking', () => ({
  getBankAccounts: (...a: unknown[]) => getBankAccounts(...a),
  getBankReconciliationState: (...a: unknown[]) => getBankReconciliationState(...a),
  reconcileBankStatementLine: (...a: unknown[]) => reconcileBankStatementLine(...a),
  unreconcileBankStatementLine: (...a: unknown[]) => unreconcileBankStatementLine(...a),
  postBankStatementLine: (...a: unknown[]) => postBankStatementLine(...a),
}))
vi.mock('@/lib/queries/accounting', () => ({
  getChartAccounts: (...a: unknown[]) => getChartAccounts(...a),
}))
vi.mock('@/lib/queries/misc', () => ({
  updateStatementBalance: (...a: unknown[]) => updateStatementBalance(...a),
}))
vi.mock('@/lib/toast', () => {
  // `toast` doit garder son identité entre deux rendus : en production il vient d'un
  // useCallback du provider, et la page le met dans les dépendances de son chargement.
  const toast = vi.fn()
  return { useToast: () => ({ toast }) }
})
vi.mock('react-i18next', async (importOriginal) => {
  const actual = await importOriginal<typeof import('react-i18next')>()
  // Comme dans react-i18next, `t` garde son identité d'un rendu à l'autre : les pages
  // le mettent dans les dépendances de leur chargement.
  const t = (key: string) => key
  const i18n = { language: 'fr', changeLanguage: vi.fn() }
  return { ...actual, useTranslation: () => ({ t, i18n }) }
})

const { BankReconciliationStatePage } = await import('../BankReconciliationStatePage')

const ETAT = {
  bank_account_id: 'acc-1',
  account_code: '512000',
  statement_balance: -3,
  accounting_balance: -28,
  unmatched_debits: 3,
  unmatched_credits: 0,
  ledger_unmatched_debits: 0,
  ledger_unmatched_credits: 28,
  is_balanced: true,
  unmatched_transactions: [
    { id: 'tx-1', date: '2026-03-12', label: 'FRAIS TENUE DE COMPTE', reference: null, type: 'debit', raw_amount: 3, amount: -3 },
  ],
  ledger_unmatched_transactions: [
    { id: 'jl-1', date: '2026-01-05', entry_number: 'FRAIS-223', entry_label: 'FRAIS-223', label: 'FRAIS BANCAIRES', debit: 0, credit: 3, amount: -3 },
    { id: 'jl-2', date: '2026-03-10', entry_number: 'CHQ-223', entry_label: 'CHQ-223', label: 'CHQ FOURNISSEUR', debit: 25, credit: 0, amount: 25 },
  ],
  reconciled_transactions: [
    {
      id: 'tx-pair', date: '2026-03-06', label: 'VIR CLIENT', type: 'credit', raw_amount: 120, amount: 120,
      reconciled_entry_id: 'e-1', entry_number: 'ENC-223', entry_date: '2026-01-05', match_type: 'ledger_manual',
      matched_account_code: '512000',
    },
  ],
  difference: -3,
  explained_difference: -3,
  is_reconciled: false,
  unmatched_count: 1,
  ledger_unmatched_count: 2,
  reconciled_count: 1,
  statement_closing_balance: 70,
  closing_date: '2026-03-31',
  closing_difference: -3,
  closing_matches: false,
}

const CHART = [
  { id: 'ca-1', code: '627000', name: 'Services bancaires', type: 'expense' },
  { id: 'ca-2', code: '768000', name: 'Autres produits financiers', type: 'income' },
]

function renderPage() {
  return render(<MemoryRouter><BankReconciliationStatePage /></MemoryRouter>)
}

describe('BankReconciliationStatePage — état de rapprochement (R-09)', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    getBankAccounts.mockResolvedValue([{ id: 'acc-1', name: 'Compte courant', currency: 'EUR' }])
    getChartAccounts.mockResolvedValue(CHART)
    getBankReconciliationState.mockResolvedValue(ETAT)
    reconcileBankStatementLine.mockResolvedValue({ transaction_id: 'tx-1' })
    unreconcileBankStatementLine.mockResolvedValue({ transaction_id: 'tx-pair' })
    postBankStatementLine.mockResolvedValue({ transaction_id: 'tx-1' })
    updateStatementBalance.mockResolvedValue({ id: 'acc-1' })
  })

  it('lit l\'état du compte choisi et montre les écarts des deux côtés', async () => {
    renderPage()

    await waitFor(() => expect(getBankReconciliationState).toHaveBeenCalledWith('acc-1', expect.any(String)))

    // écarts côté relevé et côté compte 512x, plus le contrôle d'intégrité
    expect(await screen.findByText('FRAIS TENUE DE COMPTE')).toBeInTheDocument()
    expect(screen.getByText('CHQ-223')).toBeInTheDocument()
    expect(screen.getByText('FRAIS-223')).toBeInTheDocument()
    expect(screen.getByText('state.integrityOk')).toBeInTheDocument()
    // l'état n'est PAS rapproché : un écart subsiste
    expect(screen.getByText('state.ecarts')).toBeInTheDocument()
    expect(screen.queryByText('state.reconciled')).toBeNull()
    // le solde de clôture annoncé ne colle pas aux lignes importées
    expect(screen.getByText('state.closingGap')).toBeInTheDocument()
  })

  it('pointe une ligne de relevé contre l\'écriture de même montant, sens contraire', async () => {
    renderPage()
    fireEvent.click(await screen.findByRole('button', { name: 'state.point' }))

    const dialog = await screen.findByRole('dialog')
    // seule l'écriture de 3 au crédit du compte est candidate (débit 25 exclu)
    const options = within(dialog).getAllByRole('option')
    expect(options).toHaveLength(1)
    expect(within(dialog).getByLabelText(/state.candidate/)).toHaveValue('jl-1')

    fireEvent.click(within(dialog).getByRole('button', { name: 'state.point' }))
    await waitFor(() => expect(reconcileBankStatementLine).toHaveBeenCalledWith('tx-1', 'jl-1'))
  })

  it('comptabilise une ligne non pointée avec le compte de contrepartie choisi', async () => {
    renderPage()
    fireEvent.click(await screen.findByRole('button', { name: 'state.post' }))

    const dialog = await screen.findByRole('dialog')
    expect(within(dialog).getByLabelText(/state.counterpart/)).toHaveValue('627000')

    fireEvent.click(within(dialog).getByRole('button', { name: 'state.post' }))
    await waitFor(() => expect(postBankStatementLine).toHaveBeenCalledWith('tx-1', '627000', 'FRAIS TENUE DE COMPTE'))
  })

  it('défait un pointage existant (les deux côtés reviennent aux écarts)', async () => {
    renderPage()
    fireEvent.click(await screen.findByRole('button', { name: 'state.unpoint' }))
    await waitFor(() => expect(unreconcileBankStatementLine).toHaveBeenCalledWith('tx-pair'))
  })

  it('enregistre le solde de clôture du relevé importé', async () => {
    renderPage()
    const amount = await screen.findByLabelText(/state.closingAmount/)
    fireEvent.change(amount, { target: { value: '70' } })
    fireEvent.click(screen.getByRole('button', { name: 'state.saveClosing' }))

    await waitFor(() => expect(updateStatementBalance).toHaveBeenCalledWith('acc-1', 70, expect.any(String)))
  })
})