// ADM-01 + ADM-02 : Onboarding et rôles/permissions
import { supabase } from '@/lib/supabase'
import { getTenantId, ti } from './core'

// ============ ADM-01 : Onboarding ============

export interface OnboardingState {
  step_identity: boolean
  step_legislation: boolean
  step_fiscal_year: boolean
  step_chart_accounts: boolean
  step_journals: boolean
  step_default_accounts: boolean
  step_vat_rates: boolean
  step_payment_methods: boolean
  step_stock_valuation: boolean
  step_users: boolean
  completed: boolean
  completed_at: string | null
}

export async function getOnboardingState(): Promise<OnboardingState | null> {
  const tid = await getTenantId()
  const { data, error } = await supabase
    .from('tenant_onboarding_state')
    .select('*')
    .eq('tenant_id', tid)
    .maybeSingle()
  if (error) throw error
  return data as OnboardingState | null
}

export async function updateOnboardingStep(step: string, completed: boolean): Promise<void> {
  const tid = await getTenantId()
  const updates: Record<string, boolean | string> = { [step]: completed, updated_at: new Date().toISOString() }

  // Vérifier si toutes les étapes sont complètes
  if (completed) {
    const { data, error } = await supabase
      .from('tenant_onboarding_state')
      .select('*')
      .eq('tenant_id', tid)
      .maybeSingle()
    if (error) throw error

    if (data) {
      const allSteps = [
        'step_identity', 'step_legislation', 'step_fiscal_year',
        'step_chart_accounts', 'step_journals', 'step_default_accounts',
        'step_vat_rates', 'step_payment_methods', 'step_stock_valuation', 'step_users'
      ]
      const allComplete = allSteps.every(s => s === step || data[s] === true)
      if (allComplete) {
        updates.completed = true
        updates.completed_at = new Date().toISOString()
      }
    }
  }

  await supabase
    .from('tenant_onboarding_state')
    .upsert({ tenant_id: tid, ...updates })
}

export async function isOnboardingComplete(): Promise<boolean> {
  const { data, error } = await supabase.rpc('is_onboarding_complete')
  if (error) { console.error('isOnboardingComplete:', error); return false }
  return data as boolean
}

// ============ ADM-02 : Rôles et permissions ============

export interface TenantRole {
  id: string
  name: string
  description: string | null
  is_system: boolean
  is_active: boolean
}

export async function getTenantRoles(): Promise<TenantRole[]> {
  const tid = await getTenantId()
  const { data, error } = await supabase
    .from('tenant_roles')
    .select('*')
    .eq('tenant_id', tid)
    .eq('is_active', true)
    .order('name')
  if (error) throw error
  return data as TenantRole[]
}

export async function getRolePermissions(roleId: string): Promise<string[]> {
  const tid = await getTenantId()
  const { data, error } = await supabase
    .from('role_permissions')
    .select('permission')
    .eq('tenant_id', tid)
    .eq('role_id', roleId)
  if (error) throw error
  return (data || []).map((r: any) => r.permission)
}

export async function setRolePermission(roleId: string, permission: string): Promise<void> {
  const tid = await getTenantId()
  await supabase
    .from('role_permissions')
    .insert(ti({ role_id: roleId, permission }, 'role_permissions', tid))
}

export async function removeRolePermission(roleId: string, permission: string): Promise<void> {
  const tid = await getTenantId()
  await supabase
    .from('role_permissions')
    .delete()
    .eq('tenant_id', tid)
    .eq('role_id', roleId)
    .eq('permission', permission)
}

export async function hasPermission(permission: string): Promise<boolean> {
  const { data, error } = await supabase.rpc('has_permission', { p_permission: permission })
  if (error) { console.error('hasPermission:', error); return false }
  return data as boolean
}
