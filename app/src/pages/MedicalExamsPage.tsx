import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Input, Select, Badge } from '@/components/ui'
import { getMedicalExams, createMedicalExam, updateMedicalExam } from '@/lib/queries/sprintDE'
import { getEmployees } from '@/lib/queries/payroll'
import { formatDate } from '@/lib/utils'
import { Stethoscope, Plus, X, CheckCircle } from 'lucide-react'
import type { Employee } from '@/types'
import { useToast } from '@/lib/toast'

const resultColors: Record<string, 'success' | 'warning' | 'danger' | 'neutral'> = {
  apt: 'success',
  apt_with_restrictions: 'warning',
  unapt: 'danger',
  pending: 'neutral',
}

export function MedicalExamsPage() {
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
      const [exams, emps] = await Promise.all([getMedicalExams(), getEmployees()])
      setRecords(exams || [])
      setEmployees(emps || [])
    } catch (err: any) {
      console.error(err)
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    } finally { setLoading(false) }
  }, [toast, tCommon])

  useEffect(() => { loadData() }, [loadData])

  async function handleAddResult(id: string) {
    const result = window.prompt(t('medical.result'), 'apt')
    if (!result) return
    try {
      await updateMedicalExam(id, { result: result as any, completed_date: new Date().toISOString().split('T')[0] })
      await loadData()
      toast('success', tCommon('common.success'), tCommon('common.saved'))
    } catch (err: any) { toast('error', tCommon('common.error'), err.message) }
  }

  const filtered = filterEmp ? records.filter((r) => r.employee_id === filterEmp) : records

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('groups.hr') }, { label: t('medical.title') }]} />
      <PageHeader
        title={t('medical.title')}
        subtitle={t('medical.subtitle')}
        action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('medical.add')}</Button>}
      />

      <div className="mb-4 flex items-end gap-3">
        <div className="w-64">
          <Select label={t('medical.employee')} value={filterEmp} onChange={(e) => setFilterEmp(e.target.value)} options={[
            { value: '', label: tCommon('table.all') },
            ...employees.map((e) => ({ value: e.id, label: e.name })),
          ]} />
        </div>
        <span className="text-sm text-[var(--color-text-secondary)]">{filtered.length} {t('medical.title').toLowerCase()}</span>
      </div>

      {loading ? (
        <SkeletonTable rows={4} cols={7} />
      ) : filtered.length === 0 ? (
        <EmptyState
          icon={<Stethoscope className="w-8 h-8" />}
          title={t('medical.noRecords')}
          description={t('medical.noRecordsDescription')}
          action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('medical.add')}</Button>}
        />
      ) : (
        <Card>
          <Table headers={[
            t('medical.employee'),
            t('medical.examType'),
            t('medical.scheduledDate'),
            t('medical.completedDate'),
            t('medical.result'),
            t('medical.nextExam'),
            tCommon('table.actions'),
          ]}>
            {filtered.map((r) => (
              <TableRow key={r.id}>
                <TableCell className="text-sm font-medium">
                  {r.employees ? `${r.employees.first_name} ${r.employees.last_name}` : '—'}
                </TableCell>
                <TableCell className="text-sm">{t(`medical.types.${r.exam_type}`)}</TableCell>
                <TableCell className="text-xs">{formatDate(r.scheduled_date)}</TableCell>
                <TableCell className="text-xs">{r.completed_date ? formatDate(r.completed_date) : '—'}</TableCell>
                <TableCell>
                  {r.result ? <Badge variant={resultColors[r.result] || 'neutral'}>{t(`medical.results.${r.result}`)}</Badge> : '—'}
                </TableCell>
                <TableCell className="text-xs">{r.next_exam_date ? formatDate(r.next_exam_date) : '—'}</TableCell>
                <TableCell>
                  {!r.completed_date && (
                    <button onClick={() => handleAddResult(r.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-success)]" title={t('medical.addResult')}>
                      <CheckCircle className="w-4 h-4" />
                    </button>
                  )}
                </TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}

      {showForm && (
        <MedicalExamForm
          employees={employees}
          onClose={() => setShowForm(false)}
          onSaved={() => { setShowForm(false); loadData() }}
        />
      )}
    </div>
  )
}

function MedicalExamForm({ employees, onClose, onSaved }: { employees: Employee[]; onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation('hr')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [employeeId, setEmployeeId] = useState('')
  const [examType, setExamType] = useState('periodic')
  const [scheduledDate, setScheduledDate] = useState('')
  const [doctor, setDoctor] = useState('')
  const [notes, setNotes] = useState('')
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!employeeId) { toast('error', tCommon('common.error'), t('medical.selectEmployee')); return }
    setSaving(true)
    try {
      await createMedicalExam({
        employee_id: employeeId,
        exam_type: examType as any,
        scheduled_date: scheduledDate,
        completed_date: null,
        result: null,
        restrictions: null,
        next_exam_date: null,
        occupational_doctor: doctor || null,
        notes: notes || null,
      } as any)
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
          <h2 className="text-lg font-semibold">{t('medical.add')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]" aria-label={tCommon('actions.close')} title={tCommon('actions.close')}><X className="w-5 h-5" aria-hidden="true" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('medical.employee')}</label>
            <select className="input" value={employeeId} onChange={(e) => setEmployeeId(e.target.value)} required>
              <option value="">{tCommon('form.selectPlaceholder') || '—'}</option>
              {employees.map((e) => <option key={e.id} value={e.id}>{e.name}</option>)}
            </select>
          </div>
          <Select label={t('medical.examType')} value={examType} onChange={(e) => setExamType(e.target.value)} options={[
            { value: 'initial', label: t('medical.types.initial') },
            { value: 'periodic', label: t('medical.types.periodic') },
            { value: 'reprise', label: t('medical.types.reprise') },
            { value: 'post_hazard', label: t('medical.types.post_hazard') },
            { value: 'pre_employment', label: t('medical.types.pre_employment') },
          ]} />
          <Input label={t('medical.scheduledDate')} type="date" value={scheduledDate} onChange={(e) => setScheduledDate(e.target.value)} required />
          <Input label={t('medical.occupationalDoctor')} value={doctor} onChange={(e) => setDoctor(e.target.value)} />
          <Input label={tCommon('common.notes')} value={notes} onChange={(e) => setNotes(e.target.value)} />
          <div className="flex justify-end gap-3 pt-4 border-t border-[var(--color-border)]">
            <Button type="button" variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? tCommon('actions.saving') : tCommon('actions.save')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
