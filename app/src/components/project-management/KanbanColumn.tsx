import { useTranslation } from 'react-i18next'
import { cn } from '@/lib/utils'
import type { ProjectTask, TaskStatus } from '@/types/projectManagement'
import { KanbanCard } from './KanbanCard'

interface KanbanColumnProps {
  status: TaskStatus
  title: string
  color: string
  tasks: ProjectTask[]
  projectColorMap: Map<string, string>
  projectNames: Map<string, string>
  onDrop: (taskId: string, newStatus: TaskStatus) => void
  isDragOver: boolean
  onDragOver: () => void
  onDragLeave: () => void
}

export function KanbanColumn({
  status,
  title,
  color,
  tasks,
  projectColorMap,
  projectNames,
  onDrop,
  isDragOver,
  onDragOver,
  onDragLeave,
}: KanbanColumnProps) {
  const { t } = useTranslation('taskManagement')

  return (
    <div
      role="list"
      aria-label={title}
      onDragOver={(e) => { e.preventDefault(); onDragOver() }}
      onDragLeave={onDragLeave}
      onDrop={(e) => {
        e.preventDefault()
        const taskId = e.dataTransfer.getData('text/plain')
        if (taskId) onDrop(taskId, status)
      }}
      onKeyDown={(e) => {
        if (e.key === 'Escape' && isDragOver) onDragLeave()
      }}
      tabIndex={0}
      className={cn(
        'flex flex-col rounded-lg border min-w-[250px] max-w-[300px] flex-1 transition-colors focus:outline-none focus:ring-2 focus:ring-[var(--color-primary)]',
        isDragOver ? 'border-[var(--color-primary)] bg-[rgba(0,102,204,0.04)]' : 'border-[var(--color-border)] bg-[var(--color-neutral-50)]'
      )}
    >
      <div className="flex items-center justify-between px-3 py-2 border-b border-[var(--color-border)]">
        <div className="flex items-center gap-2">
          <div className="w-2.5 h-2.5 rounded-full" style={{ backgroundColor: color }} />
          <span className="text-sm font-semibold text-[var(--color-text)]">{title}</span>
        </div>
        <span className="text-xs font-medium text-[var(--color-text-secondary)] bg-[var(--color-neutral-200)] px-2 py-0.5 rounded-full">
          {tasks.length}
        </span>
      </div>

      <div className="flex-1 overflow-y-auto p-2 space-y-2 min-h-[200px]">
        {tasks.length === 0 ? (
          <div className="text-center py-8 text-xs text-[var(--color-text-tertiary)]">
            {t('kanban.empty')}
          </div>
        ) : (
          tasks.map((task) => (
            <KanbanCard
              key={task.id}
              task={task}
              projectColor={task.project_id ? projectColorMap.get(task.project_id) || '#0066cc' : '#97a0af'}
              projectName={task.project_id ? projectNames.get(task.project_id) || '' : ''}
            />
          ))
        )}
      </div>
    </div>
  )
}
