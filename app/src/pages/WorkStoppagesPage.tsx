import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Input, Select, Badge } from '@/components/ui'
import { getWorkStoppages, createWorkStoppage, closeWorkStoppage, importBpij, regularizeIjss } from '@/lib/queries/sprintDE'
import { getEmployees } from '@/lib/queries/payroll'
import { formatDate } from '@/lib/utils'
import { HeartPulse, Plus, X, Upload, CheckCircle } from 'lucide-react'
import type { Employee } from '@/types'
import { useToast } from '@/lib/toast'

const statusColors: Record<string, 'success' | 'warning' | 'neutral'> = {
  active: 'warning',
  closed: 'success',
  regularized: 'neutral',
}

export function WorkStoppagesPage() {
  const { toast } = useToast()
  const { t } = useTranslation('hr')
  const { t: tCommon } = useTranslation('common')
  const { t: tNav } = useTranslation('nav')
  const [records, setRecords] = useState<any[]>([])
  const [employees, setEmployees] = useState<Employee[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [filterEmp, setFilterEmp] = useState('')
  const [filterStatus, setFilterStatus] = useState('')

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const [ws, emps] = await Promise.all([getWorkStoppages(), getEmployees()])
      setRecords(ws || [])
      setEmployees(emps || [])
    } catch (err: any) {
      console.error(err)
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    } finally { setLoading(false) }
  }, [toast, tCommon])

  useEffect(() => { loadData() }, [loadData])

  async function handleClose(id: string) {
    const repriseDate = window.prompt(t('workStoppages.repriseDate'))
    if (!repriseDate) return
    const repriseType = window.prompt(t('workStoppages.repriseType'), 'plein_temps') || 'plein_temps'
    try { await closeWorkStoppage(id, repriseDate, repriseType); await loadData(); toast('success', tCommon('common.success'), tCommon('common.saved')) }
    catch (err: any) { toast('error', tCommon('common.error'), err.message) }
  }

  async function handleImportBpij(id: string) {
    const bpijNumber = window.prompt(t('workStoppages.bpijNumber'))
    if (!bpijNumber) return
    const amountStr = window.prompt(t('workStoppages.ijssNet'))
    if (!amountStr) return
    try { await importBpij(id, bpijNumber, Number(amountStr)); await loadData(); toast('success', tCommon('common.success'), tCommon('common.saved')) }
    catch (err: any) { toast('error', tCommon('common.error'), err.message) }
  }

  async function handleRegularize(id: string) {
    const amountStr = window.prompt(t('workStoppages.regularizationAmount'))
    if (!amountStr) return
    try { await regularizeIjss(id, Number(amountStr)); await loadData(); toast('success', tCommon('common.success'), tCommon('common.saved')) }
    catch (err: any) { toast('error', tCommon('common.error'), err.message) }
  }

  const filtered = records.filter(r => {
    if (filterEmp && r.employee_id !== filterEmp) return false
    if (filterStatus && r.status !== filterStatus) return false
    return true
  })

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('sections.hr') }, { label: t('workStoppages.title') }]} />
      <PageHeader
        title={t('workStoppages.title')}
        subtitle={t('workStoppages.subtitle')}
        action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('workStoppages.new')}</Button>}
      />

      <div className="mb-4 flex items-end gap-3">
        <div className="w-64">
          <Select label={t('workStoppages.employee')} value={filterEmp} onChange={(e) => setFilterEmp(e.target.value)} options={[
            { value: '', label: tCommon('table.all') },
            ...employees.map((e) => ({ value: e.id, label: e.name })),
          ]} />
        </div>
        <div className="w-48">
          <Select label={t('workStoppages.status')} value={filterStatus} onChange={(e) => setFilterStatus(e.target.value)} options={[
            { value: '', label: tCommon('table.all') },
            { value: 'active', label: t('workStoppages.statuses.active') },
            { value: 'closed', label: t('workStoppages.statuses.closed') },
            { value: 'regularized', label: t('workStoppages.statuses.regularized') },
          ]} />
        </div>
        <span className="text-sm text-[var(--color-text-secondary)]">{filtered.length} {t('workStoppages.title').toLowerCase()}</span>
      </div>

      {loading ? (
        <SkeletonTable rows={4} cols={8} />
      ) : filtered.length === 0 ? (
        <EmptyState
          icon={<HeartPulse className="w-8 h-8" />}
          title={t('workStoppages.noRecords')}
          description={t('workStoppages.noRecordsDescription')}
          action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('workStoppages.new')}</Button>}
        />
      ) : (
        <Card>
          <Table headers={[
            t('workStoppages.employee'),
            t('workStoppages.stoppageType'),
            t('workStoppages.startDate'),
            t('workStoppages.endDate'),
            t('workStoppages.daysCount'),
            t('workStoppages.subrogation'),
            t('workStoppages.status'),
            tCommon('table.actions'),
          ]}>
            {filtered.map((r) => (
              <TableRow key={r.id}>
                <TableCell className="text-sm font-medium">
                  {r.employees ? `${r.employees.first_name} ${r.employees.last_name}` : '—'}
                </TableCell>
                <TableCell className="text-sm">{t(`workStoppages.types.${r.stoppage_type}`)}</TableCell>
                <TableCell className="text-xs">{formatDate(r.start_date)}</TableCell>
                <TableCell className="text-xs">{r.end_date ? formatDate(r.end_date) : '—'}</TableCell>
                <TableCell className="font-mono text-xs text-right">{r.days_count ?? '—'}</TableCell>
                <TableCell>{r.subrogation ? <Badge variant="success">{tCommon('common.yes')}</Badge> : <Badge variant="neutral">{tCommon('common.no')}</Badge>}</TableCell>
                <TableCell><Badge variant={statusColors[r.status] || 'neutral'}>{t(`workStoppages.statuses.${r.status}`)}</Badge></TableCell>
                <TableCell>
                  <div className="flex gap-1">
                    {r.status === 'active' && (
                      <>
                        <button onClick={() => handleImportBpij(r.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-info)]" title={t('workStoppages.importBpij')}>
                          <Upload className="w-4 h-4" />
                        </button>
                        <button onClick={() => handleClose(r.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-success)]" title={t('workStoppages.close')}>
                          <CheckCircle className="w-4 h-4" />
                        </button>
                      </>
                    )}
                    {r.status === 'closed' && (
                      <button onClick={() => handleRegularize(r.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-warning)]" title={t('workStoppages.regularize')}>
                        <CheckCircle className="w-4 h-4" />
                      </button>
                    )}
                  </div>
                </TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}

      {showForm && (
        <WorkStoppageForm
          employees={employees}
          onClose={() => setShowForm(false)}
          onSaved={() => { setShowForm(false); loadData() }}
        />
      )}
    </div>
  )
}

function WorkStoppageForm({ employees, onClose, onSaved }: { employees: Employee[]; onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation('hr')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [employeeId, setEmployeeId] = useState('')
  const [stoppageType, setStoppageType] = useState('maladie')
  const [startDate, setStartDate] = useState('')
  const [endDate, setEndDate] = useState('')
  const [expectedEnd, setExpectedEnd] = useState('')
  const [subrogation, setSubrogation] = useState(false)
  const [netGuarantee, setNetGuarantee] = useState(false)
  const [notes, setNotes] = useState('')
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!employeeId) { toast('error', tCommon('common.error'), t('workStoppages.selectEmployee')); return }
    setSaving(true)
    try {
      await createWorkStoppage({
        employee_id: employeeId,
        stoppage_type: stoppageType as any,
        start_date: startDate,
        end_date: endDate || null,
        expected_end_date: expectedEnd || null,
        reprise_date: null,
        reprise_type: null,
        days_count: null,
        working_days_count: null,
        subrogation,
        net_guarantee: netGuarantee,
        ijss_net_amount: 0,
        ijss_brut_amount: 0,
        ijss_daily_rate: 0,
        ijss_days_count: 0,
        ijss_care_days: 0,
        pas_days_count: 0,
        employer_maintenance_amount: 0,
        employer_maintenance_rate: 100,
        bpij_number: null,
        bpij_imported_at: null,
        regularization_amount: 0,
        regularization_type: null,
        medical_certificate_url: null,
        notes: notes || null,
        status: 'active',
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
          <h2 className="text-lg font-semibold">{t('workStoppages.new')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('workStoppages.employee')}</label>
            <select className="input" value={employeeId} onChange={(e) => setEmployeeId(e.target.value)} required>
              <option value="">{tCommon('form.selectPlaceholder') || '—'}</option>
              {employees.map((e) => <option key={e.id} value={e.id}>{e.name}</option>)}
            </select>
          </div>
          <Select label={t('workStoppages.stoppageType')} value={stoppageType} onChange={(e) => setStoppageType(e.target.value)} options={[
            { value: 'maladie', label: t('workStoppages.types.maladie') },
            { value: 'accident_travail', label: t('workStoppages.types.accident_travail') },
            { value: 'maladie_professionnelle', label: t('workStoppages.types.maladie_professionnelle') },
            { value: 'maternite', label: t('workStoppages.types.maternite') },
            { value: 'paternite', label: t('workStoppages.types.paternite') },
            { value: 'accident_vie_privee', label: t('workStoppages.types.accident_vie_privee') },
          ]} />
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('workStoppages.startDate')} type="date" value={startDate} onChange={(e) => setStartDate(e.target.value)} required />
            <Input label={t('workStoppages.endDate')} type="date" value={endDate} onChange={(e) => setEndDate(e.target.value)} />
          </div>
          <Input label={t('workStoppages.expectedEnd')} type="date" value={expectedEnd} onChange={(e) => setExpectedEnd(e.target.value)} />
          <div className="flex gap-6">
            <label className="flex items-center gap-2 text-sm">
              <input type="checkbox" checked={subrogation} onChange={(e) => setSubrogation(e.target.checked)} />
              {t('workStoppages.subrogation')}
            </label>
            <label className="flex items-center gap-2 text-sm">
              <input type="checkbox" checked={netGuarantee} onChange={(e) => setNetGuarantee(e.target.checked)} />
              {t('workStoppages.netGuarantee')}
            </label>
          </div>
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
