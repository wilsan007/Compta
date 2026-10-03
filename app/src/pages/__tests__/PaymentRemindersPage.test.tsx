import { describe, it, expect, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { PaymentRemindersPage } from '@/pages/PaymentRemindersPage'

// B9 (ven-015, dernier point ouvert) : l'écran des relances affichait « — »
// dans les colonnes « Client » et « Facture ». La table `collection_reminders`
// ne porte **ni** `customer_name` **ni** `invoice_number` — elle ne connaît que
// son propre `number`. Une relance qui ne dit ni à qui elle s'adresse, ni
// quelle facture elle concerne, ne sert à rien : c'est la chaîne complète qui
// avait été jugée « non livrée ».

const relances = [
  {
    id: 'r1', number: 'REL-2026-000007', customer_id: 'c1', invoice_id: 'i1',
    reminder_level: 2, reminder_date: '2026-03-20', due_date: '2026-03-01',
    amount: 1200, status: 'sent', payment_status: 'unpaid', payment_link_url: null,
    // les jointures que la requête doit demander
    customers: { name: 'Client Un' },
    invoices: { number: 'FAC-2026-000003' },
  },
]

vi.mock('@/lib/queries/accounting', () => ({
  getCollectionReminders: vi.fn(async () => relances),
}))
vi.mock('@/lib/queries/payroll', () => ({ generatePaymentLink: vi.fn() }))
vi.mock('@/lib/toast', () => ({ useToast: () => ({ toast: vi.fn() }) }))
vi.mock('@/hooks/useLocale', () => ({
  useLocale: () => ({ formatCurrency: (n: number) => `${n.toFixed(2)} €`, formatDate: (d: string) => d }),
}))
vi.mock('react-i18next', async (importOriginal) => {
  const actual = await importOriginal<typeof import('react-i18next')>()
  return { ...actual, useTranslation: vi.fn(() => ({ t: (key: string) => key, i18n: { language: 'fr', changeLanguage: vi.fn() } })) }
})

describe('B9 (ven-015) — l’écran des relances dit à qui et à quoi', () => {
  it('le client et la facture de la relance sont nommés', async () => {
    render(<MemoryRouter><PaymentRemindersPage /></MemoryRouter>)
    expect(await screen.findByText('Client Un')).toBeInTheDocument()
    expect(screen.getByText('FAC-2026-000003')).toBeInTheDocument()
  })

  it('le numéro de la relance lui-même est affiché', async () => {
    render(<MemoryRouter><PaymentRemindersPage /></MemoryRouter>)
    expect(await screen.findByText('REL-2026-000007')).toBeInTheDocument()
  })
})