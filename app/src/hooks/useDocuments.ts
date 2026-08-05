// useDocuments — hook for fetching, filtering, and managing documents
// with role-based filtering based on module_roles and confidentiality

import { useState, useEffect, useCallback, useMemo } from 'react'
import { useAuth } from '@/lib/auth'
import {
  getDocuments,
  uploadDocument,
  updateDocument,
  deleteDocument,
  approveDocument,
  rejectDocument,
  archiveDocument,
  getDocumentDownloadUrl,
  getDocumentPreviewUrl,
} from '@/lib/queries/documents'
import type {
  ModuleDocument,
  DocumentCreateInput,
  DocumentUpdateInput,
  ModuleName,
  Confidentiality,
  DocumentStatus,
} from '@/types/documents'

export interface UseDocumentsFilters {
  documentType?: string
  entityType?: string
  entityId?: string
  status?: DocumentStatus
  confidentiality?: Confidentiality
}

export interface UseDocumentsReturn {
  documents: ModuleDocument[]
  loading: boolean
  error: string | null
  refetch: () => void
  upload: (file: File, input: DocumentCreateInput, entityId?: string | null) => Promise<ModuleDocument>
  update: (id: string, updates: DocumentUpdateInput) => Promise<ModuleDocument>
  remove: (id: string) => Promise<void>
  approve: (id: string) => Promise<ModuleDocument>
  reject: (id: string, reason: string) => Promise<ModuleDocument>
  archive: (id: string) => Promise<ModuleDocument>
  download: (doc: ModuleDocument) => Promise<void>
  preview: (doc: ModuleDocument) => Promise<string>
  canUpload: boolean
  canApprove: boolean
  canDelete: boolean
  canEdit: boolean
  visibleDocuments: ModuleDocument[]
}

const APPROVER_ROLES = [
  'admin',
  'project_director',
  'project_manager',
  'hr_director',
  'hr_manager',
  'sales_director',
  'accountant',
  'treasurer',
  'warehouse_manager',
  'production_manager',
]

const DELETER_ROLES = [
  'admin',
  'project_director',
  'hr_director',
  'sales_director',
  'accountant',
  'treasurer',
  'warehouse_manager',
  'production_manager',
]

const EDITOR_ROLES = [
  'admin',
  'project_director',
  'project_manager',
  'hr_director',
  'hr_manager',
  'sales_director',
  'sales_rep',
  'accountant',
  'treasurer',
  'warehouse_manager',
  'production_manager',
]

export function useDocuments(
  module: ModuleName,
  filters?: UseDocumentsFilters
): UseDocumentsReturn {
  const { user } = useAuth()
  const [documents, setDocuments] = useState<ModuleDocument[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const userRole = user?.role || 'viewer'
  const moduleRoles = (user as any)?.module_roles || {}
  const currentModuleRole = moduleRoles[module] || null
  const guestPermissions = (user as any)?.guest_permissions || null

  const fetchDocuments = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const data = await getDocuments(module, filters)
      setDocuments(data)
    } catch (err: any) {
      setError(err.message || 'Failed to fetch documents')
    } finally {
      setLoading(false)
    }
  }, [module, JSON.stringify(filters)])

  useEffect(() => {
    fetchDocuments()
  }, [fetchDocuments])

  // Filter documents based on role + confidentiality
  const visibleDocuments = useMemo(() => {
    if (userRole === 'admin') return documents

    return documents.filter(doc => {
      // Guest: only see public + restricted on their projects
      if (currentModuleRole === 'guest') {
        if (doc.confidentiality === 'confidential' || doc.confidentiality === 'private') return false
        if (guestPermissions?.projectIds?.length > 0) {
          if (!guestPermissions.projectIds.includes(doc.entity_id)) return false
        }
        return true
      }

      // Consultant: only see documents on their tasks
      if (currentModuleRole === 'consultant') {
        if (doc.confidentiality === 'confidential' || doc.confidentiality === 'private') return false
        return true // RLS + app-level will further filter by task assignment
      }

      // Team member / hr_employee / sales_employee: no confidential/private from others
      if (['team_member', 'hr_employee', 'sales_employee', 'stock_clerk', 'production_operator'].includes(currentModuleRole)) {
        if (doc.confidentiality === 'confidential' || doc.confidentiality === 'private') {
          // Can see their own confidential/private docs
          return doc.uploaded_by === (user as any)?.id
        }
        return true
      }

      // Managers/directors: see everything in their module
      return true
    })
  }, [documents, userRole, currentModuleRole, guestPermissions, user])

  // Permission checks
  const canUpload = userRole === 'admin' || (currentModuleRole && currentModuleRole !== 'guest')
  const canApprove = userRole === 'admin' || APPROVER_ROLES.includes(currentModuleRole)
  const canDelete = userRole === 'admin' || DELETER_ROLES.includes(currentModuleRole)
  const canEdit = userRole === 'admin' || EDITOR_ROLES.includes(currentModuleRole)

  // Mutations
  const upload = useCallback(async (file: File, input: DocumentCreateInput, entityId?: string | null) => {
    const doc = await uploadDocument(file, input, entityId)
    setDocuments(prev => [doc, ...prev])
    return doc
  }, [])

  const update = useCallback(async (id: string, updates: DocumentUpdateInput) => {
    const doc = await updateDocument(id, updates)
    setDocuments(prev => prev.map(d => (d.id === id ? doc : d)))
    return doc
  }, [])

  const remove = useCallback(async (id: string) => {
    await deleteDocument(id)
    setDocuments(prev => prev.filter(d => d.id !== id))
  }, [])

  const approve = useCallback(async (id: string) => {
    const doc = await approveDocument(id)
    setDocuments(prev => prev.map(d => (d.id === id ? doc : d)))
    return doc
  }, [])

  const reject = useCallback(async (id: string, reason: string) => {
    const doc = await rejectDocument(id, reason)
    setDocuments(prev => prev.map(d => (d.id === id ? doc : d)))
    return doc
  }, [])

  const archive = useCallback(async (id: string) => {
    const doc = await archiveDocument(id)
    setDocuments(prev => prev.map(d => (d.id === id ? doc : d)))
    return doc
  }, [])

  const download = useCallback(async (doc: ModuleDocument) => {
    const url = await getDocumentDownloadUrl(doc)
    const a = window.document.createElement('a')
    a.href = url
    a.download = doc.file_name
    a.target = '_blank'
    window.document.body.appendChild(a)
    a.click()
    window.document.body.removeChild(a)
  }, [])

  const preview = useCallback(async (doc: ModuleDocument) => {
    return await getDocumentPreviewUrl(doc)
  }, [])

  return {
    documents,
    loading,
    error,
    refetch: fetchDocuments,
    upload,
    update,
    remove,
    approve,
    reject,
    archive,
    download,
    preview,
    canUpload,
    canApprove,
    canDelete,
    canEdit,
    visibleDocuments,
  }
}
