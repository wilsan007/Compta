import { useEffect, useState, useCallback } from 'react'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Select } from '@/components/ui'
import { getBankTransactions, getBankAccounts, updateBankTransaction } from '@/lib/queries'
import { formatCurrency, formatDate } from '@/lib/utils'
import { CheckCircle, XCircle } from 'lucide-react'
import type { BankTransaction, BankAccount } from '@/types'
import { useToast } from '@/lib/toast'

export function BankReconciliationPage() {
  const { toast } = useToast()
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
    } catch (err) {
      console.error('Failed to load:', err)
    } finally {
      setLoading(false)
    }
  }, [selectedAccount])

  useEffect(() => { loadData() }, [loadData])

  async function handleReconcile(id: string, current: boolean) {
  try {
      await updateBankTransaction(id, { reconciled: !current, matched: !current })
      await loadData()
    } catch (err: any) {
      toast('error', 'Erreur', err.message || 'échec')
    }
  }

  const unreconciled = transactions.filter(t => !t.reconciled)
  const reconciled = transactions.filter(t => t.reconciled)
  const totalUnreconciled = unreconciled.reduce((s, t) => s + (t.type === 'credit' ? Number(t.amount) : -Number(t.amount)), 0)
  const accountBalance = accounts.find(a => a.id === selectedAccount)?.balance || 0

  return (
    <div>
      <Breadcrumb items={[{ label: 'Banque' }, { label: 'Rapprochement' }]} />
      <PageHeader title="Rapprochement bancaire" subtitle="Réconciliez vos transactions bancaires" />

      <div className="mb-4 flex items-center gap-3">
        <Select value={selectedAccount} onChange={(e) => setSelectedAccount(e.target.value)} className="max-w-xs" options={[
          { value: '', label: 'Tous les comptes' },
          ...accounts.map(a => ({ value: a.id, label: a.name })),
        ]} />
      </div>

      <div className="grid grid-cols-3 gap-4 mb-6">
        <Card>
          <div className="p-4">
            <p className="text-sm text-[var(--color-text-secondary)]">Solde bancaire</p>
            <p className="text-2xl font-bold font-mono">{formatCurrency(accountBalance)}</p>
          </div>
        </Card>
        <Card>
          <div className="p-4">
            <p className="text-sm text-[var(--color-text-secondary)]">Non réconcilié</p>
            <p className="text-2xl font-bold font-mono text-[var(--color-warning)]">{formatCurrency(Math.abs(totalUnreconciled))}</p>
          </div>
        </Card>
        <Card>
          <div className="p-4">
            <p className="text-sm text-[var(--color-text-secondary)]">Transactions en attente</p>
            <p className="text-2xl font-bold">{unreconciled.length}</p>
          </div>
        </Card>
      </div>

      {loading ? (
        <SkeletonTable rows={5} cols={5} />
      ) : (
        <>
          <h3 className="text-sm font-semibold mb-2">En attente de rapprochement ({unreconciled.length})</h3>
          {unreconciled.length === 0 ? (
            <EmptyState icon={<CheckCircle className="w-8 h-8" />} title="Tout est réconcilié" description="Aucune transaction en attente." />
          ) : (
            <Card className="mb-6">
              <Table headers={['Date', 'Description', 'Type', 'Montant', 'Action']}>
                {unreconciled.map((t) => (
                  <TableRow key={t.id}>
                    <TableCell>{formatDate(t.date)}</TableCell>
                    <TableCell className="max-w-xs truncate">{t.description}</TableCell>
                    <TableCell><Badge variant={t.type === 'credit' ? 'success' : 'danger'}>{t.type === 'credit' ? 'Crédit' : 'Débit'}</Badge></TableCell>
                    <TableCell className={`font-mono ${t.type === 'credit' ? 'text-[var(--color-success)]' : 'text-[var(--color-danger)]'}`}>
                      {t.type === 'credit' ? '+' : '-'}{formatCurrency(Number(t.amount))}
                    </TableCell>
                    <TableCell>
                      <Button size="sm" onClick={() => handleReconcile(t.id, false)}>
                        <CheckCircle className="w-3 h-3" /> Réconcilier
                      </Button>
                    </TableCell>
                  </TableRow>
                ))}
              </Table>
            </Card>
          )}

          {reconciled.length > 0 && (
            <>
              <h3 className="text-sm font-semibold mb-2">Réconciliées ({reconciled.length})</h3>
              <Card>
                <Table headers={['Date', 'Description', 'Type', 'Montant', 'Action']}>
                  {reconciled.map((t) => (
                    <TableRow key={t.id}>
                      <TableCell>{formatDate(t.date)}</TableCell>
                      <TableCell className="max-w-xs truncate">{t.description}</TableCell>
                      <TableCell><Badge variant="neutral">{t.type === 'credit' ? 'Crédit' : 'Débit'}</Badge></TableCell>
                      <TableCell className="font-mono text-right">{formatCurrency(Number(t.amount))}</TableCell>
                      <TableCell>
                        <button onClick={() => handleReconcile(t.id, true)} className="text-xs text-[var(--color-danger)] flex items-center gap-1">
                          <XCircle className="w-3 h-3" /> Annuler
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
