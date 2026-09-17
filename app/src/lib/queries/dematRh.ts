import { supabase } from '../supabase'
import type { Joined } from '@/types/dbRow'
import { getTenantId, ti, tud } from './core'
import { sanitizeFilename } from '@/lib/fileSecurity'
import type { EmployeeDocument, DocumentDistributionLog, RhRequest, RhKnowledgeBaseArticle } from '@/types'

// ============ Employee Documents ============
export async function getEmployeeDocuments(employeeId: string): Promise<EmployeeDocument[]> {
  const tid = await getTenantId()
  let q = supabase.from('employee_documents').select('*').eq('employee_id', employeeId).order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as EmployeeDocument[]
}

export async function getMyDocuments(): Promise<EmployeeDocument[]> {
  const tid = await getTenantId()
  const { data: userData, error } = await supabase.auth.getUser()
  if (error) throw error
  if (!userData?.user) throw new Error('Not authenticated')
  let empQ = supabase.from('employees').select('id').eq('auth_user_id', userData.user.id)
  if (tid) empQ = empQ.eq('tenant_id', tid)
  const { data: emp, error: empError } = await empQ.single()
  if (empError || !emp) throw new Error('Employee not found')
  return getEmployeeDocuments(emp.id)
}

export async function uploadEmployeeDocument(employeeId: string, file: File, metadata: Partial<EmployeeDocument>): Promise<EmployeeDocument> {
  const tid = await getTenantId()
  const safeName = sanitizeFilename(file.name)
  const fileName = `${employeeId}/${metadata.document_type}/${Date.now()}-${safeName}`
  const { data: uploadData, error: uploadError } = await supabase.storage.from('employee-documents').upload(fileName, file)
  if (uploadError) throw uploadError
  const { data: row, error } = await supabase.from('employee_documents').insert(ti({
    employee_id: employeeId,
    document_type: metadata.document_type || 'other',
    title: metadata.title || file.name,
    file_url: uploadData.path,
    file_size: file.size,
    mime_type: file.type,
    period: metadata.period || null,
    uploaded_by: (await supabase.auth.getUser()).data?.user?.email || null,
    visible_to_employee: metadata.visible_to_employee ?? true,
    requires_acknowledgment: metadata.requires_acknowledgment ?? false,
    acknowledged: false,
    e_signed: false,
    archived: false,
    retention_years: 10,
  }, 'employee_documents', tid)).select().single()
  if (error) throw error
  return row as EmployeeDocument
}

export async function deleteEmployeeDocument(id: string): Promise<void> {
  const { error } = await supabase.from('employee_documents').delete().eq('id', id)
  if (error) throw error
}

export async function acknowledgeDocument(id: string): Promise<void> {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('employee_documents').update({
    acknowledged: true,
    acknowledged_at: new Date().toISOString(),
  }), 'employee_documents', tid).eq('id', id)
  if (error) throw error
}

export async function bulkUploadDocuments(files: File[], documentType: string, employeeIds?: string[]): Promise<void> {
  for (const file of files) {
    if (employeeIds && employeeIds.length > 0) {
      for (const empId of employeeIds) {
        await uploadEmployeeDocument(empId, file, { document_type: documentType as any, title: file.name })
      }
    }
  }
}

// ============ Distribution ============
export async function distributePaySlips(payRunId: string): Promise<DocumentDistributionLog[]> {
  const tid = await getTenantId()
  const batchId = crypto.randomUUID()
  let slipQ = supabase.from('pay_slips').select('*, employees(id, name)').eq('pay_run_id', payRunId)
  if (tid) slipQ = slipQ.eq('tenant_id', tid)
  const { data: payslips, error } = await slipQ
  if (error) throw error
  if (!payslips) return []
  const logs: DocumentDistributionLog[] = []
  for (const slip of payslips) {
    const { data: doc, error: docError } = await supabase.from('employee_documents').insert(ti({
      employee_id: slip.employee_id,
      document_type: 'payslip',
      title: `Bulletin de paie ${slip.period || ''}`,
      file_url: slip.file_url || '',
      period: slip.period,
      visible_to_employee: true,
      requires_acknowledgment: true,
      acknowledged: false,
      e_signed: false,
      archived: false,
      retention_years: 50,
    }, 'employee_documents', tid)).select().single()
    if (docError) continue
    const { data: logRow, error } = await supabase.from('document_distribution_logs').insert(ti({
      batch_id: batchId,
      employee_document_id: doc.id,
      employee_id: slip.employee_id,
      document_type: 'payslip',
      period: slip.period,
      distributed_at: new Date().toISOString(),
      status: 'distributed',
    }, 'document_distribution_logs', tid)).select().single()
    if (error) { console.error('distributePaySlips:', error); continue }
    if (logRow) logs.push(logRow as DocumentDistributionLog)
  }
  return logs
}

export async function controlBatchBeforeDiffusion(payRunId: string): Promise<{ ok: boolean; issues: string[]; recipientCount: number }> {
  const tid = await getTenantId()
  // LOT7-04 : `pay_slips` n'a pas de colonne `period` (mais `period_start` / `period_end`).
  // PostgREST renvoyait 400/42703 : le contrôle avant diffusion des bulletins échouait
  // systématiquement. Vérifié sur PostgREST 16.3.
  let q = supabase.from('pay_slips').select('id, employee_id, period_start, period_end, employees(name)').eq('pay_run_id', payRunId)
  if (tid) q = q.eq('tenant_id', tid)
  const { data: payslips, error } = await q
  if (error) throw error
  const issues: string[] = []
  if (!payslips || payslips.length === 0) {
    issues.push('Aucun bulletin dans ce lot')
    return { ok: false, issues, recipientCount: 0 }
  }
  const empIds = payslips.map(p => p.employee_id)
  const uniqueEmpIds = [...new Set(empIds)]
  if (empIds.length !== uniqueEmpIds.length) {
    issues.push('Doublons détectés: certains employés ont plusieurs bulletins')
  }
  for (const slip of payslips) {
    if (!(slip as any).file_url) {
      issues.push(`Bulletin manquant pour ${(slip as any).employees?.name || slip.employee_id}`)
    }
  }
  return { ok: issues.length === 0, issues, recipientCount: uniqueEmpIds.length }
}

export async function getDistributionLogs(batchId?: string): Promise<DocumentDistributionLog[]> {
  const tid = await getTenantId()
  let q = supabase.from('document_distribution_logs').select('*, employees(name)').order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (batchId) q = q.eq('batch_id', batchId)
  const { data, error } = await q
  if (error) throw error
  return data as DocumentDistributionLog[]
}

export async function sendDistributionReminders(batchId: string): Promise<void> {
  const tid = await getTenantId()
  let q = supabase.from('document_distribution_logs')
    .update({ status: 'reminder_sent' })
    .eq('batch_id', batchId)
    .eq('status', 'pending')
  if (tid) q = q.eq('tenant_id', tid)
  const { error } = await q
  if (error) throw error
}

// ============ e-Signature ============
export async function requestESignature(documentId: string, _employeeId: string): Promise<void> {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('employee_documents').update({
    e_signed: false,
  }), 'employee_documents', tid).eq('id', documentId)
  if (error) throw error
}

export async function signRhDocument(documentId: string): Promise<void> {
  const tid = await getTenantId()
  const { data: doc, error: docError } = await supabase.from('employee_documents').select('file_url').eq('id', documentId).single()
  if (docError) throw docError
  const hash = doc ? btoa(doc.file_url + Date.now()) : 'unknown'
  const { error } = await tud(supabase.from('employee_documents').update({
    e_signed: true,
    e_signed_at: new Date().toISOString(),
    e_signature_hash: hash,
  }), 'employee_documents', tid).eq('id', documentId)
  if (error) throw error
}

// ============ Document Stats ============
export async function getDocumentStats(): Promise<{ total: number; distributed: number; acknowledged: number; signed: number; byType: Record<string, number> }> {
  const tid = await getTenantId()
  let q = supabase.from('employee_documents').select('document_type, acknowledged, e_signed, distributed_at')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  if (!data) return { total: 0, distributed: 0, acknowledged: 0, signed: 0, byType: {} }
  const byType: Record<string, number> = {}
  for (const doc of data) {
    byType[doc.document_type] = (byType[doc.document_type] || 0) + 1
  }
  return {
    total: data.length,
    distributed: data.filter(d => d.distributed_at).length,
    acknowledged: data.filter(d => d.acknowledged).length,
    signed: data.filter(d => d.e_signed).length,
    byType,
  }
}

// ============ RH Requests ============
export async function getRhRequests(status?: string, type?: string): Promise<(RhRequest & { employees: Joined<'employees', 'name'> })[]> {
  const tid = await getTenantId()
  let q = supabase.from('rh_requests').select('*, employees(name)').order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (status) q = q.eq('status', status)
  if (type) q = q.eq('request_type', type)
  const { data, error } = await q
  if (error) throw error
  return data as (RhRequest & { employees: Joined<'employees', 'name'> })[]
}

export async function createRhRequest(data: Omit<RhRequest, 'id' | 'created_at'>): Promise<RhRequest> {
  const tid = await getTenantId()
  const { data: row, error } = await supabase.from('rh_requests').insert(ti(data, 'rh_requests', tid)).select().single()
  if (error) throw error
  return row as RhRequest
}

export async function updateRhRequest(id: string, updates: Partial<RhRequest>): Promise<RhRequest> {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('rh_requests').update(updates), 'rh_requests', tid).eq('id', id).select().single()
  if (error) throw error
  return data as RhRequest
}

export async function assignRhRequest(id: string, assignedTo: string): Promise<RhRequest> {
  return updateRhRequest(id, { assigned_to: assignedTo, status: 'in_progress' })
}

export async function resolveRhRequest(id: string, response: string): Promise<RhRequest> {
  return updateRhRequest(id, { response, status: 'resolved', resolved_at: new Date().toISOString() })
}

// ============ Knowledge Base ============
export async function getRhKnowledgeBase(category?: string, search?: string): Promise<RhKnowledgeBaseArticle[]> {
  const tid = await getTenantId()
  let q = supabase.from('rh_knowledge_base').select('*').order('updated_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (category) q = q.eq('category', category)
  if (search) {
    const s = search.replace(/[,%.]/g, ' ').trim().slice(0, 100)
    if (s) q = q.or(`title.ilike.%${s}%,content.ilike.%${s}%`)
  }
  const { data, error } = await q
  if (error) throw error
  return data as RhKnowledgeBaseArticle[]
}

export async function createRhKnowledgeBaseArticle(data: Omit<RhKnowledgeBaseArticle, 'id' | 'created_at' | 'updated_at'>): Promise<RhKnowledgeBaseArticle> {
  const tid = await getTenantId()
  const { data: row, error } = await supabase.from('rh_knowledge_base').insert(ti(data, 'rh_knowledge_base', tid)).select().single()
  if (error) throw error
  return row as RhKnowledgeBaseArticle
}

export async function updateRhKnowledgeBaseArticle(id: string, updates: Partial<RhKnowledgeBaseArticle>): Promise<RhKnowledgeBaseArticle> {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('rh_knowledge_base').update({ ...updates, updated_at: new Date().toISOString() }), 'rh_knowledge_base', tid).eq('id', id).select().single()
  if (error) throw error
  return data as RhKnowledgeBaseArticle
}

export async function deleteRhKnowledgeBaseArticle(id: string): Promise<void> {
  const tid = await getTenantId()
  let q = supabase.from('rh_knowledge_base').delete().eq('id', id)
  if (tid) q = q.eq('tenant_id', tid)
  const { error } = await q
  if (error) throw error
}

export async function incrementArticleViews(id: string): Promise<void> {
  const tid = await getTenantId()
  const { data: article, error } = await supabase.from('rh_knowledge_base').select('views').eq('id', id).eq('tenant_id', tid || '').single()
  if (error) { console.error('incrementArticleViews:', error); return }
  if (article) {
    await supabase.from('rh_knowledge_base').update({ views: (article.views || 0) + 1 }).eq('id', id).eq('tenant_id', tid || '')
  }
}
