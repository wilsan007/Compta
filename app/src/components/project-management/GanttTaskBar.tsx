import { cn } from '@/lib/utils'
import { useLocale } from '@/hooks/useLocale'
import type { GanttTask } from '@/types/projectManagement'

interface GanttTaskBarProps {
  task: GanttTask
  left: number
  width: number
  color: string
  onDragStart: (taskId: string, type: 'move' | 'resize-left' | 'resize-right', e: React.MouseEvent) => void
  isDragging: boolean
  startDate: Date
  dueDate: Date
}

export function GanttTaskBar({
  task,
  left,
  width,
  color,
  onDragStart,
  isDragging,
  startDate,
  dueDate,
}: GanttTaskBarProps) {
  const { formatDate } = useLocale()
  const startStr = formatDate(startDate)
  const dueStr = formatDate(dueDate)
  return (
    <div
      role="button"
      aria-label={`${task.title}, ${startStr} to ${dueStr}`}
      aria-grabbed={isDragging}
      tabIndex={0}
      onKeyDown={(e) => {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault()
          onDragStart(task.id, 'move', e as unknown as React.MouseEvent)
        }
      }}
      className={cn(
        'absolute rounded flex items-center px-2 cursor-grab active:cursor-grabbing group transition-opacity focus:outline-none focus:ring-2 focus:ring-white',
        isDragging && 'opacity-60'
      )}
      style={{
        left: `${left}px`,
        width: `${width}px`,
        top: '4px',
        height: '24px',
        backgroundColor: color,
      }}
      onMouseDown={(e) => onDragStart(task.id, 'move', e)}
      title={`${task.title}\n${startStr} → ${dueStr}`}
    >
      <div
        className="absolute left-0 top-0 bottom-0 w-1.5 cursor-ew-resize opacity-0 group-hover:opacity-100 bg-black/20 rounded-l"
        onMouseDown={(e) => onDragStart(task.id, 'resize-left', e)}
      />
      <span className="text-xs text-white font-medium truncate pointer-events-none">
        {task.title}
      </span>
      {task.progress > 0 && (
        <div
          className="absolute left-0 top-0 bottom-0 rounded bg-white/30 pointer-events-none"
          style={{ width: `${task.progress}%` }}
        />
      )}
      <div
        className="absolute right-0 top-0 bottom-0 w-1.5 cursor-ew-resize opacity-0 group-hover:opacity-100 bg-black/20 rounded-r"
        onMouseDown={(e) => onDragStart(task.id, 'resize-right', e)}
      />
    </div>
  )
}
