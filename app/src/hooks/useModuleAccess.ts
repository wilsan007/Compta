// useModuleAccess — hook for checking module-level access and roles
// Used by navigation, page guards, and feature toggles

import { useAuth } from '@/lib/auth'
import type { ModuleName, ModuleRole, GuestPermissions } from '@/types/documents'

export interface ModuleAccessInfo {
  hasAccess: boolean
  role: ModuleRole | null
  isAdmin: boolean
  isGuest: boolean
  isConsultant: boolean
  isManager: boolean
  isDirector: boolean
  canView: boolean
  canCreate: boolean
  canEdit: boolean
  canDelete: boolean
  canApprove: boolean
  guestPermissions: GuestPermissions | null
}

const MANAGER_ROLES: ModuleRole[] = [
  'project_manager', 'hr_manager', 'sales_rep',
  'accountant', 'treasurer', 'warehouse_manager', 'production_manager',
]

const DIRECTOR_ROLES: ModuleRole[] = [
  'project_director', 'hr_director', 'sales_director',
]

export function useModuleAccess(module: ModuleName): ModuleAccessInfo {
  const { user } = useAuth()
  const userRole: string = user?.role || 'viewer'
  const moduleRoles = (user as any)?.module_roles || {}
  const role: ModuleRole | null = moduleRoles[module] || null
  const guestPermissions: GuestPermissions | null = (user as any)?.guest_permissions || null

  const isAdmin = userRole === 'admin'
  const hasAccess = isAdmin || (role != null && String(role) !== '')
  const isGuest = role === 'guest'
  const isConsultant = role === 'consultant'
  const isManager = MANAGER_ROLES.includes(role as ModuleRole)
  const isDirector = DIRECTOR_ROLES.includes(role as ModuleRole)

  const canView = hasAccess
  const canCreate = hasAccess && (isAdmin || (!isGuest))
  const canEdit = hasAccess && (isAdmin || isManager || isDirector)
  const canDelete = hasAccess && (isAdmin || isDirector)
  const canApprove = hasAccess && (isAdmin || isManager || isDirector)

  return {
    hasAccess,
    role,
    isAdmin,
    isGuest,
    isConsultant,
    isManager,
    isDirector,
    canView,
    canCreate,
    canEdit,
    canDelete,
    canApprove,
    guestPermissions,
  }
}

export function useHasModuleAccess(module: ModuleName): boolean {
  return useModuleAccess(module).hasAccess
}

export function useModuleRole(module: ModuleName): ModuleRole | null {
  return useModuleAccess(module).role
}
