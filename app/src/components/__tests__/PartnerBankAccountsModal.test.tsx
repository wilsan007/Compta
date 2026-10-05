import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent, waitFor } from '@testing-library/react'
import { PartnerBankAccountsModal } from '@/components/PartnerBankAccountsModal'

// A5 (ach-003) : l'écran affichait « IBAN invalide » en rouge… et enregistrait
// quand même. Le message n'était qu'un avertissement, jamais un refus : un IBAN
// faux partait en base, et de là dans les virements.

const { createPartnerBankAccount, getPartnerBankAccounts, toast } = vi.hoisted(() => ({
  createPartnerBankAccount: vi.fn(async (_data?: any) => {}),
  getPartnerBankAccounts: vi.fn(async () => [] as any[]),
  toast: vi.fn(),
}))

vi.mock('@/lib/queries/partners', () => ({
  getPartnerBankAccounts,
  createPartnerBankAccount,
  updatePartnerBankAccount: vi.fn(async () => {}),
  deletePartnerBankAccount: vi.fn(async () => {}),
}))
vi.mock('@/lib/toast', () => ({ useToast: () => ({ toast }) }))
vi.mock('@/lib/confirm', () => ({ confirmDialog: () => Promise.resolve(true) }))
vi.mock('react-i18next', async (importOriginal) => {
  const actual = await importOriginal<typeof import('react-i18next')>()
  return { ...actual, useTranslation: vi.fn(() => ({ t: (key: string) => key, i18n: { language: 'fr', changeLanguage: vi.fn() } })) }
})

const IBAN_SAUVE = 'FR7630006000011234567890189'
const IBAN_FAUX = 'FR7630006000011234567890180' // même chose, clé de contrôle fausse

function ouvrirFormulaire() {
  render(<PartnerBankAccountsModal partnerType="customer" partnerId="c1" onClose={() => {}} />)
  fireEvent.click(screen.getByRole('button', { name: 'partnerBankAccounts.new' }))
  return screen.getByPlaceholderText('FR76 1234 5678 9012 3456 7890 123') as HTMLInputElement
}

describe('A5 (ach-003) — un IBAN faux n’est pas enregistré', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    getPartnerBankAccounts.mockResolvedValue([])
  })

  it('un IBAN dont la clé est fausse est refusé, rien n’est écrit', async () => {
    const input = ouvrirFormulaire()
    fireEvent.change(input, { target: { value: IBAN_FAUX } })
    // le signal existed déjà (rouge « ibanInvalid ») — c'est le refus qui manquait
    expect(await screen.findByText('partnerBankAccounts.ibanInvalid')).toBeInTheDocument()
    const save = screen.getByRole('button', { name: 'actions.save' }) as HTMLButtonElement
    expect(save.disabled).toBe(true)
    fireEvent.submit(input.closest('form')!) // même en forçant la soumission
    await waitFor(() => expect(toast).toHaveBeenCalledWith('warning', expect.anything(), 'partnerBankAccounts.ibanRefused'))
    expect(createPartnerBankAccount).not.toHaveBeenCalled()
  })

  it('un IBAN valide est enregistré', async () => {
    const input = ouvrirFormulaire()
    fireEvent.change(input, { target: { value: IBAN_SAUVE } })
    const save = screen.getByRole('button', { name: 'actions.save' }) as HTMLButtonElement
    expect(save.disabled).toBe(false)
    fireEvent.click(save)
    await waitFor(() => expect(createPartnerBankAccount).toHaveBeenCalledTimes(1))
    expect(createPartnerBankAccount.mock.calls[0][0]).toMatchObject({ account_number: IBAN_SAUVE })
  })

  it('un numéro de compte ordinaire n’est pas traité comme un IBAN faux', async () => {
    const input = ouvrirFormulaire()
    fireEvent.change(input, { target: { value: '123456789' } }) // compte américain, pas un IBAN
    const save = screen.getByRole('button', { name: 'actions.save' }) as HTMLButtonElement
    expect(save.disabled).toBe(false)
    fireEvent.click(save)
    await waitFor(() => expect(createPartnerBankAccount).toHaveBeenCalledTimes(1))
  })
})
