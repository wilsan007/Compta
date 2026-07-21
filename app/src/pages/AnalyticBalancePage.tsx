import { useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable } from '@/components/ui'
import { formatCurrency } from '@/lib/utils'
import { getAnalyticBalance } from '@/lib/queries'
import { PieChart } from 'lucide-react'

export function AnalyticBalancePage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const [data, setData] = useState<any[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => { load() }, [])

  async function load() {
    try {
      const res = await getAnalyticBalance()
      setData(res)
    } catch (err) {
      console.error('Error loading analytic balance:', err)
    } finally {
      setLoading(false)
    }
  }

  const totalDebit = data.reduce((s, d) => s + d.totalDebit, 0)
  const totalCredit = data.reduce((s, d) => s + d.totalCredit, 0)
  const totalAnalytic = data.reduce((s, d) => s + d.totalAnalytic, 0)

  return (
    <div>
      <Breadcrumb items={[{ label: t('title') }, { label: t('analyticBalance.breadcrumb') }, { label: t('analyticBalance.title') }]} />
      <PageHeader title={t('analyticBalance.title')} subtitle={t('analyticBalance.subtitle')} />

      {loading ? (
        <SkeletonTable rows={6} cols={5} />
      ) : data.length === 0 ? (
        <EmptyState
          icon={<PieChart className="w-8 h-8" />}
          title={t('analyticBalance.noData')}
          description={t('analyticBalance.noDataDescription')}
        />
      ) : (
        <div className="space-y-4">
          <div className="grid grid-cols-3 gap-4">
            <div className="card p-4">
              <p className="text-xs text-[var(--color-text-secondary)] mb-1">{t('analyticBalance.totalDebit')}</p>
              <p className="text-lg font-bold font-mono">{formatCurrency(totalDebit)}</p>
            </div>
            <div className="card p-4">
              <p className="text-xs text-[var(--color-text-secondary)] mb-1">{t('analyticBalance.totalCredit')}</p>
              <p className="text-lg font-bold font-mono">{formatCurrency(totalCredit)}</p>
            </div>
            <div className="card p-4">
              <p className="text-xs text-[var(--color-text-secondary)] mb-1">{t('analyticBalance.totalAnalytic')}</p>
              <p className="text-lg font-bold font-mono text-[var(--color-primary)]">{formatCurrency(totalAnalytic)}</p>
            </div>
          </div>

          <Card>
            <Table headers={[t('analyticBalance.code'), t('analyticBalance.section'), t('analyticBalance.debit'), t('analyticBalance.credit'), t('analyticBalance.analyticAmount'), t('analyticBalance.balance')]}>
              {data.map((d) => (
                <TableRow key={d.sectionId}>
                  <TableCell className="font-mono text-xs font-semibold">{d.sectionCode}</TableCell>
                  <TableCell className="text-sm">{d.sectionName}</TableCell>
                  <TableCell className="font-mono text-xs text-right">{formatCurrency(d.totalDebit)}</TableCell>
                  <TableCell className="font-mono text-xs text-right">{formatCurrency(d.totalCredit)}</TableCell>
                  <TableCell className="font-mono text-xs font-bold text-[var(--color-primary)] text-right">{formatCurrency(d.totalAnalytic)}</TableCell>
                  <TableCell className="font-mono text-xs text-right">{formatCurrency(d.totalDebit - d.totalCredit)}</TableCell>
                </TableRow>
              ))}
              <TableRow>
                <TableCell colSpan={2} className="font-bold">{tCommon('common.total')}</TableCell>
                <TableCell className="font-mono font-bold text-xs text-right">{formatCurrency(totalDebit)}</TableCell>
                <TableCell className="font-mono font-bold text-xs text-right">{formatCurrency(totalCredit)}</TableCell>
                <TableCell className="font-mono font-bold text-xs text-[var(--color-primary)] text-right">{formatCurrency(totalAnalytic)}</TableCell>
                <TableCell className="font-mono font-bold text-xs text-right">{formatCurrency(totalDebit - totalCredit)}</TableCell>
              </TableRow>
            </Table>
          </Card>
        </div>
      )}
    </div>
  )
}
