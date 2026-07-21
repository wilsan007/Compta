import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable } from '@/components/ui'
import { getPurchaseInvoices, updatePurchaseInvoiceApproval } from '@/lib/queries'
import { useLocale } from '@/hooks/useLocale'
import { CheckCircle2, XCircle, Clock } from 'lucide-react'
import type { PurchaseInvoice } from '@/types'
import { useToast } from '@/lib/toast'

export function PurchaseInvoiceApprovalPage() {
  const { t } = useTranslation('purchases')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const { formatCurrency, formatDate } = useLocale()
  const [invoices, setInvoices] = useState<PurchaseInvoice[]>([])
  const [loading, setLoading] = useState(true)
  const [filter, setFilter] = useState<'pending' | 'approved' | 'rejected' | 'all'>('pending')

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const data = await getPurchaseInvoices()
      const filtered = filter === 'all' ? data : data.filter((inv: any) => (inv.approval_status || 'pending') === filter)
      setInvoices(filtered as PurchaseInvoice[])
    } catch (err) {
      console.error('Failed to load purchase invoices:', err)
    } finally {
      setLoading(false)
    }
  }, [filter])

  useEffect(() => { loadData() }, [loadData])

  async function handleApprove(id: string) {
    try {
      await updatePurchaseInvoiceApproval(id, 'approved')
      toast('success', tCommon('common.success'), t('approval.approvedSuccess'))
      await loadData()
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    }
  }

  async function handleReject(id: string) {
    try {
      await updatePurchaseInvoiceApproval(id, 'rejected')
      toast('success', tCommon('common.success'), t('approval.rejectedSuccess'))
      await loadData()
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    }
  }

  const tableHeaders = [
    t('invoices.number'),
    t('invoices.supplier'),
    t('invoices.date'),
    t('invoices.dueDate'),
    t('invoices.total'),
    t('approval.status'),
    t('approval.approvedAt'),
    tCommon('common.table.actions'),
  ]

  const filterButtons = [
    { key: 'pending' as const, label: t('approval.pending'), icon: <Clock className="w-3.5 h-3.5" /> },
    { key: 'approved' as const, label: t('approval.approved'), icon: <CheckCircle2 className="w-3.5 h-3.5" /> },
    { key: 'rejected' as const, label: t('approval.rejected'), icon: <XCircle className="w-3.5 h-3.5" /> },
    { key: 'all' as const, label: tCommon('common.all'), icon: null },
  ]

  return (
    <div>
      <Breadcrumb items={[{ label: t('approval.breadcrumb') }]} />
      <PageHeader
        title={t('approval.title')}
        subtitle={t('approval.subtitle')}
      />

      <div className="mb-4 flex items-center gap-2">
        {filterButtons.map((btn) => (
          <button
            key={btn.key}
            onClick={() => setFilter(btn.key)}
            className={`flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-sm font-medium transition-colors ${
              filter === btn.key
                ? 'bg-[var(--color-primary)] text-white'
                : 'bg-[var(--color-neutral-100)] text-[var(--color-text-secondary)] hover:bg-[var(--color-neutral-200)]'
            }`}
          >
            {btn.icon}
            {btn.label}
          </button>
        ))}
      </div>

      {loading ? (
        <SkeletonTable rows={5} cols={8} />
      ) : invoices.length === 0 ? (
        <EmptyState
          icon={<CheckCircle2 className="w-8 h-8" />}
          title={t('approval.noInvoices')}
          description={t('approval.noInvoicesDescription')}
        />
      ) : (
        <Card>
          <Table headers={tableHeaders}>
            {invoices.map((inv: any) => (
              <TableRow key={inv.id}>
                <TableCell className="font-mono font-semibold text-sm">{inv.number}</TableCell>
                <TableCell className="text-sm">{inv.supplier_name || '—'}</TableCell>
                <TableCell className="text-xs">{formatDate(inv.date)}</TableCell>
                <TableCell className="text-xs">{formatDate(inv.due_date)}</TableCell>
                <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(inv.total))}</TableCell>
                <TableCell>
                  <Badge variant={inv.approval_status === 'approved' ? 'success' : inv.approval_status === 'rejected' ? 'danger' : 'warning'}>
                    {t(`approval.statuses.${inv.approval_status || 'pending'}`)}
                  </Badge>
                </TableCell>
                <TableCell className="text-xs">
                  {inv.approved_at ? formatDate(inv.approved_at) : '—'}
                </TableCell>
                <TableCell>
                  <div className="flex items-center gap-1">
                    {(inv.approval_status || 'pending') === 'pending' && (
                      <>
                        <button
                          onClick={() => handleApprove(inv.id)}
                          className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-success)]"
                          title={t('approval.approve')}
                        >
                          <CheckCircle2 className="w-4 h-4" />
                        </button>
                        <button
                          onClick={() => handleReject(inv.id)}
                          className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]"
                          title={t('approval.reject')}
                        >
                          <XCircle className="w-4 h-4" />
                        </button>
                      </>
                    )}
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
