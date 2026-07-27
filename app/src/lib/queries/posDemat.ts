import { supabase } from '@/lib/supabase'
import { getTenantId, ti, tud } from './core'
import type { PosTerminal, PosSession, PosTicket, PosTicketLine, ElectronicSignature, OnlinePayment, DocumentShare } from '@/types'

// ============ Sprint H: POS Terminals ============

export async function getPosTerminals() {
  const tid = await getTenantId()
  let q = supabase.from('pos_terminals').select('*').order('name', { ascending: true })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as PosTerminal[]
}

export async function createPosTerminal(terminal: Omit<PosTerminal, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('pos_terminals').insert(ti(terminal, 'pos_terminals', tid)).select().single()
  if (error) throw error
  return data as PosTerminal
}

export async function updatePosTerminal(id: string, updates: Partial<PosTerminal>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('pos_terminals').update(updates), 'pos_terminals', tid).eq('id', id).select().single()
  if (error) throw error
  return data as PosTerminal
}

export async function deletePosTerminal(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('pos_terminals').delete(), 'pos_terminals', tid).eq('id', id)
  if (error) throw error
}

// ============ Sprint H: POS Sessions ============

export async function getPosSessions(status?: string) {
  const tid = await getTenantId()
  let q = supabase.from('pos_sessions').select('*, terminal:pos_terminals(name)').order('opened_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (status) q = q.eq('status', status)
  const { data, error } = await q
  if (error) throw error
  return data as (PosSession & { terminal: { name: string } | null })[]
}

export async function openPosSession(session: Omit<PosSession, 'id' | 'opened_at' | 'closed_at' | 'difference' | 'expected_amount' | 'closing_amount' | 'status'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('pos_sessions').insert(ti({ ...session, status: 'open' }, 'pos_sessions', tid)).select().single()
  if (error) throw error
  return data as PosSession
}

export async function closePosSession(id: string, closingAmount: number, expectedAmount: number, notes?: string) {
  const tid = await getTenantId()
  const updates = {
    status: 'closed',
    closing_amount: closingAmount,
    expected_amount: expectedAmount,
    difference: closingAmount - expectedAmount,
    closed_at: new Date().toISOString(),
    notes: notes || null,
  }
  const { data, error } = await tud(supabase.from('pos_sessions').update(updates), 'pos_sessions', tid).eq('id', id).select().single()
  if (error) throw error
  return data as PosSession
}

// ============ Sprint H: POS Tickets ============

export async function getPosTickets(sessionId?: string, terminalId?: string) {
  const tid = await getTenantId()
  let q = supabase.from('pos_tickets').select('*, customer:customers(name), lines:pos_ticket_lines(*)').order('date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (sessionId) q = q.eq('session_id', sessionId)
  if (terminalId) q = q.eq('terminal_id', terminalId)
  const { data, error } = await q
  if (error) throw error
  return data as (PosTicket & { customer: { name: string } | null, lines: PosTicketLine[] })[]
}

export async function createPosTicket(ticket: Omit<PosTicket, 'id' | 'created_at' | 'date'>, lines: Omit<PosTicketLine, 'id' | 'created_at' | 'ticket_id' | 'tenant_id'>[]) {
  const tid = await getTenantId()
  const { data: tick, error: tickErr } = await supabase.from('pos_tickets').insert(ti({ ...ticket, date: new Date().toISOString() }, 'pos_tickets', tid)).select().single()
  if (tickErr) throw tickErr

  const linePayloads = lines.map(l => ti({ ...l, ticket_id: tick.id }, 'pos_ticket_lines', tid))
  const { error: linesErr } = await supabase.from('pos_ticket_lines').insert(linePayloads)
  if (linesErr) throw linesErr

  return tick as PosTicket
}

export async function cancelPosTicket(id: string) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('pos_tickets').update({ status: 'cancelled' }), 'pos_tickets', tid).eq('id', id).select().single()
  if (error) throw error
  return data as PosTicket
}

// ============ Sprint H: POS Stats ============

export async function getPosStats(period: 'today' | 'thisWeek' | 'thisMonth') {
  const tid = await getTenantId()
  const now = new Date()
  let startDate = new Date(now)
  if (period === 'today') startDate.setHours(0, 0, 0, 0)
  else if (period === 'thisWeek') { startDate.setDate(now.getDate() - now.getDay()); startDate.setHours(0, 0, 0, 0) }
  else if (period === 'thisMonth') { startDate = new Date(now.getFullYear(), now.getMonth(), 1) }

  let q = supabase.from('pos_tickets').select('total, vat_total, payment_method, date').eq('status', 'completed').gte('date', startDate.toISOString())
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error

  const tickets = data || []
  const totalRevenue = tickets.reduce((s, t) => s + Number(t.total), 0)
  const totalVat = tickets.reduce((s, t) => s + Number(t.vat_total), 0)
  const totalTickets = tickets.length
  const averageTicket = totalTickets > 0 ? totalRevenue / totalTickets : 0

  const byPaymentMethod: Record<string, number> = {}
  for (const t of tickets) {
    const m = t.payment_method || 'unknown'
    byPaymentMethod[m] = (byPaymentMethod[m] || 0) + Number(t.total)
  }

  const byDay: Record<string, number> = {}
  for (const t of tickets) {
    const d = new Date(t.date).toISOString().split('T')[0]
    byDay[d] = (byDay[d] || 0) + Number(t.total)
  }

  return { totalRevenue, totalVat, totalTickets, averageTicket, byPaymentMethod, byDay }
}

// ============ Sprint I: Electronic Signatures ============

export async function getElectronicSignatures(docType?: string, docId?: string) {
  const tid = await getTenantId()
  let q = supabase.from('electronic_signatures').select('*').order('signed_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (docType) q = q.eq('document_type', docType)
  if (docId) q = q.eq('document_id', docId)
  const { data, error } = await q
  if (error) throw error
  return data as ElectronicSignature[]
}

export async function createElectronicSignature(sig: Omit<ElectronicSignature, 'id' | 'signed_at' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('electronic_signatures').insert(ti({ ...sig, signed_at: new Date().toISOString() }, 'electronic_signatures', tid)).select().single()
  if (error) throw error
  return data as ElectronicSignature
}

// ============ Sprint I: Online Payments ============

export async function getOnlinePayments(status?: string) {
  const tid = await getTenantId()
  let q = supabase.from('online_payments').select('*, invoice:invoices(number), customer:customers(name)').order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (status) q = q.eq('status', status)
  const { data, error } = await q
  if (error) throw error
  return data as (OnlinePayment & { invoice: { number: string } | null, customer: { name: string } | null })[]
}

export async function createOnlinePayment(payment: Omit<OnlinePayment, 'id' | 'created_at' | 'paid_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('online_payments').insert(ti(payment, 'online_payments', tid)).select().single()
  if (error) throw error
  return data as OnlinePayment
}

export async function updateOnlinePaymentStatus(id: string, status: string) {
  const tid = await getTenantId()
  const updates: any = { status }
  if (status === 'completed') updates.paid_at = new Date().toISOString()
  const { data, error } = await tud(supabase.from('online_payments').update(updates), 'online_payments', tid).eq('id', id).select().single()
  if (error) throw error
  return data as OnlinePayment
}

// ============ Sprint I: Document Shares ============

export async function getDocumentShares(docType?: string) {
  const tid = await getTenantId()
  let q = supabase.from('document_shares').select('*').order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (docType) q = q.eq('document_type', docType)
  const { data, error } = await q
  if (error) throw error
  return data as DocumentShare[]
}

export async function createDocumentShare(share: Omit<DocumentShare, 'id' | 'created_at' | 'viewed' | 'viewed_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('document_shares').insert(ti({ ...share, viewed: false }, 'document_shares', tid)).select().single()
  if (error) throw error
  return data as DocumentShare
}

export async function deleteDocumentShare(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('document_shares').delete(), 'document_shares', tid).eq('id', id)
  if (error) throw error
}

export async function markDocumentShareViewed(token: string) {
  const { data, error } = await supabase.from('document_shares').update({ viewed: true, viewed_at: new Date().toISOString() }).eq('share_token', token).select().single()
  if (error) throw error
  return data as DocumentShare
}
