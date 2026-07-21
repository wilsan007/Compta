import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Breadcrumb, Select, Input } from '@/components/ui'
import { getCompanySettings, updateCompanySettings } from '@/lib/queries'
import { useToast } from '@/lib/toast'
import { Save, Shield, Calculator, FileText, Lock } from 'lucide-react'
import type { CompanySettings } from '@/types'

export function CompanySettingsPage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [settings, setSettings] = useState<CompanySettings | null>(null)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const s = await getCompanySettings()
      setSettings(s)
    } catch (err) {
      console.error('Failed to load company settings:', err)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  async function handleSave() {
    if (!settings) return
    setSaving(true)
    try {
      await updateCompanySettings(settings.id, settings)
      toast('success', tCommon('common.success'), tCommon('common.saved'))
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    } finally {
      setSaving(false)
    }
  }

  function update<K extends keyof CompanySettings>(key: K, value: CompanySettings[K]) {
    setSettings(prev => prev ? { ...prev, [key]: value } : prev)
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('home.breadcrumb') }, { label: t('system.breadcrumb', 'Système') }, { label: t('companySettings.breadcrumb', 'Paramètres société') }]} />
      <PageHeader
        title={t('companySettings.title', 'Paramètres société')}
        subtitle={t('companySettings.subtitle', 'Configuration comptable, fiscale et RGPD')}
        action={<Button onClick={handleSave} disabled={saving || loading}><Save className="w-4 h-4" /> {saving ? tCommon('common.saving') : tCommon('common.actions.save')}</Button>}
      />

      {loading || !settings ? (
        <Card><div className="p-8 text-center text-[var(--color-text-secondary)]">...</div></Card>
      ) : (
        <div className="space-y-4">
          {/* VAT Method */}
          <Card>
            <div className="p-5">
              <div className="flex items-center gap-2 mb-4">
                <Calculator className="w-5 h-5 text-[var(--color-primary)]" />
                <h3 className="text-sm font-semibold">{t('vatMethods.label')}</h3>
              </div>
              <p className="text-xs text-[var(--color-text-secondary)] mb-3">{t('vatMethods.description')}</p>
              <Select
                label={t('vatMethods.label')}
                value={(settings as any).vat_method || 'debit'}
                onChange={(e) => update('vat_method' as any, e.target.value)}
                options={[
                  { value: 'debit', label: t('vatMethods.debit') },
                  { value: 'encaissement', label: t('vatMethods.encaissement') },
                ]}
              />
            </div>
          </Card>

          {/* Accounting Standard */}
          <Card>
            <div className="p-5">
              <div className="flex items-center gap-2 mb-4">
                <FileText className="w-5 h-5 text-[var(--color-primary)]" />
                <h3 className="text-sm font-semibold">{t('ifrs.label')}</h3>
              </div>
              <p className="text-xs text-[var(--color-text-secondary)] mb-3">{t('ifrs.description')}</p>
              <Select
                label={t('ifrs.label')}
                value={(settings as any).accounting_standard || 'french_pcga'}
                onChange={(e) => update('accounting_standard' as any, e.target.value)}
                options={[
                  { value: 'french_pcga', label: t('ifrs.french_pcga') },
                  { value: 'french_pcg', label: t('ifrs.french_pcg') },
                  { value: 'ias_ifrs', label: t('ifrs.ias_ifrs') },
                ]}
              />
            </div>
          </Card>

          {/* GDPR */}
          <Card>
            <div className="p-5">
              <div className="flex items-center gap-2 mb-4">
                <Shield className="w-5 h-5 text-[var(--color-primary)]" />
                <h3 className="text-sm font-semibold">{t('gdpr.title')}</h3>
              </div>
              <p className="text-xs text-[var(--color-text-secondary)] mb-3">{t('gdpr.description')}</p>
              <div className="space-y-3">
                <label className="flex items-center gap-2 text-sm">
                  <input
                    type="checkbox"
                    checked={(settings as any).gdpr_enabled || false}
                    onChange={(e) => update('gdpr_enabled' as any, e.target.checked)}
                    className="w-4 h-4 rounded border-[var(--color-border)]"
                  />
                  {t('gdpr.enabled')}
                </label>
                <Input
                  label={t('gdpr.retentionYears')}
                  type="number"
                  value={(settings as any).gdpr_retention_years || 10}
                  onChange={(e) => update('gdpr_retention_years' as any, Number(e.target.value))}
                />
                <label className="flex items-center gap-2 text-sm">
                  <input
                    type="checkbox"
                    checked={(settings as any).gdpr_anonymize_after || false}
                    onChange={(e) => update('gdpr_anonymize_after' as any, e.target.checked)}
                    className="w-4 h-4 rounded border-[var(--color-border)]"
                  />
                  {t('gdpr.anonymizeAfter')}
                </label>
              </div>
            </div>
          </Card>

          {/* Fiscal Years */}
          <Card>
            <div className="p-5">
              <div className="flex items-center gap-2 mb-4">
                <Lock className="w-5 h-5 text-[var(--color-primary)]" />
                <h3 className="text-sm font-semibold">{t('fiscalYears.maxYears')}</h3>
              </div>
              <p className="text-xs text-[var(--color-text-secondary)]">{t('fiscalYears.description')}</p>
            </div>
          </Card>
        </div>
      )}
    </div>
  )
}
