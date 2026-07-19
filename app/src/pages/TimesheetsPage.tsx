import { useEffect, useState, useCallback } from 'react'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { getTimesheets, createTimesheet, updateTimesheet, deleteTimesheet, getEmployees, getProjects } from '@/lib/queries'
import { formatDate } from '@/lib/utils'
import { Clock, Plus, Trash2, X, CheckCircle, XCircle } from 'lucide-react'
import type { Employee, Project } from '@/types'
import { useToast } from '@/lib/toast'

const statusLabels: Record<string, string> = { pending: 'En attente', approved: 'Approuvé', rejected: 'Refusé' }
const statusBadge: Record<string, 'neutral' | 'success' | 'warning' | 'danger' | 'primary'> = {
  pending: 'warning', approved: 'success', rejected: 'danger',
}

export function TimesheetsPage() {
  const { toast } = useToast()
const [timesheets, setTimesheets] = useState<any[]>([])
  const [employees, setEmployees] = useState<Employee[]>([])
  const [projects, setProjects] = useState<Project[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [filterStatus, setFilterStatus] = useState('')

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const [ts, e, p] = await Promise.all([getTimesheets(), getEmployees(), getProjects()])
      setTimesheets(ts)
      setEmployees(e)
      setProjects(p)
    } catch (err) { console.error(err); toast('error', 'Erreur', 'Erreur lors du chargement') } finally { setLoading(false) }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  async function handleApprove(id: string) {
  try { await updateTimesheet(id, { status: 'approved' }); await loadData() } catch (err: any) { toast('error', 'Erreur', err.message || 'échec') }
  }

  async function handleReject(id: string) {
    try { await updateTimesheet(id, { status: 'rejected' }); await loadData() } catch (err: any) { toast('error', 'Erreur', err.message || 'échec') }
  }

  async function handleDelete(id: string) {
    if (!window.confirm('Supprimer cette feuille de temps ?')) return
    try { await deleteTimesheet(id); await loadData() } catch (err: any) { toast('error', 'Erreur', err.message || 'échec') }
  }

  const filtered = filterStatus ? timesheets.filter((t: any) => t.status === filterStatus) : timesheets
  const totalHours = timesheets.reduce((s: number, t: any) => s + Number(t.hours), 0)
  const empName = (id: string) => employees.find(e => e.id === id)?.name || 'N/A'
  const projName = (id: string) => projects.find(p => p.id === id)?.name || '—'

  return (
    <div>
      <Breadcrumb items={[{ label: 'Paie & RH' }, { label: 'Feuilles de temps' }]} />
      <PageHeader
        title="Feuilles de temps"
        subtitle="Suivez le temps de travail de vos employés"
        action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> Nouvelle entrée</Button>}
      />

      <div className="grid grid-cols-2 gap-4 mb-6">
        <Card><div className="p-4"><p className="text-sm text-[var(--color-text-secondary)]">Total heures</p><p className="text-2xl font-bold font-mono">{totalHours.toFixed(1)}h</p></div></Card>
        <Card><div className="p-4"><p className="text-sm text-[var(--color-text-secondary)]">En attente</p><p className="text-2xl font-bold text-[var(--color-warning)]">{timesheets.filter((t: any) => t.status === 'pending').length}</p></div></Card>
      </div>

      <div className="mb-4 flex items-center gap-3">
        <Select value={filterStatus} onChange={(e) => setFilterStatus(e.target.value)} className="max-w-xs" options={[
          { value: '', label: 'Tous statuts' },
          { value: 'pending', label: 'En attente' },
          { value: 'approved', label: 'Approuvé' },
          { value: 'rejected', label: 'Refusé' },
        ]} />
        <span className="text-sm text-[var(--color-text-secondary)]">{filtered.length} entrée(s)</span>
      </div>

      {loading ? (
        <SkeletonTable rows={5} cols={6} />
      ) : filtered.length === 0 ? (
        <EmptyState icon={<Clock className="w-8 h-8" />} title="Aucune feuille de temps" description="Ajoutez votre première entrée." action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> Nouvelle entrée</Button>} />
      ) : (
        <Card>
          <Table headers={['Date', 'Employé', 'Heures', 'Description', 'Projet', 'Statut', 'Actions']}>
            {filtered.map((t: any) => (
              <TableRow key={t.id}>
                <TableCell className="text-xs">{formatDate(t.date)}</TableCell>
                <TableCell className="font-medium text-sm">{t.employees?.name || empName(t.employee_id)}</TableCell>
                <TableCell className="font-mono text-xs">{Number(t.hours).toFixed(1)}h</TableCell>
                <TableCell className="text-sm max-w-xs truncate">{t.description || '—'}</TableCell>
                <TableCell className="text-xs">{projName(t.project_id)}</TableCell>
                <TableCell><Badge variant={statusBadge[t.status]}>{statusLabels[t.status]}</Badge></TableCell>
                <TableCell>
                  <div className="flex items-center gap-1">
                    {t.status === 'pending' && (
                      <>
                        <button onClick={() => handleApprove(t.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-success)]" title="Approuver"><CheckCircle className="w-4 h-4" /></button>
                        <button onClick={() => handleReject(t.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]" title="Refuser"><XCircle className="w-4 h-4" /></button>
                      </>
                    )}
                    <button onClick={() => handleDelete(t.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]"><Trash2 className="w-4 h-4" /></button>
                  </div>
                </TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}

      {showForm && <TimesheetForm employees={employees} projects={projects} onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadData() }} />}
    </div>
  )
}

function TimesheetForm({ employees, projects, onClose, onSaved }: { employees: Employee[]; projects: Project[]; onClose: () => void; onSaved: () => void }) {
  const [employeeId, setEmployeeId] = useState('')
  const { toast } = useToast()
  const [date, setDate] = useState(new Date().toISOString().split('T')[0])
  const [hours, setHours] = useState(8)
  const [description, setDescription] = useState('')
  const [projectId, setProjectId] = useState('')
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      await createTimesheet({
        employee_id: employeeId, date, hours,
        description, project_id: projectId || null, status: 'pending',
      } as any)
      onSaved()
    } catch (err: any) { toast('error', 'Erreur', err.message || 'échec') } finally { setSaving(false) }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '32rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">Nouvelle feuille de temps</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <Select label="Employé" required value={employeeId} onChange={(e) => setEmployeeId(e.target.value)} options={[
            { value: '', label: 'Sélectionner' },
            ...employees.map(e => ({ value: e.id, label: e.name })),
          ]} />
          <div className="grid grid-cols-2 gap-4">
            <Input label="Date" type="date" required value={date} onChange={(e) => setDate(e.target.value)} />
            <Input label="Heures" type="number" step="0.25" required value={hours} onChange={(e) => setHours(Number(e.target.value))} />
          </div>
          <Input label="Description" value={description} onChange={(e) => setDescription(e.target.value)} placeholder="Tâche effectuée" />
          <Select label="Projet (optionnel)" value={projectId} onChange={(e) => setProjectId(e.target.value)} options={[
            { value: '', label: 'Aucun' },
            ...projects.map(p => ({ value: p.id, label: p.name })),
          ]} />
          <div className="flex justify-end gap-3 pt-4 border-t border-[var(--color-border)]">
            <Button type="button" variant="secondary" onClick={onClose}>Annuler</Button>
            <Button type="submit" disabled={saving || !employeeId}>{saving ? '...' : 'Créer'}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
