// Sage 100 .mae binary file parser (reverse-engineering proof of concept)
//
// The .mae file is a ProvideX (PxPlus) KEYED file containing multiple tables:
// F_COMPTA (chart of accounts), F_ECRITURE (journal entries), F_JOURNAL (journals),
// F_TIERS (third parties), etc.
//
// Binary structure overview (from reverse-engineering + Strucfic.pdf docs):
// - File header: signature bytes + magic "MA30CPTA"
// - ProvideX KEYED format: blocks/pages with key trees
// - Field separator: 0x8A (hex 138)
// - Record separator: 0x0D or 0x00 padding
// - Numeric fields: stored as text strings (ProvideX uses integer math with 2 decimals)
// - String fields: fixed-length, null-padded
//
// This parser scans the binary for recognizable patterns to extract:
// 1. Account codes (numeric strings 1-8 digits starting with class 1-7)
// 2. Account names (UTF-8/ASCII text following account codes)
// 3. Journal entries (date + account + debit + credit patterns)
//
// DISCLAIMER: This is a best-effort reverse-engineering parser for testing.
// A production parser would need the full ProvideX KEYED file format spec.

export interface MaeParseResult {
  accounts: MaeAccount[]
  entries: MaeEntry[]
  journals: MaeJournal[]
  errors: string[]
  detectedVersion: string
  tableCount: number
  rawRecords: number
  fileType: 'binary' | 'ini' | 'unknown'
  connectionInfo: MaeConnectionInfo | null
}

export interface MaeConnectionInfo {
  server: string
  database: string
  creator: string
  type: string
}

export interface MaeAccount {
  code: string
  name: string
  type: 'asset' | 'liability' | 'equity' | 'income' | 'expense'
}

export interface MaeJournal {
  code: string
  name: string
  type: string
}

export interface MaeEntry {
  journal_code: string
  number: string
  date: string
  piece_number: string
  description: string
  account_code: string
  debit: number
  credit: number
}

// ProvideX field separator
const FIELD_SEP = 0x8a
// ProvideX record terminator / padding
const RECORD_PAD = 0x00

// Known table markers in .mae files (from Strucfic.pdf)
const TABLE_MARKERS = [
  'F_COMPTA', 'F_ECRITURE', 'F_JOURNAL', 'F_TIERS',
  'F_SECTION', 'F_EXERCICE', 'F_DEVISE', 'F_REGLEMENT',
  'F_MODELE', 'F_ANALYTIQUE', 'F_ENCAPS', 'F_RUBRIQUE',
]

// Magic signature for Sage 100 .mae files
const MAE_MAGIC = 'MA30CPTA'

function accountTypeFromCode(code: string): MaeAccount['type'] {
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

// Extract readable ASCII/UTF-8 strings from a binary buffer
function extractStrings(buf: Uint8Array, minLen = 3): string[] {
  const strings: string[] = []
  let current = ''
  for (let i = 0; i < buf.length; i++) {
    const b = buf[i]
    // Printable ASCII range or common French accented chars (Latin-1)
    if ((b >= 0x20 && b <= 0x7e) || (b >= 0xc0 && b <= 0xff)) {
      current += String.fromCharCode(b)
    } else {
      if (current.length >= minLen) {
        strings.push(current)
      }
      current = ''
    }
  }
  if (current.length >= minLen) strings.push(current)
  return strings
}

// Parse a ProvideX numeric value (stored as text, may use comma as decimal sep)
function parsePvxNumber(raw: string): number {
  if (!raw) return 0
  const cleaned = raw.trim().replace(/\s/g, '').replace(',', '.')
  const n = Number(cleaned)
  return Number.isNaN(n) ? 0 : n
}

// Parse a ProvideX date (various formats: YYYYMMDD, DD/MM/YYYY, or Julian)
function parsePvxDate(raw: string): string {
  const s = (raw || '').trim()
  if (!s) return new Date().toISOString().split('T')[0]
  // YYYYMMDD
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

// Split a record buffer by field separator (0x8A)
function splitFields(record: Uint8Array): string[] {
  const fields: string[] = []
  let start = 0
  for (let i = 0; i < record.length; i++) {
    if (record[i] === FIELD_SEP) {
      const slice = record.slice(start, i)
      fields.push(decodeLatin1(slice))
      start = i + 1
    }
  }
  // Last field
  const lastSlice = record.slice(start)
  fields.push(decodeLatin1(lastSlice))
  return fields
}

// Decode bytes as Latin-1 (Sage 100 uses Windows-1252/Latin-1 for French)
function decodeLatin1(buf: Uint8Array): string {
  let s = ''
  for (let i = 0; i < buf.length; i++) {
    const b = buf[i]
    if (b === 0) break // null terminator
    // Windows-1252 specific chars
    if (b >= 0x80 && b <= 0x9f) {
      const win1252: Record<number, string> = {
        0x80: '€', 0x82: '‚', 0x83: 'ƒ', 0x84: '„',
        0x85: '…', 0x86: '†', 0x87: '‡', 0x88: 'ˆ',
        0x89: '‰', 0x8a: 'Š', 0x8b: '‹', 0x8c: 'Œ',
        0x8e: 'Ž', 0x91: '‘', 0x92: '’', 0x93: '“',
        0x94: '”', 0x95: '•', 0x96: '–', 0x97: '—',
        0x98: '˜', 0x99: '™', 0x9a: 'š', 0x9b: '›',
        0x9c: 'œ', 0x9e: 'ž', 0x9f: 'Ÿ',
      }
      s += win1252[b] || String.fromCharCode(b)
    } else {
      s += String.fromCharCode(b)
    }
  }
  return s.trim()
}

// Check if a string looks like a French accounting account code
function isAccountCode(s: string): boolean {
  return /^\d{2,8}$/.test(s.trim())
}

// Check if a string looks like a journal code (usually 1-5 alphanumeric)
function isJournalCode(s: string): boolean {
  return /^[A-Z0-9]{1,5}$/.test(s.trim()) && s.trim().length >= 1
}

// Check if a string looks like a date
function isDate(s: string): boolean {
  return /^\d{8}$/.test(s.trim()) || /^\d{2}\/\d{2}\/\d{4}$/.test(s.trim())
}

// Check if a string looks like an amount
function isAmount(s: string): boolean {
  const trimmed = s.trim()
  if (!trimmed) return false
  return /^-?\d+([.,]\d+)?$/.test(trimmed)
}

export function parseMaeFile(data: ArrayBuffer): MaeParseResult {
  const errors: string[] = []
  const buf = new Uint8Array(data)

  // --- Step 0: Check if this is an INI connection file (not binary data) ---
  const fullText = decodeLatin1(buf)
  if (fullText.startsWith('[CBASE]') || fullText.includes('[CBASE]')) {
    // Parse INI-style .mae connection file
    const lines = fullText.split(/\r?\n/)
    const iniData: Record<string, string> = {}
    for (const line of lines) {
      const m = line.match(/^([^=]+)=(.*)$/)
      if (m) {
        iniData[m[1].trim()] = m[2].trim()
      }
    }

    const connectionInfo: MaeConnectionInfo = {
      server: iniData['ServeurSQL'] || '',
      database: iniData['BaseSQL'] || iniData['Base'] || '',
      creator: iniData['Createur'] || '',
      type: iniData['Type'] || '',
    }

    const version = connectionInfo.creator
      ? `Sage ${connectionInfo.creator.replace(/^MA/, '')}`
      : 'Sage 100'

    errors.push(
      `Ce fichier .mae est un fichier de connexion INI, pas un dossier comptable binaire. ` +
      `Serveur SQL: ${connectionInfo.server}. ` +
      `Les données comptables sont stockées dans la base SQL Server, pas dans ce fichier. ` +
      `Pour importer les données, exportez un FEC depuis Sage 100 ou utilisez le pilote ODBC Sage.`
    )

    return {
      accounts: [],
      entries: [],
      journals: [],
      errors,
      detectedVersion: version,
      tableCount: 0,
      rawRecords: 0,
      fileType: 'ini',
      connectionInfo,
    }
  }

  // --- Step 1: Verify magic signature ---
  const headerStr = decodeLatin1(buf.slice(0, 64))
  const magicIdx = headerStr.indexOf(MAE_MAGIC)

  if (magicIdx < 0) {
    // Try to find magic anywhere in first 4KB
    const searchStr = decodeLatin1(buf.slice(0, 4096))
    const altIdx = searchStr.indexOf(MAE_MAGIC)
    if (altIdx < 0) {
      errors.push("Signature MA30CPTA non trouvée — ce fichier n'est pas un dossier Sage 100 .mae valide")
      return {
        accounts: [], entries: [], journals: [], errors,
        detectedVersion: 'unknown', tableCount: 0, rawRecords: 0,
        fileType: 'unknown', connectionInfo: null,
      }
    }
  }

  // Extract version from header area
  const versionMatch = headerStr.match(/MA(\d+)CPTA/i)
  const detectedVersion = versionMatch ? `Sage ${versionMatch[1]}` : 'Sage 100'

  // --- Step 2: Find table markers ---
  const fullStr = decodeLatin1(buf)
  const foundTables: string[] = []
  for (const marker of TABLE_MARKERS) {
    if (fullStr.includes(marker)) {
      foundTables.push(marker)
    }
  }

  // --- Step 3: Scan for records using field separator (0x8A) ---
  // ProvideX records are separated by 0x8A between fields and
  // records are delimited by block boundaries or null padding.
  // We scan for sequences of fields separated by 0x8A that contain
  // recognizable accounting data patterns.

  const accountsMap = new Map<string, MaeAccount>()
  const journalsMap = new Map<string, MaeJournal>()
  const entries: MaeEntry[] = []
  let rawRecords = 0

  // Strategy: Find all field-separated record blocks
  // A record block is a sequence of fields (separated by 0x8A) between
  // null-padding or block boundaries
  let recordStart = 0
  const records: string[][] = []

  for (let i = 0; i < buf.length; i++) {
    // Detect record boundaries: double null, or null after field sep
    if (buf[i] === RECORD_PAD && buf[i - 1] === RECORD_PAD) {
      if (i - recordStart > 5) {
        const recordBuf = buf.slice(recordStart, i)
        // Check if this block contains field separators
        let hasFieldSep = false
        for (let j = 0; j < recordBuf.length; j++) {
          if (recordBuf[j] === FIELD_SEP) {
            hasFieldSep = true
            break
          }
        }
        if (hasFieldSep) {
          const fields = splitFields(recordBuf).filter((f) => f.length > 0)
          if (fields.length >= 2) {
            records.push(fields)
            rawRecords++
          }
        }
      }
      recordStart = i + 1
    }
  }

  // --- Step 4: Classify records and extract data ---
  // Heuristic: Look for patterns that match known table structures
  //
  // F_COMPTA: [code] [name] [type] ...
  // F_JOURNAL: [code] [name] [type] ...
  // F_ECRITURE: [journal] [number] [date] [account] [debit] [credit] ...

  for (const fields of records) {
    // Try to identify account records (F_COMPTA)
    // Pattern: first field is numeric account code, second is a text name
    if (fields.length >= 2) {
      const code = fields[0].trim()
      const name = fields[1].trim()

      if (isAccountCode(code) && name.length >= 2 && !isAmount(name) && !isDate(name)) {
        // Avoid duplicates and filter likely false positives
        if (!accountsMap.has(code) && code.length >= 2) {
          // Check if this looks like an account name (contains letters)
          if (/[a-zA-ZÀ-ÿ]/.test(name)) {
            accountsMap.set(code, {
              code,
              name: name.substring(0, 100),
              type: accountTypeFromCode(code),
            })
          }
        }
      }

      // Try to identify journal records (F_JOURNAL)
      // Journals typically have short codes (1-3 chars) and descriptive names
      if (isJournalCode(code) && code.length <= 5 && name.length >= 3) {
        if (/[a-zA-ZÀ-ÿ]/.test(name) && !isAmount(name) && !isDate(name)) {
          if (!journalsMap.has(code)) {
            // Only add if it looks like a journal name (contains "journal", "achat", "vente", "banque", etc.)
            // or if the code is very short (1-3 chars) and name is descriptive
            const journalKeywords = /journal|achat|vente|banque|caisse|od|an|divers|trésorerie|op/i
            if (journalKeywords.test(name) || (code.length <= 3 && name.length >= 5)) {
              journalsMap.set(code, {
                code,
                name: name.substring(0, 100),
                type: 'general',
              })
            }
          }
        }
      }
    }

    // Try to identify entry records (F_ECRITURE)
    // Pattern: [journal_code] [entry_number] [date] [account_code] [description] [debit] [credit]
    if (fields.length >= 5) {
      const f0 = fields[0].trim()
      const f1 = fields[1].trim()

      // Look for date field in positions 2-4
      let dateField = ''
      let dateIdx = -1
      for (let k = 2; k < Math.min(fields.length, 6); k++) {
        if (isDate(fields[k].trim())) {
          dateField = fields[k].trim()
          dateIdx = k
          break
        }
      }

      // Look for account code near the date
      let accountCode = ''
      if (dateIdx >= 0 && dateIdx + 1 < fields.length) {
        const candidate = fields[dateIdx + 1].trim()
        if (isAccountCode(candidate)) {
          accountCode = candidate
        }
      }

      // Look for debit/credit amounts (two consecutive numeric fields)
      let debit = 0
      let credit = 0
      let debitIdx = -1
      for (let k = dateIdx + 1; k < fields.length - 1; k++) {
        if (k < 0) continue
        const a = fields[k].trim()
        const b = fields[k + 1].trim()
        if (isAmount(a) && isAmount(b)) {
          debit = parsePvxNumber(a)
          credit = parsePvxNumber(b)
          debitIdx = k
          break
        }
      }

      // If we found a date and account code and amounts, treat as an entry
      if (dateField && accountCode && debitIdx >= 0) {
        const journalCode = isJournalCode(f0) ? f0 : ''
        const entryNumber = f1 !== dateField ? f1 : ''
        const description = dateIdx > 0 && dateIdx < fields.length
          ? fields.slice(Math.max(1, dateIdx - 1), dateIdx).join(' ')
          : ''

        entries.push({
          journal_code: journalCode,
          number: entryNumber,
          date: parsePvxDate(dateField),
          piece_number: entryNumber,
          description: description.substring(0, 200),
          account_code: accountCode,
          debit,
          credit,
        })
      }
    }
  }

  // --- Step 5: Fallback — if structured scan found nothing, try string extraction ---
  if (accountsMap.size === 0 && entries.length === 0) {
    errors.push("Analyse structurelle incomplète — tentative d'extraction par motifs")

    // Extract all strings and look for account code patterns
    const allStrings = extractStrings(buf, 2)
    for (let i = 0; i < allStrings.length - 1; i++) {
      const s = allStrings[i].trim()
      const next = allStrings[i + 1].trim()

      // Account code followed by a descriptive name
      if (isAccountCode(s) && next.length >= 3 && /[a-zA-ZÀ-ÿ]/.test(next)) {
        if (!accountsMap.has(s)) {
          accountsMap.set(s, {
            code: s,
            name: next.substring(0, 100),
            type: accountTypeFromCode(s),
          })
        }
      }
    }
  }

  // Sort results
  const accounts = Array.from(accountsMap.values()).sort((a, b) => a.code.localeCompare(b.code))
  const journals = Array.from(journalsMap.values()).sort((a, b) => a.code.localeCompare(b.code))

  if (accounts.length === 0 && entries.length === 0 && journals.length === 0) {
    errors.push('Aucune donnée comptable extractible trouvée dans ce fichier .mae')
  }

  return {
    accounts,
    entries,
    journals,
    errors,
    detectedVersion,
    tableCount: foundTables.length,
    rawRecords,
    fileType: 'binary',
    connectionInfo: null,
  }
}
