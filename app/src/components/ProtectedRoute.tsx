import { type ReactNode, useMemo, lazy, Suspense } from 'react'
import { Navigate, useLocation, useNavigate } from 'react-router-dom'
import { useTranslation } from 'react-i18next'
import { useAuth } from '@/lib/auth'
import { navModules } from '@/components/navModules'
import { useTenantModules } from '@/lib/useTenantModules'
import type { TenantUser } from '@/lib/queries/misc'
import { Lock, ArrowLeft, ShieldAlert } from 'lucide-react'

// PRF-02 : Layout lazy-loaded pour réduire le chunk initial
const Layout = lazy(() => import('@/components/Layout').then(m => ({ default: m.Layout })))
const LayoutFallback = () => (
  <div className="min-h-screen flex items-center justify-center">
    <div className="w-8 h-8 border-2 border-[var(--color-primary)] border-t-transparent rounded-full animate-spin" />
  </div>
)

interface ProtectedRouteProps {
  children: ReactNode
  roles?: TenantUser['role'][]
}

export function ProtectedRoute({ children, roles }: ProtectedRouteProps) {
  const { user, loading, availableTenants } = useAuth()
  const { t } = useTranslation('nav')
  const location = useLocation()

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <div className="flex flex-col items-center gap-3">
          <div className="w-8 h-8 border-2 border-[var(--color-primary)] border-t-transparent rounded-full animate-spin" />
          <p className="text-sm text-[var(--color-text-secondary)]">{t('common:common.loading')}</p>
        </div>
      </div>
    )
  }

  if (!user) {
    return <Navigate to="/login" replace />
  }

  // Multi-tenant user with no selected tenant — redirect to tenant selection
  if (!user.tenantId && availableTenants.length > 1) {
    return <Navigate to="/select-tenant" replace state={{ from: location.pathname }} />
  }

  if (!user.tenantId) {
    return <Navigate to="/onboarding" replace />
  }

  if (roles && roles.length > 0 && !roles.includes(user.role)) {
    return (
      <div className="min-h-screen flex items-center justify-center p-4">
        <div className="card p-8 text-center max-w-md">
          <div className="w-12 h-12 rounded-full bg-[rgba(222,53,11,0.1)] flex items-center justify-center mx-auto mb-4">
            <svg className="w-6 h-6 text-[var(--color-danger)]" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
            </svg>
          </div>
          <h2 className="text-lg font-semibold text-[var(--color-text)] mb-2">{t('layout.accessDenied')}</h2>
          <p className="text-sm text-[var(--color-text-secondary)]">
            {t('layout.accessDeniedMessage', { role: user.role })}
          </p>
        </div>
      </div>
    )
  }

  return <>{children}</>
}

export function ProtectedLayout() {
  return (
    <ProtectedRoute>
      <ModuleGuard>
        <Suspense fallback={<LayoutFallback />}>
          <Layout />
        </Suspense>
      </ModuleGuard>
    </ProtectedRoute>
  )
}

export function AdminRoute({ children }: { children: ReactNode }) {
  return (
    <ProtectedRoute roles={['admin']}>
      {children}
    </ProtectedRoute>
  )
}

function getModuleIdForPathAll(pathname: string): string | null {
  for (const mod of navModules) {
    const allPaths = mod.sections
      ? mod.sections.flatMap((s) => s.items.map((i) => i.path))
      : mod.items?.map((i) => i.path) || []
    for (const p of allPaths) {
      if (p === '/' && pathname === '/') return mod.id
      if (p !== '/' && pathname.startsWith(p)) return mod.id
    }
  }
  return null
}

// Modules that require module_roles RBAC check
const RBAC_MODULE_IDS = new Set(['accounting', 'commercial', 'treasury', 'stock', 'production', 'hr', 'projectManagement'])

function ModuleGuard({ children }: { children: ReactNode }) {
  const location = useLocation()
  const navigate = useNavigate()
  const { t } = useTranslation('nav')
  const { modules: enabledModules, loading } = useTenantModules()
  const { user } = useAuth()

  const moduleId = useMemo(() => getModuleIdForPathAll(location.pathname), [location.pathname])
  const isDisabled = !loading && moduleId !== null && !enabledModules.includes(moduleId)

  // RBAC check: if the module requires a module_roles entry and user doesn't have one
  const moduleRoles = (user as any)?.module_roles || {}
  const isGlobalAdmin = user?.role === 'admin'
  const rbacDenied = !loading && moduleId !== null && RBAC_MODULE_IDS.has(moduleId) && !isGlobalAdmin
    && (moduleRoles[moduleId] == null || String(moduleRoles[moduleId]) === '')

  if (rbacDenied) {
    return (
      <div className="min-h-screen flex items-center justify-center p-4">
        <div className="card p-8 text-center max-w-md">
          <div className="w-12 h-12 rounded-full bg-[rgba(222,53,11,0.1)] flex items-center justify-center mx-auto mb-4">
            <ShieldAlert className="w-6 h-6 text-[var(--color-danger)]" />
          </div>
          <h2 className="text-lg font-semibold text-[var(--color-text)] mb-2">{t('layout.rbacAccessDenied')}</h2>
          <p className="text-sm text-[var(--color-text-secondary)] mb-6">
            {t('layout.rbacAccessDeniedMessage')}
          </p>
          <button
            onClick={() => navigate('/')}
            className="inline-flex items-center gap-2 px-4 py-2 rounded-lg bg-[var(--color-primary)] text-white text-sm font-medium hover:opacity-90 transition-opacity"
          >
            <ArrowLeft className="w-4 h-4" />
            {t('layout.backHome')}
          </button>
        </div>
      </div>
    )
  }

  if (isDisabled) {
    return (
      <div className="min-h-screen flex items-center justify-center p-4">
        <div className="card p-8 text-center max-w-md">
          <div className="w-12 h-12 rounded-full bg-[rgba(234,179,8,0.1)] flex items-center justify-center mx-auto mb-4">
            <Lock className="w-6 h-6 text-[var(--color-warning)]" />
          </div>
          <h2 className="text-lg font-semibold text-[var(--color-text)] mb-2">{t('layout.moduleDisabled')}</h2>
          <p className="text-sm text-[var(--color-text-secondary)] mb-6">
            {t('layout.moduleDisabledMessage')}
          </p>
          <button
            onClick={() => navigate('/')}
            className="inline-flex items-center gap-2 px-4 py-2 rounded-lg bg-[var(--color-primary)] text-white text-sm font-medium hover:opacity-90 transition-opacity"
          >
            <ArrowLeft className="w-4 h-4" />
            {t('layout.backHome')}
          </button>
        </div>
      </div>
    )
  }

  return <>{children}</>
}
