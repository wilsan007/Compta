import { describe, it, expect } from 'vitest'
import { aggregateAnalyticBalance } from '@/lib/queries/accounting'
import { isEditableDraft } from '@/lib/invoiceDraft'

// 2.13 (353) — la grille de ventilation s'applique à l'écriture et écrit ses PARTS
// dans `analytic_distribution_lines`. La balance analytique ne lisait qu'UNE section
// par ligne d'écriture : sur une grille 60 / 40, la section dominante recevait 600
// et les 400 restants n'apparaissaient nulle part.
describe('balance analytique — chaque section reçoit sa part de ventilation', () => {
  const sections = [
    { id: 's60', code: 'GR60', name: 'Soixante', plan_id: 'p1' },
    { id: 's40', code: 'GR40', name: 'Quarante', plan_id: 'p1' },
    { id: 'sx', code: 'UNIQ', name: 'Unique', plan_id: null },
  ]

  it('une ligne ventilée 60 / 40 : 600 et 400, au crédit comme la ligne', () => {
    const rows = aggregateAnalyticBalance([
      { analytic_section_id: 's60', analytic_amount: 600, debit: 0, credit: 1000,
        analytic_distribution_lines: [{ section_id: 's60', amount: 600 }, { section_id: 's40', amount: 400 }] },
    ], sections)
    expect(rows.map((r) => [r.sectionCode, r.totalDebit, r.totalCredit, r.totalAnalytic])).toEqual([
      ['GR40', 0, 400, 400],
      ['GR60', 0, 600, 600],
    ])
    expect(rows.reduce((s, r) => s + r.totalAnalytic, 0)).toBe(1000)
  })

  it("l'ancienne lecture (une section par ligne) perdait les 400 de la seconde section", () => {
    // La même ligne, lue sans ses parts : la mesure du défaut.
    const rows = aggregateAnalyticBalance([{ analytic_section_id: 's60', analytic_amount: 600, debit: 0, credit: 1000 }], sections)
    expect(rows.map((r) => r.sectionCode)).toEqual(['GR60'])
    expect(rows[0].totalAnalytic).toBe(600)
  })

  it('une ligne sans ventilation garde sa section unique, et son plan remonte', () => {
    const rows = aggregateAnalyticBalance([
      { analytic_section_id: 'sx', analytic_amount: '250', debit: '250', credit: 0, analytic_distribution_lines: [] },
      { analytic_section_id: null, analytic_amount: null, debit: 10, credit: 0 },
    ], sections)
    expect(rows).toEqual([{ sectionId: 'sx', sectionCode: 'UNIQ', sectionName: 'Unique', planId: null, totalDebit: 250, totalCredit: 0, totalAnalytic: 250 }])
  })
})

describe('brouillon de facture — ce qui se modifie depuis l\'écran (2.13)', () => {
  it('un brouillon saisi à la main se modifie', () => {
    expect(isEditableDraft({ validation_status: 'draft', status: 'draft', invoice_lines: [{}] })).toBe(true)
  })
  it('une facture validée ou annulée ne se modifie pas', () => {
    expect(isEditableDraft({ validation_status: 'validated', status: 'sent' })).toBe(false)
    expect(isEditableDraft({ validation_status: 'draft', status: 'cancelled' })).toBe(false)
    expect(isEditableDraft(null)).toBe(false)
  })
  it("un brouillon né d'un autre document, ou qui porte un acompte, ne se rouvre pas ici", () => {
    expect(isEditableDraft({ validation_status: 'draft', invoice_lines: [{ time_entry_id: 't1' }] })).toBe(false)
    expect(isEditableDraft({ validation_status: 'draft', invoice_lines: [{ delivery_note_line_id: 'd1' }] })).toBe(false)
    expect(isEditableDraft({ validation_status: 'draft', invoice_lines: [{ sales_order_line_id: 'o1' }] })).toBe(false)
    expect(isEditableDraft({ validation_status: 'draft', invoice_lines: [{ advance_invoice_id: 'a1' }] })).toBe(false)
    expect(isEditableDraft({ validation_status: 'draft', invoice_type: 'advance' })).toBe(false)
  })
})
