import { useEffect, useState, useCallback } from 'react'
import { Card, PageHeader, Button, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { formatDate } from '@/lib/utils'
import { getManufacturingOrders, createManufacturingOrder, updateManufacturingOrder, deleteManufacturingOrder, getBOMs, getWarehouses } from '@/lib/queries'
import { Plus, Trash2, X, Factory } from 'lucide-react'
import type { ManufacturingOrder, BOM, Warehouse } from '@/types'
import { useToast } from '@/lib/toast'

const statusLabels: Record<string, string> = { planned: 'Planifié', in_progress: 'En cours', completed: 'Terminé', cancelled: 'Annulé' }

export function ManufacturingOrdersPage() {
  const { toast } = useToast()
const [orders, setOrders] = useState<ManufacturingOrder[]>([])
  const [boms, setBOMs] = useState<BOM[]>([])
  const [warehouses, setWarehouses] = useState<Warehouse[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [statusFilter, setStatusFilter] = useState('')

  const loadData = useCallback(async () => {
    try {
      const [ords, bs, whs] = await Promise.all([getManufacturingOrders(statusFilter || undefined), getBOMs(), getWarehouses()])
      setOrders(ords || [])
      setBOMs(bs || [])
      setWarehouses(whs || [])
    } catch (err) { console.error('Error:', err) }
    finally { setLoading(false) }
  }, [statusFilter])

  useEffect(() => { loadData() }, [loadData])

  async function handleStatusChange(id: string, status: string) {
  try { await updateManufacturingOrder(id, { status: status as any }); await loadData() }
    catch (err: any) { toast('error', 'Erreur', err.message || 'échec') }
  }

  async function handleDelete(id: string) {
    if (!window.confirm('Supprimer cet ordre de fabrication ?')) return
    try { await deleteManufacturingOrder(id); await loadData() }
    catch (err: any) { toast('error', 'Erreur', err.message || 'échec') }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: 'Stock' }, { label: 'Ordres de fabrication' }]} />
      <PageHeader title="Ordres de fabrication" subtitle={`${orders.length} ordre(s)`}
        action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> Nouvel OF</Button>} />

      <div className="flex gap-3 mb-4 items-end">
        <div className="w-48">
          <Select label="Statut" value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)} options={[
            { value: '', label: 'Tous' }, { value: 'planned', label: 'Planifié' }, { value: 'in_progress', label: 'En cours' },
            { value: 'completed', label: 'Terminé' }, { value: 'cancelled', label: 'Annulé' },
          ]} />
        </div>
      </div>

      {loading ? <SkeletonTable rows={4} cols={6} /> : orders.length === 0 ? (
        <EmptyState icon={<Factory className="w-8 h-8" />} title="Aucun ordre de fabrication" description="Créez votre premier OF."
          action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> Nouvel OF</Button>} />
      ) : (
        <Card>
          <Table headers={['N°', 'BOM', 'Quantité', 'Début', 'Fin', 'Statut', 'Actions']}>
            {orders.map((o) => {
              const bom = boms.find((b) => b.id === o.bom_id)
              return (
                <TableRow key={o.id}>
                  <TableCell className="font-mono text-xs">{o.number}</TableCell>
                  <TableCell className="text-sm">{bom?.name || '—'}</TableCell>
                  <TableCell className="font-mono text-xs">{Number(o.quantity)}</TableCell>
                  <TableCell className="text-xs">{o.start_date ? formatDate(o.start_date) : '—'}</TableCell>
                  <TableCell className="text-xs">{o.end_date ? formatDate(o.end_date) : '—'}</TableCell>
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

      {showForm && <OFForm boms={boms} warehouses={warehouses} onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadData() }} />}
    </div>
  )
}

function OFForm({ boms, warehouses, onClose, onSaved }: { boms: BOM[]; warehouses: Warehouse[]; onClose: () => void; onSaved: () => void }) {
  const [bomId, setBomId] = useState('')
  const { toast } = useToast()
  const [quantity, setQuantity] = useState(1)
  const [startDate, setStartDate] = useState('')
  const [endDate, setEndDate] = useState('')
  const [warehouseId, setWarehouseId] = useState('')
  const [notes, setNotes] = useState('')
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      const number = `OF-${new Date().getFullYear()}-${String(Date.now()).slice(-6)}`
      await createManufacturingOrder({ number, bom_id: bomId || null, product_id: null, quantity, status: 'planned', start_date: startDate || null, end_date: endDate || null, warehouse_id: warehouseId || null, notes: notes || null } as any)
      onSaved()
    } catch (err: any) { toast('error', 'Erreur', err.message || 'échec') }
    finally { setSaving(false) }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl overflow-hidden" style={{ width: '100%', maxWidth: '32rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">Nouvel ordre de fabrication</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">Nomenclature (BOM)</label>
            <select className="input" value={bomId} onChange={(e) => setBomId(e.target.value)} required>
              <option value="">— Sélectionner —</option>
              {boms.map((b) => <option key={b.id} value={b.id}>{b.code} — {b.name}</option>)}
            </select>
          </div>
          <Input label="Quantité" type="number" step="0.01" required value={quantity} onChange={(e) => setQuantity(Number(e.target.value))} />
          <div className="grid grid-cols-2 gap-4">
            <Input label="Date début" type="date" value={startDate} onChange={(e) => setStartDate(e.target.value)} />
            <Input label="Date fin" type="date" value={endDate} onChange={(e) => setEndDate(e.target.value)} />
          </div>
          <div>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">Dépôt</label>
            <select className="input" value={warehouseId} onChange={(e) => setWarehouseId(e.target.value)}>
              <option value="">— Sélectionner —</option>
              {warehouses.map((w) => <option key={w.id} value={w.id}>{w.name}</option>)}
            </select>
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
