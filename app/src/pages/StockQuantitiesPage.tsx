import { useEffect, useState, useCallback } from 'react'
import { Card, PageHeader, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Select } from '@/components/ui'
import { formatCurrency } from '@/lib/utils'
import { getStockQuantities, getWarehouses } from '@/lib/queries'
import { Boxes } from 'lucide-react'
import type { Warehouse } from '@/types'

export function StockQuantitiesPage() {
  const [stock, setStock] = useState<any[]>([])
  const [warehouses, setWarehouses] = useState<Warehouse[]>([])
  const [loading, setLoading] = useState(true)
  const [whFilter, setWhFilter] = useState('')

  const loadData = useCallback(async () => {
    try {
      const [stk, whs] = await Promise.all([getStockQuantities(whFilter || undefined), getWarehouses()])
      setStock(stk || [])
      setWarehouses(whs || [])
    } catch (err) { console.error('Error:', err) }
    finally { setLoading(false) }
  }, [whFilter])

  useEffect(() => { loadData() }, [loadData])

  const totalValue = stock.reduce((s, q) => s + Number(q.quantity) * Number(q.unit_cost), 0)
  const totalQty = stock.reduce((s, q) => s + Number(q.quantity), 0)
  const lowStock = stock.filter((q) => q.reorder_point > 0 && Number(q.quantity) <= Number(q.reorder_point))

  return (
    <div>
      <Breadcrumb items={[{ label: 'Stock' }, { label: 'Quantités' }]} />
      <PageHeader title="Quantités en stock" subtitle={`${stock.length} ligne(s) — ${totalQty} unités`} />

      <div className="grid grid-cols-3 gap-4 mb-6">
        <Card><div className="p-4"><p className="text-sm text-[var(--color-text-secondary)]">Total articles</p><p className="text-2xl font-bold">{totalQty}</p></div></Card>
        <Card><div className="p-4"><p className="text-sm text-[var(--color-text-secondary)]">Valeur stock</p><p className="text-2xl font-bold font-mono">{formatCurrency(totalValue)}</p></div></Card>
        <Card><div className="p-4"><p className="text-sm text-[var(--color-text-secondary)]">Sous le seuil</p><p className="text-2xl font-bold text-[var(--color-danger)]">{lowStock.length}</p></div></Card>
      </div>

      <div className="flex gap-3 mb-4 items-end">
        <div className="w-48">
          <Select label="Dépôt" value={whFilter} onChange={(e) => setWhFilter(e.target.value)} options={[
            { value: '', label: 'Tous' }, ...warehouses.map((w) => ({ value: w.id, label: w.name })),
          ]} />
        </div>
      </div>

      {loading ? <SkeletonTable rows={8} cols={6} /> : stock.length === 0 ? (
        <EmptyState icon={<Boxes className="w-8 h-8" />} title="Aucun stock" description="Aucune quantité en stock." />
      ) : (
        <Card>
          <Table headers={['Produit', 'SKU', 'Dépôt', 'Quantité', 'Réservé', 'Coût unitaire', 'Valeur', 'Seuil']}>
            {stock.map((q) => (
              <TableRow key={q.id}>
                <TableCell className="text-sm">{q.products?.name || '—'}</TableCell>
                <TableCell className="font-mono text-xs">{q.products?.sku || '—'}</TableCell>
                <TableCell className="text-xs">{q.warehouses?.name || '—'}</TableCell>
                <TableCell className="font-mono text-xs">{Number(q.quantity)}</TableCell>
                <TableCell className="font-mono text-xs text-[var(--color-warning)]">{Number(q.reserved_quantity)}</TableCell>
                <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(q.unit_cost))}</TableCell>
                <TableCell className="font-mono text-xs font-semibold text-right">{formatCurrency(Number(q.quantity) * Number(q.unit_cost))}</TableCell>
                <TableCell className={`font-mono text-xs ${Number(q.quantity) <= Number(q.reorder_point) && q.reorder_point > 0 ? 'text-[var(--color-danger)] font-bold' : ''}`}>
                  {q.reorder_point > 0 ? Number(q.reorder_point) : '—'}
                </TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}
    </div>
  )
}
