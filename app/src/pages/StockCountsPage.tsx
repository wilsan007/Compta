import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { errorMessage } from '@/lib/utils'
import {
  getStockCountCycles, createStockCountCycle, deleteStockCountCycle,
  getStockCountList, recordStockCount, getProducts, getWarehouses,
  type StockCountCycle, type StockCountDue,
} from '@/lib/queries/stock'
import { Plus, Trash2, X, ClipboardList } from 'lucide-react'
import { useToast } from '@/lib/toast'
import { confirmSync } from '@/lib/confirm'
import type { Product, Warehouse } from '@/types'

// STK-09 / E.3 : l'inventaire tournant. `stock_count_cycles` existait depuis la
// 125 sans moteur ; la 654 génère la liste des comptages dus et enregistre
// l'écart physique (mouvement valorisé).
export function StockCountsPage() {
  const { t } = useTranslation('stock')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [cycles, setCycles] = useState<StockCountCycle[]>([])
  const [due, setDue] = useState<StockCountDue[]>([])
  const [products, setProducts] = useState<Product[]>([])
  const [warehouses, setWarehouses] = useState<Warehouse[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [counting, setCounting] = useState<StockCountDue | null>(null)
  const [countedQty, setCountedQty] = useState(0)
  const [saving, setSaving] = useState(false)

  const loadData = useCallback(async () => {
    try {
      const [cc, du, prods, whs] = await Promise.all([
        getStockCountCycles(), getStockCountList(), getProducts(), getWarehouses(),
      ])
      setCycles(cc || []); setDue(du || []); setProducts(prods || []); setWarehouses(whs || [])
    } catch (err) { console.error('Error:', err); toast('error', tCommon('toast.error'), errorMessage(err) || tCommon('toast.loadingError')) }
    finally { setLoading(false) }
  }, [tCommon, toast])

  useEffect(() => { loadData() }, [loadData])

  const productName = (id: string) => products.find((p) => p.id === id)?.name ?? '—'
  const whName = (id: string | null) => (id ? (warehouses.find((w) => w.id === id)?.name ?? '—') : t('reorder.allWarehouses'))

  async function handleDeleteCycle(id: string) {
    if (!confirmSync(t('counts.confirmDeleteCycle'))) return
    try { await deleteStockCountCycle(id); await loadData() }
    catch (err) { toast('error', tCommon('toast.error'), errorMessage(err) || tCommon('toast.error')) }
  }

  function openCount(d: StockCountDue) {
    setCounting(d)
    setCountedQty(Number(d.current_stock))
  }

  async function handleRecord() {
    if (!counting) return
    setSaving(true)
    try {
      const variance = await recordStockCount(counting.cycle_id, countedQty)
      toast('success', t('counts.title'), `${t('counts.variance')} : ${variance}`)
      setCounting(null)
      await loadData()
    } catch (err) { toast('error', tCommon('toast.error'), errorMessage(err) || tCommon('toast.error')) }
    finally { setSaving(false) }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('title'), path: '/stock' }, { label: t('counts.title') }]} />
      <PageHeader title={t('counts.title')} subtitle={t('counts.subtitle')} />

      {loading ? <SkeletonTable rows={4} cols={5} /> : (
        <div className="space-y-6">
          <Card>
            <div className="p-4 border-b border-[var(--color-border)]"><h3 className="font-semibold">{t('counts.due')}</h3></div>
            {due.length === 0 ? (
              <EmptyState icon={<ClipboardList className="w-8 h-8" />} title={t('counts.noDue')} description={t('counts.noDueDescription')} />
            ) : (
              <Table headers={[t('reorder.product'), t('quantities.warehouse'), t('counts.abcClass'), t('counts.currentStock'), t('counts.nextCount'), tCommon('common.actions')]}>
                {due.map((d) => (
                  <TableRow key={d.cycle_id}>
                    <TableCell className="text-sm">{d.product_name}</TableCell>
                    <TableCell className="text-sm">{d.warehouse_name ?? t('reorder.allWarehouses')}</TableCell>
                    <TableCell className="text-xs">{d.abc_class ?? '—'}</TableCell>
                    <TableCell className="font-mono text-xs">{Number(d.current_stock)}</TableCell>
                    <TableCell className="text-xs">{d.next_count_date ?? '—'}</TableCell>
                    <TableCell><Button onClick={() => openCount(d)}>{t('counts.count')}</Button></TableCell>
                  </TableRow>
                ))}
              </Table>
            )}
          </Card>

          <Card>
            <div className="p-4 border-b border-[var(--color-border)] flex items-center justify-between">
              <h3 className="font-semibold">{t('counts.cycles')}</h3>
              <Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('counts.newCycle')}</Button>
            </div>
            {cycles.length === 0 ? (
              <EmptyState icon={<ClipboardList className="w-8 h-8" />} title={t('counts.noCycles')} description={t('counts.noCyclesDescription')} />
            ) : (
              <Table headers={[t('reorder.product'), t('quantities.warehouse'), t('counts.abcClass'), t('counts.frequency'), t('counts.nextCount'), tCommon('common.actions')]}>
                {cycles.map((c) => (
                  <TableRow key={c.id}>
                    <TableCell className="text-sm">{productName(c.product_id)}</TableCell>
                    <TableCell className="text-sm">{whName(c.warehouse_id)}</TableCell>
                    <TableCell className="text-xs">{c.abc_class ?? '—'}</TableCell>
                    <TableCell className="font-mono text-xs">{c.frequency_days} j</TableCell>
                    <TableCell className="text-xs">{c.next_count_date ?? '—'}</TableCell>
                    <TableCell>
                      <button onClick={() => handleDeleteCycle(c.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]" aria-label={tCommon('actions.delete')} title={tCommon('actions.delete')}><Trash2 className="w-4 h-4" aria-hidden="true" /></button>
                    </TableCell>
                  </TableRow>
                ))}
              </Table>
            )}
          </Card>
        </div>
      )}

      {showForm && <CountCycleForm products={products} warehouses={warehouses} onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadData() }} />}

      {counting && (
        <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
          <div className="card shadow-2xl overflow-hidden" style={{ width: '100%', maxWidth: '28rem' }}>
            <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
              <h2 className="text-lg font-semibold">{t('counts.count')} — {counting.product_name}</h2>
              <button onClick={() => setCounting(null)} className="p-1 rounded hover:bg-[var(--color-neutral-100)]" aria-label={tCommon('actions.close')} title={tCommon('actions.close')}><X className="w-5 h-5" aria-hidden="true" /></button>
            </div>
            <div className="p-6 space-y-4">
              <p className="text-sm text-[var(--color-text-secondary)]">{t('counts.currentStock')} : <span className="font-mono">{Number(counting.current_stock)}</span></p>
              <Input label={t('counts.countedQty')} type="number" step="0.01" value={countedQty} onChange={(e) => setCountedQty(Number(e.target.value))} />
              <div className="flex justify-end gap-3 pt-2">
                <Button variant="secondary" onClick={() => setCounting(null)}>{tCommon('actions.cancel')}</Button>
                <Button onClick={handleRecord} disabled={saving}>{saving ? tCommon('actions.saving') : tCommon('actions.confirm')}</Button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}

function CountCycleForm({ products, warehouses, onClose, onSaved }: { products: Product[]; warehouses: Warehouse[]; onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation('stock')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [productId, setProductId] = useState('')
  const [warehouseId, setWarehouseId] = useState('')
  const [abcClass, setAbcClass] = useState('C')
  const [frequency, setFrequency] = useState(90)
  const [nextDate, setNextDate] = useState('')
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!productId) { toast('error', tCommon('toast.error'), t('reorder.selectProduct')); return }
    setSaving(true)
    try {
      await createStockCountCycle({
        product_id: productId, warehouse_id: warehouseId || null, abc_class: abcClass,
        frequency_days: frequency, next_count_date: nextDate || null, last_count_date: null, is_active: true,
      })
      onSaved()
    } catch (err) { toast('error', tCommon('toast.error'), errorMessage(err) || tCommon('toast.error')) }
    finally { setSaving(false) }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl overflow-hidden" style={{ width: '100%', maxWidth: '32rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('counts.newCycle')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]" aria-label={tCommon('actions.close')} title={tCommon('actions.close')}><X className="w-5 h-5" aria-hidden="true" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('reorder.product')}</label>
            <select className="input" value={productId} onChange={(e) => setProductId(e.target.value)} required>
              <option value="">{t('reorder.selectProduct')}</option>
              {products.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
            </select>
          </div>
          <Select label={t('quantities.warehouse')} value={warehouseId} onChange={(e) => setWarehouseId(e.target.value)} options={[{ value: '', label: t('reorder.allWarehouses') }, ...warehouses.map((w) => ({ value: w.id, label: w.name }))]} />
          <div className="grid grid-cols-3 gap-4">
            <Select label={t('counts.abcClass')} value={abcClass} onChange={(e) => setAbcClass(e.target.value)} options={[{ value: 'A', label: 'A' }, { value: 'B', label: 'B' }, { value: 'C', label: 'C' }]} />
            <Input label={t('counts.frequency')} type="number" value={frequency} onChange={(e) => setFrequency(Number(e.target.value))} />
            <Input label={t('counts.nextCount')} type="date" value={nextDate} onChange={(e) => setNextDate(e.target.value)} />
          </div>
          <div className="flex justify-end gap-3 pt-2">
            <Button variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? tCommon('actions.saving') : tCommon('actions.create')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
