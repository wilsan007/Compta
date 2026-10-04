// ============================================================================
// misc — multiTenant.ts
// Extrait de l'ancien misc.ts le 2026-10-01 ; imports recalcules ;
// aucun code metier modifie.
// ============================================================================

import { supabase } from '@/lib/supabase'
import { getTenantId } from '../core'

// ============ Multi-Tenant Management ============

export interface Tenant {
  id: string
  name: string
  legal_name: string | null
  siren: string | null
  siret: string | null
  vat_number: string | null
  address: string | null
  city: string | null
  postal_code: string | null
  country: string
  currency: string
  phone: string | null
  email: string | null
  logo_url: string | null
  status: string
  plan: string
  trial_ends_at: string | null
  enabled_modules: string[]
  created_at: string
  legislation_pack_code?: string | null
}

export interface TenantUser {
  id: string
  tenant_id: string
  auth_id: string | null
  email: string
  name: string
  role: 'admin' | 'accountant' | 'manager' | 'viewer' | 'custom' | 'auditor'
  permissions: Record<string, string[]>
  module_roles?: Record<string, string>
  guest_permissions?: Record<string, any>
  status: 'pending' | 'active' | 'revoked'
  invited_by: string | null
  invited_at: string
  accepted_at: string | null
  last_login: string | null
  created_at: string
  valid_from: string | null
  valid_until: string | null
}

type CreateTenantData = {
  name: string
  legal_name?: string | null
  siren?: string | null
  siret?: string | null
  vat_number?: string | null
  address?: string | null
  city?: string | null
  postal_code?: string | null
  country?: string | null
  currency?: string | null
  email?: string | null
  phone?: string | null
  legislation_pack_code?: string | null
  enabled_modules?: string[]
  plan?: string | null
  trial_ends_at?: string | null
}

// AUD-B02 : la création d'une société passe par la RPC atomique
// create_tenant_for_current_user — société, administrateur, fiche salarié, plan
// comptable, journaux, exercice et paramètres dans une seule transaction.
// L'ancien enchaînement d'insertions côté client était refusé par la RLS de
// `tenants`, et l'échec de bootstrap_tenant n'était que journalisé.
async function createTenantViaRpc(payload: CreateTenantData): Promise<{ success: boolean; error?: string; tenant?: Tenant; tenantId?: string }> {
  const { data: { session } } = await supabase.auth.getSession()
  if (!session) return { success: false, error: 'Non connecté' }

  const { data, error } = await supabase.rpc('create_tenant_for_current_user', { p_data: payload })
  if (error) return { success: false, error: error.message }
  const res = data as { success?: boolean; error?: string; tenant_id?: string; tenant?: Tenant } | null
  if (!res || res.success !== true) {
    return { success: false, error: res?.error || 'Création de la société impossible' }
  }
  // L'identifiant est rendu à l'appelant : l'écran doit pouvoir rendre la société
  // créée ACTIVE avant toute lecture (cf. OnboardingPage, W-QA 29/09/2026).
  return { success: true, tenant: res.tenant, tenantId: res.tenant_id ?? res.tenant?.id }
}

export async function createTenantForUser(data: CreateTenantData): Promise<{ success: boolean; error?: string; tenant?: Tenant; tenantId?: string }> {
  return createTenantViaRpc({
    ...data,
    legal_name: data.legal_name || data.name,
    country: data.country || 'France',
    currency: data.currency || 'EUR',
    enabled_modules: data.enabled_modules || ['home', 'accounting', 'commercial', 'treasury', 'stock', 'production', 'hr', 'dashboards', 'reporting', 'system'],
  })
}

export async function createSiteForCurrentTenant(data: {
  siteName: string
  address: string
}): Promise<{ success: boolean; error?: string; tenant?: Tenant }> {
  const current = await getCurrentTenant()
  if (!current) return { success: false, error: 'Aucun tenant actif' }

  return createTenantViaRpc({
    name: data.siteName,
    legal_name: current.legal_name || data.siteName,
    siren: current.siren,
    siret: null,
    vat_number: current.vat_number,
    address: data.address,
    city: current.city,
    postal_code: current.postal_code,
    country: current.country,
    currency: current.currency,
    email: current.email,
    phone: current.phone,
    legislation_pack_code: current.legislation_pack_code || undefined,
    enabled_modules: current.enabled_modules,
    plan: current.plan,
    trial_ends_at: current.trial_ends_at,
  })
}

export async function getCurrentTenant(): Promise<Tenant | null> {
  const { data: { session } } = await supabase.auth.getSession()
  if (!session) return null

  const { data, error } = await supabase
    .from('tenant_users')
    .select('tenant_id, tenants(*)')
    .eq('auth_id', session.user.id)
    .eq('status', 'active')

  if (error) { console.error('getActiveTenant:', error); return null }
  if (!data || data.length === 0) return null
  const stored = localStorage.getItem('active_tenant_id')
  const match = data.find(tu => tu.tenant_id === stored) || data[0]
  return (match as any).tenants as Tenant
}

export async function getCurrentTenantUser(): Promise<TenantUser | null> {
  const { data: { session } } = await supabase.auth.getSession()
  if (!session) return null

  const { data, error } = await supabase
    .from('tenant_users')
    .select('*')
    .eq('auth_id', session.user.id)
    .eq('status', 'active')

  if (error) { console.error('getActiveTenantUser:', error); return null }
  if (!data || data.length === 0) return null
  const stored = localStorage.getItem('active_tenant_id')
  const match = data.find(tu => tu.tenant_id === stored) || data[0]
  return match as TenantUser
}

export async function getTenantEnabledModules(): Promise<string[]> {
  const tenant = await getCurrentTenant()
  const DEFAULT_MODS = ['home', 'accounting', 'commercial', 'treasury', 'stock', 'production', 'hr', 'projectManagement', 'dashboards', 'reporting', 'system']
  if (!tenant) return DEFAULT_MODS
  const mods = tenant.enabled_modules || DEFAULT_MODS
  // Ensure new modules are included if tenant has a saved list
  if (!mods.includes('projectManagement')) return [...mods, 'projectManagement']
  return mods
}

export async function requireAdminOfTenant(tenantId: string): Promise<{ ok: boolean; error?: string }> {
  const { data: { session } } = await supabase.auth.getSession()
  if (!session) return { ok: false, error: 'Non connecté' }
  const { data: tu } = await supabase
    .from('tenant_users')
    .select('role, status, tenant_id')
    .eq('auth_id', session.user.id)
    .eq('status', 'active')
    .eq('tenant_id', tenantId)
    .maybeSingle()
  if (!tu) return { ok: false, error: 'Utilisateur non trouvé' }
  if (tu.role !== 'admin') return { ok: false, error: 'Action réservée aux administrateurs' }
  return { ok: true }
}

export async function updateTenantModules(tenantId: string, modules: string[]): Promise<{ success: boolean; error?: string }> {
  const guard = await requireAdminOfTenant(tenantId)
  if (!guard.ok) return { success: false, error: guard.error }
  const { error } = await supabase
    .from('tenants')
    .update({ enabled_modules: modules, updated_at: new Date().toISOString() })
    .eq('id', tenantId)
  if (error) return { success: false, error: error.message }
  return { success: true }
}

export async function getTenantUsers(tenantId: string): Promise<TenantUser[]> {
  const { data: { session } } = await supabase.auth.getSession()
  if (!session) throw new Error('Non connecté')
  const tid = await getTenantId()
  if (!tid || tid !== tenantId) throw new Error('Accès non autorisé à ce tenant')

  const { data, error } = await supabase
    .from('tenant_users')
    .select('*')
    .eq('tenant_id', tenantId)
    .order('created_at', { ascending: false })

  if (error) throw error
  return (data || []) as TenantUser[]
}

export async function inviteUser(data: {
  tenantId: string
  email: string
  name: string
  role: TenantUser['role']
  permissions?: Record<string, string[]>
  moduleRoles?: Record<string, string>
  guestPermissions?: Record<string, any>
  invitedBy?: string
  validFrom?: string | null
  validUntil?: string | null
}): Promise<{ success: boolean; error?: string; message?: string }> {
  const { data: { session } } = await supabase.auth.getSession()
  if (!session) return { success: false, error: 'Non connecté' }

  // Defense-in-depth: verify caller is admin of this tenant before calling edge function
  const guard = await requireAdminOfTenant(data.tenantId)
  if (!guard.ok) return { success: false, error: guard.error }

  // Get current locale for email localization
  const locale = localStorage.getItem('i18nextLng')?.split('-')[0] || 'en'

  try {
    const { data: result, error } = await supabase.functions.invoke('create-user', {
      body: {
        email: data.email,
        name: data.name,
        role: data.role,
        permissions: data.permissions || {},
        module_roles: data.moduleRoles || {},
        guest_permissions: data.guestPermissions || {},
        tenant_id: data.tenantId,
        invited_by: data.invitedBy || null,
        locale,
        valid_from: data.validFrom || null,
        valid_until: data.validUntil || null,
      },
    })

    if (error) {
      // Try to extract the error message from the function response body
      let msg = error.message
      try {
        const ctx = (error as any).context
        if (ctx && typeof ctx.json === 'function') {
          const body = await ctx.json()
          if (body?.error) msg = body.error
        }
      } catch { /* keep default message */ }
      return { success: false, error: msg || 'Erreur lors de la création' }
    }

    if (result?.error) {
      return { success: false, error: result.error }
    }

    return { success: true, message: result?.message }
  } catch (err: any) {
    return { success: false, error: err.message || 'Erreur réseau' }
  }
}

export async function updateUserRole(
  tenantUserId: string,
  role: TenantUser['role'],
  permissions?: Record<string, string[]>,
  moduleRoles?: Record<string, string>,
  guestPermissions?: Record<string, any>
): Promise<{ success: boolean; error?: string }> {
  const tid = await getTenantId()
  if (!tid) return { success: false, error: 'Aucun tenant actif' }
  const guard = await requireAdminOfTenant(tid)
  if (!guard.ok) return { success: false, error: guard.error }

  const update: Record<string, any> = { role }
  if (permissions !== undefined) update.permissions = permissions
  if (moduleRoles !== undefined) update.module_roles = moduleRoles
  if (guestPermissions !== undefined) update.guest_permissions = guestPermissions

  const { error } = await supabase
    .from('tenant_users')
    .update(update)
    .eq('id', tenantUserId)
    .eq('tenant_id', tid)

  if (error) return { success: false, error: error.message }
  return { success: true }
}

export async function revokeUser(tenantUserId: string): Promise<{ success: boolean; error?: string }> {
  const tid = await getTenantId()
  if (!tid) return { success: false, error: 'Aucun tenant actif' }
  const guard = await requireAdminOfTenant(tid)
  if (!guard.ok) return { success: false, error: guard.error }

  const { error } = await supabase
    .from('tenant_users')
    .update({ status: 'revoked' })
    .eq('id', tenantUserId)
    .eq('tenant_id', tid)

  if (error) return { success: false, error: error.message }
  return { success: true }
}

export async function reactivateUser(tenantUserId: string): Promise<{ success: boolean; error?: string }> {
  const tid = await getTenantId()
  if (!tid) return { success: false, error: 'Aucun tenant actif' }
  const guard = await requireAdminOfTenant(tid)
  if (!guard.ok) return { success: false, error: guard.error }

  const { error } = await supabase
    .from('tenant_users')
    .update({ status: 'active' })
    .eq('id', tenantUserId)
    .eq('tenant_id', tid)

  if (error) return { success: false, error: error.message }
  return { success: true }
}

export async function reinviteUser(tenantUserId: string, email: string): Promise<{ success: boolean; error?: string; emailSent?: boolean }> {
  const tid = await getTenantId()
  if (!tid) return { success: false, error: 'Aucun tenant actif' }
  const guard = await requireAdminOfTenant(tid)
  if (!guard.ok) return { success: false, error: guard.error }

  const { error: updateError } = await supabase
    .from('tenant_users')
    .update({ status: 'pending' })
    .eq('id', tenantUserId)
    .eq('tenant_id', tid)

  if (updateError) return { success: false, error: updateError.message }

  let emailSent = false
  try {
    const redirectTo = `${window.location.origin}/accept-invitation?tenant=${tid}`
    const locale = localStorage.getItem('i18nextLng')?.split('-')[0] || 'en'
    const otpOptions: Record<string, any> = { emailRedirectTo: redirectTo }
    if (['fr', 'en', 'ar'].includes(locale)) {
      otpOptions.lang = locale
    }
    const { error: inviteError } = await supabase.auth.signInWithOtp({
      email,
      options: otpOptions,
    })
    emailSent = !inviteError
  } catch (e) {
    // Email service might not be configured
    console.error('inviteUser: email send failed:', e)
  }

  return { success: true, emailSent }
}

// Called after an invited user clicks the magic link and lands on /accept-invitation.
// Links the authenticated auth.users id to the pending tenant_users row, activates it,
// and optionally sets a password so the user can log in with email/password later.
export async function acceptInvitation(
  password?: string,
  tenantId?: string
): Promise<{ success: boolean; error?: string; tenantName?: string; otherPendingInvites?: { tenantId: string; tenantName: string }[] }> {
  const { data: { session } } = await supabase.auth.getSession()
  if (!session) return { success: false, error: 'Lien invalide ou expiré. Redemandez une invitation.' }

  const authId = session.user.id
  const email = session.user.email
  if (!email) return { success: false, error: 'Email introuvable dans la session.' }

  // Find all pending/active invitations for this email
  // SECURITY: Use .limit(10) instead of .maybeSingle() to handle multiple tenant invitations
  const { data: invitations, error: findError } = await supabase
    .from('tenant_users')
    .select('id, tenant_id, status, auth_id, tenants:tenant_id (name)')
    .eq('email', email)
    .neq('status', 'revoked')
    .order('accepted_at', { ascending: false, nullsFirst: true })
    .limit(10)

  if (findError) return { success: false, error: findError.message }
  if (!invitations || invitations.length === 0) {
    return { success: false, error: "Aucune invitation trouvée pour cet email." }
  }

  // If tenantId is provided (from magic link URL), target that specific invitation
  // Otherwise fall back to: 1) matching auth_id, 2) null auth_id (pending), 3) first
  let tenantUser
  if (tenantId) {
    tenantUser = invitations.find(i => i.tenant_id === tenantId)
  }
  if (!tenantUser) {
    tenantUser = invitations.find(i => i.auth_id === authId)
      || invitations.find(i => !i.auth_id)
      || invitations[0]
  }

  // Security: if the invitation already has a different auth_id, refuse
  if (tenantUser.auth_id && tenantUser.auth_id !== authId) {
    return { success: false, error: 'Cette invitation est associée à un autre compte.' }
  }

  // Link auth_id + activate
  // CRITICAL: filter by status='pending' to prevent race condition where
  // a revoked user could reactivate themselves between lookup and update
  const { error: updateError } = await supabase
    .from('tenant_users')
    .update({
      auth_id: authId,
      status: 'active',
      accepted_at: new Date().toISOString(),
      last_login: new Date().toISOString(),
    })
    .eq('id', tenantUser.id)
    .eq('email', email)
    .in('status', ['pending', 'active'])

  if (updateError) return { success: false, error: updateError.message }

  // Optionally set a password — enforce strong password policy
  if (password) {
    if (password.length < 8 || !/[A-Z]/.test(password) || !/[a-z]/.test(password) || !/[0-9]/.test(password)) {
      return { success: false, error: 'Le mot de passe doit contenir au moins 8 caractères, une majuscule, une minuscule et un chiffre.' }
    }
    const { error: pwError } = await supabase.auth.updateUser({ password })
    if (pwError) return { success: false, error: `Compte activé mais mot de passe non défini: ${pwError.message}` }
  }

  const tenantName = (tenantUser as any).tenants?.name || null

  // Collect other pending invitations so the UI can offer them to the user
  const otherPendingInvites = invitations
    .filter(i => i.tenant_id !== tenantUser.tenant_id && i.status === 'pending')
    .map(i => ({ tenantId: i.tenant_id, tenantName: (i as any).tenants?.name || i.tenant_id }))

  return { success: true, tenantName, otherPendingInvites }
}

/**
 * Seule implémentation de la matrice de droits par rôle. `canPerform` du contexte
 * d'authentification y délègue ; ne pas en recréer une copie.
 *
 * Ce contrôle est un confort d'interface, PAS une protection : il ne s'exécute que
 * dans le navigateur. Sur 2 296 politiques RLS, 7 seulement regardent le rôle
 * (project_members, notification_email_queue) — l'appel PostgREST correspondant
 * aboutit donc quel que soit le rôle. Toute règle qui doit vraiment être opposable
 * appartient à une politique ou à un trigger.
 */
export function hasPermission(
  user: Pick<TenantUser, 'role' | 'permissions'> | null,
  table: string,
  action: 'select' | 'insert' | 'update' | 'delete'
): boolean {
  if (!user) return false
  if (user.role === 'admin') return true
  if (user.role === 'accountant') {
    if (action === 'select' || action === 'insert' || action === 'update') return true
    if (action === 'delete' && ['journal_entries', 'journal_lines', 'invoice_lines', 'quote_lines', 'credit_note_lines'].includes(table)) return true
    return false
  }
  if (user.role === 'manager') {
    if (action === 'select') return true
    if (action === 'insert' || action === 'update') {
      const commercialTables = ['invoices', 'invoice_lines', 'quotes', 'quote_lines', 'credit_notes', 'credit_note_lines', 'customers', 'products', 'delivery_notes', 'delivery_note_lines', 'sales_orders', 'sales_order_lines', 'purchase_orders', 'purchase_order_lines', 'document_charges', 'document_transformations', 'product_grids', 'product_grid_combinations', 'product_packagings', 'product_links', 'promotions', 'warehouse_users', 'stock_alerts', 'crm_opportunities', 'crm_activities', 'crm_campaigns', 'crm_campaign_recipients', 'crm_territories', 'crm_forecasts', 'service_tickets', 'service_ticket_messages', 'service_contracts', 'knowledge_base_articles', 'saved_filters']
      return commercialTables.includes(table)
    }
    return false
  }
  if (user.role === 'viewer') return action === 'select'
  if (user.role === 'auditor') return action === 'select'
  if (user.role === 'custom') {
    const perms = user.permissions[table]
    if (!perms) return false
    return perms.includes(action)
  }
  return false
}

export const PERMISSION_TABLES = [
  { name: 'invoices' },
  { name: 'quotes' },
  { name: 'customers' },
  { name: 'suppliers' },
  { name: 'products' },
  { name: 'purchase_invoices' },
  { name: 'purchase_orders' },
  { name: 'journal_entries' },
  { name: 'bank_transactions' },
  { name: 'chart_accounts' },
  { name: 'budgets' },
  { name: 'fiscal_years' },
  { name: 'vat_returns' },
  { name: 'employees' },
  { name: 'pay_runs' },
  { name: 'company_settings' },
  { name: 'projects' },
  { name: 'warehouses' },
  { name: 'stock_movements' },
  { name: 'audit_log' },
] as const

export const PERMISSION_ACTIONS = [
  { value: 'select' },
  { value: 'insert' },
  { value: 'update' },
  { value: 'delete' },
] as const
