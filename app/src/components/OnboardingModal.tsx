import { useState } from 'react'
import { useTranslation } from 'react-i18next'
import { X, ArrowRight, ArrowLeft, Check, Rocket, Building2, Users, Banknote, Sparkles } from 'lucide-react'
import { cn } from '@/lib/utils'

interface StepText {
  title: string
  subtitle: string
  intro: string
  items: string[]
  tip?: string
}

// Les textes vivent dans common.json (onboardingTour) : ils étaient écrits en
// dur, en français sans accents, quelle que soit la langue choisie.
const stepIcons: React.ComponentType<{ className?: string }>[] = [Rocket, Building2, Users, Banknote, Sparkles]

export function OnboardingModal({ open, onClose }: { open: boolean; onClose: () => void }) {
  const { t: tCommon } = useTranslation('common')
  const [step, setStep] = useState(0)
  if (!open) return null

  const steps = tCommon('onboardingTour.steps', { returnObjects: true }) as StepText[]
  const isLast = step === steps.length - 1
  const current = { ...steps[step], icon: stepIcons[step] }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl animate-scale-in overflow-hidden" style={{ width: '100%', maxWidth: '32rem' }}>
        {/* Header */}
        <div className="relative px-6 pt-6 pb-4 bg-gradient-to-br from-[var(--color-primary)] to-purple-600 text-white">
          <button onClick={onClose} aria-label={tCommon('actions.close')} title={tCommon('actions.close')} className="absolute top-4 right-4 text-white/80 hover:text-white">
            <X className="w-5 h-5" />
          </button>
          <div className="flex items-center gap-3">
            <div className="w-12 h-12 rounded-xl bg-white/20 flex items-center justify-center">
              <current.icon className="w-6 h-6" />
            </div>
            <div>
              <h2 className="text-lg font-bold">{current.title}</h2>
              <p className="text-sm text-white/80">{current.subtitle}</p>
            </div>
          </div>
        </div>

        {/* Progress bar */}
        <div className="px-6 pt-4">
          <div className="flex gap-1.5">
            {steps.map((_, i) => (
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
          <p className="text-sm text-[var(--color-text-secondary)] mb-4">{current.intro}</p>
          <ul className="space-y-2">
            {current.items.map((item, i) => (
              <li key={i} className="flex items-center gap-2 text-sm text-[var(--color-text)]">
                <span className="w-5 h-5 rounded-full bg-[rgba(0,135,90,0.1)] flex items-center justify-center flex-shrink-0">
                  <Check className="w-3 h-3 text-[var(--color-success)]" />
                </span>
                {item}
              </li>
            ))}
          </ul>
          {current.tip && (
            <div className="mt-4 p-3 rounded-lg bg-[rgba(0,102,204,0.08)] border border-[var(--color-primary)]">
              <p className="text-xs text-[var(--color-primary)] font-medium">{current.tip}</p>
            </div>
          )}
        </div>

        {/* Footer */}
        <div className="flex items-center justify-between px-6 py-4 border-t border-[var(--color-border)]">
          <button
            onClick={() => (step === 0 ? onClose() : setStep(step - 1))}
            className="flex items-center gap-1 text-sm text-[var(--color-text-secondary)] hover:text-[var(--color-text)]"
          >
            {step === 0 ? tCommon('onboardingTour.skip') : (<><ArrowLeft className="w-4 h-4" /> {tCommon('onboardingTour.previous')}</>)}
          </button>
          <button
            onClick={() => (isLast ? onClose() : setStep(step + 1))}
            className="btn btn-primary"
          >
            {isLast ? tCommon('onboardingTour.start') : tCommon('onboardingTour.next')}
            <ArrowRight className="w-4 h-4" />
          </button>
        </div>
      </div>
    </div>
  )
}
