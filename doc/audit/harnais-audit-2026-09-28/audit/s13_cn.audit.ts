import { it } from 'vitest'
import { login, A, sql, check, attempt, save, findings } from './rig'
it('Validation de l\'avoir (CreditNotesPage)', async () => {
  await login(0, A)
  const sales = await import('@/lib/queries/sales')
  const cn = (await sql(`select id from credit_notes where number='BROUILLON-AV-BF4D22CE06'`))[0]
  const v = await attempt(() => sales.updateCreditNote(cn.id, { status: 'validated' } as any))
  const row = (await sql(`select number, status, total::float from credit_notes where id=$1`, [cn.id]))[0]
  const inv = (await sql(`select status, amount_due::float from invoices where id='5c82b56c-1d24-4a8a-abbd-ec58344e5616'`))[0]
  const lines = await sql(`select l.account_code, l.debit::float d, l.credit::float c from journal_lines l join journal_entries e on e.id=l.journal_id where e.tenant_id=$1 and e.status='posted' and (e.invoice_ref=$2 or e.number like '%'||$2||'%')`, [A, row.number])
  check('S08', 'avoir validé : AV-2026-xxxxxx, facture soldée, contrepassation D70 200 / D4457 40 / C411 240', v.ok && /^AV-2026-/.test(row.number) && inv.amount_due === 0 && lines.length >= 3, { err: v.err, row, inv, lines })
  save('s13.json', findings)
})
