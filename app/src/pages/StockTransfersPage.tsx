import { Fragment, useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Input, Select, Badge } from '@/components/ui'
import { errorMessage } from '@/lib/utils'
import {
  getStockTransfers, createStockTransfer, deleteStockTransfer,
  getStockTransferLines, createStockTransferLine,
  shipStockTransfer, receiveStockTransfer, getWarehouses, getProducts,
  type StockTransfer, type StockTransferLineRow,
} from '@/lib/queries/stock'
import { Plus, Trash2, X, Truck, ChevronDown, ChevronRight, ArrowRight } from 'lucide-react'
import type { Product, Warehouse } from '@/types'
import { useToast } from '@/lib/toast'
import { confirmSync } from '@/lib/confirm'

// STK-14 / E.2 : les transferts inter-dépôts. Les tables existaient depuis la 125
// sans écran ; la 652 les exécute (expédier sort du dépôt source, réceptionner
// fait entrer au dépôt destination).
export function StockTransfersPage() {
  const { t } = useTranslation('stock')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [transfers, setTransfers] = useState<StockTransfer[]>([])
  const [warehouses, setWarehouses] = useState<Warehouse[]>([])
  const [products, setProducts] = useState<Product[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [expanded, setExpanded] = useState<Set<string>>(new Set())
  const [lines, setLines] = useState<Record<string, StockTransferLineRow[]>>({})
  const [showLineForm, setShowLineForm] = useState<string | null>(null)

  const loadData = useCallback(async () => {
    try {
      const [trs, whs, prods] = await Promise.all([getStockTransfers(), getWarehouses(), getProducts()])
      setTransfers(trs || [])
      setWarehouses(whs || [])
      setProducts(prods || [])
    } catch (err) { console.error('Error:', err); toast('error', tCommon('toast.error'), errorMessage(err) || tCommon('toast.loadingError')) }
    finally { setLoading(false) }
  }, [tCommon, toast])

  useEffect(() => { loadData() }, [loadData])

  const whName = (id: string) => warehouses.find((w) => w.id === id)?.name ?? '—'

  async function refreshLines(id: string) {
    try { const lns = await getStockTransferLines(id); setLines((prev) => ({ ...prev, [id]: lns })) }
    catch (err) { toast('error', tCommon('toast.error'), errorMessage(err) || tCommon('toast.loadingError')) }
  }

  async function toggleExpand(id: string) {
    const next = new Set(expanded)
    if (next.has(id)) { next.delete(id) }
    else { next.add(id); if (!lines[id]) await refreshLines(id) }
    setExpanded(next)
  }

  async function handleShip(id: string) {
    if (!confirmSync(t('transfers.confirmShip'))) return
    try { await shipStockTransfer(id); await loadData(); if (expanded.has(id)) await refreshLines(id) }
    catch (err) { toast('error', tCommon('toast.error'), errorMessage(err) || tCommon('toast.error')) }
  }

  async function handleReceive(id: string) {
    if (!confirmSync(t('transfers.confirmReceive'))) return
    try { await receiveStockTransfer(id); await loadData(); if (expanded.has(id)) await refreshLines(id) }
    catch (err) { toast('error', tCommon('toast.error'), errorMessage(err) || tCommon('toast.error')) }
  }

  async function handleDelete(id: string) {
    if (!confirmSync(t('transfers.confirmDelete'))) return
    try { await deleteStockTransfer(id); await loadData() }
    catch (err) { toast('error', tCommon('toast.error'), errorMessage(err) || tCommon('toast.error')) }
  }

  const statusVariant = (s: StockTransfer['status']) =>
    s === 'received' ? 'success' : s === 'in_transit' ? 'warning' : s === 'cancelled' ? 'danger' : 'neutral'

  return (
    <div>
      <Breadcrumb items={[{ label: t('title'), path: '/stock' }, { label: t('transfers.title') }]} />
      <PageHeader title={t('transfers.title')} subtitle={`${transfers.length}`}
        action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('transfers.new')}</Button>} />

      {loading ? <SkeletonTable rows={4} cols={5} /> : transfers.length === 0 ? (
        <EmptyState icon={<Truck className="w-8 h-8" />} title={t('transfers.noTransfers')} description={t('transfers.noTransfersDescription')}
          action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('transfers.new')}</Button>} />
      ) : (
        <Card>
          <Table headers={[t('transfers.number'), t('transfers.from'), t('transfers.to'), t('transfers.status'), tCommon('common.actions')]}>
            {transfers.map((tr) => (
              <Fragment key={tr.id}>
                <TableRow>
                  <TableCell className="font-mono text-xs">
                    <div className="flex items-center gap-1">
                      <button onClick={() => toggleExpand(tr.id)} aria-label={tCommon(expanded.has(tr.id) ? 'actions.collapse' : 'actions.expand')} title={tCommon(expanded.has(tr.id) ? 'actions.collapse' : 'actions.expand')} className="p-0.5 rounded hover:bg-[var(--color-neutral-100)]">
                        {expanded.has(tr.id) ? <ChevronDown className="w-3.5 h-3.5" /> : <ChevronRight className="w-3.5 h-3.5" />}
                      </button>
                      {tr.transfer_number}
                    </div>
                  </TableCell>
                  <TableCell className="text-sm">{whName(tr.from_warehouse_id)}</TableCell>
                  <TableCell className="text-sm">
                    <span className="inline-flex items-center gap-1"><ArrowRight className="w-3 h-3 text-[var(--color-text-secondary)]" />{whName(tr.to_warehouse_id)}</span>
                  </TableCell>
                  <TableCell><Badge variant={statusVariant(tr.status)}>{t(`transfers.statuses.${tr.status}`)}</Badge></TableCell>
                  <TableCell>
                    <div className="flex gap-1">
                      {tr.status === 'pending' && (
                        <button onClick={() => handleShip(tr.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-primary)]" aria-label={t('transfers.ship')} title={t('transfers.ship')}><Truck className="w-4 h-4" aria-hidden="true" /></button>
                      )}
                      {tr.status === 'in_transit' && (
                        <button onClick={() => handleReceive(tr.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-success)]" aria-label={t('transfers.receive')} title={t('transfers.receive')}><ArrowRight className="w-4 h-4" aria-hidden="true" /></button>
                      )}
                      {tr.status !== 'received' && (
                        <button onClick={() => setShowLineForm(tr.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-primary)]" aria-label={tCommon('actions.add')} title={tCommon('actions.add')}><Plus className="w-4 h-4" aria-hidden="true" /></button>
                      )}
                      <button onClick={() => handleDelete(tr.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]" aria-label={tCommon('actions.delete')} title={tCommon('actions.delete')}><Trash2 className="w-4 h-4" aria-hidden="true" /></button>
                    </div>
                  </TableCell>
                </TableRow>
                {expanded.has(tr.id) && (
                  <tr><td colSpan={5} className="p-0">
                    <div className="px-8 py-3 bg-[var(--color-neutral-50)] border-y border-[var(--color-border)]">
                      {(lines[tr.id] || []).length === 0 ? (
                        <p className="text-xs text-[var(--color-text-secondary)]">{t('transfers.noLines')}</p>
                      ) : (
                        <Table headers={['#', t('transfers.product'), t('transfers.quantity')]}>
                          {(lines[tr.id] || []).map((line, i) => (
                            <TableRow key={line.id}>
                              <TableCell className="text-xs">{i + 1}</TableCell>
                              <TableCell className="text-sm">{line.products?.name || '—'}</TableCell>
                              <TableCell className="font-mono text-xs">{Number(line.quantity)}</TableCell>
                            </TableRow>
                          ))}
                        </Table>
                      )}
                    </div>
                  </td></tr>
                )}
              </Fragment>
            ))}
          </Table>
        </Card>
      )}

      {showForm && <TransferForm warehouses={warehouses} onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadData() }} />}
      {showLineForm && <TransferLineForm transferId={showLineForm} products={products} onClose={() => setShowLineForm(null)} onSaved={async () => { const id = showLineForm; setShowLineForm(null); await refreshLines(id) }} />}
    </div>
  )
}

function TransferForm({ warehouses, onClose, onSaved }: { warehouses: Warehouse[]; onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation('stock')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [number, setNumber] = useState(`TR-${Date.now().toString().slice(-6)}`)
  const [fromId, setFromId] = useState('')
  const [toId, setToId] = useState('')
  const [shipmentDate, setShipmentDate] = useState('')
  const [expectedDate, setExpectedDate] = useState('')
  const [notes, setNotes] = useState('')
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!fromId || !toId) { toast('error', tCommon('toast.error'), t('transfers.selectWarehouse')); return }
    if (fromId === toId) { toast('error', tCommon('toast.error'), t('transfers.sameWarehouse')); return }
    setSaving(true)
    try {
      await createStockTransfer({
        transfer_number: number, from_warehouse_id: fromId, to_warehouse_id: toId,
        shipment_date: shipmentDate || null, expected_receipt_date: expectedDate || null,
        actual_receipt_date: null, status: 'pending', notes: notes || null,
      })
      onSaved()
    } catch (err) { toast('error', tCommon('toast.error'), errorMessage(err) || tCommon('toast.error')) }
    finally { setSaving(false) }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl overflow-hidden" style={{ width: '100%', maxWidth: '34rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('transfers.new')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]" aria-label={tCommon('actions.close')} title={tCommon('actions.close')}><X className="w-5 h-5" aria-hidden="true" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <Input label={t('transfers.number')} required value={number} onChange={(e) => setNumber(e.target.value)} />
          <div className="grid grid-cols-2 gap-4">
            <Select label={t('transfers.from')} value={fromId} onChange={(e) => setFromId(e.target.value)} options={[{ value: '', label: t('transfers.selectWarehouse') }, ...warehouses.map((w) => ({ value: w.id, label: w.name }))]} />
            <Select label={t('transfers.to')} value={toId} onChange={(e) => setToId(e.target.value)} options={[{ value: '', label: t('transfers.selectWarehouse') }, ...warehouses.map((w) => ({ value: w.id, label: w.name }))]} />
          </div>
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('transfers.shipmentDate')} type="date" value={shipmentDate} onChange={(e) => setShipmentDate(e.target.value)} />
            <Input label={t('transfers.expectedDate')} type="date" value={expectedDate} onChange={(e) => setExpectedDate(e.target.value)} />
          </div>
          <Input label={t('transfers.notes')} value={notes} onChange={(e) => setNotes(e.target.value)} />
          <div className="flex justify-end gap-3 pt-2">
            <Button variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? tCommon('actions.saving') : tCommon('actions.create')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}

function TransferLineForm({ transferId, products, onClose, onSaved }: { transferId: string; products: Product[]; onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation('stock')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [productId, setProductId] = useState('')
  const [quantity, setQuantity] = useState(1)
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!productId) return
    setSaving(true)
    try {
      await createStockTransferLine({ transfer_id: transferId, product_id: productId, quantity, unit_cost: null })
      onSaved()
    } catch (err) { toast('error', tCommon('toast.error'), errorMessage(err) || tCommon('toast.error')) }
    finally { setSaving(false) }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl overflow-hidden" style={{ width: '100%', maxWidth: '30rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('transfers.addLine')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]" aria-label={tCommon('actions.close')} title={tCommon('actions.close')}><X className="w-5 h-5" aria-hidden="true" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('transfers.product')}</label>
            <select className="input" value={productId} onChange={(e) => setProductId(e.target.value)} required>
              <option value="">{t('transfers.selectProduct')}</option>
              {products.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
            </select>
          </div>
          <Input label={t('transfers.quantity')} type="number" step="0.01" required value={quantity} onChange={(e) => setQuantity(Number(e.target.value))} />
          <div className="flex justify-end gap-3 pt-2">
            <Button variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? tCommon('actions.saving') : tCommon('actions.add')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
