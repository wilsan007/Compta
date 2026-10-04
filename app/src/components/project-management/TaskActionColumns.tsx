import { useState, useEffect } from 'react'
import { useTranslation } from 'react-i18next'
import { useToast } from '@/lib/toast'
import { cn } from '@/lib/utils'
import { getTaskActions, toggleAction } from '@/lib/queries/projectManagement'
import type { TaskAction } from '@/types/projectManagement'
import { Check } from 'lucide-react'

interface TaskActionColumnsProps {
  taskId: string
  className?: string
  onTaskProgressUpdate?: (progress: number) => void
}

export function TaskActionColumns({ taskId, className, onTaskProgressUpdate }: TaskActionColumnsProps) {
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [actions, setActions] = useState<TaskAction[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    let cancelled = false
    async function load() {
      try {
        const data = await getTaskActions(taskId)
        if (!cancelled) setActions(data)
      } catch (err: any) {
        console.error("catch:", err)
        // ignore
        toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadingError'))
      } finally {
        if (!cancelled) setLoading(false)
      }
    }
    load()
    return () => { cancelled = true }
  }, [taskId, toast, tCommon])

  async function handleToggle(actionId: string, isDone: boolean) {
    try {
      const { progress } = await toggleAction(actionId, !isDone)
      setActions((prev) => prev.map((a) => (a.id === actionId ? { ...a, is_done: !isDone } : a)))
      onTaskProgressUpdate?.(progress)
    } catch (err: any) {
      console.error("catch:", err)
      // ignore
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadingError'))
    }
  }

  if (loading) {
    return <div className={cn('px-2 py-1 text-xs text-[var(--color-text-tertiary)]', className)}>…</div>
  }

  if (actions.length === 0) {
    return <div className={cn('px-2 py-1 text-xs text-[var(--color-text-tertiary)]', className)}>—</div>
  }

  return (
    <div className={cn('flex flex-col gap-1 px-2 py-1', className)}>
      {actions.map((action) => (
        <div key={action.id} className="flex items-center gap-2">
          <button
            onClick={() => handleToggle(action.id, action.is_done)}
            className={cn(
              'w-4 h-4 rounded border flex items-center justify-center flex-shrink-0 transition-colors',
              action.is_done
                ? 'bg-[var(--color-success)] border-[var(--color-success)] text-white'
                : 'border-[var(--color-border)] hover:border-[var(--color-primary)]'
            )}
          >
            {action.is_done && <Check className="w-3 h-3" />}
          </button>
          <span
            className={cn(
              'text-xs flex-1 truncate',
              action.is_done && 'line-through text-[var(--color-text-tertiary)]'
            )}
          >
            {action.title}
          </span>
          {action.weight_percentage > 0 && (
            <span className="text-[10px] text-[var(--color-text-tertiary)] tabular-nums">
              {action.weight_percentage}%
            </span>
          )}
        </div>
      ))}
    </div>
  )
}
