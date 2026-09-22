import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { getWorkHardship, createWorkHardship, deleteWorkHardship, getEmployees } from '@/lib/queries/payroll'
import { formatDate } from '@/lib/utils'
import { AlertTriangle, Plus, Trash2, X } from 'lucide-react'
import type { Employee, WorkHardship } from '@/types'
import { useToast } from '@/lib/toast'
import { confirmSync } from '@/lib/confirm'

const exposureLevelColors: Record<string, string> = {
  low: 'var(--color-success)',
  medium: 'var(--color-warning)',
  high: 'var(--color-danger)',
}

export function WorkHardshipPage() {
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
      const [wh, emps] = await Promise.all([getWorkHardship(), getEmployees()])
      setRecords(wh || [])
      setEmployees(emps || [])
    } catch (err: any) {
      console.error(err)
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    } finally { setLoading(false) }
  }, [toast, tCommon])

  useEffect(() => { loadData() }, [loadData])

  async function handleDelete(id: string) {
    if (!confirmSync(tCommon('form.confirmDelete'))) return
    try { await deleteWorkHardship(id); await loadData() }
    catch (err: any) { toast('error', tCommon('common.error'), err.message || tCommon('common.error')) }
  }

  const filtered = filterEmp ? records.filter((r) => r.employee_id === filterEmp) : records

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('groups.hr') }, { label: t('workHardship.title') }]} />
      <PageHeader
        title={t('workHardship.title')}
        subtitle={t('workHardship.subtitle')}
        action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('workHardship.new')}</Button>}
      />

      <div className="mb-4 flex items-end gap-3">
        <div className="w-64">
          <Select label={t('workHardship.employee')} value={filterEmp} onChange={(e) => setFilterEmp(e.target.value)} options={[
            { value: '', label: tCommon('table.all') },
            ...employees.map((e) => ({ value: e.id, label: e.name })),
          ]} />
        </div>
        <span className="text-sm text-[var(--color-text-secondary)]">{filtered.length} {t('workHardship.title').toLowerCase()}</span>
      </div>

      {loading ? (
        <SkeletonTable rows={4} cols={7} />
      ) : filtered.length === 0 ? (
        <EmptyState
          icon={<AlertTriangle className="w-8 h-8" />}
          title={t('workHardship.noRecords')}
          description={t('workHardship.noRecordsDescription')}
          action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('workHardship.new')}</Button>}
        />
      ) : (
        <Card>
          <Table headers={[
            t('workHardship.employee'),
            t('workHardship.exposureType'),
            t('workHardship.exposureLevel'),
            t('workHardship.startDate'),
            t('workHardship.endDate'),
            t('workHardship.points'),
            tCommon('table.actions'),
          ]}>
            {filtered.map((r) => (
              <TableRow key={r.id}>
                <TableCell className="text-sm font-medium">
                  {r.employees ? `${r.employees.first_name} ${r.employees.last_name}` : '—'}
                </TableCell>
                <TableCell className="text-sm">{r.exposure_type || '—'}</TableCell>
                <TableCell>
                  {r.exposure_level ? (
                    <span
                      className="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium"
                      style={{ color: exposureLevelColors[r.exposure_level] || 'var(--color-text-secondary)' }}
                    >
                      {t(`workHardship.levels.${r.exposure_level}`)}
                    </span>
                  ) : '—'}
                </TableCell>
                <TableCell className="text-xs">{r.start_date ? formatDate(r.start_date) : '—'}</TableCell>
                <TableCell className="text-xs">{r.end_date ? formatDate(r.end_date) : '—'}</TableCell>
                <TableCell className="font-mono text-xs text-right">{r.points ?? 0}</TableCell>
                <TableCell>
                  <button onClick={() => handleDelete(r.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]" aria-label={tCommon('actions.delete')} title={tCommon('actions.delete')}>
                    <Trash2 className="w-4 h-4" aria-hidden="true" /></button>
                </TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}

      {showForm && (
        <WorkHardshipForm
          employees={employees}
          onClose={() => setShowForm(false)}
          onSaved={() => { setShowForm(false); loadData() }}
        />
      )}
    </div>
  )
}

function WorkHardshipForm({ employees, onClose, onSaved }: { employees: Employee[]; onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation('hr')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [employeeId, setEmployeeId] = useState('')
  const [exposureType, setExposureType] = useState('')
  const [exposureLevel, setExposureLevel] = useState<'low' | 'medium' | 'high'>('low')
  const [startDate, setStartDate] = useState('')
  const [endDate, setEndDate] = useState('')
  const [points, setPoints] = useState(0)
  const [notes, setNotes] = useState('')
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!employeeId) { toast('error', tCommon('common.error'), t('workHardship.selectEmployee')); return }
    setSaving(true)
    try {
      await createWorkHardship({
        employee_id: employeeId,
        exposure_type: exposureType,
        exposure_level: exposureLevel,
        start_date: startDate || null,
        end_date: endDate || null,
        points,
        notes: notes || null,
      } as Omit<WorkHardship, 'id' | 'created_at'>)
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
          <h2 className="text-lg font-semibold">{t('workHardship.new')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]" aria-label={tCommon('actions.close')} title={tCommon('actions.close')}><X className="w-5 h-5" aria-hidden="true" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('workHardship.employee')}</label>
            <select className="input" value={employeeId} onChange={(e) => setEmployeeId(e.target.value)} required>
              <option value="">{tCommon('form.selectPlaceholder') || '—'}</option>
              {employees.map((e) => <option key={e.id} value={e.id}>{e.name}</option>)}
            </select>
          </div>
          <Input label={t('workHardship.exposureType')} value={exposureType} onChange={(e) => setExposureType(e.target.value)} placeholder={t('workHardship.exposureTypePlaceholder')} />
          <Select label={t('workHardship.exposureLevel')} value={exposureLevel} onChange={(e) => setExposureLevel(e.target.value as any)} options={[
            { value: 'low', label: t('workHardship.levels.low') },
            { value: 'medium', label: t('workHardship.levels.medium') },
            { value: 'high', label: t('workHardship.levels.high') },
          ]} />
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('workHardship.startDate')} type="date" value={startDate} onChange={(e) => setStartDate(e.target.value)} />
            <Input label={t('workHardship.endDate')} type="date" value={endDate} onChange={(e) => setEndDate(e.target.value)} />
          </div>
          <Input label={t('workHardship.points')} type="number" value={points} onChange={(e) => setPoints(Number(e.target.value))} />
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
