import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Select, Badge } from '@/components/ui'
import { formatCurrency, formatDate } from '@/lib/utils'
import { getPaySlips, getPayRuns, getEmployees, generatePaySlipsForRun, updatePaySlip, deletePaySlip } from '@/lib/queries/payroll'
import { calculatePayslip } from '@/lib/queries/businessFunctions'
import { FileText, Trash2, Sparkles, ChevronDown, ChevronRight, Receipt, AlertTriangle, Clock, Plane, RotateCcw, Calculator as CalcIcon } from 'lucide-react'
import type { PayRun, Employee } from '@/types'
import { useToast } from '@/lib/toast'
import { confirmSync } from '@/lib/confirm'

export function PaySlipsPage() {
  const { toast } = useToast()
  const { t } = useTranslation('hr')
  const { t: tCommon } = useTranslation('common')
  const { t: tNav } = useTranslation('nav')
const [slips, setSlips] = useState<any[]>([])
  const [payRuns, setPayRuns] = useState<PayRun[]>([])
  const [employees, setEmployees] = useState<Employee[]>([])
  const [loading, setLoading] = useState(true)
  const [runFilter, setRunFilter] = useState('')
  const [expanded, setExpanded] = useState<Set<string>>(new Set())
  const [generating, setGenerating] = useState(false)

  const loadData = useCallback(async () => {
    try {
      const [sl, pr, emps] = await Promise.all([getPaySlips(runFilter || undefined), getPayRuns(), getEmployees()])
      setSlips(sl || [])
      setPayRuns(pr || [])
      setEmployees(emps || [])
    } catch (err: any) { console.error('Error:', err); toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadError')) }
    finally { setLoading(false) }
  }, [runFilter, tCommon, toast])

  useEffect(() => { loadData() }, [loadData])

  async function handleGenerate(runId: string) {
  const run = payRuns.find((r) => r.id === runId)
    if (!run) return
    setGenerating(true)
    try {
      await generatePaySlipsForRun(runId, employees, run)
      await loadData()
      toast('success', tCommon('common.success'), t('paySlips.title'))
    } catch (err: any) { toast('error', tCommon('common.error'), err.message || tCommon('common.error')) }
    finally { setGenerating(false) }
  }

  async function handleStatusChange(id: string, status: string) {
    try { await updatePaySlip(id, { status: status as any }); await loadData() }
    catch (err: any) { toast('error', tCommon('common.error'), err.message || tCommon('common.error')) }
  }

  async function handleDelete(id: string) {
    if (!confirmSync(tCommon('form.confirmDelete'))) return
    try { await deletePaySlip(id); await loadData() }
    catch (err: any) { toast('error', tCommon('common.error'), err.message || tCommon('common.error')) }
  }

  async function handleCalculatePayslip(employeeId: string, period: string, payRunId?: string) {
    try {
      await calculatePayslip(employeeId, period, payRunId)
      await loadData()
      toast('success', tCommon('common.success'), t('paySlips.calculated'))
    } catch (err: any) { toast('error', tCommon('common.error'), err.message || tCommon('common.error')) }
  }

  function toggleExpand(id: string) {
    const next = new Set(expanded)
    if (next.has(id)) next.delete(id)
    else next.add(id)
    setExpanded(next)
  }

  const [expandedSlip, setExpandedSlip] = useState<string | null>(null)

  const grouped = slips.reduce((acc, s) => {
    const key = s.pay_run_id || 'none'
    if (!acc[key]) acc[key] = []
    acc[key].push(s)
    return acc
  }, {} as Record<string, any[]>)

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('sections.hr') }, { label: t('paySlips.title') }]} />
      <PageHeader title={t('paySlips.title')} subtitle={t('paySlips.subtitle')} />

      <div className="flex gap-3 mb-4 items-end">
        <div className="w-64">
          <Select label={t('payRuns.title')} value={runFilter} onChange={(e) => setRunFilter(e.target.value)} options={[
            { value: '', label: tCommon('table.all') }, ...payRuns.map((r) => ({ value: r.id, label: r.number })),
          ]} />
        </div>
      </div>

      {loading ? <SkeletonTable rows={6} cols={6} /> : slips.length === 0 ? (
        <EmptyState icon={<FileText className="w-8 h-8" />} title={t('paySlips.noPaySlips')} description={t('paySlips.noPaySlipsDescription')} />
      ) : (
        <div className="space-y-4">
          {(Object.entries(grouped) as any[]).map(([runId, runSlips]: [string, any[]]) => {
            const run = payRuns.find((r) => r.id === runId)
            const isExpanded = expanded.has(runId) || runFilter === runId
            return (
              <Card key={runId}>
                <div className="p-4 border-b border-[var(--color-border)] flex items-center justify-between">
                  <div className="flex items-center gap-2">
                    <button onClick={() => toggleExpand(runId)} className="p-0.5 rounded hover:bg-[var(--color-neutral-100)]">
                      {isExpanded ? <ChevronDown className="w-4 h-4" /> : <ChevronRight className="w-4 h-4" />}
                    </button>
                    <span className="font-semibold">{run?.number || t('paySlips.title')}</span>
                    <span className="text-xs text-[var(--color-text-secondary)]">{runSlips.length} {t('paySlips.title').toLowerCase()}</span>
                  </div>
                  <div className="flex items-center gap-2">
                    <span className="text-xs font-mono">{formatCurrency(runSlips.reduce((s, sl) => s + Number(sl.net_salary), 0))}</span>
                    {run && runSlips.length === 0 && (
                      <Button size="sm" onClick={() => handleGenerate(run.id)} disabled={generating}>
                        <Sparkles className="w-3.5 h-3.5" /> {generating ? '...' : t('payRuns.generate')}
                      </Button>
                    )}
                  </div>
                </div>
                {isExpanded && (
                  <Table headers={[t('payRuns.number'), t('paySlips.employee'), t('paySlips.period'), t('paySlips.grossSalary'), t('paySlips.deductions'), t('paySlips.netSalary'), t('paySlips.status'), 'Compta', tCommon('table.actions')]}>
                    {runSlips.map((s) => {
                      const ci = s.calc_inputs || {}
                      const hasVariableElements = ci.variableElementCount && ci.variableElementCount > 0
                      const isSlipExpanded = expandedSlip === s.id
                      return (
                        <>
                          <TableRow key={s.id}>
                            <TableCell className="font-mono text-xs">
                              {hasVariableElements && (
                                <button onClick={() => setExpandedSlip(isSlipExpanded ? null : s.id)} className="p-0.5 rounded hover:bg-[var(--color-neutral-100)] mr-1">
                                  {isSlipExpanded ? <ChevronDown className="w-3 h-3 inline" /> : <ChevronRight className="w-3 h-3 inline" />}
                                </button>
                              )}
                              {s.number}
                            </TableCell>
                            <TableCell className="text-sm">{s.employees?.name || '—'}</TableCell>
                            <TableCell className="text-xs">{formatDate(s.period_start)} → {formatDate(s.period_end)}</TableCell>
                            <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(s.total_gross))}</TableCell>
                            <TableCell className="font-mono text-xs text-[var(--color-danger)] text-right">{formatCurrency(Number(s.total_deductions))}</TableCell>
                            <TableCell className="font-mono text-xs font-bold text-[var(--color-success)] text-right">{formatCurrency(Number(s.net_salary))}</TableCell>
                            <TableCell>
                              <select value={s.status} onChange={(e) => handleStatusChange(s.id, e.target.value)}
                                className="text-xs border border-[var(--color-border)] rounded px-2 py-1 bg-[var(--color-surface)]">
                                {['draft', 'approved', 'paid', 'cancelled'].map((k) => <option key={k} value={k}>{t(`paySlips.statuses.${k}`)}</option>)}
                              </select>
                            </TableCell>
                            <TableCell>{s.journal_entry_id || s.journal_posted || s.status === 'paid' || s.status === 'approved' ? <Badge variant="success">Comptabilisé</Badge> : <Badge variant="neutral">Non</Badge>}</TableCell>
                            <TableCell>
                              <div className="flex items-center gap-1">
                                <button
                                  onClick={() => handleCalculatePayslip(s.employee_id, s.period_start?.slice(0, 7) || '', s.pay_run_id || undefined)}
                                  title={t('paySlips.calculate')}
                                  className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-primary)]"
                                >
                                  <CalcIcon className="w-4 h-4" />
                                </button>
                                <button onClick={() => handleDelete(s.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]" aria-label={tCommon('actions.delete')} title={tCommon('actions.delete')}>
                                  <Trash2 className="w-4 h-4" aria-hidden="true" /></button>
                              </div>
                            </TableCell>
                          </TableRow>
                          {isSlipExpanded && hasVariableElements && (
                            <TableRow key={s.id + '-detail'}>
                              <TableCell colSpan={9} className="bg-[var(--color-neutral-50)] p-4">
                                <div className="grid grid-cols-2 md:grid-cols-4 gap-3 text-xs">
                                  {ci.advanceDeduction && ci.advanceDeduction > 0 && (
                                    <div className="flex items-center gap-2 p-2 rounded border border-[var(--color-border)] bg-[var(--color-surface)]">
                                      <RotateCcw className="w-3.5 h-3.5 text-[var(--color-warning)]" />
                                      <div>
                                        <div className="text-[var(--color-text-secondary)]">Acompte sur salaire</div>
                                        <div className="font-mono text-[var(--color-danger)]">-{formatCurrency(ci.advanceDeduction)}</div>
                                      </div>
                                    </div>
                                  )}
                                  {ci.payRecall && ci.payRecall !== 0 && (
                                    <div className="flex items-center gap-2 p-2 rounded border border-[var(--color-border)] bg-[var(--color-surface)]">
                                      <RotateCcw className="w-3.5 h-3.5 text-[var(--color-info)]" />
                                      <div>
                                        <div className="text-[var(--color-text-secondary)]">Rappel de paie</div>
                                        <div className="font-mono text-[var(--color-success)]">+{formatCurrency(ci.payRecall)}</div>
                                      </div>
                                    </div>
                                  )}
                                  {ci.expenseReimbursement && ci.expenseReimbursement > 0 && (
                                    <div className="flex items-center gap-2 p-2 rounded border border-[var(--color-border)] bg-[var(--color-surface)]">
                                      <Receipt className="w-3.5 h-3.5 text-[var(--color-info)]" />
                                      <div>
                                        <div className="text-[var(--color-text-secondary)]">Remboursement de frais</div>
                                        <div className="font-mono text-[var(--color-success)]">+{formatCurrency(ci.expenseReimbursement)}</div>
                                      </div>
                                    </div>
                                  )}
                                  {ci.unpaidLeaveDeduction && ci.unpaidLeaveDeduction > 0 && (
                                    <div className="flex items-center gap-2 p-2 rounded border border-[var(--color-border)] bg-[var(--color-surface)]">
                                      <Plane className="w-3.5 h-3.5 text-[var(--color-warning)]" />
                                      <div>
                                        <div className="text-[var(--color-text-secondary)]">Congé sans solde</div>
                                        <div className="font-mono text-[var(--color-danger)]">-{formatCurrency(ci.unpaidLeaveDeduction)}</div>
                                      </div>
                                    </div>
                                  )}
                                  {ci.otherDeductions && ci.otherDeductions > 0 && (
                                    <div className="flex items-center gap-2 p-2 rounded border border-[var(--color-border)] bg-[var(--color-surface)]">
                                      <AlertTriangle className="w-3.5 h-3.5 text-[var(--color-danger)]" />
                                      <div>
                                        <div className="text-[var(--color-text-secondary)]">Autres déductions</div>
                                        <div className="font-mono text-[var(--color-danger)]">-{formatCurrency(ci.otherDeductions)}</div>
                                      </div>
                                    </div>
                                  )}
                                  {ci.overtimeHours && ci.overtimeHours > 0 && (
                                    <div className="flex items-center gap-2 p-2 rounded border border-[var(--color-border)] bg-[var(--color-surface)]">
                                      <Clock className="w-3.5 h-3.5 text-[var(--color-success)]" />
                                      <div>
                                        <div className="text-[var(--color-text-secondary)]">Heures supp.</div>
                                        <div className="font-mono">{ci.overtimeHours}h</div>
                                      </div>
                                    </div>
                                  )}
                                </div>
                                <div className="mt-2 text-xs text-[var(--color-text-secondary)]">
                                  {ci.variableElementCount} élément(s) variable(s) intégré(s)
                                  {ci.gridVersion && ` · Grille fiscale: ${ci.gridVersion}`}
                                </div>
                              </TableCell>
                            </TableRow>
                          )}
                        </>
                      )
                    })}
                  </Table>
                )}
              </Card>
            )
          })}
        </div>
      )}
    </div>
  )
}
