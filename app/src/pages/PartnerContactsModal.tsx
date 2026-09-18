import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Button, Input, Select, Badge, Card, Table, TableRow, TableCell, EmptyState, SkeletonTable } from '@/components/ui'
import { X, Plus, Trash2, Edit2, Users, Building } from 'lucide-react'
import { useToast } from '@/lib/toast'
import { getPartnerContacts, createPartnerContact, updatePartnerContact, deletePartnerContact, getPartnerBankAccounts, createPartnerBankAccount, updatePartnerBankAccount, deletePartnerBankAccount } from '@/lib/queries/partners'
import type { PartnerContact, PartnerBankAccount } from '@/types'

interface Props {
  partnerType: 'customer' | 'supplier'
  partnerId: string
  partnerName: string
  onClose: () => void
}

export function PartnerContactsModal({ partnerType, partnerId, partnerName, onClose }: Props) {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [activeTab, setActiveTab] = useState<'contacts' | 'bank'>('contacts')
  const [contacts, setContacts] = useState<PartnerContact[]>([])
  const [bankAccounts, setBankAccounts] = useState<PartnerBankAccount[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [editingContact, setEditingContact] = useState<PartnerContact | null>(null)
  const [editingBank, setEditingBank] = useState<PartnerBankAccount | null>(null)

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const [c, b] = await Promise.all([
        getPartnerContacts(partnerType, partnerId).catch(() => []),
        getPartnerBankAccounts(partnerType, partnerId).catch(() => []),
      ])
      setContacts(c || [])
      setBankAccounts(b || [])
    } catch (e: any) { console.error('catch:', e); toast('error', tCommon('toast.error'), e.message || tCommon('toast.loadError')) } finally { setLoading(false) }
  }, [partnerType, partnerId, tCommon, toast])

  useEffect(() => { loadData() }, [loadData])

  const contactTypeBadge: Record<string, 'success' | 'warning' | 'danger' | 'neutral' | 'primary'> = {
    primary: 'primary', invoice: 'success', delivery: 'warning', other: 'neutral',
  }

  async function handleDeleteContact(id: string) {
    try {
      await deletePartnerContact(id)
      toast('success', tCommon('common.success'), t('partnerContacts.deleted'))
      await loadData()
    } catch (e: any) { toast('error', tCommon('common.error'), e.message) }
  }

  async function handleDeleteBank(id: string) {
    try {
      await deletePartnerBankAccount(id)
      toast('success', tCommon('common.success'), t('partnerContacts.bankDeleted'))
      await loadData()
    } catch (e: any) { toast('error', tCommon('common.error'), e.message) }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl overflow-hidden" style={{ width: '100%', maxWidth: '56rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold flex items-center gap-2">
            <Users className="w-5 h-5" />
            {t('partnerContacts.title')} — {partnerName}
          </h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]" aria-label={tCommon('actions.close')} title={tCommon('actions.close')}><X className="w-5 h-5" aria-hidden="true" /></button>
        </div>

        <div className="flex border-b border-[var(--color-border)] px-6">
          {[
            { id: 'contacts', label: t('partnerContacts.tabContacts'), icon: <Users className="w-4 h-4" /> },
            { id: 'bank', label: t('partnerContacts.tabBankAccounts'), icon: <Building className="w-4 h-4" /> },
          ].map((tab) => (
            <button
              key={tab.id}
              type="button"
              onClick={() => { setActiveTab(tab.id as any); setShowForm(false) }}
              className={`px-4 py-2.5 text-sm font-medium border-b-2 transition-colors flex items-center gap-2 whitespace-nowrap ${
                activeTab === tab.id
                  ? 'border-[var(--color-primary)] text-[var(--color-primary)]'
                  : 'border-transparent text-[var(--color-text-secondary)] hover:text-[var(--color-text)]'
              }`}
            >
              {tab.icon} {tab.label}
            </button>
          ))}
        </div>

        <div className="p-6 max-h-[60vh] overflow-y-auto">
          {activeTab === 'contacts' && (
            <>
              <div className="flex justify-end mb-3">
                <Button onClick={() => { setEditingContact(null); setShowForm(true) }}><Plus className="w-4 h-4" /> {t('partnerContacts.addContact')}</Button>
              </div>
              {showForm && !editingContact && (
                <ContactForm
                  partnerType={partnerType}
                  partnerId={partnerId}
                  onClose={() => setShowForm(false)}
                  onSaved={() => { setShowForm(false); loadData() }}
                />
              )}
              {showForm && editingContact && (
                <ContactForm
                  partnerType={partnerType}
                  partnerId={partnerId}
                  contact={editingContact}
                  onClose={() => { setShowForm(false); setEditingContact(null) }}
                  onSaved={() => { setShowForm(false); setEditingContact(null); loadData() }}
                />
              )}
              {loading ? <SkeletonTable rows={3} cols={5} /> : contacts.length === 0 ? (
                <EmptyState icon={<Users className="w-8 h-8" />} title={t('partnerContacts.noContacts')} />
              ) : (
                <Table headers={[
                  t('partnerContacts.colType'), t('partnerContacts.colName'),
                  t('partnerContacts.colEmail'), t('partnerContacts.colPhone'),
                  t('partnerContacts.colFunction'), t('partnerContacts.colDefault'),
                  tCommon('table.actions'),
                ]}>
                  {contacts.map((c) => (
                    <TableRow key={c.id}>
                      <TableCell><Badge variant={contactTypeBadge[c.contact_type] || 'neutral'}>{t(`partnerContacts.types.${c.contact_type}`)}</Badge></TableCell>
                      <TableCell className="font-medium">{c.name}</TableCell>
                      <TableCell className="text-xs">{c.email || '—'}</TableCell>
                      <TableCell className="text-xs">{c.phone || c.mobile || '—'}</TableCell>
                      <TableCell className="text-xs">{c.function || '—'}</TableCell>
                      <TableCell>{c.is_default ? <Badge variant="success">{tCommon('common.yes')}</Badge> : <Badge>{tCommon('common.no')}</Badge>}</TableCell>
                      <TableCell>
                        <div className="flex gap-1">
                          <Button variant="secondary" size="sm" onClick={() => { setEditingContact(c); setShowForm(true) }} ariaLabel={tCommon('actions.edit')}><Edit2 className="w-3 h-3" aria-hidden="true" /></Button>
                          <Button variant="danger" size="sm" onClick={() => handleDeleteContact(c.id)} ariaLabel={tCommon('actions.delete')}><Trash2 className="w-3 h-3" aria-hidden="true" /></Button>
                        </div>
                      </TableCell>
                    </TableRow>
                  ))}
                </Table>
              )}
            </>
          )}

          {activeTab === 'bank' && (
            <>
              <div className="flex justify-end mb-3">
                <Button onClick={() => { setEditingBank(null); setShowForm(true) }}><Plus className="w-4 h-4" /> {t('partnerContacts.addBankAccount')}</Button>
              </div>
              {showForm && !editingBank && (
                <BankAccountForm
                  partnerType={partnerType}
                  partnerId={partnerId}
                  onClose={() => setShowForm(false)}
                  onSaved={() => { setShowForm(false); loadData() }}
                />
              )}
              {showForm && editingBank && (
                <BankAccountForm
                  partnerType={partnerType}
                  partnerId={partnerId}
                  bankAccount={editingBank}
                  onClose={() => { setShowForm(false); setEditingBank(null) }}
                  onSaved={() => { setShowForm(false); setEditingBank(null); loadData() }}
                />
              )}
              {loading ? <SkeletonTable rows={3} cols={5} /> : bankAccounts.length === 0 ? (
                <EmptyState icon={<Building className="w-8 h-8" />} title={t('partnerContacts.noBankAccounts')} />
              ) : (
                <Table headers={[
                  t('partnerContacts.colIBAN'), t('partnerContacts.colBIC'),
                  t('partnerContacts.colBankName'), t('partnerContacts.colCurrency'),
                  t('partnerContacts.colDefault'), t('partnerContacts.colActive'), tCommon('table.actions'),
                ]}>
                  {bankAccounts.map((b) => (
                    <TableRow key={b.id}>
                      <TableCell className="font-mono text-xs">{b.account_number}</TableCell>
                      <TableCell className="font-mono text-xs">{b.bic || '—'}</TableCell>
                      <TableCell>{b.bank_name || '—'}</TableCell>
                      <TableCell><Badge>{b.currency_code}</Badge></TableCell>
                      <TableCell>{b.is_default ? <Badge variant="success">{tCommon('common.yes')}</Badge> : <Badge>{tCommon('common.no')}</Badge>}</TableCell>
                      <TableCell>{b.active ? <Badge variant="success">{tCommon('common.yes')}</Badge> : <Badge>{tCommon('common.no')}</Badge>}</TableCell>
                      <TableCell>
                        <div className="flex gap-1">
                          <Button variant="secondary" size="sm" onClick={() => { setEditingBank(b); setShowForm(true) }} ariaLabel={tCommon('actions.edit')}><Edit2 className="w-3 h-3" aria-hidden="true" /></Button>
                          <Button variant="danger" size="sm" onClick={() => handleDeleteBank(b.id)} ariaLabel={tCommon('actions.delete')}><Trash2 className="w-3 h-3" aria-hidden="true" /></Button>
                        </div>
                      </TableCell>
                    </TableRow>
                  ))}
                </Table>
              )}
            </>
          )}
        </div>
      </div>
    </div>
  )
}

function ContactForm({ partnerType, partnerId, contact, onClose, onSaved }: {
  partnerType: 'customer' | 'supplier'
  partnerId: string
  contact?: PartnerContact
  onClose: () => void
  onSaved: () => void
}) {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [form, setForm] = useState({
    contact_type: (contact?.contact_type || 'other') as 'primary' | 'invoice' | 'delivery' | 'other',
    name: contact?.name || '',
    email: contact?.email || '',
    phone: contact?.phone || '',
    mobile: contact?.mobile || '',
    function: contact?.function || '',
    address: contact?.address || '',
    postal_code: contact?.postal_code || '',
    city: contact?.city || '',
    country: contact?.country || '',
    is_default: contact?.is_default || false,
    active: contact?.active ?? true,
  })
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      const data = { ...form, partner_type: partnerType, partner_id: partnerId }
      if (contact) {
        await updatePartnerContact(contact.id, data)
        toast('success', tCommon('common.success'), t('partnerContacts.updated'))
      } else {
        await createPartnerContact(data as any)
        toast('success', tCommon('common.success'), t('partnerContacts.created'))
      }
      onSaved()
    } catch (e: any) {
      toast('error', tCommon('common.error'), e.message)
    } finally { setSaving(false) }
  }

  return (
    <Card className="p-4 mb-4 space-y-3">
      <form onSubmit={handleSubmit} className="space-y-3">
        <div className="grid grid-cols-2 gap-3">
          <Input label={t('partnerContacts.colName')} required value={form.name} onChange={e => setForm({ ...form, name: e.target.value })} />
          <Select label={t('partnerContacts.colType')} value={form.contact_type} onChange={e => setForm({ ...form, contact_type: e.target.value as 'primary' | 'invoice' | 'delivery' | 'other' })}
            options={[
              { value: 'primary', label: t('partnerContacts.types.primary') },
              { value: 'invoice', label: t('partnerContacts.types.invoice') },
              { value: 'delivery', label: t('partnerContacts.types.delivery') },
              { value: 'other', label: t('partnerContacts.types.other') },
            ]} />
        </div>
        <div className="grid grid-cols-2 gap-3">
          <Input label={t('partnerContacts.colEmail')} type="email" value={form.email} onChange={e => setForm({ ...form, email: e.target.value })} />
          <Input label={t('partnerContacts.colPhone')} value={form.phone} onChange={e => setForm({ ...form, phone: e.target.value })} />
        </div>
        <div className="grid grid-cols-2 gap-3">
          <Input label={t('partnerContacts.colMobile')} value={form.mobile} onChange={e => setForm({ ...form, mobile: e.target.value })} />
          <Input label={t('partnerContacts.colFunction')} value={form.function} onChange={e => setForm({ ...form, function: e.target.value })} />
        </div>
        <Input label={t('partnerContacts.colAddress')} value={form.address} onChange={e => setForm({ ...form, address: e.target.value })} />
        <div className="grid grid-cols-3 gap-3">
          <Input label={t('partnerContacts.colPostalCode')} value={form.postal_code} onChange={e => setForm({ ...form, postal_code: e.target.value })} />
          <Input label={t('partnerContacts.colCity')} value={form.city} onChange={e => setForm({ ...form, city: e.target.value })} />
          <Input label={t('partnerContacts.colCountry')} value={form.country} onChange={e => setForm({ ...form, country: e.target.value })} />
        </div>
        <div className="flex items-center gap-4">
          <label className="flex items-center gap-2"><input type="checkbox" checked={form.is_default} onChange={e => setForm({ ...form, is_default: e.target.checked })} /> {t('partnerContacts.isDefault')}</label>
          <label className="flex items-center gap-2"><input type="checkbox" checked={form.active} onChange={e => setForm({ ...form, active: e.target.checked })} /> {t('partnerContacts.active')}</label>
        </div>
        <div className="flex gap-2">
          <Button type="submit" disabled={saving}>{tCommon('actions.save')}</Button>
          <Button variant="secondary" onClick={onClose}>{tCommon('common.cancel')}</Button>
        </div>
      </form>
    </Card>
  )
}

function BankAccountForm({ partnerType, partnerId, bankAccount, onClose, onSaved }: {
  partnerType: 'customer' | 'supplier'
  partnerId: string
  bankAccount?: PartnerBankAccount
  onClose: () => void
  onSaved: () => void
}) {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [form, setForm] = useState({
    account_number: bankAccount?.account_number || '',
    bank_name: bankAccount?.bank_name || '',
    bic: bankAccount?.bic || '',
    bank_code: bankAccount?.bank_code || '',
    sort_code: bankAccount?.sort_code || '',
    account_key: bankAccount?.account_key || '',
    currency_code: bankAccount?.currency_code || 'EUR',
    is_default: bankAccount?.is_default || false,
    active: bankAccount?.active ?? true,
  })
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      const data = { ...form, partner_type: partnerType, partner_id: partnerId }
      if (bankAccount) {
        await updatePartnerBankAccount(bankAccount.id, data)
        toast('success', tCommon('common.success'), t('partnerContacts.bankUpdated'))
      } else {
        await createPartnerBankAccount(data as any)
        toast('success', tCommon('common.success'), t('partnerContacts.bankCreated'))
      }
      onSaved()
    } catch (e: any) {
      toast('error', tCommon('common.error'), e.message)
    } finally { setSaving(false) }
  }

  return (
    <Card className="p-4 mb-4 space-y-3">
      <form onSubmit={handleSubmit} className="space-y-3">
        <div className="grid grid-cols-2 gap-3">
          <Input label={t('partnerContacts.colIBAN')} required value={form.account_number} onChange={e => setForm({ ...form, account_number: e.target.value })} placeholder="FR76 1234 5678 9012 3456 7890 123" />
          <Input label={t('partnerContacts.colBIC')} value={form.bic} onChange={e => setForm({ ...form, bic: e.target.value })} placeholder="ABCDEFGHXXX" />
        </div>
        <div className="grid grid-cols-2 gap-3">
          <Input label={t('partnerContacts.colBankName')} value={form.bank_name} onChange={e => setForm({ ...form, bank_name: e.target.value })} />
          <Input label={t('partnerContacts.colCurrency')} value={form.currency_code} onChange={e => setForm({ ...form, currency_code: e.target.value })} />
        </div>
        <div className="grid grid-cols-3 gap-3">
          <Input label={t('partnerContacts.colBankCode')} value={form.bank_code} onChange={e => setForm({ ...form, bank_code: e.target.value })} />
          <Input label={t('partnerContacts.colSortCode')} value={form.sort_code} onChange={e => setForm({ ...form, sort_code: e.target.value })} />
          <Input label={t('partnerContacts.colAccountKey')} value={form.account_key} onChange={e => setForm({ ...form, account_key: e.target.value })} />
        </div>
        <div className="flex items-center gap-4">
          <label className="flex items-center gap-2"><input type="checkbox" checked={form.is_default} onChange={e => setForm({ ...form, is_default: e.target.checked })} /> {t('partnerContacts.isDefault')}</label>
          <label className="flex items-center gap-2"><input type="checkbox" checked={form.active} onChange={e => setForm({ ...form, active: e.target.checked })} /> {t('partnerContacts.active')}</label>
        </div>
        <div className="flex gap-2">
          <Button type="submit" disabled={saving}>{tCommon('actions.save')}</Button>
          <Button variant="secondary" onClick={onClose}>{tCommon('common.cancel')}</Button>
        </div>
      </form>
    </Card>
  )
}
