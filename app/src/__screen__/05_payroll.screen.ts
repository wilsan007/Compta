import { it } from 'vitest'
import { login, A, sql, check, attempt, save, findings } from './rig'
const r2 = (n: number) => Math.round(n * 100) / 100

// Reproduction exacte du calcul de PayRunsPage (lignes 158-190)
function pageTotals(employees: { salary: number }[]) {
  const grossTotal = employees.reduce((s, e) => s + Number(e.salary), 0)
  const cnssTotal = employees.reduce((s, e) => s + Math.min(e.salary, 6000) * 0.0448, 0)
  const amoTotal = grossTotal * 0.0226
  const irTotal = employees.reduce((s, e) => {
    const sal = e.salary; const ni = sal - Math.min(sal, 6000) * 0.0448 - sal * 0.0226
    let ir = 0
    if (ni <= 2500) ir = 0; else if (ni <= 4166) ir = (ni - 2500) * 0.10; else if (ni <= 5000) ir = 166.6 + (ni - 4166) * 0.20
    else if (ni <= 6666) ir = 333.4 + (ni - 5000) * 0.30; else if (ni <= 15000) ir = 833.2 + (ni - 6666) * 0.34; else ir = 3683.0 + (ni - 15000) * 0.38
    return s + Math.max(0, ir)
  }, 0)
  const ded = cnssTotal + amoTotal + irTotal
  return { gross: grossTotal, ded, net: grossTotal - ded }
}

it('Paie — salarié, lot, bulletins, journal, virement', async () => {
  await login(0, A)
  const pay = await import('@/lib/queries/payroll')
  const misc = await import('@/lib/queries/misc')
  const stamp = Date.now() % 100000
  const emps: any[] = []
  for (const [i, salary] of [2500, 4000].entries()) {
    const e = await attempt(() => pay.createEmployee({ name: `Salarié ${i + 1} ${stamp}`, email: `s${i}${stamp}@audit.test`, phone: '', position: 'Agent', department: 'Ops', salary, hire_date: '2026-01-01', status: 'active',
      employee_number: `M${stamp}${i}`, social_security_number: null, birth_date: '1990-01-01', gender: null, address: null, city: null, postal_code: null, contract_type: 'cdi', contract_end_date: null } as any))
    check(`H0${i + 1}`, `créer le salarié ${i + 1} (brut ${salary})`, e.ok, e.err ?? (e.val as any).id)
    if (e.ok) emps.push(e.val)
  }
  const tot = pageTotals(emps.map((e) => ({ salary: Number(e.salary) })))
  const run = await attempt(() => pay.createPayRun({ number: `PAY-2026-09-${stamp}`, period_start: '2026-09-01', period_end: '2026-09-30', pay_date: '2026-09-30', status: 'draft',
    gross_total: tot.gross, tax_total: tot.ded, net_total: tot.net, employee_count: emps.length } as any))
  check('H03', 'créer le lot de paie de septembre (PayRunsPage)', run.ok, run.err ?? { brut: tot.gross, retenues_page: r2(tot.ded), net_page: r2(tot.net) })
  const pr: any = run.val
  const gen = await attempt(() => pay.generatePaySlipsForRun(pr.id, emps, pr))
  const slips = await sql(`select e.salary::float sal, s.gross_salary::float gross, s.net_salary::float net, s.employer_contributions::float emp, s.status from pay_slips s join employees e on e.id=s.employee_id where s.pay_run_id=$1 order by e.salary`, [pr.id]).catch(async () => sql(`select * from pay_slips where pay_run_id=$1`, [pr.id]))
  check('H04', 'générer les bulletins (moteur SQL calculate_payslip)', gen.ok && slips.length === 2, { err: gen.err, bulletins: slips })
  const sumNet = r2(slips.reduce((s: number, x: any) => s + Number(x.net ?? x.net_salary ?? 0), 0))
  const runRow = (await sql(`select gross_total::float, net_total::float, tax_total::float from pay_runs where id=$1`, [pr.id]))[0]
  check('H05', 'le lot affiche le même net que la somme de ses bulletins', r2(runRow.net_total) === sumNet, { lot: runRow, somme_bulletins: sumNet })
  // Contrôles de vraisemblance France 2026 : brut 2 500 → net entre 1 900 et 2 000 environ
  const s1 = slips[0]
  check('H06', 'bulletin 2 500 € brut : net cohérent avec la paie française (≈ 1 950 €)', s1 && s1.net > 1850 && s1.net < 2050, s1)
  // Journal de paie
  const j = await attempt(() => misc.generatePayrollJournal(pr.id))
  const pj = await sql(`select l.account_code, sum(l.debit)::float d, sum(l.credit)::float c from journal_lines l join journal_entries e on e.id=l.journal_id where e.tenant_id=$1 and e.status='posted' and e.id=$2 group by 1 order by 1`, [A, (j.val as any)?.entry_id])
  const d641 = pj.filter((x: any) => x.account_code.startsWith('641')).reduce((s: number, x: any) => s + x.d, 0)
  const c421 = pj.filter((x: any) => x.account_code.startsWith('421')).reduce((s: number, x: any) => s + x.c, 0)
  const bal = r2(pj.reduce((s: number, x: any) => s + x.d - x.c, 0))
  const grossSum = r2(slips.reduce((s: number, x: any) => s + Number(x.gross ?? 0), 0))
  check('H07', `journal de paie : D641 = brut (${grossSum}), C421 = nets (${sumNet}), équilibré`, j.ok && r2(d641) === grossSum && r2(c421) === sumNet && bal === 0, { err: j.err, ecriture: pj })
  const j2 = await attempt(() => misc.generatePayrollJournal(pr.id))
  const nEntries = (await sql(`select count(*)::int n from journal_entries where tenant_id=$1 and journal_code in ('PA','OD','SAL') and description ilike $2`, [A, `%${pr.number}%`]))[0].n
  check('H08', 'rejouer la génération du journal ne double pas l\'écriture', j2.ok && ((j2.val as any)?.already_posted === true), { rep: j2.val ?? j2.err, n: nEntries })
  // lecteur : ne peut pas créer de salarié ni lancer la paie
  await login(2, A)
  const ve = await attempt(() => pay.createEmployee({ name: 'Intrus', email: 'i@audit.test', salary: 99999, hire_date: '2026-01-01', status: 'active', contract_type: 'cdi' } as any))
  check('H09', 'un lecteur ne peut pas créer de salarié', !ve.ok, ve.err ?? 'ACCEPTÉ')
  const vs = await attempt(() => pay.generatePaySlipsForRun(pr.id, emps, pr))
  check('H10', 'un lecteur ne peut pas (re)calculer les bulletins', !vs.ok, vs.err ?? 'ACCEPTÉ')
  await login(0, A)
  save('s5.json', findings)
})
