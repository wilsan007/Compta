import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { getEmployees, createEmployee, updateEmployee, deleteEmployee } from '@/lib/queries'
import { formatCurrency, formatDate } from '@/lib/utils'
import { Users, Plus, Trash2, X } from 'lucide-react'
import type { Employee } from '@/types'
import { useToast } from '@/lib/toast'
import { useStatusLabels } from '@/lib/statusUtils'

export function EmployeesPage() {
  const { toast } = useToast()
  const { t } = useTranslation('hr')
  const { t: tCommon } = useTranslation('common')
  const { t: tNav } = useTranslation('nav')
  const { getStatusLabel } = useStatusLabels()
const [employees, setEmployees] = useState<Employee[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [filterDept, setFilterDept] = useState('')

  const loadData = useCallback(async () => {
    setLoading(true)
    try { setEmployees(await getEmployees()) } catch (err) { console.error(err); toast('error', tCommon('common.error'), tCommon('common.error')) } finally { setLoading(false) }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  async function handleDelete(id: string) {
  if (!window.confirm(tCommon('form.confirmDelete'))) return
    try { await deleteEmployee(id); await loadData() } catch (err: any) { toast('error', tCommon('common.error'), err.message || tCommon('common.error')) }
  }

  async function handleStatusChange(id: string, status: string) {
    try { await updateEmployee(id, { status: status as any }); await loadData() } catch (err: any) { toast('error', tCommon('common.error'), err.message || tCommon('common.error')) }
  }

  const departments = [...new Set(employees.map(e => e.department).filter(Boolean))]
  const filtered = filterDept ? employees.filter(e => e.department === filterDept) : employees
  const totalPayroll = employees.filter(e => e.status === 'active').reduce((s, e) => s + Number(e.salary), 0)

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('sections.hr') }, { label: t('employees.title') }]} />
      <PageHeader
        title={t('employees.title')}
        subtitle={t('employees.subtitle')}
        action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('employees.new')}</Button>}
      />

      <div className="grid grid-cols-3 gap-4 mb-6">
        <Card><div className="p-4"><p className="text-sm text-[var(--color-text-secondary)]">{t('dashboard.totalEmployees')}</p><p className="text-2xl font-bold">{employees.length}</p></div></Card>
        <Card><div className="p-4"><p className="text-sm text-[var(--color-text-secondary)]">{t('dashboard.activeEmployees')}</p><p className="text-2xl font-bold text-[var(--color-success)]">{employees.filter(e => e.status === 'active').length}</p></div></Card>
        <Card><div className="p-4"><p className="text-sm text-[var(--color-text-secondary)]">{t('dashboard.payrollTotal')}</p><p className="text-2xl font-bold font-mono">{formatCurrency(totalPayroll)}</p></div></Card>
      </div>

      <div className="mb-4 flex items-center gap-3">
        <Select value={filterDept} onChange={(e) => setFilterDept(e.target.value)} className="max-w-xs" options={[
          { value: '', label: tCommon('all') },
          ...departments.map(d => ({ value: d, label: d })),
        ]} />
        <span className="text-sm text-[var(--color-text-secondary)]">{filtered.length} {t('employees.title').toLowerCase()}</span>
      </div>

      {loading ? (
        <SkeletonTable rows={5} cols={6} />
      ) : filtered.length === 0 ? (
        <EmptyState icon={<Users className="w-8 h-8" />} title={t('employees.noEmployees')} description={t('employees.noEmployeesDescription')} action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('employees.new')}</Button>} />
      ) : (
        <Card>
          <Table headers={[t('employees.fullName'), t('employees.position'), t('employees.department'), t('employees.salary'), t('employees.hireDate'), t('employees.status'), tCommon('table.actions')]}>
            {filtered.map((e) => (
              <TableRow key={e.id}>
                <TableCell className="font-medium">{e.name}</TableCell>
                <TableCell className="text-sm">{e.position || '—'}</TableCell>
                <TableCell className="text-sm">{e.department || '—'}</TableCell>
                <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(e.salary))}</TableCell>
                <TableCell className="text-xs">{formatDate(e.hire_date)}</TableCell>
                <TableCell>
                  <select value={e.status} onChange={(ev) => handleStatusChange(e.id, ev.target.value)} className="text-xs border border-[var(--color-border)] rounded px-2 py-1 bg-[var(--color-surface)]">
                    {['active', 'inactive', 'on_leave'].map((k) => <option key={k} value={k}>{getStatusLabel(k)}</option>)}
                  </select>
                </TableCell>
                <TableCell>
                  <button onClick={() => handleDelete(e.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]"><Trash2 className="w-4 h-4" /></button>
                </TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}

      {showForm && <EmployeeForm onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadData() }} />}
    </div>
  )
}

function EmployeeForm({ onClose, onSaved }: { onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation('hr')
  const { t: tCommon } = useTranslation('common')
  const [name, setName] = useState('')
  const { toast } = useToast()
  const [email, setEmail] = useState('')
  const [phone, setPhone] = useState('')
  const [position, setPosition] = useState('')
  const [department, setDepartment] = useState('')
  const [salary, setSalary] = useState(0)
  const [hireDate, setHireDate] = useState(new Date().toISOString().split('T')[0])
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      await createEmployee({ name, email, phone, position, department, salary, hire_date: hireDate, status: 'active' } as any)
      onSaved()
    } catch (err: any) { toast('error', tCommon('common.error'), err.message || tCommon('common.error')) } finally { setSaving(false) }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '36rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('employees.new')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <Input label={t('employees.fullName')} required value={name} onChange={(e) => setName(e.target.value)} />
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('employees.email')} type="email" value={email} onChange={(e) => setEmail(e.target.value)} />
            <Input label={t('employees.phone')} value={phone} onChange={(e) => setPhone(e.target.value)} />
          </div>
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('employees.position')} value={position} onChange={(e) => setPosition(e.target.value)} />
            <Input label={t('employees.department')} value={department} onChange={(e) => setDepartment(e.target.value)} />
          </div>
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('employees.salary')} type="number" step="0.01" value={salary} onChange={(e) => setSalary(Number(e.target.value))} />
            <Input label={t('employees.hireDate')} type="date" value={hireDate} onChange={(e) => setHireDate(e.target.value)} />
          </div>
          <div className="flex justify-end gap-3 pt-4 border-t border-[var(--color-border)]">
            <Button type="button" variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? '...' : tCommon('actions.save')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
