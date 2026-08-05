import { useState, useEffect, useMemo } from 'react'
import { useTranslation } from 'react-i18next'
import { Popover } from './Popover'
import { Avatar } from './Avatar'
import { AlertTriangle, UserPlus, Mail } from 'lucide-react'
import { useWorkloadAlert } from '@/hooks/useWorkloadAlert'
import { getEmployees } from '@/lib/queries'
import { useModuleAwareAccess } from '@/components/cross-module/useModuleAwareAccess'
import { QuickEmployeeAccess } from '@/components/cross-module/QuickEmployeeAccess'
import { QuickUserAccess } from '@/components/cross-module/QuickUserAccess'
import type { Employee } from '@/types'
import { cn } from '@/lib/utils'

interface AssigneeSelectProps {
  /** Employee ID (UUID) or null if unassigned */
  value: string | null
  /** Called with employee_id (or null) and employee name (or null) */
  onCommit: (employeeId: string | null, employeeName: string | null) => void
  disabled?: boolean
}

export function AssigneeSelect({ value, onCommit, disabled }: AssigneeSelectProps) {
  const { t } = useTranslation('taskManagement')
  const { t: tCross } = useTranslation('crossModule')
  const { getAccessStrategy } = useModuleAwareAccess()
  const hrStrategy = getAccessStrategy('hr')
  const [employees, setEmployees] = useState<Employee[]>([])
  const [search, setSearch] = useState('')
  const [showQuickAdd, setShowQuickAdd] = useState(false)
  const [showQuickInvite, setShowQuickInvite] = useState(false)

  const loadEmployees = () => {
    getEmployees()
      .then(setEmployees)
      .catch(() => {})
  }

  useEffect(() => {
    loadEmployees()
  }, [])

  const selectedEmployee = useMemo(
    () => employees.find((emp) => emp.id === value) || null,
    [employees, value]
  )

  const displayName = selectedEmployee?.name || null
  const { workload } = useWorkloadAlert(displayName)

  const filtered = employees.filter((emp) => {
    if (!search) return true
    const name = (emp.name || '').toLowerCase()
    return name.includes(search.toLowerCase())
  })

  return (
    <>
    <Popover
      trigger={
        <div className={cn(
          'flex items-center gap-1.5 cursor-pointer px-2 py-1 rounded hover:bg-[var(--color-neutral-100)] min-h-[1.75rem]',
          disabled && 'cursor-not-allowed opacity-60'
        )}>
          {displayName ? (
            <>
              <Avatar name={displayName} size="xs" />
              <span className="text-xs truncate max-w-[70px]" title={displayName}>{displayName}</span>
              {workload.isOverloaded && (
                <AlertTriangle className="w-3 h-3 text-[var(--color-warning)]" />
              )}
            </>
          ) : (
            <span className="text-xs text-[var(--color-text-tertiary)]">—</span>
          )}
        </div>
      }
    >
      {disabled ? (
        <div className="p-2 text-xs text-[var(--color-text-tertiary)]">{t('assignee.search')}</div>
      ) : (
      <div className="w-56 space-y-2">
        <input
          type="text"
          placeholder={t('assignee.search')}
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          className="w-full px-2 py-1.5 text-sm border border-[var(--color-border)] rounded bg-[var(--color-surface)] outline-none focus:border-[var(--color-primary)]"
        />
        <div className="max-h-48 overflow-y-auto space-y-0.5">
          <button
            onClick={() => onCommit(null, null)}
            className={cn(
              'w-full flex items-center gap-2 px-2 py-1.5 text-sm rounded hover:bg-[var(--color-neutral-100)] text-left',
              !value && 'bg-[var(--color-neutral-100)]'
            )}
          >
            <span className="text-[var(--color-text-tertiary)]">{t('assignee.unassigned')}</span>
          </button>
          {filtered.map((emp) => {
            const name = emp.name || ''
            return (
              <button
                key={emp.id}
                onClick={() => onCommit(emp.id, name)}
                className={cn(
                  'w-full flex items-center gap-2 px-2 py-1.5 text-sm rounded hover:bg-[var(--color-neutral-100)] text-left',
                  value === emp.id && 'bg-[var(--color-neutral-100)]'
                )}
              >
                <Avatar name={name} size="xs" />
                <span className="truncate">{name}</span>
              </button>
            )
          })}
        </div>
        <div className="border-t border-[var(--color-border)] mt-1 pt-2 space-y-0.5">
          {hrStrategy === 'inline' && (
            <button
              onClick={() => setShowQuickAdd(true)}
              className="w-full flex items-center gap-2 px-2 py-1.5 text-sm rounded hover:bg-[var(--color-neutral-100)] text-left text-[var(--color-primary)]"
            >
              <UserPlus className="w-3.5 h-3.5" />
              <span>{tCross('employee.add')}</span>
            </button>
          )}
          <button
            onClick={() => setShowQuickInvite(true)}
            className="w-full flex items-center gap-2 px-2 py-1.5 text-sm rounded hover:bg-[var(--color-neutral-100)] text-left text-[var(--color-primary)]"
          >
            <Mail className="w-3.5 h-3.5" />
            <span>{tCross('user.invite')}</span>
          </button>
        </div>
      </div>
      )}
    </Popover>
    {showQuickAdd && (
      <QuickEmployeeAccess
        onClose={() => setShowQuickAdd(false)}
        onSaved={() => loadEmployees()}
      />
    )}
    {showQuickInvite && (
      <QuickUserAccess
        onClose={() => setShowQuickInvite(false)}
        onSaved={() => loadEmployees()}
        forceInline
        module="projectManagement"
      />
    )}
    </>
  )
}
