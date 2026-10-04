import { describe, it, expect } from 'vitest'
import { emptyOrderLine, orderLinesPayload, orderLinesTotals } from '@/lib/orderLines'

// X4 (C9, C10 — 280) : l'aperçu de l'écran suit la règle de la base
// (`line_amounts` : HT arrondi par ligne, TVA arrondie par ligne).
describe('lignes de commande (aperçu écran)', () => {
  it('totalise HT, TVA et TTC ligne à ligne, arrondis au centime', () => {
    const t = orderLinesTotals([
      { product_id: 'p', description: 'A', quantity: 5, unit_price: 20, vat_rate: 20 },
      { product_id: '', description: 'Port', quantity: 1, unit_price: 10, vat_rate: 5.5 },
      { product_id: '', description: 'Arrondi', quantity: 3, unit_price: 0.333, vat_rate: 20 },
    ])
    expect(t).toEqual({ ht: 111, tva: 20.75, ttc: 131.75 })
  })

  it("n'envoie que les lignes utiles (article ou libellé, quantité positive)", () => {
    const payload = orderLinesPayload([
      emptyOrderLine(20),
      { product_id: 'p1', description: ' Article ', quantity: 2, unit_price: 12, vat_rate: 20 },
      { product_id: '', description: 'Sans quantité', quantity: 0, unit_price: 5, vat_rate: 20 },
    ])
    expect(payload).toEqual([{ product_id: 'p1', description: 'Article', quantity: 2, unit_price: 12, vat_rate: 20 }])
  })
})
