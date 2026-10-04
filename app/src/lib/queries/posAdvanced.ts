import { supabase } from '@/lib/supabase'
import { localDateString } from '@/lib/dateRange'
import { getTenantId, ti, tud } from './core'
import type { PosTerminal, PosSession, PosTicket, PosTicketLine } from '@/types'

// ============ Terminals ============

export async function getPosTerminals(): Promise<PosTerminal[]> {
  const tid = await getTenantId()
  let q = supabase.from('pos_terminals').select('*').order('name')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return (data || []) as PosTerminal[]
}

export async function createPosTerminal(terminal: Omit<PosTerminal, 'id'>): Promise<PosTerminal> {
  const tid = await getTenantId()
  const { data, error } = await supabase
    .from('pos_terminals')
    .insert(ti({ ...terminal }, 'pos_terminals', tid))
    .select()
    .single()
  if (error) throw error
  return data as PosTerminal
}

export async function updatePosTerminal(id: string, updates: Partial<PosTerminal>): Promise<void> {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('pos_terminals').update(updates), 'pos_terminals', tid).eq('id', id)
  if (error) throw error
}

export async function deletePosTerminal(id: string): Promise<void> {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('pos_terminals').delete(), 'pos_terminals', tid).eq('id', id)
  if (error) throw error
}

// ============ Sessions ============

export async function openPosSession(terminalId: string, openingAmount: number): Promise<PosSession> {
  const tid = await getTenantId()
  const { data: { session } } = await supabase.auth.getSession()
  const userEmail = session?.user?.email || 'unknown'
  const { data, error } = await supabase
    .from('pos_sessions')
    .insert(ti({
      terminal_id: terminalId,
      user_email: userEmail,
      opening_amount: openingAmount,
      status: 'open',
    }, 'pos_sessions', tid))
    .select()
    .single()
  if (error) throw error
  return data as PosSession
}

/**
 * C12 (281) : l'écran transmet le comptage du tiroir ; l'ATTENDU (fond de caisse
 * + paiements en espèces seulement — la carte ne se compte pas dans le tiroir),
 * l'écart et l'écriture de clôture sont calculés par la base (déclencheur de
 * clôture). L'écran relit ce que la base a établi.
 */
export async function closePosSession(sessionId: string, closingAmount: number): Promise<PosSession> {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase
    .from('pos_sessions')
    .update({ closing_amount: closingAmount, status: 'closed', closed_at: new Date().toISOString() }), 'pos_sessions', tid)
    .eq('id', sessionId)
    .select()
    .single()
  if (error) throw error
  return data as PosSession
}

export async function getActiveSession(terminalId: string): Promise<PosSession | null> {
  const tid = await getTenantId()
  let q = supabase
    .from('pos_sessions')
    .select('*')
    .eq('terminal_id', terminalId)
    .eq('status', 'open')
    .order('opened_at', { ascending: false })
    .limit(1)
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q.maybeSingle()
  if (error) throw error
  return data as PosSession | null
}

export async function getPosSessions(terminalId?: string): Promise<(PosSession & { terminal: { name: string } | null })[]> {
  const tid = await getTenantId()
  let q = supabase
    .from('pos_sessions')
    .select('*, terminal:pos_terminals(name)')
    .order('opened_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (terminalId) q = q.eq('terminal_id', terminalId)
  const { data, error } = await q
  if (error) throw error
  return (data || []) as any
}

// ============ Tickets ============

/**
 * C12 / M7 (281) : un encaissement est UN appel atomique — ticket (totaux calculés
 * par la base), lignes, paiements (déduits du moyen du ticket si l'écran n'en
 * ventile pas) et sortie de stock au dépôt de la caisse. Refusé sur une session
 * close. Avant, trois écritures séparées, sans paiement : la clôture échouait.
 */
export async function createPosTicket(
  ticket: Omit<PosTicket, 'id' | 'created_at'>,
  lines: Omit<PosTicketLine, 'id' | 'created_at' | 'ticket_id'>[],
  payments?: { type?: string; payment_method_id?: string; amount: number; reference?: string }[],
): Promise<PosTicket> {
  const { data, error } = await supabase.rpc('create_pos_ticket', {
    p_ticket: ticket,
    p_lines: lines.map((l) => ({ product_id: l.product_id, description: l.description, quantity: l.quantity, unit_price: l.unit_price, vat_rate: l.vat_rate })),
    p_payments: payments && payments.length > 0 ? payments : null,
  })
  if (error) throw error
  return data as unknown as PosTicket
}

// `range` : bornes `[from, to)` d'une période, dans le fuseau de l'utilisateur
// (`localDayRange`). La borne haute est EXCLUE — la forme `lt` d'avant prenait
// le même jour que la borne basse, donc la période était vide (D4, stk-013).
export async function getPosTickets(sessionId?: string, range?: { from: string; to: string }): Promise<(PosTicket & { pos_ticket_lines: PosTicketLine[] })[]> {
  const tid = await getTenantId()
  let q = supabase
    .from('pos_tickets')
    .select('*, pos_ticket_lines(*)')
    .order('date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (sessionId) q = q.eq('session_id', sessionId)
  if (range) q = q.gte('date', range.from).lt('date', range.to)
  const { data, error } = await q
  if (error) throw error
  return (data || []) as any
}

export async function cancelPosTicket(id: string, reason?: string): Promise<void> {
  // 250 (POS-01) : l'annulation passe par la fonction dédiée. La garde
  // d'inaltérabilité refuse toute écriture directe sur un ticket encaissé ;
  // `void_pos_ticket` trace le motif, écrit l'événement NF-525, et refuse une
  // annulation après clôture de la session (l'avoir corrige alors la vente).
  const { error } = await supabase.rpc('void_pos_ticket', {
    p_ticket_id: id,
    p_reason: reason ?? null,
  })
  if (error) throw error
}

/**
 * 255 : après la clôture de la session, une vente ne s'annule plus — elle se
 * corrige par un AVOIR (pièce commerciale, stock rendu, événement NF-525).
 */
export async function refundPosTicket(id: string, reason?: string): Promise<void> {
  const { error } = await supabase.rpc('pos_refund_ticket', {
    p_ticket_id: id,
    p_reason: reason ?? null,
  })
  if (error) throw error
}

/** Les moyens de paiement ACTIFS de la société (Paramètres → Moyens de paiement de caisse). */
export async function getActivePosPaymentMethods(): Promise<{ id: string; name: string; type: string }[]> {
  const tid = await getTenantId()
  let q = supabase.from('pos_payment_methods').select('id, name, type').eq('is_active', true).order('display_order')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return (data || []) as { id: string; name: string; type: string }[]
}

export async function convertTicketToInvoice(ticketId: string): Promise<string> {
  const tid = await getTenantId()
  let ticketQ = supabase
    .from('pos_tickets')
    .select('*, pos_ticket_lines(*)')
    .eq('id', ticketId)
  if (tid) ticketQ = ticketQ.eq('tenant_id', tid)
  const { data: ticket } = await ticketQ.single()
  if (!ticket) throw new Error('Ticket not found')

  const t = ticket as any
  const invoiceNumber = 'INV-' + Date.now().toString().slice(-8)
  const { data: invoice, error: invError } = await supabase
    .from('invoices')
    .insert(ti({
      number: invoiceNumber,
      customer_id: t.customer_id,
      date: localDateString(),
      subtotal: t.subtotal,
      vat_total: t.vat_total,
      total: t.total,
      status: 'paid',
    }, 'invoices', tid))
    .select()
    .single()
  if (invError) throw invError

  const invoiceLines = (t.pos_ticket_lines || []).map((l: any) => ti({
    invoice_id: (invoice as any).id,
    product_id: l.product_id,
    description: l.description,
    quantity: l.quantity,
    unit_price: l.unit_price,
    vat_rate: l.vat_rate,
    line_total: l.line_total,
  }, 'invoice_lines', tid))

  if (invoiceLines.length > 0) {
    const { error: linesError } = await supabase.from('invoice_lines').insert(invoiceLines)
    if (linesError) throw linesError
  }

  const { error: updateError } = await supabase
    .from('pos_tickets')
    .update({ invoice_id: (invoice as any).id })
    .eq('id', ticketId)
    .eq('tenant_id', tid || '')
  if (updateError) throw updateError

  return (invoice as any).id
}

// ============ Stats ============

export async function getPosStats(sessionId: string): Promise<{
  ticketCount: number
  totalRevenue: number
  byPaymentMethod: Record<string, number>
  totalVat: number
}> {
  const tid = await getTenantId()
  let q = supabase
    .from('pos_tickets')
    .select('total, vat_total, payment_method')
    .eq('session_id', sessionId)
    .eq('status', 'completed')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error

  const tickets = data || []
  const byPaymentMethod: Record<string, number> = {}
  let totalRevenue = 0
  let totalVat = 0

  for (const t of tickets as any[]) {
    totalRevenue += Number(t.total || 0)
    totalVat += Number(t.vat_total || 0)
    const method = t.payment_method || 'unknown'
    byPaymentMethod[method] = (byPaymentMethod[method] || 0) + Number(t.total || 0)
  }

  return {
    ticketCount: tickets.length,
    totalRevenue,
    byPaymentMethod,
    totalVat,
  }
}
