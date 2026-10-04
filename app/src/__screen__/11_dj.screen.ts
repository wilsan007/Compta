import { it } from 'vitest'
import { login, B, sql, check, attempt, save, findings } from './rig'
it('Société djiboutienne', async () => {
  await login(1, B)
  const partners = await import('@/lib/queries/partners')
  const sales = await import('@/lib/queries/sales')
  const c: any = (await attempt(() => partners.createCustomer({ name: 'Client DJ', email: 'dj@audit.test', phone: '', address: '', vat_number: '', is_company: true } as any))).val
  const inv = await attempt(() => sales.createInvoice({ customer_id: c.id, customer_name: c.name, date: '2026-09-10', due_date: '2026-10-10', status: 'draft', subtotal: 100000, vat_total: 10000, total: 110000, amount_paid: 0, amount_due: 110000, notes: '', recurring: false, recurring_frequency: null,
    lines: [{ product_id: null, description: 'Prestation', quantity: 1, unit_price: 100000, vat_rate: 10, total: 100000, vat_total: 10000, vat_amount: 10000, line_order: 0, advance_invoice_id: null }] } as any))
  const v = inv.ok ? await attempt(() => sales.updateInvoice((inv.val as any).id, { validation_status: 'validated' } as any)) : inv
  const row = inv.ok ? (await sql(`select number, currency_code, transferred_entry_id from invoices where id=$1`, [(inv.val as any).id]))[0] : null
  const lines = row?.transferred_entry_id ? await sql(`select account_code, debit::float, credit::float from journal_lines where journal_id=$1`, [row.transferred_entry_id]) : []
  check('DJ01', 'facture DJF 100 000 + TVA 10 % validée et comptabilisée (société DJ, plan provisoire)', v.ok && lines.length >= 3, { err: v.err, row, lines })
  save('s11.json', findings)
})
