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
  let currencyFromFile = false
  if (acct) {
    accountNumber = getText(acct, ns, 'Id') || getText(acct.getElementsByTagName('Id')[0], ns, 'IBAN') || getText(acct, ns, 'IBAN')
    const ccy = acct.getElementsByTagNameNS(ns, 'Ccy')[0]?.textContent?.trim()
      ?? acct.getElementsByTagName('Ccy')[0]?.textContent?.trim()
    currency = ccy || 'EUR'
    currencyFromFile = Boolean(ccy)
  }
  // La devise figure aussi en attribut des montants (`<Amt Ccy="EUR">`) : c'est le
  // seul endroit où elle apparaît dans un fichier dépourvu de bloc `Acct` complet.
  if (!currencyFromFile) {
    const amtEl = doc.getElementsByTagNameNS(ns, 'Amt')[0] ?? doc.getElementsByTagName('Amt')[0]
    const ccyAttr = amtEl?.getAttribute('Ccy')?.trim()
    if (ccyAttr) {
      currency = ccyAttr
      currencyFromFile = true
    }
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

    // Libellé : `AddtlNtryInf` quand la banque le remplit, sinon le libellé non
    // structuré `Ustrd` (le plus courant), puis les détails ; en dernier recours le
    // texte concaténé du bloc, qui reste préférable à une ligne sans libellé.
    const label = getText(entry, ns, 'AddtlNtryInf')
      || getText(entry, ns, 'Ustrd')
      || getText(entry.getElementsByTagName('NtryDtls')[0], ns, 'AddtlTxInf')
      || getText(entry, ns, 'NtryDtls')

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
    currencyFromFile,
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
  let currencyFromFile = false
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

    // Solde d'ouverture :60F: (final) ou :60M: (intermédiaire) :CYYMMDDEUR1234,56
    if (line.startsWith(':60F:') || line.startsWith(':60M:')) {
      const parsed = parseMt940Balance(line.substring(5))
      openingBalance = parsed.amount
      if (parsed.currency) {
        currency = parsed.currency
        currencyFromFile = true
      }
      periodStart = parsed.date
    }

    // Solde de clôture :62F: (final) ou :62M: (intermédiaire)
    if (line.startsWith(':62F:') || line.startsWith(':62M:')) {
      const parsed = parseMt940Balance(line.substring(5))
      closingBalance = parsed.amount
      periodEnd = parsed.date
    }

    // Mouvement :61:YYMMDDMMDDDR1234,56NNNN
    if (line.startsWith(':61:')) {
      // Pousser la transaction précédente
      if (currentTx) transactions.push(currentTx)

      const raw = line.substring(4)
      // Format de la norme : YYMMDD[MMDD][R]C|DAMOUNT[Nxxx[reference]]
      const dateStr = raw.substring(0, 6)
      const date = `20${dateStr.substring(0, 2)}-${dateStr.substring(2, 4)}-${dateStr.substring(4, 6)}`

      // R-10 : la date de valeur est MMDD dans la norme, YYMMDD chez certains
      // émetteurs. On ne la consomme que si le caractère suivant est bien un sens
      // (C ou D) : sans ce contrôle, « 0102D120,00 » se lisait « montant 102 », et
      // tout relevé réel donnait des montants faux sans le moindre avertissement.
      let idx = 6
      if (/^\d{6}$/.test(raw.substring(6, 12)) && /^[CD]$/.test(raw[12] ?? '')) idx = 12
      else if (/^\d{4}$/.test(raw.substring(6, 10)) && /^[CD]$/.test(raw[10] ?? '')) idx = 10

      // Indicateur débit/crédit : C = crédit, D = débit, RC/RD = rectificatif
      if (raw[idx] === 'R') idx++
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
    currencyFromFile,
    warnings,
  }
}

function parseMt940Balance(raw: string): { amount: number; currency: string | null; date: string } {
  // Format: DYYMMDDCURRENCYAMOUNT (D = débit/crédit)
  const dateStr = raw.substring(1, 7)
  const date = `20${dateStr.substring(0, 2)}-${dateStr.substring(2, 4)}-${dateStr.substring(4, 6)}`

  // Devise : trois lettres (ISO 4217) après la date, quand le relevé l'annonce.
  // R-10 : sans ce contrôle, un solde qui ne porte pas de devise ferait lire « 100 »
  // comme devise sur `:60F:C2501011000,00`, et le contrôle de devise refuserait le relevé.
  let currency: string | null = null
  let idx = 7
  const ccy = raw.substring(7, 10).trim()
  if (/^[A-Z]{3}$/.test(ccy)) {
    currency = ccy
    idx = 10
  }
  const amountStr = raw.substring(idx).replace(',', '.')
  const amount = parseFloat(amountStr) || 0

  return { amount, currency, date }
}

// ============================================================
// CFONB 120 — Format à position fixe (France)
// ============================================================
// CFONB 120 — relevé de compte (norme CFONB, brochure 2004)
//
// Format positionnel, enregistrements de 120 caractères : 01 ancien solde (et
// en-tête commun), 04 mouvement, 05 complément de mouvement, 07 nouveau solde.
//
// R-10 : les positions ci-dessous viennent de la norme elle-même. Le lecteur
// précédent lisait une date ISO de 8 chiffres là où la norme en écrit 6 (JJMMAA),
// un « sens » dans une colonne 105 qui n'existe pas (105-120 = la référence) et un
// libellé sur la zone du numéro d'écriture et des drapeaux. Sur un fichier réel, il
// perdait donc ses dates, ses montants et ses libellés — ce qu'aucune chaîne de test
// inventée ne pouvait montrer.
// ============================================================

/** Spécificateur de signe et d'unité du montant CFONB (14e caractère de la zone). */
const CFONB_AMOUNT_SPECIFIER: Record<string, { sign: 1 | -1; units: number }> = {}
'{ABCDEFGHI'.split('').forEach((c, i) => { CFONB_AMOUNT_SPECIFIER[c] = { sign: 1, units: i } })
'}JKLMNOPQR'.split('').forEach((c, i) => { CFONB_AMOUNT_SPECIFIER[c] = { sign: -1, units: i } })

/**
 * Montant CFONB : 13 chiffres + 1 spécificateur qui porte **le signe et l'unité**
 * (positions 91-104), divisé par 10^échelle (échelle = position 20).
 * Exemple de la norme : `0000000001904}` avec échelle 2 → −190,40.
 */
export function parseCfonbAmount(field: string, scale: number): number | null {
  const raw = field.padEnd(14, ' ')
  const spec = CFONB_AMOUNT_SPECIFIER[raw[13]]
  const digits = raw.substring(0, 13).trim()
  if (!spec || digits === '' || !/^\d+$/.test(digits)) return null
  const decimals = Number.isInteger(scale) && scale >= 0 && scale <= 9 ? scale : 2
  return (spec.sign * Number(`${digits}${spec.units}`)) / Math.pow(10, decimals)
}

/** Date CFONB `JJMMAA` : pivot à 60 (61 → 1961, 60 → 2060). */
export function parseCfonbDate(field: string): string | null {
  const raw = (field || '').trim()
  if (!/^\d{6}$/.test(raw)) return null
  const day = Number(raw.substring(0, 2))
  const month = Number(raw.substring(2, 4))
  const yy = Number(raw.substring(4, 6))
  if (day < 1 || day > 31 || month < 1 || month > 12) return null
  const year = yy > 60 ? 1900 + yy : 2000 + yy
  return `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`
}

export function parseCfonb120(content: string): BankStatementParseResult {
  const warnings: string[] = []
  const transactions: ParsedBankTransaction[] = []
  let accountNumber: string | null = null
  let openingBalance: number | null = null
  let closingBalance: number | null = null
  let currency: string | null = 'EUR'
  let currencyFromFile = false
  let scale = 2
  let periodStart: string | null = null
  let periodEnd: string | null = null

  const lines = content.split(/\r?\n/)
  let currentTx: ParsedBankTransaction | null = null

  for (const line of lines) {
    if (line.length < 120) continue

    // En-tête commun à tous les enregistrements (norme positions 17-32) : devise,
    // nombre de décimales, numéro de compte.
    const ccy = line.substring(16, 19).trim()
    if (ccy && !currencyFromFile) {
      currency = ccy
      currencyFromFile = true
    }
    const scaleRaw = line.substring(19, 20).trim()
    if (/^\d$/.test(scaleRaw)) scale = Number(scaleRaw)
    const account = line.substring(21, 32).trim()
    if (account && !accountNumber) accountNumber = account

    switch (line.substring(0, 2)) {
      case '01': {
        // Ancien solde : date (35-40), montant signé (91-104)
        periodStart = parseCfonbDate(line.substring(34, 40))
        openingBalance = parseCfonbAmount(line.substring(90, 104), scale)
        break
      }
      case '04': {
        // Mouvement : date comptable (35-40), date de valeur (43-48) en repli,
        // libellé (49-80), montant signé (91-104), référence (105-120)
        const date = parseCfonbDate(line.substring(34, 40)) || parseCfonbDate(line.substring(42, 48))
        const amount = parseCfonbAmount(line.substring(90, 104), scale)
        const reference = line.substring(104, 120).trim()
        currentTx = null
        if (amount == null) {
          warnings.push('Mouvement CFONB sans montant exploitable, ignoré')
          break
        }
        if (date == null) {
          warnings.push(`Mouvement CFONB sans date exploitable (référence ${reference || 'absente'}), ignoré`)
          break
        }
        currentTx = {
          date,
          description: line.substring(48, 80).trim(),
          reference,
          type: amount < 0 ? 'debit' : 'credit',
          amount,
        }
        transactions.push(currentTx)
        break
      }
      case '05': {
        // Complément du mouvement précédent : qualificatif (46-48), information (49-118)
        const qualifier = line.substring(45, 48).trim().toUpperCase()
        const info = line.substring(48, 118).trim()
        if (!currentTx || !info) break
        if (qualifier === 'LIB') {
          currentTx.description = [currentTx.description, info].filter(Boolean).join(' ')
        } else if (qualifier.startsWith('REF') || qualifier === 'NPY') {
          currentTx.reference = [currentTx.reference, info].filter(Boolean).join(' ')
        }
        break
      }
      case '07':
      case '08': {
        // Nouveau solde : 07 selon la norme, 08 chez certains émetteurs
        closingBalance = parseCfonbAmount(line.substring(90, 104), scale)
        periodEnd = parseCfonbDate(line.substring(34, 40)) || periodEnd
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
    currencyFromFile,
    warnings,
  }
}

// ============================================================
// OFX — Open Financial Exchange (R-10)
//
// Deux générations cohabitent et les banques exportent l'une ou l'autre :
//   - OFX 1.x = SGML : les balises de valeur s'ouvrent sans se fermer
//     (`<TRNAMT>-12.34` suivi de la balise suivante). Un parseur XML les refuse ;
//   - OFX 2.x = XML bien formé (`<TRNAMT>-12.34</TRNAMT>`).
// Le format prévoyait aussi une enveloppe de headers (`OFXHEADER:100`) avant les
// données, que l'on ignore.
//
// Date OFX : YYYYMMDD[HHMMSS[.mmm]][[±h:TZ]] — seuls les 8 premiers chiffres
// portent la date. Montant signé : le signe fait foi, `TRNTYPE` ne sert que de
// repli quand le montant est positif (certains exports inversent la convention).
// ============================================================

/** Date OFX → YYYY-MM-DD, ou null si le champ n'est pas exploitable */
export function parseOfxDate(raw: string): string | null {
  const digits = (raw || '').trim().match(/^(\d{4})(\d{2})(\d{2})/)
  if (!digits) return null
  const [, y, m, d] = digits
  const month = Number(m)
  const day = Number(d)
  if (month < 1 || month > 12 || day < 1 || day > 31) return null
  return `${y}-${m}-${d}`
}

/** Les balises d'une transaction OFX, dans les deux syntaxes */
function ofxTag(block: string, tag: string): string {
  const xml = block.match(new RegExp(`<${tag}[^>]*>([^<]*)</${tag}>`, 'i'))
  if (xml) return xml[1].trim()
  const sgml = block.match(new RegExp(`<${tag}[^>]*>([^<\\r\\n]*)`, 'i'))
  return sgml ? sgml[1].trim() : ''
}

/** Les blocs `<STMTTRN>…</STMTTRN>` (XML) ou `<STMTTRN>…` (SGML, jusqu'au suivant) */
function ofxBlocks(content: string, tag: string): string[] {
  const xml = content.match(new RegExp(`<${tag}>[\\s\\S]*?</${tag}>`, 'gi'))
  if (xml && xml.length > 0) return xml
  // SGML : le bloc court jusqu'à la balise de même niveau suivante ou la fin
  const opens = content.match(new RegExp(`<${tag}>[\\s\\S]*?(?=<${tag}>|</BANKTRANLIST>|</OFX>|$)`, 'gi'))
  return opens || []
}

export function parseOfx(content: string): BankStatementParseResult {
  const warnings: string[] = []
  const transactions: ParsedBankTransaction[] = []

  // Devise du relevé : `CURDEF` (obligatoire) ; `CURSYM` en repli (bloc CURRENCY)
  const currencyTag = ofxTag(content, 'CURDEF') || ofxTag(content, 'CURSYM')
  const currency = currencyTag ? currencyTag.toUpperCase().slice(0, 3) : null
  const currencyFromFile = Boolean(currencyTag)

  const accountNumber = ofxTag(content, 'ACCTID') || null

  const periodStart = parseOfxDate(ofxTag(content, 'DTSTART'))
  const dtEnd = parseOfxDate(ofxTag(content, 'DTEND'))

  // Solde du relevé : <LEDGERBAL><BALAMT>…<DTASOF>…
  const ledger = content.match(/<LEDGERBAL>[\s\S]*?(?=<\/LEDGERBAL>|<\/STMTRS>|<LEDGERBAL>|$)/i)
  const ledgerBlock = ledger ? ledger[0] : ''
  const closingRaw = ofxTag(ledgerBlock, 'BALAMT')
  const closingBalance = closingRaw ? parseFloat(closingRaw.replace(',', '.')) : null
  const closingDate = parseOfxDate(ofxTag(ledgerBlock, 'DTASOF'))
  // Invariant partagé par les quatre lecteurs : quand un solde de clôture est
  // lu, `periodEnd` porte SA date (CAMT `CLBD`, MT940 `:62F:`, CFONB enreg. 08,
  // OFX `DTASOF`). L'import s'appuie dessus pour dater `statement_balance`.
  const periodEnd = closingBalance != null ? (closingDate || dtEnd) : dtEnd

  for (const block of ofxBlocks(content, 'STMTTRN')) {
    const amountRaw = ofxTag(block, 'TRNAMT')
    if (!amountRaw) continue
    const amount = parseFloat(amountRaw.replace(',', '.'))
    if (!Number.isFinite(amount) || amount === 0) continue

    const trnType = ofxTag(block, 'TRNTYPE').toUpperCase()
    // Le signe du montant fait foi ; `TRNTYPE` tranche seulement s'il est positif
    const outgoing = /^(DEBIT|CHECK|PAYMENT|FEE|DIRECTDEBIT|ATM|POS|SRVCHG|OTHER)$/.test(trnType)
    const type: 'debit' | 'credit' = amount < 0 ? 'debit' : (outgoing && !/^(CREDIT|DEP|DIRECTDEP|INT|DIV)$/.test(trnType) ? 'debit' : 'credit')

    const date = parseOfxDate(ofxTag(block, 'DTPOSTED') || ofxTag(block, 'DTUSER') || ofxTag(block, 'DTAVAIL'))
    if (!date) {
      warnings.push(`Transaction OFX sans date exploitable (FITID ${ofxTag(block, 'FITID') || 'inconnu'}) ignorée`)
      continue
    }

    const name = ofxTag(block, 'NAME')
    const memo = ofxTag(block, 'MEMO')
    const checkNumber = ofxTag(block, 'CHECKNUM')
    const fitid = ofxTag(block, 'FITID')

    transactions.push({
      date,
      description: [name, memo].filter(Boolean).join(' — ') || (checkNumber ? `Chèque ${checkNumber}` : 'Opération OFX'),
      reference: fitid || checkNumber || '',
      type,
      amount: type === 'debit' ? -Math.abs(amount) : Math.abs(amount),
    })
  }

  if (transactions.length === 0) {
    warnings.push('Aucune transaction trouvée dans le fichier OFX')
  }
  if (closingBalance != null && closingDate == null) {
    warnings.push('Solde de clôture OFX sans date (DTASOF absent) : daté de la fin de période')
  }

  return {
    transactions,
    rawText: content,
    accountNumber,
    periodStart,
    periodEnd,
    openingBalance: null,
    closingBalance,
    currency,
    currencyFromFile,
    warnings,
  } as BankStatementParseResult
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

  // OFX 1.x = SGML : enveloppe `OFXHEADER:100` puis des balises qui ne se ferment pas
  // (R-10 : sans cette branche, un relevé OFX SGML restait « non reconnu »)
  if (/^OFXHEADER\s*:/i.test(trimmed) || /<OFX>/i.test(trimmed) || /<STMTTRN>/i.test(trimmed)) {
    return 'ofx'
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
    case 'ofx':
      return parseOfx(content)
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
