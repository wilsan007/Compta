import { useState, useEffect, useRef } from 'react'
import { cn } from '@/lib/utils'

interface EditableCellProps {
  value: string | number
  onCommit: (value: string) => void
  type?: 'text' | 'number'
  className?: string
  placeholder?: string
  disabled?: boolean
}

export function EditableCell({
  value,
  onCommit,
  type = 'text',
  className,
  placeholder,
  disabled,
}: EditableCellProps) {
  const [editing, setEditing] = useState(false)
  const [draft, setDraft] = useState(String(value ?? ''))
  const inputRef = useRef<HTMLInputElement>(null)

  useEffect(() => {
    if (editing && inputRef.current) {
      inputRef.current.focus()
      inputRef.current.select()
    }
  }, [editing])

  function handleBlur() {
    setEditing(false)
    if (draft !== String(value ?? '')) {
      onCommit(draft)
    }
  }

  function handleKeyDown(e: React.KeyboardEvent) {
    if (e.key === 'Enter') {
      inputRef.current?.blur()
    } else if (e.key === 'Escape') {
      setDraft(String(value ?? ''))
      setEditing(false)
    }
  }

  if (editing) {
    return (
      <input
        ref={inputRef}
        type={type}
        value={draft}
        onChange={(e) => setDraft(e.target.value)}
        onBlur={handleBlur}
        onKeyDown={handleKeyDown}
        className={cn(
          'w-full px-2 py-1 text-sm border border-[var(--color-primary)] rounded bg-[var(--color-surface)] outline-none',
          className
        )}
        placeholder={placeholder}
      />
    )
  }

  return (
    <div
      onClick={() => !disabled && setEditing(true)}
      className={cn(
        'px-2 py-1 text-sm rounded min-h-[1.75rem] flex items-center',
        !disabled && 'cursor-pointer hover:bg-[var(--color-neutral-100)]',
        disabled && 'opacity-60 cursor-not-allowed',
        className
      )}
    >
      {value || placeholder || <span className="text-[var(--color-text-tertiary)]">—</span>}
    </div>
  )
}
