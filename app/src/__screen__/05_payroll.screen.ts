import { it } from 'vitest'
import { login, A, sql, check, attempt, save, findings } from './rig'
const r2 = (n: number) => Math.round(n * 100) / 100

it('Paie — salarié, lot, bulletins, journal, virement', async () => {
  await login(0, A)
  const pay = await import('@/lib/queries/payroll')
  const misc = await import('@/lib/queries/misc')
  const stamp = Date.now() % 100000
  // C6 (276) : Paramètres → Législation → « Paramètres de paie de la société » (AT/MP notifié 1,00 %,
  // moins de 50 salariés, à compter de septembre 2026) — le jeu des bulletins d'or de la 276
  const par = await attempt(() => pay.saveCompanyPayrollParameters(false, 1, '2026-09'))
  check('H00', 'paramètres de paie de la société enregistrés par l\'écran (AT/MP, effectif)', par.ok, par.err ?? 'OK')
  const emps: any[] = []
  for (const [i, salary] of [2500, 4000].entries()) {
    const e = await attempt(() => pay.createEmployee({ name: `Salarié ${i + 1} ${stamp}`, email: `s${i}${stamp}@audit.test`, phone: '', position: 'Agent', department: 'Ops', salary, hire_date: '2026-01-01', status: 'active',
      employee_number: `M${stamp}${i}`, social_security_number: null, birth_date: '1990-01-01', gender: null, address: null, city: null, postal_code: null, contract_type: 'cdi', contract_end_date: null } as any))
    check(`H0${i + 1}`, `créer le salarié ${i + 1} (brut ${salary})`, e.ok, e.err ?? (e.val as any).id)
    if (e.ok) emps.push(e.val)
  }
  // C5/C7 (275) : PayRunsPage crée un lot VIDE ; ses totaux viennent de ses bulletins
  const run = await attempt(() => pay.createPayRun({ number: `PAY-2026-09-${stamp}`, period_start: '2026-09-01', period_end: '2026-09-30', pay_date: '2026-09-30', status: 'draft' }))
  check('H03', 'créer le lot de paie de septembre (PayRunsPage, lot vide)', run.ok, run.err ?? (run.val as any).id)
  const pr: any = run.val
  const gen = await attempt(() => pay.generatePayRunSlips(pr.id))
  const slips = await sql(`select e.salary::float sal, s.gross_salary::float gross, s.net_salary::float net, s.employer_contributions::float emp, s.status from pay_slips s join employees e on e.id=s.employee_id where s.pay_run_id=$1 order by e.salary`, [pr.id]).catch(async () => sql(`select * from pay_slips where pay_run_id=$1`, [pr.id]))
  check('H04', 'générer les bulletins (moteur SQL calculate_payslip)', gen.ok && slips.length === 2, { err: gen.err, bulletins: slips })
  const sumNet = r2(slips.reduce((s: number, x: any) => s + Number(x.net ?? x.net_salary ?? 0), 0))
  const runRow = (await sql(`select gross_total::float, net_total::float, tax_total::float, employee_count from pay_runs where id=$1`, [pr.id]))[0]
  check('H05', 'le lot affiche le même net que la somme de ses bulletins', r2(runRow.net_total) === sumNet && runRow.employee_count === 2, { lot: runRow, somme_bulletins: sumNet })
  // Contrôles de vraisemblance France 2026 : brut 2 500 → net entre 1 900 et 2 000 environ
  const s1 = slips[0]
  // Bulletin d'or T02 de la 276 (calcul indépendant) : net payé 1 919,53, patronal après RGDU 554,90
  check('H06', 'bulletin 2 500 € brut non cadre = bulletin d\'or (net 1 919,53, patronal 554,90)', s1 && s1.net === 1919.53 && s1.emp === 554.9, s1)
  // Approbation (PayRunsPage : sélecteur de statut → updatePayRun), puis journal de paie
  const appr = await attempt(() => pay.updatePayRun(pr.id, { status: 'approved' }))
  check('H07a', 'approuver le lot (PayRunsPage, statut « approuvé »)', appr.ok, appr.err ?? (appr.val as any).status)
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
  const vs = await attempt(() => pay.generatePayRunSlips(pr.id))
  check('H10', 'un lecteur ne peut pas (re)calculer les bulletins', !vs.ok, vs.err ?? 'ACCEPTÉ')
  await login(0, A)
  // C3 / rh-008 (340) : TimesheetsPage n'envoie que des HEURES. 12 h pour 7 h prévues = 5 h sup,
  // calculées par la base ; l'approbation pose l'élément de paie et signe l'approbateur.
  if (emps[0]) {
    type Feuille = { id: string; overtime_minutes: number | null }
    const ts = await attempt(() => pay.createTimesheet({ employee_id: emps[0].id, date: '2026-11-10', hours: 12, description: 'Inventaire', project_id: null, status: 'pending' }))
    const feuille = ts.val as Feuille | undefined
    check('H11', 'feuille de temps de 12 h saisie par l\'écran : 300 minutes d\'heures sup calculées par la base', ts.ok && Number(feuille?.overtime_minutes) === 300, ts.err ?? feuille?.overtime_minutes)
    if (ts.ok && feuille) {
      const ap = await attempt(() => pay.updateTimesheet(feuille.id, { status: 'approved' }))
      const el = await sql(`select quantity::float q, amount::float a from payroll_variable_elements where source_id=$1 and element_type='overtime'`, [feuille.id])
      const sig = (await sql(`select approved_by, approved_at from timesheets where id=$1`, [feuille.id]))[0]
      check('H12', 'approuver la feuille pose UN élément « heures sup » (5 h, montant non nul) et signe l\'approbation', ap.ok && el.length === 1 && el[0].q === 5 && el[0].a > 0 && !!sig?.approved_by && !!sig?.approved_at, { err: ap.err, elements: el, signature: sig })
    }
  }
  // C4 / rh-009 : TimesheetsPage pointe une ABSENCE (absence_type) — quatrième source du registre (263).
  if (emps[0]) {
    const abs = await attempt(() => pay.createTimesheet({ employee_id: emps[0].id, date: '2026-11-12', hours: 0, description: '', project_id: null, status: 'pending', absence_type: 'mission', absence_reason: 'déplacement client' }))
    const reg = await sql(`select absence_kind, origin from employee_absence_days where employee_id=$1 and day='2026-11-12'`, [emps[0].id])
    check('H13', 'pointer une absence par l\'écran inscrit UN jour au registre des absences (mission, origine pointage)', abs.ok && reg.length === 1 && reg[0].absence_kind === 'mission' && reg[0].origin === 'timesheet', { err: abs.err, registre: reg })
  }
  save('s5.json', findings)
})
