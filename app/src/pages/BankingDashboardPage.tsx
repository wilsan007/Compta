import { useEffect, useState, useCallback } from 'react'
import { Card, PageHeader, SkeletonTable, Breadcrumb, Table, TableRow, TableCell, Badge } from '@/components/ui'
import { getBankAccounts, getBankTransactions, getBankRules } from '@/lib/queries'
import { formatCurrency, formatDate } from '@/lib/utils'
import type { BankAccount, BankTransaction, BankRule } from '@/types'
import { useToast } from '@/lib/toast'

export function BankingDashboardPage() {
  const { toast } = useToast()
const [accounts, setAccounts] = useState<BankAccount[]>([])
  const [transactions, setTransactions] = useState<BankTransaction[]>([])
  const [rules, setRules] = useState<BankRule[]>([])
  const [loading, setLoading] = useState(true)

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const [a, t, r] = await Promise.all([getBankAccounts(), getBankTransactions(), getBankRules()])
      setAccounts(a)
      setTransactions(t)
      setRules(r)
    } catch (err) { console.error(err); toast('error', 'Erreur', 'Erreur lors du chargement') } finally { setLoading(false) }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  const totalBalance = accounts.reduce((s, a) => s + Number(a.balance), 0)
  const unreconciled = transactions.filter(t => !t.reconciled)
  const totalInflow = transactions.filter(t => t.type === 'credit').reduce((s, t) => s + Number(t.amount), 0)
  const totalOutflow = transactions.filter(t => t.type === 'debit').reduce((s, t) => s + Number(t.amount), 0)

  return (
    <div>
      <Breadcrumb items={[{ label: 'Tableaux de bord' }, { label: 'Banque' }]} />
      <PageHeader title="Tableau de bord — Banque" subtitle="Vue d'ensemble de votre trésorerie" />

      {loading ? (
        <SkeletonTable rows={4} cols={4} />
      ) : (
        <>
          <div className="grid grid-cols-4 gap-4 mb-6">
            <Card><div className="p-4"><p className="text-sm text-[var(--color-text-secondary)]">Solde total</p><p className="text-2xl font-bold font-mono">{formatCurrency(totalBalance)}</p></div></Card>
            <Card><div className="p-4"><p className="text-sm text-[var(--color-text-secondary)]">Entrées</p><p className="text-2xl font-bold font-mono text-[var(--color-success)]">{formatCurrency(totalInflow)}</p></div></Card>
            <Card><div className="p-4"><p className="text-sm text-[var(--color-text-secondary)]">Sorties</p><p className="text-2xl font-bold font-mono text-[var(--color-danger)]">{formatCurrency(totalOutflow)}</p></div></Card>
            <Card><div className="p-4"><p className="text-sm text-[var(--color-text-secondary)]">Non réconciliées</p><p className="text-2xl font-bold text-[var(--color-warning)]">{unreconciled.length}</p></div></Card>
          </div>

          <div className="grid grid-cols-2 gap-6">
            <Card>
              <h3 className="text-sm font-semibold p-4 border-b border-[var(--color-border)]">Comptes bancaires</h3>
              <Table headers={['Nom', 'Banque', 'Solde', 'Devise']}>
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
              <h3 className="text-sm font-semibold p-4 border-b border-[var(--color-border)]">Transactions récentes</h3>
              <Table headers={['Date', 'Description', 'Montant', 'Rapprochée']}>
                {transactions.slice(0, 5).map((t) => (
                  <TableRow key={t.id}>
                    <TableCell className="text-xs">{formatDate(t.date)}</TableCell>
                    <TableCell className="text-sm max-w-xs truncate">{t.description}</TableCell>
                    <TableCell className={`font-mono text-xs ${t.type === 'credit' ? 'text-[var(--color-success)]' : 'text-[var(--color-danger)]'}`}>
                      {t.type === 'credit' ? '+' : '-'}{formatCurrency(Number(t.amount))}
                    </TableCell>
                    <TableCell><Badge variant={t.reconciled ? 'success' : 'warning'}>{t.reconciled ? 'Oui' : 'Non'}</Badge></TableCell>
                  </TableRow>
                ))}
              </Table>
            </Card>
          </div>

          <div className="mt-6">
            <Card>
              <h3 className="text-sm font-semibold p-4 border-b border-[var(--color-border)]">Règles actives ({rules.filter(r => r.active).length})</h3>
              <Table headers={['Nom', 'Condition', 'Catégorie', 'Statut']}>
                {rules.slice(0, 5).map((r) => (
                  <TableRow key={r.id}>
                    <TableCell className="text-sm font-medium">{r.name}</TableCell>
                    <TableCell className="text-xs">{r.condition_field} {r.condition_operator} "{r.condition_value}"</TableCell>
                    <TableCell className="text-xs">{r.action_category}</TableCell>
                    <TableCell><Badge variant={r.active ? 'success' : 'neutral'}>{r.active ? 'Active' : 'Inactive'}</Badge></TableCell>
                  </TableRow>
                ))}
                {rules.length === 0 && <TableRow><TableCell colSpan={4} className="text-center text-[var(--color-text-secondary)] text-sm">Aucune règle</TableCell></TableRow>}
              </Table>
            </Card>
          </div>
        </>
      )}
    </div>
  )
}
