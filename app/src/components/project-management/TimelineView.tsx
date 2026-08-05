import { useMemo } from 'react'
import { useTranslation } from 'react-i18next'
import { GitBranch } from 'lucide-react'
import { useTaskContext } from '@/contexts/TaskContext'
import { useProjectContext } from '@/contexts/ProjectContext'
import type { TimelineItem, ProjectTask } from '@/types/projectManagement'

interface TimelineViewProps {
  projectId?: string
}

export function TimelineView({ projectId }: TimelineViewProps) {
  const { t } = useTranslation('taskManagement')
  const { tasks, loading } = useTaskContext()
  const { projects, projectColorMap } = useProjectContext()

  const projectNames = useMemo(() => {
    const map = new Map<string, string>()
    projects.forEach((p) => map.set(p.id, p.name))
    return map
  }, [projects])

  const timelineItems = useMemo<TimelineItem[]>(() => {
    const filtered = projectId ? tasks.filter((t) => t.project_id === projectId) : tasks
    return filtered
      .filter((t) => t.start_date || t.due_date)
      .map((task: ProjectTask) => ({
        id: task.id,
        title: task.title,
        start_date: task.start_date || task.due_date || '',
        due_date: task.due_date,
        status: task.status,
        priority: task.priority,
        project_id: task.project_id,
        project_name: task.project_id ? projectNames.get(task.project_id) : undefined,
        project_color: task.project_id ? projectColorMap.get(task.project_id) : undefined,
        assignee: task.assignee,
        progress: task.progress,
        parent_id: task.parent_id,
        task_level: task.task_level,
      }))
      .sort((a, b) => (a.start_date || '').localeCompare(b.start_date || ''))
  }, [tasks, projectId, projectNames, projectColorMap])

  const { today, upcoming, past, noDate } = useMemo(() => {
    const now = new Date().toISOString().split('T')[0]
    return {
      today: timelineItems.filter((i) => i.start_date === now || (i.due_date && i.due_date === now)),
      upcoming: timelineItems.filter((i) => i.start_date > now),
      past: timelineItems.filter((i) => i.due_date && i.due_date < now),
      noDate: tasks.filter((t) => !t.start_date && !t.due_date && t.status !== 'done' && t.status !== 'canceled'),
    }
  }, [timelineItems, tasks])

  if (loading) {
    return (
      <div className="flex items-center justify-center h-full">
        <p className="text-[var(--color-text-secondary)]">{t('loading')}</p>
      </div>
    )
  }

  if (timelineItems.length === 0 && noDate.length === 0) {
    return (
      <div className="flex flex-col items-center justify-center h-full gap-2">
        <GitBranch className="w-12 h-12 text-[var(--color-text-secondary)] opacity-50" />
        <p className="text-[var(--color-text)] font-medium">{t('timeline.noTasks')}</p>
        <p className="text-sm text-[var(--color-text-secondary)]">{t('timeline.noTasksDesc')}</p>
      </div>
    )
  }

  const statusColors: Record<string, string> = {
    todo: 'bg-gray-400',
    doing: 'bg-blue-500',
    blocked: 'bg-orange-500',
    changes_requested: 'bg-yellow-500',
    approved: 'bg-purple-500',
    done: 'bg-green-500',
    canceled: 'bg-gray-300',
  }

  const renderSection = (title: string, items: TimelineItem[] | ProjectTask[]) => {
    if (items.length === 0) return null
    return (
      <div className="mb-6">
        <h3 className="text-sm font-semibold text-[var(--color-text-secondary)] mb-2 sticky top-0 bg-[var(--color-surface)] py-1">
          {title} ({items.length})
        </h3>
        <div className="space-y-1.5">
          {items.map((item) => {
            const isTimeline = 'start_date' in item
            const title = isTimeline ? (item as TimelineItem).title : (item as ProjectTask).title
            const status = isTimeline ? (item as TimelineItem).status : (item as ProjectTask).status
            const projName = isTimeline ? (item as TimelineItem).project_name : undefined
            const projColor = isTimeline ? (item as TimelineItem).project_color : undefined
            const startDate = isTimeline ? (item as TimelineItem).start_date : null
            const dueDate = isTimeline ? (item as TimelineItem).due_date : null
            const assignee = isTimeline ? (item as TimelineItem).assignee : (item as ProjectTask).assignee

            return (
              <div
                key={item.id}
                className="flex items-center gap-3 p-2 rounded-lg border border-[var(--color-border)] bg-[var(--color-surface)] hover:border-[var(--color-primary)] transition-colors"
              >
                <div className={`w-2 h-2 rounded-full flex-shrink-0 ${statusColors[status] || 'bg-gray-400'}`} />
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-medium truncate">{title}</p>
                  <div className="flex items-center gap-2 text-xs text-[var(--color-text-secondary)]">
                    {projName && (
                      <span
                        className="px-1.5 py-0.5 rounded text-[10px]"
                        style={{ backgroundColor: projColor ? `${projColor}20` : undefined, color: projColor }}
                      >
                        {projName}
                      </span>
                    )}
                    {assignee && <span>{assignee}</span>}
                    {startDate && <span>📅 {new Date(startDate).toLocaleDateString()}</span>}
                    {dueDate && <span>⏰ {new Date(dueDate).toLocaleDateString()}</span>}
                  </div>
                </div>
              </div>
            )
          })}
        </div>
      </div>
    )
  }

  return (
    <div className="h-full overflow-auto p-4">
      <div className="mb-4">
        <h2 className="text-lg font-semibold flex items-center gap-2">
          <GitBranch className="w-5 h-5" />
          {t('timeline.title')}
        </h2>
        <p className="text-sm text-[var(--color-text-secondary)]">{t('timeline.subtitle')}</p>
      </div>

      {renderSection(t('timeline.today'), today)}
      {renderSection(t('timeline.upcoming'), upcoming)}
      {renderSection(t('timeline.past'), past)}
      {noDate.length > 0 && renderSection(t('timeline.noDate'), noDate as ProjectTask[])}
    </div>
  )
}
