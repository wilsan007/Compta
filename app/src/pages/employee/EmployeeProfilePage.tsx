import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Input, EmptyState, SkeletonTable, Badge, Breadcrumb } from '@/components/ui'
import { AlertTriangle, User, Briefcase, TrendingUp } from 'lucide-react'
import { getMyProfile, updateMyProfile, getEmployeeAlerts } from '@/lib/queries/sprintH'
import { formatDate } from '@/lib/utils'
import { useToast } from '@/lib/toast'

export function EmployeeProfilePage() {
  const { t } = useTranslation('employee')
  const { t: tCommon } = useTranslation('common')
  const { t: tNav } = useTranslation('nav')
  const { toast } = useToast()
  const [profile, setProfile] = useState<any>(null)
  const [alerts, setAlerts] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const [p, a] = await Promise.all([getMyProfile(), getEmployeeAlerts()])
      setProfile(p)
      setAlerts(Array.isArray(a) ? a : [])
    } catch (err: any) {
      console.error(err)
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    } finally { setLoading(false) }
  }, [tCommon, toast])

  useEffect(() => { loadData() }, [loadData])

  async function handleSavePersonal() {
    setSaving(true)
    try {
      await updateMyProfile({
        address: profile.address,
        postal_code: profile.postal_code,
        city: profile.city,
        phone: profile.phone,
        emergency_contact_name: profile.emergency_contact_name,
        emergency_contact_phone: profile.emergency_contact_phone,
        emergency_contact_relation: profile.emergency_contact_relation,
        bank_iban: profile.bank_iban,
        bank_bic: profile.bank_bic,
      })
      toast('success', tCommon('common.success'), tCommon('common.saved'))
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    } finally { setSaving(false) }
  }

  if (loading) return <SkeletonTable rows={6} cols={4} />
  if (!profile) return null

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('groups.hr') }, { label: t('profile.title') }]} />
      <PageHeader title={t('profile.title')} />

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <Card>
          <h3 className="text-sm font-semibold p-4 border-b border-[var(--color-border)] flex items-center gap-2">
            <User className="w-4 h-4" /> {t('profile.personalInfo')}
          </h3>
          <div className="p-4 space-y-3">
            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="text-xs text-[var(--color-text-secondary)]">{t('profile.birthDate')}</label>
                <p className="text-sm">{formatDate(profile.birth_date)}</p>
              </div>
              <div>
                <label className="text-xs text-[var(--color-text-secondary)]">{t('profile.nationality')}</label>
                <p className="text-sm">{profile.nationality || '-'}</p>
              </div>
              <div>
                <label className="text-xs text-[var(--color-text-secondary)]">{t('profile.socialSecurity')}</label>
                <p className="text-sm font-mono">{profile.ss_number || '-'}</p>
              </div>
              <div>
                <label className="text-xs text-[var(--color-text-secondary)]">{t('profile.maritalStatus')}</label>
                <p className="text-sm">{profile.marital_status || '-'}</p>
              </div>
            </div>
            <div>
              <label className="text-xs text-[var(--color-text-secondary)]">{t('profile.address')}</label>
              <Input value={profile.address || ''} onChange={e => setProfile({ ...profile, address: e.target.value })} />
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="text-xs text-[var(--color-text-secondary)]">{t('profile.postalCode')}</label>
                <Input value={profile.postal_code || ''} onChange={e => setProfile({ ...profile, postal_code: e.target.value })} />
              </div>
              <div>
                <label className="text-xs text-[var(--color-text-secondary)]">{t('profile.city')}</label>
                <Input value={profile.city || ''} onChange={e => setProfile({ ...profile, city: e.target.value })} />
              </div>
            </div>
            <div>
              <label className="text-xs text-[var(--color-text-secondary)]">{t('profile.emergencyContact')}</label>
              <Input value={profile.emergency_contact_name || ''} onChange={e => setProfile({ ...profile, emergency_contact_name: e.target.value })} />
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="text-xs text-[var(--color-text-secondary)]">{t('profile.emergencyPhone')}</label>
                <Input value={profile.emergency_contact_phone || ''} onChange={e => setProfile({ ...profile, emergency_contact_phone: e.target.value })} />
              </div>
              <div>
                <label className="text-xs text-[var(--color-text-secondary)]">{t('profile.emergencyRelation')}</label>
                <Input value={profile.emergency_contact_relation || ''} onChange={e => setProfile({ ...profile, emergency_contact_relation: e.target.value })} />
              </div>
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="text-xs text-[var(--color-text-secondary)]">{t('profile.iban')}</label>
                <Input value={profile.bank_iban || ''} onChange={e => setProfile({ ...profile, bank_iban: e.target.value })} />
              </div>
              <div>
                <label className="text-xs text-[var(--color-text-secondary)]">{t('profile.bic')}</label>
                <Input value={profile.bank_bic || ''} onChange={e => setProfile({ ...profile, bank_bic: e.target.value })} />
              </div>
            </div>
            <Button onClick={handleSavePersonal} disabled={saving}>{t('profile.save')}</Button>
          </div>
        </Card>

        <div className="space-y-6">
          <Card>
            <h3 className="text-sm font-semibold p-4 border-b border-[var(--color-border)] flex items-center gap-2">
              <Briefcase className="w-4 h-4" /> {t('profile.professionalInfo')}
            </h3>
            <div className="p-4 grid grid-cols-2 gap-3 text-sm">
              <div><label className="text-xs text-[var(--color-text-secondary)]">{t('profile.position')}</label><p>{profile.position || '-'}</p></div>
              <div><label className="text-xs text-[var(--color-text-secondary)]">{t('profile.department')}</label><p>{profile.department || '-'}</p></div>
              <div><label className="text-xs text-[var(--color-text-secondary)]">{t('profile.hireDate')}</label><p>{formatDate(profile.hire_date)}</p></div>
              <div><label className="text-xs text-[var(--color-text-secondary)]">{t('profile.contractType')}</label><p>{profile.contract_type || '-'}</p></div>
              <div><label className="text-xs text-[var(--color-text-secondary)]">{t('profile.mealVouchers')}</label><p>{profile.meal_voucher_count || 0}</p></div>
              <div><label className="text-xs text-[var(--color-text-secondary)]">{t('profile.transportMode')}</label><p>{profile.transport_mode || '-'}</p></div>
            </div>
          </Card>

          <Card>
            <h3 className="text-sm font-semibold p-4 border-b border-[var(--color-border)] flex items-center gap-2">
              <AlertTriangle className="w-4 h-4" /> {t('profile.alerts')}
            </h3>
            <div className="p-4 space-y-2">
              {alerts.length > 0 ? alerts.map((alert, i) => (
                <Badge key={i} variant={alert.type === 'medical_overdue' ? 'danger' : alert.type === 'trial_period' ? 'warning' : 'success'}>
                  {alert.type === 'trial_period' ? t('profile.trialPeriodWarning', { days: alert.days }) :
                   alert.type === 'medical_overdue' ? t('profile.medicalExamWarning') :
                   alert.type === 'cpf_available' ? t('profile.cpfAvailable') :
                   alert.type === 'cpfExpiring' ? t('profile.cpfExpiring') : alert.type}
                </Badge>
              )) : (
                <EmptyState icon={<TrendingUp className="w-8 h-8" />} title={t('profile.noAlerts')} />
              )}
            </div>
          </Card>
        </div>
      </div>
    </div>
  )
}
