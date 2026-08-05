import { cn } from '@/lib/utils'

interface ProgressBarProps {
  value: number
  max?: number
  className?: string
  color?: string
  showLabel?: boolean
  size?: 'sm' | 'md' | 'lg'
}

export function ProgressBar({
  value,
  max = 100,
  className,
  color,
  showLabel = false,
  size = 'sm',
}: ProgressBarProps) {
  const percentage = Math.min(100, Math.max(0, max > 0 ? (value / max) * 100 : 0))
  const heightClass = size === 'sm' ? 'h-1.5' : size === 'md' ? 'h-2.5' : 'h-4'
  const bgColor = color || 'var(--color-primary)'

  return (
    <div className={cn('flex items-center gap-2', className)}>
      <div className={cn('flex-1 bg-[var(--color-neutral-100)] rounded-full overflow-hidden', heightClass)}>
        <div
          className="h-full rounded-full transition-all duration-300"
          style={{ width: `${percentage}%`, backgroundColor: bgColor }}
        />
      </div>
      {showLabel && (
        <span className="text-xs font-medium text-[var(--color-text-secondary)] tabular-nums w-8 text-right">
          {Math.round(percentage)}%
        </span>
      )}
    </div>
  )
}
