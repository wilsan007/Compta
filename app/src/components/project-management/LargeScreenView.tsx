import { useState, useMemo } from 'react'
import { useTranslation } from 'react-i18next'
import { useTaskContext } from '@/contexts/TaskContext'
import { useProjectContext } from '@/contexts/ProjectContext'
import { Badge, EmptyState } from '@/components/ui'
import { MessageSquare, ChevronRight } from 'lucide-react'
import { cn } from '@/lib/utils'
import { formatDate } from '@/lib/utils'
import { TaskChatter } from './TaskChatter'
import type { ProjectTask, TaskStatus } from '@/types/projectManagement'

const STATUS_VARIANTS: Record<TaskStatus, 'neutral' | 'primary' | 'danger' | 'warning' | 'success'> = {
  todo: 'neutral',
  doing: 'primary',
  blocked: 'danger',
  changes_requested: 'warning',
  approved: 'primary',
  done: 'success',
  canceled: 'neutral',
}

interface LargeScreenViewProps {
  projectId?: string
}

export function LargeScreenView(_props: LargeScreenViewProps) {
  const { t } = useTranslation('taskManagement')
  const { tasks, loading } = useTaskContext()
  const { projects, projectColorMap } = useProjectContext()
  const [selectedTask, setSelectedTask] = useState<ProjectTask | null>(null)

  const projectNames = useMemo(() => {
    const m = new Map<string, string>()
    projects.forEach((p) => m.set(p.id, p.name))
    return m
  }, [projects])

  if (loading) {
    return <div className="flex items-center justify-center h-64 text-[var(--color-text-secondary)]">{t('loading')}</div>
  }

  return (
    <div className="flex h-full" role="region" aria-label={t('largeScreen.title')}>
      <div className="flex-1 overflow-y-auto p-4">
        {tasks.length === 0 ? (
          <EmptyState icon={<ChevronRight className="w-8 h-8" />} title={t('largeScreen.noTasks')} description={t('largeScreen.noTasksDesc')} />
        ) : (
          <div className="space-y-1">
            {tasks.map((task) => {
              const projectName = task.project_id ? (projectNames.get(task.project_id) || '') : null
              const projectColor = task.project_id ? (projectColorMap.get(task.project_id) || '#3b82f6') : '#6b7280'
              const isSelected = selectedTask?.id === task.id

              return (
                <button
                  key={task.id}
                  onClick={() => setSelectedTask(task)}
                  className={cn(
                    'w-full flex items-center gap-3 p-3 rounded-lg border text-left transition-colors',
                    isSelected
                      ? 'border-[var(--color-primary)] bg-[var(--color-primary)]/5'
                      : 'border-[var(--color-border)] bg-[var(--color-surface)] hover:bg-[var(--color-neutral-50)]'
                  )}
                >
                  <div className="w-1 h-8 rounded-full" style={{ background: projectColor }} />
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2">
                      <span className="text-sm font-medium text-[var(--color-text)] truncate">{task.title}</span>
                      {task.parent_id && (
                        <span className="text-xs text-[var(--color-text-secondary)]">↳</span>
                      )}
                    </div>
                    <div className="flex items-center gap-2 mt-0.5">
                      {projectName && (
                        <span className="text-xs px-2 py-0.5 rounded-full" style={{ background: `${projectColor}20`, color: projectColor }}>
                          {projectName}
                        </span>
                      )}
                      <Badge variant={STATUS_VARIANTS[task.status]}>{t(`status.${task.status}`)}</Badge>
                      {task.assignee && <span className="text-xs text-[var(--color-text-secondary)]">@{task.assignee}</span>}
                    </div>
                  </div>
                  {task.due_date && (
                    <div className="text-xs text-[var(--color-text-secondary)] text-right">
                      {formatDate(task.due_date)}
                    </div>
                  )}
                  <ChevronRight className={cn('w-4 h-4 text-[var(--color-text-secondary)] transition-transform', isSelected && 'rotate-90')} />
                </button>
              )
            })}
          </div>
        )}
      </div>

      <div className="w-[380px] border-l border-[var(--color-border)] bg-[var(--color-surface)] flex flex-col">
        {selectedTask ? (
          <>
            <div className="px-4 py-3 border-b border-[var(--color-border)]">
              <h3 className="text-sm font-semibold text-[var(--color-text)]">{selectedTask.title}</h3>
              <div className="flex items-center gap-2 mt-1">
                <Badge variant={STATUS_VARIANTS[selectedTask.status]}>{t(`status.${selectedTask.status}`)}</Badge>
                {selectedTask.priority === 'urgent' && (
                  <span className="text-xs text-[var(--color-danger)] font-medium">{t('myTasks.urgent')}</span>
                )}
              </div>
            </div>
            <TaskChatter task={selectedTask} className="flex-1" />
          </>
        ) : (
          <div className="flex-1 flex items-center justify-center">
            <EmptyState icon={<MessageSquare className="w-8 h-8" />} title={t('largeScreen.selectTask')} description={t('largeScreen.selectTaskDesc')} />
          </div>
        )}
      </div>
    </div>
  )
}
