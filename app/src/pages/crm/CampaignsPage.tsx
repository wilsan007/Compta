import { useState, useEffect, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Button, Table, TableRow, TableCell, Badge, EmptyState, Select, Input } from '@/components/ui'
import { formatCurrency, formatDate } from '@/lib/utils'
import { getCampaigns, createCampaign, launchCampaign, getCampaignStats } from '@/lib/queries'
import { useToast } from '@/lib/toast'
import { Plus, X, Megaphone, Rocket } from 'lucide-react'
import type { CrmCampaign } from '@/types'

const CAMPAIGN_TYPES = ['email', 'sms', 'social', 'event', 'print'] as const

export function CampaignsPage() {
  const { t } = useTranslation('crm')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [campaigns, setCampaigns] = useState<CrmCampaign[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [statsFor, setStatsFor] = useState<string | null>(null)
  const [stats, setStats] = useState<any>(null)

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const data = await getCampaigns()
      setCampaigns(data || [])
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => { load() }, [load])

  async function handleLaunch(id: string) {
    try {
      await launchCampaign(id)
      toast('success', tCommon('toast.success'), t('campaigns.launch'))
      await load()
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message)
    }
  }

  async function handleStats(id: string) {
    try {
      const s = await getCampaignStats(id)
      setStatsFor(id)
      setStats(s)
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message)
    }
  }

  function getStatusBadge(status: string): 'neutral' | 'warning' | 'success' | 'danger' {
    if (status === 'completed') return 'success'
    if (status === 'running') return 'warning'
    if (status === 'cancelled') return 'danger'
    return 'neutral'
  }

  return (
    <div className="p-6 max-w-7xl mx-auto">
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-2xl font-bold flex items-center gap-2">
            <Megaphone className="w-6 h-6 text-[var(--color-primary)]" />
            {t('campaigns.title')}
          </h1>
          <p className="text-sm text-[var(--color-text-secondary)] mt-1">{t('campaigns.subtitle')}</p>
        </div>
        <Button onClick={() => setShowForm(true)}>
          <Plus className="w-4 h-4" /> {t('campaigns.new')}
        </Button>
      </div>

      {loading ? (
        <div className="space-y-2">{[1, 2, 3].map(i => <div key={i} className="h-12 rounded animate-pulse bg-[var(--color-neutral-100)]" />)}</div>
      ) : campaigns.length === 0 ? (
        <EmptyState icon={<Megaphone className="w-8 h-8" />} title={t('campaigns.noCampaigns')} description={t('campaigns.noCampaignsDescription')} />
      ) : (
        <Table headers={[t('campaigns.name'), t('campaigns.type'), t('campaigns.status'), t('campaigns.startDate'), t('campaigns.endDate'), t('campaigns.budget'), tCommon('table.actions')]}>
          {campaigns.map(c => (
            <TableRow key={c.id}>
              <TableCell className="font-medium">{c.name}</TableCell>
              <TableCell className="text-xs">{t(`campaigns.${c.campaign_type}`)}</TableCell>
              <TableCell><Badge variant={getStatusBadge(c.status)}>{t(`campaigns.${c.status}`)}</Badge></TableCell>
              <TableCell className="text-xs">{c.start_date ? formatDate(c.start_date) : '-'}</TableCell>
              <TableCell className="text-xs">{c.end_date ? formatDate(c.end_date) : '-'}</TableCell>
              <TableCell className="font-mono text-xs">{formatCurrency(Number(c.budget))}</TableCell>
              <TableCell>
                <div className="flex gap-1">
                  {c.status === 'draft' && (
                    <button onClick={() => handleLaunch(c.id)} className="p-1 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-primary)]" title={t('campaigns.launch')}>
                      <Rocket className="w-4 h-4" />
                    </button>
                  )}
                  <button onClick={() => handleStats(c.id)} className="p-1 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-text-secondary)]" title={t('campaigns.stats')}>
                    <Megaphone className="w-4 h-4" />
                  </button>
                </div>
              </TableCell>
            </TableRow>
          ))}
        </Table>
      )}

      {statsFor && stats && (
        <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4" onClick={() => setStatsFor(null)}>
          <div className="card shadow-2xl p-6" style={{ width: '100%', maxWidth: '28rem' }} onClick={(e) => e.stopPropagation()}>
            <h3 className="text-lg font-semibold mb-4">{t('campaigns.stats')}</h3>
            <div className="grid grid-cols-2 gap-4">
              <div className="card p-3"><div className="text-xs text-[var(--color-text-secondary)]">{t('campaigns.sentCount')}</div><div className="text-xl font-bold">{stats.sent}</div></div>
              <div className="card p-3"><div className="text-xs text-[var(--color-text-secondary)]">{t('campaigns.openRate')}</div><div className="text-xl font-bold">{stats.openRate.toFixed(1)}%</div></div>
              <div className="card p-3"><div className="text-xs text-[var(--color-text-secondary)]">{t('campaigns.clickRate')}</div><div className="text-xl font-bold">{stats.clickRate.toFixed(1)}%</div></div>
              <div className="card p-3"><div className="text-xs text-[var(--color-text-secondary)]">{t('campaigns.responseRate')}</div><div className="text-xl font-bold">{stats.responseRate.toFixed(1)}%</div></div>
            </div>
            <Button variant="secondary" onClick={() => setStatsFor(null)} className="mt-4 w-full">{tCommon('actions.close')}</Button>
          </div>
        </div>
      )}

      {showForm && <CampaignForm onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); load() }} />}
    </div>
  )
}

function CampaignForm({ onClose, onSaved }: { onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation('crm')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [name, setName] = useState('')
  const [campaignType, setCampaignType] = useState<CrmCampaign['campaign_type']>('email')
  const [startDate, setStartDate] = useState('')
  const [endDate, setEndDate] = useState('')
  const [budget, setBudget] = useState(0)
  const [targetAudience, setTargetAudience] = useState('all')
  const [description, setDescription] = useState('')
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!name) return
    setSaving(true)
    try {
      await createCampaign({
        tenant_id: null,
        name,
        description: description || null,
        campaign_type: campaignType,
        status: 'draft',
        start_date: startDate || null,
        end_date: endDate || null,
        budget,
        actual_cost: 0,
        target_audience: targetAudience,
        segment_criteria: null,
        sent_count: 0,
        open_count: 0,
        click_count: 0,
        response_count: 0,
        conversion_count: 0,
      })
      toast('success', tCommon('toast.success'), tCommon('toast.created'))
      onSaved()
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message)
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '32rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('campaigns.new')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <Input label={t('campaigns.name')} required value={name} onChange={(e) => setName(e.target.value)} />
          <Select label={t('campaigns.type')} required value={campaignType} onChange={(e) => setCampaignType(e.target.value as any)} options={CAMPAIGN_TYPES.map(tp => ({ value: tp, label: t(`campaigns.${tp}`) }))} />
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('campaigns.startDate')} type="date" value={startDate} onChange={(e) => setStartDate(e.target.value)} />
            <Input label={t('campaigns.endDate')} type="date" value={endDate} onChange={(e) => setEndDate(e.target.value)} />
          </div>
          <Input label={t('campaigns.budget')} type="number" step="0.01" value={budget} onChange={(e) => setBudget(Number(e.target.value))} />
          <Select label={t('campaigns.targetAudience')} value={targetAudience} onChange={(e) => setTargetAudience(e.target.value)} options={[
            { value: 'all', label: t('campaigns.all') },
            { value: 'segment', label: t('campaigns.segment') },
            { value: 'specific', label: t('campaigns.specific') },
          ]} />
          <Input label={t('campaigns.description')} value={description} onChange={(e) => setDescription(e.target.value)} />
          <div className="flex justify-end gap-3 pt-2 border-t border-[var(--color-border)]">
            <Button type="button" variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? '...' : tCommon('actions.save')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
