import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, SkeletonTable, Breadcrumb, Table, TableRow, TableCell } from '@/components/ui'
import { getCashFlow } from '@/lib/queries'
import { formatCurrency } from '@/lib/utils'

export function CashFlowPage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const [data, setData] = useState<{ inflow: number; outflow: number; net: number; byMonth: any[] } | null>(null)
  const [loading, setLoading] = useState(true)

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      setData(await getCashFlow())
    } catch (err) {
      console.error('Failed to load cash flow:', err)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  return (
    <div>
      <Breadcrumb items={[{ label: t('cashFlow.title') }, { label: t('cashFlow.subtitle') }]} />
      <PageHeader title={t('cashFlow.title')} subtitle={t('cashFlow.subtitle')} />

      {loading ? (
        <SkeletonTable rows={4} cols={4} />
      ) : data ? (
        <>
          <div className="grid grid-cols-3 gap-4 mb-6">
            <Card>
              <div className="p-4">
                <p className="text-sm text-[var(--color-text-secondary)]">{t('cashFlow.inflow')}</p>
                <p className="text-2xl font-bold font-mono text-[var(--color-success)]">{formatCurrency(data.inflow)}</p>
              </div>
            </Card>
            <Card>
              <div className="p-4">
                <p className="text-sm text-[var(--color-text-secondary)]">{t('cashFlow.outflow')}</p>
                <p className="text-2xl font-bold font-mono text-[var(--color-danger)]">{formatCurrency(data.outflow)}</p>
              </div>
            </Card>
            <Card>
              <div className="p-4">
                <p className="text-sm text-[var(--color-text-secondary)]">{t('cashFlow.netFlow')}</p>
                <p className={`text-2xl font-bold font-mono ${data.net >= 0 ? 'text-[var(--color-success)]' : 'text-[var(--color-danger)]'}`}>{formatCurrency(data.net)}</p>
              </div>
            </Card>
          </div>

          <Card>
            <h3 className="text-sm font-semibold p-4 border-b border-[var(--color-border)]">{t('cashFlow.byMonth')}</h3>
            <Table headers={[t('cashFlow.month'), t('cashFlow.inflow'), t('cashFlow.outflow'), t('cashFlow.netFlow')]}>
              {data.byMonth.map((m) => (
                <TableRow key={m.month}>
                  <TableCell className="font-mono">{m.month}</TableCell>
                  <TableCell className="font-mono text-[var(--color-success)] text-right">{formatCurrency(m.inflow)}</TableCell>
                  <TableCell className="font-mono text-[var(--color-danger)] text-right">{formatCurrency(m.outflow)}</TableCell>
                  <TableCell className={`font-mono font-bold text-right ${m.inflow - m.outflow >= 0 ? 'text-[var(--color-success)]' : 'text-[var(--color-danger)]'}`}>
                    {formatCurrency(m.inflow - m.outflow)}
                  </TableCell>
                </TableRow>
              ))}
              {data.byMonth.length === 0 && (
                <TableRow><TableCell colSpan={4} className="text-center text-[var(--color-text-secondary)]">{tCommon('common.noData')}</TableCell></TableRow>
              )}
            </Table>
          </Card>
        </>
      ) : null}
    </div>
  )
}
