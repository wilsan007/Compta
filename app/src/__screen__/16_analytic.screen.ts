import { it } from 'vitest'
import { login, A, sql, check, attempt, save, findings, RIG_USERS } from './rig'

// Tâche 2.13 (G1, les restes — migration 353) : par les fonctions des écrans.
//   AN01–AN02  un brouillon de facture se modifie (InvoicesPage), une facture validée non
//   AN03       la section d'une ligne d'avoir atteint l'écriture (CreditNotesPage)
//   AN04       la grille de ventilation du compte s'applique seule, et la balance
//              analytique montre CHAQUE part (DistributionGrillsPage → AnalyticBalancePage)
//   AN05       un lecteur ne modifie pas un brouillon
it('Analytique : brouillon modifiable, avoir imputé, grille appliquée', async () => {
  await login(0, A)
  const sales = await import('@/lib/queries/sales')
  const acc = await import('@/lib/queries/accounting')
  type NewInvoice = Parameters<typeof sales.createInvoice>[0]
  type NewLine = NewInvoice['lines'][number]
  const cust = (await sql<{ id: string; name: string }>(`select id, name from customers where tenant_id=$1 order by created_at limit 1`, [A]))[0]
  const suffix = String(Date.now() % 100000)

  // Les sections et le plan se créent par l'écran des sections analytiques.
  const plan = await acc.createAnalyticPlan({ code: 'AX' + suffix, name: 'Axe 2.13', description: null, is_default: false, active: true })
  const section = (code: string) => acc.createAnalyticSection({ code: code + suffix, name: 'Section ' + code, parent_id: null, axis: null, level: 1, active: true, plan_id: plan.id, section_type: 'section' })
  const sBr = await section('BR')
  const s60 = await section('G6')
  const s40 = await section('G4')

  const line = (o: Partial<NewLine> & Pick<NewLine, 'description' | 'quantity' | 'unit_price'>): NewLine => {
    const total = Math.round(o.quantity * o.unit_price * 100) / 100
    return { product_id: null, vat_rate: 20, total, vat_total: total * 0.2, vat_amount: total * 0.2, line_order: 0, advance_invoice_id: null, account_code: null, analytic_section_id: null, ...o }
  }
  const invoice = (lines: NewLine[]): NewInvoice => {
    const ht = lines.reduce((s, l) => s + l.total, 0)
    return { customer_id: cust.id, customer_name: cust.name, date: '2026-09-20', due_date: '2026-10-20', status: 'draft', subtotal: ht, vat_total: ht * 0.2, total: ht * 1.2, amount_paid: 0, amount_due: ht * 1.2, notes: '', recurring: false, recurring_frequency: null, lines }
  }

  // ---------- AN01 : modifier un brouillon ----------
  const draft = await sales.createInvoice(invoice([line({ description: 'Ancienne ligne', quantity: 1, unit_price: 100 })]))
  const up = await attempt(() => sales.updateInvoiceDraft(draft.id, { customer_id: cust.id, customer_name: cust.name, date: '2026-09-20', due_date: '2026-11-04' }, [
    line({ description: 'Ligne A', quantity: 3, unit_price: 100, analytic_section_id: sBr.id }),
    line({ description: 'Ligne B', quantity: 1, unit_price: 50 }),
  ]))
  const after = (await sql<{ number: string; ht: number; due: string; n: number; sec: number }>(
    `select i.number, i.subtotal::float ht, i.due_date::text due, count(l.id)::int n, count(l.analytic_section_id)::int sec
       from invoices i left join invoice_lines l on l.invoice_id = i.id where i.id=$1 group by i.id`, [draft.id]))[0]
  check('AN01', 'un brouillon se modifie (InvoicesPage) : deux lignes, 350 HT, échéance et section portées, numéro conservé',
    up.ok && after.n === 2 && after.ht === 350 && after.due === '2026-11-04' && after.sec === 1 && after.number === draft.number, { err: up.err, after })

  // ---------- AN02 : une facture validée ne se modifie pas ----------
  await sales.updateInvoice(draft.id, { validation_status: 'validated' } as Parameters<typeof sales.updateInvoice>[1])
  const closed = await attempt(() => sales.updateInvoiceDraft(draft.id, {}, [line({ description: 'Pirate', quantity: 1, unit_price: 1 })]))
  const pirates = (await sql<{ n: number }>(`select count(*)::int n from invoice_lines where invoice_id=$1 and description='Pirate'`, [draft.id]))[0].n
  check('AN02', 'une facture validée ne se modifie pas : refus nommé, aucune ligne écrite',
    !closed.ok && /validée/.test(closed.err ?? '') && pirates === 0, { err: closed.err, pirates })

  // ---------- AN03 : la section d'une ligne d'avoir ----------
  type NewCreditNote = Parameters<typeof sales.createCreditNote>[0]
  const cn = await attempt(() => sales.createCreditNote({
    customer_id: cust.id, date: '2026-09-21', status: 'draft', subtotal: 80, vat_total: 16, total: 96, reason: 'Geste commercial', invoice_id: null,
    lines: [{ product_id: null, account_code: '706000', analytic_section_id: sBr.id, description: 'Geste commercial', quantity: 1, unit_price: 80, vat_rate: 20, total: 80, vat_total: 16, line_order: 0 }],
  } as NewCreditNote))
  const cnId = cn.val?.id ?? ''
  const val = cn.ok ? await attempt(() => sales.updateCreditNote(cnId, { status: 'validated' } as Parameters<typeof sales.updateCreditNote>[1])) : cn
  const cnLines = await sql<{ account_code: string; section: string | null }>(
    `select l.account_code, l.analytic_section_id section from credit_notes k join journal_lines l on l.journal_id = k.transferred_entry_id where k.id=$1 and l.account_code ~ '^7'`, [cnId])
  check('AN03', 'avoir (CreditNotesPage) : la section de la ligne se retrouve sur la ligne d\'écriture de produit',
    cn.ok && val.ok && cnLines.length === 1 && cnLines[0].section === sBr.id, { err: cn.err ?? val.err, lignes: cnLines })

  // ---------- AN04 : la grille du compte, et la balance analytique ----------
  const grill = await attempt(() => acc.createDistributionGrill({ name: 'Grille 2.13 ' + suffix, description: null, account_code: '706000', journal_code: null, active: true,
    lines: [{ section_code: s60.code, percentage: 60 }, { section_code: s40.code, percentage: 40 }] }))
  const g = await sales.createInvoice(invoice([line({ description: 'Prestation ventilée', quantity: 1, unit_price: 1000, account_code: '706000' })]))
  const gv = await attempt(() => sales.updateInvoice(g.id, { validation_status: 'validated' } as Parameters<typeof sales.updateInvoice>[1]))
  const bal = await attempt(() => acc.getAnalyticBalance('2026-01-01', '2026-12-31'))
  const parts = (bal.val ?? []).filter((r) => r.sectionId === s60.id || r.sectionId === s40.id).map((r) => [r.sectionCode, r.totalCredit, r.totalAnalytic])
  check('AN04', 'grille 60 / 40 sur 706000 : une facture sans section est ventilée, et la balance analytique montre 600 et 400',
    grill.ok && gv.ok && bal.ok && JSON.stringify(parts.sort()) === JSON.stringify([[s40.code, 400, 400], [s60.code, 600, 600]].sort()), { err: grill.err ?? gv.err ?? bal.err, parts })

  // ---------- AN05 : un lecteur ----------
  const d2 = await sales.createInvoice(invoice([line({ description: 'Brouillon protégé', quantity: 1, unit_price: 10 })]))
  const role = (await sql<{ role: string }>(`select role from tenant_users where auth_id=$1 and tenant_id=$2`, [RIG_USERS[2].id, A]))[0]?.role
  await login(2, A)
  const viewer = await attempt(() => sales.updateInvoiceDraft(d2.id, {}, [line({ description: 'Pirate', quantity: 1, unit_price: 1 })]))
  const kept = (await sql<{ d: string }>(`select string_agg(description, ',') d from invoice_lines where invoice_id=$1`, [d2.id]))[0].d
  check('AN05', 'un lecteur ne modifie pas un brouillon : la ligne d\'origine reste', role === 'viewer' && !viewer.ok && /pas le droit/.test(viewer.err ?? '') && kept === 'Brouillon protégé', { role, err: viewer.err, lignes: kept })

  save('s16.json', findings)
})
