import { useEffect, useState } from 'react'
import { Card, StatCard, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState } from '@/components/ui'
import { getDashboardStats, getInvoices, getBankAccounts, getDashboardChartData, getRecentActivity } from '@/lib/queries'
import { formatCurrency, formatDate, cn } from '@/lib/utils'
import { useToast } from '@/lib/toast'
import {
  Wallet, TrendingUp, AlertCircle, ArrowDownCircle,
  Users, Package, Banknote, FileText, Clock,
  CheckCircle, ArrowUpRight, Activity,
  Sparkles, ChevronRight, Zap,
} from 'lucide-react'
import {
  XAxis, YAxis, CartesianGrid, Tooltip,
  ResponsiveContainer, PieChart, Pie, Cell, AreaChart, Area,
} from 'recharts'
import { Link } from 'react-router-dom'
import { useTranslation } from 'react-i18next'

interface Stats {
  totalRevenue: number
  outstandingInvoice: number
  outstandingBills: number
  bankBalance: number
  totalDebtors: number
  totalCreditors: number
  invoiceCount: number
  billCount: number
}

interface ActivityItem {
  id: string
  type: 'invoice' | 'payment' | 'customer' | 'supplier' | 'bank'
  icon: string
  title: string
  description: string
  time: string
  color: string
}

const iconMap: Record<string, React.ComponentType<{ className?: string }>> = {
  FileText,
  CheckCircle,
  Users,
  Banknote,
  Package,
  AlertCircle,
}

export function DashboardPage() {
  const { t } = useTranslation('common')
  const [stats, setStats] = useState<Stats | null>(null)
  const [recentInvoices, setRecentInvoices] = useState<any[]>([])
  const [bankAccounts, setBankAccounts] = useState<any[]>([])
  const [chartData, setChartData] = useState<{ monthly: Array<{ month: string; revenus: number; depenses: number }>; cashFlow: Array<{ name: string; value: number; color: string }>; overdueCount: number; overdueTotal: number }>({ monthly: [], cashFlow: [], overdueCount: 0, overdueTotal: 0 })
  const [activities, setActivities] = useState<ActivityItem[]>([])
  const [loading, setLoading] = useState(true)
  const [animateKpis, setAnimateKpis] = useState(false)
  const { toast } = useToast()

  useEffect(() => {
    async function loadData() {
      try {
        const [s, invoices, accounts, chart, activity] = await Promise.all([
          getDashboardStats(),
          getInvoices(),
          getBankAccounts(),
          getDashboardChartData(),
          getRecentActivity(),
        ])
        setStats(s)
        setRecentInvoices((invoices || []).slice(0, 5))
        setBankAccounts(accounts || [])
        setChartData(chart)
        setActivities(activity)
      } catch (err) {
        console.error('Error loading dashboard:', err)
        toast('info', t('dashboard.demoDataTitle'), t('dashboard.demoDataDesc'))
      } finally {
        setLoading(false)
        setTimeout(() => setAnimateKpis(true), 100)
      }
    }
    loadData()
  }, [])

  const monthlyData = chartData.monthly.length > 0 ? chartData.monthly : []
  const cashFlowData = chartData.cashFlow

  const statusMap: Record<string, { variant: 'success' | 'warning' | 'danger' | 'neutral' | 'primary'; label: string }> = {
    draft: { variant: 'neutral', label: t('status.draft') },
    sent: { variant: 'primary', label: t('status.sent') },
    viewed: { variant: 'primary', label: t('status.viewed') },
    paid: { variant: 'success', label: t('status.paid') },
    overdue: { variant: 'danger', label: t('status.overdue') },
    cancelled: { variant: 'neutral', label: t('status.cancelled') },
  }

  if (loading) {
    return (
      <div>
        <PageHeader title={t('dashboard.title')} subtitle={t('dashboard.subtitle')} />
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
          {[1, 2, 3, 4].map((i) => (
            <div key={i} className="card p-6 animate-pulse">
              <div className="h-4 bg-[var(--color-neutral-100)] rounded w-1/2 mb-3"></div>
              <div className="h-8 bg-[var(--color-neutral-100)] rounded w-3/4"></div>
            </div>
          ))}
        </div>
      </div>
    )
  }

  return (
    <div className="animate-fade-in">
      <PageHeader
        title={t('dashboard.title')}
        subtitle={t('dashboard.subtitle')}
        action={
          <div className="flex flex-row items-center gap-2">
            <Button variant="secondary" onClick={() => toast('info', t('dashboard.exporting'), t('dashboard.exportingDesc'))}>
              <Activity className="w-4 h-4" /> {t('dashboard.export')}
            </Button>
            <Button variant="primary" onClick={() => toast('success', t('dashboard.invoiceCreated'), t('dashboard.invoiceCreatedDesc'))}>
              <FileText className="w-4 h-4" /> {t('dashboard.newInvoice')}
            </Button>
          </div>
        }
      />

      {/* KPI Cards with animation */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
        <div className={cn('transition-all duration-500', animateKpis ? 'opacity-100 translate-y-0' : 'opacity-0 translate-y-4')}>
          <StatCard
            label={t('dashboard.bankBalance')}
            value={formatCurrency(stats?.bankBalance || 0)}
            icon={<Wallet className="w-5 h-5" />}
            color="primary"
          />
        </div>
        <div className={cn('transition-all duration-500 delay-75', animateKpis ? 'opacity-100 translate-y-0' : 'opacity-0 translate-y-4')}>
          <StatCard
            label={t('dashboard.totalRevenue')}
            value={formatCurrency(stats?.totalRevenue || 0)}
            icon={<TrendingUp className="w-5 h-5" />}
            color="success"
          />
        </div>
        <div className={cn('transition-all duration-500 delay-150', animateKpis ? 'opacity-100 translate-y-0' : 'opacity-0 translate-y-4')}>
          <StatCard
            label={t('dashboard.outstandingInvoices')}
            value={formatCurrency(stats?.outstandingInvoice || 0)}
            icon={<AlertCircle className="w-5 h-5" />}
            color="warning"
          />
        </div>
        <div className={cn('transition-all duration-500 delay-200', animateKpis ? 'opacity-100 translate-y-0' : 'opacity-0 translate-y-4')}>
          <StatCard
            label={t('dashboard.outstandingBills')}
            value={formatCurrency(stats?.outstandingBills || 0)}
            icon={<ArrowDownCircle className="w-5 h-5" />}
            color="danger"
          />
        </div>
      </div>

      {/* Charts Row */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-4 mb-6">
        {/* Revenue vs Expenses - Area Chart */}
        <Card title={t('dashboard.revenueVsExpenses')} subtitle={`${new Date().getFullYear()} - ${t('dashboard.currentYear')}`} className="lg:col-span-2">
          <ResponsiveContainer width="100%" height={300}>
            <AreaChart data={monthlyData}>
              <defs>
                <linearGradient id="colorRevenus" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="var(--color-primary)" stopOpacity={0.3} />
                  <stop offset="95%" stopColor="var(--color-primary)" stopOpacity={0} />
                </linearGradient>
                <linearGradient id="colorDepenses" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="var(--color-neutral-400)" stopOpacity={0.3} />
                  <stop offset="95%" stopColor="var(--color-neutral-400)" stopOpacity={0} />
                </linearGradient>
              </defs>
              <CartesianGrid strokeDasharray="3 3" stroke="var(--color-border)" />
              <XAxis dataKey="month" stroke="var(--color-text-secondary)" style={{ fontSize: 12 }} />
              <YAxis stroke="var(--color-text-secondary)" style={{ fontSize: 12 }} />
              <Tooltip
                contentStyle={{
                  background: 'var(--color-surface)',
                  border: '1px solid var(--color-border)',
                  borderRadius: '8px',
                  fontSize: 12,
                }}
                formatter={(value: number) => formatCurrency(value)}
              />
              <Area type="monotone" dataKey="revenus" stroke="var(--color-primary)" strokeWidth={2} fill="url(#colorRevenus)" name={t('dashboard.revenue')} />
              <Area type="monotone" dataKey="depenses" stroke="var(--color-neutral-400)" strokeWidth={2} fill="url(#colorDepenses)" name={t('dashboard.expenses')} />
            </AreaChart>
          </ResponsiveContainer>
        </Card>

        {/* Cash Flow Pie */}
        <Card title={t('dashboard.cashFlow')} subtitle={t('dashboard.thisYear')}>
          <ResponsiveContainer width="100%" height={200}>
            <PieChart>
              <Pie data={cashFlowData} cx="50%" cy="50%" outerRadius={70} dataKey="value">
                {cashFlowData.map((entry, i) => (
                  <Cell key={i} fill={entry.color} />
                ))}
              </Pie>
              <Tooltip formatter={(value: number) => formatCurrency(value)} />
            </PieChart>
          </ResponsiveContainer>
          <div className="space-y-2 mt-2">
            {cashFlowData.map((item) => (
              <div key={item.name} className="flex items-center justify-between text-sm">
                <div className="flex items-center gap-2">
                  <div className="w-3 h-3 rounded-full" style={{ background: item.color }}></div>
                  <span className="text-[var(--color-text-secondary)]">{item.name}</span>
                </div>
                <span className="font-medium text-[var(--color-text)]">{formatCurrency(item.value)}</span>
              </div>
            ))}
          </div>
        </Card>
      </div>

      {/* Activity Feed + Recent Invoices */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-4 mb-6">
        {/* Activity Feed */}
        <Card
          title={t('dashboard.recentActivity')}
          subtitle={t('dashboard.lastActions')}
          className="lg:col-span-1"
          action={
            <div className="w-2 h-2 rounded-full bg-[var(--color-success)] animate-pulse"></div>
          }
        >
          <div className="space-y-1 -mx-2">
            {activities.length > 0 ? activities.map((item, i) => {
              const Icon = iconMap[item.icon] || FileText
              return (
                <div
                  key={item.id}
                  className={cn(
                    'flex items-start gap-3 px-2 py-2.5 rounded-lg hover:bg-[var(--color-neutral-50)] transition-colors cursor-pointer',
                    animateKpis && 'animate-fade-in-up'
                  )}
                  style={{ animationDelay: `${i * 50}ms` }}
                >
                  <div className={cn('w-8 h-8 rounded-lg bg-[var(--color-neutral-100)] flex items-center justify-center flex-shrink-0', item.color)}>
                    <Icon className="w-4 h-4" />
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium text-[var(--color-text)] truncate">{item.title}</p>
                    <p className="text-xs text-[var(--color-text-secondary)] truncate">{item.description}</p>
                    <p className="text-[10px] text-[var(--color-text-secondary)] mt-0.5 flex items-center gap-1">
                      <Clock className="w-2.5 h-2.5" /> {formatDate(item.time)}
                    </p>
                  </div>
                </div>
              )
            }) : (
              <EmptyState
                icon={<Activity className="w-8 h-8" />}
                title={t('dashboard.noActivity')}
                description={t('dashboard.noActivityDesc')}
              />
            )}
          </div>
        </Card>

        {/* Recent Invoices */}
        <Card
          title={t('dashboard.recentInvoices')}
          className="lg:col-span-2"
          action={<Link to="/sales/invoices"><Button variant="ghost" size="sm">{t('dashboard.seeAll')} <ChevronRight className="w-3 h-3" /></Button></Link>}
        >
          {recentInvoices.length > 0 ? (
            <Table headers={[t('dashboard.colNumber'), t('dashboard.colCustomer'), t('dashboard.colDate'), t('dashboard.colStatus'), t('dashboard.colAmount')]}>
              {recentInvoices.map((inv) => {
                const st = statusMap[inv.status] || statusMap.draft
                return (
                  <TableRow key={inv.id}>
                    <TableCell className="font-medium">{inv.number}</TableCell>
                    <TableCell>{inv.customer_name || 'N/A'}</TableCell>
                    <TableCell>{formatDate(inv.date)}</TableCell>
                    <TableCell><Badge variant={st.variant}>{st.label}</Badge></TableCell>
                    <TableCell className="font-medium text-right">{formatCurrency(Number(inv.total))}</TableCell>
                  </TableRow>
                )
              })}
            </Table>
          ) : (
            <EmptyState
              icon={<FileText className="w-8 h-8" />}
              title={t('dashboard.noInvoices')}
              description={t('dashboard.noInvoicesDesc')}
              action={<Link to="/sales/invoices"><Button variant="primary" size="sm">{t('dashboard.createInvoice')}</Button></Link>}
            />
          )}
        </Card>
      </div>

      {/* Bank Accounts + AI Insight */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-4 mb-6">
        <Card title={t('dashboard.bankAccounts')} className="lg:col-span-2">
          {bankAccounts.length > 0 ? (
            <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
              {bankAccounts.map((acc) => (
                <div key={acc.id} className="flex items-center justify-between p-4 rounded-xl bg-gradient-to-br from-[var(--color-neutral-50)] to-[var(--color-neutral-100)] border border-[var(--color-border)]">
                  <div className="flex items-center gap-3">
                    <div className="w-11 h-11 rounded-xl bg-gradient-to-br from-[var(--color-primary)] to-purple-600 flex items-center justify-center">
                      <Banknote className="w-5 h-5 text-white" />
                    </div>
                    <div>
                      <p className="text-sm font-medium text-[var(--color-text)]">{acc.name}</p>
                      <p className="text-xs text-[var(--color-text-secondary)]">{acc.bank_name || t('dashboard.bank')}</p>
                    </div>
                  </div>
                  <div className="text-right">
                    <p className="font-bold text-[var(--color-text)]">{formatCurrency(Number(acc.balance))}</p>
                    <p className="text-xs text-[var(--color-success)] flex items-center gap-0.5 justify-end">
                      <ArrowUpRight className="w-3 h-3" /> {acc.currency || 'EUR'}
                    </p>
                  </div>
                </div>
              ))}
            </div>
          ) : (
            <EmptyState
              icon={<Banknote className="w-8 h-8" />}
              title={t('dashboard.noBankAccounts')}
              description={t('dashboard.noBankAccountsDesc')}
              action={<Link to="/banking/accounts"><Button variant="primary" size="sm">{t('dashboard.addAccount')}</Button></Link>}
            />
          )}
        </Card>

        {/* AI Insight Card */}
        <Card className="lg:col-span-1">
          <div className="flex items-center gap-2 mb-3">
            <div className="w-8 h-8 rounded-lg bg-gradient-to-br from-[var(--color-primary)] to-purple-600 flex items-center justify-center">
              <Sparkles className="w-4 h-4 text-white" />
            </div>
            <div>
              <p className="text-sm font-semibold text-[var(--color-text)]">{t('dashboard.aiInsight')}</p>
              <p className="text-[10px] text-[var(--color-text-secondary)]">{t('dashboard.autoAnalysis')}</p>
            </div>
          </div>
          <div className="space-y-3">
            <div className={cn('p-3 rounded-lg border-l-2', stats && stats.bankBalance > 0 ? 'bg-[rgba(0,135,90,0.08)] border-[var(--color-success)]' : 'bg-[var(--color-neutral-50)] border-[var(--color-neutral-200)]')}>
              <p className="text-xs font-medium flex items-center gap-1 mb-1" style={{ color: stats && stats.bankBalance > 0 ? 'var(--color-success)' : 'var(--color-text-secondary)' }}>
                <CheckCircle className="w-3 h-3" /> {stats && stats.bankBalance > 0 ? t('dashboard.positiveCash') : t('dashboard.watchCash')}
              </p>
              <p className="text-xs text-[var(--color-text-secondary)]">
                {t('dashboard.bankBalanceLabel')}: {formatCurrency(stats?.bankBalance || 0)}
              </p>
            </div>
            <div className={cn('p-3 rounded-lg border-l-2', chartData.overdueCount > 0 ? 'bg-[rgba(255,149,0,0.08)] border-[var(--color-warning)]' : 'bg-[rgba(0,135,90,0.08)] border-[var(--color-success)]')}>
              <p className="text-xs font-medium flex items-center gap-1 mb-1" style={{ color: chartData.overdueCount > 0 ? 'var(--color-warning)' : 'var(--color-success)' }}>
                <AlertCircle className="w-3 h-3" /> {chartData.overdueCount > 0 ? `${chartData.overdueCount} ${t('dashboard.overdueInvoices')}` : t('dashboard.noOverdue')}
              </p>
              <p className="text-xs text-[var(--color-text-secondary)]">
                {chartData.overdueCount > 0 ? t('dashboard.overdueTotal', { amount: formatCurrency(chartData.overdueTotal) }) : t('dashboard.allUpToDate')}
              </p>
            </div>
            <div className="p-3 rounded-lg bg-[rgba(0,102,204,0.08)] border-l-2 border-[var(--color-primary)]">
              <p className="text-xs font-medium text-[var(--color-primary)] flex items-center gap-1 mb-1">
                <Zap className="w-3 h-3" /> {t('dashboard.receivablesVsPayables')}
              </p>
              <p className="text-xs text-[var(--color-text-secondary)]">
                {t('dashboard.receivables')}: {formatCurrency(stats?.totalDebtors || 0)} / {t('dashboard.payables')}: {formatCurrency(stats?.totalCreditors || 0)}
              </p>
            </div>
          </div>
          <Button variant="ghost" size="sm" className="w-full mt-3">
            {t('dashboard.seeAllInsights')} <ChevronRight className="w-3 h-3" />
          </Button>
        </Card>
      </div>

      {/* Quick Actions */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        {[
          { label: t('dashboard.qaNewInvoice'), desc: t('dashboard.qaNewInvoiceDesc'), icon: FileText, color: 'rgba(0,102,204,0.1)', iconColor: 'text-[var(--color-primary)]', path: '/sales/invoices' },
          { label: t('dashboard.qaNewCustomer'), desc: t('dashboard.qaNewCustomerDesc'), icon: Users, color: 'rgba(0,135,90,0.1)', iconColor: 'text-[var(--color-success)]', path: '/sales/customers' },
          { label: t('dashboard.qaPurchaseInvoice'), desc: t('dashboard.qaPurchaseInvoiceDesc'), icon: Package, color: 'rgba(255,149,0,0.1)', iconColor: 'text-[var(--color-warning)]', path: '/purchases/invoices' },
          { label: t('dashboard.qaReconciliation'), desc: t('dashboard.qaReconciliationDesc'), icon: Banknote, color: 'rgba(222,53,11,0.1)', iconColor: 'text-[var(--color-danger)]', path: '/banking/reconciliation' },
        ].map((action) => (
          <Link key={action.path} to={action.path}>
            <div className="card p-4 flex items-center gap-3 hover:shadow-md transition-all hover:-translate-y-0.5 cursor-pointer">
              <div className="w-10 h-10 rounded-lg flex items-center justify-center" style={{ background: action.color }}>
                <action.icon className={cn('w-5 h-5', action.iconColor)} />
              </div>
              <div>
                <p className="text-sm font-medium text-[var(--color-text)]">{action.label}</p>
                <p className="text-xs text-[var(--color-text-secondary)]">{action.desc}</p>
              </div>
            </div>
          </Link>
        ))}
      </div>
    </div>
  )
}
