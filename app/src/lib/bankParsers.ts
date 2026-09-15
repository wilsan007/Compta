// BNQ-01 : Parsers de formats bancaires normés
// CAMT.053 (XML ISO 20022), MT940 (SWIFT), CFONB 120 (position fixe France)
// L'edge function LLM reste en repli explicite pour les PDF et formats propriétaires.

import type { ParsedBankTransaction, BankStatementParseResult } from './pdfBankParser'

// ============================================================
// Utilitaires XML
// ============================================================
function getText(parent: Element | Document | null, ns: string, tag: string): string {
  if (!parent) return ''
  const el = parent.getElementsByTagNameNS(ns, tag)[0]
    ?? parent.getElementsByTagName(tag)[0]
  return el?.textContent?.trim() ?? ''
}

function getAmount(parent: Element | null, ns: string, tag: string): number {
  const txt = getText(parent, ns, tag)
  return parseFloat(txt.replace(',', '.')) || 0
}

// ============================================================
// CAMT.053 — XML ISO 20022
// ============================================================
export function parseCamt053(xml: string): BankStatementParseResult {
  const warnings: string[] = []
  const transactions: ParsedBankTransaction[] = []
  let accountNumber: string | null = null
  let currency: string | null = null
  let openingBalance: number | null = null
  let closingBalance: number | null = null
  let periodStart: string | null = null
  let periodEnd: string | null = null

  const doc = new DOMParser().parseFromString(xml, 'application/xml')

  // Détecter le namespace CAMT.053
  const rootEl = doc.documentElement
  const ns = rootEl.namespaceURI || 'urn:iso:std:iso:20022:tech:xsd:camt.053.001.02'

  // Informations du compte
  const acct = doc.getElementsByTagNameNS(ns, 'Acct')[0] ?? doc.getElementsByTagName('Acct')[0]
  if (acct) {
    accountNumber = getText(acct, ns, 'Id') || getText(acct.getElementsByTagName('Id')[0], ns, 'IBAN') || getText(acct, ns, 'IBAN')
    currency = acct.getElementsByTagNameNS(ns, 'Ccy')[0]?.textContent?.trim()
      ?? acct.getElementsByTagName('Ccy')[0]?.textContent?.trim()
      ?? 'EUR'
  }

  // Soldes d'ouverture et de clôture
  const balances = Array.from(doc.getElementsByTagNameNS(ns, 'Bal')).length
    ? Array.from(doc.getElementsByTagNameNS(ns, 'Bal'))
    : Array.from(doc.getElementsByTagName('Bal'))
  for (const bal of balances) {
    const tp = getText(bal, ns, 'Tp') || getText(bal.getElementsByTagName('Tp')[0], ns, 'Cd') || getText(bal, ns, 'Cd')
    const amt = getAmount(bal, ns, 'Amt')
    const dt = getText(bal, ns, 'Dt')
    if (tp === 'OPBD' || tp === 'PRCD') {
      openingBalance = amt
      periodStart = dt
    } else if (tp === 'CLBD' || tp === 'CLAV') {
      closingBalance = amt
      periodEnd = dt
    }
  }

  // Transactions
  const entries = Array.from(doc.getElementsByTagNameNS(ns, 'Ntry')).length
    ? Array.from(doc.getElementsByTagNameNS(ns, 'Ntry'))
    : Array.from(doc.getElementsByTagName('Ntry'))

  for (const entry of entries) {
    const cdtDbt = getText(entry, ns, 'CdtDbtInd')
    const amt = getAmount(entry, ns, 'Amt')
    const type: 'debit' | 'credit' = cdtDbt === 'CRDT' ? 'credit' : 'debit'

    // Date de comptabilisation
    const bookgDt = entry.getElementsByTagNameNS(ns, 'BookgDt')[0] ?? entry.getElementsByTagName('BookgDt')[0]
    const date = getText(bookgDt, ns, 'Dt') || getText(entry, ns, 'ValDt') || new Date().toISOString().split('T')[0]

    // Libellé
    const label = getText(entry, ns, 'AddtlNtryInf')
      || getText(entry, ns, 'NtryDtls')
      || getText(entry.getElementsByTagName('NtryDtls')[0], ns, 'AddtlTxInf')

    // Référence structurée
    const ref = getText(entry, ns, 'Ref')
      || getText(entry, ns, 'EndToEndId')
      || getText(entry.getElementsByTagName('NtryDtls')[0], ns, 'EndToEndId')

    transactions.push({
      date,
      description: label,
      reference: ref,
      type,
      amount: type === 'debit' ? -Math.abs(amt) : Math.abs(amt),
    })
  }

  if (transactions.length === 0) {
    warnings.push('Aucune transaction trouvée dans le fichier CAMT.053')
  }

  return {
    transactions,
    rawText: xml,
    accountNumber,
    periodStart,
    periodEnd,
    openingBalance,
    closingBalance,
    currency: currency || 'EUR',
    warnings,
  }
}

// ============================================================
// MT940 — SWIFT texte
// ============================================================
export function parseMt940(content: string): BankStatementParseResult {
  const warnings: string[] = []
  const transactions: ParsedBankTransaction[] = []
  let accountNumber: string | null = null
  let openingBalance: number | null = null
  let closingBalance: number | null = null
  let currency: string | null = 'EUR'
  let periodStart: string | null = null
  let periodEnd: string | null = null

  const lines = content.split(/\r?\n/)

  // Numéro de compte (:25:)
  for (const line of lines) {
    if (line.startsWith(':25:')) {
      accountNumber = line.substring(4).trim()
      break
    }
  }

  // Parcourir les lignes pour les balises :60F: (solde ouverture), :61: (mouvement), :86: (libellé), :62F: (solde clôture)
  let currentTx: ParsedBankTransaction | null = null

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]

    // Solde d'ouverture :60F:CYYMMDDEUR1234,56
    if (line.startsWith(':60F:')) {
      const parsed = parseMt940Balance(line.substring(5))
      openingBalance = parsed.amount
      currency = parsed.currency
      periodStart = parsed.date
    }

    // Solde de clôture :62F:
    if (line.startsWith(':62F:')) {
      const parsed = parseMt940Balance(line.substring(5))
      closingBalance = parsed.amount
      periodEnd = parsed.date
    }

    // Mouvement :61:YYMMDDMMDDDR1234,56NNNN
    if (line.startsWith(':61:')) {
      // Pousser la transaction précédente
      if (currentTx) transactions.push(currentTx)

      const raw = line.substring(4)
      // Format: YYMMDD[MMDD]DCAmount[RC]...
      const dateStr = raw.substring(0, 6)
      const date = `20${dateStr.substring(0, 2)}-${dateStr.substring(2, 4)}-${dateStr.substring(4, 6)}`

      // Indicateur débit/crédit : D = débit, C = crédit, RC = crédit rectificatif, RD = débit rectificatif
      let idx = 6
      // Sauter la date de valeur optionnelle (6 chars)
      if (raw.length > 12 && /^\d{6}$/.test(raw.substring(6, 12))) idx = 12

      const dcIndicator = raw.substring(idx, idx + 1)
      idx++

      // Montant : jusqu'à la prochaine lettre ou fin de champ
      let amountStr = ''
      while (idx < raw.length && /[\d,]/.test(raw[idx])) {
        amountStr += raw[idx]
        idx++
      }
      const amount = parseFloat(amountStr.replace(',', '.')) || 0

      // Référence (reste de la ligne après N)
      const rest = raw.substring(idx)
      const refMatch = rest.match(/N(\w{3})(.*)/)
      const reference = refMatch ? refMatch[2].trim() : ''

      const type: 'debit' | 'credit' = dcIndicator === 'C' ? 'credit' : 'debit'

      currentTx = {
        date,
        description: '',
        reference,
        type,
        amount: type === 'debit' ? -Math.abs(amount) : Math.abs(amount),
      }
    }

    // Libellé complémentaire :86:
    if (line.startsWith(':86:')) {
      if (currentTx) {
        currentTx.description = line.substring(4).trim()
      }
    }
  }

  // Pousser la dernière transaction
  if (currentTx) transactions.push(currentTx)

  if (transactions.length === 0) {
    warnings.push('Aucune transaction trouvée dans le fichier MT940')
  }

  return {
    transactions,
    rawText: content,
    accountNumber,
    periodStart,
    periodEnd,
    openingBalance,
    closingBalance,
    currency,
    warnings,
  }
}

function parseMt940Balance(raw: string): { amount: number; currency: string; date: string } {
  // Format: DYYMMDDCURRENCYAMOUNT (D = débit/crédit)
  const dateStr = raw.substring(1, 7)
  const date = `20${dateStr.substring(0, 2)}-${dateStr.substring(2, 4)}-${dateStr.substring(4, 6)}`

  // Extraire la devise (3 lettres après la date)
  let currency = 'EUR'
  let amountStr = ''
  let idx = 7
  if (raw.length > 10) {
    currency = raw.substring(7, 10)
    idx = 10
  }
  amountStr = raw.substring(idx).replace(',', '.')
  const amount = parseFloat(amountStr) || 0

  return { amount, currency, date }
}

// ============================================================
// CFONB 120 — Format à position fixe (France)
// ============================================================
export function parseCfonb120(content: string): BankStatementParseResult {
  const warnings: string[] = []
  const transactions: ParsedBankTransaction[] = []
  let accountNumber: string | null = null
  let openingBalance: number | null = null
  let closingBalance: number | null = null
  let currency: string | null = 'EUR'
  let periodStart: string | null = null
  let periodEnd: string | null = null

  const lines = content.split(/\r?\n/)

  for (const line of lines) {
    if (line.length < 120) continue

    // Code enregistrement (position 1-2)
    const recordCode = line.substring(0, 2)

    switch (recordCode) {
      case '01': {
        // En-tête de relevé
        accountNumber = line.substring(21, 32).trim()
        currency = line.substring(16, 19).trim() || 'EUR'
        const startDate = line.substring(34, 42).trim()
        if (startDate.length === 8) {
          periodStart = `${startDate.substring(0, 4)}-${startDate.substring(4, 6)}-${startDate.substring(6, 8)}`
        }
        break
      }
      case '04': {
        // Mouvement
        const dateStr = line.substring(34, 42).trim()
        const date = dateStr.length === 8
          ? `${dateStr.substring(0, 4)}-${dateStr.substring(4, 6)}-${dateStr.substring(6, 8)}`
          : new Date().toISOString().split('T')[0]

        // Montant (position 91-104, 13 chiffres, 2 dernières = décimales)
        const amountRaw = line.substring(90, 103).trim()
        const amount = parseFloat(amountRaw) / 100 || 0

        // Sens (position 105) : C = crédit, D = débit
        const sens = line.substring(104, 105).trim()
        const type: 'debit' | 'credit' = sens === 'C' ? 'credit' : 'debit'

        // Libellé (position 81-100)
        const label = line.substring(80, 100).trim()

        // Référence (position 65-80)
        const reference = line.substring(64, 80).trim()

        transactions.push({
          date,
          description: label,
          reference,
          type,
          amount: type === 'debit' ? -Math.abs(amount) : Math.abs(amount),
        })
        break
      }
      case '07': {
        // Solde d'ouverture
        const amountRaw = line.substring(90, 103).trim()
        openingBalance = parseFloat(amountRaw) / 100 || 0
        break
      }
      case '08': {
        // Solde de clôture
        const amountRaw = line.substring(90, 103).trim()
        closingBalance = parseFloat(amountRaw) / 100 || 0
        const endDate = line.substring(34, 42).trim()
        if (endDate.length === 8) {
          periodEnd = `${endDate.substring(0, 4)}-${endDate.substring(4, 6)}-${endDate.substring(6, 8)}`
        }
        break
      }
    }
  }

  if (transactions.length === 0) {
    warnings.push('Aucune transaction trouvée dans le fichier CFONB 120')
  }

  return {
    transactions,
    rawText: content,
    accountNumber,
    periodStart,
    periodEnd,
    openingBalance,
    closingBalance,
    currency: currency || 'EUR',
    warnings,
  }
}

// ============================================================
// Détection de format automatique
// ============================================================
export type BankStatementFormat = 'camt053' | 'mt940' | 'cfonb120' | 'ofx' | 'unknown'

export function detectBankStatementFormat(content: string): BankStatementFormat {
  const trimmed = content.trim()

  // CAMT.053 = XML avec namespace camt
  if (trimmed.startsWith('<?xml') || trimmed.startsWith('<Document')) {
    if (trimmed.includes('camt.053') || trimmed.includes('camt053') || trimmed.includes('Ntry')) {
      return 'camt053'
    }
    // OFX = XML avec <OFX>
    if (trimmed.includes('<OFX>') || trimmed.includes('<OFX ')) {
      return 'ofx'
    }
    return 'camt053' // XML par défaut
  }

  // MT940 = commence par :20: ou :25: ou contient :61:
  if (trimmed.match(/^:[0-9]{2}:/m) || trimmed.includes(':61:') || trimmed.includes(':86:')) {
    return 'mt940'
  }

  // CFONB 120 = lignes de 120 caractères avec codes 01/04/07/08
  const firstLine = trimmed.split(/\r?\n/)[0]
  if (firstLine.length >= 120 && /^(01|04|07|08)/.test(firstLine)) {
    return 'cfonb120'
  }

  return 'unknown'
}

// ============================================================
// Point d'entrée unifié
// ============================================================
export function parseBankStatement(
  content: string,
  format?: BankStatementFormat
): BankStatementParseResult {
  const detected = format || detectBankStatementFormat(content)

  switch (detected) {
    case 'camt053':
      return parseCamt053(content)
    case 'mt940':
      return parseMt940(content)
    case 'cfonb120':
      return parseCfonb120(content)
    default:
      return {
        transactions: [],
        rawText: content,
        accountNumber: null,
        periodStart: null,
        periodEnd: null,
        openingBalance: null,
        closingBalance: null,
        currency: 'EUR',
        warnings: ['Format de relevé non reconnu. Utilisez l\'import LLM en repli.'],
      }
  }
}

// ============================================================
// Détection de doublons
// ============================================================
export function detectDuplicateTransactions(
  newTxs: ParsedBankTransaction[],
  existingTxs: ParsedBankTransaction[]
): ParsedBankTransaction[] {
  const existingKeys = new Set(
    existingTxs.map(t => `${t.date}|${t.amount.toFixed(2)}|${t.reference || ''}`)
  )
  return newTxs.filter(t =>
    existingKeys.has(`${t.date}|${t.amount.toFixed(2)}|${t.reference || ''}`)
  )
}
