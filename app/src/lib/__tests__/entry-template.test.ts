import { describe, it, expect } from 'vitest'
import { templateLineAmounts, defaultEntryDate } from '@/lib/entryTemplate'

describe('templateLineAmounts — F6 (cpt-007)', () => {
  it('un pourcentage n’est jamais recopié comme un montant', () => {
    expect(templateLineAmounts({ amount_type: 'percent', debit_pct: 100, credit_pct: 0 })).toEqual({ debit: '', credit: '' })
    expect(templateLineAmounts({ amount_type: 'input', debit_pct: 100, credit_pct: 0 })).toEqual({ debit: '', credit: '' })
  })
  it('un montant fixe va d’un seul côté : celui que désigne le pourcentage', () => {
    expect(templateLineAmounts({ amount_type: 'fixed', fixed_amount: 250, debit_pct: 100, credit_pct: 0 })).toEqual({ debit: '250', credit: '' })
    expect(templateLineAmounts({ amount_type: 'fixed', fixed_amount: 250, debit_pct: 0, credit_pct: 100 })).toEqual({ debit: '', credit: '250' })
  })
  it('sans sens indiqué, un montant fixe va au débit — jamais des deux côtés', () => {
    expect(templateLineAmounts({ amount_type: 'fixed', fixed_amount: 80, debit_pct: 0, credit_pct: 0 })).toEqual({ debit: '80', credit: '' })
  })
  it('solde et TVA calculée : rien n’est prérempli', () => {
    expect(templateLineAmounts({ amount_type: 'balance' })).toEqual({ debit: '', credit: '' })
    expect(templateLineAmounts({ amount_type: 'calc_vat', debit_pct: 20 })).toEqual({ debit: '', credit: '' })
  })
  it('un montant fixe vide ne préremplit rien', () => {
    expect(templateLineAmounts({ amount_type: 'fixed', fixed_amount: null, debit_pct: 100 })).toEqual({ debit: '', credit: '' })
  })
})

describe('defaultEntryDate — F7 (cpt-008)', () => {
  it('aujourd’hui, s’il est dans la période', () => {
    expect(defaultEntryDate('2026-10-01', '2026-10-31', '2026-10-04')).toBe('2026-10-04')
  })
  it('le premier jour de la période, si aujourd’hui est après', () => {
    expect(defaultEntryDate('2026-03-01', '2026-03-31', '2026-10-04')).toBe('2026-03-01')
  })
  it('le premier jour de la période, si aujourd’hui est avant', () => {
    expect(defaultEntryDate('2027-01-01', '2027-01-31', '2026-10-04')).toBe('2027-01-01')
  })
  it('sans période, la date du jour', () => {
    expect(defaultEntryDate(null, null, '2026-10-04')).toBe('2026-10-04')
  })
  it('les bornes de la période sont incluses', () => {
    expect(defaultEntryDate('2026-10-04', '2026-10-31', '2026-10-04')).toBe('2026-10-04')
    expect(defaultEntryDate('2026-10-01', '2026-10-04', '2026-10-04')).toBe('2026-10-04')
  })
})
