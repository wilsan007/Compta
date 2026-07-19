import { useEffect, useState, useCallback } from 'react'
import { Card, PageHeader, Button, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { formatDate } from '@/lib/utils'
import { getGoodsReceipts, createGoodsReceipt, updateGoodsReceipt, deleteGoodsReceipt, getSuppliers } from '@/lib/queries'
import { Plus, Trash2, X, PackageCheck } from 'lucide-react'
import type { GoodsReceipt, Supplier } from '@/types'
import { useToast } from '@/lib/toast'

const statusLabels: Record<string, string> = { pending: 'En attente', received: 'Reçu', partial: 'Partiel', cancelled: 'Annulé' }

export function GoodsReceiptPage() {
  const { toast } = useToast()
const [receipts, setReceipts] = useState<GoodsReceipt[]>([])
  const [suppliers, setSuppliers] = useState<Supplier[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [statusFilter, setStatusFilter] = useState('')

  const loadData = useCallback(async () => {
    try {
      const [rcpts, sups] = await Promise.all([getGoodsReceipts(statusFilter || undefined), getSuppliers()])
      setReceipts(rcpts || [])
      setSuppliers(sups || [])
    } catch (err) { console.error('Error:', err) }
    finally { setLoading(false) }
  }, [statusFilter])

  useEffect(() => { loadData() }, [loadData])

  async function handleStatusChange(id: string, status: string) {
  try { await updateGoodsReceipt(id, { status: status as any }); await loadData() }
    catch (err: any) { toast('error', 'Erreur', err.message || 'échec') }
  }

  async function handleDelete(id: string) {
    if (!window.confirm('Supprimer cette réception ?')) return
    try { await deleteGoodsReceipt(id); await loadData() }
    catch (err: any) { toast('error', 'Erreur', err.message || 'échec') }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: 'Achats' }, { label: 'Réceptions marchandises' }]} />
      <PageHeader title="Réceptions marchandises" subtitle={`${receipts.length} réception(s)`}
        action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> Nouvelle réception</Button>} />

      <div className="flex gap-3 mb-4 items-end">
        <div className="w-48">
          <Select label="Statut" value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)} options={[
            { value: '', label: 'Tous' }, { value: 'pending', label: 'En attente' }, { value: 'received', label: 'Reçu' },
            { value: 'partial', label: 'Partiel' }, { value: 'cancelled', label: 'Annulé' },
          ]} />
        </div>
        <Button variant="secondary" onClick={loadData}>Actualiser</Button>
      </div>

      {loading ? <SkeletonTable rows={6} cols={5} /> : receipts.length === 0 ? (
        <EmptyState icon={<PackageCheck className="w-8 h-8" />} title="Aucune réception" description="Enregistrez votre première réception."
          action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> Nouvelle réception</Button>} />
      ) : (
        <Card>
          <Table headers={['N°', 'Fournisseur', 'Date', 'Statut', 'Actions']}>
            {receipts.map((r) => {
              const sup = suppliers.find((s) => s.id === r.supplier_id)
              return (
                <TableRow key={r.id}>
                  <TableCell className="font-mono text-xs">{r.number}</TableCell>
                  <TableCell className="text-sm">{sup?.name || '—'}</TableCell>
                  <TableCell className="text-xs">{formatDate(r.receipt_date)}</TableCell>
                  <TableCell>
                    <select value={r.status} onChange={(e) => handleStatusChange(r.id, e.target.value)}
                      className="text-xs border border-[var(--color-border)] rounded px-2 py-1 bg-[var(--color-surface)]">
                      {Object.entries(statusLabels).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
                    </select>
                  </TableCell>
                  <TableCell>
                    <button onClick={() => handleDelete(r.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]">
                      <Trash2 className="w-4 h-4" />
                    </button>
                  </TableCell>
                </TableRow>
              )
            })}
          </Table>
        </Card>
      )}

      {showForm && <GRForm suppliers={suppliers} onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadData() }} />}
    </div>
  )
}

function GRForm({ suppliers, onClose, onSaved }: { suppliers: Supplier[]; onClose: () => void; onSaved: () => void }) {
  const [supplierId, setSupplierId] = useState('')
  const { toast } = useToast()
  const [receiptDate, setReceiptDate] = useState(new Date().toISOString().split('T')[0])
  const [notes, setNotes] = useState('')
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      const number = `BR-${new Date().getFullYear()}-${String(Date.now()).slice(-6)}`
      await createGoodsReceipt({ number, supplier_id: supplierId || null, purchase_order_id: null, receipt_date: receiptDate, status: 'pending', notes: notes || null } as any)
      onSaved()
    } catch (err: any) { toast('error', 'Erreur', err.message || 'échec') }
    finally { setSaving(false) }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl overflow-hidden" style={{ width: '100%', maxWidth: '32rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">Nouvelle réception</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">Fournisseur</label>
            <select className="input" value={supplierId} onChange={(e) => setSupplierId(e.target.value)} required>
              <option value="">— Sélectionner —</option>
              {suppliers.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
            </select>
          </div>
          <Input label="Date de réception" type="date" required value={receiptDate} onChange={(e) => setReceiptDate(e.target.value)} />
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
