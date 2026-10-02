import { useEffect, useState, useCallback } from 'react'
import { Card, PageHeader, Button, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Input, Select, Badge } from '@/components/ui'
import { errorMessage, formatDate } from '@/lib/utils'
import { getGoodsReceipts, createGoodsReceiptFromOrder, updateGoodsReceipt, deleteGoodsReceipt } from '@/lib/queries/misc'
import { getStockPostedReferences, getWarehouses } from '@/lib/queries/stock'
import { getSuppliers } from '@/lib/queries/partners'
import { getPurchaseOrders } from '@/lib/queries/purchases'
import { Plus, Trash2, X, PackageCheck } from 'lucide-react'
import type { GoodsReceipt, Supplier, PurchaseOrder, Warehouse } from '@/types'
import { useToast } from '@/lib/toast'
import { useTranslation } from 'react-i18next'
import { confirmSync } from '@/lib/confirm'
import { nextDocumentNumber } from '@/lib/queries/core'

export function GoodsReceiptPage() {
  const { t } = useTranslation('purchases')
  const { t: tCommon } = useTranslation('common')
  const { t: tNav } = useTranslation('nav')
  const { toast } = useToast()
const [receipts, setReceipts] = useState<GoodsReceipt[]>([])
  const [suppliers, setSuppliers] = useState<Supplier[]>([])
  const [warehouses, setWarehouses] = useState<Warehouse[]>([])
  const [posted, setPosted] = useState<Set<string>>(new Set())
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [statusFilter, setStatusFilter] = useState('')

  const loadData = useCallback(async () => {
    try {
      const [rcpts, sups, whs] = await Promise.all([getGoodsReceipts(statusFilter || undefined), getSuppliers(), getWarehouses()])
      setReceipts(rcpts || [])
      setSuppliers(sups || [])
      setWarehouses((whs || []).filter((w) => w.active !== false))
      // « Entré » se lit sur les mouvements de stock réels, pas sur le statut.
      setPosted(await getStockPostedReferences('goods_receipt', (rcpts || []).map((r) => r.id)))
    } catch (err) { console.error('Error:', err); toast('error', tCommon('toast.error'), errorMessage(err) || tCommon('toast.loadingError')) }
    finally { setLoading(false) }
  }, [statusFilter, toast, tCommon])

  useEffect(() => { loadData() }, [loadData])

  async function handleStatusChange(id: string, status: string) {
  try { await updateGoodsReceipt(id, { status: status as any }); await loadData() }
    catch (err) { toast('error', tCommon('common.error'), errorMessage(err) || tCommon('common.error')) }
  }

  async function handleDelete(id: string) {
    if (!confirmSync(t('goodsReceipts.deleteConfirm'))) return
    try { await deleteGoodsReceipt(id); await loadData() }
    catch (err) { toast('error', tCommon('common.error'), errorMessage(err) || tCommon('common.error')) }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('items.purchases') }, { label: t('goodsReceipts.title') }]} />
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
          <Table headers={[t('goodsReceipts.number'), t('goodsReceipts.supplier'), t('goodsReceipts.date'), t('goodsReceipts.status'), t('goodsReceipts.stock'), t('goodsReceipts.actions')]}>
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
                  <TableCell>{posted.has(r.id) ? <Badge variant="success">{t('goodsReceipts.stockIn')}</Badge> : <Badge variant="neutral">{t('goodsReceipts.stockPending')}</Badge>}</TableCell>
                  <TableCell>
                    <button onClick={() => handleDelete(r.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]" aria-label={tCommon('actions.delete')} title={tCommon('actions.delete')}>
                      <Trash2 className="w-4 h-4" aria-hidden="true" /></button>
                  </TableCell>
                </TableRow>
              )
            })}
          </Table>
        </Card>
      )}

      {showForm && <GRForm suppliers={suppliers} warehouses={warehouses} onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadData() }} />}
    </div>
  )
}

function GRForm({ suppliers, warehouses, onClose, onSaved }: { suppliers: Supplier[]; warehouses: Warehouse[]; onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation('purchases')
  const { t: tCommon } = useTranslation('common')
  const [supplierId, setSupplierId] = useState('')
  const [purchaseOrderId, setPurchaseOrderId] = useState('')
  const [purchaseOrders, setPurchaseOrders] = useState<PurchaseOrder[]>([])
  const { toast } = useToast()
  const [receiptDate, setReceiptDate] = useState(new Date().toISOString().split('T')[0])
  const [warehouseId, setWarehouseId] = useState(warehouses[0]?.id ?? '')
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      // C9 (280) : la réception naît de la commande confirmée, avec une ligne par
      // ligne de commande au reste à recevoir ; « Reçue » fera entrer le stock.
      const number = await nextDocumentNumber('BR')
      await createGoodsReceiptFromOrder(purchaseOrderId, { number, receipt_date: receiptDate, warehouse_id: warehouseId || null })
      onSaved()
    } catch (err) { toast('error', tCommon('common.error'), errorMessage(err) || tCommon('common.error')) }
    finally { setSaving(false) }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl overflow-hidden" style={{ width: '100%', maxWidth: '32rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('goodsReceipts.new')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]" aria-label={tCommon('actions.close')} title={tCommon('actions.close')}><X className="w-5 h-5" aria-hidden="true" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('goodsReceipts.supplier')}</label>
            <select className="input" value={supplierId} onChange={async (e) => { setSupplierId(e.target.value); setPurchaseOrderId(''); setPurchaseOrders([]); if (e.target.value) { try { const [part, conf] = await Promise.all([getPurchaseOrders('partial'), getPurchaseOrders('confirmed')]); setPurchaseOrders([...(conf || []), ...(part || [])].filter((o) => o.supplier_id === e.target.value)) } catch { /* ignore */ } } }} required>
              <option value="">{tCommon('form.selectPlaceholder')}</option>
              {suppliers.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
            </select>
          </div>
          <div>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('goodsReceipts.purchaseOrder')}</label>
            <select className="input" value={purchaseOrderId} onChange={(e) => setPurchaseOrderId(e.target.value)} disabled={!supplierId} required>
              <option value="">{tCommon('form.selectPlaceholder')}</option>
              {purchaseOrders.map((o) => <option key={o.id} value={o.id}>{o.number}</option>)}
            </select>
          </div>
          <Input label={t('goodsReceipts.receiptDate')} type="date" required value={receiptDate} onChange={(e) => setReceiptDate(e.target.value)} />
          <Select label={t('goodsReceipts.warehouse')} required value={warehouseId} onChange={(e) => setWarehouseId(e.target.value)} options={[
            { value: '', label: tCommon('form.selectPlaceholder') },
            ...warehouses.map((w) => ({ value: w.id, label: w.name })),
          ]} />
          <p className="text-xs text-[var(--color-text-secondary)]">{t('goodsReceipts.fromOrderHint')}</p>
          <div className="flex justify-end gap-3 pt-2">
            <Button variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? tCommon('actions.saving') : tCommon('actions.save')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
