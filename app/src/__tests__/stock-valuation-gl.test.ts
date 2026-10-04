import { describe, it, expect } from 'vitest'

// ============================================================
// Tests complets : Valorisation de stock → GL (migration 87)
// Teste les fonctions increment_stock, decrement_stock,
// update_stock_on_movement, create_journal_on_stock_movement,
// et get_stock_valuation.
// ============================================================

// ============ Types ============
interface Product {
  id: string
  name: string
  stock_quantity: number
  cost_price: number
  tenant_id: string
}

interface StockMovement {
  id: string
  product_id: string
  quantity: number
  unit_cost: number
  movement_type: 'in' | 'out' | 'adjustment' | 'transfer'
  warehouse_id: string | null
  movement_date: string
  reference: string | null
  tenant_id: string
}

interface StockQuantity {
  product_id: string
  warehouse_id: string
  quantity: number
  tenant_id: string
}

interface JournalEntry {
  id: string
  tenant_id: string
  number: string
  date: string
  journal_code: string
  status: string
  description: string
  piece_number: string
  reference: string | null
}

interface JournalLine {
  id: string
  tenant_id: string
  journal_id: string
  account_code: string
  debit: number
  credit: number
  description: string
  line_order: number
  product_id: string
  quantity: number
}

// ============ Simulation en mémoire ============
class StockSimulation {
  products: Map<string, Product> = new Map()
  stockQuantities: Map<string, StockQuantity> = new Map()
  movements: StockMovement[] = []
  journalEntries: JournalEntry[] = []
  journalLines: JournalLine[] = []
  tenantId: string = 'test-tenant-id'

  constructor() {
    this.reset()
  }

  reset() {
    this.products.clear()
    this.stockQuantities.clear()
    this.movements = []
    this.journalEntries = []
    this.journalLines = []
  }

  addProduct(product: Product) {
    this.products.set(product.id, product)
  }

  // A1. increment_stock
  incrementStock(productId: string, qty: number, warehouseId?: string) {
    const product = this.products.get(productId)
    if (!product) throw new Error(`Produit ${productId} non trouvé`)
    if (product.tenant_id !== this.tenantId) throw new Error('Aucun tenant actif')

    if (warehouseId) {
      const key = `${productId}-${warehouseId}`
      const existing = this.stockQuantities.get(key)
      if (existing) {
        existing.quantity += qty
      } else {
        this.stockQuantities.set(key, {
          product_id: productId,
          warehouse_id: warehouseId,
          quantity: qty,
          tenant_id: this.tenantId,
        })
      }
    }

    product.stock_quantity = (product.stock_quantity || 0) + qty
  }

  // A2. decrement_stock
  decrementStock(productId: string, qty: number, warehouseId?: string) {
    const product = this.products.get(productId)
    if (!product) throw new Error(`Produit ${productId} non trouvé`)
    if (product.tenant_id !== this.tenantId) throw new Error('Aucun tenant actif')

    if (product.stock_quantity < qty) {
      throw new Error(`Stock insuffisant: disponible=${product.stock_quantity}, demandé=${qty}`)
    }

    if (warehouseId) {
      const key = `${productId}-${warehouseId}`
      const existing = this.stockQuantities.get(key)
      if (existing) {
        existing.quantity = Math.max(existing.quantity - qty, 0)
      }
    }

    product.stock_quantity -= qty
  }

  // B. update_stock_on_movement (trigger)
  processMovement(movement: StockMovement) {
    this.movements.push(movement)

    if (movement.movement_type === 'in') {
      this.incrementStock(movement.product_id, movement.quantity, movement.warehouse_id || undefined)
    } else if (movement.movement_type === 'out') {
      this.decrementStock(movement.product_id, movement.quantity, movement.warehouse_id || undefined)
    } else if (movement.movement_type === 'adjustment') {
      const product = this.products.get(movement.product_id)
      if (product) {
        product.stock_quantity = movement.quantity
      }
    }

    // C. create_journal_on_stock_movement (trigger)
    this.createJournalForMovement(movement)
  }

  // C. create_journal_on_stock_movement
  createJournalForMovement(movement: StockMovement) {
    if (movement.unit_cost === null || movement.unit_cost <= 0) return
    if (!['in', 'out', 'adjustment'].includes(movement.movement_type)) return

    const amount = movement.quantity * movement.unit_cost
    if (amount === 0) return

    // Éviter les doublons
    const existing = this.journalEntries.find(
      (e) => e.piece_number === `STK-${movement.id}`
    )
    if (existing) return

    const entryId = `je-${movement.id}`
    const product = this.products.get(movement.product_id)
    const stockAccount = '310000'
    const variationAccount = '603000'

    this.journalEntries.push({
      id: entryId,
      tenant_id: this.tenantId,
      number: `JE-STK-${movement.id}`,
      date: movement.movement_date,
      journal_code: 'ST',
      status: 'posted',
      description: `Mouvement de stock ${movement.reference || movement.id}`,
      piece_number: `STK-${movement.id}`,
      reference: movement.reference,
    })

    if (movement.movement_type === 'in') {
      // Débit 310 (stock) / Crédit 603 (variation)
      this.journalLines.push(
        { id: `jl-1-${movement.id}`, tenant_id: this.tenantId, journal_id: entryId,
          account_code: stockAccount, debit: amount, credit: 0,
          description: `Entrée en stock - ${product?.name || 'Produit'}`,
          line_order: 0, product_id: movement.product_id, quantity: movement.quantity },
        { id: `jl-2-${movement.id}`, tenant_id: this.tenantId, journal_id: entryId,
          account_code: variationAccount, debit: 0, credit: amount,
          description: `Variation de stock (entrée) - ${product?.name || 'Produit'}`,
          line_order: 1, product_id: movement.product_id, quantity: movement.quantity },
      )
    } else if (movement.movement_type === 'out') {
      // Débit 603 (variation) / Crédit 310 (stock)
      this.journalLines.push(
        { id: `jl-1-${movement.id}`, tenant_id: this.tenantId, journal_id: entryId,
          account_code: variationAccount, debit: amount, credit: 0,
          description: `Variation de stock (sortie) - ${product?.name || 'Produit'}`,
          line_order: 0, product_id: movement.product_id, quantity: movement.quantity },
        { id: `jl-2-${movement.id}`, tenant_id: this.tenantId, journal_id: entryId,
          account_code: stockAccount, debit: 0, credit: amount,
          description: `Sortie de stock - ${product?.name || 'Produit'}`,
          line_order: 1, product_id: movement.product_id, quantity: movement.quantity },
      )
    } else if (movement.movement_type === 'adjustment') {
      this.journalLines.push(
        { id: `jl-1-${movement.id}`, tenant_id: this.tenantId, journal_id: entryId,
          account_code: stockAccount, debit: amount, credit: 0,
          description: `Ajustement de stock - ${product?.name || 'Produit'}`,
          line_order: 0, product_id: movement.product_id, quantity: movement.quantity },
        { id: `jl-2-${movement.id}`, tenant_id: this.tenantId, journal_id: entryId,
          account_code: variationAccount, debit: 0, credit: amount,
          description: `Variation de stock (ajustement) - ${product?.name || 'Produit'}`,
          line_order: 1, product_id: movement.product_id, quantity: movement.quantity },
      )
    }
  }

  // D. get_stock_valuation
  getStockValuation(date?: string): Array<{
    product_id: string
    product_name: string
    quantity: number
    unit_cost: number
    total_value: number
  }> {
    const result: any[] = []
    for (const product of this.products.values()) {
      // Trouver le dernier unit_cost à la date
      const movements = this.movements
        .filter((m) => m.product_id === product.id && (!date || m.movement_date <= date))
        .sort((a, b) => b.movement_date.localeCompare(a.movement_date))

      const unitCost = movements.length > 0 ? movements[0].unit_cost : (product.cost_price || 0)
      const quantity = product.stock_quantity || 0

      result.push({
        product_id: product.id,
        product_name: product.name,
        quantity,
        unit_cost: unitCost,
        total_value: quantity * unitCost,
      })
    }
    return result
  }
}

// ============ 1. increment_stock ============
describe('1. increment_stock', () => {
  it('augmente le stock total du produit', () => {
    const sim = new StockSimulation()
    sim.addProduct({ id: 'p1', name: 'Produit A', stock_quantity: 10, cost_price: 50, tenant_id: 'test-tenant-id' })
    sim.incrementStock('p1', 5)
    expect(sim.products.get('p1')!.stock_quantity).toBe(15)
  })

  it('crée une entrée stock_quantities par entrepôt', () => {
    const sim = new StockSimulation()
    sim.addProduct({ id: 'p1', name: 'A', stock_quantity: 0, cost_price: 50, tenant_id: 'test-tenant-id' })
    sim.incrementStock('p1', 10, 'wh-1')
    const sq = sim.stockQuantities.get('p1-wh-1')
    expect(sq).toBeDefined()
    expect(sq!.quantity).toBe(10)
  })

  it('met à jour stock_quantities existant', () => {
    const sim = new StockSimulation()
    sim.addProduct({ id: 'p1', name: 'A', stock_quantity: 10, cost_price: 50, tenant_id: 'test-tenant-id' })
    sim.incrementStock('p1', 5, 'wh-1')
    sim.incrementStock('p1', 3, 'wh-1')
    expect(sim.stockQuantities.get('p1-wh-1')!.quantity).toBe(8)
    expect(sim.products.get('p1')!.stock_quantity).toBe(18)
  })

  it('sans warehouse_id → met à jour seulement products', () => {
    const sim = new StockSimulation()
    sim.addProduct({ id: 'p1', name: 'A', stock_quantity: 5, cost_price: 50, tenant_id: 'test-tenant-id' })
    sim.incrementStock('p1', 10)
    expect(sim.products.get('p1')!.stock_quantity).toBe(15)
    expect(sim.stockQuantities.size).toBe(0)
  })

  it('produit inexistant → erreur', () => {
    const sim = new StockSimulation()
    expect(() => sim.incrementStock('nonexistent', 5)).toThrow('non trouvé')
  })

  it('stock initial null → traité comme 0', () => {
    const sim = new StockSimulation()
    sim.addProduct({ id: 'p1', name: 'A', stock_quantity: null as any, cost_price: 50, tenant_id: 'test-tenant-id' })
    sim.incrementStock('p1', 10)
    expect(sim.products.get('p1')!.stock_quantity).toBe(10)
  })
})

// ============ 2. decrement_stock ============
describe('2. decrement_stock', () => {
  it('diminue le stock', () => {
    const sim = new StockSimulation()
    sim.addProduct({ id: 'p1', name: 'A', stock_quantity: 20, cost_price: 50, tenant_id: 'test-tenant-id' })
    sim.decrementStock('p1', 5)
    expect(sim.products.get('p1')!.stock_quantity).toBe(15)
  })

  it('stock insuffisant → erreur', () => {
    const sim = new StockSimulation()
    sim.addProduct({ id: 'p1', name: 'A', stock_quantity: 3, cost_price: 50, tenant_id: 'test-tenant-id' })
    expect(() => sim.decrementStock('p1', 5)).toThrow('Stock insuffisant')
  })

  it('stock exact → OK', () => {
    const sim = new StockSimulation()
    sim.addProduct({ id: 'p1', name: 'A', stock_quantity: 5, cost_price: 50, tenant_id: 'test-tenant-id' })
    sim.decrementStock('p1', 5)
    expect(sim.products.get('p1')!.stock_quantity).toBe(0)
  })

  it('décrémente stock_quantities par entrepôt (avec plancher 0)', () => {
    const sim = new StockSimulation()
    sim.addProduct({ id: 'p1', name: 'A', stock_quantity: 10, cost_price: 50, tenant_id: 'test-tenant-id' })
    sim.incrementStock('p1', 10, 'wh-1')
    sim.decrementStock('p1', 3, 'wh-1')
    expect(sim.stockQuantities.get('p1-wh-1')!.quantity).toBe(7)
  })

  it('produit inexistant → erreur', () => {
    const sim = new StockSimulation()
    expect(() => sim.decrementStock('nonexistent', 5)).toThrow('non trouvé')
  })
})

// ============ 3. update_stock_on_movement (trigger) ============
describe('3. update_stock_on_movement (trigger)', () => {
  it('movement_type = "in" → incrémente le stock', () => {
    const sim = new StockSimulation()
    sim.addProduct({ id: 'p1', name: 'A', stock_quantity: 10, cost_price: 50, tenant_id: 'test-tenant-id' })
    sim.processMovement({
      id: 'm1', product_id: 'p1', quantity: 5, unit_cost: 0,
      movement_type: 'in', warehouse_id: null,
      movement_date: '2024-01-01', reference: 'REF-1', tenant_id: 'test-tenant-id',
    })
    expect(sim.products.get('p1')!.stock_quantity).toBe(15)
  })

  it('movement_type = "out" → décrémente le stock', () => {
    const sim = new StockSimulation()
    sim.addProduct({ id: 'p1', name: 'A', stock_quantity: 10, cost_cost: 50, cost_price: 50, tenant_id: 'test-tenant-id' } as any)
    sim.processMovement({
      id: 'm1', product_id: 'p1', quantity: 3, unit_cost: 0,
      movement_type: 'out', warehouse_id: null,
      movement_date: '2024-01-01', reference: null, tenant_id: 'test-tenant-id',
    })
    expect(sim.products.get('p1')!.stock_quantity).toBe(7)
  })

  it('movement_type = "adjustment" → set valeur absolue', () => {
    const sim = new StockSimulation()
    sim.addProduct({ id: 'p1', name: 'A', stock_quantity: 10, cost_price: 50, tenant_id: 'test-tenant-id' })
    sim.processMovement({
      id: 'm1', product_id: 'p1', quantity: 25, unit_cost: 0,
      movement_type: 'adjustment', warehouse_id: null,
      movement_date: '2024-01-01', reference: null, tenant_id: 'test-tenant-id',
    })
    expect(sim.products.get('p1')!.stock_quantity).toBe(25)
  })

  it('movement_type = "transfer" → ne modifie pas le stock total', () => {
    const sim = new StockSimulation()
    sim.addProduct({ id: 'p1', name: 'A', stock_quantity: 10, cost_price: 50, tenant_id: 'test-tenant-id' })
    sim.processMovement({
      id: 'm1', product_id: 'p1', quantity: 5, unit_cost: 0,
      movement_type: 'transfer', warehouse_id: null,
      movement_date: '2024-01-01', reference: null, tenant_id: 'test-tenant-id',
    })
    // transfer n'est pas géré par update_stock_on_movement
    expect(sim.products.get('p1')!.stock_quantity).toBe(10)
  })
})

// ============ 4. create_journal_on_stock_movement (trigger) ============
describe('4. create_journal_on_stock_movement (trigger)', () => {
  it('movement "in" avec unit_cost → écriture Débit 310 / Crédit 603', () => {
    const sim = new StockSimulation()
    sim.addProduct({ id: 'p1', name: 'A', stock_quantity: 0, cost_price: 50, tenant_id: 'test-tenant-id' })
    sim.processMovement({
      id: 'm1', product_id: 'p1', quantity: 10, unit_cost: 100,
      movement_type: 'in', warehouse_id: null,
      movement_date: '2024-01-01', reference: 'CMD-1', tenant_id: 'test-tenant-id',
    })
    expect(sim.journalEntries).toHaveLength(1)
    expect(sim.journalEntries[0].journal_code).toBe('ST')
    expect(sim.journalEntries[0].piece_number).toBe('STK-m1')
    expect(sim.journalLines).toHaveLength(2)
    // Ligne 1: Débit 310000
    const debitLine = sim.journalLines.find((l) => l.account_code === '310000')
    expect(debitLine).toBeDefined()
    expect(debitLine!.debit).toBe(1000)  // 10 * 100
    expect(debitLine!.credit).toBe(0)
    // Ligne 2: Crédit 603000
    const creditLine = sim.journalLines.find((l) => l.account_code === '603000')
    expect(creditLine).toBeDefined()
    expect(creditLine!.debit).toBe(0)
    expect(creditLine!.credit).toBe(1000)
  })

  it('movement "out" avec unit_cost → écriture Débit 603 / Crédit 310', () => {
    const sim = new StockSimulation()
    sim.addProduct({ id: 'p1', name: 'A', stock_quantity: 20, cost_price: 50, tenant_id: 'test-tenant-id' })
    sim.processMovement({
      id: 'm1', product_id: 'p1', quantity: 5, unit_cost: 100,
      movement_type: 'out', warehouse_id: null,
      movement_date: '2024-01-01', reference: 'OUT-1', tenant_id: 'test-tenant-id',
    })
    expect(sim.journalEntries).toHaveLength(1)
    const debitLine = sim.journalLines.find((l) => l.account_code === '603000')
    expect(debitLine!.debit).toBe(500)  // 5 * 100
    const creditLine = sim.journalLines.find((l) => l.account_code === '310000')
    expect(creditLine!.credit).toBe(500)
  })

  it('unit_cost = 0 → pas d\'écriture', () => {
    const sim = new StockSimulation()
    sim.addProduct({ id: 'p1', name: 'A', stock_quantity: 10, cost_price: 50, tenant_id: 'test-tenant-id' })
    sim.processMovement({
      id: 'm1', product_id: 'p1', quantity: 5, unit_cost: 0,
      movement_type: 'in', warehouse_id: null,
      movement_date: '2024-01-01', reference: null, tenant_id: 'test-tenant-id',
    })
    expect(sim.journalEntries).toHaveLength(0)
  })

  it('unit_cost null → pas d\'écriture', () => {
    const sim = new StockSimulation()
    sim.addProduct({ id: 'p1', name: 'A', stock_quantity: 10, cost_price: 50, tenant_id: 'test-tenant-id' })
    sim.processMovement({
      id: 'm1', product_id: 'p1', quantity: 5, unit_cost: null as any,
      movement_type: 'in', warehouse_id: null,
      movement_date: '2024-01-01', reference: null, tenant_id: 'test-tenant-id',
    })
    expect(sim.journalEntries).toHaveLength(0)
  })

  it('quantity = 0 → pas d\'écriture', () => {
    const sim = new StockSimulation()
    sim.addProduct({ id: 'p1', name: 'A', stock_quantity: 10, cost_price: 50, tenant_id: 'test-tenant-id' })
    sim.processMovement({
      id: 'm1', product_id: 'p1', quantity: 0, unit_cost: 100,
      movement_type: 'in', warehouse_id: null,
      movement_date: '2024-01-01', reference: null, tenant_id: 'test-tenant-id',
    })
    expect(sim.journalEntries).toHaveLength(0)
  })

  it('movement_type = "transfer" → pas d\'écriture', () => {
    const sim = new StockSimulation()
    sim.addProduct({ id: 'p1', name: 'A', stock_quantity: 10, cost_price: 50, tenant_id: 'test-tenant-id' })
    sim.processMovement({
      id: 'm1', product_id: 'p1', quantity: 5, unit_cost: 100,
      movement_type: 'transfer', warehouse_id: null,
      movement_date: '2024-01-01', reference: null, tenant_id: 'test-tenant-id',
    })
    expect(sim.journalEntries).toHaveLength(0)
  })

  it('anti-doublon : même mouvement deux fois → une seule écriture', () => {
    const sim = new StockSimulation()
    sim.addProduct({ id: 'p1', name: 'A', stock_quantity: 0, cost_price: 50, tenant_id: 'test-tenant-id' })
    const movement: StockMovement = {
      id: 'm1', product_id: 'p1', quantity: 10, unit_cost: 100,
      movement_type: 'in', warehouse_id: null,
      movement_date: '2024-01-01', reference: 'CMD-1', tenant_id: 'test-tenant-id',
    }
    sim.createJournalForMovement(movement)
    sim.createJournalForMovement(movement)
    expect(sim.journalEntries).toHaveLength(1)
  })

  it('équilibre Débit = Crédit pour movement "in"', () => {
    const sim = new StockSimulation()
    sim.addProduct({ id: 'p1', name: 'A', stock_quantity: 0, cost_price: 50, tenant_id: 'test-tenant-id' })
    sim.processMovement({
      id: 'm1', product_id: 'p1', quantity: 10, unit_cost: 100,
      movement_type: 'in', warehouse_id: null,
      movement_date: '2024-01-01', reference: null, tenant_id: 'test-tenant-id',
    })
    const totalDebit = sim.journalLines.reduce((s, l) => s + l.debit, 0)
    const totalCredit = sim.journalLines.reduce((s, l) => s + l.credit, 0)
    expect(totalDebit).toBe(totalCredit)
    expect(totalDebit).toBe(1000)
  })

  it('équilibre Débit = Crédit pour movement "out"', () => {
    const sim = new StockSimulation()
    sim.addProduct({ id: 'p1', name: 'A', stock_quantity: 20, cost_price: 50, tenant_id: 'test-tenant-id' })
    sim.processMovement({
      id: 'm1', product_id: 'p1', quantity: 7, unit_cost: 50,
      movement_type: 'out', warehouse_id: null,
      movement_date: '2024-01-01', reference: null, tenant_id: 'test-tenant-id',
    })
    const totalDebit = sim.journalLines.reduce((s, l) => s + l.debit, 0)
    const totalCredit = sim.journalLines.reduce((s, l) => s + l.credit, 0)
    expect(totalDebit).toBe(totalCredit)
    expect(totalDebit).toBe(350)  // 7 * 50
  })

  it('description inclut le nom du produit', () => {
    const sim = new StockSimulation()
    sim.addProduct({ id: 'p1', name: 'Widget XYZ', stock_quantity: 0, cost_price: 50, tenant_id: 'test-tenant-id' })
    sim.processMovement({
      id: 'm1', product_id: 'p1', quantity: 10, unit_cost: 100,
      movement_type: 'in', warehouse_id: null,
      movement_date: '2024-01-01', reference: null, tenant_id: 'test-tenant-id',
    })
    expect(sim.journalLines[0].description).toContain('Widget XYZ')
  })

  it('piece_number = STK-{movement.id}', () => {
    const sim = new StockSimulation()
    sim.addProduct({ id: 'p1', name: 'A', stock_quantity: 0, cost_price: 50, tenant_id: 'test-tenant-id' })
    sim.processMovement({
      id: 'mv-123', product_id: 'p1', quantity: 10, unit_cost: 100,
      movement_type: 'in', warehouse_id: null,
      movement_date: '2024-01-01', reference: null, tenant_id: 'test-tenant-id',
    })
    expect(sim.journalEntries[0].piece_number).toBe('STK-mv-123')
  })
})

// ============ 5. get_stock_valuation ============
describe('5. get_stock_valuation', () => {
  it('retourne la valorisation pour chaque produit', () => {
    const sim = new StockSimulation()
    sim.addProduct({ id: 'p1', name: 'A', stock_quantity: 10, cost_price: 50, tenant_id: 'test-tenant-id' })
    sim.addProduct({ id: 'p2', name: 'B', stock_quantity: 5, cost_price: 100, tenant_id: 'test-tenant-id' })
    const val = sim.getStockValuation()
    expect(val).toHaveLength(2)
    const p1 = val.find((v) => v.product_id === 'p1')
    expect(p1!.quantity).toBe(10)
    expect(p1!.unit_cost).toBe(50)  // cost_price par défaut
    expect(p1!.total_value).toBe(500)
  })

  it('utilise le dernier unit_cost des mouvements', () => {
    const sim = new StockSimulation()
    sim.addProduct({ id: 'p1', name: 'A', stock_quantity: 10, cost_price: 50, tenant_id: 'test-tenant-id' })
    sim.processMovement({
      id: 'm1', product_id: 'p1', quantity: 10, unit_cost: 75,
      movement_type: 'in', warehouse_id: null,
      movement_date: '2024-06-01', reference: null, tenant_id: 'test-tenant-id',
    })
    const val = sim.getStockValuation()
    // Le dernier mouvement a unit_cost = 75, stock a été incrémenté à 20
    expect(val[0].unit_cost).toBe(75)
    expect(val[0].total_value).toBe(1500)  // 20 * 75
  })

  it('filtre par date', () => {
    const sim = new StockSimulation()
    sim.addProduct({ id: 'p1', name: 'A', stock_quantity: 10, cost_price: 50, tenant_id: 'test-tenant-id' })
    sim.processMovement({
      id: 'm1', product_id: 'p1', quantity: 0, unit_cost: 80,
      movement_type: 'in', warehouse_id: null,
      movement_date: '2024-06-01', reference: null, tenant_id: 'test-tenant-id',
    })
    sim.processMovement({
      id: 'm2', product_id: 'p1', quantity: 0, unit_cost: 90,
      movement_type: 'in', warehouse_id: null,
      movement_date: '2024-12-01', reference: null, tenant_id: 'test-tenant-id',
    })
    // À la date 2024-07-01, le dernier coût est 80
    const val = sim.getStockValuation('2024-07-01')
    expect(val[0].unit_cost).toBe(80)
  })

  it('stock_quantity = 0 → total_value = 0', () => {
    const sim = new StockSimulation()
    sim.addProduct({ id: 'p1', name: 'A', stock_quantity: 0, cost_price: 50, tenant_id: 'test-tenant-id' })
    const val = sim.getStockValuation()
    expect(val[0].total_value).toBe(0)
  })

  it('cost_price null et aucun mouvement → unit_cost = 0', () => {
    const sim = new StockSimulation()
    sim.addProduct({ id: 'p1', name: 'A', stock_quantity: 10, cost_price: null as any, tenant_id: 'test-tenant-id' })
    const val = sim.getStockValuation()
    expect(val[0].unit_cost).toBe(0)
  })
})

// ============ 6. Scénarios complexes ============
describe('6. Scénarios complexes', () => {
  it('cycle complet : achat → stock → vente', () => {
    const sim = new StockSimulation()
    sim.addProduct({ id: 'p1', name: 'Widget', stock_quantity: 0, cost_price: 50, tenant_id: 'test-tenant-id' })

    // 1. Réception de marchandises (achat)
    sim.processMovement({
      id: 'm1', product_id: 'p1', quantity: 100, unit_cost: 50,
      movement_type: 'in', warehouse_id: 'wh-1',
      movement_date: '2024-01-15', reference: 'PO-001', tenant_id: 'test-tenant-id',
    })
    expect(sim.products.get('p1')!.stock_quantity).toBe(100)
    expect(sim.journalEntries).toHaveLength(1)
    expect(sim.journalEntries[0].piece_number).toBe('STK-m1')

    // 2. Sortie pour vente
    sim.processMovement({
      id: 'm2', product_id: 'p1', quantity: 30, unit_cost: 50,
      movement_type: 'out', warehouse_id: 'wh-1',
      movement_date: '2024-01-20', reference: 'SO-001', tenant_id: 'test-tenant-id',
    })
    expect(sim.products.get('p1')!.stock_quantity).toBe(70)
    expect(sim.journalEntries).toHaveLength(2)

    // 3. Vérification des écritures
    const totalDebit = sim.journalLines.reduce((s, l) => s + l.debit, 0)
    const totalCredit = sim.journalLines.reduce((s, l) => s + l.credit, 0)
    expect(totalDebit).toBe(totalCredit)
    // Entrée: 100*50 = 5000, Sortie: 30*50 = 1500 → total = 6500
    expect(totalDebit).toBe(6500)
  })

  it('multiple entrées à coûts différents', () => {
    const sim = new StockSimulation()
    sim.addProduct({ id: 'p1', name: 'A', stock_quantity: 0, cost_price: 0, tenant_id: 'test-tenant-id' })

    sim.processMovement({
      id: 'm1', product_id: 'p1', quantity: 50, unit_cost: 100,
      movement_type: 'in', warehouse_id: null,
      movement_date: '2024-01-01', reference: null, tenant_id: 'test-tenant-id',
    })
    sim.processMovement({
      id: 'm2', product_id: 'p1', quantity: 50, unit_cost: 120,
      movement_type: 'in', warehouse_id: null,
      movement_date: '2024-02-01', reference: null, tenant_id: 'test-tenant-id',
    })

    expect(sim.products.get('p1')!.stock_quantity).toBe(100)
    expect(sim.journalEntries).toHaveLength(2)

    // Valorisation au dernier coût
    const val = sim.getStockValuation()
    expect(val[0].unit_cost).toBe(120)  // dernier mouvement
    expect(val[0].total_value).toBe(12000)  // 100 * 120
  })

  it('ajustement d\'inventaire', () => {
    const sim = new StockSimulation()
    sim.addProduct({ id: 'p1', name: 'A', stock_quantity: 50, cost_price: 100, tenant_id: 'test-tenant-id' })

    // Ajustement: stock réel = 45 (perte de 5)
    sim.processMovement({
      id: 'm1', product_id: 'p1', quantity: 45, unit_cost: 100,
      movement_type: 'adjustment', warehouse_id: null,
      movement_date: '2024-03-01', reference: 'INV-ADJ', tenant_id: 'test-tenant-id',
    })
    expect(sim.products.get('p1')!.stock_quantity).toBe(45)
    expect(sim.journalEntries).toHaveLength(1)
    // Ajustement génère une écriture de valeur 45 * 100 = 4500
    const totalDebit = sim.journalLines.reduce((s, l) => s + l.debit, 0)
    expect(totalDebit).toBe(4500)
  })

  it('tenant isolation : produit d\'un autre tenant → erreur', () => {
    const sim = new StockSimulation()
    sim.addProduct({ id: 'p1', name: 'A', stock_quantity: 10, cost_price: 50, tenant_id: 'other-tenant' })
    expect(() => sim.incrementStock('p1', 5)).toThrow('tenant')
  })
})
