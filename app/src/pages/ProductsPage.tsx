import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { getProducts, createProduct, deleteProduct, getStockMovements, createStockMovement } from '@/lib/queries'
import { formatCurrency, formatDate } from '@/lib/utils'
import { Package, Plus, Trash2, X, AlertTriangle, ArrowUpDown } from 'lucide-react'
import type { Product, StockMovement } from '@/types'
import { useToast } from '@/lib/toast'
import { useLegislation } from '@/lib/legislation'

export function ProductsPage() {
  const { toast } = useToast()
  const { t } = useTranslation('inventory')
  const { t: tCommon } = useTranslation('common')
const [products, setProducts] = useState<Product[]>([])
  const [movements, setMovements] = useState<StockMovement[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [showMovementForm, setShowMovementForm] = useState(false)
  const [filterType, setFilterType] = useState('')
  const [selectedProduct, setSelectedProduct] = useState<Product | null>(null)

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const [p, m] = await Promise.all([getProducts(), getStockMovements()])
      setProducts(p)
      setMovements(m)
    } catch (err) {
      console.error('Failed to load products:', err)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  async function handleDelete(id: string) {
  if (!window.confirm(tCommon('form.confirmDelete'))) return
    try {
      await deleteProduct(id)
      await loadData()
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.deleteError'))
    }
  }

  const filtered = filterType ? products.filter(p => p.type === filterType) : products
  const lowStockProducts = products.filter(p => p.type === 'stock' && p.stock_quantity <= p.reorder_level)

  return (
    <div>
      <Breadcrumb items={[{ label: t('products.title') }]} />
      <PageHeader
        title={t('products.title')}
        subtitle={t('products.subtitle')}
        action={
          <div className="flex gap-2">
            <Button variant="secondary" onClick={() => setShowMovementForm(true)}><ArrowUpDown className="w-4 h-4" /> {t('products.stockMovement')}</Button>
            <Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('products.new')}</Button>
          </div>
        }
      />

      {lowStockProducts.length > 0 && (
        <div className="mb-4 p-3 rounded-lg bg-[var(--color-warning)]/10 border border-[var(--color-warning)]/30 flex items-center gap-2 text-sm">
          <AlertTriangle className="w-4 h-4 text-[var(--color-warning)]" />
          <span className="text-[var(--color-text)]"><strong>{lowStockProducts.length}</strong> {t('products.lowStockWarning')}: {lowStockProducts.map(p => p.name).join(', ')}</span>
        </div>
      )}

      <div className="mb-4 flex items-center gap-3">
        <Select value={filterType} onChange={(e) => setFilterType(e.target.value)} className="max-w-xs" options={[
          { value: '', label: t('products.allTypes') },
          { value: 'stock', label: t('products.types.stock') },
          { value: 'service', label: t('products.types.service') },
        ]} />
        <span className="text-sm text-[var(--color-text-secondary)]">{filtered.length} {t('products.products')}</span>
      </div>

      {loading ? (
        <SkeletonTable rows={5} cols={7} />
      ) : filtered.length === 0 ? (
        <EmptyState
          icon={<Package className="w-8 h-8" />}
          title={t('products.noProducts')}
          description={t('products.noProductsDescription')}
          action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('products.new')}</Button>}
        />
      ) : (
        <Card>
          <Table headers={[t('products.name'), 'SKU', tCommon('common.type'), t('products.salePrice'), t('products.purchasePrice'), tCommon('common.stock'), tCommon('table.actions')]}>
            {filtered.map((p) => (
              <TableRow key={p.id} onClick={() => setSelectedProduct(p)}>
                <TableCell className="font-medium">{p.name}</TableCell>
                <TableCell className="font-mono text-xs">{p.sku || '—'}</TableCell>
                <TableCell><Badge variant={p.type === 'stock' ? 'primary' : 'neutral'}>{t(`products.types.${p.type}`)}</Badge></TableCell>
                <TableCell className="font-mono text-right">{formatCurrency(Number(p.sale_price))}</TableCell>
                <TableCell className="font-mono text-right">{formatCurrency(Number(p.purchase_price))}</TableCell>
                <TableCell className="font-mono">
                  {p.type === 'stock' ? (
                    <span className={Number(p.stock_quantity) <= Number(p.reorder_level) ? 'text-[var(--color-danger)] font-bold' : ''}>
                      {p.stock_quantity} {p.unit}
                    </span>
                  ) : '—'}
                </TableCell>
                <TableCell>
                  <button onClick={(e) => { e.stopPropagation(); handleDelete(p.id) }} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]">
                    <Trash2 className="w-4 h-4" />
                  </button>
                </TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}

      {selectedProduct && (
        <ProductDetailModal product={selectedProduct} movements={movements.filter(m => m.product_id === selectedProduct.id)} onClose={() => setSelectedProduct(null)} />
      )}

      {showForm && (
        <ProductForm onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadData() }} />
      )}

      {showMovementForm && (
        <StockMovementForm products={products} onClose={() => setShowMovementForm(false)} onSaved={() => { setShowMovementForm(false); loadData() }} />
      )}
    </div>
  )
}

function ProductForm({ onClose, onSaved }: { onClose: () => void; onSaved: () => void }) {
  const [name, setName] = useState('')
  const { toast } = useToast()
  const { t } = useTranslation('inventory')
  const { t: tCommon } = useTranslation('common')
  const { defaultVatRate } = useLegislation()
  const [sku, setSku] = useState('')
  const [type, setType] = useState('stock')
  const [salePrice, setSalePrice] = useState(0)
  const [purchasePrice, setPurchasePrice] = useState(0)
  const [vatRate, setVatRate] = useState(defaultVatRate)
  const [stockQty, setStockQty] = useState(0)
  const [reorderLevel, setReorderLevel] = useState(0)
  const [unit, setUnit] = useState('unité')
  const [category, setCategory] = useState('')
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      await createProduct({
        name, sku: sku || undefined, type: type as any,
        sale_price: salePrice, purchase_price: purchasePrice, vat_rate: vatRate,
        stock_quantity: stockQty, reorder_level: reorderLevel, unit, category,
        active: true, description: '',
      } as any)
      onSaved()
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.createError'))
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4 overflow-y-auto">
      <div className="card shadow-2xl overflow-hidden my-8" style={{ width: '100%', maxWidth: '36rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('products.new')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <Input label={t('products.name')} required value={name} onChange={(e) => setName(e.target.value)} />
          <div className="grid grid-cols-2 gap-4">
            <Input label="SKU" value={sku} onChange={(e) => setSku(e.target.value)} />
            <Select label={tCommon('common.type')} value={type} onChange={(e) => setType(e.target.value)} options={[
              { value: 'stock', label: t('products.types.stock') },
              { value: 'service', label: t('products.types.service') },
            ]} />
          </div>
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('products.salePrice')} type="number" step="0.01" value={salePrice} onChange={(e) => setSalePrice(Number(e.target.value))} />
            <Input label={t('products.purchasePrice')} type="number" step="0.01" value={purchasePrice} onChange={(e) => setPurchasePrice(Number(e.target.value))} />
          </div>
          <div className="grid grid-cols-3 gap-4">
            <Input label={t('products.vatRate')} type="number" step="0.01" value={vatRate} onChange={(e) => setVatRate(Number(e.target.value))} />
            <Input label={t('products.category')} value={category} onChange={(e) => setCategory(e.target.value)} />
            <Input label={t('products.unit')} value={unit} onChange={(e) => setUnit(e.target.value)} />
          </div>
          {type === 'stock' && (
            <div className="grid grid-cols-2 gap-4">
              <Input label={t('products.initialQty')} type="number" step="0.01" value={stockQty} onChange={(e) => setStockQty(Number(e.target.value))} />
              <Input label={t('products.reorderLevel')} type="number" step="0.01" value={reorderLevel} onChange={(e) => setReorderLevel(Number(e.target.value))} />
            </div>
          )}
          <div className="flex justify-end gap-3 pt-4 border-t border-[var(--color-border)]">
            <Button type="button" variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? tCommon('actions.saving') : tCommon('actions.create')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}

function StockMovementForm({ products, onClose, onSaved }: { products: Product[]; onClose: () => void; onSaved: () => void }) {
  const [productId, setProductId] = useState('')
  const { toast } = useToast()
  const { t } = useTranslation('inventory')
  const { t: tCommon } = useTranslation('common')
  const [type, setType] = useState('in')
  const [quantity, setQuantity] = useState(0)
  const [reference, setReference] = useState('')
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      await createStockMovement({
        product_id: productId,
        type: type as any,
        quantity,
        reference,
        date: new Date().toISOString().split('T')[0],
      } as any)
      onSaved()
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.createError'))
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '32rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('products.stockMovement')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <Select label={t('products.product')} required value={productId} onChange={(e) => setProductId(e.target.value)} options={[
            { value: '', label: tCommon('form.selectOption') },
            ...products.filter(p => p.type === 'stock').map(p => ({ value: p.id, label: `${p.name} (${tCommon('common.stock')}: ${p.stock_quantity})` })),
          ]} />
          <Select label={tCommon('common.type')} value={type} onChange={(e) => setType(e.target.value)} options={[
            { value: 'in', label: t('products.movementTypes.in') },
            { value: 'out', label: t('products.movementTypes.out') },
            { value: 'adjustment', label: t('products.movementTypes.adjustment') },
          ]} />
          <Input label={t('products.quantity')} type="number" step="0.01" required value={quantity} onChange={(e) => setQuantity(Number(e.target.value))} />
          <Input label={tCommon('common.reference')} value={reference} onChange={(e) => setReference(e.target.value)} placeholder={tCommon('common.optional')} />
          <div className="flex justify-end gap-3 pt-4 border-t border-[var(--color-border)]">
            <Button type="button" variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving || !productId}>{saving ? '...' : tCommon('actions.validate')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}

function ProductDetailModal({ product, movements, onClose }: { product: Product; movements: StockMovement[]; onClose: () => void }) {
  const { t } = useTranslation('inventory')
  const { t: tCommon } = useTranslation('common')
  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4 overflow-y-auto">
      <div className="card shadow-2xl overflow-hidden my-8" style={{ width: '100%', maxWidth: '42rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{product.name}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <div className="p-6 space-y-4">
          <div className="grid grid-cols-3 gap-4 text-sm">
            <div><span className="text-[var(--color-text-secondary)]">SKU:</span> <span className="font-mono">{product.sku || '—'}</span></div>
            <div><span className="text-[var(--color-text-secondary)]">{tCommon('common.type')}:</span> {t(`products.types.${product.type}`)}</div>
            <div><span className="text-[var(--color-text-secondary)]">{t('products.category')}:</span> {product.category || '—'}</div>
            <div><span className="text-[var(--color-text-secondary)]">{t('products.salePrice')}:</span> <span className="font-mono">{formatCurrency(Number(product.sale_price))}</span></div>
            <div><span className="text-[var(--color-text-secondary)]">{t('products.purchasePrice')}:</span> <span className="font-mono">{formatCurrency(Number(product.purchase_price))}</span></div>
            <div><span className="text-[var(--color-text-secondary)]">{t('products.vatRate')}:</span> {product.vat_rate}%</div>
            {product.type === 'stock' && (
              <div><span className="text-[var(--color-text-secondary)]">{tCommon('common.stock')}:</span> <span className="font-mono font-bold">{product.stock_quantity} {product.unit}</span></div>
            )}
          </div>
          {movements.length > 0 && (
            <div>
              <h3 className="text-sm font-semibold mb-2">{t('products.recentMovements')}</h3>
              <div className="border border-[var(--color-border)] rounded-lg overflow-hidden">
                <table className="app-table min-w-[760px]">
                  <thead className="bg-[var(--color-neutral-50)]">
                    <tr>
                      <th className="px-3 py-2 text-left text-xs font-semibold">{tCommon('common.date')}</th>
                      <th className="px-3 py-2 text-left text-xs font-semibold">{tCommon('common.type')}</th>
                      <th className="px-3 py-2 text-right text-xs font-semibold">{t('products.quantity')}</th>
                      <th className="px-3 py-2 text-left text-xs font-semibold">{tCommon('common.reference')}</th>
                    </tr>
                  </thead>
                  <tbody>
                    {movements.slice(0, 10).map((m) => (
                      <tr key={m.id} className="border-t border-[var(--color-border)]">
                        <td className="px-3 py-2 text-xs">{formatDate(m.movement_date || m.created_at)}</td>
                        <td className="px-3 py-2 text-xs">{t(`products.movementTypes.${m.movement_type}`, { defaultValue: m.movement_type })}</td>
                        <td className="px-3 py-2 text-xs text-right font-mono">{m.quantity}</td>
                        <td className="px-3 py-2 text-xs">{m.reference || m.notes || '—'}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
