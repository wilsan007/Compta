import { useEffect, useState, useCallback } from 'react'
import { Card, PageHeader, Button, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { getQuotes, createQuote, updateQuote, deleteQuote, convertQuoteToInvoice, getCustomers, getProducts } from '@/lib/queries'
import { formatCurrency, formatDate } from '@/lib/utils'
import { FileText, Plus, Trash2, X, ChevronDown, ChevronRight, ArrowRight } from 'lucide-react'
import type { Quote, Customer, Product } from '@/types'
import { useToast } from '@/lib/toast'

const statusLabels: Record<string, string> = {
  draft: 'Brouillon',
  sent: 'Envoyé',
  accepted: 'Accepté',
  rejected: 'Refusé',
  expired: 'Expiré',
}

export function QuotesPage() {
  const { toast } = useToast()
const [quotes, setQuotes] = useState<Quote[]>([])
  const [customers, setCustomers] = useState<Customer[]>([])
  const [products, setProducts] = useState<Product[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [expanded, setExpanded] = useState<Set<string>>(new Set())
  const [filterStatus, setFilterStatus] = useState('')

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const [q, c, p] = await Promise.all([getQuotes(), getCustomers(), getProducts()])
      setQuotes(q)
      setCustomers(c)
      setProducts(p)
    } catch (err) {
      console.error('Failed to load quotes:', err)
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
    if (!window.confirm('Supprimer ce devis ?')) return
    try {
      await deleteQuote(id)
      await loadData()
    } catch (err: any) {
      toast('error', 'Erreur', err.message || 'échec')
    }
  }

  async function handleConvert(id: string) {
    if (!window.confirm('Convertir ce devis en facture ?')) return
    try {
      await convertQuoteToInvoice(id)
      toast('success', 'Succès', 'Devis converti en facture avec succès!')
      await loadData()
    } catch (err: any) {
      toast('error', 'Erreur', err.message || 'échec')
    }
  }

  async function handleStatusChange(id: string, status: string) {
    try {
      await updateQuote(id, { status: status as any })
      await loadData()
    } catch (err: any) {
      toast('error', 'Erreur', err.message || 'échec')
    }
  }

  const filtered = filterStatus ? quotes.filter(q => q.status === filterStatus) : quotes

  return (
    <div>
      <Breadcrumb items={[{ label: 'Ventes' }, { label: 'Devis' }]} />
      <PageHeader
        title="Devis & Estimations"
        subtitle="Créez et suivez vos devis clients"
        action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> Nouveau devis</Button>}
      />

      <div className="mb-4 flex items-center gap-3">
        <Select value={filterStatus} onChange={(e) => setFilterStatus(e.target.value)} className="max-w-xs" options={[
          { value: '', label: 'Tous les statuts' },
          { value: 'draft', label: 'Brouillon' },
          { value: 'sent', label: 'Envoyé' },
          { value: 'accepted', label: 'Accepté' },
          { value: 'rejected', label: 'Refusé' },
          { value: 'expired', label: 'Expiré' },
        ]} />
        <span className="text-sm text-[var(--color-text-secondary)]">{filtered.length} devis</span>
      </div>

      {loading ? (
        <SkeletonTable rows={5} cols={6} />
      ) : filtered.length === 0 ? (
        <EmptyState
          icon={<FileText className="w-8 h-8" />}
          title="Aucun devis"
          description="Créez votre premier devis client."
          action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> Nouveau devis</Button>}
        />
      ) : (
        <Card>
          <Table headers={['', 'Numéro', 'Date', 'Client', 'Montant', 'Statut', 'Actions']}>
            {filtered.map((quote) => (
              <div key={quote.id}>
                <TableRow onClick={() => toggleExpand(quote.id)}>
                  <TableCell className="w-8">
                    {quote.quote_lines && quote.quote_lines.length > 0
                      ? (expanded.has(quote.id) ? <ChevronDown className="w-4 h-4" /> : <ChevronRight className="w-4 h-4" />)
                      : <span className="w-4 inline-block" />}
                  </TableCell>
                  <TableCell className="font-mono font-semibold">{quote.number}</TableCell>
                  <TableCell>{formatDate(quote.date)}</TableCell>
                  <TableCell>{quote.customer_name || 'N/A'}</TableCell>
                  <TableCell className="font-mono text-right">{formatCurrency(Number(quote.total))}</TableCell>
                  <TableCell>
                    <select
                      value={quote.status}
                      onClick={(e) => e.stopPropagation()}
                      onChange={(e) => handleStatusChange(quote.id, e.target.value)}
                      className="text-xs border border-[var(--color-border)] rounded px-2 py-1 bg-[var(--color-surface)]"
                    >
                      {Object.entries(statusLabels).map(([k, v]) => (
                        <option key={k} value={k}>{v}</option>
                      ))}
                    </select>
                  </TableCell>
                  <TableCell>
                    <div className="flex items-center gap-1">
                      {quote.status === 'accepted' && (
                        <button onClick={(e) => { e.stopPropagation(); handleConvert(quote.id) }} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-success)]" title="Convertir en facture">
                          <ArrowRight className="w-4 h-4" />
                        </button>
                      )}
                      <button onClick={(e) => { e.stopPropagation(); handleDelete(quote.id) }} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]" title="Supprimer">
                        <Trash2 className="w-4 h-4" />
                      </button>
                    </div>
                  </TableCell>
                </TableRow>
                {expanded.has(quote.id) && quote.quote_lines && quote.quote_lines.map((line) => (
                  <tr key={line.id} className="bg-[var(--color-neutral-50)]">
                    <TableCell />
                    <TableCell className="font-mono text-xs text-[var(--color-text-secondary)]">{line.quantity}x</TableCell>
                    <TableCell colSpan={2} className="text-xs text-[var(--color-text-secondary)]">{line.description}</TableCell>
                    <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(line.total))}</TableCell>
                    <TableCell className="font-mono text-xs text-right">TVA: {formatCurrency(Number(line.vat_total))}</TableCell>
                    <TableCell />
                  </tr>
                ))}
              </div>
            ))}
          </Table>
        </Card>
      )}

      {showForm && (
        <QuoteForm
          customers={customers}
          products={products}
          onClose={() => setShowForm(false)}
          onSaved={() => { setShowForm(false); loadData() }}
        />
      )}
    </div>
  )
}

function QuoteForm({ customers, products, onClose, onSaved }: {
  customers: Customer[]
  products: Product[]
  onClose: () => void
  onSaved: () => void
}) {
  const [number, setNumber] = useState('DEV-' + new Date().getFullYear() + '-' + String(Math.floor(Math.random() * 999)).padStart(3, '0'))
  const { toast } = useToast()
  const [date, setDate] = useState(new Date().toISOString().split('T')[0])
  const [expiryDate, setExpiryDate] = useState(new Date(Date.now() + 30 * 86400000).toISOString().split('T')[0])
  const [customerId, setCustomerId] = useState('')
  const [notes, setNotes] = useState('')
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

  function selectProduct(idx: number, productId: string) {
    const product = products.find(p => p.id === productId)
    if (product) {
      updateLine(idx, 'description', product.name)
      updateLine(idx, 'unit_price', product.sale_price)
      updateLine(idx, 'vat_rate', product.vat_rate)
    }
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    const customer = customers.find(c => c.id === customerId)
    setSaving(true)
    try {
      await createQuote({
        number,
        date,
        expiry_date: expiryDate,
        customer_id: customerId || null,
        customer_name: customer?.name || null,
        status: 'draft',
        subtotal,
        vat_total: vatTotal,
        total,
        notes,
        quote_lines: lines.filter(l => l.description).map(l => ({
          product_id: null,
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
          <h2 className="text-lg font-semibold">Nouveau devis</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div className="grid grid-cols-3 gap-4">
            <Input label="Numéro" required value={number} onChange={(e) => setNumber(e.target.value)} />
            <Input label="Date" type="date" required value={date} onChange={(e) => setDate(e.target.value)} />
            <Input label="Expire le" type="date" required value={expiryDate} onChange={(e) => setExpiryDate(e.target.value)} />
          </div>
          <Select label="Client" required value={customerId} onChange={(e) => setCustomerId(e.target.value)} options={[
            { value: '', label: 'Sélectionner un client' },
            ...customers.map(c => ({ value: c.id, label: c.name })),
          ]} />

          <div className="border border-[var(--color-border)] rounded-lg overflow-hidden">
            <table className="app-table min-w-[760px]">
              <thead className="bg-[var(--color-neutral-50)]">
                <tr>
                  <th className="px-3 py-2 text-left text-xs font-semibold">Produit</th>
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
                      <select value="" onChange={(e) => selectProduct(idx, e.target.value)} className="text-xs border border-[var(--color-border)] rounded px-2 py-1 w-full bg-[var(--color-surface)]">
                        <option value="">—</option>
                        {products.map(p => <option key={p.id} value={p.id}>{p.name}</option>)}
                      </select>
                    </td>
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

          <Input label="Notes" value={notes} onChange={(e) => setNotes(e.target.value)} placeholder="Notes optionnelles" />

          <div className="flex justify-end gap-3 pt-4 border-t border-[var(--color-border)]">
            <Button type="button" variant="secondary" onClick={onClose}>Annuler</Button>
            <Button type="submit" disabled={saving}>{saving ? 'Enregistrement...' : 'Créer le devis'}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
