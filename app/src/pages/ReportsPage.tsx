import { useTranslation } from 'react-i18next'
import { useState, useEffect, useMemo } from 'react'
import { useNavigate } from 'react-router-dom'
import { Card, PageHeader, Button, Table, TableRow, TableCell, StatCard, Breadcrumb, Select } from '@/components/ui'
import { useLocale } from '@/hooks/useLocale'
import { TrendingUp, TrendingDown, DollarSign, FileText } from 'lucide-react'
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, LineChart, Line, Legend } from 'recharts'
import { getFiscalYears, getIncomeStatement, getIncomeStatementMonthly, type IncomeStatementRow, type IncomeStatementMonth } from '@/lib/queries/accounting'
import { generateAccountingAnnex } from '@/lib/queries/businessFunctions'
import { useToast } from '@/lib/toast'
import type { FiscalYear } from '@/types'

// Nombre de postes de charges affichés individuellement dans le graphique ; le reste
// est regroupé en « Autres dépenses ».
const MAX_EXPENSE_BARS = 6

export function ReportsPage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const navigate = useNavigate()
  const { formatCurrency, locale } = useLocale()
  const [years, setYears] = useState<FiscalYear[]>([])
  const [selectedYear, setSelectedYear] = useState('')
  const [generating, setGenerating] = useState(false)
  const [rows, setRows] = useState<IncomeStatementRow[]>([])
  const [months, setMonths] = useState<IncomeStatementMonth[]>([])
  const [loading, setLoading] = useState(false)

  useEffect(() => {
    getFiscalYears().then((fy) => {
      setYears(fy || [])
      const open = (fy || []).find((y) => y.status === 'open')
      if (open) setSelectedYear(open.id)
      else if (fy && fy.length > 0) setSelectedYear(fy[0].id)
    }).catch((err: any) => {
      toast('error', tCommon('common.error'), err?.message || tCommon('common.error'))
    })
  // oxlint-disable-next-line react-hooks/exhaustive-deps -- chargement au montage uniquement
  }, [])

  // AUD-D07 : chiffres lus dans la comptabilité (écritures validées de l'exercice choisi)
  useEffect(() => {
    if (!selectedYear) return
    let cancelled = false
    setLoading(true)
    Promise.all([getIncomeStatement(selectedYear), getIncomeStatementMonthly(selectedYear)])
      .then(([statement, monthly]) => {
        if (cancelled) return
        setRows(statement)
        setMonths(monthly)
      })
      .catch((err: any) => {
        if (cancelled) return
        setRows([])
        setMonths([])
        toast('error', tCommon('common.error'), err?.message || tCommon('common.error'))
      })
      .finally(() => { if (!cancelled) setLoading(false) })
    return () => { cancelled = true }
  // oxlint-disable-next-line react-hooks/exhaustive-deps -- rechargement voulu au seul changement d'exercice
  }, [selectedYear])

  async function handleGenerateAnnex() {
    if (!selectedYear) return
    setGenerating(true)
    try {
      await generateAccountingAnnex(selectedYear)
      toast('success', tCommon('common.success'), t('financialReports.annexGenerated'))
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    } finally {
      setGenerating(false)
    }
  }

  const totalRevenue = useMemo(() => rows.filter((r) => r.account_type === 'income').reduce((s, r) => s + r.amount, 0), [rows])
  const totalExpenses = useMemo(() => rows.filter((r) => r.account_type === 'expense').reduce((s, r) => s + r.amount, 0), [rows])
  const netProfit = totalRevenue - totalExpenses

  const plData = useMemo(() => {
    const expenses = rows.filter((r) => r.account_type === 'expense').sort((a, b) => b.amount - a.amount)
    const shown = expenses.slice(0, MAX_EXPENSE_BARS)
    const rest = expenses.slice(MAX_EXPENSE_BARS).reduce((s, r) => s + r.amount, 0)
    return [
      { category: t('financialReports.revenues'), amount: totalRevenue },
      ...shown.map((r) => ({ category: `${r.account_code} ${r.account_name}`, amount: -r.amount })),
      ...(rest !== 0 ? [{ category: t('financialReports.otherExpenses'), amount: -rest }] : []),
    ]
  }, [rows, totalRevenue, t])

  const monthlyTrend = useMemo(() => {
    const monthFormat = new Intl.DateTimeFormat(locale, { month: 'short' })
    return months.map((m) => ({
      month: monthFormat.format(new Date(`${m.month}T00:00:00`)),
      revenus: m.revenue,
      depenses: m.expense,
      profit: m.result,
    }))
  }, [months, locale])

  const hasData = rows.length > 0

  return (
    <div className="animate-fade-in">
      <Breadcrumb items={[{ label: t('home.reports') }]} />
      <PageHeader
        title={t('financialReports.title')}
        subtitle={t('financialReports.subtitle')}
        action={
          <div className="flex items-center gap-2">
            <Select
              value={selectedYear}
              onChange={(e) => setSelectedYear(e.target.value)}
              options={years.map((y) => ({ value: y.id, label: y.code }))}
            />
            <Button onClick={handleGenerateAnnex} disabled={generating || !selectedYear}>
              {generating ? tCommon('common.loading') : t('financialReports.generateAnnex')}
            </Button>
          </div>
        }
      />

      <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
        <StatCard label={t('financialReports.totalRevenue')} value={formatCurrency(totalRevenue)} icon={<TrendingUp className="w-5 h-5" />} color="success" />
        <StatCard label={t('financialReports.totalExpenses')} value={formatCurrency(totalExpenses)} icon={<TrendingDown className="w-5 h-5" />} color="danger" />
        <StatCard label={t('financialReports.netProfit')} value={formatCurrency(netProfit)} icon={<DollarSign className="w-5 h-5" />} color="primary" />
      </div>

      {loading ? (
        <Card><p className="p-6 text-sm text-[var(--color-text-secondary)]">{tCommon('common.loading')}</p></Card>
      ) : !hasData ? (
        <Card><p className="p-6 text-sm text-[var(--color-text-secondary)]">{t('financialReports.noData')}</p></Card>
      ) : (
        <>
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-4 mb-6">
            <Card title={t('financialReports.incomeStatement')} subtitle={t('financialReports.byCategory')}>
              <ResponsiveContainer width="100%" height={300}>
                <BarChart data={plData} layout="vertical">
                  <CartesianGrid strokeDasharray="3 3" stroke="var(--color-border)" />
                  <XAxis type="number" stroke="var(--color-text-secondary)" style={{ fontSize: 12 }} tickFormatter={(v) => `${v / 1000}k`} />
                  <YAxis type="category" dataKey="category" stroke="var(--color-text-secondary)" style={{ fontSize: 11 }} width={140} />
                  <Tooltip formatter={(value: number) => formatCurrency(value)} contentStyle={{ background: 'var(--color-surface)', border: '1px solid var(--color-border)', borderRadius: '8px', fontSize: 12 }} />
                  <Bar dataKey="amount" fill="var(--color-primary)" radius={[0, 4, 4, 0]} />
                </BarChart>
              </ResponsiveContainer>
            </Card>

            <Card title={t('financialReports.monthlyTrend')} subtitle={t('financialReports.revenuesExpensesProfit')}>
              <ResponsiveContainer width="100%" height={300}>
                <LineChart data={monthlyTrend}>
                  <CartesianGrid strokeDasharray="3 3" stroke="var(--color-border)" />
                  <XAxis dataKey="month" stroke="var(--color-text-secondary)" style={{ fontSize: 12 }} />
                  <YAxis stroke="var(--color-text-secondary)" style={{ fontSize: 12 }} tickFormatter={(v) => `${v / 1000}k`} />
                  <Tooltip formatter={(value: number) => formatCurrency(value)} contentStyle={{ background: 'var(--color-surface)', border: '1px solid var(--color-border)', borderRadius: '8px', fontSize: 12 }} />
                  <Legend wrapperStyle={{ fontSize: 12 }} />
                  <Line type="monotone" dataKey="revenus" stroke="var(--color-primary)" strokeWidth={2} name={t('financialReports.legendRevenues')} />
                  <Line type="monotone" dataKey="depenses" stroke="var(--color-danger)" strokeWidth={2} name={t('financialReports.legendExpenses')} />
                  <Line type="monotone" dataKey="profit" stroke="var(--color-success)" strokeWidth={2} name={t('financialReports.legendProfit')} />
                </LineChart>
              </ResponsiveContainer>
            </Card>
          </div>

          <Card title={t('financialReports.incomeDetail')}>
            <Table headers={[t('financialReports.category'), t('financialReports.amount'), t('financialReports.percentTotal')]}>
              {rows.map((row) => (
                <TableRow key={row.account_code}>
                  <TableCell className="font-medium">{row.account_code} {row.account_name}</TableCell>
                  <TableCell className={row.account_type === 'expense' ? 'text-[var(--color-danger)] text-right' : 'text-[var(--color-success)] text-right'}>
                    {formatCurrency(row.amount)}
                  </TableCell>
                  <TableCell className="text-[var(--color-text-secondary)]">
                    {totalRevenue !== 0 ? `${((row.amount / totalRevenue) * 100).toFixed(1)}%` : '—'}
                  </TableCell>
                </TableRow>
              ))}
              <TableRow key="total">
                <TableCell className="font-bold">{t('financialReports.netProfit')}</TableCell>
                <TableCell className="font-bold text-[var(--color-primary)] text-right">{formatCurrency(netProfit)}</TableCell>
                <TableCell className="text-[var(--color-text-secondary)]">—</TableCell>
              </TableRow>
            </Table>
          </Card>
        </>
      )}

      <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mt-6">
        {[
          { label: t('financialReports.balanceSheet'), icon: FileText, path: '/reports/balance-sheet' },
          { label: t('financialReports.trialBalance'), icon: FileText, path: '/reports/trial-balance' },
          { label: t('financialReports.cashFlow'), icon: FileText, path: '/reports/cash-flow' },
          { label: t('financialReports.vat'), icon: FileText, path: '/reports/vat' },
        ].map((r) => (
          <button
            key={r.path}
            type="button"
            onClick={() => navigate(r.path)}
            className="card p-4 text-left hover:shadow-md transition-shadow"
          >
            <div className="flex items-center gap-3">
              <div className="w-10 h-10 rounded-lg bg-[rgba(0,102,204,0.1)] flex items-center justify-center">
                <r.icon className="w-5 h-5 text-[var(--color-primary)]" aria-hidden="true" />
              </div>
              <span className="text-sm font-medium text-[var(--color-text)]">{r.label}</span>
            </div>
          </button>
        ))}
      </div>
    </div>
  )
}
