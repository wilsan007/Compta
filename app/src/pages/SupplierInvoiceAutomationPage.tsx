import { useEffect, useState } from 'react'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Input } from '@/components/ui'
import { formatCurrency, formatDate } from '@/lib/utils'
import { getPurchaseInvoices, getSuppliers, createPurchaseInvoice } from '@/lib/queries'
import { Upload, FileText, CheckCircle2, X, Sparkles, AlertCircle } from 'lucide-react'
import type { PurchaseInvoice, Supplier } from '@/types'
import { useToast } from '@/lib/toast'
import { useTranslation } from 'react-i18next'

export function SupplierInvoiceAutomationPage() {
  const { t } = useTranslation('purchases')
  const { t: tNav } = useTranslation('nav')
const [invoices, setInvoices] = useState<PurchaseInvoice[]>([])
  const [suppliers, setSuppliers] = useState<Supplier[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [ocrResult, setOcrResult] = useState<any>(null)
  const [processing, setProcessing] = useState(false)

  useEffect(() => { load() }, [])

  async function load() {
    try {
      const [inv, sup] = await Promise.all([getPurchaseInvoices(), getSuppliers()])
      setInvoices(inv || [])
      setSuppliers(sup || [])
    } catch (err) {
      console.error('Error loading data:', err)
    } finally {
      setLoading(false)
    }
  }

  function handleFileUpload(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0]
    if (!file) return
    setProcessing(true)
    setOcrResult(null)

    setTimeout(() => {
      const simulated = {
        supplierName: '',
        invoiceNumber: `FACT-${String(Date.now()).slice(-6)}`,
        date: new Date().toISOString().split('T')[0],
        dueDate: new Date(Date.now() + 30 * 86400000).toISOString().split('T')[0],
        total: 0,
        lines: [
          { description: 'Article 1', quantity: 1, unitPrice: 0, total: 0 },
        ],
        confidence: 0,
      }
      setOcrResult(simulated)
      setProcessing(false)
      setShowForm(true)
    }, 1500)
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
  result: any; suppliers: Supplier[]; onClose: () => void; onSaved: () => void
}) {
  const { t } = useTranslation('purchases')
  const { t: tCommon } = useTranslation('common')
const [supplierId, setSupplierId] = useState('')
const { toast } = useToast()
  const [number, setNumber] = useState(result.invoiceNumber || '')
  const [date, setDate] = useState(result.date || '')
  const [dueDate, setDueDate] = useState(result.dueDate || '')
  const [total, setTotal] = useState(result.total || 0)
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      await createPurchaseInvoice({
        number, supplier_id: supplierId || null,
        date, due_date: dueDate,
        subtotal: total, vat: 0, total,
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
            <Badge variant={result.confidence > 80 ? 'success' : 'warning'}>
              <AlertCircle className="w-3 h-3 mr-1" /> {t('automation.confidenceLevel', { confidence: result.confidence })}
            </Badge>
          </div>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
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
          <Input label={t('automation.totalAmount')} type="number" step="0.01" required value={total} onChange={(e) => setTotal(Number(e.target.value))} />
          <div className="flex justify-end gap-3 pt-2">
            <Button variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}>
              <CheckCircle2 className="w-4 h-4" /> {saving ? '...' : t('automation.validateAndCreate')}
            </Button>
          </div>
        </form>
      </div>
    </div>
  )
}
