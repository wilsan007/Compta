import { useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, Breadcrumb, SkeletonTable, StatCard } from '@/components/ui'
import { getJournalEntries, getChartAccounts, getTrialBalance } from '@/lib/queries'
import { formatCurrency, formatDate } from '@/lib/utils'
import { CalendarDays, FileText, TrendingUp, AlertTriangle, Plus, BookOpen } from 'lucide-react'
import { useNavigate } from 'react-router-dom'
import type { JournalEntry, ChartAccount } from '@/types'

export function AccountingDashboardPage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const navigate = useNavigate()
  const [entries, setEntries] = useState<JournalEntry[]>([])
  const [accounts, setAccounts] = useState<ChartAccount[]>([])
  const [trialBalance, setTrialBalance] = useState<any[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    loadData()
  }, [])

  async function loadData() {
    try {
      const [je, accs, tb] = await Promise.all([
        getJournalEntries(),
        getChartAccounts(),
        getTrialBalance(),
      ])
      setEntries(je || [])
      setAccounts(accs || [])
      setTrialBalance(tb || [])
    } catch (err) {
      console.error('Error loading accounting dashboard:', err)
    } finally {
      setLoading(false)
    }
  }

  const draftEntries = entries.filter((e) => e.status === 'draft')
  const totalDebit = entries.reduce((s, e) => s + Number(e.total_debit), 0)

  const recentEntries = entries.slice(0, 5)

  const classCounts = accounts.reduce((acc, a) => {
    const cls = a.code.charAt(0)
    acc[cls] = (acc[cls] || 0) + 1
    return acc
  }, {} as Record<string, number>)

  return (
    <div>
      <Breadcrumb items={[{ label: t('title') }, { label: t('dashboard.dailyManagement') }]} />
      <PageHeader
        title={t('dashboard.dailyManagement')}
        subtitle={t('dashboard.subtitle')}
        action={<Button onClick={() => navigate('/accounting/journal-entries')}><Plus className="w-4 h-4" /> {t('dashboard.newEntry')}</Button>}
      />

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
        <StatCard
          label={t('dashboard.totalEntries')}
          value={String(entries.length)}
          icon={<FileText className="w-5 h-5" />}
          color="primary"
        />
        <StatCard
          label={t('dashboard.pendingDrafts')}
          value={String(draftEntries.length)}
          icon={<AlertTriangle className="w-5 h-5" />}
          color={draftEntries.length > 0 ? 'warning' : 'success'}
        />
        <StatCard
          label={t('dashboard.totalDebit')}
          value={formatCurrency(totalDebit)}
          icon={<TrendingUp className="w-5 h-5" />}
          color="success"
        />
        <StatCard
          label={t('dashboard.accountsCount')}
          value={String(accounts.length)}
          icon={<BookOpen className="w-5 h-5" />}
          color="primary"
        />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div className="lg:col-span-2 space-y-6">
          <Card title={t('dashboard.recentEntries')} action={<Button variant="ghost" size="sm" onClick={() => navigate('/accounting/journal-entries')}>{tCommon('actions.seeAll')}</Button>}>
            {loading ? (
              <SkeletonTable rows={4} cols={5} />
            ) : recentEntries.length === 0 ? (
              <p className="text-sm text-[var(--color-text-secondary)] py-8 text-center">{t('dashboard.noEntriesHint')}</p>
            ) : (
              <Table headers={[t('dashboard.colNumber'), tCommon('common.date'), tCommon('common.description'), tCommon('common.status'), tCommon('common.amount')]}>
                {recentEntries.map((entry) => (
                  <TableRow key={entry.id} onClick={() => navigate('/accounting/journal-entries')}>
                    <TableCell className="font-mono font-semibold">{entry.number}</TableCell>
                    <TableCell>{formatDate(entry.date)}</TableCell>
                    <TableCell className="max-w-xs truncate">{entry.description}</TableCell>
                    <TableCell>
                      <Badge variant={entry.status === 'posted' ? 'success' : 'warning'}>
                        {entry.status === 'posted' ? t('dashboard.posted') : t('dashboard.draft')}
                      </Badge>
                    </TableCell>
                    <TableCell className="font-mono text-right">{formatCurrency(Number(entry.total_debit))}</TableCell>
                  </TableRow>
                ))}
              </Table>
            )}
          </Card>

          <Card title={t('dashboard.quickActions')}>
            <div className="grid grid-cols-2 md:grid-cols-3 gap-3">
              <button onClick={() => navigate('/accounting/journal-entries')} className="card p-4 text-left hover:border-[var(--color-primary)] transition-colors">
                <FileText className="w-6 h-6 text-[var(--color-primary)] mb-2" />
                <p className="text-sm font-semibold">{t('dashboard.entrySaisie')}</p>
                <p className="text-xs text-[var(--color-text-secondary)]">{t('dashboard.newAccountingEntry')}</p>
              </button>
              <button onClick={() => navigate('/accounting/chart-accounts')} className="card p-4 text-left hover:border-[var(--color-primary)] transition-colors">
                <BookOpen className="w-6 h-6 text-[var(--color-primary)] mb-2" />
                <p className="text-sm font-semibold">{t('dashboard.chartAccounts')}</p>
                <p className="text-xs text-[var(--color-text-secondary)]">{t('dashboard.managePCG')}</p>
              </button>
              <button onClick={() => navigate('/accounting/general-ledger')} className="card p-4 text-left hover:border-[var(--color-primary)] transition-colors">
                <CalendarDays className="w-6 h-6 text-[var(--color-primary)] mb-2" />
                <p className="text-sm font-semibold">{t('dashboard.generalLedger')}</p>
                <p className="text-xs text-[var(--color-text-secondary)]">{t('dashboard.movementsByAccount')}</p>
              </button>
              <button onClick={() => navigate('/accounting/trial-balance')} className="card p-4 text-left hover:border-[var(--color-primary)] transition-colors">
                <TrendingUp className="w-6 h-6 text-[var(--color-primary)] mb-2" />
                <p className="text-sm font-semibold">{t('dashboard.trialBalance')}</p>
                <p className="text-xs text-[var(--color-text-secondary)]">{t('dashboard.allAccountBalances')}</p>
              </button>
              <button onClick={() => navigate('/reports/journals')} className="card p-4 text-left hover:border-[var(--color-primary)] transition-colors">
                <FileText className="w-6 h-6 text-[var(--color-primary)] mb-2" />
                <p className="text-sm font-semibold">{t('dashboard.journalsReport')}</p>
                <p className="text-xs text-[var(--color-text-secondary)]">{t('dashboard.viewJournals')}</p>
              </button>
              <button onClick={() => navigate('/reports/balance-sheet')} className="card p-4 text-left hover:border-[var(--color-primary)] transition-colors">
                <AlertTriangle className="w-6 h-6 text-[var(--color-primary)] mb-2" />
                <p className="text-sm font-semibold">{t('dashboard.balanceSheet')}</p>
                <p className="text-xs text-[var(--color-text-secondary)]">{t('dashboard.financialPosition')}</p>
              </button>
            </div>
          </Card>
        </div>

        <div className="space-y-6">
          <Card title={t('dashboard.classDistribution')}>
            {loading ? (
              <SkeletonTable rows={7} cols={2} />
            ) : (
              <div className="space-y-2">
                {Object.entries(classCounts).sort(([a], [b]) => a.localeCompare(b)).map(([cls, count]) => (
                  <div key={cls} className="flex items-center justify-between py-2 border-b border-[var(--color-border)] last:border-0">
                    <span className="text-sm text-[var(--color-text)]">{t('dashboard.classLabel', { cls })}</span>
                    <Badge variant="neutral">{t('dashboard.accountCount', { count })}</Badge>
                  </div>
                ))}
              </div>
            )}
          </Card>

          <Card title={t('dashboard.alerts')}>
            <div className="space-y-3">
              {draftEntries.length > 0 && (
                <div className="flex items-start gap-3 p-3 rounded-lg bg-[rgba(255,149,0,0.08)]">
                  <AlertTriangle className="w-5 h-5 text-[var(--color-warning)] mt-0.5" />
                  <div>
                    <p className="text-sm font-medium">{t('dashboard.draftsPending', { count: draftEntries.length })}</p>
                    <p className="text-xs text-[var(--color-text-secondary)]">{t('dashboard.toValidate')}</p>
                  </div>
                </div>
              )}
              {trialBalance.length > 0 && (
                <div className="flex items-start gap-3 p-3 rounded-lg bg-[rgba(0,135,90,0.08)]">
                  <TrendingUp className="w-5 h-5 text-[var(--color-success)] mt-0.5" />
                  <div>
                    <p className="text-sm font-medium">{t('dashboard.balanceAvailable')}</p>
                    <p className="text-xs text-[var(--color-text-secondary)]">{t('dashboard.accountsMovements', { count: trialBalance.length })}</p>
                  </div>
                </div>
              )}
              {entries.length === 0 && (
                <div className="flex items-start gap-3 p-3 rounded-lg bg-[rgba(0,102,204,0.08)]">
                  <FileText className="w-5 h-5 text-[var(--color-primary)] mt-0.5" />
                  <div>
                    <p className="text-sm font-medium">{t('dashboard.noEntries')}</p>
                    <p className="text-xs text-[var(--color-text-secondary)]">{t('dashboard.startByEntering')}</p>
                  </div>
                </div>
              )}
            </div>
          </Card>
        </div>
      </div>
    </div>
  )
}
