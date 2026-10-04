// X4 (C9, C10 — 280) : brouillon de lignes de commande côté écran. Les montants
// enregistrés sont ceux de la base (`line_amounts`) ; ceux-ci ne sont qu'un aperçu.
export interface OrderLineDraft {
  product_id: string
  description: string
  quantity: number
  unit_price: number
  vat_rate: number
}

export function emptyOrderLine(vatRate: number): OrderLineDraft {
  return { product_id: '', description: '', quantity: 1, unit_price: 0, vat_rate: vatRate }
}

const r2 = (n: number) => Math.round(n * 100) / 100

export function orderLinesTotals(lines: OrderLineDraft[]) {
  let ht = 0
  let tva = 0
  for (const l of lines) {
    const t = r2((Number(l.quantity) || 0) * (Number(l.unit_price) || 0))
    ht += t
    tva += r2(t * (Number(l.vat_rate) || 0) / 100)
  }
  return { ht: r2(ht), tva: r2(tva), ttc: r2(ht + tva) }
}

/** Lignes prêtes à envoyer : un article ou un libellé, une quantité positive. */
export function orderLinesPayload(lines: OrderLineDraft[]) {
  return lines
    .filter((l) => (l.product_id || l.description.trim()) && Number(l.quantity) > 0)
    .map((l) => ({
      product_id: l.product_id || null,
      description: l.description.trim(),
      quantity: Number(l.quantity),
      unit_price: Number(l.unit_price) || 0,
      vat_rate: Number(l.vat_rate) || 0,
    }))
}
