import { useEffect, useState, useCallback } from 'react'
import { Card, PageHeader, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable } from '@/components/ui'
import { formatCurrency } from '@/lib/utils'
import { getStockQuantities } from '@/lib/queries'
import { AlertTriangle, ShoppingCart } from 'lucide-react'
import { useTranslation } from 'react-i18next'

export function ReorderPage() {
  const { t } = useTranslation('stock')
  const { t: tNav } = useTranslation('nav')
  const [stock, setStock] = useState<any[]>([])
  const [loading, setLoading] = useState(true)

  const loadData = useCallback(async () => {
    try { setStock(await getStockQuantities()) }
    catch (err) { console.error('Error:', err) }
    finally { setLoading(false) }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  const reorderItems = stock.filter((q) => q.reorder_point > 0 && Number(q.quantity) <= Number(q.reorder_point))
  const totalReorderValue = reorderItems.reduce((s, q) => s + (Number(q.reorder_point) - Number(q.quantity)) * Number(q.unit_cost), 0)

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('sections.stock') }, { label: t('reorder.title') }]} />
      <PageHeader title={t('reorder.title')} subtitle={`${reorderItems.length} ${t('reorder.product').toLowerCase()}(s)`} />

      <div className="grid grid-cols-2 gap-4 mb-6">
        <Card><div className="p-4"><p className="text-sm text-[var(--color-text-secondary)] flex items-center gap-1"><AlertTriangle className="w-4 h-4 text-[var(--color-danger)]" /> {t('reorder.itemsToReorder')}</p><p className="text-2xl font-bold text-[var(--color-danger)]">{reorderItems.length}</p></div></Card>
        <Card><div className="p-4"><p className="text-sm text-[var(--color-text-secondary)] flex items-center gap-1"><ShoppingCart className="w-4 h-4 text-[var(--color-primary)]" /> {t('reorder.estimatedValue')}</p><p className="text-2xl font-bold font-mono">{formatCurrency(totalReorderValue)}</p></div></Card>
      </div>

      {loading ? <SkeletonTable rows={6} cols={6} /> : reorderItems.length === 0 ? (
        <EmptyState icon={<ShoppingCart className="w-8 h-8" />} title={t('reorder.noReorder')} description={t('reorder.allGood')} />
      ) : (
        <Card>
          <Table headers={[t('reorder.product'), t('reorder.sku'), t('quantities.warehouse'), t('reorder.currentStock'), t('reorder.reorderPoint'), t('reorder.toOrder'), t('reorder.estimatedCost')]}>
            {reorderItems.map((q) => {
              const toOrder = Number(q.reorder_point) - Number(q.quantity)
              return (
                <TableRow key={q.id}>
                  <TableCell className="text-sm">{q.products?.name || '—'}</TableCell>
                  <TableCell className="font-mono text-xs">{q.products?.sku || '—'}</TableCell>
                  <TableCell className="text-xs">{q.warehouses?.name || '—'}</TableCell>
                  <TableCell className="font-mono text-xs text-[var(--color-danger)]">{Number(q.quantity)}</TableCell>
                  <TableCell className="font-mono text-xs">{Number(q.reorder_point)}</TableCell>
                  <TableCell className="font-mono text-xs font-bold text-[var(--color-warning)]">{toOrder}</TableCell>
                  <TableCell className="font-mono text-xs text-right">{formatCurrency(toOrder * Number(q.unit_cost))}</TableCell>
                </TableRow>
              )
            })}
          </Table>
        </Card>
      )}
    </div>
  )
}
