import { describe, it, expect, beforeAll } from 'vitest'
import i18n from 'i18next'
import fr from '@/i18n/locales/fr/errors.json'
import { chainDeleteRefusalMessage, errorMessage } from '@/lib/utils'

// Partie 5 (453) : le refus de suppression d'un document relié arrive de la base
// sous la forme { message: 'CHAIN_DELETE_REFUSED', details: '<json>' }. L'écran
// ne doit JAMAIS afficher ce code brut (défaut F4 de la recette : messages SQL bruts).
describe('Partie 5 — refus de suppression d’un document relié', () => {
  beforeAll(async () => {
    await i18n.init({ lng: 'fr', ns: ['errors'], resources: { fr: { errors: fr } } })
  })

  const refus = {
    message: 'CHAIN_DELETE_REFUSED',
    code: '23503',
    details: JSON.stringify({
      type: 'sales_orders', mode: 'document', id: 'x',
      liens: [{ effet: 'stock.reserve', vers: 'stock_reservations', vers_id: 'r1' },
              { effet: 'stock.reserve', vers: 'stock_reservations', vers_id: 'r2' }],
    }),
  }

  it('traduit le refus : nomme le document, compte les liens, nomme les types reliés', () => {
    const m = chainDeleteRefusalMessage(refus)
    expect(m).toContain('Commande client')
    expect(m).toContain('2 document(s)')
    expect(m).toContain('Réservation de stock')
    expect(m).not.toContain('CHAIN_DELETE_REFUSED')
  })

  it('errorMessage() passe par la traduction, y compris pour une instance d’Error', () => {
    const e = Object.assign(new Error('CHAIN_DELETE_REFUSED'), { details: refus.details })
    expect(errorMessage(e)).toContain('Commande client')
    expect(errorMessage(refus)).not.toBe('CHAIN_DELETE_REFUSED')
  })

  it('laisse les autres erreurs inchangées', () => {
    expect(chainDeleteRefusalMessage(new Error('autre'))).toBeNull()
    expect(errorMessage(new Error('autre'))).toBe('autre')
  })

  it('un détail illisible ne fait pas planter : le message reste traduit', () => {
    const m = chainDeleteRefusalMessage({ message: 'CHAIN_DELETE_REFUSED', details: 'pas du json' })
    expect(m).not.toBeNull()
    expect(m).not.toContain('CHAIN_DELETE_REFUSED')
  })
})
