import { useState, useRef, useEffect, useMemo } from 'react'
import { ChevronDown, Search, Check } from 'lucide-react'

interface SearchableSelectProps {
  value: string
  onChange: (value: string) => void
  options: { value: string; label: string }[]
  placeholder?: string
  searchPlaceholder?: string
  className?: string
  id?: string
}

export function SearchableSelect({
  value,
  onChange,
  options,
  placeholder = 'Sélectionner...',
  searchPlaceholder = 'Rechercher...',
  className = '',
  id,
}: SearchableSelectProps) {
  const [open, setOpen] = useState(false)
  const [query, setQuery] = useState('')
  const ref = useRef<HTMLDivElement>(null)
  const inputRef = useRef<HTMLInputElement>(null)

  const selected = options.find((o) => o.value === value)

  const filtered = useMemo(() => {
    if (!query.trim()) return options
    const q = query.toLowerCase()
    return options.filter(
      (o) => o.label.toLowerCase().includes(q) || o.value.toLowerCase().includes(q),
    )
  }, [query, options])

  useEffect(() => {
    function handleClickOutside(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) {
        setOpen(false)
        setQuery('')
      }
    }
    document.addEventListener('mousedown', handleClickOutside)
    return () => document.removeEventListener('mousedown', handleClickOutside)
  }, [])

  useEffect(() => {
    if (open && inputRef.current) {
      inputRef.current.focus()
    }
  }, [open])

  return (
    <div ref={ref} className={`relative ${className}`}>
      <button
        type="button"
        id={id}
        onClick={() => setOpen((o) => !o)}
        className="input flex items-center justify-between cursor-pointer text-[var(--color-text)]"
      >
        <span className={selected ? '' : 'text-[var(--color-text-secondary)]'}>
          {selected ? selected.label : placeholder}
        </span>
        <ChevronDown className="w-4 h-4 text-[var(--color-text-secondary)] flex-shrink-0 ml-2" />
      </button>

      {open && (
        <div className="absolute z-50 left-0 right-0 mt-1 bg-[var(--color-surface,#fff)] border border-[var(--color-neutral-200)] rounded-lg shadow-lg max-h-64 overflow-hidden flex flex-col text-[var(--color-text)]">
          <div className="p-2 border-b border-[var(--color-neutral-100)]">
            <div className="relative">
              <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 w-4 h-4 text-[var(--color-text-secondary)]" />
              <input
                ref={inputRef}
                type="text"
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                placeholder={searchPlaceholder}
                className="w-full pl-9 pr-3 py-1.5 text-sm text-[var(--color-text)] bg-[var(--color-surface,#fff)] border border-[var(--color-neutral-200)] rounded-md focus:outline-none focus:border-[var(--color-primary)]"
                onKeyDown={(e) => {
                  if (e.key === 'Enter') {
                    e.preventDefault()
                    e.stopPropagation()
                    if (filtered.length > 0) {
                      onChange(filtered[0].value)
                    }
                    setOpen(false)
                    setQuery('')
                  }
                  if (e.key === 'Escape') {
                    e.preventDefault()
                    e.stopPropagation()
                    setOpen(false)
                    setQuery('')
                  }
                }}
              />
            </div>
          </div>
          <div className="overflow-y-auto flex-1">
            {filtered.length === 0 && (
              <div className="px-3 py-4 text-sm text-[var(--color-text-secondary)] text-center">
                Aucun résultat
              </div>
            )}
            {filtered.map((o) => (
              <button
                key={o.value}
                type="button"
                onClick={() => {
                  onChange(o.value)
                  setOpen(false)
                  setQuery('')
                }}
                className={`w-full text-left px-3 py-2 text-sm text-[var(--color-text)] hover:bg-[var(--color-neutral-50)] flex items-center justify-between ${
                  o.value === value ? 'bg-[rgba(0,108,255,0.05)] font-medium' : ''
                }`}
              >
                <span>{o.label}</span>
                {o.value === value && <Check className="w-4 h-4 text-[var(--color-primary)]" />}
              </button>
            ))}
          </div>
        </div>
      )}
    </div>
  )
}
