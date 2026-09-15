import { useState, useCallback } from 'react'
import { Card, PageHeader, Breadcrumb, Button, Badge } from '@/components/ui'
import { getOnboardingState, updateOnboardingStep, isOnboardingComplete } from '@/lib/queries/admin'
import { CheckCircle, Circle } from 'lucide-react'
import { useTranslation } from 'react-i18next'
import { useToast } from '@/lib/toast'

const STEPS = [
  { key: 'step_identity', label: 'Identité et forme juridique' },
  { key: 'step_legislation', label: 'Législation et devise' },
  { key: 'step_fiscal_year', label: 'Exercice et périodicité' },
  { key: 'step_chart_accounts', label: 'Plan comptable' },
  { key: 'step_journals', label: 'Journaux' },
  { key: 'step_default_accounts', label: 'Comptes par défaut' },
  { key: 'step_vat_rates', label: 'Taux de TVA' },
  { key: 'step_payment_methods', label: 'Modes de règlement' },
  { key: 'step_stock_valuation', label: 'Méthode de valorisation de stock' },
  { key: 'step_users', label: 'Utilisateurs' },
]

export function OnboardingDashboardPage() {
  const { t: tNav } = useTranslation('nav')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [state, setState] = useState<any>(null)
  const [complete, setComplete] = useState(false)

  const loadData = useCallback(async () => {
    try {
      const [s, c] = await Promise.all([getOnboardingState(), isOnboardingComplete()])
      setState(s)
      setComplete(c)
    } catch (err: any) { console.error('Error:', err); toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadError')) }
  }, [toast, tCommon])

  loadData().catch(err => console.error('loadData:', err))

  const handleToggle = async (step: string) => {
    try {
      const current = state?.[step] || false
      await updateOnboardingStep(step, !current)
      await loadData()
    } catch (err: any) { console.error('Error:', err); toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadError')) }
  }

  const completedCount = STEPS.filter(s => state?.[s.key]).length
  const progress = Math.round((completedCount / STEPS.length) * 100)

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('settings'), path: '/settings' }, { label: 'Onboarding' }]} />
      <PageHeader title="Assistant de paramétrage" />

      <Card className="mb-4">
        <div className="flex items-center justify-between mb-4">
          <div>
            <h3 className="text-lg font-semibold">Progression</h3>
            <p className="text-sm text-gray-500">{completedCount}/{STEPS.length} étapes complétées</p>
          </div>
          {complete ? (
            <Badge variant="success">Paramétrage complet</Badge>
          ) : (
            <Badge variant="warning">Paramétrage incomplet</Badge>
          )}
        </div>
        <div className="w-full bg-gray-200 rounded-full h-3">
          <div className="bg-blue-600 h-3 rounded-full transition-all" style={{ width: `${progress}%` }} />
        </div>
      </Card>

      <Card>
        <div className="space-y-2">
          {STEPS.map((step, idx) => {
            const done = state?.[step.key] || false
            return (
              <div key={step.key} className="flex items-center justify-between p-3 border rounded-lg hover:bg-gray-50">
                <div className="flex items-center gap-3">
                  {done ? (
                    <CheckCircle className="w-5 h-5 text-green-600" />
                  ) : (
                    <Circle className="w-5 h-5 text-gray-400" />
                  )}
                  <span className="font-medium">{idx + 1}. {step.label}</span>
                </div>
                <Button variant={done ? 'secondary' : 'primary'} size="sm" onClick={() => handleToggle(step.key)}>
                  {done ? 'Marquer incomplet' : 'Marquer complet'}
                </Button>
              </div>
            )
          })}
        </div>
      </Card>
    </div>
  )
}
