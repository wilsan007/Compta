import { useState, useEffect, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, SkeletonTable, Breadcrumb, Table, TableRow, TableCell, Select, Badge, EmptyState } from '@/components/ui'
import { getMarginAnalysis } from '@/lib/queries/pilotage'
import { formatCurrency } from '@/lib/utils'
import { useToast } from '@/lib/toast'

export function MarginAnalysisPage() {
  const { t } = useTranslation('sales')
  const { t: tCommon } = useTranslation('common')
  const { t: tNav } = useTranslation('nav')
  const { toast } = useToast()

  const [period, setPeriod] = useState<'month' | 'quarter' | 'year'>('month')
  const [dimension, setDimension] = useState<'product' | 'customer' | 'category'>('product')
  const [data, setData] = useState<{ name: string; revenue: number; cost: number; margin: number; marginPercent: number }[]>([])
  const [loading, setLoading] = useState(false)

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const result = await getMarginAnalysis(period, dimension)
      setData(result)
    } catch (err) {
      console.error(err)
      toast('error', tCommon('toast.error'), tCommon('toast.loadingError'))
    } finally {
      setLoading(false)
    }
  }, [period, dimension, toast, tCommon])

  useEffect(() => { loadData() }, [loadData])

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('items.sales') }, { label: t('margins.title') }]} />
      <PageHeader title={t('margins.title')} subtitle={t('margins.subtitle')} />

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
            <label className="block text-sm text-[var(--color-text-secondary)] mb-1">{t('margins.dimension')}</label>
            <Select value={dimension} onChange={(e) => setDimension(e.target.value as any)} options={[
              { value: 'product', label: t('margins.byProduct') },
              { value: 'customer', label: t('margins.byCustomer') },
              { value: 'category', label: t('margins.byCategory') },
            ]} />
          </div>
        </div>
      </Card>

      {loading ? (
        <SkeletonTable rows={6} cols={5} />
      ) : data.length > 0 ? (
        <Card>
          <Table headers={[t('margins.name'), t('margins.revenue'), t('margins.cost'), t('margins.grossMargin'), t('margins.marginPercent')]}>
            {data.map((row) => (
              <TableRow key={row.name}>
                <TableCell className="text-sm">{row.name}</TableCell>
                <TableCell className="font-mono text-xs text-right">{formatCurrency(row.revenue)}</TableCell>
                <TableCell className="font-mono text-xs text-right">{formatCurrency(row.cost)}</TableCell>
                <TableCell className="font-mono text-xs text-right">
                  <Badge variant={row.margin < 0 ? 'danger' : row.marginPercent < 15 ? 'warning' : 'success'}>
                    {formatCurrency(row.margin)}
                  </Badge>
                </TableCell>
                <TableCell className="font-mono text-xs text-right">
                  <Badge variant={row.marginPercent < 0 ? 'danger' : row.marginPercent < 15 ? 'warning' : 'success'}>
                    {row.marginPercent.toFixed(1)}%
                  </Badge>
                </TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      ) : (
        <EmptyState title={t('margins.noData')} description={t('margins.noDataDescription')} />
      )}
    </div>
  )
}
