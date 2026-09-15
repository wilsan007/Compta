import { useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Badge, SortableTable, TableRow, TableCell, EmptyState, AutoBreadcrumb, SkeletonTable, Input, Select, ConfirmDialog } from '@/components/ui'
import { getSupplierDeliverySchedules, createSupplierDeliverySchedule, deleteSupplierDeliverySchedule, generatePurchaseFromSchedule } from '@/lib/queries/purchaseAdvanced'
import { getSuppliers } from '@/lib/queries/partners'
import { getProducts } from '@/lib/queries/stock'
import { formatDate } from '@/lib/utils'
import { useToast } from '@/lib/toast'
import { Calendar, Plus, Search, Trash2, X, Zap } from 'lucide-react'
import type { SupplierDeliverySchedule, Supplier, Product } from '@/types'

export function SupplierDeliverySchedulePage() {
  const { t } = useTranslation('purchases')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [schedules, setSchedules] = useState<SupplierDeliverySchedule[]>([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [showForm, setShowForm] = useState(false)
  const [deleteTarget, setDeleteTarget] = useState<SupplierDeliverySchedule | null>(null)
  const [suppliers, setSuppliers] = useState<Supplier[]>([])
  const [products, setProducts] = useState<Product[]>([])
  const [generateDate, setGenerateDate] = useState(new Date().toISOString().split('T')[0])

  // oxlint-disable-next-line react-hooks/exhaustive-deps -- chargement volontairement limite aux valeurs listees
  useEffect(() => { loadSchedules(); loadOptions() }, [])

  async function loadSchedules() {
    try {
      const data = await getSupplierDeliverySchedules()
      setSchedules(data || [])
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

  async function handleGenerate() {
    try {
      const orders = await generatePurchaseFromSchedule(generateDate)
      toast('success', t('deliverySchedule.title'), t('deliverySchedule.ordersGenerated', { count: orders.length }))
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message)
    }
  }

  async function handleDelete(id: string) {
    try {
      await deleteSupplierDeliverySchedule(id)
      setSchedules(schedules.filter(s => s.id !== id))
      toast('success', t('deliverySchedule.title'), tCommon('toast.deleted'))
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message)
    }
  }

  const filtered = schedules.filter(s =>
    suppliers.find(sup => sup.id === s.supplier_id)?.name?.toLowerCase().includes(search.toLowerCase()) ||
    products.find(p => p.id === s.product_id)?.name?.toLowerCase().includes(search.toLowerCase())
  )

  return (
    <div className="animate-fade-in">
      <AutoBreadcrumb />
      <PageHeader
        title={t('deliverySchedule.title')}
        subtitle={`${schedules.length} ${t('deliverySchedule.title').toLowerCase()}`}
        action={<Button variant="primary" onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('deliverySchedule.new')}</Button>}
      />

      {/* Generate orders */}
      <Card className="p-4 mb-4">
        <div className="flex items-end gap-3">
          <div className="flex-1">
            <Input label={t('deliverySchedule.generateForDate')} type="date" value={generateDate} onChange={e => setGenerateDate(e.target.value)} />
          </div>
          <Button variant="primary" onClick={handleGenerate}><Zap className="w-4 h-4" /> {t('deliverySchedule.generateOrders')}</Button>
        </div>
      </Card>

      <Card>
        <div className="mb-4 relative">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-[var(--color-text-secondary)]" />
          <input className="input pl-10" placeholder={t('deliverySchedule.searchPlaceholder')} value={search} onChange={e => setSearch(e.target.value)} />
        </div>

        {loading ? (
          <SkeletonTable rows={5} cols={5} />
        ) : filtered.length > 0 ? (
          <SortableTable
            headers={[
              { label: t('deliverySchedule.supplier'), key: 'supplier_id', sortable: true },
              { label: t('deliverySchedule.product'), key: 'product_id', sortable: true },
              { label: t('deliverySchedule.frequency'), key: 'frequency', sortable: true },
              { label: t('deliverySchedule.startDate'), key: 'start_date', sortable: true },
              { label: t('deliverySchedule.active'), key: 'active', sortable: true },
              { label: tCommon('table.actions') },
            ]}
            data={filtered as any}
            initialSortKey="start_date"
            renderRow={(s: any) => (
              <TableRow key={s.id}>
                <TableCell>{suppliers.find(sup => sup.id === s.supplier_id)?.name || s.supplier_id?.slice(0, 8)}</TableCell>
                <TableCell>{products.find(p => p.id === s.product_id)?.name || s.product_id?.slice(0, 8)}</TableCell>
                <TableCell><Badge variant="neutral">{t(`deliverySchedule.${s.frequency}`)}</Badge></TableCell>
                <TableCell>{formatDate(s.start_date)}</TableCell>
                <TableCell>{s.active ? <Badge variant="success">{tCommon('common.yes')}</Badge> : <Badge>{tCommon('common.no')}</Badge>}</TableCell>
                <TableCell>
                  <button onClick={() => setDeleteTarget(s)} className="p-1.5 rounded text-[var(--color-danger)] hover:bg-[rgba(222,53,11,0.1)]" title={tCommon('actions.delete')}><Trash2 className="w-4 h-4" /></button>
                </TableCell>
              </TableRow>
            )}
          />
        ) : (
          <EmptyState icon={<Calendar className="w-8 h-8" />} title={t('deliverySchedule.noSchedules')} description={t('deliverySchedule.noSchedulesDescription')} action={<Button variant="primary" onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('deliverySchedule.new')}</Button>} />
        )}
      </Card>

      {showForm && (
        <ScheduleForm suppliers={suppliers} products={products} onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadSchedules() }} />
      )}

      <ConfirmDialog
        open={!!deleteTarget}
        title={tCommon('actions.delete')}
        message={`${tCommon('form.confirmDelete')} ?`}
        confirmLabel={tCommon('actions.delete')}
        onConfirm={() => { if (deleteTarget) handleDelete(deleteTarget.id); setDeleteTarget(null) }}
        onCancel={() => setDeleteTarget(null)}
      />
    </div>
  )
}

function ScheduleForm({ suppliers, products, onClose, onSaved }: {
  suppliers: Supplier[]
  products: Product[]
  onClose: () => void
  onSaved: () => void
}) {
  const { t } = useTranslation('purchases')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [supplierId, setSupplierId] = useState('')
  const [productId, setProductId] = useState('')
  const [frequency, setFrequency] = useState('weekly')
  const [startDate, setStartDate] = useState(new Date().toISOString().split('T')[0])
  const [endDate, setEndDate] = useState('')
  const [mondayQty, setMondayQty] = useState(0)
  const [tuesdayQty, setTuesdayQty] = useState(0)
  const [wednesdayQty, setWednesdayQty] = useState(0)
  const [thursdayQty, setThursdayQty] = useState(0)
  const [fridayQty, setFridayQty] = useState(0)
  const [saturdayQty, setSaturdayQty] = useState(0)
  const [sundayQty, setSundayQty] = useState(0)
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!supplierId || !productId) { toast('warning', tCommon('form.requiredField'), t('deliverySchedule.supplier')); return }
    setSaving(true)
    try {
      await createSupplierDeliverySchedule({
        supplier_id: supplierId, product_id: productId, warehouse_id: null, frequency: frequency as any,
        monday_qty: mondayQty, tuesday_qty: tuesdayQty, wednesday_qty: wednesdayQty,
        thursday_qty: thursdayQty, friday_qty: fridayQty, saturday_qty: saturdayQty, sunday_qty: sundayQty,
        start_date: startDate, end_date: endDate || null, active: true,
      } as any)
      toast('success', t('deliverySchedule.title'), tCommon('toast.created'))
      onSaved()
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message)
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '40rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('deliverySchedule.new')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4 max-h-[70vh] overflow-y-auto">
          <div className="grid grid-cols-2 gap-4">
            <Select label={t('deliverySchedule.supplier')} value={supplierId} onChange={e => setSupplierId(e.target.value)}
              options={[{ value: '', label: '—' }, ...suppliers.map(s => ({ value: s.id, label: s.name }))]} />
            <Select label={t('deliverySchedule.product')} value={productId} onChange={e => setProductId(e.target.value)}
              options={[{ value: '', label: '—' }, ...products.map(p => ({ value: p.id, label: p.name }))]} />
          </div>
          <div className="grid grid-cols-3 gap-4">
            <Select label={t('deliverySchedule.frequency')} value={frequency} onChange={e => setFrequency(e.target.value)}
              options={[
                { value: 'weekly', label: t('deliverySchedule.weekly') },
                { value: 'biweekly', label: t('deliverySchedule.biweekly') },
                { value: 'monthly', label: t('deliverySchedule.monthly') },
              ]} />
            <Input label={t('deliverySchedule.startDate')} type="date" required value={startDate} onChange={e => setStartDate(e.target.value)} />
            <Input label={t('deliverySchedule.endDate')} type="date" value={endDate} onChange={e => setEndDate(e.target.value)} />
          </div>
          <div className="grid grid-cols-7 gap-2">
            {[
              { label: t('deliverySchedule.monday'), val: mondayQty, set: setMondayQty },
              { label: t('deliverySchedule.tuesday'), val: tuesdayQty, set: setTuesdayQty },
              { label: t('deliverySchedule.wednesday'), val: wednesdayQty, set: setWednesdayQty },
              { label: t('deliverySchedule.thursday'), val: thursdayQty, set: setThursdayQty },
              { label: t('deliverySchedule.friday'), val: fridayQty, set: setFridayQty },
              { label: t('deliverySchedule.saturday'), val: saturdayQty, set: setSaturdayQty },
              { label: t('deliverySchedule.sunday'), val: sundayQty, set: setSundayQty },
            ].map((day, i) => (
              <div key={i}>
                <label className="text-xs text-[var(--color-text-secondary)]">{day.label}</label>
                <input className="input" type="number" value={day.val} onChange={e => day.set(Number(e.target.value))} />
              </div>
            ))}
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
