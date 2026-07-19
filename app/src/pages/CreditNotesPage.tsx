import { useEffect, useState, useCallback } from 'react'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { getCreditNotes, createCreditNote, updateCreditNote, deleteCreditNote, getCustomers, getInvoices } from '@/lib/queries'
import { formatCurrency, formatDate } from '@/lib/utils'
import { Receipt, Plus, Trash2, X, ChevronDown, ChevronRight, CheckCircle } from 'lucide-react'
import type { CreditNote, Customer, Invoice } from '@/types'
import { useToast } from '@/lib/toast'

const statusLabels: Record<string, string> = {
  draft: 'Brouillon',
  applied: 'Appliqué',
}

const statusBadge: Record<string, 'neutral' | 'success' | 'warning' | 'danger' | 'primary'> = {
  draft: 'warning',
  applied: 'success',
}

export function CreditNotesPage() {
  const { toast } = useToast()
const [creditNotes, setCreditNotes] = useState<CreditNote[]>([])
  const [customers, setCustomers] = useState<Customer[]>([])
  const [invoices, setInvoices] = useState<Invoice[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [expanded, setExpanded] = useState<Set<string>>(new Set())

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const [cn, c, inv] = await Promise.all([getCreditNotes(), getCustomers(), getInvoices()])
      setCreditNotes(cn)
      setCustomers(c)
      setInvoices(inv)
    } catch (err) {
      console.error('Failed to load credit notes:', err)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  function toggleExpand(id: string) {
  setExpanded(prev => {
      const next = new Set(prev)
      if (next.has(id)) next.delete(id)
      else next.add(id)
      return next
    })
  }

  async function handleDelete(id: string) {
    if (!window.confirm('Supprimer cet avoir ?')) return
    try {
      await deleteCreditNote(id)
      await loadData()
    } catch (err: any) {
      toast('error', 'Erreur', err.message || 'échec')
    }
  }

  async function handleApply(id: string) {
    try {
      await updateCreditNote(id, { status: 'applied' })
      await loadData()
    } catch (err: any) {
      toast('error', 'Erreur', err.message || 'échec')
    }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: 'Ventes' }, { label: 'Avoirs' }]} />
      <PageHeader
        title="Avoirs clients"
        subtitle="Gérez les notes de crédit clients"
        action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> Nouvel avoir</Button>}
      />

      {loading ? (
        <SkeletonTable rows={4} cols={6} />
      ) : creditNotes.length === 0 ? (
        <EmptyState
          icon={<Receipt className="w-8 h-8" />}
          title="Aucun avoir"
          description="Créez votre premier avoir client."
          action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> Nouvel avoir</Button>}
        />
      ) : (
        <Card>
          <Table headers={['', 'Numéro', 'Date', 'Client', 'Montant', 'Statut', 'Actions']}>
            {creditNotes.map((cn) => (
              <div key={cn.id}>
                <TableRow onClick={() => toggleExpand(cn.id)}>
                  <TableCell className="w-8">
                    {cn.credit_note_lines && cn.credit_note_lines.length > 0
                      ? (expanded.has(cn.id) ? <ChevronDown className="w-4 h-4" /> : <ChevronRight className="w-4 h-4" />)
                      : <span className="w-4 inline-block" />}
                  </TableCell>
                  <TableCell className="font-mono font-semibold">{cn.number}</TableCell>
                  <TableCell>{formatDate(cn.date)}</TableCell>
                  <TableCell>{cn.customer_name || 'N/A'}</TableCell>
                  <TableCell className="font-mono text-[var(--color-danger)] text-right">-{formatCurrency(Number(cn.total))}</TableCell>
                  <TableCell><Badge variant={statusBadge[cn.status]}>{statusLabels[cn.status]}</Badge></TableCell>
                  <TableCell>
                    <div className="flex items-center gap-1">
                      {cn.status === 'draft' && (
                        <button onClick={(e) => { e.stopPropagation(); handleApply(cn.id) }} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-success)]" title="Appliquer">
                          <CheckCircle className="w-4 h-4" />
                        </button>
                      )}
                      <button onClick={(e) => { e.stopPropagation(); handleDelete(cn.id) }} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]" title="Supprimer">
                        <Trash2 className="w-4 h-4" />
                      </button>
                    </div>
                  </TableCell>
                </TableRow>
                {expanded.has(cn.id) && cn.credit_note_lines && cn.credit_note_lines.map((line) => (
                  <tr key={line.id} className="bg-[var(--color-neutral-50)]">
                    <TableCell />
                    <TableCell className="font-mono text-xs text-[var(--color-text-secondary)]">{line.quantity}x</TableCell>
                    <TableCell colSpan={2} className="text-xs text-[var(--color-text-secondary)]">{line.description}</TableCell>
                    <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(line.total))}</TableCell>
                    <TableCell className="font-mono text-xs text-right">TVA: {formatCurrency(Number(line.vat_total))}</TableCell>
                    <TableCell />
                  </tr>
                ))}
                {cn.reason && (
                  <tr className="bg-[var(--color-neutral-50)]">
                    <TableCell /><TableCell colSpan={6} className="text-xs text-[var(--color-text-secondary)] italic">Motif: {cn.reason}</TableCell>
                  </tr>
                )}
              </div>
            ))}
          </Table>
        </Card>
      )}

      {showForm && (
        <CreditNoteForm
          customers={customers}
          invoices={invoices}
          onClose={() => setShowForm(false)}
          onSaved={() => { setShowForm(false); loadData() }}
        />
      )}
    </div>
  )
}

function CreditNoteForm({ customers, invoices, onClose, onSaved }: {
  customers: Customer[]
  invoices: Invoice[]
  onClose: () => void
  onSaved: () => void
}) {
  const [number, setNumber] = useState('AV-' + new Date().getFullYear() + '-' + String(Math.floor(Math.random() * 999)).padStart(3, '0'))
  const { toast } = useToast()
  const [date, setDate] = useState(new Date().toISOString().split('T')[0])
  const [customerId, setCustomerId] = useState('')
  const [invoiceId, setInvoiceId] = useState('')
  const [reason, setReason] = useState('')
  const [lines, setLines] = useState<{ description: string; quantity: number; unit_price: number; vat_rate: number; total: number; vat_total: number }[]>([
    { description: '', quantity: 1, unit_price: 0, vat_rate: 20, total: 0, vat_total: 0 },
  ])
  const [saving, setSaving] = useState(false)

  const subtotal = lines.reduce((sum, l) => sum + l.total, 0)
  const vatTotal = lines.reduce((sum, l) => sum + l.vat_total, 0)
  const total = subtotal + vatTotal

  function updateLine(idx: number, field: string, value: any) {
    setLines(prev => prev.map((l, i) => {
      if (i !== idx) return l
      const updated = { ...l, [field]: value }
      if (field === 'quantity' || field === 'unit_price' || field === 'vat_rate') {
        updated.total = Number(updated.quantity) * Number(updated.unit_price)
        updated.vat_total = updated.total * (Number(updated.vat_rate) / 100)
      }
      return updated
    }))
  }

  function addLine() {
    setLines(prev => [...prev, { description: '', quantity: 1, unit_price: 0, vat_rate: 20, total: 0, vat_total: 0 }])
  }

  function removeLine(idx: number) {
    setLines(prev => prev.filter((_, i) => i !== idx))
  }

  const customerInvoices = invoices.filter(i => i.customer_id === customerId)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    const customer = customers.find(c => c.id === customerId)
    setSaving(true)
    try {
      await createCreditNote({
        number,
        date,
        customer_id: customerId || null,
        customer_name: customer?.name || null,
        status: 'draft',
        subtotal,
        vat_total: vatTotal,
        total,
        reason: reason || null,
        invoice_id: invoiceId || null,
        credit_note_lines: lines.filter(l => l.description).map(l => ({
          description: l.description,
          quantity: l.quantity,
          unit_price: l.unit_price,
          vat_rate: l.vat_rate,
          total: l.total,
          vat_total: l.vat_total,
        })),
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
          <h2 className="text-lg font-semibold">Nouvel avoir client</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div className="grid grid-cols-2 gap-4">
            <Input label="Numéro" required value={number} onChange={(e) => setNumber(e.target.value)} />
            <Input label="Date" type="date" required value={date} onChange={(e) => setDate(e.target.value)} />
          </div>
          <div className="grid grid-cols-2 gap-4">
            <Select label="Client" required value={customerId} onChange={(e) => { setCustomerId(e.target.value); setInvoiceId('') }} options={[
              { value: '', label: 'Sélectionner un client' },
              ...customers.map(c => ({ value: c.id, label: c.name })),
            ]} />
            <Select label="Facture liée (optionnel)" value={invoiceId} onChange={(e) => setInvoiceId(e.target.value)} options={[
              { value: '', label: 'Aucune' },
              ...customerInvoices.map(i => ({ value: i.id, label: `${i.number} - ${formatCurrency(Number(i.total))}` })),
            ]} />
          </div>

          <div className="border border-[var(--color-border)] rounded-lg overflow-hidden">
            <table className="app-table min-w-[760px]">
              <thead className="bg-[var(--color-neutral-50)]">
                <tr>
                  <th className="px-3 py-2 text-left text-xs font-semibold">Description</th>
                  <th className="px-3 py-2 text-right text-xs font-semibold w-20">Qté</th>
                  <th className="px-3 py-2 text-right text-xs font-semibold w-28">Prix unit.</th>
                  <th className="px-3 py-2 text-right text-xs font-semibold w-20">TVA%</th>
                  <th className="px-3 py-2 text-right text-xs font-semibold w-28">Total</th>
                  <th className="w-8"></th>
                </tr>
              </thead>
              <tbody>
                {lines.map((line, idx) => (
                  <tr key={idx} className="border-t border-[var(--color-border)]">
                    <td className="px-3 py-2">
                      <input value={line.description} onChange={(e) => updateLine(idx, 'description', e.target.value)} className="text-xs border border-[var(--color-border)] rounded px-2 py-1 w-full bg-[var(--color-surface)]" placeholder="Description" />
                    </td>
                    <td className="px-3 py-2">
                      <input type="number" step="0.01" value={line.quantity} onChange={(e) => updateLine(idx, 'quantity', Number(e.target.value))} className="text-xs border border-[var(--color-border)] rounded px-2 py-1 w-full bg-[var(--color-surface)] text-right" />
                    </td>
                    <td className="px-3 py-2">
                      <input type="number" step="0.01" value={line.unit_price} onChange={(e) => updateLine(idx, 'unit_price', Number(e.target.value))} className="text-xs border border-[var(--color-border)] rounded px-2 py-1 w-full bg-[var(--color-surface)] text-right" />
                    </td>
                    <td className="px-3 py-2">
                      <input type="number" step="0.01" value={line.vat_rate} onChange={(e) => updateLine(idx, 'vat_rate', Number(e.target.value))} className="text-xs border border-[var(--color-border)] rounded px-2 py-1 w-full bg-[var(--color-surface)] text-right" />
                    </td>
                    <td className="px-3 py-2 text-right text-xs font-mono">{formatCurrency(line.total + line.vat_total)}</td>
                    <td className="px-3 py-2">
                      {lines.length > 1 && <button type="button" onClick={() => removeLine(idx)} className="text-[var(--color-danger)] hover:bg-[var(--color-neutral-100)] rounded p-1"><X className="w-3 h-3" /></button>}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
            <button type="button" onClick={addLine} className="w-full py-2 text-sm text-[var(--color-primary)] hover:bg-[var(--color-neutral-50)] border-t border-[var(--color-border)]">
              + Ajouter une ligne
            </button>
          </div>

          <div className="flex justify-end gap-6 text-sm">
            <div><span className="text-[var(--color-text-secondary)]">Sous-total: </span><span className="font-mono font-semibold">{formatCurrency(subtotal)}</span></div>
            <div><span className="text-[var(--color-text-secondary)]">TVA: </span><span className="font-mono font-semibold">{formatCurrency(vatTotal)}</span></div>
            <div><span className="text-[var(--color-text-secondary)]">Total: </span><span className="font-mono font-bold text-base">{formatCurrency(total)}</span></div>
          </div>

          <Input label="Motif" value={reason} onChange={(e) => setReason(e.target.value)} placeholder="Raison de l'avoir" />

          <div className="flex justify-end gap-3 pt-4 border-t border-[var(--color-border)]">
            <Button type="button" variant="secondary" onClick={onClose}>Annuler</Button>
            <Button type="submit" disabled={saving}>{saving ? 'Enregistrement...' : 'Créer l\'avoir'}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
