import { useState, useCallback, useMemo } from 'react'
import { useTranslation } from 'react-i18next'
import { cn } from '@/lib/utils'
import { useTaskContext } from '@/contexts/TaskContext'
import { useProjectContext } from '@/contexts/ProjectContext'
import { useTaskEditPermissions } from '@/hooks/useTaskEditPermissions'
import { useIsMobile } from '@/hooks/useMediaQuery'
import { TaskTableHeader } from './TaskTableHeader'
import { TaskFixedColumns } from './TaskFixedColumns'
import { TaskTableBody } from './TaskTableBody'
import { LoadingState, ErrorState } from './LoadingState'
import { SubtaskCreationDialog } from './SubtaskCreationDialog'
import { TaskCreationDialog } from './TaskCreationDialog'
import { ActionCreationDialog } from './ActionCreationDialog'
import { ProjectCreationDialog } from './ProjectCreationDialog'
import type { DisplayMode, TaskStatus, TaskCreateInput } from '@/types/projectManagement'
import { confirmSync } from '@/lib/confirm'

interface DynamicTableProps {
  projectId?: string
  className?: string
}

export function DynamicTable({ projectId, className }: DynamicTableProps) {
  const { t } = useTranslation('taskManagement')
  const { tasks, loading, error, refetch, updateTask, deleteTask, duplicateTask, createSubTask, createTask } = useTaskContext()
  const { projects, projectColorMap, refetch: refetchProjects } = useProjectContext()
  const { can } = useTaskEditPermissions()
  const isMobile = useIsMobile()
  const [mode, setMode] = useState<DisplayMode>('tasks')
  const [collapsedIds, setCollapsedIds] = useState<Set<string>>(new Set())
  const [subtaskDialog, setSubtaskDialog] = useState<{ parentId: string; parentTitle: string } | null>(null)
  const [mobileStatusTab, setMobileStatusTab] = useState<TaskStatus>('todo')
  const [taskDialogOpen, setTaskDialogOpen] = useState(false)
  const [actionDialogOpen, setActionDialogOpen] = useState(false)
  const [projectDialogOpen, setProjectDialogOpen] = useState(false)

  const projectNames = useMemo(() => {
    const m = new Map<string, string>()
    projects.forEach((p) => m.set(p.id, p.name))
    return m
  }, [projects])

  const toggleCollapse = useCallback((id: string) => {
    setCollapsedIds((prev) => {
      const next = new Set(prev)
      if (next.has(id)) next.delete(id)
      else next.add(id)
      return next
    })
  }, [])

  const handleUpdateTask = useCallback(
    (id: string, updates: Record<string, unknown>) => {
      if (!can('edit')) return
      updateTask(id, updates)
    },
    [can, updateTask]
  )

  const handleDeleteTask = useCallback(
    (id: string) => {
      if (!can('delete')) return
      if (!confirmSync(t('table.deleteConfirm'))) return
      deleteTask(id)
    },
    [can, deleteTask, t]
  )

  const handleAddSubTask = useCallback(
    (parentId: string) => {
      const parent = tasks.find((t) => t.id === parentId)
      setSubtaskDialog({ parentId, parentTitle: parent?.title || '' })
    },
    [tasks]
  )

  const handleConfirmSubTask = useCallback(
    (title: string) => {
      if (subtaskDialog) {
        createSubTask(subtaskDialog.parentId, title, projectId)
      }
    },
    [subtaskDialog, createSubTask, projectId]
  )

  const handleCreateTask = useCallback(
    (task: TaskCreateInput) => {
      if (!can('create')) return
      createTask(task)
    },
    [can, createTask]
  )

  const handleExport = useCallback(() => {
    import('xlsx').then((XLSX) => {
      const headers = ['Title', 'Project', 'Assignee', 'Status', 'Priority', 'Start', 'Due', 'Effort', 'Progress']
      const rows = tasks.map((task) => ({
        Title: task.title,
        Project: projectNames.get(task.project_id || '') || '',
        Assignee: task.assignee || '',
        Status: task.status,
        Priority: task.priority,
        Start: task.start_date || '',
        Due: task.due_date || '',
        Effort: task.effort_estimate_h,
        Progress: task.progress,
      }))
      const ws = XLSX.utils.json_to_sheet(rows, { header: headers })
      const wb = XLSX.utils.book_new()
      XLSX.utils.book_append_sheet(wb, ws, 'Tasks')
      XLSX.writeFile(wb, 'tasks-export.xlsx')
    })
  }, [tasks, projectNames])

  if (loading) {
    return <LoadingState />
  }

  if (error) {
    return <ErrorState message={error} onRetry={refetch} />
  }

  const MOBILE_STATUSES: TaskStatus[] = ['todo', 'doing', 'blocked', 'changes_requested', 'approved', 'done', 'canceled']
  const mobileFilteredTasks = tasks.filter((task) => task.status === mobileStatusTab)

  if (isMobile) {
    return (
      <div className={cn('flex flex-col h-full', className)} role="region" aria-label={t('views.table')}>
        <TaskTableHeader
          onNewTask={() => setTaskDialogOpen(true)}
          onQuickAction={() => setTaskDialogOpen(true)}
          onDetailedAction={() => setActionDialogOpen(true)}
          onExport={handleExport}
          mode={mode}
          onToggleMode={() => setMode((m) => (m === 'tasks' ? 'projects' : 'tasks'))}
          taskCount={tasks.length}
          onNewProject={() => setProjectDialogOpen(true)}
        />
        <div className="flex gap-1 px-2 py-2 overflow-x-auto border-b border-[var(--color-border)]" role="tablist" aria-label={t('filters.status')}>
          {MOBILE_STATUSES.map((status) => (
            <button
              key={status}
              role="tab"
              aria-selected={mobileStatusTab === status}
              aria-label={t(`status.${status}`)}
              onClick={() => setMobileStatusTab(status)}
              className={cn(
                'px-3 py-1.5 text-xs font-medium rounded-lg whitespace-nowrap transition-colors',
                mobileStatusTab === status
                  ? 'bg-[var(--color-primary)] text-white'
                  : 'text-[var(--color-text-secondary)] bg-[var(--color-neutral-100)]'
              )}
            >
              {t(`status.${status}`)} ({tasks.filter((t) => t.status === status).length})
            </button>
          ))}
        </div>
        <div className="flex-1 overflow-y-auto p-2 space-y-2" role="tabpanel" aria-label={t(`status.${mobileStatusTab}`)}>
          {mobileFilteredTasks.length === 0 ? (
            <p className="text-center text-sm text-[var(--color-text-secondary)] py-8">{t('table.noTasks')}</p>
          ) : (
            mobileFilteredTasks.map((task) => (
              <div
                key={task.id}
                className="card p-3 space-y-2"
                role="article"
                aria-label={task.title}
              >
                <div className="flex items-center justify-between">
                  <span className="font-medium text-sm">{task.title}</span>
                  <span className={cn(
                    'text-xs px-2 py-0.5 rounded-full',
                    task.priority === 'urgent' && 'bg-red-100 text-red-700',
                    task.priority === 'high' && 'bg-orange-100 text-orange-700',
                    task.priority === 'medium' && 'bg-blue-100 text-blue-700',
                    task.priority === 'low' && 'bg-gray-100 text-gray-700',
                  )} aria-label={t(`priority.${task.priority}`)}>
                    {t(`priority.${task.priority}`)}
                  </span>
                </div>
                <div className="flex items-center justify-between text-xs text-[var(--color-text-secondary)]">
                  <span>{projectNames.get(task.project_id || '') || t('gantt.noProject')}</span>
                  {task.due_date && <span>{task.due_date}</span>}
                </div>
                <div className="w-full h-1.5 bg-[var(--color-neutral-100)] rounded-full overflow-hidden" role="progressbar" aria-valuenow={task.progress} aria-valuemin={0} aria-valuemax={100} aria-label={t('table.progress')}>
                  <div className="h-full bg-[var(--color-primary)]" style={{ width: `${task.progress}%` }} />
                </div>
              </div>
            ))
          )}
        </div>
        {subtaskDialog && (
          <SubtaskCreationDialog
            open={!!subtaskDialog}
            parentTitle={subtaskDialog.parentTitle}
            onClose={() => setSubtaskDialog(null)}
            onConfirm={handleConfirmSubTask}
          />
        )}
        <TaskCreationDialog
          open={taskDialogOpen}
          onClose={() => setTaskDialogOpen(false)}
          onConfirm={handleCreateTask}
          projectId={projectId}
        />
        <ActionCreationDialog
          open={actionDialogOpen}
          onClose={() => setActionDialogOpen(false)}
          onConfirm={(_title, _weight, _dueDate, _notes) => { setActionDialogOpen(false) }}
        />
        <ProjectCreationDialog
          open={projectDialogOpen}
          onClose={() => setProjectDialogOpen(false)}
          onCreated={refetchProjects}
        />
      </div>
    )
  }

  return (
    <div className={cn('card', className)} role="region" aria-label={t('views.table')}>
      <TaskTableHeader
        onNewTask={() => setTaskDialogOpen(true)}
        onQuickAction={() => setTaskDialogOpen(true)}
        onDetailedAction={() => setActionDialogOpen(true)}
        onExport={handleExport}
        mode={mode}
        onToggleMode={() => setMode((m) => (m === 'tasks' ? 'projects' : 'tasks'))}
        taskCount={tasks.length}
        onNewProject={() => setProjectDialogOpen(true)}
      />
      <div className="overflow-x-auto">
        <table className="w-full border-collapse">
          <TaskFixedColumns />
          <TaskTableBody
            tasks={tasks}
            collapsedIds={collapsedIds}
            onToggleCollapse={toggleCollapse}
            onUpdateTask={handleUpdateTask}
            onDeleteTask={handleDeleteTask}
            onDuplicateTask={duplicateTask}
            onAddSubTask={handleAddSubTask}
            projectColorMap={projectColorMap}
            projectNames={projectNames}
            canEdit={can('edit')}
          />
        </table>
      </div>

      {subtaskDialog && (
        <SubtaskCreationDialog
          open={!!subtaskDialog}
          parentTitle={subtaskDialog.parentTitle}
          onClose={() => setSubtaskDialog(null)}
          onConfirm={handleConfirmSubTask}
        />
      )}
      <TaskCreationDialog
        open={taskDialogOpen}
        onClose={() => setTaskDialogOpen(false)}
        onConfirm={handleCreateTask}
        projectId={projectId}
      />
      <ActionCreationDialog
        open={actionDialogOpen}
        onClose={() => setActionDialogOpen(false)}
        onConfirm={(_title, _weight, _dueDate, _notes) => { setActionDialogOpen(false) }}
      />
      <ProjectCreationDialog
        open={projectDialogOpen}
        onClose={() => setProjectDialogOpen(false)}
        onCreated={refetchProjects}
      />
    </div>
  )
}
