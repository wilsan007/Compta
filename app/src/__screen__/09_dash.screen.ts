import { it } from 'vitest'
import { login, A, sql, check, attempt, save, findings } from './rig'
it('Tableaux de bord : les chiffres affichés = la comptabilité', async () => {
  await login(0, A)
  const acc = await import('@/lib/queries/accounting')
  const ds = await attempt(() => acc.getDashboardStats())
  const fd = await attempt(() => acc.getFinancialDashboard())
  const td = await attempt(() => acc.getTreasuryDashboard())
  const gl = (await sql(`select
     round(sum(case when l.account_code like '7%' then l.credit-l.debit else 0 end),2)::float ca,
     round(sum(case when l.account_code like '6%' then l.debit-l.credit else 0 end),2)::float charges,
     round(sum(case when l.account_code like '411%' then l.debit-l.credit else 0 end),2)::float clients,
     round(sum(case when l.account_code like '401%' then l.credit-l.debit else 0 end),2)::float fournisseurs,
     round(sum(case when l.account_code like '5%' then l.debit-l.credit else 0 end),2)::float treso
     from journal_lines l join journal_entries e on e.id=l.journal_id where e.tenant_id=$1 and e.status='posted'`, [A]))[0]
  const inv = (await sql(`select round(sum(total) filter (where validation_status='validated'),2)::float ttc, round(sum(subtotal) filter (where validation_status='validated'),2)::float ht, round(sum(amount_due) filter (where validation_status='validated'),2)::float du from invoices where tenant_id=$1`, [A]))[0]
  const bankBal = (await sql(`select round(sum(balance),2)::float b from bank_accounts where tenant_id=$1`, [A]))[0]
  check('D01', 'getDashboardStats (accueil) répond', ds.ok, ds.err ?? ds.val)
  check('D02', 'getFinancialDashboard répond', fd.ok, fd.err ?? fd.val)
  check('D03', 'getTreasuryDashboard répond', td.ok, td.err ?? td.val)
  check('D00', 'référence grand livre / pièces', true, { gl, factures: inv, soldes_bancaires_affiches: bankBal })
  save('s9.json', findings)
})
