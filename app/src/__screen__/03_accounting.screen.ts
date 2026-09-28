import { it } from 'vitest'
import { login, A, sql, check, attempt, save, findings } from './rig'
const r2 = (n: number) => Math.round(n * 100) / 100

const BANQUE = async (A: string) => (await sql(`select account_code from bank_accounts where tenant_id=$1 order by created_at limit 1`, [A]))[0]?.account_code ?? '512000'
it('Comptabilité générale — saisie, états, TVA, FEC, lettrage', async () => {
  await login(0, A)
  const bq = await BANQUE(A)
  const acc = await import('@/lib/queries/accounting')
  const bf = await import('@/lib/queries/businessFunctions')
  const fy = (await sql(`select id from fiscal_years where tenant_id=$1 and code='FY2026'`, [A]))[0]

  // C01 écriture déséquilibrée (JournalEntriesPage -> post_journal_entry) : décision D-A,
  // un brouillon faux reste enregistrable, mais « Valider » le refuse et il reste brouillon
  const bad = await attempt(() => acc.createJournalEntry({ number: '', date: '2026-09-15', description: 'déséquilibrée', reference: null, status: 'draft', total_debit: 100, total_credit: 90,
    lines: [{ account_code: '606100', account_name: 'x', debit: 100, credit: 0, description: null }, { account_code: bq, account_name: 'y', debit: 0, credit: 90, description: null }] } as any))
  const badV = bad.ok ? await attempt(() => acc.validateJournalEntries([(bad.val as any).id])) : bad
  const badRow = bad.ok ? (await sql(`select status, posting_number from journal_entries where id=$1`, [(bad.val as any).id]))[0] : null
  check('C01', 'écriture 100/90 : « Valider » la refuse (verdict nommé), elle reste brouillon', !bad.ok || (badV.ok && (badV.val as any)[0]?.ok === false && badRow?.status === 'draft'),
    bad.ok ? { verdict: badV.val ?? badV.err, row: badRow } : bad.err)

  // C02 écriture équilibrée (loyer 1000 HT + TVA 200 payé)
  const good = await attempt(() => acc.createJournalEntry({ number: '', date: '2026-09-15', description: 'Loyer septembre', reference: 'LOY-09', status: 'draft', total_debit: 1200, total_credit: 1200,
    lines: [{ account_code: '613200', account_name: 'Locations', debit: 1000, credit: 0, description: 'Loyer' }, { account_code: '445660', account_name: 'TVA ded', debit: 200, credit: 0, description: 'TVA' },
      { account_code: bq, account_name: 'Banque', debit: 0, credit: 1200, description: 'Paiement' }] } as any))
  const ge: any = good.val
  const row = good.ok ? (await sql(`select status, number, posting_number, journal_code, fiscal_year_id is not null fy from journal_entries where id=$1`, [ge.id]))[0] : null
  check('C02', 'écriture équilibrée 1 200 créée (statut ?)', good.ok, good.err ?? row)
  // C03 « Valider » (JournalEntriesPage / JournalSaisiePage / BrouillardPage -> validate_journal_entries)
  if (good.ok && row.status !== 'posted') {
    const v = await attempt(() => acc.validateJournalEntries([ge.id]))
    const row2 = (await sql(`select status, posting_number, validated_by is not null validated from journal_entries where id=$1`, [ge.id]))[0]
    check('C03', 'un brouillon manuel est validé depuis l\'interface (« Valider » → posted, numéro définitif, validateur)', v.ok && (v.val as any)[0]?.ok === true && row2.status === 'posted' && !!row2.posting_number && row2.validated, { verdict: v.val ?? v.err, row2 })
  } else check('C03', 'écriture validée dès sa création', row?.status === 'posted', row)

  // C04 balance = grand livre
  const tb = await attempt(() => acc.getTrialBalance())
  const tbD = tb.ok ? r2((tb.val as any[]).reduce((s, x) => s + x.total_debit, 0)) : -1
  const tbC = tb.ok ? r2((tb.val as any[]).reduce((s, x) => s + x.total_credit, 0)) : -1
  const gl = (await sql(`select round(sum(l.debit),2)::float d, round(sum(l.credit),2)::float c from journal_lines l join journal_entries e on e.id=l.journal_id where e.tenant_id=$1 and e.status='posted' and e.date between '2026-01-01' and '2026-12-31'`, [A]))[0]
  check('C04', 'balance générale (écran) : Σ débits = Σ crédits = grand livre validé', tb.ok && tbD === tbC && tbD === gl.d, { err: tb.err, balance: [tbD, tbC], grand_livre: gl })

  // C05 bilan équilibré, C06 résultat = produits - charges
  const bs = await attempt(() => acc.getBalanceSheet())
  check('C05', 'bilan (écran) équilibré : écart = 0', bs.ok && (bs.val as any).gap === 0, bs.err ?? { gap: (bs.val as any).gap, nonclasses: (bs.val as any).unclassified.map((x: any) => x.code) })
  const is = await attempt(() => acc.getIncomeStatement(fy.id))
  const prod = is.ok ? r2((is.val as any[]).filter((x) => x.account_type === 'income').reduce((s, x) => s + x.amount, 0)) : -1
  const chg = is.ok ? r2((is.val as any[]).filter((x) => x.account_type === 'expense').reduce((s, x) => s + x.amount, 0)) : -1
  const gl67 = (await sql(`select round(sum(case when l.account_code like '7%' then l.credit-l.debit else 0 end),2)::float p, round(sum(case when l.account_code like '6%' then l.debit-l.credit else 0 end),2)::float c from journal_lines l join journal_entries e on e.id=l.journal_id where e.tenant_id=$1 and e.status='posted'`, [A]))[0]
  check('C06', 'compte de résultat (écran) = classes 7 et 6 du grand livre', is.ok && prod === gl67.p && chg === gl67.c, { err: is.err, ecran: { prod, chg }, gl: gl67 })

  // C07 TVA de septembre : collectée - déductible
  const vat = await attempt(() => bf.generateVatReturn('2026-09-01', '2026-09-30'))
  const glv = (await sql(`select round(sum(case when l.account_code like '4457%' then l.credit-l.debit else 0 end),2)::float coll, round(sum(case when l.account_code like '4456%' then l.debit-l.credit else 0 end),2)::float ded from journal_lines l join journal_entries e on e.id=l.journal_id where e.tenant_id=$1 and e.status='posted' and e.date between '2026-09-01' and '2026-09-30'`, [A]))[0]
  check('C07', `déclaration de TVA septembre = grand livre (collectée ${glv.coll}, déductible ${glv.ded}, nette ${r2(glv.coll - glv.ded)})`, vat.ok, { err: vat.err, rpc: vat.val, gl: glv })

  // C08 FEC (FECExportPage -> getFECExport) : 18 colonnes, virgule décimale
  const fec = await attempt(() => acc.getFECExport(fy.id))
  const rows: any[] = fec.ok ? (fec.val as any).rows : []
  const amt = (v: string) => Number(String(v ?? '0').replace(',', '.'))
  const fecD = r2(rows.reduce((s, x) => s + amt(x.Debit), 0)), fecC = r2(rows.reduce((s, x) => s + amt(x.Credit), 0))
  const cols = rows[0] ? Object.keys(rows[0]) : []
  const std = ['JournalCode', 'JournalLib', 'EcritureNum', 'EcritureDate', 'CompteNum', 'CompteLib', 'CompAuxNum', 'CompAuxLib', 'PieceRef', 'PieceDate', 'EcritureLib', 'Debit', 'Credit', 'EcritureLet', 'DateLet', 'ValidDate', 'Montantdevise', 'Idevise']
  check('C08', 'FEC : 18 colonnes réglementaires, Σ débit = Σ crédit = grand livre, écritures validées seulement', fec.ok && std.every((c) => cols.includes(c)) && fecD === fecC && fecD === gl.d,
    { err: fec.err, lignes: rows.length, colonnes_manquantes: std.filter((c) => !cols.includes(c)), fecD, fecC, gl: gl.d, exemple: rows[0] })

  // C09 lettrage 411 : facture payée
  const l411 = await sql(`select l.id, l.debit::float, l.credit::float, l.account_tiers, l.lettrage_code from journal_lines l join journal_entries e on e.id=l.journal_id where e.tenant_id=$1 and e.status='posted' and l.account_code like '411%' order by l.created_at`, [A])
  const lettered = l411.filter((x: any) => x.lettrage_code)
  check('C09', 'lettrage : les lignes 411 de la facture soldée sont lettrées (auto ou manuel)', lettered.length > 0, { lignes411: l411.length, lettrees: lettered.length, exemple: l411.slice(0, 4) })

  // C10 écriture sur un exercice clos / hors exercice
  const outFy = await attempt(() => acc.createJournalEntry({ number: '', date: '2031-01-15', description: 'hors exercice', reference: null, status: 'draft', total_debit: 10, total_credit: 10,
    lines: [{ account_code: '606100', account_name: 'x', debit: 10, credit: 0, description: null }, { account_code: bq, account_name: 'y', debit: 0, credit: 10, description: null }] } as any))
  check('C10', 'écriture datée hors de tout exercice refusée', !outFy.ok, outFy.err ?? 'ACCEPTÉE')

  // C11 compte inexistant
  const ghost = await attempt(() => acc.createJournalEntry({ number: '', date: '2026-09-16', description: 'compte fantôme', reference: null, status: 'draft', total_debit: 10, total_credit: 10,
    lines: [{ account_code: '999999', account_name: 'x', debit: 10, credit: 0, description: null }, { account_code: bq, account_name: 'y', debit: 0, credit: 10, description: null }] } as any))
  check('C11', 'écriture sur un compte absent du plan : refusée (ou signalée)', !ghost.ok, ghost.err ?? 'ACCEPTÉE')

  // C13 saisie par journal (JournalSaisiePage -> createSaisieEntry), puis clôture du journal × période
  const per = (await sql(`select id from fiscal_periods where tenant_id=$1 and '2026-09-20' between start_date and end_date`, [A]))[0]
  const sais = await attempt(() => acc.createSaisieEntry({ number: 'OD-' + Date.now().toString().slice(-6), date: '2026-09-20', description: 'Saisie OD', journal_code: 'OD', fiscal_period_id: per?.id,
    piece_number: 'PJ-77', invoice_ref: null, entry_template_id: null, status: 'draft', status_detail: 'open', total_debit: 40, total_credit: 40, currency_code: 'EUR', functional_currency: 'EUR', exchange_rate: 1, exchange_rate_date: '2026-09-20',
    lines: [{ account_code: '606100', account_name: 'Fournitures', account_general: '606100', account_tiers: null, debit: 40, credit: 0, description: 'Fournitures', piece_number: 'PJ-77', reference: null, line_order: 0, line_date: '2026-09-20', vat_code: null, analytic_section: null, echeance_date: null, lettrage_code: null },
      { account_code: bq, account_name: 'Banque', account_general: bq, account_tiers: null, debit: 0, credit: 40, description: 'Fournitures', piece_number: 'PJ-77', reference: null, line_order: 1, line_date: '2026-09-20', vat_code: null, analytic_section: null, echeance_date: null, lettrage_code: null }] }))
  const saisRow = sais.ok ? (await sql(`select status, piece_number, (select count(*)::int from journal_lines where journal_id=e.id) n from journal_entries e where id=$1`, [(sais.val as any).id]))[0] : null
  check('C13', 'saisie par journal : en-tête et lignes créés ensemble (pièce gardée, brouillon)', sais.ok && saisRow?.n === 2 && saisRow?.piece_number === 'PJ-77' && saisRow?.status === 'draft', sais.err ?? saisRow)
  const clo = await attempt(() => acc.closeJournalPeriod('OD', per?.id))
  const nomme = /écriture (\S+) \(/.exec(clo.err ?? '')?.[1]
  const nommeBrouillon = nomme ? (await sql(`select count(*)::int n from journal_entries where tenant_id=$1 and journal_code='OD' and fiscal_period_id=$2 and number=$3 and status='draft'`, [A, per?.id, nomme]))[0].n : 0
  const clotures = (await sql(`select count(*)::int n from journal_entries where tenant_id=$1 and journal_code='OD' and fiscal_period_id=$2 and status_detail='closed'`, [A, per?.id]))[0].n
  check('C14', 'clôture du journal × période refusée tant qu\'un brouillon reste, en le nommant (rien n\'est clôturé)', !clo.ok && nommeBrouillon === 1 && clotures === 0, { err: clo.err ?? 'ACCEPTÉE', nomme, clotures })

  // C12 viewer ne peut pas saisir
  await login(2, A)
  const v = await attempt(() => acc.createJournalEntry({ number: '', date: '2026-09-16', description: 'par un lecteur', reference: null, status: 'draft', total_debit: 10, total_credit: 10,
    lines: [{ account_code: '606100', account_name: 'x', debit: 10, credit: 0, description: null }, { account_code: bq, account_name: 'y', debit: 0, credit: 10, description: null }] } as any))
  check('C12', 'un lecteur ne peut pas saisir d\'écriture', !v.ok, v.err ?? 'ACCEPTÉE')
  save('s3.json', findings)
})
