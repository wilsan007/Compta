import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAuth } from '@/lib/auth'
import { Button } from '@/components/ui'
import { createTenantForUser } from '@/lib/queries'
import { Building2, AlertCircle, CheckCircle2, MapPin, FileText, Phone } from 'lucide-react'

export function OnboardingPage() {
  const { reloadUser } = useAuth()
  const navigate = useNavigate()
  const [step, setStep] = useState(1)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const [form, setForm] = useState({
    name: '',
    legal_name: '',
    siren: '',
    vat_number: '',
    address: '',
    city: '',
    postal_code: '',
    country: 'France',
    currency: 'EUR',
    email: '',
    phone: '',
  })

  function update<K extends keyof typeof form>(key: K, value: string) {
    setForm((prev) => ({ ...prev, [key]: value }))
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setError(null)
    if (!form.name.trim()) {
      setError("Le nom de l'entreprise est obligatoire")
      return
    }
    setLoading(true)
    const { success, error: createError } = await createTenantForUser({
      name: form.name.trim(),
      legal_name: form.legal_name.trim() || form.name.trim(),
      siren: form.siren.trim() || undefined,
      vat_number: form.vat_number.trim() || undefined,
      address: form.address.trim() || undefined,
      city: form.city.trim() || undefined,
      postal_code: form.postal_code.trim() || undefined,
      country: form.country || 'France',
      currency: form.currency || 'EUR',
      email: form.email.trim() || undefined,
      phone: form.phone.trim() || undefined,
    })
    if (!success || createError) {
      setError(createError || 'Erreur lors de la création')
      setLoading(false)
      return
    }
    await reloadUser()
    navigate('/')
  }

  function nextStep() {
    if (step === 1 && !form.name.trim()) {
      setError("Le nom de l'entreprise est obligatoire")
      return
    }
    setError(null)
    setStep((s) => Math.min(s + 1, 3))
  }

  function prevStep() {
    setError(null)
    setStep((s) => Math.max(s - 1, 1))
  }

  const steps = [
    { num: 1, label: 'Entreprise', icon: Building2 },
    { num: 2, label: 'Adresse', icon: MapPin },
    { num: 3, label: 'Confirmation', icon: CheckCircle2 },
  ]

  return (
    <div className="min-h-screen flex items-center justify-center bg-[var(--color-neutral-50)] p-4">
      <div className="w-full max-w-2xl">
        <div className="text-center mb-8">
          <div className="inline-flex items-center justify-center w-16 h-16 rounded-2xl bg-[var(--color-primary)] text-white mb-4">
            <Building2 className="w-8 h-8" />
          </div>
          <h1 className="text-2xl font-bold text-[var(--color-text)]">Bienvenue sur ERP Compta</h1>
          <p className="text-sm text-[var(--color-text-secondary)] mt-1">
            Configurez votre entreprise en quelques étapes pour commencer
          </p>
        </div>

        {/* Stepper */}
        <div className="flex items-center justify-center gap-2 mb-6">
          {steps.map((s, i) => {
            const Icon = s.icon
            const active = step === s.num
            const done = step > s.num
            return (
              <div key={s.num} className="flex items-center">
                <div
                  className={`flex items-center gap-2 px-3 py-1.5 rounded-full text-sm font-medium transition-colors ${
                    active
                      ? 'bg-[var(--color-primary)] text-white'
                      : done
                        ? 'bg-[rgba(0,135,90,0.1)] text-[var(--color-success)]'
                        : 'bg-[var(--color-neutral-100)] text-[var(--color-text-secondary)]'
                  }`}
                >
                  <Icon className="w-4 h-4" />
                  <span>{s.label}</span>
                </div>
                {i < steps.length - 1 && (
                  <div className={`w-8 h-px ${done ? 'bg-[var(--color-success)]' : 'bg-[var(--color-neutral-200)]'}`} />
                )}
              </div>
            )
          })}
        </div>

        <form onSubmit={handleSubmit} className="card p-6 space-y-4">
          {error && (
            <div className="flex items-center gap-2 p-3 rounded-lg bg-[rgba(222,53,11,0.08)] border border-[var(--color-danger)] text-sm text-[var(--color-danger)]">
              <AlertCircle className="w-4 h-4 flex-shrink-0" />
              <span>{error}</span>
            </div>
          )}

          {/* Step 1: Company info */}
          {step === 1 && (
            <div className="space-y-4">
              <div className="space-y-1.5">
                <label className="text-sm font-medium text-[var(--color-text)]">
                  Nom de l'entreprise <span className="text-[var(--color-danger)]">*</span>
                </label>
                <div className="relative">
                  <Building2 className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-[var(--color-text-secondary)]" />
                  <input
                    type="text"
                    required
                    value={form.name}
                    onChange={(e) => update('name', e.target.value)}
                    placeholder="Mon Entreprise SARL"
                    className="input pl-10"
                    autoFocus
                  />
                </div>
              </div>

              <div className="space-y-1.5">
                <label className="text-sm font-medium text-[var(--color-text)]">Raison sociale</label>
                <input
                  type="text"
                  value={form.legal_name}
                  onChange={(e) => update('legal_name', e.target.value)}
                  placeholder="Mon Entreprise SARL (si différent)"
                  className="input"
                />
              </div>

              <div className="grid grid-cols-2 gap-4">
                <div className="space-y-1.5">
                  <label className="text-sm font-medium text-[var(--color-text)]">SIREN</label>
                  <div className="relative">
                    <FileText className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-[var(--color-text-secondary)]" />
                    <input
                      type="text"
                      value={form.siren}
                      onChange={(e) => update('siren', e.target.value)}
                      placeholder="123 456 789"
                      className="input pl-10"
                    />
                  </div>
                </div>
                <div className="space-y-1.5">
                  <label className="text-sm font-medium text-[var(--color-text)]">N° TVA</label>
                  <input
                    type="text"
                    value={form.vat_number}
                    onChange={(e) => update('vat_number', e.target.value)}
                    placeholder="FR12345678901"
                    className="input"
                  />
                </div>
              </div>

              <div className="grid grid-cols-2 gap-4">
                <div className="space-y-1.5">
                  <label className="text-sm font-medium text-[var(--color-text)]">Devise</label>
                  <select
                    value={form.currency}
                    onChange={(e) => update('currency', e.target.value)}
                    className="input"
                  >
                    <option value="EUR">Euro (€)</option>
                    <option value="USD">Dollar US ($)</option>
                    <option value="GBP">Livre (£)</option>
                    <option value="CHF">Franc suisse (CHF)</option>
                    <option value="MAD">Dirham marocain (MAD)</option>
                    <option value="XOF">Franc CFA (XOF)</option>
                  </select>
                </div>
                <div className="space-y-1.5">
                  <label className="text-sm font-medium text-[var(--color-text)]">Pays</label>
                  <select
                    value={form.country}
                    onChange={(e) => update('country', e.target.value)}
                    className="input"
                  >
                    <option value="France">France</option>
                    <option value="Belgique">Belgique</option>
                    <option value="Suisse">Suisse</option>
                    <option value="Maroc">Maroc</option>
                    <option value="Sénégal">Sénégal</option>
                    <option value="Côte d'Ivoire">Côte d'Ivoire</option>
                  </select>
                </div>
              </div>
            </div>
          )}

          {/* Step 2: Address & Contact */}
          {step === 2 && (
            <div className="space-y-4">
              <div className="space-y-1.5">
                <label className="text-sm font-medium text-[var(--color-text)]">Adresse</label>
                <div className="relative">
                  <MapPin className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-[var(--color-text-secondary)]" />
                  <input
                    type="text"
                    value={form.address}
                    onChange={(e) => update('address', e.target.value)}
                    placeholder="12 rue de la Paix"
                    className="input pl-10"
                    autoFocus
                  />
                </div>
              </div>

              <div className="grid grid-cols-2 gap-4">
                <div className="space-y-1.5">
                  <label className="text-sm font-medium text-[var(--color-text)]">Code postal</label>
                  <input
                    type="text"
                    value={form.postal_code}
                    onChange={(e) => update('postal_code', e.target.value)}
                    placeholder="75001"
                    className="input"
                  />
                </div>
                <div className="space-y-1.5">
                  <label className="text-sm font-medium text-[var(--color-text)]">Ville</label>
                  <input
                    type="text"
                    value={form.city}
                    onChange={(e) => update('city', e.target.value)}
                    placeholder="Paris"
                    className="input"
                  />
                </div>
              </div>

              <div className="space-y-1.5">
                <label className="text-sm font-medium text-[var(--color-text)]">Email</label>
                <input
                  type="email"
                  value={form.email}
                  onChange={(e) => update('email', e.target.value)}
                  placeholder="contact@entreprise.fr"
                  className="input"
                />
              </div>

              <div className="space-y-1.5">
                <label className="text-sm font-medium text-[var(--color-text)]">Téléphone</label>
                <div className="relative">
                  <Phone className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-[var(--color-text-secondary)]" />
                  <input
                    type="tel"
                    value={form.phone}
                    onChange={(e) => update('phone', e.target.value)}
                    placeholder="01 23 45 67 89"
                    className="input pl-10"
                  />
                </div>
              </div>
            </div>
          )}

          {/* Step 3: Confirmation */}
          {step === 3 && (
            <div className="space-y-4">
              <div className="flex items-center gap-3 p-4 rounded-lg bg-[rgba(0,135,90,0.08)] border border-[var(--color-success)]">
                <CheckCircle2 className="w-5 h-5 text-[var(--color-success)] flex-shrink-0" />
                <div>
                  <p className="text-sm font-medium text-[var(--color-text)]">Prêt à créer votre entreprise</p>
                  <p className="text-xs text-[var(--color-text-secondary)] mt-0.5">
                    Vérifiez les informations ci-dessous et cliquez sur « Créer »
                  </p>
                </div>
              </div>

              <div className="space-y-2 text-sm">
                <div className="flex justify-between py-2 border-b border-[var(--color-neutral-100)]">
                  <span className="text-[var(--color-text-secondary)]">Nom</span>
                  <span className="font-medium text-[var(--color-text)]">{form.name}</span>
                </div>
                {form.legal_name && form.legal_name !== form.name && (
                  <div className="flex justify-between py-2 border-b border-[var(--color-neutral-100)]">
                    <span className="text-[var(--color-text-secondary)]">Raison sociale</span>
                    <span className="font-medium text-[var(--color-text)]">{form.legal_name}</span>
                  </div>
                )}
                {form.siren && (
                  <div className="flex justify-between py-2 border-b border-[var(--color-neutral-100)]">
                    <span className="text-[var(--color-text-secondary)]">SIREN</span>
                    <span className="font-medium text-[var(--color-text)]">{form.siren}</span>
                  </div>
                )}
                {form.vat_number && (
                  <div className="flex justify-between py-2 border-b border-[var(--color-neutral-100)]">
                    <span className="text-[var(--color-text-secondary)]">N° TVA</span>
                    <span className="font-medium text-[var(--color-text)]">{form.vat_number}</span>
                  </div>
                )}
                {form.address && (
                  <div className="flex justify-between py-2 border-b border-[var(--color-neutral-100)]">
                    <span className="text-[var(--color-text-secondary)]">Adresse</span>
                    <span className="font-medium text-[var(--color-text)] text-right">
                      {form.address}{form.postal_code ? `, ${form.postal_code}` : ''}{form.city ? ` ${form.city}` : ''}
                    </span>
                  </div>
                )}
                <div className="flex justify-between py-2 border-b border-[var(--color-neutral-100)]">
                  <span className="text-[var(--color-text-secondary)]">Pays / Devise</span>
                  <span className="font-medium text-[var(--color-text)]">{form.country} / {form.currency}</span>
                </div>
                {form.email && (
                  <div className="flex justify-between py-2 border-b border-[var(--color-neutral-100)]">
                    <span className="text-[var(--color-text-secondary)]">Email</span>
                    <span className="font-medium text-[var(--color-text)]">{form.email}</span>
                  </div>
                )}
                {form.phone && (
                  <div className="flex justify-between py-2">
                    <span className="text-[var(--color-text-secondary)]">Téléphone</span>
                    <span className="font-medium text-[var(--color-text)]">{form.phone}</span>
                  </div>
                )}
              </div>

              <div className="p-3 rounded-lg bg-[var(--color-neutral-50)] text-xs text-[var(--color-text-secondary)]">
                <p>
                  Votre compte sera créé avec un essai gratuit de 30 jours.
                  Vous serez l'administrateur de cette entreprise et pourrez inviter des collaborateurs.
                </p>
              </div>
            </div>
          )}

          {/* Navigation buttons */}
          <div className="flex items-center justify-between pt-2">
            {step > 1 ? (
              <Button type="button" variant="secondary" onClick={prevStep} disabled={loading}>
                Retour
              </Button>
            ) : (
              <div />
            )}

            {step < 3 ? (
              <Button type="button" onClick={nextStep} disabled={loading}>
                Continuer
              </Button>
            ) : (
              <Button type="submit" disabled={loading}>
                {loading ? 'Création...' : 'Créer mon entreprise'}
              </Button>
            )}
          </div>
        </form>

        <p className="text-center text-xs text-[var(--color-text-secondary)] mt-6">
          ERP Compta — Solution de gestion d'entreprise
        </p>
      </div>
    </div>
  )
}
