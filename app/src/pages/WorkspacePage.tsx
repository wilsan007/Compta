import { useEffect, useState, useCallback } from 'react'
import { Card, PageHeader, Breadcrumb, Button, Table, TableRow, TableCell, Badge, SkeletonTable } from '@/components/ui'
import { getInvoices, getQuotes, getBankAccounts, getBankTransactions, getProducts, getEmployees, getProjects, getPurchaseInvoices } from '@/lib/queries'
import { formatCurrency, translateStatus } from '@/lib/utils'
import { LayoutGrid, TrendingUp, TrendingDown, Wallet, Users, Package, FolderKanban, ShoppingCart, X, Plus } from 'lucide-react'
import type { Invoice, Quote, BankAccount, BankTransaction, Product, Employee, Project, PurchaseInvoice } from '@/types'
import { useToast } from '@/lib/toast'

interface WidgetConfig {
  id: string
  title: string
  icon: React.ComponentType<{ className?: string }>
  visible: boolean
}

const defaultWidgets: WidgetConfig[] = [
  { id: 'sales-summary', title: 'Ventes — Résumé', icon: TrendingUp, visible: true },
  { id: 'purchases-summary', title: 'Achats — Résumé', icon: ShoppingCart, visible: true },
  { id: 'bank-summary', title: 'Trésorerie', icon: Wallet, visible: true },
  { id: 'recent-invoices', title: 'Factures récentes', icon: LayoutGrid, visible: true },
  { id: 'low-stock', title: 'Stock bas', icon: Package, visible: true },
  { id: 'employees-summary', title: 'Employés', icon: Users, visible: true },
  { id: 'projects-summary', title: 'Projets actifs', icon: FolderKanban, visible: true },
  { id: 'recent-quotes', title: 'Devis récents', icon: TrendingDown, visible: false },
]

export function WorkspacePage() {
  const { toast } = useToast()
const [widgets, setWidgets] = useState<WidgetConfig[]>(() => {
    const saved = localStorage.getItem('compta-workspace-widgets')
    if (saved) {
      try { return JSON.parse(saved) } catch { return defaultWidgets }
    }
    return defaultWidgets
  })
  const [showConfig, setShowConfig] = useState(false)
  const [invoices, setInvoices] = useState<Invoice[]>([])
  const [quotes, setQuotes] = useState<Quote[]>([])
  const [bankAccounts, setBankAccounts] = useState<BankAccount[]>([])
  const [transactions, setTransactions] = useState<BankTransaction[]>([])
  const [products, setProducts] = useState<Product[]>([])
  const [employees, setEmployees] = useState<Employee[]>([])
  const [projects, setProjects] = useState<Project[]>([])
  const [purchaseInvoices, setPurchaseInvoices] = useState<PurchaseInvoice[]>([])
  const [loading, setLoading] = useState(true)

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const [inv, q, ba, bt, p, e, pr, pi] = await Promise.all([
        getInvoices(), getQuotes(), getBankAccounts(), getBankTransactions(),
        getProducts(), getEmployees(), getProjects(), getPurchaseInvoices(),
      ])
      setInvoices(inv)
      setQuotes(q)
      setBankAccounts(ba)
      setTransactions(bt)
      setProducts(p)
      setEmployees(e)
      setProjects(pr)
      setPurchaseInvoices(pi)
    } catch (err) { console.error(err); toast('error', 'Erreur', 'Erreur lors du chargement de l\'espace de travail') } finally { setLoading(false) }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  function toggleWidget(id: string) {
    setWidgets(prev => {
      const updated = prev.map(w => w.id === id ? { ...w, visible: !w.visible } : w)
      localStorage.setItem('compta-workspace-widgets', JSON.stringify(updated))
      return updated
    })
  }

  function resetWidgets() {
    setWidgets(defaultWidgets)
    localStorage.setItem('compta-workspace-widgets', JSON.stringify(defaultWidgets))
  }

  const visibleWidgets = widgets.filter(w => w.visible)

  const totalSales = invoices.reduce((s, i) => s + Number(i.total), 0)
  const totalPaid = invoices.reduce((s, i) => s + Number(i.amount_paid), 0)
  const totalOutstanding = invoices.reduce((s, i) => s + Number(i.amount_due), 0)
  const totalPurchases = purchaseInvoices.reduce((s, i) => s + Number(i.total), 0)
  const totalBankBalance = bankAccounts.reduce((s, a) => s + Number(a.balance), 0)
  const lowStockProducts = products.filter(p => p.type === 'stock' && Number(p.stock_quantity) <= Number(p.reorder_level))
  const activeProjects = projects.filter(p => p.status === 'active')
  const activeEmployees = employees.filter(e => e.status === 'active')

  function renderWidget(widgetId: string) {
    if (loading) return <SkeletonTable rows={3} cols={3} />

    switch (widgetId) {
      case 'sales-summary':
        return (
          <div className="space-y-2 p-4">
            <div className="flex justify-between text-sm"><span className="text-[var(--color-text-secondary)]">Total facturé</span><span className="font-mono font-bold">{formatCurrency(totalSales)}</span></div>
            <div className="flex justify-between text-sm"><span className="text-[var(--color-text-secondary)]">Encaissé</span><span className="font-mono text-[var(--color-success)]">{formatCurrency(totalPaid)}</span></div>
            <div className="flex justify-between text-sm"><span className="text-[var(--color-text-secondary)]">En attente</span><span className="font-mono text-[var(--color-warning)]">{formatCurrency(totalOutstanding)}</span></div>
            <div className="flex justify-between text-sm border-t border-[var(--color-border)] pt-2"><span className="text-[var(--color-text-secondary)]">Factures</span><span className="font-bold">{invoices.length}</span></div>
          </div>
        )
      case 'purchases-summary':
        return (
          <div className="space-y-2 p-4">
            <div className="flex justify-between text-sm"><span className="text-[var(--color-text-secondary)]">Total achats</span><span className="font-mono font-bold">{formatCurrency(totalPurchases)}</span></div>
            <div className="flex justify-between text-sm"><span className="text-[var(--color-text-secondary)]">Payé</span><span className="font-mono text-[var(--color-success)]">{formatCurrency(purchaseInvoices.reduce((s, i) => s + Number(i.amount_paid), 0))}</span></div>
            <div className="flex justify-between text-sm"><span className="text-[var(--color-text-secondary)]">À payer</span><span className="font-mono text-[var(--color-warning)]">{formatCurrency(purchaseInvoices.reduce((s, i) => s + Number(i.amount_due), 0))}</span></div>
            <div className="flex justify-between text-sm border-t border-[var(--color-border)] pt-2"><span className="text-[var(--color-text-secondary)]">Factures d'achat</span><span className="font-bold">{purchaseInvoices.length}</span></div>
          </div>
        )
      case 'bank-summary':
        return (
          <div className="space-y-2 p-4">
            <div className="flex justify-between text-sm"><span className="text-[var(--color-text-secondary)]">Solde total</span><span className="font-mono font-bold text-base">{formatCurrency(totalBankBalance)}</span></div>
            {bankAccounts.slice(0, 3).map(a => (
              <div key={a.id} className="flex justify-between text-xs"><span className="text-[var(--color-text-secondary)]">{a.name}</span><span className="font-mono">{formatCurrency(Number(a.balance))}</span></div>
            ))}
            <div className="flex justify-between text-sm border-t border-[var(--color-border)] pt-2"><span className="text-[var(--color-text-secondary)]">Transactions</span><span className="font-bold">{transactions.length}</span></div>
          </div>
        )
      case 'recent-invoices':
        return (
          <Table headers={['Numéro', 'Client', 'Montant', 'Statut']}>
            {invoices.slice(0, 5).map(inv => (
              <TableRow key={inv.id}>
                <TableCell className="font-mono text-xs">{inv.number}</TableCell>
                <TableCell className="text-sm truncate max-w-[120px]">{inv.customer_name || 'N/A'}</TableCell>
                <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(inv.total))}</TableCell>
                <TableCell><Badge variant={inv.status === 'paid' ? 'success' : inv.status === 'overdue' ? 'danger' : 'neutral'}>{translateStatus(inv.status)}</Badge></TableCell>
              </TableRow>
            ))}
            {invoices.length === 0 && <TableRow><TableCell colSpan={4} className="text-center text-[var(--color-text-secondary)] text-sm">Aucune facture</TableCell></TableRow>}
          </Table>
        )
      case 'low-stock':
        return (
          <Table headers={['Produit', 'Stock', 'Seuil']}>
            {lowStockProducts.slice(0, 5).map(p => (
              <TableRow key={p.id}>
                <TableCell className="text-sm">{p.name}</TableCell>
                <TableCell className="font-mono text-xs text-[var(--color-danger)]">{p.stock_quantity}</TableCell>
                <TableCell className="font-mono text-xs">{p.reorder_level}</TableCell>
              </TableRow>
            ))}
            {lowStockProducts.length === 0 && <TableRow><TableCell colSpan={3} className="text-center text-[var(--color-text-secondary)] text-sm">Aucun stock bas</TableCell></TableRow>}
          </Table>
        )
      case 'employees-summary':
        return (
          <div className="space-y-2 p-4">
            <div className="flex justify-between text-sm"><span className="text-[var(--color-text-secondary)]">Total employés</span><span className="font-bold">{employees.length}</span></div>
            <div className="flex justify-between text-sm"><span className="text-[var(--color-text-secondary)]">Actifs</span><span className="font-bold text-[var(--color-success)]">{activeEmployees.length}</span></div>
            <div className="flex justify-between text-sm"><span className="text-[var(--color-text-secondary)]">En congé</span><span className="font-bold text-[var(--color-warning)]">{employees.filter(e => e.status === 'on_leave').length}</span></div>
            <div className="flex justify-between text-sm border-t border-[var(--color-border)] pt-2"><span className="text-[var(--color-text-secondary)]">Masse salariale</span><span className="font-mono font-bold">{formatCurrency(activeEmployees.reduce((s, e) => s + Number(e.salary), 0))}</span></div>
          </div>
        )
      case 'projects-summary':
        return (
          <Table headers={['Projet', 'Budget', 'Rentabilité']}>
            {activeProjects.slice(0, 5).map(p => {
              const profit = Number(p.budget) - Number(p.actual_cost)
              return (
                <TableRow key={p.id}>
                  <TableCell className="text-sm truncate max-w-[120px]">{p.name}</TableCell>
                  <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(p.budget))}</TableCell>
                  <TableCell className={`font-mono text-xs text-right ${profit >= 0 ? 'text-[var(--color-success)]' : 'text-[var(--color-danger)]'}`}>{formatCurrency(profit)}</TableCell>
                </TableRow>
              )
            })}
            {activeProjects.length === 0 && <TableRow><TableCell colSpan={3} className="text-center text-[var(--color-text-secondary)] text-sm">Aucun projet actif</TableCell></TableRow>}
          </Table>
        )
      case 'recent-quotes':
        return (
          <Table headers={['Numéro', 'Client', 'Montant', 'Statut']}>
            {quotes.slice(0, 5).map(q => (
              <TableRow key={q.id}>
                <TableCell className="font-mono text-xs">{q.number}</TableCell>
                <TableCell className="text-sm truncate max-w-[120px]">{q.customer_name || 'N/A'}</TableCell>
                <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(q.total))}</TableCell>
                <TableCell><Badge variant={q.status === 'accepted' ? 'success' : 'warning'}>{translateStatus(q.status)}</Badge></TableCell>
              </TableRow>
            ))}
            {quotes.length === 0 && <TableRow><TableCell colSpan={4} className="text-center text-[var(--color-text-secondary)] text-sm">Aucun devis</TableCell></TableRow>}
          </Table>
        )
      default:
        return null
    }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: 'Tableaux de bord' }, { label: 'Mon espace' }]} />
      <PageHeader
        title="Mon espace de travail"
        subtitle="Personnalisez votre tableau de bord avec des widgets"
        action={
          <div className="flex gap-2">
            <Button variant="secondary" onClick={() => setShowConfig(!showConfig)}>
              <LayoutGrid className="w-4 h-4" /> Configurer
            </Button>
            <Button variant="secondary" onClick={resetWidgets}>Réinitialiser</Button>
          </div>
        }
      />

      {showConfig && (
        <Card className="mb-6">
          <div className="p-4">
            <h3 className="text-sm font-semibold mb-3">Widgets disponibles</h3>
            <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
              {widgets.map(w => (
                <button
                  key={w.id}
                  onClick={() => toggleWidget(w.id)}
                  className={`flex items-center gap-2 px-3 py-2 rounded-lg border text-sm transition-colors ${
                    w.visible
                      ? 'border-[var(--color-primary)] bg-[rgba(0,102,204,0.05)] text-[var(--color-primary)]'
                      : 'border-[var(--color-border)] text-[var(--color-text-secondary)] hover:bg-[var(--color-neutral-50)]'
                  }`}
                >
                  <w.icon className="w-4 h-4" />
                  <span className="flex-1 text-left">{w.title}</span>
                  {w.visible ? <X className="w-3 h-3" /> : <Plus className="w-3 h-3" />}
                </button>
              ))}
            </div>
          </div>
        </Card>
      )}

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        {visibleWidgets.map(w => (
          <Card key={w.id}>
            <div className="flex items-center gap-2 px-4 py-3 border-b border-[var(--color-border)]">
              <w.icon className="w-4 h-4 text-[var(--color-primary)]" />
              <h3 className="text-sm font-semibold">{w.title}</h3>
            </div>
            {renderWidget(w.id)}
          </Card>
        ))}
      </div>

      {visibleWidgets.length === 0 && (
        <Card>
          <div className="p-12 text-center">
            <LayoutGrid className="w-12 h-12 mx-auto mb-3 text-[var(--color-text-secondary)]" />
            <p className="text-[var(--color-text-secondary)]">Aucun widget affiché. Cliquez sur "Configurer" pour ajouter des widgets.</p>
          </div>
        </Card>
      )}
    </div>
  )
}
