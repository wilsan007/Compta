import { createContext, useContext, useState, useEffect, useCallback, type ReactNode } from 'react'
import { supabase, setTenantId } from '@/lib/supabase'
import { resetModuleCache } from '@/lib/useTenantModules'
import { clearTenantCache } from '@/lib/queries'
import type { TenantUser } from '@/lib/queries'

interface AuthUser {
  id: string
  email: string
  name: string
  role: TenantUser['role']
  tenantId: string | null
  tenantName: string | null
  permissions: Record<string, string[]>
}

interface AuthContextType {
  user: AuthUser | null
  loading: boolean
  signIn: (email: string, password: string) => Promise<{ error: string | null }>
  signUp: (email: string, password: string) => Promise<{ error: string | null; needsConfirmation: boolean }>
  signOut: () => Promise<void>
  reloadUser: () => Promise<void>
  hasRole: (...roles: TenantUser['role'][]) => boolean
  canPerform: (table: string, action: 'select' | 'insert' | 'update' | 'delete') => boolean
  switchTenant: (tenantId: string) => Promise<void>
  availableTenants: { tenantId: string; tenantName: string; role: TenantUser['role'] }[]
}

const AuthContext = createContext<AuthContextType | undefined>(undefined)

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<AuthUser | null>(null)
  const [loading, setLoading] = useState(true)
  const [availableTenants, setAvailableTenants] = useState<{ tenantId: string; tenantName: string; role: TenantUser['role'] }[]>([])

  const loadUser = useCallback(async () => {
    try {
      const { data: { session } } = await supabase.auth.getSession()
      if (!session) {
        setUser(null)
        return
      }

      // Try tenant_users first (new multi-tenant system)
      // Fetch ALL active tenant_users rows for this user (they may belong to multiple tenants)
      const { data: tenantUsers, error: tenantErr } = await supabase
        .from('tenant_users')
        .select(`*, tenants:tenant_id (name)`)
        .eq('auth_id', session.user.id)
        .eq('status', 'active')

      // Auto-revoke expired auditors (best-effort, ignore errors)
      try {
        await supabase.rpc('auto_revoke_expired_auditors')
      } catch { /* ignore */ }

      // Filter out any auditors whose valid_until has passed (in case RPC didn't run)
      const now = new Date()
      const validTenantUsers = (tenantUsers || []).filter((tu: any) => {
        if (tu.role !== 'auditor') return true
        if (tu.valid_until && new Date(tu.valid_until) < now) return false
        if (tu.valid_from && new Date(tu.valid_from) > now) return false
        return true
      })

      if (!tenantErr && validTenantUsers.length > 0) {
        // Store all available tenants for the switcher UI
        setAvailableTenants(validTenantUsers.map((tu: any) => ({
          tenantId: tu.tenant_id,
          tenantName: tu.tenants?.name || tu.tenant_id,
          role: tu.role,
        })))

        const storedTenantId = localStorage.getItem('active_tenant_id')
        const matchedTenant = validTenantUsers.find(tu => tu.tenant_id === storedTenantId)

        if (matchedTenant) {
          // Stored preference found — use it
          const prevTenantId = user?.tenantId
          const newTenantId = matchedTenant.tenant_id
          if (prevTenantId && prevTenantId !== newTenantId) {
            resetModuleCache()
          }
          setTenantId(newTenantId)
          setUser({
            id: matchedTenant.id,
            email: matchedTenant.email,
            name: matchedTenant.name,
            role: matchedTenant.role,
            tenantId: matchedTenant.tenant_id,
            tenantName: (matchedTenant as any).tenants?.name || null,
            permissions: matchedTenant.permissions || {},
          })
          return
        }

        // No stored preference
        if (validTenantUsers.length === 1) {
          // Only one tenant — auto-select it
          const tu = validTenantUsers[0]
          setTenantId(tu.tenant_id)
          setUser({
            id: tu.id,
            email: tu.email,
            name: tu.name,
            role: tu.role,
            tenantId: tu.tenant_id,
            tenantName: (tu as any).tenants?.name || null,
            permissions: tu.permissions || {},
          })
          return
        }

        // Multiple tenants and no stored preference — let user choose
        // Set a minimal user object with tenantId=null so ProtectedRoute
        // redirects to /select-tenant
        setTenantId(null)
        setUser({
          id: session.user.id,
          email: session.user.email || '',
          name: session.user.email || '',
          role: 'viewer',
          tenantId: null,
          tenantName: null,
          permissions: {},
        })
        return
      }

      // Fallback: try old users table
      const { data: userData, error } = await supabase
        .from('users')
        .select('id, email, name, role, active')
        .eq('auth_id', session.user.id)
        .single()

      if (!error && userData) {
        if (!userData.active) {
          await supabase.auth.signOut()
          setTenantId(null)
          setUser(null)
          return
        }
        // SECURITY: Old users table fallback — use 'viewer' role, force onboarding flow
        setTenantId(null)
        setUser({
          id: userData.id,
          email: userData.email,
          name: userData.name,
          role: 'viewer',
          tenantId: null,
          tenantName: null,
          permissions: {},
        })
        return
      }

      // Check if there's a pending invitation for this email
      const userEmail = session.user.email
      if (userEmail) {
        const { data: pendingInvite } = await supabase
          .from('tenant_users')
          .select('id, tenant_id, status, tenants:tenant_id (name)')
          .eq('email', userEmail)
          .eq('status', 'pending')
          .maybeSingle()

        if (pendingInvite) {
          // User has a pending invitation — redirect to accept page
          setTenantId(null)
          setUser({
            id: session.user.id,
            email: userEmail,
            name: userEmail,
            role: 'viewer',
            tenantId: null,
            tenantName: null,
            permissions: {},
          })
          // Redirect to accept-invitation page
          if (window.location.pathname !== '/accept-invitation') {
            window.location.href = '/accept-invitation'
          }
          return
        }
      }

      // No tenant_users or users record found and no pending invitation.
      // Keep the session alive with a minimal user object so the user can
      // access /onboarding to create their tenant. ProtectedRoute will
      // redirect them there since tenantId is null.
      // SECURITY: Use 'viewer' role — admin privileges should only come from a verified tenant_users record.
      setAvailableTenants([])
      setTenantId(null)
      setUser({
        id: session.user.id,
        email: session.user.email || '',
        name: session.user.email || '',
        role: 'viewer',
        tenantId: null,
        tenantName: null,
        permissions: {},
      })
    } catch {
      setTenantId(null)
      setUser(null)
    }
  }, [])

  useEffect(() => {
    loadUser().finally(() => setLoading(false))

    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, _session) => {
      setLoading(true)
      loadUser().finally(() => setLoading(false))
    })

    return () => subscription.unsubscribe()
  }, [loadUser])

  const signIn = useCallback(async (email: string, password: string): Promise<{ error: string | null }> => {
    const now = Date.now()
    // SECURITY: Use both localStorage and sessionStorage so clearing one doesn't reset the limit
    const lsAttempts = JSON.parse(localStorage.getItem('_auth_attempts') || '[]') as number[]
    const ssAttempts = JSON.parse(sessionStorage.getItem('_auth_attempts') || '[]') as number[]
    const allAttempts = [...lsAttempts, ...ssAttempts].filter((t) => now - t < 60000)
    const uniqueRecent = [...new Set(allAttempts)].sort((a, b) => a - b).slice(-10)
    if (uniqueRecent.length >= 5) {
      return { error: 'Trop de tentatives. Réessayez dans 1 minute.' }
    }
    try {
      const { error } = await supabase.auth.signInWithPassword({ email, password })
      if (error) {
        const updated = [...uniqueRecent, now]
        localStorage.setItem('_auth_attempts', JSON.stringify(updated))
        sessionStorage.setItem('_auth_attempts', JSON.stringify(updated))
        return { error: error.message }
      }
      localStorage.removeItem('_auth_attempts')
      sessionStorage.removeItem('_auth_attempts')
      return { error: null }
    } catch (err: any) {
      const updated = [...uniqueRecent, now]
      localStorage.setItem('_auth_attempts', JSON.stringify(updated))
      sessionStorage.setItem('_auth_attempts', JSON.stringify(updated))
      return { error: err.message || 'Erreur de connexion' }
    }
  }, [])

  const signUp = useCallback(async (email: string, password: string): Promise<{ error: string | null; needsConfirmation: boolean }> => {
    if (password.length < 8 || !/[A-Z]/.test(password) || !/[a-z]/.test(password) || !/[0-9]/.test(password)) {
      return { error: 'Password must be at least 8 characters with 1 uppercase, 1 lowercase, and 1 digit.', needsConfirmation: false }
    }
    try {
      // Pre-check: block signup if email already exists in auth.users
      const { data: emailExists, error: rpcErr } = await supabase
        .rpc('auth_email_exists', { p_email: email })
      if (rpcErr) {
        // If RPC fails (e.g. function not deployed yet), fall through to signUp
        console.warn('auth_email_exists RPC failed, falling back to signUp:', rpcErr.message)
      } else if (emailExists) {
        return { error: 'Un compte existe déjà avec cet email. Veuillez vous connecter avec vos identifiants actuels.', needsConfirmation: false }
      }

      const { data, error } = await supabase.auth.signUp({
        email,
        password,
        options: {
          emailRedirectTo: `${window.location.origin}/onboarding`,
        },
      })
      if (error) return { error: error.message, needsConfirmation: false }
      // If no session is returned, email confirmation is required before login
      const needsConfirmation = !data.session
      return { error: null, needsConfirmation }
    } catch (err: any) {
      return { error: err.message || "Erreur lors de l'inscription", needsConfirmation: false }
    }
  }, [])

  const signOut = useCallback(async () => {
    await supabase.auth.signOut()
    setTenantId(null)
    clearTenantCache()
    setUser(null)
    setAvailableTenants([])
    localStorage.removeItem('active_tenant_id')
    resetModuleCache()
  }, [])

  const switchTenant = useCallback(async (tenantId: string) => {
    clearTenantCache()
    localStorage.setItem('active_tenant_id', tenantId)
    resetModuleCache()
    await setTenantId(tenantId)
    window.location.reload()
  }, [])

  const hasRole = useCallback((...roles: TenantUser['role'][]) => {
    if (!user) return false
    return roles.includes(user.role)
  }, [user])

  const canPerform = useCallback((table: string, action: 'select' | 'insert' | 'update' | 'delete') => {
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
        const commercialTables = ['invoices', 'invoice_lines', 'quotes', 'quote_lines', 'credit_notes', 'credit_note_lines', 'customers', 'products', 'delivery_notes', 'delivery_note_lines', 'sales_orders', 'sales_order_lines', 'purchase_orders', 'purchase_order_lines']
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
  }, [user])

  return (
    <AuthContext.Provider value={{ user, loading, signIn, signUp, signOut, reloadUser: loadUser, hasRole, canPerform, switchTenant, availableTenants }}>
      {children}
    </AuthContext.Provider>
  )
}

export function useAuth() {
  const ctx = useContext(AuthContext)
  if (!ctx) throw new Error('useAuth must be used within AuthProvider')
  return ctx
}
