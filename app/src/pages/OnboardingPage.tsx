import { useState, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { useTranslation } from 'react-i18next'
import { useAuth } from '@/lib/auth'
import { Button } from '@/components/ui'
import { createTenantForUser, getLegislationPacks, getApplicableVatRates } from '@/lib/queries'
import type { LegislationPack, TaxRate } from '@/types'
import { Building2, AlertCircle, CheckCircle2, MapPin, FileText, Phone, Scale, LayoutGrid } from 'lucide-react'
import { COUNTRIES, CURRENCIES } from '@/lib/countries'
import { SearchableSelect } from '@/components/SearchableSelect'

export function OnboardingPage() {
  const { t } = useTranslation('auth')
  const { user, reloadUser } = useAuth()
  const navigate = useNavigate()
  const [step, setStep] = useState(1)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [legislationPacks, setLegislationPacks] = useState<LegislationPack[]>([])
  const [selectedPack, setSelectedPack] = useState<LegislationPack | null>(null)
  const [packTaxRates, setPackTaxRates] = useState<TaxRate[]>([])

  useEffect(() => {
    getLegislationPacks().then(setLegislationPacks).catch(() => {})
  }, [])

  // When a legislation pack is selected, auto-fill currency/country and fetch VAT rates
  useEffect(() => {
    if (!selectedPack) return
    setForm((prev) => ({
      ...prev,
      currency: selectedPack.currency,
      country: selectedPack.country_name,
      legislation_pack_code: selectedPack.code,
    }))
    getApplicableVatRates(selectedPack.code).then(setPackTaxRates).catch(() => setPackTaxRates([]))
  }, [selectedPack])

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
    legislation_pack_code: '',
  })

  const [selectedModules, setSelectedModules] = useState<string[]>([
    'home', 'accounting', 'commercial', 'treasury', 'system',
  ])

  const selectableModules = [
    { id: 'accounting', icon: '📚', color: 'indigo' },
    { id: 'commercial', icon: '🛒', color: 'emerald' },
    { id: 'treasury', icon: '💰', color: 'amber' },
    { id: 'stock', icon: '📦', color: 'violet' },
    { id: 'production', icon: '🏭', color: 'rose' },
    { id: 'hr', icon: '👥', color: 'cyan' },
    { id: 'dashboards', icon: '📊', color: 'teal' },
    { id: 'reporting', icon: '📈', color: 'fuchsia' },
  ]

  function toggleModule(moduleId: string) {
    setSelectedModules((prev) =>
      prev.includes(moduleId)
        ? prev.filter((m) => m !== moduleId)
        : [...prev, moduleId],
    )
  }

  function update<K extends keyof typeof form>(key: K, value: string) {
    setForm((prev) => ({ ...prev, [key]: value }))
  }

  const [created, setCreated] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setError(null)
    if (!form.name.trim()) {
      setError(t('onboarding.companyNameRequired'))
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
      legislation_pack_code: form.legislation_pack_code || undefined,
      enabled_modules: ['home', ...selectedModules, 'system'],
    })
    if (!success || createError) {
      setError(createError || t('onboarding.createError'))
      setLoading(false)
      return
    }
    await reloadUser()
    setCreated(true)
  }

  // Redirect to dashboard only after user state has been refreshed with tenantId
  useEffect(() => {
    if (created && user?.tenantId) {
      navigate('/', { replace: true })
    }
  }, [created, user, navigate])

  function nextStep() {
    if (step === 1 && !form.name.trim()) {
      setError(t('onboarding.companyNameRequired'))
      return
    }
    if (step === 4 && selectedModules.length === 0) {
      setError(t('onboarding.selectAtLeastOneModule'))
      return
    }
    setError(null)
    setStep((s) => Math.min(s + 1, 5))
  }

  function prevStep() {
    setError(null)
    setStep((s) => Math.max(s - 1, 1))
  }

  const steps = [
    { num: 1, label: t('onboarding.steps.company'), icon: Building2 },
    { num: 2, label: t('onboarding.legislation'), icon: Scale },
    { num: 3, label: t('onboarding.steps.address'), icon: MapPin },
    { num: 4, label: t('onboarding.steps.modules'), icon: LayoutGrid },
    { num: 5, label: t('onboarding.steps.confirmation'), icon: CheckCircle2 },
  ]

  return (
    <div className="min-h-screen flex items-center justify-center bg-[var(--color-neutral-50)] p-4">
      <div className="w-full max-w-2xl">
        <div className="text-center mb-8">
          <div className="inline-flex items-center justify-center w-16 h-16 rounded-2xl bg-[var(--color-primary)] text-white mb-4">
            <Building2 className="w-8 h-8" />
          </div>
          <h1 className="text-2xl font-bold text-[var(--color-text)]">{t('onboarding.title')}</h1>
          <p className="text-sm text-[var(--color-text-secondary)] mt-1">
            {t('onboarding.subtitle')}
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

        <form onSubmit={step === 5 ? handleSubmit : (e) => e.preventDefault()} className="card p-6 space-y-4">
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
                  {t('onboarding.companyName')} <span className="text-[var(--color-danger)]">*</span>
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
                <label className="text-sm font-medium text-[var(--color-text)]">{t('onboarding.legalName')}</label>
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
                  <label className="text-sm font-medium text-[var(--color-text)]">{t('onboarding.siren')}</label>
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
                  <label className="text-sm font-medium text-[var(--color-text)]">{t('onboarding.vatNumber')}</label>
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
                  <label className="text-sm font-medium text-[var(--color-text)]">{t('onboarding.currency')}</label>
                  <SearchableSelect
                    value={form.currency}
                    onChange={(v) => update('currency', v)}
                    options={CURRENCIES.map((c) => ({ value: c.code, label: c.label }))}
                    searchPlaceholder={t('onboarding.searchCurrency')}
                    placeholder={t('onboarding.selectCurrency')}
                    className="w-full"
                  />
                </div>
                <div className="space-y-1.5">
                  <label className="text-sm font-medium text-[var(--color-text)]">{t('onboarding.country')}</label>
                  <SearchableSelect
                    value={form.country}
                    onChange={(v) => update('country', v)}
                    options={COUNTRIES.map((c) => ({ value: c, label: c }))}
                    searchPlaceholder={t('onboarding.searchCountry')}
                    placeholder={t('onboarding.selectCountry')}
                    className="w-full"
                  />
                </div>
              </div>
            </div>
          )}

          {/* Step 2: Legislation pack */}
          {step === 2 && (
            <div className="space-y-4">
              <div className="text-center mb-2">
                <Scale className="w-8 h-8 mx-auto text-[var(--color-primary)] mb-2" />
                <h3 className="text-sm font-semibold text-[var(--color-text)]">{t('onboarding.legislation')}</h3>
                <p className="text-xs text-[var(--color-text-secondary)] mt-1">{t('onboarding.legislationSubtitle')}</p>
              </div>

              <div className="space-y-1.5">
                <label className="text-sm font-medium text-[var(--color-text)]">{t('onboarding.legislationPack')}</label>
                <SearchableSelect
                  value={form.legislation_pack_code}
                  onChange={(code) => {
                    const pack = legislationPacks.find((p) => p.code === code)
                    if (pack) setSelectedPack(pack)
                    update('legislation_pack_code', code)
                  }}
                  options={legislationPacks.map((p) => ({
                    value: p.code,
                    label: `${p.country_name} — ${p.accounting_standard} (${p.currency})`,
                  }))}
                  searchPlaceholder={t('onboarding.legislationPackPlaceholder')}
                  placeholder={t('onboarding.legislationPackPlaceholder')}
                  className="w-full"
                />
                <p className="text-xs text-[var(--color-text-secondary)]">{t('onboarding.legislationPackHint')}</p>
              </div>

              {selectedPack && (
                <div className="grid grid-cols-2 gap-4 p-4 rounded-lg bg-[var(--color-neutral-50)] border border-[var(--color-neutral-200)]">
                  <div>
                    <p className="text-xs text-[var(--color-text-secondary)]">{t('onboarding.country')}</p>
                    <p className="text-sm font-medium text-[var(--color-text)]">{selectedPack.country_name}</p>
                  </div>
                  <div>
                    <p className="text-xs text-[var(--color-text-secondary)]">{t('onboarding.standard')}</p>
                    <p className="text-sm font-medium text-[var(--color-text)]">{selectedPack.accounting_standard}</p>
                  </div>
                  <div>
                    <p className="text-xs text-[var(--color-text-secondary)]">{t('onboarding.currency')}</p>
                    <p className="text-sm font-medium text-[var(--color-text)]">{selectedPack.currency}</p>
                  </div>
                  <div>
                    <p className="text-xs text-[var(--color-text-secondary)]">{t('onboarding.fiscalYearStart')}</p>
                    <p className="text-sm font-medium text-[var(--color-text)]">{selectedPack.fiscal_year_start}</p>
                  </div>
                </div>
              )}

              {packTaxRates.length > 0 && (
                <div className="space-y-2">
                  <p className="text-xs font-medium text-[var(--color-text-secondary)]">{t('onboarding.taxRates')}</p>
                  <div className="flex flex-wrap gap-2">
                    {packTaxRates.map((rate) => (
                      <span
                        key={rate.id}
                        className={`inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-xs font-medium ${
                          rate.is_default
                            ? 'bg-[var(--color-primary)] text-white'
                            : 'bg-[var(--color-neutral-100)] text-[var(--color-text)]'
                        }`}
                      >
                        {rate.name} — {rate.rate.toFixed(1)}%
                      </span>
                    ))}
                  </div>
                </div>
              )}

              {selectedPack && (
                <div className="p-3 rounded-lg bg-[rgba(0,135,90,0.08)] border border-[var(--color-success)] text-xs text-[var(--color-text-secondary)]">
                  <p>{t('onboarding.autoLoadedChart')}</p>
                  <p>{t('onboarding.autoLoadedVat')}</p>
                </div>
              )}
            </div>
          )}

          {/* Step 3: Address & Contact */}
          {step === 3 && (
            <div className="space-y-4">
              <div className="space-y-1.5">
                <label className="text-sm font-medium text-[var(--color-text)]">{t('onboarding.address')}</label>
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
                  <label className="text-sm font-medium text-[var(--color-text)]">{t('onboarding.zipCode')}</label>
                  <input
                    type="text"
                    value={form.postal_code}
                    onChange={(e) => update('postal_code', e.target.value)}
                    placeholder="75001"
                    className="input"
                  />
                </div>
                <div className="space-y-1.5">
                  <label className="text-sm font-medium text-[var(--color-text)]">{t('onboarding.city')}</label>
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
                <label className="text-sm font-medium text-[var(--color-text)]">{t('onboarding.email')}</label>
                <input
                  type="email"
                  value={form.email}
                  onChange={(e) => update('email', e.target.value)}
                  placeholder="contact@entreprise.fr"
                  className="input"
                />
              </div>

              <div className="space-y-1.5">
                <label className="text-sm font-medium text-[var(--color-text)]">{t('onboarding.phone')}</label>
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

          {/* Step 4: Module selection */}
          {step === 4 && (
            <div className="space-y-4">
              <div className="text-center mb-2">
                <LayoutGrid className="w-8 h-8 mx-auto text-[var(--color-primary)] mb-2" />
                <h3 className="text-sm font-semibold text-[var(--color-text)]">{t('onboarding.modulesTitle')}</h3>
                <p className="text-xs text-[var(--color-text-secondary)] mt-1">{t('onboarding.modulesSubtitle')}</p>
              </div>

              <div className="grid grid-cols-2 gap-3">
                {selectableModules.map((mod) => {
                  const isSelected = selectedModules.includes(mod.id)
                  const modColorVar = `--mod-${mod.color}`
                  const modColorBg = `--mod-${mod.color}-bg`
                  return (
                    <button
                      key={mod.id}
                      type="button"
                      onClick={() => toggleModule(mod.id)}
                      className={`relative flex items-center gap-3 p-4 rounded-xl border transition-all duration-200 text-left overflow-hidden ${
                        isSelected
                          ? 'border-transparent shadow-md'
                          : 'border-[var(--color-border)] bg-[var(--color-surface)] hover:border-[var(--color-neutral-300)] hover:shadow-sm'
                      }`}
                      style={isSelected ? { background: `var(${modColorBg})`, borderColor: `var(${modColorVar})` } : undefined}
                    >
                      <span className="text-2xl flex-shrink-0">{mod.icon}</span>
                      <div className="flex-1 min-w-0">
                        <p
                          className="text-sm font-medium truncate"
                          style={isSelected ? { color: `var(${modColorVar})` } : undefined}
                        >
                          {t(`onboarding.moduleNames.${mod.id}`)}
                        </p>
                        <p className="text-xs text-[var(--color-text-secondary)] truncate">
                          {t(`onboarding.moduleDescriptions.${mod.id}`)}
                        </p>
                      </div>
                      <div
                        className={`w-5 h-5 rounded-full border-2 flex items-center justify-center flex-shrink-0 transition-all ${
                          isSelected ? 'border-transparent' : 'border-[var(--color-neutral-300)]'
                        }`}
                        style={isSelected ? { background: `var(${modColorVar})` } : undefined}
                      >
                        {isSelected && <CheckCircle2 className="w-4 h-4 text-white" />}
                      </div>
                    </button>
                  )
                })}
              </div>

              <div className="p-3 rounded-lg bg-[var(--color-neutral-50)] text-xs text-[var(--color-text-secondary)]">
                <p>{t('onboarding.modulesHint')}</p>
              </div>
            </div>
          )}

          {/* Step 5: Confirmation */}
          {step === 5 && (
            <div className="space-y-4">
              <div className="flex items-center gap-3 p-4 rounded-lg bg-[rgba(0,135,90,0.08)] border border-[var(--color-success)]">
                <CheckCircle2 className="w-5 h-5 text-[var(--color-success)] flex-shrink-0" />
                <div>
                  <p className="text-sm font-medium text-[var(--color-text)]">{t('onboarding.readyToCreate')}</p>
                  <p className="text-xs text-[var(--color-text-secondary)] mt-0.5">
                    {t('onboarding.readyToCreateDescription')}
                  </p>
                </div>
              </div>

              <div className="space-y-2 text-sm">
                <div className="flex justify-between py-2 border-b border-[var(--color-neutral-100)]">
                  <span className="text-[var(--color-text-secondary)]">{t('onboarding.companyName')}</span>
                  <span className="font-medium text-[var(--color-text)]">{form.name}</span>
                </div>
                {form.legal_name && form.legal_name !== form.name && (
                  <div className="flex justify-between py-2 border-b border-[var(--color-neutral-100)]">
                    <span className="text-[var(--color-text-secondary)]">{t('onboarding.legalName')}</span>
                    <span className="font-medium text-[var(--color-text)]">{form.legal_name}</span>
                  </div>
                )}
                {form.siren && (
                  <div className="flex justify-between py-2 border-b border-[var(--color-neutral-100)]">
                    <span className="text-[var(--color-text-secondary)]">{t('onboarding.siren')}</span>
                    <span className="font-medium text-[var(--color-text)]">{form.siren}</span>
                  </div>
                )}
                {form.vat_number && (
                  <div className="flex justify-between py-2 border-b border-[var(--color-neutral-100)]">
                    <span className="text-[var(--color-text-secondary)]">{t('onboarding.vatNumber')}</span>
                    <span className="font-medium text-[var(--color-text)]">{form.vat_number}</span>
                  </div>
                )}
                {form.address && (
                  <div className="flex justify-between py-2 border-b border-[var(--color-neutral-100)]">
                    <span className="text-[var(--color-text-secondary)]">{t('onboarding.address')}</span>
                    <span className="font-medium text-[var(--color-text)] text-right">
                      {form.address}{form.postal_code ? `, ${form.postal_code}` : ''}{form.city ? ` ${form.city}` : ''}
                    </span>
                  </div>
                )}
                <div className="flex justify-between py-2 border-b border-[var(--color-neutral-100)]">
                  <span className="text-[var(--color-text-secondary)]">{t('onboarding.countryCurrency')}</span>
                  <span className="font-medium text-[var(--color-text)]">{form.country} / {form.currency}</span>
                </div>
                {form.legislation_pack_code && (
                  <div className="flex justify-between py-2 border-b border-[var(--color-neutral-100)]">
                    <span className="text-[var(--color-text-secondary)]">{t('onboarding.legislationPack')}</span>
                    <span className="font-medium text-[var(--color-text)]">{form.legislation_pack_code}</span>
                  </div>
                )}
                <div className="flex justify-between py-2 border-b border-[var(--color-neutral-100)]">
                  <span className="text-[var(--color-text-secondary)]">{t('onboarding.selectedModules')}</span>
                  <span className="font-medium text-[var(--color-text)] text-right">
                    {selectedModules.map((m) => t(`onboarding.moduleNames.${m}`)).join(', ')}
                  </span>
                </div>
                {form.email && (
                  <div className="flex justify-between py-2 border-b border-[var(--color-neutral-100)]">
                    <span className="text-[var(--color-text-secondary)]">{t('onboarding.email')}</span>
                    <span className="font-medium text-[var(--color-text)]">{form.email}</span>
                  </div>
                )}
                {form.phone && (
                  <div className="flex justify-between py-2">
                    <span className="text-[var(--color-text-secondary)]">{t('onboarding.phone')}</span>
                    <span className="font-medium text-[var(--color-text)]">{form.phone}</span>
                  </div>
                )}
              </div>

              <div className="p-3 rounded-lg bg-[var(--color-neutral-50)] text-xs text-[var(--color-text-secondary)]">
                <p>
                  {t('onboarding.trialInfo')}
                </p>
              </div>
            </div>
          )}

          {/* Navigation buttons */}
          <div className="flex items-center justify-between pt-2">
            {step > 1 ? (
              <Button type="button" variant="secondary" onClick={prevStep} disabled={loading}>
                {t('onboarding.back')}
              </Button>
            ) : (
              <div />
            )}

            {step < 5 ? (
              <Button type="button" onClick={nextStep} disabled={loading}>
                {t('onboarding.continue')}
              </Button>
            ) : (
              <Button type="submit" disabled={loading}>
                {loading ? t('onboarding.creatingCompany') : t('onboarding.create')}
              </Button>
            )}
          </div>
        </form>

        <p className="text-center text-xs text-[var(--color-text-secondary)] mt-6">
          ERP Compta — {t('onboarding.tagline')}
        </p>
      </div>
    </div>
  )
}
