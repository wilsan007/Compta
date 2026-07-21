import { useEffect, useState } from 'react'
import { Card, PageHeader, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Button, Select } from '@/components/ui'
import { formatCurrency } from '@/lib/utils'
import { getInvoices, getPurchaseInvoices, getBankAccounts, getJournalEntries, getCustomers, getSuppliers, getProducts } from '@/lib/queries'
import { Download, FileSpreadsheet, BarChart3, TrendingUp, TrendingDown } from 'lucide-react'
import { useTranslation } from 'react-i18next'

interface ReportData {
  totalRevenue: number
  totalExpenses: number
  grossMargin: number
  customerCount: number
  supplierCount: number
  productCount: number
  invoiceCount: number
  purchaseInvoiceCount: number
  journalEntryCount: number
  bankBalance: number
}

export function BIReportingPage() {
  const { t } = useTranslation('reports')
  const [data, setData] = useState<ReportData | null>(null)
  const [loading, setLoading] = useState(true)
  const [reportType, setReportType] = useState('summary')

  useEffect(() => { load() }, [])

  async function load() {
    try {
      const [inv, pur, banks, journals, custs, sups, prods] = await Promise.all([
        getInvoices(), getPurchaseInvoices(), getBankAccounts(), getJournalEntries(),
        getCustomers(), getSuppliers(), getProducts(),
      ])
      const totalRevenue = (inv || []).filter((i: any) => i.status === 'paid').reduce((s: number, i: any) => s + Number(i.total), 0)
      const totalExpenses = (pur || []).filter((i: any) => i.status === 'paid').reduce((s: number, i: any) => s + Number(i.total), 0)
      const bankBalance = (banks || []).reduce((s: number, a: any) => s + Number(a.balance), 0)
      setData({
        totalRevenue, totalExpenses, grossMargin: totalRevenue - totalExpenses,
        customerCount: (custs || []).length, supplierCount: (sups || []).length,
        productCount: (prods || []).length, invoiceCount: (inv || []).length,
        purchaseInvoiceCount: (pur || []).length, journalEntryCount: (journals || []).length,
        bankBalance,
      })
    } catch (err) {
      console.error('Error loading BI report:', err)
    } finally {
      setLoading(false)
    }
  }

  function exportData() {
    if (!data) return
    const headers = [t('bi.indicator'), t('bi.value')]
    const rows: [string, string][] = [
      [t('bi.revenue'), data.totalRevenue.toFixed(2)],
      [t('bi.expenses'), data.totalExpenses.toFixed(2)],
      [t('bi.grossMargin'), data.grossMargin.toFixed(2)],
      [t('bi.bankBalance'), data.bankBalance.toFixed(2)],
      [t('bi.customers'), String(data.customerCount)],
      [t('bi.suppliers'), String(data.supplierCount)],
      [t('bi.products'), String(data.productCount)],
      [t('bi.customerInvoices'), String(data.invoiceCount)],
      [t('bi.supplierInvoices'), String(data.purchaseInvoiceCount)],
      [t('bi.journalEntries'), String(data.journalEntryCount)],
    ]
    const csv = [headers, ...rows].map(r => r.join(';')).join('\n')
    const blob = new Blob([csv], { type: 'text/csv' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `rapport-bi-${reportType}.csv`
    a.click()
  }

  if (loading) return <SkeletonTable rows={6} />
  if (!data) return <EmptyState title={t('bi.noData')} description={t('bi.noDataDesc')} />

  return (
    <div>
      <Breadcrumb items={[{ label: t('title'), path: '/reporting/bi' }, { label: t('bi.title') }]} />
      <PageHeader title={t('bi.title')} subtitle={t('bi.subtitle')} action={
        <div className="flex items-center gap-2">
          <Select value={reportType} onChange={(e) => setReportType(e.target.value)} options={[
            { value: 'summary', label: t('bi.reportTypes.summary') },
            { value: 'sales', label: t('bi.reportTypes.sales') },
            { value: 'purchases', label: t('bi.reportTypes.purchases') },
            { value: 'financial', label: t('bi.reportTypes.financial') },
          ]} />
          <Button variant="secondary" onClick={exportData}><Download className="w-4 h-4 mr-2" /> {t('bi.exportCsv')}</Button>
        </div>
      } />

      <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
        <Card>
          <div className="flex items-center gap-3">
            <div className="p-2 rounded-lg bg-green-50"><TrendingUp className="w-5 h-5 text-green-600" /></div>
            <div>
              <p className="text-sm text-gray-500">{t('bi.revenue')}</p>
              <p className="text-xl font-bold">{formatCurrency(data.totalRevenue)}</p>
            </div>
          </div>
        </Card>
        <Card>
          <div className="flex items-center gap-3">
            <div className="p-2 rounded-lg bg-red-50"><TrendingDown className="w-5 h-5 text-red-600" /></div>
            <div>
              <p className="text-sm text-gray-500">{t('bi.expenses')}</p>
              <p className="text-xl font-bold">{formatCurrency(data.totalExpenses)}</p>
            </div>
          </div>
        </Card>
        <Card>
          <div className="flex items-center gap-3">
            <div className="p-2 rounded-lg bg-blue-50"><BarChart3 className="w-5 h-5 text-blue-600" /></div>
            <div>
              <p className="text-sm text-gray-500">{t('bi.grossMargin')}</p>
              <p className="text-xl font-bold">{formatCurrency(data.grossMargin)}</p>
            </div>
          </div>
        </Card>
      </div>

      <Card>
        <h3 className="text-lg font-semibold mb-4 flex items-center gap-2"><FileSpreadsheet className="w-5 h-5" /> {t('bi.detailedData')}</h3>
        <Table headers={[t('bi.indicator'), t('bi.value')]}>
          <tbody>
            <TableRow><TableCell>{t('bi.customers')}</TableCell><TableCell className="text-right font-medium">{data.customerCount}</TableCell></TableRow>
            <TableRow><TableCell>{t('bi.suppliers')}</TableCell><TableCell className="text-right font-medium">{data.supplierCount}</TableCell></TableRow>
            <TableRow><TableCell>{t('bi.products')}</TableCell><TableCell className="text-right font-medium">{data.productCount}</TableCell></TableRow>
            <TableRow><TableCell>{t('bi.customerInvoices')}</TableCell><TableCell className="text-right font-medium">{data.invoiceCount}</TableCell></TableRow>
            <TableRow><TableCell>{t('bi.supplierInvoices')}</TableCell><TableCell className="text-right font-medium">{data.purchaseInvoiceCount}</TableCell></TableRow>
            <TableRow><TableCell>{t('bi.journalEntries')}</TableCell><TableCell className="text-right font-medium">{data.journalEntryCount}</TableCell></TableRow>
            <TableRow><TableCell>{t('bi.bankBalance')}</TableCell><TableCell className="text-right font-medium">{formatCurrency(data.bankBalance)}</TableCell></TableRow>
          </tbody>
        </Table>
      </Card>
    </div>
  )
}
