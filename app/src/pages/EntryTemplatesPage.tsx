import { useEffect, useState } from 'react'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { getEntryTemplates, createEntryTemplate, updateEntryTemplate, deleteEntryTemplate, getJournals } from '@/lib/queries'
import { LayoutTemplate, Plus, Pencil, Trash2, X, Search, Star } from 'lucide-react'
import type { EntryTemplate, Journal } from '@/types'
import { useToast } from '@/lib/toast'

export function EntryTemplatesPage() {
  const { toast } = useToast()
const [templates, setTemplates] = useState<EntryTemplate[]>([])
  const [journals, setJournals] = useState<Journal[]>([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [showForm, setShowForm] = useState(false)
  const [editing, setEditing] = useState<EntryTemplate | null>(null)

  useEffect(() => {
    loadData()
  }, [])

  async function loadData() {
    try {
      const [t, j] = await Promise.all([
        getEntryTemplates(),
        getJournals().catch(() => []),
      ])
      setTemplates(t || [])
      setJournals(j || [])
    } catch (err) {
      console.error('Error loading templates:', err)
    } finally {
      setLoading(false)
    }
  }

  const filtered = templates.filter((t) => {
    return !search ||
      t.name.toLowerCase().includes(search.toLowerCase()) ||
      (t.description || '').toLowerCase().includes(search.toLowerCase())
  })

  function getJournalName(code: string | null) {
  if (!code) return '—'
    const j = journals.find((x) => x.code === code)
    return j ? `${j.code} — ${j.name}` : code
  }

  function openCreate() {
    setEditing(null)
    setShowForm(true)
  }

  function openEdit(t: EntryTemplate) {
    setEditing(t)
    setShowForm(true)
  }

  async function handleDelete(id: string) {
    if (!window.confirm('Supprimer ce modèle de saisie ?')) return
    try {
      await deleteEntryTemplate(id)
      await loadData()
    } catch (err) {
      toast('error', 'Erreur', 'Erreur lors de la suppression')
    }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: 'Comptabilité' }, { label: 'Structure' }, { label: 'Modèles de saisie' }]} />
      <PageHeader
        title="Modèles de saisie"
        subtitle={`${templates.length} modèle(s) — pré-remplissage automatique des écritures`}
        action={<Button onClick={openCreate}><Plus className="w-4 h-4" /> Nouveau modèle</Button>}
      />

      <div className="flex gap-3 mb-4">
        <div className="flex-1 relative">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-[var(--color-text-secondary)]" />
          <input
            className="input pl-10"
            placeholder="Rechercher un modèle..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
        </div>
      </div>

      {loading ? (
        <SkeletonTable rows={5} cols={5} />
      ) : filtered.length === 0 ? (
        <EmptyState
          icon={<LayoutTemplate className="w-8 h-8" />}
          title="Aucun modèle trouvé"
          description="Créez des modèles pour pré-remplir automatiquement vos saisies d'écritures."
          action={<Button onClick={openCreate}><Plus className="w-4 h-4" /> Nouveau modèle</Button>}
        />
      ) : (
        <Card>
          <Table headers={['Nom', 'Journal', 'Description', 'Lignes', 'Défaut', 'Statut', 'Actions']}>
            {filtered.map((t) => (
              <TableRow key={t.id}>
                <TableCell className="font-medium">{t.name}</TableCell>
                <TableCell className="text-xs">{getJournalName(t.journal_code)}</TableCell>
                <TableCell className="text-xs text-[var(--color-text-secondary)]">{t.description || '—'}</TableCell>
                <TableCell className="font-mono">{t.template_lines?.length || 0}</TableCell>
                <TableCell>{t.is_default ? <Badge variant="primary"><Star className="w-3 h-3 inline mr-1" />Défaut</Badge> : '—'}</TableCell>
                <TableCell>{t.active ? <Badge variant="success">Actif</Badge> : <Badge variant="neutral">Inactif</Badge>}</TableCell>
                <TableCell>
                  <div className="flex gap-2">
                    <button onClick={() => openEdit(t)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-text-secondary)]">
                      <Pencil className="w-4 h-4" />
                    </button>
                    <button onClick={() => handleDelete(t.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]">
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
        <TemplateForm
          template={editing}
          journals={journals}
          onClose={() => setShowForm(false)}
          onSaved={() => { setShowForm(false); loadData() }}
        />
      )}
    </div>
  )
}

interface TemplateLineData {
  account_general: string
  account_tiers: string
  label: string
  debit_pct: number
  credit_pct: number
}

function TemplateForm({ template, journals, onClose, onSaved }: {
  template: EntryTemplate | null
  journals: Journal[]
  onClose: () => void
  onSaved: () => void
}) {
  const [name, setName] = useState(template?.name || '')
  const { toast } = useToast()
  const [journalCode, setJournalCode] = useState(template?.journal_code || '')
  const [description, setDescription] = useState(template?.description || '')
  const [isDefault, setIsDefault] = useState(template?.is_default || false)
  const [active, setActive] = useState(template?.active ?? true)
  const [lines, setLines] = useState<TemplateLineData[]>(
    (template?.template_lines as TemplateLineData[]) || [{ account_general: '', account_tiers: '', label: '', debit_pct: 0, credit_pct: 0 }]
  )
  const [saving, setSaving] = useState(false)

  function addLine() {
    setLines([...lines, { account_general: '', account_tiers: '', label: '', debit_pct: 0, credit_pct: 0 }])
  }

  function removeLine(idx: number) {
    setLines(lines.filter((_, i) => i !== idx))
  }

  function updateLine(idx: number, field: keyof TemplateLineData, value: string | number) {
    setLines(lines.map((l, i) => i === idx ? { ...l, [field]: value } : l))
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      const data = {
        name,
        journal_code: journalCode || null,
        description: description || null,
        template_lines: lines.filter((l) => l.account_general || l.label),
        is_default: isDefault,
        active,
      }
      if (template) {
        await updateEntryTemplate(template.id, data)
      } else {
        await createEntryTemplate(data as any)
      }
      onSaved()
    } catch (err: any) {
      toast('error', 'Erreur', err.message || 'échec')
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl overflow-hidden" style={{ width: '100%', maxWidth: '42rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{template ? 'Modifier le modèle' : 'Nouveau modèle de saisie'}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4 max-h-[70vh] overflow-y-auto">
          <div className="grid grid-cols-2 gap-4">
            <Input label="Nom" required value={name} onChange={(e) => setName(e.target.value)} placeholder="Ex: Achat marchandises TTC" />
            <Select label="Journal associé" value={journalCode} onChange={(e) => setJournalCode(e.target.value)} options={[
              { value: '', label: '— Aucun —' },
              ...journals.map((j) => ({ value: j.code, label: `${j.code} — ${j.name}` })),
            ]} />
          </div>
          <Input label="Description" value={description} onChange={(e) => setDescription(e.target.value)} />

          <div>
            <div className="flex items-center justify-between mb-2">
              <label className="text-sm font-medium text-[var(--color-text-secondary)]">Lignes du modèle</label>
              <Button variant="ghost" size="sm" onClick={addLine}><Plus className="w-3 h-3" /> Ajouter une ligne</Button>
            </div>
            <div className="space-y-2">
              {lines.map((line, idx) => (
                <div key={idx} className="grid grid-cols-12 gap-2 items-end p-2 bg-[var(--color-neutral-50)] rounded-lg">
                  <div className="col-span-3">
                    <input className="input text-xs" placeholder="Cpte général" value={line.account_general} onChange={(e) => updateLine(idx, 'account_general', e.target.value)} />
                  </div>
                  <div className="col-span-3">
                    <input className="input text-xs" placeholder="Cpte tiers" value={line.account_tiers} onChange={(e) => updateLine(idx, 'account_tiers', e.target.value)} />
                  </div>
                  <div className="col-span-3">
                    <input className="input text-xs" placeholder="Libellé" value={line.label} onChange={(e) => updateLine(idx, 'label', e.target.value)} />
                  </div>
                  <div className="col-span-2">
                    <div className="grid grid-cols-2 gap-1">
                      <input className="input text-xs" type="number" placeholder="D%" value={line.debit_pct} onChange={(e) => updateLine(idx, 'debit_pct', Number(e.target.value))} />
                      <input className="input text-xs" type="number" placeholder="C%" value={line.credit_pct} onChange={(e) => updateLine(idx, 'credit_pct', Number(e.target.value))} />
                    </div>
                  </div>
                  <div className="col-span-1">
                    <button type="button" onClick={() => removeLine(idx)} className="p-1.5 rounded text-[var(--color-danger)] hover:bg-[var(--color-neutral-100)]">
                      <Trash2 className="w-4 h-4" />
                    </button>
                  </div>
                </div>
              ))}
            </div>
          </div>

          <div className="flex items-center gap-4">
            <label className="flex items-center gap-2 text-sm">
              <input type="checkbox" checked={isDefault} onChange={(e) => setIsDefault(e.target.checked)} />
              Modèle par défaut
            </label>
            <label className="flex items-center gap-2 text-sm">
              <input type="checkbox" checked={active} onChange={(e) => setActive(e.target.checked)} />
              Actif
            </label>
          </div>

          <div className="flex justify-end gap-3 pt-2">
            <Button variant="secondary" onClick={onClose}>Annuler</Button>
            <Button type="submit" disabled={saving}>{saving ? 'Enregistrement...' : 'Enregistrer'}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
