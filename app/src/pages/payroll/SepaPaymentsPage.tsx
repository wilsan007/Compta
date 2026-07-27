import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable } from '@/components/ui'
import { formatCurrency, formatDate } from '@/lib/utils'
import { getSepaPaymentOrders, transmitSepaOrder, getPayRuns } from '@/lib/queries'
import type { SepaPaymentOrder, PayRun } from '@/types'
import { useToast } from '@/lib/toast'
import { FileText, Send, Download } from 'lucide-react'

export function SepaPaymentsPage() {
  const { t } = useTranslation('payroll')
  const { t: tCommon } = useTranslation('common')
  const { t: tNav } = useTranslation('nav')
  const { toast } = useToast()
  const [orders, setOrders] = useState<SepaPaymentOrder[]>([])
  const [payRuns, setPayRuns] = useState<PayRun[]>([])
  const [loading, setLoading] = useState(true)

  const loadData = useCallback(async () => {
    try {
      const [ords, runs] = await Promise.all([getSepaPaymentOrders(), getPayRuns()])
      setOrders(ords || [])
      setPayRuns(runs || [])
    } catch (err: any) { console.error(err) }
    finally { setLoading(false) }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  async function handleTransmit(id: string) {
    if (!window.confirm(t('sepa.confirmTransmit'))) return
    try {
      await transmitSepaOrder(id)
      toast('success', tCommon('common.success'), t('sepa.transmitted'))
      await loadData()
    } catch (err: any) { toast('error', tCommon('common.error'), err.message) }
  }

  function handleDownload(order: SepaPaymentOrder) {
    if (!order.file_url) {
      toast('error', tCommon('common.error'), t('sepa.noFile'))
      return
    }
    window.open(order.file_url, '_blank')
  }

  const payRunNumber = (id: string | null) => payRuns.find((r) => r.id === id)?.number || '—'

  const statusVariant = (status: string) => {
    switch (status) {
      case 'draft': return 'neutral' as const
      case 'generated': return 'warning' as const
      case 'transmitted': return 'primary' as const
      case 'processed': return 'success' as const
      case 'rejected': return 'danger' as const
      default: return 'neutral' as const
    }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('sections.hr') }, { label: t('sepa.title') }]} />
      <PageHeader title={t('sepa.title')} subtitle={t('sepa.subtitle')} />

      {loading ? <SkeletonTable rows={4} cols={7} /> : orders.length === 0 ? (
        <EmptyState icon={<FileText className="w-8 h-8" />} title={t('sepa.noOrders')} description={t('sepa.noOrdersDescription')} />
      ) : (
        <Card>
          <Table headers={[
            t('sepa.number'), t('sepa.payRun'), t('sepa.executionDate'),
            t('sepa.totalAmount'), t('sepa.employees'), t('sepa.status'),
            tCommon('table.actions'),
          ]}>
            {orders.map((o) => (
              <TableRow key={o.id}>
                <TableCell className="text-xs font-mono">{o.number}</TableCell>
                <TableCell className="text-xs">{payRunNumber(o.pay_run_id)}</TableCell>
                <TableCell className="text-xs">{formatDate(o.execution_date)}</TableCell>
                <TableCell className="font-mono text-xs font-bold">{formatCurrency(Number(o.total_amount))}</TableCell>
                <TableCell className="font-mono text-xs">{o.employee_count}</TableCell>
                <TableCell><Badge variant={statusVariant(o.status)}>{t(`sepa.statuses.${o.status}`)}</Badge></TableCell>
                <TableCell>
                  <div className="flex gap-1">
                    {o.file_url && (
                      <button onClick={() => handleDownload(o)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-primary)]" title={tCommon('actions.download')}>
                        <Download className="w-4 h-4" />
                      </button>
                    )}
                    {o.status === 'generated' && (
                      <button onClick={() => handleTransmit(o.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-success)]" title={t('sepa.transmit')}>
                        <Send className="w-4 h-4" />
                      </button>
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
