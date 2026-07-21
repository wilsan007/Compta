// French payroll calculation engine.
// Computes gross, social contributions, income tax (prélèvement à la source),
// and net pay for employees based on 2024-2025 French rates.

export interface PayrollInput {
  grossSalary: number
  contractType: 'cdi' | 'cdd' | 'apprentice'
  hoursPerWeek: number
  overtimeHours: number
  mealVouchers: number
  transportAllowance: number
  age: number
  department: string
  taxRate: number
}

export interface PayrollResult {
  grossSalary: number
  overtimePay: number
  totalGross: number
  mealVouchers: number
  transportAllowance: number
  // Employee contributions (cotisations salariales)
  socialSecurityEmployee: number
  healthEmployee: number
  retirementEmployee: number
  unemploymentEmployee: number
  csgCrds: number
  totalEmployeeContributions: number
  // Employer contributions (cotisations patronales)
  socialSecurityEmployer: number
  healthEmployer: number
  retirementEmployer: number
  unemploymentEmployer: number
  totalEmployerContributions: number
  // Tax
  incomeTax: number
  // Net
  netPay: number
  netPayable: number
  totalCostEmployer: number
}

// 2024-2025 French payroll rates (simplified)
const RATES = {
  socialSecurity: { employee: 0.0698, employer: 0.2974 },
  health: { employee: 0.004, employer: 0.0728 },
  retirement: { employee: 0.1140, employer: 0.1093 },
  unemployment: { employee: 0.0024, employer: 0.0428 },
  csgCrds: 0.0920,
  overtimeRate: 1.25,
}

export function calculatePayroll(input: PayrollInput): PayrollResult {
  const grossSalary = input.grossSalary
  const overtimePay = input.overtimeHours * (grossSalary / 151.67) * RATES.overtimeRate
  const totalGross = grossSalary + overtimePay

  const mealVouchers = input.mealVouchers
  const transportAllowance = input.transportAllowance

  const taxableGross = totalGross + transportAllowance

  // Employee contributions
  const socialSecurityEmployee = grossSalary * RATES.socialSecurity.employee
  const healthEmployee = grossSalary * RATES.health.employee
  const retirementEmployee = grossSalary * RATES.retirement.employee
  const unemploymentEmployee = grossSalary * RATES.unemployment.employee
  const csgCrds = (totalGross * 0.9825) * RATES.csgCrds

  const totalEmployeeContributions =
    socialSecurityEmployee + healthEmployee + retirementEmployee + unemploymentEmployee + csgCrds

  // Employer contributions
  const socialSecurityEmployer = grossSalary * RATES.socialSecurity.employer
  const healthEmployer = grossSalary * RATES.health.employer
  const retirementEmployer = grossSalary * RATES.retirement.employer
  const unemploymentEmployer = grossSalary * RATES.unemployment.employer

  const totalEmployerContributions =
    socialSecurityEmployer + healthEmployer + retirementEmployer + unemploymentEmployer

  // Income tax (prélèvement à la source)
  const incomeTax = taxableGross * (input.taxRate / 100)

  // Net pay (gross - employee contributions - income tax)
  const netPay = totalGross - totalEmployeeContributions - incomeTax
  const netPayable = netPay + mealVouchers + transportAllowance

  const totalCostEmployer = totalGross + totalEmployerContributions + mealVouchers + transportAllowance

  return {
    grossSalary,
    overtimePay,
    totalGross,
    mealVouchers,
    transportAllowance,
    socialSecurityEmployee,
    healthEmployee,
    retirementEmployee,
    unemploymentEmployee,
    csgCrds,
    totalEmployeeContributions,
    socialSecurityEmployer,
    healthEmployer,
    retirementEmployer,
    unemploymentEmployer,
    totalEmployerContributions,
    incomeTax,
    netPay,
    netPayable,
    totalCostEmployer,
  }
}

export function formatPayrollAmount(n: number): string {
  return n.toFixed(2)
}
