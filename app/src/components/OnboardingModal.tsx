import { useState } from 'react'
import { useTranslation } from 'react-i18next'
import { X, ArrowRight, ArrowLeft, Check, Rocket, Building2, Users, Banknote, Sparkles } from 'lucide-react'
import { cn } from '@/lib/utils'

// Le guide de bienvenue — une fois par compte (`compta-onboarded`).
//
// Ses textes vivaient ici, en français et sans accents (« Votre comptabilite,
// simplifiee et augmentee », mesuré le 29/09/2026) : ils sont désormais dans
// l'espace `common` sous `guide.*`, en fr / en / ar, et le contrôle de parité
// i18n couvre chaque clé une par une. Seules les icônes restent dans le code.
const STEPS = [
  { icon: Rocket, key: 's1' },
  { icon: Building2, key: 's2' },
  { icon: Users, key: 's3' },
  { icon: Banknote, key: 's4' },
  { icon: Sparkles, key: 's5' },
]

export function OnboardingModal({ open, onClose }: { open: boolean; onClose: () => void }) {
  const { t } = useTranslation('common')
  const [step, setStep] = useState(0)
  if (!open) return null

  const isLast = step === STEPS.length - 1
  const current = STEPS[step]
  const key = `guide.${current.key}`
  const items = [1, 2, 3, 4].map((n) => t(`${key}Item${n}`))
  const tip = t(`${key}Tip`, { defaultValue: '' })
  const Icon = current.icon

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl animate-scale-in max-h-[90vh] overflow-y-auto" style={{ width: '100%', maxWidth: '32rem' }}>
        {/* Header */}
        <div className="relative px-6 pt-6 pb-4 bg-gradient-to-br from-[var(--color-primary)] to-purple-600 text-white">
          <button onClick={onClose} aria-label={t('actions.close')} title={t('actions.close')} className="absolute top-4 right-4 min-w-6 min-h-6 flex items-center justify-center text-white/80 hover:text-white">
            <X className="w-5 h-5" />
          </button>
          <div className="flex items-center gap-3">
            <div className="w-12 h-12 rounded-xl bg-white/20 flex items-center justify-center">
              <Icon className="w-6 h-6" />
            </div>
            <div>
              <h2 className="text-lg font-bold">{t(`${key}Title`)}</h2>
              <p className="text-sm text-white/80">{t(`${key}Subtitle`)}</p>
            </div>
          </div>
        </div>

        {/* Progress bar */}
        <div className="px-6 pt-4">
          <div className="flex gap-1.5">
            {STEPS.map((_, i) => (
              <div
                key={i}
                className={cn(
                  'h-1.5 flex-1 rounded-full transition-colors',
                  i <= step ? 'bg-[var(--color-primary)]' : 'bg-[var(--color-neutral-200)]'
                )}
              />
            ))}
          </div>
        </div>

        {/* Content */}
        <div className="px-6 py-5">
          <p className="text-sm text-[var(--color-text-secondary)] mb-4">{t(`${key}Intro`)}</p>
          <ul className="space-y-2">
            {items.map((item, i) => (
              <li key={i} className="flex items-center gap-2 text-sm text-[var(--color-text)]">
                <span className="w-5 h-5 rounded-full bg-[rgba(0,135,90,0.1)] flex items-center justify-center flex-shrink-0">
                  <Check className="w-3 h-3 text-[var(--color-success)]" />
                </span>
                {item}
              </li>
            ))}
          </ul>
          {tip && (
            <div className="mt-4 p-3 rounded-lg bg-[rgba(0,102,204,0.08)] border border-[var(--color-primary)]">
              <p className="text-xs text-[var(--color-primary)] font-medium">{tip}</p>
            </div>
          )}
        </div>

        {/* Footer */}
        <div className="flex items-center justify-between px-6 py-4 border-t border-[var(--color-border)]">
          <button
            onClick={() => (step === 0 ? onClose() : setStep(step - 1))}
            className="flex items-center gap-1 min-h-6 text-sm text-[var(--color-text-secondary)] hover:text-[var(--color-text)]"
          >
            {step === 0 ? t('guide.skip') : (<><ArrowLeft className="w-4 h-4" /> {t('guide.previous')}</>)}
          </button>
          <button
            onClick={() => (isLast ? onClose() : setStep(step + 1))}
            className="btn btn-primary"
          >
            {isLast ? t('guide.start') : t('guide.next')}
            <ArrowRight className="w-4 h-4" />
          </button>
        </div>
      </div>
    </div>
  )
}
