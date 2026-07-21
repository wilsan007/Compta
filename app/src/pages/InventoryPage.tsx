import { useEffect, useState, useCallback } from 'react'
import { Card, PageHeader, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Input, Button } from '@/components/ui'
import { formatDate } from '@/lib/utils'
import { getStockMovements, getWarehouses, createStockMovement, getProducts } from '@/lib/queries'
import { ClipboardList, Plus, X } from 'lucide-react'
import type { Warehouse, Product } from '@/types'
import { useToast } from '@/lib/toast'
import { useTranslation } from 'react-i18next'

export function InventoryPage() {
  const { t } = useTranslation('stock')
  const { t: tNav } = useTranslation('nav')
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
      <Breadcrumb items={[{ label: tNav('sections.stock') }, { label: t('inventory.title') }]} />
      <PageHeader title={t('inventory.title')} subtitle={t('inventory.subtitle')}
        action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('inventory.newAdjustment')}</Button>} />

      {loading ? <SkeletonTable rows={6} cols={5} /> : adjustments.length === 0 ? (
        <EmptyState icon={<ClipboardList className="w-8 h-8" />} title={t('inventory.noAdjustments')} description={t('inventory.noAdjustmentsDescription')}
          action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('inventory.newAdjustment')}</Button>} />
      ) : (
        <Card>
          <Table headers={[t('inventory.date'), t('inventory.product'), t('inventory.title'), t('inventory.quantity'), t('inventory.reference'), t('inventory.notes')]}>
            {adjustments.map((m) => (
              <TableRow key={m.id}>
                <TableCell className="text-xs">{formatDate(m.movement_date)}</TableCell>
                <TableCell className="text-sm">{m.products?.name || '—'}</TableCell>
                <TableCell className="text-xs">{m.movement_type === 'initial' ? t('inventory.initialStock') : t('inventory.adjustment')}</TableCell>
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
  const { t } = useTranslation('stock')
  const { t: tCommon } = useTranslation('common')
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
    } catch (err: any) { toast('error', tCommon('common.error'), err.message || tCommon('common.error')) }
    finally { setSaving(false) }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl overflow-hidden" style={{ width: '100%', maxWidth: '32rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('inventory.newAdjustment')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('inventory.product')}</label>
            <select className="input" value={productId} onChange={(e) => setProductId(e.target.value)} required>
              <option value="">{tCommon('form.selectPlaceholder') || '—'}</option>
              {products.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
            </select>
          </div>
          <div>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('inventory.warehouse')}</label>
            <select className="input" value={warehouseId} onChange={(e) => setWarehouseId(e.target.value)}>
              <option value="">{tCommon('form.selectPlaceholder') || '—'}</option>
              {warehouses.map((w) => <option key={w.id} value={w.id}>{w.name}</option>)}
            </select>
          </div>
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('inventory.quantity')} type="number" step="0.01" required value={quantity} onChange={(e) => setQuantity(Number(e.target.value))} />
            <Input label={t('inventory.date')} type="date" required value={movementDate} onChange={(e) => setMovementDate(e.target.value)} />
          </div>
          <Input label={t('inventory.notes')} value={notes} onChange={(e) => setNotes(e.target.value)} />
          <div className="flex justify-end gap-3 pt-2">
            <Button variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? '...' : t('inventory.validate')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
