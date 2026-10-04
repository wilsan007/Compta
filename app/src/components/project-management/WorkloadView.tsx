import { useMemo } from 'react'
import { useTranslation } from 'react-i18next'
import { Users, AlertTriangle, CheckCircle } from 'lucide-react'
import { useTaskContext } from '@/contexts/TaskContext'
import type { WorkloadEntry } from '@/types/projectManagement'

interface WorkloadViewProps {
  projectId?: string
}

export function WorkloadView({ projectId }: WorkloadViewProps) {
  const { t } = useTranslation('taskManagement')
  const { tasks, loading } = useTaskContext()

  const workloadData = useMemo<WorkloadEntry[]>(() => {
    if (loading || tasks.length === 0) return []
    const filtered = projectId ? tasks.filter((t) => t.project_id === projectId) : tasks
    return getWorkloadDataSync(filtered)
  }, [tasks, projectId, loading])

  if (loading) {
    return (
      <div className="flex items-center justify-center h-full">
        <p className="text-[var(--color-text-secondary)]">{t('loading')}</p>
      </div>
    )
  }

  if (workloadData.length === 0) {
    return (
      <div className="flex flex-col items-center justify-center h-full gap-2">
        <Users className="w-12 h-12 text-[var(--color-text-secondary)] opacity-50" />
        <p className="text-[var(--color-text)] font-medium">{t('workload.noData')}</p>
        <p className="text-sm text-[var(--color-text-secondary)]">{t('workload.noDataDesc')}</p>
      </div>
    )
  }

  const statusColors: Record<WorkloadEntry['status'], string> = {
    underloaded: 'text-blue-500 bg-blue-50',
    balanced: 'text-green-500 bg-green-50',
    overloaded: 'text-red-500 bg-red-50',
  }

  const statusIcons: Record<WorkloadEntry['status'], React.ReactNode> = {
    underloaded: <CheckCircle className="w-4 h-4" />,
    balanced: <CheckCircle className="w-4 h-4" />,
    overloaded: <AlertTriangle className="w-4 h-4" />,
  }

  return (
    <div className="h-full overflow-auto p-4">
      <div className="mb-4">
        <h2 className="text-lg font-semibold">{t('workload.title')}</h2>
        <p className="text-sm text-[var(--color-text-secondary)]">{t('workload.subtitle')}</p>
      </div>

      <div className="grid gap-3">
        {workloadData.map((entry) => (
          <div
            key={entry.employee_id}
            className="rounded-lg border border-[var(--color-border)] bg-[var(--color-surface)] p-4"
          >
            <div className="flex items-center justify-between mb-3">
              <div className="flex items-center gap-2">
                <div className="w-8 h-8 rounded-full bg-[var(--color-primary)] text-white flex items-center justify-center text-sm font-medium">
                  {entry.employee_name.charAt(0).toUpperCase()}
                </div>
                <span className="font-medium">{entry.employee_name}</span>
              </div>
              <span
                className={`flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium ${statusColors[entry.status]}`}
              >
                {statusIcons[entry.status]}
                {t(`workload.${entry.status}`)}
              </span>
            </div>

            <div className="grid grid-cols-2 md:grid-cols-4 gap-3 text-sm">
              <div>
                <span className="text-xs text-[var(--color-text-secondary)]">{t('workload.totalTasks')}</span>
                <p className="font-semibold">{entry.total_tasks}</p>
              </div>
              <div>
                <span className="text-xs text-[var(--color-text-secondary)]">{t('workload.activeTasks')}</span>
                <p className="font-semibold">{entry.active_tasks}</p>
              </div>
              <div>
                <span className="text-xs text-[var(--color-text-secondary)]">{t('workload.overdueTasks')}</span>
                <p className="font-semibold text-red-500">{entry.overdue_tasks}</p>
              </div>
              <div>
                <span className="text-xs text-[var(--color-text-secondary)]">{t('workload.estimatedHours')}</span>
                <p className="font-semibold">{entry.estimated_hours}h</p>
              </div>
            </div>

            <div className="mt-3">
              <div className="flex items-center justify-between text-xs mb-1">
                <span className="text-[var(--color-text-secondary)]">{t('workload.utilization')}</span>
                <span className="font-medium">{entry.utilization_percentage}%</span>
              </div>
              <div className="h-2 rounded-full bg-[var(--color-neutral-100)] overflow-hidden">
                <div
                  className={`h-full rounded-full transition-all ${
                    entry.status === 'overloaded'
                      ? 'bg-red-500'
                      : entry.status === 'balanced'
                      ? 'bg-green-500'
                      : 'bg-blue-500'
                  }`}
                  style={{ width: `${Math.min(entry.utilization_percentage, 100)}%` }}
                />
              </div>
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}

function getWorkloadDataSync(tasks: import('@/types/projectManagement').ProjectTask[]): WorkloadEntry[] {
  const now = new Date()
  const overdueThreshold = now.toISOString().split('T')[0]
  const capacityHoursPerWeek = 40

  const byEmployee = new Map<string, import('@/types/projectManagement').ProjectTask[]>()

  for (const task of tasks) {
    if (!task.assignee || task.status === 'done' || task.status === 'canceled') continue
    if (!byEmployee.has(task.assignee)) {
      byEmployee.set(task.assignee, [])
    }
    byEmployee.get(task.assignee)!.push(task)
  }

  const entries: WorkloadEntry[] = []
  for (const [name, taskList] of byEmployee) {
    const total = taskList.length
    const active = taskList.filter((t) => t.status === 'doing' || t.status === 'todo').length
    const overdue = taskList.filter(
      (t) => t.due_date && t.due_date < overdueThreshold && t.status !== 'done' && t.status !== 'canceled'
    ).length
    const estimated = taskList.reduce((sum, t) => sum + (t.effort_estimate_h || 0), 0)
    const spent = taskList.reduce((sum, t) => sum + (t.effort_spent_h || 0), 0)
    const utilization = capacityHoursPerWeek > 0 ? Math.round((estimated / capacityHoursPerWeek) * 100) : 0

    let status: WorkloadEntry['status'] = 'balanced'
    if (utilization > 100) status = 'overloaded'
    else if (utilization < 50) status = 'underloaded'

    entries.push({
      employee_id: name,
      employee_name: name,
      total_tasks: total,
      active_tasks: active,
      overdue_tasks: overdue,
      estimated_hours: Math.round(estimated * 10) / 10,
      spent_hours: Math.round(spent * 10) / 10,
      capacity_hours: capacityHoursPerWeek,
      utilization_percentage: utilization,
      status,
    })
  }

  return entries.sort((a, b) => b.utilization_percentage - a.utilization_percentage)
}
