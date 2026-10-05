// Import OCR de factures fournisseurs via l'Edge Function ocr-invoice-import.
// Le modèle de vision n'accepte que des images : un PDF est rendu (page 1) en PNG côté navigateur.
import { supabase } from '@/lib/supabase'
import type { PurchaseInvoiceInput } from '@/lib/queries/sales'

export interface OcrInvoiceResult {
  supplierName: string
  supplierId: string | null
  invoiceNumber: string
  date: string
  dueDate: string
  subtotal: number
  vatTotal: number
  total: number
  currency: string
}

const MAX_RENDER_WIDTH = 1600

function blobToBase64(blob: Blob): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader()
    reader.onload = () => resolve(String(reader.result).split(',')[1] || '')
    reader.onerror = () => reject(reader.error)
    reader.readAsDataURL(blob)
  })
}

async function renderPdfFirstPage(file: File): Promise<string> {
  const pdfjsLib = await import('pdfjs-dist')
  const workerModule = await import('pdfjs-dist/build/pdf.worker.min.mjs?url')
  pdfjsLib.GlobalWorkerOptions.workerSrc = workerModule.default
  const pdf = await pdfjsLib.getDocument({ data: await file.arrayBuffer() }).promise
  const page = await pdf.getPage(1)
  const base = page.getViewport({ scale: 1 })
  const viewport = page.getViewport({ scale: Math.min(2, MAX_RENDER_WIDTH / base.width) })
  const canvas = document.createElement('canvas')
  canvas.width = Math.ceil(viewport.width)
  canvas.height = Math.ceil(viewport.height)
  const context = canvas.getContext('2d')
  if (!context) throw new Error('Rendu PDF impossible')
  await page.render({ canvas, canvasContext: context, viewport }).promise
  const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, 'image/png'))
  if (!blob) throw new Error('Rendu PDF impossible')
  return blobToBase64(blob)
}

const toNumber = (v: unknown) => {
  const n = typeof v === 'number' ? v : Number(String(v ?? '').replace(/\s/g, '').replace(',', '.'))
  return Number.isFinite(n) ? n : 0
}
const toIsoDate = (v: unknown) => {
  const s = String(v ?? '')
  const fr = s.match(/^(\d{2})\/(\d{2})\/(\d{4})$/)
  if (fr) return `${fr[3]}-${fr[2]}-${fr[1]}`
  return /^\d{4}-\d{2}-\d{2}/.test(s) ? s.slice(0, 10) : ''
}

export async function extractSupplierInvoice(file: File): Promise<OcrInvoiceResult> {
  const isPdf = file.type === 'application/pdf' || file.name.toLowerCase().endsWith('.pdf')
  const fileBase64 = isPdf ? await renderPdfFirstPage(file) : await blobToBase64(file)
  const mimeType = isPdf ? 'image/png' : (file.type || 'image/png')

  const { data, error } = await supabase.functions.invoke('ocr-invoice-import', {
    body: { file_base64: fileBase64, mime_type: mimeType },
  })
  if (error) throw error
  if (!data?.success || !data.extracted_data) {
    throw new Error(data?.error || 'Lecture de la facture impossible')
  }

  const d = data.extracted_data
  const total = toNumber(d.total)
  const vatTotal = toNumber(d.vat_total)
  const subtotal = d.subtotal != null ? toNumber(d.subtotal) : Math.max(0, total - vatTotal)
  return {
    supplierName: d.matched_supplier_name || d.supplier_name || '',
    supplierId: d.matched_supplier_id || null,
    invoiceNumber: d.invoice_number || '',
    date: toIsoDate(d.invoice_date),
    dueDate: toIsoDate(d.due_date),
    subtotal,
    vatTotal,
    total,
    currency: d.currency || 'EUR',
  }
}

/** Ce que le formulaire de relecture (SupplierInvoiceAutomationPage) remet à l'enregistrement. */
export interface OcrInvoiceForm {
  number: string
  supplierId: string
  supplierName?: string
  date: string
  dueDate: string
  subtotal: number
  vatTotal: number
  /** Libellé de la ligne unique (traduit par l'écran). */
  lineLabel: string
}

// La charge utile de l'écran, hors du composant : le banc « chemin de l'écran »
// (src/__screen__/02, verdicts P08/P09) la remet telle quelle à `createPurchaseInvoice`.
//
// Une facture lue par OCR entre comme toute facture saisie : en BROUILLON, puis elle
// suit le circuit d'approbation (numéro légal et écriture à l'approbation). Le statut
// `received` qu'écrivait l'écran n'existe pas pour une facture d'achat
// (`purchase_invoices_status_check`) : l'enregistrement échouait toujours.
// L'OCR ne lit que des totaux : ils deviennent UNE ligne (la base refuse d'approuver
// une facture sans ligne, et recalcule la TVA de la ligne depuis son taux — d'où le
// taux déduit des deux montants relus, gardé à six décimales pour retomber au centime).
export function ocrFormToPurchaseInvoice(form: OcrInvoiceForm): PurchaseInvoiceInput {
  const subtotal = Number(form.subtotal) || 0
  const vatTotal = Number(form.vatTotal) || 0
  const total = Math.round((subtotal + vatTotal) * 100) / 100
  const reference = form.number.trim()
  return {
    supplier_reference: reference,
    supplier_id: form.supplierId || null,
    supplier_name: form.supplierName || '',
    date: form.date,
    due_date: form.dueDate || form.date,
    status: 'draft',
    subtotal, vat_total: vatTotal, total, amount_paid: 0, amount_due: total,
    notes: '',
    lines: [{
      product_id: null,
      description: form.lineLabel,
      quantity: 1,
      unit_price: subtotal,
      vat_rate: subtotal > 0 ? Math.round((vatTotal / subtotal) * 1e8) / 1e6 : 0,
      total: subtotal,
      vat_total: vatTotal,
      vat_amount: vatTotal,
      line_order: 0,
    }],
  }
}
