import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Input, Select, Badge } from '@/components/ui'
import { getInterviewCampaigns, createInterviewCampaign, launchInterviewCampaign, closeCampaign } from '@/lib/queries'
import { formatDate } from '@/lib/utils'
import { Users, Plus, X, Play, Lock } from 'lucide-react'
import { useToast } from '@/lib/toast'

const statusColors: Record<string, 'neutral' | 'success' | 'warning'> = {
  draft: 'neutral',
  active: 'success',
  closed: 'warning',
}

export function InterviewCampaignsPage() {
  const { toast } = useToast()
  const { t } = useTranslation('hr')
  const { t: tCommon } = useTranslation('common')
  const { t: tNav } = useTranslation('nav')
  const [campaigns, setCampaigns] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const data = await getInterviewCampaigns()
      setCampaigns(data || [])
    } catch (err: any) {
      console.error(err)
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    } finally { setLoading(false) }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  async function handleLaunch(id: string) {
    try { await launchInterviewCampaign(id); await loadData(); toast('success', tCommon('common.success'), tCommon('common.saved')) }
    catch (err: any) { toast('error', tCommon('common.error'), err.message) }
  }

  async function handleClose(id: string) {
    try { await closeCampaign(id); await loadData(); toast('success', tCommon('common.success'), tCommon('common.saved')) }
    catch (err: any) { toast('error', tCommon('common.error'), err.message) }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('sections.hr') }, { label: t('campaigns.title') }]} />
      <PageHeader
        title={t('campaigns.title')}
        subtitle={t('campaigns.subtitle')}
        action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('campaigns.new')}</Button>}
      />

      {loading ? (
        <SkeletonTable rows={4} cols={6} />
      ) : campaigns.length === 0 ? (
        <EmptyState
          icon={<Users className="w-8 h-8" />}
          title={t('campaigns.noRecords')}
          description={t('campaigns.noRecordsDescription')}
          action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('campaigns.new')}</Button>}
        />
      ) : (
        <Card>
          <Table headers={[
            t('campaigns.name'),
            t('campaigns.campaignType'),
            t('campaigns.startDate'),
            t('campaigns.endDate'),
            t('campaigns.status'),
            tCommon('table.actions'),
          ]}>
            {campaigns.map((c) => (
              <TableRow key={c.id}>
                <TableCell className="text-sm font-medium">{c.name}</TableCell>
                <TableCell className="text-sm">{t(`campaigns.types.${c.campaign_type}`)}</TableCell>
                <TableCell className="text-xs">{formatDate(c.start_date)}</TableCell>
                <TableCell className="text-xs">{c.end_date ? formatDate(c.end_date) : '—'}</TableCell>
                <TableCell><Badge variant={statusColors[c.status] || 'neutral'}>{t(`campaigns.statuses.${c.status}`)}</Badge></TableCell>
                <TableCell>
                  <div className="flex gap-1">
                    {c.status === 'draft' && (
                      <button onClick={() => handleLaunch(c.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-success)]" title={t('campaigns.launch')}>
                        <Play className="w-4 h-4" />
                      </button>
                    )}
                    {c.status === 'active' && (
                      <button onClick={() => handleClose(c.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-warning)]" title={t('campaigns.close')}>
                        <Lock className="w-4 h-4" />
                      </button>
                    )}
                  </div>
                </TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}

      {showForm && (
        <CampaignForm
          onClose={() => setShowForm(false)}
          onSaved={() => { setShowForm(false); loadData() }}
        />
      )}
    </div>
  )
}

function CampaignForm({ onClose, onSaved }: { onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation('hr')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [name, setName] = useState('')
  const [campaignType, setCampaignType] = useState('annual')
  const [startDate, setStartDate] = useState('')
  const [endDate, setEndDate] = useState('')
  const [reminderDays, setReminderDays] = useState(7)
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      await createInterviewCampaign({
        name,
        campaign_type: campaignType as any,
        start_date: startDate,
        end_date: endDate || null,
        reminder_days: Number(reminderDays),
        status: 'draft',
        form_template: null,
      } as any)
      toast('success', tCommon('common.success'), tCommon('common.saved'))
      onSaved()
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    } finally { setSaving(false) }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '36rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('campaigns.new')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <Input label={t('campaigns.name')} value={name} onChange={(e) => setName(e.target.value)} required />
          <Select label={t('campaigns.campaignType')} value={campaignType} onChange={(e) => setCampaignType(e.target.value)} options={[
            { value: 'annual', label: t('campaigns.types.annual') },
            { value: 'mid_year', label: t('campaigns.types.mid_year') },
            { value: 'professional', label: t('campaigns.types.professional') },
            { value: 'exit', label: t('campaigns.types.exit') },
            { value: 'other', label: t('campaigns.types.other') },
          ]} />
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('campaigns.startDate')} type="date" value={startDate} onChange={(e) => setStartDate(e.target.value)} required />
            <Input label={t('campaigns.endDate')} type="date" value={endDate} onChange={(e) => setEndDate(e.target.value)} />
          </div>
          <Input label={t('campaigns.reminderDays')} type="number" value={reminderDays} onChange={(e) => setReminderDays(Number(e.target.value))} />
          <div className="flex justify-end gap-3 pt-4 border-t border-[var(--color-border)]">
            <Button type="button" variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? '...' : tCommon('actions.save')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
