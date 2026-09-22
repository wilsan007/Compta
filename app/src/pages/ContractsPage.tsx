import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { formatCurrency, formatDate } from '@/lib/utils'
import { getContracts, createContract, updateContract, deleteContract, getEmployees } from '@/lib/queries/payroll'
import { FileSignature, Plus, Trash2, X } from 'lucide-react'
import type { Employee } from '@/types'
import { useToast } from '@/lib/toast'
import { useStatusLabels } from '@/lib/statusUtils'
import { confirmSync } from '@/lib/confirm'
import { nextDocumentNumber } from '@/lib/queries/core'

const contractTypeKeys: Record<string, string> = { cdi: 'cdi', cdd: 'cdd', apprentissage: 'apprentissage', stage: 'stage', interim: 'interim', freelance: 'freelance' }

export function ContractsPage() {
  const { toast } = useToast()
  const { t } = useTranslation('hr')
  const { t: tCommon } = useTranslation('common')
  const { t: tNav } = useTranslation('nav')
  const { getStatusLabel } = useStatusLabels()
const [contracts, setContracts] = useState<any[]>([])
  const [employees, setEmployees] = useState<Employee[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [typeFilter, setTypeFilter] = useState('')

  const loadData = useCallback(async () => {
    try {
      const [cs, emps] = await Promise.all([getContracts(), getEmployees()])
      setContracts(cs || [])
      setEmployees(emps || [])
    } catch (err: any) { console.error('Error:', err); toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadingError')) }
    finally { setLoading(false) }
  }, [toast, tCommon])

  useEffect(() => { loadData() }, [loadData])

  async function handleStatusChange(id: string, status: string) {
  try { await updateContract(id, { status: status as any }); await loadData() }
    catch (err: any) { toast('error', tCommon('common.error'), err.message || tCommon('common.error')) }
  }

  async function handleDelete(id: string) {
    if (!confirmSync(tCommon('form.confirmDelete'))) return
    try { await deleteContract(id); await loadData() }
    catch (err: any) { toast('error', tCommon('common.error'), err.message || tCommon('common.error')) }
  }

  const filtered = typeFilter ? contracts.filter((c) => c.contract_type === typeFilter) : contracts

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('groups.hr') }, { label: t('contracts.title') }]} />
      <PageHeader title={t('contracts.title')} subtitle={t('contracts.subtitle')}
        action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('contracts.new')}</Button>} />

      <div className="flex gap-3 mb-4 items-end">
        <div className="w-48">
          <Select label={t('contracts.type')} value={typeFilter} onChange={(e) => setTypeFilter(e.target.value)} options={[
            { value: '', label: tCommon('table.all') }, ...Object.entries(contractTypeKeys).map(([k, v]) => ({ value: k, label: t(`contracts.types.${v}`) as string })),
          ]} />
        </div>
      </div>

      {loading ? <SkeletonTable rows={5} cols={7} /> : filtered.length === 0 ? (
        <EmptyState icon={<FileSignature className="w-8 h-8" />} title={t('contracts.noContracts')} description={t('contracts.noContractsDescription')}
          action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('contracts.new')}</Button>} />
      ) : (
        <Card>
          <Table headers={[t('payRuns.number'), t('contracts.employee'), t('contracts.type'), t('contracts.startDate'), t('contracts.endDate'), t('contracts.salary'), t('contracts.workingHours'), t('contracts.status'), tCommon('table.actions')]}>
            {filtered.map((c) => (
              <TableRow key={c.id}>
                <TableCell className="font-mono text-xs">{c.number}</TableCell>
                <TableCell className="text-sm">{c.employees?.name || '—'}</TableCell>
                <TableCell className="text-xs">{t(`contracts.types.${c.contract_type}`) || c.contract_type}</TableCell>
                <TableCell className="text-xs">{formatDate(c.start_date)}</TableCell>
                <TableCell className="text-xs">{c.end_date ? formatDate(c.end_date) : '—'}</TableCell>
                <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(c.monthly_salary))}</TableCell>
                <TableCell className="font-mono text-xs">{Number(c.weekly_hours)}h</TableCell>
                <TableCell>
                  <select value={c.status} onChange={(e) => handleStatusChange(c.id, e.target.value)}
                    className="text-xs border border-[var(--color-border)] rounded px-2 py-1 bg-[var(--color-surface)]">
                    {['active', 'ended', 'suspended', 'terminated'].map((k) => <option key={k} value={k}>{getStatusLabel(k)}</option>)}
                  </select>
                </TableCell>
                <TableCell>
                  <button onClick={() => handleDelete(c.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]" aria-label={tCommon('actions.delete')} title={tCommon('actions.delete')}>
                    <Trash2 className="w-4 h-4" aria-hidden="true" /></button>
                </TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}

      {showForm && <ContractForm employees={employees} onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadData() }} />}
    </div>
  )
}

function ContractForm({ employees, onClose, onSaved }: { employees: Employee[]; onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation('hr')
  const { t: tCommon } = useTranslation('common')
  const [employeeId, setEmployeeId] = useState('')
  const { toast } = useToast()
  const [contractType, setContractType] = useState('cdi')
  const [startDate, setStartDate] = useState(new Date().toISOString().split('T')[0])
  const [endDate, setEndDate] = useState('')
  const [position, setPosition] = useState('')
  const [department, setDepartment] = useState('')
  const [monthlySalary, setMonthlySalary] = useState(0)
  const [weeklyHours, setWeeklyHours] = useState(35)
  const [trialPeriodDays, setTrialPeriodDays] = useState(0)
  const [notes, setNotes] = useState('')
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      const number = await nextDocumentNumber('CTR')
      await createContract({
        number, employee_id: employeeId, contract_type: contractType as any,
        start_date: startDate, end_date: endDate || null,
        position: position || null, department: department || null,
        monthly_salary: monthlySalary, hourly_rate: 0, weekly_hours: weeklyHours,
        trial_period_days: trialPeriodDays, status: 'active', notes: notes || null,
      } as any)
      onSaved()
    } catch (err: any) { toast('error', tCommon('common.error'), err.message || tCommon('common.error')) }
    finally { setSaving(false) }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl overflow-hidden" style={{ width: '100%', maxWidth: '36rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('contracts.new')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]" aria-label={tCommon('actions.close')} title={tCommon('actions.close')}><X className="w-5 h-5" aria-hidden="true" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('contracts.employee')}</label>
            <select className="input" value={employeeId} onChange={(e) => { setEmployeeId(e.target.value); const emp = employees.find((em) => em.id === e.target.value); if (emp) { setPosition(emp.position); setDepartment(emp.department); setMonthlySalary(Number(emp.salary)) } }} required>
              <option value="">{tCommon('form.selectPlaceholder') || '—'}</option>
              {employees.map((emp) => <option key={emp.id} value={emp.id}>{emp.name}</option>)}
            </select>
          </div>
          <div className="grid grid-cols-2 gap-4">
            <Select label={t('contracts.type')} value={contractType} onChange={(e) => setContractType(e.target.value)} options={[
              { value: 'cdi', label: t('contracts.types.cdi') }, { value: 'cdd', label: t('contracts.types.cdd') }, { value: 'apprentissage', label: t('contracts.types.apprentissage') },
              { value: 'stage', label: t('contracts.types.stage') }, { value: 'interim', label: t('contracts.types.interim') }, { value: 'freelance', label: t('contracts.types.freelance') },
            ]} />
            <Input label={t('contracts.trialPeriod')} type="number" value={trialPeriodDays} onChange={(e) => setTrialPeriodDays(Number(e.target.value))} />
          </div>
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('contracts.startDate')} type="date" required value={startDate} onChange={(e) => setStartDate(e.target.value)} />
            <Input label={t('contracts.endDate')} type="date" value={endDate} onChange={(e) => setEndDate(e.target.value)} />
          </div>
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('contracts.position')} value={position} onChange={(e) => setPosition(e.target.value)} />
            <Input label={t('contracts.department')} value={department} onChange={(e) => setDepartment(e.target.value)} />
          </div>
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('contracts.salary')} type="number" step="0.01" value={monthlySalary} onChange={(e) => setMonthlySalary(Number(e.target.value))} />
            <Input label={t('contracts.workingHours')} type="number" step="0.1" value={weeklyHours} onChange={(e) => setWeeklyHours(Number(e.target.value))} />
          </div>
          <Input label={tCommon('common.notes')} value={notes} onChange={(e) => setNotes(e.target.value)} />
          <div className="flex justify-end gap-3 pt-2">
            <Button variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? tCommon('actions.saving') : tCommon('actions.save')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
