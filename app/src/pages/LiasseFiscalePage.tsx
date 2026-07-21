import { useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, EmptyState, AutoBreadcrumb, Select } from '@/components/ui'
import { getFiscalYears, getBalanceSheet, getTrialBalance } from '@/lib/queries'
import { formatCurrency } from '@/lib/utils'
import { FileText, FileBarChart } from 'lucide-react'
import type { FiscalYear } from '@/types'

export function LiasseFiscalePage() {
  const { t } = useTranslation('features')
  const [fiscalYears, setFiscalYears] = useState<FiscalYear[]>([])
  const [selectedYear, setSelectedYear] = useState('')
  const [loading, setLoading] = useState(true)
  const [generating, setGenerating] = useState(false)
  const [data, setData] = useState<{ assets: any[]; liabilities: any[]; equity: any[] } | null>(null)
  const [trialBalance, setTrialBalance] = useState<any[]>([])

  useEffect(() => {
    loadFiscalYears()
  }, [])

  async function loadFiscalYears() {
    try {
      const years = await getFiscalYears()
      setFiscalYears(years || [])
    } catch (err) {
      console.error('Error loading fiscal years:', err)
    } finally {
      setLoading(false)
    }
  }

  async function handleGenerate() {
    if (!selectedYear) return
    setGenerating(true)
    try {
      const [bs, tb] = await Promise.all([
        getBalanceSheet(),
        getTrialBalance(),
      ])
      setData(bs)
      setTrialBalance(tb || [])
    } catch (err) {
      console.error('Error generating liasse:', err)
    } finally {
      setGenerating(false)
    }
  }

  const totalAssets = (data?.assets || []).reduce((s, a) => s + (a.debit - a.credit), 0)
  const totalLiabilities = (data?.liabilities || []).reduce((s, a) => s + (a.credit - a.debit), 0)
  const totalEquity = (data?.equity || []).reduce((s, a) => s + (a.credit - a.debit), 0)

  // Income statement from trial balance (class 6 & 7)
  const revenueAccounts = trialBalance.filter((a) => a.code?.startsWith('7'))
  const expenseAccounts = trialBalance.filter((a) => a.code?.startsWith('6'))
  const totalRevenue = revenueAccounts.reduce((s, a) => s + (a.credit - a.debit), 0)
  const totalExpenses = expenseAccounts.reduce((s, a) => s + (a.debit - a.credit), 0)
  const netResult = totalRevenue - totalExpenses

  return (
    <div className="animate-fade-in">
      <AutoBreadcrumb />
      <PageHeader title={t('liasseFiscale.title')} subtitle={t('liasseFiscale.subtitle')} />

      <Card className="mb-4">
        <div className="p-4">
          <p className="text-sm text-[var(--color-text-secondary)] mb-4">{t('liasseFiscale.intro')}</p>
          <div className="flex flex-wrap gap-3 items-end">
            <div className="w-64">
              <Select
                label={t('liasseFiscale.fiscalYear')}
                value={selectedYear}
                onChange={(e) => setSelectedYear(e.target.value)}
                options={[
                  { value: '', label: t('liasseFiscale.selectYear') },
                  ...fiscalYears.map((y) => ({ value: y.code, label: `${y.code} (${y.start_date?.substring(0, 10)} → ${y.end_date?.substring(0, 10)})` })),
                ]}
              />
            </div>
            <Button onClick={handleGenerate} disabled={!selectedYear || generating}>
              <FileText className="w-4 h-4" /> {t('liasseFiscale.generate')}
            </Button>
          </div>
        </div>
      </Card>

      {loading ? (
        <Card><div className="p-8 text-center text-[var(--color-text-secondary)]">...</div></Card>
      ) : !data ? (
        <EmptyState
          icon={<FileBarChart className="w-8 h-8" />}
          title={t('liasseFiscale.noData')}
          description={t('liasseFiscale.noDataDesc')}
        />
      ) : (
        <div className="space-y-4">
          {/* Balance Sheet */}
          <Card>
            <div className="p-4">
              <h3 className="text-sm font-semibold mb-4">{t('liasseFiscale.balanceSheet')}</h3>
              <div className="grid md:grid-cols-2 gap-6">
                {/* Assets */}
                <div>
                  <h4 className="text-xs font-semibold uppercase text-[var(--color-text-secondary)] mb-2">{t('liasseFiscale.assets')}</h4>
                  <div className="space-y-1">
                    {data.assets.map((a) => (
                      <div key={a.code} className="flex justify-between text-sm py-1">
                        <span className="text-[var(--color-text-secondary)]">{a.code} — {a.name}</span>
                        <span className="font-mono">{formatCurrency(a.debit - a.credit)}</span>
                      </div>
                    ))}
                    <div className="flex justify-between font-bold pt-2 border-t border-[var(--color-border)]">
                      <span>{t('liasseFiscale.totalAssets')}</span>
                      <span className="font-mono">{formatCurrency(totalAssets)}</span>
                    </div>
                  </div>
                </div>
                {/* Liabilities + Equity */}
                <div>
                  <h4 className="text-xs font-semibold uppercase text-[var(--color-text-secondary)] mb-2">{t('liasseFiscale.liabilities')}</h4>
                  <div className="space-y-1">
                    {data.equity.map((a) => (
                      <div key={a.code} className="flex justify-between text-sm py-1">
                        <span className="text-[var(--color-text-secondary)]">{a.code} — {a.name}</span>
                        <span className="font-mono">{formatCurrency(a.credit - a.debit)}</span>
                      </div>
                    ))}
                    {data.liabilities.map((a) => (
                      <div key={a.code} className="flex justify-between text-sm py-1">
                        <span className="text-[var(--color-text-secondary)]">{a.code} — {a.name}</span>
                        <span className="font-mono">{formatCurrency(a.credit - a.debit)}</span>
                      </div>
                    ))}
                    <div className="flex justify-between font-bold pt-2 border-t border-[var(--color-border)]">
                      <span>{t('liasseFiscale.totalLiabilities')}</span>
                      <span className="font-mono">{formatCurrency(totalLiabilities + totalEquity)}</span>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </Card>

          {/* Income Statement */}
          <Card>
            <div className="p-4">
              <h3 className="text-sm font-semibold mb-4">{t('liasseFiscale.incomeStatement')}</h3>
              <div className="grid md:grid-cols-2 gap-6">
                <div>
                  <h4 className="text-xs font-semibold uppercase text-[var(--color-text-secondary)] mb-2">{t('liasseFiscale.revenue')}</h4>
                  <div className="space-y-1">
                    {revenueAccounts.map((a) => (
                      <div key={a.code} className="flex justify-between text-sm py-1">
                        <span className="text-[var(--color-text-secondary)]">{a.code} — {a.name}</span>
                        <span className="font-mono">{formatCurrency(a.credit - a.debit)}</span>
                      </div>
                    ))}
                    <div className="flex justify-between font-bold pt-2 border-t border-[var(--color-border)]">
                      <span>{t('liasseFiscale.revenue')}</span>
                      <span className="font-mono">{formatCurrency(totalRevenue)}</span>
                    </div>
                  </div>
                </div>
                <div>
                  <h4 className="text-xs font-semibold uppercase text-[var(--color-text-secondary)] mb-2">{t('liasseFiscale.expenses')}</h4>
                  <div className="space-y-1">
                    {expenseAccounts.map((a) => (
                      <div key={a.code} className="flex justify-between text-sm py-1">
                        <span className="text-[var(--color-text-secondary)]">{a.code} — {a.name}</span>
                        <span className="font-mono">{formatCurrency(a.debit - a.credit)}</span>
                      </div>
                    ))}
                    <div className="flex justify-between font-bold pt-2 border-t border-[var(--color-border)]">
                      <span>{t('liasseFiscale.expenses')}</span>
                      <span className="font-mono">{formatCurrency(totalExpenses)}</span>
                    </div>
                  </div>
                </div>
              </div>
              <div className="mt-4 p-4 rounded-lg bg-[var(--color-primary)]/5 border border-[var(--color-primary)]/20">
                <div className="flex justify-between text-lg font-bold">
                  <span>{t('liasseFiscale.netResult')}</span>
                  <span className="font-mono">{formatCurrency(netResult)}</span>
                </div>
              </div>
            </div>
          </Card>
        </div>
      )}
    </div>
  )
}
