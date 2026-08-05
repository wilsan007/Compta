import { useTranslation } from 'react-i18next'
import { Plus, Zap, FileText, Download } from 'lucide-react'
import { cn } from '@/lib/utils'

interface TaskTableHeaderProps {
  onNewTask: () => void
  onQuickAction: () => void
  onDetailedAction: () => void
  onExport: () => void
  mode: 'tasks' | 'projects'
  onToggleMode: () => void
  taskCount: number
  className?: string
  onNewProject?: () => void
}

export function TaskTableHeader({
  onNewTask,
  onQuickAction,
  onDetailedAction,
  onExport,
  mode,
  onToggleMode,
  taskCount,
  className,
  onNewProject,
}: TaskTableHeaderProps) {
  const { t } = useTranslation('taskManagement')

  return (
    <div className={cn('flex items-center justify-between px-4 py-3 border-b border-[var(--color-border)] bg-[var(--color-surface)]', className)}>
      <div className="flex items-center gap-2">
        {mode === 'tasks' ? (
          <>
            <button
              onClick={onNewTask}
              className="flex items-center gap-1.5 px-3 py-1.5 text-sm rounded-lg bg-[var(--color-primary)] text-white hover:opacity-90"
            >
              <Plus className="w-4 h-4" />
              {t('table.newTask')}
            </button>
            <button
              onClick={onQuickAction}
              className="flex items-center gap-1.5 px-3 py-1.5 text-sm rounded-lg border border-[var(--color-border)] hover:bg-[var(--color-neutral-100)]"
            >
              <Zap className="w-4 h-4" />
              {t('table.quickAction')}
            </button>
            <button
              onClick={onDetailedAction}
              className="flex items-center gap-1.5 px-3 py-1.5 text-sm rounded-lg border border-[var(--color-border)] hover:bg-[var(--color-neutral-100)]"
            >
              <FileText className="w-4 h-4" />
              {t('table.detailedAction')}
            </button>
          </>
        ) : (
          <button
            onClick={onNewProject}
            disabled={!onNewProject}
            className="flex items-center gap-1.5 px-3 py-1.5 text-sm rounded-lg bg-[var(--color-primary)] text-white hover:opacity-90 disabled:opacity-40 disabled:cursor-not-allowed"
          >
            <Plus className="w-4 h-4" />
            {t('actions.newProject')}
          </button>
        )}
      </div>

      <div className="flex items-center gap-3">
        <span className="text-xs text-[var(--color-text-secondary)]">
          {taskCount} {t('table.tasks')}
        </span>
        <div className="flex rounded-lg border border-[var(--color-border)] overflow-hidden">
          <button
            onClick={() => mode !== 'tasks' && onToggleMode()}
            className={cn(
              'px-3 py-1 text-xs font-medium',
              mode === 'tasks' ? 'bg-[var(--color-primary)] text-white' : 'hover:bg-[var(--color-neutral-100)]'
            )}
          >
            {t('table.modeTasks')}
          </button>
          <button
            onClick={() => mode !== 'projects' && onToggleMode()}
            className={cn(
              'px-3 py-1 text-xs font-medium',
              mode === 'projects' ? 'bg-[var(--color-primary)] text-white' : 'hover:bg-[var(--color-neutral-100)]'
            )}
          >
            {t('table.modeProjects')}
          </button>
        </div>
        <button
          onClick={onExport}
          className="flex items-center gap-1.5 px-3 py-1.5 text-sm rounded-lg border border-[var(--color-border)] hover:bg-[var(--color-neutral-100)]"
          title={t('table.export')}
        >
          <Download className="w-4 h-4" />
        </button>
      </div>
    </div>
  )
}
