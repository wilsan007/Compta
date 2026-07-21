import { describe, it, expect } from 'vitest'
import frNav from '@/i18n/locales/fr/nav.json'
import enNav from '@/i18n/locales/en/nav.json'
import arNav from '@/i18n/locales/ar/nav.json'
import frAcc from '@/i18n/locales/fr/accounting.json'
import enAcc from '@/i18n/locales/en/accounting.json'
import arAcc from '@/i18n/locales/ar/accounting.json'

describe('Phase 1.0 — i18n Completeness', () => {
  const requiredNavKeys = [
    'recurringEntries', 'regularization', 'paymentReminders',
    'bankReconRules', 'bankStatementImport', 'ediTva',
    'paymentDelay', 'currencyRevaluation', 'tvs',
    'progressiveBalance', 'fiscalBackup',
    'analyticPlans', 'distributionGrills',
    'companySettings', 'liasseFiscale', 'multiCompany',
  ]

  const requiredAccKeys = [
    'gdpr', 'ifrs', 'fiscalBackup', 'vatMethods',
    'companySettings', 'system',
  ]

  describe('nav.json — all 3 locales have required keys', () => {
    for (const key of requiredNavKeys) {
      it(`fr/nav.json has items.${key}`, () => {
        expect(frNav.items).toHaveProperty(key)
      })
      it(`en/nav.json has items.${key}`, () => {
        expect(enNav.items).toHaveProperty(key)
      })
      it(`ar/nav.json has items.${key}`, () => {
        expect(arNav.items).toHaveProperty(key)
      })
    }
  })

  describe('accounting.json — all 3 locales have required sections', () => {
    for (const key of requiredAccKeys) {
      it(`fr/accounting.json has ${key}`, () => {
        expect(frAcc).toHaveProperty(key)
      })
      it(`en/accounting.json has ${key}`, () => {
        expect(enAcc).toHaveProperty(key)
      })
      it(`ar/accounting.json has ${key}`, () => {
        expect(arAcc).toHaveProperty(key)
      })
    }
  })

  describe('home.breadcrumb exists in all locales', () => {
    it('fr has home.breadcrumb', () => {
      expect(frAcc.home).toHaveProperty('breadcrumb')
    })
    it('en has home.breadcrumb', () => {
      expect(enAcc.home).toHaveProperty('breadcrumb')
    })
    it('ar has home.breadcrumb', () => {
      expect(arAcc.home).toHaveProperty('breadcrumb')
    })
  })

  describe('No duplicate top-level keys in accounting.json', () => {
    it('fr/accounting.json has 57 keys (no duplicates)', () => {
      expect(Object.keys(frAcc).length).toBe(57)
    })
    it('en/accounting.json has 57 keys (no duplicates)', () => {
      expect(Object.keys(enAcc).length).toBe(57)
    })
    it('ar/accounting.json has 57 keys (no duplicates)', () => {
      expect(Object.keys(arAcc).length).toBe(57)
    })
  })

  describe('VAT method keys exist', () => {
    it('fr has vatMethods.debit and vatMethods.encaissement', () => {
      expect(frAcc.vatMethods).toHaveProperty('debit')
      expect(frAcc.vatMethods).toHaveProperty('encaissement')
    })
    it('en has vatMethods.debit and vatMethods.encaissement', () => {
      expect(enAcc.vatMethods).toHaveProperty('debit')
      expect(enAcc.vatMethods).toHaveProperty('encaissement')
    })
    it('ar has vatMethods.debit and vatMethods.encaissement', () => {
      expect(arAcc.vatMethods).toHaveProperty('debit')
      expect(arAcc.vatMethods).toHaveProperty('encaissement')
    })
  })

  describe('GDPR keys exist', () => {
    it('fr has gdpr.enabled, gdpr.retentionYears, gdpr.anonymizeAfter', () => {
      expect(frAcc.gdpr).toHaveProperty('enabled')
      expect(frAcc.gdpr).toHaveProperty('retentionYears')
      expect(frAcc.gdpr).toHaveProperty('anonymizeAfter')
    })
    it('en has gdpr.enabled, gdpr.retentionYears, gdpr.anonymizeAfter', () => {
      expect(enAcc.gdpr).toHaveProperty('enabled')
      expect(enAcc.gdpr).toHaveProperty('retentionYears')
      expect(enAcc.gdpr).toHaveProperty('anonymizeAfter')
    })
    it('ar has gdpr.enabled, gdpr.retentionYears, gdpr.anonymizeAfter', () => {
      expect(arAcc.gdpr).toHaveProperty('enabled')
      expect(arAcc.gdpr).toHaveProperty('retentionYears')
      expect(arAcc.gdpr).toHaveProperty('anonymizeAfter')
    })
  })

  describe('IFRS keys exist', () => {
    it('fr has ifrs.french_pcga, ifrs.ias_ifrs', () => {
      expect(frAcc.ifrs).toHaveProperty('french_pcga')
      expect(frAcc.ifrs).toHaveProperty('ias_ifrs')
    })
    it('en has ifrs.french_pcga, ifrs.ias_ifrs', () => {
      expect(enAcc.ifrs).toHaveProperty('french_pcga')
      expect(enAcc.ifrs).toHaveProperty('ias_ifrs')
    })
    it('ar has ifrs.french_pcga, ifrs.ias_ifrs', () => {
      expect(arAcc.ifrs).toHaveProperty('french_pcga')
      expect(arAcc.ifrs).toHaveProperty('ias_ifrs')
    })
  })
})
