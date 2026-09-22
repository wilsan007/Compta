import { useState, useEffect, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Button, Table, TableRow, TableCell, Badge, EmptyState, Select, Input } from '@/components/ui'
import { formatCurrency } from '@/lib/utils'
import { getForecasts, createForecast } from '@/lib/queries/crmAdvanced'
import { getSalesRepresentatives } from '@/lib/queries/misc'
import { useToast } from '@/lib/toast'
import { Plus, X, TrendingUp } from 'lucide-react'
import type { CrmForecast, SalesRepresentative } from '@/types'

export function SalesForecastPage() {
  const { t } = useTranslation('crm')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [forecasts, setForecasts] = useState<CrmForecast[]>([])
  const [reps, setReps] = useState<SalesRepresentative[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [filterPeriod, setFilterPeriod] = useState('')

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const [fcData, repsData] = await Promise.all([getForecasts(), getSalesRepresentatives()])
      setForecasts(fcData || [])
      setReps(repsData || [])
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message)
    } finally {
      setLoading(false)
    }
  }, [tCommon, toast])

  useEffect(() => { load() }, [load])

  const filtered = filterPeriod ? forecasts.filter(f => f.period === filterPeriod) : forecasts

  function getRepName(repId: string | null): string {
    if (!repId) return '-'
    return reps.find(r => r.id === repId)?.name || '-'
  }

  return (
    <div className="p-6 max-w-7xl mx-auto">
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-2xl font-bold flex items-center gap-2">
            <TrendingUp className="w-6 h-6 text-[var(--color-primary)]" />
            {t('forecasts.title')}
          </h1>
          <p className="text-sm text-[var(--color-text-secondary)] mt-1">{t('forecasts.subtitle')}</p>
        </div>
        <Button onClick={() => setShowForm(true)}>
          <Plus className="w-4 h-4" /> {t('forecasts.new')}
        </Button>
      </div>

      <div className="mb-4">
        <Input placeholder="2024-Q1" value={filterPeriod} onChange={(e) => setFilterPeriod(e.target.value)} />
      </div>

      {loading ? (
        <div className="space-y-2">{[1, 2, 3].map(i => <div key={i} className="h-12 rounded animate-pulse bg-[var(--color-neutral-100)]" />)}</div>
      ) : filtered.length === 0 ? (
        <EmptyState icon={<TrendingUp className="w-8 h-8" />} title={t('forecasts.noForecasts')} description={t('forecasts.noForecastsDescription')} />
      ) : (
        <Table headers={[t('forecasts.period'), t('opportunities.salesRep'), t('forecasts.target'), t('forecasts.committed'), t('forecasts.bestCase'), t('forecasts.pipeline'), t('forecasts.closed')]}>
          {filtered.map(f => (
            <TableRow key={f.id}>
              <TableCell className="font-mono text-xs">{f.period}</TableCell>
              <TableCell className="text-xs">{getRepName(f.sales_rep_id)}</TableCell>
              <TableCell className="font-mono text-xs">{formatCurrency(Number(f.target_amount))}</TableCell>
              <TableCell className="font-mono text-xs">{formatCurrency(Number(f.committed_amount))}</TableCell>
              <TableCell className="font-mono text-xs">{formatCurrency(Number(f.best_case_amount))}</TableCell>
              <TableCell className="font-mono text-xs">{formatCurrency(Number(f.pipeline_amount))}</TableCell>
              <TableCell className="font-mono text-xs">
                <Badge variant={Number(f.closed_amount) >= Number(f.target_amount) ? 'success' : 'neutral'}>
                  {formatCurrency(Number(f.closed_amount))}
                </Badge>
              </TableCell>
            </TableRow>
          ))}
        </Table>
      )}

      {showForm && <ForecastForm reps={reps} onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); load() }} />}
    </div>
  )
}

function ForecastForm({ reps, onClose, onSaved }: { reps: SalesRepresentative[]; onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation('crm')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [period, setPeriod] = useState('')
  const [salesRepId, setSalesRepId] = useState('')
  const [target, setTarget] = useState(0)
  const [committed, setCommitted] = useState(0)
  const [bestCase, setBestCase] = useState(0)
  const [pipeline, setPipeline] = useState(0)
  const [closed, setClosed] = useState(0)
  const [notes, setNotes] = useState('')
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!period) return
    setSaving(true)
    try {
      await createForecast({
        tenant_id: null,
        period,
        sales_rep_id: salesRepId || null,
        target_amount: target,
        committed_amount: committed,
        best_case_amount: bestCase,
        pipeline_amount: pipeline,
        closed_amount: closed,
        notes: notes || null,
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
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '32rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('forecasts.new')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]" aria-label={tCommon('actions.close')} title={tCommon('actions.close')}><X className="w-5 h-5" aria-hidden="true" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <Input label={t('forecasts.period')} required placeholder="2024-Q1" value={period} onChange={(e) => setPeriod(e.target.value)} />
          <Select label={t('opportunities.salesRep')} value={salesRepId} onChange={(e) => setSalesRepId(e.target.value)} options={[
            { value: '', label: tCommon('form.selectPlaceholder') },
            ...reps.map(r => ({ value: r.id, label: r.name })),
          ]} />
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('forecasts.target')} type="number" step="0.01" value={target} onChange={(e) => setTarget(Number(e.target.value))} />
            <Input label={t('forecasts.committed')} type="number" step="0.01" value={committed} onChange={(e) => setCommitted(Number(e.target.value))} />
            <Input label={t('forecasts.bestCase')} type="number" step="0.01" value={bestCase} onChange={(e) => setBestCase(Number(e.target.value))} />
            <Input label={t('forecasts.pipeline')} type="number" step="0.01" value={pipeline} onChange={(e) => setPipeline(Number(e.target.value))} />
            <Input label={t('forecasts.closed')} type="number" step="0.01" value={closed} onChange={(e) => setClosed(Number(e.target.value))} />
          </div>
          <Input label={t('forecasts.notes')} value={notes} onChange={(e) => setNotes(e.target.value)} />
          <div className="flex justify-end gap-3 pt-2 border-t border-[var(--color-border)]">
            <Button type="button" variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? tCommon('actions.saving') : tCommon('actions.save')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
