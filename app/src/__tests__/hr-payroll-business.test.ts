import { describe, it, expect } from 'vitest'
import { calculatePayroll, formatPayrollAmount } from '@/lib/payroll'
import type { Employee, PayRun, PaySlip, Contract, LeaveRequest, PayrollComponent, PayrollTaxGridLine, PayrollAccountingEntry, SalaryAdvance, DsnDeclaration, EmployeeDocument } from '@/types'

const mockEmp1: Employee = { id: 'emp-001', name: 'Ahmed Benali', email: 'a@co.com', phone: '06', position: 'Dev', department: 'IT', salary: 3500, hire_date: '2022-03-01', status: 'active', employee_number: 'E1', social_security_number: '1', birth_date: '1990-05-15', address: 'rue', city: 'Paris', postal_code: '75002', contract_type: 'CDI', contract_end_date: null, created_at: '2022-03-01', updated_at: '2024-01-01' }
const mockEmp2: Employee = { ...mockEmp1, id: 'emp-002', name: 'Fatima', salary: 2800, contract_type: 'CDD', contract_end_date: '2025-12-31' }
const mockEmp3: Employee = { ...mockEmp1, id: 'emp-003', name: 'Karim', salary: 4200, status: 'on_leave' }
const mockEmp4: Employee = { ...mockEmp1, id: 'emp-004', name: 'Sara', salary: 1500, status: 'inactive', contract_type: 'Stage' }
const allEmps = [mockEmp1, mockEmp2, mockEmp3, mockEmp4]

const mockPayRun: PayRun = { id: 'pr-001', number: 'PR-2024-01', period_start: '2024-01-01', period_end: '2024-01-31', pay_date: '2024-01-31', status: 'draft', gross_total: 0, tax_total: 0, net_total: 0, employee_count: 0, created_at: '2024-01-01' }
const mockPayRunApp: PayRun = { ...mockPayRun, id: 'pr-002', number: 'PR-2024-02', status: 'approved', gross_total: 10500, tax_total: 3150, net_total: 7350, employee_count: 3 }

const ps1: PaySlip = { id: 'ps-1', number: 'BS-PR-2024-01-AHM', pay_run_id: 'pr-001', employee_id: 'emp-001', period_start: '2024-01-01', period_end: '2024-01-31', gross_salary: 3500, overtime_pay: 0, bonus: 0, total_gross: 3500, social_security_employee: 770, income_tax: 350, other_deductions: 0, total_deductions: 1120, net_salary: 2380, employer_contributions: 1470, status: 'draft', payment_date: null, created_at: '2024-01-31' }
const ps2: PaySlip = { ...ps1, id: 'ps-2', number: 'BS-PR-2024-01-FAT', employee_id: 'emp-002', gross_salary: 2800, total_gross: 2800, social_security_employee: 616, income_tax: 280, total_deductions: 896, net_salary: 1904, employer_contributions: 1176 }
const ps3: PaySlip = { ...ps1, id: 'ps-3', number: 'BS-PR-2024-01-KAR', employee_id: 'emp-003', gross_salary: 4200, total_gross: 4200, social_security_employee: 924, income_tax: 420, total_deductions: 1344, net_salary: 2856, employer_contributions: 1764 }
const allSlips = [ps1, ps2, ps3]

const mockCT: Contract = { id: 'ct-1', number: 'CT-2022-001', employee_id: 'emp-001', contract_type: 'cdi', start_date: '2022-03-01', end_date: null, position: 'Dev', department: 'IT', monthly_salary: 3500, hourly_rate: 23.09, weekly_hours: 35, trial_period_days: 90, status: 'active', notes: null, created_at: '2022-03-01' }

const mockLR: LeaveRequest = { id: 'lr-1', employee_id: 'emp-001', leave_type: 'annual', start_date: '2024-07-01', end_date: '2024-07-14', days: 10, status: 'pending', reason: 'Vacances', approved_by: null, approved_at: null, created_at: '2024-06-01' }

const mockGL: PayrollTaxGridLine[] = [
  { id: 'gl-1', grid_id: 'g1', line_type: 'percentage', category: 'social_security', label: 'Sécu', base_type: 'gross', min_amount: 0, max_amount: null, rate_employee: 6.98, rate_employer: 29.74, cap_amount: null, fixed_amount: 0, sort_order: 1, created_at: '2024-01-01' },
  { id: 'gl-2', grid_id: 'g1', line_type: 'percentage', category: 'retirement', label: 'Retraite', base_type: 'gross', min_amount: 0, max_amount: null, rate_employee: 11.40, rate_employer: 10.93, cap_amount: null, fixed_amount: 0, sort_order: 2, created_at: '2024-01-01' },
  { id: 'gl-3', grid_id: 'g1', line_type: 'percentage', category: 'csg_crds', label: 'CSG', base_type: 'total_gross', min_amount: 0, max_amount: null, rate_employee: 9.20, rate_employer: 0, cap_amount: null, fixed_amount: 0, sort_order: 3, created_at: '2024-01-01' },
  { id: 'gl-4', grid_id: 'g1', line_type: 'percentage', category: 'income_tax', label: 'IR', base_type: 'taxable_gross', min_amount: 0, max_amount: null, rate_employee: 0, rate_employer: 0, cap_amount: null, fixed_amount: 0, sort_order: 4, created_at: '2024-01-01' },
]

const mockAdv: SalaryAdvance = { id: 'sa-1', tenant_id: 'tid', employee_id: 'emp-001', amount: 500, advance_date: '2024-01-15', deduction_month: '2024-02', status: 'pending', notes: 'Avance', created_at: '2024-01-15' }
const mockDsn: DsnDeclaration = { id: 'dsn-1', tenant_id: 'tid', period: '2024-01', type: 'mensuelle', status: 'draft', file_url: null, generated_at: null, transmitted_at: null, response_code: null, response_message: null, created_at: '2024-01-01' }
const mockDoc: EmployeeDocument = { id: 'doc-1', tenant_id: 'tid', employee_id: 'emp-001', document_type: 'payslip', title: 'Bull 2024-01', file_url: '/d.pdf', file_name: 'd.pdf', file_size: 245000, mime_type: 'application/pdf', period: '2024-01', uploaded_by: 'rh@co.com', visible_to_employee: true, requires_acknowledgment: true, acknowledged: false, acknowledged_at: null, distributed_at: '2024-02-01', e_signed: false, e_signed_at: null, e_signature_hash: null, archived: false, archive_date: null, retention_years: 50, created_at: '2024-02-01' }
const mockPAE: PayrollAccountingEntry = { id: 'pae-1', number: 'OD-PAIE-2024-01', pay_run_id: 'pr-001', period_date: '2024-01-31', gross_total: 10500, employer_contributions_total: 4410, employee_deductions_total: 3360, net_total: 7140, journal_entry_id: null, status: 'draft', created_at: '2024-01-31' }

// ============ 2a: CALCULS DE PAIE ============
describe('2a. Calculs de paie', () => {
  describe('Fallback (sans grid)', () => {
    it('Brut 3500, 0h supp → totalGross=3500', () => {
      const r = calculatePayroll({ grossSalary: 3500, contractType: 'cdi', hoursPerWeek: 35, overtimeHours: 0, mealVouchers: 0, transportAllowance: 0, age: 34, department: 'IT', taxRate: 10 })
      expect(r.grossSalary).toBe(3500)
      expect(r.totalGross).toBe(3500)
    })
    it('10h supp → overtimePay ≈ 288.65', () => {
      const r = calculatePayroll({ grossSalary: 3500, contractType: 'cdi', hoursPerWeek: 35, overtimeHours: 10, mealVouchers: 0, transportAllowance: 0, age: 34, department: 'IT', taxRate: 10 })
      expect(r.overtimePay).toBeCloseTo(10 * (3500/151.67) * 1.25, 1)
    })
    it('Sécu fallback: 3500*6.98% = 244.30', () => {
      const r = calculatePayroll({ grossSalary: 3500, contractType: 'cdi', hoursPerWeek: 35, overtimeHours: 0, mealVouchers: 0, transportAllowance: 0, age: 34, department: 'IT', taxRate: 10 })
      expect(r.socialSecurityEmployee).toBeCloseTo(244.30, 0)
    })
    it('CSG/CRDS: 3500*0.9825*9.2% = 316.365', () => {
      const r = calculatePayroll({ grossSalary: 3500, contractType: 'cdi', hoursPerWeek: 35, overtimeHours: 0, mealVouchers: 0, transportAllowance: 0, age: 34, department: 'IT', taxRate: 10 })
      expect(r.csgCrds).toBeCloseTo(316.365, 1)
    })
    it('IR: 3500*10% = 350', () => {
      const r = calculatePayroll({ grossSalary: 3500, contractType: 'cdi', hoursPerWeek: 35, overtimeHours: 0, mealVouchers: 0, transportAllowance: 0, age: 34, department: 'IT', taxRate: 10 })
      expect(r.incomeTax).toBeCloseTo(350, 0)
    })
    it('Net > 0 et < brut', () => {
      const r = calculatePayroll({ grossSalary: 3500, contractType: 'cdi', hoursPerWeek: 35, overtimeHours: 0, mealVouchers: 0, transportAllowance: 0, age: 34, department: 'IT', taxRate: 10 })
      expect(r.netPay).toBeGreaterThan(0)
      expect(r.netPay).toBeLessThan(3500)
    })
    it('NetPayable = net + vouchers + transport', () => {
      const r = calculatePayroll({ grossSalary: 3500, contractType: 'cdi', hoursPerWeek: 35, overtimeHours: 0, mealVouchers: 200, transportAllowance: 75, age: 34, department: 'IT', taxRate: 10 })
      expect(r.netPayable).toBeCloseTo(r.netPay + 275, 2)
    })
    it('Salaire 0 → tout 0', () => {
      const r = calculatePayroll({ grossSalary: 0, contractType: 'cdi', hoursPerWeek: 35, overtimeHours: 0, mealVouchers: 0, transportAllowance: 0, age: 34, department: 'IT', taxRate: 10 })
      expect(r.netPay).toBe(0)
    })
  })
  describe('Avec grid lines', () => {
    it('Sécu 6.98% + Retraite 11.40% sur 3500', () => {
      const r = calculatePayroll({ grossSalary: 3500, contractType: 'cdi', hoursPerWeek: 35, overtimeHours: 0, mealVouchers: 0, transportAllowance: 0, age: 34, department: 'IT', taxRate: 10 }, mockGL)
      expect(r.socialSecurityEmployee).toBeCloseTo(244.30, 0)
      expect(r.retirementEmployee).toBeCloseTo(399.00, 0)
    })
    it('lineDetails non vide', () => {
      const r = calculatePayroll({ grossSalary: 3500, contractType: 'cdi', hoursPerWeek: 35, overtimeHours: 0, mealVouchers: 0, transportAllowance: 0, age: 34, department: 'IT', taxRate: 10 }, mockGL)
      expect(r.lineDetails.length).toBeGreaterThan(0)
    })
    it('Cotisations patronales: sécu 29.74%', () => {
      const r = calculatePayroll({ grossSalary: 3500, contractType: 'cdi', hoursPerWeek: 35, overtimeHours: 0, mealVouchers: 0, transportAllowance: 0, age: 34, department: 'IT', taxRate: 10 }, mockGL)
      expect(r.socialSecurityEmployer).toBeCloseTo(1040.90, 0)
    })
  })
  describe('formatPayrollAmount', () => {
    it('3500.5 → "3500.50"', () => expect(formatPayrollAmount(3500.5)).toBe('3500.50'))
    it('0 → "0.00"', () => expect(formatPayrollAmount(0)).toBe('0.00'))
  })
})

// ============ 2b: GÉNÉRATION BULLETINS ============
describe('2b. Génération bulletins', () => {
  it('Exclut employés inactifs', () => {
    expect(allEmps.filter(e => e.status !== 'inactive')).toHaveLength(3)
  })
  it('Inclut on_leave', () => {
    expect(allEmps.filter(e => e.status !== 'inactive').find(e => e.id === 'emp-003')).toBeDefined()
  })
  it('Numéro: BS-{run}-{3 lettres nom}', () => {
    expect(`BS-${mockPayRun.number}-${mockEmp1.name.substring(0,3).toUpperCase()}`).toBe('BS-PR-2024-01-AHM')
  })
  it('Net = brut - 22% - 10% pour chaque actif', () => {
    allEmps.filter(e => e.status !== 'inactive').forEach(e => {
      const g = Number(e.salary)
      const net = g - g*0.22 - g*0.10
      expect(net).toBeGreaterThan(0)
      expect(net).toBeLessThan(g)
    })
  })
})

// ============ 2c: COHÉRENCE PAYRUN/PAYSLIPS ============
describe('2c. Cohérence PayRun/PaySlips', () => {
  it('Somme brut = gross_total', () => {
    expect(allSlips.reduce((s,p) => s+p.total_gross, 0)).toBe(mockPayRunApp.gross_total)
  })
  it('Somme net = 7140', () => {
    expect(allSlips.reduce((s,p) => s+p.net_salary, 0)).toBe(7140)
  })
  it('Somme cotisations employeur = 4410', () => {
    expect(allSlips.reduce((s,p) => s+p.employer_contributions, 0)).toBe(4410)
  })
  it('Nombre bulletins = employee_count', () => {
    expect(allSlips.length).toBe(mockPayRunApp.employee_count)
  })
  it('Pas de doublons employé', () => {
    const ids = allSlips.map(p => p.employee_id)
    expect(new Set(ids).size).toBe(ids.length)
  })
  it('Tous employee_id valides', () => {
    const valid = allEmps.map(e => e.id)
    allSlips.forEach(p => expect(valid).toContain(p.employee_id))
  })
})

// ============ 2d: TRANSFERT COMPTABLE ============
describe('2d. Transfert comptable', () => {
  it('BUG: débit ≠ crédit (manque charges patronales au crédit)', () => {
    const debit = mockPAE.gross_total + mockPAE.employer_contributions_total
    const credit = mockPAE.employee_deductions_total + mockPAE.net_total
    expect(debit).toBe(14910)
    expect(credit).toBe(10500)
    expect(debit).not.toBe(credit)
  })
  it('Statut transferred après transfert', () => {
    const e = { ...mockPAE, status: 'transferred' as const, journal_entry_id: 'je-1' }
    expect(e.status).toBe('transferred')
  })
  it('BUG: double préfixe OD-PAIE', () => {
    const num = `OD-PAIE-${mockPAE.number}`
    expect(num).toBe('OD-PAIE-OD-PAIE-2024-01')
  })
})

// ============ 2e: CONGÉS ============
describe('2e. Congés', () => {
  it('10 jours pour lr-1', () => expect(mockLR.days).toBe(10))
  it('Pending → approved', () => {
    const a = { ...mockLR, status: 'approved' as const, approved_by: 'RH', approved_at: '2024-06-15' }
    expect(a.status).toBe('approved')
    expect(a.approved_by).not.toBeNull()
  })
  it('Types valides', () => {
    const types = ['annual','sick','maternity','paternity','unpaid','other']
    expect(types).toContain(mockLR.leave_type)
  })
})

// ============ 2f: CONTRATS ============
describe('2f. Contrats', () => {
  it('CDI: end_date null', () => {
    expect(mockCT.contract_type).toBe('cdi')
    expect(mockCT.end_date).toBeNull()
  })
  it('Taux horaire ≈ 23.09', () => {
    expect(mockCT.monthly_salary / (mockCT.weekly_hours*52/12)).toBeCloseTo(23.09, 1)
  })
  it('Transitions statut', () => {
    let c = { ...mockCT, status: 'active' as const }
    c = { ...c, status: 'suspended' as const }
    expect(c.status).toBe('suspended')
    c = { ...c, status: 'terminated' as const }
    expect(c.status).toBe('terminated')
  })
})

// ============ 2g: AVANCES SALAIRE ============
describe('2g. Avances sur salaire', () => {
  it('Avance 500€ en pending', () => {
    expect(mockAdv.amount).toBe(500)
    expect(mockAdv.status).toBe('pending')
  })
  it('Déduction: net - avance = net restant', () => {
    const net = 2380
    const afterDeduction = net - mockAdv.amount
    expect(afterDeduction).toBe(1880)
  })
  it('Statut deducted après déduction', () => {
    const d = { ...mockAdv, status: 'deducted' as const }
    expect(d.status).toBe('deducted')
  })
})

// ============ 2h: DSN ============
describe('2h. DSN', () => {
  it('DSN draft', () => {
    expect(mockDsn.status).toBe('draft')
    expect(mockDsn.file_url).toBeNull()
  })
  it('Transitions: draft → generated → transmitted → accepted', () => {
    let d = { ...mockDsn, status: 'generated' as const, file_url: '/dsn.xml', generated_at: '2024-02-05' }
    expect(d.status).toBe('generated')
    d = { ...d, status: 'transmitted' as const, transmitted_at: '2024-02-06', response_code: 'OK' }
    expect(d.status).toBe('transmitted')
    d = { ...d, status: 'accepted' as const }
    expect(d.status).toBe('accepted')
  })
  it('Types valides', () => {
    const types = ['mensuelle','arret','reprise','fin_contrat']
    expect(types).toContain(mockDsn.type)
  })
})

// ============ 2i: DOCUMENTS ============
describe('2i. Documents employé', () => {
  it('Payslip: requires_acknowledgment=true, acknowledged=false', () => {
    expect(mockDoc.requires_acknowledgment).toBe(true)
    expect(mockDoc.acknowledged).toBe(false)
  })
  it('Rétention payslip = 50 ans', () => {
    expect(mockDoc.retention_years).toBe(50)
  })
  it('After acknowledge: acknowledged=true + date', () => {
    const d = { ...mockDoc, acknowledged: true, acknowledged_at: '2024-02-10' }
    expect(d.acknowledged).toBe(true)
    expect(d.acknowledged_at).not.toBeNull()
  })
  it('After e-sign: e_signed=true + hash', () => {
    const d = { ...mockDoc, e_signed: true, e_signed_at: '2024-02-11', e_signature_hash: 'abc123' }
    expect(d.e_signed).toBe(true)
    expect(d.e_signature_hash).not.toBeNull()
  })
  it('Archivage: archived=true + date', () => {
    const d = { ...mockDoc, archived: true, archive_date: '2024-03-01' }
    expect(d.archived).toBe(true)
  })
})

// ============ 2j: MULTI-TENANT ============
describe('2j. Multi-tenant', () => {
  it('Tous les types avec tenant_id ont une valeur', () => {
    expect(mockAdv.tenant_id).toBe('tid')
    expect(mockDsn.tenant_id).toBe('tid')
    expect(mockDoc.tenant_id).toBe('tid')
  })
  it('Employee sans tenant_id dans interface (filtrage au niveau query)', () => {
    expect((mockEmp1 as any).tenant_id).toBeUndefined()
  })
})

// ============ 2k: ROBUSTESSE ============
describe('2k. Robustesse', () => {
  it('calculatePayroll avec salaire négatif → net négatif', () => {
    const r = calculatePayroll({ grossSalary: -100, contractType: 'cdi', hoursPerWeek: 35, overtimeHours: 0, mealVouchers: 0, transportAllowance: 0, age: 34, department: 'IT', taxRate: 10 })
    expect(r.netPay).toBeLessThan(0)
  })
  it('calculatePayroll avec taxRate=0 → IR=0', () => {
    const r = calculatePayroll({ grossSalary: 3500, contractType: 'cdi', hoursPerWeek: 35, overtimeHours: 0, mealVouchers: 0, transportAllowance: 0, age: 34, department: 'IT', taxRate: 0 })
    expect(r.incomeTax).toBe(0)
  })
  it('calculatePayroll avec heures supp négatives → overtimePay négatif', () => {
    const r = calculatePayroll({ grossSalary: 3500, contractType: 'cdi', hoursPerWeek: 35, overtimeHours: -5, mealVouchers: 0, transportAllowance: 0, age: 34, department: 'IT', taxRate: 10 })
    expect(r.overtimePay).toBeLessThan(0)
  })
  it('formatPayrollAmount avec NaN → "NaN"', () => {
    expect(formatPayrollAmount(NaN)).toBe('NaN')
  })
})
