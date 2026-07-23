import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Input } from '@/components/ui'
import { useToast } from '@/lib/toast'
import { useLocale } from '@/hooks/useLocale'
import { Plus, Trash2 } from 'lucide-react'
import {
  getAssetDepreciationPlans, createAssetDepreciationPlan,
  getAssetFamilies, createAssetFamily, deleteAssetFamily,
  getAssetRevaluations, createAssetRevaluation,
  getAssetBatchDisposals, createAssetBatchDisposal, updateAssetBatchDisposal,
} from '@/lib/queries'

// ============ Asset Depreciation Plans Page ============
export function AssetDepreciationPlansPage() {
  const { t } = useTranslation('assets')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const { formatCurrency } = useLocale()
  const [items, setItems] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [form, setForm] = useState({ asset_id: '', plan_type: 'economic' as const, depreciation_method: 'linear' as const, duration_months: 12, residual_value: 0, start_date: '', active: true })

  const loadData = useCallback(async () => { setLoading(true); try { setItems(await getAssetDepreciationPlans() || []) } catch { } finally { setLoading(false) } }, [])
  useEffect(() => { loadData() }, [loadData])

  async function handleCreate() { try { await createAssetDepreciationPlan(form as any); toast('success', tCommon('common.success'), t('depPlans.created')); setShowForm(false); await loadData() } catch (e: any) { toast('error', tCommon('common.error'), e.message) } }

  return (
    <div>
      <Breadcrumb items={[{ label: t('depPlans.breadcrumb1'), path: '/assets' }, { label: t('depPlans.title') }]} />
      <PageHeader title={t('depPlans.title')} action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('depPlans.new')}</Button>} />
      {showForm && (<Card className="p-4 mb-4 space-y-3"><div className="grid grid-cols-2 gap-3"><Input placeholder={t('depPlans.assetId')} value={form.asset_id} onChange={e => setForm({ ...form, asset_id: e.target.value })} /><select className="border rounded px-3 py-2" value={form.plan_type} onChange={e => setForm({ ...form, plan_type: e.target.value as any })}><option value="economic">{t('depPlans.types.economic')}</option><option value="fiscal">{t('depPlans.types.fiscal')}</option><option value="derogatory">{t('depPlans.types.derogatory')}</option><option value="exceptional">{t('depPlans.types.exceptional')}</option></select><select className="border rounded px-3 py-2" value={form.depreciation_method} onChange={e => setForm({ ...form, depreciation_method: e.target.value as any })}><option value="linear">{t('depPlans.methods.linear')}</option><option value="degressive">{t('depPlans.methods.degressive')}</option><option value="variable">{t('depPlans.methods.variable')}</option><option value="manual">{t('depPlans.methods.manual')}</option></select><Input type="number" placeholder={t('depPlans.duration')} value={form.duration_months} onChange={e => setForm({ ...form, duration_months: parseInt(e.target.value) || 12 })} /><Input type="date" value={form.start_date} onChange={e => setForm({ ...form, start_date: e.target.value })} /></div><div className="flex gap-2"><Button onClick={handleCreate}>{tCommon('actions.save')}</Button><Button variant="secondary" onClick={() => setShowForm(false)}>{tCommon('common.cancel')}</Button></div></Card>)}
      {loading ? <SkeletonTable /> : items.length === 0 ? <EmptyState title={t('depPlans.empty')} /> : (
        <Table headers={[t('depPlans.asset'), t('depPlans.type'), t('depPlans.method'), t('depPlans.duration'), t('depPlans.netValue'), t('depPlans.active')]}>
          {items.map(p => (<TableRow key={p.id}><TableCell>{p.fixed_assets?.name || '-'}</TableCell><TableCell>{t(`depPlans.types.${p.plan_type}`)}</TableCell><TableCell>{t(`depPlans.methods.${p.depreciation_method}`)}</TableCell><TableCell>{p.duration_months}m</TableCell><TableCell>{formatCurrency(p.current_net_value)}</TableCell><TableCell>{p.active ? <Badge>{tCommon('common.yes')}</Badge> : <Badge>{tCommon('common.no')}</Badge>}</TableCell></TableRow>))}
        </Table>
      )}
    </div>
  )
}

// ============ Asset Families Page ============
export function AssetFamiliesPage() {
  const { t } = useTranslation('assets')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [items, setItems] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [form, setForm] = useState({ code: '', name: '', default_account: '', default_depreciation_account: '', default_duration_months: 60, default_method: 'linear' as const, depreciation_rate: 0, description: '' })

  const loadData = useCallback(async () => { setLoading(true); try { setItems(await getAssetFamilies() || []) } catch { } finally { setLoading(false) } }, [])
  useEffect(() => { loadData() }, [loadData])

  async function handleCreate() { try { await createAssetFamily(form as any); toast('success', tCommon('common.success'), t('families.created')); setShowForm(false); setForm({ code: '', name: '', default_account: '', default_depreciation_account: '', default_duration_months: 60, default_method: 'linear', depreciation_rate: 0, description: '' }); await loadData() } catch (e: any) { toast('error', tCommon('common.error'), e.message) } }
  async function handleDelete(id: string) { if (!window.confirm(tCommon('form.confirmDelete'))) return; try { await deleteAssetFamily(id); await loadData() } catch (e: any) { toast('error', tCommon('common.error'), e.message) } }

  return (
    <div>
      <Breadcrumb items={[{ label: t('families.breadcrumb1'), path: '/assets' }, { label: t('families.title') }]} />
      <PageHeader title={t('families.title')} action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('families.new')}</Button>} />
      {showForm && (<Card className="p-4 mb-4 space-y-3"><div className="grid grid-cols-2 gap-3"><Input placeholder={t('families.code')} value={form.code} onChange={e => setForm({ ...form, code: e.target.value })} /><Input placeholder={t('families.name')} value={form.name} onChange={e => setForm({ ...form, name: e.target.value })} /><Input placeholder={t('families.account')} value={form.default_account} onChange={e => setForm({ ...form, default_account: e.target.value })} /><Input type="number" placeholder={t('families.duration')} value={form.default_duration_months} onChange={e => setForm({ ...form, default_duration_months: parseInt(e.target.value) || 60 })} /></div><div className="flex gap-2"><Button onClick={handleCreate}>{tCommon('actions.save')}</Button><Button variant="secondary" onClick={() => setShowForm(false)}>{tCommon('common.cancel')}</Button></div></Card>)}
      {loading ? <SkeletonTable /> : items.length === 0 ? <EmptyState title={t('families.empty')} /> : (
        <Table headers={[t('families.code'), t('families.name'), t('families.account'), t('families.duration'), tCommon('common.actions')]}>
          {items.map(f => (<TableRow key={f.id}><TableCell>{f.code}</TableCell><TableCell>{f.name}</TableCell><TableCell>{f.default_account || '-'}</TableCell><TableCell>{f.default_duration_months || '-'}m</TableCell><TableCell><Button size="sm" variant="danger" onClick={() => handleDelete(f.id)}><Trash2 className="w-4 h-4" /></Button></TableCell></TableRow>))}
        </Table>
      )}
    </div>
  )
}

// ============ Asset Revaluations Page ============
export function AssetRevaluationPage() {
  const { t } = useTranslation('assets')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const { formatCurrency } = useLocale()
  const [items, setItems] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [form, setForm] = useState({ asset_id: '', revaluation_date: '', old_value: 0, new_value: 0, reason: '' })

  const loadData = useCallback(async () => { setLoading(true); try { setItems(await getAssetRevaluations() || []) } catch { } finally { setLoading(false) } }, [])
  useEffect(() => { loadData() }, [loadData])

  async function handleCreate() { try { const diff = form.new_value - form.old_value; await createAssetRevaluation({ ...form, difference: diff } as any); toast('success', tCommon('common.success'), t('revaluations.created')); setShowForm(false); await loadData() } catch (e: any) { toast('error', tCommon('common.error'), e.message) } }

  return (
    <div>
      <Breadcrumb items={[{ label: t('revaluations.breadcrumb1'), path: '/assets' }, { label: t('revaluations.title') }]} />
      <PageHeader title={t('revaluations.title')} action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('revaluations.new')}</Button>} />
      {showForm && (<Card className="p-4 mb-4 space-y-3"><div className="grid grid-cols-2 gap-3"><Input placeholder={t('revaluations.assetId')} value={form.asset_id} onChange={e => setForm({ ...form, asset_id: e.target.value })} /><Input type="date" value={form.revaluation_date} onChange={e => setForm({ ...form, revaluation_date: e.target.value })} /><Input type="number" placeholder={t('revaluations.oldValue')} value={form.old_value} onChange={e => setForm({ ...form, old_value: parseFloat(e.target.value) || 0 })} /><Input type="number" placeholder={t('revaluations.newValue')} value={form.new_value} onChange={e => setForm({ ...form, new_value: parseFloat(e.target.value) || 0 })} /></div><div className="flex gap-2"><Button onClick={handleCreate}>{tCommon('actions.save')}</Button><Button variant="secondary" onClick={() => setShowForm(false)}>{tCommon('common.cancel')}</Button></div></Card>)}
      {loading ? <SkeletonTable /> : items.length === 0 ? <EmptyState title={t('revaluations.empty')} /> : (
        <Table headers={[t('revaluations.asset'), t('revaluations.date'), t('revaluations.oldValue'), t('revaluations.newValue'), t('revaluations.difference')]}>
          {items.map(r => (<TableRow key={r.id}><TableCell>{r.fixed_assets?.name || '-'}</TableCell><TableCell>{r.revaluation_date}</TableCell><TableCell>{formatCurrency(r.old_value)}</TableCell><TableCell>{formatCurrency(r.new_value)}</TableCell><TableCell>{formatCurrency(r.difference)}</TableCell></TableRow>))}
        </Table>
      )}
    </div>
  )
}

// ============ Asset Batch Disposals Page ============
export function BatchDisposalPage() {
  const { t } = useTranslation('assets')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const { formatCurrency } = useLocale()
  const [items, setItems] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [form, setForm] = useState({ batch_number: '', disposal_date: '', notes: '' })

  const loadData = useCallback(async () => { setLoading(true); try { setItems(await getAssetBatchDisposals() || []) } catch { } finally { setLoading(false) } }, [])
  useEffect(() => { loadData() }, [loadData])

  async function handleCreate() { try { await createAssetBatchDisposal(form as any); toast('success', tCommon('common.success'), t('batchDisposals.created')); setShowForm(false); await loadData() } catch (e: any) { toast('error', tCommon('common.error'), e.message) } }
  async function handleProcess(id: string) { try { await updateAssetBatchDisposal(id, { status: 'processed' }); await loadData() } catch (e: any) { toast('error', tCommon('common.error'), e.message) } }

  return (
    <div>
      <Breadcrumb items={[{ label: t('batchDisposals.breadcrumb1'), path: '/assets' }, { label: t('batchDisposals.title') }]} />
      <PageHeader title={t('batchDisposals.title')} action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('batchDisposals.new')}</Button>} />
      {showForm && (<Card className="p-4 mb-4 space-y-3"><div className="grid grid-cols-2 gap-3"><Input placeholder={t('batchDisposals.number')} value={form.batch_number} onChange={e => setForm({ ...form, batch_number: e.target.value })} /><Input type="date" value={form.disposal_date} onChange={e => setForm({ ...form, disposal_date: e.target.value })} /></div><div className="flex gap-2"><Button onClick={handleCreate}>{tCommon('actions.save')}</Button><Button variant="secondary" onClick={() => setShowForm(false)}>{tCommon('common.cancel')}</Button></div></Card>)}
      {loading ? <SkeletonTable /> : items.length === 0 ? <EmptyState title={t('batchDisposals.empty')} /> : (
        <Table headers={[t('batchDisposals.number'), t('batchDisposals.date'), t('batchDisposals.assets'), t('batchDisposals.proceeds'), t('batchDisposals.gainLoss'), t('batchDisposals.status'), tCommon('common.actions')]}>
          {items.map(b => (<TableRow key={b.id}><TableCell>{b.batch_number}</TableCell><TableCell>{b.disposal_date}</TableCell><TableCell>{b.total_assets}</TableCell><TableCell>{formatCurrency(b.total_proceeds)}</TableCell><TableCell>{formatCurrency(b.total_gain_loss)}</TableCell><TableCell><Badge>{t(`batchDisposals.statuses.${b.status}`)}</Badge></TableCell><TableCell>{b.status === 'draft' && <Button size="sm" variant="secondary" onClick={() => handleProcess(b.id)}>{t('batchDisposals.process')}</Button>}</TableCell></TableRow>))}
        </Table>
      )}
    </div>
  )
}

// ============ Asset From Entry Page (création immobilisation depuis écriture) ============
export function AssetFromEntryPage() {
  const { t } = useTranslation('assets')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [entryId, setEntryId] = useState('')

  async function handleCreate() {
    if (!entryId) return
    try {
      const { supabase } = await import('@/lib/supabase')
      const { getTenantId } = await import('@/lib/queries')
      const tid = await getTenantId()
      const { data: entry, error: eErr } = await supabase.from('journal_entries').select('*, journal_lines(*)').eq('id', entryId).eq('tenant_id', tid).single()
      if (eErr) throw eErr
      if (!entry) throw new Error(t('fromEntry.notFound'))
      const assetLine = entry.journal_lines?.find((l: any) => parseFloat(l.debit || 0) > 0)
      if (!assetLine) throw new Error(t('fromEntry.noAssetLine'))
      const { error: aErr } = await supabase.from('fixed_assets').insert({
        name: entry.description || t('fromEntry.defaultName'),
        acquisition_date: entry.entry_date,
        acquisition_value: parseFloat(assetLine.debit),
        asset_type: 'owned',
        purchase_entry_id: entry.id,
        tenant_id: tid,
      }).select().single()
      if (aErr) throw aErr
      toast('success', tCommon('common.success'), t('fromEntry.created'))
      setEntryId('')
    } catch (e: any) { toast('error', tCommon('common.error'), e.message) }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('fromEntry.breadcrumb1'), path: '/assets' }, { label: t('fromEntry.title') }]} />
      <PageHeader title={t('fromEntry.title')} />
      <Card className="p-4 space-y-3">
        <Input placeholder={t('fromEntry.entryId')} value={entryId} onChange={e => setEntryId(e.target.value)} />
        <Button onClick={handleCreate}>{t('fromEntry.create')}</Button>
      </Card>
    </div>
  )
}
