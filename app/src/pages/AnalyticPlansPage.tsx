import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Input } from '@/components/ui'
import { getAnalyticPlans, createAnalyticPlan, deleteAnalyticPlan } from '@/lib/queries'
import { Plus, Trash2, Layers } from 'lucide-react'
import type { AnalyticPlan } from '@/types'
import { useToast } from '@/lib/toast'

export function AnalyticPlansPage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [plans, setPlans] = useState<AnalyticPlan[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const data = await getAnalyticPlans()
      setPlans(data || [])
    } catch (err) {
      console.error('Failed to load analytic plans:', err)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  async function handleDelete(id: string) {
    if (!window.confirm(t('analyticPlans.deleteConfirm'))) return
    try {
      await deleteAnalyticPlan(id)
      toast('success', tCommon('common.success'), t('analyticPlans.deleteSuccess'))
      await loadData()
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    }
  }

  const tableHeaders = [t('analyticPlans.code'), t('analyticPlans.name'), t('analyticPlans.description'), t('analyticPlans.default'), tCommon('common.table.actions')]

  return (
    <div>
      <Breadcrumb items={[{ label: t('home.breadcrumb') }, { label: t('structure.breadcrumb') }, { label: t('analyticPlans.breadcrumb') }]} />
      <PageHeader
        title={t('analyticPlans.title')}
        subtitle={t('analyticPlans.subtitle')}
        action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('analyticPlans.new')}</Button>}
      />

      {loading ? (
        <SkeletonTable rows={3} cols={5} />
      ) : plans.length === 0 ? (
        <EmptyState
          icon={<Layers className="w-8 h-8" />}
          title={t('analyticPlans.noPlans')}
          description={t('analyticPlans.noPlansDescription')}
          action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('analyticPlans.new')}</Button>}
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
                  <button onClick={() => handleDelete(plan.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]">
                    <Trash2 className="w-4 h-4" />
                  </button>
                </TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}

      {showForm && <PlanForm onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadData() }} />}
    </div>
  )
}

function PlanForm({ onClose, onSaved }: { onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [code, setCode] = useState('')
  const [name, setName] = useState('')
  const [description, setDescription] = useState('')
  const [isDefault, setIsDefault] = useState(false)
  const [saving, setSaving] = useState(false)

  async function handleSave() {
    if (!code || !name) {
      toast('warning', tCommon('common.warning'), tCommon('common.fillRequired'))
      return
    }
    setSaving(true)
    try {
      await createAnalyticPlan({ code, name, description: description || null, is_default: isDefault, active: true })
      toast('success', tCommon('common.success'), t('analyticPlans.saveSuccess'))
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
          <h2 className="text-lg font-semibold">{t('analyticPlans.create')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]">✕</button>
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
          <Button variant="secondary" onClick={onClose}>{tCommon('common.actions.cancel')}</Button>
          <Button onClick={handleSave} disabled={saving}>{saving ? tCommon('common.saving') : tCommon('common.actions.save')}</Button>
        </div>
      </div>
    </div>
  )
}
