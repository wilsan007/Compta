import { useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Button, Input, Select } from '@/components/ui'
import { getEmployees } from '@/lib/queries'
import { formatDate } from '@/lib/utils'
import { Plus, Pencil, Trash2, X, GraduationCap } from 'lucide-react'
import type { Employee } from '@/types'

interface Training {
  id: string
  employee_id: string
  employee_name: string
  title: string
  provider: string
  start_date: string
  end_date: string
  cost: number
  status: 'planned' | 'in_progress' | 'completed' | 'cancelled'
  skills: string
  notes: string
}

export function TrainingPage() {
  const { t } = useTranslation('hr')
  const { t: tCommon } = useTranslation('common')
  const { t: tNav } = useTranslation('nav')
  const [trainings, setTrainings] = useState<Training[]>([])
  const [employees, setEmployees] = useState<Employee[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [editing, setEditing] = useState<Training | null>(null)
  const [form, setForm] = useState<Partial<Training>>({})

  useEffect(() => { load() }, [])

  async function load() {
    try {
      const emps = await getEmployees()
      setEmployees(emps || [])
      setTrainings([])
    } catch (err) {
      console.error('Error loading training data:', err)
    } finally {
      setLoading(false)
    }
  }

  function openCreate() {
    setEditing(null)
    setForm({ status: 'planned', cost: 0 })
    setShowForm(true)
  }

  function openEdit(t: Training) {
    setEditing(t)
    setForm(t)
    setShowForm(true)
  }

  function handleSave() {
    if (!form.title || !form.employee_id) return
    const emp = employees.find(e => e.id === form.employee_id)
    const newTraining: Training = {
      id: editing?.id || crypto.randomUUID(),
      employee_id: form.employee_id!,
      employee_name: emp?.name || '',
      title: form.title!,
      provider: form.provider || '',
      start_date: form.start_date || new Date().toISOString().split('T')[0],
      end_date: form.end_date || new Date().toISOString().split('T')[0],
      cost: form.cost || 0,
      status: form.status as Training['status'] || 'planned',
      skills: form.skills || '',
      notes: form.notes || '',
    }
    if (editing) {
      setTrainings(prev => prev.map(t => t.id === editing.id ? newTraining : t))
    } else {
      setTrainings(prev => [...prev, newTraining])
    }
    setShowForm(false)
  }

  function handleDelete(id: string) {
    setTrainings(prev => prev.filter(t => t.id !== id))
  }

  if (loading) return <SkeletonTable rows={6} />

  const statusLabels: Record<string, string> = {
    planned: t('training.statuses.planned'), in_progress: t('training.statuses.in_progress'), completed: t('training.statuses.completed'), cancelled: t('training.statuses.cancelled'),
  }

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('sections.hr') }, { label: t('training.title') }]} />
      <PageHeader title={t('training.title')} subtitle={t('training.subtitle')} action={
        <Button onClick={openCreate}><Plus className="w-4 h-4 mr-2" /> {t('training.new')}</Button>
      } />

      {showForm && (
        <Card className="mb-4">
          <div className="flex items-center justify-between mb-4">
            <h3 className="font-semibold">{editing ? t('training.edit') : t('training.new')}</h3>
            <button onClick={() => setShowForm(false)}><X className="w-4 h-4" /></button>
          </div>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <Select label={t('training.employee')} value={form.employee_id || ''} onChange={(e) => setForm({ ...form, employee_id: e.target.value })} options={[
              { value: '', label: tCommon('form.selectPlaceholder') || '—' },
              ...employees.map(e => ({ value: e.id, label: e.name })),
            ]} required />
            <Input label={t('training.trainingTitle')} value={form.title || ''} onChange={(e) => setForm({ ...form, title: e.target.value })} required />
            <Input label={t('training.provider')} value={form.provider || ''} onChange={(e) => setForm({ ...form, provider: e.target.value })} />
            <Select label={t('training.status')} value={form.status || 'planned'} onChange={(e) => setForm({ ...form, status: e.target.value as Training['status'] })} options={[
              { value: 'planned', label: t('training.statuses.planned') },
              { value: 'in_progress', label: t('training.statuses.in_progress') },
              { value: 'completed', label: t('training.statuses.completed') },
              { value: 'cancelled', label: t('training.statuses.cancelled') },
            ]} />
            <Input label={t('training.startDate')} type="date" value={form.start_date || ''} onChange={(e) => setForm({ ...form, start_date: e.target.value })} />
            <Input label={t('training.endDate')} type="date" value={form.end_date || ''} onChange={(e) => setForm({ ...form, end_date: e.target.value })} />
            <Input label={t('training.cost')} type="number" value={String(form.cost || 0)} onChange={(e) => setForm({ ...form, cost: Number(e.target.value) })} />
            <Input label={t('training.skills')} value={form.skills || ''} onChange={(e) => setForm({ ...form, skills: e.target.value })} />
          </div>
          <div className="flex justify-end gap-2 mt-4">
            <Button variant="secondary" onClick={() => setShowForm(false)}>{tCommon('actions.cancel')}</Button>
            <Button onClick={handleSave}>{editing ? t('training.edit') : t('training.create')}</Button>
          </div>
        </Card>
      )}

      {trainings.length === 0 ? (
        <EmptyState title={t('training.noTrainings')} description={t('training.noTrainingsDescription')} icon={<GraduationCap className="w-8 h-8" />} />
      ) : (
        <Card>
          <Table headers={[t('training.employee'), t('training.trainingTitle'), t('training.provider'), t('training.startDate'), t('training.cost'), t('training.status'), tCommon('table.actions')]}>
            <tbody>
              {trainings.map((tr) => (
                <TableRow key={tr.id}>
                  <TableCell>{tr.employee_name}</TableCell>
                  <TableCell className="font-medium">{tr.title}</TableCell>
                  <TableCell>{tr.provider || '—'}</TableCell>
                  <TableCell className="text-xs">{formatDate(tr.start_date)} → {formatDate(tr.end_date)}</TableCell>
                  <TableCell className="text-right">{tr.cost > 0 ? `${tr.cost.toFixed(2)} €` : '—'}</TableCell>
                  <TableCell>
                    <span className="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-gray-100 text-gray-700">
                      {statusLabels[tr.status] || tr.status}
                    </span>
                  </TableCell>
                  <TableCell>
                    <div className="flex items-center gap-1">
                      <button onClick={() => openEdit(tr)} className="p-1 hover:bg-gray-100 rounded"><Pencil className="w-3.5 h-3.5" /></button>
                      <button onClick={() => handleDelete(tr.id)} className="p-1 hover:bg-gray-100 rounded text-red-600"><Trash2 className="w-3.5 h-3.5" /></button>
                    </div>
                  </TableCell>
                </TableRow>
              ))}
            </tbody>
          </Table>
        </Card>
      )}
    </div>
  )
}
