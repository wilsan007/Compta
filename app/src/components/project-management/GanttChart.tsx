import { useState, useMemo, useCallback } from 'react'
import { cn } from '@/lib/utils'
import { useTaskContext } from '@/contexts/TaskContext'
import { useProjectContext } from '@/contexts/ProjectContext'
import { useGanttDrag } from '@/hooks/useGanttDrag'
import { GanttHeader } from './GanttHeader'
import { GanttTimeline } from './GanttTimeline'
import { GanttTaskList } from './GanttTaskList'
import { LoadingState, ErrorState } from './LoadingState'
import { getTimelineRange, getTimelineWidth, VIEW_MODE_CONFIG } from '@/lib/ganttHelpers'
import { assignProjectColors } from '@/lib/ganttColors'
import type { ViewMode, DisplayMode, GanttTask } from '@/types/projectManagement'

interface GanttChartProps {
  projectId?: string
  className?: string
}

const ROW_HEIGHT = 32

export function GanttChart({ projectId, className }: GanttChartProps) {
  const { tasks, loading, error, refetch, updateTask } = useTaskContext()
  const { projects } = useProjectContext()
  const [viewMode, setViewMode] = useState<ViewMode>('month')
  const [yearBuffer, setYearBuffer] = useState(1)
  const [mode, setMode] = useState<DisplayMode>('tasks')

  const projectColorMap = useMemo(() => {
    const ids = projects.map((p) => p.id)
    return assignProjectColors(ids)
  }, [projects])

  const projectNames = useMemo(() => {
    const map = new Map<string, string>()
    projects.forEach((p) => map.set(p.id, p.name))
    return map
  }, [projects])

  const ganttTasks: GanttTask[] = useMemo(() => {
    return tasks.map((t) => ({
      id: t.id,
      title: t.title,
      start_date: t.start_date || t.due_date || new Date().toISOString(),
      due_date: t.due_date || t.start_date || new Date().toISOString(),
      progress: t.progress,
      project_id: t.project_id,
      project_name: t.project_id ? projectNames.get(t.project_id) : undefined,
      project_color: t.project_id ? projectColorMap.get(t.project_id) : undefined,
      parent_id: t.parent_id,
      task_level: t.task_level,
      status: t.status,
      priority: t.priority,
      assignee: t.assignee,
      display_order: t.display_order,
    }))
  }, [tasks, projectNames, projectColorMap])

  const { start: timelineStart, end: timelineEnd } = useMemo(
    () => getTimelineRange(ganttTasks, yearBuffer),
    [ganttTasks, yearBuffer]
  )

  const timelineWidth = useMemo(
    () => getTimelineWidth(timelineStart, timelineEnd, viewMode),
    [timelineStart, timelineEnd, viewMode]
  )

  const config = VIEW_MODE_CONFIG[viewMode]
  const dayToPixel = config.pixelPerUnit / config.daysPerUnit

  const handleUpdate = useCallback(
    (taskId: string, startDate: string, dueDate: string) => {
      updateTask(taskId, { start_date: startDate, due_date: dueDate })
    },
    [updateTask]
  )

  const { dragState, previewDates, handleDragStart } = useGanttDrag(
    ganttTasks,
    dayToPixel,
    handleUpdate
  )

  if (loading) return <LoadingState />
  if (error) return <ErrorState message={error} onRetry={refetch} />

  return (
    <div className={cn('flex flex-col h-full', className)} role="region" aria-label="Gantt chart">
      <GanttHeader
        viewMode={viewMode}
        onViewModeChange={setViewMode}
        yearBuffer={yearBuffer}
        onYearBufferChange={setYearBuffer}
        mode={mode}
        onToggleMode={() => setMode((m) => (m === 'tasks' ? 'projects' : 'tasks'))}
      />
      <div className="flex flex-1 overflow-hidden">
        <div className="w-64 flex-shrink-0 border-r border-[var(--color-border)] overflow-hidden">
          <GanttTaskList
            tasks={ganttTasks}
            projectColorMap={projectColorMap}
            projectNames={projectNames}
            rowHeight={ROW_HEIGHT}
          />
        </div>
        <div className="flex-1 overflow-auto">
          <GanttTimeline
            tasks={ganttTasks}
            timelineStart={timelineStart}
            timelineEnd={timelineEnd}
            viewMode={viewMode}
            projectColorMap={projectColorMap}
            onDragStart={handleDragStart}
            dragState={dragState}
            previewDates={previewDates}
            timelineWidth={timelineWidth}
            rowHeight={ROW_HEIGHT}
          />
        </div>
      </div>
    </div>
  )
}
