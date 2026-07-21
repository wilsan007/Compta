import { useState, useEffect, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Plus, Trash2, Send, Truck, PackageCheck, Eye } from 'lucide-react'
import { Card, Button, Input, Select, Table, TableRow, TableCell, EmptyState, PageHeader, Breadcrumb, SkeletonTable, Badge } from '@/components/ui'
import { useToast } from '@/lib/toast'
import {
  getSTOrders, createSTOrder, deleteSTOrder, updateSTOrder,
  getSTShipments, deleteSTShipment,
  getSTReceipts, deleteSTReceipt,
  getSTSupervisorData,
  getSuppliers, getProducts, getManufacturingOrders,
} from '@/lib/queries'
import { formatDate, formatCurrency } from '@/lib/utils'
import type { Supplier, Product } from '@/types'

export function SubcontractingOrdersPage() {
  const { toast } = useToast()
  const { t } = useTranslation('production')
  const { t: tCommon } = useTranslation('common')
  const [orders, setOrders] = useState<any[]>([])
  const [suppliers, setSuppliers] = useState<Supplier[]>([])
  const [products, setProducts] = useState<Product[]>([])
  const [mos, setMOs] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)

  const loadData = useCallback(async () => {
    try {
      const [ords, sups, prods, moList] = await Promise.all([getSTOrders(), getSuppliers(), getProducts(), getManufacturingOrders()])
      setOrders(ords || [])
      setSuppliers(sups || [])
      setProducts(prods || [])
      setMOs(moList || [])
    } catch (err) { console.error('Error:', err) }
    finally { setLoading(false) }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  async function handleDelete(id: string) {
    if (!window.confirm(tCommon('form.confirmDelete'))) return
    try { await deleteSTOrder(id); await loadData() }
    catch (err: any) { toast('error', tCommon('toast.error'), err.message) }
  }

  async function handleStatusChange(id: string, status: string) {
    try { await updateSTOrder(id, { status: status as any }); await loadData() }
    catch (err: any) { toast('error', tCommon('toast.error'), err.message) }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('subcontracting.title'), path: '/production/subcontracting/orders' }, { label: t('subcontracting.ordersLabel') }]} />
      <PageHeader title={t('subcontracting.ordersTitle')} subtitle={`${orders.length} ${t('subcontracting.ordersCount')}`}
        action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('subcontracting.newOrder')}</Button>} />

      {loading ? <SkeletonTable rows={4} cols={7} /> : orders.length === 0 ? (
        <EmptyState icon={<Send className="w-8 h-8" />} title={t('subcontracting.noOrders')} description={t('subcontracting.noOrdersDescription')}
          action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('subcontracting.newOrder')}</Button>} />
      ) : (
        <Card>
          <Table headers={[t('subcontracting.number'), t('subcontracting.supplier'), t('subcontracting.product'), t('subcontracting.quantity'), t('subcontracting.totalPrice'), tCommon('common.date'), tCommon('common.status'), tCommon('table.actions')]}>
            {orders.map((o) => (
              <TableRow key={o.id}>
                <TableCell className="font-mono text-xs">{o.number}</TableCell>
                <TableCell className="text-sm">{o.suppliers?.name || '—'}</TableCell>
                <TableCell className="text-sm">{o.products?.name || '—'}</TableCell>
                <TableCell className="font-mono text-xs">{Number(o.quantity)} {o.unit}</TableCell>
                <TableCell className="font-mono text-xs">{formatCurrency(Number(o.total_price))}</TableCell>
                <TableCell className="text-xs">{formatDate(o.order_date)}</TableCell>
                <TableCell>
                  <select value={o.status} onChange={(e) => handleStatusChange(o.id, e.target.value)}
                    className="text-xs border border-[var(--color-border)] rounded px-2 py-1 bg-[var(--color-surface)]">
                    {['draft', 'sent', 'in_progress', 'received', 'cancelled'].map((k) => <option key={k} value={k}>{t(`subcontracting.statusLabels.${k}`, { defaultValue: k })}</option>)}
                  </select>
                </TableCell>
                <TableCell>
                  <button onClick={() => handleDelete(o.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]"><Trash2 className="w-4 h-4" /></button>
                </TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}

      {showForm && <STOrderFormModal suppliers={suppliers} products={products} mos={mos} onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadData() }} />}
    </div>
  )
}

function STOrderFormModal({ suppliers, products, mos, onClose, onSaved }: { suppliers: Supplier[]; products: Product[]; mos: any[]; onClose: () => void; onSaved: () => void }) {
  const { toast } = useToast()
  const { t } = useTranslation('production')
  const { t: tCommon } = useTranslation('common')
  const [supplierId, setSupplierId] = useState('')
  const [productId, setProductId] = useState('')
  const [moId, setMoId] = useState('')
  const [quantity, setQuantity] = useState(1)
  const [unit, setUnit] = useState('unit')
  const [unitPrice, setUnitPrice] = useState(0)
  const [expectedDate, setExpectedDate] = useState('')
  const [notes, setNotes] = useState('')

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!supplierId) { toast('error', tCommon('toast.error'), t('subcontracting.supplierRequired')); return }
    try {
      const number = `ST-${new Date().getFullYear()}-${String(Date.now()).slice(-6)}`
      await createSTOrder({
        number, supplier_id: supplierId, manufacturing_order_id: moId || null,
        routing_operation_id: null, product_id: productId || null,
        quantity, unit, unit_price: unitPrice, total_price: quantity * unitPrice,
        status: 'draft', order_date: new Date().toISOString().split('T')[0],
        expected_date: expectedDate || null, notes: notes || null,
      })
      onSaved()
    } catch (err: any) { toast('error', tCommon('toast.error'), err.message) }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40" onClick={onClose}>
      <div className="bg-[var(--color-surface)] rounded-xl shadow-xl p-6 w-full max-w-md" onClick={(e) => e.stopPropagation()}>
        <h2 className="text-lg font-semibold mb-4">{t('subcontracting.newOrder')}</h2>
        <form onSubmit={handleSubmit} className="space-y-3">
          <Select label={t('subcontracting.supplier')} value={supplierId} onChange={(e) => setSupplierId(e.target.value)} options={[{ value: '', label: '—' }, ...suppliers.map((s) => ({ value: s.id, label: s.name }))]} />
          <Select label={t('subcontracting.moOptional')} value={moId} onChange={(e) => setMoId(e.target.value)} options={[{ value: '', label: '—' }, ...mos.map((m) => ({ value: m.id, label: m.number }))]} />
          <Select label={t('subcontracting.product')} value={productId} onChange={(e) => setProductId(e.target.value)} options={[{ value: '', label: '—' }, ...products.map((p) => ({ value: p.id, label: p.name }))]} />
          <div className="grid grid-cols-2 gap-3">
            <Input label={t('subcontracting.quantity')} type="number" step="0.01" value={quantity} onChange={(e) => setQuantity(Number(e.target.value))} />
            <Input label={t('subcontracting.unit')} value={unit} onChange={(e) => setUnit(e.target.value)} />
          </div>
          <Input label={t('subcontracting.unitPrice')} type="number" step="0.01" value={unitPrice} onChange={(e) => setUnitPrice(Number(e.target.value))} />
          <Input label={t('subcontracting.expectedDate')} type="date" value={expectedDate} onChange={(e) => setExpectedDate(e.target.value)} />
          <Input label={tCommon('common.notes')} value={notes} onChange={(e) => setNotes(e.target.value)} />
          <div className="flex gap-2 justify-end pt-2">
            <Button type="button" variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit">{tCommon('actions.create')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}

// ============ Shipments Page ============

export function SubcontractingShipmentsPage() {
  const { toast } = useToast()
  const { t } = useTranslation('production')
  const { t: tCommon } = useTranslation('common')
  const [shipments, setShipments] = useState<any[]>([])
  const [loading, setLoading] = useState(true)

  const loadData = useCallback(async () => {
    try { setShipments(await getSTShipments() || []) }
    catch (err) { console.error('Error:', err) }
    finally { setLoading(false) }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  async function handleDelete(id: string) {
    if (!window.confirm(tCommon('form.confirmDelete'))) return
    try { await deleteSTShipment(id); await loadData() }
    catch (err: any) { toast('error', tCommon('toast.error'), err.message) }
  }

  const shipStatusVariants: Record<string, 'neutral' | 'warning' | 'success'> = { pending: 'neutral', shipped: 'warning', returned: 'success' }

  return (
    <div>
      <Breadcrumb items={[{ label: t('subcontracting.title') }, { label: t('subcontracting.shipments') }]} />
      <PageHeader title={t('subcontracting.shipmentsTitle')} subtitle={`${shipments.length} ${t('subcontracting.shipmentsCount')}`} />
      {loading ? <SkeletonTable rows={4} cols={5} /> : shipments.length === 0 ? (
        <EmptyState icon={<Truck className="w-8 h-8" />} title={t('subcontracting.noShipments')} description={t('subcontracting.noShipmentsDescription')} />
      ) : (
        <Card>
          <Table headers={[t('subcontracting.number'), t('subcontracting.stOrder'), t('subcontracting.supplier'), tCommon('common.date'), t('subcontracting.warehouse'), tCommon('common.status'), tCommon('table.actions')]}>
            {shipments.map((s) => (
              <TableRow key={s.id}>
                <TableCell className="font-mono text-xs">{s.number}</TableCell>
                <TableCell className="font-mono text-xs">{s.st_orders?.number || '—'}</TableCell>
                <TableCell className="text-sm">{s.st_orders?.suppliers?.name || '—'}</TableCell>
                <TableCell className="text-xs">{formatDate(s.shipment_date)}</TableCell>
                <TableCell className="text-sm">{s.warehouses?.name || '—'}</TableCell>
                <TableCell><Badge variant={shipStatusVariants[s.status] || 'neutral'}>{t(`subcontracting.shipStatusLabels.${s.status}`, { defaultValue: s.status })}</Badge></TableCell>
                <TableCell><button onClick={() => handleDelete(s.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]"><Trash2 className="w-4 h-4" /></button></TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}
    </div>
  )
}

// ============ Receipts Page ============

export function SubcontractingReceiptsPage() {
  const { toast } = useToast()
  const { t } = useTranslation('production')
  const { t: tCommon } = useTranslation('common')
  const [receipts, setReceipts] = useState<any[]>([])
  const [loading, setLoading] = useState(true)

  const loadData = useCallback(async () => {
    try { setReceipts(await getSTReceipts() || []) }
    catch (err) { console.error('Error:', err) }
    finally { setLoading(false) }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  async function handleDelete(id: string) {
    if (!window.confirm(tCommon('form.confirmDelete'))) return
    try { await deleteSTReceipt(id); await loadData() }
    catch (err: any) { toast('error', tCommon('toast.error'), err.message) }
  }

  const receiptStatusVariants: Record<string, 'neutral' | 'success' | 'warning' | 'danger'> = { pending: 'neutral', received: 'success', partial: 'warning', cancelled: 'danger' }

  return (
    <div>
      <Breadcrumb items={[{ label: t('subcontracting.title') }, { label: t('subcontracting.receipts') }]} />
      <PageHeader title={t('subcontracting.receiptsTitle')} subtitle={`${receipts.length} ${t('subcontracting.receiptsCount')}`} />
      {loading ? <SkeletonTable rows={4} cols={6} /> : receipts.length === 0 ? (
        <EmptyState icon={<PackageCheck className="w-8 h-8" />} title={t('subcontracting.noReceipts')} description={t('subcontracting.noReceiptsDescription')} />
      ) : (
        <Card>
          <Table headers={[t('subcontracting.number'), t('subcontracting.stOrder'), t('subcontracting.supplier'), tCommon('common.date'), t('subcontracting.qtyReceived'), t('subcontracting.qtyReturned'), tCommon('common.status'), tCommon('table.actions')]}>
            {receipts.map((r) => (
              <TableRow key={r.id}>
                <TableCell className="font-mono text-xs">{r.number}</TableCell>
                <TableCell className="font-mono text-xs">{r.st_orders?.number || '—'}</TableCell>
                <TableCell className="text-sm">{r.st_orders?.suppliers?.name || '—'}</TableCell>
                <TableCell className="text-xs">{formatDate(r.receipt_date)}</TableCell>
                <TableCell className="font-mono text-xs">{Number(r.quantity_received)}</TableCell>
                <TableCell className="font-mono text-xs">{Number(r.quantity_returned)}</TableCell>
                <TableCell><Badge variant={receiptStatusVariants[r.status] || 'neutral'}>{t(`subcontracting.receiptStatusLabels.${r.status}`, { defaultValue: r.status })}</Badge></TableCell>
                <TableCell><button onClick={() => handleDelete(r.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]"><Trash2 className="w-4 h-4" /></button></TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}
    </div>
  )
}

// ============ Supervisor Page ============

export function SubcontractingSupervisorPage() {
  const { t } = useTranslation('production')
  const { t: tCommon } = useTranslation('common')
  const [data, setData] = useState<any[]>([])
  const [loading, setLoading] = useState(true)

  const loadData = useCallback(async () => {
    try { setData(await getSTSupervisorData() || []) }
    catch (err) { console.error('Error:', err) }
    finally { setLoading(false) }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  const statusVariants2: Record<string, 'neutral' | 'success' | 'warning' | 'danger'> = { draft: 'neutral', sent: 'warning', in_progress: 'warning', received: 'success', cancelled: 'danger' }

  return (
    <div>
      <Breadcrumb items={[{ label: t('subcontracting.title') }, { label: t('subcontracting.supervisor') }]} />
      <PageHeader title={t('subcontracting.supervisorTitle')} subtitle={t('subcontracting.supervisorSubtitle')} />
      {loading ? <SkeletonTable rows={4} cols={6} /> : data.length === 0 ? (
        <EmptyState icon={<Eye className="w-8 h-8" />} title={t('subcontracting.noData')} description={t('subcontracting.noDataDescription')} />
      ) : (
        <Card>
          <Table headers={[t('subcontracting.number'), t('subcontracting.supplier'), t('subcontracting.product'), tCommon('common.status'), t('subcontracting.shipments'), t('subcontracting.receipts'), t('subcontracting.qtyReceived')]}>
            {data.map((o) => (
              <TableRow key={o.id}>
                <TableCell className="font-mono text-xs">{o.number}</TableCell>
                <TableCell className="text-sm">{o.suppliers?.name || '—'}</TableCell>
                <TableCell className="text-sm">{o.products?.name || '—'}</TableCell>
                <TableCell><Badge variant={statusVariants2[o.status] || 'neutral'}>{t(`subcontracting.statusLabels.${o.status}`, { defaultValue: o.status })}</Badge></TableCell>
                <TableCell className="text-xs">{(o.st_shipments || []).length} {t('subcontracting.shipmentsCount')}</TableCell>
                <TableCell className="text-xs">{(o.st_receipts || []).length} {t('subcontracting.receiptsCount')}</TableCell>
                <TableCell className="font-mono text-xs">{(o.st_receipts || []).reduce((sum: number, r: any) => sum + Number(r.quantity_received || 0), 0)}</TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}
    </div>
  )
}
