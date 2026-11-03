import { memo, type RefObject, type UIEvent } from 'react'
import { useTranslation } from 'react-i18next'
import { ChevronDown, ChevronRight } from 'lucide-react'
import { cn } from '@/lib/utils'
import { useLocale } from '@/hooks/useLocale'
import { parseDay } from '@/lib/dayMath'
import type { TaskPriority, TaskStatus } from '@/types/projectManagement'
import { AssigneeSelect } from './AssigneeSelect'
import { EditableCellWithDebounce } from './cells/EditableCellWithDebounce'
import { BadgeSelect, CommentsCell, DateCell, DocumentsCell, ProgressCell, ProjectPill, RowMenu, TitleCell } from './table/cells'
import { HEAD_H, HEADER_CELL, HEADER_ROW, PANEL_H, PRIORITY_STYLE, projectInk, STATUS_STYLE } from './table/kit'
import { rowHeight, type TableRow } from './table/rows'

export interface RowHandlers {
  onSelect: (id: string) => void
  onEdit: (id: string) => void
  onUpdate: (id: string, patch: Record<string, unknown>) => Promise<void>
  onDelete: (id: string) => void
  onDuplicate: (id: string) => void
  onAddSubTask: (id: string) => void
  onCreateFromGhost: (title: string) => Promise<void>
  onToggleBand: (projectId: string) => void
  onCountsChanged: () => void
}

interface TaskFixedColumnsProps {
  // objet STABLE (useMemo chez l'appelant) : les lignes sont mémoïsées dessus
  handlers: RowHandlers
  rows: TableRow[]
  selectedTaskId: string | null
  projectNames: Map<string, string>
  documents: Map<string, number>
  comments: Map<string, number>
  canEdit: boolean
  canDelete: boolean
  scrollRef: RefObject<HTMLDivElement | null>
  onScroll: (e: UIEvent<HTMLDivElement>) => void
}

const COLUMNS: { key: string; min: number }[] = [
  { key: 'task', min: 200 },
  { key: 'project', min: 150 },
  { key: 'assignee', min: 150 },
  { key: 'start', min: 80 },
  { key: 'due', min: 80 },
  { key: 'priority', min: 80 },
  { key: 'status', min: 80 },
  { key: 'effort', min: 80 },
  { key: 'progress', min: 100 },
  { key: 'documents', min: 100 },
  { key: 'comments', min: 100 },
  { key: 'actions', min: 50 },
]

// La colonne « Tâche » reste visible quand on fait défiler les autres colonnes
// vers la droite : sans elle, une ligne de dates ou de statuts n'avait plus de nom.
const STICKY_CELL = 'sticky start-0 z-10 shadow-[1px_0_0_0_var(--color-border)]'

// Panneau de GAUCHE : les colonnes fixes de la tâche, comme le tableau de
// wadashaqayn (en-tête dégradé, lignes de 64 px — 51 px pour une sous-tâche).
export function TaskFixedColumns(props: TaskFixedColumnsProps) {
  const { t } = useTranslation('taskManagement')
  const { rows, scrollRef, onScroll, handlers } = props
  return (
    <div ref={scrollRef} className="overflow-auto" style={{ height: PANEL_H }} onScroll={onScroll} data-panel="fixed">
      <table className="w-full border-separate border-spacing-0">
        <thead className="sticky top-0 z-20">
          <tr className={HEADER_ROW} style={{ height: HEAD_H }}>
            {COLUMNS.map((c) => (
              <th
                key={c.key}
                className={cn(HEADER_CELL, 'px-3 text-left whitespace-nowrap', c.key === 'task' && STICKY_CELL, c.key === 'task' && HEADER_ROW)}
                style={{ minWidth: c.min }}
              >
                {t(`dyn.col.${c.key}`)}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((row) =>
            row.kind === 'band' ? (
              <BandRow key={row.key} row={row} onToggle={handlers.onToggleBand} />
            ) : row.kind === 'ghost' ? (
              <GhostRow key={row.key} canCreate={props.canEdit} onCreate={handlers.onCreateFromGhost} />
            ) : (
              <TaskRowMemo
                key={row.key}
                row={row}
                selected={props.selectedTaskId === row.task.id}
                projectName={(row.task.project_id && props.projectNames.get(row.task.project_id)) || null}
                documents={props.documents.get(row.task.id) || 0}
                comments={props.comments.get(row.task.id) || 0}
                canEdit={props.canEdit}
                canDelete={props.canDelete}
                handlers={handlers}
              />
            )
          )}
        </tbody>
      </table>
    </div>
  )
}

// ------------------------------------------------------------------ bandeau de projet
function BandRow({ row, onToggle }: { row: Extract<TableRow, { kind: 'band' }>; onToggle: (id: string) => void }) {
  const { t } = useTranslation('taskManagement')
  const { formatDate } = useLocale()
  const tint = `color-mix(in srgb, ${row.color} 12%, var(--color-surface))`
  const start = parseDay(row.summary?.start_date)
  const end = parseDay(row.summary?.end_date)
  return (
    <tr style={{ height: rowHeight(row) }} data-project-group={row.projectId}>
      <td colSpan={COLUMNS.length} className="border-b border-[var(--color-border)] px-2" style={{ backgroundColor: tint, boxShadow: `inset 4px 0 0 0 ${row.color}` }}>
        <div className="sticky start-2 inline-flex items-center gap-4">
          <button type="button" onClick={() => onToggle(row.projectId)} aria-expanded={!row.folded} className="flex items-center gap-1.5 text-left">
            {row.folded ? <ChevronRight className="h-4 w-4" /> : <ChevronDown className="h-4 w-4" />}
            <span className="text-sm font-bold" style={{ color: projectInk(row.color) }}>{row.name || t('gantt.noProject')}</span>
            <span className="text-xs text-[var(--color-text-tertiary)]">({row.count})</span>
          </button>
          {(start || end) && (
            <span className="text-xs whitespace-nowrap text-[var(--color-text-secondary)]">
              {start ? formatDate(start) : '…'} → {end ? formatDate(end) : '…'}
            </span>
          )}
          {row.summary && <ProgressCell value={row.summary.progress || 0} color={row.color} small={false} />}
        </div>
      </td>
    </tr>
  )
}

// ------------------------------------------------------------------ ligne fantôme
function GhostRow({ canCreate, onCreate }: { canCreate: boolean; onCreate: (title: string) => Promise<void> }) {
  return (
    <tr className="group opacity-70 transition-opacity hover:opacity-100" style={{ height: 64 }}>
      <td className={cn('border-b border-dashed border-[var(--color-border)] bg-[var(--color-surface)] px-2', STICKY_CELL)}>
        <TitleCell value="" number="" depth={0} isSub={false} ghost readOnly={!canCreate} onCommit={onCreate} />
      </td>
      <td colSpan={COLUMNS.length - 1} className="border-b border-dashed border-[var(--color-border)]" />
    </tr>
  )
}

// ------------------------------------------------------------------ ligne de tâche
const TaskRowMemo = memo(function TaskRow({
  row,
  selected,
  projectName,
  documents,
  comments,
  canEdit,
  canDelete,
  handlers,
}: {
  row: Extract<TableRow, { kind: 'task' }>
  selected: boolean
  projectName: string | null
  documents: number
  comments: number
  canEdit: boolean
  canDelete: boolean
  handlers: RowHandlers
}) {
  const { t } = useTranslation('taskManagement')
  const { task, isSub, color } = row
  const h = rowHeight(row)
  const set = (patch: Record<string, unknown>) => handlers.onUpdate(task.id, patch)
  const td = cn('border-b border-[var(--color-border)] px-2', isSub && 'text-xs')
  // fond OPAQUE sur la cellule collante, sinon les colonnes défilent dessous
  const stickyBg = selected
    ? 'bg-[color-mix(in_srgb,var(--color-primary)_12%,var(--color-surface))]'
    : 'bg-[var(--color-surface)] group-hover:bg-[var(--color-neutral-50)]'
  const statuses: TaskStatus[] = ['todo', 'doing', 'blocked', 'changes_requested', 'approved', 'done', 'canceled']
  const priorities: TaskPriority[] = ['low', 'medium', 'high', 'urgent']
  return (
    <tr
      className={cn(
        'group cursor-pointer transition-colors',
        selected ? 'bg-[color-mix(in_srgb,var(--color-primary)_12%,transparent)]' : 'hover:bg-[var(--color-neutral-50)]'
      )}
      style={{ height: h }}
      aria-selected={selected}
      onClick={() => handlers.onSelect(task.id)}
      onDoubleClick={() => handlers.onEdit(task.id)}
    >
      <td className={cn(td, STICKY_CELL, stickyBg)} style={{ boxShadow: `inset 3px 0 0 0 ${isSub ? `color-mix(in srgb, ${color} 55%, transparent)` : color}, 1px 0 0 0 var(--color-border)` }}>
        <TitleCell
          value={task.title}
          color={color}
          number={row.number}
          depth={row.depth}
          isSub={isSub}
          ghost={false}
          readOnly={!canEdit}
          onCommit={(v) => set({ title: v })}
          onAction={isSub ? (canDelete ? () => handlers.onDelete(task.id) : undefined) : canEdit ? () => handlers.onAddSubTask(task.id) : undefined}
        />
      </td>
      <td className={td}><ProjectPill name={projectName} color={color} /></td>
      <td className={td} onClick={(e) => e.stopPropagation()}>
        <AssigneeSelect value={task.assignee_id} onCommit={(id, name) => void set({ assignee_id: id, assignee: name })} disabled={!canEdit} />
      </td>
      <td className={td}><DateCell value={task.start_date} readOnly={!canEdit} small={isSub} onCommit={(v) => void set({ start_date: v })} /></td>
      <td className={td}><DateCell value={task.due_date} readOnly={!canEdit} small={isSub} onCommit={(v) => void set({ due_date: v })} /></td>
      <td className={td}>
        <BadgeSelect value={task.priority} styles={PRIORITY_STYLE} readOnly={!canEdit} small={isSub}
          options={priorities.map((p) => ({ value: p, label: t(`priority.${p}`) }))} onCommit={(v) => void set({ priority: v })} />
      </td>
      <td className={td}>
        <BadgeSelect value={task.status} styles={STATUS_STYLE} readOnly={!canEdit} small={isSub}
          options={statuses.map((s) => ({ value: s, label: t(`status.${s}`) }))} onCommit={(v) => void set({ status: v })} />
      </td>
      <td className={td} onClick={(e) => e.stopPropagation()}>
        <EditableCellWithDebounce value={task.effort_estimate_h || 0} type="number" placeholder="0h" disabled={!canEdit}
          onCommit={(v) => set({ effort_estimate_h: Number(v) || 0 })} />
      </td>
      <td className={td}><ProgressCell value={task.progress || 0} color={color} small={isSub} /></td>
      <td className={td}><DocumentsCell task={task} count={documents} small={isSub} canUpload={canEdit} onChanged={handlers.onCountsChanged} /></td>
      <td className={td}><CommentsCell task={task} count={comments} small={isSub} onChanged={handlers.onCountsChanged} /></td>
      <td className={td} onClick={(e) => e.stopPropagation()}>
        <RowMenu onEdit={() => handlers.onEdit(task.id)} onDuplicate={() => handlers.onDuplicate(task.id)} onDelete={() => handlers.onDelete(task.id)} canDelete={canDelete} />
      </td>
    </tr>
  )
})

