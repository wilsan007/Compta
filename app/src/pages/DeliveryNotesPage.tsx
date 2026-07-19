import { useEffect, useState, useCallback } from 'react'
import { Card, PageHeader, Button, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { formatDate } from '@/lib/utils'
import { getDeliveryNotes, createDeliveryNote, updateDeliveryNote, deleteDeliveryNote, getCustomers } from '@/lib/queries'
import { Plus, Trash2, X, Truck } from 'lucide-react'
import type { DeliveryNote, Customer } from '@/types'
import { useToast } from '@/lib/toast'

const statusLabels: Record<string, string> = { pending: 'En attente', delivered: 'Livré', returned: 'Retourné', cancelled: 'Annulé' }

export function DeliveryNotesPage() {
  const { toast } = useToast()
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
    catch (err: any) { toast('error', 'Erreur', err.message || 'échec') }
  }

  async function handleDelete(id: string) {
    if (!window.confirm('Supprimer ce bon de livraison ?')) return
    try { await deleteDeliveryNote(id); await loadData() }
    catch (err: any) { toast('error', 'Erreur', err.message || 'échec') }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: 'Commercial' }, { label: 'Bons de livraison' }]} />
      <PageHeader title="Bons de livraison" subtitle={`${notes.length} bon(s)`}
        action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> Nouveau BL</Button>} />

      <div className="flex gap-3 mb-4 items-end">
        <div className="w-48">
          <Select label="Statut" value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)} options={[
            { value: '', label: 'Tous' }, { value: 'pending', label: 'En attente' }, { value: 'delivered', label: 'Livré' },
            { value: 'returned', label: 'Retourné' }, { value: 'cancelled', label: 'Annulé' },
          ]} />
        </div>
        <Button variant="secondary" onClick={loadData}>Actualiser</Button>
      </div>

      {loading ? <SkeletonTable rows={6} cols={6} /> : notes.length === 0 ? (
        <EmptyState icon={<Truck className="w-8 h-8" />} title="Aucun bon de livraison" description="Créez votre premier bon de livraison."
          action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> Nouveau BL</Button>} />
      ) : (
        <Card>
          <Table headers={['N°', 'Client', 'Date', 'Transporteur', 'Suivi', 'Statut', 'Actions']}>
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
                      {Object.entries(statusLabels).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
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
    } catch (err: any) { toast('error', 'Erreur', err.message || 'échec') }
    finally { setSaving(false) }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl overflow-hidden" style={{ width: '100%', maxWidth: '32rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">Nouveau bon de livraison</h2>
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
          <Input label="Date de livraison" type="date" required value={deliveryDate} onChange={(e) => setDeliveryDate(e.target.value)} />
          <div className="grid grid-cols-2 gap-4">
            <Input label="Transporteur" value={carrier} onChange={(e) => setCarrier(e.target.value)} placeholder="Chronopost, DHL..." />
            <Input label="N° de suivi" value={trackingNumber} onChange={(e) => setTrackingNumber(e.target.value)} />
          </div>
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
