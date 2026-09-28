import { it } from 'vitest'
import { login, A, sql, check, attempt, save, findings } from './rig'
it('Tableaux de bord : les chiffres affichés = la comptabilité', async () => {
  await login(0, A)
  const acc = await import('@/lib/queries/accounting')
  const ds = await attempt(() => acc.getDashboardStats())
  const fd = await attempt(() => acc.getFinancialDashboard())
  const td = await attempt(() => acc.getTreasuryDashboard())
  const gl = (await sql(`select
     round(sum(case when l.account_code like '70%' then l.credit-l.debit else 0 end),2)::float ca,
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
  // M5 (278) : chaque indicateur affiché = le grand livre (écritures validées de l'exercice 2026)
  const eq = (x: number, y: number) => Math.round(x * 100) === Math.round(y * 100)
  const d: any = ds.val, f: any = fd.val, tr: any = td.val
  check('D04', 'accueil : CA = 70x, encours clients = 411, fournisseurs = 401, trésorerie = 5x', ds.ok && eq(d.totalRevenue, gl.ca) && eq(d.totalDebtors, gl.clients) && eq(d.outstandingInvoice, gl.clients) && eq(d.totalCreditors, gl.fournisseurs) && eq(d.bankBalance, gl.treso),
    { ecran: d, gl })
  check('D05', 'financier : CA = 70x, charges = 6x, trésorerie = 5x', fd.ok && eq(f.revenue, gl.ca) && eq(f.expenses, gl.charges) && eq(f.cashPosition, gl.treso), { ecran: f, gl })
  check('D06', 'trésorerie : solde = 5x du grand livre', td.ok && eq(tr.totalBalance, gl.treso), { ecran: tr?.totalBalance, gl: gl.treso })
  const drafts = (await sql(`select count(*)::int n from invoices where tenant_id=$1 and validation_status='validated' and status='draft'`, [A]))[0].n
  check('D07', 'aucune facture validée ne reste au statut brouillon', drafts === 0, { validees_en_brouillon: drafts })
  save('s9.json', findings)
})
