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
          <Table headers={[t('employees.fullName'), t('employees.employeeNumber'), t('employees.position'), t('employees.department'), t('employees.contractType'), t('employees.salary'), t('employees.hireDate'), t('employees.status'), tCommon('table.actions')]}>
            {filtered.map((e) => (
              <TableRow key={e.id}>
                <TableCell className="font-medium">{e.name}</TableCell>
                <TableCell className="font-mono text-xs">{e.employee_number || '—'}</TableCell>
                <TableCell className="text-sm">{e.position || '—'}</TableCell>
                <TableCell className="text-sm">{e.department || '—'}</TableCell>
                <TableCell className="text-sm">{e.contract_type || 'CDI'}</TableCell>
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
  const [employeeNumber, setEmployeeNumber] = useState('')
  const [ssNumber, setSsNumber] = useState('')
  const [birthDate, setBirthDate] = useState('')
  const [address, setAddress] = useState('')
  const [city, setCity] = useState('')
  const [postalCode, setPostalCode] = useState('')
  const [contractType, setContractType] = useState('CDI')
  const [contractEndDate, setContractEndDate] = useState('')

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      await createEmployee({
        name, email, phone, position, department, salary, hire_date: hireDate, status: 'active',
        employee_number: employeeNumber || null,
        social_security_number: ssNumber || null,
        birth_date: birthDate || null,
        address: address || null,
        city: city || null,
        postal_code: postalCode || null,
        contract_type: contractType as any,
        contract_end_date: contractEndDate || null,
      } as any)
      onSaved()
    } catch (err: any) { toast('error', tCommon('common.error'), err.message || tCommon('common.error')) } finally { setSaving(false) }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '42rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('employees.new')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4 max-h-[70vh] overflow-y-auto">
          <Input label={t('employees.fullName')} required value={name} onChange={(e) => setName(e.target.value)} />
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('employees.employeeNumber')} value={employeeNumber} onChange={(e) => setEmployeeNumber(e.target.value)} placeholder="MAT001" />
            <Input label={t('employees.ssNumber')} value={ssNumber} onChange={(e) => setSsNumber(e.target.value)} placeholder="1 23 45 67 890 123" />
          </div>
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
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('employees.birthDate')} type="date" value={birthDate} onChange={(e) => setBirthDate(e.target.value)} />
            <Select label={t('employees.contractType')} value={contractType} onChange={(e) => setContractType(e.target.value)} options={[
              { value: 'CDI', label: 'CDI' },
              { value: 'CDD', label: 'CDD' },
              { value: 'Apprentissage', label: t('employees.contractTypes.apprentissage') },
              { value: 'Stage', label: t('employees.contractTypes.stage') },
              { value: 'Interim', label: t('employees.contractTypes.interim') },
            ]} />
          </div>
          {contractType !== 'CDI' && (
            <Input label={t('employees.contractEndDate')} type="date" value={contractEndDate} onChange={(e) => setContractEndDate(e.target.value)} />
          )}
          <Input label={t('employees.address')} value={address} onChange={(e) => setAddress(e.target.value)} />
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('employees.postalCode')} value={postalCode} onChange={(e) => setPostalCode(e.target.value)} />
            <Input label={t('employees.city')} value={city} onChange={(e) => setCity(e.target.value)} />
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
