import { useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Select, Input, Button } from '@/components/ui'
import { formatCurrency } from '@/lib/utils'
import { getAgedBalance } from '@/lib/queries'
import { Clock } from 'lucide-react'

export function AgedBalancePage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const [data, setData] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [typeFilter, setTypeFilter] = useState('')
  const [refDate, setRefDate] = useState('')

  useEffect(() => { load() }, [])

  async function load() {
    setLoading(true)
    try {
      const res = await getAgedBalance(typeFilter || undefined, refDate || undefined)
      setData(res)
    } catch (err) {
      console.error('Error loading aged balance:', err)
    } finally {
      setLoading(false)
    }
  }

  const totals = data.reduce((acc, r) => ({
    total: acc.total + r.total,
    b0_30: acc.b0_30 + r.bucket0_30,
    b31_60: acc.b31_60 + r.bucket31_60,
    b61_90: acc.b61_90 + r.bucket61_90,
    b90p: acc.b90p + r.bucket90p,
  }), { total: 0, b0_30: 0, b31_60: 0, b61_90: 0, b90p: 0 })

  return (
    <div>
      <Breadcrumb items={[{ label: t('title') }, { label: t('agedBalance.breadcrumb') }, { label: t('agedBalance.title') }]} />
      <PageHeader title={t('agedBalance.title')} subtitle={t('agedBalance.subtitle')} />

      <Card className="mb-4">
        <div className="p-4 flex gap-3 items-end">
          <div className="w-48">
            <Select
              label={t('agedBalance.type')}
              value={typeFilter}
              onChange={(e) => setTypeFilter(e.target.value)}
              options={[
                { value: '', label: tCommon('common.all') },
                { value: 'customer', label: t('agedBalance.customer') },
                { value: 'supplier', label: t('agedBalance.supplier') },
              ]}
            />
          </div>
          <div className="w-48">
            <Input label={t('agedBalance.refDate')} type="date" value={refDate} onChange={(e) => setRefDate(e.target.value)} />
          </div>
          <Button onClick={load} disabled={loading}>{tCommon('actions.refresh')}</Button>
        </div>
      </Card>

      {loading ? (
        <SkeletonTable rows={6} cols={7} />
      ) : data.length === 0 ? (
        <EmptyState
          icon={<Clock className="w-8 h-8" />}
          title={tCommon('common.noData')}
          description={t('agedBalance.noDataDescription')}
        />
      ) : (
        <div className="space-y-4">
          <div className="grid grid-cols-5 gap-4">
            <div className="card p-3">
              <p className="text-xs text-[var(--color-text-secondary)]">{tCommon('common.total')}</p>
              <p className="text-lg font-bold font-mono">{formatCurrency(totals.total)}</p>
            </div>
            <div className="card p-3">
              <p className="text-xs text-[var(--color-text-secondary)]">{t('agedBalance.0-30')}</p>
              <p className="text-lg font-bold font-mono text-[var(--color-success)]">{formatCurrency(totals.b0_30)}</p>
            </div>
            <div className="card p-3">
              <p className="text-xs text-[var(--color-text-secondary)]">{t('agedBalance.31-60')}</p>
              <p className="text-lg font-bold font-mono">{formatCurrency(totals.b31_60)}</p>
            </div>
            <div className="card p-3">
              <p className="text-xs text-[var(--color-text-secondary)]">{t('agedBalance.61-90')}</p>
              <p className="text-lg font-bold font-mono text-[var(--color-warning)]">{formatCurrency(totals.b61_90)}</p>
            </div>
            <div className="card p-3">
              <p className="text-xs text-[var(--color-text-secondary)]">{t('agedBalance.90+')}</p>
              <p className="text-lg font-bold font-mono text-[var(--color-danger)]">{formatCurrency(totals.b90p)}</p>
            </div>
          </div>

          <Card>
            <Table headers={[t('agedBalance.account'), t('agedBalance.thirdParty'), t('agedBalance.type'), t('agedBalance.0-30'), t('agedBalance.31-60'), t('agedBalance.61-90'), t('agedBalance.90+'), tCommon('common.total')]}>
              {data.map((r) => (
                <TableRow key={r.code}>
                  <TableCell className="font-mono text-xs font-semibold">{r.code}</TableCell>
                  <TableCell className="text-sm">{r.name}</TableCell>
                  <TableCell className="text-xs">{r.type === 'customer' ? t('agedBalance.customer') : r.type === 'supplier' ? t('agedBalance.supplier') : r.type}</TableCell>
                  <TableCell className="font-mono text-xs text-right">{r.bucket0_30 !== 0 ? formatCurrency(r.bucket0_30) : ''}</TableCell>
                  <TableCell className="font-mono text-xs text-right">{r.bucket31_60 !== 0 ? formatCurrency(r.bucket31_60) : ''}</TableCell>
                  <TableCell className="font-mono text-xs text-right">{r.bucket61_90 !== 0 ? formatCurrency(r.bucket61_90) : ''}</TableCell>
                  <TableCell className="font-mono text-xs text-[var(--color-danger)] text-right">{r.bucket90p !== 0 ? formatCurrency(r.bucket90p) : ''}</TableCell>
                  <TableCell className="font-mono text-xs font-bold text-right">{formatCurrency(r.total)}</TableCell>
                </TableRow>
              ))}
              <TableRow>
                <TableCell colSpan={3} className="font-bold">{tCommon('common.total')}</TableCell>
                <TableCell className="font-mono font-bold text-xs text-right">{formatCurrency(totals.b0_30)}</TableCell>
                <TableCell className="font-mono font-bold text-xs text-right">{formatCurrency(totals.b31_60)}</TableCell>
                <TableCell className="font-mono font-bold text-xs text-right">{formatCurrency(totals.b61_90)}</TableCell>
                <TableCell className="font-mono font-bold text-xs text-right">{formatCurrency(totals.b90p)}</TableCell>
                <TableCell className="font-mono font-bold text-xs text-right">{formatCurrency(totals.total)}</TableCell>
              </TableRow>
            </Table>
          </Card>
        </div>
      )}
    </div>
  )
}
