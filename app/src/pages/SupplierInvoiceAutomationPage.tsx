import { useEffect, useState } from 'react'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Input } from '@/components/ui'
import { formatCurrency, formatDate } from '@/lib/utils'
import { getPurchaseInvoices, createPurchaseInvoice } from '@/lib/queries/sales'
import { getSuppliers } from '@/lib/queries/partners'
import { validateFileUpload, FILE_PROFILES } from '@/lib/fileSecurity'
import { extractSupplierInvoice, type OcrInvoiceResult } from '@/lib/ocrInvoice'
import { Upload, FileText, CheckCircle2, X, Sparkles, AlertCircle } from 'lucide-react'
import type { PurchaseInvoice, Supplier } from '@/types'
import { useToast } from '@/lib/toast'
import { useTranslation } from 'react-i18next'

export function SupplierInvoiceAutomationPage() {
  const { t } = useTranslation('purchases')
  const { t: tNav } = useTranslation('nav')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [invoices, setInvoices] = useState<PurchaseInvoice[]>([])
  const [suppliers, setSuppliers] = useState<Supplier[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [ocrResult, setOcrResult] = useState<OcrInvoiceResult | null>(null)
  const [processing, setProcessing] = useState(false)

  // oxlint-disable-next-line react-hooks/exhaustive-deps -- chargement volontairement limite aux valeurs listees
  useEffect(() => { load() }, [])

  async function load() {
    try {
      const [inv, sup] = await Promise.all([getPurchaseInvoices(), getSuppliers()])
      setInvoices(inv || [])
      setSuppliers(sup || [])
    } catch (err: any) { console.error('Error loading data:', err); toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadError'))
    } finally {
      setLoading(false)
    }
  }

  async function handleFileUpload(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0]
    if (!file) return
    // SECURITY: Validate file before processing
    const validation = await validateFileUpload(file, FILE_PROFILES.invoiceScan)
    if (!validation.ok) {
      toast('error', t('common.error'), validation.error || 'Invalid file')
      e.target.value = ''
      return
    }
    setProcessing(true)
    setOcrResult(null)
    try {
      setOcrResult(await extractSupplierInvoice(file))
      setShowForm(true)
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.error'))
    } finally {
      setProcessing(false)
      e.target.value = ''
    }
  }

  const recentInvoices = invoices.slice(0, 10)

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('sections.purchases') }, { label: t('automation.title') }]} />
      <PageHeader title={t('automation.title')} subtitle={t('automation.subtitle')} />

      <Card className="mb-6">
        <div className="p-6">
          <div className="flex items-center gap-3 mb-4">
            <Sparkles className="w-5 h-5 text-[var(--color-primary)]" />
            <h3 className="text-sm font-semibold">{t('automation.uploadTitle')}</h3>
          </div>
          <div className="border-2 border-dashed border-[var(--color-border)] rounded-lg p-8 text-center">
            <Upload className="w-10 h-10 mx-auto text-[var(--color-text-secondary)] mb-3" />
            <p className="text-sm text-[var(--color-text-secondary)] mb-2">
              {t('automation.dragDropText')}
            </p>
            <p className="text-xs text-[var(--color-text-secondary)] mb-4">{t('automation.fileTypes')}</p>
            <label className="btn-primary text-sm px-4 py-2 rounded-lg cursor-pointer inline-flex items-center gap-2">
              <Upload className="w-4 h-4" /> {t('automation.browse')}
              <input type="file" accept=".pdf,.png,.jpg,.jpeg" className="hidden" onChange={handleFileUpload} />
            </label>
            {processing && (
              <div className="mt-4 flex items-center justify-center gap-2 text-sm text-[var(--color-primary)]">
                <div className="w-4 h-4 border-2 border-[var(--color-primary)] border-t-transparent rounded-full animate-spin" />
                {t('automation.ocrProcessing')}
              </div>
            )}
          </div>
        </div>
      </Card>

      <Card title={t('automation.recentInvoicesTitle')}>
        {loading ? (
          <SkeletonTable rows={5} cols={5} />
        ) : recentInvoices.length === 0 ? (
          <EmptyState icon={<FileText className="w-8 h-8" />} title={t('automation.noInvoices')} description={t('automation.noInvoicesDescription')} />
        ) : (
          <Table headers={[t('invoices.number'), t('invoices.supplier'), t('invoices.date'), t('invoices.amount'), t('invoices.status')]}>
            {recentInvoices.map((inv) => (
              <TableRow key={inv.id}>
                <TableCell className="font-mono text-xs">{inv.number}</TableCell>
                <TableCell className="text-sm">{suppliers.find((s) => s.id === inv.supplier_id)?.name || '—'}</TableCell>
                <TableCell className="text-xs">{formatDate(inv.date)}</TableCell>
                <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(inv.total))}</TableCell>
                <TableCell>
                  <Badge variant={inv.status === 'paid' ? 'success' : inv.status === 'overdue' ? 'danger' : 'warning'}>
                    {t(`automation.statuses.${inv.status}`) as string}
                  </Badge>
                </TableCell>
              </TableRow>
            ))}
          </Table>
        )}
      </Card>

      {showForm && ocrResult && (
        <OcrForm
          result={ocrResult}
          suppliers={suppliers}
          onClose={() => { setShowForm(false); setOcrResult(null) }}
          onSaved={() => { setShowForm(false); setOcrResult(null); load() }}
        />
      )}
    </div>
  )
}

function OcrForm({ result, suppliers, onClose, onSaved }: {
  result: OcrInvoiceResult; suppliers: Supplier[]; onClose: () => void; onSaved: () => void
}) {
  const { t } = useTranslation('purchases')
  const { t: tCommon } = useTranslation('common')
const [supplierId, setSupplierId] = useState(
  result.supplierId
  || suppliers.find((s) => result.supplierName && s.name.toLowerCase() === result.supplierName.toLowerCase())?.id
  || '')
const { toast } = useToast()
  const [number, setNumber] = useState(result.invoiceNumber || '')
  const [date, setDate] = useState(result.date || '')
  const [dueDate, setDueDate] = useState(result.dueDate || '')
  const [subtotal, setSubtotal] = useState(result.subtotal || 0)
  const [vatTotal, setVatTotal] = useState(result.vatTotal || 0)
  const total = Math.round((Number(subtotal) + Number(vatTotal)) * 100) / 100
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      await createPurchaseInvoice({
        number, supplier_id: supplierId || null,
        date, due_date: dueDate,
        subtotal, vat_total: vatTotal, total, amount_paid: 0, amount_due: total,
        status: 'received',
      } as any)
      onSaved()
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl overflow-hidden" style={{ width: '100%', maxWidth: '36rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <div className="flex items-center gap-2">
            <h2 className="text-lg font-semibold">{t('automation.ocrReviewTitle')}</h2>
          </div>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]" aria-label={tCommon('actions.close')} title={tCommon('actions.close')}><X className="w-5 h-5" aria-hidden="true" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div className="p-3 rounded-lg bg-[var(--color-warning)]/10 border border-[var(--color-warning)]/30 text-xs text-[var(--color-text-secondary)] flex items-center gap-2">
            <AlertCircle className="w-4 h-4 text-[var(--color-warning)] flex-shrink-0" />
            {t('automation.reviewWarning')}
          </div>
          <div>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('invoices.supplier')}</label>
            <select className="input" value={supplierId} onChange={(e) => setSupplierId(e.target.value)} required>
              <option value="">{tCommon('form.selectPlaceholder')}</option>
              {suppliers.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
            </select>
          </div>
          <Input label={t('automation.invoiceNumber')} required value={number} onChange={(e) => setNumber(e.target.value)} />
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('invoices.date')} type="date" required value={date} onChange={(e) => setDate(e.target.value)} />
            <Input label={t('automation.dueDate')} type="date" value={dueDate} onChange={(e) => setDueDate(e.target.value)} />
          </div>
          <div className="grid grid-cols-3 gap-4">
            <Input label={t('automation.subtotalAmount')} type="number" step="0.01" required value={subtotal} onChange={(e) => setSubtotal(Number(e.target.value))} />
            <Input label={t('automation.vat')} type="number" step="0.01" value={vatTotal} onChange={(e) => setVatTotal(Number(e.target.value))} />
            <Input label={t('automation.totalAmount')} type="number" value={total} readOnly />
          </div>
          {result.total > 0 && Math.abs(result.total - total) > 0.01 && (
            <p className="text-xs text-[var(--color-warning)]">{t('automation.totalMismatch', { total: result.total })}</p>
          )}
          <div className="flex justify-end gap-3 pt-2">
            <Button variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}>
              <CheckCircle2 className="w-4 h-4" /> {saving ? tCommon('actions.saving') : t('automation.validateAndCreate')}
            </Button>
          </div>
        </form>
      </div>
    </div>
  )
}
