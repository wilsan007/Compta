import { useEffect, useState } from 'react'
import { Card, PageHeader, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Select } from '@/components/ui'
import { formatCurrency, formatDate } from '@/lib/utils'
import { getEcheancier } from '@/lib/queries'
import { CalendarClock, AlertTriangle } from 'lucide-react'

export function EcheancierPage() {
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
      <Breadcrumb items={[{ label: 'Comptabilité' }, { label: 'États' }, { label: 'Échéancier' }]} />
      <PageHeader title="Échéancier" subtitle="Échéances de règlement à venir" />

      <div className="flex gap-3 mb-4 items-end">
        <div className="w-48">
          <Select
            label="Type"
            value={typeFilter}
            onChange={(e) => { setTypeFilter(e.target.value); }}
            options={[
              { value: '', label: 'Tous' },
              { value: 'customer', label: 'Clients' },
              { value: 'supplier', label: 'Fournisseurs' },
            ]}
          />
        </div>
        <button onClick={load} className="btn-secondary text-sm px-4 py-2 rounded-lg">Actualiser</button>
        <div className="flex gap-4 ml-auto text-sm">
          <span className="text-[var(--color-text-secondary)]">Restant à régler: <strong className="font-mono">{formatCurrency(totalRemaining)}</strong></span>
          {totalOverdue > 0 && (
            <span className="text-[var(--color-danger)] flex items-center gap-1">
              <AlertTriangle className="w-3.5 h-3.5" /> En retard: <strong className="font-mono">{formatCurrency(totalOverdue)}</strong>
            </span>
          )}
        </div>
      </div>

      {loading ? (
        <SkeletonTable rows={6} cols={7} />
      ) : data.length === 0 ? (
        <EmptyState
          icon={<CalendarClock className="w-8 h-8" />}
          title="Aucune échéance"
          description="Aucune facture impayée trouvée."
        />
      ) : (
        <Card>
          <Table headers={['Type', 'N°', 'Tiers', 'Date', 'Échéance', 'Montant', 'Restant', 'Retard (j)']}>
            {data.map((r, i) => (
              <TableRow key={i}>
                <TableCell>
                  <Badge variant={r.type === 'customer' ? 'success' : 'warning'}>
                    {r.type === 'customer' ? 'Client' : 'Fournisseur'}
                  </Badge>
                </TableCell>
                <TableCell className="font-mono text-xs">{r.number}</TableCell>
                <TableCell className="text-sm">{r.third_party_name}</TableCell>
                <TableCell className="text-xs">{formatDate(r.date)}</TableCell>
                <TableCell className="text-xs">{formatDate(r.due_date)}</TableCell>
                <TableCell className="font-mono text-xs text-right">{formatCurrency(r.amount)}</TableCell>
                <TableCell className="font-mono text-xs font-bold text-right">{formatCurrency(r.remaining)}</TableCell>
                <TableCell className={`text-xs font-semibold ${r.days_overdue > 0 ? 'text-[var(--color-danger)]' : 'text-[var(--color-text-secondary)]'}`}>
                  {r.days_overdue > 0 ? `${r.days_overdue} j` : '—'}
                </TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}
    </div>
  )
}
