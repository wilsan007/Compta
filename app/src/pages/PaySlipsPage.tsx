import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Select } from '@/components/ui'
import { formatCurrency, formatDate } from '@/lib/utils'
import { getPaySlips, getPayRuns, getEmployees, generatePaySlipsForRun, updatePaySlip, deletePaySlip } from '@/lib/queries'
import { FileText, Trash2, Sparkles, ChevronDown, ChevronRight } from 'lucide-react'
import type { PayRun, Employee } from '@/types'
import { useToast } from '@/lib/toast'

const statusLabels: Record<string, string> = { draft: 'Brouillon', approved: 'Approuvé', paid: 'Payé', cancelled: 'Annulé' }

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
    } catch (err) { console.error('Error:', err) }
    finally { setLoading(false) }
  }, [runFilter])

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
    if (!window.confirm(tCommon('form.confirmDelete'))) return
    try { await deletePaySlip(id); await loadData() }
    catch (err: any) { toast('error', tCommon('common.error'), err.message || tCommon('common.error')) }
  }

  function toggleExpand(id: string) {
    const next = new Set(expanded)
    if (next.has(id)) next.delete(id)
    else next.add(id)
    setExpanded(next)
  }

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
                  <Table headers={[t('payRuns.number'), t('paySlips.employee'), t('paySlips.period'), t('paySlips.grossSalary'), t('paySlips.deductions'), t('paySlips.netSalary'), t('paySlips.status'), tCommon('table.actions')]}>
                    {runSlips.map((s) => (
                      <TableRow key={s.id}>
                        <TableCell className="font-mono text-xs">{s.number}</TableCell>
                        <TableCell className="text-sm">{s.employees?.name || '—'}</TableCell>
                        <TableCell className="text-xs">{formatDate(s.period_start)} → {formatDate(s.period_end)}</TableCell>
                        <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(s.total_gross))}</TableCell>
                        <TableCell className="font-mono text-xs text-[var(--color-danger)] text-right">{formatCurrency(Number(s.total_deductions))}</TableCell>
                        <TableCell className="font-mono text-xs font-bold text-[var(--color-success)] text-right">{formatCurrency(Number(s.net_salary))}</TableCell>
                        <TableCell>
                          <select value={s.status} onChange={(e) => handleStatusChange(s.id, e.target.value)}
                            className="text-xs border border-[var(--color-border)] rounded px-2 py-1 bg-[var(--color-surface)]">
                            {Object.entries(statusLabels).map(([k]) => <option key={k} value={k}>{t(`paySlips.statuses.${k}`) || statusLabels[k]}</option>)}
                          </select>
                        </TableCell>
                        <TableCell>
                          <button onClick={() => handleDelete(s.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]">
                            <Trash2 className="w-4 h-4" />
                          </button>
                        </TableCell>
                      </TableRow>
                    ))}
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
