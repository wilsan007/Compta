import { useState, useEffect, useRef, useCallback } from 'react'
import { cn } from '@/lib/utils'
import { Loader2, Check, AlertCircle } from 'lucide-react'

interface EditableCellWithDebounceProps {
  value: string | number
  onCommit: (value: string) => Promise<void>
  type?: 'text' | 'number'
  className?: string
  placeholder?: string
  debounceMs?: number
  disabled?: boolean
}

type SaveState = 'idle' | 'saving' | 'saved' | 'error'

export function EditableCellWithDebounce({
  value,
  onCommit,
  type = 'text',
  className,
  placeholder,
  debounceMs = 800,
  disabled,
}: EditableCellWithDebounceProps) {
  const [editing, setEditing] = useState(false)
  const [draft, setDraft] = useState(String(value ?? ''))
  const [saveState, setSaveState] = useState<SaveState>('idle')
  const inputRef = useRef<HTMLInputElement>(null)
  const debounceTimer = useRef<ReturnType<typeof setTimeout> | null>(null)
  const lastCommittedRef = useRef(String(value ?? ''))

  useEffect(() => {
    if (editing && inputRef.current) {
      inputRef.current.focus()
      inputRef.current.select()
    }
  }, [editing])

  const commit = useCallback(
    async (val: string) => {
      if (val === lastCommittedRef.current) return
      setSaveState('saving')
      try {
        await onCommit(val)
        lastCommittedRef.current = val
        setSaveState('saved')
        setTimeout(() => setSaveState('idle'), 1500)
      } catch {
        setSaveState('error')
        setTimeout(() => setSaveState('idle'), 2000)
      }
    },
    [onCommit]
  )

  function scheduleCommit(val: string) {
    setDraft(val)
    if (debounceTimer.current) clearTimeout(debounceTimer.current)
    debounceTimer.current = setTimeout(() => commit(val), debounceMs)
  }

  function handleBlur() {
    setEditing(false)
    if (debounceTimer.current) {
      clearTimeout(debounceTimer.current)
      debounceTimer.current = null
    }
    if (draft !== lastCommittedRef.current) {
      commit(draft)
    }
  }

  function handleKeyDown(e: React.KeyboardEvent) {
    if (e.key === 'Enter') {
      inputRef.current?.blur()
    } else if (e.key === 'Escape') {
      setDraft(lastCommittedRef.current)
      setEditing(false)
      if (debounceTimer.current) {
        clearTimeout(debounceTimer.current)
        debounceTimer.current = null
      }
    }
  }

  if (editing) {
    return (
      <div className="relative flex items-center">
        <input
          ref={inputRef}
          type={type}
          value={draft}
          onChange={(e) => scheduleCommit(e.target.value)}
          onBlur={handleBlur}
          onKeyDown={handleKeyDown}
          className={cn(
            'w-full px-2 py-1 text-sm border border-[var(--color-primary)] rounded bg-[var(--color-surface)] outline-none pr-7',
            className
          )}
          placeholder={placeholder}
        />
        {saveState === 'saving' && (
          <Loader2 className="w-3.5 h-3.5 absolute right-2 animate-spin text-[var(--color-primary)]" />
        )}
        {saveState === 'saved' && (
          <Check className="w-3.5 h-3.5 absolute right-2 text-[var(--color-success)]" />
        )}
        {saveState === 'error' && (
          <AlertCircle className="w-3.5 h-3.5 absolute right-2 text-[var(--color-danger)]" />
        )}
      </div>
    )
  }

  return (
    <div
      onClick={() => !disabled && setEditing(true)}
      className={cn(
        'px-2 py-1 text-sm rounded min-h-[1.75rem] flex items-center justify-between gap-1',
        !disabled && 'cursor-pointer hover:bg-[var(--color-neutral-100)]',
        disabled && 'opacity-60 cursor-not-allowed',
        className
      )}
    >
      <span>{value || placeholder || <span className="text-[var(--color-text-tertiary)]">—</span>}</span>
      {saveState === 'saving' && <Loader2 className="w-3 h-3 animate-spin text-[var(--color-primary)]" />}
      {saveState === 'saved' && <Check className="w-3 h-3 text-[var(--color-success)]" />}
      {saveState === 'error' && <AlertCircle className="w-3 h-3 text-[var(--color-danger)]" />}
    </div>
  )
}
