import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable } from '@/components/ui'
import { getPendingExpenseReports, approveExpenseReport, rejectExpenseReport, getExpenseReportLines } from '@/lib/queries/sprintDE'
import { formatDate, formatCurrency } from '@/lib/utils'
import { CheckCircle, XCircle, ChevronRight, Receipt } from 'lucide-react'
import { useToast } from '@/lib/toast'

export function ManagerExpenseApprovalsPage() {
  const { toast } = useToast()
  const { t } = useTranslation('hr')
  const { t: tCommon } = useTranslation('common')
  const { t: tNav } = useTranslation('nav')
  const [reports, setReports] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [selectedReport, setSelectedReport] = useState<any>(null)
  const [lines, setLines] = useState<any[]>([])

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const data = await getPendingExpenseReports()
      setReports(data || [])
    } catch (err: any) {
      console.error(err)
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    } finally { setLoading(false) }
  }, [tCommon, toast])

  useEffect(() => { loadData() }, [loadData])

  async function handleApprove(id: string) {
    const comment = window.prompt(t('expenses.approvalComment'), '') || ''
    try { await approveExpenseReport(id, 'current-manager', comment); await loadData(); toast('success', tCommon('common.success'), t('expenses.approved')) }
    catch (err: any) { toast('error', tCommon('common.error'), err.message) }
  }

  async function handleReject(id: string) {
    const comment = window.prompt(t('expenses.rejectionReason'), '') || ''
    try { await rejectExpenseReport(id, 'current-manager', comment); await loadData(); toast('success', tCommon('common.success'), t('expenses.rejected')) }
    catch (err: any) { toast('error', tCommon('common.error'), err.message) }
  }

  async function handleSelectReport(r: any) {
    setSelectedReport(r)
    try {
      const l = await getExpenseReportLines(r.id)
      setLines(l || [])
    } catch (e: any) { console.error(e); toast('error', tCommon('toast.error'), e.message || tCommon('toast.loadError')) }
  }

  if (selectedReport) {
    const totalTtc = lines.reduce((s, l) => s + (l.amount_ttc || 0), 0)
    return (
      <div>
        <div className="flex items-center justify-between mb-6">
          <div>
            <h2 className="text-lg font-semibold">{t('expenses.title')} — {selectedReport.employees ? `${selectedReport.employees.first_name} ${selectedReport.employees.last_name}` : ''}</h2>
            <p className="text-sm text-[var(--color-text-secondary)]">{selectedReport.period} — {formatCurrency(totalTtc)}</p>
          </div>
          <div className="flex gap-2">
            <Button variant="secondary" onClick={() => setSelectedReport(null)}>{tCommon('actions.close')}</Button>
            <Button onClick={() => handleApprove(selectedReport.id)}><CheckCircle className="w-4 h-4" /> {t('expenses.approve')}</Button>
            <Button variant="secondary" onClick={() => handleReject(selectedReport.id)}><XCircle className="w-4 h-4" /> {t('expenses.reject')}</Button>
          </div>
        </div>
        <Card>
          <Table headers={[t('expenses.date'), t('expenses.category'), t('expenses.description'), t('expenses.amountHt'), t('expenses.amountTtc')]}>
            {lines.map((l) => (
              <TableRow key={l.id}>
                <TableCell className="text-xs">{formatDate(l.date)}</TableCell>
                <TableCell className="text-sm">{l.expense_categories?.label || '—'}</TableCell>
                <TableCell className="text-sm">{l.description || '—'}</TableCell>
                <TableCell className="font-mono text-xs text-right">{formatCurrency(l.amount_ht || 0)}</TableCell>
                <TableCell className="font-mono text-xs text-right">{formatCurrency(l.amount_ttc || 0)}</TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      </div>
    )
  }

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('sections.hr') }, { label: t('expenses.approvals') }]} />
      <PageHeader title={t('expenses.approvals')} subtitle={t('expenses.approvalsSubtitle')} />

      {loading ? (
        <SkeletonTable rows={4} cols={5} />
      ) : reports.length === 0 ? (
        <EmptyState icon={<Receipt className="w-8 h-8" />} title={t('expenses.noPending')} description={t('expenses.noPendingDescription')} />
      ) : (
        <Card>
          <Table headers={[
            t('expenses.employee'),
            t('expenses.period'),
            t('expenses.amount'),
            t('expenses.submittedAt'),
            tCommon('table.actions'),
          ]}>
            {reports.map((r) => (
              <TableRow key={r.id}>
                <TableCell className="text-sm font-medium">{r.employees ? `${r.employees.first_name} ${r.employees.last_name}` : '—'}</TableCell>
                <TableCell className="text-sm">{r.period || '—'}</TableCell>
                <TableCell className="font-mono text-xs text-right">{formatCurrency(r.total_ttc || 0)}</TableCell>
                <TableCell className="text-xs">{r.submitted_at ? formatDate(r.submitted_at) : '—'}</TableCell>
                <TableCell>
                  <div className="flex gap-1">
                    <button onClick={() => handleApprove(r.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-success)]" title={t('expenses.approve')}>
                      <CheckCircle className="w-4 h-4" />
                    </button>
                    <button onClick={() => handleReject(r.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]" title={t('expenses.reject')}>
                      <XCircle className="w-4 h-4" />
                    </button>
                    <button onClick={() => handleSelectReport(r)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-info)]" title={tCommon('actions.view')}>
                      <ChevronRight className="w-4 h-4" />
                    </button>
                  </div>
                </TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}
    </div>
  )
}
