import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Button, Table, TableRow, TableCell, Badge, EmptyState, Input, Select } from '@/components/ui'
import { getPartnerBankAccounts, createPartnerBankAccount, updatePartnerBankAccount, deletePartnerBankAccount } from '@/lib/queries/partners'
import { validateIBAN } from '@/lib/queries/misc'
import { Plus, Trash2, X, Pencil, CheckCircle, XCircle, Landmark } from 'lucide-react'
import type { PartnerBankAccount } from '@/types'
import { useToast } from '@/lib/toast'
import { confirmSync } from '@/lib/confirm'

interface Props {
  partnerType: 'customer' | 'supplier'
  partnerId: string
  onClose: () => void
}

export function PartnerBankAccountsModal({ partnerType, partnerId, onClose }: Props) {
  const { t } = useTranslation('banking')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [accounts, setAccounts] = useState<PartnerBankAccount[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [editing, setEditing] = useState<PartnerBankAccount | null>(null)

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const data = await getPartnerBankAccounts(partnerType, partnerId)
      setAccounts(data)
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message || '')
    } finally {
      setLoading(false)
    }
  }, [partnerType, partnerId, tCommon, toast])

  useEffect(() => { loadData() }, [loadData])

  async function handleDelete(id: string) {
    if (!confirmSync(t('partnerBankAccounts.deleteConfirm'))) return
    try {
      await deletePartnerBankAccount(id)
      toast('success', tCommon('common.success'), t('partnerBankAccounts.deleted'))
      await loadData()
    } catch (err: any) {
      toast('error', tCommon('toast.error'), t('partnerBankAccounts.deleteError') + ': ' + (err.message || ''))
    }
  }

  function openCreate() {
    setEditing(null)
    setShowForm(true)
  }

  function openEdit(acc: PartnerBankAccount) {
    setEditing(acc)
    setShowForm(true)
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '42rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('partnerBankAccounts.title')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>

        <div className="p-6">
          <div className="flex items-center justify-between mb-4">
            <p className="text-sm text-[var(--color-text-secondary)]">{t('partnerBankAccounts.subtitle')}</p>
            <Button size="sm" onClick={openCreate}><Plus className="w-4 h-4" /> {t('partnerBankAccounts.new')}</Button>
          </div>

          {loading ? (
            <p className="text-sm text-[var(--color-text-secondary)]">...</p>
          ) : accounts.length === 0 ? (
            <EmptyState
              icon={<Landmark className="w-8 h-8" />}
              title={t('partnerBankAccounts.noAccounts')}
              description={t('partnerBankAccounts.noAccountsDesc')}
              action={<Button size="sm" onClick={openCreate}><Plus className="w-4 h-4" /> {t('partnerBankAccounts.new')}</Button>}
            />
          ) : (
            <Table headers={[
              t('partnerBankAccounts.accountNumber'),
              t('partnerBankAccounts.bankName'),
              t('partnerBankAccounts.bic'),
              t('partnerBankAccounts.currency'),
              t('partnerBankAccounts.isDefault'),
              tCommon('table.actions'),
            ]}>
              {accounts.map((acc) => (
                <TableRow key={acc.id}>
                  <TableCell className="font-mono text-xs">{acc.account_number}</TableCell>
                  <TableCell className="text-sm">{acc.bank_name || '—'}</TableCell>
                  <TableCell className="font-mono text-xs">{acc.bic || '—'}</TableCell>
                  <TableCell className="text-xs">{acc.currency_code}</TableCell>
                  <TableCell>
                    {acc.is_default ? <Badge variant="success">{tCommon('common.yes')}</Badge> : <Badge variant="neutral">{tCommon('common.no')}</Badge>}
                  </TableCell>
                  <TableCell>
                    <div className="flex items-center gap-1">
                      <button onClick={() => openEdit(acc)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-text-secondary)]">
                        <Pencil className="w-4 h-4" />
                      </button>
                      <button onClick={() => handleDelete(acc.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]">
                        <Trash2 className="w-4 h-4" />
                      </button>
                    </div>
                  </TableCell>
                </TableRow>
              ))}
            </Table>
          )}

          {showForm && (
            <PartnerBankAccountForm
              partnerType={partnerType}
              partnerId={partnerId}
              account={editing}
              onClose={() => setShowForm(false)}
              onSaved={() => { setShowForm(false); loadData() }}
            />
          )}
        </div>
      </div>
    </div>
  )
}

function PartnerBankAccountForm({ partnerType, partnerId, account, onClose, onSaved }: {
  partnerType: 'customer' | 'supplier'
  partnerId: string
  account: PartnerBankAccount | null
  onClose: () => void
  onSaved: () => void
}) {
  const { t } = useTranslation('banking')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [accountNumber, setAccountNumber] = useState(account?.account_number || '')
  const [bankName, setBankName] = useState(account?.bank_name || '')
  const [bic, setBic] = useState(account?.bic || '')
  const [bankCode, setBankCode] = useState(account?.bank_code || '')
  const [sortCode, setSortCode] = useState(account?.sort_code || '')
  const [accountKey, setAccountKey] = useState(account?.account_key || '')
  const [currencyCode, setCurrencyCode] = useState(account?.currency_code || 'EUR')
  const [isDefault, setIsDefault] = useState(account?.is_default || false)
  const [ibanValid, setIbanValid] = useState<boolean | null>(null)
  const [saving, setSaving] = useState(false)

  function checkIBAN(value: string) {
    setAccountNumber(value)
    if (value.length > 5) {
      setIbanValid(validateIBAN(value))
    } else {
      setIbanValid(null)
    }
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      const data = {
        partner_type: partnerType,
        partner_id: partnerId,
        account_number: accountNumber,
        bank_name: bankName || null,
        bic: bic || null,
        bank_code: bankCode || null,
        sort_code: sortCode || null,
        account_key: accountKey || null,
        currency_code: currencyCode,
        is_default: isDefault,
        active: true,
      }
      if (account) {
        await updatePartnerBankAccount(account.id, data)
      } else {
        await createPartnerBankAccount(data as any)
      }
      toast('success', tCommon('common.success'), t('partnerBankAccounts.saved'))
      onSaved()
    } catch (err: any) {
      toast('error', tCommon('toast.error'), t('partnerBankAccounts.saveError') + ': ' + (err.message || ''))
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9991] flex items-center justify-center p-4">
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '36rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h3 className="text-lg font-semibold">{account ? t('partnerBankAccounts.edit') : t('partnerBankAccounts.new')}</h3>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4 max-h-[60vh] overflow-y-auto">
          <div>
            <div className="flex items-center justify-between">
              <label className="text-sm font-medium">{t('partnerBankAccounts.accountNumber')}</label>
              {ibanValid !== null && (
                <span className={`text-xs flex items-center gap-1 ${ibanValid ? 'text-[var(--color-success)]' : 'text-[var(--color-danger)]'}`}>
                  {ibanValid ? <><CheckCircle className="w-3 h-3" /> {t('partnerBankAccounts.ibanValid')}</> : <><XCircle className="w-3 h-3" /> {t('partnerBankAccounts.ibanInvalid')}</>}
                </span>
              )}
            </div>
            <Input required value={accountNumber} onChange={(e) => checkIBAN(e.target.value)} placeholder="FR76 1234 5678 9012 3456 7890 123" />
          </div>
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('partnerBankAccounts.bankName')} value={bankName} onChange={(e) => setBankName(e.target.value)} placeholder="BNP Paribas" />
            <Input label={t('partnerBankAccounts.bic')} value={bic} onChange={(e) => setBic(e.target.value)} placeholder="ABCDEFGHXXX" />
          </div>
          <div className="grid grid-cols-3 gap-4">
            <Input label={t('partnerBankAccounts.bankCode')} value={bankCode} onChange={(e) => setBankCode(e.target.value)} placeholder="12345" />
            <Input label={t('partnerBankAccounts.sortCode')} value={sortCode} onChange={(e) => setSortCode(e.target.value)} placeholder="67890" />
            <Input label={t('partnerBankAccounts.accountKey')} value={accountKey} onChange={(e) => setAccountKey(e.target.value)} placeholder="23" />
          </div>
          <Select label={t('partnerBankAccounts.currency')} value={currencyCode} onChange={(e) => setCurrencyCode(e.target.value)} options={[
            { value: 'EUR', label: 'EUR' },
            { value: 'USD', label: 'USD ($)' },
            { value: 'GBP', label: 'GBP (£)' },
            { value: 'MAD', label: 'MAD' },
          ]} />
          <label className="flex items-center gap-2 text-sm">
            <input type="checkbox" checked={isDefault} onChange={(e) => setIsDefault(e.target.checked)} />
            {t('partnerBankAccounts.isDefault')}
          </label>
          <div className="flex justify-end gap-3 pt-4 border-t border-[var(--color-border)]">
            <Button variant="secondary" type="button" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? tCommon('actions.saving') : tCommon('actions.save')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
