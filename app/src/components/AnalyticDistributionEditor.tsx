import { useState, useEffect, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { X, Plus, Trash2, CheckCircle, Layers } from 'lucide-react'
import { Button, Input, Select } from '@/components/ui'
import { useToast } from '@/lib/toast'
import { getAnalyticPlans } from '@/lib/queries/accounting'
import { getAnalyticSections } from '@/lib/queries/accounting'
import {
  validateDistribution,
  distributeEvenly,
  saveDistributionLines,
  getDistributionLines,
  type AnalyticDistribution,
} from '@/lib/analyticDistribution'
import type { AnalyticPlan, AnalyticSection } from '@/types'

interface AnalyticDistributionEditorProps {
  journalLineId: string | null
  lineAmount: number
  onClose: () => void
  onSaved?: (dist: AnalyticDistribution) => void
}

export function AnalyticDistributionEditor({
  journalLineId,
  lineAmount,
  onClose,
  onSaved,
}: AnalyticDistributionEditorProps) {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [plans, setPlans] = useState<AnalyticPlan[]>([])
  const [sections, setSections] = useState<AnalyticSection[]>([])
  const [dist, setDist] = useState<AnalyticDistribution>({})
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const [p, s] = await Promise.all([
        getAnalyticPlans().catch(() => []),
        getAnalyticSections().catch(() => []),
      ])
      setPlans(p || [])
      setSections(s || [])

      if (journalLineId) {
        const existing = await getDistributionLines(journalLineId)
        setDist(existing)
      }
    } catch (err: any) { console.error("catch:", err); toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadingError'))
      // ignore
    } finally {
      setLoading(false)
    }
  }, [journalLineId, tCommon, toast])

  useEffect(() => {
    loadData().catch(err => console.error('loadData:', err))
  }, [loadData])

  function getSectionsForPlan(planId: string): AnalyticSection[] {
    return sections.filter((s) => s.plan_id === planId || !s.plan_id)
  }

  function addSectionToPlan(planId: string) {
    const planSections = getSectionsForPlan(planId)
    if (planSections.length === 0) return
    setDist((prev) => {
      const next = { ...prev }
      if (!next[planId]) next[planId] = {}
      const firstSection = planSections[0]
      next[planId][firstSection.id] = 0
      return next
    })
  }

  function removeSectionFromPlan(planId: string, sectionId: string) {
    setDist((prev) => {
      const next = { ...prev }
      if (next[planId]) {
        delete next[planId][sectionId]
        if (Object.keys(next[planId]).length === 0) delete next[planId]
      }
      return next
    })
  }

  function updatePercentage(planId: string, sectionId: string, value: number) {
    setDist((prev) => ({
      ...prev,
      [planId]: { ...prev[planId], [sectionId]: value },
    }))
  }

  function handleDistributeEvenly(planId: string) {
    const planSections = getSectionsForPlan(planId)
    const sectionIds = planSections.map((s) => s.id)
    if (sectionIds.length === 0) return
    setDist((prev) => ({
      ...prev,
      [planId]: distributeEvenly(sectionIds),
    }))
  }

  function getPlanSum(planId: string): number {
    if (!dist[planId]) return 0
    return Object.values(dist[planId]).reduce((s, v) => s + (Number(v) || 0), 0)
  }

  async function handleSave() {
    if (!journalLineId) {
      toast('error', tCommon('common.error'), t('analyticDistribution.saveError'))
      return
    }
    if (!validateDistribution(dist)) {
      toast('warning', t('analyticDistribution.title'), t('analyticDistribution.sumMustBe100'))
      return
    }
    setSaving(true)
    try {
      await saveDistributionLines(journalLineId, dist, lineAmount)
      toast('success', t('analyticDistribution.title'), t('analyticDistribution.saved'))
      onSaved?.(dist)
      onClose()
    } catch (e: any) {
      toast('error', tCommon('common.error'), e.message || t('analyticDistribution.saveError'))
    } finally {
      setSaving(false)
    }
  }

  if (loading) {
    return (
      <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
        <div className="card p-6 w-full max-w-2xl">
          <p className="text-sm text-[var(--color-text-secondary)]">Loading...</p>
        </div>
      </div>
    )
  }

  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
      <div className="card p-6 w-full max-w-2xl max-h-[80vh] overflow-y-auto">
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center gap-2">
            <Layers className="w-5 h-5 text-[var(--color-primary)]" />
            <h2 className="text-lg font-bold">{t('analyticDistribution.title')}</h2>
          </div>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]" aria-label={tCommon('actions.close')} title={tCommon('actions.close')}>
            <X className="w-5 h-5" aria-hidden="true" />
          </button>
        </div>

        <p className="text-sm text-[var(--color-text-secondary)] mb-4">
          {t('analyticDistribution.subtitle')}
        </p>

        {plans.length === 0 ? (
          <div className="text-center py-8 text-[var(--color-text-secondary)]">
            {t('analyticDistribution.noPlans')}
          </div>
        ) : (
          <div className="space-y-4">
            {plans.map((plan) => {
              const planDist = dist[plan.id] || {}
              const planSum = getPlanSum(plan.id)
              const planSections = getSectionsForPlan(plan.id)
              const isValid = Math.abs(planSum - 100) < 0.01 || Object.keys(planDist).length === 0

              return (
                <div key={plan.id} className="border border-[var(--color-border)] rounded-lg p-4">
                  <div className="flex items-center justify-between mb-3">
                    <div>
                      <span className="font-semibold text-sm">{plan.code} — {plan.name}</span>
                    </div>
                    <div className="flex items-center gap-2">
                      <span className={`text-xs font-mono ${isValid ? 'text-[var(--color-success)]' : 'text-[var(--color-danger)]'}`}>
                        {t('analyticDistribution.currentSum', { sum: planSum.toFixed(2) })}
                      </span>
                      <Button
                        size="sm"
                        variant="secondary"
                        onClick={() => handleDistributeEvenly(plan.id)}
                        disabled={planSections.length === 0}
                      >
                        {t('analyticDistribution.distributeEvenly')}
                      </Button>
                      <Button
                        size="sm"
                        variant="secondary"
                        onClick={() => addSectionToPlan(plan.id)}
                        disabled={planSections.length === 0}
                      >
                        <Plus className="w-3 h-3" /> {t('analyticDistribution.addSection')}
                      </Button>
                    </div>
                  </div>

                  {planSections.length === 0 ? (
                    <p className="text-xs text-[var(--color-text-secondary)] py-2">
                      {t('analyticDistribution.noSections')}
                    </p>
                  ) : Object.keys(planDist).length === 0 ? (
                    <p className="text-xs text-[var(--color-text-secondary)] py-2">
                      {t('analyticDistribution.addSection')}
                    </p>
                  ) : (
                    <table className="w-full text-sm">
                      <thead>
                        <tr className="text-xs text-[var(--color-text-secondary)] border-b border-[var(--color-border)]">
                          <th className="text-left py-1">{t('analyticDistribution.section')}</th>
                          <th className="text-right py-1 w-32">{t('analyticDistribution.percentage')}</th>
                          <th className="text-right py-1 w-32">{t('analyticDistribution.amount')}</th>
                          <th className="w-8"></th>
                        </tr>
                      </thead>
                      <tbody>
                        {Object.entries(planDist).map(([sectionId, pct]) => {
                          const amount = (lineAmount * (Number(pct) || 0)) / 100
                          return (
                            <tr key={sectionId} className="border-b border-[var(--color-border)] last:border-0">
                              <td className="py-1.5">
                                <Select
                                  value={sectionId}
                                  onChange={(e) => {
                                    const newSectionId = e.target.value
                                    if (newSectionId === sectionId) return
                                    setDist((prev) => {
                                      const next = { ...prev }
                                      const oldPct = next[plan.id][sectionId]
                                      delete next[plan.id][sectionId]
                                      next[plan.id][newSectionId] = oldPct
                                      return next
                                    })
                                  }}
                                  options={planSections.map((s) => ({
                                    value: s.id,
                                    label: `${s.code} — ${s.name}`,
                                  }))}
                                  className="text-xs"
                                />
                              </td>
                              <td className="py-1.5 text-right">
                                <Input
                                  type="number"
                                  value={String(pct)}
                                  onChange={(e) => updatePercentage(plan.id, sectionId, Number(e.target.value) || 0)}
                                  className="text-xs text-right w-28 ml-auto"
                                />
                              </td>
                              <td className="py-1.5 text-right font-mono text-xs">
                                {amount.toFixed(2)}
                              </td>
                              <td className="py-1.5 text-center">
                                <button
                                  onClick={() => removeSectionFromPlan(plan.id, sectionId)}
                                  className="p-1 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]" aria-label={tCommon('actions.delete')} title={tCommon('actions.delete')}>
                                  <Trash2 className="w-3.5 h-3.5" aria-hidden="true" /></button>
                              </td>
                            </tr>
                          )
                        })}
                      </tbody>
                    </table>
                  )}
                </div>
              )
            })}
          </div>
        )}

        <div className="flex justify-end gap-2 mt-6">
          <Button variant="secondary" onClick={onClose}>
            {t('analyticDistribution.cancel')}
          </Button>
          <Button onClick={handleSave} disabled={saving || plans.length === 0}>
            <CheckCircle className="w-4 h-4" /> {t('analyticDistribution.validate')}
          </Button>
        </div>
      </div>
    </div>
  )
}
