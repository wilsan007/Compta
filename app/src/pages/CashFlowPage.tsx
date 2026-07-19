import { useEffect, useState, useCallback } from 'react'
import { Card, PageHeader, SkeletonTable, Breadcrumb, Table, TableRow, TableCell } from '@/components/ui'
import { getCashFlow } from '@/lib/queries'
import { formatCurrency } from '@/lib/utils'

export function CashFlowPage() {
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
      <Breadcrumb items={[{ label: 'Rapports' }, { label: 'Flux de trésorerie' }]} />
      <PageHeader title="Flux de trésorerie" subtitle="Analyse de vos flux de trésorerie" />

      {loading ? (
        <SkeletonTable rows={4} cols={4} />
      ) : data ? (
        <>
          <div className="grid grid-cols-3 gap-4 mb-6">
            <Card>
              <div className="p-4">
                <p className="text-sm text-[var(--color-text-secondary)]">Entrées</p>
                <p className="text-2xl font-bold font-mono text-[var(--color-success)]">{formatCurrency(data.inflow)}</p>
              </div>
            </Card>
            <Card>
              <div className="p-4">
                <p className="text-sm text-[var(--color-text-secondary)]">Sorties</p>
                <p className="text-2xl font-bold font-mono text-[var(--color-danger)]">{formatCurrency(data.outflow)}</p>
              </div>
            </Card>
            <Card>
              <div className="p-4">
                <p className="text-sm text-[var(--color-text-secondary)]">Flux net</p>
                <p className={`text-2xl font-bold font-mono ${data.net >= 0 ? 'text-[var(--color-success)]' : 'text-[var(--color-danger)]'}`}>{formatCurrency(data.net)}</p>
              </div>
            </Card>
          </div>

          <Card>
            <h3 className="text-sm font-semibold p-4 border-b border-[var(--color-border)]">Flux par mois</h3>
            <Table headers={['Mois', 'Entrées', 'Sorties', 'Net']}>
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
                <TableRow><TableCell colSpan={4} className="text-center text-[var(--color-text-secondary)]">Aucune donnée</TableCell></TableRow>
              )}
            </Table>
          </Card>
        </>
      ) : null}
    </div>
  )
}
