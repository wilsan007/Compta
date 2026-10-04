import { cn } from '@/lib/utils'
import { DropdownMenu, type DropdownMenuItem } from '../DropdownMenu'
import { ChevronDown } from 'lucide-react'
import type { ReactNode } from 'react'

interface SelectOption {
  value: string
  label: string
  color?: string
}

interface EditableSelectCellProps {
  value: string
  options: SelectOption[]
  onCommit: (value: string) => void
  className?: string
  disabled?: boolean
  renderBadge?: (option: SelectOption) => ReactNode
}

export function EditableSelectCell({
  value,
  options,
  onCommit,
  className,
  disabled,
  renderBadge,
}: EditableSelectCellProps) {
  const selected = options.find((o) => o.value === value)

  const items: DropdownMenuItem[] = options.map((opt) => ({
    label: opt.label,
    onClick: () => onCommit(opt.value),
  }))

  const badgeColorMap: Record<string, string> = {
    todo: 'bg-[var(--color-neutral-200)] text-[var(--color-text)]',
    doing: 'bg-[rgba(0,102,204,0.12)] text-[var(--color-primary)]',
    blocked: 'bg-[rgba(222,53,11,0.12)] text-[var(--color-danger)]',
    done: 'bg-[rgba(0,135,90,0.12)] text-[var(--color-success)]',
    canceled: 'bg-[var(--color-neutral-200)] text-[var(--color-text-tertiary)]',
    changes_requested: 'bg-[rgba(255,149,0,0.12)] text-[var(--color-warning-text)]',
    approved: 'bg-[rgba(0,135,90,0.12)] text-[var(--color-success)]',
    low: 'bg-[var(--color-neutral-200)] text-[var(--color-text-secondary)]',
    medium: 'bg-[rgba(255,149,0,0.12)] text-[var(--color-warning-text)]',
    high: 'bg-[rgba(222,53,11,0.12)] text-[var(--color-danger)]',
    urgent: 'bg-[rgba(222,53,11,0.2)] text-[var(--color-danger)] font-bold',
  }

  return (
    <div
      className={cn(
        'px-1 py-0.5 min-h-[1.75rem] flex items-center',
        disabled && 'opacity-60',
        className
      )}
    >
      <DropdownMenu
        trigger={
          <div className={cn('flex items-center gap-1 cursor-pointer rounded px-2 py-0.5 hover:bg-[var(--color-neutral-100)]', disabled && 'cursor-not-allowed')}>
            {renderBadge && selected ? (
              renderBadge(selected)
            ) : selected ? (
              <span
                className={cn(
                  'inline-flex items-center px-2 py-0.5 rounded text-xs font-medium',
                  badgeColorMap[selected.value] || 'bg-[var(--color-neutral-200)] text-[var(--color-text)]'
                )}
              >
                {selected.label}
              </span>
            ) : (
              <span className="text-sm text-[var(--color-text-tertiary)]">—</span>
            )}
            {!disabled && <ChevronDown className="w-3 h-3 text-[var(--color-text-tertiary)]" />}
          </div>
        }
        items={items}
      />
    </div>
  )
}
