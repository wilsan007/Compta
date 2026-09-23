import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Input, Select, Badge } from '@/components/ui'
import { getExitProcesses, createExitProcess } from '@/lib/queries/sprintDE'
import { getEmployees } from '@/lib/queries/payroll'
import { calculateSeverancePay, calculateNoticeCompensation } from '@/lib/queries/businessFunctions'
import { formatDate, formatCurrency } from '@/lib/utils'
import { LogOut, Plus, X, ChevronRight, FileText, Send, CheckCircle } from 'lucide-react'
import type { Employee } from '@/types'
import { useToast } from '@/lib/toast'

const statusColors: Record<string, 'warning' | 'success' | 'neutral'> = {
  in_progress: 'warning',
  completed: 'success',
  cancelled: 'neutral',
}

export function EmployeeExitPage() {
  const { toast } = useToast()
  const { t } = useTranslation('hr')
  const { t: tCommon } = useTranslation('common')
  const { t: tNav } = useTranslation('nav')
  const [processes, setProcesses] = useState<any[]>([])
  const [employees, setEmployees] = useState<Employee[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [selectedProcess, setSelectedProcess] = useState<any>(null)

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const [procs, emps] = await Promise.all([getExitProcesses(), getEmployees()])
      setProcesses(procs || [])
      setEmployees(emps || [])
    } catch (err: any) {
      console.error(err)
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    } finally { setLoading(false) }
  }, [toast, tCommon])

  useEffect(() => { loadData() }, [loadData])

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('groups.hr') }, { label: t('exit.title') }]} />
      <PageHeader
        title={t('exit.title')}
        subtitle={t('exit.subtitle')}
        action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('exit.new')}</Button>}
      />

      {loading ? (
        <SkeletonTable rows={4} cols={6} />
      ) : processes.length === 0 ? (
        <EmptyState
          icon={<LogOut className="w-8 h-8" />}
          title={t('exit.noRecords')}
          description={t('exit.noRecordsDescription')}
          action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('exit.new')}</Button>}
        />
      ) : selectedProcess ? (
        <ExitWizard
          process={selectedProcess}
          onClose={() => { setSelectedProcess(null); loadData() }}
        />
      ) : (
        <Card>
          <Table headers={[
            t('exit.employee'),
            t('exit.exitDate'),
            t('exit.exitReason'),
            t('exit.step'),
            t('exit.status'),
            tCommon('table.actions'),
          ]}>
            {processes.map((p) => (
              <TableRow key={p.id} onClick={() => setSelectedProcess(p)}>
                <TableCell className="text-sm font-medium">
                  {p.employees ? `${p.employees.first_name} ${p.employees.last_name}` : '—'}
                </TableCell>
                <TableCell className="text-xs">{formatDate(p.exit_date)}</TableCell>
                <TableCell className="text-sm">{t(`exit.reasons.${p.exit_reason}`)}</TableCell>
                <TableCell className="font-mono text-xs text-center">{p.step}/6</TableCell>
                <TableCell><Badge variant={statusColors[p.status] || 'neutral'}>{t(`exit.statuses.${p.status}`)}</Badge></TableCell>
                <TableCell>
                  <ChevronRight className="w-4 h-4 text-[var(--color-text-secondary)]" />
                </TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}

      {showForm && (
        <ExitStartForm
          employees={employees}
          onClose={() => setShowForm(false)}
          onSaved={() => { setShowForm(false); loadData() }}
        />
      )}
    </div>
  )
}

function ExitStartForm({ employees, onClose, onSaved }: { employees: Employee[]; onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation('hr')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [employeeId, setEmployeeId] = useState('')
  const [exitDate, setExitDate] = useState('')
  const [exitReason, setExitReason] = useState('resignation')
  const [saving, setSaving] = useState(false)
  const [severance, setSeverance] = useState<number | null>(null)
  const [calcLoading, setCalcLoading] = useState(false)
  const [noticeComp, setNoticeComp] = useState<number | null>(null)
  const [noticeLoading, setNoticeLoading] = useState(false)

  async function handleCalcSeverance() {
    if (!employeeId) { toast('error', tCommon('common.error'), t('exit.selectEmployee')); return }
    if (!exitDate) { toast('error', tCommon('common.error'), t('exit.exitDate')); return }
    setCalcLoading(true)
    try {
      const res = await calculateSeverancePay(employeeId, exitDate)
      const amount = Number(res) || 0
      setSeverance(amount)
      toast('success', tCommon('common.success'), `${'Indemnité de rupture'}: ${formatCurrency(amount)}`)
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    } finally { setCalcLoading(false) }
  }

  async function handleCalcNoticeComp() {
    if (!employeeId) { toast('error', tCommon('common.error'), t('exit.selectEmployee')); return }
    setNoticeLoading(true)
    try {
      const res = await calculateNoticeCompensation(employeeId)
      const amount = Number(res?.amount ?? res?.notice_compensation ?? res ?? 0)
      setNoticeComp(amount)
      toast('success', tCommon('common.success'), `Indemnité de préavis: ${formatCurrency(amount)}`)
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    } finally { setNoticeLoading(false) }
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!employeeId) { toast('error', tCommon('common.error'), t('exit.selectEmployee')); return }
    setSaving(true)
    try {
      await createExitProcess(employeeId, exitDate, exitReason)
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
          <h2 className="text-lg font-semibold">{t('exit.new')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]" aria-label={tCommon('actions.close')} title={tCommon('actions.close')}><X className="w-5 h-5" aria-hidden="true" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('exit.selectEmployee')}</label>
            <select className="input" value={employeeId} onChange={(e) => setEmployeeId(e.target.value)} required>
              <option value="">{tCommon('form.selectPlaceholder') || '—'}</option>
              {employees.filter(e => e.status !== 'inactive').map((e) => <option key={e.id} value={e.id}>{e.name}</option>)}
            </select>
          </div>
          <Input label={t('exit.exitDate')} type="date" value={exitDate} onChange={(e) => setExitDate(e.target.value)} required />
          <Select label={t('exit.exitReason')} value={exitReason} onChange={(e) => setExitReason(e.target.value)} options={[
            { value: 'resignation', label: t('exit.reasons.resignation') },
            { value: 'dismissal', label: t('exit.reasons.dismissal') },
            { value: 'end_cdd', label: t('exit.reasons.end_cdd') },
            { value: 'retirement', label: t('exit.reasons.retirement') },
            { value: 'mutual_agreement', label: t('exit.reasons.mutual_agreement') },
            { value: 'probation_fail', label: t('exit.reasons.probation_fail') },
          ]} />
          <div className="flex justify-end gap-3 pt-4 border-t border-[var(--color-border)]">
            <Button type="button" variant="secondary" onClick={handleCalcSeverance} disabled={calcLoading}>
              {calcLoading ? tCommon('actions.saving') : 'Calculer l\'indemnité de rupture'}
            </Button>
            <Button type="button" variant="secondary" onClick={handleCalcNoticeComp} disabled={noticeLoading}>
              {noticeLoading ? tCommon('actions.saving') : 'Calculer l\'indemnité de préavis'}
            </Button>
            <Button type="button" variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? tCommon('actions.saving') : tCommon('actions.save')}</Button>
          </div>
          {severance !== null && (
            <div className="mt-2 p-3 rounded bg-[var(--color-neutral-100)] text-sm">
              <strong>Indemnité de rupture:</strong> <span className="font-mono">{formatCurrency(severance)}</span>
            </div>
          )}
          {noticeComp !== null && (
            <div className="mt-2 p-3 rounded bg-[var(--color-neutral-100)] text-sm">
              <strong>Indemnité de préavis:</strong> <span className="font-mono">{formatCurrency(noticeComp)}</span>
            </div>
          )}
        </form>
      </div>
    </div>
  )
}

function ExitWizard({ process, onClose }: { process: any; onClose: () => void }) {
  const { t } = useTranslation('hr')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [currentStep, setCurrentStep] = useState(process.step || 1)
  const [working, setWorking] = useState(false)

  const steps = [t('exit.step1'), t('exit.step2'), t('exit.step3'), t('exit.step4'), t('exit.step5'), t('exit.step6')]

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <div>
          <h2 className="text-lg font-semibold">{t('exit.title')} — {process.employees ? `${process.employees.first_name} ${process.employees.last_name}` : ''}</h2>
          <p className="text-sm text-[var(--color-text-secondary)]">{t('exit.exitDate')}: {formatDate(process.exit_date)}</p>
        </div>
        <Button variant="secondary" onClick={onClose}>{tCommon('actions.close')}</Button>
      </div>

      <div className="flex items-center gap-2 mb-6">
        {steps.map((_label, i) => (
          <div key={i} className="flex items-center">
            <div className={`flex items-center justify-center w-8 h-8 rounded-full text-xs font-medium ${i + 1 <= currentStep ? 'bg-[var(--color-primary)] text-white' : 'bg-[var(--color-neutral-100)] text-[var(--color-text-secondary)]'}`}>
              {i + 1}
            </div>
            {i < steps.length - 1 && <div className={`w-12 h-0.5 ${i + 1 < currentStep ? 'bg-[var(--color-primary)]' : 'bg-[var(--color-neutral-200)]'}`} />}
          </div>
        ))}
      </div>

      <Card title={steps[currentStep - 1]}>
        <div className="p-4 space-y-4">
          {currentStep === 1 && (
            <div className="space-y-2">
              <p className="text-sm"><strong>{t('exit.employee')}:</strong> {process.employees ? `${process.employees.first_name} ${process.employees.last_name}` : '—'}</p>
              <p className="text-sm"><strong>{t('exit.exitDate')}:</strong> {formatDate(process.exit_date)}</p>
              <p className="text-sm"><strong>{t('exit.exitReason')}:</strong> {t(`exit.reasons.${process.exit_reason}`)}</p>
              <Button onClick={() => setCurrentStep(2)}>{tCommon('actions.next')}</Button>
            </div>
          )}
          {currentStep === 2 && (
            <div className="space-y-2">
              <p className="text-sm text-[var(--color-text-secondary)]">{t('exit.step2Description')}</p>
              <Button onClick={() => setCurrentStep(3)}>{tCommon('actions.next')}</Button>
            </div>
          )}
          {currentStep === 3 && (
            <div className="space-y-3">
              <div className="grid grid-cols-2 gap-2 text-sm">
                <div>{t('exit.cpIndemnity')}</div><div className="font-mono text-right">{process.cp_indemnity || 0}</div>
                <div>{t('exit.rttIndemnity')}</div><div className="font-mono text-right">{process.rtt_indemnity || 0}</div>
                <div>{t('exit.recoveryIndemnity')}</div><div className="font-mono text-right">{process.recovery_indemnity || 0}</div>
                <div>{t('exit.bonusAmount')}</div><div className="font-mono text-right">{process.bonus_amount || 0}</div>
                <div>{t('exit.advanceDeduction')}</div><div className="font-mono text-right">{process.advance_deduction || 0}</div>
                <div>{t('exit.overtimeAmount')}</div><div className="font-mono text-right">{process.overtime_amount || 0}</div>
                <div className="border-t pt-2 font-medium">{t('exit.totalGross')}</div><div className="border-t pt-2 font-mono text-right font-medium">{process.total_gross || 0}</div>
                <div className="font-medium">{t('exit.totalNet')}</div><div className="font-mono text-right font-medium">{process.total_net || 0}</div>
              </div>
              <Button onClick={() => setCurrentStep(4)}>{tCommon('actions.next')}</Button>
            </div>
          )}
          {currentStep === 4 && (
            <div className="space-y-3">
              <Button variant="secondary" onClick={async () => { setWorking(true); try { await import('@/lib/queries').then(m => m.generateExitDocuments(process.id)); toast('success', tCommon('common.success'), tCommon('common.saved')); } catch(e:any) { toast('error', tCommon('common.error'), e.message) } finally { setWorking(false) } }} disabled={working}>
                <FileText className="w-4 h-4" /> {t('exit.generateDocuments')}
              </Button>
              <Button onClick={() => setCurrentStep(5)}>{tCommon('actions.next')}</Button>
            </div>
          )}
          {currentStep === 5 && (
            <div className="space-y-3">
              <Button variant="secondary" onClick={async () => { setWorking(true); try { await import('@/lib/queries').then(m => m.markDsnExitGenerated(process.id)); toast('success', tCommon('common.success'), tCommon('common.saved')); } catch(e:any) { toast('error', tCommon('common.error'), e.message) } finally { setWorking(false) } }} disabled={working}>
                <FileText className="w-4 h-4" /> {t('exit.generateDsnExit')}
              </Button>
              <Button variant="secondary" onClick={async () => { setWorking(true); try { await import('@/lib/queries').then(m => m.transmitDsnExit(process.id)); toast('success', tCommon('common.success'), tCommon('common.saved')); } catch(e:any) { toast('error', tCommon('common.error'), e.message) } finally { setWorking(false) } }} disabled={working}>
                <Send className="w-4 h-4" /> {t('exit.transmitDsnExit')}
              </Button>
              <Button onClick={() => setCurrentStep(6)}>{tCommon('actions.next')}</Button>
            </div>
          )}
          {currentStep === 6 && (
            <div className="space-y-3">
              <p className="text-sm text-[var(--color-text-secondary)]">{t('exit.step6Description')}</p>
              <Button onClick={async () => { setWorking(true); try { await import('@/lib/queries').then(m => m.completeExitProcess(process.id)); toast('success', tCommon('common.success'), t('exit.complete')); onClose(); } catch(e:any) { toast('error', tCommon('common.error'), e.message) } finally { setWorking(false) } }} disabled={working}>
                <CheckCircle className="w-4 h-4" /> {t('exit.validate')}
              </Button>
            </div>
          )}
        </div>
      </Card>
    </div>
  )
}
