import { useEffect, useState, useCallback } from 'react'
import { Card, PageHeader, Button, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { getProjects, createProject, updateProject, deleteProject, getCustomers } from '@/lib/queries'
import { formatCurrency } from '@/lib/utils'
import { FolderKanban, Plus, Trash2, X } from 'lucide-react'
import type { Project, Customer } from '@/types'
import { useToast } from '@/lib/toast'

const statusLabels: Record<string, string> = { active: 'Actif', completed: 'Terminé', on_hold: 'En pause', cancelled: 'Annulé' }

export function ProjectsPage() {
  const { toast } = useToast()
const [projects, setProjects] = useState<Project[]>([])
  const [customers, setCustomers] = useState<Customer[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const [p, c] = await Promise.all([getProjects(), getCustomers()])
      setProjects(p)
      setCustomers(c)
    } catch (err) {
      console.error('Failed to load projects:', err)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  async function handleDelete(id: string) {
  if (!window.confirm('Supprimer ce projet ?')) return
    try {
      await deleteProject(id)
      await loadData()
    } catch (err: any) {
      toast('error', 'Erreur', err.message || 'échec')
    }
  }

  async function handleStatusChange(id: string, status: string) {
    try {
      await updateProject(id, { status: status as any })
      await loadData()
    } catch (err: any) {
      toast('error', 'Erreur', err.message || 'échec')
    }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: 'Comptabilité' }, { label: 'Projets' }]} />
      <PageHeader
        title="Projets"
        subtitle="Suivi de projets et rentabilité"
        action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> Nouveau projet</Button>}
      />

      {loading ? (
        <SkeletonTable rows={4} cols={6} />
      ) : projects.length === 0 ? (
        <EmptyState
          icon={<FolderKanban className="w-8 h-8" />}
          title="Aucun projet"
          description="Créez votre premier projet."
          action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> Nouveau projet</Button>}
        />
      ) : (
        <Card>
          <Table headers={['Nom', 'Client', 'Budget', 'Coût réel', 'Rentabilité', 'Statut', 'Actions']}>
            {projects.map((p) => {
              const customerName = customers.find(c => c.id === p.customer_id)?.name || '—'
              const profit = Number(p.budget) - Number(p.actual_cost)
              const margin = Number(p.budget) > 0 ? (profit / Number(p.budget)) * 100 : 0
              return (
                <TableRow key={p.id}>
                  <TableCell className="font-medium">{p.name}</TableCell>
                  <TableCell className="text-sm">{customerName}</TableCell>
                  <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(p.budget))}</TableCell>
                  <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(p.actual_cost))}</TableCell>
                  <TableCell className="text-right">
                    <span className={`font-mono text-xs font-bold ${profit >= 0 ? 'text-[var(--color-success)]' : 'text-[var(--color-danger)]'}`}>
                      {formatCurrency(profit)} ({margin.toFixed(1)}%)
                    </span>
                  </TableCell>
                  <TableCell>
                    <select
                      value={p.status}
                      onChange={(e) => handleStatusChange(p.id, e.target.value)}
                      className="text-xs border border-[var(--color-border)] rounded px-2 py-1 bg-[var(--color-surface)]"
                    >
                      {Object.entries(statusLabels).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
                    </select>
                  </TableCell>
                  <TableCell>
                    <button onClick={() => handleDelete(p.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]">
                      <Trash2 className="w-4 h-4" />
                    </button>
                  </TableCell>
                </TableRow>
              )
            })}
          </Table>
        </Card>
      )}

      {showForm && (
        <ProjectForm customers={customers} onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadData() }} />
      )}
    </div>
  )
}

function ProjectForm({ customers, onClose, onSaved }: { customers: Customer[]; onClose: () => void; onSaved: () => void }) {
  const [name, setName] = useState('')
  const { toast } = useToast()
  const [description, setDescription] = useState('')
  const [customerId, setCustomerId] = useState('')
  const [budget, setBudget] = useState(0)
  const [startDate, setStartDate] = useState(new Date().toISOString().split('T')[0])
  const [endDate, setEndDate] = useState('')
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      await createProject({
        name, description, customer_id: customerId || null,
        status: 'active', budget, actual_cost: 0,
        start_date: startDate, end_date: endDate || null,
      } as any)
      onSaved()
    } catch (err: any) {
      toast('error', 'Erreur', err.message || 'échec')
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '36rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">Nouveau projet</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <Input label="Nom" required value={name} onChange={(e) => setName(e.target.value)} />
          <Input label="Description" value={description} onChange={(e) => setDescription(e.target.value)} />
          <Select label="Client" value={customerId} onChange={(e) => setCustomerId(e.target.value)} options={[
            { value: '', label: 'Aucun' },
            ...customers.map(c => ({ value: c.id, label: c.name })),
          ]} />
          <div className="grid grid-cols-3 gap-4">
            <Input label="Budget" type="number" step="0.01" value={budget} onChange={(e) => setBudget(Number(e.target.value))} />
            <Input label="Date début" type="date" value={startDate} onChange={(e) => setStartDate(e.target.value)} />
            <Input label="Date fin" type="date" value={endDate} onChange={(e) => setEndDate(e.target.value)} />
          </div>
          <div className="flex justify-end gap-3 pt-4 border-t border-[var(--color-border)]">
            <Button type="button" variant="secondary" onClick={onClose}>Annuler</Button>
            <Button type="submit" disabled={saving}>{saving ? '...' : 'Créer'}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
