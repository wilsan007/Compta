import { useState, useEffect, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Plus, Trash2, TrendingUp, Upload, Calculator } from 'lucide-react'
import { Card, Button, Input, Select, Table, TableRow, TableCell, EmptyState, PageHeader, Breadcrumb, SkeletonTable, Badge } from '@/components/ui'
import { useToast } from '@/lib/toast'
import { getProductionForecasts, createProductionForecast, deleteProductionForecast, importForecastsFromInvoices, calculateForecastReliability, getProducts } from '@/lib/queries'
import type { Product } from '@/types'

export function ForecastsPage() {
  const { toast } = useToast()
  const { t } = useTranslation('production')
  const { t: tCommon } = useTranslation('common')
  const [forecasts, setForecasts] = useState<any[]>([])
  const [products, setProducts] = useState<Product[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [showImport, setShowImport] = useState(false)

  const loadData = useCallback(async () => {
    try {
      const [f, p] = await Promise.all([getProductionForecasts(), getProducts()])
      setForecasts(f || [])
      setProducts(p || [])
    } catch (err) { console.error('Error:', err) }
    finally { setLoading(false) }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  async function handleDelete(id: string) {
    if (!window.confirm(tCommon('form.confirmDelete'))) return
    try { await deleteProductionForecast(id); await loadData() }
    catch (err: any) { toast('error', tCommon('toast.error'), err.message) }
  }

  async function handleReliability(id: string) {
    try { await calculateForecastReliability(id); await loadData() }
    catch (err: any) { toast('error', tCommon('toast.error'), err.message) }
  }

  function getReliabilityVariant(rate: number): 'success' | 'warning' | 'danger' {
    if (rate >= 80) return 'success'
    if (rate >= 50) return 'warning'
    return 'danger'
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('forecasts.title'), path: '/production' }]} />
      <PageHeader title={t('forecasts.title')} subtitle={`${forecasts.length} ${t('forecasts.title').toLowerCase()}`}
        action={
          <div className="flex gap-2">
            <Button variant="secondary" onClick={() => setShowImport(true)}><Upload className="w-4 h-4" /> {t('forecasts.importInvoices')}</Button>
            <Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('forecasts.new')}</Button>
          </div>
        } />

      {loading ? <SkeletonTable rows={4} cols={7} /> : forecasts.length === 0 ? (
        <EmptyState icon={<TrendingUp className="w-8 h-8" />} title={t('forecasts.noForecasts')} description={t('forecasts.noForecastsDescription')}
          action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('forecasts.new')}</Button>} />
      ) : (
        <Card>
          <Table headers={[t('forecasts.number'), t('forecasts.period'), t('forecasts.product'), t('forecasts.forecastedQty'), t('forecasts.actualQty'), t('forecasts.reliability'), t('forecasts.source'), tCommon('table.actions')]}>
            {forecasts.map((f) => (
              <TableRow key={f.id}>
                <TableCell className="font-mono text-xs">{f.forecast_number}</TableCell>
                <TableCell className="text-sm">{f.period}</TableCell>
                <TableCell className="text-sm">{f.products?.name || '—'}</TableCell>
                <TableCell className="font-mono text-xs">{Number(f.forecasted_quantity)}</TableCell>
                <TableCell className="font-mono text-xs">{Number(f.actual_quantity)}</TableCell>
                <TableCell>
                  {Number(f.reliability_rate) > 0 ? (
                    <div className="flex items-center gap-2">
                      <Badge variant={getReliabilityVariant(Number(f.reliability_rate))}>{Number(f.reliability_rate)}%</Badge>
                      <button onClick={() => handleReliability(f.id)} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><Calculator className="w-3.5 h-3.5" /></button>
                    </div>
                  ) : (
                    <button onClick={() => handleReliability(f.id)} className="text-xs text-[var(--color-primary)] hover:underline">{t('forecasts.calculate')}</button>
                  )}
                </TableCell>
                <TableCell><Badge variant="neutral">{t(`forecasts.sources.${f.source}`) || f.source}</Badge></TableCell>
                <TableCell>
                  <button onClick={() => handleDelete(f.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]"><Trash2 className="w-4 h-4" /></button>
                </TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}

      {showForm && <ForecastFormModal products={products} onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadData() }} />}
      {showImport && <ImportFormModal onClose={() => setShowImport(false)} onSaved={() => { setShowImport(false); loadData() }} />}
    </div>
  )
}

function ForecastFormModal({ products, onClose, onSaved }: { products: Product[]; onClose: () => void; onSaved: () => void }) {
  const { toast } = useToast()
  const { t } = useTranslation('production')
  const { t: tCommon } = useTranslation('common')
  const [period, setPeriod] = useState('')
  const [startDate, setStartDate] = useState('')
  const [endDate, setEndDate] = useState('')
  const [productId, setProductId] = useState('')
  const [quantity, setQuantity] = useState(0)
  const [notes, setNotes] = useState('')

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!period || !startDate || !endDate) { toast('error', tCommon('toast.error'), t('forecasts.periodRequired')); return }
    try {
      const num = `PREV-${period}-${String(Date.now()).slice(-4)}`
      await createProductionForecast({
        forecast_number: num, period, start_date: startDate, end_date: endDate,
        product_id: productId || null, forecasted_quantity: quantity, actual_quantity: 0,
        reliability_rate: 0, source: 'manual', notes: notes || null,
      })
      onSaved()
    } catch (err: any) { toast('error', tCommon('toast.error'), err.message) }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40" onClick={onClose}>
      <div className="bg-[var(--color-surface)] rounded-xl shadow-xl p-6 w-full max-w-md" onClick={(e) => e.stopPropagation()}>
        <h2 className="text-lg font-semibold mb-4">{t('forecasts.new')}</h2>
        <form onSubmit={handleSubmit} className="space-y-3">
          <Input label={t('forecasts.periodPlaceholder')} value={period} onChange={(e) => setPeriod(e.target.value)} required />
          <div className="grid grid-cols-2 gap-3">
            <Input label={t('forecasts.startDate')} type="date" value={startDate} onChange={(e) => setStartDate(e.target.value)} required />
            <Input label={t('forecasts.endDate')} type="date" value={endDate} onChange={(e) => setEndDate(e.target.value)} required />
          </div>
          <Select label={t('forecasts.product')} value={productId} onChange={(e) => setProductId(e.target.value)} options={[{ value: '', label: '—' }, ...products.map((p) => ({ value: p.id, label: p.name }))]} />
          <Input label={t('forecasts.forecastedQty')} type="number" step="0.001" value={quantity} onChange={(e) => setQuantity(Number(e.target.value))} />
          <Input label={tCommon('common.notes')} value={notes} onChange={(e) => setNotes(e.target.value)} />
          <div className="flex gap-2 justify-end pt-2">
            <Button type="button" variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit">{tCommon('actions.create')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}

function ImportFormModal({ onClose, onSaved }: { onClose: () => void; onSaved: () => void }) {
  const { toast } = useToast()
  const { t } = useTranslation('production')
  const { t: tCommon } = useTranslation('common')
  const [period, setPeriod] = useState('')
  const [startDate, setStartDate] = useState('')
  const [endDate, setEndDate] = useState('')
  const [importing, setImporting] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!period || !startDate || !endDate) { toast('error', tCommon('toast.error'), t('forecasts.periodRequired')); return }
    setImporting(true)
    try {
      const count = await importForecastsFromInvoices(period, startDate, endDate)
      toast('success', t('forecasts.importComplete'), t('forecasts.importCompleteMsg', { count }))
      onSaved()
    } catch (err: any) { toast('error', tCommon('toast.error'), err.message) }
    finally { setImporting(false) }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40" onClick={onClose}>
      <div className="bg-[var(--color-surface)] rounded-xl shadow-xl p-6 w-full max-w-md" onClick={(e) => e.stopPropagation()}>
        <h2 className="text-lg font-semibold mb-4">{t('forecasts.importFromInvoices')}</h2>
        <p className="text-xs text-[var(--color-text-secondary)] mb-4">{t('forecasts.importDescription')}</p>
        <form onSubmit={handleSubmit} className="space-y-3">
          <Input label={t('forecasts.periodPlaceholder')} value={period} onChange={(e) => setPeriod(e.target.value)} required />
          <div className="grid grid-cols-2 gap-3">
            <Input label={t('forecasts.startDate')} type="date" value={startDate} onChange={(e) => setStartDate(e.target.value)} required />
            <Input label={t('forecasts.endDate')} type="date" value={endDate} onChange={(e) => setEndDate(e.target.value)} required />
          </div>
          <div className="flex gap-2 justify-end pt-2">
            <Button type="button" variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={importing}>{importing ? '...' : t('forecasts.import')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
