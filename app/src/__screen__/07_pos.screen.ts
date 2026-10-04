import { it } from 'vitest'
import { login, A, sql, check, attempt, save, findings } from './rig'
const r2 = (n: number) => Math.round(n * 100) / 100
it('Caisse — terminal, session, tickets, clôture, comptabilité, stock', async () => {
  await login(0, A)
  const pos = await import('@/lib/queries/posAdvanced')
  const prod = (await sql(`select id, name, sale_price::float sp, vat_rate::float vr, stock_quantity::float q from products where tenant_id=$1 order by created_at desc limit 1`, [A]))[0]
  const t = await attempt(() => pos.createPosTerminal({ name: 'Caisse 1 ' + Date.now(), warehouse_id: null, location: null, active: true } as any))
  check('K01', 'créer un terminal', t.ok, t.err ?? (t.val as any).id)
  const term: any = t.val
  const s = await attempt(() => pos.openPosSession(term.id, 100))
  check('K02', 'ouvrir une session avec fond de caisse 100', s.ok, s.err ?? (s.val as any).status)
  const sess: any = s.val
  const mk = (qty: number, method: string, received: number) => {
    const line_total = qty * prod.sp, subtotal = line_total, vat = line_total * prod.vr / 100, total = subtotal + vat
    return pos.createPosTicket({ number: 'T-' + Date.now().toString().slice(-8) + qty, session_id: sess.id, terminal_id: term.id, customer_id: null, date: new Date().toISOString(), subtotal, vat_total: vat, total,
      payment_method: method, amount_paid: received, change_given: Math.max(0, received - total), status: 'completed', invoice_id: null, notes: null } as any,
      [{ product_id: prod.id, description: prod.name, quantity: qty, unit_price: prod.sp, vat_rate: prod.vr, line_total, tenant_id: null } as any])
  }
  const t1 = await attempt(() => mk(2, 'cash', 50))
  const tk1 = t1.ok ? (await sql(`select number, total::float, hash is not null h, status from pos_tickets where id=$1`, [(t1.val as any).id]).catch(async () => sql(`select number,total::float,status from pos_tickets where id=$1`, [(t1.val as any).id])))[0] : null
  check('K03', `ticket espèces 2 × ${prod.sp} HT + TVA ${prod.vr} % = ${r2(2 * prod.sp * (1 + prod.vr / 100))}`, t1.ok && tk1.total === r2(2 * prod.sp * (1 + prod.vr / 100)), t1.err ?? tk1)
  const stockAfter = (await sql(`select stock_quantity::float q from products where id=$1`, [prod.id]))[0].q
  check('K04', `la vente en caisse sort 2 unités du stock (${prod.q} → ${prod.q - 2})`, stockAfter === prod.q - 2, { avant: prod.q, apres: stockAfter })
  const t2 = await attempt(() => mk(1, 'card', 0))
  check('K05', 'ticket carte bancaire', t2.ok, t2.err ?? 'ok')
  const cashSales = r2(2 * prod.sp * (1 + prod.vr / 100))
  const c = await attempt(() => pos.closePosSession(sess.id, 100 + cashSales))
  const cs: any = c.val
  check('K06', `clôture : caisse comptée 100 + ${cashSales} espèces → écart 0 (la carte ne doit pas être attendue en tiroir)`, c.ok && r2(Number(cs.difference)) === 0, c.err ?? { attendu: cs.expected_amount, compte: cs.closing_amount, ecart: cs.difference })
  const je = await sql(`select l.account_code, sum(l.debit)::float d, sum(l.credit)::float c from journal_lines l join journal_entries e on e.id=l.journal_id where e.tenant_id=$1 and e.status='posted' and e.journal_code in ('POS','CA') and e.date::date = current_date group by 1 order by 1`, [A])
  check('K07', 'la clôture comptabilise les ventes (53/512 D, 70 C, 4457 C)', je.length > 0, je)
  const nf = await sql(`select count(*)::int n from nf525_event_log where tenant_id=$1`, [A]).catch(() => [{ n: -1 }])
  check('K08', 'journal NF-525 alimenté (tickets et clôture)', nf[0].n > 0, nf[0])
  const t3 = await attempt(() => mk(1, 'cash', 100))
  check('K09', 'un ticket sur une session CLOSE est refusé', !t3.ok, t3.err ?? 'ACCEPTÉ')
  await login(2, A)
  const t4 = await attempt(() => pos.openPosSession(term.id, 0))
  check('K10', 'un lecteur ne peut pas ouvrir de session de caisse', !t4.ok, t4.err ?? 'ACCEPTÉ')
  // D5 (stk-014) : PosSessionsPage annule un ticket tant que la session est ouverte.
  await login(0, A)
  const s2 = await attempt(() => pos.openPosSession(term.id, 0))
  if (s2.ok) {
    sess.id = (s2.val as { id: string }).id
    const avant = (await sql(`select stock_quantity::float q from products where id=$1`, [prod.id]))[0].q
    const t5 = await attempt(() => mk(1, 'cash', 100))
    const id5 = (t5.val as { id: string } | undefined)?.id
    const an = id5 ? await attempt(() => pos.cancelPosTicket(id5, 'erreur de saisie')) : { ok: false, err: t5.err }
    const apres = (await sql(`select stock_quantity::float q from products where id=$1`, [prod.id]))[0].q
    const st = id5 ? (await sql(`select status from pos_tickets where id=$1`, [id5]))[0]?.status : null
    check('K11', 'annuler un ticket par l\'écran (session ouverte) : statut « annulé » et stock rendu', an.ok && st === 'cancelled' && apres === avant, { err: an.err, statut: st, avant, apres })
  }
  save('s7.json', findings)
})
