import { describe, it, expect, vi, beforeAll, beforeEach } from 'vitest'
import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import i18n from 'i18next'
import { initReactI18next } from 'react-i18next'
import fr from '@/i18n/locales/fr/crossModule.json'
import { ExplainAmount } from '@/components/ExplainAmount'

// I-08 — « pourquoi ce chiffre ? », moitié interface.
//
// La base est prouvée par la suite 462 (5 scénarios). Ces tests
// vérifient la seule chose qui distingue cet écran d'un calcul de plus :
// il AFFICHE ce que la base a rendu, et ne comble jamais un vide.
//
//   1. il montre les écritures et les lignes que la base a rendues ;
//   2. il NE RECALCULE RIEN — pas de total de secours ;
//   3. une provenance VIDE est une vraie réponse, pas une alerte.

const rpc = vi.fn()

vi.mock('@/lib/queries/chainView', async () => {
  const reel = await vi.importActual<typeof import('@/lib/queries/chainView')>('@/lib/queries/chainView')
  return { ...reel, expliquerMontant: () => Promise.resolve(rpc()) }
})
vi.mock('@/lib/supabase', () => ({ supabase: {} }))
vi.mock('@/lib/queries/core', () => ({ getTenantId: async () => 'societe-1' }))

const ligne = (compte: string, libelle: string, montant: number) => ({
  genre: 'ligne', type: 'journal_lines', id: `l-${compte}`, libelle: compte,
  libelle_piece: libelle, effet: null, lien_etat: 'actif', profondeur: 1,
  montant, debit: true, date_piece: '2026-10-02',
})

describe('I-08 — le « pourquoi ce chiffre ? »', () => {
  beforeAll(async () => {
    await i18n.use(initReactI18next).init({ lng: 'fr', ns: ['crossModule'], resources: { fr: { crossModule: fr } } })
  })
  beforeEach(() => {
    rpc.mockReset()
    vi.clearAllMocks()
  })

  it('montre les écritures et les lignes que la BASE a rendues', async () => {
    rpc.mockImplementation(() => [
      { genre: 'ecriture', type: 'journal_entries', id: 'je-1', libelle: 'VE-001',
        libelle_piece: 'Vente', effet: 'invoice.create', lien_etat: 'actif', profondeur: 1,
        montant: 120, debit: true, date_piece: '2026-10-02' },
      ligne('700000', 'Ventes', 120),
      ligne('445000', 'Clients', 0),
    ])
    render(<ExplainAmount type="invoices" id="fa-1" montantAffiche={120} />)
    fireEvent.click(screen.getByRole('button'))
    await waitFor(() => expect(screen.getByText('VE-001')).toBeTruthy())
    expect(screen.getByText('700000')).toBeTruthy()
    expect(screen.getByTestId('explain-amount')).toBeTruthy()
  })

  it('NE RECALCULE RIEN : sans provenance, il ne comble pas avec un calcul de secours', async () => {
    rpc.mockImplementation(() => [])
    render(<ExplainAmount type="invoices" id="fa-1" montantAffiche={980} />)
    fireEvent.click(screen.getByRole('button'))
    // Une VRAIE réponse, pas une alerte : « aucune provenance ».
    await waitFor(() => expect(screen.getByText(/Aucune provenance/)).toBeTruthy())
    expect(screen.queryByRole('alert')).toBeNull()
    // Et surtout : aucun montant n'a été recomposé à l'écran.
    expect(screen.queryByText(/980/)).toBeNull()
  })

  it('reste discret : le détail est caché tant que le client ne l’ouvre pas', async () => {
    rpc.mockImplementation(() => [ligne('700000', 'Ventes', 120)])
    render(<ExplainAmount type="invoices" id="fa-1" />)
    await waitFor(() => expect(screen.getByRole('button')).toBeTruthy())
    // Rien ne s'affiche avant le clic : une fiche ne doit pas être écrasée
    // par dix lignes d'écriture.
    expect(screen.queryByText('700000')).toBeNull()
  })
})