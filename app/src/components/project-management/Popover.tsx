import { useState, useRef, useEffect, useLayoutEffect, type ReactNode } from 'react'
import { cn } from '@/lib/utils'

interface PopoverProps {
  trigger: ReactNode
  children: ReactNode
  align?: 'left' | 'right'
  className?: string
  contentClassName?: string
}

export function Popover({ trigger, children, align = 'left', className, contentClassName }: PopoverProps) {
  const [open, setOpen] = useState(false)
  const ref = useRef<HTMLDivElement>(null)
  const contentRef = useRef<HTMLDivElement>(null)
  const [pos, setPos] = useState<{ top: number; left: number } | null>(null)

  useLayoutEffect(() => {
    if (!open || !ref.current) return
    const rect = ref.current.getBoundingClientRect()
    const top = rect.bottom + 4
    let left = align === 'right' ? rect.right : rect.left
    // Clamp to viewport
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
    function handleEscape(e: KeyboardEvent) {
      if (e.key === 'Escape') setOpen(false)
    }
    function handleScroll() {
      setOpen(false)
    }
    document.addEventListener('mousedown', handleClickOutside)
    document.addEventListener('keydown', handleEscape)
    window.addEventListener('scroll', handleScroll, true)
    return () => {
      document.removeEventListener('mousedown', handleClickOutside)
      document.removeEventListener('keydown', handleEscape)
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
            'min-w-[12rem] card shadow-lg border border-[var(--color-border)] rounded-lg p-2',
            contentClassName
          )}
        >
          {children}
        </div>
      )}
    </div>
  )
}
