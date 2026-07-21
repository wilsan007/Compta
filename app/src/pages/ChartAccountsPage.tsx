import { useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { getChartAccounts, createChartAccount, updateChartAccount, deleteChartAccount, getThirdPartyAccounts } from '@/lib/queries'
import { formatCurrency } from '@/lib/utils'
import { BookOpen, Plus, Pencil, Trash2, X, Search, ChevronDown, ChevronRight, Link2 } from 'lucide-react'
import type { ChartAccount, ThirdPartyAccount } from '@/types'
import { useToast } from '@/lib/toast'

const accountTypeBadge: Record<string, 'success' | 'warning' | 'danger' | 'neutral' | 'primary'> = {
  asset: 'primary',
  liability: 'warning',
  equity: 'success',
  income: 'success',
  expense: 'danger',
}

export function ChartAccountsPage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
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
              {t(`chartAccounts.types.${account.type}`, { defaultValue: account.type })}
            </Badge>
          </TableCell>
          <TableCell className="text-xs">
            {isTiersAccount && (
              <span className="flex items-center gap-1 text-[var(--color-primary)]">
                <Link2 className="w-3.5 h-3.5" />
                {tiersCount > 0 ? t('chartAccounts.tiersCount', { count: tiersCount }) : t('chartAccounts.tiersAccount')}
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
    if (!window.confirm(t('chartAccounts.deleteConfirm'))) return
    try {
      await deleteChartAccount(id)
      await loadAccounts()
    } catch (err) {
      console.error('Error deleting account:', err)
      toast('error', tCommon('toast.error'), tCommon('toast.deleteError'))
    }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('title') }, { label: t('chartAccounts.breadcrumb') }, { label: t('chartAccounts.title') }]} />
      <PageHeader
        title={t('chartAccounts.title')}
        subtitle={t('chartAccounts.subtitle', { count: accounts.length })}
        action={<Button onClick={openCreate}><Plus className="w-4 h-4" /> {t('chartAccounts.new')}</Button>}
      />

      <div className="flex gap-3 mb-4">
        <div className="flex-1 relative">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-[var(--color-text-secondary)]" />
          <input
            className="input pl-10"
            placeholder={t('chartAccounts.searchPlaceholder')}
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
        </div>
        <select
          className="input cursor-pointer w-56"
          value={filterClass}
          onChange={(e) => setFilterClass(e.target.value)}
        >
          <option value="">{t('chartAccounts.allClasses')}</option>
          <option value="1">{t('chartAccounts.classLabels.1')}</option>
          <option value="2">{t('chartAccounts.classLabels.2')}</option>
          <option value="3">{t('chartAccounts.classLabels.3')}</option>
          <option value="4">{t('chartAccounts.classLabels.4')}</option>
          <option value="5">{t('chartAccounts.classLabels.5')}</option>
          <option value="6">{t('chartAccounts.classLabels.6')}</option>
          <option value="7">{t('chartAccounts.classLabels.7')}</option>
          <option value="8">{t('chartAccounts.classLabels.8')}</option>
        </select>
      </div>

      {loading ? (
        <SkeletonTable rows={8} cols={6} />
      ) : sortedClasses.length === 0 ? (
        <EmptyState
          icon={<BookOpen className="w-8 h-8" />}
          title={t('chartAccounts.noAccounts')}
          description={t('chartAccounts.noAccountsDescription')}
          action={<Button onClick={openCreate}><Plus className="w-4 h-4" /> {t('chartAccounts.new')}</Button>}
        />
      ) : (
        <div className="space-y-6">
          {sortedClasses.map((cls) => (
            <Card key={cls} title={t(`chartAccounts.classLabels.${cls}`, { defaultValue: `Classe ${cls}` })}>
              <Table headers={[tCommon('common.code'), tCommon('common.label'), tCommon('common.type'), t('chartAccounts.thirdPartyLink'), tCommon('common.balance'), tCommon('table.actions')]}>
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
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [code, setCode] = useState(account?.code || '')
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
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.updateError'))
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl overflow-hidden" style={{ width: '100%', maxWidth: '36rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{account ? t('chartAccounts.edit') : t('chartAccounts.create')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div className="grid grid-cols-2 gap-4">
            <Input label={tCommon('common.code')} required value={code} onChange={(e) => setCode(e.target.value)} placeholder="411000" />
            <Select label={tCommon('common.type')} value={type} onChange={(e) => setType(e.target.value as 'asset' | 'liability' | 'equity' | 'income' | 'expense')} options={[
              { value: 'asset', label: t('chartAccounts.types.asset') },
              { value: 'liability', label: t('chartAccounts.types.liability') },
              { value: 'equity', label: t('chartAccounts.types.equity') },
              { value: 'income', label: t('chartAccounts.types.revenue') },
              { value: 'expense', label: t('chartAccounts.types.expense') },
            ]} />
          </div>
          <Input label={tCommon('common.label')} required value={name} onChange={(e) => setName(e.target.value)} placeholder="" />
          <div>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('chartAccounts.parent')}</label>
            <select className="input" value={parentId} onChange={(e) => setParentId(e.target.value)}>
              <option value="">{t('chartAccounts.noParent')}</option>
              {parentOptions.map((a) => <option key={a.id} value={a.id}>{a.code} — {a.name}</option>)}
            </select>
          </div>
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('chartAccounts.initialBalance')} type="number" value={balance} onChange={(e) => setBalance(e.target.value)} />
            <Input label={t('chartAccounts.vatRate')} type="text" value={vatRate} onChange={(e) => setVatRate(e.target.value)} placeholder="20" />
          </div>
          <Input label={tCommon('common.description')} value={description} onChange={(e) => setDescription(e.target.value)} />
          <div className="flex justify-end gap-3 pt-2">
            <Button variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? tCommon('common.saving') : tCommon('actions.save')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
