import { Fragment, useEffect, useState, useMemo } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { getChartAccounts, createChartAccount, updateChartAccount, deleteChartAccount, getThirdPartyAccounts } from '@/lib/queries'
import { formatCurrency } from '@/lib/utils'
import { BookOpen, Plus, Pencil, Trash2, X, Search, ChevronDown, ChevronRight, Link2, Eye, EyeOff } from 'lucide-react'
import type { ChartAccount, ThirdPartyAccount } from '@/types'
import { useToast } from '@/lib/toast'

const accountTypeBadge: Record<string, 'success' | 'warning' | 'danger' | 'neutral' | 'primary'> = {
  asset: 'primary',
  liability: 'warning',
  equity: 'success',
  income: 'success',
  expense: 'danger',
}

const CLASS_COLORS: Record<string, string> = {
  '1': 'var(--color-success)', '2': 'var(--color-primary)', '3': 'var(--color-primary)',
  '4': 'var(--color-warning)', '5': 'var(--color-primary)',
  '6': 'var(--color-danger)', '7': 'var(--color-success)', '8': 'var(--color-neutral)',
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
  const [hideZeroBalances, setHideZeroBalances] = useState(true)
  const [collapsedClasses, setCollapsedClasses] = useState<Set<string>>(new Set())

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

  const tiersByAccount = useMemo(() => {
    const m = new Map<string, number>()
    for (const tp of tiers) {
      const codes = [tp.account_general_code, tp.code?.substring(0, 3), tp.code?.substring(0, 6)].filter(Boolean) as string[]
      for (const code of codes) { m.set(code, (m.get(code) || 0) + 1) }
    }
    return m
  }, [tiers])

  const filtered = useMemo(() => {
    return accounts.filter((a) => {
      const matchSearch = !search || a.code.includes(search) || a.name.toLowerCase().includes(search.toLowerCase())
      const matchClass = !filterClass || a.code.startsWith(filterClass)
      const matchBalance = !hideZeroBalances || (Number(a.balance) || 0) !== 0
      return matchSearch && matchClass && matchBalance
    })
  }, [accounts, search, filterClass, hideZeroBalances])

  const classStats = useMemo(() => {
    const stats: Record<string, { count: number; totalBalance: number; activeCount: number }> = {}
    for (const a of accounts) {
      const cls = a.code.charAt(0)
      if (!stats[cls]) stats[cls] = { count: 0, totalBalance: 0, activeCount: 0 }
      stats[cls].count++
      stats[cls].totalBalance += Number(a.balance) || 0
      if ((Number(a.balance) || 0) !== 0) stats[cls].activeCount++
    }
    return stats
  }, [accounts])

  const filteredIds = new Set(filtered.map((a) => a.id))

  const childrenByParent = useMemo(() => {
    const m = new Map<string, ChartAccount[]>()
    for (const a of filtered) {
      if (a.parent_id) {
        const children = m.get(a.parent_id) || []
        children.push(a)
        m.set(a.parent_id, children)
      }
    }
    return m
  }, [filtered])

  const rootAccounts = filtered.filter((a) => !a.parent_id || !filteredIds.has(a.parent_id))

  function toggleExpand(id: string) {
    setExpanded((prev) => {
      const next = new Set(prev)
      if (next.has(id)) next.delete(id)
      else next.add(id)
      return next
    })
  }

  function toggleClassCollapse(cls: string) {
    setCollapsedClasses((prev) => {
      const next = new Set(prev)
      if (next.has(cls)) next.delete(cls)
      else next.add(cls)
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
      <Fragment key={account.id}>
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
          <TableCell className={`font-mono text-right ${(Number(account.balance) || 0) !== 0 ? 'font-semibold' : 'text-[var(--color-text-secondary)]'}`}>
            {formatCurrency(Number(account.balance) || 0)}
          </TableCell>
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
      </Fragment>
    )
  }

  const grouped = useMemo(() => {
    return rootAccounts.reduce((acc, account) => {
      const cls = account.code.charAt(0)
      if (!acc[cls]) acc[cls] = []
      acc[cls].push(account)
      return acc
    }, {} as Record<string, ChartAccount[]>)
  }, [rootAccounts])

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

  const totalAccounts = accounts.length
  const activeAccounts = accounts.filter((a) => (Number(a.balance) || 0) !== 0).length

  return (
    <div>
      <Breadcrumb items={[{ label: t('title') }, { label: t('chartAccounts.breadcrumb') }, { label: t('chartAccounts.title') }]} />
      <PageHeader
        title={t('chartAccounts.title')}
        subtitle={t('chartAccounts.subtitle', { count: accounts.length })}
        action={<Button onClick={openCreate}><Plus className="w-4 h-4" /> {t('chartAccounts.new')}</Button>}
      />

      {/* Class overview dashboard */}
      {!loading && accounts.length > 0 && (
        <div className="grid grid-cols-2 sm:grid-cols-4 lg:grid-cols-8 gap-3 mb-6">
          {Object.entries(classStats).sort(([a], [b]) => a.localeCompare(b)).map(([cls, stats]) => (
            <button
              key={cls}
              onClick={() => setFilterClass(filterClass === cls ? '' : cls)}
              className={`text-left p-3 rounded-lg border transition-all hover:shadow-md ${filterClass === cls ? 'border-[var(--color-primary)] bg-[var(--color-primary)]/5 ring-1 ring-[var(--color-primary)]' : 'border-[var(--color-border)] hover:border-[var(--color-text-secondary)]'}`}
            >
              <div className="flex items-center gap-2 mb-1">
                <span className="w-2 h-2 rounded-full" style={{ backgroundColor: CLASS_COLORS[cls] || 'var(--color-neutral)' }} />
                <span className="text-xs font-semibold text-[var(--color-text-secondary)] uppercase">{t('chartAccounts.classLabel', { cls })}</span>
              </div>
              <div className="text-lg font-bold">{stats.count}</div>
              <div className="text-xs text-[var(--color-text-secondary)]">
                {t('chartAccounts.activeAccounts', { count: stats.activeCount })}
              </div>
              <div className="text-xs font-mono mt-1 text-[var(--color-text-secondary)] truncate">
                {formatCurrency(stats.totalBalance)}
              </div>
            </button>
          ))}
        </div>
      )}

      {/* Search & filters */}
      <div className="flex flex-wrap gap-3 mb-4 items-center">
        <div className="flex-1 relative min-w-[200px]">
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
        <button
          onClick={() => setHideZeroBalances(!hideZeroBalances)}
          className={`flex items-center gap-2 px-3 py-2 rounded-lg border text-sm transition-colors ${hideZeroBalances ? 'border-[var(--color-primary)] text-[var(--color-primary)] bg-[var(--color-primary)]/5' : 'border-[var(--color-border)] text-[var(--color-text-secondary)] hover:bg-[var(--color-neutral-50)]'}`}
        >
          {hideZeroBalances ? <Eye className="w-4 h-4" /> : <EyeOff className="w-4 h-4" />}
          {hideZeroBalances ? t('chartAccounts.showAll') : t('chartAccounts.hideZeroBalances')}
        </button>
      </div>

      {/* Results count */}
      {!loading && (
        <div className="text-sm text-[var(--color-text-secondary)] mb-3">
          {t('chartAccounts.resultsCount', { shown: filtered.length, total: totalAccounts, active: activeAccounts })}
        </div>
      )}

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
        <div className="space-y-4">
          {sortedClasses.map((cls) => {
            const isCollapsed = collapsedClasses.has(cls)
            const stats = classStats[cls]
            return (
              <Card key={cls}>
                <div
                  className="flex items-center justify-between px-4 py-3 cursor-pointer hover:bg-[var(--color-neutral-50)] rounded-t-lg"
                  onClick={() => toggleClassCollapse(cls)}
                >
                  <div className="flex items-center gap-3">
                    <span className="w-3 h-3 rounded-full" style={{ backgroundColor: CLASS_COLORS[cls] || 'var(--color-neutral)' }} />
                    <span className="font-semibold text-sm">
                      {t(`chartAccounts.classLabels.${cls}`, { defaultValue: `Classe ${cls}` })}
                    </span>
                    <Badge variant="neutral">{t('chartAccounts.accountCount', { count: grouped[cls].length })}</Badge>
                  </div>
                  <div className="flex items-center gap-3">
                    <span className="text-sm font-mono text-[var(--color-text-secondary)]">
                      {formatCurrency(stats?.totalBalance || 0)}
                    </span>
                    {isCollapsed ? <ChevronRight className="w-4 h-4 text-[var(--color-text-secondary)]" /> : <ChevronDown className="w-4 h-4 text-[var(--color-text-secondary)]" />}
                  </div>
                </div>
                {!isCollapsed && (
                  <Table headers={[tCommon('common.code'), tCommon('common.label'), tCommon('common.type'), t('chartAccounts.thirdPartyLink'), tCommon('common.balance'), tCommon('table.actions')]}>
                    {grouped[cls].map((account) => renderAccount(account, 0))}
                  </Table>
                )}
              </Card>
            )
          })}
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
  const [activeTab, setActiveTab] = useState('compte')
  const [code, setCode] = useState(account?.code || '')
  const [name, setName] = useState(account?.name || '')
  const [type, setType] = useState<'asset' | 'liability' | 'equity' | 'income' | 'expense'>(account?.type || 'asset')
  const [balance, setBalance] = useState(String(account?.balance || 0))
  const [vatRate, setVatRate] = useState(account?.vat_rate || '')
  const [parentId, setParentId] = useState(account?.parent_id || '')
  const [description, setDescription] = useState(account?.description || '')
  const [saving, setSaving] = useState(false)

  const racine = code.substring(0, Math.min(code.length, 3))
  const classe = code.charAt(0) || ''

  const parentOptions = accounts
    .filter((a) => a.id !== account?.id && a.code.length < (code.length || 10) && (!code || a.code.charAt(0) === code.charAt(0)))
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

  const tabs = [
    { id: 'compte', label: t('chartAccounts.tabs.compte') },
    { id: 'complement', label: t('chartAccounts.tabs.complement') },
    { id: 'n1', label: t('chartAccounts.tabs.exerciseN1') },
    { id: 'n', label: t('chartAccounts.tabs.exerciseN') },
    { id: 'n1plus', label: t('chartAccounts.tabs.exerciseN1plus') },
    { id: 'free', label: t('chartAccounts.tabs.freeInfo') },
  ]

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl overflow-hidden" style={{ width: '100%', maxWidth: '42rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{account ? t('chartAccounts.edit') : t('chartAccounts.create')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit}>
          <div className="flex border-b border-[var(--color-border)] px-6">
            {tabs.map((tab) => (
              <button
                key={tab.id}
                type="button"
                onClick={() => setActiveTab(tab.id)}
                className={`px-4 py-2.5 text-sm font-medium border-b-2 transition-colors ${
                  activeTab === tab.id
                    ? 'border-[var(--color-primary)] text-[var(--color-primary)]'
                    : 'border-transparent text-[var(--color-text-secondary)] hover:text-[var(--color-text)]'
                }`}
              >
                {tab.label}
              </button>
            ))}
          </div>

          <div className="p-6 space-y-4">
            {activeTab === 'compte' && (
              <>
                <div className="grid grid-cols-2 gap-4">
                  <Input label={t('chartAccounts.accountNumber')} required value={code} onChange={(e) => setCode(e.target.value)} placeholder="411000" />
                  <Input label={t('chartAccounts.designation')} required value={name} onChange={(e) => setName(e.target.value)} placeholder="" />
                </div>
                <div className="grid grid-cols-3 gap-4">
                  <Input label={t('chartAccounts.racine')} value={racine} disabled placeholder="411" />
                  <Input label={t('chartAccounts.classe')} value={classe} disabled placeholder="4" />
                  <Select label={t('chartAccounts.nature')} value={type} onChange={(e) => setType(e.target.value as 'asset' | 'liability' | 'equity' | 'income' | 'expense')} options={[
                    { value: 'asset', label: t('chartAccounts.natures.asset') },
                    { value: 'liability', label: t('chartAccounts.natures.liability') },
                    { value: 'equity', label: t('chartAccounts.natures.equity') },
                    { value: 'income', label: t('chartAccounts.natures.income') },
                    { value: 'expense', label: t('chartAccounts.natures.expense') },
                  ]} />
                </div>
                <div>
                  <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">{t('chartAccounts.parent')}</label>
                  <select className="input" value={parentId} onChange={(e) => setParentId(e.target.value)}>
                    <option value="">{t('chartAccounts.noParent')}</option>
                    {parentOptions.map((a) => <option key={a.id} value={a.id}>{a.code} — {a.name}</option>)}
                  </select>
                </div>
              </>
            )}

            {activeTab === 'complement' && (
              <>
                <div className="grid grid-cols-2 gap-4">
                  <Input label={t('chartAccounts.defaultTaxCode')} value={vatRate} onChange={(e) => setVatRate(e.target.value)} placeholder="20" />
                  <Input label={t('chartAccounts.nbLines')} type="number" value="" onChange={() => {}} placeholder="0" />
                </div>
                <div className="grid grid-cols-2 gap-4">
                  <Input label={t('chartAccounts.pageBreak')} type="number" value="" onChange={() => {}} placeholder="0" />
                  <Input label={t('chartAccounts.regrouping')} value="" onChange={() => {}} placeholder="" />
                </div>
                <div className="grid grid-cols-3 gap-4">
                  <label className="flex items-center gap-2 text-sm pt-6">
                    <input type="checkbox" defaultChecked />
                    {t('chartAccounts.analyticEntry')}
                  </label>
                  <label className="flex items-center gap-2 text-sm pt-6">
                    <input type="checkbox" defaultChecked />
                    {t('chartAccounts.echeanceEntry')}
                  </label>
                  <label className="flex items-center gap-2 text-sm pt-6">
                    <input type="checkbox" defaultChecked />
                    {t('chartAccounts.tiersEntry')}
                  </label>
                </div>
                <Input label={tCommon('common.description')} value={description} onChange={(e) => setDescription(e.target.value)} />
              </>
            )}

            {activeTab === 'n1' && (
              <>
                <div className="grid grid-cols-2 gap-4">
                  <Input label={t('chartAccounts.debitN1')} type="number" value="0" disabled />
                  <Input label={t('chartAccounts.creditN1')} type="number" value="0" disabled />
                </div>
                <div className="text-sm text-[var(--color-text-secondary)] p-3 rounded-lg bg-[var(--color-neutral-50)]">
                  {t('chartAccounts.exerciseHint')}
                </div>
              </>
            )}

            {activeTab === 'n' && (
              <>
                <div className="grid grid-cols-3 gap-4">
                  <Input label={t('chartAccounts.debitN')} type="number" value={balance} onChange={(e) => setBalance(e.target.value)} />
                  <Input label={t('chartAccounts.creditN')} type="number" value="0" disabled />
                  <Input label={t('chartAccounts.soldeN')} type="number" value={balance} disabled />
                </div>
              </>
            )}

            {activeTab === 'n1plus' && (
              <>
                <div className="grid grid-cols-2 gap-4">
                  <Input label={t('chartAccounts.debitN1plus')} type="number" value="0" disabled />
                  <Input label={t('chartAccounts.creditN1plus')} type="number" value="0" disabled />
                </div>
                <div className="text-sm text-[var(--color-text-secondary)] p-3 rounded-lg bg-[var(--color-neutral-50)]">
                  {t('chartAccounts.exerciseFutureHint')}
                </div>
              </>
            )}

            {activeTab === 'free' && (
              <>
                <div className="space-y-3">
                  {Array.from({ length: 10 }, (_, i) => (
                    <div key={i} className="grid grid-cols-2 gap-4">
                      <Input label={t('chartAccounts.freeFieldLabel', { n: i + 1 })} value="" onChange={() => {}} placeholder="" />
                      <Input label={t('chartAccounts.freeFieldValue', { n: i + 1 })} value="" onChange={() => {}} placeholder="" />
                    </div>
                  )).slice(0, 5)}
                </div>
                <p className="text-xs text-[var(--color-text-secondary)]">{t('chartAccounts.freeInfoHint')}</p>
              </>
            )}
          </div>

          <div className="flex justify-end gap-3 px-6 py-4 border-t border-[var(--color-border)]">
            <Button variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? tCommon('common.saving') : tCommon('actions.save')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
