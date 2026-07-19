import { useState } from 'react'
import { X, ArrowRight, ArrowLeft, Check, Rocket, Building2, Users, Banknote, Sparkles } from 'lucide-react'
import { cn } from '@/lib/utils'

interface StepData {
  icon: React.ComponentType<{ className?: string }>
  title: string
  subtitle: string
  intro: string
  items: string[]
  tip?: string
}

const steps: StepData[] = [
  {
    icon: Rocket,
    title: 'Bienvenue sur Compta !',
    subtitle: 'Votre comptabilite, simplifiee et augmentee',
    intro: 'Nous allons vous guider a travers les fonctionnalites principales en quelques etapes. Vous pourrez revenir a ce guide a tout moment depuis l\'aide.',
    items: [
      'Tableau de bord intelligent',
      'Assistant IA integre',
      'Navigation rapide (Cmd+K)',
      'Mode sombre',
    ],
  },
  {
    icon: Building2,
    title: 'Configurez votre entreprise',
    subtitle: 'Etape 1 sur 4',
    intro: 'Rendez-vous dans Parametres > Entreprise pour configurer votre societe. Ces informations apparaitront automatiquement sur vos factures et documents.',
    items: [
      'Nom et raison sociale',
      'Numero TVA et SIRET',
      'Adresse et coordonnees',
      'Devise et exercice fiscal',
    ],
  },
  {
    icon: Users,
    title: 'Ajoutez vos clients et fournisseurs',
    subtitle: 'Etape 2 sur 4',
    intro: 'Dans les onglets Ventes et Achats, vous pouvez gerer vos relations commerciales et vos transactions.',
    items: [
      'Creer des fiches clients et fournisseurs',
      'Envoyer des factures et devis',
      'Suivre les paiements et relances',
      'Enregistrer les factures d\'achat',
    ],
  },
  {
    icon: Banknote,
    title: 'Connectez votre banque',
    subtitle: 'Etape 3 sur 4',
    intro: 'Dans l\'onglet Banque, connectez vos comptes pour automatiser votre comptabilite.',
    items: [
      'Importer automatiquement vos transactions',
      'Categoriser avec des regles automatiques',
      'Reconcilier en un clic',
      'Suivre votre tresorerie en temps reel',
    ],
  },
  {
    icon: Sparkles,
    title: 'Utilisez l\'Assistant IA',
    subtitle: 'Etape 4 sur 4',
    intro: 'Cliquez sur "Assistant IA" en haut a droite pour obtenir de l\'aide a tout moment.',
    items: [
      'Analyser votre tresorerie',
      'Identifier les factures en retard',
      'Preparer votre declaration de TVA',
      'Obtenir des conseils personnalises',
    ],
    tip: 'Astuce: Appuyez sur Cmd+K (Mac) ou Ctrl+K (Windows) pour ouvrir la recherche rapide a tout moment !',
  },
]

export function OnboardingModal({ open, onClose }: { open: boolean; onClose: () => void }) {
  const [step, setStep] = useState(0)
  if (!open) return null

  const isLast = step === steps.length - 1
  const current = steps[step]

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl animate-scale-in overflow-hidden" style={{ width: '100%', maxWidth: '32rem' }}>
        {/* Header */}
        <div className="relative px-6 pt-6 pb-4 bg-gradient-to-br from-[var(--color-primary)] to-purple-600 text-white">
          <button onClick={onClose} className="absolute top-4 right-4 text-white/80 hover:text-white">
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
            {step === 0 ? 'Passer' : (<><ArrowLeft className="w-4 h-4" /> Precedent</>)}
          </button>
          <button
            onClick={() => (isLast ? onClose() : setStep(step + 1))}
            className="btn btn-primary"
          >
            {isLast ? 'Commencer' : 'Suivant'}
            <ArrowRight className="w-4 h-4" />
          </button>
        </div>
      </div>
    </div>
  )
}
