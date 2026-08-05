import { useTranslation } from 'react-i18next'
import { cn } from '@/lib/utils'
import type { ViewMode, DisplayMode } from '@/types/projectManagement'

interface GanttHeaderProps {
  viewMode: ViewMode
  onViewModeChange: (mode: ViewMode) => void
  yearBuffer: number
  onYearBufferChange: (buffer: number) => void
  mode: DisplayMode
  onToggleMode: () => void
  className?: string
}

const VIEW_MODES: ViewMode[] = ['day', 'week', 'month', 'quarter', 'year']

export function GanttHeader({
  viewMode,
  onViewModeChange,
  yearBuffer,
  onYearBufferChange,
  mode,
  onToggleMode,
  className,
}: GanttHeaderProps) {
  const { t } = useTranslation('taskManagement')

  return (
    <div className={cn('flex items-center justify-between px-4 py-2 border-b border-[var(--color-border)] bg-[var(--color-surface)]', className)}>
      <div className="flex items-center gap-2">
        <div className="flex rounded-lg border border-[var(--color-border)] overflow-hidden">
          {VIEW_MODES.map((vm) => (
            <button
              key={vm}
              onClick={() => onViewModeChange(vm)}
              className={cn(
                'px-3 py-1 text-xs font-medium',
                viewMode === vm ? 'bg-[var(--color-primary)] text-white' : 'hover:bg-[var(--color-neutral-100)]'
              )}
            >
              {t(`gantt.viewMode.${vm}`)}
            </button>
          ))}
        </div>
        <div className="flex items-center gap-1">
          <button
            onClick={() => onYearBufferChange(Math.max(0, yearBuffer - 1))}
            className="px-2 py-1 text-xs rounded border border-[var(--color-border)] hover:bg-[var(--color-neutral-100)]"
          >
            −
          </button>
          <span className="text-xs text-[var(--color-text-secondary)] px-1">{t('gantt.yearBuffer')}: {yearBuffer}</span>
          <button
            onClick={() => onYearBufferChange(yearBuffer + 1)}
            className="px-2 py-1 text-xs rounded border border-[var(--color-border)] hover:bg-[var(--color-neutral-100)]"
          >
            +
          </button>
        </div>
      </div>

      <div className="flex rounded-lg border border-[var(--color-border)] overflow-hidden">
        <button
          onClick={() => mode !== 'tasks' && onToggleMode()}
          className={cn(
            'px-3 py-1 text-xs font-medium',
            mode === 'tasks' ? 'bg-[var(--color-primary)] text-white' : 'hover:bg-[var(--color-neutral-100)]'
          )}
        >
          {t('gantt.modeTasks')}
        </button>
        <button
          onClick={() => mode !== 'projects' && onToggleMode()}
          className={cn(
            'px-3 py-1 text-xs font-medium',
            mode === 'projects' ? 'bg-[var(--color-primary)] text-white' : 'hover:bg-[var(--color-neutral-100)]'
          )}
        >
          {t('gantt.modeProjects')}
        </button>
      </div>
    </div>
  )
}
