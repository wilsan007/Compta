import { supabase } from '@/lib/supabase'
import { fetchAllRows, getTenantId, ti, tud } from './core'
import type { CrmOpportunity, CrmActivity, CrmCampaign, CrmTerritory, CrmForecast, ServiceTicket, ServiceTicketMessage, ServiceContract, KnowledgeBaseArticle } from '@/types'

// ============ Sprint F: CRM Opportunities ============

export async function getOpportunities(stage?: string) {
  const tid = await getTenantId()
  let q = supabase.from('crm_opportunities').select('*, customer:customers(name), prospect:prospects(name)').order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (stage) q = q.eq('stage', stage)
  const { data, error } = await q
  if (error) throw error
  return data as (CrmOpportunity & { customer: { name: string } | null, prospect: { name: string } | null })[]
}

export async function getOpportunityById(id: string) {
  const tid = await getTenantId()
  let q = supabase.from('crm_opportunities').select('*').eq('id', id)
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q.maybeSingle()
  if (error) throw error
  return data as CrmOpportunity | null
}

export async function createOpportunity(opp: Omit<CrmOpportunity, 'id' | 'created_at' | 'updated_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('crm_opportunities').insert(ti(opp, 'crm_opportunities', tid)).select().single()
  if (error) throw error
  return data as CrmOpportunity
}

export async function updateOpportunityStage(id: string, stage: string) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('crm_opportunities').update({ stage, updated_at: new Date().toISOString() }), 'crm_opportunities', tid).eq('id', id).select().single()
  if (error) throw error
  return data as CrmOpportunity
}

export async function deleteOpportunity(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('crm_opportunities').delete(), 'crm_opportunities', tid).eq('id', id)
  if (error) throw error
}

// ============ Sprint F: CRM Activities ============

export async function getActivities(opportunityId?: string) {
  const tid = await getTenantId()
  let q = supabase.from('crm_activities').select('*').order('scheduled_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (opportunityId) q = q.eq('opportunity_id', opportunityId)
  const { data, error } = await q
  if (error) throw error
  return data as CrmActivity[]
}

export async function createActivity(activity: Omit<CrmActivity, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('crm_activities').insert(ti(activity, 'crm_activities', tid)).select().single()
  if (error) throw error
  return data as CrmActivity
}

export async function completeActivity(id: string) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('crm_activities').update({ status: 'done', completed_date: new Date().toISOString() }), 'crm_activities', tid).eq('id', id).select().single()
  if (error) throw error
  return data as CrmActivity
}

export async function deleteActivity(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('crm_activities').delete(), 'crm_activities', tid).eq('id', id)
  if (error) throw error
}

// ============ Sprint F: CRM Campaigns ============

export async function getCampaigns(status?: string) {
  const tid = await getTenantId()
  let q = supabase.from('crm_campaigns').select('*').order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (status) q = q.eq('status', status)
  const { data, error } = await q
  if (error) throw error
  return data as CrmCampaign[]
}

export async function createCampaign(camp: Omit<CrmCampaign, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('crm_campaigns').insert(ti(camp, 'crm_campaigns', tid)).select().single()
  if (error) throw error
  return data as CrmCampaign
}

export async function launchCampaign(id: string) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('crm_campaigns').update({ status: 'running' }), 'crm_campaigns', tid).eq('id', id).select().single()
  if (error) throw error
  return data as CrmCampaign
}

export async function getCampaignStats(id: string) {
  const tid = await getTenantId()
  let q = supabase.from('crm_campaigns').select('*').eq('id', id)
  if (tid) q = q.eq('tenant_id', tid)
  const { data: camp, error } = await q.maybeSingle()
  if (error) throw error
  if (!camp) return null

  let qR = supabase.from('crm_campaign_recipients').select('sent, opened, clicked, responded').eq('campaign_id', id)
  if (tid) qR = qR.eq('tenant_id', tid)
  const { data: recipients } = await qR

  const total = recipients?.length || 0
  const sent = recipients?.filter((r: any) => r.sent).length || 0
  const opened = recipients?.filter((r: any) => r.opened).length || 0
  const clicked = recipients?.filter((r: any) => r.clicked).length || 0
  const responded = recipients?.filter((r: any) => r.responded).length || 0

  return {
    total,
    sent,
    opened,
    clicked,
    responded,
    openRate: sent > 0 ? (opened / sent) * 100 : 0,
    clickRate: sent > 0 ? (clicked / sent) * 100 : 0,
    responseRate: sent > 0 ? (responded / sent) * 100 : 0,
    conversionRate: camp.conversion_count || 0,
  }
}

// ============ Sprint F: CRM Territories ============

export async function getTerritories() {
  const tid = await getTenantId()
  let q = supabase.from('crm_territories').select('*').order('name', { ascending: true })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as CrmTerritory[]
}

export async function createTerritory(terr: Omit<CrmTerritory, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('crm_territories').insert(ti(terr, 'crm_territories', tid)).select().single()
  if (error) throw error
  return data as CrmTerritory
}

export async function assignTerritoryRep(id: string, repId: string) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('crm_territories').update({ sales_rep_id: repId }), 'crm_territories', tid).eq('id', id).select().single()
  if (error) throw error
  return data as CrmTerritory
}

export async function deleteTerritory(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('crm_territories').delete(), 'crm_territories', tid).eq('id', id)
  if (error) throw error
}

// ============ Sprint F: CRM Forecasts ============

export async function getForecasts(period?: string) {
  const tid = await getTenantId()
  let q = supabase.from('crm_forecasts').select('*').order('period', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (period) q = q.eq('period', period)
  const { data, error } = await q
  if (error) throw error
  return data as CrmForecast[]
}

export async function createForecast(fc: Omit<CrmForecast, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('crm_forecasts').insert(ti(fc, 'crm_forecasts', tid)).select().single()
  if (error) throw error
  return data as CrmForecast
}

export async function deleteForecast(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('crm_forecasts').delete(), 'crm_forecasts', tid).eq('id', id)
  if (error) throw error
}

export async function getSalesPipeline() {
  const tid = await getTenantId()
  let q = supabase.from('crm_opportunities').select('stage, expected_amount, probability').order('id')
  if (tid) q = q.eq('tenant_id', tid)
  // LOT7-03 : le pipeline commercial agrège toutes les opportunités par étape.
  const data = await fetchAllRows<any>(q, { label: 'getSalesPipeline/crm_opportunities' })

  const stages = ['new', 'qualified', 'proposition', 'negotiation', 'won', 'lost']
  const pipeline: Record<string, { count: number; total: number; weighted: number }> = {}
  for (const s of stages) pipeline[s] = { count: 0, total: 0, weighted: 0 }

  for (const opp of data) {
    const stage = (opp as any).stage as string
    if (pipeline[stage]) {
      pipeline[stage].count++
      pipeline[stage].total += Number((opp as any).expected_amount || 0)
      pipeline[stage].weighted += Number((opp as any).expected_amount || 0) * (Number((opp as any).probability || 0) / 100)
    }
  }

  return pipeline
}

// ============ Sprint G: Service Tickets ============

export async function getTickets(status?: string, priority?: string) {
  const tid = await getTenantId()
  let q = supabase.from('service_tickets').select('*, customer:customers(name)').order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (status) q = q.eq('status', status)
  if (priority) q = q.eq('priority', priority)
  const { data, error } = await q
  if (error) throw error
  return data as (ServiceTicket & { customer: { name: string } | null })[]
}

export async function createTicket(ticket: Omit<ServiceTicket, 'id' | 'created_at' | 'updated_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('service_tickets').insert(ti(ticket, 'service_tickets', tid)).select().single()
  if (error) throw error
  return data as ServiceTicket
}

export async function updateTicketStatus(id: string, status: string) {
  const tid = await getTenantId()
  const updates: any = { status, updated_at: new Date().toISOString() }
  if (status === 'resolved') updates.resolved_at = new Date().toISOString()
  if (status === 'closed') updates.closed_at = new Date().toISOString()
  const { data, error } = await tud(supabase.from('service_tickets').update(updates), 'service_tickets', tid).eq('id', id).select().single()
  if (error) throw error
  return data as ServiceTicket
}

export async function assignTicket(id: string, agent: string) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('service_tickets').update({ assigned_to: agent, updated_at: new Date().toISOString() }), 'service_tickets', tid).eq('id', id).select().single()
  if (error) throw error
  return data as ServiceTicket
}

export async function deleteTicket(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('service_tickets').delete(), 'service_tickets', tid).eq('id', id)
  if (error) throw error
}

// ============ Sprint G: Ticket Messages ============

export async function getTicketMessages(ticketId: string) {
  const tid = await getTenantId()
  let q = supabase.from('service_ticket_messages').select('*').eq('ticket_id', ticketId).order('created_at', { ascending: true })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as ServiceTicketMessage[]
}

export async function addTicketMessage(msg: Omit<ServiceTicketMessage, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('service_ticket_messages').insert(ti(msg, 'service_ticket_messages', tid)).select().single()
  if (error) throw error
  return data as ServiceTicketMessage
}

export async function checkSlaCompliance(ticketId: string) {
  const tid = await getTenantId()
  let q = supabase.from('service_tickets').select('*, service_contracts(sla_response_hours, sla_resolution_hours)').eq('id', ticketId)
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q.maybeSingle()
  if (error) throw error
  if (!data) return null

  const ticket = data as any
  const contract = ticket.service_contracts
  if (!contract) return { hasContract: false, responseBreached: false, resolutionBreached: false }

  const now = new Date()
  const created = new Date(ticket.created_at)
  const elapsed = (now.getTime() - created.getTime()) / (1000 * 60 * 60)

  return {
    hasContract: true,
    responseBreached: !ticket.first_response_at && contract.sla_response_hours && elapsed > contract.sla_response_hours,
    resolutionBreached: !ticket.resolved_at && contract.sla_resolution_hours && elapsed > contract.sla_resolution_hours,
    elapsedHours: elapsed,
    slaResponseHours: contract.sla_response_hours,
    slaResolutionHours: contract.sla_resolution_hours,
  }
}

// ============ Sprint G: Service Contracts ============

export async function getServiceContracts(customerId?: string) {
  const tid = await getTenantId()
  let q = supabase.from('service_contracts').select('*, customer:customers(name)').order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (customerId) q = q.eq('customer_id', customerId)
  const { data, error } = await q
  if (error) throw error
  return data as (ServiceContract & { customer: { name: string } | null })[]
}

export async function createServiceContract(contract: Omit<ServiceContract, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('service_contracts').insert(ti(contract, 'service_contracts', tid)).select().single()
  if (error) throw error
  return data as ServiceContract
}

export async function deleteServiceContract(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('service_contracts').delete(), 'service_contracts', tid).eq('id', id)
  if (error) throw error
}

// ============ Sprint G: Knowledge Base ============

export async function getKbArticles(category?: string, status?: string) {
  const tid = await getTenantId()
  let q = supabase.from('knowledge_base_articles').select('*').order('updated_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (category) q = q.eq('category', category)
  if (status) q = q.eq('status', status)
  const { data, error } = await q
  if (error) throw error
  return data as KnowledgeBaseArticle[]
}

export async function createKbArticle(article: Omit<KnowledgeBaseArticle, 'id' | 'created_at' | 'updated_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('knowledge_base_articles').insert(ti(article, 'knowledge_base_articles', tid)).select().single()
  if (error) throw error
  return data as KnowledgeBaseArticle
}

export async function updateKbArticle(id: string, updates: Partial<KnowledgeBaseArticle>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('knowledge_base_articles').update({ ...updates, updated_at: new Date().toISOString() }), 'knowledge_base_articles', tid).eq('id', id).select().single()
  if (error) throw error
  return data as KnowledgeBaseArticle
}

export async function incrementKbViews(id: string) {
  const tid = await getTenantId()
  let q = supabase.from('knowledge_base_articles').select('views').eq('id', id)
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q.maybeSingle()
  if (error) throw error
  if (!data) return

  await tud(supabase.from('knowledge_base_articles').update({ views: (data as any).views + 1 }), 'knowledge_base_articles', tid).eq('id', id)
}

export async function rateKbArticle(id: string, helpful: boolean) {
  const tid = await getTenantId()
  let q = supabase.from('knowledge_base_articles').select('helpful_count, not_helpful_count').eq('id', id)
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q.maybeSingle()
  if (error) throw error
  if (!data) return

  const updates = helpful
    ? { helpful_count: (data as any).helpful_count + 1 }
    : { not_helpful_count: (data as any).not_helpful_count + 1 }

  await tud(supabase.from('knowledge_base_articles').update(updates), 'knowledge_base_articles', tid).eq('id', id)
}

export async function deleteKbArticle(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('knowledge_base_articles').delete(), 'knowledge_base_articles', tid).eq('id', id)
  if (error) throw error
}
