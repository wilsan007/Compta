import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { getCareerHistory, createCareerHistory, deleteCareerHistory, getEmployees } from '@/lib/queries'
import { formatCurrency, formatDate } from '@/lib/utils'
import { TrendingUp, Plus, Trash2, X } from 'lucide-react'
import type { Employee, CareerHistory } from '@/types'
import { useToast } from '@/lib/toast'

const changeTypeColors: Record<string, string> = {
  hire: 'var(--color-success)',
  promotion: 'var(--color-primary)',
  transfer: 'var(--color-warning)',
  salary_change: 'var(--color-info)',
  departure: 'var(--color-danger)',
}

export function CareerHistoryPage() {
  const { toast } = useToast()
  const { t } = useTranslation('hr')
  const { t: tCommon } = useTranslation('common')
  const { t: tNav } = useTranslation('nav')
  const [records, setRecords] = useState<any[]>([])
  const [employees, setEmployees] = useState<Employee[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [filterEmp, setFilterEmp] = useState('')

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const [ch, emps] = await Promise.all([getCareerHistory(), getEmployees()])
      setRecords(ch || [])
      setEmployees(emps || [])
    } catch (err: any) {
      console.error(err)
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    } finally { setLoading(false) }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  async function handleDelete(id: string) {
    if (!window.confirm(tCommon('form.confirmDelete'))) return
    try { await deleteCareerHistory(id); await loadData() }
    catch (err: any) { toast('error', tCommon('common.error'), err.message || tCommon('common.error')) }
  }

  const filtered = filterEmp ? records.filter((r) => r.employee_id === filterEmp) : records

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('sections.hr') }, { label: t('careerHistory.title') }]} />
      <PageHeader
        title={t('careerHistory.title')}
        subtitle={t('careerHistory.subtitle')}
        action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('careerHistory.new')}</Button>}
      />

      <div className="mb-4 flex items-end gap-3">
        <div className="w-64">
          <Select label={t('careerHistory.employee')} value={filterEmp} onChange={(e) => setFilterEmp(e.target.value)} options={[
            { value: '', label: tCommon('table.all') },
            ...employees.map((e) => ({ value: e.id, label: e.name })),
          ]} />
        </div>
        <span className="text-sm text-[var(--color-text-secondary)]">{filtered.length} {t('careerHistory.title').toLowerCase()}</span>
      </div>

      {loading ? (
        <SkeletonTable rows={4} cols={8} />
      ) : filtered.length === 0 ? (
        <EmptyState
          icon={<TrendingUp className="w-8 h-8" />}
          title={t('careerHistory.noRecords')}
          description={t('careerHistory.noRecordsDescription')}
          action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('careerHistory.new')}</Button>}
        />
      ) : (
        <Card>
          <Table headers={[
            t('careerHistory.employee'),
            t('careerHistory.position'),
            t('careerHistory.department'),
            t('careerHistory.changeType'),
            t('careerHistory.startDate'),
            t('careerHistory.endDate'),
            t('careerHistory.salary'),
            tCommon('table.actions'),
          ]}>
            {filtered.map((r) => (
              <TableRow key={r.id}>
                <TableCell className="text-sm font-medium">
                  {r.employees ? `${r.employees.first_name} ${r.employees.last_name}` : '—'}
                </TableCell>
                <TableCell className="text-sm">{r.position || '—'}</TableCell>
                <TableCell className="text-sm">{r.department || '—'}</TableCell>
                <TableCell>
                  {r.change_type ? (
                    <span className="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium" style={{ color: changeTypeColors[r.change_type] || 'var(--color-text-secondary)' }}>
                      {t(`careerHistory.changeTypes.${r.change_type}`)}
                    </span>
                  ) : '—'}
                </TableCell>
                <TableCell className="text-xs">{r.start_date ? formatDate(r.start_date) : '—'}</TableCell>
                <TableCell className="text-xs">{r.end_date ? formatDate(r.end_date) : '—'}</TableCell>
                <TableCell className="font-mono text-xs text-right">{r.salary ? formatCurrency(Number(r.salary)) : '—'}</TableCell>
                <TableCell>
                  <button onClick={() => handleDelete(r.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]">
                    <Trash2 className="w-4 h-4" />
                  </button>
                </TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}

      {showForm && (
        <CareerHistoryForm
          employees={employees}
          onClose={() => setShowForm(false)}
          onSaved={() => { setShowForm(false); loadData() }}
        />
      )}
    </div>
  )
}

function CareerHistoryForm({ employees, onClose, onSaved }: { employees: Employee[]; onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation('hr')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [employeeId, setEmployeeId] = useState('')
  const [position, setPosition] = useState('')
  const [department, setDepartment] = useState('')
  const [salary, setSalary] = useState(0)
  const [startDate, setStartDate] = useState(new Date().toISOString().split('T')[0])
  const [endDate, setEndDate] = useState('')
  const [changeType, setChangeType] = useState<'hire' | 'promotion' | 'transfer' | 'salary_change' | 'departure'>('hire')
  const [notes, setNotes] = useState('')
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!employeeId) { toast('error', tCommon('common.error'), t('careerHistory.selectEmployee')); return }
    setSaving(true)
    try {
      await createCareerHistory({
        employee_id: employeeId,
        position: position || null,
        department: department || null,
        salary: salary || null,
        start_date: startDate,
        end_date: endDate || null,
        change_type: changeType,
        notes: notes || null,
      } as Omit<CareerHistory, 'id' | 'created_at'>)
      toast('success', tCommon('common.success'), tCommon('common.saved'))
      onSaved()
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    } finally { setSaving(false) }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '36rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('careerHistory.new')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('careerHistory.employee')}</label>
            <select className="input" value={employeeId} onChange={(e) => {
              setEmployeeId(e.target.value)
              const emp = employees.find((em) => em.id === e.target.value)
              if (emp) { setPosition(emp.position || ''); setDepartment(emp.department || ''); setSalary(Number(emp.salary)) }
            }} required>
              <option value="">{tCommon('form.selectPlaceholder') || '—'}</option>
              {employees.map((e) => <option key={e.id} value={e.id}>{e.name}</option>)}
            </select>
          </div>
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('careerHistory.position')} value={position} onChange={(e) => setPosition(e.target.value)} />
            <Input label={t('careerHistory.department')} value={department} onChange={(e) => setDepartment(e.target.value)} />
          </div>
          <Select label={t('careerHistory.changeType')} value={changeType} onChange={(e) => setChangeType(e.target.value as any)} options={[
            { value: 'hire', label: t('careerHistory.changeTypes.hire') },
            { value: 'promotion', label: t('careerHistory.changeTypes.promotion') },
            { value: 'transfer', label: t('careerHistory.changeTypes.transfer') },
            { value: 'salary_change', label: t('careerHistory.changeTypes.salary_change') },
            { value: 'departure', label: t('careerHistory.changeTypes.departure') },
          ]} />
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('careerHistory.startDate')} type="date" required value={startDate} onChange={(e) => setStartDate(e.target.value)} />
            <Input label={t('careerHistory.endDate')} type="date" value={endDate} onChange={(e) => setEndDate(e.target.value)} />
          </div>
          <Input label={t('careerHistory.salary')} type="number" step="0.01" value={salary} onChange={(e) => setSalary(Number(e.target.value))} />
          <Input label={tCommon('common.notes')} value={notes} onChange={(e) => setNotes(e.target.value)} />
          <div className="flex justify-end gap-3 pt-4 border-t border-[var(--color-border)]">
            <Button type="button" variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? '...' : tCommon('actions.save')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
