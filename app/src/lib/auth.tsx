import { createContext, useContext, useState, useEffect, useCallback, type ReactNode } from 'react'
import { supabase, setTenantId } from '@/lib/supabase'
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
}

const AuthContext = createContext<AuthContextType | undefined>(undefined)

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<AuthUser | null>(null)
  const [loading, setLoading] = useState(true)

  const loadUser = useCallback(async () => {
    try {
      const { data: { session } } = await supabase.auth.getSession()
      if (!session) {
        setUser(null)
        return
      }

      // Try tenant_users first (new multi-tenant system)
      const { data: tenantUser, error: tenantErr } = await supabase
        .from('tenant_users')
        .select(`*, tenants:tenant_id (name)`)
        .eq('auth_id', session.user.id)
        .eq('status', 'active')
        .single()

      if (!tenantErr && tenantUser) {
        setTenantId(tenantUser.tenant_id)
        setUser({
          id: tenantUser.id,
          email: tenantUser.email,
          name: tenantUser.name,
          role: tenantUser.role,
          tenantId: tenantUser.tenant_id,
          tenantName: (tenantUser as any).tenants?.name || null,
          permissions: tenantUser.permissions || {},
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
        setTenantId(null)
        setUser({
          id: userData.id,
          email: userData.email,
          name: userData.name,
          role: userData.role,
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
      // Sign out — do NOT grant admin access to unrecognised users.
      await supabase.auth.signOut()
      setTenantId(null)
      setUser(null)
    } catch {
      setTenantId(null)
      setUser(null)
    }
  }, [])

  useEffect(() => {
    loadUser().finally(() => setLoading(false))

    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, _session) => {
      loadUser().finally(() => setLoading(false))
    })

    return () => subscription.unsubscribe()
  }, [loadUser])

  const signIn = useCallback(async (email: string, password: string): Promise<{ error: string | null }> => {
    const now = Date.now()
    const attempts = JSON.parse(localStorage.getItem('_auth_attempts') || '[]') as number[]
    const recent = attempts.filter((t) => now - t < 60000)
    if (recent.length >= 5) {
      return { error: 'Trop de tentatives. Réessayez dans 1 minute.' }
    }
    try {
      const { error } = await supabase.auth.signInWithPassword({ email, password })
      if (error) {
        localStorage.setItem('_auth_attempts', JSON.stringify([...recent, now]))
        return { error: error.message }
      }
      localStorage.removeItem('_auth_attempts')
      return { error: null }
    } catch (err: any) {
      localStorage.setItem('_auth_attempts', JSON.stringify([...recent, now]))
      return { error: err.message || 'Erreur de connexion' }
    }
  }, [])

  const signUp = useCallback(async (email: string, password: string): Promise<{ error: string | null; needsConfirmation: boolean }> => {
    if (password.length < 8 || !/[A-Z]/.test(password) || !/[a-z]/.test(password) || !/[0-9]/.test(password)) {
      return { error: 'Password must be at least 8 characters with 1 uppercase, 1 lowercase, and 1 digit.', needsConfirmation: false }
    }
    try {
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
    setUser(null)
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
    if (user.role === 'custom') {
      const perms = user.permissions[table]
      if (!perms) return false
      return perms.includes(action)
    }
    return false
  }, [user])

  return (
    <AuthContext.Provider value={{ user, loading, signIn, signUp, signOut, reloadUser: loadUser, hasRole, canPerform }}>
      {children}
    </AuthContext.Provider>
  )
}

export function useAuth() {
  const ctx = useContext(AuthContext)
  if (!ctx) throw new Error('useAuth must be used within AuthProvider')
  return ctx
}
