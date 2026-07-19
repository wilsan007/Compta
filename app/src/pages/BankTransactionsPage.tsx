import { useEffect, useState, useCallback } from 'react'
import { Card, PageHeader, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Select } from '@/components/ui'
import { getBankTransactions, getBankAccounts, updateBankTransaction, deleteBankTransaction } from '@/lib/queries'
import { formatCurrency, formatDate } from '@/lib/utils'
import { ArrowLeftRight, Trash2, CheckCircle } from 'lucide-react'
import type { BankTransaction, BankAccount } from '@/types'
import { useToast } from '@/lib/toast'

export function BankTransactionsPage() {
  const { toast } = useToast()
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
      toast('error', 'Erreur', err.message || 'échec')
    }
  }

  async function handleDelete(id: string) {
    if (!window.confirm('Supprimer cette transaction ?')) return
    try {
      await deleteBankTransaction(id)
      await loadData()
    } catch (err: any) {
      toast('error', 'Erreur', err.message || 'échec')
    }
  }

  const filtered = filterType ? transactions.filter(t => t.type === filterType) : transactions
  const accountName = (id: string) => accounts.find(a => a.id === id)?.name || 'N/A'

  return (
    <div>
      <Breadcrumb items={[{ label: 'Banque' }, { label: 'Transactions' }]} />
      <PageHeader title="Transactions bancaires" subtitle="Toutes vos transactions en un coup d'œil" />

      <div className="mb-4 flex items-center gap-3">
        <Select value={filterAccount} onChange={(e) => setFilterAccount(e.target.value)} className="max-w-xs" options={[
          { value: '', label: 'Tous les comptes' },
          ...accounts.map(a => ({ value: a.id, label: a.name })),
        ]} />
        <Select value={filterType} onChange={(e) => setFilterType(e.target.value)} className="max-w-xs" options={[
          { value: '', label: 'Tous types' },
          { value: 'credit', label: 'Crédit (entrée)' },
          { value: 'debit', label: 'Débit (sortie)' },
        ]} />
        <span className="text-sm text-[var(--color-text-secondary)]">{filtered.length} transaction(s)</span>
      </div>

      {loading ? (
        <SkeletonTable rows={6} cols={7} />
      ) : filtered.length === 0 ? (
        <EmptyState icon={<ArrowLeftRight className="w-8 h-8" />} title="Aucune transaction" description="Aucune transaction bancaire trouvée." />
      ) : (
        <Card>
          <Table headers={['Date', 'Compte', 'Description', 'Référence', 'Type', 'Montant', 'Rapprochée', 'Actions']}>
            {filtered.map((t) => (
              <TableRow key={t.id}>
                <TableCell>{formatDate(t.date)}</TableCell>
                <TableCell className="text-xs">{accountName(t.account_id)}</TableCell>
                <TableCell className="max-w-xs truncate">{t.description}</TableCell>
                <TableCell className="text-xs">{t.reference || '—'}</TableCell>
                <TableCell>
                  <Badge variant={t.type === 'credit' ? 'success' : 'danger'}>
                    {t.type === 'credit' ? 'Crédit' : 'Débit'}
                  </Badge>
                </TableCell>
                <TableCell className={`font-mono ${t.type === 'credit' ? 'text-[var(--color-success)]' : 'text-[var(--color-danger)]'}`}>
                  {t.type === 'credit' ? '+' : '-'}{formatCurrency(Number(t.amount))}
                </TableCell>
                <TableCell>
                  <button onClick={() => handleReconcile(t.id, t.reconciled)} className="text-xs">
                    {t.reconciled ? <span className="text-[var(--color-success)] flex items-center gap-1"><CheckCircle className="w-3 h-3" /> Oui</span> : <span className="text-[var(--color-text-secondary)]">Non</span>}
                  </button>
                </TableCell>
                <TableCell>
                  <button onClick={() => handleDelete(t.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]">
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
