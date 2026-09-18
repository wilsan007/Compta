import { useEffect, useState, useCallback } from 'react'
import { Card, PageHeader, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Input, Button, Select } from '@/components/ui'
import { formatDate, formatCurrency } from '@/lib/utils'
import { getStockMovements, getWarehouses, createStockMovement, getProducts } from '@/lib/queries/stock'
import { calculateStockValuation, calculateInventoryVariance } from '@/lib/queries/businessFunctions'
import { ClipboardList, Plus, X, Calculator } from 'lucide-react'
import type { Warehouse, Product } from '@/types'
import { useToast } from '@/lib/toast'
import { useTranslation } from 'react-i18next'

interface StockValuationRow {
  product_id: string
  product_name: string
  warehouse_id: string | null
  quantity: number
  unit_cost: number
  total_value: number
  method: string
}

export function InventoryPage() {
  const { t } = useTranslation('stock')
  const { t: tNav } = useTranslation('nav')
const [movements, setMovements] = useState<any[]>([])
  const [warehouses, setWarehouses] = useState<Warehouse[]>([])
  const [products, setProducts] = useState<Product[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [selectedWarehouse, setSelectedWarehouse] = useState('')
  const [valuationMethod, setValuationMethod] = useState('cump')
  const [valuationRows, setValuationRows] = useState<StockValuationRow[]>([])
  const [valuationLoading, setValuationLoading] = useState(false)
  const [showValuation, setShowValuation] = useState(false)
  const { toast } = useToast()
  const { t: tCommon } = useTranslation("common")

  const loadData = useCallback(async () => {
    try {
      const [movs, whs, prods] = await Promise.all([getStockMovements(), getWarehouses(), getProducts()])
      setMovements(movs || [])
      setWarehouses(whs || [])
      setProducts(prods || [])
    } catch (err: any) { console.error('Error:', err); toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadError')) }
    finally { setLoading(false) }
  }, [toast, tCommon])

  useEffect(() => { loadData() }, [loadData])

  async function handleValuation() {
    setValuationLoading(true)
    setShowValuation(true)
    try {
      const res = await calculateStockValuation(valuationMethod, selectedWarehouse || undefined)
      const rows = Array.isArray(res) ? res : (res ? [res] : [])
      setValuationRows(rows)
      const total = rows.reduce((sum, r) => sum + Number(r.total_value || 0), 0)
      toast('success', t('inventory.title'), `${rows.length} produits — ${formatCurrency(total)}`)
    } catch (err: any) { toast('error', t('inventory.title'), err.message || 'Erreur') }
    finally { setValuationLoading(false) }
  }

  async function handleVariance() {
    try {
      const res = await calculateInventoryVariance(selectedWarehouse || undefined)
      toast('success', t('inventory.title'), JSON.stringify(res))
    } catch (err: any) { toast('error', t('inventory.title'), err.message || 'Erreur') }
  }

  const adjustments = movements.filter((m) => m.movement_type === 'adjustment' || m.movement_type === 'initial')

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('sections.stock') }, { label: t('inventory.title') }]} />
      <PageHeader title={t('inventory.title')} subtitle={t('inventory.subtitle')}
        action={
          <div className="flex gap-2">
            <Button variant="secondary" onClick={handleValuation}>Valoriser le stock</Button>
            <Button variant="secondary" onClick={handleVariance}>Calculer les écarts</Button>
            <Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('inventory.newAdjustment')}</Button>
          </div>
        } />

      <div className="flex gap-3 mb-4 items-end">
        <div className="w-56">
          <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('inventory.warehouse')}</label>
          <select className="input" value={selectedWarehouse} onChange={(e) => setSelectedWarehouse(e.target.value)}>
            <option value="">{t('common.all') || '—'}</option>
            {warehouses.map((w) => <option key={w.id} value={w.id}>{w.name}</option>)}
          </select>
        </div>
        <div className="w-48">
          <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('inventory.valuationMethod')}</label>
          <Select value={valuationMethod} onChange={(e) => setValuationMethod(e.target.value)} options={[
            { value: 'cump', label: t('inventory.methods.cump') },
            { value: 'fifo', label: t('inventory.methods.fifo') },
            { value: 'lifo', label: t('inventory.methods.lifo') },
          ]} />
        </div>
      </div>

      {showValuation && (
        <Card className="mb-4">
          <div className="flex items-center justify-between px-4 py-3 border-b border-[var(--color-border)]">
            <h3 className="text-sm font-semibold flex items-center gap-2">
              <Calculator className="w-4 h-4" /> {t('inventory.valuationResult')} — {t(`inventory.methods.${valuationMethod}`)}
            </h3>
            <button onClick={() => setShowValuation(false)} className="p-1 rounded hover:bg-[var(--color-neutral-100)]" aria-label={tCommon('actions.close')} title={tCommon('actions.close')}><X className="w-4 h-4" aria-hidden="true" /></button>
          </div>
          {valuationLoading ? (
            <SkeletonTable rows={4} cols={5} />
          ) : valuationRows.length === 0 ? (
            <EmptyState icon={<ClipboardList className="w-8 h-8" />} title={t('inventory.noValuation')} description={t('inventory.noValuationDescription')} />
          ) : (
            <Table headers={[t('inventory.product'), t('inventory.quantity'), t('inventory.unitCost'), t('inventory.totalValue'), t('inventory.method')]}>
              {valuationRows.map((r) => (
                <TableRow key={r.product_id + (r.warehouse_id || '')}>
                  <TableCell className="font-medium">{r.product_name || '—'}</TableCell>
                  <TableCell className="font-mono text-right">{Number(r.quantity || 0)}</TableCell>
                  <TableCell className="font-mono text-right">{formatCurrency(Number(r.unit_cost || 0))}</TableCell>
                  <TableCell className="font-mono text-right font-semibold">{formatCurrency(Number(r.total_value || 0))}</TableCell>
                  <TableCell><span className="text-xs uppercase text-[var(--color-text-secondary)]">{r.method || valuationMethod}</span></TableCell>
                </TableRow>
              ))}
            </Table>
          )}
          {valuationRows.length > 0 && (
            <div className="px-4 py-3 border-t border-[var(--color-border)] text-right">
              <span className="text-sm text-[var(--color-text-secondary)]">{t('inventory.grandTotal')}: </span>
              <span className="font-bold font-mono">{formatCurrency(valuationRows.reduce((s, r) => s + Number(r.total_value || 0), 0))}</span>
            </div>
          )}
        </Card>
      )}

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
  const [unitCost, setUnitCost] = useState(0)
  const [movementType, setMovementType] = useState<'adjustment' | 'initial'>('adjustment')
  const [movementDate, setMovementDate] = useState(new Date().toISOString().split('T')[0])
  const [notes, setNotes] = useState('')
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      await createStockMovement({
        product_id: productId, warehouse_id: warehouseId || null,
        movement_type: movementType, quantity, unit_cost: unitCost,
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
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]" aria-label={tCommon('actions.close')} title={tCommon('actions.close')}><X className="w-5 h-5" aria-hidden="true" /></button>
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
            <div>
              <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('inventory.type', { defaultValue: 'Type' })}</label>
              <select className="input" value={movementType} onChange={(e) => setMovementType(e.target.value as 'adjustment' | 'initial')}>
                <option value="adjustment">{t('inventory.adjustment')}</option>
                <option value="initial">{t('inventory.initialStock')}</option>
              </select>
            </div>
            <Input label={t('inventory.quantity')} type="number" step="0.01" required value={quantity} onChange={(e) => setQuantity(Number(e.target.value))} />
          </div>
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('inventory.unitCost', { defaultValue: 'Coût unitaire' })} type="number" step="0.01" value={unitCost} onChange={(e) => setUnitCost(Number(e.target.value))} />
            <Input label={t('inventory.date')} type="date" required value={movementDate} onChange={(e) => setMovementDate(e.target.value)} />
          </div>
          <Input label={t('inventory.notes')} value={notes} onChange={(e) => setNotes(e.target.value)} />
          <div className="flex justify-end gap-3 pt-2">
            <Button variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? tCommon('actions.saving') : t('inventory.validate')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
