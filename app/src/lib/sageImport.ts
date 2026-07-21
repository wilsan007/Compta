// Sage 100 import parser.
// Sage 100 can export accounting data as a FEC file (NF Z32-03) or as a
// tab/pipe-separated journal export. This module parses those formats and
// maps them to our chart_accounts and journal_entries structures.

export interface SageParseResult {
  accounts: SageAccount[]
  entries: SageEntry[]
  errors: string[]
  detectedDelimiter: string
  detectedFormat: 'fec' | 'unknown'
}

export interface SageAccount {
  code: string
  name: string
  type: 'asset' | 'liability' | 'equity' | 'income' | 'expense'
}

export interface SageEntryLine {
  account_code: string
  account_name: string
  account_tiers: string
  description: string
  debit: number
  credit: number
  lettrage_code: string
}

export interface SageEntry {
  journal_code: string
  journal_lib: string
  number: string
  date: string
  piece_number: string
  description: string
  lines: SageEntryLine[]
}

const FEC_HEADER_KEYS = ['JournalCode', 'EcritureNum', 'CompteNum', 'Debit', 'Credit']

function detectDelimiter(headerLine: string): string {
  const candidates = ['\t', '|', ';', ',']
  let best = '\t'
  let bestCount = 0
  for (const d of candidates) {
    const count = headerLine.split(d).length
    if (count > bestCount) {
      bestCount = count
      best = d
    }
  }
  return best
}

// Map French account class (first digit) to our type enum
function accountTypeFromCode(code: string): SageAccount['type'] {
  const first = code.trim().charAt(0)
  switch (first) {
    case '1': return 'equity'
    case '2': return 'asset'
    case '3': return 'asset'
    case '4': return 'liability'
    case '5': return 'asset'
    case '6': return 'expense'
    case '7': return 'income'
    default: return 'asset'
  }
}

function parseSageDate(raw: string): string {
  const s = (raw || '').trim()
  if (!s) return new Date().toISOString().split('T')[0]
  // FEC format: YYYYMMDD
  if (/^\d{8}$/.test(s)) {
    return `${s.substring(0, 4)}-${s.substring(4, 6)}-${s.substring(6, 8)}`
  }
  // DD/MM/YYYY
  const m = s.match(/^(\d{2})\/(\d{2})\/(\d{4})$/)
  if (m) return `${m[3]}-${m[2]}-${m[1]}`
  // Already ISO
  if (/^\d{4}-\d{2}-\d{2}/.test(s)) return s.substring(0, 10)
  return new Date().toISOString().split('T')[0]
}

function parseAmount(raw: string): number {
  if (!raw) return 0
  const cleaned = String(raw).trim().replace(/\s/g, '').replace(',', '.')
  const n = Number(cleaned)
  return Number.isNaN(n) ? 0 : n
}

export function parseSageFile(content: string): SageParseResult {
  const errors: string[] = []
  const lines = content.split(/\r?\n/).filter((l) => l.trim().length > 0)

  if (lines.length < 2) {
    return {
      accounts: [], entries: [], errors: ['Fichier vide ou sans données'],
      detectedDelimiter: '\t', detectedFormat: 'unknown',
    }
  }

  const delimiter = detectDelimiter(lines[0])
  const header = lines[0].split(delimiter).map((h) => h.trim())

  // Map header column indexes
  const idx = (key: string) => header.findIndex((h) => h.toLowerCase() === key.toLowerCase())
  const isFec = FEC_HEADER_KEYS.every((k) => idx(k) >= 0)

  if (!isFec) {
    errors.push("Format non reconnu. En-tête FEC attendu (JournalCode, EcritureNum, CompteNum, Debit, Credit).")
    return { accounts: [], entries: [], errors, detectedDelimiter: delimiter, detectedFormat: 'unknown' }
  }

  const cJournalCode = idx('JournalCode')
  const cJournalLib = idx('JournalLib')
  const cEcritureNum = idx('EcritureNum')
  const cEcritureDate = idx('EcritureDate')
  const cCompteNum = idx('CompteNum')
  const cCompteLib = idx('CompteLib')
  const cCompAuxNum = idx('CompAuxNum')
  const cPieceRef = idx('PieceRef')
  const cEcritureLib = idx('EcritureLib')
  const cDebit = idx('Debit')
  const cCredit = idx('Credit')
  const cEcritureLet = idx('EcritureLet')

  const accountsMap = new Map<string, SageAccount>()
  const entriesMap = new Map<string, SageEntry>()

  for (let i = 1; i < lines.length; i++) {
    const cols = lines[i].split(delimiter)
    const accountCode = (cols[cCompteNum] || '').trim()
    if (!accountCode) {
      errors.push(`Ligne ${i + 1}: numéro de compte manquant`)
      continue
    }
    const accountName = (cols[cCompteLib] || '').trim()

    if (!accountsMap.has(accountCode)) {
      accountsMap.set(accountCode, {
        code: accountCode,
        name: accountName || accountCode,
        type: accountTypeFromCode(accountCode),
      })
    }

    const journalCode = (cols[cJournalCode] || '').trim()
    const ecritureNum = (cols[cEcritureNum] || '').trim()
    const entryKey = `${journalCode}#${ecritureNum}`

    if (!entriesMap.has(entryKey)) {
      entriesMap.set(entryKey, {
        journal_code: journalCode,
        journal_lib: (cols[cJournalLib] || '').trim() || journalCode,
        number: ecritureNum,
        date: parseSageDate(cols[cEcritureDate] || ''),
        piece_number: (cPieceRef >= 0 ? cols[cPieceRef] : '')?.trim() || ecritureNum,
        description: (cols[cEcritureLib] || '').trim(),
        lines: [],
      })
    }

    entriesMap.get(entryKey)!.lines.push({
      account_code: accountCode,
      account_name: accountName,
      account_tiers: (cCompAuxNum >= 0 ? cols[cCompAuxNum] : '')?.trim() || '',
      description: (cols[cEcritureLib] || '').trim(),
      debit: parseAmount(cols[cDebit]),
      credit: parseAmount(cols[cCredit]),
      lettrage_code: (cEcritureLet >= 0 ? cols[cEcritureLet] : '')?.trim() || '',
    })
  }

  return {
    accounts: Array.from(accountsMap.values()).sort((a, b) => a.code.localeCompare(b.code)),
    entries: Array.from(entriesMap.values()),
    errors,
    detectedDelimiter: delimiter === '\t' ? 'TAB' : delimiter,
    detectedFormat: 'fec',
  }
}
