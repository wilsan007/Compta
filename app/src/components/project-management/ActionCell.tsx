import { memo } from 'react'
import { useTranslation } from 'react-i18next'
import { Check, Paperclip } from 'lucide-react'
import { cn } from '@/lib/utils'
import type { TaskAction } from '@/types/projectManagement'

export const ACTION_COLUMN_WIDTH = 140

interface ActionCellProps {
  action: TaskAction | undefined
  taskTitle: string
  proofs: number
  isSub: boolean
  selected: boolean
  canEdit: boolean
  onToggle: (action: TaskAction) => void
  onProof: (action: TaskAction) => void
}

// Une case de colonne d'action, comme dans wadashaqayn : la case à cocher et le
// poids de l'action, et le trombone qui joint une preuve (avec son compteur).
// Sans preuve, la case est grisée : la base refuserait de toute façon (803).
export const ActionCell = memo(function ActionCell({ action, taskTitle, proofs, isSub, selected, canEdit, onToggle, onProof }: ActionCellProps) {
  const { t } = useTranslation('taskManagement')
  if (!action) return <span className="text-[var(--color-text-tertiary)]" aria-hidden="true">·</span>
  const locked = !action.is_done && proofs === 0
  return (
    <div className="flex items-center justify-center gap-1.5">
      <div className="flex flex-col items-center">
        {/* zone cliquable de 24 px (porte d'accessibilité du harnais QA), case de 18 px */}
        <button
          type="button"
          role="checkbox"
          aria-checked={action.is_done}
          aria-label={`${action.title} — ${taskTitle}`}
          title={locked ? t('dyn.proofRequiredHint') : undefined}
          disabled={!canEdit || locked}
          onClick={(e) => {
            e.stopPropagation()
            onToggle(action)
          }}
          className="group/cb flex h-6 w-6 items-center justify-center rounded disabled:cursor-not-allowed"
        >
          <span
            className={cn(
              'flex items-center justify-center rounded border-2 transition-colors',
              isSub ? 'h-4 w-4' : 'h-[18px] w-[18px]',
              action.is_done
                ? 'border-emerald-500 bg-emerald-500 text-white'
                : 'border-[var(--color-text-tertiary)] group-enabled/cb:group-hover/cb:border-[var(--color-primary)]',
              (locked || !canEdit) && !action.is_done && 'border-dashed opacity-50'
            )}
          >
            {action.is_done && <Check className="h-3 w-3" strokeWidth={3} />}
          </span>
        </button>
        <span className={cn('text-[11px] font-medium tabular-nums text-[var(--color-text-tertiary)]', selected && 'font-semibold text-[var(--color-primary)]')}>
          {action.weight_percentage}%
        </span>
      </div>
      {canEdit && (
        <button
          type="button"
          onClick={(e) => {
            e.stopPropagation()
            onProof(action)
          }}
          className={cn(
            'relative flex h-6 w-6 items-center justify-center rounded transition-colors hover:bg-[var(--color-neutral-100)]',
            proofs > 0 ? 'text-emerald-600 dark:text-emerald-400' : 'text-[var(--color-text-tertiary)] hover:text-[var(--color-primary)]'
          )}
          title={proofs > 0 ? t('dyn.proofCount', { count: proofs }) : t('dyn.proofAdd')}
          aria-label={proofs > 0 ? t('dyn.proofCount', { count: proofs }) : t('dyn.proofAdd')}
        >
          <Paperclip className="h-3.5 w-3.5" />
          {proofs > 0 && (
            <span className="absolute -top-0.5 -right-0.5 flex h-3.5 min-w-3.5 items-center justify-center rounded-full bg-emerald-600 px-0.5 text-[9px] font-semibold text-white">
              {proofs}
            </span>
          )}
        </button>
      )}
    </div>
  )
})
