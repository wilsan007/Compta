import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { formatCurrency, formatDate, translateStatus } from '@/lib/utils'
import { getSalesOrders, createSalesOrder, updateSalesOrder, deleteSalesOrder } from '@/lib/queries/sales'
import { getCustomers } from '@/lib/queries/partners'
import { getSalesOrderLines, transformSalesOrderToDeliveryNote } from '@/lib/queries/misc'
import { Plus, Trash2, X, FileText, Truck } from 'lucide-react'
import type { SalesOrder, SalesOrderLine, Customer } from '@/types'
import { useToast } from '@/lib/toast'
import { confirmSync } from '@/lib/confirm'
import { nextDocumentNumber } from '@/lib/queries/core'

const statusKeys: string[] = ['draft', 'confirmed', 'delivered', 'invoiced', 'cancelled']

export function SalesOrdersPage() {
  const { toast } = useToast()
  const { t } = useTranslation('sales')
  const { t: tCommon } = useTranslation('common')
const [orders, setOrders] = useState<SalesOrder[]>([])
  const [customers, setCustomers] = useState<Customer[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [statusFilter, setStatusFilter] = useState('')
  const [transformOrder, setTransformOrder] = useState<SalesOrder | null>(null)
  const [orderLines, setOrderLines] = useState<SalesOrderLine[]>([])
  const [transformLoading, setTransformLoading] = useState(false)

  const loadData = useCallback(async () => {
    try {
      const [ords, custs] = await Promise.all([getSalesOrders(statusFilter || undefined), getCustomers()])
      setOrders(ords || [])
      setCustomers(custs || [])
    } catch (err: any) { console.error('Error:', err); toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadError')) }
    finally { setLoading(false) }
  }, [statusFilter, toast, tCommon])

  useEffect(() => { loadData() }, [loadData])

  async function handleStatusChange(id: string, status: string) {
    try { await updateSalesOrder(id, { status: status as any }); await loadData() }
    catch (err: any) { toast('error', tCommon('toast.error'), err.message || tCommon('toast.updateError')) }
  }

  async function handleDelete(id: string) {
    if (!confirmSync(tCommon('form.confirmDelete'))) return
    try { await deleteSalesOrder(id); await loadData() }
    catch (err: any) { toast('error', tCommon('toast.error'), err.message || tCommon('toast.deleteError')) }
  }

  async function handleTransformToDelivery(order: SalesOrder) {
    setTransformLoading(true)
    try {
      const lines = await getSalesOrderLines(order.id)
      setOrderLines(lines)
      setTransformOrder(order)
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message || t('transformations.transformationError'))
    } finally {
      setTransformLoading(false)
    }
  }

  async function confirmTransformToDelivery(orderId: string, selectedLines: { sales_order_line_id: string; quantity: number }[]) {
    if (selectedLines.length === 0) { toast('warning', t('transformations.transformationError'), t('transformations.noLinesSelected')); return }
    try {
      await transformSalesOrderToDeliveryNote(orderId, selectedLines)
      toast('success', tCommon('toast.success'), t('transformations.transformationSuccess'))
      setTransformOrder(null)
      await loadData()
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message || t('transformations.transformationError'))
    }
  }

  const totalAmount = orders.reduce((s, o) => s + Number(o.total), 0)

  return (
    <div>
      <Breadcrumb items={[{ label: t('orders.title') }]} />
      <PageHeader title={t('orders.title')} subtitle={`${orders.length} ${t('orders.title').toLowerCase()} — ${formatCurrency(totalAmount)}`}
        action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('orders.new')}</Button>} />

      <div className="flex gap-3 mb-4 items-end">
        <div className="w-48">
          <Select label={t('orders.status')} value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)} options={[
            { value: '', label: tCommon('filters.all') }, ...statusKeys.map(k => ({ value: k, label: translateStatus(k) })),
          ]} />
        </div>
        <Button variant="secondary" onClick={loadData}>{tCommon('actions.refresh')}</Button>
      </div>

      {loading ? <SkeletonTable rows={6} cols={6} /> : orders.length === 0 ? (
        <EmptyState icon={<FileText className="w-8 h-8" />} title={t('orders.noOrders')} description={t('orders.noOrdersDescription')}
          action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('orders.new')}</Button>} />
      ) : (
        <Card>
          <Table headers={[t('orders.number'), t('orders.customer'), t('orders.date'), t('orders.deliveryDate'), t('orders.amount'), t('orders.status'), t('orders.deliveryStatus'), tCommon('table.actions')]}>
            {orders.map((o) => {
              const cust = customers.find((c) => c.id === o.customer_id)
              return (
                <TableRow key={o.id}>
                  <TableCell className="font-mono text-xs">{o.number}</TableCell>
                  <TableCell className="text-sm">{cust?.name || '—'}</TableCell>
                  <TableCell className="text-xs">{formatDate(o.order_date)}</TableCell>
                  <TableCell className="text-xs">{o.delivery_date ? formatDate(o.delivery_date) : '—'}</TableCell>
                  <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(o.total))}</TableCell>
                  <TableCell>
                    <select value={o.status} onChange={(e) => handleStatusChange(o.id, e.target.value)}
                      className="text-xs border border-[var(--color-border)] rounded px-2 py-1 bg-[var(--color-surface)]">
                      {statusKeys.map(k => <option key={k} value={k}>{translateStatus(k)}</option>)}
                    </select>
                  </TableCell>
                  <TableCell>
                    <span className={`text-xs ${o.delivery_status === 'delivered' ? 'text-[var(--color-success)]' : o.delivery_status === 'partial' ? 'text-[var(--color-warning)]' : 'text-[var(--color-text-secondary)]'}`}>
                      {o.delivery_status === 'delivered' ? t('orders.deliveryDelivered') : o.delivery_status === 'partial' ? t('orders.deliveryPartial') : t('orders.deliveryPending')}
                    </span>
                  </TableCell>
                  <TableCell>
                    <div className="flex items-center gap-1">
                      {o.status === 'confirmed' && o.delivery_status !== 'delivered' && (
                        <button onClick={() => handleTransformToDelivery(o)} disabled={transformLoading} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-primary)]" title={t('orders.transformToDelivery')}>
                          <Truck className="w-4 h-4" />
                        </button>
                      )}
                      <button onClick={() => handleDelete(o.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]">
                        <Trash2 className="w-4 h-4" />
                      </button>
                    </div>
                  </TableCell>
                </TableRow>
              )
            })}
          </Table>
        </Card>
      )}

      {showForm && <OrderForm customers={customers} onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadData() }} />}

      {transformOrder && (
        <TransformToDeliveryModal
          order={transformOrder}
          lines={orderLines}
          onClose={() => setTransformOrder(null)}
          onConfirm={(selected) => confirmTransformToDelivery(transformOrder.id, selected)}
        />
      )}
    </div>
  )
}

function OrderForm({ customers, onClose, onSaved }: { customers: Customer[]; onClose: () => void; onSaved: () => void }) {
  const [customerId, setCustomerId] = useState('')
  const { toast } = useToast()
  const { t } = useTranslation('sales')
  const { t: tCommon } = useTranslation('common')
  const [orderDate, setOrderDate] = useState(new Date().toISOString().split('T')[0])
  const [deliveryDate, setDeliveryDate] = useState('')
  const [total, setTotal] = useState(0)
  const [notes, setNotes] = useState('')
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      const number = await nextDocumentNumber('CMD')
      await createSalesOrder({ number, customer_id: customerId || null, order_date: orderDate, delivery_date: deliveryDate || null, status: 'draft', subtotal: total, vat: 0, total, notes: notes || null } as any)
      onSaved()
    } catch (err: any) { toast('error', tCommon('toast.error'), err.message || tCommon('toast.createError')) }
    finally { setSaving(false) }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl overflow-hidden" style={{ width: '100%', maxWidth: '32rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('orders.new')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('orders.customer')}</label>
            <select className="input" value={customerId} onChange={(e) => setCustomerId(e.target.value)} required>
              <option value="">— {tCommon('form.selectOption')} —</option>
              {customers.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
            </select>
          </div>
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('orders.date')} type="date" required value={orderDate} onChange={(e) => setOrderDate(e.target.value)} />
            <Input label={t('orders.deliveryDate')} type="date" value={deliveryDate} onChange={(e) => setDeliveryDate(e.target.value)} />
          </div>
          <Input label={t('orders.amount')} type="number" step="0.01" required value={total} onChange={(e) => setTotal(Number(e.target.value))} />
          <Input label={t('invoices.notes')} value={notes} onChange={(e) => setNotes(e.target.value)} />
          <div className="flex justify-end gap-3 pt-2">
            <Button variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? tCommon('actions.saving') : tCommon('actions.create')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}

function TransformToDeliveryModal({ order, lines, onClose, onConfirm }: {
  order: SalesOrder
  lines: SalesOrderLine[]
  onClose: () => void
  onConfirm: (selected: { sales_order_line_id: string; quantity: number }[]) => void
}) {
  const { t } = useTranslation('sales')
  const { t: tCommon } = useTranslation('common')
  const [selected, setSelected] = useState<Record<string, number>>({})

  function toggle(lineId: string) {
    setSelected(prev => {
      const next = { ...prev }
      if (next[lineId] !== undefined) delete next[lineId]
      else next[lineId] = 0
      return next
    })
  }

  function setQty(lineId: string, qty: number) {
    setSelected(prev => ({ ...prev, [lineId]: qty }))
  }

  function handleConfirm() {
    const result = Object.entries(selected)
      .filter(([_, qty]) => qty > 0)
      .map(([lineId, qty]) => ({ sales_order_line_id: lineId, quantity: qty }))
    onConfirm(result)
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4 overflow-y-auto">
      <div className="card shadow-2xl my-8" style={{ width: '100%', maxWidth: '42rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('orders.transformToDelivery')} — {order.number}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <div className="p-6 space-y-4">
          <p className="text-sm text-[var(--color-text-secondary)]">{t('orders.selectLinesDescription')}</p>
          <div className="border border-[var(--color-border)] rounded-lg overflow-hidden">
            <table className="app-table min-w-[600px]">
              <thead className="bg-[var(--color-neutral-50)]">
                <tr>
                  <th className="px-3 py-2 text-left text-xs font-semibold w-8"></th>
                  <th className="px-3 py-2 text-left text-xs font-semibold">{t('invoices.description')}</th>
                  <th className="px-3 py-2 text-right text-xs font-semibold">{t('invoices.quantity')}</th>
                  <th className="px-3 py-2 text-right text-xs font-semibold">{t('orders.deliveredQuantity')}</th>
                  <th className="px-3 py-2 text-right text-xs font-semibold">{t('orders.remainingQuantity')}</th>
                  <th className="px-3 py-2 text-right text-xs font-semibold">{t('orders.quantityToTransform')}</th>
                </tr>
              </thead>
              <tbody>
                {lines.map((line) => {
                  const remaining = Number(line.quantity) - Number(line.delivered_quantity || 0)
                  const isSelected = selected[line.id] !== undefined
                  return (
                    <tr key={line.id} className="border-t border-[var(--color-border)]">
                      <td className="px-3 py-2">
                        <input type="checkbox" checked={isSelected} onChange={() => toggle(line.id)} disabled={remaining <= 0} />
                      </td>
                      <td className="px-3 py-2 text-xs">{line.description}</td>
                      <td className="px-3 py-2 text-right text-xs font-mono">{Number(line.quantity)}</td>
                      <td className="px-3 py-2 text-right text-xs font-mono">{Number(line.delivered_quantity || 0)}</td>
                      <td className="px-3 py-2 text-right text-xs font-mono">{remaining}</td>
                      <td className="px-3 py-2 text-right">
                        {isSelected && (
                          <input type="number" step="0.01" min={0} max={remaining} value={selected[line.id]} onChange={(e) => setQty(line.id, Math.min(Number(e.target.value), remaining))} className="text-xs border border-[var(--color-border)] rounded px-2 py-1 w-20 bg-[var(--color-surface)] text-right" />
                        )}
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
          <div className="flex justify-end gap-3 pt-2 border-t border-[var(--color-border)]">
            <Button variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button onClick={handleConfirm}>{t('orders.confirmTransformation')}</Button>
          </div>
        </div>
      </div>
    </div>
  )
}
