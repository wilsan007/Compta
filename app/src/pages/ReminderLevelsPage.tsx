import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Input } from '@/components/ui'
import { useToast } from '@/lib/toast'
import { getReminderLevels, createReminderLevel, updateReminderLevel, deleteReminderLevel } from '@/lib/queries/misc'
import { Plus, Trash2, Edit2, X, Bell } from 'lucide-react'
import type { ReminderLevel } from '@/types'

export function ReminderLevelsPage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [levels, setLevels] = useState<ReminderLevel[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [editing, setEditing] = useState<ReminderLevel | null>(null)

  const [form, setForm] = useState({
    level: 1,
    name: '',
    template: '',
    days_after_due: 0,
    penalty_rate: 0,
    active: true,
  })

  const load = useCallback(async () => {
    try {
      setLoading(true)
      const data = await getReminderLevels()
      setLevels(data || [])
    } catch (err) {
      console.error('Error loading reminder levels:', err)
      toast('error', t('reminderLevels.title'), t('reminderLevels.loadError'))
    } finally {
      setLoading(false)
    }
  }, [toast, t])

  useEffect(() => { load() }, [load])

  function resetForm() {
    setForm({ level: 1, name: '', template: '', days_after_due: 0, penalty_rate: 0, active: true })
    setEditing(null)
    setShowForm(false)
  }

  function startEdit(lvl: ReminderLevel) {
    setEditing(lvl)
    setForm({
      level: lvl.level,
      name: lvl.name,
      template: lvl.template || '',
      days_after_due: lvl.days_after_due,
      penalty_rate: lvl.penalty_rate,
      active: lvl.active,
    })
    setShowForm(true)
  }

  async function handleSubmit() {
    try {
      const payload = { ...form, template: form.template || null }
      if (editing) {
        await updateReminderLevel(editing.id, payload)
        toast('success', t('reminderLevels.title'), t('reminderLevels.updateSuccess'))
      } else {
        await createReminderLevel(payload as any)
        toast('success', t('reminderLevels.title'), t('reminderLevels.createSuccess'))
      }
      resetForm()
      await load()
    } catch (err) {
      console.error('Error saving reminder level:', err)
      toast('error', t('reminderLevels.title'), t('reminderLevels.saveError'))
    }
  }

  async function handleDelete(id: string) {
    if (!confirm(t('reminderLevels.deleteConfirm'))) return
    try {
      await deleteReminderLevel(id)
      toast('success', t('reminderLevels.title'), t('reminderLevels.deleteSuccess'))
      await load()
    } catch (err) {
      console.error('Error deleting:', err)
      toast('error', t('reminderLevels.title'), t('reminderLevels.deleteError'))
    }
  }

  if (loading) {
    return (
      <div>
        <Breadcrumb items={[{ label: t('title') }, { label: t('home.structure') }, { label: t('reminderLevels.title') }]} />
        <PageHeader title={t('reminderLevels.title')} subtitle={t('reminderLevels.subtitle')} />
        <SkeletonTable rows={6} cols={6} />
      </div>
    )
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('title') }, { label: t('home.structure') }, { label: t('reminderLevels.title') }]} />
      <PageHeader title={t('reminderLevels.title')} subtitle={t('reminderLevels.subtitle')} />

      {showForm && (
        <Card className="mb-4">
          <div className="p-4">
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-lg font-semibold">{editing ? t('reminderLevels.edit') : t('reminderLevels.create')}</h3>
              <Button variant="secondary" onClick={resetForm}><X className="w-4 h-4" /></Button>
            </div>
            <div className="grid grid-cols-3 gap-4">
              <div>
                <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('reminderLevels.level')}</label>
                <input
                  className="input"
                  type="number"
                  min={1}
                  max={10}
                  value={form.level}
                  onChange={(e) => setForm({ ...form, level: Number(e.target.value) })}
                />
              </div>
              <Input label={t('reminderLevels.name')} value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} required />
              <Input label={t('reminderLevels.daysAfterDue')} type="number" value={form.days_after_due} onChange={(e) => setForm({ ...form, days_after_due: Number(e.target.value) })} />
              <Input label={t('reminderLevels.penaltyRate')} type="number" step="0.01" value={form.penalty_rate} onChange={(e) => setForm({ ...form, penalty_rate: Number(e.target.value) })} />
              <Input label={t('reminderLevels.template')} value={form.template} onChange={(e) => setForm({ ...form, template: e.target.value })} />
              <div className="flex items-end">
                <label className="flex items-center gap-2 text-sm">
                  <input type="checkbox" checked={form.active} onChange={(e) => setForm({ ...form, active: e.target.checked })} />
                  {tCommon('common.active')}
                </label>
              </div>
            </div>
            <div className="flex justify-end gap-3 mt-4">
              <Button variant="secondary" onClick={resetForm}>{tCommon('actions.cancel')}</Button>
              <Button onClick={handleSubmit} disabled={!form.name || form.level < 1 || form.level > 10}>{tCommon('actions.save')}</Button>
            </div>
          </div>
        </Card>
      )}

      <div className="flex justify-end mb-3">
        <Button onClick={() => { resetForm(); setShowForm(true) }}>
          <Plus className="w-4 h-4" /> {t('reminderLevels.create')}
        </Button>
      </div>

      {levels.length === 0 ? (
        <EmptyState icon={<Bell className="w-8 h-8" />} title={t('reminderLevels.empty')} description={t('reminderLevels.emptyDesc')} />
      ) : (
        <Card>
          <Table headers={[
            t('reminderLevels.level'),
            t('reminderLevels.name'),
            t('reminderLevels.daysAfterDue'),
            t('reminderLevels.penaltyRate'),
            t('reminderLevels.status'),
            '',
          ]}>
            {levels.map((lvl) => (
              <TableRow key={lvl.id}>
                <TableCell className="font-mono font-semibold">{lvl.level}</TableCell>
                <TableCell className="font-medium">{lvl.name}</TableCell>
                <TableCell className="text-xs">{lvl.days_after_due} {t('reminderLevels.days')}</TableCell>
                <TableCell className="font-mono text-xs">{lvl.penalty_rate.toFixed(2)}%</TableCell>
                <TableCell><Badge variant={lvl.active ? 'success' : 'neutral'}>{lvl.active ? tCommon('common.active') : tCommon('common.inactive')}</Badge></TableCell>
                <TableCell>
                  <div className="flex gap-1">
                    <button onClick={() => startEdit(lvl)} className="p-1 text-[var(--color-text-secondary)] hover:text-[var(--color-primary)]"><Edit2 className="w-4 h-4" /></button>
                    <button onClick={() => handleDelete(lvl.id)} className="p-1 text-[var(--color-text-secondary)] hover:text-[var(--color-danger)]"><Trash2 className="w-4 h-4" /></button>
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
