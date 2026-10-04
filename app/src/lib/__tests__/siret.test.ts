import { describe, it, expect } from 'vitest'
import { isSiretValid, luhnValid, hasSiret } from '@/lib/siret'
import { countryLabel, isEuCountry, normalizeCountryCode, EU_COUNTRY_CODES } from '@/lib/countries'

// A4 (migration 318) — le SIRET se contrôle au clavier (clé de Luhn) et le
// pays est un code ISO 3166-1 alpha-2, jamais un nom. C'est ce que le
// générateur Factur-X écrit dans `<cbc:IdentificationCode>`.

describe('A4 — la clé de Luhn du SIRET', () => {
  it('un SIRET bien formé et protégé est accepté', () => {
    expect(isSiretValid('73282932000074')).toBe(true)   // document de test
    expect(isSiretValid('732 829 320 00074')).toBe(true) // les espaces ne comptent pas
  })

  it('un SIRET dont la clé est fausse est refusé', () => {
    expect(isSiretValid('12345678901234')).toBe(false)
    expect(isSiretValid('73282932000075')).toBe(false)  // un seul chiffre changé
  })

  it('ce qui n’est pas un SIRET est refusé, et un SIRET absent ne l’est pas', () => {
    expect(isSiretValid('7328293200007')).toBe(false)   // 13 chiffres
    expect(isSiretValid('732829320000741')).toBe(false) // 15 chiffres
    expect(isSiretValid('ABCDEFGHIJKLMN')).toBe(false)  // lettres
    expect(isSiretValid('')).toBe(true)                 // non renseigné ≠ faux
    expect(isSiretValid(null)).toBe(true)
  })

  it('la clé de Luhn, prise seule, porte sur les chiffres', () => {
    // 732 829 320 est le SIREN du document de test : somme de Luhn 40.
    expect(luhnValid('732829320')).toBe(true)
    expect(luhnValid('732829321')).toBe(false)
    expect(hasSiret('  ')).toBe(false)
    expect(hasSiret('732829320')).toBe(true)
  })
})

describe('A4 — le pays est un code ISO à deux lettres', () => {
  it('un code est normalisé, un nom aussi (l’existant portait des noms)', () => {
    expect(normalizeCountryCode('BE')).toBe('BE')
    expect(normalizeCountryCode(' be ')).toBe('BE')
    expect(normalizeCountryCode('Belgique')).toBe('BE')
    expect(normalizeCountryCode('France')).toBe('FR')
  })

  it('un code à deux lettres hors liste passe quand même, un nom sans code non', () => {
    // La liste n'est pas le catalogue ISO complet, et c'est délibéré : on ne
    // refuse pas un client parce qu'il vient d'un pays non listé. La base, elle,
    // n'accepte que deux lettres (migration 318).
    expect(normalizeCountryCode('ZZ')).toBe('ZZ')
    expect(normalizeCountryCode('BXL')).toBeNull()  // trois lettres : ce n'est pas un code
    expect(normalizeCountryCode('')).toBeNull()
    expect(normalizeCountryCode(null)).toBeNull()
  })

  it('l’Union européenne est reconnue par son code (B3)', () => {
    expect(EU_COUNTRY_CODES).toHaveLength(27)
    expect(isEuCountry('BE')).toBe(true)
    expect(isEuCountry('FR')).toBe(true)
    expect(isEuCountry('MA')).toBe(false)  // voisin, hors UE
    expect(isEuCountry('GB')).toBe(false)
    expect(isEuCountry('ZZ')).toBe(false)
    expect(isEuCountry(null)).toBe(false)
  })

  it('un code inconnu est affiché tel quel plutôt que perdu', () => {
    expect(countryLabel('BE')).toBe('Belgique')
    expect(countryLabel('ZZ')).toBe('ZZ')
    expect(countryLabel(null)).toBe('')
  })
})
