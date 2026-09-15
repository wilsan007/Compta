import { useState, useEffect, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Button, Table, TableRow, TableCell, Badge, EmptyState, Select, Input } from '@/components/ui'
import { formatCurrency, formatDate } from '@/lib/utils'
import { getOpportunities, createOpportunity, updateOpportunityStage } from '@/lib/queries/crmAdvanced'
import { getCustomers } from '@/lib/queries/partners'
import { getSalesRepresentatives } from '@/lib/queries/misc'
import { useToast } from '@/lib/toast'
import { Plus, X, Target, Search, Kanban, List } from 'lucide-react'
import type { CrmOpportunity, Customer, SalesRepresentative } from '@/types'

type OppWithRelations = CrmOpportunity & { customer: { name: string } | null, prospect: { name: string } | null }

const STAGES = ['new', 'qualified', 'proposition', 'negotiation', 'won', 'lost'] as const

export function OpportunitiesPage() {
  const { t } = useTranslation('crm')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [opportunities, setOpportunities] = useState<OppWithRelations[]>([])
  const [customers, setCustomers] = useState<Customer[]>([])
  const [reps, setReps] = useState<SalesRepresentative[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [view, setView] = useState<'kanban' | 'list'>('kanban')
  const [search, setSearch] = useState('')
  const [filterRep, setFilterRep] = useState('')

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const [opps, custs, repsData] = await Promise.all([getOpportunities(), getCustomers(), getSalesRepresentatives()])
      setOpportunities(opps || [])
      setCustomers(custs || [])
      setReps(repsData || [])
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message)
    } finally {
      setLoading(false)
    }
  }, [tCommon, toast])

  useEffect(() => { load() }, [load])

  const filtered = opportunities.filter(o => {
    if (search && !o.title.toLowerCase().includes(search.toLowerCase())) return false
    if (filterRep && o.sales_rep_id !== filterRep) return false
    return true
  })

  async function handleStageChange(id: string, stage: string) {
    try {
      await updateOpportunityStage(id, stage)
      toast('success', tCommon('toast.success'), tCommon('toast.updated'))
      await load()
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message)
    }
  }

  function getStageBadgeVariant(stage: string): 'neutral' | 'warning' | 'success' | 'danger' {
    if (stage === 'won') return 'success'
    if (stage === 'lost') return 'danger'
    if (stage === 'negotiation' || stage === 'proposition') return 'warning'
    return 'neutral'
  }

  return (
    <div className="p-6 max-w-7xl mx-auto">
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-2xl font-bold flex items-center gap-2">
            <Target className="w-6 h-6 text-[var(--color-primary)]" />
            {t('opportunities.title')}
          </h1>
          <p className="text-sm text-[var(--color-text-secondary)] mt-1">{t('opportunities.subtitle')}</p>
        </div>
        <div className="flex gap-2">
          <Button variant="secondary" onClick={() => setView(view === 'kanban' ? 'list' : 'kanban')}>
            {view === 'kanban' ? <List className="w-4 h-4" /> : <Kanban className="w-4 h-4" />}
            {view === 'kanban' ? t('opportunities.listView') : t('opportunities.kanbanView')}
          </Button>
          <Button onClick={() => setShowForm(true)}>
            <Plus className="w-4 h-4" /> {t('opportunities.new')}
          </Button>
        </div>
      </div>

      <div className="flex items-center gap-4 mb-4">
        <div className="relative flex-1 max-w-xs">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-[var(--color-text-secondary)]" />
          <input type="text" placeholder={t('opportunities.searchPlaceholder')} value={search} onChange={(e) => setSearch(e.target.value)} className="input pl-9" />
        </div>
        <Select value={filterRep} onChange={(e) => setFilterRep(e.target.value)} options={[
          { value: '', label: tCommon('select.all') },
          ...reps.map(r => ({ value: r.id, label: r.name })),
        ]} />
      </div>

      {loading ? (
        <div className="space-y-2">{[1, 2, 3].map(i => <div key={i} className="h-12 rounded animate-pulse bg-[var(--color-neutral-100)]" />)}</div>
      ) : view === 'kanban' ? (
        <div className="flex gap-4 overflow-x-auto pb-4">
          {STAGES.map(stage => {
            const stageOpps = filtered.filter(o => o.stage === stage)
            const total = stageOpps.reduce((sum, o) => sum + Number(o.expected_amount || 0), 0)
            return (
              <div key={stage} className="flex-shrink-0 w-72">
                <div className="card">
                  <div className="px-3 py-2 border-b border-[var(--color-border)] flex items-center justify-between">
                    <span className="text-sm font-semibold">{t(`opportunities.stage${stage.charAt(0).toUpperCase() + stage.slice(1)}`)}</span>
                    <span className="text-xs text-[var(--color-text-secondary)]">{stageOpps.length} · {formatCurrency(total)}</span>
                  </div>
                  <div className="p-2 space-y-2 max-h-96 overflow-y-auto">
                    {stageOpps.map(o => (
                      <div key={o.id} className="p-2 rounded border border-[var(--color-border)] hover:border-[var(--color-primary)] cursor-pointer" onClick={() => handleStageChange(o.id, STAGES[(STAGES.indexOf(o.stage as any) + 1) % STAGES.length])}>
                        <div className="text-sm font-medium truncate">{o.title}</div>
                        <div className="text-xs text-[var(--color-text-secondary)]">{o.customer?.name || o.prospect?.name || '-'}</div>
                        <div className="flex items-center justify-between mt-1">
                          <span className="text-xs font-mono">{formatCurrency(Number(o.expected_amount))}</span>
                          <div className="flex items-center gap-1">
                            {(o as any).quote_id || (o as any).quote_generated ? <Badge variant="success">Devis</Badge> : null}
                            <Badge variant={getStageBadgeVariant(o.stage)}>{o.probability}%</Badge>
                          </div>
                        </div>
                      </div>
                    ))}
                    {stageOpps.length === 0 && <div className="text-xs text-[var(--color-text-secondary)] text-center py-4">—</div>}
                  </div>
                </div>
              </div>
            )
          })}
        </div>
      ) : filtered.length === 0 ? (
        <EmptyState icon={<Target className="w-8 h-8" />} title={t('opportunities.noOpportunities')} description={t('opportunities.noOpportunitiesDescription')} action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('opportunities.createFirst')}</Button>} />
      ) : (
        <Table headers={[t('opportunities.number'), t('opportunities.titleField'), t('opportunities.customer'), t('opportunities.stage'), t('opportunities.expectedAmount'), t('opportunities.probability'), t('opportunities.expectedCloseDate'), 'Devis']}>
          {filtered.map(o => (
            <TableRow key={o.id}>
              <TableCell className="font-mono text-xs">{o.number}</TableCell>
              <TableCell className="font-medium">{o.title}</TableCell>
              <TableCell className="text-xs">{o.customer?.name || o.prospect?.name || '-'}</TableCell>
              <TableCell><Badge variant={getStageBadgeVariant(o.stage)}>{t(`opportunities.stage${o.stage.charAt(0).toUpperCase() + o.stage.slice(1)}`)}</Badge></TableCell>
              <TableCell className="font-mono text-xs">{formatCurrency(Number(o.expected_amount))}</TableCell>
              <TableCell className="text-xs">{o.probability}%</TableCell>
              <TableCell className="text-xs">{o.expected_close_date ? formatDate(o.expected_close_date) : '-'}</TableCell>
              <TableCell>{(o as any).quote_id || (o as any).quote_generated ? <Badge variant="success">Devis créé</Badge> : <span className="text-xs text-[var(--color-text-secondary)]">—</span>}</TableCell>
            </TableRow>
          ))}
        </Table>
      )}

      {showForm && (
        <OpportunityForm customers={customers} reps={reps} onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); load() }} />
      )}
    </div>
  )
}

function OpportunityForm({ customers, reps, onClose, onSaved }: { customers: Customer[]; reps: SalesRepresentative[]; onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation('crm')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [title, setTitle] = useState('')
  const [customerId, setCustomerId] = useState('')
  const [stage, setStage] = useState<CrmOpportunity['stage']>('new')
  const [probability, setProbability] = useState(0)
  const [expectedAmount, setExpectedAmount] = useState(0)
  const [expectedCloseDate, setExpectedCloseDate] = useState('')
  const [salesRepId, setSalesRepId] = useState('')
  const [source, setSource] = useState('')
  const [description, setDescription] = useState('')
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!title) return
    setSaving(true)
    try {
      const num = `OPP-${Date.now().toString().slice(-6)}`
      await createOpportunity({
        tenant_id: null,
        number: num,
        customer_id: customerId || null,
        prospect_id: null,
        title,
        description: description || null,
        stage,
        probability,
        expected_amount: expectedAmount,
        expected_close_date: expectedCloseDate || null,
        actual_amount: null,
        actual_close_date: null,
        sales_rep_id: salesRepId || null,
        source: source || null,
        lost_reason: null,
        tags: null,
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
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '36rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('opportunities.new')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <Input label={t('opportunities.titleField')} required value={title} onChange={(e) => setTitle(e.target.value)} />
          <Select label={t('opportunities.customer')} value={customerId} onChange={(e) => setCustomerId(e.target.value)} options={[
            { value: '', label: tCommon('select.choose') },
            ...customers.map(c => ({ value: c.id, label: c.name })),
          ]} />
          <div className="grid grid-cols-2 gap-4">
            <Select label={t('opportunities.stage')} value={stage} onChange={(e) => setStage(e.target.value as any)} options={STAGES.map(s => ({ value: s, label: t(`opportunities.stage${s.charAt(0).toUpperCase() + s.slice(1)}`) }))} />
            <Input label={t('opportunities.probability')} type="number" step="1" value={probability} onChange={(e) => setProbability(Number(e.target.value))} />
          </div>
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('opportunities.expectedAmount')} type="number" step="0.01" value={expectedAmount} onChange={(e) => setExpectedAmount(Number(e.target.value))} />
            <Input label={t('opportunities.expectedCloseDate')} type="date" value={expectedCloseDate} onChange={(e) => setExpectedCloseDate(e.target.value)} />
          </div>
          <Select label={t('opportunities.salesRep')} value={salesRepId} onChange={(e) => setSalesRepId(e.target.value)} options={[
            { value: '', label: tCommon('select.choose') },
            ...reps.map(r => ({ value: r.id, label: r.name })),
          ]} />
          <Input label={t('opportunities.source')} value={source} onChange={(e) => setSource(e.target.value)} />
          <Input label={t('opportunities.description')} value={description} onChange={(e) => setDescription(e.target.value)} />
          <div className="flex justify-end gap-3 pt-2 border-t border-[var(--color-border)]">
            <Button type="button" variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? tCommon('actions.saving') : tCommon('actions.save')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
