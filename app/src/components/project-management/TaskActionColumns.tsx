import { memo, useMemo, type RefObject, type UIEvent } from 'react'
import { useTranslation } from 'react-i18next'
import { cn } from '@/lib/utils'
import type { ActionColumn, ActionMatrix } from '@/lib/actionColumns'
import type { TaskAction } from '@/types/projectManagement'
import { ActionCell, ACTION_COLUMN_WIDTH } from './ActionCell'
import { HEAD_H, HEADER_CELL, HEADER_ROW, PANEL_H } from './table/kit'
import { rowHeight, type TableRow } from './table/rows'

interface TaskActionColumnsProps {
  rows: TableRow[]
  matrix: ActionMatrix
  proofs: Map<string, number>
  selectedTaskId: string | null
  canEdit: boolean
  onToggle: (action: TaskAction) => void
  onProof: (action: TaskAction) => void
  scrollRef: RefObject<HTMLDivElement | null>
  onScroll: (e: UIEvent<HTMLDivElement>) => void
}

// Panneau de DROITE : une colonne par titre d'action. Les mêmes lignes, aux
// mêmes hauteurs, que le panneau de gauche ; les colonnes de la tâche
// sélectionnée passent en premier et sont soulignées, comme dans wadashaqayn.
export function TaskActionColumns({ rows, matrix, proofs, selectedTaskId, canEdit, onToggle, onProof, scrollRef, onScroll }: TaskActionColumnsProps) {
  const { t } = useTranslation('taskManagement')

  const selectedKeys = useMemo(
    () => (selectedTaskId ? new Set(matrix.byTask.get(selectedTaskId)?.keys()) : new Set<string>()),
    [matrix, selectedTaskId]
  )
  const columns: ActionColumn[] = useMemo(() => {
    if (selectedKeys.size === 0) return matrix.columns
    return [...matrix.columns.filter((c) => selectedKeys.has(c.key)), ...matrix.columns.filter((c) => !selectedKeys.has(c.key))]
  }, [matrix.columns, selectedKeys])

  if (columns.length === 0) {
    return (
      <div ref={scrollRef} className="flex items-center justify-center overflow-auto bg-[var(--color-neutral-50)]" style={{ height: PANEL_H }} onScroll={onScroll} data-panel="actions">
        <div className="p-8 text-center">
          <p className="mb-2 font-medium text-[var(--color-text-secondary)]">{t('dyn.noActionColumns')}</p>
          <p className="text-sm text-[var(--color-text-tertiary)]">{t('dyn.noActionColumnsHint')}</p>
        </div>
      </div>
    )
  }

  return (
    <div ref={scrollRef} className="overflow-auto" style={{ height: PANEL_H }} onScroll={onScroll} data-panel="actions">
      <table className="border-separate border-spacing-0">
        <thead className="sticky top-0 z-20">
          <tr className={HEADER_ROW} style={{ height: HEAD_H }}>
            {columns.map((c) => {
              const hot = selectedKeys.has(c.key)
              return (
                <th
                  key={c.key}
                  title={c.title}
                  data-action-column={c.key}
                  className={cn(
                    HEADER_CELL,
                    'px-2 text-center normal-case tracking-normal transition-colors',
                    hot && 'bg-white/15 shadow-[inset_0_-3px_0_0_#facc15]'
                  )}
                  style={{ width: ACTION_COLUMN_WIDTH, minWidth: ACTION_COLUMN_WIDTH, maxWidth: ACTION_COLUMN_WIDTH }}
                >
                  <span className="line-clamp-2 leading-tight break-words">{c.title}</span>
                </th>
              )
            })}
          </tr>
        </thead>
        <tbody>
          {rows.map((row) => {
            if (row.kind === 'band') {
              return (
                <tr key={row.key} style={{ height: rowHeight(row) }}>
                  <td colSpan={columns.length} className="border-b border-[var(--color-border)]" style={{ backgroundColor: `color-mix(in srgb, ${row.color} 12%, var(--color-surface))` }} />
                </tr>
              )
            }
            if (row.kind === 'ghost') {
              return (
                <tr key={row.key} style={{ height: rowHeight(row) }}>
                  {columns.map((c) => (
                    <td key={c.key} className="border-b border-dashed border-[var(--color-border)]" />
                  ))}
                </tr>
              )
            }
            return (
              <ActionRow
                key={row.key}
                row={row}
                columns={columns}
                cells={matrix.byTask.get(row.task.id)}
                proofs={proofs}
                selected={selectedTaskId === row.task.id}
                canEdit={canEdit}
                onToggle={onToggle}
                onProof={onProof}
              />
            )
          })}
        </tbody>
      </table>
    </div>
  )
}

const ActionRow = memo(function ActionRow({
  row,
  columns,
  cells,
  proofs,
  selected,
  canEdit,
  onToggle,
  onProof,
}: {
  row: Extract<TableRow, { kind: 'task' }>
  columns: ActionColumn[]
  cells?: Map<string, TaskAction>
  proofs: Map<string, number>
  selected: boolean
  canEdit: boolean
  onToggle: (action: TaskAction) => void
  onProof: (action: TaskAction) => void
}) {
  return (
    <tr className={cn('transition-colors', selected && 'bg-[color-mix(in_srgb,var(--color-primary)_10%,transparent)]')} style={{ height: rowHeight(row) }}>
      {columns.map((c) => {
        const action = cells?.get(c.key)
        return (
          <td
            key={c.key}
            className={cn('border-b border-[var(--color-border)] text-center', row.isSub && 'text-xs', selected && action && 'bg-[color-mix(in_srgb,var(--color-primary)_5%,transparent)]')}
            style={{ width: ACTION_COLUMN_WIDTH, minWidth: ACTION_COLUMN_WIDTH, maxWidth: ACTION_COLUMN_WIDTH }}
          >
            <ActionCell
              action={action}
              taskTitle={row.task.title}
              proofs={action ? proofs.get(action.id) || 0 : 0}
              isSub={row.isSub}
              selected={selected && !!action}
              canEdit={canEdit}
              onToggle={onToggle}
              onProof={onProof}
            />
          </td>
        )
      })}
    </tr>
  )
})
