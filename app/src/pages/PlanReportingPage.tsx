import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { formatDate } from '@/lib/utils'
import { useToast } from '@/lib/toast'
import { getReportingPlans, createReportingPlan, updateReportingPlan, deleteReportingPlan } from '@/lib/queries/misc'
import { Plus, Trash2, Edit2, X, FileBarChart } from 'lucide-react'
import type { ReportingPlan } from '@/types'

export function PlanReportingPage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [plans, setPlans] = useState<ReportingPlan[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [editing, setEditing] = useState<ReportingPlan | null>(null)

  const [form, setForm] = useState({
    name: '',
    report_type: 'balance' as 'balance' | 'pnl' | 'cashflow' | 'vat' | 'custom',
    schedule: 'manual' as 'manual' | 'monthly' | 'quarterly' | 'annual',
    format: 'pdf' as 'pdf' | 'excel' | 'csv',
    recipients: '',
    active: true,
  })

  const load = useCallback(async () => {
    try {
      setLoading(true)
      const data = await getReportingPlans()
      setPlans(data || [])
    } catch (err) {
      console.error('Error loading reporting plans:', err)
      toast('error', t('reportingPlans.title'), t('reportingPlans.loadError'))
    } finally {
      setLoading(false)
    }
  }, [toast, t])

  useEffect(() => { load() }, [load])

  function resetForm() {
    setForm({ name: '', report_type: 'balance', schedule: 'manual', format: 'pdf', recipients: '', active: true })
    setEditing(null)
    setShowForm(false)
  }

  function startEdit(plan: ReportingPlan) {
    setEditing(plan)
    setForm({
      name: plan.name,
      report_type: plan.report_type,
      schedule: plan.schedule,
      format: plan.format,
      recipients: plan.recipients || '',
      active: plan.active,
    })
    setShowForm(true)
  }

  async function handleSubmit() {
    try {
      const payload = { ...form, recipients: form.recipients || null, parameters: {} }
      if (editing) {
        await updateReportingPlan(editing.id, payload)
        toast('success', t('reportingPlans.title'), t('reportingPlans.updateSuccess'))
      } else {
        await createReportingPlan(payload as any)
        toast('success', t('reportingPlans.title'), t('reportingPlans.createSuccess'))
      }
      resetForm()
      await load()
    } catch (err) {
      console.error('Error saving reporting plan:', err)
      toast('error', t('reportingPlans.title'), t('reportingPlans.saveError'))
    }
  }

  async function handleDelete(id: string) {
    if (!confirm(t('reportingPlans.deleteConfirm'))) return
    try {
      await deleteReportingPlan(id)
      toast('success', t('reportingPlans.title'), t('reportingPlans.deleteSuccess'))
      await load()
    } catch (err) {
      console.error('Error deleting:', err)
      toast('error', t('reportingPlans.title'), t('reportingPlans.deleteError'))
    }
  }

  if (loading) {
    return (
      <div>
        <Breadcrumb items={[{ label: t('title') }, { label: t('home.structure') }, { label: t('reportingPlans.title') }]} />
        <PageHeader title={t('reportingPlans.title')} subtitle={t('reportingPlans.subtitle')} />
        <SkeletonTable rows={6} cols={6} />
      </div>
    )
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('title') }, { label: t('home.structure') }, { label: t('reportingPlans.title') }]} />
      <PageHeader title={t('reportingPlans.title')} subtitle={t('reportingPlans.subtitle')} />

      {showForm && (
        <Card className="mb-4">
          <div className="p-4">
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-lg font-semibold">{editing ? t('reportingPlans.edit') : t('reportingPlans.create')}</h3>
              <Button variant="secondary" onClick={resetForm}><X className="w-4 h-4" /></Button>
            </div>
            <div className="grid grid-cols-3 gap-4">
              <Input label={t('reportingPlans.name')} value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} required />
              <Select
                label={t('reportingPlans.reportType')}
                value={form.report_type}
                onChange={(e) => setForm({ ...form, report_type: e.target.value as any })}
                options={[
                  { value: 'balance', label: t('reportingPlans.types.balance') },
                  { value: 'pnl', label: t('reportingPlans.types.pnl') },
                  { value: 'cashflow', label: t('reportingPlans.types.cashflow') },
                  { value: 'vat', label: t('reportingPlans.types.vat') },
                  { value: 'custom', label: t('reportingPlans.types.custom') },
                ]}
              />
              <Select
                label={t('reportingPlans.schedule')}
                value={form.schedule}
                onChange={(e) => setForm({ ...form, schedule: e.target.value as any })}
                options={[
                  { value: 'manual', label: t('reportingPlans.schedules.manual') },
                  { value: 'monthly', label: t('reportingPlans.schedules.monthly') },
                  { value: 'quarterly', label: t('reportingPlans.schedules.quarterly') },
                  { value: 'annual', label: t('reportingPlans.schedules.annual') },
                ]}
              />
              <Select
                label={t('reportingPlans.format')}
                value={form.format}
                onChange={(e) => setForm({ ...form, format: e.target.value as any })}
                options={[
                  { value: 'pdf', label: 'PDF' },
                  { value: 'excel', label: 'Excel' },
                  { value: 'csv', label: 'CSV' },
                ]}
              />
              <Input label={t('reportingPlans.recipients')} value={form.recipients} onChange={(e) => setForm({ ...form, recipients: e.target.value })} />
              <div className="flex items-end">
                <label className="flex items-center gap-2 text-sm">
                  <input type="checkbox" checked={form.active} onChange={(e) => setForm({ ...form, active: e.target.checked })} />
                  {tCommon('common.active')}
                </label>
              </div>
            </div>
            <div className="flex justify-end gap-3 mt-4">
              <Button variant="secondary" onClick={resetForm}>{tCommon('actions.cancel')}</Button>
              <Button onClick={handleSubmit} disabled={!form.name}>{tCommon('actions.save')}</Button>
            </div>
          </div>
        </Card>
      )}

      <div className="flex justify-end mb-3">
        <Button onClick={() => { resetForm(); setShowForm(true) }}>
          <Plus className="w-4 h-4" /> {t('reportingPlans.create')}
        </Button>
      </div>

      {plans.length === 0 ? (
        <EmptyState icon={<FileBarChart className="w-8 h-8" />} title={t('reportingPlans.empty')} description={t('reportingPlans.emptyDesc')} />
      ) : (
        <Card>
          <Table headers={[
            t('reportingPlans.name'),
            t('reportingPlans.reportType'),
            t('reportingPlans.schedule'),
            t('reportingPlans.format'),
            t('reportingPlans.lastGenerated'),
            t('reportingPlans.status'),
            '',
          ]}>
            {plans.map((plan) => (
              <TableRow key={plan.id}>
                <TableCell className="font-medium">{plan.name}</TableCell>
                <TableCell className="text-xs">{t(`reportingPlans.types.${plan.report_type}`)}</TableCell>
                <TableCell className="text-xs">{t(`reportingPlans.schedules.${plan.schedule}`)}</TableCell>
                <TableCell className="font-mono text-xs uppercase">{plan.format}</TableCell>
                <TableCell className="text-xs">{plan.last_generated ? formatDate(plan.last_generated) : '—'}</TableCell>
                <TableCell><Badge variant={plan.active ? 'success' : 'neutral'}>{plan.active ? tCommon('common.active') : tCommon('common.inactive')}</Badge></TableCell>
                <TableCell>
                  <div className="flex gap-1">
                    <button onClick={() => startEdit(plan)} className="p-1 text-[var(--color-text-secondary)] hover:text-[var(--color-primary)]"><Edit2 className="w-4 h-4" /></button>
                    <button onClick={() => handleDelete(plan.id)} className="p-1 text-[var(--color-text-secondary)] hover:text-[var(--color-danger)]"><Trash2 className="w-4 h-4" /></button>
                  </div>
                </TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}
    </div>
  )
}
