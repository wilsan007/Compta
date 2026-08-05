import type { GanttTask, ViewMode } from '@/types/projectManagement'
import { getTaskPosition, getTimelineHeaders } from '@/lib/ganttHelpers'
import { GanttTaskBar } from './GanttTaskBar'
import type { DragState } from '@/hooks/useGanttDrag'

interface GanttTimelineProps {
  tasks: GanttTask[]
  timelineStart: Date
  timelineEnd: Date
  viewMode: ViewMode
  projectColorMap: Map<string, string>
  onDragStart: (taskId: string, type: 'move' | 'resize-left' | 'resize-right', e: React.MouseEvent) => void
  dragState: DragState | null
  previewDates: { start: Date; end: Date } | null
  timelineWidth: number
  rowHeight: number
}

export function GanttTimeline({
  tasks,
  timelineStart,
  timelineEnd,
  viewMode,
  projectColorMap,
  onDragStart,
  dragState,
  previewDates,
  timelineWidth,
  rowHeight,
}: GanttTimelineProps) {
  const headers = getTimelineHeaders(timelineStart, timelineEnd, viewMode)

  return (
    <div className="relative" style={{ width: timelineWidth, minWidth: '100%' }}>
      <div className="sticky top-0 z-10 bg-[var(--color-surface)] border-b border-[var(--color-border)]">
        <div className="flex h-8">
          {headers.map((header, i) => (
            <div
              key={i}
              className="text-xs text-[var(--color-text-secondary)] font-medium border-r border-[var(--color-border)] flex items-center justify-center px-1 whitespace-nowrap"
              style={{ position: 'absolute', left: header.position, width: header.width }}
            >
              {header.label}
            </div>
          ))}
        </div>
      </div>

      <div className="relative" style={{ height: tasks.length * rowHeight }}>
        {tasks.map((task, i) => {
          const { left, width } = getTaskPosition(task, timelineStart, viewMode)
          const isDragging = dragState?.taskId === task.id
          const taskStart = isDragging && previewDates ? previewDates.start : new Date(task.start_date || task.due_date || new Date())
          const taskEnd = isDragging && previewDates ? previewDates.end : new Date(task.due_date || task.start_date || new Date())

          return (
            <div
              key={task.id}
              className="absolute border-b border-[var(--color-border)]"
              style={{ top: i * rowHeight, height: rowHeight, width: timelineWidth }}
            >
              <GanttTaskBar
                task={task}
                left={left}
                width={width}
                color={task.project_id ? projectColorMap.get(task.project_id) || '#0066cc' : '#97a0af'}
                onDragStart={onDragStart}
                isDragging={isDragging}
                startDate={taskStart}
                dueDate={taskEnd}
              />
            </div>
          )
        })}
      </div>
    </div>
  )
}
