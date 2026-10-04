import { useState, useEffect, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Link } from 'react-router-dom'
import { QuickAccessModal } from './QuickAccessModal'
import { Button, Input, Select, EmptyState, Table, TableRow, TableCell } from '@/components/ui'
import { getBankAccounts, createBankAccount } from '@/lib/queries/banking'
import { useToast } from '@/lib/toast'
import { useModuleAwareAccess } from './useModuleAwareAccess'
import { Landmark, Plus, ExternalLink, Search } from 'lucide-react'
import type { BankAccount } from '@/types'

interface QuickBankAccountAccessProps {
  onClose: () => void
  onSaved?: (account: BankAccount) => void
  forceInline?: boolean
}

/**
 * Cross-module Quick Access for Bank Accounts.
 * - If treasury module is active → link to /treasury/bank-accounts
 * - If treasury module is NOT active → inline mini-CRUD
 */
export function QuickBankAccountAccess({ onClose, onSaved, forceInline }: QuickBankAccountAccessProps) {
  const { t } = useTranslation('crossModule')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const { getAccessStrategy } = useModuleAwareAccess()

  const strategy = forceInline ? 'inline' : getAccessStrategy('treasury')
  const [accounts, setAccounts] = useState<BankAccount[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [search, setSearch] = useState('')

  const [name, setName] = useState('')
  const [bankName, setBankName] = useState('')
  const [accountNumber, setAccountNumber] = useState('')
  const [type, setType] = useState<'chequing' | 'savings' | 'credit_card' | 'cash' | 'loan' | 'other'>('chequing')
  const [saving, setSaving] = useState(false)

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      setAccounts(await getBankAccounts())
    } catch (err: any) { console.error("catch:", err); toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadingError'))
      /* ignore */
    } finally {
      setLoading(false)
    }
  }, [tCommon, toast])

  useEffect(() => {
    if (strategy === 'inline') loadData().catch(err => console.error('loadData:', err))
  }, [strategy, loadData])

  async function handleSave(e: React.FormEvent) {
    e.preventDefault()
    if (!name.trim()) return
    setSaving(true)
    try {
      const acc = await createBankAccount({
        name: name.trim(),
        bank_name: bankName.trim(),
        account_number: accountNumber.trim(),
        type,
        sort_code: '',
        balance: 0,
        currency: 'EUR',
        connected: false,
      } as Omit<BankAccount, 'id' | 'created_at' | 'updated_at'>)
      toast('success', tCommon('common.success'), t('bankAccount.created'))
      onSaved?.(acc)
      await loadData()
      setShowForm(false)
      setName(''); setBankName(''); setAccountNumber('')
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || t('bankAccount.createError'))
    } finally {
      setSaving(false)
    }
  }

  const filtered = accounts.filter((a) =>
    !search || a.name.toLowerCase().includes(search.toLowerCase()) || (a.bank_name || '').toLowerCase().includes(search.toLowerCase()),
  )

  if (strategy === 'full' && !forceInline) {
    return (
      <QuickAccessModal title={t('bankAccount.title')} onClose={onClose}>
        <EmptyState
          icon={<Landmark className="w-8 h-8" />}
          title={t('bankAccount.moduleActive')}
          description={t('bankAccount.moduleActiveDescription')}
          action={
            <Link to="/treasury/bank-accounts" onClick={onClose}>
              <Button><ExternalLink className="w-4 h-4" /> {t('bankAccount.goToBankAccounts')}</Button>
            </Link>
          }
        />
      </QuickAccessModal>
    )
  }

  return (
    <QuickAccessModal title={t('bankAccount.title')} onClose={onClose}>
      <div className="space-y-4">
        <div className="flex items-center gap-2">
          <div className="relative flex-1">
            <Search className="w-4 h-4 absolute left-3 top-1/2 -translate-y-1/2 text-[var(--color-text-tertiary)]" />
            <input
              type="text"
              placeholder={t('bankAccount.search')}
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              className="w-full pl-9 pr-3 py-2 text-sm border border-[var(--color-border)] rounded-lg bg-[var(--color-surface)] outline-none focus:border-[var(--color-primary)]"
            />
          </div>
          <Button size="sm" onClick={() => setShowForm(!showForm)}>
            <Plus className="w-4 h-4" /> {t('bankAccount.add')}
          </Button>
        </div>

        {showForm && (
          <form onSubmit={handleSave} className="space-y-3 p-4 rounded-lg border border-[var(--color-border)] bg-[var(--color-neutral-50)]">
            <Input label={t('bankAccount.name')} required value={name} onChange={(e) => setName(e.target.value)} />
            <div className="grid grid-cols-2 gap-3">
              <Input label={t('bankAccount.bankName')} value={bankName} onChange={(e) => setBankName(e.target.value)} />
              <Input label={t('bankAccount.accountNumber')} value={accountNumber} onChange={(e) => setAccountNumber(e.target.value)} />
            </div>
            <Select
              label={t('bankAccount.type')}
              value={type}
              onChange={(e) => setType(e.target.value as any)}
              options={[
                { value: 'chequing', label: t('bankAccount.types.chequing') },
                { value: 'savings', label: t('bankAccount.types.savings') },
                { value: 'credit_card', label: t('bankAccount.types.credit_card') },
                { value: 'cash', label: t('bankAccount.types.cash') },
                { value: 'loan', label: t('bankAccount.types.loan') },
                { value: 'other', label: t('bankAccount.types.other') },
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
            icon={<Landmark className="w-8 h-8" />}
            title={t('bankAccount.noBankAccounts')}
            description={t('bankAccount.noBankAccountsDescription')}
            action={<Button size="sm" onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('bankAccount.add')}</Button>}
          />
        ) : (
          <Table headers={[t('bankAccount.name'), t('bankAccount.bankName'), t('bankAccount.type')]}>
            {filtered.slice(0, 20).map((a) => (
              <TableRow key={a.id}>
                <TableCell className="font-medium">{a.name}</TableCell>
                <TableCell className="text-sm">{a.bank_name || '—'}</TableCell>
                <TableCell className="text-sm">{t(`bankAccount.types.${a.type}`)}</TableCell>
              </TableRow>
            ))}
          </Table>
        )}
      </div>
    </QuickAccessModal>
  )
}
