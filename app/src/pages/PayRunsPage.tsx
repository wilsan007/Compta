import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Input } from '@/components/ui'
import { getPayRuns, createPayRun, updatePayRun, deletePayRun, getEmployees, generatePayrollJournal } from '@/lib/queries'
import { formatCurrency, formatDate } from '@/lib/utils'
import { Calendar, Plus, Trash2, X, FileText } from 'lucide-react'
import type { PayRun, Employee } from '@/types'
import { useToast } from '@/lib/toast'

const statusLabels: Record<string, string> = { draft: 'Brouillon', approved: 'Approuvé', paid: 'Payé' }

export function PayRunsPage() {
  const { toast } = useToast()
  const { t } = useTranslation('hr')
  const { t: tCommon } = useTranslation('common')
  const { t: tNav } = useTranslation('nav')
const [payRuns, setPayRuns] = useState<PayRun[]>([])
  const [employees, setEmployees] = useState<Employee[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const [pr, e] = await Promise.all([getPayRuns(), getEmployees()])
      setPayRuns(pr)
      setEmployees(e)
    } catch (err) { console.error(err); toast('error', tCommon('common.error'), tCommon('common.error')) } finally { setLoading(false) }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  async function handleStatusChange(id: string, status: string) {
  try { await updatePayRun(id, { status: status as any }); await loadData() } catch (err: any) { toast('error', tCommon('common.error'), err.message || tCommon('common.error')) }
  }

  async function handleDelete(id: string) {
    if (!window.confirm(tCommon('form.confirmDelete'))) return
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

  const activeEmployees = employees.filter(e => e.status === 'active')

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('sections.hr') }, { label: t('payRuns.title') }]} />
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
                    {Object.entries(statusLabels).map(([k]) => <option key={k} value={k}>{t(`payRuns.statuses.${k}`) || statusLabels[k]}</option>)}
                  </select>
                </TableCell>
                <TableCell>
                  <div className="flex items-center gap-1">
                    <button onClick={() => handleGenerateJournal(pr.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-primary)]" title={t('payrollAccounting.generate')}><FileText className="w-4 h-4" /></button>
                    <button onClick={() => handleDelete(pr.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]"><Trash2 className="w-4 h-4" /></button>
                  </div>
                </TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}

      {showForm && <PayRunForm employees={activeEmployees} onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadData() }} />}
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

  const grossTotal = employees.reduce((s, e) => s + Number(e.salary), 0)
  const taxTotal = grossTotal * 0.23
  const netTotal = grossTotal - taxTotal

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      await createPayRun({
        number, period_start: periodStart, period_end: periodEnd, pay_date: payDate,
        status: 'draft', gross_total: grossTotal, tax_total: taxTotal, net_total: netTotal,
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
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
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
            <div className="flex justify-between"><span className="text-[var(--color-text-secondary)]">{t('payRuns.chargesTotal')} (~23%):</span><span className="font-mono text-[var(--color-danger)]">-{formatCurrency(taxTotal)}</span></div>
            <div className="flex justify-between border-t border-[var(--color-border)] pt-1"><span className="font-semibold">{t('paySlips.netSalary')}:</span><span className="font-mono font-bold text-[var(--color-success)]">{formatCurrency(netTotal)}</span></div>
          </div>
          <div className="flex justify-end gap-3 pt-4 border-t border-[var(--color-border)]">
            <Button type="button" variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving || employees.length === 0}>{saving ? '...' : t('payRuns.generate')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
