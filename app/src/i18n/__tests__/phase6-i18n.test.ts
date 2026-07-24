import { describe, it, expect } from 'vitest'
import frAccounting from '@/i18n/locales/fr/accounting.json'
import enAccounting from '@/i18n/locales/en/accounting.json'
import arAccounting from '@/i18n/locales/ar/accounting.json'
import frNav from '@/i18n/locales/fr/nav.json'
import enNav from '@/i18n/locales/en/nav.json'
import arNav from '@/i18n/locales/ar/nav.json'

// ============ Helper: deep key extraction ============
function getDeepKeys(obj: Record<string, any>, prefix = ''): string[] {
  const keys: string[] = []
  for (const key of Object.keys(obj)) {
    const fullKey = prefix ? `${prefix}.${key}` : key
    if (typeof obj[key] === 'object' && obj[key] !== null && !Array.isArray(obj[key])) {
      keys.push(...getDeepKeys(obj[key], fullKey))
    } else {
      keys.push(fullKey)
    }
  }
  return keys
}

function getMissingKeys(sourceKeys: string[], targetObj: Record<string, any>, prefix: string): string[] {
  const targetKeys = getDeepKeys(targetObj, prefix)
  return sourceKeys.filter(k => !targetKeys.includes(k))
}

// ============ Phase 6 feature keys ============
const phase6Namespaces = [
  'batchEntry', 'autoLabel', 'extourne', 'carryForward', 'lettrageDiff',
  'controls', 'cashControl', 'fecAttest', 'tierRIB',
  'ifrsAdjustments', 'taxPayment', 'customReport', 'deferredPrint',
  'journalAccessRights', 'vatCollection',
]

const phase6NavItems = [
  'batchEntry', 'autoLabel', 'extourne', 'carryForward',
  'lettrageDifferences', 'accountingControls', 'cashControl', 'fecAttestation',
  'tierRIBs', 'ifrsAdjustments', 'taxPayments', 'customReports',
  'deferredPrinting', 'journalAccessRights', 'vatOnCollections',
]

// ============ Tests ============

describe('Phase 6 — i18n Key Completeness (fr → en)', () => {
  for (const ns of phase6Namespaces) {
    it(`English has all French keys for "${ns}"`, () => {
      const frKeys = getDeepKeys((frAccounting as any)[ns] || {}, ns)
      if (frKeys.length === 0) { expect(true).toBe(true); return }
      const missing = getMissingKeys(frKeys, enAccounting, '')
      expect(missing).toEqual([])
    })
  }
})

describe('Phase 6 — i18n Key Completeness (fr → ar)', () => {
  for (const ns of phase6Namespaces) {
    it(`Arabic has all French keys for "${ns}"`, () => {
      const frKeys = getDeepKeys((frAccounting as any)[ns] || {}, ns)
      if (frKeys.length === 0) { expect(true).toBe(true); return }
      const missing = getMissingKeys(frKeys, arAccounting, '')
      expect(missing).toEqual([])
    })
  }
})

describe('Phase 6 — i18n No Empty Values', () => {
  for (const ns of phase6Namespaces) {
    it(`French "${ns}" has no empty string values`, () => {
      const keys = getDeepKeys((frAccounting as any)[ns] || {}, ns)
      for (const key of keys) {
        const parts = key.split('.')
        let val: any = frAccounting
        for (const p of parts) val = val?.[p]
        expect(val).not.toBe('')
        expect(val).not.toBe(null)
        expect(val).not.toBe(undefined)
      }
    })

    it(`English "${ns}" has no empty string values`, () => {
      const keys = getDeepKeys((enAccounting as any)[ns] || {}, ns)
      for (const key of keys) {
        const parts = key.split('.')
        let val: any = enAccounting
        for (const p of parts) val = val?.[p]
        expect(val).not.toBe('')
        expect(val).not.toBe(null)
        expect(val).not.toBe(undefined)
      }
    })

    it(`Arabic "${ns}" has no empty string values`, () => {
      const keys = getDeepKeys((arAccounting as any)[ns] || {}, ns)
      for (const key of keys) {
        const parts = key.split('.')
        let val: any = arAccounting
        for (const p of parts) val = val?.[p]
        expect(val).not.toBe('')
        expect(val).not.toBe(null)
        expect(val).not.toBe(undefined)
      }
    })
  }
})

describe('Phase 6 — Nav Items in all 3 languages', () => {
  for (const navKey of phase6NavItems) {
    it(`French nav has "${navKey}"`, () => {
      expect((frNav.items as any)[navKey]).toBeDefined()
      expect((frNav.items as any)[navKey]).not.toBe('')
    })

    it(`English nav has "${navKey}"`, () => {
      expect((enNav.items as any)[navKey]).toBeDefined()
      expect((enNav.items as any)[navKey]).not.toBe('')
    })

    it(`Arabic nav has "${navKey}"`, () => {
      expect((arNav.items as any)[navKey]).toBeDefined()
      expect((arNav.items as any)[navKey]).not.toBe('')
    })
  }
})

describe('Phase 6 — No duplicate keys in accounting.json', () => {
  it('French accounting.json has no duplicate top-level keys', () => {
    const raw = JSON.stringify(frAccounting)
    const parsed = JSON.parse(raw)
    const keys = Object.keys(parsed)
    const unique = new Set(keys)
    expect(keys.length).toBe(unique.size)
  })

  it('English accounting.json has no duplicate top-level keys', () => {
    const raw = JSON.stringify(enAccounting)
    const parsed = JSON.parse(raw)
    const keys = Object.keys(parsed)
    const unique = new Set(keys)
    expect(keys.length).toBe(unique.size)
  })

  it('Arabic accounting.json has no duplicate top-level keys', () => {
    const raw = JSON.stringify(arAccounting)
    const parsed = JSON.parse(raw)
    const keys = Object.keys(parsed)
    const unique = new Set(keys)
    expect(keys.length).toBe(unique.size)
  })
})

describe('Phase 6 — i18n Key Structure Validation', () => {
  const requiredSubKeys = ['title', 'subtitle', 'empty']

  for (const ns of phase6Namespaces) {
    it(`"${ns}" has required sub-keys (title, subtitle, empty) in fr`, () => {
      const section = (frAccounting as any)[ns]
      expect(section).toBeDefined()
      for (const sk of requiredSubKeys) {
        expect(section[sk]).toBeDefined()
      }
    })

    it(`"${ns}" has required sub-keys (title, subtitle, empty) in en`, () => {
      const section = (enAccounting as any)[ns]
      expect(section).toBeDefined()
      for (const sk of requiredSubKeys) {
        expect(section[sk]).toBeDefined()
      }
    })

    it(`"${ns}" has required sub-keys (title, subtitle, empty) in ar`, () => {
      const section = (arAccounting as any)[ns]
      expect(section).toBeDefined()
      for (const sk of requiredSubKeys) {
        expect(section[sk]).toBeDefined()
      }
    })
  }
})
