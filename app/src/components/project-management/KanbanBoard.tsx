import { useState, useCallback, useMemo } from 'react'
import { useTranslation } from 'react-i18next'
import { cn } from '@/lib/utils'
import { useTaskContext } from '@/contexts/TaskContext'
import { useProjectContext } from '@/contexts/ProjectContext'
import { KanbanColumn } from './KanbanColumn'
import { LoadingState, ErrorState } from './LoadingState'
import type { TaskStatus } from '@/types/projectManagement'

interface KanbanBoardProps {
  projectId?: string
  className?: string
}

const COLUMNS: { status: TaskStatus; color: string }[] = [
  { status: 'todo', color: '#97a0af' },
  { status: 'doing', color: '#0066cc' },
  { status: 'blocked', color: '#de350b' },
  { status: 'changes_requested', color: '#ff9f00' },
  { status: 'approved', color: '#36b37e' },
  { status: 'done', color: '#00875a' },
  { status: 'canceled', color: '#6b7280' },
]

export function KanbanBoard({ className }: KanbanBoardProps) {
  const { t } = useTranslation('taskManagement')
  const { tasks, loading, error, refetch, updateTask } = useTaskContext()
  const { projects, projectColorMap } = useProjectContext()
  const [dragOverColumn, setDragOverColumn] = useState<TaskStatus | null>(null)

  const projectNames = useMemo(() => {
    const m = new Map<string, string>()
    projects.forEach((p) => m.set(p.id, p.name))
    return m
  }, [projects])

  const handleDrop = useCallback(
    (taskId: string, newStatus: TaskStatus) => {
      setDragOverColumn(null)
      updateTask(taskId, { status: newStatus })
    },
    [updateTask]
  )

  if (loading) return <LoadingState />
  if (error) return <ErrorState message={error} onRetry={refetch} />

  return (
    <div className={cn('flex gap-4 p-4 overflow-x-auto h-full', className)} role="region" aria-label={t('views.kanban')}>
      {COLUMNS.map((col) => {
        const columnTasks = tasks.filter((task) => task.status === col.status)
        return (
          <KanbanColumn
            key={col.status}
            status={col.status}
            title={t(`status.${col.status}`)}
            color={col.color}
            tasks={columnTasks}
            projectColorMap={projectColorMap}
            projectNames={projectNames}
            onDrop={handleDrop}
            isDragOver={dragOverColumn === col.status}
            onDragOver={() => setDragOverColumn(col.status)}
            onDragLeave={() => setDragOverColumn(null)}
          />
        )
      })}
    </div>
  )
}
