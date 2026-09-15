import { describe, it, expect } from 'vitest'
import { calculatePayroll, formatPayrollAmount } from '@/lib/payroll'
import type { PayrollTaxGridLine } from '@/types'

// ============================================================
// Tests complets : Éléments variables de paie (migration 81)
// Teste l'intégration des acomptes, rappels, notes de frais,
// congés sans solde et autres déductions dans le moteur de calcul.
// ============================================================

const baseInput = {
  grossSalary: 3500,
  contractType: 'cdi' as const,
  hoursPerWeek: 35,
  overtimeHours: 0,
  mealVouchers: 0,
  transportAllowance: 0,
  age: 34,
  department: 'IT',
  taxRate: 10,
}

const mockGrid: PayrollTaxGridLine[] = [
  { id: 'gl-1', grid_id: 'g1', line_type: 'percentage', category: 'social_security', label: 'Sécu', base_type: 'gross', min_amount: 0, max_amount: null, rate_employee: 6.98, rate_employer: 29.74, cap_amount: null, fixed_amount: 0, sort_order: 1, created_at: '2024-01-01' },
  { id: 'gl-2', grid_id: 'g1', line_type: 'percentage', category: 'retirement', label: 'Retraite', base_type: 'gross', min_amount: 0, max_amount: null, rate_employee: 11.40, rate_employer: 10.93, cap_amount: null, fixed_amount: 0, sort_order: 2, created_at: '2024-01-01' },
  { id: 'gl-3', grid_id: 'g1', line_type: 'percentage', category: 'csg_crds', label: 'CSG', base_type: 'total_gross', min_amount: 0, max_amount: null, rate_employee: 9.20, rate_employer: 0, cap_amount: null, fixed_amount: 0, sort_order: 3, created_at: '2024-01-01' },
  { id: 'gl-4', grid_id: 'g1', line_type: 'percentage', category: 'income_tax', label: 'IR', base_type: 'taxable_gross', min_amount: 0, max_amount: null, rate_employee: 0, rate_employer: 0, cap_amount: null, fixed_amount: 0, sort_order: 4, created_at: '2024-01-01' },
]

// ============ 1. Acompte sur salaire (advance_deduction) ============
describe('1. Acompte sur salaire (advanceDeduction)', () => {
  it('déduit l\'acompte du net à payer (fallback)', () => {
    const sans = calculatePayroll(baseInput)
    const avec = calculatePayroll({ ...baseInput, advanceDeduction: 500 })
    expect(avec.advanceDeduction).toBe(500)
    expect(avec.totalVariableDeductions).toBe(500)
    expect(avec.netPayable).toBeCloseTo(sans.netPayable - 500, 2)
  })

  it('déduit l\'acompte du net à payer (avec grid)', () => {
    const sans = calculatePayroll(baseInput, mockGrid)
    const avec = calculatePayroll({ ...baseInput, advanceDeduction: 500 }, mockGrid)
    expect(avec.netPayable).toBeCloseTo(sans.netPayable - 500, 2)
  })

  it('n\'affecte pas le totalGross (déduction post-brut)', () => {
    const sans = calculatePayroll(baseInput)
    const avec = calculatePayroll({ ...baseInput, advanceDeduction: 500 })
    expect(avec.totalGross).toBe(sans.totalGross)
  })

  it('n\'affecte pas les cotisations sociales (base = brut)', () => {
    const sans = calculatePayroll(baseInput)
    const avec = calculatePayroll({ ...baseInput, advanceDeduction: 500 })
    expect(avec.socialSecurityEmployee).toBe(sans.socialSecurityEmployee)
    expect(avec.retirementEmployee).toBe(sans.retirementEmployee)
  })

  it('ajoute l\'acompte dans lineDetails', () => {
    const r = calculatePayroll({ ...baseInput, advanceDeduction: 300 })
    const advanceLine = r.lineDetails.find((l) => l.category === 'advance_deduction')
    expect(advanceLine).toBeDefined()
    expect(advanceLine!.amount).toBe(-300)
    expect(advanceLine!.label).toContain('Acompte')
  })

  it('acompte de 0 → pas dans lineDetails', () => {
    const r = calculatePayroll(baseInput)
    expect(r.lineDetails.find((l) => l.category === 'advance_deduction')).toBeUndefined()
  })

  it('acompte supérieur au net → netPayable négatif', () => {
    const r = calculatePayroll({ ...baseInput, advanceDeduction: 100000 })
    expect(r.netPayable).toBeLessThan(0)
  })

  it('multiple acomptes cumulés', () => {
    const r = calculatePayroll({ ...baseInput, advanceDeduction: 200 + 300 + 100 })
    expect(r.advanceDeduction).toBe(600)
    expect(r.totalVariableDeductions).toBe(600)
  })
})

// ============ 2. Rappel de paie (pay_recall) ============
describe('2. Rappel de paie (payRecall)', () => {
  it('augmente le totalGross (rappel positif)', () => {
    const sans = calculatePayroll(baseInput)
    const avec = calculatePayroll({ ...baseInput, payRecall: 800 })
    expect(avec.totalGross).toBeCloseTo(sans.totalGross + 800, 2)
  })

  it('augmente la CSG/CRDS (base = totalGross plus élevé)', () => {
    const sans = calculatePayroll(baseInput)
    const avec = calculatePayroll({ ...baseInput, payRecall: 800 })
    // En fallback, socialSecurityEmployee est sur grossSalary (fixe),
    // mais csgCrds est sur totalGross (qui inclut le rappel)
    expect(avec.csgCrds).toBeGreaterThan(sans.csgCrds)
  })

  it('augmente l\'impôt sur le revenu', () => {
    const sans = calculatePayroll(baseInput)
    const avec = calculatePayroll({ ...baseInput, payRecall: 800 })
    expect(avec.incomeTax).toBeGreaterThan(sans.incomeTax)
  })

  it('rappel de 0 → pas dans lineDetails', () => {
    const r = calculatePayroll(baseInput)
    expect(r.lineDetails.find((l) => l.category === 'pay_recall')).toBeUndefined()
  })

  it('ajoute le rappel dans lineDetails', () => {
    const r = calculatePayroll({ ...baseInput, payRecall: 500 })
    const recallLine = r.lineDetails.find((l) => l.category === 'pay_recall')
    expect(recallLine).toBeDefined()
    expect(recallLine!.amount).toBe(500)
  })

  it('rappel avec grid → cotisations calculées sur totalGross', () => {
    const r = calculatePayroll({ ...baseInput, payRecall: 1000 }, mockGrid)
    const expectedSecu = 3500 * 6.98 / 100  // sur brut de base
    // La sécu est sur 'gross' (brut de base), pas sur totalGross
    expect(r.socialSecurityEmployee).toBeCloseTo(expectedSecu, 0)
    // Mais la CSG est sur totalGross
    const expectedCsg = (4500 * 0.9825) * 9.2 / 100
    expect(r.csgCrds).toBeCloseTo(expectedCsg, 0)
  })
})

// ============ 3. Remboursement de notes de frais (expense_reimbursement) ============
describe('3. Remboursement de frais (expenseReimbursement)', () => {
  it('ajoute au net à payer (non imposable)', () => {
    const sans = calculatePayroll(baseInput)
    const avec = calculatePayroll({ ...baseInput, expenseReimbursement: 250 })
    expect(avec.netPayable).toBeCloseTo(sans.netPayable + 250, 2)
  })

  it('n\'augmente pas le totalGross', () => {
    const sans = calculatePayroll(baseInput)
    const avec = calculatePayroll({ ...baseInput, expenseReimbursement: 250 })
    expect(avec.totalGross).toBe(sans.totalGross)
  })

  it('n\'augmente pas les cotisations', () => {
    const sans = calculatePayroll(baseInput)
    const avec = calculatePayroll({ ...baseInput, expenseReimbursement: 250 })
    expect(avec.socialSecurityEmployee).toBe(sans.socialSecurityEmployee)
    expect(avec.csgCrds).toBe(sans.csgCrds)
  })

  it('n\'augmente pas l\'impôt', () => {
    const sans = calculatePayroll(baseInput)
    const avec = calculatePayroll({ ...baseInput, expenseReimbursement: 250 })
    expect(avec.incomeTax).toBe(sans.incomeTax)
  })

  it('totalReimbursements = expenseReimbursement', () => {
    const r = calculatePayroll({ ...baseInput, expenseReimbursement: 350 })
    expect(r.totalReimbursements).toBe(350)
  })

  it('ajoute dans lineDetails', () => {
    const r = calculatePayroll({ ...baseInput, expenseReimbursement: 150 })
    const line = r.lineDetails.find((l) => l.category === 'expense_reimbursement')
    expect(line).toBeDefined()
    expect(line!.amount).toBe(150)
  })

  it('augmente le coût total employeur', () => {
    const sans = calculatePayroll(baseInput)
    const avec = calculatePayroll({ ...baseInput, expenseReimbursement: 200 })
    expect(avec.totalCostEmployer).toBeGreaterThan(sans.totalCostEmployer)
  })
})

// ============ 4. Congé sans solde (unpaid_leave_deduction) ============
describe('4. Congé sans solde (unpaidLeaveDeduction)', () => {
  it('déduit du net à payer', () => {
    const sans = calculatePayroll(baseInput)
    const avec = calculatePayroll({ ...baseInput, unpaidLeaveDeduction: 400 })
    expect(avec.netPayable).toBeCloseTo(sans.netPayable - 400, 2)
  })

  it('n\'affecte pas le totalGross', () => {
    const sans = calculatePayroll(baseInput)
    const avec = calculatePayroll({ ...baseInput, unpaidLeaveDeduction: 400 })
    expect(avec.totalGross).toBe(sans.totalGross)
  })

  it('n\'affecte pas les cotisations', () => {
    const sans = calculatePayroll(baseInput)
    const avec = calculatePayroll({ ...baseInput, unpaidLeaveDeduction: 400 })
    expect(avec.socialSecurityEmployee).toBe(sans.socialSecurityEmployee)
  })

  it('incluse dans totalVariableDeductions', () => {
    const r = calculatePayroll({ ...baseInput, unpaidLeaveDeduction: 300 })
    expect(r.totalVariableDeductions).toBe(300)
  })

  it('ajoute dans lineDetails avec montant négatif', () => {
    const r = calculatePayroll({ ...baseInput, unpaidLeaveDeduction: 250 })
    const line = r.lineDetails.find((l) => l.category === 'unpaid_leave_deduction')
    expect(line).toBeDefined()
    expect(line!.amount).toBe(-250)
  })
})

// ============ 5. Autres déductions (other_deductions) ============
describe('5. Autres déductions (otherDeductions)', () => {
  it('déduit du net à payer', () => {
    const sans = calculatePayroll(baseInput)
    const avec = calculatePayroll({ ...baseInput, otherDeductions: 150 })
    expect(avec.netPayable).toBeCloseTo(sans.netPayable - 150, 2)
  })

  it('n\'affecte pas le totalGross', () => {
    const r = calculatePayroll({ ...baseInput, otherDeductions: 150 })
    expect(r.totalGross).toBe(3500)
  })

  it('incluse dans totalVariableDeductions', () => {
    const r = calculatePayroll({ ...baseInput, otherDeductions: 100 })
    expect(r.totalVariableDeductions).toBe(100)
  })

  it('ajoute dans lineDetails', () => {
    const r = calculatePayroll({ ...baseInput, otherDeductions: 75 })
    const line = r.lineDetails.find((l) => l.category === 'other_deductions')
    expect(line).toBeDefined()
    expect(line!.amount).toBe(-75)
  })
})

// ============ 6. Combinaisons complexes ============
describe('6. Combinaisons d\'éléments variables', () => {
  it('acompte + rappel + frais + congé + autres simultanément', () => {
    const r = calculatePayroll({
      ...baseInput,
      advanceDeduction: 500,
      payRecall: 800,
      expenseReimbursement: 250,
      unpaidLeaveDeduction: 300,
      otherDeductions: 100,
    })
    // totalGross = brut + rappel
    expect(r.totalGross).toBeCloseTo(3500 + 800, 2)
    // totalVariableDeductions = acompte + congé + autres
    expect(r.totalVariableDeductions).toBe(500 + 300 + 100)
    // totalReimbursements = frais
    expect(r.totalReimbursements).toBe(250)
    // Vérifier que tous les éléments sont dans lineDetails
    expect(r.lineDetails.find((l) => l.category === 'advance_deduction')).toBeDefined()
    expect(r.lineDetails.find((l) => l.category === 'pay_recall')).toBeDefined()
    expect(r.lineDetails.find((l) => l.category === 'expense_reimbursement')).toBeDefined()
    expect(r.lineDetails.find((l) => l.category === 'unpaid_leave_deduction')).toBeDefined()
    expect(r.lineDetails.find((l) => l.category === 'other_deductions')).toBeDefined()
  })

  it('netPayable = netPay + mealVouchers + transport + reimbursements - variableDeductions', () => {
    const r = calculatePayroll({
      ...baseInput,
      mealVouchers: 200,
      transportAllowance: 75,
      advanceDeduction: 500,
      expenseReimbursement: 250,
      unpaidLeaveDeduction: 300,
    })
    const expected = r.netPay + 200 + 75 + 250 - (500 + 300)
    expect(r.netPayable).toBeCloseTo(expected, 2)
  })

  it('avec grid : tous les éléments simultanément', () => {
    const r = calculatePayroll({
      ...baseInput,
      advanceDeduction: 500,
      payRecall: 800,
      expenseReimbursement: 250,
      unpaidLeaveDeduction: 300,
      otherDeductions: 100,
    }, mockGrid)
    expect(r.totalGross).toBeCloseTo(4300, 2)
    expect(r.totalVariableDeductions).toBe(900)
    expect(r.totalReimbursements).toBe(250)
    expect(r.netPayable).toBeGreaterThan(0)
  })

  it('toutes les déductions à 0 → netPayable = netPay + allowances', () => {
    const r = calculatePayroll({
      ...baseInput,
      mealVouchers: 200,
      transportAllowance: 75,
    })
    expect(r.totalVariableDeductions).toBe(0)
    expect(r.totalReimbursements).toBe(0)
    expect(r.netPayable).toBeCloseTo(r.netPay + 275, 2)
  })

  it('rappel négatif (récupération) diminue le brut', () => {
    const r = calculatePayroll({ ...baseInput, payRecall: -500 })
    expect(r.totalGross).toBeCloseTo(3000, 2)
    expect(r.payRecall).toBe(-500)
  })

  it('valeurs décimales précises', () => {
    const r = calculatePayroll({
      ...baseInput,
      advanceDeduction: 123.45,
      expenseReimbursement: 67.89,
      unpaidLeaveDeduction: 234.56,
    })
    expect(r.advanceDeduction).toBe(123.45)
    expect(r.expenseReimbursement).toBe(67.89)
    expect(r.unpaidLeaveDeduction).toBe(234.56)
    expect(r.totalVariableDeductions).toBeCloseTo(358.01, 2)
    expect(r.totalReimbursements).toBe(67.89)
  })
})

// ============ 7. Tests de cohérence ============
describe('7. Cohérence du moteur de calcul', () => {
  it('totalVariableDeductions = advance + unpaidLeave + other', () => {
    const r = calculatePayroll({
      ...baseInput,
      advanceDeduction: 100,
      unpaidLeaveDeduction: 200,
      otherDeductions: 50,
    })
    expect(r.totalVariableDeductions).toBe(r.advanceDeduction + r.unpaidLeaveDeduction + r.otherVariableDeductions)
  })

  it('totalReimbursements = expenseReimbursement', () => {
    const r = calculatePayroll({ ...baseInput, expenseReimbursement: 300 })
    expect(r.totalReimbursements).toBe(r.expenseReimbursement)
  })

  it('netPayable = netPay + allowances + reimbursements - variableDeductions (fallback)', () => {
    const r = calculatePayroll({
      ...baseInput,
      mealVouchers: 100,
      transportAllowance: 50,
      advanceDeduction: 200,
      expenseReimbursement: 100,
    })
    expect(r.netPayable).toBeCloseTo(
      r.netPay + 100 + 50 + 100 - 200, 2
    )
  })

  it('netPayable = netPay + allowances + reimbursements - variableDeductions (grid)', () => {
    const r = calculatePayroll({
      ...baseInput,
      mealVouchers: 100,
      transportAllowance: 50,
      advanceDeduction: 200,
      expenseReimbursement: 100,
    }, mockGrid)
    expect(r.netPayable).toBeCloseTo(
      r.netPay + 100 + 50 + 100 - 200, 2
    )
  })

  it('formatPayrollAmount formate avec 2 décimales', () => {
    expect(formatPayrollAmount(1234.5)).toBe('1234.50')
    expect(formatPayrollAmount(0)).toBe('0.00')
    expect(formatPayrollAmount(1234.567)).toBe('1234.57')
  })

  it('totalCostEmployer inclut les remboursements', () => {
    const sans = calculatePayroll(baseInput)
    const avec = calculatePayroll({ ...baseInput, expenseReimbursement: 500 })
    expect(avec.totalCostEmployer).toBeCloseTo(sans.totalCostEmployer + 500, 2)
  })

  it('totalCostEmployer n\'inclut pas les déductions variables', () => {
    const sans = calculatePayroll(baseInput)
    const avec = calculatePayroll({ ...baseInput, advanceDeduction: 500 })
    expect(avec.totalCostEmployer).toBe(sans.totalCostEmployer)
  })
})

// ============ 8. Edge cases ============
describe('8. Edge cases', () => {
  it('salaire 0 avec tous les éléments → déductions seulement', () => {
    const r = calculatePayroll({
      ...baseInput,
      grossSalary: 0,
      advanceDeduction: 100,
      expenseReimbursement: 50,
    })
    expect(r.grossSalary).toBe(0)
    expect(r.totalGross).toBe(0)
    expect(r.netPay).toBe(0)
    expect(r.netPayable).toBeCloseTo(50 - 100, 2)  // reimbursement - deduction
  })

  it('heures supp + acompte + rappel combinés', () => {
    const r = calculatePayroll({
      ...baseInput,
      overtimeHours: 10,
      payRecall: 500,
      advanceDeduction: 300,
    })
    // totalGross = 3500 + overtime + 500
    expect(r.totalGross).toBeCloseTo(3500 + r.overtimePay + 500, 2)
    // netPayable réduit par l'acompte
    const sansAcompte = calculatePayroll({
      ...baseInput,
      overtimeHours: 10,
      payRecall: 500,
    })
    expect(r.netPayable).toBeCloseTo(sansAcompte.netPayable - 300, 2)
  })

  it('très grand montant d\'acompte', () => {
    const r = calculatePayroll({ ...baseInput, advanceDeduction: 999999.99 })
    expect(r.advanceDeduction).toBe(999999.99)
    expect(r.netPayable).toBeLessThan(0)
  })

  it('montants négatifs interdits pour expenseReimbursement', () => {
    // Le moteur ne valide pas, mais on teste le comportement
    const r = calculatePayroll({ ...baseInput, expenseReimbursement: -100 })
    expect(r.expenseReimbursement).toBe(-100)
    expect(r.totalReimbursements).toBe(-100)
  })

  it('undefined vs 0 pour tous les champs optionnels', () => {
    const r1 = calculatePayroll(baseInput)
    const r2 = calculatePayroll({
      ...baseInput,
      advanceDeduction: 0,
      payRecall: 0,
      expenseReimbursement: 0,
      unpaidLeaveDeduction: 0,
      otherDeductions: 0,
    })
    expect(r1.netPayable).toBe(r2.netPayable)
    expect(r1.totalVariableDeductions).toBe(r2.totalVariableDeductions)
  })
})
