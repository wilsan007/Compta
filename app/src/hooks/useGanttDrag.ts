import { useState, useCallback, useRef, useEffect } from 'react'
import type { GanttTask } from '@/types/projectManagement'

export interface DragState {
  taskId: string
  type: 'move' | 'resize-left' | 'resize-right'
  startX: number
  originalStart: Date
  originalEnd: Date
}

export function useGanttDrag(
  tasks: GanttTask[],
  dayToPixel: number,
  onUpdate: (taskId: string, startDate: string, dueDate: string) => void
) {
  const [dragState, setDragState] = useState<DragState | null>(null)
  const [previewDates, setPreviewDates] = useState<{ start: Date; end: Date } | null>(null)
  const containerRef = useRef<HTMLDivElement>(null)

  const handleDragStart = useCallback(
    (taskId: string, type: DragState['type'], e: React.MouseEvent) => {
      const task = tasks.find((t) => t.id === taskId)
      if (!task) return
      e.preventDefault()
      e.stopPropagation()
      setDragState({
        taskId,
        type,
        startX: e.clientX,
        originalStart: new Date(task.start_date || task.due_date || new Date()),
        originalEnd: new Date(task.due_date || task.start_date || new Date()),
      })
      setPreviewDates({
        start: new Date(task.start_date || task.due_date || new Date()),
        end: new Date(task.due_date || task.start_date || new Date()),
      })
    },
    [tasks]
  )

  useEffect(() => {
    if (!dragState) return

    function handleMouseMove(e: MouseEvent) {
      if (!dragState) return
      const deltaPx = e.clientX - dragState.startX
      const deltaDays = Math.round(deltaPx / dayToPixel)

      if (dragState.type === 'move') {
        const newStart = new Date(dragState.originalStart)
        newStart.setDate(newStart.getDate() + deltaDays)
        const newEnd = new Date(dragState.originalEnd)
        newEnd.setDate(newEnd.getDate() + deltaDays)
        setPreviewDates({ start: newStart, end: newEnd })
      } else if (dragState.type === 'resize-left') {
        const newStart = new Date(dragState.originalStart)
        newStart.setDate(newStart.getDate() + deltaDays)
        if (newStart < dragState.originalEnd) {
          setPreviewDates({ start: newStart, end: dragState.originalEnd })
        }
      } else if (dragState.type === 'resize-right') {
        const newEnd = new Date(dragState.originalEnd)
        newEnd.setDate(newEnd.getDate() + deltaDays)
        if (newEnd > dragState.originalStart) {
          setPreviewDates({ start: dragState.originalStart, end: newEnd })
        }
      }
    }

    function handleMouseUp() {
      if (dragState && previewDates) {
        const startStr = previewDates.start.toISOString().split('T')[0]
        const endStr = previewDates.end.toISOString().split('T')[0]
        onUpdate(dragState.taskId, startStr, endStr)
      }
      setDragState(null)
      setPreviewDates(null)
    }

    document.addEventListener('mousemove', handleMouseMove)
    document.addEventListener('mouseup', handleMouseUp)
    return () => {
      document.removeEventListener('mousemove', handleMouseMove)
      document.removeEventListener('mouseup', handleMouseUp)
    }
  }, [dragState, previewDates, dayToPixel, onUpdate])

  return {
    dragState,
    previewDates,
    handleDragStart,
    containerRef,
  }
}
