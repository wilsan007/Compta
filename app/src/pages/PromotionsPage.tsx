import { useState, useEffect, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Button, Table, TableRow, TableCell, Badge, EmptyState, Select, Input } from '@/components/ui'
import { formatCurrency, formatDate } from '@/lib/utils'
import { getPromotions, createPromotion, deletePromotion } from '@/lib/queries/catalogAdvanced'
import { getProducts } from '@/lib/queries/stock'
import { getCustomers } from '@/lib/queries/partners'
import { useToast } from '@/lib/toast'
import { Plus, Trash2, X, Tag, Search } from 'lucide-react'
import type { Promotion, Product, Customer } from '@/types'

export function PromotionsPage() {
  const { t } = useTranslation('sales')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [promotions, setPromotions] = useState<Promotion[]>([])
  const [products, setProducts] = useState<Product[]>([])
  const [customers, setCustomers] = useState<Customer[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [search, setSearch] = useState('')
  const [filterStatus, setFilterStatus] = useState<'all' | 'active' | 'expired' | 'upcoming'>('all')

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const [promos, prods, custs] = await Promise.all([getPromotions(), getProducts(), getCustomers()])
      setPromotions(promos || [])
      setProducts(prods || [])
      setCustomers(custs || [])
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message)
    } finally {
      setLoading(false)
    }
  }, [tCommon, toast])

  useEffect(() => { load() }, [load])

  function getPromoStatus(p: Promotion): 'active' | 'expired' | 'upcoming' {
    const now = new Date().toISOString().split('T')[0]
    if (p.end_date < now) return 'expired'
    if (p.start_date > now) return 'upcoming'
    return 'active'
  }

  const filtered = promotions.filter(p => {
    if (search && !p.name.toLowerCase().includes(search.toLowerCase())) return false
    if (filterStatus !== 'all' && getPromoStatus(p) !== filterStatus) return false
    return true
  })

  async function handleDelete(id: string) {
    try {
      await deletePromotion(id)
      toast('success', tCommon('toast.success'), tCommon('toast.deleted'))
      await load()
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message)
    }
  }

  return (
    <div className="p-6 max-w-7xl mx-auto">
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-2xl font-bold flex items-center gap-2">
            <Tag className="w-6 h-6 text-[var(--color-primary)]" />
            {t('promotions.title')}
          </h1>
          <p className="text-sm text-[var(--color-text-secondary)] mt-1">{t('promotions.subtitle')}</p>
        </div>
        <Button onClick={() => setShowForm(true)}>
          <Plus className="w-4 h-4" /> {t('promotions.new')}
        </Button>
      </div>

      <div className="flex items-center gap-4 mb-4">
        <div className="relative flex-1 max-w-xs">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-[var(--color-text-secondary)]" />
          <input
            type="text"
            placeholder={t('promotions.searchPlaceholder')}
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="input pl-9"
          />
        </div>
        <Select
          value={filterStatus}
          onChange={(e) => setFilterStatus(e.target.value as any)}
          options={[
            { value: 'all', label: tCommon('filters.all') },
            { value: 'active', label: t('promotions.active') },
            { value: 'expired', label: t('promotions.expired') },
            { value: 'upcoming', label: t('promotions.upcoming') },
          ]}
        />
      </div>

      {loading ? (
        <div className="space-y-2">
          {[1, 2, 3].map(i => <div key={i} className="h-12 rounded animate-pulse bg-[var(--color-neutral-100)]" />)}
        </div>
      ) : filtered.length === 0 ? (
        <EmptyState
          icon={<Tag className="w-8 h-8" />}
          title={t('promotions.noPromotions')}
          description={t('promotions.noPromotionsDescription')}
          action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('promotions.createFirst')}</Button>}
        />
      ) : (
        <Table headers={[t('promotions.name'), t('promotions.type'), t('promotions.value'), t('promotions.startDate'), t('promotions.endDate'), tCommon('common.status'), tCommon('table.actions')]}>
          {filtered.map((p) => {
            const status = getPromoStatus(p)
            return (
              <TableRow key={p.id}>
                <TableCell className="font-medium">{p.name}</TableCell>
                <TableCell className="text-xs">{t(`promotions.${p.promo_type === 'fixed_amount' ? 'fixedAmount' : p.promo_type === 'buy_x_get_y' ? 'buyXGetY' : p.promo_type === 'free_shipping' ? 'freeShipping' : 'percentage'}`)}</TableCell>
                <TableCell className="font-mono text-xs">{p.value ? (p.promo_type === 'percentage' ? `${p.value}%` : formatCurrency(Number(p.value))) : '-'}</TableCell>
                <TableCell className="text-xs">{formatDate(p.start_date)}</TableCell>
                <TableCell className="text-xs">{formatDate(p.end_date)}</TableCell>
                <TableCell>
                  <Badge variant={status === 'active' ? 'success' : status === 'expired' ? 'danger' : 'warning'}>
                    {t(`promotions.${status}`)}
                  </Badge>
                </TableCell>
                <TableCell>
                  <button onClick={() => handleDelete(p.id)} className="p-1 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]" aria-label={tCommon('actions.delete')} title={tCommon('actions.delete')}>
                    <Trash2 className="w-4 h-4" aria-hidden="true" /></button>
                </TableCell>
              </TableRow>
            )
          })}
        </Table>
      )}

      {showForm && (
        <PromotionForm
          products={products}
          customers={customers}
          onClose={() => setShowForm(false)}
          onSaved={() => { setShowForm(false); load() }}
        />
      )}
    </div>
  )
}

function PromotionForm({ products, customers, onClose, onSaved }: {
  products: Product[]
  customers: Customer[]
  onClose: () => void
  onSaved: () => void
}) {
  const { t } = useTranslation('sales')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [name, setName] = useState('')
  const [description, setDescription] = useState('')
  const [promoType, setPromoType] = useState<'percentage' | 'fixed_amount' | 'buy_x_get_y' | 'free_shipping'>('percentage')
  const [value, setValue] = useState(0)
  const [productId, setProductId] = useState('')
  const [customerId, setCustomerId] = useState('')
  const [startDate, setStartDate] = useState(new Date().toISOString().split('T')[0])
  const [endDate, setEndDate] = useState(new Date(Date.now() + 30 * 86400000).toISOString().split('T')[0])
  const [minQuantity, setMinQuantity] = useState(1)
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!name || !startDate || !endDate) return
    setSaving(true)
    try {
      await createPromotion({
        tenant_id: null,
        name,
        description: description || null,
        promo_type: promoType,
        value: value || null,
        product_id: productId || null,
        category: null,
        customer_id: customerId || null,
        start_date: startDate,
        end_date: endDate,
        min_quantity: minQuantity,
        free_product_id: null,
        free_product_qty: 1,
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
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '36rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('promotions.new')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]" aria-label={tCommon('actions.close')} title={tCommon('actions.close')}><X className="w-5 h-5" aria-hidden="true" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <Input label={t('promotions.name')} required value={name} onChange={(e) => setName(e.target.value)} />
          <Input label={t('promotions.description')} value={description} onChange={(e) => setDescription(e.target.value)} />
          <Select label={t('promotions.type')} required value={promoType} onChange={(e) => setPromoType(e.target.value as any)} options={[
            { value: 'percentage', label: t('promotions.percentage') },
            { value: 'fixed_amount', label: t('promotions.fixedAmount') },
            { value: 'buy_x_get_y', label: t('promotions.buyXGetY') },
            { value: 'free_shipping', label: t('promotions.freeShipping') },
          ]} />
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('promotions.value')} type="number" step="0.01" value={value} onChange={(e) => setValue(Number(e.target.value))} />
            <Input label={t('promotions.minQuantity')} type="number" step="0.01" value={minQuantity} onChange={(e) => setMinQuantity(Number(e.target.value))} />
          </div>
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('promotions.startDate')} type="date" required value={startDate} onChange={(e) => setStartDate(e.target.value)} />
            <Input label={t('promotions.endDate')} type="date" required value={endDate} onChange={(e) => setEndDate(e.target.value)} />
          </div>
          <Select label={t('promotions.product')} value={productId} onChange={(e) => setProductId(e.target.value)} options={[
            { value: '', label: tCommon('common.all') },
            ...products.map(p => ({ value: p.id, label: p.name })),
          ]} />
          <Select label={t('promotions.customer')} value={customerId} onChange={(e) => setCustomerId(e.target.value)} options={[
            { value: '', label: tCommon('common.all') },
            ...customers.map(c => ({ value: c.id, label: c.name })),
          ]} />
          <div className="flex justify-end gap-3 pt-2 border-t border-[var(--color-border)]">
            <Button type="button" variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? tCommon('actions.saving') : tCommon('actions.save')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
