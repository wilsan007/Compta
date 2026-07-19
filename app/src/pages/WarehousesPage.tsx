import { useEffect, useState, useCallback } from 'react'
import { Card, PageHeader, Button, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Input } from '@/components/ui'
import { getWarehouses, createWarehouse, updateWarehouse, deleteWarehouse } from '@/lib/queries'
import { Plus, Trash2, X, Warehouse as WarehouseIcon } from 'lucide-react'
import type { Warehouse } from '@/types'
import { useToast } from '@/lib/toast'

export function WarehousesPage() {
  const { toast } = useToast()
const [warehouses, setWarehouses] = useState<Warehouse[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)

  const loadData = useCallback(async () => {
    try { setWarehouses(await getWarehouses()) }
    catch (err) { console.error('Error:', err) }
    finally { setLoading(false) }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  async function handleToggleActive(w: Warehouse) {
  try { await updateWarehouse(w.id, { active: !w.active }); await loadData() }
    catch (err: any) { toast('error', 'Erreur', err.message || 'échec') }
  }

  async function handleDelete(id: string) {
    if (!window.confirm('Supprimer ce dépôt ?')) return
    try { await deleteWarehouse(id); await loadData() }
    catch (err: any) { toast('error', 'Erreur', err.message || 'échec') }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: 'Stock' }, { label: 'Dépôts' }]} />
      <PageHeader title="Dépôts" subtitle={`${warehouses.length} dépôt(s)`}
        action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> Nouveau dépôt</Button>} />

      {loading ? <SkeletonTable rows={4} cols={5} /> : warehouses.length === 0 ? (
        <EmptyState icon={<WarehouseIcon className="w-8 h-8" />} title="Aucun dépôt" description="Créez votre premier dépôt."
          action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> Nouveau dépôt</Button>} />
      ) : (
        <Card>
          <Table headers={['Code', 'Nom', 'Adresse', 'Ville', 'Actif', 'Actions']}>
            {warehouses.map((w) => (
              <TableRow key={w.id}>
                <TableCell className="font-mono text-xs">{w.code}</TableCell>
                <TableCell className="font-medium">{w.name}</TableCell>
                <TableCell className="text-xs">{w.address || '—'}</TableCell>
                <TableCell className="text-xs">{w.city || '—'}</TableCell>
                <TableCell>
                  <button onClick={() => handleToggleActive(w)} className={`text-xs px-2 py-1 rounded ${w.active ? 'bg-[var(--color-success)]/10 text-[var(--color-success)]' : 'bg-[var(--color-neutral-100)] text-[var(--color-text-secondary)]'}`}>
                    {w.active ? 'Actif' : 'Inactif'}
                  </button>
                </TableCell>
                <TableCell>
                  <button onClick={() => handleDelete(w.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]">
                    <Trash2 className="w-4 h-4" />
                  </button>
                </TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}

      {showForm && <WarehouseForm onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadData() }} />}
    </div>
  )
}

function WarehouseForm({ onClose, onSaved }: { onClose: () => void; onSaved: () => void }) {
  const [code, setCode] = useState('')
  const { toast } = useToast()
  const [name, setName] = useState('')
  const [address, setAddress] = useState('')
  const [city, setCity] = useState('')
  const [postalCode, setPostalCode] = useState('')
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      await createWarehouse({ code, name, address: address || null, city: city || null, postal_code: postalCode || null, country: 'France', active: true } as any)
      onSaved()
    } catch (err: any) { toast('error', 'Erreur', err.message || 'échec') }
    finally { setSaving(false) }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl overflow-hidden" style={{ width: '100%', maxWidth: '32rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">Nouveau dépôt</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div className="grid grid-cols-2 gap-4">
            <Input label="Code" required value={code} onChange={(e) => setCode(e.target.value)} placeholder="DEP-01" />
            <Input label="Nom" required value={name} onChange={(e) => setName(e.target.value)} />
          </div>
          <Input label="Adresse" value={address} onChange={(e) => setAddress(e.target.value)} />
          <div className="grid grid-cols-2 gap-4">
            <Input label="Ville" value={city} onChange={(e) => setCity(e.target.value)} />
            <Input label="Code postal" value={postalCode} onChange={(e) => setPostalCode(e.target.value)} />
          </div>
          <div className="flex justify-end gap-3 pt-2">
            <Button variant="secondary" onClick={onClose}>Annuler</Button>
            <Button type="submit" disabled={saving}>{saving ? '...' : 'Créer'}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
