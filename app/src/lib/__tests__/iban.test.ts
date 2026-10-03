import { describe, it, expect } from 'vitest'
import { validateIBAN, looksLikeIBAN, cleanIban, isIbanRejected } from '@/lib/iban'

// A5 (ach-003) : l'IBAN est protégé par la clé mod 97-10 (ISO 13616) — on
// déplace les quatre premiers caractères à la fin, chaque lettre devient son
// numéro (A = 10 … Z = 35), et le reste doit valoir 1 modulo 97.
//
// Deux questions distinctes, et c'est le fond du correctif :
//   - « est-ce bien un IBAN ? » → la FORME (2 lettres de pays + 2 chiffres) ;
//   - « est-il exact ? » → la CLÉ de contrôle.
// Ce formulaire sert aussi les comptes ordinaires (champs bank code / sort code
// d'un compte américain) : un numéro de compte n'est pas un IBAN, et ne doit
// donc pas être traité comme un IBAN faux.

const IBAN_SAUVE = 'FR7630006000011234567890189'
const IBAN_FAUX = 'FR7630006000011234567890180' // même numéro, clé de contrôle fausse

describe('A5 — IBAN : la forme et la clé', () => {
  it('un IBAN valide est accepté, avec ou sans espaces', () => {
    expect(validateIBAN(IBAN_SAUVE)).toBe(true)
    expect(validateIBAN('FR76 3000 6000 0112 3456 7890 189')).toBe(true)
    expect(validateIBAN('BE68539007547034')).toBe(true)
    expect(validateIBAN('DE89370400440532013000')).toBe(true)
  })

  it('un IBAN dont la clé ne correspond pas est refusé', () => {
    expect(validateIBAN(IBAN_FAUX)).toBe(false)   // dernier chiffre changé
    expect(validateIBAN('BE68539007547035')).toBe(false)
    expect(validateIBAN('FR76300060000112345678')).toBe(false) // trop court
    expect(validateIBAN('')).toBe(false)
  })

  it('la forme distingue un IBAN d’un simple numéro de compte', () => {
    expect(looksLikeIBAN('FR76 3000 6000 0112 3456 7890 189')).toBe(true)
    expect(looksLikeIBAN('fr7630006000011234567890180')).toBe(true)   // casse indifférente
    expect(looksLikeIBAN('3000600001123456789018')).toBe(false)      // compte ordinaire
    expect(looksLikeIBAN('123456789')).toBe(false)                   // compte américain
    expect(looksLikeIBAN('')).toBe(false)
  })

  it('le nettoyage ignore les espaces et la casse', () => {
    expect(cleanIban(' fr76 3000 ')).toBe('FR763000')
  })

  it('isIbanRejected : la décision partagée par les trois écritures', () => {
    expect(isIbanRejected(IBAN_SAUVE)).toBe(false)          // IBAN exact
    expect(isIbanRejected(IBAN_FAUX)).toBe(true)            // IBAN, clé fausse
    expect(isIbanRejected('123456789')).toBe(false)         // compte ordinaire
    expect(isIbanRejected('')).toBe(false)                  // rien saisi
    expect(isIbanRejected('   ')).toBe(false)               // rien saisi non plus
  })
})
