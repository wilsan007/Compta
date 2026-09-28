import { it } from 'vitest'
import { login, A, sql, check, attempt, ledger, save, findings } from './rig'

it('Ventes -> trésorerie -> grand livre, par les fonctions des écrans', async () => {
  await login(0, A)
  const partners = await import('@/lib/queries/partners')
  const sales = await import('@/lib/queries/sales')
  const banking = await import('@/lib/queries/banking')
  const core = await import('@/lib/queries/core')
  const misc = await import('@/lib/queries/misc')

  // S01 client
  const c = await attempt(() => partners.createCustomer({ name: 'Client Audit 1', email: 'c1@audit.test', phone: '', address: '1 rue X', vat_number: 'FR12345678901', is_company: true } as any))
  check('S01', 'créer un client (CustomersPage)', c.ok, c.err ?? (c.val as any)?.id)
  const cust: any = c.val
  const acc = await sql(`select account_tiers, account_collectif from customers where id=$1`, [cust?.id]).catch((e) => [{ e: e.message }])
  check('S01b', 'le client reçoit un compte auxiliaire', !!acc[0]?.account_tiers, acc[0])

  // S02 compte bancaire avec solde initial 1000
  const b = await attempt(() => banking.createBankAccount({ name: 'Banque Audit', bank_name: 'BNP', type: 'chequing', balance: 1000, currency: 'EUR', connected: false, account_number: '' } as any))
  check('S02', 'créer un compte bancaire (BankAccountsPage)', b.ok, b.err ?? (b.val as any)?.id)
  const bank: any = b.val
  const bankRow = (await sql(`select * from bank_accounts where id=$1`, [bank?.id]))[0]
  const l512 = await sql(`select coalesce(sum(debit-credit),0)::float s from journal_lines l join journal_entries e on e.id=l.journal_id where e.tenant_id=$1 and e.status='posted' and l.account_code like $2`, [A, (bankRow?.account_code || '512') + '%'])
  check('S02b', 'solde initial saisi (1000) et solde comptable du compte banque concordent', Number(bankRow?.balance) === Number(l512[0].s), { bank_balance: bankRow?.balance, ledger: l512[0].s, account_code: bankRow?.account_code, gl_account: bankRow?.gl_account_code })

  // S03 facture brouillon : 10 x 100 @20 + 1 x 55.50 @5.5
  const lines = [
    { description: 'Prestation', quantity: 10, unit_price: 100, vat_rate: 20 },
    { description: 'Livre', quantity: 1, unit_price: 55.5, vat_rate: 5.5 },
  ]
  const r2 = (n: number) => Math.round(n * 100) / 100
  const ht = r2(lines.reduce((s, l) => s + l.quantity * l.unit_price, 0))
  const tva = r2(lines.reduce((s, l) => s + r2(l.quantity * l.unit_price * l.vat_rate / 100), 0))
  const inv = await attempt(() => sales.createInvoice({
    customer_id: cust.id, customer_name: cust.name, date: '2026-09-10', due_date: '2026-10-10', status: 'draft',
    subtotal: ht, vat_total: tva, total: r2(ht + tva), amount_paid: 0, amount_due: r2(ht + tva), notes: '', recurring: false, recurring_frequency: null,
    lines: lines.map((l, i) => ({ product_id: null, description: l.description, quantity: l.quantity, unit_price: l.unit_price, vat_rate: l.vat_rate,
      total: r2(l.quantity * l.unit_price), vat_total: r2(l.quantity * l.unit_price * l.vat_rate / 100), vat_amount: r2(l.quantity * l.unit_price * l.vat_rate / 100), line_order: i, advance_invoice_id: null })),
  } as any))
  const invoice: any = inv.val
  check('S03', `créer une facture brouillon (attendu ${ht} / ${tva} / ${r2(ht + tva)})`, inv.ok && Number(invoice.subtotal) === ht && Number(invoice.vat_total) === tva && Number(invoice.total) === r2(ht + tva),
    inv.err ?? { n: invoice.number, st: invoice.status, v: invoice.validation_status, ht: invoice.subtotal, tva: invoice.vat_total, ttc: invoice.total })
  const draftEntries = await sql(`select count(*)::int n from journal_entries where tenant_id=$1 and (reference=$2 or invoice_ref=$2)`, [A, invoice?.number])
  check('S03b', 'un brouillon ne passe aucune écriture', draftEntries[0].n === 0, draftEntries[0])

  // S04 validation
  const v = await attempt(() => sales.updateInvoice(invoice.id, { validation_status: 'validated' } as any))
  const invV = (await sql(`select number, status, validation_status, subtotal::float, vat_total::float, total::float, amount_due::float, transferred_entry_id from invoices where id=$1`, [invoice.id]))[0]
  check('S04', 'valider la facture : numéro légal FAC-2026-xxxxxx', v.ok && /^FAC-2026-\d{6}$/.test(invV.number), v.err ?? invV)
  const je = await sql(`select e.id, e.status, e.journal_code, e.posting_number, e.total_debit::float td, e.total_credit::float tc from journal_entries e where e.tenant_id=$1 and (e.id=$2 or e.reference=$3 or e.invoice_ref=$3)`, [A, invV.transferred_entry_id, invV.number])
  const jl = je[0] ? await sql(`select account_code, debit::float, credit::float from journal_lines where journal_id=$1 order by line_order`, [je[0].id]) : []
  const d411 = jl.filter((l: any) => l.account_code.startsWith('411')).reduce((s: number, l: any) => s + l.debit, 0)
  const c706 = jl.filter((l: any) => l.account_code.startsWith('70')).reduce((s: number, l: any) => s + l.credit, 0)
  const c4457 = jl.filter((l: any) => l.account_code.startsWith('4457')).reduce((s: number, l: any) => s + l.credit, 0)
  check('S04b', `écriture de vente : D411 ${r2(ht + tva)} / C70 ${ht} / C4457 ${tva}, validée, journal VT`,
    je.length === 1 && je[0].status === 'posted' && je[0].journal_code === 'VT' && r2(d411) === r2(ht + tva) && r2(c706) === ht && r2(c4457) === tva,
    { entries: je, lines: jl })
  const vatAccounts = [...new Set(jl.filter((l: any) => l.account_code.startsWith('4457')).map((l: any) => l.account_code))]
  check('S04c', 'deux taux (20 % et 5,5 %) -> deux comptes de TVA collectée distincts', vatAccounts.length === 2, vatAccounts)

  // S05 modifier / supprimer une facture validée : refusé
  const upd = await attempt(() => sales.updateInvoice(invoice.id, { subtotal: 1, total: 1 } as any))
  const after = (await sql(`select subtotal::float, total::float from invoices where id=$1`, [invoice.id]))[0]
  check('S05', 'modifier le montant d\'une facture validée est refusé', !upd.ok || (after.subtotal === ht), { err: upd.err, after })
  const del = await attempt(() => sales.deleteInvoice(invoice.id))
  const still = (await sql(`select count(*)::int n from invoices where id=$1`, [invoice.id]))[0].n
  check('S05b', 'supprimer une facture validée est refusé', !del.ok && still === 1, { err: del.err, still })

  // S06 règlement partiel 500 puis solde
  const pay1 = await attempt(async () => partners.createCustomerPayment({ number: await core.nextDocumentNumber('REG'), customer_id: cust.id, invoice_id: invoice.id,
    payment_date: '2026-09-20', amount: 500, method: 'transfer', bank_account_id: bank.id, reference: invV.number, status: 'recorded' } as any))
  const i1 = (await sql(`select status, amount_paid::float, amount_due::float from invoices where id=$1`, [invoice.id]))[0]
  check('S06', `règlement partiel 500 : payé 500, reste ${r2(ht + tva - 500)}`, pay1.ok && i1.amount_paid === 500 && i1.amount_due === r2(ht + tva - 500), pay1.err ?? i1)
  const pay2 = await attempt(async () => partners.createCustomerPayment({ number: await core.nextDocumentNumber('REG'), customer_id: cust.id, invoice_id: invoice.id,
    payment_date: '2026-09-25', amount: r2(ht + tva - 500), method: 'transfer', bank_account_id: bank.id, reference: invV.number, status: 'recorded' } as any))
  const i2 = (await sql(`select status, amount_paid::float, amount_due::float from invoices where id=$1`, [invoice.id]))[0]
  check('S06b', 'règlement du solde : facture payée, reste 0', pay2.ok && i2.status === 'paid' && i2.amount_due === 0, pay2.err ?? i2)
  const pay3 = await attempt(async () => partners.createCustomerPayment({ number: await core.nextDocumentNumber('REG'), customer_id: cust.id, invoice_id: invoice.id,
    payment_date: '2026-09-26', amount: 100, method: 'transfer', bank_account_id: bank.id, reference: invV.number, status: 'recorded' } as any))
  const i3 = (await sql(`select status, amount_paid::float, amount_due::float from invoices where id=$1`, [invoice.id]))[0]
  check('S06c', 'un trop-perçu sur une facture soldée est refusé (ou tracé en avance client, pas en payé > total)', !pay3.ok || i3.amount_paid <= r2(ht + tva), pay3.err ?? i3)
  const g = await ledger(A)
  const s411 = g.filter((x: any) => x.code.startsWith('411')).reduce((s: number, x: any) => s + x.d - x.c, 0)
  const s512 = g.filter((x: any) => x.code.startsWith('512')).reduce((s: number, x: any) => s + x.d - x.c, 0)
  check('S06d', `grand livre : 411 soldé (0), 512 = +${r2(ht + tva)} d'encaissements`, r2(s411) === 0 && r2(s512) >= r2(ht + tva), { s411: r2(s411), s512: r2(s512), ledger: g })
  const bankAfter = (await sql(`select balance::float from bank_accounts where id=$1`, [bank.id]))[0]
  check('S06e', 'le solde affiché du compte bancaire suit les encaissements', bankAfter.balance === r2(1000 + ht + tva) || bankAfter.balance === r2(s512), { balance: bankAfter.balance, s512: r2(s512) })

  // S07 devis -> facture
  const q = await attempt(() => sales.createQuote({ customer_id: cust.id, customer_name: cust.name, date: '2026-09-11', expiry_date: '2026-10-11', status: 'draft', subtotal: 200, vat_total: 40, total: 240, notes: '',
    lines: [{ product_id: null, description: 'Audit', quantity: 2, unit_price: 100, vat_rate: 20, total: 200, vat_total: 40 }] } as any))
  check('S07', 'créer un devis', q.ok, q.err ?? (q.val as any)?.number)
  const conv = q.ok ? await attempt(() => sales.convertQuoteToInvoice((q.val as any).id)) : { ok: false, err: 'pas de devis' }
  const inv2 = q.ok ? (await sql(`select id, number, status, validation_status, total::float, quote_id from invoices where quote_id=$1`, [(q.val as any).id]))[0] : null
  check('S07b', 'transformer le devis en facture (240 TTC, liée au devis)', conv.ok && !!inv2 && inv2.total === 240, conv.err ?? inv2)

  // S08 avoir sur la facture 2 (validée d'abord)
  if (inv2) {
    if (inv2.validation_status !== 'validated') await attempt(() => sales.updateInvoice(inv2.id, { validation_status: 'validated' } as any))
    const cn = await attempt(() => misc.transformInvoiceToCreditNote(inv2.id, 'Erreur de facturation'))
    // L'avoir naît brouillon ; l'écran des avoirs le valide (CreditNotesPage → updateCreditNote).
    const draft = (await sql(`select id from credit_notes where invoice_id=$1`, [inv2.id]))[0]
    const cnValid = draft ? await attempt(() => sales.updateCreditNote(draft.id, { status: 'validated' } as any)) : { ok: false, err: 'aucun avoir' }
    const cnRow = (await sql(`select id, number, status, total::float, subtotal::float from credit_notes where invoice_id=$1`, [inv2.id]))[0]
    const inv2After = (await sql(`select status, amount_due::float from invoices where id=$1`, [inv2.id]))[0]
    check('S08', 'avoir total sur facture validée : AV-2026-xxxxxx, 240, facture soldée', cn.ok && cnValid.ok && !!cnRow && /^AV-2026-/.test(cnRow.number) && cnRow.total === 240 && inv2After.amount_due === 0, { err: cn.err ?? cnValid.err, cnRow, inv2After })
    // l'écriture de l'avoir est celle que la base lui rattache (credit_notes.transferred_entry_id)
    const cnEntry = cnRow ? await sql(`select l.account_code, l.debit::float, l.credit::float from journal_lines l join journal_entries e on e.id=l.journal_id
      join credit_notes cn on cn.transferred_entry_id=e.id where cn.id=$1 and e.status='posted'`, [cnRow.id]) : []
    check('S08b', 'l\'avoir contrepasse : C411 240 / D70 200 / D4457 40', cnEntry.length >= 3 && r2(cnEntry.filter((l: any) => l.account_code.startsWith('411')).reduce((s: number, l: any) => s + l.credit, 0)) === 240, cnEntry)
  }

  // S09 facture hors exercice
  const out = await attempt(() => sales.createInvoice({ customer_id: cust.id, customer_name: cust.name, date: '2025-06-10', due_date: '2025-07-10', status: 'draft', subtotal: 100, vat_total: 20, total: 120, amount_paid: 0, amount_due: 120, notes: '', recurring: false, recurring_frequency: null,
    lines: [{ product_id: null, description: 'x', quantity: 1, unit_price: 100, vat_rate: 20, total: 100, vat_total: 20, vat_amount: 20, line_order: 0, advance_invoice_id: null }] } as any))
  const outV = out.ok ? await attempt(() => sales.updateInvoice((out.val as any).id, { validation_status: 'validated' } as any)) : out
  check('S09', 'valider une facture datée hors de tout exercice est refusé, avec un message clair', !outV.ok, outV.err ?? 'ACCEPTÉE')

  // S10 totaux falsifiés par le client : en-tête recalculé depuis les lignes
  const fake = await attempt(() => sales.createInvoice({ customer_id: cust.id, customer_name: cust.name, date: '2026-09-12', due_date: '2026-09-12', status: 'draft', subtotal: 1, vat_total: 0, total: 1, amount_paid: 0, amount_due: 1, notes: '', recurring: false, recurring_frequency: null,
    lines: [{ product_id: null, description: 'x', quantity: 3, unit_price: 33.33, vat_rate: 20, total: 99.99, vat_total: 20, vat_amount: 20, line_order: 0, advance_invoice_id: null }] } as any))
  const fk = fake.ok ? (await sql(`select subtotal::float, vat_total::float, total::float from invoices where id=$1`, [(fake.val as any).id]))[0] : null
  check('S10', 'en-tête falsifié (1 €) : recalculé depuis la ligne 3 × 33,33 → 99,99 / 20,00 / 119,99', !!fk && fk.subtotal === 99.99 && fk.vat_total === 20 && fk.total === 119.99, fake.err ?? fk)

  // S11 lecture par l'écran
  const list = await attempt(() => sales.getInvoices())
  check('S11', 'getInvoices (liste de l\'écran) rend les factures créées', list.ok && (list.val as any[]).length >= 3, list.err ?? (list.val as any[]).length)
  save('s1.json', findings)
})
