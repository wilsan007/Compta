import { useEffect, useState } from 'react'
import { Card, StatCard, PageHeader, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable } from '@/components/ui'
import { getFinancialDashboard } from '@/lib/queries'
import { formatCurrency } from '@/lib/utils'
import { TrendingUp, TrendingDown, Wallet, FileText, ArrowRight, Activity } from 'lucide-react'
import { Link } from 'react-router-dom'

interface FinancialData {
  revenue: number
  expenses: number
  margin: number
  marginPct: number
  cashPosition: number
  pendingEntries: number
  totalEntries: number
  invoiceCount: number
  supplierInvoiceCount: number
}

export function FinancialDashboardPage() {
  const [data, setData] = useState<FinancialData | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => { load() }, [])

  async function load() {
    try {
      const d = await getFinancialDashboard()
      setData(d)
    } catch (err) {
      console.error('Error loading financial dashboard:', err)
    } finally {
      setLoading(false)
    }
  }

  if (loading) return <SkeletonTable rows={6} />
  if (!data) return <EmptyState title="Aucune donnée" description="Les données financières ne sont pas disponibles." />

  return (
    <div>
      <Breadcrumb items={[{ label: 'Reporting', path: '/reporting/financial' }, { label: 'Tableau de bord financier' }]} />
      <PageHeader title="Tableau de bord financier" subtitle="KPIs financiers en temps réel" />

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
        <StatCard label="Chiffre d'affaires" value={formatCurrency(data.revenue)} icon={<TrendingUp className="w-5 h-5" />} color="success" />
        <StatCard label="Dépenses" value={formatCurrency(data.expenses)} icon={<TrendingDown className="w-5 h-5" />} color="danger" />
        <StatCard label="Marge nette" value={formatCurrency(data.margin)} trend={{ value: `${data.marginPct.toFixed(1)}%`, positive: data.margin >= 0 }} icon={<Activity className="w-5 h-5" />} color="primary" />
        <StatCard label="Position trésorerie" value={formatCurrency(data.cashPosition)} icon={<Wallet className="w-5 h-5" />} color="primary" />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <Card>
          <h3 className="text-lg font-semibold mb-4">Indicateurs comptables</h3>
          <Table headers={['Indicateur', 'Valeur']}>
            <tbody>
              <TableRow>
                <TableCell>Écritures en attente</TableCell>
                <TableCell className="text-right font-medium">{data.pendingEntries}</TableCell>
              </TableRow>
              <TableRow>
                <TableCell>Total écritures</TableCell>
                <TableCell className="text-right font-medium">{data.totalEntries}</TableCell>
              </TableRow>
              <TableRow>
                <TableCell>Factures clients payées</TableCell>
                <TableCell className="text-right font-medium">{data.invoiceCount}</TableCell>
              </TableRow>
              <TableRow>
                <TableCell>Factures fournisseurs payées</TableCell>
                <TableCell className="text-right font-medium">{data.supplierInvoiceCount}</TableCell>
              </TableRow>
            </tbody>
          </Table>
        </Card>

        <Card>
          <h3 className="text-lg font-semibold mb-4">Accès rapides</h3>
          <div className="space-y-2">
            <Link to="/accounting/states/general-ledger" className="flex items-center justify-between p-3 rounded-lg hover:bg-gray-50 transition-colors">
              <span className="flex items-center gap-2"><FileText className="w-4 h-4" /> Grand-livre</span>
              <ArrowRight className="w-4 h-4 text-gray-400" />
            </Link>
            <Link to="/accounting/states/trial-balance" className="flex items-center justify-between p-3 rounded-lg hover:bg-gray-50 transition-colors">
              <span className="flex items-center gap-2"><FileText className="w-4 h-4" /> Balance</span>
              <ArrowRight className="w-4 h-4 text-gray-400" />
            </Link>
            <Link to="/reporting/budget" className="flex items-center justify-between p-3 rounded-lg hover:bg-gray-50 transition-colors">
              <span className="flex items-center gap-2"><FileText className="w-4 h-4" /> Suivi budgétaire</span>
              <ArrowRight className="w-4 h-4 text-gray-400" />
            </Link>
            <Link to="/treasury/dashboard" className="flex items-center justify-between p-3 rounded-lg hover:bg-gray-50 transition-colors">
              <span className="flex items-center gap-2"><Wallet className="w-4 h-4" /> Trésorerie</span>
              <ArrowRight className="w-4 h-4 text-gray-400" />
            </Link>
          </div>
        </Card>
      </div>
    </div>
  )
}
