// B8 (ven-010) : « Télécharger » produisait un blob `text/plain` de 156 octets
// (« Factures FAC-… / Client: null / … »). Le bouton produit désormais un vrai
// document : en-tête vendeur (raison sociale, SIREN, TVA, adresse), client,
// lignes, HT par taux, TVA, TTC et mentions légales.
//
// Le PDF est écrit ici, sans service externe ni dépendance nouvelle :
// `pdfjs-dist`, présent dans le bundle, ne sait que **lire** un PDF. Le fichier
// est un PDF 1.4 minimal (Helvetica, encodage WinAnsi) : une page, un flux de
// contenu, une table xref. Les libellés sont fournis par l'appelant (traduits),
// si bien que ce module reste pur et se teste sans DOM.
import type { Invoice, Customer } from '@/types'
import { formatCurrency, getCurrentLocale } from '@/lib/utils'

export interface InvoicePdfLabels {
  title: string
  proForma: string
  seller: string
  customer: string
  date: string
  dueDate: string
  description: string
  quantity: string
  unitPrice: string
  vatRate: string
  lineTotal: string
  subtotal: string
  vatTotal: string
  total: string
  balance: string
  mentions: string[]
}

interface Seller {
  name?: string | null
  siren?: string | null
  siret?: string | null
  vat_number?: string | null
  address?: string | null
  postal_code?: string | null
  city?: string | null
}

interface InvoicePdfLine {
  description?: string | null
  quantity?: number | string | null
  unit_price?: number | string | null
  vat_rate?: number | string | null
  total?: number | string | null
}

/** Les montants suivent la langue de l'app ; le PDF écrit l'espace insécable comme un espace. */
const money = (n: unknown): string => formatCurrency(Number(n) || 0).replace(/\u202f|\u00a0/g, ' ')

const num2 = (n: unknown): string =>
  new Intl.NumberFormat(getCurrentLocale(), { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(Number(n) || 0)

function escapePdfText(s: string): string {
  return s.replace(/\\/g, '\\\\').replace(/\(/g, '\\(').replace(/\)/g, '\\)')
}

/** Le PDF encode le texte en WinAnsi (Latin-1) : les caractères hors plan sont ignorés. */
function latin1(s: string): number[] {
  const out: number[] = []
  for (const ch of s) {
    const code = ch.codePointAt(0) ?? 63
    out.push(code <= 0xff ? code : 63)
  }
  return out
}

/** Le corps du document : les lignes de texte, dans l'ordre d'impression. */
export function invoicePdfLines(inv: Invoice, customer: Customer | null, company: Seller | null, labels: InvoicePdfLabels): string[] {
  const lines = (inv.invoice_lines || []) as InvoicePdfLine[]
  const out: string[] = []

  if (labels.proForma) out.push(labels.proForma, '')
  out.push(`${labels.title} ${inv.number}`)
  out.push('')

  out.push(labels.seller)
  if (company?.name) out.push(company.name)
  const siren = company?.siren || company?.siret
  if (siren) out.push(`${company?.siren ? 'SIREN' : 'SIRET'} ${siren}`)
  if (company?.vat_number) out.push(`TVA ${company.vat_number}`)
  const addr = [company?.address, [company?.postal_code, company?.city].filter(Boolean).join(' ')].filter(Boolean).join(', ')
  if (addr) out.push(addr)
  out.push('')

  out.push(labels.customer)
  out.push(customer?.name || inv.customer_name || '—')
  if (customer?.vat_number) out.push(`TVA ${customer.vat_number}`)
  out.push('')

  out.push(`${labels.date} : ${inv.date || ''}`)
  out.push(`${labels.dueDate} : ${inv.due_date || ''}`)
  out.push('')

  out.push(`${labels.description}  |  ${labels.quantity}  |  ${labels.unitPrice}  |  ${labels.vatRate}  |  ${labels.lineTotal}`)
  for (const raw of lines) {
    out.push(`${raw.description || ''}  |  ${num2(raw.quantity)}  |  ${money(raw.unit_price)}  |  ${num2(raw.vat_rate)} %  |  ${money(raw.total)}`)
  }
  out.push('')

  // HT par taux, comme sur la facture
  const byRate = new Map<number, number>()
  for (const raw of lines) {
    const rate = Number(raw.vat_rate) || 0
    byRate.set(rate, (byRate.get(rate) ?? 0) + (Number(raw.total) || 0))
  }
  for (const [rate, base] of [...byRate.entries()].sort((a, b) => a[0] - b[0])) {
    out.push(`${labels.subtotal} ${num2(rate)} %  :  ${money(base)}`)
  }
  out.push(`${labels.vatTotal}  :  ${money(inv.vat_total)}`)
  out.push(`${labels.total}  :  ${money(inv.total)}`)
  out.push(`${labels.balance}  :  ${money(inv.amount_due)}`)
  out.push('')

  for (const mention of labels.mentions) {
    if (mention) out.push(mention)
  }
  return out
}

/** Construit le PDF (octets) d'une facture. Pur : aucun accès au DOM. */
export function buildInvoicePdf(inv: Invoice, customer: Customer | null, company: Seller | null, labels: InvoicePdfLabels): Uint8Array {
  const lines = invoicePdfLines(inv, customer, company, labels)

  const content: number[] = []
  const push = (s: string) => { content.push(...latin1(s)) }
  push('BT\n/F1 10 Tf\n1 0 0 1 40 800 Tm\n14 TL\n')
  for (const line of lines) {
    push(`(${escapePdfText(line)}) Tj\nT*\n`)
  }
  push('ET\n')

  const objects: string[] = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>',
    `<< /Length ${content.length} >>\nstream\n${String.fromCharCode(...content)}\nendstream`,
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>',
  ]

  const chunks: number[] = [...latin1('%PDF-1.4\n')]
  const offsets: number[] = []
  objects.forEach((body, i) => {
    offsets.push(chunks.length)
    chunks.push(...latin1(`${i + 1} 0 obj\n${body}\nendobj\n`))
  })

  const xrefStart = chunks.length
  chunks.push(...latin1(`xref\n0 ${objects.length + 1}\n0000000000 65535 f \n`))
  for (const off of offsets) {
    chunks.push(...latin1(`${String(off).padStart(10, '0')} 00000 n \n`))
  }
  chunks.push(...latin1(`trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${xrefStart}\n%%EOF\n`))

  return new Uint8Array(chunks)
}

/** Télécharge le PDF dans le navigateur (nom de fichier explicite). */
export function downloadInvoicePdf(inv: Invoice, customer: Customer | null, company: Seller | null, labels: InvoicePdfLabels): void {
  const bytes = buildInvoicePdf(inv, customer, company, labels)
  const proForma = labels.proForma ? 'PRO-FORMA-' : ''
  const blob = new Blob([bytes as unknown as BlobPart], { type: 'application/pdf' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = `${proForma}${inv.number || 'facture'}.pdf`
  a.click()
  URL.revokeObjectURL(url)
}

