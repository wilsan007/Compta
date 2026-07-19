import { useEffect, useState, useCallback } from 'react'
import { Card, PageHeader, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Input, Button } from '@/components/ui'
import { formatDate } from '@/lib/utils'
import { getStockMovements, getWarehouses, createStockMovement, getProducts } from '@/lib/queries'
import { ClipboardList, Plus, X } from 'lucide-react'
import type { Warehouse, Product } from '@/types'
import { useToast } from '@/lib/toast'

export function InventoryPage() {
const [movements, setMovements] = useState<any[]>([])
  const [warehouses, setWarehouses] = useState<Warehouse[]>([])
  const [products, setProducts] = useState<Product[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)

  const loadData = useCallback(async () => {
    try {
      const [movs, whs, prods] = await Promise.all([getStockMovements(), getWarehouses(), getProducts()])
      setMovements(movs || [])
      setWarehouses(whs || [])
      setProducts(prods || [])
    } catch (err) { console.error('Error:', err) }
    finally { setLoading(false) }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  const adjustments = movements.filter((m) => m.movement_type === 'adjustment' || m.movement_type === 'initial')

  return (
    <div>
      <Breadcrumb items={[{ label: 'Stock' }, { label: 'Inventaire' }]} />
      <PageHeader title="Inventaire" subtitle="Saisies d'inventaire et ajustements"
        action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> Nouvel ajustement</Button>} />

      {loading ? <SkeletonTable rows={6} cols={5} /> : adjustments.length === 0 ? (
        <EmptyState icon={<ClipboardList className="w-8 h-8" />} title="Aucun ajustement" description="Saisissez votre premier inventaire."
          action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> Nouvel ajustement</Button>} />
      ) : (
        <Card>
          <Table headers={['Date', 'Produit', 'Type', 'Quantité', 'Référence', 'Notes']}>
            {adjustments.map((m) => (
              <TableRow key={m.id}>
                <TableCell className="text-xs">{formatDate(m.movement_date)}</TableCell>
                <TableCell className="text-sm">{m.products?.name || '—'}</TableCell>
                <TableCell className="text-xs">{m.movement_type === 'initial' ? 'Stock initial' : 'Ajustement'}</TableCell>
                <TableCell className="font-mono text-xs">{Number(m.quantity)}</TableCell>
                <TableCell className="font-mono text-xs">{m.reference || '—'}</TableCell>
                <TableCell className="text-xs">{m.notes || '—'}</TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}

      {showForm && <AdjustmentForm warehouses={warehouses} products={products} onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadData() }} />}
    </div>
  )
}

function AdjustmentForm({ warehouses, products, onClose, onSaved }: { warehouses: Warehouse[]; products: Product[]; onClose: () => void; onSaved: () => void }) {
  
  const { toast } = useToast()
const [productId, setProductId] = useState('')
  const [warehouseId, setWarehouseId] = useState('')
  const [quantity, setQuantity] = useState(0)
  const [movementDate, setMovementDate] = useState(new Date().toISOString().split('T')[0])
  const [notes, setNotes] = useState('')
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      await createStockMovement({
        product_id: productId, warehouse_id: warehouseId || null,
        movement_type: 'adjustment', quantity, unit_cost: 0,
        reference: 'INV-' + new Date().toISOString().split('T')[0],
        reference_type: 'inventory', reference_id: null,
        movement_date: movementDate, notes: notes || null,
      } as any)
      onSaved()
    } catch (err: any) { toast('error', 'Erreur', err.message || 'échec') }
    finally { setSaving(false) }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl overflow-hidden" style={{ width: '100%', maxWidth: '32rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">Nouvel ajustement</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">Produit</label>
            <select className="input" value={productId} onChange={(e) => setProductId(e.target.value)} required>
              <option value="">— Sélectionner —</option>
              {products.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
            </select>
          </div>
          <div>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">Dépôt</label>
            <select className="input" value={warehouseId} onChange={(e) => setWarehouseId(e.target.value)}>
              <option value="">— Sélectionner —</option>
              {warehouses.map((w) => <option key={w.id} value={w.id}>{w.name}</option>)}
            </select>
          </div>
          <div className="grid grid-cols-2 gap-4">
            <Input label="Quantité" type="number" step="0.01" required value={quantity} onChange={(e) => setQuantity(Number(e.target.value))} />
            <Input label="Date" type="date" required value={movementDate} onChange={(e) => setMovementDate(e.target.value)} />
          </div>
          <Input label="Notes" value={notes} onChange={(e) => setNotes(e.target.value)} />
          <div className="flex justify-end gap-3 pt-2">
            <Button variant="secondary" onClick={onClose}>Annuler</Button>
            <Button type="submit" disabled={saving}>{saving ? '...' : 'Valider'}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
