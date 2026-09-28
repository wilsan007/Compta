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

export type FECColumn = typeof FEC_COLUMNS[number]
export type FECRow = Record<FECColumn, string>

/** Libellés que l'export lit au plan comptable, aux journaux et aux tiers (A47 A-1) */
export interface FECReferences {
  accounts: Record<string, string>
  journals: Record<string, string>
  tiers: Record<string, string>
  functionalCurrency: string
}

/** Un FEC prêt à contrôler et à écrire : ses lignes et l'identité de la société */
export interface FECExport {
  rows: FECRow[]
  siren: string | null
  entryCount: number
}

// A47 A-1 : montants sans séparateur de milliers, séparateur décimal VIRGULE
export function formatFECAmount(value: unknown): string {
  const n = Math.round((Number(value) || 0) * 100) / 100
  return n.toFixed(2).replace('.', ',')
}

function fecDate(value: string | null | undefined): string {
  return value ? value.slice(0, 10).replace(/-/g, '') : ''
}

// Le séparateur de champ est « | » : il ne peut pas apparaître dans une valeur
function fecText(value: unknown): string {
  if (value === null || value === undefined) return ''
  return String(value).replace(/[|\r\n\t]+/g, ' ').trim()
}

/**
 * M1 (X2) : une ligne de FEC par ligne d'écriture validée, avec les libellés
 * que l'arrêté exige — CompteLib (plan comptable), JournalLib (journal),
 * CompAuxLib (tiers), DateLet (date du lettrage), ValidDate (date de
 * validation), Montantdevise/Idevise quand la pièce n'est pas dans la devise
 * de la société.
 */
export function buildFECRows(entries: any[], refs: FECReferences): FECRow[] {
  const rows: FECRow[] = []
  for (const je of entries) {
    const foreign = je.currency_code && je.currency_code !== refs.functionalCurrency
    const rate = Number(je.exchange_rate) || 1
    for (const line of je.journal_lines || []) {
      const account = line.account_general || line.account_code || ''
      const aux = line.account_tiers || ''
      const amount = (Number(line.debit) || 0) + (Number(line.credit) || 0)
      rows.push({
        JournalCode: fecText(je.journal_code),
        JournalLib: fecText(refs.journals[je.journal_code] ?? ''),
        // AUD-C11 : numéro définitif, continu par journal et par exercice
        EcritureNum: fecText(je.posting_number || je.number),
        EcritureDate: fecDate(je.date),
        CompteNum: fecText(account),
        CompteLib: fecText(refs.accounts[account] || line.account_name || ''),
        CompAuxNum: fecText(aux),
        CompAuxLib: fecText(aux ? refs.tiers[aux] ?? '' : ''),
        PieceRef: fecText(line.piece_number || je.piece_number || je.number),
        PieceDate: fecDate(line.line_date || je.date),
        EcritureLib: fecText(line.description || je.description),
        Debit: formatFECAmount(line.debit),
        Credit: formatFECAmount(line.credit),
        EcritureLet: fecText(line.lettrage_code || ''),
        DateLet: line.lettrage_code ? fecDate(line.lettrage_date) : '',
        ValidDate: fecDate(je.validated_at),
        Montantdevise: foreign ? formatFECAmount(amount * rate) : '',
        Idevise: foreign ? fecText(je.currency_code) : '',
      })
    }
  }
  return rows
}

export function generateFECText(rows: FECRow[]): string {
  return [FEC_COLUMNS.join('|'), ...rows.map((r) => FEC_COLUMNS.map((c) => r[c]).join('|'))].join('\n')
}

// SIREN = 9 chiffres ; le SIRET (14) le contient en tête
export function sirenFrom(value: string | null | undefined): string | null {
  const digits = (value || '').replace(/\s/g, '')
  return /^\d{9}(\d{5})?$/.test(digits) ? digits.slice(0, 9) : null
}

const AMOUNT = /^\d+,\d{2}$/
const DATE = /^\d{8}$/

export function validateFECData(fec: FECExport): FECValidationResult {
  const errors: FECValidationError[] = []
  const warnings: FECValidationWarning[] = []
  let totalDebit = 0
  let totalCredit = 0
  const journalsUsed = new Set<string>()
  let minDate: string | null = null
  let maxDate: string | null = null
  const err = (line: number, field: FECColumn | 'Balance' | 'SIREN', message: string, severity: 'critical' | 'major' = 'major') =>
    errors.push({ line, field, message, severity })

  if (!fec.siren) {
    err(0, 'SIREN', 'SIREN de la société absent : le fichier ne peut pas être nommé {SIREN}FEC{AAAAMMJJ}.txt (Paramètres → Société)', 'critical')
  }

  fec.rows.forEach((r, i) => {
    const n = i + 1
    const debit = Number(r.Debit.replace(',', '.')) || 0
    const credit = Number(r.Credit.replace(',', '.')) || 0
    totalDebit += debit
    totalCredit += credit
    if (r.JournalCode) journalsUsed.add(r.JournalCode)
    if (!r.JournalCode) err(n, 'JournalCode', 'Code journal manquant', 'critical')
    if (!r.JournalLib) err(n, 'JournalLib', `Libellé du journal ${r.JournalCode} manquant`)
    if (!r.EcritureNum) err(n, 'EcritureNum', "Numéro d'écriture manquant", 'critical')
    if (!DATE.test(r.EcritureDate)) err(n, 'EcritureDate', "Date d'écriture manquante ou mal formée", 'critical')
    else {
      if (!minDate || r.EcritureDate < minDate) minDate = r.EcritureDate
      if (!maxDate || r.EcritureDate > maxDate) maxDate = r.EcritureDate
    }
    if (!r.CompteNum) err(n, 'CompteNum', 'Numéro de compte manquant', 'critical')
    if (!r.CompteLib) err(n, 'CompteLib', `Libellé du compte ${r.CompteNum} manquant (plan comptable)`)
    if (r.CompAuxNum && !r.CompAuxLib) err(n, 'CompAuxLib', `Libellé du compte auxiliaire ${r.CompAuxNum} manquant`)
    if (!r.PieceRef) err(n, 'PieceRef', 'Référence de pièce manquante')
    if (!DATE.test(r.PieceDate)) err(n, 'PieceDate', 'Date de pièce manquante ou mal formée')
    if (!AMOUNT.test(r.Debit) || !AMOUNT.test(r.Credit)) err(n, 'Debit', 'Montant mal formé (virgule décimale, sans séparateur de milliers)', 'critical')
    if (r.EcritureLet && !DATE.test(r.DateLet)) err(n, 'DateLet', `Date du lettrage ${r.EcritureLet} manquante`)
    if (!DATE.test(r.ValidDate)) err(n, 'ValidDate', 'Date de validation manquante', 'critical')
    if (Boolean(r.Montantdevise) !== Boolean(r.Idevise)) err(n, 'Idevise', 'Montant en devise et code devise vont ensemble')
    if (!r.EcritureLib) warnings.push({ line: n, field: 'EcritureLib', message: 'Libellé manquant' })
    if (debit === 0 && credit === 0) warnings.push({ line: n, field: 'Debit/Credit', message: 'Débit et crédit tous deux à zéro' })
    if (debit > 0 && credit > 0) warnings.push({ line: n, field: 'Debit/Credit', message: 'Débit et crédit tous deux non nuls' })
  })

  const balanceOk = Math.abs(totalDebit - totalCredit) < 0.01
  if (!balanceOk) {
    err(0, 'Balance', `Déséquilibre: Débit ${totalDebit.toFixed(2)} ≠ Crédit ${totalCredit.toFixed(2)} (écart: ${(totalDebit - totalCredit).toFixed(2)})`, 'critical')
  }

  return {
    // M1 : l'export est BLOQUÉ par toute erreur, majeure comprise (un FEC sans
    // libellé de compte est rejeté par l'administration)
    isValid: errors.length === 0,
    errors,
    warnings,
    stats: {
      totalEntries: fec.entryCount,
      totalLines: fec.rows.length,
      totalDebit,
      totalCredit,
      balanceOk,
      journalsUsed: Array.from(journalsUsed),
      dateRange: minDate && maxDate ? { start: minDate, end: maxDate } : null,
    },
  }
}

/** A47 A-1 : `{SIREN}FEC{AAAAMMJJ}.txt` — refusé sans SIREN (plus de « 000000000 ») */
export function generateFECFileName(siren: string, closingDate: string): string {
  const s = sirenFrom(siren)
  const d = closingDate.replace(/-/g, '').slice(0, 8)
  if (!s) throw new Error('SIREN de la société absent ou invalide : export FEC impossible')
  if (!DATE.test(d)) throw new Error(`Date de clôture invalide : ${closingDate}`)
  return `${s}FEC${d}.txt`
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
