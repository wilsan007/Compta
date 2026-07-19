import { useEffect, useState } from 'react'
import { Card, PageHeader, Button, SortableTable, TableRow, TableCell, Badge, EmptyState, AutoBreadcrumb, SkeletonTable, Input, Combobox, exportToCSV } from '@/components/ui'
import { getPurchaseInvoices, getSuppliers, createPurchaseInvoice, updatePurchaseInvoice, getChartAccounts, getFiscalYears, checkBudgetAvailability, createBudgetCommitment } from '@/lib/queries'
import { formatCurrency, formatDate, translateStatus } from '@/lib/utils'
import { useToast } from '@/lib/toast'
import { Package, Plus, Search, Eye, X, CheckCircle, Download, AlertTriangle } from 'lucide-react'
import type { PurchaseInvoice, Supplier, ChartAccount, FiscalYear, BudgetControlResult } from '@/types'

export function PurchaseInvoicesPage() {
  const { toast } = useToast()
  const [invoices, setInvoices] = useState<PurchaseInvoice[]>([])
  const [suppliers, setSuppliers] = useState<Supplier[]>([])
  const [accounts, setAccounts] = useState<ChartAccount[]>([])
  const [years, setYears] = useState<FiscalYear[]>([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [showForm, setShowForm] = useState(false)
  const [viewing, setViewing] = useState<PurchaseInvoice | null>(null)
  const [actionLoading, setActionLoading] = useState<string | null>(null)

  useEffect(() => {
    loadInvoices()
  }, [])

  async function loadInvoices() {
    try {
      const [inv, sup, accs, fys] = await Promise.all([getPurchaseInvoices(), getSuppliers(), getChartAccounts(), getFiscalYears()])
      setInvoices(inv || [])
      setSuppliers(sup || [])
      setAccounts(accs || [])
      setYears(fys || [])
    } catch (err) {
      console.error('Error loading purchase invoices:', err)
    } finally {
      setLoading(false)
    }
  }

  async function handleMarkPaid(id: string) {
    setActionLoading(id)
    try {
      const inv = invoices.find(i => i.id === id)
      if (!inv) return
      await updatePurchaseInvoice(id, { status: 'paid', amount_paid: inv.total, amount_due: 0 })
      toast('success', 'Facture marquée comme payée')
      await loadInvoices()
    } catch (err: any) {
      toast('error', 'Erreur', err.message || 'échec')
    } finally {
      setActionLoading(null)
    }
  }

  function handleExportCSV() {
    const headers = ['Numéro', 'Fournisseur', 'Date', 'Échéance', 'Statut', 'Total', 'À payer']
    const rows = filtered.map((inv) => [
      inv.number || '',
      inv.supplier_name || '',
      formatDate(inv.date),
      formatDate(inv.due_date),
      statusMap[inv.status]?.label || translateStatus(inv.status),
      Number(inv.total || 0),
      Number(inv.amount_due || 0),
    ])
    exportToCSV(`factures-achat-${new Date().toISOString().split('T')[0]}.csv`, headers, rows)
    toast('info', 'Export CSV', `${filtered.length} facture(s) exportée(s)`)
  }

  const statusMap: Record<string, { variant: 'success' | 'warning' | 'danger' | 'neutral' | 'primary'; label: string }> = {
    draft: { variant: 'neutral', label: 'Brouillon' },
    received: { variant: 'primary', label: 'Reçue' },
    paid: { variant: 'success', label: 'Payée' },
    overdue: { variant: 'danger', label: 'En retard' },
    cancelled: { variant: 'neutral', label: 'Annulée' },
  }

  const filtered = invoices.filter((inv) =>
    inv.number?.toLowerCase().includes(search.toLowerCase()) ||
    inv.supplier_name?.toLowerCase().includes(search.toLowerCase())
  )

  const totalAmount = filtered.reduce((sum, inv) => sum + Number(inv.total || 0), 0)
  const totalDue = filtered.reduce((sum, inv) => sum + Number(inv.amount_due || 0), 0)

  return (
    <div className="animate-fade-in">
      <AutoBreadcrumb />
      <PageHeader
        title="Factures d'achat"
        subtitle={`${invoices.length} facture(s) • ${formatCurrency(totalAmount)} total • ${formatCurrency(totalDue)} à payer`}
        action={
          <div className="flex items-center gap-2">
            <Button variant="secondary" onClick={handleExportCSV}><Download className="w-4 h-4" /> Exporter</Button>
            <Button variant="primary" onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> Nouvelle facture d'achat</Button>
          </div>
        }
      />

      <Card>
        <div className="mb-4 relative">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-[var(--color-text-secondary)]" />
          <input
            className="input pl-10"
            placeholder="Rechercher par numéro ou fournisseur..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
        </div>

        {loading ? (
          <SkeletonTable rows={5} cols={8} />
        ) : filtered.length > 0 ? (
          <SortableTable
            headers={[
              { label: 'Numéro', key: 'number', sortable: true },
              { label: 'Fournisseur', key: 'supplier_name', sortable: true },
              { label: 'Date', key: 'date', sortable: true },
              { label: 'Échéance', key: 'due_date', sortable: true },
              { label: 'Statut', key: 'status', sortable: true },
              { label: 'Total', key: 'total', sortable: true, className: 'text-right' },
              { label: 'À payer', key: 'amount_due', sortable: true, className: 'text-right' },
              { label: 'Actions' },
            ]}
            data={filtered as any}
            initialSortKey="date"
            initialSortDir="desc"
            renderRow={(inv: any) => {
              const st = statusMap[inv.status] || { variant: 'neutral' as const, label: translateStatus(inv.status) }
              return (
                <TableRow key={inv.id}>
                  <TableCell className="font-medium">{inv.number}</TableCell>
                  <TableCell>{inv.supplier_name || '—'}</TableCell>
                  <TableCell>{formatDate(inv.date)}</TableCell>
                  <TableCell>{formatDate(inv.due_date)}</TableCell>
                  <TableCell><Badge variant={st.variant}>{st.label}</Badge></TableCell>
                  <TableCell className="font-medium text-right">{formatCurrency(Number(inv.total) || 0)}</TableCell>
                  <TableCell className={Number(inv.amount_due) > 0 ? 'text-[var(--color-danger)] font-medium text-right' : 'text-right'}>
                    {formatCurrency(Number(inv.amount_due) || 0)}
                  </TableCell>
                  <TableCell>
                    <div className="flex items-center gap-1">
                      <button onClick={() => setViewing(inv)} className="p-1.5 rounded text-[var(--color-text-secondary)] hover:bg-[var(--color-neutral-100)]" title="Voir">
                        <Eye className="w-4 h-4" />
                      </button>
                      {inv.status !== 'paid' && inv.status !== 'cancelled' && (
                        <button onClick={() => handleMarkPaid(inv.id)} disabled={actionLoading === inv.id} className="p-1.5 rounded text-[var(--color-success)] hover:bg-[rgba(0,135,90,0.1)] disabled:opacity-40" title="Marquer payée">
                          <CheckCircle className="w-4 h-4" />
                        </button>
                      )}
                    </div>
                  </TableCell>
                </TableRow>
              )
            }}
          />
        ) : (
          <EmptyState
            icon={<Package className="w-8 h-8" />}
            title="Aucune facture d'achat"
            description="Enregistrez votre première facture fournisseur"
            action={<Button variant="primary" onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> Enregistrer un achat</Button>}
          />
        )}
      </Card>

      {showForm && (
        <PurchaseInvoiceForm suppliers={suppliers} accounts={accounts} years={years} onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadInvoices() }} />
      )}

      {viewing && (
        <PurchaseInvoiceDetailModal invoice={viewing} onClose={() => setViewing(null)} />
      )}
    </div>
  )
}

function PurchaseInvoiceForm({ suppliers, accounts, years, onClose, onSaved }: {
  suppliers: Supplier[]
  accounts: ChartAccount[]
  years: FiscalYear[]
  onClose: () => void
  onSaved: () => void
}) {
  const [supplierId, setSupplierId] = useState('')
  const { toast } = useToast()
  const [number, setNumber] = useState('ACH-' + new Date().getFullYear() + '-' + String(Math.floor(Math.random() * 9999)).padStart(3, '0'))
  const [date, setDate] = useState(new Date().toISOString().split('T')[0])
  const [dueDate, setDueDate] = useState('')
  const [total, setTotal] = useState('')
  const [accountCode, setAccountCode] = useState('')
  const [fiscalYearId, setFiscalYearId] = useState('')
  const [budgetCheck, setBudgetCheck] = useState<BudgetControlResult | null>(null)
  const [checking, setChecking] = useState(false)
  const [saving, setSaving] = useState(false)

  const expenseAccounts = accounts.filter(a => a.type === 'expense')
  const totalNum = Number(total) || 0

  async function checkBudget() {
    if (!accountCode || totalNum <= 0) return
    setChecking(true)
    try {
      const result = await checkBudgetAvailability(accountCode, totalNum, fiscalYearId || undefined)
      setBudgetCheck(result)
    } catch (err) { console.error('Budget check error:', err) }
    finally { setChecking(false) }
  }

  useEffect(() => {
    if (accountCode && totalNum > 0) {
      const t = setTimeout(checkBudget, 300)
      return () => clearTimeout(t)
    } else {
      setBudgetCheck(null)
    }
  }, [accountCode, total, fiscalYearId])

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!supplierId) { toast('warning', 'Sélection requise', 'Sélectionnez un fournisseur'); return }
    if (!total || Number(total) <= 0) { toast('warning', 'Montant invalide', 'Le montant doit être positif'); return }
    setSaving(true)
    try {
      if (budgetCheck?.would_exceed) {
        if (!window.confirm(`Attention: cette facture de ${formatCurrency(totalNum)} dépasse le disponible budgétaire de ${formatCurrency(budgetCheck.overshoot_amount)}. Continuer quand même?`)) {
          setSaving(false)
          return
        }
      }
      const supplier = suppliers.find(s => s.id === supplierId)
      const inv = await createPurchaseInvoice({
        number,
        supplier_id: supplierId,
        supplier_name: supplier?.name || '',
        date,
        due_date: dueDate || date,
        status: 'received',
        subtotal: totalNum,
        vat_total: 0,
        total: totalNum,
        amount_paid: 0,
        amount_due: totalNum,
      } as any)
      if (accountCode) {
        await createBudgetCommitment({
          description: `Facture achat ${number}`,
          account_code: accountCode,
          fiscal_year_id: fiscalYearId || null,
          amount: totalNum,
          commitment_date: date,
          source_type: 'purchase_invoice',
          source_id: inv.id,
          status: 'active',
          supplier_id: supplierId,
          notes: null,
        })
      }
      toast('success', 'Facture d\'achat créée', `Facture ${number} enregistrée`)
      onSaved()
    } catch (err: any) {
      toast('error', 'Erreur', err.message || 'échec')
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '32rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">Nouvelle facture d'achat</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <Input label="Numéro" required value={number} onChange={(e) => setNumber(e.target.value)} />
          <Combobox label="Fournisseur" required value={supplierId} onChange={(v) => setSupplierId(v)} placeholder="Sélectionner un fournisseur..." options={suppliers.map(s => ({ value: s.id, label: s.name }))} />
          <Input label="Date" type="date" required value={date} onChange={(e) => setDate(e.target.value)} />
          <Input label="Échéance" type="date" value={dueDate} onChange={(e) => setDueDate(e.target.value)} />
          <Input label="Montant total (€)" type="number" step="0.01" required value={total} onChange={(e) => setTotal(e.target.value)} placeholder="0.00" />
          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">Compte budgétaire</label>
              <select className="input" value={accountCode} onChange={(e) => setAccountCode(e.target.value)}>
                <option value="">— Aucun —</option>
                {expenseAccounts.map(a => <option key={a.id} value={a.code}>{a.code} — {a.name}</option>)}
              </select>
            </div>
            <div>
              <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">Exercice</label>
              <select className="input" value={fiscalYearId} onChange={(e) => setFiscalYearId(e.target.value)}>
                <option value="">— Tous —</option>
                {years.map(y => <option key={y.id} value={y.id}>{y.code}</option>)}
              </select>
            </div>
          </div>
          {checking && <p className="text-xs text-[var(--color-text-secondary)]">Vérification budgétaire...</p>}
          {budgetCheck && (
            <div className={`rounded-lg p-3 text-sm ${budgetCheck.would_exceed ? 'bg-red-50 border border-red-200 text-red-700' : 'bg-green-50 border border-green-200 text-green-700'}`}>
              <div className="flex items-start gap-2">
                {budgetCheck.would_exceed && <AlertTriangle className="w-4 h-4 mt-0.5 flex-shrink-0" />}
                <div className="space-y-1">
                  <div className="flex justify-between"><span>Budget total:</span><span className="font-mono">{formatCurrency(budgetCheck.budget_total)}</span></div>
                  <div className="flex justify-between"><span>Réalisé:</span><span className="font-mono">{formatCurrency(budgetCheck.realized)}</span></div>
                  <div className="flex justify-between"><span>Engagé:</span><span className="font-mono">{formatCurrency(budgetCheck.committed)}</span></div>
                  <div className="flex justify-between font-semibold"><span>Disponible:</span><span className="font-mono">{formatCurrency(budgetCheck.available)}</span></div>
                  {budgetCheck.would_exceed && (
                    <div className="flex justify-between font-bold"><span>Dépassement:</span><span className="font-mono">{formatCurrency(budgetCheck.overshoot_amount)}</span></div>
                  )}
                </div>
              </div>
            </div>
          )}
          <div className="flex justify-end gap-3 pt-4 border-t border-[var(--color-border)]">
            <Button variant="secondary" type="button" onClick={onClose}>Annuler</Button>
            <Button type="submit" loading={saving}>Créer</Button>
          </div>
        </form>
      </div>
    </div>
  )
}

function PurchaseInvoiceDetailModal({ invoice, onClose }: { invoice: PurchaseInvoice; onClose: () => void }) {
  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '36rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">Facture {invoice.number}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <div className="p-6 space-y-3">
          <div className="flex justify-between text-sm"><span className="text-[var(--color-text-secondary)]">Fournisseur</span><span className="font-medium">{invoice.supplier_name || 'N/A'}</span></div>
          <div className="flex justify-between text-sm"><span className="text-[var(--color-text-secondary)]">Date</span><span>{formatDate(invoice.date)}</span></div>
          <div className="flex justify-between text-sm"><span className="text-[var(--color-text-secondary)]">Échéance</span><span>{formatDate(invoice.due_date)}</span></div>
          <div className="flex justify-between text-sm"><span className="text-[var(--color-text-secondary)]">Statut</span><Badge variant={invoice.status === 'paid' ? 'success' : invoice.status === 'overdue' ? 'danger' : 'neutral'}>{translateStatus(invoice.status)}</Badge></div>
          <div className="flex justify-between text-sm border-t border-[var(--color-border)] pt-3"><span className="text-[var(--color-text-secondary)]">Total</span><span className="font-mono font-bold">{formatCurrency(Number(invoice.total))}</span></div>
          <div className="flex justify-between text-sm"><span className="text-[var(--color-text-secondary)]">Payé</span><span className="font-mono text-[var(--color-success)]">{formatCurrency(Number(invoice.amount_paid))}</span></div>
          <div className="flex justify-between text-sm"><span className="text-[var(--color-text-secondary)]">Reste à payer</span><span className="font-mono text-[var(--color-danger)]">{formatCurrency(Number(invoice.amount_due))}</span></div>
        </div>
      </div>
    </div>
  )
}
