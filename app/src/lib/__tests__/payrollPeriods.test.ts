import { describe, it, expect } from 'vitest'
import { periodBounds, periodOf, periodOverlapFilter } from '@/lib/payrollPeriods'

// W4 (RH-06, RH-09) — le rouge d'abord, tel qu'il a été mesuré sur le front :
//   * `.lte('date', '2026-04-31')` → PostgreSQL refuse la date (22008) ; cinq
//     mois sur douze n'importaient rien (février, avril, juin, septembre,
//     novembre) ;
//   * un congé à cheval sur deux mois était filtré « contenu dans la période »
//     et n'entrait dans AUCUN bulletin.
describe('periodBounds — les bornes d\'un mois sont calculées, jamais supposées', () => {
  it('avril : le dernier jour est le 30, pas le 31', () => {
    expect(periodBounds('2026-04')).toEqual({ first: '2026-04-01', last: '2026-04-30' })
  })

  it('les cinq mois qui n\'ont pas de 31 rendent leur vrai dernier jour', () => {
    expect(periodBounds('2026-02').last).toBe('2026-02-28')
    expect(periodBounds('2026-04').last).toBe('2026-04-30')
    expect(periodBounds('2026-06').last).toBe('2026-06-30')
    expect(periodBounds('2026-09').last).toBe('2026-09-30')
    expect(periodBounds('2026-11').last).toBe('2026-11-30')
  })

  it('février bissextile : 29 jours', () => {
    expect(periodBounds('2028-02').last).toBe('2028-02-29')
  })

  it('les mois de 31 jours restent à 31', () => {
    expect(periodBounds('2026-01').last).toBe('2026-01-31')
    expect(periodBounds('2026-12').last).toBe('2026-12-31')
  })

  it('refuse une période qui n\'en est pas une, plutôt que de deviner', () => {
    expect(() => periodBounds('2026-4')).toThrow(/Période invalide/)
    expect(() => periodBounds('2026-13')).toThrow(/mois hors/)
    expect(() => periodBounds('avril-2026')).toThrow(/Période invalide/)
  })
})

describe('periodOverlapFilter — un congé qui traverse deux mois compte dans les deux', () => {
  it('le filtre est une INTERSECTION : commence avant la fin, finit après le début', () => {
    const filter = periodOverlapFilter(periodBounds('2026-04'))
    expect(filter).toBe('start_date.lte.2026-04-30,end_date.gte.2026-04-01')
  })

  it('un congé du 28/04 au 03/05 satisfait le filtre d\'avril ET celui de mai', () => {
    // 28/04 ≤ 30/04 et 03/05 ≥ 01/04 → avril ; 28/04 ≤ 31/05 et 03/05 ≥ 01/05 → mai.
    const avril = periodOverlapFilter(periodBounds('2026-04'))
    const mai = periodOverlapFilter(periodBounds('2026-05'))
    const conge = { start_date: '2026-04-28', end_date: '2026-05-03' }
    const satisfait = (filter: string, r: { start_date: string; end_date: string }) => {
      const [, startCol, startLimit, endCol, endMin] = /^(\w+)\.lte\.(\S+?),(\w+)\.gte\.(\S+)$/.exec(filter) ?? []
      expect(startCol).toBe('start_date')
      expect(endCol).toBe('end_date')
      return r.start_date <= startLimit && r.end_date >= endMin
    }
    expect(satisfait(avril, conge)).toBe(true)
    expect(satisfait(mai, conge)).toBe(true)
  })

  it('les colonnes du filtre sont paramétrables (une absence n\'a pas les mêmes noms)', () => {
    expect(periodOverlapFilter(periodBounds('2026-02'), 'date', 'date')).toBe('date.lte.2026-02-28,date.gte.2026-02-01')
  })
})

describe('periodOf', () => {
  it('rend le mois d\'une date ou d\'un instant ISO', () => {
    expect(periodOf('2026-04-30')).toBe('2026-04')
    expect(periodOf('2026-04-30T23:59:59')).toBe('2026-04')
  })

  it('refuse une date qui n\'en est pas une', () => {
    expect(() => periodOf('avril')).toThrow(/Date invalide/)
  })
})
