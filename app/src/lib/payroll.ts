// Data-driven payroll calculation engine.
// Computes gross, social contributions, income tax (ITS/PAS),
// and net pay for employees based on configurable tax grid lines.
// Falls back to hardcoded French 2024-2025 rates if no grid lines provided.

import type { PayrollTaxGridLine } from '@/types'

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
  // Breakdown details from grid lines
  lineDetails: { label: string; amount: number; category: string }[]
}

// 2024-2025 French payroll rates (fallback when no grid lines provided)
const FALLBACK_RATES = {
  socialSecurity: { employee: 6.98, employer: 29.74 },
  health: { employee: 0.40, employer: 7.28 },
  retirement: { employee: 11.40, employer: 10.93 },
  unemployment: { employee: 0.24, employer: 4.28 },
  csgCrds: 9.20,
  overtimeRate: 1.25,
}

function getBaseAmount(baseType: string, gross: number, totalGross: number, taxableGross: number, net: number): number {
  switch (baseType) {
    case 'gross': return gross
    case 'total_gross': return totalGross
    case 'taxable_gross': return taxableGross
    case 'net': return net
    default: return gross
  }
}

function calculateBracket(base: number, line: PayrollTaxGridLine): number {
  const min = Number(line.min_amount || 0)
  const max = line.max_amount != null ? Number(line.max_amount) : Infinity
  if (base <= min) return 0
  const taxableInBracket = Math.min(base, max) - min
  const rate = Number(line.rate_employee || 0) / 100
  return taxableInBracket * rate
}

function calculatePercentage(base: number, line: PayrollTaxGridLine, isEmployer: boolean): number {
  const rate = isEmployer ? Number(line.rate_employer || 0) / 100 : Number(line.rate_employee || 0) / 100
  let amount = base * rate
  const cap = line.cap_amount != null ? Number(line.cap_amount) : null
  if (cap != null && amount > cap) amount = cap
  return amount
}

export function calculatePayroll(input: PayrollInput, gridLines?: PayrollTaxGridLine[]): PayrollResult {
  const grossSalary = input.grossSalary
  const overtimeRate = FALLBACK_RATES.overtimeRate
  const overtimePay = input.overtimeHours * (grossSalary / 151.67) * overtimeRate
  const totalGross = grossSalary + overtimePay

  const mealVouchers = input.mealVouchers
  const transportAllowance = input.transportAllowance
  const taxableGross = totalGross + transportAllowance

  const lineDetails: { label: string; amount: number; category: string }[] = []

  // If grid lines provided, use data-driven calculation
  if (gridLines && gridLines.length > 0) {
    let socialSecurityEmployee = 0, healthEmployee = 0, retirementEmployee = 0
    let unemploymentEmployee = 0, csgCrds = 0, incomeTax = 0
    let socialSecurityEmployer = 0, healthEmployer = 0, retirementEmployer = 0
    let unemploymentEmployer = 0
    let otherEmployee = 0, otherEmployer = 0

    for (const line of gridLines) {
      const base = getBaseAmount(line.base_type, grossSalary, totalGross, taxableGross, 0)
      let employeeAmount = 0
      let employerAmount = 0

      if (line.line_type === 'percentage') {
        employeeAmount = calculatePercentage(base, line, false)
        employerAmount = calculatePercentage(base, line, true)
      } else if (line.line_type === 'bracket') {
        employeeAmount = calculateBracket(base, line)
      } else if (line.line_type === 'fixed_amount') {
        employeeAmount = Number(line.fixed_amount || 0)
      } else if (line.line_type === 'flat') {
        employeeAmount = Number(line.rate_employee || 0)
        employerAmount = Number(line.rate_employer || 0)
      }

      // CSG/CRDS is calculated on 98.25% of total gross
      if (line.category === 'csg_crds') {
        const csgBase = totalGross * 0.9825
        if (line.line_type === 'percentage') {
          employeeAmount = csgBase * (Number(line.rate_employee || 0) / 100)
        }
        csgCrds += employeeAmount
      } else if (line.category === 'social_security') {
        socialSecurityEmployee += employeeAmount
        socialSecurityEmployer += employerAmount
      } else if (line.category === 'health') {
        healthEmployee += employeeAmount
        healthEmployer += employerAmount
      } else if (line.category === 'retirement') {
        retirementEmployee += employeeAmount
        retirementEmployer += employerAmount
      } else if (line.category === 'unemployment') {
        unemploymentEmployee += employeeAmount
        unemploymentEmployer += employerAmount
      } else if (line.category === 'its' || line.category === 'income_tax') {
        if (line.line_type === 'percentage' && Number(line.rate_employee || 0) === 0) {
          // Use the input taxRate if grid rate is 0 (placeholder for PAS)
          incomeTax += taxableGross * (input.taxRate / 100)
        } else {
          incomeTax += employeeAmount
        }
      } else {
        otherEmployee += employeeAmount
        otherEmployer += employerAmount
      }

      if (employeeAmount !== 0) {
        lineDetails.push({ label: line.label, amount: employeeAmount, category: line.category })
      }
    }

    const totalEmployeeContributions =
      socialSecurityEmployee + healthEmployee + retirementEmployee +
      unemploymentEmployee + csgCrds + otherEmployee

    const totalEmployerContributions =
      socialSecurityEmployer + healthEmployer + retirementEmployer +
      unemploymentEmployer + otherEmployer

    const netPay = totalGross - totalEmployeeContributions - incomeTax
    const netPayable = netPay + mealVouchers + transportAllowance
    const totalCostEmployer = totalGross + totalEmployerContributions + mealVouchers + transportAllowance

    return {
      grossSalary, overtimePay, totalGross, mealVouchers, transportAllowance,
      socialSecurityEmployee, healthEmployee, retirementEmployee, unemploymentEmployee,
      csgCrds, totalEmployeeContributions,
      socialSecurityEmployer, healthEmployer, retirementEmployer, unemploymentEmployer,
      totalEmployerContributions,
      incomeTax, netPay, netPayable, totalCostEmployer, lineDetails,
    }
  }

  // Fallback: hardcoded French rates
  const socialSecurityEmployee = grossSalary * FALLBACK_RATES.socialSecurity.employee / 100
  const healthEmployee = grossSalary * FALLBACK_RATES.health.employee / 100
  const retirementEmployee = grossSalary * FALLBACK_RATES.retirement.employee / 100
  const unemploymentEmployee = grossSalary * FALLBACK_RATES.unemployment.employee / 100
  const csgCrds = (totalGross * 0.9825) * FALLBACK_RATES.csgCrds / 100

  const totalEmployeeContributions =
    socialSecurityEmployee + healthEmployee + retirementEmployee + unemploymentEmployee + csgCrds

  const socialSecurityEmployer = grossSalary * FALLBACK_RATES.socialSecurity.employer / 100
  const healthEmployer = grossSalary * FALLBACK_RATES.health.employer / 100
  const retirementEmployer = grossSalary * FALLBACK_RATES.retirement.employer / 100
  const unemploymentEmployer = grossSalary * FALLBACK_RATES.unemployment.employer / 100

  const totalEmployerContributions =
    socialSecurityEmployer + healthEmployer + retirementEmployer + unemploymentEmployer

  const incomeTax = taxableGross * (input.taxRate / 100)

  const netPay = totalGross - totalEmployeeContributions - incomeTax
  const netPayable = netPay + mealVouchers + transportAllowance
  const totalCostEmployer = totalGross + totalEmployerContributions + mealVouchers + transportAllowance

  return {
    grossSalary, overtimePay, totalGross, mealVouchers, transportAllowance,
    socialSecurityEmployee, healthEmployee, retirementEmployee, unemploymentEmployee,
    csgCrds, totalEmployeeContributions,
    socialSecurityEmployer, healthEmployer, retirementEmployer, unemploymentEmployer,
    totalEmployerContributions,
    incomeTax, netPay, netPayable, totalCostEmployer, lineDetails,
  }
}

export function formatPayrollAmount(n: number): string {
  return n.toFixed(2)
}

