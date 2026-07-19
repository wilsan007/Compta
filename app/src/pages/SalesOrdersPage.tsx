import { useEffect, useState, useCallback } from 'react'
import { Card, PageHeader, Button, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { formatCurrency, formatDate } from '@/lib/utils'
import { getSalesOrders, createSalesOrder, updateSalesOrder, deleteSalesOrder, getCustomers } from '@/lib/queries'
import { Plus, Trash2, X, FileText } from 'lucide-react'
import type { SalesOrder, Customer } from '@/types'
import { useToast } from '@/lib/toast'

const statusLabels: Record<string, string> = { draft: 'Brouillon', confirmed: 'Confirmée', delivered: 'Livrée', invoiced: 'Facturée', cancelled: 'Annulée' }

export function SalesOrdersPage() {
  const { toast } = useToast()
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
    catch (err: any) { toast('error', 'Erreur', err.message || 'échec') }
  }

  async function handleDelete(id: string) {
    if (!window.confirm('Supprimer cette commande ?')) return
    try { await deleteSalesOrder(id); await loadData() }
    catch (err: any) { toast('error', 'Erreur', err.message || 'échec') }
  }

  const totalAmount = orders.reduce((s, o) => s + Number(o.total), 0)

  return (
    <div>
      <Breadcrumb items={[{ label: 'Commercial' }, { label: 'Commandes clients' }]} />
      <PageHeader title="Commandes clients" subtitle={`${orders.length} commande(s) — ${formatCurrency(totalAmount)}`}
        action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> Nouvelle commande</Button>} />

      <div className="flex gap-3 mb-4 items-end">
        <div className="w-48">
          <Select label="Statut" value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)} options={[
            { value: '', label: 'Tous' }, { value: 'draft', label: 'Brouillon' }, { value: 'confirmed', label: 'Confirmée' },
            { value: 'delivered', label: 'Livrée' }, { value: 'invoiced', label: 'Facturée' }, { value: 'cancelled', label: 'Annulée' },
          ]} />
        </div>
        <Button variant="secondary" onClick={loadData}>Actualiser</Button>
      </div>

      {loading ? <SkeletonTable rows={6} cols={6} /> : orders.length === 0 ? (
        <EmptyState icon={<FileText className="w-8 h-8" />} title="Aucune commande" description="Créez votre première commande client."
          action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> Nouvelle commande</Button>} />
      ) : (
        <Card>
          <Table headers={['N°', 'Client', 'Date', 'Livraison', 'Montant', 'Statut', 'Actions']}>
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
                      {Object.entries(statusLabels).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
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
    } catch (err: any) { toast('error', 'Erreur', err.message || 'échec') }
    finally { setSaving(false) }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl overflow-hidden" style={{ width: '100%', maxWidth: '32rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">Nouvelle commande client</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">Client</label>
            <select className="input" value={customerId} onChange={(e) => setCustomerId(e.target.value)} required>
              <option value="">— Sélectionner —</option>
              {customers.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
            </select>
          </div>
          <div className="grid grid-cols-2 gap-4">
            <Input label="Date commande" type="date" required value={orderDate} onChange={(e) => setOrderDate(e.target.value)} />
            <Input label="Date livraison" type="date" value={deliveryDate} onChange={(e) => setDeliveryDate(e.target.value)} />
          </div>
          <Input label="Montant total" type="number" step="0.01" required value={total} onChange={(e) => setTotal(Number(e.target.value))} />
          <Input label="Notes" value={notes} onChange={(e) => setNotes(e.target.value)} />
          <div className="flex justify-end gap-3 pt-2">
            <Button variant="secondary" onClick={onClose}>Annuler</Button>
            <Button type="submit" disabled={saving}>{saving ? '...' : 'Créer'}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
