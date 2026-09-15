// Document Management System — Query functions
// CRUD + upload/download/approve with permission checks and audit trail

import { supabase } from '@/lib/supabase'
import { getTenantId, ti, tud } from '@/lib/queries/core'
import { validateFileUpload } from '@/lib/fileSecurity'
import type {
  ModuleDocument,
  DocumentAccessLog,
  DocumentShare,
  DocumentCreateInput,
  DocumentUpdateInput,
  ModuleName,
  Confidentiality,
  DocumentStatus,
  DocumentAccessAction,
} from '@/types/documents'
import { BUCKET_BY_MODULE } from '@/types/documents'

// ============ Helper: get current tenant user id ============

async function getCurrentTenantUserId(): Promise<string> {
  const { data: { session } } = await supabase.auth.getSession()
  if (!session) throw new Error('Not authenticated')
  const tid = await getTenantId()
  let q = supabase
    .from('tenant_users')
    .select('id')
    .eq('auth_id', session.user.id)
    .eq('status', 'active')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q.single()
  if (error || !data) throw new Error('Tenant user not found')
  return data.id
}

// ============ Helper: log access ============

async function logAccess(
  documentId: string,
  action: DocumentAccessAction,
  tid: string | null
): Promise<void> {
  try {
    const userId = await getCurrentTenantUserId()
    await supabase.from('module_document_access_log').insert(
      ti({
        document_id: documentId,
        user_id: userId,
        action,
      }, 'module_document_access_log', tid)
    )
  } catch (err) {
    console.error("catch:", err)
    // Best-effort logging — don't fail the operation
  }
}

// ============ Get Documents ============

export async function getDocuments(
  module: ModuleName,
  filters?: {
    documentType?: string
    entityType?: string
    entityId?: string
    status?: DocumentStatus
    confidentiality?: Confidentiality
    uploadedBy?: string
  }
): Promise<ModuleDocument[]> {
  const tid = await getTenantId()
  let q = supabase
    .from('module_documents')
    .select('*')
    .eq('module', module)
    .order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (filters?.documentType) q = q.eq('document_type', filters.documentType)
  if (filters?.entityType) q = q.eq('entity_type', filters.entityType)
  if (filters?.entityId) q = q.eq('entity_id', filters.entityId)
  if (filters?.status) q = q.eq('status', filters.status)
  if (filters?.confidentiality) q = q.eq('confidentiality', filters.confidentiality)
  if (filters?.uploadedBy) q = q.eq('uploaded_by', filters.uploadedBy)
  const { data, error } = await q
  if (error) throw error
  return (data || []) as ModuleDocument[]
}

export async function getDocumentById(id: string): Promise<ModuleDocument | null> {
  const tid = await getTenantId()
  let q = supabase.from('module_documents').select('*').eq('id', id)
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q.maybeSingle()
  if (error) throw error
  return data as ModuleDocument | null
}

// ============ Upload Document ============

const ALLOWED_MIME_TYPES = [
  'application/pdf',
  'image/png',
  'image/jpeg',
  'image/webp',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'application/msword',
  'application/vnd.ms-excel',
  'text/plain',
  'text/csv',
  'application/zip',
  'application/octet-stream',
]

const ALLOWED_EXTENSIONS = [
  '.pdf', '.png', '.jpg', '.jpeg', '.webp',
  '.docx', '.xlsx', '.pptx', '.doc', '.xls',
  '.txt', '.csv', '.zip',
]

const MAX_FILE_SIZE = 50 * 1024 * 1024 // 50 MB

export async function uploadDocument(
  file: File,
  input: DocumentCreateInput,
  entityId?: string | null
): Promise<ModuleDocument> {
  const tid = await getTenantId()
  if (!tid) throw new Error('No active tenant')

  // Validate file
  const validation = await validateFileUpload(file, {
    maxSize: MAX_FILE_SIZE,
    allowedMimeTypes: ALLOWED_MIME_TYPES,
    allowedExtensions: ALLOWED_EXTENSIONS,
    checkMagicBytes: true,
  })
  if (!validation.ok || !validation.sanitizedFilename) {
    throw new Error(validation.error || 'File validation failed')
  }

  const safeName = validation.sanitizedFilename
  const userId = await getCurrentTenantUserId()
  const bucket = BUCKET_BY_MODULE[input.module]
  const entityPart = entityId || input.entity_id || 'general'
  const filePath = `${tid}/${entityPart}/${Date.now()}-${safeName}`

  // Upload to Storage
  const { error: uploadError } = await supabase.storage
    .from(bucket)
    .upload(filePath, file, {
      cacheControl: '3600',
      upsert: false,
    })
  if (uploadError) throw uploadError

  // Compute SHA-256 hash
  const arrayBuffer = await file.arrayBuffer()
  const hashBuffer = await crypto.subtle.digest('SHA-256', arrayBuffer)
  const fileHash = Array.from(new Uint8Array(hashBuffer))
    .map(b => b.toString(16).padStart(2, '0'))
    .join('')

  // Insert DB record
  const payload = ti({
    module: input.module,
    document_type: input.document_type,
    confidentiality: input.confidentiality,
    entity_type: input.entity_type || null,
    entity_id: input.entity_id || entityId || null,
    title: input.title,
    description: input.description || null,
    file_url: filePath,
    file_name: safeName,
    file_size: file.size,
    mime_type: file.type,
    file_hash: fileHash,
    status: 'pending',
    uploaded_by: userId,
    metadata: input.metadata || {},
    expires_at: input.expires_at || null,
  }, 'module_documents', tid)

  const { data, error } = await supabase
    .from('module_documents')
    .insert(payload)
    .select()
    .single()
  if (error) {
    // Cleanup: delete uploaded file if DB insert failed
    await supabase.storage.from(bucket).remove([filePath])
    throw error
  }

  // Log access
  await logAccess(data.id, 'upload', tid)

  return data as ModuleDocument
}

// ============ Download Document ============

export async function getDocumentDownloadUrl(doc: ModuleDocument): Promise<string> {
  const tid = await getTenantId()
  const bucket = BUCKET_BY_MODULE[doc.module]
  const { data, error } = await supabase.storage
    .from(bucket)
    .createSignedUrl(doc.file_url, 60) // 60 seconds signed URL
  if (error || !data) throw error || new Error('Failed to create download URL')

  // Log access + increment download count
  await logAccess(doc.id, 'download', tid)
  await tud(
    supabase.rpc('increment_download_count', { doc_id: doc.id }),
    'module_documents',
    tid
  ).then(() => {}, () => {}) // best-effort

  return data.signedUrl
}

// ============ Preview Document (signed URL without incrementing count) ============

export async function getDocumentPreviewUrl(doc: ModuleDocument): Promise<string> {
  const bucket = BUCKET_BY_MODULE[doc.module]
  const { data, error } = await supabase.storage
    .from(bucket)
    .createSignedUrl(doc.file_url, 300) // 5 minutes for preview
  if (error || !data) throw error || new Error('Failed to create preview URL')
  await logAccess(doc.id, 'preview', await getTenantId())
  return data.signedUrl
}

// ============ Update Document ============

export async function updateDocument(
  id: string,
  updates: DocumentUpdateInput
): Promise<ModuleDocument> {
  const tid = await getTenantId()
  const { data, error } = await tud(
    supabase.from('module_documents').update(updates),
    'module_documents',
    tid
  )
    .eq('id', id)
    .select()
    .single()
  if (error) throw error
  return data as ModuleDocument
}

// ============ Approve Document ============

export async function approveDocument(id: string): Promise<ModuleDocument> {
  const tid = await getTenantId()
  const userId = await getCurrentTenantUserId()
  const { data, error } = await tud(
    supabase.from('module_documents').update({
      status: 'approved',
      approved_by: userId,
      approved_at: new Date().toISOString(),
      rejection_reason: null,
    }),
    'module_documents',
    tid
  )
    .eq('id', id)
    .select()
    .single()
  if (error) throw error
  await logAccess(id, 'approve', tid)
  return data as ModuleDocument
}

// ============ Reject Document ============

export async function rejectDocument(id: string, reason: string): Promise<ModuleDocument> {
  const tid = await getTenantId()
  const userId = await getCurrentTenantUserId()
  const { data, error } = await tud(
    supabase.from('module_documents').update({
      status: 'rejected',
      approved_by: userId,
      approved_at: new Date().toISOString(),
      rejection_reason: reason,
    }),
    'module_documents',
    tid
  )
    .eq('id', id)
    .select()
    .single()
  if (error) throw error
  await logAccess(id, 'reject', tid)
  return data as ModuleDocument
}

// ============ Archive Document ============

export async function archiveDocument(id: string): Promise<ModuleDocument> {
  const tid = await getTenantId()
  const { data, error } = await tud(
    supabase.from('module_documents').update({
      status: 'archived',
      archived_at: new Date().toISOString(),
    }),
    'module_documents',
    tid
  )
    .eq('id', id)
    .select()
    .single()
  if (error) throw error
  await logAccess(id, 'archive', tid)
  return data as ModuleDocument
}

// ============ Delete Document ============

export async function deleteDocument(id: string): Promise<void> {
  const tid = await getTenantId()
  // Get doc to find file path + bucket
  const doc = await getDocumentById(id)
  if (!doc) throw new Error('Document not found')

  const bucket = BUCKET_BY_MODULE[doc.module]
  // Delete from storage
  const { error: storageError } = await supabase.storage
    .from(bucket)
    .remove([doc.file_url])
  if (storageError) throw storageError

  // Delete from DB
  const { error } = await tud(
    supabase.from('module_documents').delete(),
    'module_documents',
    tid
  ).eq('id', id)
  if (error) throw error
  await logAccess(id, 'delete', tid)
}

// ============ Share Document ============

export async function createDocumentShare(
  documentId: string,
  options?: { password?: string; expiresAt?: string; maxDownloads?: number }
): Promise<DocumentShare> {
  const tid = await getTenantId()
  const userId = await getCurrentTenantUserId()
  const shareToken = crypto.randomUUID()

  let passwordHash: string | null = null
  if (options?.password) {
    const encoder = new TextEncoder()
    const hashBuffer = await crypto.subtle.digest('SHA-256', encoder.encode(options.password))
    passwordHash = Array.from(new Uint8Array(hashBuffer))
      .map(b => b.toString(16).padStart(2, '0'))
      .join('')
  }

  const payload = ti({
    document_id: documentId,
    share_token: shareToken,
    password_hash: passwordHash,
    created_by: userId,
    expires_at: options?.expiresAt || null,
    max_downloads: options?.maxDownloads || null,
  }, 'module_document_shares', tid)

  const { data, error } = await supabase
    .from('module_document_shares')
    .insert(payload)
    .select()
    .single()
  if (error) throw error
  await logAccess(documentId, 'share', tid)
  return data as DocumentShare
}

// ============ Get Access Logs ============

export async function getDocumentAccessLogs(documentId: string): Promise<DocumentAccessLog[]> {
  const tid = await getTenantId()
  let q = supabase
    .from('module_document_access_log')
    .select('*')
    .eq('document_id', documentId)
    .order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return (data || []) as DocumentAccessLog[]
}

// ============ Get Document Stats ============

export async function getDocumentStats(module: ModuleName): Promise<{
  total: number
  pending: number
  approved: number
  rejected: number
  archived: number
  byType: Record<string, number>
  byConfidentiality: Record<string, number>
}> {
  const tid = await getTenantId()
  let q = supabase
    .from('module_documents')
    .select('document_type, confidentiality, status')
    .eq('module', module)
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  if (!data) return { total: 0, pending: 0, approved: 0, rejected: 0, archived: 0, byType: {}, byConfidentiality: {} }

  const byType: Record<string, number> = {}
  const byConfidentiality: Record<string, number> = {}
  for (const doc of data) {
    byType[doc.document_type] = (byType[doc.document_type] || 0) + 1
    byConfidentiality[doc.confidentiality] = (byConfidentiality[doc.confidentiality] || 0) + 1
  }
  return {
    total: data.length,
    pending: data.filter(d => d.status === 'pending').length,
    approved: data.filter(d => d.status === 'approved').length,
    rejected: data.filter(d => d.status === 'rejected').length,
    archived: data.filter(d => d.status === 'archived').length,
    byType,
    byConfidentiality,
  }
}
