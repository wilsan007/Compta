import { useEffect, useState, useCallback } from 'react'
import { Card, PageHeader, Button, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { formatCurrency, formatDate } from '@/lib/utils'
import { getContracts, createContract, updateContract, deleteContract, getEmployees } from '@/lib/queries'
import { FileSignature, Plus, Trash2, X } from 'lucide-react'
import type { Employee } from '@/types'
import { useToast } from '@/lib/toast'

const typeLabels: Record<string, string> = { cdi: 'CDI', cdd: 'CDD', apprentissage: 'Apprentissage', stage: 'Stage', interim: 'Intérim', freelance: 'Freelance' }
const statusLabels: Record<string, string> = { active: 'Actif', ended: 'Terminé', suspended: 'Suspendu', terminated: 'Rompu' }

export function ContractsPage() {
  const { toast } = useToast()
const [contracts, setContracts] = useState<any[]>([])
  const [employees, setEmployees] = useState<Employee[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [typeFilter, setTypeFilter] = useState('')

  const loadData = useCallback(async () => {
    try {
      const [cs, emps] = await Promise.all([getContracts(), getEmployees()])
      setContracts(cs || [])
      setEmployees(emps || [])
    } catch (err) { console.error('Error:', err) }
    finally { setLoading(false) }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  async function handleStatusChange(id: string, status: string) {
  try { await updateContract(id, { status: status as any }); await loadData() }
    catch (err: any) { toast('error', 'Erreur', err.message || 'échec') }
  }

  async function handleDelete(id: string) {
    if (!window.confirm('Supprimer ce contrat ?')) return
    try { await deleteContract(id); await loadData() }
    catch (err: any) { toast('error', 'Erreur', err.message || 'échec') }
  }

  const filtered = typeFilter ? contracts.filter((c) => c.contract_type === typeFilter) : contracts

  return (
    <div>
      <Breadcrumb items={[{ label: 'Paie & RH' }, { label: 'Contrats' }]} />
      <PageHeader title="Contrats de travail" subtitle={`${contracts.length} contrat(s)`}
        action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> Nouveau contrat</Button>} />

      <div className="flex gap-3 mb-4 items-end">
        <div className="w-48">
          <Select label="Type" value={typeFilter} onChange={(e) => setTypeFilter(e.target.value)} options={[
            { value: '', label: 'Tous' }, ...Object.entries(typeLabels).map(([k, v]) => ({ value: k, label: v })),
          ]} />
        </div>
      </div>

      {loading ? <SkeletonTable rows={5} cols={7} /> : filtered.length === 0 ? (
        <EmptyState icon={<FileSignature className="w-8 h-8" />} title="Aucun contrat" description="Créez votre premier contrat."
          action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> Nouveau contrat</Button>} />
      ) : (
        <Card>
          <Table headers={['N°', 'Employé', 'Type', 'Début', 'Fin', 'Salaire', 'Heures/sem', 'Statut', 'Actions']}>
            {filtered.map((c) => (
              <TableRow key={c.id}>
                <TableCell className="font-mono text-xs">{c.number}</TableCell>
                <TableCell className="text-sm">{c.employees?.name || '—'}</TableCell>
                <TableCell className="text-xs">{typeLabels[c.contract_type] || c.contract_type}</TableCell>
                <TableCell className="text-xs">{formatDate(c.start_date)}</TableCell>
                <TableCell className="text-xs">{c.end_date ? formatDate(c.end_date) : '—'}</TableCell>
                <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(c.monthly_salary))}</TableCell>
                <TableCell className="font-mono text-xs">{Number(c.weekly_hours)}h</TableCell>
                <TableCell>
                  <select value={c.status} onChange={(e) => handleStatusChange(c.id, e.target.value)}
                    className="text-xs border border-[var(--color-border)] rounded px-2 py-1 bg-[var(--color-surface)]">
                    {Object.entries(statusLabels).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
                  </select>
                </TableCell>
                <TableCell>
                  <button onClick={() => handleDelete(c.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]">
                    <Trash2 className="w-4 h-4" />
                  </button>
                </TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}

      {showForm && <ContractForm employees={employees} onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadData() }} />}
    </div>
  )
}

function ContractForm({ employees, onClose, onSaved }: { employees: Employee[]; onClose: () => void; onSaved: () => void }) {
  const [employeeId, setEmployeeId] = useState('')
  const { toast } = useToast()
  const [contractType, setContractType] = useState('cdi')
  const [startDate, setStartDate] = useState(new Date().toISOString().split('T')[0])
  const [endDate, setEndDate] = useState('')
  const [position, setPosition] = useState('')
  const [department, setDepartment] = useState('')
  const [monthlySalary, setMonthlySalary] = useState(0)
  const [weeklyHours, setWeeklyHours] = useState(35)
  const [trialPeriodDays, setTrialPeriodDays] = useState(0)
  const [notes, setNotes] = useState('')
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      const number = `CTR-${new Date().getFullYear()}-${String(Date.now()).slice(-4)}`
      await createContract({
        number, employee_id: employeeId, contract_type: contractType as any,
        start_date: startDate, end_date: endDate || null,
        position: position || null, department: department || null,
        monthly_salary: monthlySalary, hourly_rate: 0, weekly_hours: weeklyHours,
        trial_period_days: trialPeriodDays, status: 'active', notes: notes || null,
      } as any)
      onSaved()
    } catch (err: any) { toast('error', 'Erreur', err.message || 'échec') }
    finally { setSaving(false) }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl overflow-hidden" style={{ width: '100%', maxWidth: '36rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">Nouveau contrat</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">Employé</label>
            <select className="input" value={employeeId} onChange={(e) => { setEmployeeId(e.target.value); const emp = employees.find((em) => em.id === e.target.value); if (emp) { setPosition(emp.position); setDepartment(emp.department); setMonthlySalary(Number(emp.salary)) } }} required>
              <option value="">— Sélectionner —</option>
              {employees.map((emp) => <option key={emp.id} value={emp.id}>{emp.name}</option>)}
            </select>
          </div>
          <div className="grid grid-cols-2 gap-4">
            <Select label="Type de contrat" value={contractType} onChange={(e) => setContractType(e.target.value)} options={[
              { value: 'cdi', label: 'CDI' }, { value: 'cdd', label: 'CDD' }, { value: 'apprentissage', label: 'Apprentissage' },
              { value: 'stage', label: 'Stage' }, { value: 'interim', label: 'Intérim' }, { value: 'freelance', label: 'Freelance' },
            ]} />
            <Input label="Période d'essai (jours)" type="number" value={trialPeriodDays} onChange={(e) => setTrialPeriodDays(Number(e.target.value))} />
          </div>
          <div className="grid grid-cols-2 gap-4">
            <Input label="Date de début" type="date" required value={startDate} onChange={(e) => setStartDate(e.target.value)} />
            <Input label="Date de fin" type="date" value={endDate} onChange={(e) => setEndDate(e.target.value)} />
          </div>
          <div className="grid grid-cols-2 gap-4">
            <Input label="Poste" value={position} onChange={(e) => setPosition(e.target.value)} />
            <Input label="Département" value={department} onChange={(e) => setDepartment(e.target.value)} />
          </div>
          <div className="grid grid-cols-2 gap-4">
            <Input label="Salaire mensuel" type="number" step="0.01" value={monthlySalary} onChange={(e) => setMonthlySalary(Number(e.target.value))} />
            <Input label="Heures/semaine" type="number" step="0.1" value={weeklyHours} onChange={(e) => setWeeklyHours(Number(e.target.value))} />
          </div>
          <Input label="Notes" value={notes} onChange={(e) => setNotes(e.target.value)} />
          <div className="flex justify-end gap-3 pt-2">
            <Button variant="secondary" onClick={onClose}>Annuler</Button>
            <Button type="submit" disabled={saving}>{saving ? '...' : 'Créer'}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
