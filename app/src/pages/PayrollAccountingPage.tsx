import { useEffect, useState, useCallback } from 'react'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Input } from '@/components/ui'
import { formatCurrency, formatDate } from '@/lib/utils'
import { getPayrollAccountingEntries, createPayrollAccountingEntry, transferPayrollToAccounting, deletePayrollAccountingEntry, getPayRuns } from '@/lib/queries'
import { Calculator, Plus, Trash2, X, ArrowRightLeft, CheckCircle2 } from 'lucide-react'
import type { PayRun, PayrollAccountingEntry } from '@/types'
import { useToast } from '@/lib/toast'

const statusLabels: Record<string, string> = { draft: 'Brouillon', transferred: 'Transféré', cancelled: 'Annulé' }
const statusBadge: Record<string, 'neutral' | 'success' | 'warning' | 'danger'> = { draft: 'warning', transferred: 'success', cancelled: 'danger' }

export function PayrollAccountingPage() {
  const { toast } = useToast()
const [entries, setEntries] = useState<any[]>([])
  const [payRuns, setPayRuns] = useState<PayRun[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [transferring, setTransferring] = useState<string | null>(null)

  const loadData = useCallback(async () => {
    try {
      const [es, prs] = await Promise.all([getPayrollAccountingEntries(), getPayRuns()])
      setEntries(es || [])
      setPayRuns(prs || [])
    } catch (err) { console.error('Error:', err) }
    finally { setLoading(false) }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  async function handleTransfer(entry: PayrollAccountingEntry) {
  setTransferring(entry.id)
    try {
      await transferPayrollToAccounting(entry.id, entry)
      await loadData()
      toast('success', 'Succès', 'OD de paie transférée en comptabilité')
    } catch (err: any) { toast('error', 'Erreur', err.message || 'échec') }
    finally { setTransferring(null) }
  }

  async function handleDelete(id: string) {
    if (!window.confirm('Supprimer cette OD de paie ?')) return
    try { await deletePayrollAccountingEntry(id); await loadData() }
    catch (err: any) { toast('error', 'Erreur', err.message || 'échec') }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: 'Paie & RH' }, { label: 'OD de paie' }]} />
      <PageHeader title="OD de paie" subtitle={`${entries.length} écriture(s)`}
        action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> Nouvelle OD</Button>} />

      {loading ? <SkeletonTable rows={4} cols={6} /> : entries.length === 0 ? (
        <EmptyState icon={<Calculator className="w-8 h-8" />} title="Aucune OD de paie" description="Créez votre première écriture de paie."
          action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> Nouvelle OD</Button>} />
      ) : (
        <Card>
          <Table headers={['N°', 'Campagne', 'Période', 'Brut', 'Charges patronales', 'Net', 'Statut', 'Actions']}>
            {entries.map((e) => (
              <TableRow key={e.id}>
                <TableCell className="font-mono text-xs">{e.number}</TableCell>
                <TableCell className="text-xs">{e.pay_runs?.number || '—'}</TableCell>
                <TableCell className="text-xs">{formatDate(e.period_date)}</TableCell>
                <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(e.gross_total))}</TableCell>
                <TableCell className="font-mono text-xs text-[var(--color-danger)] text-right">{formatCurrency(Number(e.employer_contributions_total))}</TableCell>
                <TableCell className="font-mono text-xs font-bold text-right">{formatCurrency(Number(e.net_total))}</TableCell>
                <TableCell><Badge variant={statusBadge[e.status] || 'neutral'}>{statusLabels[e.status] || e.status}</Badge></TableCell>
                <TableCell>
                  <div className="flex gap-1">
                    {e.status === 'draft' && (
                      <button onClick={() => handleTransfer(e)} disabled={transferring === e.id}
                        className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-primary)]" title="Transférer en compta">
                        {transferring === e.id ? <CheckCircle2 className="w-4 h-4" /> : <ArrowRightLeft className="w-4 h-4" />}
                      </button>
                    )}
                    <button onClick={() => handleDelete(e.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]">
                      <Trash2 className="w-4 h-4" />
                    </button>
                  </div>
                </TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}

      {showForm && <ODForm payRuns={payRuns} onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadData() }} />}
    </div>
  )
}

function ODForm({ payRuns, onClose, onSaved }: { payRuns: PayRun[]; onClose: () => void; onSaved: () => void }) {
  const [payRunId, setPayRunId] = useState('')
  const { toast } = useToast()
  const [periodDate, setPeriodDate] = useState(new Date().toISOString().split('T')[0])
  const [saving, setSaving] = useState(false)

  const selectedRun = payRuns.find((r) => r.id === payRunId)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      const number = `OD-PAIE-${new Date().getFullYear()}-${String(Date.now()).slice(-4)}`
      await createPayrollAccountingEntry({
        number, pay_run_id: payRunId || null, period_date: periodDate,
        gross_total: Number(selectedRun?.gross_total) || 0,
        employer_contributions_total: (Number(selectedRun?.gross_total) || 0) * 0.42,
        employee_deductions_total: Number(selectedRun?.tax_total) || 0,
        net_total: Number(selectedRun?.net_total) || 0,
        journal_entry_id: null, status: 'draft',
      } as any)
      onSaved()
    } catch (err: any) { toast('error', 'Erreur', err.message || 'échec') }
    finally { setSaving(false) }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl overflow-hidden" style={{ width: '100%', maxWidth: '32rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">Nouvelle OD de paie</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">Campagne de paie</label>
            <select className="input" value={payRunId} onChange={(e) => setPayRunId(e.target.value)} required>
              <option value="">— Sélectionner —</option>
              {payRuns.map((r) => <option key={r.id} value={r.id}>{r.number} ({formatDate(r.period_start)} → {formatDate(r.period_end)})</option>)}
            </select>
          </div>
          <Input label="Date d'écriture" type="date" required value={periodDate} onChange={(e) => setPeriodDate(e.target.value)} />
          {selectedRun && (
            <div className="p-3 rounded-lg bg-[var(--color-neutral-50)] space-y-1 text-sm">
              <div className="flex justify-between"><span className="text-[var(--color-text-secondary)]">Brut total:</span><span className="font-mono font-bold">{formatCurrency(Number(selectedRun.gross_total))}</span></div>
              <div className="flex justify-between"><span className="text-[var(--color-text-secondary)]">Charges patronales (42%):</span><span className="font-mono text-[var(--color-danger)]">{formatCurrency(Number(selectedRun.gross_total) * 0.42)}</span></div>
              <div className="flex justify-between"><span className="text-[var(--color-text-secondary)]">Cotisations salariales:</span><span className="font-mono text-[var(--color-danger)]">{formatCurrency(Number(selectedRun.tax_total))}</span></div>
              <div className="flex justify-between border-t border-[var(--color-border)] pt-1"><span className="font-semibold">Net à payer:</span><span className="font-mono font-bold text-[var(--color-success)]">{formatCurrency(Number(selectedRun.net_total))}</span></div>
            </div>
          )}
          <div className="flex justify-end gap-3 pt-2">
            <Button variant="secondary" onClick={onClose}>Annuler</Button>
            <Button type="submit" disabled={saving}>{saving ? '...' : 'Créer'}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
