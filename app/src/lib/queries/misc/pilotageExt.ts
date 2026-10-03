// ============================================================================
// misc — pilotageExt.ts
// Extrait de l'ancien misc.ts le 2026-10-01 ; imports recalcules ;
// aucun code metier modifie.
// ============================================================================

import { supabase } from '@/lib/supabase'
import { getTenantId, tud } from '../core'
import { type RevisionCycle, type ReportingPlan, type StatField, type FusionLog, type CompactionLog, type RGPDRequest, type GridTemplate, type ReimputationLog, type BankStatementTemplate } from '@/types'

// ============ Phase 7C: Revision Cycles ============

export async function getRevisionCycles(): Promise<RevisionCycle[]> {
  const tid = await getTenantId()
  let q = supabase.from('revision_cycles').select('*').order('name', { ascending: true })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as RevisionCycle[]
}

export async function createRevisionCycle(rc: Omit<RevisionCycle, 'id' | 'created_at' | 'updated_at' | 'tenant_id'>): Promise<RevisionCycle> {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('revision_cycles').insert({ ...rc, tenant_id: tid }).select().single()
  if (error) throw error
  return data as RevisionCycle
}

export async function updateRevisionCycle(id: string, updates: Partial<RevisionCycle>): Promise<RevisionCycle> {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('revision_cycles').update(updates), 'revision_cycles', tid).eq('id', id).select().single()
  if (error) throw error
  return data as RevisionCycle
}

export async function deleteRevisionCycle(id: string): Promise<void> {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('revision_cycles').delete(), 'revision_cycles', tid).eq('id', id)
  if (error) throw error
}



// ============ Phase 7C: Reporting Plans ============

export async function getReportingPlans(): Promise<ReportingPlan[]> {
  const tid = await getTenantId()
  let q = supabase.from('reporting_plans').select('*').order('name', { ascending: true })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as ReportingPlan[]
}

export async function createReportingPlan(rp: Omit<ReportingPlan, 'id' | 'created_at' | 'updated_at' | 'tenant_id'>): Promise<ReportingPlan> {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('reporting_plans').insert({ ...rp, tenant_id: tid }).select().single()
  if (error) throw error
  return data as ReportingPlan
}

export async function updateReportingPlan(id: string, updates: Partial<ReportingPlan>): Promise<ReportingPlan> {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('reporting_plans').update(updates), 'reporting_plans', tid).eq('id', id).select().single()
  if (error) throw error
  return data as ReportingPlan
}

export async function deleteReportingPlan(id: string): Promise<void> {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('reporting_plans').delete(), 'reporting_plans', tid).eq('id', id)
  if (error) throw error
}



// ============ Phase 7C: Stat Fields ============

export async function getStatFields(entityType?: string, entityId?: string): Promise<StatField[]> {
  const tid = await getTenantId()
  let q = supabase.from('stat_fields').select('*').order('field_name', { ascending: true })
  if (tid) q = q.eq('tenant_id', tid)
  if (entityType) q = q.eq('entity_type', entityType)
  if (entityId) q = q.eq('entity_id', entityId)
  const { data, error } = await q
  if (error) throw error
  return data as StatField[]
}

export async function createStatField(sf: Omit<StatField, 'id' | 'created_at' | 'updated_at' | 'tenant_id'>): Promise<StatField> {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('stat_fields').insert({ ...sf, tenant_id: tid }).select().single()
  if (error) throw error
  return data as StatField
}

export async function deleteStatField(id: string): Promise<void> {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('stat_fields').delete(), 'stat_fields', tid).eq('id', id)
  if (error) throw error
}



// ============ Phase 7C: Fusion de comptes ============

export async function getFusionLogs(): Promise<FusionLog[]> {
  const tid = await getTenantId()
  let q = supabase.from('fusion_logs').select('*').order('fused_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as FusionLog[]
}

export async function fuseAccounts(sourceCode: string, targetCode: string): Promise<FusionLog> {
  const tid = await getTenantId()
  // Move all journal_lines from source to target
  const { data: moved, error: moveError } = await tud(
    supabase.from('journal_lines').update({ account_code: targetCode, account_general: targetCode }),
    'journal_lines', tid
  ).eq('account_general', sourceCode).select('id')
  if (moveError) throw moveError
  const linesMoved = moved?.length || 0

  // Log the fusion
  const { data, error: insertError } = await supabase.from('fusion_logs').insert({
    source_account_code: sourceCode,
    target_account_code: targetCode,
    lines_moved: linesMoved,
    fused_by: null,
    tenant_id: tid,
  }).select().single()
  if (insertError) throw insertError
  return data as FusionLog
}



// ============ Phase 7C: Compaction ============

export async function getCompactionLogs(): Promise<CompactionLog[]> {
  const tid = await getTenantId()
  let q = supabase.from('compaction_logs').select('*').order('compacted_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as CompactionLog[]
}

export async function createCompactionLog(cl: Omit<CompactionLog, 'id' | 'compacted_at' | 'tenant_id'>): Promise<CompactionLog> {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('compaction_logs').insert({ ...cl, tenant_id: tid }).select().single()
  if (error) throw error
  return data as CompactionLog
}

export async function updateCompactionLog(id: string, updates: Partial<CompactionLog>): Promise<CompactionLog> {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('compaction_logs').update(updates), 'compaction_logs', tid).eq('id', id).select().single()
  if (error) throw error
  return data as CompactionLog
}



// ============ Phase 7C: RGPD Requests ============

export async function getRGPDRequests(): Promise<RGPDRequest[]> {
  const tid = await getTenantId()
  let q = supabase.from('rgpd_requests').select('*').order('requested_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as RGPDRequest[]
}

export async function createRGPDRequest(rr: Omit<RGPDRequest, 'id' | 'requested_at' | 'tenant_id'>): Promise<RGPDRequest> {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('rgpd_requests').insert({ ...rr, tenant_id: tid }).select().single()
  if (error) throw error
  return data as RGPDRequest
}

export async function updateRGPDRequest(id: string, updates: Partial<RGPDRequest>): Promise<RGPDRequest> {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('rgpd_requests').update(updates), 'rgpd_requests', tid).eq('id', id).select().single()
  if (error) throw error
  return data as RGPDRequest
}



// ============ Phase 7D: Grid Templates (Modèles de grille) ============

export async function getGridTemplates(): Promise<GridTemplate[]> {
  const tid = await getTenantId()
  let q = supabase.from('grid_templates').select('*').order('code')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as GridTemplate[]
}

export async function createGridTemplate(gt: Omit<GridTemplate, 'id' | 'created_at' | 'updated_at' | 'tenant_id'>): Promise<GridTemplate> {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('grid_templates').insert({ ...gt, tenant_id: tid }).select().single()
  if (error) throw error
  return data as GridTemplate
}

export async function updateGridTemplate(id: string, updates: Partial<GridTemplate>): Promise<GridTemplate> {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('grid_templates').update(updates), 'grid_templates', tid).eq('id', id).select().single()
  if (error) throw error
  return data as GridTemplate
}

export async function deleteGridTemplate(id: string): Promise<void> {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('grid_templates').delete(), 'grid_templates', tid).eq('id', id)
  if (error) throw error
}



// ============ Phase 7D: Reimputation Logs (Réimputation) ============

export async function getReimputationLogs(): Promise<ReimputationLog[]> {
  const tid = await getTenantId()
  let q = supabase.from('reimputation_logs').select('*').order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as ReimputationLog[]
}

export async function createReimputationLog(rl: Omit<ReimputationLog, 'id' | 'created_at' | 'tenant_id'>): Promise<ReimputationLog> {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('reimputation_logs').insert({ ...rl, tenant_id: tid }).select().single()
  if (error) throw error
  return data as ReimputationLog
}



// ============ Template Validation Logic ============
// Flow: user validates AI results. If no corrections → consecutive_successes++.
// When consecutive_successes >= 2 → status = 'validated'.
// If corrections made → consecutive_successes = 0, status stays 'pending'.

export async function getTemplateByBankId(bankId: string): Promise<BankStatementTemplate | null> {
  // First try own tenant's template
  const tid = await getTenantId()
  let q = supabase.from('bank_statement_templates').select('*').eq('bank_id', bankId).eq('is_active', true)
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q.order('updated_at', { ascending: false }).limit(1)
  if (error) throw error
  if (data && data.length > 0) return data[0] as BankStatementTemplate

  // Fallback: any validated template from any tenant (shared knowledge)
  const { data: validated, error: vErr } = await supabase
    .from('bank_statement_templates')
    .select('*')
    .eq('bank_id', bankId)
    .eq('validation_status', 'validated')
    .eq('is_active', true)
    .order('updated_at', { ascending: false })
    .limit(1)
  if (vErr) throw vErr
  return (validated && validated.length > 0) ? validated[0] as BankStatementTemplate : null
}

export async function validateTemplateResult(templateId: string, hadCorrections: boolean, correctionNotes?: string): Promise<BankStatementTemplate> {
  const tid = await getTenantId()
  // Fetch current state
  const { data: current, error: fetchErr } = await supabase
    .from('bank_statement_templates')
    .select('consecutive_successes, validation_count, validation_status')
    .eq('id', templateId)
    .single()
  if (fetchErr || !current) throw fetchErr || new Error('Template not found')

  const cur = current as any
  let newConsecutive: number
  let newStatus: string

  if (hadCorrections) {
    newConsecutive = 0
    newStatus = 'pending'
  } else {
    newConsecutive = (cur.consecutive_successes || 0) + 1
    newStatus = newConsecutive >= 2 ? 'validated' : 'pending'
  }

  const updates = {
    consecutive_successes: newConsecutive,
    validation_count: (cur.validation_count || 0) + 1,
    validation_status: newStatus,
    last_validated_at: new Date().toISOString(),
    last_correction_notes: hadCorrections ? (correctionNotes || null) : null,
  }

  const { data, error } = await tud(
    supabase.from('bank_statement_templates').update(updates),
    'bank_statement_templates',
    tid
  ).eq('id', templateId).select().single()
  if (error) throw error
  return data as BankStatementTemplate
}



// ============ #30 — Credit limit check ============
export async function checkCreditLimit(tpaCode: string): Promise<{ exceeded: boolean; balance: number; limit: number | null }> {
  const tid = await getTenantId()
  let q = supabase.from('third_party_accounts').select('balance, credit_limit').eq('code', tpaCode)
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q.single()
  if (error) { console.error('checkCreditLimit:', error); return { exceeded: false, balance: 0, limit: null } }
  if (!data) return { exceeded: false, balance: 0, limit: null }
  const balance = Number(data.balance || 0)
  const limit = data.credit_limit != null ? Number(data.credit_limit) : null
  return { exceeded: limit != null && balance > limit, balance, limit }
}



// ============ IBAN Validation (#80) ============
// A5 : la clé de contrôle est un validateur **pur** — elle vit dans
// `src/lib/iban.ts`, à côté de `looksLikeIBAN` (la forme, qui décide de
// bloquer), et elle est réexportée ici pour les appelants existants.
//
// Elle était écrite ici EN DOUBLE, sur deux fichiers : la 324 a ajouté la même
// clé de contrôle en base (`public.is_valid_iban`), et le contrôle d'écran
// était un second algorithme, susceptible de diverger de la base. Il n'y a
// plus qu'une règle, et elle est pure : donc testable, donc réutilisable.
export { validateIBAN, looksLikeIBAN, cleanIban } from '@/lib/iban'
