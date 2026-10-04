import { useState, useRef, useCallback, type ReactNode } from 'react'
import { cn } from '@/lib/utils'

interface ResizablePanelProps {
  left: ReactNode
  right: ReactNode
  initialLeftWidth?: number
  minLeftWidth?: number
  maxLeftWidth?: number
  className?: string
}

export function ResizablePanel({
  left,
  right,
  initialLeftWidth = 60,
  minLeftWidth = 20,
  maxLeftWidth = 80,
  className,
}: ResizablePanelProps) {
  const [leftWidth, setLeftWidth] = useState(initialLeftWidth)
  const containerRef = useRef<HTMLDivElement>(null)
  const draggingRef = useRef(false)

  const handleMouseDown = useCallback(() => {
    draggingRef.current = true
    document.body.style.cursor = 'col-resize'
    document.body.style.userSelect = 'none'
  }, [])

  const handleMouseMove = useCallback((e: React.MouseEvent) => {
    if (!draggingRef.current || !containerRef.current) return
    const rect = containerRef.current.getBoundingClientRect()
    const percentage = ((e.clientX - rect.left) / rect.width) * 100
    const clamped = Math.min(maxLeftWidth, Math.max(minLeftWidth, percentage))
    setLeftWidth(clamped)
  }, [minLeftWidth, maxLeftWidth])

  const handleMouseUp = useCallback(() => {
    draggingRef.current = false
    document.body.style.cursor = ''
    document.body.style.userSelect = ''
  }, [])

  return (
    <div
      ref={containerRef}
      className={cn('flex w-full h-full', className)}
      onMouseMove={handleMouseMove}
      onMouseUp={handleMouseUp}
      onMouseLeave={handleMouseUp}
    >
      <div style={{ width: `${leftWidth}%` }} className="h-full overflow-hidden min-w-0">
        {left}
      </div>
      <div
        onMouseDown={handleMouseDown}
        className="w-1.5 flex-shrink-0 bg-[var(--color-border)] hover:bg-[var(--color-primary)] cursor-col-resize transition-colors relative group"
      >
        <div className="absolute inset-y-0 -left-1 -right-1 z-10" />
      </div>
      <div style={{ width: `${100 - leftWidth}%` }} className="h-full overflow-hidden min-w-0">
        {right}
      </div>
    </div>
  )
}
