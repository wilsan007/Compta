import { useState, useEffect, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, Button, Table, TableRow, TableCell, Badge, EmptyState, Select, Input } from '@/components/ui'
import { formatCurrency } from '@/lib/utils'
import { getProducts, getProductGrids, createProductGrid, deleteProductGrid, getProductGridCombinations, generateAllCombinations } from '@/lib/queries'
import { useToast } from '@/lib/toast'
import { Plus, Trash2, X, Grid3x3, Sparkles } from 'lucide-react'
import type { Product, ProductGrid, ProductGridCombination } from '@/types'

export function ProductGridsPage() {
  const { t } = useTranslation('stock')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [products, setProducts] = useState<Product[]>([])
  const [selectedProduct, setSelectedProduct] = useState('')
  const [grids, setGrids] = useState<ProductGrid[]>([])
  const [combinations, setCombinations] = useState<ProductGridCombination[]>([])
  const [loading, setLoading] = useState(false)
  const [showGridForm, setShowGridForm] = useState(false)

  useEffect(() => {
    (async () => {
      try {
        const prods = await getProducts()
        setProducts(prods || [])
      } catch (err: any) {
        toast('error', tCommon('toast.error'), err.message)
      }
    })()
  }, [])

  const loadGrids = useCallback(async (productId: string) => {
    if (!productId) { setGrids([]); setCombinations([]); return }
    setLoading(true)
    try {
      const [g, c] = await Promise.all([getProductGrids(productId), getProductGridCombinations(productId)])
      setGrids(g || [])
      setCombinations(c || [])
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => { if (selectedProduct) loadGrids(selectedProduct) }, [selectedProduct, loadGrids])

  async function handleGenerate() {
    if (!selectedProduct) return
    try {
      await generateAllCombinations(selectedProduct)
      toast('success', tCommon('toast.success'), t('grids.combinationsGenerated'))
      await loadGrids(selectedProduct)
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message)
    }
  }

  async function handleDeleteGrid(id: string) {
    try {
      await deleteProductGrid(id)
      toast('success', tCommon('toast.success'), tCommon('toast.deleted'))
      if (selectedProduct) await loadGrids(selectedProduct)
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message)
    }
  }

  return (
    <div className="p-6 max-w-7xl mx-auto">
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-2xl font-bold flex items-center gap-2">
            <Grid3x3 className="w-6 h-6 text-[var(--color-primary)]" />
            {t('grids.title')}
          </h1>
          <p className="text-sm text-[var(--color-text-secondary)] mt-1">{t('grids.subtitle')}</p>
        </div>
        <div className="flex gap-2">
          {grids.length > 0 && (
            <Button variant="secondary" onClick={handleGenerate}>
              <Sparkles className="w-4 h-4" /> {t('grids.generateCombinations')}
            </Button>
          )}
          {selectedProduct && (
            <Button onClick={() => setShowGridForm(true)}>
              <Plus className="w-4 h-4" /> {t('grids.new')}
            </Button>
          )}
        </div>
      </div>

      <div className="mb-6">
        <Select
          label={t('grids.product')}
          value={selectedProduct}
          onChange={(e) => setSelectedProduct(e.target.value)}
          options={[
            { value: '', label: tCommon('select.choose') },
            ...products.map(p => ({ value: p.id, label: `${p.name} (${p.sku || '-'})` })),
          ]}
        />
      </div>

      {!selectedProduct ? (
        <EmptyState
          icon={<Grid3x3 className="w-8 h-8" />}
          title={t('grids.title')}
          description={t('grids.noGridsDescription')}
        />
      ) : loading ? (
        <div className="space-y-2">
          {[1, 2, 3].map(i => <div key={i} className="h-12 rounded animate-pulse bg-[var(--color-neutral-100)]" />)}
        </div>
      ) : (
        <div className="space-y-6">
          <Card>
            <div className="px-4 py-3 border-b border-[var(--color-border)]">
              <h3 className="text-sm font-semibold">{t('grids.title')}</h3>
            </div>
            {grids.length === 0 ? (
              <EmptyState
                icon={<Grid3x3 className="w-6 h-6" />}
                title={t('grids.noGrids')}
                description={t('grids.noGridsDescription')}
              />
            ) : (
              <Table headers={[t('grids.name'), t('grids.axis'), t('grids.values'), tCommon('table.status'), tCommon('table.actions')]}>
                {grids.map((g) => (
                  <TableRow key={g.id}>
                    <TableCell className="font-medium">{g.name}</TableCell>
                    <TableCell className="text-xs">{t(`grids.${g.axis}`)}</TableCell>
                    <TableCell className="text-xs">{(g.values || []).join(', ')}</TableCell>
                    <TableCell>
                      <Badge variant={g.active ? 'success' : 'neutral'}>{g.active ? tCommon('status.active') : tCommon('status.inactive')}</Badge>
                    </TableCell>
                    <TableCell>
                      <button onClick={() => handleDeleteGrid(g.id)} className="p-1 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]">
                        <Trash2 className="w-4 h-4" />
                      </button>
                    </TableCell>
                  </TableRow>
                ))}
              </Table>
            )}
          </Card>

          {combinations.length > 0 && (
            <Card>
              <div className="px-4 py-3 border-b border-[var(--color-border)]">
                <h3 className="text-sm font-semibold">{t('grids.combinations')}</h3>
              </div>
              <Table headers={[t('grids.matrix'), t('grids.sku'), t('grids.barcode'), t('grids.priceOverride'), t('grids.stock'), tCommon('table.status')]}>
                {combinations.map((c) => (
                  <TableRow key={c.id}>
                    <TableCell className="text-xs">{Object.entries(c.combination || {}).map(([k, v]) => `${k}: ${v}`).join(' | ')}</TableCell>
                    <TableCell className="font-mono text-xs">{c.sku || '-'}</TableCell>
                    <TableCell className="font-mono text-xs">{c.barcode || '-'}</TableCell>
                    <TableCell className="font-mono text-xs">{c.price_override ? formatCurrency(Number(c.price_override)) : '-'}</TableCell>
                    <TableCell className="font-mono text-xs">{Number(c.stock_quantity || 0)}</TableCell>
                    <TableCell>
                      <Badge variant={c.active ? 'success' : 'neutral'}>{c.active ? tCommon('status.active') : tCommon('status.inactive')}</Badge>
                    </TableCell>
                  </TableRow>
                ))}
              </Table>
            </Card>
          )}
        </div>
      )}

      {showGridForm && selectedProduct && (
        <GridForm
          productId={selectedProduct}
          onClose={() => setShowGridForm(false)}
          onSaved={() => { setShowGridForm(false); loadGrids(selectedProduct) }}
        />
      )}
    </div>
  )
}

function GridForm({ productId, onClose, onSaved }: { productId: string; onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation('stock')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [name, setName] = useState('')
  const [axis, setAxis] = useState<'size' | 'color' | 'material' | 'style'>('size')
  const [valuesInput, setValuesInput] = useState('')
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!name || !valuesInput) return
    setSaving(true)
    try {
      const values = valuesInput.split(',').map(v => v.trim()).filter(Boolean)
      await createProductGrid({
        tenant_id: null,
        product_id: productId,
        name,
        axis,
        values,
        active: true,
      })
      toast('success', tCommon('toast.success'), tCommon('toast.created'))
      onSaved()
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message)
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '28rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('grids.new')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <Input label={t('grids.name')} required value={name} onChange={(e) => setName(e.target.value)} />
          <Select label={t('grids.axis')} required value={axis} onChange={(e) => setAxis(e.target.value as any)} options={[
            { value: 'size', label: t('grids.size') },
            { value: 'color', label: t('grids.color') },
            { value: 'material', label: t('grids.material') },
            { value: 'style', label: t('grids.style') },
          ]} />
          <Input label={t('grids.values')} required placeholder={t('grids.valuesPlaceholder')} value={valuesInput} onChange={(e) => setValuesInput(e.target.value)} />
          <div className="flex justify-end gap-3 pt-2 border-t border-[var(--color-border)]">
            <Button type="button" variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? '...' : tCommon('actions.save')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
