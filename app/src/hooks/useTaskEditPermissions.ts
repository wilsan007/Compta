import { useAuth } from '@/lib/auth'

export type TaskPermission = 'create' | 'edit' | 'delete' | 'assign' | 'changeStatus' | 'changePriority'

interface UseTaskEditPermissionsReturn {
  can: (permission: TaskPermission) => boolean
  role: string
}

export function useTaskEditPermissions(): UseTaskEditPermissionsReturn {
  const { user } = useAuth()
  const globalRole: string = (user as any)?.role || 'viewer'
  const moduleRoles = (user as any)?.module_roles || {}
  const pmRole: string = moduleRoles.projectManagement || globalRole

  const can = (permission: TaskPermission): boolean => {
    // Global admin: full access
    if (globalRole === 'admin') return true

    // Module-based RBAC for projectManagement
    switch (pmRole) {
      case 'project_director':
        return true
      case 'project_manager':
        return ['create', 'edit', 'delete', 'assign', 'changeStatus', 'changePriority'].includes(permission)
      case 'team_member':
        return ['edit', 'changeStatus'].includes(permission)
      case 'consultant':
        return ['edit', 'changeStatus'].includes(permission)
      case 'guest':
        return false
      // Fallback to legacy global roles
      case 'manager':
        return ['create', 'edit', 'delete', 'assign', 'changeStatus', 'changePriority'].includes(permission)
      case 'employee':
        return ['edit', 'changeStatus'].includes(permission)
      default:
        return false
    }
  }

  return { can, role: pmRole }
}
