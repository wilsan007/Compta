// X4 (C9, C10 — 280) : une commande porte des LIGNES (article, quantité, prix,
// TVA). Les montants affichés ici sont un aperçu ; les montants enregistrés sont
// calculés par la base (`line_amounts`, déclencheurs de la 280), comme pour les
// factures.
import { useTranslation } from 'react-i18next'
import { Plus, Trash2 } from 'lucide-react'
import { formatCurrency } from '@/lib/utils'
import type { Product } from '@/types'
import { emptyOrderLine, orderLinesTotals, type OrderLineDraft } from '@/lib/orderLines'

export function OrderLinesEditor({ lines, onChange, products, priceField, defaultVatRate }: {
  lines: OrderLineDraft[]
  onChange: (lines: OrderLineDraft[]) => void
  products: Product[]
  /** prix proposé à la sélection d'un article : achat (commande fournisseur) ou vente */
  priceField: 'purchase_price' | 'sale_price'
  defaultVatRate: number
}) {
  const { t } = useTranslation('common')
  const totals = orderLinesTotals(lines)

  function update(i: number, patch: Partial<OrderLineDraft>) {
    onChange(lines.map((l, k) => (k === i ? { ...l, ...patch } : l)))
  }
  function selectProduct(i: number, id: string) {
    const p = products.find((x) => x.id === id)
    update(i, p
      ? { product_id: id, description: p.name, unit_price: Number(p[priceField]) || 0, vat_rate: Number(p.vat_rate ?? defaultVatRate) }
      : { product_id: '' })
  }

  return (
    <div className="space-y-2">
      <div className="text-sm font-medium text-[var(--color-text-secondary)]">{t('orderLines.title')}</div>
      <div className="overflow-x-auto">
        <table className="w-full text-xs">
          <thead>
            <tr className="text-left text-[var(--color-text-secondary)]">
              <th className="py-1 pr-2">{t('orderLines.product')}</th>
              <th className="py-1 pr-2">{t('orderLines.description')}</th>
              <th className="py-1 pr-2 w-20">{t('orderLines.quantity')}</th>
              <th className="py-1 pr-2 w-24">{t('orderLines.unitPrice')}</th>
              <th className="py-1 pr-2 w-16">{t('orderLines.vatRate')}</th>
              <th className="py-1 pr-2 w-24 text-right">{t('orderLines.total')}</th>
              <th className="py-1 w-8"><span className="sr-only">{t('actions.delete')}</span></th>
            </tr>
          </thead>
          <tbody>
            {lines.map((l, i) => (
              <tr key={i}>
                <td className="py-1 pr-2">
                  <select className="input text-xs min-w-[10rem]" aria-label={t('orderLines.product')} value={l.product_id} onChange={(e) => selectProduct(i, e.target.value)}>
                    <option value="">{t('form.selectOption')}</option>
                    {products.map((p) => <option key={p.id} value={p.id}>{p.sku ? `${p.sku} — ` : ''}{p.name}</option>)}
                  </select>
                </td>
                <td className="py-1 pr-2">
                  <input className="input text-xs min-w-[8rem]" aria-label={t('orderLines.description')} value={l.description} onChange={(e) => update(i, { description: e.target.value })} />
                </td>
                <td className="py-1 pr-2">
                  <input className="input text-xs min-w-[4.5rem]" type="number" step="0.01" min="0" aria-label={t('orderLines.quantity')} value={l.quantity} onChange={(e) => update(i, { quantity: Number(e.target.value) })} />
                </td>
                <td className="py-1 pr-2">
                  <input className="input text-xs min-w-[6rem]" type="number" step="0.01" min="0" aria-label={t('orderLines.unitPrice')} value={l.unit_price} onChange={(e) => update(i, { unit_price: Number(e.target.value) })} />
                </td>
                <td className="py-1 pr-2">
                  <input className="input text-xs min-w-[4.5rem]" type="number" step="0.01" min="0" aria-label={t('orderLines.vatRate')} value={l.vat_rate} onChange={(e) => update(i, { vat_rate: Number(e.target.value) })} />
                </td>
                <td className="py-1 pr-2 text-right font-mono">{formatCurrency(orderLinesTotals([l]).ht)}</td>
                <td className="py-1">
                  <button type="button" onClick={() => onChange(lines.filter((_, k) => k !== i))} disabled={lines.length <= 1}
                    className="p-1 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)] disabled:opacity-40"
                    aria-label={t('actions.delete')} title={t('actions.delete')}>
                    <Trash2 className="w-3.5 h-3.5" aria-hidden="true" />
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <button type="button" onClick={() => onChange([...lines, emptyOrderLine(defaultVatRate)])}
        className="text-xs inline-flex items-center gap-1 text-[var(--color-primary)] hover:underline">
        <Plus className="w-3.5 h-3.5" aria-hidden="true" /> {t('orderLines.add')}
      </button>
      <div className="flex justify-end gap-6 text-xs pt-1 border-t border-[var(--color-border)]">
        <span>{t('orderLines.subtotal')} : <span className="font-mono">{formatCurrency(totals.ht)}</span></span>
        <span>{t('orderLines.vat')} : <span className="font-mono">{formatCurrency(totals.tva)}</span></span>
        <span className="font-semibold">{t('orderLines.totalTtc')} : <span className="font-mono">{formatCurrency(totals.ttc)}</span></span>
      </div>
    </div>
  )
}
