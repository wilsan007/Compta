// useDocumentPermissions — hook for checking document-level permissions

import { useAuth } from '@/lib/auth'
import type { ModuleName, ModuleRole, Confidentiality } from '@/types/documents'

export interface DocumentPermissions {
  canUpload: boolean
  canDownload: (confidentiality: Confidentiality) => boolean
  canEdit: boolean
  canDelete: boolean
  canApprove: boolean
  canReject: boolean
  canArchive: boolean
  canShare: boolean
  moduleRole: ModuleRole | null
  hasModuleAccess: boolean
}

export function useDocumentPermissions(module: ModuleName): DocumentPermissions {
  const { user } = useAuth()
  const userRole: string = user?.role || 'viewer'
  const moduleRoles = (user as any)?.module_roles || {}
  const moduleRole = moduleRoles[module] || null

  const hasModuleAccess = userRole === 'admin' || (moduleRole != null && moduleRole !== '')

  const canUpload = hasModuleAccess && (userRole === 'admin' || moduleRole !== 'guest')

  const canDownload = (confidentiality: Confidentiality): boolean => {
    if (!hasModuleAccess) return false
    if (userRole === 'admin') return true
    if (confidentiality === 'public') return true
    if (confidentiality === 'restricted') return moduleRole !== 'guest' || true // guests can download restricted
    if (confidentiality === 'confidential') {
      return ['project_director', 'hr_director', 'sales_director', 'accountant', 'auditor', 'treasurer'].includes(moduleRole)
    }
    if (confidentiality === 'private') {
      return userRole === 'admin'
    }
    return false
  }

  const canEdit = hasModuleAccess && (userRole === 'admin' || [
    'project_director', 'project_manager',
    'hr_director', 'hr_manager',
    'sales_director', 'sales_rep',
    'accountant', 'treasurer',
    'warehouse_manager', 'production_manager',
  ].includes(moduleRole))

  const canDelete = hasModuleAccess && (userRole === 'admin' || [
    'project_director', 'hr_director', 'sales_director',
    'accountant', 'treasurer', 'warehouse_manager', 'production_manager',
  ].includes(moduleRole))

  const canApprove = hasModuleAccess && (userRole === 'admin' || [
    'project_director', 'project_manager',
    'hr_director', 'hr_manager',
    'sales_director', 'sales_rep',
    'accountant', 'treasurer',
    'warehouse_manager', 'production_manager',
  ].includes(moduleRole))

  const canReject = canApprove
  const canArchive = canApprove
  const canShare = canEdit

  return {
    canUpload,
    canDownload,
    canEdit,
    canDelete,
    canApprove,
    canReject,
    canArchive,
    canShare,
    moduleRole,
    hasModuleAccess,
  }
}
