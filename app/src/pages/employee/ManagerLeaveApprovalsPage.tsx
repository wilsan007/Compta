import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable } from '@/components/ui'
import { formatDate } from '@/lib/utils'
import { getPendingLeaveRequests, approveLeaveRequest, rejectLeaveRequest } from '@/lib/queries/leavesAbsences'
import { useToast } from '@/lib/toast'
import { CheckCircle, XCircle, CalendarClock, AlertTriangle, X } from 'lucide-react'

export function ManagerLeaveApprovalsPage() {
  const { t } = useTranslation('hr')
  const { t: tCommon } = useTranslation('common')
  const { t: tNav } = useTranslation('nav')
  const { toast } = useToast()
  const [requests, setRequests] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [comment, setComment] = useState('')
  const [activeId, setActiveId] = useState<string | null>(null)

  const loadData = useCallback(async () => {
    try {
      const data = await getPendingLeaveRequests()
      setRequests(data || [])
    } catch (err: any) { console.error(err); toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadingError')) }
    finally { setLoading(false) }
  }, [toast, tCommon])

  useEffect(() => { loadData() }, [loadData])

  async function handleApprove(id: string) {
    try {
      await approveLeaveRequest(id, 'manager', comment || undefined)
      toast('success', tCommon('common.success'), t('leaveApprovals.approved'))
      setComment(''); setActiveId(null)
      await loadData()
    } catch (err: any) { toast('error', tCommon('common.error'), err.message) }
  }

  async function handleReject(id: string) {
    if (!comment) { toast('error', tCommon('common.error'), t('leaveApprovals.commentRequired')); return }
    try {
      await rejectLeaveRequest(id, 'manager', comment)
      toast('success', tCommon('common.success'), t('leaveApprovals.rejected'))
      setComment(''); setActiveId(null)
      await loadData()
    } catch (err: any) { toast('error', tCommon('common.error'), err.message) }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('groups.hr') }, { label: t('leaveApprovals.title') }]} />
      <PageHeader title={t('leaveApprovals.title')} subtitle={t('leaveApprovals.subtitle')} />

      {loading ? <SkeletonTable rows={4} cols={7} /> : requests.length === 0 ? (
        <EmptyState icon={<CalendarClock className="w-8 h-8" />} title={t('leaveApprovals.noPending')} description={t('leaveApprovals.noPendingDescription')} />
      ) : (
        <Card>
          <Table headers={[
            t('leaveRequests.employee'), t('leaveRequests.type'), t('leaveRequests.startDate'),
            t('leaveRequests.endDate'), t('leaveRequests.days'), t('leaveRequests.reason'),
            tCommon('table.actions'),
          ]}>
            {requests.map((r) => (
              <TableRow key={r.id}>
                <TableCell className="text-sm font-medium">{r.employees?.name || '—'}</TableCell>
                <TableCell className="text-xs"><Badge variant="neutral">{t(`leaveRequests.types.${r.leave_type}`) || r.leave_type}</Badge></TableCell>
                <TableCell className="text-xs">{formatDate(r.start_date)}</TableCell>
                <TableCell className="text-xs">{formatDate(r.end_date)}</TableCell>
                <TableCell className="font-mono text-xs">{Number(r.days)}</TableCell>
                <TableCell className="text-xs">{r.reason || '—'}</TableCell>
                <TableCell>
                  <div className="flex gap-1">
                    <button onClick={() => setActiveId(r.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-success)]" title={t('leaveRequests.approve')}>
                      <CheckCircle className="w-4 h-4" />
                    </button>
                    <button onClick={() => setActiveId(r.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]" title={t('leaveRequests.reject')}>
                      <XCircle className="w-4 h-4" />
                    </button>
                  </div>
                </TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}

      {activeId && (
        <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
          <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '28rem' }}>
            <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
              <h2 className="text-lg font-semibold">{t('leaveApprovals.reviewTitle')}</h2>
              <button onClick={() => { setActiveId(null); setComment('') }} className="p-1 rounded hover:bg-[var(--color-neutral-100)]" aria-label={tCommon('actions.close')} title={tCommon('actions.close')}><X className="w-4 h-4" aria-hidden="true" /></button>
            </div>
            <div className="p-6 space-y-4">
              <div className="flex items-start gap-2 p-3 rounded-lg bg-[var(--color-neutral-50)]">
                <AlertTriangle className="w-5 h-5 text-[var(--color-warning)] flex-shrink-0" />
                <p className="text-xs text-[var(--color-text-secondary)]">{t('leaveApprovals.commentHint')}</p>
              </div>
              <div>
                <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('leaveApprovals.comment')}</label>
                <textarea className="input" rows={3} value={comment} onChange={(e) => setComment(e.target.value)} placeholder={t('leaveApprovals.commentPlaceholder')} />
              </div>
              <div className="flex justify-end gap-3 pt-2 border-t border-[var(--color-border)]">
                <Button variant="secondary" onClick={() => { setActiveId(null); setComment('') }}>{tCommon('actions.cancel')}</Button>
                <Button variant="secondary" onClick={() => handleReject(activeId)}><XCircle className="w-4 h-4" /> {t('leaveRequests.reject')}</Button>
                <Button onClick={() => handleApprove(activeId)}><CheckCircle className="w-4 h-4" /> {t('leaveRequests.approve')}</Button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
