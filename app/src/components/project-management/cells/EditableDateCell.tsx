import { useState, useEffect } from 'react'
import { cn } from '@/lib/utils'
import { Popover } from '../Popover'
import { ChevronDown } from 'lucide-react'

interface EditableDateCellProps {
  value: string | null
  onCommit: (value: string | null) => void
  className?: string
  disabled?: boolean
}

function formatDate(dateStr: string | null): string {
  if (!dateStr) return '—'
  const d = new Date(dateStr)
  if (isNaN(d.getTime())) return dateStr
  return d.toLocaleDateString(undefined, { day: '2-digit', month: '2-digit', year: 'numeric' })
}

export function EditableDateCell({ value, onCommit, className, disabled }: EditableDateCellProps) {
  const [draft, setDraft] = useState(value || '')

  useEffect(() => {
    setDraft(value || '')
  }, [value])

  function handleClear() {
    setDraft('')
    onCommit(null)
  }

  function handleApply() {
    onCommit(draft || null)
  }

  return (
    <Popover
      trigger={
        <div
          className={cn(
            'px-2 py-1 text-sm rounded min-h-[1.75rem] flex items-center justify-between gap-1 cursor-pointer hover:bg-[var(--color-neutral-100)]',
            disabled && 'cursor-not-allowed opacity-60',
            className
          )}
        >
          <span className={!value ? 'text-[var(--color-text-tertiary)]' : ''}>{formatDate(value)}</span>
          <ChevronDown className="w-3 h-3 text-[var(--color-text-tertiary)]" />
        </div>
      }
      contentClassName="w-auto"
    >
      <div className="p-2 space-y-2">
        <input
          type="date"
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          className="px-2 py-1 text-sm border border-[var(--color-border)] rounded bg-[var(--color-surface)] outline-none focus:border-[var(--color-primary)]"
        />
        <div className="flex justify-between gap-2">
          <button
            onClick={handleClear}
            className="px-2 py-1 text-xs rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-text-secondary)]"
          >
            Clear
          </button>
          <button
            onClick={handleApply}
            className="px-3 py-1 text-xs rounded bg-[var(--color-primary)] text-white hover:opacity-90"
          >
            OK
          </button>
        </div>
      </div>
    </Popover>
  )
}
