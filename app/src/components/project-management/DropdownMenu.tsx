import { useState, useRef, useEffect, useLayoutEffect, type ReactNode } from 'react'
import { cn } from '@/lib/utils'

export interface DropdownMenuItem {
  label: string
  icon?: ReactNode
  onClick?: () => void
  variant?: 'default' | 'danger'
  disabled?: boolean
  divider?: boolean
}

interface DropdownMenuProps {
  trigger: ReactNode
  items: DropdownMenuItem[]
  align?: 'left' | 'right'
  className?: string
}

export function DropdownMenu({ trigger, items, align = 'right', className }: DropdownMenuProps) {
  const [open, setOpen] = useState(false)
  const ref = useRef<HTMLDivElement>(null)
  const contentRef = useRef<HTMLDivElement>(null)
  const [pos, setPos] = useState<{ top: number; left: number } | null>(null)

  useLayoutEffect(() => {
    if (!open || !ref.current) return
    const rect = ref.current.getBoundingClientRect()
    const top = rect.bottom + 4
    let left = align === 'right' ? rect.right : rect.left
    const maxLeft = window.innerWidth - 200
    if (left > maxLeft) left = maxLeft
    if (left < 0) left = 0
    setPos({ top, left })
  }, [open, align])

  useEffect(() => {
    if (!open) return
    function handleClickOutside(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node) &&
          contentRef.current && !contentRef.current.contains(e.target as Node)) {
        setOpen(false)
      }
    }
    function handleScroll() {
      setOpen(false)
    }
    document.addEventListener('mousedown', handleClickOutside)
    window.addEventListener('scroll', handleScroll, true)
    return () => {
      document.removeEventListener('mousedown', handleClickOutside)
      window.removeEventListener('scroll', handleScroll, true)
    }
  }, [open])

  return (
    <div ref={ref} className={cn('relative inline-block', className)}>
      <div onClick={() => setOpen((v) => !v)} className="cursor-pointer inline-flex">
        {trigger}
      </div>
      {open && pos && (
        <div
          ref={contentRef}
          style={{ position: 'fixed', top: pos.top, left: pos.left, zIndex: 9999 }}
          className={cn(
            'min-w-[10rem] card shadow-lg border border-[var(--color-border)] rounded-lg py-1'
          )}
        >
          {items.map((item, i) => (
            <div key={i}>
              {item.divider && <div className="h-px bg-[var(--color-border)] my-1" />}
              <button
                disabled={item.disabled}
                onClick={() => {
                  if (item.disabled) return
                  item.onClick?.()
                  setOpen(false)
                }}
                className={cn(
                  'w-full flex items-center gap-2 px-3 py-2 text-sm text-left hover:bg-[var(--color-neutral-100)] transition-colors',
                  item.variant === 'danger' && 'text-[var(--color-danger)] hover:bg-[rgba(222,53,11,0.08)]',
                  item.disabled && 'opacity-50 cursor-not-allowed'
                )}
              >
                {item.icon && <span className="flex-shrink-0">{item.icon}</span>}
                <span>{item.label}</span>
              </button>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
