import { useCallback, useEffect, useMemo, useRef, useState, type UIEvent } from 'react'
import { useTranslation } from 'react-i18next'
import { cn } from '@/lib/utils'
import { useTaskContext } from '@/contexts/TaskContext'
import { useProjectContext } from '@/contexts/ProjectContext'
import { useTaskEditPermissions } from '@/hooks/useTaskEditPermissions'
import { useTaskFilters } from '@/hooks/useTaskFilters'
import { useIsMobile } from '@/hooks/useMediaQuery'
import { useTaskActionMatrix } from '@/hooks/useTaskActionMatrix'
import { useToast } from '@/lib/toast'
import { confirmDialog } from '@/lib/confirm'
import { getEmployeesShared } from '@/lib/employeesShared'
import { orderAsTree } from '@/lib/taskTree'
import { addDaysToDay, formatDay } from '@/lib/dayMath'
import { exportTasksToCsv, exportTasksToExcel, exportTasksToPdf } from '@/lib/taskExport'
import {
  addActionColumn,
  addDetailedAction,
  getTaskTableCounts,
  newTaskInput,
  updateTask as updateTaskQuery,
  type TaskTableCounts,
} from '@/lib/queries/projectManagement'
import type { TaskAction, TaskCreateInput, TaskStatus } from '@/types/projectManagement'
import { TaskTableHeader, type ExportFormat, type TableMode } from './TaskTableHeader'
import { TaskFixedColumns, type RowHandlers } from './TaskFixedColumns'
import { TaskActionColumns } from './TaskActionColumns'
import { ResizablePanel } from './ResizablePanel'
import { LoadingState, ErrorState } from './LoadingState'
import { SubtaskCreationDialog, type SubtaskDraft } from './SubtaskCreationDialog'
import { TaskCreationDialog } from './TaskCreationDialog'
import { ActionCreationDialog } from './ActionCreationDialog'
import { TaskDetailDialog } from './TaskDetailDialog'
import { ProjectsTable, type ProjectCard } from './ProjectsTable'
import { FilterBar, applyTaskFilters } from './table/FilterBar'
import { ActionProofDialog } from './table/ActionProofDialog'
import { buildTableRows, projectCollapseKey, type ProjectSummary } from './table/rows'
import { PANEL_H } from './table/kit'

interface DynamicTableProps {
  projectId?: string
  className?: string
}

const EMPTY_COUNTS: TaskTableCounts = { documents: new Map(), comments: new Map(), proofs: new Map() }

// Le tableau dynamique d'exécution, à l'image de celui de wadashaqayn : deux
// panneaux redimensionnables (colonnes de la tâche à gauche, colonnes d'actions
// à droite) qui défilent ensemble ; ce qu'on y écrit, la base le propage
// (avancement, dates, preuves — 800 à 803) et le tableau le relit.
export function DynamicTable({ projectId, className }: DynamicTableProps) {
  const { t } = useTranslation('taskManagement')
  const { toast } = useToast()
  const { tasks, loading, error, refetch, refreshSilently, updateTask, deleteTask, duplicateTask, createTask, toggleAction } = useTaskContext()
  const { projects, projectColorMap, refreshSilently: refreshProjects } = useProjectContext()
  const { can } = useTaskEditPermissions()
  // `can` est une fonction neuve à chaque rendu : on garde les booléens, qui eux sont stables.
  const canEdit = can('edit')
  const canDelete = can('delete')
  const canCreate = can('create')
  const isMobile = useIsMobile()
  const { filters, setFilters, reset } = useTaskFilters()

  const [mode, setMode] = useState<TableMode>('tasks')
  const [collapsed, setCollapsed] = useState<Set<string>>(new Set())
  const [selectedTaskId, setSelectedTaskId] = useState<string | null>(null)
  const [quickAction, setQuickAction] = useState('')
  const [taskDialog, setTaskDialog] = useState(false)
  const [actionDialog, setActionDialog] = useState(false)
  const [subtaskParentId, setSubtaskParentId] = useState<string | null>(null)
  const [detailId, setDetailId] = useState<string | null>(null)
  const [proofAction, setProofAction] = useState<TaskAction | null>(null)
  const [exporting, setExporting] = useState(false)
  const [counts, setCounts] = useState<TaskTableCounts>(EMPTY_COUNTS)
  const [employees, setEmployees] = useState<{ id: string; name: string }[]>([])
  const [mobileStatus, setMobileStatus] = useState<TaskStatus>('todo')

  useEffect(() => {
    getEmployeesShared()
      .then((l) => setEmployees(l.map((e) => ({ id: e.id, name: e.name }))))
      .catch(() => setEmployees([]))
  }, [])

  // ------------------------------------------------------------ données
  const projectNames = useMemo(() => new Map(projects.map((p) => [p.id, p.name])), [projects])
  const projectsByCreation = useMemo(
    () => [...projects].sort((a, b) => String(a.created_at || '').localeCompare(String(b.created_at || '')) || a.id.localeCompare(b.id)),
    [projects]
  )
  const summaries: ProjectSummary[] = useMemo(
    () => projectsByCreation.map((p) => ({ id: p.id, name: p.name, progress: p.progress || 0, start_date: p.start_date, end_date: p.end_date })),
    [projectsByCreation]
  )
  const filtered = useMemo(() => applyTaskFilters(tasks, filters), [tasks, filters])
  const ordered = useMemo(() => orderAsTree(filtered), [filtered])
  const rows = useMemo(() => buildTableRows(ordered, summaries, projectColorMap, collapsed, canCreate), [ordered, summaries, projectColorMap, collapsed, canCreate])
  const { matrix, patchAction, appendAction } = useTaskActionMatrix(ordered, !isMobile)

  const idsKey = useMemo(() => ordered.map((x) => x.id).sort().join('|'), [ordered])
  const reloadCounts = useCallback(() => {
    getTaskTableCounts(idsKey ? idsKey.split('|') : [])
      .then(setCounts)
      .catch((e: Error) => toast('error', t('saveError'), e.message))
  }, [idsKey, toast, t])
  useEffect(() => {
    if (!isMobile) reloadCounts()
  }, [reloadCounts, isMobile])

  // Une écriture se propage en base : on relit tâches et projets, sans écran de chargement.
  const refreshAll = useCallback(() => {
    void refreshSilently()
    void refreshProjects()
  }, [refreshSilently, refreshProjects])

  const latest = useRef({ tasks, deleteTask, duplicateTask })
  useEffect(() => {
    latest.current = { tasks, deleteTask, duplicateTask }
  })

  // ------------------------------------------------------------ lignes (objet stable)
  const handlers: RowHandlers = useMemo(
    () => ({
      onSelect: (id) => setSelectedTaskId((cur) => (cur === id ? null : id)),
      onEdit: (id) => setDetailId(id),
      onUpdate: async (id, patch) => {
        if (!canEdit) return
        try {
          await updateTask(id, patch)
          refreshAll()
        } catch (e) {
          // un refus de la base (borne de dates, lien « après ») est dit, pas avalé
          toast('error', t('saveError'), (e as Error).message)
          throw e
        }
      },
      onDelete: async (id) => {
        if (!canDelete) return
        if (!(await confirmDialog(t('table.deleteConfirm')))) return
        try {
          await latest.current.deleteTask(id)
          refreshAll()
        } catch (e) {
          toast('error', t('saveError'), (e as Error).message)
        }
      },
      onDuplicate: (id) => {
        latest.current.duplicateTask(id).then(refreshAll).catch((e: Error) => toast('error', t('saveError'), e.message))
      },
      onAddSubTask: (id) => setSubtaskParentId(id),
      onCreateFromGhost: async (title) => {
        if (!canCreate) return
        const today = formatDay(new Date())
        try {
          await createTask(newTaskInput({ title, project_id: projectId ?? null, start_date: today, due_date: addDaysToDay(today, 7) }))
          refreshAll()
        } catch (e) {
          toast('error', t('saveError'), (e as Error).message)
          throw e
        }
      },
      onToggleBand: (pid) =>
        setCollapsed((prev) => {
          const next = new Set(prev)
          const k = projectCollapseKey(pid)
          if (next.has(k)) next.delete(k)
          else next.add(k)
          return next
        }),
      onCountsChanged: () => reloadCounts(),
    }),
    [canEdit, canDelete, canCreate, updateTask, createTask, refreshAll, reloadCounts, projectId, toast, t]
  )

  // ------------------------------------------------------------ actions
  const onToggleAction = useCallback(
    async (action: TaskAction) => {
      if (!canEdit) return
      const next = !action.is_done
      if (next && !(counts.proofs.get(action.id) || 0)) {
        toast('error', t('dyn.proofRequired'), t('dyn.proofRequiredHint'))
        return
      }
      patchAction(action.id, { is_done: next, progress: next ? 100 : 0 })
      try {
        await toggleAction(action.id, next)
        refreshAll()
      } catch (e) {
        patchAction(action.id, { is_done: action.is_done, progress: action.progress })
        toast('error', t('saveError'), (e as Error).message)
      }
    },
    [canEdit, counts.proofs, patchAction, toggleAction, refreshAll, toast, t]
  )

  const onQuickAction = useCallback(async () => {
    if (!selectedTaskId || !quickAction.trim()) return
    try {
      appendAction(await addActionColumn(selectedTaskId, quickAction.trim().slice(0, 40)))
      setQuickAction('')
      refreshAll()
    } catch (e) {
      toast('error', t('saveError'), (e as Error).message)
    }
  }, [selectedTaskId, quickAction, appendAction, refreshAll, toast, t])

  const onDetailedAction = useCallback(
    async (title: string, weight: number, dueDate: string | null, notes: string | null) => {
      if (!selectedTaskId) return
      try {
        appendAction(await addDetailedAction(selectedTaskId, title, weight, dueDate, notes))
        refreshAll()
      } catch (e) {
        toast('error', t('saveError'), (e as Error).message)
      }
    },
    [selectedTaskId, appendAction, refreshAll, toast, t]
  )

  const onCreateSubtask = useCallback(
    async (draft: SubtaskDraft) => {
      const parent = latest.current.tasks.find((x) => x.id === subtaskParentId)
      if (!parent) return
      try {
        const created = await createTask(
          newTaskInput({
            title: draft.title,
            parent_id: parent.id,
            project_id: parent.project_id,
            priority: parent.priority,
            start_date: draft.start_date,
            due_date: draft.due_date,
            effort_estimate_h: draft.effort_estimate_h,
            assignee_id: draft.assignee_id,
            assignee: draft.assignee,
            task_level: (parent.task_level || 0) + 1,
          })
        )
        if (draft.linked_action_id) await updateTaskQuery(created.id, { linked_action_id: draft.linked_action_id })
        for (const a of draft.actions) appendAction(await addDetailedAction(created.id, a.title, a.weight, a.due_date, a.notes))
        refreshAll()
      } catch (e) {
        toast('error', t('saveError'), (e as Error).message)
        throw e
      }
    },
    [subtaskParentId, createTask, appendAction, refreshAll, toast, t]
  )

  const onExport = useCallback(
    async (format: ExportFormat) => {
      setExporting(true)
      try {
        const ctx = { projectNames, parentTitles: new Map(tasks.map((x) => [x.id, x.title])), filters }
        const name = format === 'excel' ? await exportTasksToExcel(ordered, ctx) : format === 'pdf' ? await exportTasksToPdf(ordered, ctx) : exportTasksToCsv(ordered, ctx)
        toast('success', t('dyn.exportDone', { count: ordered.length, file: name }))
      } catch (e) {
        toast('error', t('saveError'), (e as Error).message)
      } finally {
        setExporting(false)
      }
    },
    [ordered, tasks, projectNames, filters, toast, t]
  )

  // ------------------------------------------------------------ défilement lié
  const leftRef = useRef<HTMLDivElement>(null)
  const rightRef = useRef<HTMLDivElement>(null)
  const sync = useCallback((from: 'left' | 'right') => (e: UIEvent<HTMLDivElement>) => {
    const target = from === 'left' ? rightRef.current : leftRef.current
    // tolérance d'un pixel : le défilement provoqué ici ne relance pas la synchronisation
    if (target && Math.abs(target.scrollTop - e.currentTarget.scrollTop) > 1) target.scrollTop = e.currentTarget.scrollTop
  }, [])

  if (loading) return <LoadingState />
  if (error) return <ErrorState message={error} onRetry={refetch} />

  const subtaskParent = subtaskParentId ? tasks.find((x) => x.id === subtaskParentId) || null : null
  const detailTask = detailId ? tasks.find((x) => x.id === detailId) || null : null
  const cards: ProjectCard[] = projectsByCreation.map((p) => ({
    id: p.id, name: p.name, status: p.status, progress: p.progress || 0, manager_id: p.manager_id, start_date: p.start_date, end_date: p.end_date,
  }))

  const dialogs = (
    <>
      <TaskCreationDialog
        open={taskDialog}
        onClose={() => setTaskDialog(false)}
        projectId={projectId}
        parentCandidates={tasks}
        onConfirm={(task: TaskCreateInput) => {
          createTask(task).then(refreshAll).catch((e: Error) => toast('error', t('saveError'), e.message))
        }}
      />
      <ActionCreationDialog open={actionDialog} onClose={() => setActionDialog(false)} onConfirm={onDetailedAction} />
      <SubtaskCreationDialog
        parent={subtaskParent}
        parentActions={subtaskParent ? Array.from(matrix.byTask.get(subtaskParent.id)?.values() || []) : []}
        onClose={() => setSubtaskParentId(null)}
        onConfirm={onCreateSubtask}
      />
      <TaskDetailDialog
        task={detailTask}
        subtasks={detailTask ? tasks.filter((x) => x.parent_id === detailTask.id) : []}
        actions={detailTask ? Array.from(matrix.byTask.get(detailTask.id)?.values() || []) : []}
        projects={projectsByCreation.map((p) => ({ id: p.id, name: p.name }))}
        canEdit={canEdit}
        onClose={() => setDetailId(null)}
        onSave={handlers.onUpdate}
      />
      <ActionProofDialog action={proofAction} onClose={() => setProofAction(null)} onUploaded={reloadCounts} />
    </>
  )

  if (isMobile) {
    const MOBILE: TaskStatus[] = ['todo', 'doing', 'blocked', 'done']
    const list = ordered.filter((x) => x.status === mobileStatus)
    return (
      <div className={cn('flex h-full flex-col', className)} role="region" aria-label={t('views.table')}>
        <div className="flex gap-1 overflow-x-auto border-b border-[var(--color-border)] px-2 py-2" role="tablist">
          {MOBILE.map((s) => (
            <button key={s} type="button" role="tab" aria-selected={mobileStatus === s} onClick={() => setMobileStatus(s)}
              className={cn('whitespace-nowrap rounded-lg px-3 py-1.5 text-xs font-medium', mobileStatus === s ? 'bg-[var(--color-primary)] text-white' : 'bg-[var(--color-neutral-100)] text-[var(--color-text-secondary)]')}>
              {t(`status.${s}`)} ({ordered.filter((x) => x.status === s).length})
            </button>
          ))}
        </div>
        <div className="flex-1 space-y-2 overflow-y-auto p-2">
          {list.length === 0 ? <p className="py-8 text-center text-sm text-[var(--color-text-secondary)]">{t('table.noTasks')}</p> : list.map((task) => {
            const color = (task.project_id && projectColorMap.get(task.project_id)) || '#97a0af'
            return (
              <button key={task.id} type="button" onClick={() => setDetailId(task.id)} className="card w-full space-y-2 border-s-4 p-3 text-left" style={{ borderInlineStartColor: color }}>
                <span className="block text-sm font-medium" style={{ color }}>{task.title}</span>
                <span className="flex justify-between text-xs text-[var(--color-text-secondary)]">
                  <span>{(task.project_id && projectNames.get(task.project_id)) || t('gantt.noProject')}</span>
                  <span>{task.progress || 0}%</span>
                </span>
              </button>
            )
          })}
        </div>
        {dialogs}
      </div>
    )
  }

  return (
    <div className={cn('card w-full overflow-hidden', className)} role="region" aria-label={t('views.table')}>
      <TaskTableHeader
        mode={mode}
        onModeChange={setMode}
        onNewTask={() => setTaskDialog(true)}
        onExport={onExport}
        exporting={exporting}
        exportCount={ordered.length}
        selectedTaskTitle={(selectedTaskId && tasks.find((x) => x.id === selectedTaskId)?.title) || null}
        quickAction={quickAction}
        setQuickAction={setQuickAction}
        onQuickAction={onQuickAction}
        onDetailedAction={() => setActionDialog(true)}
        canCreate={canCreate}
      />
      {mode === 'tasks' && (
        <div className="px-4 pb-3 sm:px-5">
          <FilterBar
            filters={filters}
            setFilters={setFilters}
            reset={reset}
            projects={projectsByCreation.map((p) => ({ id: p.id, name: p.name }))}
            employees={employees}
            total={tasks.length}
            filtered={filtered.length}
          />
        </div>
      )}
      <div className="px-4 pb-4 sm:px-5 sm:pb-5">
        {mode === 'tasks' ? (
          <div className="overflow-hidden rounded-lg border border-[var(--color-border)]" style={{ height: PANEL_H }}>
            <ResizablePanel
              initialLeftWidth={60}
              minLeftWidth={40}
              maxLeftWidth={80}
              left={
                <TaskFixedColumns
                  rows={rows}
                  handlers={handlers}
                  selectedTaskId={selectedTaskId}
                  projectNames={projectNames}
                  documents={counts.documents}
                  comments={counts.comments}
                  canEdit={canEdit}
                  canDelete={canDelete}
                  scrollRef={leftRef}
                  onScroll={sync('left')}
                />
              }
              right={
                <TaskActionColumns
                  rows={rows}
                  matrix={matrix}
                  proofs={counts.proofs}
                  selectedTaskId={selectedTaskId}
                  canEdit={canEdit}
                  onToggle={onToggleAction}
                  onProof={setProofAction}
                  scrollRef={rightRef}
                  onScroll={sync('right')}
                />
              }
            />
          </div>
        ) : (
          <ProjectsTable projects={cards} tasks={tasks} projectColorMap={projectColorMap} />
        )}
      </div>
      {dialogs}
    </div>
  )
}
