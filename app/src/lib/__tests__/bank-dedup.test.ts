/**
 * X6 / M4 — deux opérations identiques le même jour sont deux opérations.
 * Mesuré avant (chemin de l'écran, B01) : un relevé MT940 portant deux paiements
 * CB de 12,50 € le même jour (référence « NONREF ») n'en importait qu'un.
 */
import { describe, it, expect } from 'vitest'
import { selectNewBankTransactions, bankReference, detectDuplicateTransactions } from '@/lib/bankParsers'

const cb = { date: '2026-09-21', amount: -12.5, reference: 'NONREF', description: 'CB BOULANGERIE' }
const vir = { date: '2026-09-20', amount: 500, reference: 'NONREF', description: 'VIR CLIENT' }

describe('M4 — dédoublonnage des relevés', () => {
  it('« NONREF » et une référence vide ne sont pas des références de banque', () => {
    expect(bankReference('NONREF')).toBeNull()
    expect(bankReference('  ')).toBeNull()
    expect(bankReference('FITID-42')).toBe('FITID-42')
  })

  it('premier import : les deux CB identiques entrent', () => {
    expect(selectNewBankTransactions([vir, cb, { ...cb }], [])).toHaveLength(3)
  })

  it('réimport du même fichier : rien n’entre', () => {
    expect(selectNewBankTransactions([vir, cb, { ...cb }], [vir, cb, { ...cb }])).toHaveLength(0)
  })

  it('un relevé qui porte une troisième CB identique n’importe que celle-là', () => {
    const fresh = selectNewBankTransactions([vir, cb, { ...cb }, { ...cb }], [vir, cb, { ...cb }])
    expect(fresh).toHaveLength(1)
    expect(fresh[0].amount).toBe(-12.5)
  })

  it('une référence réelle (FITID) identifie l’opération, même répétée dans le fichier', () => {
    const a = { date: '2026-09-21', amount: -12.5, reference: 'FIT-1', description: 'CB' }
    expect(selectNewBankTransactions([a, { ...a }], [])).toHaveLength(1)
    expect(selectNewBankTransactions([a], [a])).toHaveLength(0)
  })

  it('detectDuplicateTransactions rend exactement ce qui n’entre pas', () => {
    expect(detectDuplicateTransactions([vir, cb] as any, [vir] as any)).toEqual([vir])
  })
})
