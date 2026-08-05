import { useState, useEffect, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Repeat, Save, X } from 'lucide-react'
import type { RecurringRuleType } from '@/types/projectManagement'

interface RecurringTaskModalProps {
  open: boolean
  onClose: () => void
  taskId: string
  currentRecurring: boolean
  currentInterval: number
  currentRuleType: RecurringRuleType
  onSave: (recurring: boolean, interval: number, ruleType: RecurringRuleType) => void
}

export function RecurringTaskModal({
  open,
  onClose,
  currentRecurring,
  currentInterval,
  currentRuleType,
  onSave,
}: RecurringTaskModalProps) {
  const { t } = useTranslation('taskManagement')
  const [enabled, setEnabled] = useState(currentRecurring)
  const [interval, setInterval] = useState(currentInterval || 1)
  const [ruleType, setRuleType] = useState<RecurringRuleType>(currentRuleType || 'weekly')

  useEffect(() => {
    setEnabled(currentRecurring)
    setInterval(currentInterval || 1)
    setRuleType(currentRuleType || 'weekly')
  }, [currentRecurring, currentInterval, currentRuleType, open])

  const handleSave = useCallback(() => {
    onSave(enabled, interval, ruleType)
    onClose()
  }, [enabled, interval, ruleType, onSave, onClose])

  if (!open) return null

  const ruleTypes: { value: RecurringRuleType; label: string }[] = [
    { value: 'daily', label: t('recurring.daily') },
    { value: 'weekly', label: t('recurring.weekly') },
    { value: 'monthly', label: t('recurring.monthly') },
    { value: 'yearly', label: t('recurring.yearly') },
  ]

  const unitLabel = ruleType === 'daily' ? t('recurring.days') : ruleType === 'weekly' ? t('recurring.weeks') : ruleType === 'monthly' ? t('recurring.months') : t('recurring.years')

  const computeNextOccurrence = () => {
    if (!enabled) return null
    const now = new Date()
    const next = new Date(now)
    const mult = interval || 1
    switch (ruleType) {
      case 'daily': next.setDate(next.getDate() + mult); break
      case 'weekly': next.setDate(next.getDate() + mult * 7); break
      case 'monthly': next.setMonth(next.getMonth() + mult); break
      case 'yearly': next.setFullYear(next.getFullYear() + mult); break
    }
    return next.toLocaleDateString()
  }

  const nextDate = computeNextOccurrence()

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40" onClick={onClose}>
      <div
        className="w-full max-w-md rounded-xl bg-[var(--color-surface)] shadow-lg p-6 space-y-4"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between">
          <h2 className="text-lg font-semibold flex items-center gap-2">
            <Repeat className="w-5 h-5 text-[var(--color-primary)]" />
            {t('recurring.title')}
          </h2>
          <button onClick={onClose} className="text-[var(--color-text-secondary)] hover:text-[var(--color-text)]">
            <X className="w-5 h-5" />
          </button>
        </div>

        <label className="flex items-center gap-2 cursor-pointer">
          <input
            type="checkbox"
            checked={enabled}
            onChange={(e) => setEnabled(e.target.checked)}
            className="w-4 h-4 rounded"
          />
          <span className="text-sm">{t('recurring.enable')}</span>
        </label>

        {enabled && (
          <>
            <div>
              <label className="text-sm text-[var(--color-text-secondary)] mb-1 block">{t('recurring.ruleType')}</label>
              <select
                value={ruleType}
                onChange={(e) => setRuleType(e.target.value as RecurringRuleType)}
                className="w-full px-3 py-2 rounded-lg border border-[var(--color-border)] bg-[var(--color-surface)] text-sm"
              >
                {ruleTypes.map((rt) => (
                  <option key={rt.value} value={rt.value}>{rt.label}</option>
                ))}
              </select>
            </div>

            <div>
              <label className="text-sm text-[var(--color-text-secondary)] mb-1 block">{t('recurring.interval')}</label>
              <div className="flex items-center gap-2">
                <span className="text-sm text-[var(--color-text-secondary)]">{t('recurring.every')}</span>
                <input
                  type="number"
                  min="1"
                  max="365"
                  value={interval}
                  onChange={(e) => setInterval(Math.max(1, parseInt(e.target.value) || 1))}
                  className="w-20 px-2 py-1.5 rounded-lg border border-[var(--color-border)] bg-[var(--color-surface)] text-sm text-center"
                />
                <span className="text-sm text-[var(--color-text-secondary)]">{unitLabel}</span>
              </div>
            </div>

            {nextDate && (
              <div className="rounded-lg bg-[var(--color-neutral-100)] p-3 text-sm">
                <span className="text-[var(--color-text-secondary)]">{t('recurring.nextOccurrence')}: </span>
                <span className="font-medium">{nextDate}</span>
              </div>
            )}
          </>
        )}

        <div className="flex justify-end gap-2 pt-2">
          <button
            onClick={onClose}
            className="px-4 py-2 text-sm rounded-lg bg-[var(--color-neutral-100)] hover:bg-[var(--color-neutral-200)] transition-colors"
          >
            {t('actions.cancel')}
          </button>
          <button
            onClick={handleSave}
            className="flex items-center gap-1.5 px-4 py-2 text-sm rounded-lg bg-[var(--color-primary)] text-white hover:opacity-90 transition-opacity"
          >
            <Save className="w-4 h-4" />
            {t('recurring.save')}
          </button>
        </div>
      </div>
    </div>
  )
}
