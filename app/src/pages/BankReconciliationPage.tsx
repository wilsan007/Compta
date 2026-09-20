import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Select } from '@/components/ui'
import { getBankTransactions, getBankAccounts, updateBankTransaction, autoMatchBankTransactions } from '@/lib/queries/banking'
import { smartBankReconciliation, applyBankReconciliationRules } from '@/lib/queries/businessFunctions'
import { formatCurrency, formatDate } from '@/lib/utils'
import { CheckCircle, XCircle, Zap } from 'lucide-react'
import type { BankTransaction, BankAccount } from '@/types'
import { useToast } from '@/lib/toast'

export function BankReconciliationPage() {
  const { toast } = useToast()
  const { t } = useTranslation('banking')
  const { t: tCommon } = useTranslation('common')
const [transactions, setTransactions] = useState<BankTransaction[]>([])
  const [accounts, setAccounts] = useState<BankAccount[]>([])
  const [loading, setLoading] = useState(true)
  const [selectedAccount, setSelectedAccount] = useState('')

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const [txns, accs] = await Promise.all([getBankTransactions(selectedAccount || undefined), getBankAccounts()])
      setTransactions(txns)
      setAccounts(accs)
    } catch (err: any) { console.error('Failed to load:', err)
    toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadError'))
    } finally {
      setLoading(false)
    }
  }, [selectedAccount, toast, tCommon])

  useEffect(() => { loadData() }, [loadData])

  async function handleReconcile(id: string, current: boolean) {
  try {
      await updateBankTransaction(id, { reconciled: !current, matched: !current })
      await loadData()
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    }
  }

  async function handleAutoMatch() {
    try {
      const result = await autoMatchBankTransactions(selectedAccount || undefined)
      toast('success', tCommon('common.success'), t('reconciliation.autoMatchResult', { matched: result.matched, unmatched: result.unmatched }))
      await loadData()
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    }
  }

  async function handleSmartReconciliation() {
    if (!selectedAccount) {
      toast('error', tCommon('common.error'), t('reconciliation.selectAccount'))
      return
    }
    try {
      const result = await smartBankReconciliation(selectedAccount)
      const matched = result?.matched ?? result?.match_count ?? result ?? 0
      toast('success', tCommon('common.success'), t('reconciliation.smartResult', { matched: typeof matched === 'number' ? matched : 0 }))
      await loadData()
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    }
  }

  async function handleApplyRules() {
    if (!selectedAccount) {
      toast('error', tCommon('common.error'), t('reconciliation.selectAccount'))
      return
    }
    try {
      const result = await applyBankReconciliationRules(selectedAccount)
      const applied = result?.applied ?? result?.matched ?? result?.count ?? 0
      toast('success', tCommon('common.success'), `${applied} règle(s) appliquée(s)`)
      await loadData()
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    }
  }

  const unreconciled = transactions.filter(t => !t.reconciled)
  const reconciled = transactions.filter(t => t.reconciled)
  const totalUnreconciled = unreconciled.reduce((s, t) => s + (t.type === 'credit' ? Number(t.amount) : -Number(t.amount)), 0)
  const accountBalance = accounts.find(a => a.id === selectedAccount)?.balance || 0
  const selectedAcc = accounts.find(a => a.id === selectedAccount)
  const isForeignCurrency = selectedAcc && selectedAcc.currency && selectedAcc.currency !== 'EUR'

  return (
    <div>
      <Breadcrumb items={[{ label: t('title') }, { label: t('reconciliation.title') }]} />
      <PageHeader title={t('reconciliation.title')} subtitle={t('reconciliation.subtitle')} />

      <div className="mb-4 flex items-center gap-3">
        <Select value={selectedAccount} onChange={(e) => setSelectedAccount(e.target.value)} className="max-w-xs" options={[
          { value: '', label: t('reconciliation.allAccounts') },
          ...accounts.map(a => ({ value: a.id, label: a.name })),
        ]} />
        <Button onClick={handleAutoMatch} disabled={loading || unreconciled.length === 0}>
          <Zap className="w-4 h-4" /> {t('reconciliation.autoMatch')}
        </Button>
        <Button onClick={handleSmartReconciliation} disabled={loading || !selectedAccount || unreconciled.length === 0} variant="secondary">
          <Zap className="w-4 h-4" /> {t('reconciliation.smartMatch')}
        </Button>
        <Button onClick={handleApplyRules} disabled={loading || !selectedAccount || unreconciled.length === 0} variant="secondary">
          <Zap className="w-4 h-4" /> Appliquer les règles
        </Button>
      </div>

      <div className="grid grid-cols-3 gap-4 mb-6">
        <Card>
          <div className="p-4">
            <p className="text-sm text-[var(--color-text-secondary)]">{t('reconciliation.bankBalance')}</p>
            <p className="text-2xl font-bold font-mono">{formatCurrency(accountBalance)}</p>
          </div>
        </Card>
        <Card>
          <div className="p-4">
            <p className="text-sm text-[var(--color-text-secondary)]">{t('reconciliation.unreconciledAmount')}</p>
            <p className="text-2xl font-bold font-mono text-[var(--color-warning-text)]">{formatCurrency(Math.abs(totalUnreconciled))}</p>
          </div>
        </Card>
        <Card>
          <div className="p-4">
            <p className="text-sm text-[var(--color-text-secondary)]">{t('reconciliation.pendingCount')}</p>
            <p className="text-2xl font-bold">{unreconciled.length}</p>
          </div>
        </Card>
      </div>

      {loading ? (
        <SkeletonTable rows={5} cols={5} />
      ) : (
        <>
          <h3 className="text-sm font-semibold mb-2">{t('reconciliation.pendingTitle', { count: unreconciled.length })}</h3>
          {unreconciled.length === 0 ? (
            <EmptyState icon={<CheckCircle className="w-8 h-8" />} title={t('reconciliation.fullyReconciled')} description={t('reconciliation.fullyReconciledDesc')} />
          ) : (
            <Card className="mb-6">
              <Table headers={[
                t('transactions.date'),
                t('transactions.description'),
                t('transactions.type'),
                t('transactions.amount'),
                ...(isForeignCurrency ? [t('multiCurrency.originalAmount'), t('multiCurrency.exchangeRate')] : []),
                t('reconciliation.action'),
              ]}>
                {unreconciled.map((tx) => (
                  <TableRow key={tx.id}>
                    <TableCell>{formatDate(tx.date)}</TableCell>
                    <TableCell className="max-w-xs truncate">{tx.description}</TableCell>
                    <TableCell><Badge variant={tx.type === 'credit' ? 'success' : 'danger'}>{tx.type === 'credit' ? t('transactions.types.credit') : t('transactions.types.debit')}</Badge></TableCell>
                    <TableCell className={`font-mono ${tx.type === 'credit' ? 'text-[var(--color-success)]' : 'text-[var(--color-danger)]'}`}>
                      {tx.type === 'credit' ? '+' : '-'}{formatCurrency(Number(tx.amount))}
                    </TableCell>
                    {isForeignCurrency && (
                      <TableCell className="font-mono text-xs text-[var(--color-text-secondary)]">
                        {tx.original_amount ? `${Number(tx.original_amount).toFixed(2)} ${tx.original_currency || selectedAcc?.currency}` : '—'}
                      </TableCell>
                    )}
                    {isForeignCurrency && (
                      <TableCell className="font-mono text-xs text-[var(--color-text-secondary)]">
                        {tx.exchange_rate ? Number(tx.exchange_rate).toFixed(4) : '—'}
                      </TableCell>
                    )}
                    <TableCell>
                      <Button size="sm" onClick={() => handleReconcile(tx.id, false)}>
                        <CheckCircle className="w-3 h-3" /> {t('reconciliation.reconcileBtn')}
                      </Button>
                    </TableCell>
                  </TableRow>
                ))}
              </Table>
            </Card>
          )}

          {reconciled.length > 0 && (
            <>
              <h3 className="text-sm font-semibold mb-2">{t('reconciliation.reconciledTitle', { count: reconciled.length })}</h3>
              <Card>
                <Table headers={[t('transactions.date'), t('transactions.description'), t('transactions.type'), t('transactions.amount'), t('reconciliation.action')]}>
                  {reconciled.map((tx) => (
                    <TableRow key={tx.id}>
                      <TableCell>{formatDate(tx.date)}</TableCell>
                      <TableCell className="max-w-xs truncate">{tx.description}</TableCell>
                      <TableCell><Badge variant="neutral">{tx.type === 'credit' ? t('transactions.types.credit') : t('transactions.types.debit')}</Badge></TableCell>
                      <TableCell className="font-mono text-right">{formatCurrency(Number(tx.amount))}</TableCell>
                      <TableCell>
                        <button onClick={() => handleReconcile(tx.id, true)} className="text-xs text-[var(--color-danger)] flex items-center gap-1">
                          <XCircle className="w-3 h-3" /> {t('reconciliation.cancel')}
                        </button>
                      </TableCell>
                    </TableRow>
                  ))}
                </Table>
              </Card>
            </>
          )}
        </>
      )}
    </div>
  )
}
