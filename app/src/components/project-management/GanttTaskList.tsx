import { useTranslation } from 'react-i18next'
import { cn } from '@/lib/utils'
import type { GanttTask } from '@/types/projectManagement'
import { Avatar } from './Avatar'

interface GanttTaskListProps {
  tasks: GanttTask[]
  projectColorMap: Map<string, string>
  projectNames: Map<string, string>
  rowHeight: number
  className?: string
}

export function GanttTaskList({
  tasks,
  projectColorMap,
  projectNames,
  rowHeight,
  className,
}: GanttTaskListProps) {
  const { t } = useTranslation('taskManagement')

  const grouped = new Map<string, GanttTask[]>()
  for (const task of tasks) {
    const key = task.project_id || 'no-project'
    if (!grouped.has(key)) grouped.set(key, [])
    grouped.get(key)!.push(task)
  }

  let index = 0

  return (
    <div className={cn('overflow-y-auto', className)}>
      {grouped.size === 0 ? (
        <div className="text-center py-8 text-sm text-[var(--color-text-tertiary)]">
          {t('gantt.noTasks')}
        </div>
      ) : (
        Array.from(grouped.entries()).map(([projectId, projectTasks]) => {
          const projectName = projectId === 'no-project' ? t('gantt.noProject') : projectNames.get(projectId) || ''
          const projectColor = projectId === 'no-project' ? '#97a0af' : projectColorMap.get(projectId) || '#0066cc'
          return (
            <div key={projectId}>
              <div
                className="sticky top-0 z-5 bg-[var(--color-neutral-100)] border-b border-[var(--color-border)] px-3 py-1.5 flex items-center gap-2"
                style={{ height: rowHeight }}
              >
                <div className="w-2.5 h-2.5 rounded-full" style={{ backgroundColor: projectColor }} />
                <span className="text-xs font-semibold text-[var(--color-text)] truncate">{projectName}</span>
                <span className="text-xs text-[var(--color-text-tertiary)]">({projectTasks.length})</span>
              </div>
              {projectTasks.map((task) => {
                const rowIdx = index++
                return (
                  <div
                    key={task.id}
                    className="flex items-center gap-2 px-3 border-b border-[var(--color-border)] hover:bg-[var(--color-neutral-50)]"
                    style={{ height: rowHeight }}
                    data-row-index={rowIdx}
                  >
                    <span
                      className="text-xs truncate flex-1"
                      style={{ paddingLeft: `${task.task_level * 12}px` }}
                    >
                      {task.title}
                    </span>
                    {task.assignee && <Avatar name={task.assignee} size="xs" />}
                  </div>
                )
              })}
            </div>
          )
        })
      )}
    </div>
  )
}
