import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, SkeletonTable, Breadcrumb, Table, TableRow, TableCell, Badge } from '@/components/ui'
import { getInvoices, getQuotes, getCreditNotes } from '@/lib/queries'
import { formatCurrency, translateStatus } from '@/lib/utils'
import type { Invoice, Quote, CreditNote } from '@/types'
import { useToast } from '@/lib/toast'

export function SalesDashboardPage() {
  const { toast } = useToast()
  const { t } = useTranslation('sales')
  const { t: tCommon } = useTranslation('common')
const [invoices, setInvoices] = useState<Invoice[]>([])
  const [quotes, setQuotes] = useState<Quote[]>([])
  const [creditNotes, setCreditNotes] = useState<CreditNote[]>([])
  const [loading, setLoading] = useState(true)

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const [inv, q, cn] = await Promise.all([getInvoices(), getQuotes(), getCreditNotes()])
      setInvoices(inv)
      setQuotes(q)
      setCreditNotes(cn)
    } catch (err) { console.error(err); toast('error', tCommon('toast.error'), tCommon('toast.loadingError')) } finally { setLoading(false) }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  const totalInvoiced = invoices.reduce((s, i) => s + Number(i.total), 0)
  const totalPaid = invoices.reduce((s, i) => s + Number(i.amount_paid), 0)
  const totalOutstanding = invoices.reduce((s, i) => s + Number(i.amount_due), 0)
  const totalQuotes = quotes.reduce((s, q) => s + Number(q.total), 0)
  const acceptedQuotes = quotes.filter(q => q.status === 'accepted').length
  const totalCreditNotes = creditNotes.reduce((s, cn) => s + Number(cn.total), 0)

  return (
    <div>
      <Breadcrumb items={[{ label: t('dashboard.title') }]} />
      <PageHeader title={t('dashboard.title')} subtitle={t('dashboard.subtitle')} />

      {loading ? (
        <SkeletonTable rows={4} cols={4} />
      ) : (
        <>
          <div className="grid grid-cols-4 gap-4 mb-6">
            <Card><div className="p-4"><p className="text-sm text-[var(--color-text-secondary)]">{t('dashboard.totalInvoices')}</p><p className="text-2xl font-bold font-mono">{formatCurrency(totalInvoiced)}</p></div></Card>
            <Card><div className="p-4"><p className="text-sm text-[var(--color-text-secondary)]">{t('dashboard.paidInvoices')}</p><p className="text-2xl font-bold font-mono text-[var(--color-success)]">{formatCurrency(totalPaid)}</p></div></Card>
            <Card><div className="p-4"><p className="text-sm text-[var(--color-text-secondary)]">{t('dashboard.pendingInvoices')}</p><p className="text-2xl font-bold font-mono text-[var(--color-warning)]">{formatCurrency(totalOutstanding)}</p></div></Card>
            <Card><div className="p-4"><p className="text-sm text-[var(--color-text-secondary)]">{t('creditNotes.title')}</p><p className="text-2xl font-bold font-mono text-[var(--color-danger)]">{formatCurrency(totalCreditNotes)}</p></div></Card>
          </div>

          <div className="grid grid-cols-2 gap-6">
            <Card>
              <h3 className="text-sm font-semibold p-4 border-b border-[var(--color-border)]">{t('dashboard.recentInvoices')}</h3>
              <Table headers={[t('invoices.number'), t('invoices.customer'), t('invoices.amount'), t('invoices.status')]}>
                {invoices.slice(0, 5).map((inv) => (
                  <TableRow key={inv.id}>
                    <TableCell className="font-mono text-xs">{inv.number}</TableCell>
                    <TableCell className="text-sm">{inv.customer_name || '—'}</TableCell>
                    <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(inv.total))}</TableCell>
                    <TableCell><Badge variant={inv.status === 'paid' ? 'success' : inv.status === 'overdue' ? 'danger' : 'neutral'}>{translateStatus(inv.status)}</Badge></TableCell>
                  </TableRow>
                ))}
              </Table>
            </Card>

            <Card>
              <h3 className="text-sm font-semibold p-4 border-b border-[var(--color-border)]">{t('quotes.title')}</h3>
              <Table headers={[t('quotes.number'), t('quotes.customer'), t('quotes.amount'), t('quotes.status')]}>
                {quotes.slice(0, 5).map((q) => (
                  <TableRow key={q.id}>
                    <TableCell className="font-mono text-xs">{q.number}</TableCell>
                    <TableCell className="text-sm">{q.customer_name || '—'}</TableCell>
                    <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(q.total))}</TableCell>
                    <TableCell><Badge variant={q.status === 'accepted' ? 'success' : q.status === 'rejected' ? 'danger' : 'warning'}>{translateStatus(q.status)}</Badge></TableCell>
                  </TableRow>
                ))}
              </Table>
            </Card>
          </div>

          <div className="mt-6 grid grid-cols-3 gap-4">
            <Card><div className="p-4"><p className="text-sm text-[var(--color-text-secondary)]">{t('dashboard.conversionRate')}</p><p className="text-xl font-bold">{quotes.filter(q => q.status === 'draft' || q.status === 'sent').length}</p></div></Card>
            <Card><div className="p-4"><p className="text-sm text-[var(--color-text-secondary)]">{t('dashboard.conversionRate')}</p><p className="text-xl font-bold">{quotes.length > 0 ? ((acceptedQuotes / quotes.length) * 100).toFixed(1) : 0}%</p></div></Card>
            <Card><div className="p-4"><p className="text-sm text-[var(--color-text-secondary)]">{t('dashboard.totalRevenue')}</p><p className="text-xl font-bold font-mono">{formatCurrency(totalQuotes)}</p></div></Card>
          </div>
        </>
      )}
    </div>
  )
}
