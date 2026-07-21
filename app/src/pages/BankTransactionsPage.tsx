import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Select } from '@/components/ui'
import { getBankTransactions, getBankAccounts, updateBankTransaction, deleteBankTransaction } from '@/lib/queries'
import { formatCurrency, formatDate } from '@/lib/utils'
import { ArrowLeftRight, Trash2, CheckCircle } from 'lucide-react'
import type { BankTransaction, BankAccount } from '@/types'
import { useToast } from '@/lib/toast'

export function BankTransactionsPage() {
  const { toast } = useToast()
  const { t } = useTranslation('banking')
  const { t: tCommon } = useTranslation('common')
const [transactions, setTransactions] = useState<BankTransaction[]>([])
  const [accounts, setAccounts] = useState<BankAccount[]>([])
  const [loading, setLoading] = useState(true)
  const [filterAccount, setFilterAccount] = useState('')
  const [filterType, setFilterType] = useState('')

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const [txns, accs] = await Promise.all([getBankTransactions(filterAccount || undefined), getBankAccounts()])
      setTransactions(txns)
      setAccounts(accs)
    } catch (err) {
      console.error('Failed to load transactions:', err)
    } finally {
      setLoading(false)
    }
  }, [filterAccount])

  useEffect(() => { loadData() }, [loadData])

  async function handleReconcile(id: string, current: boolean) {
  try {
      await updateBankTransaction(id, { reconciled: !current })
      await loadData()
    } catch (err: any) {
      toast('error', tCommon('error'), err.message || tCommon('error'))
    }
  }

  async function handleDelete(id: string) {
    if (!window.confirm(t('transactions.deleteConfirm'))) return
    try {
      await deleteBankTransaction(id)
      await loadData()
    } catch (err: any) {
      toast('error', tCommon('error'), err.message || tCommon('error'))
    }
  }

  const filtered = filterType ? transactions.filter(t => t.type === filterType) : transactions
  const accountName = (id: string) => accounts.find(a => a.id === id)?.name || 'N/A'

  return (
    <div>
      <Breadcrumb items={[{ label: t('title') }, { label: t('transactions.title') }]} />
      <PageHeader title={t('transactions.title')} subtitle={t('transactions.subtitle')} />

      <div className="mb-4 flex items-center gap-3">
        <Select value={filterAccount} onChange={(e) => setFilterAccount(e.target.value)} className="max-w-xs" options={[
          { value: '', label: t('transactions.allAccounts') },
          ...accounts.map(a => ({ value: a.id, label: a.name })),
        ]} />
        <Select value={filterType} onChange={(e) => setFilterType(e.target.value)} className="max-w-xs" options={[
          { value: '', label: t('transactions.allTypes') },
          { value: 'credit', label: t('transactions.creditIn') },
          { value: 'debit', label: t('transactions.debitOut') },
        ]} />
        <span className="text-sm text-[var(--color-text-secondary)]">{t('transactions.count', { count: filtered.length })}</span>
      </div>

      {loading ? (
        <SkeletonTable rows={6} cols={7} />
      ) : filtered.length === 0 ? (
        <EmptyState icon={<ArrowLeftRight className="w-8 h-8" />} title={t('transactions.noTransactions')} description={t('transactions.noTransactionsDescription')} />
      ) : (
        <Card>
          <Table headers={[t('transactions.date'), t('transactions.account'), t('transactions.description'), t('transactions.reference'), t('transactions.type'), t('transactions.amount'), t('transactions.reconciled'), tCommon('table.actions')]}>
            {filtered.map((tx) => (
              <TableRow key={tx.id}>
                <TableCell>{formatDate(tx.date)}</TableCell>
                <TableCell className="text-xs">{accountName(tx.account_id)}</TableCell>
                <TableCell className="max-w-xs truncate">{tx.description}</TableCell>
                <TableCell className="text-xs">{tx.reference || '—'}</TableCell>
                <TableCell>
                  <Badge variant={tx.type === 'credit' ? 'success' : 'danger'}>
                    {tx.type === 'credit' ? t('transactions.types.credit') : t('transactions.types.debit')}
                  </Badge>
                </TableCell>
                <TableCell className={`font-mono ${tx.type === 'credit' ? 'text-[var(--color-success)]' : 'text-[var(--color-danger)]'}`}>
                  {tx.type === 'credit' ? '+' : '-'}{formatCurrency(Number(tx.amount))}
                </TableCell>
                <TableCell>
                  <button onClick={() => handleReconcile(tx.id, tx.reconciled)} className="text-xs">
                    {tx.reconciled ? <span className="text-[var(--color-success)] flex items-center gap-1"><CheckCircle className="w-3 h-3" /> {t('transactions.yes')}</span> : <span className="text-[var(--color-text-secondary)]">{t('transactions.no')}</span>}
                  </button>
                </TableCell>
                <TableCell>
                  <button onClick={() => handleDelete(tx.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]">
                    <Trash2 className="w-4 h-4" />
                  </button>
                </TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}
    </div>
  )
}
