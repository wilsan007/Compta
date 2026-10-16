// D-B (280) : les mouvements de stock enregistrés sans effet avant la 280
// (« fantômes ») ne sont PAS rejoués automatiquement. Ils sont listés ici et
// l'utilisateur décide, un par un : rejouer (un mouvement neuf, daté du jour de
// la décision) ou ignorer. Un inventaire fantôme ne se rejoue pas.
import { useCallback, useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { AlertTriangle } from 'lucide-react'
import { Button, Card } from '@/components/ui'
import { formatDate } from '@/lib/utils'
import { getStockMovementPhantoms, resolveStockMovementPhantom, type StockMovementPhantom } from '@/lib/queries/stockPhantoms'
import { useToast } from '@/lib/toast'
import { confirmDialog } from '@/lib/confirm'

export function StockPhantomsPanel({ onResolved }: { onResolved?: () => void }) {
  const { t } = useTranslation('stock')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [rows, setRows] = useState<(StockMovementPhantom & { products?: { name: string; sku: string | null } | null })[]>([])
  const [busy, setBusy] = useState<string | null>(null)

  const load = useCallback(async () => {
    try { setRows(await getStockMovementPhantoms()) }
    catch (err: any) { toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadingError')) }
  }, [toast, tCommon])

  useEffect(() => { load() }, [load])

  async function decide(id: string, decision: 'replayed' | 'ignored') {
    if (!(await confirmDialog(t(decision === 'replayed' ? 'phantoms.confirmReplay' : 'phantoms.confirmIgnore')))) return
    setBusy(id)
    try {
      await resolveStockMovementPhantom(id, decision)
      await load()
      onResolved?.()
    } catch (err: any) { toast('error', tCommon('toast.error'), err.message || tCommon('toast.error')) }
    finally { setBusy(null) }
  }

  if (rows.length === 0) return null
  return (
    <Card className="mb-4 border border-[var(--color-warning)]">
      <div className="p-4 space-y-3">
        <div className="flex items-start gap-2">
          <AlertTriangle className="w-5 h-5 text-[var(--color-warning)] flex-shrink-0" aria-hidden="true" />
          <div>
            <h2 className="font-semibold">{t('phantoms.title', { count: rows.length })}</h2>
            <p className="text-sm text-[var(--color-text-secondary)]">{t('phantoms.description')}</p>
          </div>
        </div>
        <table className="w-full text-xs">
          <thead>
            <tr className="text-left text-[var(--color-text-secondary)]">
              <th className="py-1">{t('phantoms.date')}</th>
              <th className="py-1">{t('phantoms.product')}</th>
              <th className="py-1">{t('phantoms.type')}</th>
              <th className="py-1 text-right">{t('phantoms.quantity')}</th>
              <th className="py-1">{t('phantoms.reference')}</th>
              <th className="py-1 text-right">{tCommon('table.actions')}</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r.id} className="border-t border-[var(--color-border)]">
                <td className="py-1">{r.movement_date ? formatDate(r.movement_date) : '—'}</td>
                <td className="py-1">{r.products?.name ?? '—'}</td>
                <td className="py-1">{t(`products.movementTypes.${r.type}`, { defaultValue: r.type })}</td>
                <td className="py-1 text-right font-mono">{Number(r.quantity)}</td>
                <td className="py-1">{r.reference ?? '—'}</td>
                <td className="py-1 text-right space-x-2">
                  {['in', 'out', 'initial'].includes(r.type) && (
                    <Button size="sm" variant="secondary" disabled={busy === r.id} onClick={() => decide(r.id, 'replayed')}>{t('phantoms.replay')}</Button>
                  )}
                  <Button size="sm" variant="ghost" disabled={busy === r.id} onClick={() => decide(r.id, 'ignored')}>{t('phantoms.ignore')}</Button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </Card>
  )
}
