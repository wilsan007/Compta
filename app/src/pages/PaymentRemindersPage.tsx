import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable } from '@/components/ui'
import { getCollectionReminders, generatePaymentLink } from '@/lib/queries'
import { useLocale } from '@/hooks/useLocale'
import { Link2, Copy, Mail } from 'lucide-react'
import type { CollectionReminder } from '@/types'
import { useToast } from '@/lib/toast'

export function PaymentRemindersPage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const { formatCurrency, formatDate } = useLocale()
  const [reminders, setReminders] = useState<CollectionReminder[]>([])
  const [loading, setLoading] = useState(true)

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const data = await getCollectionReminders()
      setReminders(data || [])
    } catch (err) {
      console.error('Failed to load reminders:', err)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  async function handleGenerateLink(id: string) {
    try {
      await generatePaymentLink(id)
      toast('success', tCommon('common.success'), t('reminders.linkGenerated'))
      await loadData()
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    }
  }

  function handleCopyLink(url: string) {
    navigator.clipboard.writeText(url)
    toast('success', tCommon('common.success'), t('reminders.linkCopied'))
  }

  const tableHeaders = [
    t('reminders.customer'),
    t('reminders.invoice'),
    t('reminders.amount'),
    t('reminders.dueDate'),
    t('reminders.level'),
    t('reminders.paymentStatus'),
    t('reminders.paymentLink'),
    tCommon('common.table.actions'),
  ]

  return (
    <div>
      <Breadcrumb items={[{ label: t('home.breadcrumb') }, { label: t('treatment.breadcrumb') }, { label: t('reminders.breadcrumb') }]} />
      <PageHeader
        title={t('reminders.title')}
        subtitle={t('reminders.subtitle')}
      />

      {loading ? (
        <SkeletonTable rows={5} cols={8} />
      ) : reminders.length === 0 ? (
        <EmptyState
          icon={<Mail className="w-8 h-8" />}
          title={t('reminders.noReminders')}
          description={t('reminders.noRemindersDescription')}
        />
      ) : (
        <Card>
          <Table headers={tableHeaders}>
            {reminders.map((reminder: any) => (
              <TableRow key={reminder.id}>
                <TableCell className="text-sm">{reminder.customer_name || '—'}</TableCell>
                <TableCell className="font-mono text-xs">{reminder.invoice_number || '—'}</TableCell>
                <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(reminder.amount || 0))}</TableCell>
                <TableCell className="text-xs">{reminder.due_date ? formatDate(reminder.due_date) : '—'}</TableCell>
                <TableCell>
                  <Badge variant={reminder.reminder_level >= 3 ? 'danger' : reminder.reminder_level >= 2 ? 'warning' : 'neutral'}>
                    {t('reminders.levels.level')} {reminder.reminder_level || 1}
                  </Badge>
                </TableCell>
                <TableCell>
                  <Badge variant={reminder.payment_status === 'paid' ? 'success' : reminder.payment_status === 'pending' ? 'warning' : 'neutral'}>
                    {t(`reminders.paymentStatuses.${reminder.payment_status || 'unpaid'}`)}
                  </Badge>
                </TableCell>
                <TableCell className="text-xs">
                  {reminder.payment_link_url ? (
                    <span className="text-[var(--color-primary)] truncate max-w-[150px] inline-block">{reminder.payment_link_url}</span>
                  ) : (
                    <span className="text-[var(--color-text-tertiary)]">—</span>
                  )}
                </TableCell>
                <TableCell>
                  <div className="flex items-center gap-1">
                    {!reminder.payment_link_url && (
                      <button
                        onClick={() => handleGenerateLink(reminder.id)}
                        className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-primary)]"
                        title={t('reminders.generateLink')}
                      >
                        <Link2 className="w-4 h-4" />
                      </button>
                    )}
                    {reminder.payment_link_url && (
                      <button
                        onClick={() => handleCopyLink(reminder.payment_link_url)}
                        className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-text-secondary)]"
                        title={t('reminders.copyLink')}
                      >
                        <Copy className="w-4 h-4" />
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
