import { useRef, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { ChevronDown, Download, FileDown, FileSpreadsheet, FileText, FolderKanban, ListChecks, MousePointerClick, Plus, SlidersHorizontal } from 'lucide-react'
import { cn } from '@/lib/utils'
import { Floating } from './table/kit'

export type ExportFormat = 'excel' | 'pdf' | 'csv'
export type TableMode = 'tasks' | 'projects'

interface TaskTableHeaderProps {
  mode: TableMode
  onModeChange: (mode: TableMode) => void
  onNewTask: () => void
  onExport: (format: ExportFormat) => void
  exporting: boolean
  exportCount: number
  selectedTaskTitle: string | null
  quickAction: string
  setQuickAction: (v: string) => void
  onQuickAction: () => void
  onDetailedAction: () => void
  canCreate: boolean
}

const BTN = 'inline-flex h-9 items-center gap-2 rounded-lg px-3 text-sm font-medium transition-colors disabled:cursor-not-allowed disabled:opacity-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--color-primary)]'
const BTN_PRIMARY = cn(BTN, 'bg-[var(--color-primary)] text-white hover:bg-[var(--color-primary-dark)]')
const BTN_SECONDARY = cn(BTN, 'border border-[var(--color-border)] bg-[var(--color-surface)] hover:bg-[var(--color-neutral-100)]')

// En-tête du tableau : le titre et le mode d'affichage à gauche, l'export et la
// création à droite ; dessous, en mode tâches, la barre d'action qui NOMME la
// tâche sélectionnée (les fonctions de wadashaqayn, rangées comme le reste de
// l'application).
export function TaskTableHeader({
  mode,
  onModeChange,
  onNewTask,
  onExport,
  exporting,
  exportCount,
  selectedTaskTitle,
  quickAction,
  setQuickAction,
  onQuickAction,
  onDetailedAction,
  canCreate,
}: TaskTableHeaderProps) {
  const { t } = useTranslation('taskManagement')
  const [open, setOpen] = useState(false)
  const anchor = useRef<HTMLButtonElement>(null)
  const hasSelection = !!selectedTaskTitle
  const quickEnabled = hasSelection && quickAction.trim().length > 0
  const item = 'flex w-full items-start gap-2 rounded px-2 py-2 text-left hover:bg-[var(--color-neutral-100)]'
  const seg = (on: boolean) =>
    cn(
      'inline-flex h-8 items-center gap-1.5 rounded-md px-3 text-sm font-medium transition-colors',
      on ? 'bg-[var(--color-surface)] text-[var(--color-text)] shadow-sm' : 'text-[var(--color-text-secondary)] hover:text-[var(--color-text)]'
    )

  return (
    <div className="space-y-3 px-4 pt-4 pb-3 sm:px-5">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex flex-wrap items-center gap-3">
          <h2 className="text-base font-semibold text-[var(--color-text)]">{t('dyn.title')}</h2>
          <div className="inline-flex rounded-lg bg-[var(--color-neutral-100)] p-0.5" role="group" aria-label={t('dyn.displayMode')}>
            <button type="button" aria-pressed={mode === 'tasks'} className={seg(mode === 'tasks')} onClick={() => onModeChange('tasks')}>
              <ListChecks className="h-4 w-4" />
              {t('gantt.tasks')}
            </button>
            <button type="button" aria-pressed={mode === 'projects'} className={seg(mode === 'projects')} onClick={() => onModeChange('projects')}>
              <FolderKanban className="h-4 w-4" />
              {t('gantt.projects')}
            </button>
          </div>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          {exportCount > 0 && (
            <>
              <button ref={anchor} type="button" disabled={exporting} onClick={() => setOpen((o) => !o)} className={BTN_SECONDARY} aria-haspopup="menu" aria-expanded={open}>
                <Download className={cn('h-4 w-4', exporting && 'animate-pulse')} />
                {exporting ? t('dyn.exporting') : t('table.export')}
                {!exporting && <span className="rounded bg-[var(--color-neutral-100)] px-1.5 text-xs tabular-nums text-[var(--color-text-secondary)]">{exportCount}</span>}
                <ChevronDown className="h-3.5 w-3.5 opacity-60" />
              </button>
              <Floating open={open} onClose={() => setOpen(false)} anchorRef={anchor} align="end" className="w-56">
                <p className="px-2 py-1 text-xs text-[var(--color-text-tertiary)]">{t('dyn.exportFormat')}</p>
                <div className="my-1 h-px bg-[var(--color-border)]" />
                {([
                  ['excel', FileSpreadsheet, 'text-green-600'],
                  ['pdf', FileText, 'text-red-600'],
                  ['csv', FileDown, 'text-blue-600'],
                ] as const).map(([f, Icon, color]) => (
                  <button key={f} type="button" role="menuitem" className={item} onClick={() => { setOpen(false); onExport(f) }}>
                    <Icon className={cn('mt-0.5 h-4 w-4', color)} />
                    <span className="flex flex-col">
                      <span className="text-sm font-medium">{t(`dyn.export_${f}`)}</span>
                      <span className="text-xs text-[var(--color-text-tertiary)]">{t(`dyn.export_${f}_desc`)}</span>
                    </span>
                  </button>
                ))}
              </Floating>
            </>
          )}
          {canCreate && (
            <button type="button" onClick={onNewTask} className={BTN_PRIMARY}>
              <Plus className="h-4 w-4" />
              {t('table.newTask')}
            </button>
          )}
        </div>
      </div>

      {mode === 'tasks' && canCreate && (
        <div
          className={cn(
            'flex flex-wrap items-center gap-2 rounded-lg border px-3 py-2 transition-colors',
            hasSelection
              ? 'border-[color-mix(in_srgb,var(--color-primary)_35%,transparent)] bg-[color-mix(in_srgb,var(--color-primary)_6%,transparent)]'
              : 'border-dashed border-[var(--color-border)]'
          )}
        >
          {hasSelection ? (
            <span className="flex min-w-0 items-center gap-1.5 text-sm text-[var(--color-text-secondary)]">
              {t('dyn.actionOn')}
              <strong className="max-w-[16rem] truncate font-semibold text-[var(--color-text)]" title={selectedTaskTitle}>{selectedTaskTitle}</strong>
            </span>
          ) : (
            <span className="flex items-center gap-1.5 text-sm text-[var(--color-text-tertiary)]">
              <MousePointerClick className="h-4 w-4" />
              {t('table.selectTaskFirst')}
            </span>
          )}
          <div className="ms-auto flex items-center gap-2">
            <div className="flex">
              <input
                value={quickAction}
                onChange={(e) => setQuickAction(e.target.value)}
                onKeyDown={(e) => e.key === 'Enter' && quickEnabled && onQuickAction()}
                disabled={!hasSelection}
                placeholder={t('dyn.quickActionPlaceholder')}
                aria-label={t('dyn.quickActionPlaceholder')}
                className="h-9 w-48 rounded-s-lg border border-e-0 border-[var(--color-border)] bg-[var(--color-surface)] px-3 text-sm outline-none focus:border-[var(--color-primary)] disabled:cursor-not-allowed disabled:opacity-60"
              />
              <button
                type="button"
                onClick={onQuickAction}
                disabled={!quickEnabled}
                title={!hasSelection ? t('table.selectTaskFirst') : !quickAction.trim() ? t('dyn.enterActionName') : ''}
                aria-label={t('dyn.addQuickAction')}
                className={cn(BTN_PRIMARY, 'rounded-s-none px-2.5')}
              >
                <Plus className="h-4 w-4" />
              </button>
            </div>
            <button
              type="button"
              onClick={onDetailedAction}
              disabled={!hasSelection}
              title={!hasSelection ? t('table.selectTaskFirst') : t('dyn.createDetailedAction')}
              className={BTN_SECONDARY}
            >
              <SlidersHorizontal className="h-4 w-4" />
              {t('table.detailedAction')}
            </button>
          </div>
        </div>
      )}
    </div>
  )
}
