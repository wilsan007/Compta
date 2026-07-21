import { useEffect, useState } from 'react'
import { Card, StatCard, PageHeader, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable } from '@/components/ui'
import { getFinancialDashboard } from '@/lib/queries'
import { formatCurrency } from '@/lib/utils'
import { TrendingUp, TrendingDown, Wallet, FileText, ArrowRight, Activity } from 'lucide-react'
import { Link } from 'react-router-dom'
import { useTranslation } from 'react-i18next'

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
  const { t } = useTranslation('accounting')
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
  if (!data) return <EmptyState title={t('financialDashboard.noData')} description={t('financialDashboard.noDataDesc')} />

  return (
    <div>
      <Breadcrumb items={[{ label: t('financialDashboard.breadcrumb'), path: '/reporting/financial' }, { label: t('financialDashboard.breadcrumb2') }]} />
      <PageHeader title={t('financialDashboard.title')} subtitle={t('financialDashboard.subtitle')} />

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
        <StatCard label={t('financialDashboard.revenue')} value={formatCurrency(data.revenue)} icon={<TrendingUp className="w-5 h-5" />} color="success" />
        <StatCard label={t('financialDashboard.expenses')} value={formatCurrency(data.expenses)} icon={<TrendingDown className="w-5 h-5" />} color="danger" />
        <StatCard label={t('financialDashboard.netMargin')} value={formatCurrency(data.margin)} trend={{ value: `${data.marginPct.toFixed(1)}%`, positive: data.margin >= 0 }} icon={<Activity className="w-5 h-5" />} color="primary" />
        <StatCard label={t('financialDashboard.cashPosition')} value={formatCurrency(data.cashPosition)} icon={<Wallet className="w-5 h-5" />} color="primary" />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <Card>
          <h3 className="text-lg font-semibold mb-4">{t('financialDashboard.accountingIndicators')}</h3>
          <Table headers={[t('financialDashboard.indicator'), t('financialDashboard.value')]}>
            <tbody>
              <TableRow>
                <TableCell>{t('financialDashboard.pendingEntries')}</TableCell>
                <TableCell className="text-right font-medium">{data.pendingEntries}</TableCell>
              </TableRow>
              <TableRow>
                <TableCell>{t('financialDashboard.totalEntries')}</TableCell>
                <TableCell className="text-right font-medium">{data.totalEntries}</TableCell>
              </TableRow>
              <TableRow>
                <TableCell>{t('financialDashboard.paidCustomerInvoices')}</TableCell>
                <TableCell className="text-right font-medium">{data.invoiceCount}</TableCell>
              </TableRow>
              <TableRow>
                <TableCell>{t('financialDashboard.paidSupplierInvoices')}</TableCell>
                <TableCell className="text-right font-medium">{data.supplierInvoiceCount}</TableCell>
              </TableRow>
            </tbody>
          </Table>
        </Card>

        <Card>
          <h3 className="text-lg font-semibold mb-4">{t('financialDashboard.quickAccess')}</h3>
          <div className="space-y-2">
            <Link to="/accounting/states/general-ledger" className="flex items-center justify-between p-3 rounded-lg hover:bg-gray-50 transition-colors">
              <span className="flex items-center gap-2"><FileText className="w-4 h-4" /> {t('financialDashboard.generalLedger')}</span>
              <ArrowRight className="w-4 h-4 text-gray-400" />
            </Link>
            <Link to="/accounting/states/trial-balance" className="flex items-center justify-between p-3 rounded-lg hover:bg-gray-50 transition-colors">
              <span className="flex items-center gap-2"><FileText className="w-4 h-4" /> {t('financialDashboard.trialBalance')}</span>
              <ArrowRight className="w-4 h-4 text-gray-400" />
            </Link>
            <Link to="/reporting/budget" className="flex items-center justify-between p-3 rounded-lg hover:bg-gray-50 transition-colors">
              <span className="flex items-center gap-2"><FileText className="w-4 h-4" /> {t('financialDashboard.budgetTracking')}</span>
              <ArrowRight className="w-4 h-4 text-gray-400" />
            </Link>
            <Link to="/treasury/dashboard" className="flex items-center justify-between p-3 rounded-lg hover:bg-gray-50 transition-colors">
              <span className="flex items-center gap-2"><Wallet className="w-4 h-4" /> {t('financialDashboard.treasury')}</span>
              <ArrowRight className="w-4 h-4 text-gray-400" />
            </Link>
          </div>
        </Card>
      </div>
    </div>
  )
}
