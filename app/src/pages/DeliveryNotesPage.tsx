import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { formatDate, translateStatus } from '@/lib/utils'
import { getDeliveryNotes, createDeliveryNote, updateDeliveryNote, deleteDeliveryNote, getCustomers } from '@/lib/queries'
import { Plus, Trash2, X, Truck } from 'lucide-react'
import type { DeliveryNote, Customer } from '@/types'
import { useToast } from '@/lib/toast'

const statusKeys: string[] = ['pending', 'delivered', 'returned', 'cancelled']

export function DeliveryNotesPage() {
  const { toast } = useToast()
  const { t } = useTranslation('sales')
  const { t: tCommon } = useTranslation('common')
const [notes, setNotes] = useState<DeliveryNote[]>([])
  const [customers, setCustomers] = useState<Customer[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [statusFilter, setStatusFilter] = useState('')

  const loadData = useCallback(async () => {
    try {
      const [ns, custs] = await Promise.all([getDeliveryNotes(statusFilter || undefined), getCustomers()])
      setNotes(ns || [])
      setCustomers(custs || [])
    } catch (err) { console.error('Error:', err) }
    finally { setLoading(false) }
  }, [statusFilter])

  useEffect(() => { loadData() }, [loadData])

  async function handleStatusChange(id: string, status: string) {
    try { await updateDeliveryNote(id, { status: status as any }); await loadData() }
    catch (err: any) { toast('error', tCommon('toast.error'), err.message || tCommon('toast.updateError')) }
  }

  async function handleDelete(id: string) {
    if (!window.confirm(tCommon('form.confirmDelete'))) return
    try { await deleteDeliveryNote(id); await loadData() }
    catch (err: any) { toast('error', tCommon('toast.error'), err.message || tCommon('toast.deleteError')) }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('deliveryNotes.title') }]} />
      <PageHeader title={t('deliveryNotes.title')} subtitle={`${notes.length} ${t('deliveryNotes.title').toLowerCase()}`}
        action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('deliveryNotes.new')}</Button>} />

      <div className="flex gap-3 mb-4 items-end">
        <div className="w-48">
          <Select label={t('deliveryNotes.status')} value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)} options={[
            { value: '', label: tCommon('filters.all') }, ...statusKeys.map(k => ({ value: k, label: translateStatus(k) })),
          ]} />
        </div>
        <Button variant="secondary" onClick={loadData}>{tCommon('actions.refresh')}</Button>
      </div>

      {loading ? <SkeletonTable rows={6} cols={6} /> : notes.length === 0 ? (
        <EmptyState icon={<Truck className="w-8 h-8" />} title={t('deliveryNotes.noDeliveryNotes')} description={t('deliveryNotes.noDeliveryNotesDescription')}
          action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('deliveryNotes.new')}</Button>} />
      ) : (
        <Card>
          <Table headers={[t('deliveryNotes.number'), t('deliveryNotes.customer'), t('deliveryNotes.date'), t('deliveryNotes.carrier'), t('deliveryNotes.tracking'), t('deliveryNotes.status'), tCommon('table.actions')]}>
            {notes.map((n) => {
              const cust = customers.find((c) => c.id === n.customer_id)
              return (
                <TableRow key={n.id}>
                  <TableCell className="font-mono text-xs">{n.number}</TableCell>
                  <TableCell className="text-sm">{cust?.name || '—'}</TableCell>
                  <TableCell className="text-xs">{formatDate(n.delivery_date)}</TableCell>
                  <TableCell className="text-xs">{n.carrier || '—'}</TableCell>
                  <TableCell className="font-mono text-xs">{n.tracking_number || '—'}</TableCell>
                  <TableCell>
                    <select value={n.status} onChange={(e) => handleStatusChange(n.id, e.target.value)}
                      className="text-xs border border-[var(--color-border)] rounded px-2 py-1 bg-[var(--color-surface)]">
                      {statusKeys.map(k => <option key={k} value={k}>{translateStatus(k)}</option>)}
                    </select>
                  </TableCell>
                  <TableCell>
                    <button onClick={() => handleDelete(n.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]">
                      <Trash2 className="w-4 h-4" />
                    </button>
                  </TableCell>
                </TableRow>
              )
            })}
          </Table>
        </Card>
      )}

      {showForm && <DNForm customers={customers} onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadData() }} />}
    </div>
  )
}

function DNForm({ customers, onClose, onSaved }: { customers: Customer[]; onClose: () => void; onSaved: () => void }) {
  const [customerId, setCustomerId] = useState('')
  const { toast } = useToast()
  const { t } = useTranslation('sales')
  const { t: tCommon } = useTranslation('common')
  const [deliveryDate, setDeliveryDate] = useState(new Date().toISOString().split('T')[0])
  const [carrier, setCarrier] = useState('')
  const [trackingNumber, setTrackingNumber] = useState('')
  const [notes, setNotes] = useState('')
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      const number = `BL-${new Date().getFullYear()}-${String(Date.now()).slice(-6)}`
      await createDeliveryNote({ number, customer_id: customerId || null, sales_order_id: null, delivery_date: deliveryDate, status: 'pending', carrier: carrier || null, tracking_number: trackingNumber || null, notes: notes || null } as any)
      onSaved()
    } catch (err: any) { toast('error', tCommon('toast.error'), err.message || tCommon('toast.createError')) }
    finally { setSaving(false) }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl overflow-hidden" style={{ width: '100%', maxWidth: '32rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('deliveryNotes.new')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('deliveryNotes.customer')}</label>
            <select className="input" value={customerId} onChange={(e) => setCustomerId(e.target.value)} required>
              <option value="">— {tCommon('form.selectOption')} —</option>
              {customers.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
            </select>
          </div>
          <Input label={t('deliveryNotes.date')} type="date" required value={deliveryDate} onChange={(e) => setDeliveryDate(e.target.value)} />
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('deliveryNotes.carrier')} value={carrier} onChange={(e) => setCarrier(e.target.value)} placeholder={t('deliveryNotes.carrierPlaceholder')} />
            <Input label={t('deliveryNotes.tracking')} value={trackingNumber} onChange={(e) => setTrackingNumber(e.target.value)} />
          </div>
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
