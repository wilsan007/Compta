import { describe, it, expect } from 'vitest'

// ============================================================
// Tests complets : Three-way matching (migration 86)
// Teste la logique de matching entre PO, réception et facture.
// Les règles sont reproduites en TypeScript pour validation unitaire.
// ============================================================

// ============ Types ============
interface InvoiceLine {
  id: string
  product_id: string
  quantity: number
  unit_price: number
  purchase_order_line_id?: string | null
}

interface POLine {
  id: string
  product_id: string
  quantity: number
  unit_price: number
}

interface ReceiptLine {
  goods_receipt_id: string
  product_id: string
  quantity_received: number
}

interface MatchInput {
  hasPO: boolean
  hasReceipt: boolean
  poLines: POLine[]
  receiptLines: ReceiptLine[]
  invoiceLines: InvoiceLine[]
}

interface LineResult {
  invoice_line_id: string
  product_id: string
  po_quantity: number
  po_unit_price: number
  received_quantity: number
  invoiced_quantity: number
  invoice_unit_price: number
  price_variance: number
  quantity_variance: number
  status: string
}

interface MatchResult {
  match_status: 'matched' | 'partial_match' | 'mismatch' | 'pending_review' | 'unmatched'
  total_ordered: number
  total_received: number
  total_invoiced: number
  price_variance: number
  quantity_variance: number
  line_results: LineResult[]
  reason?: string
}

// ============ Logique de matching (reproduit la fonction SQL) ============
const TOLERANCE = 0.01  // 1%

function performThreeWayMatch(input: MatchInput): MatchResult {
  if (!input.hasPO) {
    return {
      match_status: 'pending_review',
      total_ordered: 0, total_received: 0, total_invoiced: 0,
      price_variance: 0, quantity_variance: 0,
      line_results: [],
      reason: 'no_purchase_order_linked',
    }
  }

  let matchStatus: MatchResult['match_status'] = 'matched'
  let totalOrdered = 0
  let totalReceived = 0
  let totalInvoiced = 0
  let priceVariance = 0
  let quantityVariance = 0
  const lineResults: LineResult[] = []

  for (const invLine of input.invoiceLines) {
    let lineStatus = 'matched'
    totalInvoiced += (invLine.quantity || 0) * (invLine.unit_price || 0)

    // Trouver la ligne du PO
    let poLine: POLine | undefined
    if (invLine.purchase_order_line_id) {
      poLine = input.poLines.find((l) => l.id === invLine.purchase_order_line_id)
    } else {
      poLine = input.poLines.find((l) => l.product_id === invLine.product_id)
    }

    if (poLine) {
      totalOrdered += (poLine.quantity || 0) * (poLine.unit_price || 0)

      // Vérifier le prix
      if (poLine.unit_price > 0) {
        const varPct = Math.abs(invLine.unit_price - poLine.unit_price) / poLine.unit_price
        priceVariance = Math.max(priceVariance, varPct)
        if (varPct > TOLERANCE) {
          lineStatus = 'price_mismatch'
          matchStatus = 'mismatch'
        }
      }

      // Vérifier la quantité si réception
      if (input.hasReceipt) {
        const grLine = input.receiptLines.find(
          (r) => r.product_id === invLine.product_id
        )
        if (grLine) {
          totalReceived += (grLine.quantity_received || 0) * (poLine.unit_price || 0)
          if (invLine.quantity > grLine.quantity_received) {
            quantityVariance = Math.max(quantityVariance, invLine.quantity - grLine.quantity_received)
            lineStatus = 'quantity_exceeds_received'
            matchStatus = 'mismatch'
          }
          lineResults.push({
            invoice_line_id: invLine.id,
            product_id: invLine.product_id,
            po_quantity: poLine.quantity,
            po_unit_price: poLine.unit_price,
            received_quantity: grLine.quantity_received,
            invoiced_quantity: invLine.quantity,
            invoice_unit_price: invLine.unit_price,
            price_variance: poLine.unit_price > 0
              ? Math.abs(invLine.unit_price - poLine.unit_price) / poLine.unit_price
              : 0,
            quantity_variance: Math.max(0, invLine.quantity - grLine.quantity_received),
            status: lineStatus,
          })
        } else {
          lineStatus = 'no_receipt_line'
          if (matchStatus === 'matched') matchStatus = 'partial_match'
          lineResults.push({
            invoice_line_id: invLine.id,
            product_id: invLine.product_id,
            po_quantity: poLine.quantity,
            po_unit_price: poLine.unit_price,
            received_quantity: 0,
            invoiced_quantity: invLine.quantity,
            invoice_unit_price: invLine.unit_price,
            price_variance: 0,
            quantity_variance: 0,
            status: lineStatus,
          })
        }
      } else {
        lineStatus = 'no_receipt'
        if (matchStatus === 'matched') matchStatus = 'pending_review'
        lineResults.push({
          invoice_line_id: invLine.id,
          product_id: invLine.product_id,
          po_quantity: poLine.quantity,
          po_unit_price: poLine.unit_price,
          received_quantity: 0,
          invoiced_quantity: invLine.quantity,
          invoice_unit_price: invLine.unit_price,
          price_variance: 0,
          quantity_variance: 0,
          status: lineStatus,
        })
      }
    } else {
      lineStatus = 'no_po_line'
      matchStatus = 'mismatch'
      lineResults.push({
        invoice_line_id: invLine.id,
        product_id: invLine.product_id,
        po_quantity: 0,
        po_unit_price: 0,
        received_quantity: 0,
        invoiced_quantity: invLine.quantity,
        invoice_unit_price: invLine.unit_price,
        price_variance: 0,
        quantity_variance: 0,
        status: lineStatus,
      })
    }
  }

  return {
    match_status: matchStatus,
    total_ordered: totalOrdered,
    total_received: totalReceived,
    total_invoiced: totalInvoiced,
    price_variance: priceVariance,
    quantity_variance: quantityVariance,
    line_results: lineResults,
  }
}

// ============ 1. Matching parfait ============
describe('1. Three-way matching parfait', () => {
  it('PO + réception + facture identiques → matched', () => {
    const result = performThreeWayMatch({
      hasPO: true,
      hasReceipt: true,
      poLines: [{ id: 'pol1', product_id: 'p1', quantity: 10, unit_price: 100 }],
      receiptLines: [{ goods_receipt_id: 'gr1', product_id: 'p1', quantity_received: 10 }],
      invoiceLines: [{ id: 'il1', product_id: 'p1', quantity: 10, unit_price: 100 }],
    })
    expect(result.match_status).toBe('matched')
    expect(result.total_ordered).toBe(1000)
    expect(result.total_invoiced).toBe(1000)
    expect(result.price_variance).toBe(0)
    expect(result.quantity_variance).toBe(0)
    expect(result.line_results).toHaveLength(1)
    expect(result.line_results[0].status).toBe('matched')
  })

  it('multi-lignes toutes matchées → matched', () => {
    const result = performThreeWayMatch({
      hasPO: true,
      hasReceipt: true,
      poLines: [
        { id: 'pol1', product_id: 'p1', quantity: 5, unit_price: 50 },
        { id: 'pol2', product_id: 'p2', quantity: 10, unit_price: 25 },
      ],
      receiptLines: [
        { goods_receipt_id: 'gr1', product_id: 'p1', quantity_received: 5 },
        { goods_receipt_id: 'gr1', product_id: 'p2', quantity_received: 10 },
      ],
      invoiceLines: [
        { id: 'il1', product_id: 'p1', quantity: 5, unit_price: 50 },
        { id: 'il2', product_id: 'p2', quantity: 10, unit_price: 25 },
      ],
    })
    expect(result.match_status).toBe('matched')
    expect(result.total_ordered).toBe(500)  // 5*50 + 10*25
    expect(result.total_invoiced).toBe(500)
    expect(result.line_results).toHaveLength(2)
  })

  it('matching par purchase_order_line_id explicite', () => {
    const result = performThreeWayMatch({
      hasPO: true,
      hasReceipt: true,
      poLines: [{ id: 'pol1', product_id: 'p1', quantity: 10, unit_price: 100 }],
      receiptLines: [{ goods_receipt_id: 'gr1', product_id: 'p1', quantity_received: 10 }],
      invoiceLines: [{ id: 'il1', product_id: 'p1', quantity: 10, unit_price: 100, purchase_order_line_id: 'pol1' }],
    })
    expect(result.match_status).toBe('matched')
  })

  it('tolérance de prix < 1% → matched', () => {
    const result = performThreeWayMatch({
      hasPO: true,
      hasReceipt: true,
      poLines: [{ id: 'pol1', product_id: 'p1', quantity: 10, unit_price: 100 }],
      receiptLines: [{ goods_receipt_id: 'gr1', product_id: 'p1', quantity_received: 10 }],
      invoiceLines: [{ id: 'il1', product_id: 'p1', quantity: 10, unit_price: 100.5 }],
    })
    // 0.5% < 1% → matched
    expect(result.match_status).toBe('matched')
    expect(result.line_results[0].price_variance).toBeCloseTo(0.005, 4)
  })
})

// ============ 2. Mismatch de prix ============
describe('2. Mismatch de prix', () => {
  it('prix facturé > prix commandé (écart > 1%) → mismatch', () => {
    const result = performThreeWayMatch({
      hasPO: true,
      hasReceipt: true,
      poLines: [{ id: 'pol1', product_id: 'p1', quantity: 10, unit_price: 100 }],
      receiptLines: [{ goods_receipt_id: 'gr1', product_id: 'p1', quantity_received: 10 }],
      invoiceLines: [{ id: 'il1', product_id: 'p1', quantity: 10, unit_price: 120 }],
    })
    expect(result.match_status).toBe('mismatch')
    expect(result.line_results[0].status).toBe('price_mismatch')
    expect(result.price_variance).toBeCloseTo(0.2, 4)  // 20%
  })

  it('prix facturé < prix commandé (écart > 1%) → mismatch', () => {
    const result = performThreeWayMatch({
      hasPO: true,
      hasReceipt: true,
      poLines: [{ id: 'pol1', product_id: 'p1', quantity: 10, unit_price: 100 }],
      receiptLines: [{ goods_receipt_id: 'gr1', product_id: 'p1', quantity_received: 10 }],
      invoiceLines: [{ id: 'il1', product_id: 'p1', quantity: 10, unit_price: 80 }],
    })
    expect(result.match_status).toBe('mismatch')
    expect(result.line_results[0].status).toBe('price_mismatch')
  })

  it('prix exactement à la tolérance (1%) → matched', () => {
    const result = performThreeWayMatch({
      hasPO: true,
      hasReceipt: true,
      poLines: [{ id: 'pol1', product_id: 'p1', quantity: 10, unit_price: 100 }],
      receiptLines: [{ goods_receipt_id: 'gr1', product_id: 'p1', quantity_received: 10 }],
      invoiceLines: [{ id: 'il1', product_id: 'p1', quantity: 10, unit_price: 101 }],
    })
    // 1% = tolérance exacte → pas > tolérance → matched
    expect(result.match_status).toBe('matched')
  })

  it('prix PO = 0 → pas de vérification de prix', () => {
    const result = performThreeWayMatch({
      hasPO: true,
      hasReceipt: true,
      poLines: [{ id: 'pol1', product_id: 'p1', quantity: 10, unit_price: 0 }],
      receiptLines: [{ goods_receipt_id: 'gr1', product_id: 'p1', quantity_received: 10 }],
      invoiceLines: [{ id: 'il1', product_id: 'p1', quantity: 10, unit_price: 100 }],
    })
    // Prix PO = 0 → on ne vérifie pas le prix
    expect(result.match_status).toBe('matched')
  })
})

// ============ 3. Mismatch de quantité ============
describe('3. Mismatch de quantité', () => {
  it('quantité facturée > quantité reçue → mismatch', () => {
    const result = performThreeWayMatch({
      hasPO: true,
      hasReceipt: true,
      poLines: [{ id: 'pol1', product_id: 'p1', quantity: 20, unit_price: 100 }],
      receiptLines: [{ goods_receipt_id: 'gr1', product_id: 'p1', quantity_received: 10 }],
      invoiceLines: [{ id: 'il1', product_id: 'p1', quantity: 15, unit_price: 100 }],
    })
    expect(result.match_status).toBe('mismatch')
    expect(result.line_results[0].status).toBe('quantity_exceeds_received')
    expect(result.quantity_variance).toBe(5)
  })

  it('quantité facturée = quantité reçue < quantité commandée → matched', () => {
    const result = performThreeWayMatch({
      hasPO: true,
      hasReceipt: true,
      poLines: [{ id: 'pol1', product_id: 'p1', quantity: 20, unit_price: 100 }],
      receiptLines: [{ goods_receipt_id: 'gr1', product_id: 'p1', quantity_received: 10 }],
      invoiceLines: [{ id: 'il1', product_id: 'p1', quantity: 10, unit_price: 100 }],
    })
    // On paie ce qu'on a reçu → matched
    expect(result.match_status).toBe('matched')
  })

  it('quantité facturée < quantité reçue → matched', () => {
    const result = performThreeWayMatch({
      hasPO: true,
      hasReceipt: true,
      poLines: [{ id: 'pol1', product_id: 'p1', quantity: 20, unit_price: 100 }],
      receiptLines: [{ goods_receipt_id: 'gr1', product_id: 'p1', quantity_received: 15 }],
      invoiceLines: [{ id: 'il1', product_id: 'p1', quantity: 10, unit_price: 100 }],
    })
    expect(result.match_status).toBe('matched')
  })
})

// ============ 4. Pas de réception ============
describe('4. Sans réception (goods receipt)', () => {
  it('PO + facture sans réception → pending_review', () => {
    const result = performThreeWayMatch({
      hasPO: true,
      hasReceipt: false,
      poLines: [{ id: 'pol1', product_id: 'p1', quantity: 10, unit_price: 100 }],
      receiptLines: [],
      invoiceLines: [{ id: 'il1', product_id: 'p1', quantity: 10, unit_price: 100 }],
    })
    expect(result.match_status).toBe('pending_review')
    expect(result.line_results[0].status).toBe('no_receipt')
  })

  it('sans réception + mismatch prix → mismatch (priorité)', () => {
    const result = performThreeWayMatch({
      hasPO: true,
      hasReceipt: false,
      poLines: [{ id: 'pol1', product_id: 'p1', quantity: 10, unit_price: 100 }],
      receiptLines: [],
      invoiceLines: [{ id: 'il1', product_id: 'p1', quantity: 10, unit_price: 150 }],
    })
    // Le mismatch prix prend le pas sur pending_review
    expect(result.match_status).toBe('mismatch')
  })
})

// ============ 5. Pas de PO ============
describe('5. Sans bon de commande', () => {
  it('pas de PO lié → pending_review', () => {
    const result = performThreeWayMatch({
      hasPO: false,
      hasReceipt: false,
      poLines: [],
      receiptLines: [],
      invoiceLines: [{ id: 'il1', product_id: 'p1', quantity: 10, unit_price: 100 }],
    })
    expect(result.match_status).toBe('pending_review')
    expect(result.reason).toBe('no_purchase_order_linked')
    expect(result.line_results).toHaveLength(0)
  })
})

// ============ 6. Partial match ============
describe('6. Partial match', () => {
  it('réception manquante pour un produit → partial_match', () => {
    const result = performThreeWayMatch({
      hasPO: true,
      hasReceipt: true,
      poLines: [
        { id: 'pol1', product_id: 'p1', quantity: 10, unit_price: 100 },
        { id: 'pol2', product_id: 'p2', quantity: 5, unit_price: 50 },
      ],
      receiptLines: [
        { goods_receipt_id: 'gr1', product_id: 'p1', quantity_received: 10 },
        // Pas de réception pour p2
      ],
      invoiceLines: [
        { id: 'il1', product_id: 'p1', quantity: 10, unit_price: 100 },
        { id: 'il2', product_id: 'p2', quantity: 5, unit_price: 50 },
      ],
    })
    expect(result.match_status).toBe('partial_match')
    expect(result.line_results).toHaveLength(2)
    expect(result.line_results[0].status).toBe('matched')
    expect(result.line_results[1].status).toBe('no_receipt_line')
  })

  it('partial match + mismatch prix → mismatch (priorité)', () => {
    const result = performThreeWayMatch({
      hasPO: true,
      hasReceipt: true,
      poLines: [
        { id: 'pol1', product_id: 'p1', quantity: 10, unit_price: 100 },
        { id: 'pol2', product_id: 'p2', quantity: 5, unit_price: 50 },
      ],
      receiptLines: [
        { goods_receipt_id: 'gr1', product_id: 'p1', quantity_received: 10 },
      ],
      invoiceLines: [
        { id: 'il1', product_id: 'p1', quantity: 10, unit_price: 100 },
        { id: 'il2', product_id: 'p2', quantity: 5, unit_price: 75 },  // prix mismatch
      ],
    })
    expect(result.match_status).toBe('mismatch')
  })
})

// ============ 7. Ligne de facture sans ligne PO ============
describe('7. Ligne sans correspondance PO', () => {
  it('produit facturé non dans le PO → mismatch', () => {
    const result = performThreeWayMatch({
      hasPO: true,
      hasReceipt: true,
      poLines: [{ id: 'pol1', product_id: 'p1', quantity: 10, unit_price: 100 }],
      receiptLines: [{ goods_receipt_id: 'gr1', product_id: 'p1', quantity_received: 10 }],
      invoiceLines: [
        { id: 'il1', product_id: 'p1', quantity: 10, unit_price: 100 },
        { id: 'il2', product_id: 'p2', quantity: 5, unit_price: 50 },  // pas dans PO
      ],
    })
    expect(result.match_status).toBe('mismatch')
    expect(result.line_results[1].status).toBe('no_po_line')
  })
})

// ============ 8. Calculs de totaux ============
describe('8. Calculs de totaux', () => {
  it('total_invoiced = somme(qty * price)', () => {
    const result = performThreeWayMatch({
      hasPO: true,
      hasReceipt: true,
      poLines: [
        { id: 'pol1', product_id: 'p1', quantity: 10, unit_price: 100 },
        { id: 'pol2', product_id: 'p2', quantity: 5, unit_price: 50 },
      ],
      receiptLines: [
        { goods_receipt_id: 'gr1', product_id: 'p1', quantity_received: 10 },
        { goods_receipt_id: 'gr1', product_id: 'p2', quantity_received: 5 },
      ],
      invoiceLines: [
        { id: 'il1', product_id: 'p1', quantity: 10, unit_price: 100 },
        { id: 'il2', product_id: 'p2', quantity: 5, unit_price: 50 },
      ],
    })
    expect(result.total_invoiced).toBe(1250)  // 1000 + 250
    expect(result.total_ordered).toBe(1250)
    expect(result.total_received).toBe(1250)
  })

  it('total_received utilise le prix du PO', () => {
    const result = performThreeWayMatch({
      hasPO: true,
      hasReceipt: true,
      poLines: [{ id: 'pol1', product_id: 'p1', quantity: 10, unit_price: 100 }],
      receiptLines: [{ goods_receipt_id: 'gr1', product_id: 'p1', quantity_received: 8 }],
      invoiceLines: [{ id: 'il1', product_id: 'p1', quantity: 8, unit_price: 110 }],
    })
    // total_received = 8 * 100 (prix PO) = 800
    expect(result.total_received).toBe(800)
    // total_invoiced = 8 * 110 (prix facture) = 880
    expect(result.total_invoiced).toBe(880)
  })
})

// ============ 9. Edge cases ============
describe('9. Edge cases', () => {
  it('aucune ligne de facture → matched (vide)', () => {
    const result = performThreeWayMatch({
      hasPO: true,
      hasReceipt: true,
      poLines: [{ id: 'pol1', product_id: 'p1', quantity: 10, unit_price: 100 }],
      receiptLines: [{ goods_receipt_id: 'gr1', product_id: 'p1', quantity_received: 10 }],
      invoiceLines: [],
    })
    expect(result.match_status).toBe('matched')
    expect(result.total_invoiced).toBe(0)
    expect(result.line_results).toHaveLength(0)
  })

  it('quantité facturée = 0 → matched', () => {
    const result = performThreeWayMatch({
      hasPO: true,
      hasReceipt: true,
      poLines: [{ id: 'pol1', product_id: 'p1', quantity: 10, unit_price: 100 }],
      receiptLines: [{ goods_receipt_id: 'gr1', product_id: 'p1', quantity_received: 10 }],
      invoiceLines: [{ id: 'il1', product_id: 'p1', quantity: 0, unit_price: 100 }],
    })
    expect(result.match_status).toBe('matched')
    expect(result.total_invoiced).toBe(0)
  })

  it('prix unitaire = 0 dans la facture → pas de mismatch prix', () => {
    const result = performThreeWayMatch({
      hasPO: true,
      hasReceipt: true,
      poLines: [{ id: 'pol1', product_id: 'p1', quantity: 10, unit_price: 100 }],
      receiptLines: [{ goods_receipt_id: 'gr1', product_id: 'p1', quantity_received: 10 }],
      invoiceLines: [{ id: 'il1', product_id: 'p1', quantity: 10, unit_price: 0 }],
    })
    // Prix facture = 0, prix PO = 100 → écart 100% > 1% → mismatch
    expect(result.match_status).toBe('mismatch')
    expect(result.line_results[0].status).toBe('price_mismatch')
  })

  it('multi-lignes avec mélange matched/mismatch → mismatch global', () => {
    const result = performThreeWayMatch({
      hasPO: true,
      hasReceipt: true,
      poLines: [
        { id: 'pol1', product_id: 'p1', quantity: 10, unit_price: 100 },
        { id: 'pol2', product_id: 'p2', quantity: 5, unit_price: 50 },
      ],
      receiptLines: [
        { goods_receipt_id: 'gr1', product_id: 'p1', quantity_received: 10 },
        { goods_receipt_id: 'gr1', product_id: 'p2', quantity_received: 5 },
      ],
      invoiceLines: [
        { id: 'il1', product_id: 'p1', quantity: 10, unit_price: 100 },  // matched
        { id: 'il2', product_id: 'p2', quantity: 5, unit_price: 75 },    // mismatch
      ],
    })
    expect(result.match_status).toBe('mismatch')
    expect(result.line_results[0].status).toBe('matched')
    expect(result.line_results[1].status).toBe('price_mismatch')
  })
})
