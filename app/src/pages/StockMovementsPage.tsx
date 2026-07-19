import { useEffect, useState, useCallback } from 'react'
import { Card, PageHeader, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Select } from '@/components/ui'
import { formatCurrency, formatDate } from '@/lib/utils'
import { getStockMovements, getWarehouses } from '@/lib/queries'
import { ArrowLeftRight } from 'lucide-react'
import type { Warehouse } from '@/types'

const typeLabels: Record<string, string> = { in: 'Entrée', out: 'Sortie', transfer: 'Transfert', adjustment: 'Ajustement', initial: 'Initial' }
const typeColors: Record<string, string> = { in: 'text-[var(--color-success)]', out: 'text-[var(--color-danger)]', transfer: 'text-[var(--color-primary)]', adjustment: 'text-[var(--color-warning)]', initial: 'text-[var(--color-text-secondary)]' }

export function StockMovementsPage() {
  const [movements, setMovements] = useState<any[]>([])
  const [warehouses, setWarehouses] = useState<Warehouse[]>([])
  const [loading, setLoading] = useState(true)
  const [whFilter, setWhFilter] = useState('')

  const loadData = useCallback(async () => {
    try {
      const [movs, whs] = await Promise.all([getStockMovements(undefined, whFilter || undefined), getWarehouses()])
      setMovements(movs || [])
      setWarehouses(whs || [])
    } catch (err) { console.error('Error:', err) }
    finally { setLoading(false) }
  }, [whFilter])

  useEffect(() => { loadData() }, [loadData])

  return (
    <div>
      <Breadcrumb items={[{ label: 'Stock' }, { label: 'Mouvements' }]} />
      <PageHeader title="Mouvements de stock" subtitle={`${movements.length} mouvement(s)`} />

      <div className="flex gap-3 mb-4 items-end">
        <div className="w-48">
          <Select label="Dépôt" value={whFilter} onChange={(e) => setWhFilter(e.target.value)} options={[
            { value: '', label: 'Tous' }, ...warehouses.map((w) => ({ value: w.id, label: w.name })),
          ]} />
        </div>
      </div>

      {loading ? <SkeletonTable rows={8} cols={6} /> : movements.length === 0 ? (
        <EmptyState icon={<ArrowLeftRight className="w-8 h-8" />} title="Aucun mouvement" description="Aucun mouvement de stock enregistré." />
      ) : (
        <Card>
          <Table headers={['Date', 'Produit', 'Type', 'Quantité', 'Coût unit.', 'Dépôt', 'Référence']}>
            {movements.map((m) => (
              <TableRow key={m.id}>
                <TableCell className="text-xs">{formatDate(m.movement_date)}</TableCell>
                <TableCell className="text-sm">{m.products?.name || '—'}</TableCell>
                <TableCell className={`text-xs font-semibold ${typeColors[m.movement_type] || ''}`}>{typeLabels[m.movement_type] || m.movement_type}</TableCell>
                <TableCell className={`font-mono text-xs ${typeColors[m.movement_type] || ''}`}>
                  {m.movement_type === 'in' || m.movement_type === 'initial' ? '+' : m.movement_type === 'out' ? '−' : ''}{Number(m.quantity)}
                </TableCell>
                <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(m.unit_cost))}</TableCell>
                <TableCell className="text-xs">{m.warehouses?.name || '—'}</TableCell>
                <TableCell className="font-mono text-xs">{m.reference || '—'}</TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}
    </div>
  )
}
