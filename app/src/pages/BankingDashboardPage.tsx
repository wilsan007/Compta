import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, SkeletonTable, Breadcrumb, Table, TableRow, TableCell, Badge } from '@/components/ui'
import { getBankAccounts, getBankTransactions, getBankRules } from '@/lib/queries'
import { formatCurrency, formatDate } from '@/lib/utils'
import type { BankAccount, BankTransaction, BankRule } from '@/types'
import { useToast } from '@/lib/toast'

export function BankingDashboardPage() {
  const { toast } = useToast()
  const { t } = useTranslation('banking')
  const { t: tCommon } = useTranslation('common')
  const { t: tNav } = useTranslation('nav')
const [accounts, setAccounts] = useState<BankAccount[]>([])
  const [transactions, setTransactions] = useState<BankTransaction[]>([])
  const [rules, setRules] = useState<BankRule[]>([])
  const [loading, setLoading] = useState(true)

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const [a, txns, r] = await Promise.all([getBankAccounts(), getBankTransactions(), getBankRules()])
      setAccounts(a)
      setTransactions(txns)
      setRules(r)
    } catch (err) { console.error(err); toast('error', tCommon('error'), err.message || tCommon('error')) } finally { setLoading(false) }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  const totalBalance = accounts.reduce((s, a) => s + Number(a.balance), 0)
  const unreconciled = transactions.filter(t => !t.reconciled)
  const totalInflow = transactions.filter(t => t.type === 'credit').reduce((s, t) => s + Number(t.amount), 0)
  const totalOutflow = transactions.filter(t => t.type === 'debit').reduce((s, t) => s + Number(t.amount), 0)

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('sections.dashboards') }, { label: t('title') }]} />
      <PageHeader title={t('dashboard.title')} subtitle={t('dashboard.subtitle')} />

      {loading ? (
        <SkeletonTable rows={4} cols={4} />
      ) : (
        <>
          <div className="grid grid-cols-4 gap-4 mb-6">
            <Card><div className="p-4"><p className="text-sm text-[var(--color-text-secondary)]">{t('dashboard.totalBalance')}</p><p className="text-2xl font-bold font-mono">{formatCurrency(totalBalance)}</p></div></Card>
            <Card><div className="p-4"><p className="text-sm text-[var(--color-text-secondary)]">{t('dashboard.inflow')}</p><p className="text-2xl font-bold font-mono text-[var(--color-success)]">{formatCurrency(totalInflow)}</p></div></Card>
            <Card><div className="p-4"><p className="text-sm text-[var(--color-text-secondary)]">{t('dashboard.outflow')}</p><p className="text-2xl font-bold font-mono text-[var(--color-danger)]">{formatCurrency(totalOutflow)}</p></div></Card>
            <Card><div className="p-4"><p className="text-sm text-[var(--color-text-secondary)]">{t('dashboard.unreconciled')}</p><p className="text-2xl font-bold text-[var(--color-warning)]">{unreconciled.length}</p></div></Card>
          </div>

          <div className="grid grid-cols-2 gap-6">
            <Card>
              <h3 className="text-sm font-semibold p-4 border-b border-[var(--color-border)]">{t('dashboard.bankAccounts')}</h3>
              <Table headers={[t('dashboard.name'), t('dashboard.bank'), t('dashboard.balance'), t('dashboard.currency')]}>
                {accounts.map((a) => (
                  <TableRow key={a.id}>
                    <TableCell className="font-medium text-sm">{a.name}</TableCell>
                    <TableCell className="text-xs">{a.bank_name || '—'}</TableCell>
                    <TableCell className="font-mono text-xs font-bold text-right">{formatCurrency(Number(a.balance))}</TableCell>
                    <TableCell className="text-xs">{a.currency || 'EUR'}</TableCell>
                  </TableRow>
                ))}
              </Table>
            </Card>

            <Card>
              <h3 className="text-sm font-semibold p-4 border-b border-[var(--color-border)]">{t('dashboard.recentTransactions')}</h3>
              <Table headers={[t('transactions.date'), t('transactions.description'), t('transactions.amount'), t('transactions.reconciled')]}>
                {transactions.slice(0, 5).map((tx) => (
                  <TableRow key={tx.id}>
                    <TableCell className="text-xs">{formatDate(tx.date)}</TableCell>
                    <TableCell className="text-sm max-w-xs truncate">{tx.description}</TableCell>
                    <TableCell className={`font-mono text-xs ${tx.type === 'credit' ? 'text-[var(--color-success)]' : 'text-[var(--color-danger)]'}`}>
                      {tx.type === 'credit' ? '+' : '-'}{formatCurrency(Number(tx.amount))}
                    </TableCell>
                    <TableCell><Badge variant={tx.reconciled ? 'success' : 'warning'}>{tx.reconciled ? t('transactions.yes') : t('transactions.no')}</Badge></TableCell>
                  </TableRow>
                ))}
              </Table>
            </Card>
          </div>

          <div className="mt-6">
            <Card>
              <h3 className="text-sm font-semibold p-4 border-b border-[var(--color-border)]">{t('dashboard.activeRules', { count: rules.filter(r => r.active).length })}</h3>
              <Table headers={[t('dashboard.name'), t('dashboard.condition'), t('dashboard.category'), t('dashboard.status')]}>
                {rules.slice(0, 5).map((r) => (
                  <TableRow key={r.id}>
                    <TableCell className="text-sm font-medium">{r.name}</TableCell>
                    <TableCell className="text-xs">{r.condition_field} {r.condition_operator} "{r.condition_value}"</TableCell>
                    <TableCell className="text-xs">{r.action_category}</TableCell>
                    <TableCell><Badge variant={r.active ? 'success' : 'neutral'}>{r.active ? t('dashboard.active') : t('dashboard.inactive')}</Badge></TableCell>
                  </TableRow>
                ))}
                {rules.length === 0 && <TableRow><TableCell colSpan={4} className="text-center text-[var(--color-text-secondary)] text-sm">{t('dashboard.noRules')}</TableCell></TableRow>}
              </Table>
            </Card>
          </div>
        </>
      )}
    </div>
  )
}
