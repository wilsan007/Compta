import { useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Select } from '@/components/ui'
import { useToast } from '@/lib/toast'
import { errorMessage, formatCurrency } from '@/lib/utils'
import { getAnalyticBalance, getAnalyticPlans, getFiscalYears } from '@/lib/queries/accounting'
import { PieChart } from 'lucide-react'

interface Exercice { id: string; code: string; start_date: string; end_date: string }

export function AnalyticBalancePage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  // Corrigé le 2026-10-01 : ces états étaient des tableaux de `any`. Les nommer
  // depuis leur fonction verrouille le contrat — c'est ce qui a révélé que
  // l'agrégat ne portait pas `planId` (le filtre par plan vidait l'écran).
  const [data, setData] = useState<Awaited<ReturnType<typeof getAnalyticBalance>>>([])
  const [plans, setPlans] = useState<Awaited<ReturnType<typeof getAnalyticPlans>>>([])
  const [exercices, setExercices] = useState<Exercice[]>([])
  const [selectedPlan, setSelectedPlan] = useState('')
  const [selectedExercice, setSelectedExercice] = useState('')
  const [loading, setLoading] = useState(true)

  // oxlint-disable-next-line react-hooks/exhaustive-deps -- chargement volontairement limite aux valeurs listees
  useEffect(() => { load() }, [])

  async function load(exerciceId?: string) {
    try {
      const [exercicesRes, p] = await Promise.all([
        getFiscalYears().catch(() => []),
        getAnalyticPlans().catch(() => []),
      ])
      const ex: Exercice[] = (exercicesRes || []) as Exercice[]
      setPlans(p || [])
      setExercices(ex)

      // ANA-03 : la balance porte sur un exercice, pas sur tout l'historique.
      const aujourdhui = new Date().toISOString().slice(0, 10)
      const courant = ex.find((e) => e.start_date <= aujourdhui && e.end_date >= aujourdhui) || ex[0]
      if (!courant) {
        setData([])
        return
      }
      setSelectedExercice(exerciceId || courant.id)
      const res = await getAnalyticBalance(courant.start_date, courant.end_date)
      setData(res)
    } catch (err) {
      console.error('Error loading analytic balance:', err)
      toast('error', tCommon('toast.error'), errorMessage(err) || tCommon('toast.loadingError'))
    } finally {
      setLoading(false)
    }
  }

  async function changerExercice(id: string) {
    const ex = exercices.find((e) => e.id === id)
    if (!ex) return
    setSelectedExercice(id)
    setLoading(true)
    try {
      setData(await getAnalyticBalance(ex.start_date, ex.end_date))
    } catch (err) {
      console.error('Error loading analytic balance:', err)
      toast('error', tCommon('toast.error'), errorMessage(err) || tCommon('toast.loadingError'))
    } finally {
      setLoading(false)
    }
  }

  // Corrigé le 2026-10-01 : le filtre cherchait `d.planId` ET `d.plan_id`, deux
  // propriétés que `getAnalyticBalance` ne renvoyait pas. La condition était donc
  // TOUJOURS fausse : choisir un plan vidait l'écran et ses totaux au lieu de
  // filtrer. L'agrégat porte désormais `planId` (cf. accounting/etats.ts).
  const filtered = selectedPlan ? data.filter((d) => d.planId === selectedPlan) : data
  const totalDebit = filtered.reduce((s, d) => s + d.totalDebit, 0)
  const totalCredit = filtered.reduce((s, d) => s + d.totalCredit, 0)
  const totalAnalytic = filtered.reduce((s, d) => s + d.totalAnalytic, 0)

  return (
    <div>
      <Breadcrumb items={[{ label: t('title') }, { label: t('analyticBalance.breadcrumb') }, { label: t('analyticBalance.title') }]} />
      <PageHeader title={t('analyticBalance.title')} subtitle={t('analyticBalance.subtitle')} />

      {(plans.length > 0 || exercices.length > 0) && (
        <Card className="mb-4">
          <div className="p-4 grid grid-cols-1 md:grid-cols-2 gap-4">
            {exercices.length > 0 && (
              <Select
                label={t('analyticBalance.fiscalYear')}
                value={selectedExercice}
                onChange={(e) => changerExercice(e.target.value)}
                options={exercices.map((ex) => ({ value: ex.id, label: `${ex.code} (${ex.start_date} → ${ex.end_date})` }))}
              />
            )}
            {plans.length > 0 && (
              <Select
                label={t('analyticBalance.plan')}
                value={selectedPlan}
                onChange={(e) => setSelectedPlan(e.target.value)}
                options={[{ value: '', label: tCommon('common.all') }, ...plans.map((p) => ({ value: p.id, label: `${p.code} — ${p.name}` }))]}
              />
            )}
          </div>
        </Card>
      )}

      {loading ? (
        <SkeletonTable rows={6} cols={5} />
      ) : filtered.length === 0 ? (
        <EmptyState
          icon={<PieChart className="w-8 h-8" />}
          title={t('analyticBalance.noData')}
          description={t('analyticBalance.noDataDescription')}
        />
      ) : (
        <div className="space-y-4">
          <div className="grid grid-cols-3 gap-4">
            <div className="card p-4">
              <p className="text-xs text-[var(--color-text-secondary)] mb-1">{t('analyticBalance.totalDebit')}</p>
              <p className="text-lg font-bold font-mono">{formatCurrency(totalDebit)}</p>
            </div>
            <div className="card p-4">
              <p className="text-xs text-[var(--color-text-secondary)] mb-1">{t('analyticBalance.totalCredit')}</p>
              <p className="text-lg font-bold font-mono">{formatCurrency(totalCredit)}</p>
            </div>
            <div className="card p-4">
              <p className="text-xs text-[var(--color-text-secondary)] mb-1">{t('analyticBalance.totalAnalytic')}</p>
              <p className="text-lg font-bold font-mono text-[var(--color-primary)]">{formatCurrency(totalAnalytic)}</p>
            </div>
          </div>

          <Card>
            <Table headers={[t('analyticBalance.code'), t('analyticBalance.section'), t('analyticDistribution.plan'), t('analyticBalance.debit'), t('analyticBalance.credit'), t('analyticBalance.analyticAmount'), t('analyticBalance.balance')]}>
              {filtered.map((d) => {
                const plan = plans.find((p) => p.id === d.planId)
                return (
                <TableRow key={d.sectionId}>
                  <TableCell className="font-mono text-xs font-semibold">{d.sectionCode}</TableCell>
                  <TableCell className="text-sm">{d.sectionName}</TableCell>
                  <TableCell className="text-xs text-[var(--color-text-secondary)]">{plan ? `${plan.code} — ${plan.name}` : '—'}</TableCell>
                  <TableCell className="font-mono text-xs text-right">{formatCurrency(d.totalDebit)}</TableCell>
                  <TableCell className="font-mono text-xs text-right">{formatCurrency(d.totalCredit)}</TableCell>
                  <TableCell className="font-mono text-xs font-bold text-[var(--color-primary)] text-right">{formatCurrency(d.totalAnalytic)}</TableCell>
                  <TableCell className="font-mono text-xs text-right">{formatCurrency(d.totalDebit - d.totalCredit)}</TableCell>
                </TableRow>
                )
              })}
              <TableRow>
                <TableCell colSpan={3} className="font-bold">{tCommon('common.total')}</TableCell>
                <TableCell className="font-mono font-bold text-xs text-right">{formatCurrency(totalDebit)}</TableCell>
                <TableCell className="font-mono font-bold text-xs text-right">{formatCurrency(totalCredit)}</TableCell>
                <TableCell className="font-mono font-bold text-xs text-[var(--color-primary)] text-right">{formatCurrency(totalAnalytic)}</TableCell>
                <TableCell className="font-mono font-bold text-xs text-right">{formatCurrency(totalDebit - totalCredit)}</TableCell>
              </TableRow>
            </Table>
          </Card>
        </div>
      )}
    </div>
  )
}
