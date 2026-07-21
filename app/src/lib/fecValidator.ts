// FEC (Fichier des Écritures Comptables) validation and certification.
// The FEC is mandatory in France for tax audits (contrôle fiscal).
// Format: NF Z32-03 standard, pipe-separated text file.

export interface FECValidationResult {
  isValid: boolean
  errors: FECValidationError[]
  warnings: FECValidationWarning[]
  stats: {
    totalEntries: number
    totalLines: number
    totalDebit: number
    totalCredit: number
    balanceOk: boolean
    journalsUsed: string[]
    dateRange: { start: string; end: string } | null
  }
}

export interface FECValidationError {
  line: number
  field: string
  message: string
  severity: 'critical' | 'major'
}

export interface FECValidationWarning {
  line: number
  field: string
  message: string
}

// Required FEC columns (NF Z32-03)
export const FEC_COLUMNS = [
  'JournalCode', 'JournalLib', 'EcritureNum', 'EcritureDate', 'CompteNum',
  'CompteLib', 'CompAuxNum', 'CompAuxLib', 'PieceRef', 'PieceDate',
  'EcritureLib', 'Debit', 'Credit', 'EcritureLet', 'DateLet',
  'ValidDate', 'Montantdevise', 'Idevise',
] as const

export function validateFECData(entries: any[]): FECValidationResult {
  const errors: FECValidationError[] = []
  const warnings: FECValidationWarning[] = []
  let totalDebit = 0
  let totalCredit = 0
  let totalLines = 0
  const journalsUsed = new Set<string>()
  let minDate: string | null = null
  let maxDate: string | null = null
  let lineNum = 1

  for (const entry of entries) {
    const entryLines = entry.journal_lines || []
    for (const line of entryLines) {
      totalLines++
      const debit = Number(line.debit) || 0
      const credit = Number(line.credit) || 0
      totalDebit += debit
      totalCredit += credit

      // Journal code
      if (!entry.journal_code) {
        errors.push({
          line: lineNum,
          field: 'JournalCode',
          message: 'Code journal manquant',
          severity: 'critical',
        })
      }
      journalsUsed.add(entry.journal_code || '')

      // Account number
      const accountNum = line.account_general || line.account_code
      if (!accountNum) {
        errors.push({
          line: lineNum,
          field: 'CompteNum',
          message: 'Numéro de compte manquant',
          severity: 'critical',
        })
      }

      // Account name
      if (!line.account_name) {
        errors.push({
          line: lineNum,
          field: 'CompteLib',
          message: 'Libellé de compte manquant',
          severity: 'major',
        })
      }

      // Entry number
      if (!entry.number) {
        errors.push({
          line: lineNum,
          field: 'EcritureNum',
          message: "Numéro d'écriture manquant",
          severity: 'critical',
        })
      }

      // Date
      if (!entry.date) {
        errors.push({
          line: lineNum,
          field: 'EcritureDate',
          message: "Date d'écriture manquante",
          severity: 'critical',
        })
      } else {
        const dateStr = entry.date.replace(/-/g, '')
        if (!minDate || dateStr < minDate) minDate = dateStr
        if (!maxDate || dateStr > maxDate) maxDate = dateStr
      }

      // Debit or Credit must be non-zero (not both zero, not both non-zero)
      if (debit === 0 && credit === 0) {
        warnings.push({
          line: lineNum,
          field: 'Debit/Credit',
          message: 'Débit et crédit tous deux à zéro',
        })
      }
      if (debit > 0 && credit > 0) {
        warnings.push({
          line: lineNum,
          field: 'Debit/Credit',
          message: 'Débit et crédit tous deux non nul (une seule ligne devrait avoir une valeur)',
        })
      }

      // Description
      if (!line.description && !entry.description) {
        warnings.push({
          line: lineNum,
          field: 'EcritureLib',
          message: 'Libellé manquant',
        })
      }

      lineNum++
    }
  }

  const balanceOk = Math.abs(totalDebit - totalCredit) < 0.01

  if (!balanceOk) {
    errors.push({
      line: 0,
      field: 'Balance',
      message: `Déséquilibre: Débit ${totalDebit.toFixed(2)} ≠ Crédit ${totalCredit.toFixed(2)} (écart: ${(totalDebit - totalCredit).toFixed(2)})`,
      severity: 'critical',
    })
  }

  return {
    isValid: errors.filter((e) => e.severity === 'critical').length === 0,
    errors,
    warnings,
    stats: {
      totalEntries: entries.length,
      totalLines,
      totalDebit,
      totalCredit,
      balanceOk,
      journalsUsed: Array.from(journalsUsed).filter(Boolean),
      dateRange: minDate && maxDate ? { start: minDate, end: maxDate } : null,
    },
  }
}

export function generateFECFileName(siren: string, endYear: string): string {
  const sirenClean = siren.replace(/\s/g, '').substring(0, 9) || '000000000'
  return `FEC_${sirenClean}_${endYear}.txt`
}

export function downloadFEC(content: string, filename: string) {
  const blob = new Blob([content], { type: 'text/plain;charset=utf-8' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  a.click()
  URL.revokeObjectURL(url)
}
