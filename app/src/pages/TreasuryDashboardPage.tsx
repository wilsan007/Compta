import { useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable } from '@/components/ui'
import { formatCurrency, formatDate } from '@/lib/utils'
import { getTreasuryDashboard } from '@/lib/queries'
import { Wallet, TrendingUp, TrendingDown, Clock } from 'lucide-react'

export function TreasuryDashboardPage() {
  const { t } = useTranslation('treasury')
  const [data, setData] = useState<any>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => { load() }, [])

  async function load() {
    try {
      const res = await getTreasuryDashboard()
      setData(res)
    } catch (err) {
      console.error('Error loading treasury dashboard:', err)
    } finally {
      setLoading(false)
    }
  }

  if (loading) {
    return (
      <div>
        <Breadcrumb items={[{ label: t('title') }, { label: t('dashboard.title') }]} />
        <PageHeader title={t('dashboard.title')} subtitle={t('dashboard.subtitle')} />
        <SkeletonTable rows={4} cols={4} />
      </div>
    )
  }

  const { accounts, totalBalance, forecastBuckets, pendingPayments } = data || {}

  return (
    <div>
      <Breadcrumb items={[{ label: t('title') }, { label: t('dashboard.title') }]} />
      <PageHeader title={t('dashboard.title')} subtitle={t('dashboard.subtitle')} />

      <div className="grid grid-cols-4 gap-4 mb-6">
        <Card>
          <div className="p-4">
            <div className="flex items-center gap-2 mb-2">
              <Wallet className="w-5 h-5 text-[var(--color-primary)]" />
              <p className="text-sm text-[var(--color-text-secondary)]">{t('dashboard.totalBalance')}</p>
            </div>
            <p className="text-2xl font-bold font-mono">{formatCurrency(totalBalance || 0)}</p>
          </div>
        </Card>
        <Card>
          <div className="p-4">
            <div className="flex items-center gap-2 mb-2">
              <TrendingUp className="w-5 h-5 text-[var(--color-success)]" />
              <p className="text-sm text-[var(--color-text-secondary)]">{t('dashboard.inflow90')}</p>
            </div>
            <p className="text-2xl font-bold font-mono text-[var(--color-success)]">
              {formatCurrency(forecastBuckets?.reduce((s: number, b: any) => s + b.incoming, 0) || 0)}
            </p>
          </div>
        </Card>
        <Card>
          <div className="p-4">
            <div className="flex items-center gap-2 mb-2">
              <TrendingDown className="w-5 h-5 text-[var(--color-danger)]" />
              <p className="text-sm text-[var(--color-text-secondary)]">{t('dashboard.outflow90')}</p>
            </div>
            <p className="text-2xl font-bold font-mono text-[var(--color-danger)]">
              {formatCurrency(forecastBuckets?.reduce((s: number, b: any) => s + b.outgoing, 0) || 0)}
            </p>
          </div>
        </Card>
        <Card>
          <div className="p-4">
            <div className="flex items-center gap-2 mb-2">
              <Clock className="w-5 h-5 text-[var(--color-warning)]" />
              <p className="text-sm text-[var(--color-text-secondary)]">{t('dashboard.pendingPayments')}</p>
            </div>
            <p className="text-2xl font-bold font-mono">{pendingPayments?.length || 0}</p>
          </div>
        </Card>
      </div>

      <div className="grid grid-cols-2 gap-6 mb-6">
        <Card title={t('dashboard.bankAccounts')}>
          <Table headers={[t('dashboard.bank'), t('dashboard.type'), t('dashboard.balance')]}>
            {(accounts || []).map((acc: any) => (
              <TableRow key={acc.id}>
                <TableCell className="font-medium">{acc.name}</TableCell>
                <TableCell className="text-xs">{acc.type}</TableCell>
                <TableCell className="font-mono text-right">{formatCurrency(Number(acc.balance))}</TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>

        <Card title={t('dashboard.forecast90')}>
          <Table headers={[t('dashboard.period'), t('dashboard.incoming'), t('dashboard.outgoing'), t('dashboard.net')]}>
            {(forecastBuckets || []).map((b: any) => (
              <TableRow key={b.label}>
                <TableCell className="font-medium">{b.label}</TableCell>
                <TableCell className="font-mono text-[var(--color-success)] text-right">{formatCurrency(b.incoming)}</TableCell>
                <TableCell className="font-mono text-[var(--color-danger)] text-right">{formatCurrency(b.outgoing)}</TableCell>
                <TableCell className={`font-mono font-bold text-right ${b.incoming - b.outgoing >= 0 ? 'text-[var(--color-success)]' : 'text-[var(--color-danger)]'}`}>
                  {formatCurrency(b.incoming - b.outgoing)}
                </TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      </div>

      <Card title={t('dashboard.pendingPayments')}>
        {(pendingPayments || []).length === 0 ? (
          <EmptyState icon={<Clock className="w-8 h-8" />} title={t('dashboard.noPending')} description={t('dashboard.noPendingDesc')} />
        ) : (
          <Table headers={[t('dashboard.number'), t('dashboard.beneficiary'), t('dashboard.amount'), t('dashboard.date'), t('dashboard.status')]}>
            {(pendingPayments || []).map((p: any) => (
              <TableRow key={p.id}>
                <TableCell className="font-mono text-xs">{p.number}</TableCell>
                <TableCell className="text-sm">{p.third_party_name || '—'}</TableCell>
                <TableCell className="font-mono text-right">{formatCurrency(Number(p.amount))}</TableCell>
                <TableCell className="text-xs">{formatDate(p.payment_date)}</TableCell>
                <TableCell>
                  <Badge variant={p.status === 'approved' ? 'warning' : 'neutral'}>
                    {p.status === 'approved' ? t('dashboard.statusApproved') : t('dashboard.statusDraft')}
                  </Badge>
                </TableCell>
              </TableRow>
            ))}
          </Table>
        )}
      </Card>
    </div>
  )
}
