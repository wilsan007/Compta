import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent, waitFor } from '@testing-library/react'
import '@testing-library/jest-dom/vitest'

// D-10 (décision recommandée) — LE COMPTE DE TRÉSORERIE.
//
// L'ancien « Marquer payée » enregistrait un virement sans date, sans mode ni
// compte : tout partait en 512000/BQ avec la date du jour. La fenêtre de
// règlement (R-08, 22/09) a posé les quatre informations ; ce que D-10 ajoute,
// c'est que le COMPTE soit **exigé** là où il n'est pas déterminé par le mode.
//
// Espèces (530000) et carte/chèque (511200) sont déterminés par le mode
// (décision D-E) : rien à demander. Virement et prélèvement, eux, n'ont pas de
// compte implicite.
//
// La quatrième assertion est une LIMITE DITE, pas un défaut caché : une société
// neuve n'a aucun compte bancaire — l'écran ne doit pas l'empêcher d'enregistrer
// un règlement, il retombe alors sur le compte par défaut **et le dit**.

const getBankAccounts = vi.fn()

vi.mock('@/lib/queries/banking', () => ({
  getBankAccounts: (...a: unknown[]) => getBankAccounts(...a),
}))

vi.mock('react-i18next', async (importOriginal) => {
  const actual = await importOriginal<typeof import('react-i18next')>()
  return {
    ...actual,
    useTranslation: vi.fn(() => ({ t: (key: string) => key, i18n: { language: 'fr' } })),
  }
})

const { PaymentDialog } = await import('../PaymentDialog')

const DEUX_COMPTES = [
  { id: 'b1', name: 'Compte courant', bank_name: 'Banque A' },
  { id: 'b2', name: 'Compte épargne', bank_name: 'Banque B' },
]

describe('PaymentDialog — le compte de trésorerie est une information d’écriture (D-10)', () => {
  const onSubmit = vi.fn()
  const onClose = vi.fn()

  beforeEach(() => {
    vi.clearAllMocks()
    // DEUX comptes : un compte unique est pré-sélectionné par la fenêtre, ce qui
    // n'éprouverait pas la règle.
    getBankAccounts.mockResolvedValue(DEUX_COMPTES)
  })

  function ouvrir() {
    render(<PaymentDialog title="Règlement" defaultAmount={100} onSubmit={onSubmit} onClose={onClose} />)
  }

  it('refuse un VIREMENT sans compte, le dit, et ne transmet rien', async () => {
    ouvrir()
    await waitFor(() => expect(getBankAccounts).toHaveBeenCalled())

    fireEvent.click(screen.getByRole('button', { name: 'payments.record' }))

    expect(onSubmit).not.toHaveBeenCalled()
    expect(await screen.findByText('payments.bankAccountRequired')).toBeInTheDocument()
  })

  it('accepte le virement dès qu’un compte est choisi, et transmet ce compte', async () => {
    ouvrir()
    await waitFor(() => expect(getBankAccounts).toHaveBeenCalled())

    fireEvent.change(screen.getByLabelText(/payments.bankAccount/), { target: { value: 'b2' } })
    fireEvent.click(screen.getByRole('button', { name: 'payments.record' }))

    await waitFor(() => expect(onSubmit).toHaveBeenCalledTimes(1))
    expect(onSubmit.mock.calls[0][0].bank_account_id).toBe('b2')
    expect(onSubmit.mock.calls[0][0].method).toBe('transfer')
  })

  it('ne demande RIEN en espèces : le mode détermine le compte (530000)', async () => {
    ouvrir()
    await waitFor(() => expect(getBankAccounts).toHaveBeenCalled())

    fireEvent.change(screen.getByLabelText(/payments.method/), { target: { value: 'cash' } })
    fireEvent.click(screen.getByRole('button', { name: 'payments.record' }))

    await waitFor(() => expect(onSubmit).toHaveBeenCalledTimes(1))
    expect(onSubmit.mock.calls[0][0].bank_account_id).toBeNull()
    expect(screen.queryByText('payments.bankAccountRequired')).not.toBeInTheDocument()
  })

  it('ne bloque pas une société SANS compte bancaire — la limite est dite, pas subie', async () => {
    getBankAccounts.mockResolvedValue([])
    ouvrir()
    await waitFor(() => expect(getBankAccounts).toHaveBeenCalled())

    fireEvent.click(screen.getByRole('button', { name: 'payments.record' }))

    await waitFor(() => expect(onSubmit).toHaveBeenCalledTimes(1))
    expect(onSubmit.mock.calls[0][0].bank_account_id).toBeNull()
    // Le repli est EXPLIQUÉ à l'écran (texte d'aide), pas silencieux
    expect(screen.getByText('payments.defaultBankAccountHint')).toBeInTheDocument()
  })
})
