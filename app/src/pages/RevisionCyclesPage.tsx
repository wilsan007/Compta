import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { useToast } from '@/lib/toast'
import { getRevisionCycles, createRevisionCycle, updateRevisionCycle, deleteRevisionCycle } from '@/lib/queries/misc'
import { Plus, Trash2, Edit2, X, RefreshCw } from 'lucide-react'
import type { RevisionCycle } from '@/types'

export function RevisionCyclesPage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [cycles, setCycles] = useState<RevisionCycle[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [editing, setEditing] = useState<RevisionCycle | null>(null)

  const [form, setForm] = useState({
    name: '',
    frequency: 'annual' as 'monthly' | 'quarterly' | 'annual' | 'custom',
    start_month: 1,
    account_class: '',
    active: true,
  })

  const load = useCallback(async () => {
    try {
      setLoading(true)
      const data = await getRevisionCycles()
      setCycles(data || [])
    } catch (err) {
      console.error('Error loading revision cycles:', err)
      toast('error', t('revisionCycles.title'), t('revisionCycles.loadError'))
    } finally {
      setLoading(false)
    }
  }, [toast, t])

  useEffect(() => { load() }, [load])

  function resetForm() {
    setForm({ name: '', frequency: 'annual', start_month: 1, account_class: '', active: true })
    setEditing(null)
    setShowForm(false)
  }

  function startEdit(cyc: RevisionCycle) {
    setEditing(cyc)
    setForm({
      name: cyc.name,
      frequency: cyc.frequency,
      start_month: cyc.start_month,
      account_class: cyc.account_class || '',
      active: cyc.active,
    })
    setShowForm(true)
  }

  async function handleSubmit() {
    try {
      const payload = { ...form, account_class: form.account_class || null }
      if (editing) {
        await updateRevisionCycle(editing.id, payload)
        toast('success', t('revisionCycles.title'), t('revisionCycles.updateSuccess'))
      } else {
        await createRevisionCycle(payload as any)
        toast('success', t('revisionCycles.title'), t('revisionCycles.createSuccess'))
      }
      resetForm()
      await load()
    } catch (err) {
      console.error('Error saving revision cycle:', err)
      toast('error', t('revisionCycles.title'), t('revisionCycles.saveError'))
    }
  }

  async function handleDelete(id: string) {
    if (!confirm(t('revisionCycles.deleteConfirm'))) return
    try {
      await deleteRevisionCycle(id)
      toast('success', t('revisionCycles.title'), t('revisionCycles.deleteSuccess'))
      await load()
    } catch (err) {
      console.error('Error deleting:', err)
      toast('error', t('revisionCycles.title'), t('revisionCycles.deleteError'))
    }
  }

  if (loading) {
    return (
      <div>
        <Breadcrumb items={[{ label: t('title') }, { label: t('home.structure') }, { label: t('revisionCycles.title') }]} />
        <PageHeader title={t('revisionCycles.title')} subtitle={t('revisionCycles.subtitle')} />
        <SkeletonTable rows={6} cols={6} />
      </div>
    )
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('title') }, { label: t('home.structure') }, { label: t('revisionCycles.title') }]} />
      <PageHeader title={t('revisionCycles.title')} subtitle={t('revisionCycles.subtitle')} />

      {showForm && (
        <Card className="mb-4">
          <div className="p-4">
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-lg font-semibold">{editing ? t('revisionCycles.edit') : t('revisionCycles.create')}</h3>
              <Button variant="secondary" onClick={resetForm} ariaLabel={tCommon('actions.close')}><X className="w-4 h-4" aria-hidden="true" /></Button>
            </div>
            <div className="grid grid-cols-3 gap-4">
              <Input label={t('revisionCycles.name')} value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} required />
              <Select
                label={t('revisionCycles.frequency')}
                value={form.frequency}
                onChange={(e) => setForm({ ...form, frequency: e.target.value as any })}
                options={[
                  { value: 'monthly', label: t('revisionCycles.frequencies.monthly') },
                  { value: 'quarterly', label: t('revisionCycles.frequencies.quarterly') },
                  { value: 'annual', label: t('revisionCycles.frequencies.annual') },
                  { value: 'custom', label: t('revisionCycles.frequencies.custom') },
                ]}
              />
              <div>
                <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('revisionCycles.startMonth')}</label>
                <input className="input" type="number" min={1} max={12} value={form.start_month} onChange={(e) => setForm({ ...form, start_month: Number(e.target.value) })} />
              </div>
              <Input label={t('revisionCycles.accountClass')} value={form.account_class} onChange={(e) => setForm({ ...form, account_class: e.target.value })} />
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
          <Plus className="w-4 h-4" /> {t('revisionCycles.create')}
        </Button>
      </div>

      {cycles.length === 0 ? (
        <EmptyState icon={<RefreshCw className="w-8 h-8" />} title={t('revisionCycles.empty')} description={t('revisionCycles.emptyDesc')} />
      ) : (
        <Card>
          <Table headers={[
            t('revisionCycles.name'),
            t('revisionCycles.frequency'),
            t('revisionCycles.startMonth'),
            t('revisionCycles.accountClass'),
            t('revisionCycles.status'),
            '',
          ]}>
            {cycles.map((cyc) => (
              <TableRow key={cyc.id}>
                <TableCell className="font-medium">{cyc.name}</TableCell>
                <TableCell className="text-xs">{t(`revisionCycles.frequencies.${cyc.frequency}`)}</TableCell>
                <TableCell className="font-mono text-xs">{cyc.start_month}</TableCell>
                <TableCell className="font-mono text-xs">{cyc.account_class || '—'}</TableCell>
                <TableCell><Badge variant={cyc.active ? 'success' : 'neutral'}>{cyc.active ? tCommon('common.active') : tCommon('common.inactive')}</Badge></TableCell>
                <TableCell>
                  <div className="flex gap-1">
                    <button onClick={() => startEdit(cyc)} className="p-1 text-[var(--color-text-secondary)] hover:text-[var(--color-primary)]" aria-label={tCommon('actions.edit')} title={tCommon('actions.edit')}><Edit2 className="w-4 h-4" aria-hidden="true" /></button>
                    <button onClick={() => handleDelete(cyc.id)} className="p-1 text-[var(--color-text-secondary)] hover:text-[var(--color-danger)]" aria-label={tCommon('actions.delete')} title={tCommon('actions.delete')}><Trash2 className="w-4 h-4" aria-hidden="true" /></button>
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
