import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { formatDate } from '@/lib/utils'
import { getManufacturingOrders, createManufacturingOrder, updateManufacturingOrder, deleteManufacturingOrder } from '@/lib/queries/production'
import { getBOMs, getWarehouses, getRoutings } from '@/lib/queries/stock'
import { calculateProductionCost } from '@/lib/queries/businessFunctions'
import { Plus, Trash2, X, Factory, ExternalLink } from 'lucide-react'
import { Link } from 'react-router-dom'
import type { ManufacturingOrder, BOM, Warehouse, Routing } from '@/types'
import { useToast } from '@/lib/toast'
import { Badge } from '@/components/ui'
import { confirmSync } from '@/lib/confirm'
import { nextDocumentNumber } from '@/lib/queries/core'

const originVariants: Record<string, 'neutral' | 'success' | 'warning'> = { manual: 'neutral', mrp: 'success', sub_level: 'warning' }

export function ManufacturingOrdersPage() {
  const { t } = useTranslation('production')
  const { toast } = useToast()
  const { t: tCommon } = useTranslation("common")
const [orders, setOrders] = useState<ManufacturingOrder[]>([])
  const [boms, setBOMs] = useState<BOM[]>([])
  const [warehouses, setWarehouses] = useState<Warehouse[]>([])
  const [routings, setRoutings] = useState<Routing[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [statusFilter, setStatusFilter] = useState('')

  const loadData = useCallback(async () => {
    try {
      const [ords, bs, whs, rts] = await Promise.all([getManufacturingOrders(statusFilter || undefined), getBOMs(), getWarehouses(), getRoutings()])
      setOrders(ords || [])
      setBOMs(bs || [])
      setWarehouses(whs || [])
      setRoutings(rts || [])
    } catch (err: any) { console.error('Error:', err); toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadingError')) }
    finally { setLoading(false) }
  }, [statusFilter, tCommon, toast])

  useEffect(() => { loadData() }, [loadData])

  async function handleStatusChange(id: string, status: string) {
  try { await updateManufacturingOrder(id, { status: status as any }); await loadData() }
    catch (err: any) { toast('error', t('common.error'), err.message || t('common.error')) }
  }

  async function handleDelete(id: string) {
    if (!confirmSync(t('manufacturing.confirmDelete'))) return
    try { await deleteManufacturingOrder(id); await loadData() }
    catch (err: any) { toast('error', t('common.error'), err.message || t('common.error')) }
  }

  async function handleProductionCost(id: string) {
    try {
      const res = await calculateProductionCost(id)
      toast('success', t('manufacturing.title'), `${res?.total_cost ?? res} €`)
    } catch (err: any) { toast('error', t('common.error'), err.message || t('common.error')) }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('title'), path: '/production' }, { label: t('manufacturing.title') }]} />
      <PageHeader title={t('manufacturing.title')} subtitle={t('manufacturing.count', { count: orders.length })}
        action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('manufacturing.new')}</Button>} />

      <div className="flex gap-3 mb-4 items-end">
        <div className="w-48">
          <Select label={t('manufacturing.status')} value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)} options={[
            { value: '', label: t('common:common.all') }, { value: 'planned', label: t('manufacturing.statuses.planned') }, { value: 'in_progress', label: t('manufacturing.statuses.in_progress') },
            { value: 'completed', label: t('manufacturing.statuses.completed') }, { value: 'cancelled', label: t('manufacturing.statuses.cancelled') },
          ]} />
        </div>
      </div>

      {loading ? <SkeletonTable rows={4} cols={6} /> : orders.length === 0 ? (
        <EmptyState icon={<Factory className="w-8 h-8" />} title={t('manufacturing.noOrders')} description={t('manufacturing.noOrdersDescription')}
          action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('manufacturing.new')}</Button>} />
      ) : (
        <Card>
          <Table headers={[t('manufacturing.number'), t('manufacturing.bom'), t('manufacturing.quantity'), t('manufacturing.origin'), t('manufacturing.startDate'), t('manufacturing.endDate'), t('manufacturing.status'), 'Stock', t('common.actions')]}>
            {orders.map((o) => {
              const bom = boms.find((b) => b.id === o.bom_id)
              return (
                <TableRow key={o.id}>
                  <TableCell className="font-mono text-xs">
                    <Link to={`/production/of/${o.id}`} className="text-[var(--color-primary)] hover:underline inline-flex items-center gap-1">
                      {o.number} <ExternalLink className="w-3 h-3" />
                    </Link>
                  </TableCell>
                  <TableCell className="text-sm">{bom?.name || '—'}</TableCell>
                  <TableCell className="font-mono text-xs">{Number(o.quantity)}</TableCell>
                  <TableCell><Badge variant={originVariants[(o as any).origin] || 'neutral'}>{t('manufacturing.origins.' + ((o as any).origin || 'manual'))}</Badge></TableCell>
                  <TableCell className="text-xs">{o.start_date ? formatDate(o.start_date) : '—'}</TableCell>
                  <TableCell className="text-xs">{o.end_date ? formatDate(o.end_date) : '—'}</TableCell>
                  <TableCell>
                    <select value={o.status} onChange={(e) => handleStatusChange(o.id, e.target.value)}
                      className="text-xs border border-[var(--color-border)] rounded px-2 py-1 bg-[var(--color-surface)]">
                      {['planned', 'in_progress', 'completed', 'cancelled'].map((k) => <option key={k} value={k}>{t('manufacturing.statuses.' + k)}</option>)}
                    </select>
                  </TableCell>
                  <TableCell>{(o as any).stock_movement_id || (o as any).stock_created || o.status === 'completed' ? <Badge variant="success">Généré</Badge> : <Badge variant="neutral">En attente</Badge>}</TableCell>
                  <TableCell>
                    <div className="flex gap-1">
                      <button onClick={() => handleProductionCost(o.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-primary)]" title="Calculer le coût de production">
                        <Factory className="w-4 h-4" />
                      </button>
                      <button onClick={() => handleDelete(o.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]" aria-label={tCommon('actions.delete')} title={tCommon('actions.delete')}>
                        <Trash2 className="w-4 h-4" aria-hidden="true" /></button>
                    </div>
                  </TableCell>
                </TableRow>
              )
            })}
          </Table>
        </Card>
      )}

      {showForm && <OFForm boms={boms} warehouses={warehouses} routings={routings} onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadData() }} />}
    </div>
  )
}

function OFForm({ boms, warehouses, routings, onClose, onSaved }: { boms: BOM[]; warehouses: Warehouse[]; routings: Routing[]; onClose: () => void; onSaved: () => void }) {
  const [bomId, setBomId] = useState('')
  const { t } = useTranslation('production')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [quantity, setQuantity] = useState(1)
  const [startDate, setStartDate] = useState('')
  const [endDate, setEndDate] = useState('')
  const [warehouseId, setWarehouseId] = useState('')
  const [routingId, setRoutingId] = useState('')
  const [notes, setNotes] = useState('')
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      const number = await nextDocumentNumber('OF')
      await createManufacturingOrder({ number, bom_id: bomId || null, product_id: null, quantity, status: 'planned', start_date: startDate || null, end_date: endDate || null, warehouse_id: warehouseId || null, routing_id: routingId || null, notes: notes || null } as any)
      onSaved()
    } catch (err: any) { toast('error', t('common.error'), err.message || t('common.error')) }
    finally { setSaving(false) }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl overflow-hidden" style={{ width: '100%', maxWidth: '32rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('manufacturing.create')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]" aria-label={tCommon('actions.close')} title={tCommon('actions.close')}><X className="w-5 h-5" aria-hidden="true" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('manufacturing.bom')}</label>
            <select className="input" value={bomId} onChange={(e) => setBomId(e.target.value)} required>
              <option value="">{t('bom.selectProduct')}</option>
              {boms.map((b) => <option key={b.id} value={b.id}>{b.code} — {b.name}{(b as any).bom_type === 'amalgam' ? ' (' + t('bom.amalgam') + ')' : ''}</option>)}
            </select>
          </div>
          <Input label={t('manufacturing.quantity')} type="number" step="0.01" required value={quantity} onChange={(e) => setQuantity(Number(e.target.value))} />
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('manufacturing.startDate')} type="date" value={startDate} onChange={(e) => setStartDate(e.target.value)} />
            <Input label={t('manufacturing.endDate')} type="date" value={endDate} onChange={(e) => setEndDate(e.target.value)} />
          </div>
          <div>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('manufacturing.warehouse')}</label>
            <select className="input" value={warehouseId} onChange={(e) => setWarehouseId(e.target.value)}>
              <option value="">{t('manufacturing.selectWarehouse')}</option>
              {warehouses.map((w) => <option key={w.id} value={w.id}>{w.name}</option>)}
            </select>
          </div>
          <Input label={t('common.description')} value={notes} onChange={(e) => setNotes(e.target.value)} />
          <div>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('manufacturing.routing')}</label>
            <select className="input" value={routingId} onChange={(e) => setRoutingId(e.target.value)}>
              <option value="">{t('manufacturing.selectRouting')}</option>
              {routings.map((r) => <option key={r.id} value={r.id}>{r.code} — {r.name}</option>)}
            </select>
          </div>
          <div className="flex justify-end gap-3 pt-2">
            <Button variant="secondary" onClick={onClose}>{t('common.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? tCommon('actions.saving') : t('common.create')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
