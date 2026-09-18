import { useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Button, Badge } from '@/components/ui'
import { Check, X, ChevronLeft, ChevronRight } from 'lucide-react'
import { supabase } from '@/lib/supabase'
import { getTenantId } from '@/lib/queries/core'
import { formatDate, formatCurrency } from '@/lib/utils'
import { useToast } from '@/lib/toast'

export function MobileApproval() {
  const { t } = useTranslation('employee')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [items, setItems] = useState<any[]>([])
  const [currentIdx, setCurrentIdx] = useState(0)
  const [loading, setLoading] = useState(false)
  const [showRejectModal, setShowRejectModal] = useState(false)
  const [rejectComment, setRejectComment] = useState('')

  async function handleApprove(item: any) {
    setLoading(true)
    try {
      const tid = await getTenantId()
      if (item.type === 'leave') {
        const { error } = await supabase.from('leave_requests').update({ status: 'approved' }).eq('id', item.id).eq('tenant_id', tid)
        if (error) throw error
      } else {
        const { error } = await supabase.from('expense_reports').update({ status: 'approved' }).eq('id', item.id).eq('tenant_id', tid)
        if (error) throw error
      }
      toast('success', tCommon('common.success'), t('approvals.approved'))
      nextItem()
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    } finally { setLoading(false) }
  }

  async function handleReject() {
    const item = items[currentIdx]
    if (!item) return
    setLoading(true)
    try {
      const tid = await getTenantId()
      if (item.type === 'leave') {
        const { error } = await supabase.from('leave_requests').update({ status: 'rejected', manager_comment: rejectComment }).eq('id', item.id).eq('tenant_id', tid)
        if (error) throw error
      } else {
        const { error } = await supabase.from('expense_reports').update({ status: 'rejected', manager_comment: rejectComment }).eq('id', item.id).eq('tenant_id', tid)
        if (error) throw error
      }
      toast('success', tCommon('common.success'), t('approvals.rejected'))
      setShowRejectModal(false); setRejectComment('')
      nextItem()
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    } finally { setLoading(false) }
  }

  function nextItem() {
    setItems(prev => prev.filter((_, i) => i !== currentIdx))
    setCurrentIdx(prev => Math.max(0, prev - 1))
  }

  const current = items[currentIdx]

  if (!current) {
    return (
      <div className="flex flex-col items-center justify-center p-8 gap-3">
        <Check className="w-12 h-12 text-[var(--color-success)]" />
        <p className="text-sm font-medium">{t('approvals.noPending')}</p>
      </div>
    )
  }

  return (
    <div className="p-4">
      <div className="flex items-center justify-between mb-4">
        <Badge variant="warning">{items.length} {t('approvals.pending')}</Badge>
        <div className="flex gap-1">
          <Button size="sm" variant="ghost" onClick={() => setCurrentIdx(Math.max(0, currentIdx - 1))} ariaLabel={tCommon('actions.previous')}><ChevronLeft className="w-4 h-4" aria-hidden="true" /></Button>
          <Button size="sm" variant="ghost" onClick={() => setCurrentIdx(Math.min(items.length - 1, currentIdx + 1))} ariaLabel={tCommon('actions.next')}><ChevronRight className="w-4 h-4" aria-hidden="true" /></Button>
        </div>
      </div>

      <div className="card p-4 mb-4">
        <p className="text-sm font-medium mb-2">{current.employee_name || 'Employee'}</p>
        <p className="text-xs text-[var(--color-text-secondary)] mb-3">{current.type === 'leave' ? t('approvals.leaveApprovals') : t('approvals.expenseApprovals')}</p>
        {current.type === 'leave' ? (
          <div className="text-sm space-y-1">
            <p>{t('leaves.leaveType')}: {t(`leaves.types.${current.leave_type}`) || current.leave_type}</p>
            <p>{t('leaves.startDate')}: {formatDate(current.start_date)}</p>
            <p>{t('leaves.endDate')}: {formatDate(current.end_date)}</p>
          </div>
        ) : (
          <div className="text-sm space-y-1">
            <p>{t('expenses.totalAmount')}: {formatCurrency(Number(current.total_amount))}</p>
            <p>{t('expenses.period')}: {current.period || '-'}</p>
          </div>
        )}
      </div>

      <div className="flex gap-2 sticky bottom-4">
        <Button variant="danger" className="flex-1" onClick={() => setShowRejectModal(true)} disabled={loading}>
          <X className="w-4 h-4" /> {t('approvals.reject')}
        </Button>
        <Button className="flex-1" onClick={() => handleApprove(current)} disabled={loading}>
          <Check className="w-4 h-4" /> {t('approvals.approve')}
        </Button>
      </div>

      {showRejectModal && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
          <div className="bg-[var(--color-surface)] rounded-lg p-4 w-full max-w-sm">
            <h3 className="text-sm font-semibold mb-3">{t('approvals.commentRequired')}</h3>
            <textarea
              value={rejectComment}
              onChange={e => setRejectComment(e.target.value)}
              className="input w-full mb-3 min-h-[80px]"
              required
            />
            <div className="flex gap-2">
              <Button variant="ghost" onClick={() => setShowRejectModal(false)}>{tCommon('common.cancel')}</Button>
              <Button variant="danger" onClick={handleReject} disabled={!rejectComment || loading}>{t('approvals.reject')}</Button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
