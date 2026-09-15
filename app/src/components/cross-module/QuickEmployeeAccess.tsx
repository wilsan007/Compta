import { useState, useEffect, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Link } from 'react-router-dom'
import { QuickAccessModal } from './QuickAccessModal'
import { Button, Input, EmptyState, Table, TableRow, TableCell, Badge } from '@/components/ui'
import { getEmployees, createEmployee } from '@/lib/queries/payroll'
import { useToast } from '@/lib/toast'
import { useModuleAwareAccess } from './useModuleAwareAccess'
import { Users, Plus, ExternalLink, Search } from 'lucide-react'
import type { Employee } from '@/types'

interface QuickEmployeeAccessProps {
  onClose: () => void
  onSaved?: (employee: Employee) => void
  /** When true, forces inline mode even if HR module is active (e.g. for quick pickers) */
  forceInline?: boolean
}

/**
 * Cross-module Quick Access for Employees.
 * - If HR module is active → shows a link to /hr/employees
 * - If HR module is NOT active → shows inline mini-CRUD (list + add form)
 *
 * Uses the same `employees` table and `getEmployees`/`createEmployee` queries
 * as the full HR module. No data duplication.
 */
export function QuickEmployeeAccess({ onClose, onSaved, forceInline }: QuickEmployeeAccessProps) {
  const { t } = useTranslation('crossModule')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const { getAccessStrategy } = useModuleAwareAccess()

  const strategy = forceInline ? 'inline' : getAccessStrategy('hr')
  const [employees, setEmployees] = useState<Employee[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [search, setSearch] = useState('')

  const [name, setName] = useState('')
  const [email, setEmail] = useState('')
  const [position, setPosition] = useState('')
  const [department, setDepartment] = useState('')
  const [saving, setSaving] = useState(false)

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      setEmployees(await getEmployees())
    } catch (err: any) { console.error("catch:", err); toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadError'))
      /* ignore */
    } finally {
      setLoading(false)
    }
  }, [tCommon, toast])

  useEffect(() => {
    if (strategy === 'inline') loadData().catch(err => console.error('loadData:', err))
  }, [strategy, loadData])

  async function handleSave(e: React.FormEvent) {
    e.preventDefault()
    if (!name.trim()) return
    setSaving(true)
    try {
      const emp = await createEmployee({
        name: name.trim(),
        email: email.trim(),
        phone: '',
        position: position.trim(),
        department: department.trim(),
        salary: 0,
        hire_date: new Date().toISOString().split('T')[0],
        status: 'active',
        contract_type: 'CDI',
      } as Omit<Employee, 'id' | 'created_at' | 'updated_at'>)
      toast('success', tCommon('common.success'), t('employee.created'))
      onSaved?.(emp)
      await loadData()
      setShowForm(false)
      setName(''); setEmail(''); setPosition(''); setDepartment('')
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || t('employee.createError'))
    } finally {
      setSaving(false)
    }
  }

  const filtered = employees.filter((e) =>
    !search || e.name.toLowerCase().includes(search.toLowerCase()) || e.email.toLowerCase().includes(search.toLowerCase()),
  )

  if (strategy === 'full' && !forceInline) {
    return (
      <QuickAccessModal title={t('employee.title')} onClose={onClose}>
        <EmptyState
          icon={<Users className="w-8 h-8" />}
          title={t('employee.moduleActive')}
          description={t('employee.moduleActiveDescription')}
          action={
            <Link to="/hr/employees" onClick={onClose}>
              <Button><ExternalLink className="w-4 h-4" /> {t('employee.goToHR')}</Button>
            </Link>
          }
        />
      </QuickAccessModal>
    )
  }

  return (
    <QuickAccessModal title={t('employee.title')} onClose={onClose}>
      <div className="space-y-4">
        <div className="flex items-center gap-2">
          <div className="relative flex-1">
            <Search className="w-4 h-4 absolute left-3 top-1/2 -translate-y-1/2 text-[var(--color-text-tertiary)]" />
            <input
              type="text"
              placeholder={t('employee.search')}
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              className="w-full pl-9 pr-3 py-2 text-sm border border-[var(--color-border)] rounded-lg bg-[var(--color-surface)] outline-none focus:border-[var(--color-primary)]"
            />
          </div>
          <Button size="sm" onClick={() => setShowForm(!showForm)}>
            <Plus className="w-4 h-4" /> {t('employee.add')}
          </Button>
        </div>

        {showForm && (
          <form onSubmit={handleSave} className="space-y-3 p-4 rounded-lg border border-[var(--color-border)] bg-[var(--color-neutral-50)]">
            <div className="grid grid-cols-2 gap-3">
              <Input label={t('employee.name')} required value={name} onChange={(e) => setName(e.target.value)} />
              <Input label={t('employee.email')} type="email" value={email} onChange={(e) => setEmail(e.target.value)} />
              <Input label={t('employee.position')} value={position} onChange={(e) => setPosition(e.target.value)} />
              <Input label={t('employee.department')} value={department} onChange={(e) => setDepartment(e.target.value)} />
            </div>
            <div className="flex justify-end gap-2">
              <Button type="button" variant="secondary" size="sm" onClick={() => setShowForm(false)}>{tCommon('actions.cancel')}</Button>
              <Button type="submit" size="sm" disabled={saving}>{saving ? '...' : tCommon('actions.save')}</Button>
            </div>
          </form>
        )}

        {loading ? (
          <p className="text-sm text-[var(--color-text-secondary)] text-center py-8">{tCommon('common.loading')}</p>
        ) : filtered.length === 0 ? (
          <EmptyState
            icon={<Users className="w-8 h-8" />}
            title={t('employee.noEmployees')}
            description={t('employee.noEmployeesDescription')}
            action={<Button size="sm" onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('employee.add')}</Button>}
          />
        ) : (
          <Table headers={[t('employee.name'), t('employee.position'), t('employee.department'), tCommon('common.status')]}>
            {filtered.slice(0, 20).map((e) => (
              <TableRow key={e.id}>
                <TableCell className="font-medium">{e.name}</TableCell>
                <TableCell className="text-sm">{e.position || '—'}</TableCell>
                <TableCell className="text-sm">{e.department || '—'}</TableCell>
                <TableCell>
                  <Badge variant={e.status === 'active' ? 'success' : e.status === 'on_leave' ? 'warning' : 'neutral'}>
                    {tCommon(`status.${e.status}`)}
                  </Badge>
                </TableCell>
              </TableRow>
            ))}
          </Table>
        )}
        {filtered.length > 20 && (
          <p className="text-xs text-[var(--color-text-tertiary)] text-center">
            {t('employee.showingCount', { count: 20, total: filtered.length })}
          </p>
        )}
      </div>
    </QuickAccessModal>
  )
}
