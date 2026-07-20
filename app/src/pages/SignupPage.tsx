import { useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { useAuth } from '@/lib/auth'
import { Button } from '@/components/ui'
import { Building2, Lock, Mail, AlertCircle, CheckCircle2 } from 'lucide-react'

export function SignupPage() {
  const { signUp } = useAuth()
  const navigate = useNavigate()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [confirmPassword, setConfirmPassword] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)
  const [confirmationSent, setConfirmationSent] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setError(null)
    if (!email.trim() || !password.trim()) {
      setError('Veuillez saisir votre email et mot de passe')
      return
    }
    if (password.length < 6) {
      setError('Le mot de passe doit contenir au moins 6 caractères')
      return
    }
    if (password !== confirmPassword) {
      setError('Les mots de passe ne correspondent pas')
      return
    }
    setLoading(true)
    const { error: signUpError, needsConfirmation } = await signUp(email, password)
    if (signUpError) {
      setError(signUpError)
      setLoading(false)
      return
    }
    if (needsConfirmation) {
      setConfirmationSent(true)
      setLoading(false)
      return
    }
    // Session active immediately -> go to onboarding to create the company
    navigate('/onboarding')
  }

  if (confirmationSent) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-[var(--color-neutral-50)] p-4">
        <div className="w-full max-w-md text-center">
          <div className="inline-flex items-center justify-center w-16 h-16 rounded-2xl bg-[var(--color-success)] text-white mb-4">
            <CheckCircle2 className="w-8 h-8" />
          </div>
          <h1 className="text-2xl font-bold text-[var(--color-text)]">Vérifiez votre email</h1>
          <p className="text-sm text-[var(--color-text-secondary)] mt-2">
            Un email de confirmation a été envoyé à <strong>{email}</strong>. Cliquez sur le lien
            pour activer votre compte, puis configurez votre entreprise.
          </p>
          <Link to="/login" className="inline-block mt-6 text-sm text-[var(--color-primary)] font-medium">
            Retour à la connexion
          </Link>
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
          <h1 className="text-2xl font-bold text-[var(--color-text)]">Créer un compte</h1>
          <p className="text-sm text-[var(--color-text-secondary)] mt-1">
            Créez votre espace entreprise en quelques secondes
          </p>
        </div>

        <div className="card p-6 space-y-4">
          {error && (
            <div className="flex items-center gap-2 p-3 rounded-lg bg-[rgba(222,53,11,0.08)] border border-[var(--color-danger)] text-sm text-[var(--color-danger)]">
              <AlertCircle className="w-4 h-4 flex-shrink-0" />
              <span>{error}</span>
            </div>
          )}

          <form onSubmit={handleSubmit} className="space-y-4">
            <div className="space-y-1.5">
              <label className="text-sm font-medium text-[var(--color-text)]">Email professionnel</label>
              <div className="relative">
                <Mail className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-[var(--color-text-secondary)]" />
                <input
                  type="email"
                  required
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="vous@entreprise.fr"
                  className="input pl-10"
                  autoComplete="email"
                />
              </div>
            </div>

            <div className="space-y-1.5">
              <label className="text-sm font-medium text-[var(--color-text)]">Mot de passe</label>
              <div className="relative">
                <Lock className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-[var(--color-text-secondary)]" />
                <input
                  type="password"
                  required
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  placeholder="Au moins 6 caractères"
                  className="input pl-10"
                  autoComplete="new-password"
                />
              </div>
            </div>

            <div className="space-y-1.5">
              <label className="text-sm font-medium text-[var(--color-text)]">Confirmer le mot de passe</label>
              <div className="relative">
                <Lock className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-[var(--color-text-secondary)]" />
                <input
                  type="password"
                  required
                  value={confirmPassword}
                  onChange={(e) => setConfirmPassword(e.target.value)}
                  placeholder="••••••••"
                  className="input pl-10"
                  autoComplete="new-password"
                />
              </div>
            </div>

            <Button type="submit" disabled={loading} className="w-full">
              {loading ? 'Création...' : 'Créer mon compte'}
            </Button>
          </form>

          <p className="text-center text-sm text-[var(--color-text-secondary)]">
            Vous avez déjà un compte ?{' '}
            <Link to="/login" className="text-[var(--color-primary)] font-medium">
              Se connecter
            </Link>
          </p>
        </div>

        <p className="text-center text-xs text-[var(--color-text-secondary)] mt-6">
          ERP Compta — Solution de gestion d'entreprise
        </p>
      </div>
    </div>
  )
}
