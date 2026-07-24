import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useTranslation } from 'react-i18next'
import { useAuth } from '@/lib/auth'
import { Building2, ChevronRight, LogOut } from 'lucide-react'

export function TenantSelectionPage() {
  const { t } = useTranslation('nav')
  const { availableTenants, switchTenant, user, signOut } = useAuth()
  const navigate = useNavigate()
  const [selecting, setSelecting] = useState<string | null>(null)

  async function handleSelect(tenantId: string) {
    setSelecting(tenantId)
    await switchTenant(tenantId)
  }

  async function handleSignOut() {
    await signOut()
    navigate('/login')
  }

  return (
    <div className="min-h-screen flex items-center justify-center p-4 bg-[var(--color-neutral-50)]">
      <div className="w-full max-w-lg">
        {/* Logo */}
        <div className="flex flex-col items-center mb-8">
          <div className="w-14 h-14 rounded-2xl bg-gradient-to-br from-[var(--color-primary)] to-purple-600 flex items-center justify-center shadow-lg mb-4">
            <span className="text-white font-bold text-2xl">C</span>
          </div>
          <h1 className="text-2xl font-bold text-[var(--color-text)] text-center">
            {t('tenantSelection.title')}
          </h1>
          <p className="text-sm text-[var(--color-text-secondary)] text-center mt-2">
            {t('tenantSelection.subtitle', { email: user?.email })}
          </p>
        </div>

        {/* Tenant cards */}
        <div className="space-y-3">
          {availableTenants.map((tenant) => (
            <button
              key={tenant.tenantId}
              disabled={selecting !== null}
              onClick={() => handleSelect(tenant.tenantId)}
              className={`w-full flex items-center gap-4 p-4 rounded-xl border-2 transition-all text-left ${
                selecting === tenant.tenantId
                  ? 'border-[var(--color-primary)] bg-[rgba(59,130,246,0.05)]'
                  : 'border-[var(--color-border)] bg-[var(--color-surface)] hover:border-[var(--color-primary)] hover:shadow-md'
              } ${selecting !== null && selecting !== tenant.tenantId ? 'opacity-50' : ''}`}
            >
              <div className="w-11 h-11 rounded-xl bg-gradient-to-br from-[var(--color-primary)] to-purple-600 flex items-center justify-center flex-shrink-0">
                <Building2 className="w-5 h-5 text-white" />
              </div>
              <div className="flex-1 min-w-0">
                <p className="font-semibold text-[var(--color-text)] truncate">{tenant.tenantName}</p>
                <p className="text-xs text-[var(--color-text-secondary)] capitalize mt-0.5">
                  {t('layout.tenantRole')}: {tenant.role}
                </p>
              </div>
              {selecting === tenant.tenantId ? (
                <div className="w-5 h-5 border-2 border-[var(--color-primary)] border-t-transparent rounded-full animate-spin flex-shrink-0" />
              ) : (
                <ChevronRight className="w-5 h-5 text-[var(--color-text-secondary)] flex-shrink-0" />
              )}
            </button>
          ))}
        </div>

        {/* Sign out */}
        <button
          onClick={handleSignOut}
          className="w-full mt-6 flex items-center justify-center gap-2 px-4 py-2.5 rounded-lg text-sm text-[var(--color-text-secondary)] hover:bg-[var(--color-neutral-100)] transition-colors"
        >
          <LogOut className="w-4 h-4" />
          {t('layout.logout')}
        </button>
      </div>
    </div>
  )
}
