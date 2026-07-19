import { useEffect, useState } from 'react'
import { Card, PageHeader, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Select } from '@/components/ui'
import { formatCurrency, formatDate } from '@/lib/utils'
import { getTreasuryForecast } from '@/lib/queries'
import { TrendingUp, TrendingDown, Calendar } from 'lucide-react'

export function TreasuryForecastPage() {
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
      <Breadcrumb items={[{ label: 'Trésorerie' }, { label: 'Prévisions' }]} />
      <PageHeader title="Prévisions de trésorerie" subtitle="Flux de trésorerie prévisionnels" />

      <div className="flex gap-3 mb-4 items-end">
        <div className="w-48">
          <Select
            label="Horizon"
            value={horizon}
            onChange={(e) => setHorizon(e.target.value)}
            options={[
              { value: '30', label: '30 jours' },
              { value: '60', label: '60 jours' },
              { value: '90', label: '90 jours' },
              { value: '180', label: '180 jours' },
            ]}
          />
        </div>
      </div>

      {loading ? (
        <SkeletonTable rows={8} cols={5} />
      ) : !data || data.timeline.length === 0 ? (
        <EmptyState
          icon={<Calendar className="w-8 h-8" />}
          title="Aucune prévision"
          description="Aucune facture en attente dans cette période."
        />
      ) : (
        <div className="space-y-4">
          <div className="grid grid-cols-4 gap-4">
            <div className="card p-4">
              <p className="text-xs text-[var(--color-text-secondary)] mb-1">Solde actuel</p>
              <p className="text-lg font-bold font-mono">{formatCurrency(data.currentBalance)}</p>
            </div>
            <div className="card p-4">
              <p className="text-xs text-[var(--color-text-secondary)] mb-1 flex items-center gap-1"><TrendingUp className="w-3 h-3 text-[var(--color-success)]" /> Encaissements</p>
              <p className="text-lg font-bold font-mono text-[var(--color-success)]">{formatCurrency(data.totalIncoming)}</p>
            </div>
            <div className="card p-4">
              <p className="text-xs text-[var(--color-text-secondary)] mb-1 flex items-center gap-1"><TrendingDown className="w-3 h-3 text-[var(--color-danger)]" /> Décaissements</p>
              <p className="text-lg font-bold font-mono text-[var(--color-danger)]">{formatCurrency(data.totalOutgoing)}</p>
            </div>
            <div className="card p-4">
              <p className="text-xs text-[var(--color-text-secondary)] mb-1">Solde projeté</p>
              <p className={`text-lg font-bold font-mono ${projectedBalance >= 0 ? 'text-[var(--color-success)]' : 'text-[var(--color-danger)]'}`}>
                {formatCurrency(projectedBalance)}
              </p>
            </div>
          </div>

          <Card title="Timeline des flux">
            <Table headers={['Date', 'Référence', 'Type', 'Montant', 'Solde cumulé']}>
              {data.timeline.map((e: any, i: number) => (
                <TableRow key={i}>
                  <TableCell className="text-xs">{formatDate(e.date)}</TableCell>
                  <TableCell className="font-mono text-xs">{e.reference}</TableCell>
                  <TableCell>
                    <Badge variant={e.type === 'in' ? 'success' : 'danger'}>
                      {e.type === 'in' ? 'Encaissement' : 'Décaissement'}
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
