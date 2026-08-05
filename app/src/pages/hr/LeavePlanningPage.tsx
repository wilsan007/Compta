import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, EmptyState, Breadcrumb, SkeletonTable, Select } from '@/components/ui'
import { getLeaveRequests, getEmployees, getPublicHolidays, getLeaveRules } from '@/lib/queries'
import { DEFAULT_LEAVE_COLOR } from '@/lib/constants'
import type { Employee, LeaveRule, PublicHoliday } from '@/types'
import { CalendarDays } from 'lucide-react'

export function LeavePlanningPage() {
  const { t } = useTranslation('hr')
  const { t: tCommon } = useTranslation('common')
  const { t: tNav } = useTranslation('nav')
  const [requests, setRequests] = useState<any[]>([])
  const [employees, setEmployees] = useState<Employee[]>([])
  const [rules, setRules] = useState<LeaveRule[]>([])
  const [holidays, setHolidays] = useState<PublicHoliday[]>([])
  const [loading, setLoading] = useState(true)
  const [month, setMonth] = useState(new Date().getMonth())
  const [year, setYear] = useState(new Date().getFullYear())
  const [deptFilter, setDeptFilter] = useState('')

  const loadData = useCallback(async () => {
    try {
      const [reqs, emps, rls, hols] = await Promise.all([
        getLeaveRequests(),
        getEmployees(),
        getLeaveRules(true),
        getPublicHolidays(year),
      ])
      setRequests(reqs || [])
      setEmployees(emps || [])
      setRules(rls || [])
      setHolidays(hols || [])
    } catch (err: any) { console.error(err) }
    finally { setLoading(false) }
  }, [year])

  useEffect(() => { loadData() }, [loadData])

  const empName = (id: string) => employees.find((e) => e.id === id)?.name || '—'
  const empDept = (id: string) => employees.find((e) => e.id === id)?.department || ''
  const ruleColor = (type: string) => rules.find((r) => r.leave_type === type)?.color || DEFAULT_LEAVE_COLOR

  const daysInMonth = new Date(year, month + 1, 0).getDate()
  const days = Array.from({ length: daysInMonth }, (_, i) => i + 1)
  const holidayDates = new Set(holidays.map((h) => h.holiday_date))

  const filteredRequests = requests.filter((r) => {
    if (r.status !== 'approved' && r.status !== 'pending') return false
    const start = new Date(r.start_date)
    const end = new Date(r.end_date)
    if (start.getFullYear() > year || end.getFullYear() < year) return false
    if (start.getMonth() > month && end.getMonth() < month) return false
    if (deptFilter && empDept(r.employee_id) !== deptFilter) return false
    return true
  })

  const departments = [...new Set(employees.map((e) => e.department).filter(Boolean))]

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('sections.hr') }, { label: t('leavePlanning.title') }]} />
      <PageHeader title={t('leavePlanning.title')} subtitle={t('leavePlanning.subtitle')} />

      <div className="flex gap-3 mb-4 items-end">
        <div className="w-32">
          <Select label={t('leavePlanning.month')} value={String(month)} onChange={(e) => setMonth(Number(e.target.value))} options={[
            ...Array.from({ length: 12 }, (_, i) => ({ value: String(i), label: tCommon(`months.${i}`) })),
          ]} />
        </div>
        <div className="w-28">
          <Select label={t('leavePlanning.year')} value={String(year)} onChange={(e) => setYear(Number(e.target.value))} options={[
            { value: String(new Date().getFullYear() - 1), label: String(new Date().getFullYear() - 1) },
            { value: String(new Date().getFullYear()), label: String(new Date().getFullYear()) },
            { value: String(new Date().getFullYear() + 1), label: String(new Date().getFullYear() + 1) },
          ]} />
        </div>
        <div className="w-48">
          <Select label={t('leavePlanning.department')} value={deptFilter} onChange={(e) => setDeptFilter(e.target.value)} options={[
            { value: '', label: tCommon('table.all') },
            ...departments.map((d) => ({ value: d, label: d })),
          ]} />
        </div>
      </div>

      <div className="flex flex-wrap gap-3 mb-4">
        {rules.map((r) => (
          <div key={r.id} className="flex items-center gap-2 text-xs">
            <div className="w-3 h-3 rounded" style={{ backgroundColor: r.color }} />
            <span>{r.label}</span>
          </div>
        ))}
        <div className="flex items-center gap-2 text-xs">
          <div className="w-3 h-3 rounded bg-gray-300" />
          <span>{t('leavePlanning.holiday')}</span>
        </div>
      </div>

      {loading ? <SkeletonTable rows={6} cols={8} /> : filteredRequests.length === 0 ? (
        <EmptyState icon={<CalendarDays className="w-8 h-8" />} title={t('leavePlanning.noLeaves')} description={t('leavePlanning.noLeavesDescription')} />
      ) : (
        <Card>
          <div className="overflow-x-auto">
            <table className="w-full text-xs">
              <thead>
                <tr className="border-b border-[var(--color-border)]">
                  <th className="text-left p-2 sticky left-0 bg-[var(--color-surface)] min-w-[120px]">{t('leavePlanning.employee')}</th>
                  {days.map((d) => {
                    const dateStr = `${year}-${String(month + 1).padStart(2, '0')}-${String(d).padStart(2, '0')}`
                    const isHoliday = holidayDates.has(dateStr)
                    const dow = new Date(year, month, d).getDay()
                    const isWeekend = dow === 0 || dow === 6
                    return (
                      <th key={d} className={`p-1 text-center min-w-[28px] ${isHoliday ? 'bg-gray-200' : isWeekend ? 'bg-gray-100' : ''}`}>
                        {d}
                      </th>
                    )
                  })}
                </tr>
              </thead>
              <tbody>
                {filteredRequests.map((r) => {
                  const color = ruleColor(r.leave_type)
                  return (
                    <tr key={r.id} className="border-b border-[var(--color-border)]">
                      <td className="p-2 sticky left-0 bg-[var(--color-surface)] font-medium">
                        {empName(r.employee_id)}
                      </td>
                      {days.map((d) => {
                        const dateStr = `${year}-${String(month + 1).padStart(2, '0')}-${String(d).padStart(2, '0')}`
                        const start = r.start_date
                        const end = r.end_date
                        const isOnLeave = dateStr >= start && dateStr <= end
                        return (
                          <td key={d} className="p-1 text-center">
                            {isOnLeave && <div className="w-full h-4 rounded" style={{ backgroundColor: color }} title={`${r.leave_type} — ${r.status}`} />}
                          </td>
                        )
                      })}
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        </Card>
      )}

      <div className="mt-4">
        <h3 className="text-sm font-semibold mb-2">{t('leavePlanning.legend')}</h3>
        <div className="flex flex-wrap gap-4">
          {rules.map((r) => (
            <div key={r.id} className="flex items-center gap-2 text-xs">
              <div className="w-3 h-3 rounded" style={{ backgroundColor: r.color }} />
              <span>{r.label}</span>
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}
