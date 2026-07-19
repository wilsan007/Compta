import { useEffect, useState, useCallback } from 'react'
import { Card, PageHeader, SkeletonTable, Breadcrumb, Table, TableRow, TableCell, Badge } from '@/components/ui'
import { getPurchaseInvoices, getSuppliers, getProducts } from '@/lib/queries'
import { formatCurrency, translateStatus } from '@/lib/utils'
import type { PurchaseInvoice, Supplier, Product } from '@/types'
import { useToast } from '@/lib/toast'

export function PurchasesDashboardPage() {
  const { toast } = useToast()
const [invoices, setInvoices] = useState<PurchaseInvoice[]>([])
  const [suppliers, setSuppliers] = useState<Supplier[]>([])
  const [products, setProducts] = useState<Product[]>([])
  const [loading, setLoading] = useState(true)

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const [inv, s, p] = await Promise.all([getPurchaseInvoices(), getSuppliers(), getProducts()])
      setInvoices(inv)
      setSuppliers(s)
      setProducts(p)
    } catch (err) { console.error(err); toast('error', 'Erreur', 'Erreur lors du chargement') } finally { setLoading(false) }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  const totalBills = invoices.reduce((s, i) => s + Number(i.total), 0)
  const totalPaid = invoices.reduce((s, i) => s + Number(i.amount_paid), 0)
  const totalOutstanding = invoices.reduce((s, i) => s + Number(i.amount_due), 0)
  const lowStock = products.filter(p => p.type === 'stock' && Number(p.stock_quantity) <= Number(p.reorder_level))

  return (
    <div>
      <Breadcrumb items={[{ label: 'Tableaux de bord' }, { label: 'Achats' }]} />
      <PageHeader title="Tableau de bord — Achats" subtitle="Vue d'ensemble de vos achats et fournisseurs" />

      {loading ? (
        <SkeletonTable rows={4} cols={4} />
      ) : (
        <>
          <div className="grid grid-cols-4 gap-4 mb-6">
            <Card><div className="p-4"><p className="text-sm text-[var(--color-text-secondary)]">Total factures</p><p className="text-2xl font-bold font-mono">{formatCurrency(totalBills)}</p></div></Card>
            <Card><div className="p-4"><p className="text-sm text-[var(--color-text-secondary)]">Payé</p><p className="text-2xl font-bold font-mono text-[var(--color-success)]">{formatCurrency(totalPaid)}</p></div></Card>
            <Card><div className="p-4"><p className="text-sm text-[var(--color-text-secondary)]">À payer</p><p className="text-2xl font-bold font-mono text-[var(--color-warning)]">{formatCurrency(totalOutstanding)}</p></div></Card>
            <Card><div className="p-4"><p className="text-sm text-[var(--color-text-secondary)]">Fournisseurs</p><p className="text-2xl font-bold">{suppliers.length}</p></div></Card>
          </div>

          <div className="grid grid-cols-2 gap-6">
            <Card>
              <h3 className="text-sm font-semibold p-4 border-b border-[var(--color-border)]">Factures récentes</h3>
              <Table headers={['Numéro', 'Fournisseur', 'Montant', 'Statut']}>
                {invoices.slice(0, 5).map((inv) => (
                  <TableRow key={inv.id}>
                    <TableCell className="font-mono text-xs">{inv.number}</TableCell>
                    <TableCell className="text-sm">{inv.supplier_name || 'N/A'}</TableCell>
                    <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(inv.total))}</TableCell>
                    <TableCell><Badge variant={inv.status === 'paid' ? 'success' : 'warning'}>{translateStatus(inv.status)}</Badge></TableCell>
                  </TableRow>
                ))}
              </Table>
            </Card>

            <Card>
              <h3 className="text-sm font-semibold p-4 border-b border-[var(--color-border)]">Stock bas ({lowStock.length})</h3>
              <Table headers={['Produit', 'Stock', 'Seuil', 'Unité']}>
                {lowStock.slice(0, 5).map((p) => (
                  <TableRow key={p.id}>
                    <TableCell className="text-sm">{p.name}</TableCell>
                    <TableCell className="font-mono text-xs text-[var(--color-danger)]">{p.stock_quantity}</TableCell>
                    <TableCell className="font-mono text-xs">{p.reorder_level}</TableCell>
                    <TableCell className="text-xs">{p.unit}</TableCell>
                  </TableRow>
                ))}
                {lowStock.length === 0 && <TableRow><TableCell colSpan={4} className="text-center text-[var(--color-text-secondary)] text-sm">Aucun stock bas</TableCell></TableRow>}
              </Table>
            </Card>
          </div>
        </>
      )}
    </div>
  )
}
