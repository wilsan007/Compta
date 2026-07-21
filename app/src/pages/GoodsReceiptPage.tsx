import { useEffect, useState, useCallback } from 'react'
import { Card, PageHeader, Button, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { formatDate } from '@/lib/utils'
import { getGoodsReceipts, createGoodsReceipt, updateGoodsReceipt, deleteGoodsReceipt, getSuppliers } from '@/lib/queries'
import { Plus, Trash2, X, PackageCheck } from 'lucide-react'
import type { GoodsReceipt, Supplier } from '@/types'
import { useToast } from '@/lib/toast'
import { useTranslation } from 'react-i18next'

export function GoodsReceiptPage() {
  const { t } = useTranslation('purchases')
  const { t: tCommon } = useTranslation('common')
  const { t: tNav } = useTranslation('nav')
  const { toast } = useToast()
const [receipts, setReceipts] = useState<GoodsReceipt[]>([])
  const [suppliers, setSuppliers] = useState<Supplier[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [statusFilter, setStatusFilter] = useState('')

  const loadData = useCallback(async () => {
    try {
      const [rcpts, sups] = await Promise.all([getGoodsReceipts(statusFilter || undefined), getSuppliers()])
      setReceipts(rcpts || [])
      setSuppliers(sups || [])
    } catch (err) { console.error('Error:', err) }
    finally { setLoading(false) }
  }, [statusFilter])

  useEffect(() => { loadData() }, [loadData])

  async function handleStatusChange(id: string, status: string) {
  try { await updateGoodsReceipt(id, { status: status as any }); await loadData() }
    catch (err: any) { toast('error', tCommon('common.error'), err.message || tCommon('common.error')) }
  }

  async function handleDelete(id: string) {
    if (!window.confirm(t('goodsReceipts.deleteConfirm'))) return
    try { await deleteGoodsReceipt(id); await loadData() }
    catch (err: any) { toast('error', tCommon('common.error'), err.message || tCommon('common.error')) }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('sections.purchases') }, { label: t('goodsReceipts.title') }]} />
      <PageHeader title={t('goodsReceipts.title')} subtitle={`${receipts.length} ${t('goodsReceipts.title').toLowerCase()}`}
        action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('goodsReceipts.new')}</Button>} />

      <div className="flex gap-3 mb-4 items-end">
        <div className="w-48">
          <Select label={t('goodsReceipts.status')} value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)} options={[
            { value: '', label: tCommon('common.all') }, { value: 'pending', label: t('goodsReceipts.statuses.pending') }, { value: 'received', label: t('goodsReceipts.statuses.received') },
            { value: 'partial', label: t('goodsReceipts.statuses.partial') }, { value: 'cancelled', label: t('goodsReceipts.statuses.cancelled') },
          ]} />
        </div>
        <Button variant="secondary" onClick={loadData}>{t('goodsReceipts.refresh')}</Button>
      </div>

      {loading ? <SkeletonTable rows={6} cols={5} /> : receipts.length === 0 ? (
        <EmptyState icon={<PackageCheck className="w-8 h-8" />} title={t('goodsReceipts.noGoodsReceipts')} description={t('goodsReceipts.noGoodsReceiptsDescription')}
          action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('goodsReceipts.new')}</Button>} />
      ) : (
        <Card>
          <Table headers={[t('goodsReceipts.number'), t('goodsReceipts.supplier'), t('goodsReceipts.date'), t('goodsReceipts.status'), t('goodsReceipts.actions')]}>
            {receipts.map((r) => {
              const sup = suppliers.find((s) => s.id === r.supplier_id)
              return (
                <TableRow key={r.id}>
                  <TableCell className="font-mono text-xs">{r.number}</TableCell>
                  <TableCell className="text-sm">{sup?.name || '—'}</TableCell>
                  <TableCell className="text-xs">{formatDate(r.receipt_date)}</TableCell>
                  <TableCell>
                    <select value={r.status} onChange={(e) => handleStatusChange(r.id, e.target.value)}
                      className="text-xs border border-[var(--color-border)] rounded px-2 py-1 bg-[var(--color-surface)]">
                      {['pending', 'received', 'partial', 'cancelled'].map((k) => <option key={k} value={k}>{t(`goodsReceipts.statuses.${k}`) as string}</option>)}
                    </select>
                  </TableCell>
                  <TableCell>
                    <button onClick={() => handleDelete(r.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]">
                      <Trash2 className="w-4 h-4" />
                    </button>
                  </TableCell>
                </TableRow>
              )
            })}
          </Table>
        </Card>
      )}

      {showForm && <GRForm suppliers={suppliers} onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadData() }} />}
    </div>
  )
}

function GRForm({ suppliers, onClose, onSaved }: { suppliers: Supplier[]; onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation('purchases')
  const { t: tCommon } = useTranslation('common')
  const [supplierId, setSupplierId] = useState('')
  const { toast } = useToast()
  const [receiptDate, setReceiptDate] = useState(new Date().toISOString().split('T')[0])
  const [notes, setNotes] = useState('')
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      const number = `BR-${new Date().getFullYear()}-${String(Date.now()).slice(-6)}`
      await createGoodsReceipt({ number, supplier_id: supplierId || null, purchase_order_id: null, receipt_date: receiptDate, status: 'pending', notes: notes || null } as any)
      onSaved()
    } catch (err: any) { toast('error', tCommon('common.error'), err.message || tCommon('common.error')) }
    finally { setSaving(false) }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl overflow-hidden" style={{ width: '100%', maxWidth: '32rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('goodsReceipts.new')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('goodsReceipts.supplier')}</label>
            <select className="input" value={supplierId} onChange={(e) => setSupplierId(e.target.value)} required>
              <option value="">{tCommon('form.selectPlaceholder')}</option>
              {suppliers.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
            </select>
          </div>
          <Input label={t('goodsReceipts.receiptDate')} type="date" required value={receiptDate} onChange={(e) => setReceiptDate(e.target.value)} />
          <Input label={t('orders.notes')} value={notes} onChange={(e) => setNotes(e.target.value)} />
          <div className="flex justify-end gap-3 pt-2">
            <Button variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? '...' : tCommon('actions.save')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
