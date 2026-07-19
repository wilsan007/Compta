import { useEffect, useState } from 'react'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { getChartAccounts, createChartAccount, updateChartAccount, deleteChartAccount, getThirdPartyAccounts } from '@/lib/queries'
import { formatCurrency } from '@/lib/utils'
import { BookOpen, Plus, Pencil, Trash2, X, Search, ChevronDown, ChevronRight, Link2 } from 'lucide-react'
import type { ChartAccount, ThirdPartyAccount } from '@/types'
import { useToast } from '@/lib/toast'

const accountTypeLabels: Record<string, string> = {
  asset: 'Actif',
  liability: 'Passif',
  equity: 'Capitaux propres',
  income: 'Produits',
  expense: 'Charges',
}

const accountTypeBadge: Record<string, 'success' | 'warning' | 'danger' | 'neutral' | 'primary'> = {
  asset: 'primary',
  liability: 'warning',
  equity: 'success',
  income: 'success',
  expense: 'danger',
}

const classLabels: Record<string, string> = {
  '1': 'Classe 1 — Capitaux',
  '2': 'Classe 2 — Immobilisations',
  '3': 'Classe 3 — Stocks',
  '4': 'Classe 4 — Tiers',
  '5': 'Classe 5 — Financiers',
  '6': 'Classe 6 — Charges',
  '7': 'Classe 7 — Produits',
  '8': 'Classe 8 — Spéciaux',
}

export function ChartAccountsPage() {
  const { toast } = useToast()
const [accounts, setAccounts] = useState<ChartAccount[]>([])
  const [tiers, setTiers] = useState<ThirdPartyAccount[]>([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [filterClass, setFilterClass] = useState('')
  const [showForm, setShowForm] = useState(false)
  const [editing, setEditing] = useState<ChartAccount | null>(null)
  const [expanded, setExpanded] = useState<Set<string>>(new Set())

  useEffect(() => { loadAccounts() }, [])

  async function loadAccounts() {
    try {
      const [accs, tp] = await Promise.all([getChartAccounts(), getThirdPartyAccounts()])
      setAccounts(accs || [])
      setTiers(tp || [])
    } catch (err) {
      console.error('Error loading chart accounts:', err)
    } finally {
      setLoading(false)
    }
  }

  const tiersByAccount = new Map<string, number>()
  for (const tp of tiers) {
    const code = tp.account_general_code || tp.code?.substring(0, 3) || ''
    if (code) {
      tiersByAccount.set(code, (tiersByAccount.get(code) || 0) + 1)
    }
  }

  const filtered = accounts.filter((a) => {
    const matchSearch = !search ||
      a.code.includes(search) ||
      a.name.toLowerCase().includes(search.toLowerCase())
    const matchClass = !filterClass || a.code.startsWith(filterClass)
    return matchSearch && matchClass
  })

  const filteredIds = new Set(filtered.map((a) => a.id))

  const childrenByParent = new Map<string, ChartAccount[]>()
  for (const a of filtered) {
    if (a.parent_id) {
      const children = childrenByParent.get(a.parent_id) || []
      children.push(a)
      childrenByParent.set(a.parent_id, children)
    }
  }

  const rootAccounts = filtered.filter((a) => !a.parent_id || !filteredIds.has(a.parent_id))

  function toggleExpand(id: string) {
    setExpanded((prev) => {
      const next = new Set(prev)
      if (next.has(id)) next.delete(id)
      else next.add(id)
      return next
    })
  }

  function renderAccount(account: ChartAccount, depth: number): React.ReactNode {
    const children = childrenByParent.get(account.id) || []
    const hasChildren = children.length > 0
    const isExpanded = expanded.has(account.id)
    const tiersCount = tiersByAccount.get(account.code) || 0
    const isTiersAccount = account.code.startsWith('4')

    return (
      <div key={account.id}>
        <TableRow>
          <TableCell className="font-mono font-semibold">
            <div className="flex items-center gap-1" style={{ paddingLeft: `${depth * 20}px` }}>
              {hasChildren ? (
                <button onClick={() => toggleExpand(account.id)} className="p-0.5 rounded hover:bg-[var(--color-neutral-100)]">
                  {isExpanded ? <ChevronDown className="w-3.5 h-3.5" /> : <ChevronRight className="w-3.5 h-3.5" />}
                </button>
              ) : (
                <span className="w-4 inline-block" />
              )}
              {account.code}
            </div>
          </TableCell>
          <TableCell className="text-sm">{account.name}</TableCell>
          <TableCell>
            <Badge variant={accountTypeBadge[account.type] || 'neutral'}>
              {accountTypeLabels[account.type] || account.type}
            </Badge>
          </TableCell>
          <TableCell className="text-xs">
            {isTiersAccount && (
              <span className="flex items-center gap-1 text-[var(--color-primary)]">
                <Link2 className="w-3.5 h-3.5" />
                {tiersCount > 0 ? `${tiersCount} tiers` : 'Compte tiers'}
              </span>
            )}
          </TableCell>
          <TableCell className="font-mono text-right">{formatCurrency(Number(account.balance) || 0)}</TableCell>
          <TableCell>
            <div className="flex gap-2">
              <button onClick={() => openEdit(account)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-text-secondary)]">
                <Pencil className="w-4 h-4" />
              </button>
              <button onClick={() => handleDelete(account.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]">
                <Trash2 className="w-4 h-4" />
              </button>
            </div>
          </TableCell>
        </TableRow>
        {hasChildren && isExpanded && children.map((child) => renderAccount(child, depth + 1))}
      </div>
    )
  }

  const grouped = rootAccounts.reduce((acc, account) => {
    const cls = account.code.charAt(0)
    if (!acc[cls]) acc[cls] = []
    acc[cls].push(account)
    return acc
  }, {} as Record<string, ChartAccount[]>)

  const sortedClasses = Object.keys(grouped).sort()

  function openCreate() {
  setEditing(null)
    setShowForm(true)
  }

  function openEdit(account: ChartAccount) {
    setEditing(account)
    setShowForm(true)
  }

  async function handleDelete(id: string) {
    if (!window.confirm('Supprimer ce compte ?')) return
    try {
      await deleteChartAccount(id)
      await loadAccounts()
    } catch (err) {
      console.error('Error deleting account:', err)
      toast('error', 'Erreur', 'Erreur lors de la suppression')
    }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: 'Comptabilité' }, { label: 'Structure' }, { label: 'Plan comptable' }]} />
      <PageHeader
        title="Plan comptable"
        subtitle={`${accounts.length} compte(s) — PCG français — Hiérarchique`}
        action={<Button onClick={openCreate}><Plus className="w-4 h-4" /> Nouveau compte</Button>}
      />

      <div className="flex gap-3 mb-4">
        <div className="flex-1 relative">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-[var(--color-text-secondary)]" />
          <input
            className="input pl-10"
            placeholder="Rechercher par code ou libellé..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
        </div>
        <select
          className="input cursor-pointer w-56"
          value={filterClass}
          onChange={(e) => setFilterClass(e.target.value)}
        >
          <option value="">Toutes les classes</option>
          <option value="1">Classe 1 — Capitaux</option>
          <option value="2">Classe 2 — Immobilisations</option>
          <option value="3">Classe 3 — Stocks</option>
          <option value="4">Classe 4 — Tiers</option>
          <option value="5">Classe 5 — Financiers</option>
          <option value="6">Classe 6 — Charges</option>
          <option value="7">Classe 7 — Produits</option>
          <option value="8">Classe 8 — Spéciaux</option>
        </select>
      </div>

      {loading ? (
        <SkeletonTable rows={8} cols={6} />
      ) : sortedClasses.length === 0 ? (
        <EmptyState
          icon={<BookOpen className="w-8 h-8" />}
          title="Aucun compte trouvé"
          description="Ajoutez votre premier compte comptable ou ajustez vos filtres."
          action={<Button onClick={openCreate}><Plus className="w-4 h-4" /> Nouveau compte</Button>}
        />
      ) : (
        <div className="space-y-6">
          {sortedClasses.map((cls) => (
            <Card key={cls} title={classLabels[cls] || `Classe ${cls}`}>
              <Table headers={['Code', 'Libellé', 'Type', 'Lien tiers', 'Solde', 'Actions']}>
                {grouped[cls].map((account) => renderAccount(account, 0))}
              </Table>
            </Card>
          ))}
        </div>
      )}

      {showForm && (
        <AccountForm
          account={editing}
          accounts={accounts}
          onClose={() => setShowForm(false)}
          onSaved={() => { setShowForm(false); loadAccounts() }}
        />
      )}
    </div>
  )
}

function AccountForm({ account, accounts, onClose, onSaved }: { account: ChartAccount | null; accounts: ChartAccount[]; onClose: () => void; onSaved: () => void }) {
  const [code, setCode] = useState(account?.code || '')
  const { toast } = useToast()
  const [name, setName] = useState(account?.name || '')
  const [type, setType] = useState<'asset' | 'liability' | 'equity' | 'income' | 'expense'>(account?.type || 'asset')
  const [balance, setBalance] = useState(String(account?.balance || 0))
  const [vatRate, setVatRate] = useState(account?.vat_rate || '')
  const [parentId, setParentId] = useState(account?.parent_id || '')
  const [description, setDescription] = useState(account?.description || '')
  const [saving, setSaving] = useState(false)

  const parentOptions = accounts
    .filter((a) => a.id !== account?.id && a.code.length < (code.length || 10))
    .sort((a, b) => a.code.localeCompare(b.code))

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      const data = { code, name, type, balance: Number(balance) || 0, vat_rate: vatRate || undefined, parent_id: parentId || undefined, description: description || undefined }
      if (account) {
        await updateChartAccount(account.id, data)
      } else {
        await createChartAccount(data as any)
      }
      onSaved()
    } catch (err: any) {
      toast('error', 'Erreur', err.message || 'échec')
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl overflow-hidden" style={{ width: '100%', maxWidth: '36rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{account ? 'Modifier le compte' : 'Nouveau compte'}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div className="grid grid-cols-2 gap-4">
            <Input label="Code" required value={code} onChange={(e) => setCode(e.target.value)} placeholder="Ex: 411000" />
            <Select label="Type" value={type} onChange={(e) => setType(e.target.value as 'asset' | 'liability' | 'equity' | 'income' | 'expense')} options={[
              { value: 'asset', label: 'Actif' },
              { value: 'liability', label: 'Passif' },
              { value: 'equity', label: 'Capitaux propres' },
              { value: 'income', label: 'Produits' },
              { value: 'expense', label: 'Charges' },
            ]} />
          </div>
          <Input label="Libellé" required value={name} onChange={(e) => setName(e.target.value)} placeholder="Ex: Clients" />
          <div>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">Compte parent (hiérarchie)</label>
            <select className="input" value={parentId} onChange={(e) => setParentId(e.target.value)}>
              <option value="">— Aucun (racine) —</option>
              {parentOptions.map((a) => <option key={a.id} value={a.id}>{a.code} — {a.name}</option>)}
            </select>
          </div>
          <div className="grid grid-cols-2 gap-4">
            <Input label="Solde initial" type="number" value={balance} onChange={(e) => setBalance(e.target.value)} />
            <Input label="Taux TVA (%)" type="text" value={vatRate} onChange={(e) => setVatRate(e.target.value)} placeholder="Ex: 20" />
          </div>
          <Input label="Description" value={description} onChange={(e) => setDescription(e.target.value)} />
          <div className="flex justify-end gap-3 pt-2">
            <Button variant="secondary" onClick={onClose}>Annuler</Button>
            <Button type="submit" disabled={saving}>{saving ? 'Enregistrement...' : 'Enregistrer'}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
