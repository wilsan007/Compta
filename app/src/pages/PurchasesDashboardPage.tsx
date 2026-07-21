import { useEffect, useState, useCallback } from 'react'
import { Card, PageHeader, SkeletonTable, Breadcrumb, Table, TableRow, TableCell, Badge } from '@/components/ui'
import { getPurchaseInvoices, getSuppliers, getProducts } from '@/lib/queries'
import { formatCurrency, translateStatus } from '@/lib/utils'
import type { PurchaseInvoice, Supplier, Product } from '@/types'
import { useToast } from '@/lib/toast'
import { useTranslation } from 'react-i18next'

export function PurchasesDashboardPage() {
  const { t } = useTranslation('purchases')
  const { t: tCommon } = useTranslation('common')
  const { t: tNav } = useTranslation('nav')
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
    } catch (err) { console.error(err); toast('error', tCommon('common.error'), t('dashboard.loadError')) } finally { setLoading(false) }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  const totalBills = invoices.reduce((s, i) => s + Number(i.total), 0)
  const totalPaid = invoices.reduce((s, i) => s + Number(i.amount_paid), 0)
  const totalOutstanding = invoices.reduce((s, i) => s + Number(i.amount_due), 0)
  const lowStock = products.filter(p => p.type === 'stock' && Number(p.stock_quantity) <= Number(p.reorder_level))

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('sections.dashboard') }, { label: t('title') }]} />
      <PageHeader title={t('dashboard.title')} subtitle={t('dashboard.subtitle')} />

      {loading ? (
        <SkeletonTable rows={4} cols={4} />
      ) : (
        <>
          <div className="grid grid-cols-4 gap-4 mb-6">
            <Card><div className="p-4"><p className="text-sm text-[var(--color-text-secondary)]">{t('dashboard.totalBills')}</p><p className="text-2xl font-bold font-mono">{formatCurrency(totalBills)}</p></div></Card>
            <Card><div className="p-4"><p className="text-sm text-[var(--color-text-secondary)]">{t('dashboard.paid')}</p><p className="text-2xl font-bold font-mono text-[var(--color-success)]">{formatCurrency(totalPaid)}</p></div></Card>
            <Card><div className="p-4"><p className="text-sm text-[var(--color-text-secondary)]">{t('dashboard.toPay')}</p><p className="text-2xl font-bold font-mono text-[var(--color-warning)]">{formatCurrency(totalOutstanding)}</p></div></Card>
            <Card><div className="p-4"><p className="text-sm text-[var(--color-text-secondary)]">{t('dashboard.suppliersCount')}</p><p className="text-2xl font-bold">{suppliers.length}</p></div></Card>
          </div>

          <div className="grid grid-cols-2 gap-6">
            <Card>
              <h3 className="text-sm font-semibold p-4 border-b border-[var(--color-border)]">{t('dashboard.recentInvoices')}</h3>
              <Table headers={[t('invoices.number'), t('invoices.supplier'), t('invoices.amount'), t('invoices.status')]}>
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
              <h3 className="text-sm font-semibold p-4 border-b border-[var(--color-border)]">{t('dashboard.lowStock')} ({lowStock.length})</h3>
              <Table headers={[t('dashboard.product'), t('dashboard.stock'), t('dashboard.threshold'), t('dashboard.unit')]}>
                {lowStock.slice(0, 5).map((p) => (
                  <TableRow key={p.id}>
                    <TableCell className="text-sm">{p.name}</TableCell>
                    <TableCell className="font-mono text-xs text-[var(--color-danger)]">{p.stock_quantity}</TableCell>
                    <TableCell className="font-mono text-xs">{p.reorder_level}</TableCell>
                    <TableCell className="text-xs">{p.unit}</TableCell>
                  </TableRow>
                ))}
                {lowStock.length === 0 && <TableRow><TableCell colSpan={4} className="text-center text-[var(--color-text-secondary)] text-sm">{t('dashboard.noLowStock')}</TableCell></TableRow>}
              </Table>
            </Card>
          </div>
        </>
      )}
    </div>
  )
}
