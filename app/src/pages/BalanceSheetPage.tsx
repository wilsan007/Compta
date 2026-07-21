import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, SkeletonTable, Breadcrumb, Table, TableRow, TableCell } from '@/components/ui'
import { getBalanceSheet } from '@/lib/queries'
import { formatCurrency } from '@/lib/utils'

export function BalanceSheetPage() {
  const { t } = useTranslation('accounting')
  const [data, setData] = useState<{ assets: any[]; liabilities: any[]; equity: any[] } | null>(null)
  const [loading, setLoading] = useState(true)

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      setData(await getBalanceSheet())
    } catch (err) {
      console.error('Failed to load balance sheet:', err)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  const totalAssets = (data?.assets || []).reduce((s, a) => s + (a.debit - a.credit), 0)
  const totalLiabilities = (data?.liabilities || []).reduce((s, l) => s + (l.credit - l.debit), 0)
  const totalEquity = (data?.equity || []).reduce((s, e) => s + (e.credit - e.debit), 0)

  return (
    <div>
      <Breadcrumb items={[{ label: t('balanceSheet.breadcrumb') }, { label: t('balanceSheet.title') }]} />
      <PageHeader title={t('balanceSheet.title')} subtitle={t('balanceSheet.subtitle')} />

      {loading ? (
        <SkeletonTable rows={6} cols={3} />
      ) : (
        <div className="grid grid-cols-2 gap-6">
          <div>
            <h3 className="text-sm font-semibold mb-3">{t('balanceSheet.assets')}</h3>
            <Card>
              <Table headers={[t('balanceSheet.code'), t('balanceSheet.account'), t('balanceSheet.amount')]}>
                {(data?.assets || []).map((a) => (
                  <TableRow key={a.code}>
                    <TableCell className="font-mono text-xs">{a.code}</TableCell>
                    <TableCell className="text-sm">{a.name}</TableCell>
                    <TableCell className="font-mono text-right">{formatCurrency(a.debit - a.credit)}</TableCell>
                  </TableRow>
                ))}
                <TableRow>
                  <TableCell /><TableCell className="font-bold">{t('balanceSheet.totalAssets')}</TableCell>
                  <TableCell className="font-mono text-right font-bold text-base">{formatCurrency(totalAssets)}</TableCell>
                </TableRow>
              </Table>
            </Card>
          </div>
          <div>
            <h3 className="text-sm font-semibold mb-3">{t('balanceSheet.liabilities')}</h3>
            <Card>
              <Table headers={[t('balanceSheet.code'), t('balanceSheet.account'), t('balanceSheet.amount')]}>
                {(data?.liabilities || []).map((l) => (
                  <TableRow key={l.code}>
                    <TableCell className="font-mono text-xs">{l.code}</TableCell>
                    <TableCell className="text-sm">{l.name}</TableCell>
                    <TableCell className="font-mono text-right">{formatCurrency(l.credit - l.debit)}</TableCell>
                  </TableRow>
                ))}
                {(data?.equity || []).map((e) => (
                  <TableRow key={e.code}>
                    <TableCell className="font-mono text-xs">{e.code}</TableCell>
                    <TableCell className="text-sm">{e.name}</TableCell>
                    <TableCell className="font-mono text-right">{formatCurrency(e.credit - e.debit)}</TableCell>
                  </TableRow>
                ))}
                <TableRow>
                  <TableCell /><TableCell className="font-bold">{t('balanceSheet.totalLiabilitiesEquity')}</TableCell>
                  <TableCell className="font-mono text-right font-bold text-base">{formatCurrency(totalLiabilities + totalEquity)}</TableCell>
                </TableRow>
              </Table>
            </Card>
          </div>
        </div>
      )}
    </div>
  )
}
