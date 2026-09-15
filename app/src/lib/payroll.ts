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
  // PAY-01 : Taux PAS personnalisé DGFiP (si null, utiliser le taux neutre)
  withholdingTaxRate?: number | null
  // PAY-01 : source du taux PAS (dgfip, neutral, manual)
  withholdingRateSource?: 'dgfip' | 'neutral' | 'manual' | string | null
  // Éléments variables issus des triggers de workflow (migration 81)
  advanceDeduction?: number       // Déduction d'acompte sur salaire
  payRecall?: number              // Rappel de paie (positif = à payer, négatif = à récupérer)
  expenseReimbursement?: number   // Remboursement de notes de frais (non imposable)
  unpaidLeaveDeduction?: number   // Déduction pour congé sans solde
  otherDeductions?: number        // Déductions diverses (retards, saisies, etc.)
  // PAY-03 : Période d'emploi et prorata
  periodStart?: Date              // Début de période d'emploi (entrée/sortie)
  periodEnd?: Date                // Fin de période d'emploi
  daysWorked?: number             // Jours travaillés dans le mois
  daysInPeriod?: number           // Jours dans la période (mois)
  hoursWorked?: number            // Heures réellement travaillées
  hoursContract?: number          // Heures contractuelles (temps partiel)
  absenceHours?: number           // Heures d'absence
  absenceMethod?: 'hours_real' | 'working_days' | 'thirtieth'
  // PAY-04 : Cumuls annuels pour régularisation progressive
  cumulativeGrossYTD?: number      // Brut cumulé depuis janvier
  cumulativeCeilingBaseYTD?: number  // Assiette plafonnée cumulée
  cumulativeCeilingAvailableYTD?: number // Plafond cumulé disponible
  // PAY-06 : Paramètres réduction générale
  smicAnnual?: number             // SMIC annuel (pour coefficient Fillon)
  reductionGeneraleT?: number     // Paramètre T (somme des taux éligibles)
}

export interface PayrollResult {
  grossSalary: number
  overtimePay: number
  totalGross: number
  mealVouchers: number
  transportAllowance: number
  // Éléments variables de workflow (migration 81)
  advanceDeduction: number
  payRecall: number
  expenseReimbursement: number
  unpaidLeaveDeduction: number
  otherVariableDeductions: number
  totalVariableDeductions: number   // Somme de toutes les déductions variables
  totalReimbursements: number       // Somme des remboursements non imposables
  // Employee contributions (cotisations salariales)
  socialSecurityEmployee: number
  healthEmployee: number
  retirementEmployee: number
  unemploymentEmployee: number
  // PAY-05 : CSG scindée
  csgCrds: number
  csgDeductible: number           // CSG déductible (retirée du net imposable)
  csgNonDeductible: number        // CSG non déductible (réintégrée au net imposable)
  crds: number                    // CRDS (réintégrée au net imposable)
  // PAY-05 : Net imposable et net social
  netImposable: number            // Net imposable fiscal
  netSocial: number               // Montant net social (mention obligatoire)
  // PAY-03 : Prorata
  proration: number               // Facteur de proratisation (0-1)
  proratedGross: number           // Brut proratisé
  // PAY-04 : Cumuls
  cumulativeGrossYTD: number       // Brut cumulé année
  cumulativeCeilingBaseYTD: number
  // PAY-06 : Réduction générale
  reductionGenerale: number       // Réduction générale de cotisations patronales
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
  netPay: number                    // Net avant remboursements et déductions variables
  netPayable: number                // Net à payer = netPay + remboursements - déductions variables
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

// PAY-03 : Calcul du facteur de proratisation
function calculateProration(input: PayrollInput): number {
  const daysWorked = input.daysWorked
  const daysInPeriod = input.daysInPeriod

  if (daysWorked != null && daysInPeriod != null && daysInPeriod > 0) {
    return Math.min(1, daysWorked / daysInPeriod)
  }

  // Prorata sur les heures (temps partiel / entrée / sortie)
  if (input.hoursWorked != null && input.hoursContract != null && input.hoursContract > 0) {
    return Math.min(1, input.hoursWorked / input.hoursContract)
  }

  return 1 // Pas de prorata
}

// PAY-03 : Calcul de la retenue d'absence
function calculateAbsenceDeduction(input: PayrollInput, grossSalary: number): number {
  if (!input.absenceHours || input.absenceHours <= 0) return 0
  const method = input.absenceMethod || 'hours_real'

  switch (method) {
    case 'hours_real':
      // Brut × heures_absence / heures_mois
      const monthlyHours = input.hoursContract || 151.67
      return grossSalary * (input.absenceHours / monthlyHours)
    case 'working_days':
      // Brut × jours_absence / jours_ouvrés_mois
      const workingDays = input.daysInPeriod || 22
      const absentDays = input.absenceHours // réutilisé comme jours
      return grossSalary * (absentDays / workingDays)
    case 'thirtieth':
      // Brut × jours_calendaires_absence / 30
      return grossSalary * (input.absenceHours / 30)
    default:
      return 0
  }
}

// PAY-02 : Calcul de l'assiette plafonnée
function ceilingBase(
  gross: number,
  ceilingType: string | undefined,
  ceilingMultiplier: number | undefined,
  floorMultiplier: number | undefined,
  ceilingValue: number | undefined,
  pmss: number,
  proration: number
): number {
  if (!ceilingType || ceilingType === 'none') return gross

  const ceiling = ceilingType === 'fixed'
    ? (ceilingValue || 0)
    : pmss * (ceilingMultiplier ?? 1) * proration
  const floor = pmss * (floorMultiplier ?? 0) * proration

  return Math.max(0, Math.min(gross, ceiling) - floor)
}

// PAY-05 : Calcul du net imposable
function calculateNetImposable(
  totalGross: number,
  totalEmployeeContributions: number,
  csgNonDeductible: number,
  crds: number,
  employerMutuellePart: number = 0,
  advantagesInKind: number = 0,
  employeeMutuellePart: number = 0
): number {
  // net_imposable = brut − cotisations salariales déductibles + CSG non déductible + CRDS
  //                + part patronale prévoyance/mutuelle + avantages en nature
  //                − part salariale mutuelle obligatoire (dans la limite)
  const deductibleContributions = totalEmployeeContributions - csgNonDeductible - crds
  return totalGross - deductibleContributions + csgNonDeductible + crds
    + employerMutuellePart + advantagesInKind - employeeMutuellePart
}

// PAY-05 : Calcul du montant net social
function calculateNetSocial(
  totalGross: number,
  totalEmployeeContributions: number,
  _csgDeductible: number,
  _csgNonDeductible: number,
  _crds: number,
  employerMutuellePart: number = 0
): number {
  // Net social = brut − cotisations salariales (y compris CSG/CRDS) + part patronale prévoyance
  void _csgDeductible; void _csgNonDeductible; void _crds
  return totalGross - totalEmployeeContributions + employerMutuellePart
}

// PAY-06 : Calcul de la réduction générale (coefficient Fillon)
function calculateReductionGenerale(
  grossMonthly: number,
  smicMonthly: number,
  tParam: number,
  proration: number
): number {
  if (grossMonthly <= 0 || smicMonthly <= 0) return 0

  // Coefficient annuel : C = (T / 0,6) × (1,6 × SMIC / rémunération − 1)
  // ratio > 1 quand salaire < 1,6 SMIC → réduction s'applique
  // ratio <= 1 quand salaire >= 1,6 SMIC → pas de réduction
  const ratio = (1.6 * smicMonthly * proration) / grossMonthly
  if (ratio <= 1) return 0 // Au-dessus de 1,6 SMIC, pas de réduction

  const coefficient = Math.max(0, (tParam / 0.6) * (ratio - 1))
  const cappedCoefficient = Math.min(coefficient, tParam)

  return grossMonthly * cappedCoefficient
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
  // PAY-03 : Proratisation
  const proration = calculateProration(input)
  const absenceDeduction = calculateAbsenceDeduction(input, input.grossSalary)
  const proratedGross = input.grossSalary * proration - absenceDeduction

  const grossSalary = proratedGross
  const overtimeRate = FALLBACK_RATES.overtimeRate
  const overtimePay = input.overtimeHours * (input.grossSalary / 151.67) * overtimeRate

  // Éléments variables de workflow (migration 81)
  const advanceDeduction = Number(input.advanceDeduction || 0)
  const payRecall = Number(input.payRecall || 0)
  const expenseReimbursement = Number(input.expenseReimbursement || 0)
  const unpaidLeaveDeduction = Number(input.unpaidLeaveDeduction || 0)
  const otherVariableDeductions = Number(input.otherDeductions || 0)

  // Le rappel de paie augmente le brut (positif = à payer)
  const totalGross = grossSalary + overtimePay + payRecall

  const mealVouchers = input.mealVouchers
  const transportAllowance = input.transportAllowance
  // PAY-01 : l'indemnité de transport est exonérée dans la limite légale
  // seule la part au-delà du plafond d'exonération entre dans l'assiette imposable
  const TRANSPORT_EXEMPT_MONTHLY_CAP = 75 // paramètre légal français 2026 (à paramétriser par législation)
  const transportExempt = Math.min(transportAllowance, TRANSPORT_EXEMPT_MONTHLY_CAP)
  const transportTaxable = Math.max(0, transportAllowance - transportExempt)
  const taxableGross = totalGross + transportTaxable

  // Les remboursements de frais ne sont pas imposables
  const totalReimbursements = expenseReimbursement

  // Les déductions variables réduisent le net à payer
  const totalVariableDeductions = advanceDeduction + unpaidLeaveDeduction + otherVariableDeductions

  const lineDetails: { label: string; amount: number; category: string }[] = []

  // Ajouter les éléments variables au détail pour audit
  if (advanceDeduction !== 0)
    lineDetails.push({ label: 'Acompte sur salaire', amount: -advanceDeduction, category: 'advance_deduction' })
  if (payRecall !== 0)
    lineDetails.push({ label: 'Rappel de paie', amount: payRecall, category: 'pay_recall' })
  if (expenseReimbursement !== 0)
    lineDetails.push({ label: 'Remboursement de frais', amount: expenseReimbursement, category: 'expense_reimbursement' })
  if (unpaidLeaveDeduction !== 0)
    lineDetails.push({ label: 'Déduction congé sans solde', amount: -unpaidLeaveDeduction, category: 'unpaid_leave_deduction' })
  if (otherVariableDeductions !== 0)
    lineDetails.push({ label: 'Autres déductions', amount: -otherVariableDeductions, category: 'other_deductions' })

  // If grid lines provided, use data-driven calculation
  if (gridLines && gridLines.length > 0) {
    let socialSecurityEmployee = 0, healthEmployee = 0, retirementEmployee = 0
    let unemploymentEmployee = 0, csgCrds = 0, incomeTax = 0
    let socialSecurityEmployer = 0, healthEmployer = 0, retirementEmployer = 0
    let unemploymentEmployer = 0
    let otherEmployee = 0, otherEmployer = 0
    // PAY-05 : CSG scindée
    let csgDeductible = 0, csgNonDeductible = 0, crds = 0
    // PAY-06 : Réduction générale
    let eligibleEmployerContributions = 0

    const pmss = 3925 // Paramètre légal — devrait venir de payroll_legal_parameters

    for (const line of gridLines) {
      // PAY-02 : assiette plafonnée
      const base = ceilingBase(
        getBaseAmount(line.base_type, grossSalary, totalGross, taxableGross, 0),
        (line as any).ceiling_type,
        (line as any).ceiling_multiplier,
        (line as any).floor_multiplier,
        (line as any).ceiling_value,
        pmss,
        proration
      )
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

      // PAY-05 : CSG/CRDS scindée sur 98,25 % du brut
      if (line.category === 'csg_crds') {
        const csgBase = totalGross * 0.9825
        if (line.line_type === 'percentage') {
          employeeAmount = csgBase * (Number(line.rate_employee || 0) / 100)
        }
        csgCrds += employeeAmount
        // Scission selon le type CSG
        const csgType = (line as any).csg_type
        if (csgType === 'deductible') csgDeductible += employeeAmount
        else if (csgType === 'non_deductible') csgNonDeductible += employeeAmount
        else if (csgType === 'crds') crds += employeeAmount
        else csgDeductible += employeeAmount // fallback
      } else if (line.category === 'social_security') {
        socialSecurityEmployee += employeeAmount
        socialSecurityEmployer += employerAmount
        if ((line as any).eligible_reduction_generale) eligibleEmployerContributions += employerAmount
      } else if (line.category === 'health') {
        healthEmployee += employeeAmount
        healthEmployer += employerAmount
        if ((line as any).eligible_reduction_generale) eligibleEmployerContributions += employerAmount
      } else if (line.category === 'retirement') {
        retirementEmployee += employeeAmount
        retirementEmployer += employerAmount
        if ((line as any).eligible_reduction_generale) eligibleEmployerContributions += employerAmount
      } else if (line.category === 'unemployment') {
        unemploymentEmployee += employeeAmount
        unemploymentEmployer += employerAmount
        if ((line as any).eligible_reduction_generale) eligibleEmployerContributions += employerAmount
      } else if (line.category === 'its' || line.category === 'income_tax') {
        if (line.line_type === 'percentage' && Number(line.rate_employee || 0) === 0) {
          // PAY-05 : PAS sur le net imposable, pas sur le brut
          incomeTax += 0 // sera calculé après net imposable
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

    // PAY-05 : Net imposable et net social
    const netImposable = calculateNetImposable(totalGross, totalEmployeeContributions, csgNonDeductible, crds)
    const netSocial = calculateNetSocial(totalGross, totalEmployeeContributions, csgDeductible, csgNonDeductible, crds)

    // PAY-05 : PAS sur le net imposable
    if (incomeTax === 0) {
      incomeTax = netImposable * (input.taxRate / 100)
    }

    // PAY-06 : Réduction générale
    const smicMonthly = input.grossSalary > 0 && input.grossSalary < 1801.80 * 1.6
      ? 1801.80 * proration
      : 1801.80 * proration
    const reductionGenerale = calculateReductionGenerale(
      grossSalary,
      smicMonthly,
      input.reductionGeneraleT || 0.3194,
      proration
    )

    const totalEmployerContributions =
      socialSecurityEmployer + healthEmployer + retirementEmployer +
      unemploymentEmployer + otherEmployer - reductionGenerale

    const netPay = totalGross - totalEmployeeContributions - incomeTax
    const netPayable = netPay + mealVouchers + transportAllowance + totalReimbursements - totalVariableDeductions
    const totalCostEmployer = totalGross + totalEmployerContributions + mealVouchers + transportAllowance + totalReimbursements

    // PAY-04 : Cumuls
    const cumulativeGrossYTD = (input.cumulativeGrossYTD || 0) + totalGross
    const cumulativeCeilingBaseYTD = (input.cumulativeCeilingBaseYTD || 0) + Math.min(grossSalary, pmss * proration)

    return {
      grossSalary, overtimePay, totalGross, mealVouchers, transportAllowance,
      advanceDeduction, payRecall, expenseReimbursement, unpaidLeaveDeduction,
      otherVariableDeductions, totalVariableDeductions, totalReimbursements,
      socialSecurityEmployee, healthEmployee, retirementEmployee, unemploymentEmployee,
      csgCrds, csgDeductible, csgNonDeductible, crds,
      netImposable, netSocial,
      proration, proratedGross,
      cumulativeGrossYTD, cumulativeCeilingBaseYTD,
      reductionGenerale,
      totalEmployeeContributions,
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

  // PAY-05 : CSG scindée
  const csgBase = totalGross * 0.9825
  const csgDeductible = csgBase * 6.80 / 100
  const csgNonDeductible = csgBase * 2.40 / 100
  const crds = csgBase * 0.50 / 100
  const csgCrds = csgDeductible + csgNonDeductible + crds

  const totalEmployeeContributions =
    socialSecurityEmployee + healthEmployee + retirementEmployee + unemploymentEmployee + csgCrds

  const socialSecurityEmployer = grossSalary * FALLBACK_RATES.socialSecurity.employer / 100
  const healthEmployer = grossSalary * FALLBACK_RATES.health.employer / 100
  const retirementEmployer = grossSalary * FALLBACK_RATES.retirement.employer / 100
  const unemploymentEmployer = grossSalary * FALLBACK_RATES.unemployment.employer / 100

  // PAY-05 : Net imposable et net social
  const netImposable = calculateNetImposable(totalGross, totalEmployeeContributions, csgNonDeductible, crds)
  const netSocial = calculateNetSocial(totalGross, totalEmployeeContributions, csgDeductible, csgNonDeductible, crds)

  // PAY-05 : PAS sur le net imposable
  const incomeTax = netImposable * (input.taxRate / 100)

  // PAY-06 : Réduction générale
  const smicMonthly = 1801.80 * proration
  const reductionGenerale = calculateReductionGenerale(
    grossSalary, smicMonthly, input.reductionGeneraleT || 0.3194, proration
  )

  const totalEmployerContributions =
    socialSecurityEmployer + healthEmployer + retirementEmployer + unemploymentEmployer - reductionGenerale

  const netPay = totalGross - totalEmployeeContributions - incomeTax
  const netPayable = netPay + mealVouchers + transportAllowance + totalReimbursements - totalVariableDeductions
  const totalCostEmployer = totalGross + totalEmployerContributions + mealVouchers + transportAllowance + totalReimbursements

  // PAY-04 : Cumuls
  const cumulativeGrossYTD = (input.cumulativeGrossYTD || 0) + totalGross
  const cumulativeCeilingBaseYTD = (input.cumulativeCeilingBaseYTD || 0) + Math.min(grossSalary, 3925 * proration)

  return {
    grossSalary, overtimePay, totalGross, mealVouchers, transportAllowance,
    advanceDeduction, payRecall, expenseReimbursement, unpaidLeaveDeduction,
    otherVariableDeductions, totalVariableDeductions, totalReimbursements,
    socialSecurityEmployee, healthEmployee, retirementEmployee, unemploymentEmployee,
    csgCrds, csgDeductible, csgNonDeductible, crds,
    netImposable, netSocial,
    proration, proratedGross,
    cumulativeGrossYTD, cumulativeCeilingBaseYTD,
    reductionGenerale,
    totalEmployeeContributions,
    socialSecurityEmployer, healthEmployer, retirementEmployer, unemploymentEmployer,
    totalEmployerContributions,
    incomeTax, netPay, netPayable, totalCostEmployer, lineDetails,
  }
}

export function formatPayrollAmount(n: number): string {
  return n.toFixed(2)
}

