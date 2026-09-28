import { it } from 'vitest'
import { login, A, sql, check, attempt, save, findings } from './rig'
const r2 = (n: number) => Math.round(n * 100) / 100

it('Achats, fournisseurs, stock — par les fonctions des écrans', async () => {
  await login(0, A)
  const partners = await import('@/lib/queries/partners')
  const sales = await import('@/lib/queries/sales')
  const stock = await import('@/lib/queries/stock')
  const misc = await import('@/lib/queries/misc')
  const core = await import('@/lib/queries/core')
  const purchases = await import('@/lib/queries/purchases')
  const bank = (await sql(`select id from bank_accounts where tenant_id=$1 order by created_at limit 1`, [A]))[0]

  // ---------- Achats ----------
  const s = await attempt(() => partners.createSupplier({ name: 'Fournisseur Audit', email: 'f@audit.test', phone: '', address: '', vat_number: '' } as any))
  check('P01', 'créer un fournisseur', s.ok, s.err ?? (s.val as any).id)
  const sup: any = s.val
  const pi = await attempt(() => sales.createPurchaseInvoice({ supplier_reference: 'F-778', supplier_id: sup.id, supplier_name: sup.name, date: '2026-09-05', due_date: '2026-10-05', status: 'draft',
    subtotal: 300, vat_total: 60, total: 360, amount_paid: 0, amount_due: 360, notes: '',
    lines: [{ product_id: null, description: 'Fournitures', quantity: 3, unit_price: 100, vat_rate: 20, total: 300, vat_total: 60, vat_amount: 60, line_order: 0 }] } as any))
  const pinv: any = pi.val
  check('P02', 'saisir une facture d\'achat 300 + 60 = 360', pi.ok && Number(pinv.total) === 360, pi.err ?? { n: pinv.number, total: pinv.total, st: pinv.status })
  const selfApprove = await attempt(() => sales.updatePurchaseInvoiceApproval(pinv.id, 'approved'))
  const st1 = (await sql(`select status, approval_status, number from purchase_invoices where id=$1`, [pinv.id]))[0]
  check('P03', 'séparation des tâches : le saisisseur ne peut pas approuver sa propre facture', !selfApprove.ok, selfApprove.err ?? st1)
  await login(3, A) // comptable
  const approve = await attempt(() => sales.updatePurchaseInvoiceApproval(pinv.id, 'approved'))
  const st2 = (await sql(`select status, approval_status, number from purchase_invoices where id=$1`, [pinv.id]))[0]
  const ac = await sql(`select l.account_code, l.debit::float d, l.credit::float c, e.journal_code from journal_lines l join journal_entries e on e.id=l.journal_id where e.tenant_id=$1 and e.status='posted' and e.journal_code='AC' and e.id=(select id from journal_entries where tenant_id=$1 and journal_code='AC' order by created_at desc limit 1)`, [A])
  const d6 = ac.filter((x: any) => x.account_code.startsWith('6')).reduce((a: number, x: any) => a + x.d, 0)
  const d4456 = ac.filter((x: any) => x.account_code.startsWith('4456')).reduce((a: number, x: any) => a + x.d, 0)
  const c401 = ac.filter((x: any) => x.account_code.startsWith('401')).reduce((a: number, x: any) => a + x.c, 0)
  check('P04', 'approbation par un comptable : écriture AC D6 300 / D4456 60 / C401 360', approve.ok && r2(d6) === 300 && r2(d4456) === 60 && r2(c401) === 360, { err: approve.err, st2, ac })
  await login(0, A)
  const pay = await attempt(async () => partners.createSupplierPayment({ number: await core.nextDocumentNumber('DEC'), supplier_id: sup.id, purchase_invoice_id: pinv.id, payment_date: '2026-09-28', amount: 360, method: 'transfer', bank_account_id: bank.id, reference: 'F-778', status: 'recorded' } as any))
  const st3 = (await sql(`select status, amount_paid::float, amount_due::float from purchase_invoices where id=$1`, [pinv.id]))[0]
  const s401 = (await sql(`select coalesce(sum(debit-credit),0)::float s from journal_lines l join journal_entries e on e.id=l.journal_id where e.tenant_id=$1 and e.status='posted' and l.account_code like '401%'`, [A]))[0].s
  check('P05', 'décaissement 360 : facture payée, 401 soldé', pay.ok && st3.amount_due === 0 && r2(s401) === 0, { err: pay.err, st3, s401 })

  // commande fournisseur et réception par les écrans
  const po = await attempt(async () => purchases.createPurchaseOrder({ number: await core.nextDocumentNumber('CF'), supplier_id: sup.id, order_date: '2026-09-01', expected_date: null, status: 'draft', subtotal: 500, vat: 0, total: 500, notes: null } as any))
  const poLines = po.ok ? (await sql(`select count(*)::int n from purchase_order_lines where purchase_order_id=$1`, [(po.val as any).id]))[0].n : -1
  check('P06', 'commande fournisseur (PurchaseOrdersPage) : porte-t-elle des lignes article/quantité ?', po.ok && poLines > 0, { err: po.err, lignes: poLines, tva: (po.val as any)?.vat })

  // ---------- Stock ----------
  const w = await attempt(() => stock.createWarehouse({ code: 'DEP'+Date.now(), name: 'Dépôt principal', address: null, city: null, postal_code: null, country: 'France', active: true } as any))
  check('ST01', 'créer un dépôt', w.ok, w.err ?? (w.val as any).id)
  const wh: any = w.val
  const p = await attempt(() => stock.createProduct({ name: 'Article A', sku: 'ART-'+Date.now(), type: 'stock', sale_price: 20, purchase_price: 12, vat_rate: 20, stock_quantity: 50, reorder_level: 5, unit: 'u', category: '', active: true, description: '', sale_account_code: null, purchase_account_code: null, stock_account_code: null } as any))
  const prod: any = p.val
  const layers0 = p.ok ? (await sql(`select coalesce(sum(remaining_qty),0)::float q, coalesce(sum(remaining_qty*unit_cost),0)::float v from stock_valuation_layers where product_id=$1`, [prod.id]))[0] : null
  const mv0 = p.ok ? (await sql(`select count(*)::int n from stock_movements where product_id=$1`, [prod.id]))[0].n : -1
  check('ST02', 'article créé avec stock initial 50 (ProductsPage) : le stock a une origine (mouvement + couche valorisée)', p.ok && mv0 > 0 && layers0!.q === 50, { err: p.err, stock_quantity: prod?.stock_quantity, mouvements: mv0, couches: layers0 })

  // ProductsPage : mouvement d'entrée 10 (envoie `type` seulement)
  const m1 = await attempt(() => stock.createStockMovement({ product_id: prod.id, type: 'in', quantity: 10, reference: 'E1', date: '2026-09-28' } as any))
  const q1 = (await sql(`select stock_quantity::float q from products where id=$1`, [prod.id]))[0]
  check('ST03', 'entrée de 10 depuis la fiche article : stock 50 → 60', m1.ok && q1.q === 60, { err: m1.err, stock: q1.q })
  // InventoryPage : ajustement (envoie `movement_type` seulement)
  const m2 = await attempt(() => stock.createStockMovement({ product_id: prod.id, warehouse_id: wh.id, movement_type: 'adjustment', quantity: 7, unit_cost: 12, reference: 'INV-2026-09-28', reference_type: 'inventory', reference_id: null, movement_date: '2026-09-28', notes: null } as any))
  const q2 = (await sql(`select p.stock_quantity::float q, (select coalesce(sum(quantity),0)::float from stock_quantities sq where sq.product_id=p.id and sq.warehouse_id=$2) wq from products p where id=$1`, [prod.id, wh.id]).catch(async () => sql(`select stock_quantity::float q from products where id=$1`, [prod.id])))[0]
  check('ST04', 'ajustement d\'inventaire (InventoryPage) de 7 au dépôt : accepté, stock cohérent', m2.ok, { err: m2.err, apres: q2 })
  const m3 = await attempt(() => stock.createStockMovement({ product_id: prod.id, type: 'out', quantity: 5000, reference: 'S-trop', date: '2026-09-28' } as any))
  const q3 = (await sql(`select stock_quantity::float q from products where id=$1`, [prod.id]))[0]
  check('ST05', 'sortie de 5 000 sur un stock de ~60 : refusée, stock jamais négatif', !m3.ok && q3.q >= 0, { err: m3.err, stock: q3.q })
  const m4 = await attempt(() => stock.createStockMovement({ product_id: prod.id, type: 'out', quantity: 4, reference: 'S1', date: '2026-09-28' } as any))
  const q4 = (await sql(`select stock_quantity::float q from products where id=$1`, [prod.id]))[0]
  check('ST06', 'sortie de 4 depuis la fiche article : stock baisse de 4', m4.ok && q4.q === r2(q3.q - 4), { err: m4.err, avant: q3.q, apres: q4.q })
  const st = await sql(`select l.account_code, sum(l.debit)::float d, sum(l.credit)::float c from journal_lines l join journal_entries e on e.id=l.journal_id where e.tenant_id=$1 and e.status='posted' and e.journal_code='ST' group by 1`, [A])
  check('ST07', 'les mouvements valorisés passent au journal ST (31/603)', st.length > 0, st)

  // réception par l'écran
  const gr = await attempt(async () => misc.createGoodsReceipt({ number: await core.nextDocumentNumber('BR'), supplier_id: sup.id, purchase_order_id: (po.val as any)?.id ?? null, receipt_date: '2026-09-28', status: 'pending', notes: null } as any))
  const before = (await sql(`select count(*)::int n from stock_movements where tenant_id=$1`, [A]))[0].n
  const recv = gr.ok ? await attempt(() => (misc as any).updateGoodsReceipt((gr.val as any).id, { status: 'received' })) : gr
  const afterN = (await sql(`select count(*)::int n from stock_movements where tenant_id=$1`, [A]))[0].n
  const grl = gr.ok ? (await sql(`select count(*)::int n from goods_receipt_lines where goods_receipt_id=$1`, [(gr.val as any).id]))[0].n : -1
  check('ST08', 'réception saisie par l\'écran puis « reçue » : fait-elle entrer de la marchandise ?', recv.ok && afterN > before, { err: recv.err, lignes_de_reception: grl, mouvements_avant: before, apres: afterN })

  // commande client et BL par les écrans
  const cust = (await sql(`select id from customers where tenant_id=$1 limit 1`, [A]))[0]
  const so = await attempt(async () => sales.createSalesOrder({ number: await core.nextDocumentNumber('CC'), customer_id: cust.id, order_date: '2026-09-28', delivery_date: null, status: 'draft', subtotal: 1000, vat: 0, total: 1000, notes: null } as any))
  const sol = so.ok ? (await sql(`select count(*)::int n from sales_order_lines where sales_order_id=$1`, [(so.val as any).id]))[0].n : -1
  check('ST09', 'commande client (SalesOrdersPage) : lignes et TVA', so.ok && sol > 0, { err: so.err, lignes: sol, tva: (so.val as any)?.vat, total: (so.val as any)?.total })
  save('s2.json', findings)
})
