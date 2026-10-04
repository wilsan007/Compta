import { it } from 'vitest'
import { login, A, sql, check, attempt, save, findings } from './rig'
it('Devis -> facture -> avoir', async () => {
  await login(0, A)
  const sales = await import('@/lib/queries/sales')
  const misc = await import('@/lib/queries/misc')
  const cust = (await sql(`select id, name from customers where tenant_id=$1 and email is not null limit 1`, [A]))[0]
  const q = await attempt(() => sales.createQuote({ date: '2026-09-11', expiry_date: '2026-10-11', customer_id: cust.id, customer_name: cust.name, status: 'draft', subtotal: 200, vat_total: 40, total: 240, notes: '',
    lines: [{ product_id: null, description: 'Audit', quantity: 2, unit_price: 100, vat_rate: 20, total: 200, vat_total: 40 }] } as any))
  check('S07', 'créer un devis (QuotesPage)', q.ok, q.err ?? (q.val as any).number)
  const conv = q.ok ? await attempt(() => sales.convertQuoteToInvoice((q.val as any).id)) : q
  const inv2 = q.ok ? (await sql(`select id, number, validation_status, total::float from invoices where quote_id=$1`, [(q.val as any).id]))[0] : null
  check('S07b', 'devis transformé en facture de 240 TTC liée au devis', conv.ok && inv2?.total === 240, { err: conv.err, inv2 })
  if (inv2) {
    if (inv2.validation_status !== 'validated') await attempt(() => sales.updateInvoice(inv2.id, { validation_status: 'validated' } as any))
    const cn = await attempt(() => misc.transformInvoiceToCreditNote(inv2.id, 'Erreur de facturation'))
    const cnRow = (await sql(`select id, number, status, total::float from credit_notes where invoice_id=$1`, [inv2.id]))[0]
    const after = (await sql(`select status, amount_due::float from invoices where id=$1`, [inv2.id]))[0]
    const lines = cnRow ? await sql(`select l.account_code, l.debit::float d, l.credit::float c from journal_lines l join journal_entries e on e.id=l.journal_id where e.tenant_id=$1 and e.status='posted' and (e.invoice_ref=$2 or e.reference=$2 or e.number like '%'||$2||'%')`, [A, cnRow.number]) : []
    check('S08', 'avoir total : numéroté, facture soldée, écriture de contrepassation 411/70/4457', cn.ok && !!cnRow && after.amount_due === 0 && lines.length >= 3, { err: cn.err, cnRow, after, lines })
  }
  save('s12.json', findings)
})
