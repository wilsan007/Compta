import { Fragment, useEffect, useState } from 'react'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Input } from '@/components/ui'
import { getJournalEntries, createJournalEntry, deleteJournalEntry, getChartAccounts } from '@/lib/queries'
import { formatCurrency, formatDate } from '@/lib/utils'
import { BookOpen, Plus, Trash2, X, ChevronDown, ChevronRight } from 'lucide-react'
import type { JournalEntry, ChartAccount } from '@/types'
import { useToast } from '@/lib/toast'

const statusLabels: Record<string, string> = {
  draft: 'Brouillon',
  posted: 'Validé',
}

const statusBadge: Record<string, 'warning' | 'success'> = {
  draft: 'warning',
  posted: 'success',
}

export function JournalEntriesPage() {
  const { toast } = useToast()
const [entries, setEntries] = useState<JournalEntry[]>([])
  const [accounts, setAccounts] = useState<ChartAccount[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [expanded, setExpanded] = useState<Set<string>>(new Set())

  useEffect(() => {
    loadData()
  }, [])

  async function loadData() {
    try {
      const [je, accs] = await Promise.all([
        getJournalEntries(),
        getChartAccounts(),
      ])
      setEntries(je || [])
      setAccounts(accs || [])
    } catch (err) {
      console.error('Error loading journal entries:', err)
    } finally {
      setLoading(false)
    }
  }

  function toggleExpand(id: string) {
  setExpanded((prev) => {
      const next = new Set(prev)
      if (next.has(id)) next.delete(id)
      else next.add(id)
      return next
    })
  }

  async function handleDelete(id: string) {
    if (!window.confirm('Supprimer cette écriture ?')) return
    try {
      await deleteJournalEntry(id)
      await loadData()
    } catch (err) {
      toast('error', 'Erreur', 'Erreur lors de la suppression')
    }
  }

  const totalDebit = entries.reduce((s, e) => s + Number(e.total_debit), 0)
  const totalCredit = entries.reduce((s, e) => s + Number(e.total_credit), 0)

  return (
    <div>
      <Breadcrumb items={[{ label: 'Comptabilité' }, { label: 'Journaux' }]} />
      <PageHeader
        title="Saisie & Journaux"
        subtitle={`${entries.length} écriture(s) — Total débit: ${formatCurrency(totalDebit)} | Total crédit: ${formatCurrency(totalCredit)}`}
        action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> Nouvelle écriture</Button>}
      />

      {loading ? (
        <SkeletonTable rows={6} cols={6} />
      ) : entries.length === 0 ? (
        <EmptyState
          icon={<BookOpen className="w-8 h-8" />}
          title="Aucune écriture"
          description="Saisissez votre première écriture comptable."
          action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> Nouvelle écriture</Button>}
        />
      ) : (
        <Card>
          <Table headers={['', 'Numéro', 'Date', 'Description', 'Statut', 'Débit', 'Crédit', 'Actions']}>
            {entries.map((entry) => (
              <Fragment key={entry.id}>
                <TableRow onClick={() => toggleExpand(entry.id)}>
                  <TableCell className="w-8">
                    {entry.journal_lines && entry.journal_lines.length > 0
                      ? (expanded.has(entry.id) ? <ChevronDown className="w-4 h-4" /> : <ChevronRight className="w-4 h-4" />)
                      : <span className="w-4 inline-block" />}
                  </TableCell>
                  <TableCell className="font-mono font-semibold">{entry.number}</TableCell>
                  <TableCell>{formatDate(entry.date)}</TableCell>
                  <TableCell className="max-w-xs truncate">{entry.description}</TableCell>
                  <TableCell><Badge variant={statusBadge[entry.status]}>{statusLabels[entry.status]}</Badge></TableCell>
                  <TableCell className="font-mono text-right">{formatCurrency(Number(entry.total_debit))}</TableCell>
                  <TableCell className="font-mono text-right">{formatCurrency(Number(entry.total_credit))}</TableCell>
                  <TableCell>
                    <button onClick={(e) => { e.stopPropagation(); handleDelete(entry.id) }} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]">
                      <Trash2 className="w-4 h-4" />
                    </button>
                  </TableCell>
                </TableRow>
                {expanded.has(entry.id) && entry.journal_lines && entry.journal_lines.map((line) => (
                  <tr key={line.id} className="bg-[var(--color-neutral-50)]">
                    <TableCell />
                    <TableCell className="font-mono text-xs text-[var(--color-text-secondary)]">{line.account_code}</TableCell>
                    <TableCell colSpan={2} className="text-xs text-[var(--color-text-secondary)]">
                      {line.account_name} — {line.description || ''}
                    </TableCell>
                    <TableCell />
                    <TableCell className="font-mono text-xs text-right">{Number(line.debit) > 0 ? formatCurrency(Number(line.debit)) : ''}</TableCell>
                    <TableCell className="font-mono text-xs text-right">{Number(line.credit) > 0 ? formatCurrency(Number(line.credit)) : ''}</TableCell>
                    <TableCell />
                  </tr>
                ))}
              </Fragment>
            ))}
          </Table>
        </Card>
      )}

      {showForm && (
        <JournalForm
          accounts={accounts}
          onClose={() => setShowForm(false)}
          onSaved={() => { setShowForm(false); loadData() }}
        />
      )}
    </div>
  )
}

interface LineDraft {
  account_code: string
  account_name: string
  debit: string
  credit: string
  description: string
}

function JournalForm({ accounts, onClose, onSaved }: { accounts: ChartAccount[]; onClose: () => void; onSaved: () => void }) {
  const [number, setNumber] = useState(`JE-${new Date().getFullYear()}-${String(Date.now()).slice(-4)}`)
  const { toast } = useToast()
  const [date, setDate] = useState(new Date().toISOString().slice(0, 10))
  const [description, setDescription] = useState('')
  const [reference, setReference] = useState('')
  const [lines, setLines] = useState<LineDraft[]>([
    { account_code: '', account_name: '', debit: '', credit: '', description: '' },
    { account_code: '', account_name: '', debit: '', credit: '', description: '' },
  ])
  const [saving, setSaving] = useState(false)

  function addLine() {
    setLines([...lines, { account_code: '', account_name: '', debit: '', credit: '', description: '' }])
  }

  function removeLine(idx: number) {
    setLines(lines.filter((_, i) => i !== idx))
  }

  function updateLine(idx: number, field: keyof LineDraft, value: string) {
    setLines(lines.map((l, i) => {
      if (i !== idx) return l
      const updated = { ...l, [field]: value }
      if (field === 'account_code') {
        const acc = accounts.find((a) => a.code === value)
        updated.account_name = acc?.name || ''
      }
      return updated
    }))
  }

  const totalDebit = lines.reduce((s, l) => s + (Number(l.debit) || 0), 0)
  const totalCredit = lines.reduce((s, l) => s + (Number(l.credit) || 0), 0)
  const isBalanced = Math.abs(totalDebit - totalCredit) < 0.01 && totalDebit > 0

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!isBalanced) {
      toast('info', 'Information', 'Les écritures ne sont pas équilibrées. Débit et crédit doivent être égaux.')
      return
    }
    setSaving(true)
    try {
      const linesData = lines
        .filter((l) => l.account_code && (Number(l.debit) > 0 || Number(l.credit) > 0))
        .map((l) => ({
          account_code: l.account_code,
          account_name: l.account_name,
          debit: Number(l.debit) || 0,
          credit: Number(l.credit) || 0,
          description: l.description || null,
        }))
      await createJournalEntry({
        number,
        date,
        description,
        reference: reference || null,
        status: 'draft',
        total_debit: totalDebit,
        total_credit: totalCredit,
        lines: linesData,
      } as any)
      onSaved()
    } catch (err: any) {
      toast('error', 'Erreur', err.message || 'échec')
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4 overflow-y-auto">
      <div className="card shadow-2xl overflow-hidden my-8" style={{ width: '100%', maxWidth: '48rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">Nouvelle écriture comptable</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div className="grid grid-cols-3 gap-4">
            <Input label="Numéro" required value={number} onChange={(e) => setNumber(e.target.value)} />
            <Input label="Date" type="date" required value={date} onChange={(e) => setDate(e.target.value)} />
            <Input label="Référence" value={reference} onChange={(e) => setReference(e.target.value)} placeholder="Optionnel" />
          </div>
          <Input label="Description" required value={description} onChange={(e) => setDescription(e.target.value)} placeholder="Objet de l'écriture" />

          <div className="border border-[var(--color-border)] rounded-lg overflow-hidden">
            <table className="app-table min-w-[760px]">
              <thead>
                <tr className="border-b border-[var(--color-border)] bg-[var(--color-neutral-50)]">
                  <th className="text-left text-xs font-semibold text-[var(--color-text-secondary)] uppercase px-3 py-2">Compte</th>
                  <th className="text-left text-xs font-semibold text-[var(--color-text-secondary)] uppercase px-3 py-2">Libellé ligne</th>
                  <th className="text-right text-xs font-semibold text-[var(--color-text-secondary)] uppercase px-3 py-2 w-32">Débit</th>
                  <th className="text-right text-xs font-semibold text-[var(--color-text-secondary)] uppercase px-3 py-2 w-32">Crédit</th>
                  <th className="w-10" />
                </tr>
              </thead>
              <tbody className="divide-y divide-[var(--color-border)]">
                {lines.map((line, idx) => (
                  <tr key={idx}>
                    <td className="px-3 py-2">
                      <select
                        className="input text-sm py-1"
                        value={line.account_code}
                        onChange={(e) => updateLine(idx, 'account_code', e.target.value)}
                      >
                        <option value="">— Sélectionner —</option>
                        {accounts.map((a) => (
                          <option key={a.id} value={a.code}>{a.code} — {a.name}</option>
                        ))}
                      </select>
                    </td>
                    <td className="px-3 py-2">
                      <input
                        className="input text-sm py-1"
                        value={line.description}
                        onChange={(e) => updateLine(idx, 'description', e.target.value)}
                        placeholder="Libellé"
                      />
                    </td>
                    <td className="px-3 py-2">
                      <input
                        type="number"
                        step="0.01"
                        className="input text-sm py-1 text-right font-mono"
                        value={line.debit}
                        onChange={(e) => updateLine(idx, 'debit', e.target.value)}
                      />
                    </td>
                    <td className="px-3 py-2">
                      <input
                        type="number"
                        step="0.01"
                        className="input text-sm py-1 text-right font-mono"
                        value={line.credit}
                        onChange={(e) => updateLine(idx, 'credit', e.target.value)}
                      />
                    </td>
                    <td className="px-2 py-2">
                      {lines.length > 2 && (
                        <button type="button" onClick={() => removeLine(idx)} className="p-1 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]">
                          <X className="w-4 h-4" />
                        </button>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
              <tfoot>
                <tr className="border-t-2 border-[var(--color-border)] bg-[var(--color-neutral-50)]">
                  <td colSpan={2} className="px-3 py-2">
                    <button type="button" onClick={addLine} className="text-sm text-[var(--color-primary)] hover:underline flex items-center gap-1">
                      <Plus className="w-3 h-3" /> Ajouter une ligne
                    </button>
                  </td>
                  <td className="px-3 py-2 text-right font-mono font-semibold text-sm">{formatCurrency(totalDebit)}</td>
                  <td className="px-3 py-2 text-right font-mono font-semibold text-sm">{formatCurrency(totalCredit)}</td>
                  <td />
                </tr>
                <tr className="bg-[var(--color-neutral-50)]">
                  <td colSpan={2} className="px-3 py-2 text-sm font-medium">
                    {isBalanced ? (
                      <span className="text-[var(--color-success)]">✓ Écriture équilibrée</span>
                    ) : (
                      <span className="text-[var(--color-danger)]">Δ {formatCurrency(Math.abs(totalDebit - totalCredit))}</span>
                    )}
                  </td>
                  <td colSpan={3} className="px-3 py-2 text-right text-sm text-[var(--color-text-secondary)]">
                    Différence: {formatCurrency(totalDebit - totalCredit)}
                  </td>
                </tr>
              </tfoot>
            </table>
          </div>

          <div className="flex justify-end gap-3 pt-2">
            <Button variant="secondary" onClick={onClose}>Annuler</Button>
            <Button type="submit" disabled={saving || !isBalanced}>{saving ? 'Enregistrement...' : 'Enregistrer l\'écriture'}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
