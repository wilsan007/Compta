import { useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Select } from '@/components/ui'
import { useLocale } from '@/hooks/useLocale'
import { getEcheancier } from '@/lib/queries'
import { CalendarClock, AlertTriangle } from 'lucide-react'

export function EcheancierPage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { formatCurrency, formatDate } = useLocale()
  const [data, setData] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [typeFilter, setTypeFilter] = useState('')

  useEffect(() => { load() }, [])

  async function load() {
    setLoading(true)
    try {
      const res = await getEcheancier(typeFilter || undefined)
      setData(res)
    } catch (err) {
      console.error('Error loading echeancier:', err)
    } finally {
      setLoading(false)
    }
  }

  const totalRemaining = data.reduce((s, r) => s + r.remaining, 0)
  const totalOverdue = data.filter((r) => r.days_overdue > 0).reduce((s, r) => s + r.remaining, 0)

  return (
    <div>
      <Breadcrumb items={[{ label: t('title') }, { label: t('home.states') }, { label: t('echeancier.title') }]} />
      <PageHeader title={t('echeancier.title')} subtitle={t('echeancier.subtitle')} />

      <div className="flex gap-3 mb-4 items-end">
        <div className="w-48">
          <Select
            label={t('echeancier.type')}
            value={typeFilter}
            onChange={(e) => { setTypeFilter(e.target.value); }}
            options={[
              { value: '', label: t('echeancier.all') },
              { value: 'customer', label: t('echeancier.customers') },
              { value: 'supplier', label: t('echeancier.suppliers') },
            ]}
          />
        </div>
        <button onClick={load} className="btn-secondary text-sm px-4 py-2 rounded-lg">{t('echeancier.refresh')}</button>
        <div className="flex gap-4 ml-auto text-sm">
          <span className="text-[var(--color-text-secondary)]">{t('echeancier.remainingToPay')}: <strong className="font-mono">{formatCurrency(totalRemaining)}</strong></span>
          {totalOverdue > 0 && (
            <span className="text-[var(--color-danger)] flex items-center gap-1">
              <AlertTriangle className="w-3.5 h-3.5" /> {t('echeancier.overdue')}: <strong className="font-mono">{formatCurrency(totalOverdue)}</strong>
            </span>
          )}
        </div>
      </div>

      {loading ? (
        <SkeletonTable rows={6} cols={7} />
      ) : data.length === 0 ? (
        <EmptyState
          icon={<CalendarClock className="w-8 h-8" />}
          title={t('echeancier.noData')}
          description={t('echeancier.noDataDescription')}
        />
      ) : (
        <Card>
          <Table headers={[t('echeancier.type'), t('echeancier.number'), t('echeancier.thirdParty'), t('echeancier.date'), t('echeancier.dueDate'), t('echeancier.amount'), t('echeancier.remaining'), t('echeancier.daysOverdue')]}>
            {data.map((r, i) => (
              <TableRow key={i}>
                <TableCell>
                  <Badge variant={r.type === 'customer' ? 'success' : 'warning'}>
                    {r.type === 'customer' ? t('echeancier.customer') : t('echeancier.supplier')}
                  </Badge>
                </TableCell>
                <TableCell className="font-mono text-xs">{r.number}</TableCell>
                <TableCell className="text-sm">{r.third_party_name}</TableCell>
                <TableCell className="text-xs">{formatDate(r.date)}</TableCell>
                <TableCell className="text-xs">{formatDate(r.due_date)}</TableCell>
                <TableCell className="font-mono text-xs text-right">{formatCurrency(r.amount)}</TableCell>
                <TableCell className="font-mono text-xs font-bold text-right">{formatCurrency(r.remaining)}</TableCell>
                <TableCell className={`text-xs font-semibold ${r.days_overdue > 0 ? 'text-[var(--color-danger)]' : 'text-[var(--color-text-secondary)]'}`}>
                  {r.days_overdue > 0 ? `${r.days_overdue} ${tCommon('dates.days')}` : '—'}
                </TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}
    </div>
  )
}
