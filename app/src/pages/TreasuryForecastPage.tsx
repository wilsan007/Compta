import { useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Select } from '@/components/ui'
import { formatCurrency, formatDate } from '@/lib/utils'
import { getTreasuryForecast } from '@/lib/queries'
import { TrendingUp, TrendingDown, Calendar } from 'lucide-react'

export function TreasuryForecastPage() {
  const { t } = useTranslation('treasury')
  const [data, setData] = useState<any>(null)
  const [loading, setLoading] = useState(true)
  const [horizon, setHorizon] = useState('90')

  useEffect(() => { load() }, [horizon])

  async function load() {
    setLoading(true)
    try {
      const res = await getTreasuryForecast(Number(horizon))
      setData(res)
    } catch (err) {
      console.error('Error loading treasury forecast:', err)
    } finally {
      setLoading(false)
    }
  }

  const netFlow = (data?.totalIncoming || 0) - (data?.totalOutgoing || 0)
  const projectedBalance = (data?.currentBalance || 0) + netFlow

  return (
    <div>
      <Breadcrumb items={[{ label: t('title') }, { label: t('forecast.title') }]} />
      <PageHeader title={t('forecast.title')} subtitle={t('forecast.subtitle')} />

      <div className="flex gap-3 mb-4 items-end">
        <div className="w-48">
          <Select
            label={t('forecast.horizon')}
            value={horizon}
            onChange={(e) => setHorizon(e.target.value)}
            options={[
              { value: '30', label: t('forecast.days30') },
              { value: '60', label: t('forecast.days60') },
              { value: '90', label: t('forecast.days90') },
              { value: '180', label: t('forecast.days180') },
            ]}
          />
        </div>
      </div>

      {loading ? (
        <SkeletonTable rows={8} cols={5} />
      ) : !data || data.timeline.length === 0 ? (
        <EmptyState
          icon={<Calendar className="w-8 h-8" />}
          title={t('forecast.noForecast')}
          description={t('forecast.noForecastDesc')}
        />
      ) : (
        <div className="space-y-4">
          <div className="grid grid-cols-4 gap-4">
            <div className="card p-4">
              <p className="text-xs text-[var(--color-text-secondary)] mb-1">{t('forecast.currentBalance')}</p>
              <p className="text-lg font-bold font-mono">{formatCurrency(data.currentBalance)}</p>
            </div>
            <div className="card p-4">
              <p className="text-xs text-[var(--color-text-secondary)] mb-1 flex items-center gap-1"><TrendingUp className="w-3 h-3 text-[var(--color-success)]" /> {t('forecast.incoming')}</p>
              <p className="text-lg font-bold font-mono text-[var(--color-success)]">{formatCurrency(data.totalIncoming)}</p>
            </div>
            <div className="card p-4">
              <p className="text-xs text-[var(--color-text-secondary)] mb-1 flex items-center gap-1"><TrendingDown className="w-3 h-3 text-[var(--color-danger)]" /> {t('forecast.outgoing')}</p>
              <p className="text-lg font-bold font-mono text-[var(--color-danger)]">{formatCurrency(data.totalOutgoing)}</p>
            </div>
            <div className="card p-4">
              <p className="text-xs text-[var(--color-text-secondary)] mb-1">{t('forecast.projectedBalance')}</p>
              <p className={`text-lg font-bold font-mono ${projectedBalance >= 0 ? 'text-[var(--color-success)]' : 'text-[var(--color-danger)]'}`}>
                {formatCurrency(projectedBalance)}
              </p>
            </div>
          </div>

          <Card title={t('forecast.timeline')}>
            <Table headers={[t('forecast.date'), t('forecast.reference'), t('forecast.type'), t('forecast.amount'), t('forecast.cumulativeBalance')]}>
              {data.timeline.map((e: any, i: number) => (
                <TableRow key={i}>
                  <TableCell className="text-xs">{formatDate(e.date)}</TableCell>
                  <TableCell className="font-mono text-xs">{e.reference}</TableCell>
                  <TableCell>
                    <Badge variant={e.type === 'in' ? 'success' : 'danger'}>
                      {e.type === 'in' ? t('forecast.incomingType') : t('forecast.outgoingType')}
                    </Badge>
                  </TableCell>
                  <TableCell className={`font-mono text-xs text-right ${e.type === 'in' ? 'text-[var(--color-success)]' : 'text-[var(--color-danger)]'}`}>
                    {e.type === 'in' ? '+' : '−'}{formatCurrency(e.amount)}
                  </TableCell>
                  <TableCell className={`font-mono text-xs font-semibold text-right ${e.runningBalance >= 0 ? '' : 'text-[var(--color-danger)]'}`}>
                    {formatCurrency(e.runningBalance)}
                  </TableCell>
                </TableRow>
              ))}
            </Table>
          </Card>
        </div>
      )}
    </div>
  )
}
