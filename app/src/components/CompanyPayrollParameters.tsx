import { useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Button, Card, Input } from '@/components/ui'
import { Save } from 'lucide-react'
import { useToast } from '@/lib/toast'
import { getCompanyPayrollParameters, saveCompanyPayrollParameters } from '@/lib/queries/payroll'

/**
 * X3/C6 (276) : les deux paramètres de paie que la loi ne fixe pas pour tous —
 * le taux AT/MP notifié par la Carsat, et l'effectif de 50 salariés ou plus
 * (FNAL à 0,50 %, coefficient maximal de la réduction générale). Sans eux, le
 * moteur calcule l'AT/MP à 0 % et l'entreprise comme ayant moins de 50 salariés.
 */
export function CompanyPayrollParameters() {
  const { t } = useTranslation('settings')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [big, setBig] = useState(false)
  const [atmp, setAtmp] = useState('')
  const [month, setMonth] = useState(new Date().toISOString().slice(0, 7))
  const [saving, setSaving] = useState(false)

  useEffect(() => {
    getCompanyPayrollParameters()
      .then((p) => { setBig(p.effectif50Plus); setAtmp(p.tauxAtmp === null ? '' : String(p.tauxAtmp)) })
      .catch((err) => toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadingError')))
  }, [tCommon, toast])

  async function handleSave() {
    setSaving(true)
    try {
      await saveCompanyPayrollParameters(big, atmp.trim() === '' ? null : Number(atmp.replace(',', '.')), month)
      toast('success', tCommon('toast.success'), t('payrollParameters.saved', { month }))
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.updateError'))
    } finally {
      setSaving(false)
    }
  }

  return (
    <Card title={t('payrollParameters.title')}>
      <div className="space-y-4">
        <p className="text-sm text-[var(--color-text-secondary)]">{t('payrollParameters.hint')}</p>
        <Input label={t('payrollParameters.effectiveMonth')} type="month" value={month} onChange={(e) => setMonth(e.target.value)} />
        <Input label={t('payrollParameters.atmpRate')} type="number" step="0.01" value={atmp} onChange={(e) => setAtmp(e.target.value)} placeholder="1,00" />
        <label className="flex items-center gap-2 text-sm">
          <input type="checkbox" checked={big} onChange={(e) => setBig(e.target.checked)} />
          {t('payrollParameters.effectif50Plus')}
        </label>
        <div className="flex justify-end">
          <Button variant="primary" onClick={handleSave} disabled={saving}>
            <Save className="w-4 h-4" /> {saving ? tCommon('actions.saving') : tCommon('actions.save')}
          </Button>
        </div>
      </div>
    </Card>
  )
}
