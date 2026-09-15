// PRF-02 : pdfjs-dist chargé dynamiquement pour réduire le bundle initial
import { supabase } from '@/lib/supabase'

export interface ParsedBankTransaction {
  date: string
  description: string
  reference: string
  type: 'debit' | 'credit'
  amount: number
}

export interface BankStatementParseResult {
  transactions: ParsedBankTransaction[]
  rawText: string
  accountNumber: string | null
  periodStart: string | null
  periodEnd: string | null
  openingBalance: number | null
  closingBalance: number | null
  currency: string | null
  warnings: string[]
}

interface BankTemplate {
  id: string
  name: string
  datePattern: RegExp
  amountPattern: RegExp
  descriptionPattern?: RegExp
  referencePattern?: RegExp
  debitIndicator?: RegExp
  creditIndicator?: RegExp
  accountNumberPattern?: RegExp
  periodPattern?: RegExp
  balancePattern?: RegExp
  currencyPattern?: RegExp
  skipLines?: RegExp
}

const TEMPLATES: BankTemplate[] = [
  {
    id: 'generic',
    name: 'Générique',
    datePattern: /(\d{2}[/\-.]\d{2}[/\-.]\d{2,4})/,
    amountPattern: /(-?\d{1,3}(?:[.,\s]\d{3})*(?:[.,]\d{2})?)\s*(?:USD|EUR|DJF|FCFA|F)?$/i,
    descriptionPattern: /[A-Z]{2,}.*?(?=\d{2}[/\-.]|\d+(?:[.,]\d{2})\s*$|$)/,
    skipLines: /^(solde|total|page|relevé|compte|date|libell|montant|définition)/i,
  },
  {
    id: 'bcim',
    name: 'BCIM Djibouti',
    datePattern: /(\d{2}[/\-.]\d{2}[/\-.]\d{2,4})/,
    amountPattern: /(-?\d{1,3}(?:[.,\s]\d{3})*(?:[.,]\d{2})?)\s*(?:DJF|USD|EUR)?$/i,
    descriptionPattern: /(.+?)(?=\s+\d)/,
    referencePattern: /(REF[:\s]*[A-Z0-9-]+)/i,
    debitIndicator: /(débit|debit|retrait|DR)/i,
    creditIndicator: /(crédit|credit|dépôt|depot|CR)/i,
    accountNumberPattern: /compte[:\s]*(\d[\d\s-]{5,30})/i,
    periodPattern: /période[:\s]*(\d{2}[/\-.]\d{2}[/\-.]\d{2,4})\s*(?:au|to|à|a)\s*(\d{2}[/\-.]\d{2}[/\-.]\d{2,4})/i,
    balancePattern: /(?:nouveau|ancien|initial)[\s:]*solde[:\s]*(-?\d[\d\s.,]*)/i,
    currencyPattern: /(USD|EUR|DJF|FCFA)/i,
    skipLines: /^(solde|total|page|relevé|compte n|date|libellé|montant|définition|banque)/i,
  },
  {
    id: 'bred',
    name: 'BRED',
    datePattern: /(\d{2}[/\-.]\d{2}[/\-.]\d{2,4})/,
    amountPattern: /(-?\d{1,3}(?:[.,\s]\d{3})*(?:[.,]\d{2})?)\s*(?:EUR|USD|DJF)?$/i,
    descriptionPattern: /(.+?)(?=\s+-?\d)/,
    referencePattern: /(?:n°|no|ref)[:\s]*([A-Z0-9-]+)/i,
    debitIndicator: /(débit|debit|retrait)/i,
    creditIndicator: /(crédit|credit|dépôt|depot)/i,
    accountNumberPattern: /compte[:\s]*(\d[\d\s-]{5,30})/i,
    periodPattern: /du\s+(\d{2}[/\-.]\d{2}[/\-.]\d{2,4})\s*(?:au|to)\s*(\d{2}[/\-.]\d{2}[/\-.]\d{2,4})/i,
    skipLines: /^(solde|total|page|relevé|date|libellé|montant)/i,
  },
  {
    id: 'boa',
    name: 'Bank of Africa',
    datePattern: /(\d{2}[/\-.]\d{2}[/\-.]\d{2,4})/,
    amountPattern: /(-?\d{1,3}(?:[.,\s]\d{3})*(?:[.,]\d{2})?)\s*(?:DJF|USD|EUR|FCFA)?$/i,
    descriptionPattern: /(.+?)(?=\s+-?\d)/,
    referencePattern: /(?:op|operation)[:\s]*([A-Z0-9-]+)/i,
    debitIndicator: /(débit|debit|retrait|DR)/i,
    creditIndicator: /(crédit|credit|dépôt|depot|CR)/i,
    accountNumberPattern: /compte[:\s]*(\d[\d\s-]{5,30})/i,
    skipLines: /^(solde|total|page|relevé|date|libellé|montant|bank of)/i,
  },
]

function parseDate(dateStr: string): string {
  const cleaned = dateStr.trim().replace(/\s/g, '')
  const parts = cleaned.split(/[/\-.]/)
  if (parts.length !== 3) return dateStr
  let [dd, mm, yy] = parts
  if (yy.length === 2) yy = '20' + yy
  return `${yy}-${mm.padStart(2, '0')}-${dd.padStart(2, '0')}`
}

function parseAmount(amountStr: string): number {
  let cleaned = amountStr.trim().replace(/\s/g, '')
  const isNegative = cleaned.startsWith('-')
  cleaned = cleaned.replace(/^-/, '').replace(/^\+/, '')
  if (cleaned.includes('.') && cleaned.includes(',')) {
    cleaned = cleaned.replace(/\./g, '').replace(',', '.')
  } else if (cleaned.includes(',') && !cleaned.includes('.')) {
    cleaned = cleaned.replace(',', '.')
  } else {
    cleaned = cleaned.replace(/\./g, '')
  }
  const num = parseFloat(cleaned) || 0
  return isNegative ? -Math.abs(num) : num
}

function detectType(line: string, template: BankTemplate): 'debit' | 'credit' {
  if (template.creditIndicator && template.creditIndicator.test(line)) return 'credit'
  if (template.debitIndicator && template.debitIndicator.test(line)) return 'debit'
  return 'debit'
}

export async function extractPdfText(file: File): Promise<string> {
  const arrayBuffer = await file.arrayBuffer()
  const pdfjsLib = await import('pdfjs-dist')
  const workerModule = await import('pdfjs-dist/build/pdf.worker.min.mjs?url')
  pdfjsLib.GlobalWorkerOptions.workerSrc = workerModule.default
  const pdf = await pdfjsLib.getDocument({ data: arrayBuffer }).promise

  // SECURITY: Cap page count to prevent DoS via huge PDFs
  const MAX_PAGES = 50
  const MAX_TEXT_LENGTH = 150_000
  const pageCount = Math.min(pdf.numPages, MAX_PAGES)
  let fullText = ''

  for (let i = 1; i <= pageCount; i++) {
    const page = await pdf.getPage(i)
    const textContent = await page.getTextContent()
    const pageText = textContent.items
      .map((item: any) => item.str)
      .join(' ')
    fullText += pageText + '\n'
    // SECURITY: Stop if text exceeds max length
    if (fullText.length > MAX_TEXT_LENGTH) {
      fullText = fullText.slice(0, MAX_TEXT_LENGTH)
      break
    }
  }
  return fullText
}

export function parseBankStatement(rawText: string, templateId: string = 'generic'): BankStatementParseResult {
  const template = TEMPLATES.find(t => t.id === templateId) || TEMPLATES[0]
  const warnings: string[] = []
  const lines = rawText.split('\n').map(l => l.trim()).filter(Boolean)

  let accountNumber: string | null = null
  let periodStart: string | null = null
  let periodEnd: string | null = null
  let openingBalance: number | null = null
  let closingBalance: number | null = null
  let currency: string | null = null

  for (const line of lines) {
    if (!accountNumber && template.accountNumberPattern) {
      const m = line.match(template.accountNumberPattern)
      if (m) accountNumber = m[1].trim()
    }
    if (!periodStart && template.periodPattern) {
      const m = line.match(template.periodPattern)
      if (m) {
        periodStart = parseDate(m[1])
        periodEnd = parseDate(m[2])
      }
    }
    if (openingBalance === null && template.balancePattern) {
      const m = line.match(template.balancePattern)
      if (m) openingBalance = parseAmount(m[1])
    }
    if (!currency && template.currencyPattern) {
      const m = line.match(template.currencyPattern)
      if (m) currency = m[1]
    }
  }

  const transactions: ParsedBankTransaction[] = []
  for (const line of lines) {
    if (template.skipLines && template.skipLines.test(line)) continue

    const dateMatch = line.match(template.datePattern)
    if (!dateMatch) continue

    const date = parseDate(dateMatch[1])
    const amountMatch = line.match(template.amountPattern)
    if (!amountMatch) continue

    const rawAmount = amountMatch[1]
    const amount = Math.abs(parseAmount(rawAmount))
    if (amount === 0) continue

    let description = line
      .replace(dateMatch[0], '')
      .replace(amountMatch[0], '')
      .trim()

    if (template.referencePattern) {
      const refMatch = line.match(template.referencePattern)
      if (refMatch) {
        description = description.replace(refMatch[0], '').trim()
      }
    }

    description = description.replace(/\s+/g, ' ').substring(0, 200)

    const type = rawAmount.startsWith('-') ? 'debit' : detectType(line, template)
    const reference = template.referencePattern ? (line.match(template.referencePattern)?.[1] || '') : ''

    transactions.push({ date, description, reference, type, amount })
  }

  if (transactions.length === 0) {
    warnings.push('No transactions found. Try a different template or check PDF format.')
  }

  return {
    transactions,
    rawText,
    accountNumber,
    periodStart,
    periodEnd,
    openingBalance,
    closingBalance,
    currency,
    warnings,
  }
}

export function getAvailableTemplates() {
  return TEMPLATES.map(t => ({ id: t.id, name: t.name }))
}

// ============ DB-learned templates ============

interface DBTemplate {
  id: string
  bank_name: string
  date_pattern: string
  amount_pattern: string
  description_pattern: string | null
  reference_pattern: string | null
  debit_indicator: string | null
  credit_indicator: string | null
  account_number_pattern: string | null
  period_pattern: string | null
  balance_pattern: string | null
  currency_pattern: string | null
  skip_lines_pattern: string | null
}

function dbTemplateToBankTemplate(dbt: DBTemplate): BankTemplate {
  return {
    id: `db_${dbt.id}`,
    name: dbt.bank_name,
    datePattern: new RegExp(dbt.date_pattern),
    amountPattern: new RegExp(dbt.amount_pattern),
    descriptionPattern: dbt.description_pattern ? new RegExp(dbt.description_pattern) : undefined,
    referencePattern: dbt.reference_pattern ? new RegExp(dbt.reference_pattern) : undefined,
    debitIndicator: dbt.debit_indicator ? new RegExp(dbt.debit_indicator, 'i') : undefined,
    creditIndicator: dbt.credit_indicator ? new RegExp(dbt.credit_indicator, 'i') : undefined,
    accountNumberPattern: dbt.account_number_pattern ? new RegExp(dbt.account_number_pattern, 'i') : undefined,
    periodPattern: dbt.period_pattern ? new RegExp(dbt.period_pattern, 'i') : undefined,
    balancePattern: dbt.balance_pattern ? new RegExp(dbt.balance_pattern, 'i') : undefined,
    currencyPattern: dbt.currency_pattern ? new RegExp(dbt.currency_pattern, 'i') : undefined,
    skipLines: dbt.skip_lines_pattern ? new RegExp(dbt.skip_lines_pattern, 'i') : undefined,
  }
}

export async function getLearnedTemplates(): Promise<{ id: string; name: string }[]> {
  try {
    const { data, error } = await supabase
      .from('bank_statement_templates')
      .select('id, bank_name')
      .eq('is_active', true)
      .order('bank_name')
    if (error) throw error
    return (data || []).map((t: any) => ({ id: `db_${t.id}`, name: `🤖 ${t.bank_name}` }))
  } catch (err) {
    console.error('getLearnedTemplates:', err)
    return []
  }
}

export async function parseWithLearnedTemplate(rawText: string, templateId: string): Promise<BankStatementParseResult | null> {
  if (!templateId.startsWith('db_')) return null
  const dbId = templateId.replace('db_', '')
  const { data, error } = await supabase
    .from('bank_statement_templates')
    .select('*')
    .eq('id', dbId)
    .single()
  if (error) { console.error('pdfBankParser getTemplateById:', error); return null }
  if (!data) return null
  const template = dbTemplateToBankTemplate(data as DBTemplate)
  return parseBankStatementWithTemplate(rawText, template)
}

function parseBankStatementWithTemplate(rawText: string, template: BankTemplate): BankStatementParseResult {
  const warnings: string[] = []
  const lines = rawText.split('\n').map(l => l.trim()).filter(Boolean)

  let accountNumber: string | null = null
  let periodStart: string | null = null
  let periodEnd: string | null = null
  let openingBalance: number | null = null
  let closingBalance: number | null = null
  let currency: string | null = null

  for (const line of lines) {
    if (!accountNumber && template.accountNumberPattern) {
      const m = line.match(template.accountNumberPattern)
      if (m) accountNumber = m[1].trim()
    }
    if (!periodStart && template.periodPattern) {
      const m = line.match(template.periodPattern)
      if (m) { periodStart = parseDate(m[1]); periodEnd = parseDate(m[2]) }
    }
    if (openingBalance === null && template.balancePattern) {
      const m = line.match(template.balancePattern)
      if (m) openingBalance = parseAmount(m[1])
    }
    if (!currency && template.currencyPattern) {
      const m = line.match(template.currencyPattern)
      if (m) currency = m[1]
    }
  }

  const transactions: ParsedBankTransaction[] = []
  for (const line of lines) {
    if (template.skipLines && template.skipLines.test(line)) continue
    const dateMatch = line.match(template.datePattern)
    if (!dateMatch) continue
    const date = parseDate(dateMatch[1])
    const amountMatch = line.match(template.amountPattern)
    if (!amountMatch) continue
    const rawAmount = amountMatch[1]
    const amount = Math.abs(parseAmount(rawAmount))
    if (amount === 0) continue
    let description = line.replace(dateMatch[0], '').replace(amountMatch[0], '').trim()
    if (template.referencePattern) {
      const refMatch = line.match(template.referencePattern)
      if (refMatch) description = description.replace(refMatch[0], '').trim()
    }
    description = description.replace(/\s+/g, ' ').substring(0, 200)
    const type = rawAmount.startsWith('-') ? 'debit' : detectType(line, template)
    const reference = template.referencePattern ? (line.match(template.referencePattern)?.[1] || '') : ''
    transactions.push({ date, description, reference, type, amount })
  }

  if (transactions.length === 0) warnings.push('No transactions found with this template.')
  return { transactions, rawText, accountNumber, periodStart, periodEnd, openingBalance, closingBalance, currency, warnings }
}

// ============ AI-powered parsing (first time for a new bank) ============

export interface AIParseResult extends BankStatementParseResult {
  templateId?: string
  bankName?: string
  validationStatus?: 'pending' | 'validated' | 'rejected'
}

export interface PreviousTemplate {
  date_pattern: string
  amount_pattern: string
  description_pattern: string | null
  reference_pattern: string | null
  debit_indicator: string | null
  credit_indicator: string | null
  skip_lines_pattern: string | null
}

export async function parseWithAI(
  rawText: string,
  bankName?: string,
  bankId?: string,
  previousTemplate?: PreviousTemplate | null,
  correctionNotes?: string | null,
  attemptCount?: number,
): Promise<AIParseResult> {
  const { data: { session } } = await supabase.auth.getSession()
  if (!session) throw new Error('Not authenticated')

  const response = await fetch(`${import.meta.env.VITE_SUPABASE_URL}/functions/v1/parse-bank-statement`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${session.access_token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ rawText, bankName, bankId, previousTemplate, correctionNotes, attemptCount }),
  })

  if (!response.ok) {
    const err = await response.json().catch(() => ({ error: 'Unknown error' }))
    throw new Error(err.error || 'AI parsing failed')
  }

  const result = await response.json()
  return {
    transactions: result.transactions || [],
    rawText,
    accountNumber: result.accountNumber || null,
    periodStart: result.periodStart || null,
    periodEnd: result.periodEnd || null,
    openingBalance: null,
    closingBalance: null,
    currency: result.currency || null,
    warnings: result.warnings || [],
    templateId: result.templateId,
    bankName: result.bankName,
    validationStatus: result.validationStatus || 'pending',
  }
}

// Parse using a saved template from the DB (by bank_id)
export async function parseWithBankTemplate(rawText: string, bankId: string): Promise<BankStatementParseResult | null> {
  const { data, error } = await supabase
    .from('bank_statement_templates')
    .select('*')
    .eq('bank_id', bankId)
    .eq('is_active', true)
    .order('updated_at', { ascending: false })
    .limit(1)
    .maybeSingle()
  if (error) { console.error('pdfBankParser getTemplateByBankId:', error); return null }
  if (!data) return null
  const template = dbTemplateToBankTemplate(data as DBTemplate)
  return parseBankStatementWithTemplate(rawText, template)
}
