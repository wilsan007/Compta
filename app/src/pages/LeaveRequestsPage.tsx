import { useEffect, useState, useCallback } from 'react'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { formatDate } from '@/lib/utils'
import { getLeaveRequests, createLeaveRequest, updateLeaveRequest, deleteLeaveRequest, getEmployees } from '@/lib/queries'
import { CalendarDays, Plus, Trash2, X, Check, XCircle } from 'lucide-react'
import type { Employee } from '@/types'
import { useToast } from '@/lib/toast'

const typeLabels: Record<string, string> = { annual: 'Congé payé', sick: 'Maladie', maternity: 'Maternité', paternity: 'Paternité', unpaid: 'Sans solde', other: 'Autre' }
const statusLabels: Record<string, string> = { pending: 'En attente', approved: 'Approuvé', rejected: 'Refusé', cancelled: 'Annulé' }
const statusBadge: Record<string, 'neutral' | 'success' | 'warning' | 'danger'> = { pending: 'warning', approved: 'success', rejected: 'danger', cancelled: 'neutral' }

export function LeaveRequestsPage() {
  const { toast } = useToast()
const [requests, setRequests] = useState<any[]>([])
  const [employees, setEmployees] = useState<Employee[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [statusFilter, setStatusFilter] = useState('')

  const loadData = useCallback(async () => {
    try {
      const [reqs, emps] = await Promise.all([getLeaveRequests(statusFilter || undefined), getEmployees()])
      setRequests(reqs || [])
      setEmployees(emps || [])
    } catch (err) { console.error('Error:', err) }
    finally { setLoading(false) }
  }, [statusFilter])

  useEffect(() => { loadData() }, [loadData])

  async function handleApprove(id: string) {
  try { await updateLeaveRequest(id, { status: 'approved', approved_at: new Date().toISOString() } as any); await loadData() }
    catch (err: any) { toast('error', 'Erreur', err.message || 'échec') }
  }

  async function handleReject(id: string) {
    try { await updateLeaveRequest(id, { status: 'rejected' }); await loadData() }
    catch (err: any) { toast('error', 'Erreur', err.message || 'échec') }
  }

  async function handleDelete(id: string) {
    if (!window.confirm('Supprimer cette demande ?')) return
    try { await deleteLeaveRequest(id); await loadData() }
    catch (err: any) { toast('error', 'Erreur', err.message || 'échec') }
  }

  const pendingCount = requests.filter((r) => r.status === 'pending').length

  return (
    <div>
      <Breadcrumb items={[{ label: 'Paie & RH' }, { label: 'Congés' }]} />
      <PageHeader title="Demandes de congés" subtitle={`${requests.length} demande(s) — ${pendingCount} en attente`}
        action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> Nouvelle demande</Button>} />

      <div className="flex gap-3 mb-4 items-end">
        <div className="w-48">
          <Select label="Statut" value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)} options={[
            { value: '', label: 'Tous' }, { value: 'pending', label: 'En attente' }, { value: 'approved', label: 'Approuvé' },
            { value: 'rejected', label: 'Refusé' }, { value: 'cancelled', label: 'Annulé' },
          ]} />
        </div>
      </div>

      {loading ? <SkeletonTable rows={5} cols={6} /> : requests.length === 0 ? (
        <EmptyState icon={<CalendarDays className="w-8 h-8" />} title="Aucune demande" description="Créez votre première demande de congé."
          action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> Nouvelle demande</Button>} />
      ) : (
        <Card>
          <Table headers={['Employé', 'Type', 'Du', 'Au', 'Jours', 'Motif', 'Statut', 'Actions']}>
            {requests.map((r) => (
              <TableRow key={r.id}>
                <TableCell className="text-sm">{r.employees?.name || '—'}</TableCell>
                <TableCell className="text-xs">{typeLabels[r.leave_type] || r.leave_type}</TableCell>
                <TableCell className="text-xs">{formatDate(r.start_date)}</TableCell>
                <TableCell className="text-xs">{formatDate(r.end_date)}</TableCell>
                <TableCell className="font-mono text-xs">{Number(r.days)}</TableCell>
                <TableCell className="text-xs">{r.reason || '—'}</TableCell>
                <TableCell><Badge variant={statusBadge[r.status] || 'neutral'}>{statusLabels[r.status] || r.status}</Badge></TableCell>
                <TableCell>
                  <div className="flex gap-1">
                    {r.status === 'pending' && (
                      <>
                        <button onClick={() => handleApprove(r.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-success)]" title="Approuver"><Check className="w-4 h-4" /></button>
                        <button onClick={() => handleReject(r.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]" title="Refuser"><XCircle className="w-4 h-4" /></button>
                      </>
                    )}
                    <button onClick={() => handleDelete(r.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]"><Trash2 className="w-4 h-4" /></button>
                  </div>
                </TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}

      {showForm && <LeaveForm employees={employees} onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadData() }} />}
    </div>
  )
}

function LeaveForm({ employees, onClose, onSaved }: { employees: Employee[]; onClose: () => void; onSaved: () => void }) {
  const [employeeId, setEmployeeId] = useState('')
  const { toast } = useToast()
  const [leaveType, setLeaveType] = useState('annual')
  const [startDate, setStartDate] = useState(new Date().toISOString().split('T')[0])
  const [endDate, setEndDate] = useState(new Date().toISOString().split('T')[0])
  const [reason, setReason] = useState('')
  const [saving, setSaving] = useState(false)

  const days = Math.ceil((new Date(endDate).getTime() - new Date(startDate).getTime()) / (1000 * 60 * 60 * 24)) + 1

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      await createLeaveRequest({ employee_id: employeeId, leave_type: leaveType as any, start_date: startDate, end_date: endDate, days, status: 'pending', reason: reason || null } as any)
      onSaved()
    } catch (err: any) { toast('error', 'Erreur', err.message || 'échec') }
    finally { setSaving(false) }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl overflow-hidden" style={{ width: '100%', maxWidth: '32rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">Nouvelle demande de congé</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">Employé</label>
            <select className="input" value={employeeId} onChange={(e) => setEmployeeId(e.target.value)} required>
              <option value="">— Sélectionner —</option>
              {employees.map((emp) => <option key={emp.id} value={emp.id}>{emp.name}</option>)}
            </select>
          </div>
          <Select label="Type de congé" value={leaveType} onChange={(e) => setLeaveType(e.target.value)} options={[
            { value: 'annual', label: 'Congé payé' }, { value: 'sick', label: 'Maladie' }, { value: 'maternity', label: 'Maternité' },
            { value: 'paternity', label: 'Paternité' }, { value: 'unpaid', label: 'Sans solde' }, { value: 'other', label: 'Autre' },
          ]} />
          <div className="grid grid-cols-2 gap-4">
            <Input label="Du" type="date" required value={startDate} onChange={(e) => setStartDate(e.target.value)} />
            <Input label="Au" type="date" required value={endDate} onChange={(e) => setEndDate(e.target.value)} />
          </div>
          <div className="text-sm text-[var(--color-text-secondary)]">Durée: <span className="font-bold">{days > 0 ? days : 0} jour(s)</span></div>
          <Input label="Motif" value={reason} onChange={(e) => setReason(e.target.value)} />
          <div className="flex justify-end gap-3 pt-2">
            <Button variant="secondary" onClick={onClose}>Annuler</Button>
            <Button type="submit" disabled={saving}>{saving ? '...' : 'Créer'}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
