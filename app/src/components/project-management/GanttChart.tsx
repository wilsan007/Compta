import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { ChevronDown, ChevronRight } from 'lucide-react'
import { cn } from '@/lib/utils'
import { useTaskContext } from '@/contexts/TaskContext'
import { useProjectContext } from '@/contexts/ProjectContext'
import { useTaskEditPermissions } from '@/hooks/useTaskEditPermissions'
import { useToast } from '@/lib/toast'
import { confirmDialog } from '@/lib/confirm'
import { updateProject } from '@/lib/queries/accounting'
import {
  createProjectDependency,
  createTaskDependency,
  deleteProjectDependency,
  deleteTaskDependency,
  getDependenciesForTasks,
  getProjectDependencies,
} from '@/lib/queries/projectManagement'
import { getTimelineHeaders, VIEW_MODE_CONFIG } from '@/lib/ganttHelpers'
import { diffDays, formatDay, maxDay, minDay, parseDay } from '@/lib/dayMath'
import {
  applyDrag,
  buildGanttRows,
  dependencyPath,
  projectBounds,
  taskBounds,
  type BarBox,
  type Bounds,
  type DragType,
  type GanttProject,
  type GanttRow,
} from '@/lib/ganttModel'
import { orderAsTree } from '@/lib/taskTree'
import type {
  DependencyType,
  DisplayMode,
  ProjectDependency,
  ProjectTaskDependency,
  ViewMode,
} from '@/types/projectManagement'
import { GanttHeader } from './GanttHeader'
import { LoadingState, ErrorState } from './LoadingState'

interface GanttChartProps {
  projectId?: string
  className?: string
}

const ROW_H = 36
const HEADER_H = 36
const LIST_W = 280
const MIN_BAR = 24 // cible tactile (WCAG 2.5.8), la même pour la barre et ses flèches

interface DragState {
  row: GanttRow
  type: DragType
  startX: number
  origStart: string
  origEnd: string
  bounds: Bounds
  preview: { start: string; end: string }
}

interface LinkState {
  from: GanttRow
  x: number
  y: number
}

export function GanttChart({ className }: GanttChartProps) {
  const { t } = useTranslation('taskManagement')
  const { toast } = useToast()
  const { tasks, loading, error, refetch, updateTask, refreshSilently } = useTaskContext()
  const { projects, projectColorMap, refreshSilently: refreshProjects } = useProjectContext()
  const { can } = useTaskEditPermissions()
  const canEdit = can('edit')
  const [viewMode, setViewMode] = useState<ViewMode>('week')
  const [yearBuffer, setYearBuffer] = useState(0)
  const [mode, setMode] = useState<DisplayMode>('tasks')
  const [collapsed, setCollapsed] = useState<Set<string>>(new Set())
  const [taskDeps, setTaskDeps] = useState<ProjectTaskDependency[]>([])
  const [projectDeps, setProjectDeps] = useState<ProjectDependency[]>([])
  const [drag, setDrag] = useState<DragState | null>(null)
  const [link, setLink] = useState<LinkState | null>(null)
  const [hoverRow, setHoverRow] = useState<string | null>(null)
  const [hoverDep, setHoverDep] = useState<string | null>(null)
  const contentRef = useRef<HTMLDivElement>(null)

  // ------------------------------------------------------------ données
  const ganttProjects: GanttProject[] = useMemo(
    () =>
      [...projects]
        .sort((a, b) => String(a.created_at || '').localeCompare(String(b.created_at || '')) || a.id.localeCompare(b.id))
        .map((p) => ({ id: p.id, name: p.name, progress: p.progress || 0, start_date: p.start_date, end_date: p.end_date })),
    [projects]
  )
  const ordered = useMemo(() => orderAsTree(tasks), [tasks])
  const rows = useMemo(
    () => buildGanttRows(mode, ordered, ganttProjects, projectColorMap, collapsed, t('gantt.noProject')),
    [mode, ordered, ganttProjects, projectColorMap, collapsed, t]
  )
  const tasksById = useMemo(() => new Map(tasks.map((x) => [x.id, x])), [tasks])
  const projectsById = useMemo(() => new Map(ganttProjects.map((p) => [p.id, p])), [ganttProjects])

  const idsKey = useMemo(() => tasks.map((x) => x.id).sort().join('|'), [tasks])
  const reloadDeps = useCallback(async () => {
    try {
      const [td, pd] = await Promise.all([
        getDependenciesForTasks(idsKey ? idsKey.split('|') : []),
        getProjectDependencies(),
      ])
      setTaskDeps(td)
      setProjectDeps(pd)
    } catch (err) {
      toast('error', t('saveError'), (err as Error).message)
    }
  }, [idsKey, toast, t])
  useEffect(() => {
    void reloadDeps()
  }, [reloadDeps])

  // Une écriture se propage en base (enfants décalés, successeurs reportés,
  // progression remontée) : on relit tout, sans écran de chargement.
  const refreshAll = useCallback(() => {
    void refreshSilently()
    void refreshProjects()
  }, [refreshSilently, refreshProjects])

  // ------------------------------------------------------------ échelle
  const config = VIEW_MODE_CONFIG[viewMode]
  const dayPx = config.pixelPerUnit / config.daysPerUnit
  const today = formatDay(new Date())
  const { timelineStart, timelineEnd } = useMemo(() => {
    const lo = minDay(today, ...rows.map((r) => r.start)) || today
    const hi = maxDay(today, ...rows.map((r) => r.end)) || today
    const a = parseDay(lo)!
    const b = parseDay(hi)!
    return {
      timelineStart: new Date(a.getFullYear() - yearBuffer, a.getMonth() - 1, 1),
      timelineEnd: new Date(b.getFullYear() + yearBuffer, b.getMonth() + 2, 0),
    }
  }, [rows, today, yearBuffer])
  const timelineWidth = (diffDays(timelineStart, timelineEnd) + 1) * dayPx
  const headers = useMemo(() => getTimelineHeaders(timelineStart, timelineEnd, viewMode), [timelineStart, timelineEnd, viewMode])
  const xOf = useCallback((day: string) => diffDays(timelineStart, parseDay(day)!) * dayPx, [timelineStart, dayPx])

  const datesOf = useCallback(
    (row: GanttRow): { start: string; end: string } | null => {
      if (drag && drag.row.kind === row.kind && drag.row.id === row.id) return drag.preview
      return row.start && row.end ? { start: row.start, end: row.end } : null
    },
    [drag]
  )
  const boxOf = useCallback(
    (row: GanttRow, index: number): BarBox | null => {
      const d = datesOf(row)
      if (!d) return null
      const x1 = xOf(d.start)
      const w = Math.max((diffDays(parseDay(d.start)!, parseDay(d.end)!) + 1) * dayPx, MIN_BAR)
      return { x1, x2: x1 + w, y: index * ROW_H + ROW_H / 2 }
    },
    [datesOf, xOf, dayPx]
  )
  const rowIndex = useMemo(() => new Map(rows.map((r, i) => [`${r.kind}:${r.id}`, i])), [rows])

  // ------------------------------------------------------------ bornes d'une barre
  const boundsOf = useCallback(
    (row: GanttRow): Bounds => {
      if (row.kind === 'task') {
        return taskBounds(
          row.task,
          tasksById,
          projectsById,
          tasks.filter((x) => x.parent_id === row.id),
          taskDeps.filter((d) => d.task_id === row.id)
        )
      }
      return projectBounds(
        projectsById,
        tasks.filter((x) => x.project_id === row.id),
        projectDeps.filter((d) => d.project_id === row.id)
      )
    },
    [tasks, tasksById, projectsById, taskDeps, projectDeps]
  )

  // ------------------------------------------------------------ écriture
  const commitDates = useCallback(
    async (row: GanttRow, start: string, end: string) => {
      try {
        if (row.kind === 'task') await updateTask(row.id, { start_date: start, due_date: end })
        else await updateProject(row.id, { start_date: start, end_date: end })
      } catch (err) {
        // la base a refusé (une borne qu'on ne voit pas d'ici : échéance d'action,
        // successeur qui sortirait de sa mère…) : on le dit, on revient à son état
        toast('error', t('saveError'), (err as Error).message)
      } finally {
        refreshAll()
      }
    },
    [updateTask, refreshAll, toast, t]
  )

  const startDrag = useCallback(
    (row: GanttRow, type: DragType, e: React.MouseEvent) => {
      if (!canEdit || e.button !== 0) return
      if (row.kind === 'project' && !row.draggable) return
      if (!row.start || !row.end) return
      e.preventDefault()
      e.stopPropagation()
      setDrag({
        row,
        type,
        startX: e.clientX,
        origStart: row.start,
        origEnd: row.end,
        bounds: boundsOf(row),
        preview: { start: row.start, end: row.end },
      })
    },
    [canEdit, boundsOf]
  )

  useEffect(() => {
    if (!drag) return
    const onMove = (e: MouseEvent) => {
      const delta = Math.round((e.clientX - drag.startX) / dayPx)
      const preview = applyDrag(drag.type, drag.origStart, drag.origEnd, delta, drag.bounds)
      setDrag((cur) =>
        cur && (cur.preview.start !== preview.start || cur.preview.end !== preview.end) ? { ...cur, preview } : cur
      )
    }
    const onUp = () => {
      const { row, preview, origStart, origEnd } = drag
      setDrag(null)
      if (preview.start !== origStart || preview.end !== origEnd) void commitDates(row, preview.start, preview.end)
    }
    document.addEventListener('mousemove', onMove)
    document.addEventListener('mouseup', onUp)
    return () => {
      document.removeEventListener('mousemove', onMove)
      document.removeEventListener('mouseup', onUp)
    }
  }, [drag, dayPx, commitDates])

  // Clavier : ← → déplace d'un jour, Maj+← → change la fin — dans les bornes.
  const onBarKey = useCallback(
    (row: GanttRow, e: React.KeyboardEvent) => {
      if (!canEdit || !row.start || !row.end) return
      if (row.kind === 'project' && !row.draggable) return
      if (e.key !== 'ArrowLeft' && e.key !== 'ArrowRight') return
      e.preventDefault()
      const delta = e.key === 'ArrowRight' ? 1 : -1
      const next = applyDrag(e.shiftKey ? 'resize-end' : 'move', row.start, row.end, delta, boundsOf(row))
      if (next.start !== row.start || next.end !== row.end) void commitDates(row, next.start, next.end)
    },
    [canEdit, boundsOf, commitDates]
  )

  // ------------------------------------------------------------ liens « après »
  const pointer = (e: MouseEvent | React.MouseEvent) => {
    const r = contentRef.current!.getBoundingClientRect()
    return { x: e.clientX - r.left, y: e.clientY - r.top }
  }
  const startLink = useCallback(
    (row: GanttRow, e: React.MouseEvent) => {
      if (!canEdit) return
      e.preventDefault()
      e.stopPropagation()
      setLink({ from: row, ...pointer(e) })
    },
    [canEdit]
  )

  useEffect(() => {
    if (!link) return
    const onMove = (e: MouseEvent) => setLink((cur) => (cur ? { ...cur, ...pointer(e) } : cur))
    const onUp = async (e: MouseEvent) => {
      const from = link.from
      setLink(null)
      const el = (document.elementFromPoint(e.clientX, e.clientY) as HTMLElement | null)?.closest('[data-gantt-row]') as HTMLElement | null
      if (!el) return
      const kind = el.dataset.ganttKind
      const id = el.dataset.ganttRow
      if (!id || id === from.id) return
      if (kind !== from.kind) {
        toast('warning', t('gantt.linkKindMismatch'))
        return
      }
      try {
        // « id commence après from »
        if (from.kind === 'task') await createTaskDependency(id, from.id, 'finish-to-start', 0)
        else await createProjectDependency(id, from.id, 0)
        toast('success', t('gantt.linkCreated'))
      } catch (err) {
        toast('error', t('saveError'), (err as Error).message)
      } finally {
        await reloadDeps()
        refreshAll()
      }
    }
    document.addEventListener('mousemove', onMove)
    document.addEventListener('mouseup', onUp)
    return () => {
      document.removeEventListener('mousemove', onMove)
      document.removeEventListener('mouseup', onUp)
    }
  }, [link, reloadDeps, refreshAll, toast, t])

  const removeLink = useCallback(
    async (kind: 'task' | 'project', id: string, fromName: string, toName: string) => {
      if (!canEdit) return
      if (!(await confirmDialog(t('gantt.deleteLinkConfirm', { from: fromName, to: toName })))) return
      try {
        if (kind === 'task') await deleteTaskDependency(id)
        else await deleteProjectDependency(id)
      } catch (err) {
        toast('error', t('saveError'), (err as Error).message)
      } finally {
        await reloadDeps()
      }
    },
    [canEdit, reloadDeps, toast, t]
  )

  // ------------------------------------------------------------ flèches visibles
  const arrows = useMemo(() => {
    const out: { key: string; kind: 'task' | 'project'; id: string; d: string; fromName: string; toName: string }[] = []
    const nameOf = (r: GanttRow) => (r.kind === 'task' ? r.task.title : r.name)
    const add = (kind: 'task' | 'project', id: string, predId: string, succId: string, type: DependencyType) => {
      const pi = rowIndex.get(`${kind}:${predId}`)
      const si = rowIndex.get(`${kind}:${succId}`)
      if (pi === undefined || si === undefined) return
      const a = boxOf(rows[pi], pi)
      const b = boxOf(rows[si], si)
      if (!a || !b) return
      out.push({ key: `${kind}:${id}`, kind, id, d: dependencyPath(type, a, b, ROW_H), fromName: nameOf(rows[pi]), toName: nameOf(rows[si]) })
    }
    for (const d of taskDeps) add('task', d.id, d.depends_on_task_id, d.task_id, d.dependency_type)
    for (const d of projectDeps) add('project', d.id, d.depends_on_project_id, d.project_id, 'finish-to-start')
    return out
  }, [taskDeps, projectDeps, rowIndex, rows, boxOf])

  if (loading) return <LoadingState />
  if (error) return <ErrorState message={error} onRetry={refetch} />

  const toggle = (key: string) =>
    setCollapsed((prev) => {
      const next = new Set(prev)
      if (next.has(key)) next.delete(key)
      else next.add(key)
      return next
    })

  const dragZone = drag ? { lo: drag.bounds.minStart, hi: drag.bounds.maxEnd, index: rowIndex.get(`${drag.row.kind}:${drag.row.id}`) } : null
  const linkFrom = link ? boxOf(link.from, rowIndex.get(`${link.from.kind}:${link.from.id}`) ?? 0) : null

  return (
    <div className={cn('flex h-full flex-col', className)} role="region" aria-label={t('views.gantt')}>
      <GanttHeader
        viewMode={viewMode}
        onViewModeChange={setViewMode}
        yearBuffer={yearBuffer}
        onYearBufferChange={setYearBuffer}
        mode={mode}
        onToggleMode={() => setMode((m) => (m === 'tasks' ? 'projects' : 'tasks'))}
      />
      {canEdit && (
        <p className="border-b border-[var(--color-border)] px-4 py-1 text-xs text-[var(--color-text-tertiary)]">
          {t('gantt.hint')}
        </p>
      )}
      {/* Un seul défilement : la liste (collée à gauche) et la frise partagent les
          mêmes lignes, de même hauteur. Plus de synchronisation, plus de décalage. */}
      <div className="relative flex-1 overflow-auto" dir="ltr">
        <div className="relative" style={{ width: LIST_W + timelineWidth }}>
          {/* en-tête */}
          <div className="sticky top-0 z-30 flex border-b border-[var(--color-border)] bg-[var(--color-surface)]" style={{ height: HEADER_H }}>
            <div
              className="sticky left-0 z-40 flex items-center border-e border-[var(--color-border)] bg-[var(--color-surface)] px-3 text-xs font-semibold"
              style={{ width: LIST_W, minWidth: LIST_W }}
            >
              {mode === 'projects' ? t('gantt.projects') : t('gantt.tasks')}
            </div>
            <div className="relative" style={{ width: timelineWidth }}>
              {headers.map((h, i) => (
                <div
                  key={i}
                  className="absolute top-0 flex h-full items-center justify-center whitespace-nowrap border-e border-[var(--color-border)] px-1 text-xs font-medium text-[var(--color-text-secondary)]"
                  style={{ left: h.position, width: h.width }}
                >
                  {h.label}
                </div>
              ))}
            </div>
          </div>

          <div className="flex">
            {/* liste */}
            <div
              className="sticky left-0 z-20 border-e border-[var(--color-border)] bg-[var(--color-surface)]"
              style={{ width: LIST_W, minWidth: LIST_W }}
            >
              {rows.length === 0 && (
                <p className="px-3 py-8 text-center text-sm text-[var(--color-text-tertiary)]">{t('gantt.noTasks')}</p>
              )}
              {rows.map((row) => (
                <ListRow
                  key={`${row.kind}:${row.id}`}
                  row={row}
                  mode={mode}
                  hovered={hoverRow === `${row.kind}:${row.id}`}
                  folded={row.kind === 'project' ? collapsed.has(`project:${row.id}`) : collapsed.has(row.id)}
                  onToggle={() => toggle(row.kind === 'project' ? `project:${row.id}` : row.id)}
                  onHover={setHoverRow}
                />
              ))}
            </div>

            {/* frise */}
            <div ref={contentRef} className="relative" style={{ width: timelineWidth, height: Math.max(rows.length, 1) * ROW_H }}>
              {headers.map((h, i) => (
                <div key={i} className="absolute top-0 bottom-0 border-e border-[var(--color-border)] opacity-50" style={{ left: h.position + h.width - 1 }} />
              ))}
              {rows.map((row, i) => (
                <div
                  key={`bg:${row.kind}:${row.id}`}
                  className={cn(
                    'absolute left-0 right-0 border-b border-[var(--color-border)]',
                    hoverRow === `${row.kind}:${row.id}` && 'bg-[var(--color-neutral-50)]'
                  )}
                  style={{
                    top: i * ROW_H,
                    height: ROW_H,
                    backgroundColor: row.kind === 'project' ? `color-mix(in srgb, ${row.color} 7%, transparent)` : undefined,
                  }}
                  onMouseEnter={() => setHoverRow(`${row.kind}:${row.id}`)}
                  onMouseLeave={() => setHoverRow(null)}
                />
              ))}
              {/* zone autorisée pendant un glissement */}
              {dragZone && dragZone.index !== undefined && (
                <div
                  className="pointer-events-none absolute rounded bg-[color-mix(in_srgb,var(--color-primary)_10%,transparent)] ring-1 ring-[var(--color-primary)]"
                  style={{
                    top: dragZone.index * ROW_H + 2,
                    height: ROW_H - 4,
                    left: dragZone.lo ? xOf(dragZone.lo) : 0,
                    width: (dragZone.hi ? xOf(dragZone.hi) + dayPx : timelineWidth) - (dragZone.lo ? xOf(dragZone.lo) : 0),
                  }}
                  aria-hidden="true"
                />
              )}
              {/* aujourd'hui */}
              <div className="pointer-events-none absolute top-0 bottom-0 w-px bg-[var(--color-danger)]" style={{ left: xOf(today) + dayPx / 2 }} title={t('gantt.today')} />

              {rows.map((row, i) => {
                const box = boxOf(row, i)
                if (!box) return null
                const d = datesOf(row)!
                return (
                  <Bar
                    key={`bar:${row.kind}:${row.id}`}
                    row={row}
                    box={box}
                    dates={d}
                    canEdit={canEdit && !(row.kind === 'project' && !row.draggable)}
                    canLink={canEdit && (row.kind === 'task' || row.id !== 'no-project')}
                    dragging={!!drag && drag.row.id === row.id && drag.row.kind === row.kind}
                    onDragStart={startDrag}
                    onLinkStart={startLink}
                    onKey={onBarKey}
                  />
                )
              })}

              {/* flèches : au-dessus des barres, cliquables pour être retirées */}
              <svg className="pointer-events-none absolute inset-0 overflow-visible" width={timelineWidth} height={rows.length * ROW_H} aria-hidden="false">
                <defs>
                  <marker id="gantt-arrow" markerWidth="8" markerHeight="8" refX="7" refY="4" orient="auto" markerUnits="userSpaceOnUse">
                    <path d="M0,0 L8,4 L0,8 z" fill="var(--color-text-secondary)" />
                  </marker>
                  <marker id="gantt-arrow-hot" markerWidth="8" markerHeight="8" refX="7" refY="4" orient="auto" markerUnits="userSpaceOnUse">
                    <path d="M0,0 L8,4 L0,8 z" fill="var(--color-primary)" />
                  </marker>
                </defs>
                {arrows.map((a) => (
                  <g key={a.key}>
                    <path
                      d={a.d}
                      fill="none"
                      stroke={hoverDep === a.key ? 'var(--color-primary)' : 'var(--color-text-secondary)'}
                      strokeWidth={hoverDep === a.key ? 2 : 1.25}
                      markerEnd={`url(#${hoverDep === a.key ? 'gantt-arrow-hot' : 'gantt-arrow'})`}
                    />
                    {/* zone de clic large, invisible */}
                    <path
                      d={a.d}
                      fill="none"
                      stroke="transparent"
                      strokeWidth={10}
                      style={{ pointerEvents: canEdit ? 'stroke' : 'none', cursor: 'pointer' }}
                      onMouseEnter={() => setHoverDep(a.key)}
                      onMouseLeave={() => setHoverDep(null)}
                      onClick={() => removeLink(a.kind, a.id, a.fromName, a.toName)}
                    >
                      <title>{t('gantt.linkTitle', { from: a.fromName, to: a.toName })}</title>
                    </path>
                  </g>
                ))}
                {link && linkFrom && (
                  <line
                    x1={linkFrom.x2}
                    y1={linkFrom.y}
                    x2={link.x}
                    y2={link.y}
                    stroke="var(--color-primary)"
                    strokeWidth={1.5}
                    strokeDasharray="4 3"
                    markerEnd="url(#gantt-arrow-hot)"
                  />
                )}
              </svg>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}

// ------------------------------------------------------------------ liste
function ListRow({
  row,
  mode,
  hovered,
  folded,
  onToggle,
  onHover,
}: {
  row: GanttRow
  mode: DisplayMode
  hovered: boolean
  folded: boolean
  onToggle: () => void
  onHover: (key: string | null) => void
}) {
  const key = `${row.kind}:${row.id}`
  const foldable = (row.kind === 'project' && mode === 'tasks') || (row.kind === 'task' && row.hasChildren)
  return (
    <div
      className={cn('flex items-center gap-1.5 border-b border-[var(--color-border)] px-2', hovered && 'bg-[var(--color-neutral-50)]')}
      style={{
        height: ROW_H,
        paddingInlineStart: row.kind === 'task' ? 8 + row.depth * 14 : 8,
        boxShadow: `inset 3px 0 0 0 ${row.color}`,
        backgroundColor: row.kind === 'project' && !hovered ? `color-mix(in srgb, ${row.color} 10%, var(--color-surface))` : undefined,
      }}
      onMouseEnter={() => onHover(key)}
      onMouseLeave={() => onHover(null)}
    >
      {foldable ? (
        <button type="button" onClick={onToggle} aria-expanded={!folded} className="flex-shrink-0 rounded hover:bg-[var(--color-neutral-100)]">
          {folded ? <ChevronRight className="h-3.5 w-3.5" /> : <ChevronDown className="h-3.5 w-3.5" />}
        </button>
      ) : (
        <span className="w-3.5 flex-shrink-0" />
      )}
      <span
        className={cn('flex-1 truncate', row.kind === 'project' ? 'text-sm font-semibold' : 'text-xs')}
        style={row.kind === 'project' ? { color: row.color } : undefined}
        title={row.kind === 'task' ? row.task.title : row.name}
      >
        {row.kind === 'task' ? row.task.title : row.name}
      </span>
      {row.kind === 'project' && mode === 'tasks' && <span className="text-xs text-[var(--color-text-tertiary)]">({row.count})</span>}
      <span className="w-9 flex-shrink-0 text-right text-[11px] tabular-nums text-[var(--color-text-tertiary)]">{row.progress}%</span>
    </div>
  )
}

// ------------------------------------------------------------------ barres
function Bar({
  row,
  box,
  dates,
  canEdit,
  canLink,
  dragging,
  onDragStart,
  onLinkStart,
  onKey,
}: {
  row: GanttRow
  box: BarBox
  dates: { start: string; end: string }
  canEdit: boolean
  canLink: boolean
  dragging: boolean
  onDragStart: (row: GanttRow, type: DragType, e: React.MouseEvent) => void
  onLinkStart: (row: GanttRow, e: React.MouseEvent) => void
  onKey: (row: GanttRow, e: React.KeyboardEvent) => void
}) {
  const { t } = useTranslation('taskManagement')
  const name = row.kind === 'task' ? row.task.title : row.name
  const width = box.x2 - box.x1
  const top = box.y - ROW_H / 2
  const isProject = row.kind === 'project'
  const isSub = row.kind === 'task' && row.depth > 0
  const fill = isSub ? `color-mix(in srgb, ${row.color} 72%, white)` : row.color
  const label = `${name} — ${dates.start} → ${dates.end} — ${row.progress}%`

  return (
    <div
      data-gantt-row={row.id}
      data-gantt-kind={row.kind}
      className="group absolute"
      style={{ left: box.x1, top, width, height: ROW_H }}
    >
      <div
        role="slider"
        tabIndex={0}
        aria-label={label}
        aria-valuemin={0}
        aria-valuemax={100}
        aria-valuenow={row.progress}
        aria-valuetext={label}
        aria-disabled={!canEdit}
        title={label}
        onMouseDown={(e) => onDragStart(row, 'move', e)}
        onKeyDown={(e) => onKey(row, e)}
        className={cn(
          'absolute inset-x-0 overflow-hidden focus:outline-none focus:ring-2 focus:ring-[var(--color-primary)]',
          isProject ? 'top-[12px] h-[10px] rounded-sm' : 'top-[7px] h-[22px] rounded',
          canEdit ? 'cursor-grab active:cursor-grabbing' : 'cursor-default',
          dragging && 'opacity-80 shadow-lg'
        )}
        style={{ backgroundColor: fill }}
      >
        {/* avancement */}
        <div className="pointer-events-none absolute inset-y-0 left-0 bg-black/20" style={{ width: `${row.progress}%` }} />
        {!isProject && (
          <span className="pointer-events-none relative z-10 block truncate px-2 text-[11px] font-medium leading-[22px] text-white">
            {name}
          </span>
        )}
      </div>
      {/* crochets du récapitulatif de projet, comme dans les outils de planification */}
      {isProject && (
        <>
          <span className="pointer-events-none absolute left-0 top-[22px] h-0 w-0 border-x-[5px] border-t-[6px] border-x-transparent" style={{ borderTopColor: fill }} />
          <span className="pointer-events-none absolute right-0 top-[22px] h-0 w-0 border-x-[5px] border-t-[6px] border-x-transparent" style={{ borderTopColor: fill }} />
          <span className="pointer-events-none absolute left-full top-[8px] ms-2 whitespace-nowrap text-[11px] font-semibold" style={{ color: row.color }}>
            {name} · {row.progress}%
          </span>
        </>
      )}
      {canEdit && (
        <>
          <div
            className="absolute top-[7px] left-0 h-[22px] w-1.5 cursor-ew-resize rounded-l bg-black/25 opacity-0 group-hover:opacity-100"
            onMouseDown={(e) => onDragStart(row, 'resize-start', e)}
            aria-hidden="true"
          />
          <div
            className="absolute top-[7px] right-0 h-[22px] w-1.5 cursor-ew-resize rounded-r bg-black/25 opacity-0 group-hover:opacity-100"
            onMouseDown={(e) => onDragStart(row, 'resize-end', e)}
            aria-hidden="true"
          />
        </>
      )}
      {canLink && (
        <button
          type="button"
          onMouseDown={(e) => onLinkStart(row, e)}
          aria-label={t('gantt.linkHandle', { name })}
          title={t('gantt.linkHandle', { name })}
          className="absolute top-1/2 -right-3 h-3 w-3 -translate-y-1/2 rounded-full border-2 border-[var(--color-surface)] opacity-0 shadow group-hover:opacity-100 focus:opacity-100"
          style={{ backgroundColor: row.color }}
        />
      )}
    </div>
  )
}

