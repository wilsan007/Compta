import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Table, TableRow, TableCell, Badge, EmptyState, AutoBreadcrumb, SkeletonTable } from '@/components/ui'
import { TrendingUp, TrendingDown } from 'lucide-react'
import { getExchangeGainLossEntries } from '@/lib/queries'
import type { ExchangeGainLossEntry } from '@/types'

export function ExchangeGainLossPage() {
  const { t } = useTranslation('banking')
  const [entries, setEntries] = useState<ExchangeGainLossEntry[]>([])
  const [loading, setLoading] = useState(true)

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const data = await getExchangeGainLossEntries()
      setEntries(data || [])
    } catch { } finally { setLoading(false) }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  return (
    <div className="p-6 space-y-6">
      <AutoBreadcrumb />
      <PageHeader title={t('exchangeGainLoss.title')} subtitle={t('exchangeGainLoss.subtitle')} />
      <Card>
        {loading ? <SkeletonTable /> : entries.length === 0 ? (
          <EmptyState
            icon={<TrendingUp className="w-12 h-12" />}
            title={t('exchangeGainLoss.noEntries')}
            description={t('exchangeGainLoss.noEntriesDesc')}
          />
        ) : (
          <Table headers={[
            t('exchangeGainLoss.date'),
            t('exchangeGainLoss.type'),
            t('exchangeGainLoss.amount'),
            t('exchangeGainLoss.paymentId'),
            t('exchangeGainLoss.invoiceId'),
            t('exchangeGainLoss.rateOriginal'),
            t('exchangeGainLoss.ratePayment'),
            t('exchangeGainLoss.accountGain'),
            t('exchangeGainLoss.accountLoss'),
            t('exchangeGainLoss.journalEntry'),
          ]}>
            {entries.map(entry => (
              <TableRow key={entry.id}>
                <TableCell>{new Date(entry.created_at).toLocaleDateString()}</TableCell>
                <TableCell>
                  {entry.type === 'gain' ? (
                    <Badge variant="success"><TrendingUp className="w-3 h-3 mr-1 inline" /> {t('exchangeGainLoss.gain')}</Badge>
                  ) : (
                    <Badge variant="danger"><TrendingDown className="w-3 h-3 mr-1 inline" /> {t('exchangeGainLoss.loss')}</Badge>
                  )}
                </TableCell>
                <TableCell className="font-mono text-xs text-right">{entry.amount.toFixed(2)}</TableCell>
                <TableCell className="font-mono text-xs">{entry.payment_id ? entry.payment_id.slice(0, 8) + '…' : '—'}</TableCell>
                <TableCell className="font-mono text-xs">{entry.invoice_id ? entry.invoice_id.slice(0, 8) + '…' : '—'}</TableCell>
                <TableCell className="font-mono text-xs">{entry.exchange_rate_original ?? '—'}</TableCell>
                <TableCell className="font-mono text-xs">{entry.exchange_rate_payment ?? '—'}</TableCell>
                <TableCell className="font-mono text-xs">{entry.account_gain_code || '—'}</TableCell>
                <TableCell className="font-mono text-xs">{entry.account_loss_code || '—'}</TableCell>
                <TableCell className="font-mono text-xs">{entry.journal_entry_id ? entry.journal_entry_id.slice(0, 8) + '…' : '—'}</TableCell>
              </TableRow>
            ))}
          </Table>
        )}
      </Card>
    </div>
  )
}
