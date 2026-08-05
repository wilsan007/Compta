import type { ModuleRole } from '@/types/documents'

export type ModuleName = 'projectManagement' | 'accounting' | 'hr' | 'commercial' | 'treasury' | 'stock' | 'production'

export interface ModuleRoleOption {
  value: ModuleRole
  labelKey: string
}

export const MODULE_ROLE_OPTIONS: { module: ModuleName; roles: ModuleRoleOption[] }[] = [
  {
    module: 'projectManagement',
    roles: [
      { value: 'project_director', labelKey: 'hr:team.moduleRoles.project_director' },
      { value: 'project_manager', labelKey: 'hr:team.moduleRoles.project_manager' },
      { value: 'team_member', labelKey: 'hr:team.moduleRoles.team_member' },
      { value: 'consultant', labelKey: 'hr:team.moduleRoles.consultant' },
      { value: 'guest', labelKey: 'hr:team.moduleRoles.guest' },
    ],
  },
  {
    module: 'accounting',
    roles: [
      { value: 'accountant', labelKey: 'hr:team.moduleRoles.accountant' },
      { value: 'auditor', labelKey: 'hr:team.moduleRoles.auditor' },
      { value: 'custom', labelKey: 'hr:team.moduleRoles.custom' },
    ],
  },
  {
    module: 'hr',
    roles: [
      { value: 'hr_director', labelKey: 'hr:team.moduleRoles.hr_director' },
      { value: 'hr_manager', labelKey: 'hr:team.moduleRoles.hr_manager' },
      { value: 'hr_employee', labelKey: 'hr:team.moduleRoles.hr_employee' },
    ],
  },
  {
    module: 'commercial',
    roles: [
      { value: 'sales_director', labelKey: 'hr:team.moduleRoles.sales_director' },
      { value: 'sales_rep', labelKey: 'hr:team.moduleRoles.sales_rep' },
      { value: 'sales_employee', labelKey: 'hr:team.moduleRoles.sales_employee' },
    ],
  },
  {
    module: 'treasury',
    roles: [
      { value: 'treasurer', labelKey: 'hr:team.moduleRoles.treasurer' },
      { value: 'treasury_viewer', labelKey: 'hr:team.moduleRoles.treasury_viewer' },
    ],
  },
  {
    module: 'stock',
    roles: [
      { value: 'warehouse_manager', labelKey: 'hr:team.moduleRoles.warehouse_manager' },
      { value: 'stock_clerk', labelKey: 'hr:team.moduleRoles.stock_clerk' },
    ],
  },
  {
    module: 'production',
    roles: [
      { value: 'production_manager', labelKey: 'hr:team.moduleRoles.production_manager' },
      { value: 'production_operator', labelKey: 'hr:team.moduleRoles.production_operator' },
    ],
  },
]

export function getModuleRoles(module: ModuleName): ModuleRoleOption[] {
  const entry = MODULE_ROLE_OPTIONS.find(m => m.module === module)
  return entry?.roles || []
}

export function getEnabledModuleRoleOptions(enabledModules: string[]): { module: ModuleName; roles: ModuleRoleOption[] }[] {
  return MODULE_ROLE_OPTIONS.filter(m => enabledModules.includes(m.module))
}
