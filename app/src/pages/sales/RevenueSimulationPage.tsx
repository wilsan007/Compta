import { useState, useEffect, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, SkeletonTable, Breadcrumb, Table, TableRow, TableCell, Button, Input, Select, Badge, EmptyState } from '@/components/ui'
import { getRevenueSimulation } from '@/lib/queries/pilotage'
import { formatCurrency } from '@/lib/utils'
import { useToast } from '@/lib/toast'

export function RevenueSimulationPage() {
  const { t } = useTranslation('sales')
  const { t: tCommon } = useTranslation('common')
  const { t: tNav } = useTranslation('nav')
  const { toast } = useToast()

  const [period, setPeriod] = useState<'month' | 'quarter' | 'year'>('month')
  const [growthRate, setGrowthRate] = useState(10)
  const [data, setData] = useState<{ currentRevenue: number; projectedRevenue: number; projection: { month: string; current: number; projected: number }[] } | null>(null)
  const [loading, setLoading] = useState(false)

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const result = await getRevenueSimulation(period, growthRate)
      setData(result)
    } catch (err) {
      console.error(err)
      toast('error', tCommon('toast.error'), tCommon('toast.loadingError'))
    } finally {
      setLoading(false)
    }
  }, [period, growthRate, toast, tCommon])

  useEffect(() => { loadData() }, [loadData])

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('sections.sales') }, { label: t('simulation.title') }]} />
      <PageHeader title={t('simulation.title')} subtitle={t('simulation.subtitle')} />

      <Card className="mb-6">
        <div className="p-4 flex flex-wrap gap-4 items-end">
          <div>
            <label className="block text-sm text-[var(--color-text-secondary)] mb-1">{t('simulation.period')}</label>
            <Select value={period} onChange={(e) => setPeriod(e.target.value as any)} options={[
              { value: 'month', label: t('simulation.monthly') },
              { value: 'quarter', label: t('simulation.quarterly') },
              { value: 'year', label: t('simulation.yearly') },
            ]} />
          </div>
          <div>
            <label className="block text-sm text-[var(--color-text-secondary)] mb-1">{t('simulation.growthRate')} (%)</label>
            <Input type="number" value={growthRate} onChange={(e) => setGrowthRate(Number(e.target.value))} className="w-32" />
          </div>
          <div className="flex gap-2">
            <Button variant="secondary" size="sm" onClick={() => setGrowthRate(5)}>{t('simulation.pessimistic')}</Button>
            <Button variant="secondary" size="sm" onClick={() => setGrowthRate(10)}>{t('simulation.realistic')}</Button>
            <Button variant="secondary" size="sm" onClick={() => setGrowthRate(20)}>{t('simulation.optimistic')}</Button>
          </div>
        </div>
      </Card>

      {loading ? (
        <SkeletonTable rows={4} cols={4} />
      ) : data ? (
        <>
          <div className="grid grid-cols-2 gap-4 mb-6">
            <Card>
              <div className="p-4">
                <p className="text-sm text-[var(--color-text-secondary)]">{t('simulation.currentRevenue')}</p>
                <p className="text-2xl font-bold font-mono">{formatCurrency(data.currentRevenue)}</p>
              </div>
            </Card>
            <Card>
              <div className="p-4">
                <p className="text-sm text-[var(--color-text-secondary)]">{t('simulation.projectedRevenue')}</p>
                <p className="text-2xl font-bold font-mono text-[var(--color-success)]">{formatCurrency(data.projectedRevenue)}</p>
              </div>
            </Card>
          </div>

          {data.projection.length > 0 ? (
            <Card>
              <h3 className="text-sm font-semibold p-4 border-b border-[var(--color-border)]">{t('simulation.byMonth')}</h3>
              <Table headers={[t('simulation.month'), t('simulation.currentRevenue'), t('simulation.projectedRevenue'), t('simulation.difference')]}>
                {data.projection.map((row) => (
                  <TableRow key={row.month}>
                    <TableCell className="font-mono text-xs">{row.month}</TableCell>
                    <TableCell className="font-mono text-xs text-right">{formatCurrency(row.current)}</TableCell>
                    <TableCell className="font-mono text-xs text-right text-[var(--color-success)]">{formatCurrency(row.projected)}</TableCell>
                    <TableCell className="font-mono text-xs text-right">
                      <Badge variant={row.projected > row.current ? 'success' : 'neutral'}>
                        {formatCurrency(row.projected - row.current)}
                      </Badge>
                    </TableCell>
                  </TableRow>
                ))}
              </Table>
            </Card>
          ) : (
            <EmptyState title={t('simulation.noData')} description={t('simulation.noDataDescription')} />
          )}
        </>
      ) : (
        <EmptyState title={t('simulation.noData')} description={t('simulation.noDataDescription')} />
      )}
    </div>
  )
}
