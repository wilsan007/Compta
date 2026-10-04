import { useState, useCallback } from 'react'
import { Card, PageHeader, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Button } from '@/components/ui'
import { traceLotDownstream, traceLotUpstream, type LotMovement } from '@/lib/queries/stock'
import { Search } from 'lucide-react'
import { useTranslation } from 'react-i18next'
import { useToast } from '@/lib/toast'
import { errorMessage } from '@/lib/utils'

export function LotTraceabilityPage() {
  const { t } = useTranslation('stock')
  const { t: tNav } = useTranslation('nav')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [lotId, setLotId] = useState('')
  const [direction, setDirection] = useState<'downstream' | 'upstream'>('downstream')
  const [results, setResults] = useState<LotMovement[]>([])
  const [loading, setLoading] = useState(false)
  const [searched, setSearched] = useState(false)

  const handleSearch = useCallback(async () => {
    if (!lotId.trim()) return
    setLoading(true)
    setSearched(true)
    try {
      const data = direction === 'downstream'
        ? await traceLotDownstream(lotId.trim())
        : await traceLotUpstream(lotId.trim())
      setResults(data?.movements || [])
    } catch (err) { console.error('Error:', err); toast('error', tCommon('toast.error'), errorMessage(err) || tCommon('toast.loadingError')) }
    finally { setLoading(false) }
  }, [lotId, direction, tCommon, toast])

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('groups.stock'), path: '/stock' }, { label: t('traceability') }]} />
      <PageHeader title={t('traceability')} />

      <Card className="mb-4">
        <div className="flex gap-4 items-end">
          <div className="flex-1">
            <label className="block text-sm font-medium mb-1">{t('lot_id')}</label>
            <input
              type="text"
              value={lotId}
              onChange={(e) => setLotId(e.target.value)}
              placeholder={t('lot_id_placeholder')}
              onKeyDown={(e) => { if (e.key === 'Enter') handleSearch() }}
              className="w-full border rounded px-3 py-2"
            />
          </div>
          <div>
            <label className="block text-sm font-medium mb-1">{t('direction')}</label>
            <select
              value={direction}
              onChange={(e) => setDirection(e.target.value as 'downstream' | 'upstream')}
              className="border rounded px-3 py-2"
            >
              <option value="downstream">{t('downstream')} (lot → clients)</option>
              <option value="upstream">{t('upstream')} (lot → OF → produits)</option>
            </select>
          </div>
          <Button onClick={handleSearch} disabled={loading || !lotId.trim()}>
            {loading ? '...' : t('search')}
          </Button>
        </div>
      </Card>

      <Card>
        {loading ? (
          <SkeletonTable cols={6} rows={3} />
        ) : !searched ? (
          <EmptyState icon={<Search className="w-12 h-12" />} title={t('search_lot_to_trace')} />
        ) : results.length === 0 ? (
          <EmptyState icon={<Search className="w-12 h-12" />} title={t('no_results')} />
        ) : (
          // 2.16 : les deux sens rendent des MOUVEMENTS de stock (aval : du plus récent au plus
          // ancien ; amont : l'inverse). L'écran lisait `product_name`, `customer_name`,
          // `mo_number` et `quantity_produced`, qu'aucun mouvement ne porte : l'article
          // s'affichait « — » et le tableau amont n'avait que des colonnes vides.
          <Table headers={[t('product'), t('movement_type'), t('date'), t('quantity'), t('reference')]}>
            {results.map((r) => (
              <TableRow key={r.id}>
                <TableCell>{r.products?.name || '—'}</TableCell>
                <TableCell>{r.movement_type || r.type}</TableCell>
                <TableCell className="text-xs">{r.movement_date ? new Date(r.movement_date).toLocaleDateString() : '—'}</TableCell>
                <TableCell className="font-mono">{r.quantity}</TableCell>
                <TableCell className="text-xs">{r.reference || '—'}</TableCell>
              </TableRow>
            ))}
          </Table>
        )}
      </Card>
    </div>
  )
}
