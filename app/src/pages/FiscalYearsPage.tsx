import { useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Input } from '@/components/ui'
import { getFiscalYears, createFiscalYear, updateFiscalYear, deleteFiscalYear, getFiscalPeriods, createFiscalPeriodsForYear, updateFiscalPeriod } from '@/lib/queries'
import { Calendar, Plus, Pencil, Trash2, X, ChevronDown, ChevronRight, Lock, Unlock } from 'lucide-react'
import type { FiscalYear, FiscalPeriod } from '@/types'
import { useToast } from '@/lib/toast'

export function FiscalYearsPage() {
  const { toast } = useToast()
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
const [years, setYears] = useState<FiscalYear[]>([])
  const [periods, setPeriods] = useState<Record<string, FiscalPeriod[]>>({})
  const [loading, setLoading] = useState(true)
  const [expandedId, setExpandedId] = useState<string | null>(null)
  const [showForm, setShowForm] = useState(false)
  const [editing, setEditing] = useState<FiscalYear | null>(null)

  useEffect(() => {
    loadYears()
  }, [])

  async function loadYears() {
    try {
      const data = await getFiscalYears()
      setYears(data || [])
      const periodsMap: Record<string, FiscalPeriod[]> = {}
      for (const y of data) {
        try {
          const p = await getFiscalPeriods(y.id)
          periodsMap[y.id] = p || []
        } catch { periodsMap[y.id] = [] }
      }
      setPeriods(periodsMap)
    } catch (err) {
      console.error('Error loading fiscal years:', err)
    } finally {
      setLoading(false)
    }
  }

  function openCreate() {
  setEditing(null)
    setShowForm(true)
  }

  function openEdit(y: FiscalYear) {
    setEditing(y)
    setShowForm(true)
  }

  async function handleDelete(id: string) {
    if (!window.confirm(t('fiscalYears.deleteConfirm'))) return
    try {
      await deleteFiscalYear(id)
      await loadYears()
    } catch (err) {
      toast('error', tCommon('toast.error'), tCommon('toast.deleteError'))
    }
  }

  async function togglePeriodStatus(period: FiscalPeriod) {
    const newStatus = period.status === 'open' ? 'closed' : 'open'
    try {
      await updateFiscalPeriod(period.id, { status: newStatus })
      await loadYears()
    } catch (err) {
      toast('error', tCommon('toast.error'), tCommon('toast.updateError'))
    }
  }

  async function toggleYearStatus(y: FiscalYear) {
    const newStatus = y.status === 'open' ? 'closed' : 'open'
    try {
      await updateFiscalYear(y.id, { status: newStatus, closed_at: newStatus === 'closed' ? new Date().toISOString() : null })
      await loadYears()
    } catch (err) {
      toast('error', tCommon('toast.error'), tCommon('toast.updateError'))
    }
  }

  const statusBadge = (status: string) => {
    if (status === 'open') return <Badge variant="success">{t('fiscalYears.open')}</Badge>
    if (status === 'closed') return <Badge variant="warning">{t('fiscalYears.closed')}</Badge>
    return <Badge variant="danger">{t('fiscalYears.locked')}</Badge>
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('title') }, { label: t('home.structure') }, { label: t('fiscalYears.title') }]} />
      <PageHeader
        title={t('fiscalYears.title')}
        subtitle={t('fiscalYears.subtitle', { count: years.length })}
        action={<Button onClick={openCreate}><Plus className="w-4 h-4" /> {t('fiscalYears.new')}</Button>}
      />

      {loading ? (
        <SkeletonTable rows={4} cols={5} />
      ) : years.length === 0 ? (
        <EmptyState
          icon={<Calendar className="w-8 h-8" />}
          title={t('fiscalYears.noYears')}
          description={t('fiscalYears.noYearsDescription')}
          action={<Button onClick={openCreate}><Plus className="w-4 h-4" /> {t('fiscalYears.new')}</Button>}
        />
      ) : (
        <div className="space-y-4">
          {years.map((y) => (
            <Card key={y.id}>
              <div className="flex items-center gap-3">
                <button
                  onClick={() => setExpandedId(expandedId === y.id ? null : y.id)}
                  className="p-1 rounded hover:bg-[var(--color-neutral-100)]"
                >
                  {expandedId === y.id ? <ChevronDown className="w-5 h-5" /> : <ChevronRight className="w-5 h-5" />}
                </button>
                <div className="font-mono font-semibold text-lg">{y.code}</div>
                <div className="text-sm text-[var(--color-text-secondary)]">
                  {new Date(y.start_date).toLocaleDateString('fr-FR')} → {new Date(y.end_date).toLocaleDateString('fr-FR')}
                </div>
                <div className="ml-auto flex items-center gap-3">
                  {statusBadge(y.status)}
                  <button onClick={() => toggleYearStatus(y)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-text-secondary)]" title={y.status === 'open' ? t('fiscalYears.close') : t('fiscalYears.reopen')}>
                    {y.status === 'open' ? <Lock className="w-4 h-4" /> : <Unlock className="w-4 h-4" />}
                  </button>
                  <button onClick={() => openEdit(y)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-text-secondary)]">
                    <Pencil className="w-4 h-4" />
                  </button>
                  <button onClick={() => handleDelete(y.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]">
                    <Trash2 className="w-4 h-4" />
                  </button>
                </div>
              </div>

              {expandedId === y.id && (
                <div className="mt-4 border-t border-[var(--color-border)] pt-4">
                  <h4 className="text-sm font-semibold mb-2">{t('fiscalYears.periods', { count: periods[y.id]?.length || 0 })}</h4>
                  <Table headers={[t('fiscalYears.number'), t('fiscalYears.label'), t('fiscalYears.start'), t('fiscalYears.end'), tCommon('common.status'), tCommon('table.actions')]}>
                    {(periods[y.id] || []).map((p) => (
                      <TableRow key={p.id}>
                        <TableCell className="font-mono">{p.period_number}</TableCell>
                        <TableCell>{p.period_label}</TableCell>
                        <TableCell className="text-xs">{new Date(p.start_date).toLocaleDateString('fr-FR')}</TableCell>
                        <TableCell className="text-xs">{new Date(p.end_date).toLocaleDateString('fr-FR')}</TableCell>
                        <TableCell>{statusBadge(p.status)}</TableCell>
                        <TableCell>
                          <button onClick={() => togglePeriodStatus(p)} className="text-xs text-[var(--color-primary)] hover:underline">
                            {p.status === 'open' ? t('fiscalYears.close') : t('fiscalYears.reopen')}
                          </button>
                        </TableCell>
                      </TableRow>
                    ))}
                  </Table>
                </div>
              )}
            </Card>
          ))}
        </div>
      )}

      {showForm && (
        <FiscalYearForm
          year={editing}
          onClose={() => setShowForm(false)}
          onSaved={() => { setShowForm(false); loadYears() }}
        />
      )}
    </div>
  )
}

function FiscalYearForm({ year, onClose, onSaved }: {
  year: FiscalYear | null
  onClose: () => void
  onSaved: () => void
}) {
  const [code, setCode] = useState(year?.code || '')
  const { toast } = useToast()
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const [startDate, setStartDate] = useState(year?.start_date || '')
  const [endDate, setEndDate] = useState(year?.end_date || '')
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      const data = { code: code.toUpperCase(), start_date: startDate, end_date: endDate, status: year?.status || 'open' as const }
      if (year) {
        await updateFiscalYear(year.id, data)
      } else {
        const fy = await createFiscalYear(data as any)
        if (startDate && endDate) {
          await createFiscalPeriodsForYear(fy.id, startDate, endDate)
        }
      }
      onSaved()
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.createError'))
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl overflow-hidden" style={{ width: '100%', maxWidth: '32rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{year ? t('fiscalYears.edit') : t('fiscalYears.new')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <Input label={t('fiscalYears.code')} required value={code} onChange={(e) => setCode(e.target.value)} placeholder="EX2025" />
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('fiscalYears.startDate')} type="date" required value={startDate} onChange={(e) => setStartDate(e.target.value)} />
            <Input label={t('fiscalYears.endDate')} type="date" required value={endDate} onChange={(e) => setEndDate(e.target.value)} />
          </div>
          {!year && (
            <p className="text-xs text-[var(--color-text-secondary)] bg-[var(--color-neutral-50)] p-3 rounded-lg">
              {t('fiscalYears.autoPeriodsHint')}
            </p>
          )}
          <div className="flex justify-end gap-3 pt-2">
            <Button variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? tCommon('common.saving') : tCommon('actions.save')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
