// M2 (audit fonctionnel exécuté du 28/09/2026) : un champ e-mail laissé vide arrivait
// en '' et la contrainte de format le refusait — client, fournisseur ou salarié sans
// e-mail impossible à créer. Le chemin complet est prouvé par la suite SQL 272 et par
// les scénarios src/__screen__ ; ce test garde la normalisation de l'écran.
import { describe, expect, it } from 'vitest'
import { blankEmailToNull } from '@/lib/queries/core'

describe('blankEmailToNull', () => {
  it('rend NULL un e-mail vide ou fait d\'espaces', () => {
    expect(blankEmailToNull({ name: 'A', email: '' })).toEqual({ name: 'A', email: null })
    expect(blankEmailToNull({ name: 'A', email: '   ' })).toEqual({ name: 'A', email: null })
  })

  it('laisse intacte une adresse, et un objet sans e-mail', () => {
    expect(blankEmailToNull({ email: 'a@b.fr' })).toEqual({ email: 'a@b.fr' })
    const sans = { name: 'B' }
    expect(blankEmailToNull(sans)).toBe(sans)
  })
})
