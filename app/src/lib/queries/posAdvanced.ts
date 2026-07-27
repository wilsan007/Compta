import { supabase } from '@/lib/supabase'
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

export async function closePosSession(sessionId: string, closingAmount: number): Promise<PosSession> {
  const tid = await getTenantId()
  let sessionQ = supabase
    .from('pos_sessions')
    .select('opening_amount, pos_tickets(total)')
    .eq('id', sessionId)
  if (tid) sessionQ = sessionQ.eq('tenant_id', tid)
  const { data: session } = await sessionQ.single()
  if (session) {
    const openingAmount = Number((session as any).opening_amount || 0)
    const ticketsTotal = ((session as any).pos_tickets || []).reduce(
      (sum: number, t: any) => sum + Number(t.total || 0), 0
    )
    const expected = openingAmount + ticketsTotal
    const difference = closingAmount - expected
    const { data, error } = await supabase
      .from('pos_sessions')
      .update({
        closing_amount: closingAmount,
        expected_amount: expected,
        difference,
        status: 'closed',
        closed_at: new Date().toISOString(),
      })
      .eq('id', sessionId)
      .eq('tenant_id', tid || '')
      .select()
      .single()
    if (error) throw error
    return data as PosSession
  }
  throw new Error('Session not found')
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

export async function createPosTicket(
  ticket: Omit<PosTicket, 'id' | 'created_at'>,
  lines: Omit<PosTicketLine, 'id' | 'created_at' | 'ticket_id'>[]
): Promise<PosTicket> {
  const tid = await getTenantId()
  const { data: ticketData, error: ticketError } = await supabase
    .from('pos_tickets')
    .insert(ti({ ...ticket }, 'pos_tickets', tid))
    .select()
    .single()
  if (ticketError) throw ticketError
  const createdTicket = ticketData as PosTicket

  const ticketLines = lines.map(l => ti({
    ...l,
    ticket_id: createdTicket.id,
  }, 'pos_ticket_lines', tid))

  const { error: linesError } = await supabase
    .from('pos_ticket_lines')
    .insert(ticketLines)
  if (linesError) throw linesError

  return createdTicket
}

export async function getPosTickets(sessionId?: string, date?: string): Promise<(PosTicket & { pos_ticket_lines: PosTicketLine[] })[]> {
  const tid = await getTenantId()
  let q = supabase
    .from('pos_tickets')
    .select('*, pos_ticket_lines(*)')
    .order('date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (sessionId) q = q.eq('session_id', sessionId)
  if (date) q = q.gte('date', date).lt('date', date + 'T23:59:59')
  const { data, error } = await q
  if (error) throw error
  return (data || []) as any
}

export async function cancelPosTicket(id: string): Promise<void> {
  const tid = await getTenantId()
  const { error } = await supabase
    .from('pos_tickets')
    .update({ status: 'cancelled' })
    .eq('id', id)
    .eq('tenant_id', tid || '')
  if (error) throw error
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
      date: new Date().toISOString().split('T')[0],
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
