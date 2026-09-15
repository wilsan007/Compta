import { useState, useEffect, useCallback } from 'react'
import { Card, PageHeader, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Badge } from '@/components/ui'
import { getStockReservations, releaseStockReservation } from '@/lib/queries/stock'
import { Package } from 'lucide-react'
import { useTranslation } from 'react-i18next'
import { useToast } from '@/lib/toast'
import { confirmSync } from '@/lib/confirm'

export function StockReservationsPage() {
  const { t } = useTranslation('stock')
  const { t: tNav } = useTranslation('nav')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [reservations, setReservations] = useState<any[]>([])
  const [loading, setLoading] = useState(true)

  const loadData = useCallback(async () => {
    try {
      const data = await getStockReservations()
      setReservations(data || [])
    } catch (err: any) { console.error('Error:', err); toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadError')) }
    finally { setLoading(false) }
  }, [toast, tCommon])

  useEffect(() => { loadData() }, [loadData])

  const handleRelease = async (id: string) => {
    if (!confirmSync('Libérer cette réservation ?')) return
    try {
      await releaseStockReservation(id)
      await loadData()
    } catch (err: any) { console.error('Error:', err); toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadError')) }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('stock'), path: '/stock' }, { label: t('reservations') }]} />
      <PageHeader title={t('reservations')} />

      <Card>
        {loading ? (
          <SkeletonTable cols={6} rows={5} />
        ) : reservations.length === 0 ? (
          <EmptyState icon={<Package className="w-12 h-12" />} title={t('no_reservations')} />
        ) : (
          <Table headers={[t('product'), t('warehouse', { defaultValue: 'Dépôt' }), t('quantity'), t('reference'), t('status'), t('created_at'), t('actions')]}>
            {reservations.map((r) => (
              <TableRow key={r.id}>
                <TableCell>{r.products?.name || '—'}</TableCell>
                <TableCell className="text-xs">{r.warehouses?.name || (r.warehouse_id ? r.warehouse_id.slice(0, 8) : '—')}</TableCell>
                <TableCell className="font-mono">{r.quantity}</TableCell>
                <TableCell className="text-xs">{r.reference_type} #{r.reference_id?.slice(0, 8)}</TableCell>
                <TableCell>
                  <Badge variant={r.status === 'active' ? 'success' : 'neutral'}>{r.status}</Badge>
                </TableCell>
                <TableCell className="text-xs">{new Date(r.created_at).toLocaleDateString()}</TableCell>
                <TableCell>
                  {r.status === 'active' && (
                    <button onClick={() => handleRelease(r.id)} className="text-red-600 hover:underline text-sm">
                      {t('release')}
                    </button>
                  )}
                </TableCell>
              </TableRow>
            ))}
          </Table>
        )}
      </Card>
    </div>
  )
}
