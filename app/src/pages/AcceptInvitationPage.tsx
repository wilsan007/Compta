import { useState, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { supabase } from '@/lib/supabase'
import { useAuth } from '@/lib/auth'
import { acceptInvitation } from '@/lib/queries'
import { Button } from '@/components/ui'
import { Building2, Lock, AlertCircle, Loader2 } from 'lucide-react'
import { useTranslation } from 'react-i18next'

export function AcceptInvitationPage() {
  const { t } = useTranslation('auth')
  const navigate = useNavigate()
  const { reloadUser } = useAuth()
  const [checking, setChecking] = useState(true)
  const [sessionEmail, setSessionEmail] = useState<string | null>(null)
  const [password, setPassword] = useState('')
  const [confirmPassword, setConfirmPassword] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)

  useEffect(() => {
    // The magic link establishes a session automatically. Wait for it.
    async function check() {
      const { data: { session } } = await supabase.auth.getSession()
      if (session?.user?.email) {
        setSessionEmail(session.user.email)
      }
      setChecking(false)
    }
    check()
    const { data: { subscription } } = supabase.auth.onAuthStateChange((_e, session) => {
      if (session?.user?.email) {
        setSessionEmail(session.user.email)
        setChecking(false)
      }
    })
    return () => subscription.unsubscribe()
  }, [])

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setError(null)
    if (password && password.length < 6) {
      setError(t('invitation.passwordTooShort'))
      return
    }
    if (password !== confirmPassword) {
      setError(t('invitation.passwordMismatch'))
      return
    }
    setLoading(true)
    const { success, error: acceptError } = await acceptInvitation(password || undefined)
    if (!success) {
      setError(acceptError || t('invitation.acceptError'))
      setLoading(false)
      return
    }
    await reloadUser()
    navigate('/')
  }

  if (checking) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-[var(--color-neutral-50)]">
        <div className="flex flex-col items-center gap-3">
          <Loader2 className="w-8 h-8 animate-spin text-[var(--color-primary)]" />
          <p className="text-sm text-[var(--color-text-secondary)]">{t('invitation.checkInvitation')}</p>
        </div>
      </div>
    )
  }

  if (!sessionEmail) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-[var(--color-neutral-50)] p-4">
        <div className="w-full max-w-md text-center">
          <div className="inline-flex items-center justify-center w-16 h-16 rounded-2xl bg-[rgba(222,53,11,0.1)] text-[var(--color-danger)] mb-4">
            <AlertCircle className="w-8 h-8" />
          </div>
          <h1 className="text-2xl font-bold text-[var(--color-text)]">{t('invitation.invalidLink')}</h1>
          <p className="text-sm text-[var(--color-text-secondary)] mt-2">
            {t('invitation.invalidLinkDescription')}
          </p>
          <Button className="mt-6" onClick={() => navigate('/login')}>{t('password.backToLogin')}</Button>
        </div>
      </div>
    )
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-[var(--color-neutral-50)] p-4">
      <div className="w-full max-w-md">
        <div className="text-center mb-8">
          <div className="inline-flex items-center justify-center w-16 h-16 rounded-2xl bg-[var(--color-primary)] text-white mb-4">
            <Building2 className="w-8 h-8" />
          </div>
          <h1 className="text-2xl font-bold text-[var(--color-text)]">{t('invitation.joinCompany')}</h1>
          <p className="text-sm text-[var(--color-text-secondary)] mt-1">
            {t('invitation.connectedAs')} <strong>{sessionEmail}</strong>
          </p>
        </div>

        <div className="card p-6 space-y-4">
          {error && (
            <div className="flex items-center gap-2 p-3 rounded-lg bg-[rgba(222,53,11,0.08)] border border-[var(--color-danger)] text-sm text-[var(--color-danger)]">
              <AlertCircle className="w-4 h-4 flex-shrink-0" />
              <span>{error}</span>
            </div>
          )}

          <p className="text-sm text-[var(--color-text-secondary)]">
            {t('invitation.setPassword')}
          </p>

          <form onSubmit={handleSubmit} className="space-y-4">
            <div className="space-y-1.5">
              <label className="text-sm font-medium text-[var(--color-text)]">{t('invitation.password')}</label>
              <div className="relative">
                <Lock className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-[var(--color-text-secondary)]" />
                <input
                  type="password"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  placeholder={t('invitation.passwordPlaceholderOptional')}
                  className="input pl-10"
                  autoComplete="new-password"
                />
              </div>
            </div>

            <div className="space-y-1.5">
              <label className="text-sm font-medium text-[var(--color-text)]">{t('invitation.confirmPassword')}</label>
              <div className="relative">
                <Lock className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-[var(--color-text-secondary)]" />
                <input
                  type="password"
                  value={confirmPassword}
                  onChange={(e) => setConfirmPassword(e.target.value)}
                  placeholder="••••••••"
                  className="input pl-10"
                  autoComplete="new-password"
                />
              </div>
            </div>

            <Button type="submit" disabled={loading} className="w-full">
              {loading ? t('invitation.activating') : t('invitation.joinCompany')}
            </Button>
          </form>
        </div>
      </div>
    </div>
  )
}
