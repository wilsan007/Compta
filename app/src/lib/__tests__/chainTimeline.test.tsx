import { describe, it, expect, vi, beforeAll, beforeEach } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import i18n from 'i18next'
import { initReactI18next } from 'react-i18next'
import fr from '@/i18n/locales/fr/crossModule.json'
import { ChainTimeline } from '@/components/ChainTimeline'

// I-01 — la Vue Chaîne, moitié interface.
//
// Ces tests ne vérifient pas la base : c'est le rôle de la suite 460
// (8 scénarios, migration `chain_document_arborescence`). Ils vérifient
// que l'écran ne MENSONGE pas — qu'il montre ce que la base a tracé, et
// qu'il ne transforme pas un cas normal en alerte.
//
// Les trois règles du composant sont donc testées ici :
//   1. la base fait foi — aucun lien n'est inventé ;
//   2. un lien FERMÉ s'affiche comme fermé, pas comme un lien mort ;
//   3. un document sans chaîne n'est pas une erreur.

const rpc = vi.fn()

vi.mock('@/lib/queries/chainView', async () => {
  const reel = await vi.importActual<typeof import('@/lib/queries/chainView')>('@/lib/queries/chainView')
  return {
    ...reel,
    // On ne teste pas le transport ici : `getChain` est déjà couvert par
    // la suite 460. On force ici la réponse que la base « rend ».
    getChain: (type: string, id: string, o?: { sens?: string }) =>
      o?.sens === 'amont' ? Promise.resolve(rpc('amont', type, id)) : Promise.resolve(rpc('aval', type, id)),
  }
})

vi.mock('@/lib/supabase', () => ({ supabase: {} }))
vi.mock('@/lib/queries/core', () => ({ getTenantId: async () => 'societe-1' }))

const noeud = (sens: string, profondeur: number, type: string, libelle: string, etat = 'actif') => ({
  sens, profondeur, type, id: `${type}-${profondeur}`, libelle, effet: 'delivery.create', etat, tour: 1,
  lien_date: '2026-10-02T10:00:00Z', lien_id: `lien-${profondeur}`,
})

describe('I-01 — Vue Chaîne, composant', () => {
  beforeAll(async () => {
    // Le composant lit ses libellés dans l'espace `crossModule`. Sans i18n
    // initialisé, `useTranslation` renvoie un `t` inerte et le rendu
    // EXPLOSE : c'est ce que le premier jet a mesuré. Et il faut
    // LIER react-i18next (`initReactI18next`) — un simple `i18n.init()`
    // laisse la page lever « NO_I18NEXT_INSTANCE », mesuré aussi.
    await i18n.use(initReactI18next).init({ lng: 'fr', ns: ['crossModule'], resources: { fr: { crossModule: fr } } })
  })

  beforeEach(() => {
    rpc.mockReset()
    vi.clearAllMocks()
  })

  it('montre ce qui a produit et ce que le document a produit, dans l’ordre', async () => {
    rpc.mockImplementation((sens: string) =>
      sens === 'amont'
        ? [noeud('amont', 1, 'delivery_notes', 'Bon de livraison')]
        : [noeud('aval', 1, 'invoices', 'Facture client')])

    render(<ChainTimeline type="sales_orders" id="cmd-1" libelle="Commande client" />)

    await waitFor(() => expect(screen.getByText('Bon de livraison')).toBeTruthy())
    expect(screen.getByText('Facture client')).toBeTruthy()
    expect(screen.getByText('Commande client')).toBeTruthy()
  })

  it('un lien FERMÉ est affiché comme fermé, pas masqué ni traité comme une erreur', async () => {
    rpc.mockImplementation((sens: string) =>
      sens === 'aval' ? [noeud('aval', 1, 'invoices', 'Facture client', 'rompu')] : [])

    render(<ChainTimeline type="sales_orders" id="cmd-1" />)

    await waitFor(() => expect(screen.getByText('Facture client')).toBeTruthy())
    // Traduit par i18n : un lien rompu est une ANNULATION, pas une panne.
    expect(screen.getByText('annulé')).toBeTruthy()
  })

  it('un document seul n’affiche PAS d’alerte : une saisie manuelle n’a pas d’origine', async () => {
    rpc.mockImplementation(() => [])

    render(<ChainTimeline type="invoices" id="fa-1" />)

    await waitFor(() => expect(screen.getByText(/saisi seul/)).toBeTruthy())
    expect(screen.queryByRole('alert')).toBeNull()
  })

  it('n’invente aucun lien : le composant rend exactement ce que la base a renvoyé', async () => {
    rpc.mockImplementation((sens: string) => (sens === 'aval' ? [noeud('aval', 1, 'invoices', 'Facture client')] : []))

    render(<ChainTimeline type="sales_orders" id="cmd-1" libelle="Commande client" />)

    await waitFor(() => expect(screen.getByTestId('chain-timeline')).toBeTruthy())
    // Le composant montre le document et CE QUE LA BASE A RENDU — ni plus,
    // ni moins. Une pièce amont n'a pas été renvoyée : elle n'apparaît pas.
    expect(screen.getByText('Commande client')).toBeTruthy()
    expect(screen.getByText('Facture client')).toBeTruthy()
    expect(screen.queryByText('Bon de livraison')).toBeNull()
  })
})