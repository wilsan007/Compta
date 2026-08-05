import { cn } from '@/lib/utils'
import { useLocale } from '@/hooks/useLocale'
import { Avatar } from './Avatar'
import { ProgressBar } from './ProgressBar'
import type { ProjectTask } from '@/types/projectManagement'
import { Calendar, Flag } from 'lucide-react'

interface KanbanCardProps {
  task: ProjectTask
  projectColor: string
  projectName: string
  className?: string
}

const priorityColors: Record<string, string> = {
  low: 'text-[var(--color-text-tertiary)]',
  medium: 'text-[var(--color-warning)]',
  high: 'text-[var(--color-danger)]',
  urgent: 'text-[var(--color-danger)]',
}

export function KanbanCard({ task, projectColor, projectName, className }: KanbanCardProps) {
  const { formatDate } = useLocale()
  const isOverdue = task.due_date && new Date(task.due_date) < new Date() && task.status !== 'done'

  return (
    <div
      role="listitem"
      aria-label={task.title}
      draggable
      onDragStart={(e) => e.dataTransfer.setData('text/plain', task.id)}
      onKeyDown={(e) => {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault()
          e.currentTarget.click()
        }
      }}
      tabIndex={0}
      className={cn(
        'card p-3 cursor-grab active:cursor-grabbing hover:shadow-md transition-shadow border-l-4 focus:outline-none focus:ring-2 focus:ring-[var(--color-primary)]',
        className
      )}
      style={{ borderLeftColor: projectColor }}
    >
      <div className="flex items-start justify-between gap-2 mb-2">
        <span className="text-sm font-medium text-[var(--color-text)] line-clamp-2">{task.title}</span>
        <Flag className={cn('w-3.5 h-3.5 flex-shrink-0', priorityColors[task.priority] || priorityColors.low)} />
      </div>

      {projectName && (
        <div className="flex items-center gap-1 mb-2">
          <div className="w-2 h-2 rounded-full" style={{ backgroundColor: projectColor }} />
          <span className="text-xs text-[var(--color-text-secondary)] truncate">{projectName}</span>
        </div>
      )}

      {task.progress > 0 && (
        <ProgressBar value={task.progress} showLabel size="sm" className="mb-2" />
      )}

      <div className="flex items-center justify-between">
        <div className="flex items-center gap-1.5">
          {task.due_date && (
            <div className={cn(
              'flex items-center gap-1 text-xs',
              isOverdue ? 'text-[var(--color-danger)]' : 'text-[var(--color-text-tertiary)]'
            )}>
              <Calendar className="w-3 h-3" />
              {formatDate(task.due_date)}
            </div>
          )}
        </div>
        {task.assignee && <Avatar name={task.assignee} size="xs" />}
      </div>
    </div>
  )
}
