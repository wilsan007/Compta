// Import OCR de factures fournisseurs via l'Edge Function ocr-invoice-import.
// Le modèle de vision n'accepte que des images : un PDF est rendu (page 1) en PNG côté navigateur.
import { supabase } from '@/lib/supabase'

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
