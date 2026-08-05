import { useState, useEffect, useRef } from 'react'
import { cn } from '@/lib/utils'
import { Plus, Minus } from 'lucide-react'

interface EditableTitleCellProps {
  value: string
  onCommit: (value: string) => void
  onAddSubTask?: () => void
  onCollapse?: () => void
  isCollapsed?: boolean
  hasSubTasks?: boolean
  taskLevel: number
  className?: string
  disabled?: boolean
}

export function EditableTitleCell({
  value,
  onCommit,
  onAddSubTask,
  onCollapse,
  isCollapsed,
  hasSubTasks,
  taskLevel,
  className,
  disabled,
}: EditableTitleCellProps) {
  const [editing, setEditing] = useState(false)
  const [draft, setDraft] = useState(value)
  const inputRef = useRef<HTMLInputElement>(null)

  useEffect(() => {
    if (editing && inputRef.current) {
      inputRef.current.focus()
      inputRef.current.select()
    }
  }, [editing])

  function handleBlur() {
    setEditing(false)
    if (draft !== value) onCommit(draft)
  }

  function handleKeyDown(e: React.KeyboardEvent) {
    if (e.key === 'Enter') {
      inputRef.current?.blur()
    } else if (e.key === 'Escape') {
      setDraft(value)
      setEditing(false)
    }
  }

  const indent = taskLevel * 20

  return (
    <div className={cn('flex items-center gap-1 min-h-[1.75rem]', className)} style={{ paddingLeft: `${indent}px` }}>
      {hasSubTasks && (
        <button
          onClick={onCollapse}
          className="p-0.5 rounded hover:bg-[var(--color-neutral-100)] flex-shrink-0"
          title={isCollapsed ? 'Expand' : 'Collapse'}
        >
          {isCollapsed ? <Plus className="w-3 h-3" /> : <Minus className="w-3 h-3" />}
        </button>
      )}
      {(!hasSubTasks || !isCollapsed) && onAddSubTask && (
        <button
          onClick={onAddSubTask}
          className="p-0.5 rounded hover:bg-[var(--color-neutral-100)] flex-shrink-0 opacity-0 group-hover:opacity-100 transition-opacity"
          title="Add subtask"
        >
          <Plus className="w-3 h-3 text-[var(--color-text-tertiary)]" />
        </button>
      )}
      {editing ? (
        <input
          ref={inputRef}
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          onBlur={handleBlur}
          onKeyDown={handleKeyDown}
          className="flex-1 px-2 py-1 text-sm border border-[var(--color-primary)] rounded bg-[var(--color-surface)] outline-none"
        />
      ) : (
        <div
          onClick={() => !disabled && setEditing(true)}
          className={cn(
            'flex-1 px-2 py-1 text-sm rounded cursor-pointer hover:bg-[var(--color-neutral-100)] truncate',
            disabled && 'cursor-not-allowed opacity-60'
          )}
        >
          {value || <span className="text-[var(--color-text-tertiary)]">—</span>}
        </div>
      )}
    </div>
  )
}
