import { useEffect, useState } from 'react'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { getAnalyticSections, createAnalyticSection, updateAnalyticSection, deleteAnalyticSection } from '@/lib/queries'
import { Plus, Pencil, Trash2, X, PieChart } from 'lucide-react'
import type { AnalyticSection } from '@/types'
import { useToast } from '@/lib/toast'

const axisLabels: Record<string, string> = {
  cost: 'Coûts',
  revenue: 'Revenus',
  project: 'Projet',
  department: 'Département',
  other: 'Autre',
}

export function AnalyticSectionsPage() {
  const { toast } = useToast()
const [sections, setSections] = useState<AnalyticSection[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [editing, setEditing] = useState<AnalyticSection | null>(null)

  useEffect(() => { load() }, [])

  async function load() {
    try {
      const data = await getAnalyticSections()
      setSections(data || [])
    } catch (err) {
      console.error('Error loading analytic sections:', err)
    } finally {
      setLoading(false)
    }
  }

  function openCreate() { setEditing(null); setShowForm(true) }
  function openEdit(s: AnalyticSection) { setEditing(s); setShowForm(true) }

  async function handleDelete(id: string) {
  if (!window.confirm('Supprimer cette section ?')) return
    try { await deleteAnalyticSection(id); await load() }
    catch (err) { toast('error', 'Erreur', 'Erreur lors de la suppression') }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: 'Comptabilité' }, { label: 'Structure' }, { label: 'Sections analytiques' }]} />
      <PageHeader
        title="Sections analytiques"
        subtitle={`${sections.length} section(s)`}
        action={<Button onClick={openCreate}><Plus className="w-4 h-4" /> Nouvelle section</Button>}
      />

      {loading ? (
        <SkeletonTable rows={4} cols={5} />
      ) : sections.length === 0 ? (
        <EmptyState
          icon={<PieChart className="w-8 h-8" />}
          title="Aucune section"
          description="Créez votre première section analytique."
          action={<Button onClick={openCreate}><Plus className="w-4 h-4" /> Nouvelle section</Button>}
        />
      ) : (
        <Card>
          <Table headers={['Code', 'Libellé', 'Type', 'Active', 'Actions']}>
            {sections.map((s) => (
              <TableRow key={s.id}>
                <TableCell className="font-mono font-semibold">{s.code}</TableCell>
                <TableCell>{s.name}</TableCell>
                <TableCell><Badge variant="neutral">{axisLabels[s.axis || ''] || s.axis || '—'}</Badge></TableCell>
                <TableCell><Badge variant={s.active ? 'success' : 'danger'}>{s.active ? 'Oui' : 'Non'}</Badge></TableCell>
                <TableCell>
                  <div className="flex gap-2">
                    <button onClick={() => openEdit(s)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-text-secondary)]">
                      <Pencil className="w-4 h-4" />
                    </button>
                    <button onClick={() => handleDelete(s.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]">
                      <Trash2 className="w-4 h-4" />
                    </button>
                  </div>
                </TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}

      {showForm && (
        <SectionForm
          section={editing}
          onClose={() => setShowForm(false)}
          onSaved={() => { setShowForm(false); load() }}
        />
      )}
    </div>
  )
}

function SectionForm({ section, onClose, onSaved }: { section: AnalyticSection | null; onClose: () => void; onSaved: () => void }) {
  const [code, setCode] = useState(section?.code || '')
  const { toast } = useToast()
  const [name, setName] = useState(section?.name || '')
  const [axis, setAxis] = useState(section?.axis || 'cost')
  const [active, setActive] = useState(section?.active !== false)
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      const data = { code, name, axis, active, level: section?.level || 1 }
      if (section) await updateAnalyticSection(section.id, data)
      else await createAnalyticSection(data as any)
      onSaved()
    } catch (err: any) {
      toast('error', 'Erreur', err.message || 'échec')
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl overflow-hidden" style={{ width: '100%', maxWidth: '32rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{section ? 'Modifier la section' : 'Nouvelle section'}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div className="grid grid-cols-2 gap-4">
            <Input label="Code" required value={code} onChange={(e) => setCode(e.target.value)} placeholder="Ex: A01" />
            <Select label="Axe" value={axis} onChange={(e) => setAxis(e.target.value)} options={[
              { value: 'cost', label: 'Coûts' },
              { value: 'revenue', label: 'Revenus' },
              { value: 'project', label: 'Projet' },
              { value: 'department', label: 'Département' },
              { value: 'other', label: 'Autre' },
            ]} />
          </div>
          <Input label="Libellé" required value={name} onChange={(e) => setName(e.target.value)} placeholder="Ex: Direction commerciale" />
          <label className="flex items-center gap-2 text-sm">
            <input type="checkbox" checked={active} onChange={(e) => setActive(e.target.checked)} />
            Section active
          </label>
          <div className="flex justify-end gap-3 pt-2">
            <Button variant="secondary" onClick={onClose}>Annuler</Button>
            <Button type="submit" disabled={saving}>{saving ? '...' : 'Enregistrer'}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
