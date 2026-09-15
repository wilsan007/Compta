import { useState, useEffect, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Link } from 'react-router-dom'
import { QuickAccessModal } from './QuickAccessModal'
import { Button, Input, Select, EmptyState, Table, TableRow, TableCell, Badge } from '@/components/ui'
import { getProducts, createProduct } from '@/lib/queries/stock'
import { useToast } from '@/lib/toast'
import { useModuleAwareAccess } from './useModuleAwareAccess'
import { Package, Plus, ExternalLink, Search } from 'lucide-react'
import type { Product } from '@/types'

interface QuickProductAccessProps {
  onClose: () => void
  onSaved?: (product: Product) => void
  forceInline?: boolean
}

/**
 * Cross-module Quick Access for Products.
 * - If stock module is active → link to /stock/products
 * - If stock module is NOT active → inline mini-CRUD
 */
export function QuickProductAccess({ onClose, onSaved, forceInline }: QuickProductAccessProps) {
  const { t } = useTranslation('crossModule')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const { getAccessStrategy } = useModuleAwareAccess()

  const strategy = forceInline ? 'inline' : getAccessStrategy('stock')
  const [products, setProducts] = useState<Product[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [search, setSearch] = useState('')

  const [name, setName] = useState('')
  const [sku, setSku] = useState('')
  const [type, setType] = useState<'stock' | 'service'>('stock')
  const [salePrice, setSalePrice] = useState('0')
  const [saving, setSaving] = useState(false)

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      setProducts(await getProducts())
    } catch (err: any) { console.error("catch:", err); toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadError'))
      /* ignore */
    } finally {
      setLoading(false)
    }
  }, [toast, tCommon])

  useEffect(() => {
    if (strategy === 'inline') loadData().catch(err => console.error('loadData:', err))
  }, [strategy, loadData])

  async function handleSave(e: React.FormEvent) {
    e.preventDefault()
    if (!name.trim()) return
    setSaving(true)
    try {
      const prod = await createProduct({
        name: name.trim(),
        sku: sku.trim() || `SKU-${Date.now()}`,
        description: '',
        type,
        sale_price: Number(salePrice) || 0,
        purchase_price: 0,
        vat_rate: 0,
        stock_quantity: 0,
        reorder_level: 0,
        unit: 'pcs',
        category: '',
        active: true,
      } as Omit<Product, 'id' | 'created_at' | 'updated_at'>)
      toast('success', tCommon('common.success'), t('product.created'))
      onSaved?.(prod)
      await loadData()
      setShowForm(false)
      setName(''); setSku(''); setSalePrice('0')
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || t('product.createError'))
    } finally {
      setSaving(false)
    }
  }

  const filtered = products.filter((p) =>
    !search || p.name.toLowerCase().includes(search.toLowerCase()) || p.sku.toLowerCase().includes(search.toLowerCase()),
  )

  if (strategy === 'full' && !forceInline) {
    return (
      <QuickAccessModal title={t('product.title')} onClose={onClose}>
        <EmptyState
          icon={<Package className="w-8 h-8" />}
          title={t('product.moduleActive')}
          description={t('product.moduleActiveDescription')}
          action={
            <Link to="/stock/products" onClick={onClose}>
              <Button><ExternalLink className="w-4 h-4" /> {t('product.goToProducts')}</Button>
            </Link>
          }
        />
      </QuickAccessModal>
    )
  }

  return (
    <QuickAccessModal title={t('product.title')} onClose={onClose}>
      <div className="space-y-4">
        <div className="flex items-center gap-2">
          <div className="relative flex-1">
            <Search className="w-4 h-4 absolute left-3 top-1/2 -translate-y-1/2 text-[var(--color-text-tertiary)]" />
            <input
              type="text"
              placeholder={t('product.search')}
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              className="w-full pl-9 pr-3 py-2 text-sm border border-[var(--color-border)] rounded-lg bg-[var(--color-surface)] outline-none focus:border-[var(--color-primary)]"
            />
          </div>
          <Button size="sm" onClick={() => setShowForm(!showForm)}>
            <Plus className="w-4 h-4" /> {t('product.add')}
          </Button>
        </div>

        {showForm && (
          <form onSubmit={handleSave} className="space-y-3 p-4 rounded-lg border border-[var(--color-border)] bg-[var(--color-neutral-50)]">
            <Input label={t('product.name')} required value={name} onChange={(e) => setName(e.target.value)} />
            <div className="grid grid-cols-2 gap-3">
              <Input label={t('product.sku')} value={sku} onChange={(e) => setSku(e.target.value)} />
              <Input label={t('product.salePrice')} type="number" step="0.01" value={salePrice} onChange={(e) => setSalePrice(e.target.value)} />
            </div>
            <Select
              label={t('product.type')}
              value={type}
              onChange={(e) => setType(e.target.value as 'stock' | 'service')}
              options={[
                { value: 'stock', label: t('product.types.stock') },
                { value: 'service', label: t('product.types.service') },
              ]}
            />
            <div className="flex justify-end gap-2">
              <Button type="button" variant="secondary" size="sm" onClick={() => setShowForm(false)}>{tCommon('actions.cancel')}</Button>
              <Button type="submit" size="sm" disabled={saving}>{saving ? '...' : tCommon('actions.save')}</Button>
            </div>
          </form>
        )}

        {loading ? (
          <p className="text-sm text-[var(--color-text-secondary)] text-center py-8">{tCommon('common.loading')}</p>
        ) : filtered.length === 0 ? (
          <EmptyState
            icon={<Package className="w-8 h-8" />}
            title={t('product.noProducts')}
            description={t('product.noProductsDescription')}
            action={<Button size="sm" onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('product.add')}</Button>}
          />
        ) : (
          <Table headers={[t('product.name'), t('product.sku'), t('product.type'), tCommon('common.status')]}>
            {filtered.slice(0, 20).map((p) => (
              <TableRow key={p.id}>
                <TableCell className="font-medium">{p.name}</TableCell>
                <TableCell className="font-mono text-xs">{p.sku}</TableCell>
                <TableCell className="text-sm">{t(`product.types.${p.type}`)}</TableCell>
                <TableCell>
                  <Badge variant={p.active ? 'success' : 'neutral'}>
                    {p.active ? tCommon('status.active') : tCommon('status.inactive')}
                  </Badge>
                </TableCell>
              </TableRow>
            ))}
          </Table>
        )}
      </div>
    </QuickAccessModal>
  )
}
