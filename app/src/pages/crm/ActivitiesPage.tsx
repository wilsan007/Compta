import { useState, useEffect, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Button, Table, TableRow, TableCell, Badge, EmptyState, Select, Input } from '@/components/ui'
import { formatDate } from '@/lib/utils'
import { getActivities, createActivity, completeActivity } from '@/lib/queries'
import { useToast } from '@/lib/toast'
import { Plus, X, Calendar, CheckCircle } from 'lucide-react'
import type { CrmActivity } from '@/types'

const ACTIVITY_TYPES = ['call', 'meeting', 'email', 'task', 'visit'] as const

export function ActivitiesPage() {
  const { t } = useTranslation('crm')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [activities, setActivities] = useState<CrmActivity[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [filterType, setFilterType] = useState('')
  const [filterStatus, setFilterStatus] = useState('')

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const data = await getActivities()
      setActivities(data || [])
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => { load() }, [load])

  const filtered = activities.filter(a => {
    if (filterType && a.activity_type !== filterType) return false
    if (filterStatus && a.status !== filterStatus) return false
    return true
  })

  async function handleComplete(id: string) {
    try {
      await completeActivity(id)
      toast('success', tCommon('toast.success'), tCommon('toast.updated'))
      await load()
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message)
    }
  }

  function getStatusBadge(status: string): 'neutral' | 'success' | 'danger' | 'warning' {
    if (status === 'done') return 'success'
    if (status === 'cancelled') return 'danger'
    if (status === 'postponed') return 'warning'
    return 'neutral'
  }

  return (
    <div className="p-6 max-w-7xl mx-auto">
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-2xl font-bold flex items-center gap-2">
            <Calendar className="w-6 h-6 text-[var(--color-primary)]" />
            {t('activities.title')}
          </h1>
          <p className="text-sm text-[var(--color-text-secondary)] mt-1">{t('activities.subtitle')}</p>
        </div>
        <Button onClick={() => setShowForm(true)}>
          <Plus className="w-4 h-4" /> {t('activities.new')}
        </Button>
      </div>

      <div className="flex items-center gap-4 mb-4">
        <Select value={filterType} onChange={(e) => setFilterType(e.target.value)} options={[
          { value: '', label: tCommon('filters.all') },
          ...ACTIVITY_TYPES.map(tp => ({ value: tp, label: t(`activities.${tp}`) })),
        ]} />
        <Select value={filterStatus} onChange={(e) => setFilterStatus(e.target.value)} options={[
          { value: '', label: tCommon('filters.all') },
          { value: 'planned', label: t('activities.planned') },
          { value: 'done', label: t('activities.done') },
          { value: 'cancelled', label: t('activities.cancelled') },
          { value: 'postponed', label: t('activities.postponed') },
        ]} />
      </div>

      {loading ? (
        <div className="space-y-2">{[1, 2, 3].map(i => <div key={i} className="h-12 rounded animate-pulse bg-[var(--color-neutral-100)]" />)}</div>
      ) : filtered.length === 0 ? (
        <EmptyState icon={<Calendar className="w-8 h-8" />} title={t('activities.noActivities')} description={t('activities.noActivitiesDescription')} />
      ) : (
        <Table headers={[t('activities.type'), t('activities.subject'), t('activities.scheduledDate'), t('activities.duration'), t('activities.status'), t('activities.assignedTo'), tCommon('table.actions')]}>
          {filtered.map(a => (
            <TableRow key={a.id}>
              <TableCell><Badge variant="neutral">{t(`activities.${a.activity_type}`)}</Badge></TableCell>
              <TableCell className="font-medium">{a.subject}</TableCell>
              <TableCell className="text-xs">{a.scheduled_date ? formatDate(a.scheduled_date) : '-'}</TableCell>
              <TableCell className="text-xs">{a.duration_minutes ? `${a.duration_minutes} min` : '-'}</TableCell>
              <TableCell><Badge variant={getStatusBadge(a.status)}>{t(`activities.${a.status}`)}</Badge></TableCell>
              <TableCell className="text-xs">{a.assigned_to || '-'}</TableCell>
              <TableCell>
                {a.status !== 'done' && (
                  <button onClick={() => handleComplete(a.id)} className="p-1 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-success)]" title={t('activities.complete')}>
                    <CheckCircle className="w-4 h-4" />
                  </button>
                )}
              </TableCell>
            </TableRow>
          ))}
        </Table>
      )}

      {showForm && <ActivityForm onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); load() }} />}
    </div>
  )
}

function ActivityForm({ onClose, onSaved }: { onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation('crm')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [activityType, setActivityType] = useState<CrmActivity['activity_type']>('call')
  const [subject, setSubject] = useState('')
  const [description, setDescription] = useState('')
  const [scheduledDate, setScheduledDate] = useState('')
  const [duration, setDuration] = useState(30)
  const [assignedTo, setAssignedTo] = useState('')
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!subject) return
    setSaving(true)
    try {
      await createActivity({
        tenant_id: null,
        opportunity_id: null,
        customer_id: null,
        activity_type: activityType,
        subject,
        description: description || null,
        scheduled_date: scheduledDate ? new Date(scheduledDate).toISOString() : null,
        completed_date: null,
        duration_minutes: duration,
        status: 'planned',
        assigned_to: assignedTo || null,
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
          <h2 className="text-lg font-semibold">{t('activities.new')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <Select label={t('activities.type')} required value={activityType} onChange={(e) => setActivityType(e.target.value as any)} options={ACTIVITY_TYPES.map(tp => ({ value: tp, label: t(`activities.${tp}`) }))} />
          <Input label={t('activities.subject')} required value={subject} onChange={(e) => setSubject(e.target.value)} />
          <Input label={t('activities.description')} value={description} onChange={(e) => setDescription(e.target.value)} />
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('activities.scheduledDate')} type="datetime-local" value={scheduledDate} onChange={(e) => setScheduledDate(e.target.value)} />
            <Input label={t('activities.duration')} type="number" value={duration} onChange={(e) => setDuration(Number(e.target.value))} />
          </div>
          <Input label={t('activities.assignedTo')} value={assignedTo} onChange={(e) => setAssignedTo(e.target.value)} />
          <div className="flex justify-end gap-3 pt-2 border-t border-[var(--color-border)]">
            <Button type="button" variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? tCommon('actions.saving') : tCommon('actions.save')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
