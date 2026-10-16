import { useCallback, useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Input, Select, EmptyState, Breadcrumb, Skeleton } from '@/components/ui'
import { errorMessage } from '@/lib/utils'
import { useToast } from '@/lib/toast'
import { confirmSync } from '@/lib/confirm'
import {
  getResourceCapacities,
  createResourceCapacity,
  deleteResourceCapacity,
  getEmployeeOptions,
  type ResourceCapacity,
  type EmployeeOption,
} from '@/lib/queries/resourceCapacities'
import { CalendarClock, Plus, Trash2 } from 'lucide-react'

export function ResourceCapacityPage() {
  const { t } = useTranslation('settings')
  const { t: tNav } = useTranslation('nav')
  const { toast } = useToast()

  const [capacities, setCapacities] = useState<ResourceCapacity[]>([])
  const [employees, setEmployees] = useState<EmployeeOption[]>([])
  const [loading, setLoading] = useState(true)

  const [employeeId, setEmployeeId] = useState('')
  const [periodStart, setPeriodStart] = useState('')
  const [periodEnd, setPeriodEnd] = useState('')
  const [weeklyHours, setWeeklyHours] = useState('')

  const loadAll = useCallback(async () => {
    try {
      const [caps, emps] = await Promise.all([getResourceCapacities(), getEmployeeOptions()])
      setCapacities(caps)
      setEmployees(emps)
      setEmployeeId((cur) => (cur && emps.some((e) => e.id === cur) ? cur : (emps[0]?.id ?? '')))
    } catch (err) {
      toast('error', t('resourceCapacity.title'), errorMessage(err))
    } finally {
      setLoading(false)
    }
  }, [toast, t])

  useEffect(() => { loadAll() }, [loadAll])

  function employeeName(id: string): string {
    return employees.find((e) => e.id === id)?.name ?? id
  }

  async function handleCreate() {
    if (!employeeId || !periodStart || !periodEnd || !weeklyHours) return
    try {
      await createResourceCapacity({
        employeeId,
        periodStart,
        periodEnd,
        weeklyHours: Number(weeklyHours),
      })
      setPeriodStart(''); setPeriodEnd(''); setWeeklyHours('')
      await loadAll()
    } catch (err) {
      toast('error', t('resourceCapacity.title'), errorMessage(err))
    }
  }

  async function handleDelete(id: string) {
    if (!confirmSync(t('resourceCapacity.confirmDelete'))) return
    try {
      await deleteResourceCapacity(id)
      await loadAll()
    } catch (err) {
      toast('error', t('resourceCapacity.title'), errorMessage(err))
    }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('groups.system') }, { label: t('resourceCapacity.title') }]} />
      <PageHeader title={t('resourceCapacity.title')} subtitle={t('resourceCapacity.subtitle')} />

      {loading ? (
        <Skeleton className="h-40 w-full" />
      ) : (
        <div className="space-y-6">
          <Card>
            <div className="flex items-center gap-2 mb-3">
              <CalendarClock className="w-5 h-5 text-[var(--color-primary)]" aria-hidden="true" />
              <h3 className="font-semibold">{t('resourceCapacity.createTitle')}</h3>
            </div>
            <div className="grid grid-cols-1 md:grid-cols-5 gap-2">
              <Select label={t('resourceCapacity.employee')} value={employeeId} onChange={(e) => setEmployeeId(e.target.value)}>
                {employees.map((emp) => <option key={emp.id} value={emp.id}>{emp.name}</option>)}
              </Select>
              <Input label={t('resourceCapacity.start')} type="date" value={periodStart}
                onChange={(e) => setPeriodStart(e.target.value)} />
              <Input label={t('resourceCapacity.end')} type="date" value={periodEnd}
                onChange={(e) => setPeriodEnd(e.target.value)} />
              <Input label={t('resourceCapacity.hours')} type="number" value={weeklyHours}
                onChange={(e) => setWeeklyHours(e.target.value.replace(/[^0-9.]/g, ''))} />
              <div className="flex items-end">
                <Button onClick={handleCreate} disabled={!employeeId || !periodStart || !periodEnd || !weeklyHours}>
                  <Plus className="w-4 h-4 mr-1" aria-hidden="true" />{t('resourceCapacity.create')}
                </Button>
              </div>
            </div>
          </Card>

          {capacities.length === 0 ? (
            <EmptyState icon={<CalendarClock className="w-8 h-8" aria-hidden="true" />} title={t('resourceCapacity.empty')} />
          ) : (
            <Card>
              <ul className="divide-y divide-[var(--color-border)]">
                {capacities.map((c) => (
                  <li key={c.id} className="flex items-center justify-between py-2">
                    <div>
                      <span className="font-medium">{employeeName(c.employee_id)}</span>{' '}
                      <span className="text-sm text-[var(--color-text-secondary)]">
                        {c.period_start} → {c.period_end} · {Number(c.weekly_hours).toFixed(2)} {t('resourceCapacity.hoursUnit')}
                      </span>
                    </div>
                    <button
                      type="button"
                      onClick={() => handleDelete(c.id)}
                      aria-label={t('resourceCapacity.remove')}
                      title={t('resourceCapacity.remove')}
                      className="text-[var(--color-danger)] min-w-[24px] min-h-[24px]"
                    >
                      <Trash2 className="w-4 h-4" aria-hidden="true" />
                    </button>
                  </li>
                ))}
              </ul>
            </Card>
          )}
        </div>
      )}
    </div>
  )
}

