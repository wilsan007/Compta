import { useState, useMemo, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { useTaskContext } from '@/contexts/TaskContext'
import { useProjectContext } from '@/contexts/ProjectContext'
import { Card, EmptyState, Badge } from '@/components/ui'
import { ChevronLeft, ChevronRight, Calendar as CalIcon, X } from 'lucide-react'
import { cn } from '@/lib/utils'
import {
  startOfMonth, endOfMonth, startOfWeek, endOfWeek,
  addDays, addMonths, format, isSameMonth, isToday,
  parseISO,
} from 'date-fns'
import type { ProjectTask } from '@/types/projectManagement'

const STATUS_VARIANTS: Record<string, 'neutral' | 'primary' | 'danger' | 'warning' | 'success'> = {
  todo: 'neutral',
  doing: 'primary',
  blocked: 'danger',
  changes_requested: 'warning',
  approved: 'primary',
  done: 'success',
  canceled: 'neutral',
}

interface CalendarViewProps {
  projectId?: string
}

export function CalendarView(_props: CalendarViewProps) {
  const { t } = useTranslation('taskManagement')
  const { t: tCommon } = useTranslation('common')
  const { tasks, loading } = useTaskContext()
  const { projects, projectColorMap } = useProjectContext()
  const [currentDate, setCurrentDate] = useState(new Date())
  const [selectedTask, setSelectedTask] = useState<ProjectTask | null>(null)

  const projectNames = useMemo(() => {
    const m = new Map<string, string>()
    projects.forEach((p) => m.set(p.id, p.name))
    return m
  }, [projects])

  const calendarDays = useMemo(() => {
    const monthStart = startOfMonth(currentDate)
    const monthEnd = endOfMonth(currentDate)
    const calStart = startOfWeek(monthStart, { weekStartsOn: 1 })
    const calEnd = endOfWeek(monthEnd, { weekStartsOn: 1 })

    const days: Date[] = []
    let day = calStart
    while (day <= calEnd) {
      days.push(day)
      day = addDays(day, 1)
    }
    return days
  }, [currentDate])

  const tasksByDate = useMemo(() => {
    const m = new Map<string, ProjectTask[]>()
    for (const task of tasks) {
      const dateStr = task.due_date || task.start_date
      if (!dateStr) continue
      try {
        const dateKey = format(parseISO(dateStr), 'yyyy-MM-dd')
        if (!m.has(dateKey)) m.set(dateKey, [])
        m.get(dateKey)!.push(task)
      } catch { /* skip invalid dates */ }
    }
    return m
  }, [tasks])

  const tasksForDate = useCallback((date: Date) => {
    const key = format(date, 'yyyy-MM-dd')
    return tasksByDate.get(key) || []
  }, [tasksByDate])

  if (loading) {
    return <div className="flex items-center justify-center h-64 text-[var(--color-text-secondary)]">{t('loading')}</div>
  }

  const weekDays = [
    t('calendar.mon'), t('calendar.tue'), t('calendar.wed'),
    t('calendar.thu'), t('calendar.fri'), t('calendar.sat'), t('calendar.sun'),
  ]

  return (
    <div className="flex flex-col h-full p-4 gap-4" role="region" aria-label={t('calendar.title')}>
      <div className="flex items-center justify-between">
        <h2 className="text-lg font-semibold text-[var(--color-text)]">
          {format(currentDate, 'MMMM yyyy')}
        </h2>
        <div className="flex items-center gap-2">
          <button
            onClick={() => setCurrentDate(new Date())}
            className="px-3 py-1.5 text-sm rounded-lg border border-[var(--color-border)] hover:bg-[var(--color-neutral-100)] transition-colors"
          >
            {t('calendar.today')}
          </button>
          <button
            onClick={() => setCurrentDate(addMonths(currentDate, -1))}
            className="p-1.5 rounded-lg border border-[var(--color-border)] hover:bg-[var(--color-neutral-100)] transition-colors"
            aria-label={t('calendar.prevMonth')}
          >
            <ChevronLeft className="w-4 h-4" />
          </button>
          <button
            onClick={() => setCurrentDate(addMonths(currentDate, 1))}
            className="p-1.5 rounded-lg border border-[var(--color-border)] hover:bg-[var(--color-neutral-100)] transition-colors"
            aria-label={t('calendar.nextMonth')}
          >
            <ChevronRight className="w-4 h-4" />
          </button>
        </div>
      </div>

      {tasks.length === 0 ? (
        <EmptyState icon={<CalIcon className="w-8 h-8" />} title={t('calendar.noTasks')} description={t('calendar.noTasksDesc')} />
      ) : (
        <Card className="flex-1 overflow-hidden">
          <div className="grid grid-cols-7 border-b border-[var(--color-border)]">
            {weekDays.map((day) => (
              <div key={day} className="p-2 text-center text-xs font-semibold text-[var(--color-text-secondary)] uppercase">
                {day}
              </div>
            ))}
          </div>
          <div className="grid grid-cols-7" style={{ minHeight: '400px' }}>
            {calendarDays.map((day) => {
              const dayTasks = tasksForDate(day)
              const inMonth = isSameMonth(day, currentDate)
              const today = isToday(day)

              return (
                <div
                  key={day.toISOString()}
                  className={cn(
                    'border-r border-b border-[var(--color-border)] p-1 min-h-[80px] overflow-y-auto',
                    !inMonth && 'bg-[var(--color-neutral-50)] opacity-50'
                  )}
                >
                  <div className={cn(
                    'text-xs font-medium mb-1 inline-flex items-center justify-center w-6 h-6 rounded-full',
                    today ? 'bg-[var(--color-primary)] text-white' : 'text-[var(--color-text-secondary)]'
                  )}>
                    {format(day, 'd')}
                  </div>
                  <div className="space-y-1">
                    {dayTasks.slice(0, 3).map((task) => {
                      const color = task.project_id ? (projectColorMap.get(task.project_id) || '#3b82f6') : '#6b7280'
                      return (
                        <button
                          key={task.id}
                          onClick={() => setSelectedTask(task)}
                          className="w-full text-left text-xs px-1.5 py-1 rounded truncate block hover:opacity-80 transition-opacity"
                          style={{ background: `${color}20`, color }}
                          title={task.title}
                        >
                          {task.title}
                        </button>
                      )
                    })}
                    {dayTasks.length > 3 && (
                      <div className="text-xs text-[var(--color-text-secondary)] px-1">
                        +{dayTasks.length - 3} {t('calendar.more')}
                      </div>
                    )}
                  </div>
                </div>
              )
            })}
          </div>
        </Card>
      )}

      {selectedTask && (
        <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4" onClick={() => setSelectedTask(null)}>
          <div className="card shadow-2xl max-w-md w-full p-6" onClick={(e) => e.stopPropagation()}>
            <div className="flex items-start justify-between mb-4">
              <h3 className="text-lg font-semibold text-[var(--color-text)]">{selectedTask.title}</h3>
              <button onClick={() => setSelectedTask(null)} className="text-[var(--color-text-secondary)] hover:text-[var(--color-text)]" aria-label={tCommon('actions.close')} title={tCommon('actions.close')}><X className="w-4 h-4" aria-hidden="true" /></button>
            </div>
            <div className="space-y-3">
              {selectedTask.project_id && (
                <div>
                  <span className="text-xs text-[var(--color-text-secondary)]">{t('calendar.project')}</span>
                  <div className="text-sm font-medium">{projectNames.get(selectedTask.project_id) || '—'}</div>
                </div>
              )}
              <div>
                <span className="text-xs text-[var(--color-text-secondary)]">{t('calendar.status')}</span>
                <div><Badge variant={STATUS_VARIANTS[selectedTask.status]}>{t(`status.${selectedTask.status}`)}</Badge></div>
              </div>
              {selectedTask.due_date && (
                <div>
                  <span className="text-xs text-[var(--color-text-secondary)]">{t('calendar.dueDate')}</span>
                  <div className="text-sm font-medium">{format(parseISO(selectedTask.due_date), 'PPP')}</div>
                </div>
              )}
              {selectedTask.assignee && (
                <div>
                  <span className="text-xs text-[var(--color-text-secondary)]">{t('calendar.assignee')}</span>
                  <div className="text-sm font-medium">@{selectedTask.assignee}</div>
                </div>
              )}
              {selectedTask.effort_estimate_h > 0 && (
                <div>
                  <span className="text-xs text-[var(--color-text-secondary)]">{t('calendar.estimatedHours')}</span>
                  <div className="text-sm font-medium">{selectedTask.effort_estimate_h}h</div>
                </div>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
