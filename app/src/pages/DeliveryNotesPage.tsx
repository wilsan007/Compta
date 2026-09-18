import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { formatDate, translateStatus } from '@/lib/utils'
import { getDeliveryNotes, createDeliveryNote, updateDeliveryNote, deleteDeliveryNote, getSalesOrders } from '@/lib/queries/sales'
import { getCustomers } from '@/lib/queries/partners'
import { getDeliveryNoteLines, transformDeliveryNoteToInvoice } from '@/lib/queries/misc'
import { Plus, Trash2, X, Truck, FileText } from 'lucide-react'
import type { DeliveryNote, DeliveryNoteLine, Customer, SalesOrder } from '@/types'
import { useToast } from '@/lib/toast'
import { confirmSync } from '@/lib/confirm'
import { nextDocumentNumber } from '@/lib/queries/core'

const statusKeys: string[] = ['pending', 'shipped', 'delivered', 'returned', 'cancelled']

export function DeliveryNotesPage() {
  const { toast } = useToast()
  const { t } = useTranslation('sales')
  const { t: tCommon } = useTranslation('common')
const [notes, setNotes] = useState<DeliveryNote[]>([])
  const [customers, setCustomers] = useState<Customer[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [statusFilter, setStatusFilter] = useState('')
  const [transformDN, setTransformDN] = useState<DeliveryNote | null>(null)
  const [dnLines, setDnLines] = useState<DeliveryNoteLine[]>([])
  const [transformLoading, setTransformLoading] = useState(false)

  const loadData = useCallback(async () => {
    try {
      const [ns, custs] = await Promise.all([getDeliveryNotes(statusFilter || undefined), getCustomers()])
      setNotes(ns || [])
      setCustomers(custs || [])
    } catch (err: any) { console.error('Error:', err); toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadError')) }
    finally { setLoading(false) }
  }, [statusFilter, toast, tCommon])

  useEffect(() => { loadData() }, [loadData])

  async function handleStatusChange(id: string, status: string) {
    try { await updateDeliveryNote(id, { status: status as any }); await loadData() }
    catch (err: any) { toast('error', tCommon('toast.error'), err.message || tCommon('toast.updateError')) }
  }

  async function handleDelete(id: string) {
    if (!confirmSync(tCommon('form.confirmDelete'))) return
    try { await deleteDeliveryNote(id); await loadData() }
    catch (err: any) { toast('error', tCommon('toast.error'), err.message || tCommon('toast.deleteError')) }
  }

  async function handleTransformToInvoice(dn: DeliveryNote) {
    setTransformLoading(true)
    try {
      const lines = await getDeliveryNoteLines(dn.id)
      setDnLines(lines)
      setTransformDN(dn)
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message || t('transformations.transformationError'))
    } finally {
      setTransformLoading(false)
    }
  }

  async function confirmTransformToInvoice(dnId: string, selectedLines: { delivery_note_line_id: string; quantity: number }[]) {
    if (selectedLines.length === 0) { toast('warning', t('transformations.transformationError'), t('transformations.noLinesSelected')); return }
    try {
      await transformDeliveryNoteToInvoice(dnId, selectedLines)
      toast('success', tCommon('toast.success'), t('transformations.transformationSuccess'))
      setTransformDN(null)
      await loadData()
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message || t('transformations.transformationError'))
    }
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
          <Table headers={[t('deliveryNotes.number'), t('deliveryNotes.customer'), t('deliveryNotes.date'), t('deliveryNotes.carrier'), t('deliveryNotes.tracking'), t('deliveryNotes.status'), t('deliveryNotes.invoiceStatus'), 'Stock', tCommon('table.actions')]}>
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
                    <span className={`text-xs ${n.invoice_status === 'invoiced' ? 'text-[var(--color-success)]' : n.invoice_status === 'partial' ? 'text-[var(--color-warning)]' : 'text-[var(--color-text-secondary)]'}`}>
                      {n.invoice_status === 'invoiced' ? t('deliveryNotes.invoiceInvoiced') : n.invoice_status === 'partial' ? t('deliveryNotes.invoicePartial') : t('deliveryNotes.invoicePending')}
                    </span>
                  </TableCell>
                  <TableCell>{(n as any).stock_movement_id || (n as any).stock_out_created ? <Badge variant="success">Sorti</Badge> : <Badge variant="neutral">En attente</Badge>}</TableCell>
                  <TableCell>
                    <div className="flex items-center gap-1">
                      {n.status !== 'cancelled' && n.invoice_status !== 'invoiced' && (
                        <button onClick={() => handleTransformToInvoice(n)} disabled={transformLoading} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-primary)]" title={t('deliveryNotes.transformToInvoice')}>
                          <FileText className="w-4 h-4" />
                        </button>
                      )}
                      <button onClick={() => handleDelete(n.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]" aria-label={tCommon('actions.delete')} title={tCommon('actions.delete')}>
                        <Trash2 className="w-4 h-4" aria-hidden="true" /></button>
                    </div>
                  </TableCell>
                </TableRow>
              )
            })}
          </Table>
        </Card>
      )}

      {showForm && <DNForm customers={customers} onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadData() }} />}

      {transformDN && (
        <TransformToInvoiceModal
          dn={transformDN}
          lines={dnLines}
          onClose={() => setTransformDN(null)}
          onConfirm={(selected) => confirmTransformToInvoice(transformDN.id, selected)}
        />
      )}
    </div>
  )
}

function DNForm({ customers, onClose, onSaved }: { customers: Customer[]; onClose: () => void; onSaved: () => void }) {
  const [customerId, setCustomerId] = useState('')
  const [salesOrderId, setSalesOrderId] = useState('')
  const [salesOrders, setSalesOrders] = useState<SalesOrder[]>([])
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
      const number = await nextDocumentNumber('BL')
      await createDeliveryNote({ number, customer_id: customerId || null, sales_order_id: salesOrderId || null, delivery_date: deliveryDate, status: 'pending', carrier: carrier || null, tracking_number: trackingNumber || null, notes: notes || null } as any)
      onSaved()
    } catch (err: any) { toast('error', tCommon('toast.error'), err.message || tCommon('toast.createError')) }
    finally { setSaving(false) }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl overflow-hidden" style={{ width: '100%', maxWidth: '32rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('deliveryNotes.new')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]" aria-label={tCommon('actions.close')} title={tCommon('actions.close')}><X className="w-5 h-5" aria-hidden="true" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('deliveryNotes.customer')}</label>
            <select className="input" value={customerId} onChange={async (e) => { setCustomerId(e.target.value); setSalesOrderId(''); setSalesOrders([]); if (e.target.value) { try { const all = await getSalesOrders('confirmed'); setSalesOrders((all || []).filter((o) => o.customer_id === e.target.value)) } catch { /* ignore */ } } }} required>
              <option value="">— {tCommon('form.selectOption')} —</option>
              {customers.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
            </select>
          </div>
          <div>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('deliveryNotes.salesOrder')}</label>
            <select className="input" value={salesOrderId} onChange={(e) => setSalesOrderId(e.target.value)} disabled={!customerId}>
              <option value="">— {tCommon('form.selectOption')} —</option>
              {salesOrders.map((o) => <option key={o.id} value={o.id}>{o.number}</option>)}
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
            <Button type="submit" disabled={saving}>{saving ? tCommon('actions.saving') : tCommon('actions.create')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}

function TransformToInvoiceModal({ dn, lines, onClose, onConfirm }: {
  dn: DeliveryNote
  lines: DeliveryNoteLine[]
  onClose: () => void
  onConfirm: (selected: { delivery_note_line_id: string; quantity: number }[]) => void
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
      .map(([lineId, qty]) => ({ delivery_note_line_id: lineId, quantity: qty }))
    onConfirm(result)
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4 overflow-y-auto">
      <div className="card shadow-2xl my-8" style={{ width: '100%', maxWidth: '42rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('deliveryNotes.transformToInvoice')} — {dn.number}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]" aria-label={tCommon('actions.close')} title={tCommon('actions.close')}><X className="w-5 h-5" aria-hidden="true" /></button>
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
                  <th className="px-3 py-2 text-right text-xs font-semibold">{t('deliveryNotes.invoicedQuantity')}</th>
                  <th className="px-3 py-2 text-right text-xs font-semibold">{t('deliveryNotes.remainingQuantity')}</th>
                  <th className="px-3 py-2 text-right text-xs font-semibold">{t('orders.quantityToTransform')}</th>
                </tr>
              </thead>
              <tbody>
                {lines.map((line) => {
                  const remaining = Number(line.quantity) - Number(line.invoiced_quantity || 0)
                  const isSelected = selected[line.id] !== undefined
                  return (
                    <tr key={line.id} className="border-t border-[var(--color-border)]">
                      <td className="px-3 py-2">
                        <input type="checkbox" checked={isSelected} onChange={() => toggle(line.id)} disabled={remaining <= 0} />
                      </td>
                      <td className="px-3 py-2 text-xs">{line.description}</td>
                      <td className="px-3 py-2 text-right text-xs font-mono">{Number(line.quantity)}</td>
                      <td className="px-3 py-2 text-right text-xs font-mono">{Number(line.invoiced_quantity || 0)}</td>
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
