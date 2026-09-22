import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Input } from '@/components/ui'
import { getAnalyticPlans, createAnalyticPlan, updateAnalyticPlan, deleteAnalyticPlan } from '@/lib/queries/accounting'
import { Plus, Trash2, Pencil, Layers, X } from 'lucide-react'
import type { AnalyticPlan } from '@/types'
import { useToast } from '@/lib/toast'
import { confirmSync } from '@/lib/confirm'

export function AnalyticPlansPage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [plans, setPlans] = useState<AnalyticPlan[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [editing, setEditing] = useState<AnalyticPlan | null>(null)

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const data = await getAnalyticPlans()
      setPlans(data || [])
    } catch (err: any) { console.error('Failed to load analytic plans:', err)
    toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadingError'))
    } finally {
      setLoading(false)
    }
  }, [tCommon, toast])

  useEffect(() => { loadData() }, [loadData])

  function startEdit(plan: AnalyticPlan) {
    setEditing(plan)
    setShowForm(true)
  }

  function openCreate() {
    setEditing(null)
    setShowForm(true)
  }

  async function handleDelete(id: string) {
    if (!confirmSync(t('analyticPlans.deleteConfirm'))) return
    try {
      await deleteAnalyticPlan(id)
      toast('success', tCommon('common.success'), t('analyticPlans.deleteSuccess'))
      await loadData()
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    }
  }

  const tableHeaders = [t('analyticPlans.code'), t('analyticPlans.name'), t('analyticPlans.description'), t('analyticPlans.default'), tCommon('table.actions')]

  return (
    <div>
      <Breadcrumb items={[{ label: t('home.breadcrumb') }, { label: t('structure.breadcrumb') }, { label: t('analyticPlans.breadcrumb') }]} />
      <PageHeader
        title={t('analyticPlans.title')}
        subtitle={t('analyticPlans.subtitle')}
        action={<Button onClick={openCreate}><Plus className="w-4 h-4" /> {t('analyticPlans.new')}</Button>}
      />

      {loading ? (
        <SkeletonTable rows={3} cols={5} />
      ) : plans.length === 0 ? (
        <EmptyState
          icon={<Layers className="w-8 h-8" />}
          title={t('analyticPlans.noPlans')}
          description={t('analyticPlans.noPlansDescription')}
          action={<Button onClick={openCreate}><Plus className="w-4 h-4" /> {t('analyticPlans.new')}</Button>}
        />
      ) : (
        <Card>
          <Table headers={tableHeaders}>
            {plans.map((plan) => (
              <TableRow key={plan.id}>
                <TableCell className="font-mono font-semibold">{plan.code}</TableCell>
                <TableCell className="text-sm">{plan.name}</TableCell>
                <TableCell className="text-xs text-[var(--color-text-secondary)]">{plan.description || '—'}</TableCell>
                <TableCell>{plan.is_default && <Badge variant="success">{t('analyticPlans.default')}</Badge>}</TableCell>
                <TableCell>
                  <div className="flex gap-2">
                    <button onClick={() => startEdit(plan)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-text-secondary)]" aria-label={tCommon('actions.edit')} title={tCommon('actions.edit')}>
                      <Pencil className="w-4 h-4" aria-hidden="true" /></button>
                    <button onClick={() => handleDelete(plan.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]" aria-label={tCommon('actions.delete')} title={tCommon('actions.delete')}>
                      <Trash2 className="w-4 h-4" aria-hidden="true" /></button>
                  </div>
                </TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}

      {showForm && <PlanForm plan={editing} onClose={() => { setShowForm(false); setEditing(null) }} onSaved={() => { setShowForm(false); setEditing(null); loadData() }} />}
    </div>
  )
}

function PlanForm({ plan, onClose, onSaved }: { plan: AnalyticPlan | null; onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [code, setCode] = useState(plan?.code || '')
  const [name, setName] = useState(plan?.name || '')
  const [description, setDescription] = useState(plan?.description || '')
  const [isDefault, setIsDefault] = useState(plan?.is_default || false)
  const [saving, setSaving] = useState(false)

  async function handleSave() {
    if (!code || !name) {
      toast('warning', tCommon('common.warning'), tCommon('common.fillRequired'))
      return
    }
    setSaving(true)
    try {
      const payload = { code, name, description: description || null, is_default: isDefault, active: true }
      if (plan) {
        await updateAnalyticPlan(plan.id, payload)
        toast('success', tCommon('common.success'), t('analyticPlans.saveSuccess'))
      } else {
        await createAnalyticPlan(payload)
        toast('success', tCommon('common.success'), t('analyticPlans.saveSuccess'))
      }
      onSaved()
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '32rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{plan ? t('analyticPlans.edit') : t('analyticPlans.create')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]" aria-label={tCommon('actions.close')} title={tCommon('actions.close')}><X className="w-4 h-4" aria-hidden="true" /></button>
        </div>
        <div className="p-6 space-y-4">
          <Input label={t('analyticPlans.code')} value={code} onChange={(e) => setCode(e.target.value)} required />
          <Input label={t('analyticPlans.name')} value={name} onChange={(e) => setName(e.target.value)} required />
          <Input label={t('analyticPlans.description')} value={description} onChange={(e) => setDescription(e.target.value)} />
          <label className="flex items-center gap-2 text-sm">
            <input type="checkbox" checked={isDefault} onChange={(e) => setIsDefault(e.target.checked)} />
            {t('analyticPlans.setDefault')}
          </label>
        </div>
        <div className="flex justify-end gap-3 px-6 py-4 border-t border-[var(--color-border)]">
          <Button variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
          <Button onClick={handleSave} disabled={saving}>{saving ? tCommon('common.saving') : tCommon('actions.save')}</Button>
        </div>
      </div>
    </div>
  )
}
