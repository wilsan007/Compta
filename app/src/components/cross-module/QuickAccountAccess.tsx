import { useState, useEffect, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Link } from 'react-router-dom'
import { QuickAccessModal } from './QuickAccessModal'
import { Button, Input, Select, EmptyState, Table, TableRow, TableCell } from '@/components/ui'
import { getChartAccounts, createChartAccount } from '@/lib/queries'
import { useToast } from '@/lib/toast'
import { useModuleAwareAccess } from './useModuleAwareAccess'
import { BookOpen, Plus, ExternalLink, Search } from 'lucide-react'
import type { ChartAccount } from '@/types'

interface QuickAccountAccessProps {
  onClose: () => void
  onSaved?: (account: ChartAccount) => void
  forceInline?: boolean
}

/**
 * Cross-module Quick Access for Chart of Accounts.
 * - If accounting module is active → link to /accounting/chart-of-accounts
 * - If accounting module is NOT active → inline mini-CRUD
 */
export function QuickAccountAccess({ onClose, onSaved, forceInline }: QuickAccountAccessProps) {
  const { t } = useTranslation('crossModule')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const { getAccessStrategy } = useModuleAwareAccess()

  const strategy = forceInline ? 'inline' : getAccessStrategy('accounting')
  const [accounts, setAccounts] = useState<ChartAccount[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [search, setSearch] = useState('')

  const [code, setCode] = useState('')
  const [name, setName] = useState('')
  const [type, setType] = useState<'asset' | 'liability' | 'equity' | 'income' | 'expense'>('asset')
  const [saving, setSaving] = useState(false)

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      setAccounts(await getChartAccounts())
    } catch {
      /* ignore */
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    if (strategy === 'inline') loadData()
  }, [strategy, loadData])

  async function handleSave(e: React.FormEvent) {
    e.preventDefault()
    if (!code.trim() || !name.trim()) return
    setSaving(true)
    try {
      const acc = await createChartAccount({
        code: code.trim(),
        name: name.trim(),
        type,
        balance: 0,
        vat_rate: '0',
        description: '',
        parent_id: null,
      } as Omit<ChartAccount, 'id'>)
      toast('success', tCommon('common.success'), t('account.created'))
      onSaved?.(acc)
      await loadData()
      setShowForm(false)
      setCode(''); setName('')
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || t('account.createError'))
    } finally {
      setSaving(false)
    }
  }

  const filtered = accounts.filter((a) =>
    !search || a.code.includes(search) || a.name.toLowerCase().includes(search.toLowerCase()),
  )

  if (strategy === 'full' && !forceInline) {
    return (
      <QuickAccessModal title={t('account.title')} onClose={onClose}>
        <EmptyState
          icon={<BookOpen className="w-8 h-8" />}
          title={t('account.moduleActive')}
          description={t('account.moduleActiveDescription')}
          action={
            <Link to="/accounting/chart-of-accounts" onClick={onClose}>
              <Button><ExternalLink className="w-4 h-4" /> {t('account.goToAccounts')}</Button>
            </Link>
          }
        />
      </QuickAccessModal>
    )
  }

  return (
    <QuickAccessModal title={t('account.title')} onClose={onClose}>
      <div className="space-y-4">
        <div className="flex items-center gap-2">
          <div className="relative flex-1">
            <Search className="w-4 h-4 absolute left-3 top-1/2 -translate-y-1/2 text-[var(--color-text-tertiary)]" />
            <input
              type="text"
              placeholder={t('account.search')}
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              className="w-full pl-9 pr-3 py-2 text-sm border border-[var(--color-border)] rounded-lg bg-[var(--color-surface)] outline-none focus:border-[var(--color-primary)]"
            />
          </div>
          <Button size="sm" onClick={() => setShowForm(!showForm)}>
            <Plus className="w-4 h-4" /> {t('account.add')}
          </Button>
        </div>

        {showForm && (
          <form onSubmit={handleSave} className="space-y-3 p-4 rounded-lg border border-[var(--color-border)] bg-[var(--color-neutral-50)]">
            <div className="grid grid-cols-2 gap-3">
              <Input label={t('account.code')} required value={code} onChange={(e) => setCode(e.target.value)} />
              <Input label={t('account.name')} required value={name} onChange={(e) => setName(e.target.value)} />
            </div>
            <Select
              label={t('account.type')}
              value={type}
              onChange={(e) => setType(e.target.value as any)}
              options={[
                { value: 'asset', label: t('account.types.asset') },
                { value: 'liability', label: t('account.types.liability') },
                { value: 'equity', label: t('account.types.equity') },
                { value: 'income', label: t('account.types.income') },
                { value: 'expense', label: t('account.types.expense') },
              ]}
            />
            <div className="flex justify-end gap-2">
              <Button type="button" variant="secondary" size="sm" onClick={() => setShowForm(false)}>{tCommon('actions.cancel')}</Button>
              <Button type="submit" size="sm" disabled={saving}>{saving ? '...' : tCommon('actions.save')}</Button>
            </div>
          </form>
        )}

        {loading ? (
          <p className="text-sm text-[var(--color-text-secondary)] text-center py-8">{tCommon('common.loading')}</p>
        ) : filtered.length === 0 ? (
          <EmptyState
            icon={<BookOpen className="w-8 h-8" />}
            title={t('account.noAccounts')}
            description={t('account.noAccountsDescription')}
            action={<Button size="sm" onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('account.add')}</Button>}
          />
        ) : (
          <Table headers={[t('account.code'), t('account.name'), t('account.type')]}>
            {filtered.slice(0, 20).map((a) => (
              <TableRow key={a.id}>
                <TableCell className="font-mono text-xs">{a.code}</TableCell>
                <TableCell className="font-medium">{a.name}</TableCell>
                <TableCell className="text-sm">{t(`account.types.${a.type}`)}</TableCell>
              </TableRow>
            ))}
          </Table>
        )}
      </div>
    </QuickAccessModal>
  )
}
