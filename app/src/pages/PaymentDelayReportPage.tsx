import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Select } from '@/components/ui'
import { getCustomers, getInvoices } from '@/lib/queries'
import { useLocale } from '@/hooks/useLocale'
import type { Customer, Invoice } from '@/types'

export function PaymentDelayReportPage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { formatCurrency, formatDate } = useLocale()
  const [customers, setCustomers] = useState<Customer[]>([])
  const [invoices, setInvoices] = useState<Invoice[]>([])
  const [loading, setLoading] = useState(true)
  const [filter, setFilter] = useState('all')

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const [custs, invs] = await Promise.all([getCustomers(), getInvoices()])
      setCustomers(custs || [])
      setInvoices(invs || [])
    } catch (err) {
      console.error('Failed to load payment delay data:', err)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  const paidInvoices = invoices.filter((inv) => inv.status === 'paid' && inv.amount_paid > 0)
  const filtered = filter === 'all' ? paidInvoices : paidInvoices.filter((inv) => inv.customer_id === filter)

  const rows = filtered.map((inv) => {
    const customer = customers.find((c) => c.id === inv.customer_id)
    const invoiceDate = new Date(inv.date)
    const paidDate = new Date(inv.updated_at)
    const dueDate = new Date(inv.due_date)
    const agreedDelay = Math.round((dueDate.getTime() - invoiceDate.getTime()) / (1000 * 60 * 60 * 24))
    const actualDelay = Math.round((paidDate.getTime() - invoiceDate.getTime()) / (1000 * 60 * 60 * 24))
    const overdueDays = Math.max(0, actualDelay - agreedDelay)
    return {
      id: inv.id,
      number: inv.number,
      customer: customer?.name || '—',
      date: inv.date,
      dueDate: inv.due_date,
      amount: Number(inv.total),
      agreedDelay,
      actualDelay,
      overdueDays,
    }
  })

  const avgDelay = rows.length > 0 ? Math.round(rows.reduce((s, r) => s + r.actualDelay, 0) / rows.length) : 0
  const avgOverdue = rows.length > 0 ? Math.round(rows.reduce((s, r) => s + r.overdueDays, 0) / rows.length) : 0

  const tableHeaders = [
    t('reports.paymentDelay.number'),
    t('reports.paymentDelay.customer'),
    t('reports.paymentDelay.date'),
    t('reports.paymentDelay.dueDate'),
    t('reports.paymentDelay.amount'),
    t('reports.paymentDelay.agreedDelay'),
    t('reports.paymentDelay.actualDelay'),
    t('reports.paymentDelay.overdueDays'),
  ]

  return (
    <div>
      <Breadcrumb items={[{ label: t('home.breadcrumb') }, { label: t('etats.breadcrumb') }, { label: t('reports.paymentDelay.breadcrumb') }]} />
      <PageHeader
        title={t('reports.paymentDelay.title')}
        subtitle={t('reports.paymentDelay.subtitle')}
      />

      <div className="mb-4 flex items-center gap-4">
        <Select
          label={t('reports.paymentDelay.filterByCustomer')}
          value={filter}
          onChange={(e) => setFilter(e.target.value)}
          options={[
            { value: 'all', label: tCommon('common.all') },
            ...customers.map((c) => ({ value: c.id, label: c.name })),
          ]}
        />
        <div className="flex gap-6 text-sm">
          <div className="px-4 py-2 rounded-lg bg-[var(--color-neutral-50)]">
            <span className="text-[var(--color-text-secondary)]">{t('reports.paymentDelay.avgDelay')}: </span>
            <strong className="font-mono">{avgDelay} {t('reports.paymentDelay.days')}</strong>
          </div>
          <div className="px-4 py-2 rounded-lg bg-[var(--color-neutral-50)]">
            <span className="text-[var(--color-text-secondary)]">{t('reports.paymentDelay.avgOverdue')}: </span>
            <strong className="font-mono">{avgOverdue} {t('reports.paymentDelay.days')}</strong>
          </div>
        </div>
      </div>

      {loading ? (
        <SkeletonTable rows={5} cols={8} />
      ) : rows.length === 0 ? (
        <EmptyState
          icon={<span className="text-2xl">📊</span>}
          title={t('reports.paymentDelay.noData')}
          description={t('reports.paymentDelay.noDataDescription')}
        />
      ) : (
        <Card>
          <Table headers={tableHeaders}>
            {rows.map((row) => (
              <TableRow key={row.id}>
                <TableCell className="font-mono font-semibold text-sm">{row.number}</TableCell>
                <TableCell className="text-sm">{row.customer}</TableCell>
                <TableCell className="text-xs">{formatDate(row.date)}</TableCell>
                <TableCell className="text-xs">{formatDate(row.dueDate)}</TableCell>
                <TableCell className="font-mono text-xs text-right">{formatCurrency(row.amount)}</TableCell>
                <TableCell className="text-center text-xs">{row.agreedDelay} {t('reports.paymentDelay.days')}</TableCell>
                <TableCell className="text-center text-xs">{row.actualDelay} {t('reports.paymentDelay.days')}</TableCell>
                <TableCell className="text-center">
                  <Badge variant={row.overdueDays === 0 ? 'success' : row.overdueDays <= 7 ? 'warning' : 'danger'}>
                    {row.overdueDays} {t('reports.paymentDelay.days')}
                  </Badge>
                </TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}
    </div>
  )
}
