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

  // ---------- 2.17 : une facture d'achat approuvée et impayée est un décaissement à venir ----------
  // Mesuré le 05/10 (rouges avant) : `purchase_invoices_status_check` n'admet pas `received`, et une
  // facture approuvée impayée reste `draft / approved / not_paid`. Les trois lecteurs et le moteur
  // `cash_flow_forecast` la cherchaient sous `['received','overdue']` : sorties à venir = 0, toujours.
  // Critère commun au moteur (470) et aux lecteurs : approuvée, non annulée, reste dû > 0 ; montant = reste dû.
  const partners = await import('@/lib/queries/partners')
  const sales = await import('@/lib/queries/sales')
  const core = await import('@/lib/queries/core')
  const iso = (d: Date) => d.toISOString().split('T')[0]
  const today = new Date()
  const due = new Date(today)
  due.setDate(due.getDate() + 20)
  const sup = await attempt(() => partners.createSupplier({ name: 'Fournisseur Trésorerie', email: 't@audit.test', phone: '', address: '', vat_number: '' } as Parameters<typeof partners.createSupplier>[0]))
  const supId = sup.val?.id ?? ''
  const pi = await attempt(() => sales.createPurchaseInvoice({ supplier_reference: 'F-217', supplier_id: supId, supplier_name: 'Fournisseur Trésorerie', date: iso(today), due_date: iso(due), status: 'draft',
    subtotal: 200, vat_total: 40, total: 240, amount_paid: 0, amount_due: 240, notes: '',
    lines: [{ product_id: null, description: 'Prestation', quantity: 2, unit_price: 100, vat_rate: 20, total: 200, vat_total: 40, vat_amount: 40, line_order: 0 }] }))
  const pid = pi.val?.id ?? ''
  const appr = await attempt(() => sales.updatePurchaseInvoiceApproval(pid, 'approved'))
  type Achat = { number: string; status: string; approval_status: string; payment_state: string; due: number }
  const lire = async () => (await sql<Achat>(`select number, status, approval_status, payment_state, amount_due::float due from purchase_invoices where id=$1`, [pid]))[0]
  // la référence, lue en base : ce qui reste dû aux fournisseurs sur des factures approuvées non annulées
  type Ref = { a30: number; a90: number; moteur90: number; depenses: number }
  const reference = async () => (await sql<Ref>(`select
      coalesce(round(sum(amount_due) filter (where amount_due > 0 and due_date between current_date and current_date + 30), 2), 0)::float a30,
      coalesce(round(sum(amount_due) filter (where amount_due > 0 and due_date between current_date and current_date + 90), 2), 0)::float a90,
      coalesce(round(sum(amount_due) filter (where amount_due > 0 and due_date <= current_date + 90), 2), 0)::float moteur90,
      coalesce(round(sum(total) filter (where date >= date_trunc('year', current_date)), 2), 0)::float depenses
    from purchase_invoices where tenant_id=$1 and approval_status='approved' and status <> 'cancelled'`, [A]))[0]
  const sortiesTableau = (v: Awaited<ReturnType<typeof acc.getTreasuryDashboard>> | undefined) => (v?.forecastBuckets ?? []).reduce((a, b) => a + b.outgoing, 0)

  const a1 = await lire()
  const ref1 = await reference()
  const td1 = await attempt(() => acc.getTreasuryDashboard())
  const tf1 = await attempt(() => acc.getTreasuryForecast(90))
  const ch1 = await attempt(() => acc.getDashboardChartData())
  const ev1 = tf1.val?.timeline.find((e) => e.reference === a1?.number)
  const sortiesLigne1 = (tf1.val?.timeline ?? []).filter((e) => e.type === 'out').reduce((a, e) => a + e.amount, 0)
  check('D08', 'tableau de trésorerie : la facture d\'achat approuvée impayée (240, échéance à 20 j) est dans les sorties 0-30 j, pour son reste dû',
    pi.ok && appr.ok && td1.ok && a1?.approval_status === 'approved' && a1.due === 240 && ref1.a30 >= 240 && eq(td1.val?.forecastBuckets[0].outgoing ?? 0, ref1.a30) && eq(sortiesTableau(td1.val), ref1.a90),
    { err: pi.err ?? appr.err ?? td1.err, facture: a1, ecran: td1.val?.forecastBuckets, base: ref1 })
  check('D09', 'prévision de trésorerie : elle figure à la ligne de temps pour 240, et le total des sorties est celui du moteur',
    tf1.ok && ev1?.type === 'out' && eq(ev1.amount, 240) && eq(sortiesLigne1, ref1.a90) && eq(tf1.val?.totalOutgoing ?? 0, ref1.moteur90),
    { err: tf1.err, evenement: ev1 ?? null, sorties_ligne_de_temps: sortiesLigne1, totalOutgoing: tf1.val?.totalOutgoing, base: ref1 })
  check('D10', 'graphique d\'accueil : les dépenses de l\'année = les factures d\'achat approuvées non annulées',
    ch1.ok && ref1.depenses >= 240 && eq(ch1.val?.cashFlow.find((c) => c.key === 'outflow')?.value ?? 0, ref1.depenses),
    { err: ch1.err, ecran: ch1.val?.cashFlow, base: ref1.depenses })

  // un décaissement partiel : c'est le RESTE DÛ qui sort, plus le total
  const bank = (await sql<{ id: string }>(`select id from bank_accounts where tenant_id=$1 order by created_at limit 1`, [A]))[0]
  const pay = await attempt(async () => partners.createSupplierPayment({ number: await core.nextDocumentNumber('DEC'), supplier_id: supId, purchase_invoice_id: pid, payment_date: iso(today), amount: 100, method: 'transfer', bank_account_id: bank.id, reference: 'F-217', status: 'recorded' }))
  const a2 = await lire()
  const ref2 = await reference()
  const td2 = await attempt(() => acc.getTreasuryDashboard())
  const tf2 = await attempt(() => acc.getTreasuryForecast(90))
  const ev2 = tf2.val?.timeline.find((e) => e.reference === a2?.number)
  check('D11', 'après un décaissement de 100 : la facture ne sort plus que pour 140, au tableau, à la ligne de temps et au moteur',
    pay.ok && a2?.due === 140 && eq(ref1.a30 - ref2.a30, 100) && td2.ok && eq(td2.val?.forecastBuckets[0].outgoing ?? 0, ref2.a30)
      && tf2.ok && eq(ev2?.amount ?? 0, 140) && eq(tf2.val?.totalOutgoing ?? 0, ref2.moteur90),
    { err: pay.err ?? td2.err ?? tf2.err, facture: a2, tableau: td2.val?.forecastBuckets, evenement: ev2 ?? null, totalOutgoing: tf2.val?.totalOutgoing, base: ref2 })
  save('s9.json', findings)
})
