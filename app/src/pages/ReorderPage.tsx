import { useEffect, useState, useCallback } from 'react'
import { Card, PageHeader, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Button, Input, Select } from '@/components/ui'
import { errorMessage, formatCurrency } from '@/lib/utils'
import {
  getStockQuantities, getReorderRules, createReorderRule, deleteReorderRule,
  getReorderSuggestions, getProducts, getWarehouses,
  type ReorderRule, type ReorderSuggestion,
} from '@/lib/queries/stock'
import { AlertTriangle, ShoppingCart, Plus, Trash2, X, ClipboardList } from 'lucide-react'
import { useTranslation } from 'react-i18next'
import { useToast } from '@/lib/toast'
import { confirmSync } from '@/lib/confirm'
import type { Product, Warehouse } from '@/types'

export function ReorderPage() {
  const { t } = useTranslation('stock')
  const { t: tNav } = useTranslation('nav')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [stock, setStock] = useState<Awaited<ReturnType<typeof getStockQuantities>>>([])
  const [rules, setRules] = useState<ReorderRule[]>([])
  const [suggestions, setSuggestions] = useState<ReorderSuggestion[]>([])
  const [products, setProducts] = useState<Product[]>([])
  const [warehouses, setWarehouses] = useState<Warehouse[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)

  const loadData = useCallback(async () => {
    try {
      const [st, rs, sug, prods, whs] = await Promise.all([
        getStockQuantities(), getReorderRules(), getReorderSuggestions(), getProducts(), getWarehouses(),
      ])
      setStock(st); setRules(rs); setSuggestions(sug); setProducts(prods); setWarehouses(whs)
    } catch (err) { console.error('Error:', err); toast('error', tCommon('toast.error'), errorMessage(err) || tCommon('toast.loadingError')) }
    finally { setLoading(false) }
  }, [toast, tCommon])

  useEffect(() => { loadData() }, [loadData])

  const productName = (id: string) => products.find((p) => p.id === id)?.name ?? '—'
  const whName = (id: string | null) => (id ? (warehouses.find((w) => w.id === id)?.name ?? '—') : t('reorder.allWarehouses'))

  async function handleDeleteRule(id: string) {
    if (!confirmSync(t('reorder.confirmDeleteRule'))) return
    try { await deleteReorderRule(id); await loadData() }
    catch (err) { toast('error', tCommon('toast.error'), errorMessage(err) || tCommon('toast.error')) }
  }

  const reorderItems = stock.filter((q) => q.reorder_point > 0 && Number(q.quantity) <= Number(q.reorder_point))
  const totalReorderValue = reorderItems.reduce((s, q) => s + (Number(q.reorder_point) - Number(q.quantity)) * Number(q.unit_cost), 0)

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('groups.stock') }, { label: t('reorder.title') }]} />
      <PageHeader title={t('reorder.title')} subtitle={`${reorderItems.length} ${t('reorder.product').toLowerCase()}(s)`} />

      <div className="grid grid-cols-2 gap-4 mb-6">
        <Card><div className="p-4"><p className="text-sm text-[var(--color-text-secondary)] flex items-center gap-1"><AlertTriangle className="w-4 h-4 text-[var(--color-danger)]" /> {t('reorder.itemsToReorder')}</p><p className="text-2xl font-bold text-[var(--color-danger)]">{reorderItems.length}</p></div></Card>
        <Card><div className="p-4"><p className="text-sm text-[var(--color-text-secondary)] flex items-center gap-1"><ShoppingCart className="w-4 h-4 text-[var(--color-primary)]" /> {t('reorder.estimatedValue')}</p><p className="text-2xl font-bold font-mono">{formatCurrency(totalReorderValue)}</p></div></Card>
      </div>

      {loading ? <SkeletonTable rows={6} cols={6} /> : reorderItems.length === 0 ? (
        <EmptyState icon={<ShoppingCart className="w-8 h-8" />} title={t('reorder.noReorder')} description={t('reorder.allGood')} />
      ) : (
        <Card>
          <Table headers={[t('reorder.product'), t('reorder.sku'), t('quantities.warehouse'), t('reorder.currentStock'), t('reorder.reorderPoint'), t('reorder.toOrder'), t('reorder.estimatedCost')]}>
            {reorderItems.map((q) => {
              const toOrder = Number(q.reorder_point) - Number(q.quantity)
              return (
                <TableRow key={q.id}>
                  <TableCell className="text-sm">{q.products?.name || '—'}</TableCell>
                  <TableCell className="font-mono text-xs">{q.products?.sku || '—'}</TableCell>
                  <TableCell className="text-xs">{q.warehouses?.name || '—'}</TableCell>
                  <TableCell className="font-mono text-xs text-[var(--color-danger)]">{Number(q.quantity)}</TableCell>
                  <TableCell className="font-mono text-xs">{Number(q.reorder_point)}</TableCell>
                  <TableCell className="font-mono text-xs font-bold text-[var(--color-warning-text)]">{toOrder}</TableCell>
                  <TableCell className="font-mono text-xs text-right">{formatCurrency(toOrder * Number(q.unit_cost))}</TableCell>
                </TableRow>
              )
            })}
          </Table>
        </Card>
      )}

      <div className="mt-6 space-y-6">
        <Card>
          <div className="p-4 border-b border-[var(--color-border)] flex items-center justify-between">
            <h3 className="font-semibold">{t('reorder.rules')}</h3>
            <Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('reorder.newRule')}</Button>
          </div>
          {rules.length === 0 ? (
            <EmptyState icon={<ClipboardList className="w-8 h-8" />} title={t('reorder.noRules')} description={t('reorder.noRulesDescription')} />
          ) : (
            <Table headers={[t('reorder.product'), t('quantities.warehouse'), t('reorder.min'), t('reorder.max'), t('reorder.multiple'), tCommon('common.actions')]}>
              {rules.map((r) => (
                <TableRow key={r.id}>
                  <TableCell className="text-sm">{productName(r.product_id)}</TableCell>
                  <TableCell className="text-sm">{whName(r.warehouse_id)}</TableCell>
                  <TableCell className="font-mono text-xs">{Number(r.min_quantity)}</TableCell>
                  <TableCell className="font-mono text-xs">{Number(r.max_quantity)}</TableCell>
                  <TableCell className="font-mono text-xs">{Number(r.multiple_quantity ?? 1)}</TableCell>
                  <TableCell>
                    <button onClick={() => handleDeleteRule(r.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]" aria-label={tCommon('actions.delete')} title={tCommon('actions.delete')}><Trash2 className="w-4 h-4" aria-hidden="true" /></button>
                  </TableCell>
                </TableRow>
              ))}
            </Table>
          )}
        </Card>

        <Card>
          <div className="p-4 border-b border-[var(--color-border)]"><h3 className="font-semibold">{t('reorder.suggestions')}</h3></div>
          {suggestions.length === 0 ? (
            <EmptyState icon={<ShoppingCart className="w-8 h-8" />} title={t('reorder.noSuggestions')} description={t('reorder.noSuggestionsDescription')} />
          ) : (
            <Table headers={[t('reorder.product'), t('quantities.warehouse'), t('reorder.currentStock'), t('reorder.min'), t('reorder.max'), t('reorder.toOrder')]}>
              {suggestions.map((s) => (
                <TableRow key={`${s.product_id}-${s.warehouse_id ?? 'all'}`}>
                  <TableCell className="text-sm">{s.product_name}</TableCell>
                  <TableCell className="text-sm">{s.warehouse_name ?? t('reorder.allWarehouses')}</TableCell>
                  <TableCell className="font-mono text-xs text-[var(--color-danger)]">{Number(s.stock)}</TableCell>
                  <TableCell className="font-mono text-xs">{Number(s.min_quantity)}</TableCell>
                  <TableCell className="font-mono text-xs">{Number(s.max_quantity)}</TableCell>
                  <TableCell className="font-mono text-xs font-bold text-[var(--color-warning-text)]">{Number(s.suggested_qty)}</TableCell>
                </TableRow>
              ))}
            </Table>
          )}
        </Card>
      </div>

      {showForm && <ReorderRuleForm products={products} warehouses={warehouses} onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadData() }} />}
    </div>
  )
}

function ReorderRuleForm({ products, warehouses, onClose, onSaved }: { products: Product[]; warehouses: Warehouse[]; onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation('stock')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [productId, setProductId] = useState('')
  const [warehouseId, setWarehouseId] = useState('')
  const [min, setMin] = useState(0)
  const [max, setMax] = useState(0)
  const [multiple, setMultiple] = useState(1)
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!productId) { toast('error', tCommon('toast.error'), t('reorder.selectProduct')); return }
    if (max < min) { toast('error', tCommon('toast.error'), t('reorder.maxBelowMin')); return }
    setSaving(true)
    try {
      await createReorderRule({ product_id: productId, warehouse_id: warehouseId || null, min_quantity: min, max_quantity: max, multiple_quantity: multiple, lead_time_days: null, is_active: true })
      onSaved()
    } catch (err) { toast('error', tCommon('toast.error'), errorMessage(err) || tCommon('toast.error')) }
    finally { setSaving(false) }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl overflow-hidden" style={{ width: '100%', maxWidth: '32rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('reorder.newRule')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]" aria-label={tCommon('actions.close')} title={tCommon('actions.close')}><X className="w-5 h-5" aria-hidden="true" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('reorder.product')}</label>
            <select className="input" value={productId} onChange={(e) => setProductId(e.target.value)} required>
              <option value="">{t('reorder.selectProduct')}</option>
              {products.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
            </select>
          </div>
          <Select label={t('quantities.warehouse')} value={warehouseId} onChange={(e) => setWarehouseId(e.target.value)} options={[{ value: '', label: t('reorder.allWarehouses') }, ...warehouses.map((w) => ({ value: w.id, label: w.name }))]} />
          <div className="grid grid-cols-3 gap-4">
            <Input label={t('reorder.min')} type="number" step="0.01" required value={min} onChange={(e) => setMin(Number(e.target.value))} />
            <Input label={t('reorder.max')} type="number" step="0.01" required value={max} onChange={(e) => setMax(Number(e.target.value))} />
            <Input label={t('reorder.multiple')} type="number" step="0.01" value={multiple} onChange={(e) => setMultiple(Number(e.target.value))} />
          </div>
          <div className="flex justify-end gap-3 pt-2">
            <Button variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? tCommon('actions.saving') : tCommon('actions.create')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
