import { it } from 'vitest'
import { login, A, sql, check, attempt, save, findings, RIG_USERS } from './rig'
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
  // M9 (271) : la séparation des tâches s'active dans les paramètres de la société (D-13) ;
  // elle est activée ici PAR L'ÉCRAN (Paramètres → Société), puis rendue à son état.
  const acc = await import('@/lib/queries/accounting')
  const cs = await acc.getCompanySettings()
  await acc.updateCompanySettings(cs!.id, { enforce_segregation: true } as any)
  const selfApprove = await attempt(() => sales.updatePurchaseInvoiceApproval(pinv.id, 'approved'))
  const st1 = (await sql(`select status, approval_status, number from purchase_invoices where id=$1`, [pinv.id]))[0]
  check('P03', 'séparation des tâches : le saisisseur ne peut pas approuver sa propre facture', !selfApprove.ok, selfApprove.err ?? st1)
  await login(3, A) // comptable
  const approve = await attempt(() => sales.updatePurchaseInvoiceApproval(pinv.id, 'approved'))
  const st2 = (await sql(`select status, approval_status, number, created_by = $2 as auteur_admin, approved_by = $3 as approbateur_comptable
                          from purchase_invoices where id=$1`, [pinv.id, RIG_USERS[0].id, RIG_USERS[3].id]))[0]
  check('P03b', 'l\'approbation enregistre l\'auteur (admin) et l\'approbateur (comptable)', approve.ok && st2.auteur_admin && st2.approbateur_comptable, { err: approve.err, st2 })
  await login(0, A)
  await acc.updateCompanySettings(cs!.id, { enforce_segregation: (cs as any)?.enforce_segregation ?? false } as any)
  await login(3, A)
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

  // ---------- Stock ----------
  const w = await attempt(() => stock.createWarehouse({ code: 'DEP'+Date.now(), name: 'Dépôt principal', address: null, city: null, postal_code: null, country: 'France', active: true } as any))
  check('ST01', 'créer un dépôt', w.ok, w.err ?? (w.val as any).id)
  const wh: any = w.val
  // ProductsPage (M6, 280) : la quantité initiale devient un mouvement `initial` au dépôt choisi, au prix d'achat
  const p = await attempt(() => stock.createProduct({ name: 'Article A', sku: 'ART-'+Date.now(), type: 'stock', sale_price: 20, purchase_price: 12, vat_rate: 20, reorder_level: 5, unit: 'u', category: '', active: true, description: '', sale_account_code: null, purchase_account_code: null, stock_account_code: null } as any,
    { quantity: 50, warehouse_id: wh.id, unit_cost: 12 }))
  const prod: any = p.val
  const layers0 = p.ok ? (await sql(`select coalesce(sum(remaining_qty),0)::float q, coalesce(sum(remaining_qty*unit_cost),0)::float v from stock_valuation_layers where product_id=$1`, [prod.id]))[0] : null
  const mv0 = p.ok ? (await sql(`select count(*)::int n from stock_movements where product_id=$1`, [prod.id]))[0].n : -1
  check('ST02', 'article créé avec stock initial 50 (ProductsPage) : le stock a une origine (mouvement + couche valorisée)', p.ok && mv0 > 0 && layers0!.q === 50 && Number(prod.stock_quantity) === 50, { err: p.err, stock_quantity: prod?.stock_quantity, mouvements: mv0, couches: layers0 })
  const direct = await attempt(() => stock.updateProduct(prod.id, { stock_quantity: 999 } as any))
  const qd = (await sql(`select stock_quantity::float q from products where id=$1`, [prod.id]))[0].q
  check('ST02b', 'la quantité en stock ne se saisit pas sur la fiche (écriture directe refusée)', !direct.ok && qd === 50, { err: direct.err, stock: qd })

  // ProductsPage : entrée de 10 (C8, 280 : type, dépôt et coût)
  const today = '2026-09-28'
  const m1 = await attempt(() => stock.createStockMovement({ product_id: prod.id, warehouse_id: wh.id, movement_type: 'in', quantity: 10, unit_cost: 12, reference: 'E1', reference_type: 'manual', reference_id: null, movement_date: today, notes: null } as any))
  const q1 = (await sql(`select stock_quantity::float q from products where id=$1`, [prod.id]))[0]
  check('ST03', 'entrée de 10 depuis la fiche article : stock 50 → 60', m1.ok && q1.q === 60, { err: m1.err, stock: q1.q })
  // InventoryPage : 57 comptés au dépôt pour 60 attendus
  const m2 = await attempt(() => stock.createStockMovement({ product_id: prod.id, warehouse_id: wh.id, movement_type: 'adjustment', quantity: 57, unit_cost: 12, reference: 'INV-2026-09-28', reference_type: 'inventory', reference_id: null, movement_date: today, notes: null } as any))
  const q2 = (await sql(`select p.stock_quantity::float q, (select coalesce(sum(quantity),0)::float from stock_quantities sq where sq.product_id=p.id and sq.warehouse_id=$2) wq from products p where id=$1`, [prod.id, wh.id]))[0]
  check('ST04', 'ajustement d\'inventaire (InventoryPage) : 57 comptés au dépôt pour 60 → stock 57, article et dépôt d\'accord', m2.ok && q2.q === 57 && q2.wq === 57, { err: m2.err, apres: q2 })
  const m3 = await attempt(() => stock.createStockMovement({ product_id: prod.id, warehouse_id: wh.id, movement_type: 'out', quantity: 5000, unit_cost: 0, reference: 'S-trop', reference_type: 'manual', reference_id: null, movement_date: today, notes: null } as any))
  const q3 = (await sql(`select stock_quantity::float q from products where id=$1`, [prod.id]))[0]
  check('ST05', 'sortie de 5 000 sur un stock de 57 : refusée, stock inchangé', !m3.ok && q3.q === 57, { err: m3.err, stock: q3.q })
  const m4 = await attempt(() => stock.createStockMovement({ product_id: prod.id, warehouse_id: wh.id, movement_type: 'out', quantity: 4, unit_cost: 0, reference: 'S1', reference_type: 'manual', reference_id: null, movement_date: today, notes: null } as any))
  const q4 = (await sql(`select stock_quantity::float q from products where id=$1`, [prod.id]))[0]
  check('ST06', 'sortie de 4 depuis la fiche article : stock baisse de 4', m4.ok && q4.q === r2(q3.q - 4), { err: m4.err, avant: q3.q, apres: q4.q })
  const st = await sql(`select l.account_code, sum(l.debit)::float d, sum(l.credit)::float c from journal_lines l join journal_entries e on e.id=l.journal_id where e.tenant_id=$1 and e.status='posted' and e.journal_code='ST' group by 1`, [A])
  check('ST07', 'les mouvements valorisés passent au journal ST (31/603)', st.length > 0, st)

  // ---------- Commande fournisseur et réception (C9, 280) ----------
  const po = await attempt(async () => purchases.createPurchaseOrder({ number: await core.nextDocumentNumber('CF'), supplier_id: sup.id, order_date: '2026-09-01', expected_date: null, notes: null },
    [{ product_id: prod.id, description: 'Article A', quantity: 20, unit_price: 12, vat_rate: 20 }]))
  const poRow = po.ok ? (await sql(`select subtotal::float ht, vat::float tva, total::float ttc, (select count(*)::int from purchase_order_lines l where l.purchase_order_id=o.id) n from purchase_orders o where id=$1`, [(po.val as any).id]))[0] : null
  check('P06', 'commande fournisseur (PurchaseOrdersPage) : 1 ligne 20 × 12, totaux calculés par la base 240 + 48 = 288', po.ok && poRow.n === 1 && poRow.ht === 240 && poRow.tva === 48 && poRow.ttc === 288, { err: po.err, poRow })
  const conf = po.ok ? await attempt(() => purchases.updatePurchaseOrder((po.val as any).id, { status: 'confirmed' } as any)) : po
  const before = (await sql(`select stock_quantity::float q from products where id=$1`, [prod.id]))[0].q
  const gr = conf.ok ? await attempt(async () => misc.createGoodsReceiptFromOrder((po.val as any).id, { number: await core.nextDocumentNumber('BR'), receipt_date: today, warehouse_id: wh.id })) : conf
  const grl = gr.ok ? (await sql(`select count(*)::int n, coalesce(sum(quantity_received),0)::float q from goods_receipt_lines where goods_receipt_id=$1`, [(gr.val as any).id]))[0] : null
  const recv = gr.ok ? await attempt(() => misc.updateGoodsReceipt((gr.val as any).id, { status: 'received' })) : gr
  const afterQ = (await sql(`select stock_quantity::float q from products where id=$1`, [prod.id]))[0].q
  const poSt = po.ok ? (await sql(`select status from purchase_orders where id=$1`, [(po.val as any).id]))[0].status : null
  check('ST08', 'réception créée depuis la commande confirmée (1 ligne, 20) puis « reçue » : +20 en stock, commande reçue', recv.ok && grl?.n === 1 && grl?.q === 20 && afterQ === before + 20 && poSt === 'received', { err: recv.err, lignes_de_reception: grl, avant: before, apres: afterQ, commande: poSt })
  const again = po.ok ? await attempt(async () => misc.createGoodsReceiptFromOrder((po.val as any).id, { number: await core.nextDocumentNumber('BR'), receipt_date: today, warehouse_id: wh.id })) : po
  check('ST08b', 'une commande entièrement reçue ne se réceptionne plus', !again.ok, again.err ?? 'ACCEPTÉ')

  // ---------- Commande client et BL (C10, 280) ----------
  const cust = (await sql(`select id from customers where tenant_id=$1 limit 1`, [A]))[0]
  const so = await attempt(async () => sales.createSalesOrder({ number: await core.nextDocumentNumber('CC'), customer_id: cust.id, order_date: today, delivery_date: null, notes: null },
    [{ product_id: prod.id, description: 'Article A', quantity: 5, unit_price: 20, vat_rate: 20 }]))
  const soRow = so.ok ? (await sql(`select subtotal::float ht, vat::float tva, total::float ttc, (select count(*)::int from sales_order_lines l where l.sales_order_id=o.id) n from sales_orders o where id=$1`, [(so.val as any).id]))[0] : null
  check('ST09', 'commande client (SalesOrdersPage) : 1 ligne 5 × 20, TVA 20 → 100 + 20 = 120', so.ok && soRow.n === 1 && soRow.ht === 100 && soRow.tva === 20 && soRow.ttc === 120, { err: so.err, soRow })
  const soConf = so.ok ? await attempt(() => sales.updateSalesOrder((so.val as any).id, { status: 'confirmed' } as any)) : so
  const bq0 = (await sql(`select stock_quantity::float q from products where id=$1`, [prod.id]))[0].q
  const soLines = soConf.ok ? await misc.getSalesOrderLines((so.val as any).id) : []
  const dn = soConf.ok ? await attempt(() => misc.transformSalesOrderToDeliveryNote((so.val as any).id, soLines.map((l) => ({ sales_order_line_id: l.id, quantity: Number(l.quantity) - Number(l.delivered_quantity || 0) })), { delivery_date: today })) : soConf
  const ship = dn.ok ? await attempt(() => sales.updateDeliveryNote((dn.val as any).id, { status: 'shipped' } as any)) : dn
  const bq1 = (await sql(`select stock_quantity::float q from products where id=$1`, [prod.id]))[0].q
  const posted = dn.ok ? await stock.getStockPostedReferences('delivery_note', [(dn.val as any).id]) : new Set()
  check('ST10', 'BL créé depuis la commande puis expédié : −5 en stock, et l\'écran lit « Sorti » sur le mouvement réel', ship.ok && bq1 === bq0 - 5 && posted.size === 1, { err: ship.err ?? soConf.err, avant: bq0, apres: bq1, sorti: posted.size })
  save('s2.json', findings)
})
