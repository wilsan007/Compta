import { useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, SortableTable, TableRow, TableCell, EmptyState, AutoBreadcrumb, SkeletonTable, Input, Select, ConfirmDialog } from '@/components/ui'
import { getSupplierPriceLists, createSupplierPriceList, deleteSupplierPriceList, getBestSupplierPrice } from '@/lib/queries/purchaseAdvanced'
import { getSuppliers } from '@/lib/queries/partners'
import { getProducts } from '@/lib/queries/stock'
import { formatCurrency, formatDate } from '@/lib/utils'
import { useToast } from '@/lib/toast'
import { Tag, Plus, Search, Trash2, X, TrendingDown } from 'lucide-react'
import type { SupplierPriceList, Supplier, Product } from '@/types'

export function SupplierPriceListsPage() {
  const { t } = useTranslation('purchases')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [lists, setLists] = useState<SupplierPriceList[]>([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [showForm, setShowForm] = useState(false)
  const [deleteTarget, setDeleteTarget] = useState<SupplierPriceList | null>(null)
  const [suppliers, setSuppliers] = useState<Supplier[]>([])
  const [products, setProducts] = useState<Product[]>([])
  const [compareProduct, setCompareProduct] = useState('')
  const [compareResult, setCompareResult] = useState<any>(null)

  // oxlint-disable-next-line react-hooks/exhaustive-deps -- chargement volontairement limite aux valeurs listees
  useEffect(() => { loadLists(); loadOptions() }, [])

  async function loadLists() {
    try {
      const data = await getSupplierPriceLists()
      setLists(data || [])
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message)
    } finally {
      setLoading(false)
    }
  }

  async function loadOptions() {
    try {
      const [s, p] = await Promise.all([getSuppliers(), getProducts()])
      setSuppliers(s || [])
      setProducts(p || [])
    } catch (err: any) { console.error("catch:", err); toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadError')) }
  }

  async function handleCompare() {
    if (!compareProduct) return
    try {
      const result = await getBestSupplierPrice(compareProduct, 1)
      setCompareResult(result)
      if (!result) toast('info', t('supplierPrices.compare'), t('supplierPrices.noPriceFound'))
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message)
    }
  }

  async function handleDelete(id: string) {
    try {
      await deleteSupplierPriceList(id)
      setLists(lists.filter(l => l.id !== id))
      toast('success', t('supplierPrices.title'), tCommon('toast.deleted'))
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message)
    }
  }

  const filtered = lists.filter(l =>
    l.name?.toLowerCase().includes(search.toLowerCase()) ||
    suppliers.find(s => s.id === l.supplier_id)?.name?.toLowerCase().includes(search.toLowerCase())
  )

  return (
    <div className="animate-fade-in">
      <AutoBreadcrumb />
      <PageHeader
        title={t('supplierPrices.title')}
        subtitle={`${lists.length} ${t('supplierPrices.title').toLowerCase()}`}
        action={<Button variant="primary" onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('supplierPrices.new')}</Button>}
      />

      {/* Comparateur */}
      <Card className="p-4 mb-4">
        <div className="flex items-end gap-3">
          <div className="flex-1">
            <Select label={t('supplierPrices.compare')} value={compareProduct} onChange={e => setCompareProduct(e.target.value)}
              options={[{ value: '', label: '—' }, ...products.map(p => ({ value: p.id, label: p.name }))]} />
          </div>
          <Button variant="secondary" onClick={handleCompare}><TrendingDown className="w-4 h-4" /> {t('supplierPrices.bestPrice')}</Button>
        </div>
        {compareResult && (
          <div className="mt-3 p-3 rounded-lg bg-[var(--color-neutral-50)] border border-[var(--color-border)]">
            <p className="text-sm font-medium">{t('supplierPrices.bestPrice')}: {formatCurrency(compareResult.effective_price)}</p>
            <p className="text-xs text-[var(--color-text-secondary)]">{t('supplierPrices.leadTime')}: {compareResult.lead_time_days || '—'} {t('supplierPrices.days')}</p>
          </div>
        )}
      </Card>

      <Card>
        <div className="mb-4 relative">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-[var(--color-text-secondary)]" />
          <input className="input pl-10" placeholder={t('supplierPrices.searchPlaceholder')} value={search} onChange={e => setSearch(e.target.value)} />
        </div>

        {loading ? (
          <SkeletonTable rows={5} cols={5} />
        ) : filtered.length > 0 ? (
          <SortableTable
            headers={[
              { label: t('supplierPrices.name'), key: 'name', sortable: true },
              { label: t('supplierPrices.supplier'), key: 'supplier_id', sortable: true },
              { label: t('supplierPrices.validFrom'), key: 'valid_from', sortable: true },
              { label: t('supplierPrices.validTo'), key: 'valid_to', sortable: true },
              { label: t('supplierPrices.discount'), key: 'discount_percent', sortable: true, className: 'text-right' },
              { label: tCommon('table.actions') },
            ]}
            data={filtered as any}
            initialSortKey="name"
            renderRow={(l: any) => (
              <TableRow key={l.id}>
                <TableCell className="font-medium">{l.name}</TableCell>
                <TableCell>{suppliers.find(s => s.id === l.supplier_id)?.name || l.supplier_id?.slice(0, 8)}</TableCell>
                <TableCell>{formatDate(l.valid_from)}</TableCell>
                <TableCell>{l.valid_to ? formatDate(l.valid_to) : '—'}</TableCell>
                <TableCell className="text-right">{Number(l.discount_percent || 0)}%</TableCell>
                <TableCell>
                  <button onClick={() => setDeleteTarget(l)} className="p-1.5 rounded text-[var(--color-danger)] hover:bg-[rgba(222,53,11,0.1)]" title={tCommon('actions.delete')}><Trash2 className="w-4 h-4" /></button>
                </TableCell>
              </TableRow>
            )}
          />
        ) : (
          <EmptyState icon={<Tag className="w-8 h-8" />} title={t('supplierPrices.noLists')} description={t('supplierPrices.noListsDescription')} action={<Button variant="primary" onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('supplierPrices.new')}</Button>} />
        )}
      </Card>

      {showForm && (
        <PriceListForm suppliers={suppliers} onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadLists() }} />
      )}

      <ConfirmDialog
        open={!!deleteTarget}
        title={tCommon('actions.delete')}
        message={`${tCommon('form.confirmDelete')} ${deleteTarget?.name} ?`}
        confirmLabel={tCommon('actions.delete')}
        onConfirm={() => { if (deleteTarget) handleDelete(deleteTarget.id); setDeleteTarget(null) }}
        onCancel={() => setDeleteTarget(null)}
      />
    </div>
  )
}

function PriceListForm({ suppliers, onClose, onSaved }: {
  suppliers: Supplier[]
  onClose: () => void
  onSaved: () => void
}) {
  const { t } = useTranslation('purchases')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [supplierId, setSupplierId] = useState('')
  const [name, setName] = useState('')
  const [validFrom, setValidFrom] = useState(new Date().toISOString().split('T')[0])
  const [validTo, setValidTo] = useState('')
  const [currencyCode, setCurrencyCode] = useState('EUR')
  const [discountPercent, setDiscountPercent] = useState(0)
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!supplierId || !name.trim()) { toast('warning', tCommon('form.requiredField'), t('supplierPrices.name')); return }
    setSaving(true)
    try {
      await createSupplierPriceList({
        supplier_id: supplierId, name, valid_from: validFrom, valid_to: validTo || null,
        currency_code: currencyCode, min_quantity: 1, discount_percent: discountPercent, active: true,
      } as any)
      toast('success', t('supplierPrices.title'), tCommon('toast.created'))
      onSaved()
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message)
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '32rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('supplierPrices.new')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <Select label={t('supplierPrices.supplier')} value={supplierId} onChange={e => setSupplierId(e.target.value)}
            options={[{ value: '', label: '—' }, ...suppliers.map(s => ({ value: s.id, label: s.name }))]} />
          <Input label={t('supplierPrices.name')} required value={name} onChange={e => setName(e.target.value)} />
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('supplierPrices.validFrom')} type="date" required value={validFrom} onChange={e => setValidFrom(e.target.value)} />
            <Input label={t('supplierPrices.validTo')} type="date" value={validTo} onChange={e => setValidTo(e.target.value)} />
          </div>
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('supplierPrices.currency')} value={currencyCode} onChange={e => setCurrencyCode(e.target.value)} />
            <Input label={t('supplierPrices.discount')} type="number" value={discountPercent} onChange={e => setDiscountPercent(Number(e.target.value))} />
          </div>
          <div className="flex justify-end gap-3 pt-4 border-t border-[var(--color-border)]">
            <Button variant="secondary" type="button" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" loading={saving}>{tCommon('actions.create')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
