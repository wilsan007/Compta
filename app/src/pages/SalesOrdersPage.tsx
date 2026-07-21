import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { formatCurrency, formatDate, translateStatus } from '@/lib/utils'
import { getSalesOrders, createSalesOrder, updateSalesOrder, deleteSalesOrder, getCustomers } from '@/lib/queries'
import { Plus, Trash2, X, FileText } from 'lucide-react'
import type { SalesOrder, Customer } from '@/types'
import { useToast } from '@/lib/toast'

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

  const loadData = useCallback(async () => {
    try {
      const [ords, custs] = await Promise.all([getSalesOrders(statusFilter || undefined), getCustomers()])
      setOrders(ords || [])
      setCustomers(custs || [])
    } catch (err) { console.error('Error:', err) }
    finally { setLoading(false) }
  }, [statusFilter])

  useEffect(() => { loadData() }, [loadData])

  async function handleStatusChange(id: string, status: string) {
    try { await updateSalesOrder(id, { status: status as any }); await loadData() }
    catch (err: any) { toast('error', tCommon('toast.error'), err.message || tCommon('toast.updateError')) }
  }

  async function handleDelete(id: string) {
    if (!window.confirm(tCommon('form.confirmDelete'))) return
    try { await deleteSalesOrder(id); await loadData() }
    catch (err: any) { toast('error', tCommon('toast.error'), err.message || tCommon('toast.deleteError')) }
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
          <Table headers={[t('orders.number'), t('orders.customer'), t('orders.date'), t('orders.deliveryDate'), t('orders.amount'), t('orders.status'), tCommon('table.actions')]}>
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
                    <button onClick={() => handleDelete(o.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]">
                      <Trash2 className="w-4 h-4" />
                    </button>
                  </TableCell>
                </TableRow>
              )
            })}
          </Table>
        </Card>
      )}

      {showForm && <OrderForm customers={customers} onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadData() }} />}
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
      const number = `CMD-${new Date().getFullYear()}-${String(Date.now()).slice(-6)}`
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
            <Button type="submit" disabled={saving}>{saving ? '...' : tCommon('actions.create')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
