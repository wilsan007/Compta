import { useEffect, useState } from 'react'
import { Card, PageHeader, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Select, Input, Button } from '@/components/ui'
import { formatCurrency } from '@/lib/utils'
import { getAgedBalance } from '@/lib/queries'
import { Clock } from 'lucide-react'

export function AgedBalancePage() {
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
      <Breadcrumb items={[{ label: 'Comptabilité' }, { label: 'États' }, { label: 'Balance âgée' }]} />
      <PageHeader title="Balance âgée tiers" subtitle="Créances et dettes par tranche d'ancienneté" />

      <Card className="mb-4">
        <div className="p-4 flex gap-3 items-end">
          <div className="w-48">
            <Select
              label="Type de tiers"
              value={typeFilter}
              onChange={(e) => setTypeFilter(e.target.value)}
              options={[
                { value: '', label: 'Tous' },
                { value: 'customer', label: 'Clients' },
                { value: 'supplier', label: 'Fournisseurs' },
              ]}
            />
          </div>
          <div className="w-48">
            <Input label="Date de référence" type="date" value={refDate} onChange={(e) => setRefDate(e.target.value)} />
          </div>
          <Button onClick={load} disabled={loading}>Actualiser</Button>
        </div>
      </Card>

      {loading ? (
        <SkeletonTable rows={6} cols={7} />
      ) : data.length === 0 ? (
        <EmptyState
          icon={<Clock className="w-8 h-8" />}
          title="Aucune donnée"
          description="Aucun solde non lettré trouvé pour les critères sélectionnés."
        />
      ) : (
        <div className="space-y-4">
          <div className="grid grid-cols-5 gap-4">
            <div className="card p-3">
              <p className="text-xs text-[var(--color-text-secondary)]">Total</p>
              <p className="text-lg font-bold font-mono">{formatCurrency(totals.total)}</p>
            </div>
            <div className="card p-3">
              <p className="text-xs text-[var(--color-text-secondary)]">0-30 j</p>
              <p className="text-lg font-bold font-mono text-[var(--color-success)]">{formatCurrency(totals.b0_30)}</p>
            </div>
            <div className="card p-3">
              <p className="text-xs text-[var(--color-text-secondary)]">31-60 j</p>
              <p className="text-lg font-bold font-mono">{formatCurrency(totals.b31_60)}</p>
            </div>
            <div className="card p-3">
              <p className="text-xs text-[var(--color-text-secondary)]">61-90 j</p>
              <p className="text-lg font-bold font-mono text-[var(--color-warning)]">{formatCurrency(totals.b61_90)}</p>
            </div>
            <div className="card p-3">
              <p className="text-xs text-[var(--color-text-secondary)]">+90 j</p>
              <p className="text-lg font-bold font-mono text-[var(--color-danger)]">{formatCurrency(totals.b90p)}</p>
            </div>
          </div>

          <Card>
            <Table headers={['Code', 'Tiers', 'Type', '0-30 j', '31-60 j', '61-90 j', '+90 j', 'Total']}>
              {data.map((r) => (
                <TableRow key={r.code}>
                  <TableCell className="font-mono text-xs font-semibold">{r.code}</TableCell>
                  <TableCell className="text-sm">{r.name}</TableCell>
                  <TableCell className="text-xs">{r.type === 'customer' ? 'Client' : r.type === 'supplier' ? 'Fournisseur' : r.type}</TableCell>
                  <TableCell className="font-mono text-xs text-right">{r.bucket0_30 !== 0 ? formatCurrency(r.bucket0_30) : ''}</TableCell>
                  <TableCell className="font-mono text-xs text-right">{r.bucket31_60 !== 0 ? formatCurrency(r.bucket31_60) : ''}</TableCell>
                  <TableCell className="font-mono text-xs text-right">{r.bucket61_90 !== 0 ? formatCurrency(r.bucket61_90) : ''}</TableCell>
                  <TableCell className="font-mono text-xs text-[var(--color-danger)] text-right">{r.bucket90p !== 0 ? formatCurrency(r.bucket90p) : ''}</TableCell>
                  <TableCell className="font-mono text-xs font-bold text-right">{formatCurrency(r.total)}</TableCell>
                </TableRow>
              ))}
              <TableRow>
                <TableCell colSpan={3} className="font-bold">TOTAUX</TableCell>
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
