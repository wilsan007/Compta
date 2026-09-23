import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Input } from '@/components/ui'
import { getPayRuns, createPayRun, updatePayRun, deletePayRun, getEmployees } from '@/lib/queries/payroll'
import { generatePayrollJournal, payPayrollRun } from '@/lib/queries/misc'
import { formatCurrency, formatDate } from '@/lib/utils'
import { Calendar, Plus, Trash2, X, FileText, Banknote } from 'lucide-react'
import type { PayRun, Employee } from '@/types'
import { useToast } from '@/lib/toast'
import { confirmSync } from '@/lib/confirm'
import { PaymentDialog, type PaymentValues } from '@/components/PaymentDialog'

export function PayRunsPage() {
  const { toast } = useToast()
  const { t } = useTranslation('hr')
  const { t: tCommon } = useTranslation('common')
  const { t: tNav } = useTranslation('nav')
const [payRuns, setPayRuns] = useState<PayRun[]>([])
  const [employees, setEmployees] = useState<Employee[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  // R-04 : identifiant du lot en cours de versement (bouton désactivé pendant l'appel)
  const [paying, setPaying] = useState<string | null>(null)
  // R-08 (décision D-10) : le versement se saisit dans la fenêtre de règlement —
  // date et compte bancaire choisis, comme pour les factures. Sans elle, tout
  // partait au compte 512000 / journal BQ, à la date du jour.
  const [payRunToPay, setPayRunToPay] = useState<PayRun | null>(null)

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const [pr, e] = await Promise.all([getPayRuns(), getEmployees()])
      setPayRuns(pr)
      setEmployees(e)
    } catch (err) { console.error(err); toast('error', tCommon('common.error'), tCommon('common.error')) } finally { setLoading(false) }
  }, [toast, tCommon])

  useEffect(() => { loadData() }, [loadData])

  async function handleStatusChange(id: string, status: string) {
  try { await updatePayRun(id, { status: status as any }); await loadData() } catch (err: any) { toast('error', tCommon('common.error'), err.message || tCommon('common.error')) }
  }

  async function handleDelete(id: string) {
    if (!confirmSync(tCommon('form.confirmDelete'))) return
    try { await deletePayRun(id); await loadData() } catch (err: any) { toast('error', tCommon('common.error'), err.message || tCommon('common.error')) }
  }

  async function handleGenerateJournal(id: string) {
    try {
      await generatePayrollJournal(id)
      toast('success', tCommon('common.success'), t('payrollAccounting.generatedEntries'))
      await loadData()
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    }
  }

  async function handlePay(run: PayRun, values: PaymentValues) {
    setPaying(run.id)
    try {
      const res = await payPayrollRun(run.id, values.bank_account_id, values.payment_date, 'all')
      const reste = (res.remaining || []).length
      setPayRunToPay(null)
      if ((res.entries || []).length === 0 && reste === 0) {
        toast('info', t('payRuns.pay'), t('payRuns.payNothing'))
      } else if (reste > 0) {
        toast('warning', t('payRuns.pay'), t('payRuns.payPartial'))
      } else {
        toast('success', t('payRuns.pay'), t('payRuns.payDone'))
      }
      await loadData()
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    } finally {
      setPaying(null)
    }
  }

  const activeEmployees = employees.filter(e => e.status === 'active')

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('groups.hr') }, { label: t('payRuns.title') }]} />
      <PageHeader
        title={t('payRuns.title')}
        subtitle={t('payRuns.subtitle')}
        action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('payRuns.new')}</Button>}
      />

      {loading ? (
        <SkeletonTable rows={4} cols={7} />
      ) : payRuns.length === 0 ? (
        <EmptyState icon={<Calendar className="w-8 h-8" />} title={t('payRuns.noPayRuns')} description={t('payRuns.noPayRunsDescription')} action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('payRuns.new')}</Button>} />
      ) : (
        <Card>
          <Table headers={[t('payRuns.number'), t('payRuns.period'), t('payRuns.payDate'), t('payRuns.employeesCount'), t('payRuns.grossTotal'), t('payRuns.netTotal'), t('payRuns.status'), tCommon('table.actions')]}>
            {payRuns.map((pr) => (
              <TableRow key={pr.id}>
                <TableCell className="font-mono font-semibold text-xs">{pr.number}</TableCell>
                <TableCell className="text-xs">{formatDate(pr.period_start)} → {formatDate(pr.period_end)}</TableCell>
                <TableCell className="text-xs">{formatDate(pr.pay_date)}</TableCell>
                <TableCell className="font-mono text-xs">{pr.employee_count}</TableCell>
                <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(pr.gross_total))}</TableCell>
                <TableCell className="font-mono text-xs font-bold text-right">{formatCurrency(Number(pr.net_total))}</TableCell>
                <TableCell>
                  <select value={pr.status} onChange={(e) => handleStatusChange(pr.id, e.target.value)} className="text-xs border border-[var(--color-border)] rounded px-2 py-1 bg-[var(--color-surface)]">
                    {['draft', 'processing', 'approved', 'paid'].map((k) => <option key={k} value={k}>{t(`payRuns.statuses.${k}`)}</option>)}
                  </select>
                </TableCell>
                <TableCell>
                  <div className="flex items-center gap-1">
                    <button onClick={() => handleGenerateJournal(pr.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-primary)]" title={t('payrollAccounting.generate')}><FileText className="w-4 h-4" /></button>
                    {pr.status !== 'paid' && pr.status !== 'cancelled' && pr.status !== 'draft' && (
                      <button onClick={() => setPayRunToPay(pr)} disabled={paying === pr.id} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-success)] disabled:opacity-50" title={paying === pr.id ? t('payRuns.paying') : t('payRuns.pay')} aria-label={t('payRuns.pay')}>
                        <Banknote className="w-4 h-4" aria-hidden="true" />
                      </button>
                    )}
                    <button onClick={() => handleDelete(pr.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]" aria-label={tCommon('actions.delete')} title={tCommon('actions.delete')}><Trash2 className="w-4 h-4" aria-hidden="true" /></button>
                  </div>
                </TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}

      {showForm && <PayRunForm employees={activeEmployees} onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadData() }} />}

      {payRunToPay && (
        <PaymentDialog
          title={t('payRuns.payTitle', { number: payRunToPay.number })}
          subtitle={t('payRuns.paySubtitle')}
          defaultAmount={0}
          showAmount={false}
          submitLabel={t('payRuns.pay')}
          onSubmit={(values) => handlePay(payRunToPay, values)}
          onClose={() => setPayRunToPay(null)}
        />
      )}
    </div>
  )
}

function PayRunForm({ employees, onClose, onSaved }: { employees: Employee[]; onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation('hr')
  const { t: tCommon } = useTranslation('common')
  const today = new Date()
  const firstDay = new Date(today.getFullYear(), today.getMonth(), 1).toISOString().split('T')[0]
  const lastDay = new Date(today.getFullYear(), today.getMonth() + 1, 0).toISOString().split('T')[0]
  const [number, setNumber] = useState('PAY-' + today.getFullYear() + '-' + String(today.getMonth() + 1).padStart(2, '0'))
  const { toast } = useToast()
  const [periodStart, setPeriodStart] = useState(firstDay)
  const [periodEnd, setPeriodEnd] = useState(lastDay)
  const [payDate, setPayDate] = useState(today.toISOString().split('T')[0])
  const [saving, setSaving] = useState(false)

  // Moroccan payroll calculation
  const grossTotal = employees.reduce((s, e) => s + Number(e.salary), 0)
  const cnssTotal = employees.reduce((s, e) => {
    const sal = Number(e.salary)
    const cnssBase = Math.min(sal, 6000) // CNSS plafonné à 6000 MAD
    return s + cnssBase * 0.0448 // 4.48% part salariale
  }, 0)
  const amoTotal = grossTotal * 0.0226 // AMO 2.26%
  const irTotal = employees.reduce((s, e) => {
    const sal = Number(e.salary)
    const cnssDed = Math.min(sal, 6000) * 0.0448
    const amoDed = sal * 0.0226
    const netImposable = sal - cnssDed - amoDed
    // Simplified IR barème
    let ir = 0
    if (netImposable <= 2500) ir = 0
    else if (netImposable <= 4166) ir = (netImposable - 2500) * 0.10
    else if (netImposable <= 5000) ir = 166.6 + (netImposable - 4166) * 0.20
    else if (netImposable <= 6666) ir = 333.4 + (netImposable - 5000) * 0.30
    else if (netImposable <= 15000) ir = 833.2 + (netImposable - 6666) * 0.34
    else ir = 3683.0 + (netImposable - 15000) * 0.38
    return s + Math.max(0, ir)
  }, 0)
  const totalDeductions = cnssTotal + amoTotal + irTotal
  const netTotal = grossTotal - totalDeductions
  const employerCnssTotal = employees.reduce((s, e) => {
    const sal = Number(e.salary)
    const cnssBase = Math.min(sal, 6000)
    return s + cnssBase * 0.0898
  }, 0)
  const employerAmoTotal = grossTotal * 0.0226
  const employerContributionsTotal = employerCnssTotal + employerAmoTotal

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      await createPayRun({
        number, period_start: periodStart, period_end: periodEnd, pay_date: payDate,
        status: 'draft', gross_total: grossTotal, tax_total: totalDeductions, net_total: netTotal,
        employer_contributions_total: employerContributionsTotal,
        employee_count: employees.length,
      } as any)
      onSaved()
    } catch (err: any) { toast('error', tCommon('common.error'), err.message || tCommon('common.error')) } finally { setSaving(false) }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '36rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('payRuns.new')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]" aria-label={tCommon('actions.close')} title={tCommon('actions.close')}><X className="w-5 h-5" aria-hidden="true" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <Input label={t('payRuns.number')} required value={number} onChange={(e) => setNumber(e.target.value)} />
          <div className="grid grid-cols-3 gap-4">
            <Input label={t('payRuns.startDate')} type="date" required value={periodStart} onChange={(e) => setPeriodStart(e.target.value)} />
            <Input label={t('payRuns.endDate')} type="date" required value={periodEnd} onChange={(e) => setPeriodEnd(e.target.value)} />
            <Input label={t('payRuns.payDate')} type="date" required value={payDate} onChange={(e) => setPayDate(e.target.value)} />
          </div>
          <div className="p-3 rounded-lg bg-[var(--color-neutral-50)] space-y-1 text-sm">
            <div className="flex justify-between"><span className="text-[var(--color-text-secondary)]">{t('dashboard.activeEmployees')}:</span><span className="font-bold">{employees.length}</span></div>
            <div className="flex justify-between"><span className="text-[var(--color-text-secondary)]">{t('payRuns.grossTotal')}:</span><span className="font-mono font-bold">{formatCurrency(grossTotal)}</span></div>
            <div className="flex justify-between"><span className="text-[var(--color-text-secondary)]">{t('payRuns.cnss')} (4.48%):</span><span className="font-mono text-[var(--color-danger)]">-{formatCurrency(cnssTotal)}</span></div>
            <div className="flex justify-between"><span className="text-[var(--color-text-secondary)]">{t('payRuns.amo')} (2.26%):</span><span className="font-mono text-[var(--color-danger)]">-{formatCurrency(amoTotal)}</span></div>
            <div className="flex justify-between"><span className="text-[var(--color-text-secondary)]">{t('payRuns.ir')}:</span><span className="font-mono text-[var(--color-danger)]">-{formatCurrency(irTotal)}</span></div>
            <div className="flex justify-between border-t border-[var(--color-border)] pt-1"><span className="font-semibold">{t('paySlips.netSalary')}:</span><span className="font-mono font-bold text-[var(--color-success)]">{formatCurrency(netTotal)}</span></div>
          </div>
          <div className="flex justify-end gap-3 pt-4 border-t border-[var(--color-border)]">
            <Button type="button" variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving || employees.length === 0}>{saving ? tCommon('actions.saving') : t('payRuns.generate')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
