import { it } from 'vitest'
import { login, A, sql, check, attempt, save, findings } from './rig'
it('Production et trésorerie', async () => {
  await login(0, A)
  const stock = await import('@/lib/queries/stock')
  const prodq = await import('@/lib/queries/production')
  const banking = await import('@/lib/queries/banking')
  const n = Date.now() % 100000
  const wh = (await sql(`select id from warehouses where tenant_id=$1 order by created_at desc limit 1`, [A]))[0]
  // composant avec stock initial 100 @5 via InventoryPage ('initial')
  const comp: any = (await attempt(() => stock.createProduct({ name: 'Composant ' + n, sku: 'CMP' + n, type: 'stock', sale_price: 0, purchase_price: 5, vat_rate: 20, stock_quantity: 0, reorder_level: 0, unit: 'u', category: '', active: true, description: '' } as any))).val
  const fin: any = (await attempt(() => stock.createProduct({ name: 'Produit fini ' + n, sku: 'PF' + n, type: 'stock', sale_price: 50, purchase_price: 0, vat_rate: 20, stock_quantity: 0, reorder_level: 0, unit: 'u', category: '', active: true, description: '' } as any))).val
  const init = await attempt(() => stock.createStockMovement({ product_id: comp.id, warehouse_id: wh.id, movement_type: 'initial', quantity: 100, unit_cost: 5, reference: 'INV', reference_type: 'inventory', reference_id: null, movement_date: '2026-09-28', notes: null } as any))
  check('M01', 'stock initial du composant : 100 @ 5 (InventoryPage, type « initial »)', init.ok, init.err ?? (await sql(`select stock_quantity::float q from products where id=$1`, [comp.id]))[0])
  const bom = await attempt(() => stock.createBOM({ code: 'BOM' + n, name: 'Nomenclature', product_id: fin.id, quantity: 1, unit: 'u', active: true, bom_type: 'standard', routing_id: null } as any))
  const bl = bom.ok ? await attempt(() => stock.createBOMLine({ bom_id: (bom.val as any).id, product_id: comp.id, quantity: 2, unit_cost: 5, position: 1 } as any)) : bom
  check('M02', 'nomenclature : 1 produit fini = 2 composants', bom.ok && bl.ok, bom.err ?? bl.err ?? 'ok')
  const mo = await attempt(() => prodq.createManufacturingOrder({ number: 'OF-' + n, bom_id: (bom.val as any)?.id, product_id: null, quantity: 10, status: 'planned', start_date: '2026-09-28', end_date: null, warehouse_id: wh.id, routing_id: null, notes: null } as any))
  check('M03', 'ordre de fabrication de 10 (ManufacturingOrdersPage, product_id: null)', mo.ok, mo.err ?? (mo.val as any).number)
  const upd = (prodq as any).updateManufacturingOrder ?? (stock as any).updateManufacturingOrder
  const s1 = await attempt(() => upd((mo.val as any).id, { status: 'in_progress' }))
  const s2 = await attempt(() => upd((mo.val as any).id, { status: 'completed' }))
  const q = await sql(`select (select stock_quantity::float from products where id=$1) fin, (select stock_quantity::float from products where id=$2) comp`, [fin.id, comp.id])
  check('M04', 'OF terminé : +10 produits finis, −20 composants', s1.ok && s2.ok && q[0].fin === 10 && q[0].comp === 80, { err: s1.err ?? s2.err, stocks: q[0] })
  const moRow = (await sql(`select status, product_id from manufacturing_orders where id=$1`, [(mo.val as any).id]))[0]
  check('M05', 'l\'écran affiche « Stock : Généré » (statut completed) — vérité en base ?', !(moRow.status === 'completed' && q[0].fin !== 10), { statut: moRow.status, badge_affiche: moRow.status === 'completed' ? 'Généré' : 'En attente', stock_fini_reel: q[0].fin })

  // ---------- Trésorerie ----------
  const bank = (await sql(`select id, account_code from bank_accounts where tenant_id=$1 order by created_at limit 1`, [A]))[0]
  const mt940 = [':20:REL1', ':25:FR7612345', ':28C:1/1', ':60F:C260901EUR1000,00',
    ':61:2609200920C500,00NTRFNONREF', ':86:VIR CLIENT AUDIT FAC-2026-000004',
    ':61:2609210921D12,50NCHGNONREF', ':86:CB BOULANGERIE',
    ':61:2609210921D12,50NCHGNONREF', ':86:CB BOULANGERIE',
    ':62F:C260930EUR1475,00', '-'].join('\n')
  const imp = await attempt(() => banking.importBankStatement(bank.id, 'releve.sta', mt940, 'mt940' as any))
  const tx = await sql(`select date, amount::float, type, description from bank_transactions where bank_account_id=$1 order by date, id`, [bank.id])
  check('B01', 'import MT940 : 3 opérations, dont 2 paiements CB identiques le même jour (légitimes)', imp.ok && tx.length === 3, { err: imp.err, resume: imp.val, lignes: tx })
  // M4 : réimporter le même relevé n'ajoute rien
  const imp2 = await attempt(() => banking.importBankStatement(bank.id, 'releve.sta', mt940, 'mt940' as any))
  const tx2 = await sql(`select count(*)::int n from bank_transactions where bank_account_id=$1`, [bank.id])
  check('B01b', 'réimport du même relevé : aucune opération ajoutée', imp2.ok && (imp2.val as any).imported === 0 && tx2[0].n === tx.length, { err: imp2.err, resume: imp2.val, lignes: tx2[0].n })
  const acct = (await sql(`select balance::float, statement_balance::float, calculated_balance::float from bank_accounts where id=$1`, [bank.id]))[0]
  check('B02', 'solde de clôture du relevé repris (1 475,00)', acct.statement_balance === 1475, acct)
  const am = await attempt(() => banking.autoMatchBankTransactions(bank.id))
  const matched = await sql(`select count(*)::int n from bank_transactions where bank_account_id=$1 and (reconciled or matched_line_id is not null)`, [bank.id])
  check('B03', 'rapprochement automatique : le virement de 500 trouve l\'encaissement de 500 au 512', am.ok && matched[0].n >= 1, { err: am.err, res: am.val, rapproches: matched[0].n })
  const state = await attempt(() => banking.getBankReconciliationState(bank.id, '2026-09-30'))
  check('B04', 'état de rapprochement lisible au 30/09', state.ok, state.err ?? state.val)
  save('s8.json', findings)
})
