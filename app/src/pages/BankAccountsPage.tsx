import { useEffect, useState } from 'react'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, StatCard, Breadcrumb, SkeletonCard, Input, Select } from '@/components/ui'
import { getBankAccounts, getBankTransactions, createBankAccount } from '@/lib/queries'
import { formatCurrency, formatDate } from '@/lib/utils'
import { Banknote, Plus, Landmark, CreditCard, Wallet, TrendingDown, TrendingUp, X } from 'lucide-react'
import type { BankAccount } from '@/types'
import { useToast } from '@/lib/toast'

export function BankAccountsPage() {
const [accounts, setAccounts] = useState<BankAccount[]>([])
  const [transactions, setTransactions] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [selectedAccount, setSelectedAccount] = useState<string | null>(null)
  const [showForm, setShowForm] = useState(false)

  useEffect(() => {
    loadAccounts()
  }, [])

  async function loadAccounts() {
    try {
      const data = await getBankAccounts()
      setAccounts(data || [])
      if (data && data.length > 0) {
        setSelectedAccount(data[0].id)
        const txns = await getBankTransactions(data[0].id)
        setTransactions(txns || [])
      }
    } catch (err) {
      console.error('Error loading bank accounts:', err)
    } finally {
      setLoading(false)
    }
  }

  async function selectAccount(id: string) {
    setSelectedAccount(id)
    try {
      const txns = await getBankTransactions(id)
      setTransactions(txns || [])
    } catch (err) {
      console.error('Error loading transactions:', err)
    }
  }

  const totalBalance = accounts.reduce((sum, a) => sum + Number(a.balance || 0), 0)

  const accountTypeIcons: Record<string, React.ReactNode> = {
    chequing: <Landmark className="w-5 h-5" />,
    savings: <Banknote className="w-5 h-5" />,
    credit_card: <CreditCard className="w-5 h-5" />,
    cash: <Wallet className="w-5 h-5" />,
    loan: <Landmark className="w-5 h-5" />,
    other: <Banknote className="w-5 h-5" />,
  }

  return (
    <div className="animate-fade-in">
      <Breadcrumb items={[{ label: 'Banque', path: '/banking' }, { label: 'Comptes bancaires' }]} />
      <PageHeader
        title="Comptes bancaires"
        subtitle={`${accounts.length} compte(s) • Solde total: ${formatCurrency(totalBalance)}`}
        action={<Button variant="primary" onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> Nouveau compte</Button>}
      />

      {loading ? (
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-4 mb-6">
          <SkeletonCard />
          <SkeletonCard />
          <SkeletonCard />
        </div>
      ) : (
        <>
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-4 mb-6">
            <StatCard label="Solde total" value={formatCurrency(totalBalance)} icon={<Banknote className="w-5 h-5" />} color="primary" />
            <StatCard label="Transactions" value={String(transactions.length)} icon={<TrendingUp className="w-5 h-5" />} color="success" />
            <StatCard label="Comptes connectés" value={String(accounts.filter((a) => a.connected).length)} icon={<Landmark className="w-5 h-5" />} color="warning" />
          </div>

          <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
        <Card title="Comptes" className="lg:col-span-1">
          {accounts.length > 0 ? (
            <div className="space-y-2">
              {accounts.map((acc) => (
                <button
                  key={acc.id}
                  onClick={() => selectAccount(acc.id)}
                  className={`w-full flex items-center justify-between p-3 rounded-lg transition-colors text-left ${
                    selectedAccount === acc.id
                      ? 'bg-[rgba(0,102,204,0.08)] border border-[var(--color-primary)]'
                      : 'bg-[var(--color-neutral-50)] hover:bg-[var(--color-neutral-100)] border border-transparent'
                  }`}
                >
                  <div className="flex items-center gap-3">
                    <div className="w-10 h-10 rounded-lg bg-[var(--color-primary)] flex items-center justify-center text-white">
                      {accountTypeIcons[acc.type] || <Banknote className="w-5 h-5" />}
                    </div>
                    <div>
                      <p className="text-sm font-medium text-[var(--color-text)]">{acc.name}</p>
                      <p className="text-xs text-[var(--color-text-secondary)]">{acc.bank_name || acc.type}</p>
                    </div>
                  </div>
                  <span className="font-semibold text-[var(--color-text)]">{formatCurrency(Number(acc.balance) || 0)}</span>
                </button>
              ))}
            </div>
          ) : (
            <EmptyState
              icon={<Banknote className="w-8 h-8" />}
              title="Aucun compte"
              description="Ajoutez votre premier compte bancaire"
              action={<Button variant="primary" size="sm" onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> Ajouter</Button>}
            />
          )}
        </Card>

        <Card 
          title="Transactions" 
          className="lg:col-span-2"
        >
          {transactions.length > 0 ? (
            <Table headers={['Date', 'Description', 'Référence', 'Type', 'Montant', 'Statut']}>
              {transactions.slice(0, 20).map((txn) => (
                <TableRow key={txn.id}>
                  <TableCell>{formatDate(txn.date)}</TableCell>
                  <TableCell className="font-medium">{txn.description}</TableCell>
                  <TableCell className="text-[var(--color-text-secondary)]">{txn.reference || '—'}</TableCell>
                  <TableCell>
                    <span className={`flex items-center gap-1 text-xs ${txn.type === 'credit' ? 'text-[var(--color-success)]' : 'text-[var(--color-danger)]'}`}>
                      {txn.type === 'credit' ? <TrendingUp className="w-3 h-3" /> : <TrendingDown className="w-3 h-3" />}
                      {txn.type === 'credit' ? 'Crédit' : 'Débit'}
                    </span>
                  </TableCell>
                  <TableCell className={txn.type === 'credit' ? 'text-[var(--color-success)] font-medium text-right' : 'text-[var(--color-danger)] font-medium text-right'}>
                    {txn.type === 'credit' ? '+' : '-'}{formatCurrency(Number(txn.amount) || 0)}
                  </TableCell>
                  <TableCell>
                    <Badge variant={txn.reconciled ? 'success' : 'neutral'}>
                      {txn.reconciled ? 'Rapproché' : 'En attente'}
                    </Badge>
                  </TableCell>
                </TableRow>
              ))}
            </Table>
          ) : (
            <EmptyState
              icon={<TrendingUp className="w-8 h-8" />}
              title="Aucune transaction"
              description="Les transactions apparaîtront ici une fois le compte connecté"
            />
          )}
        </Card>
          </div>
        </>
      )}

      {showForm && (
        <BankAccountForm onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadAccounts() }} />
      )}
    </div>
  )
}

function BankAccountForm({ onClose, onSaved }: { onClose: () => void; onSaved: () => void }) {
  
  const { toast } = useToast()
const [name, setName] = useState('')
  const [bankName, setBankName] = useState('')
  const [type, setType] = useState('chequing')
  const [balance, setBalance] = useState('')
  const [currency, setCurrency] = useState('EUR')
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!name.trim()) { toast('warning', 'Attention', 'Le nom du compte est obligatoire'); return }
    setSaving(true)
    try {
      await createBankAccount({
        name,
        bank_name: bankName,
        type,
        balance: Number(balance) || 0,
        currency,
        connected: false,
        account_number: '',
      } as any)
      onSaved()
    } catch (err: any) {
      toast('error', 'Erreur', err.message || 'échec')
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '32rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">Nouveau compte bancaire</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <Input label="Nom du compte" required value={name} onChange={(e) => setName(e.target.value)} placeholder="Compte principal" />
          <Input label="Banque" value={bankName} onChange={(e) => setBankName(e.target.value)} placeholder="BNP Paribas" />
          <Select label="Type" value={type} onChange={(e) => setType(e.target.value)} options={[
            { value: 'chequing', label: 'Courant' },
            { value: 'savings', label: 'Épargne' },
            { value: 'credit_card', label: 'Carte de crédit' },
            { value: 'cash', label: 'Caisse' },
            { value: 'loan', label: 'Prêt' },
            { value: 'other', label: 'Autre' },
          ]} />
          <Input label="Solde initial (€)" type="number" step="0.01" value={balance} onChange={(e) => setBalance(e.target.value)} placeholder="0.00" />
          <Select label="Devise" value={currency} onChange={(e) => setCurrency(e.target.value)} options={[
            { value: 'EUR', label: 'EUR (€)' },
            { value: 'USD', label: 'USD ($)' },
            { value: 'GBP', label: 'GBP (£)' },
          ]} />
          <div className="flex justify-end gap-3 pt-4 border-t border-[var(--color-border)]">
            <Button variant="secondary" type="button" onClick={onClose}>Annuler</Button>
            <Button type="submit" disabled={saving}>{saving ? 'Enregistrement...' : 'Créer'}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
